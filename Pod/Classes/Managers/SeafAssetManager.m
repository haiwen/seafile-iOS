#import "SeafAssetManager.h"
#import "SeafUploadFile.h"
#import "SeafUploadFileModel.h"
#import "Utils.h"
#import "Debug.h"
#import <Photos/Photos.h>
#import <ImageIO/ImageIO.h>
#import "FileMimeType.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h> // Used for iOS 14/macOS 11 and later
#import <MobileCoreServices/MobileCoreServices.h>
#import "SeafMotionPhotoComposer.h"
#import "SeafVideoConverter.h"

#ifndef kUTTypeHEIC
#define kUTTypeHEIC CFSTR("public.heic")
#endif

#ifndef kUTTypeHEIF
#define kUTTypeHEIF CFSTR("public.heif")
#endif

// Live Photo retry mechanism constants
// Used to ensure paired video resource is available for newly captured Live Photos
static const NSInteger kLivePhotoMaxRetryCount = 5;
static const NSTimeInterval kLivePhotoRetryDelay = 1.0; // seconds

@implementation SeafAssetManager

- (void)setAsset:(PHAsset *)asset url:(NSURL *)url forFile:(SeafUploadFile *)file {
    if (!file || !file.model) return;
    
    [file.model setAsset:asset url:url identifier:asset.localIdentifier];
}

- (void)checkAssetWithFile:(SeafUploadFile *)file completion:(void (^)(BOOL success, NSError *error))completion {
    if (!file.model.asset) {
        if (completion) completion(YES, nil);
        return;
    }
    
    if (![Utils checkMakeDir:[file.model.lpath stringByDeletingLastPathComponent]]) {
        [file finishUpload:false oid:nil error:nil];
        if (completion) {
            completion(NO, nil); // failed
        }
        return;
    }
    
    PHAssetResource *resource = [[PHAssetResource assetResourcesForAsset:file.model.asset] firstObject];
    if (!resource) {
        NSError *error = [NSError errorWithDomain:@"SeafAssetManager" 
                                           code:-1 
                                       userInfo:@{NSLocalizedDescriptionKey: @"Asset resource not found"}];
        if (completion) completion(NO, error);
        return;
    }
    
    if (file.model.asset.mediaType == PHAssetMediaTypeImage) {
        // Check if this is a Live Photo and should be uploaded as Motion Photo
        // Only upload as Motion Photo when:
        // 1. The asset is a Live Photo (mediaSubtypes check)
        // 2. The "Upload Live Photo" setting is enabled
        // When setting is disabled, Live Photo uploads as static image only (no video)
        BOOL shouldUploadAsLivePhoto = [self isLivePhotoAsset:file.model.asset] && [file uploadLivePhoto];
        
        if (shouldUploadAsLivePhoto) {
            // Use retry mechanism to ensure paired video resource is available
            // This handles the timing issue where PHPhotoLibraryChangeObserver fires
            // before the paired video resource is fully ready for newly captured Live Photos
            [self uploadLivePhotoWithRetry:file retryCount:0 completion:completion];
        } else {
            [self getImageDataForAsset:file completion:completion];
        }
    } else if (file.model.asset.mediaType == PHAssetMediaTypeVideo) {
        [self getVideoForAsset:file completion:completion];
    } else {
        NSError *error = [NSError errorWithDomain:@"SeafAssetManager" 
                                           code:-2 
                                       userInfo:@{NSLocalizedDescriptionKey: @"Unsupported asset type"}];
        if (completion) completion(NO, error);
    }
}

- (void)getImageDataForAsset:(SeafUploadFile *)file completion:(void (^)(BOOL success, NSError *error))completion {
    PHAssetResource *resource = nil;
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:file.model.asset];

    // First check for modified image resource
    for (PHAssetResource *res in resources) {
        if (res.type == PHAssetResourceTypeAdjustmentData) {
            [self getModifiedImageDataForAsset:file completion:completion];
            return;
        }
    }
    
    // If no modified version, get original image
    for (PHAssetResource *res in resources) {
        if (res.type == PHAssetResourceTypePhoto || res.type == PHAssetResourceTypeFullSizePhoto) {
            resource = res;
            break;
        }
    }

    if (!resource) {
        resource = resources.firstObject;
    }

    // Always keep original format (no HEIC→JPG conversion)
    // Per new specification: static photos always keep their original format
    NSString *writePath = file.model.lpath;
    
    NSOutputStream *stream = [NSOutputStream outputStreamToFileAtPath:writePath append:NO];
    [stream open];

    PHAssetResourceRequestOptions *options = [[PHAssetResourceRequestOptions alloc] init];
    options.networkAccessAllowed = YES;

    [[PHAssetResourceManager defaultManager] requestDataForAssetResource:resource 
                                                               options:options 
                                                 dataReceivedHandler:^(NSData * _Nonnull data) {
        @autoreleasepool {
            [stream write:data.bytes maxLength:data.length];
        }
    } completionHandler:^(NSError * _Nullable error) {
        [stream close];
        if (error) {
            if (completion) completion(NO, error);
            return;
        }
        if (completion) completion(YES, nil);
    }];
}

