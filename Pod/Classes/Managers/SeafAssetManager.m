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

#ifndef kUTTypeHEIC
#define kUTTypeHEIC CFSTR("public.heic")
#endif

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
        [self getImageDataForAsset:file completion:completion];
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

    NSString *filePath = file.model.lpath;
    NSOutputStream *stream = [NSOutputStream outputStreamToFileAtPath:filePath append:NO];
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

        // Check if HEIC conversion is needed
        NSURL *sourceURL = [NSURL fileURLWithPath:file.model.lpath];
        NSString *filename = resource.originalFilename;
        NSString *fileExtension = filename.pathExtension.lowercaseString;
        
        if (![file uploadHeic] && [fileExtension isEqualToString:@"heic"]) {
            NSString *destinationPath = file.model.lpath;
            NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath];

            if ([self convertHEICToJPEGAtURL:sourceURL destinationURL:destinationURL]) {
                file.model.lpath = destinationPath;
                if (completion) completion(YES, nil);
            } else {
                if (completion) completion(NO, nil);
            }
        } else {
            if (completion) completion(YES, nil);
        }
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
        
        if (![file uploadHeic] && [dataUTI isEqualToString:@"public.heic"]) {
            file.model.lpath = [file.model.lpath stringByReplacingOccurrencesOfString:@"HEIC" withString:@"JPG"];
            CIImage* ciImage = [CIImage imageWithData:imageData];
            if (![Utils writeCIImage:ciImage toPath:file.model.lpath]) {
                if (completion) completion(NO, nil);
                return;
            }
        } else {
            NSString *newExtension = [FileMimeType fileExtensionForUTI:dataUTI];
            if (!newExtension) {
                newExtension = file.model.lpath.pathExtension;
            }
            
            if (newExtension && ![[file.model.lpath.pathExtension lowercaseString] isEqualToString:[newExtension lowercaseString]]) {
                file.model.lpath = [[file.model.lpath stringByDeletingPathExtension] stringByAppendingPathExtension:newExtension];
                Debug(@"Updated file path to: %@", file.model.lpath);
            }
            
            if (![Utils writeDataWithMeta:imageData toPath:file.model.lpath]) {
                if (completion) completion(NO, nil);
                return;
            }
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

- (void)getVideoForAsset:(SeafUploadFile *)file completion:(void (^)(BOOL success, NSError *error))completion {
    PHVideoRequestOptions *options = [PHVideoRequestOptions new];
    options.networkAccessAllowed = YES;
    // 使用原始视频版本
    options.version = PHVideoRequestOptionsVersionOriginal;
    
    // 设置进度回调
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
            // 创建目标目录
            [Utils checkMakeDir:[file.model.lpath stringByDeletingLastPathComponent]];
            
            // 拷贝视频文件
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
            // 非 AVURLAsset 类型处理
            [file finishUpload:false oid:nil error:nil];
            if (completion) {
                completion(NO, nil);
            }
            return;
        }
        
        // 更新文件大小并清理 asset
        file.model.filesize = [Utils fileSizeAtPath1:file.model.lpath];
        file.model.asset = nil;
        
        if (completion) {
            completion(YES, nil);
        }
    }];
}

@end 