- (void)getModifiedImageDataForAsset:(SeafUploadFile *)file completion:(void (^)(BOOL success, NSError *error))completion {
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    options.synchronous = NO;
    
    options.progressHandler = ^(double progress, NSError * _Nullable error, BOOL * _Nonnull stop, NSDictionary * _Nullable info) {
        if (error) {
            Debug("Failed to get image data: %@", error);
            if (completion) completion(NO, error);
            *stop = YES;
        }
    };
    
    [[PHImageManager defaultManager] requestImageDataForAsset:file.model.asset 
                                                    options:options 
                                              resultHandler:^(NSData * _Nullable imageData, 
                                                           NSString * _Nullable dataUTI, 
                                                           UIImageOrientation orientation, 
                                                           NSDictionary * _Nullable info) {
        if (!imageData) {
            NSError *noDataError = [NSError errorWithDomain:@"SeafAssetManager"
                                                     code:-1
                                                 userInfo:@{NSLocalizedDescriptionKey: @"No image data returned."}];
            if (completion) completion(NO, noDataError);
            return;
        }
        
        // Always keep original format (no HEIC→JPG conversion)
        // Per new specification: static photos always keep their original format
        NSData *dataToWrite = imageData;
        
        // Keep original extension based on UTI
        NSString *newExtension = [FileMimeType fileExtensionForUTI:dataUTI];
        if (!newExtension) {
            newExtension = file.model.lpath.pathExtension;
        }
        
        if (newExtension && ![[file.model.lpath.pathExtension lowercaseString] isEqualToString:[newExtension lowercaseString]]) {
            file.model.lpath = [[file.model.lpath stringByDeletingPathExtension] stringByAppendingPathExtension:newExtension];
            Debug(@"Updated file path to: %@", file.model.lpath);
        }
        
        if (![Utils writeDataWithMeta:dataToWrite toPath:file.model.lpath]) {
            if (completion) completion(NO, nil);
            return;
        }
        
        if (completion) completion(YES, nil);
    }];
}

- (BOOL)convertHEICToJPEGAtURL:(NSURL *)sourceURL destinationURL:(NSURL *)destinationURL {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)sourceURL, NULL);
    if (!source) return NO;
    
    CFStringRef sourceType = CGImageSourceGetType(source);
    BOOL success = NO;

    if (@available(iOS 14.0, *)) {
        UTType *type = [UTType typeWithIdentifier:(__bridge NSString *)sourceType];
        if ([type conformsToType:UTTypeHEIC]) {
            CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)destinationURL, (__bridge CFStringRef)UTTypeJPEG.identifier, 1, NULL);
            if (destination) {
                NSDictionary *options = @{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @0.8};
                CGImageDestinationAddImageFromSource(destination, source, 0, (__bridge CFDictionaryRef)options);
                success = CGImageDestinationFinalize(destination);
                CFRelease(destination);
            }
        }
    } else {
        if (UTTypeConformsTo(sourceType, kUTTypeHEIC)) {
            CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)destinationURL, kUTTypeJPEG, 1, NULL);
            if (destination) {
                NSDictionary *options = @{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @0.8};
                CGImageDestinationAddImageFromSource(destination, source, 0, (__bridge CFDictionaryRef)options);
                success = CGImageDestinationFinalize(destination);
                CFRelease(destination);
            }
        }
    }

    if (!success) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        success = [fileManager copyItemAtURL:sourceURL toURL:destinationURL error:nil];
    }

    CFRelease(source);
    return success;
}

#pragma mark - JPG to HEIC Conversion

- (nullable NSData *)convertJPEGDataToHEIC:(NSData *)jpegData {
    if (!jpegData || jpegData.length == 0) return nil;
    
    UIImage *uiImage = [UIImage imageWithData:jpegData];
    if (!uiImage) return nil;
    
    // Normalize orientation by redrawing
    UIGraphicsBeginImageContextWithOptions(uiImage.size, NO, uiImage.scale);
    [uiImage drawInRect:CGRectMake(0, 0, uiImage.size.width, uiImage.size.height)];
    UIImage *normalizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    if (!normalizedImage || !normalizedImage.CGImage) return nil;
    
    // Get original metadata
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)jpegData, NULL);
    NSMutableDictionary *props = [NSMutableDictionary dictionary];
    if (source) {
        NSDictionary *origProps = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
        if (origProps) [props addEntriesFromDictionary:origProps];
        CFRelease(source);
    }
    
    // Set orientation to Up and remove TIFF orientation
    props[(__bridge NSString *)kCGImagePropertyOrientation] = @(kCGImagePropertyOrientationUp);
    NSMutableDictionary *tiffDict = [props[(__bridge NSString *)kCGImagePropertyTIFFDictionary] mutableCopy];
    if (tiffDict) {
        [tiffDict removeObjectForKey:(__bridge NSString *)kCGImagePropertyTIFFOrientation];
        props[(__bridge NSString *)kCGImagePropertyTIFFDictionary] = tiffDict;
    }
    
    // Create HEIC
    NSMutableData *heicData = [NSMutableData data];
    CGImageDestinationRef dest = NULL;
    if (@available(iOS 14.0, *)) {
        dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)heicData,
                                                 (__bridge CFStringRef)UTTypeHEIC.identifier, 1, NULL);
    } else {
        dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)heicData, kUTTypeHEIC, 1, NULL);
    }
    if (!dest) return nil;
    
    props[(__bridge NSString *)kCGImageDestinationLossyCompressionQuality] = @0.9;
    CGImageDestinationAddImage(dest, normalizedImage.CGImage, (__bridge CFDictionaryRef)props);
    
    BOOL success = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    
    return success ? [heicData copy] : nil;
}

- (BOOL)isJPEGData:(NSData *)data {
    if (data.length < 3) return NO;
    uint8_t header[3];
    [data getBytes:header range:NSMakeRange(0, 3)];
    return header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF;
}

- (BOOL)isHEICData:(NSData *)data {
    if (data.length < 12) return NO;
    char type[5] = {0}, brand[5] = {0};
    [data getBytes:type range:NSMakeRange(4, 4)];
    if (strcmp(type, "ftyp") != 0) return NO;
    [data getBytes:brand range:NSMakeRange(8, 4)];
    return strcmp(brand, "heic") == 0 || strcmp(brand, "mif1") == 0 || 
           strcmp(brand, "msf1") == 0 || strcmp(brand, "heix") == 0;
}

- (void)getVideoForAsset:(SeafUploadFile *)file completion:(void (^)(BOOL success, NSError *error))completion {
    PHVideoRequestOptions *options = [PHVideoRequestOptions new];
    options.networkAccessAllowed = YES;
    // Use the original video version
    options.version = PHVideoRequestOptionsVersionOriginal;
    
    // Set progress callback
    options.progressHandler = ^(double progress, NSError * _Nullable error, BOOL * _Nonnull stop, NSDictionary * _Nullable info) {
        if (error) {
            Debug("Failed to get video: %@", error);
            [file finishUpload:false oid:nil error:error];
            if (completion) {
                completion(NO, error);
            }
            *stop = YES;
        }
    };
    
    [[PHImageManager defaultManager] requestAVAssetForVideo:file.model.asset
                                                   options:options
                                             resultHandler:^(AVAsset * _Nullable asset,
                                                             AVAudioMix * _Nullable audioMix,
                                                             NSDictionary * _Nullable info) {
        if ([asset isKindOfClass:[AVURLAsset class]]) {
            // Create target directory
            [Utils checkMakeDir:[file.model.lpath stringByDeletingLastPathComponent]];
            
            // Copy video file
            AVURLAsset *urlAsset = (AVURLAsset *)asset;
            BOOL result = [Utils copyFile:urlAsset.URL to:[NSURL fileURLWithPath:file.model.lpath]];
            if (!result) {
                [file finishUpload:false oid:nil error:nil];
                if (completion) {
                    completion(NO, nil);
                }
                return;
            }
        } else {
            // Handle non-AVURLAsset types
            [file finishUpload:false oid:nil error:nil];
            if (completion) {
                completion(NO, nil);
            }
            return;
        }
        
        // Update file size and clear asset
        file.model.filesize = [Utils fileSizeAtPath1:file.model.lpath];
        file.model.asset = nil;
        
        if (completion) {
            completion(YES, nil);
        }
    }];
}

#pragma mark - Live Photo / Motion Photo Support

- (BOOL)isLivePhotoAsset:(PHAsset *)asset {
    if (!asset) return NO;
    return (asset.mediaSubtypes & PHAssetMediaSubtypePhotoLive) != 0;
}

/// Check if the paired video resource is available for a Live Photo asset.
/// @param asset The PHAsset to check
/// @return YES if the paired video resource is available
- (BOOL)checkPairedVideoAvailable:(PHAsset *)asset {
    if (!asset) return NO;
    
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    for (PHAssetResource *resource in resources) {
        if (resource.type == PHAssetResourceTypePairedVideo || 
            resource.type == PHAssetResourceTypeFullSizePairedVideo) {
            return YES;
        }
    }
    return NO;
}

/// Upload Live Photo with retry mechanism.
/// This ensures the paired video resource is available before uploading.
/// @param file The upload file
/// @param retryCount Current retry count
/// @param completion Completion handler
- (void)uploadLivePhotoWithRetry:(SeafUploadFile *)file 
                      retryCount:(NSInteger)retryCount 
                      completion:(void (^)(BOOL success, NSError *error))completion {
    
    // Check if paired video resource is available
    BOOL hasPairedVideo = [self checkPairedVideoAvailable:file.model.asset];
    
    if (hasPairedVideo) {
        // Paired video available, proceed with Motion Photo upload
        file.model.isLivePhoto = YES;
        Debug("Live Photo paired video available, uploading as Motion Photo: %@", file.name);
        [self getMotionPhotoDataForAsset:file completion:completion];
        
    } else if (retryCount < kLivePhotoMaxRetryCount) {
        // Paired video not available yet, retry after delay
        Debug("Live Photo paired video not ready for %@, retry %ld/%ld after %.1fs", 
              file.name, (long)(retryCount + 1), (long)kLivePhotoMaxRetryCount, kLivePhotoRetryDelay);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLivePhotoRetryDelay * NSEC_PER_SEC)), 
                      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self uploadLivePhotoWithRetry:file retryCount:retryCount + 1 completion:completion];
        });
        
    } else {
        // Retry limit reached, fail with error instead of falling back to static image
        // This ensures that when "Upload Live Photo" is enabled, we don't silently degrade to static
        Warning("Live Photo paired video not available after %ld retries: %@", 
                (long)kLivePhotoMaxRetryCount, file.name);
        
        NSError *error = [NSError errorWithDomain:@"SeafAssetManager"
                                             code:-100
                                         userInfo:@{NSLocalizedDescriptionKey: 
                                             NSLocalizedString(@"Live Photo video resource not available, please retry later", @"Seafile")}];
        if (completion) completion(NO, error);
    }
}

- (void)getMotionPhotoDataForAsset:(SeafUploadFile *)file 
                        completion:(void (^)(BOOL success, NSError *error))completion {
    PHAsset *asset = file.model.asset;
    if (!asset) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"SeafAssetManager"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"No asset provided"}];
            completion(NO, error);
        }
        return;
    }
    
    // Get asset resources
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    
    PHAssetResource *photoResource = nil;
    PHAssetResource *videoResource = nil;
    
    for (PHAssetResource *resource in resources) {
        switch (resource.type) {
            case PHAssetResourceTypePhoto:
            case PHAssetResourceTypeFullSizePhoto:
                if (!photoResource) {
                    photoResource = resource;
                }
                break;
                
            case PHAssetResourceTypePairedVideo:
            case PHAssetResourceTypeFullSizePairedVideo:
                if (!videoResource) {
                    videoResource = resource;
                }
                break;
                
            default:
                break;
        }
    }
    
    if (!photoResource || !videoResource) {
        // Fallback to regular image processing
        [self getImageDataForAsset:file completion:completion];
        return;
    }
    
    // Create temporary paths for image and video
    // Use original filename extension from resource to preserve format info
    NSString *tempDir = NSTemporaryDirectory();
    NSString *originalImageExt = photoResource.originalFilename.pathExtension.lowercaseString ?: @"heic";
    NSString *originalVideoExt = videoResource.originalFilename.pathExtension.lowercaseString ?: @"mov";
    NSString *imageFileName = [NSString stringWithFormat:@"livephoto_image_%@.%@", [[NSUUID UUID] UUIDString], originalImageExt];
    NSString *videoFileName = [NSString stringWithFormat:@"livephoto_video_%@.%@", [[NSUUID UUID] UUIDString], originalVideoExt];
    NSString *tempImagePath = [tempDir stringByAppendingPathComponent:imageFileName];
    NSString *tempVideoPath = [tempDir stringByAppendingPathComponent:videoFileName];
    
    // Request options
    PHAssetResourceRequestOptions *options = [[PHAssetResourceRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    
    // Use dispatch group to wait for both resources
    dispatch_group_t group = dispatch_group_create();
    
    __block BOOL imageSuccess = NO;
    __block BOOL videoSuccess = NO;
    __block NSError *imageError = nil;
    __block NSError *videoError = nil;
    
    // Request image data
    dispatch_group_enter(group);
    [[PHAssetResourceManager defaultManager] writeDataForAssetResource:photoResource
                                                                toFile:[NSURL fileURLWithPath:tempImagePath]
                                                               options:options
                                                     completionHandler:^(NSError * _Nullable error) {
        if (error) {
            imageError = error;
        } else {
            imageSuccess = YES;
        }
        dispatch_group_leave(group);
    }];
    
    // Request video data
    dispatch_group_enter(group);
    [[PHAssetResourceManager defaultManager] writeDataForAssetResource:videoResource
                                                                toFile:[NSURL fileURLWithPath:tempVideoPath]
                                                               options:options
                                                     completionHandler:^(NSError * _Nullable error) {
        if (error) {
            videoError = error;
        } else {
            videoSuccess = YES;
        }
        dispatch_group_leave(group);
    }];
    
    // Wait for both resources and then compose Motion Photo
    dispatch_group_notify(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Mutable array to track temp files for cleanup
        NSMutableArray<NSString *> *tempFilesToCleanup = [NSMutableArray arrayWithObjects:tempImagePath, tempVideoPath, nil];
        
        // Cleanup function
        void (^cleanup)(void) = ^{
            for (NSString *path in tempFilesToCleanup) {
                [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            }
        };
        
        if (!imageSuccess || !videoSuccess) {
            cleanup();
            
            // Fallback to regular image processing
            dispatch_async(dispatch_get_main_queue(), ^{
                [self getImageDataForAsset:file completion:completion];
            });
            return;
        }
        
        // Read image and video data
        NSData *imageData = [NSData dataWithContentsOfFile:tempImagePath];
        NSData *videoData = [NSData dataWithContentsOfFile:tempVideoPath];
        
        if (!imageData || !videoData) {
            cleanup();
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self getImageDataForAsset:file completion:completion];
            });
            return;
        }
        
        [self composeV1V2MotionPhoto:imageData
                           videoData:videoData
                                file:file
                             cleanup:cleanup
                          completion:completion];
    });
}

- (void)composeV1V2MotionPhoto:(NSData *)imageData
                     videoData:(NSData *)videoData
                          file:(SeafUploadFile *)file
                       cleanup:(void (^)(void))cleanup
                    completion:(void (^)(BOOL success, NSError *error))completion {
    
    // Convert JPEG to HEIC if necessary
    NSData *heicImageData = imageData;
    if ([self isJPEGData:imageData]) {
        NSData *convertedData = [self convertJPEGDataToHEIC:imageData];
        if (convertedData) {
            heicImageData = convertedData;
        } else {
            cleanup();
            dispatch_async(dispatch_get_main_queue(), ^{
                [self getImageDataForAsset:file completion:completion];
            });
            return;
        }
    } else if (![self isHEICData:imageData]) {
        cleanup();
        dispatch_async(dispatch_get_main_queue(), ^{
            [self getImageDataForAsset:file completion:completion];
        });
        return;
    }
    
    // Compose Motion Photo
    NSData *motionPhotoData = [SeafMotionPhotoComposer composeV1V2MotionPhotoWithImageData:heicImageData
                                                                                 videoData:videoData];
    if (!motionPhotoData) {
        cleanup();
        dispatch_async(dispatch_get_main_queue(), ^{
            [self getImageDataForAsset:file completion:completion];
        });
        return;
    }
    
    // Write to file
    NSError *writeError = nil;
    BOOL writeSuccess = [motionPhotoData writeToFile:file.model.lpath 
                                             options:NSDataWritingAtomic 
                                               error:&writeError];
    cleanup();
    
    if (!writeSuccess) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO, writeError);
        });
        return;
    }
    
    file.model.filesize = [Utils fileSizeAtPath1:file.model.lpath];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(YES, nil);
    });
}

@end 
