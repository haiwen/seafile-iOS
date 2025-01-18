//
//  SeafUploadFile.m
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafStorage.h"
#import "SeafUploadFile.h"
#import "SeafRepos.h"
#import "SeafDataTaskManager.h"

#import "Utils.h"
#import "FileMimeType.h"
#import "UIImage+FileType.h"
#import "ExtentedString.h"
#import "NSData+Encryption.h"
#import "Debug.h"

#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h> // Required for older system versions
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h> // Used for iOS 14/macOS 11 and later
#import "FileMimeType.h"
#import "SeafRealmManager.h"

#ifndef kUTTypeHEIC
#define kUTTypeHEIC CFSTR("public.heic")
#endif

@interface SeafUploadFile ()
@property (readonly) NSString *mime;
@property (strong, readonly) NSURL *preViewURL;
@property (strong) NSURLSessionUploadTask *task;

@property dispatch_semaphore_t semaphore;
//@property (nonatomic) TaskCompleteBlock taskCompleteBlock;
@property (nonatomic) TaskProgressBlock taskProgressBlock;
@property (nonatomic, strong) PHImageRequestOptions *requestOptions;

@end

@implementation SeafUploadFile
@synthesize assetURL = _assetURL;
@synthesize filesize = _filesize;
@synthesize lastFinishTimestamp = _lastFinishTimestamp;
@synthesize retryable = _retryable;
@synthesize retryCount = _retryCount;

#pragma mark - Initialization

- (id)initWithPath:(NSString *)lpath
{
    self = [super init];
    if (self) {
        self.retryable = true;
        _lpath = lpath;
        _uProgress = 0;
        _uploading = NO;
        _uploadFileAutoSync = NO;
        _starred = NO;
        _uploaded = NO;
        _overwrite = NO;
        _semaphore = dispatch_semaphore_create(0);
        _shouldShowUploadFailure = true;
    }
    return self;
}

+ (void)clearCache
{
    [Utils clearAllFiles:SeafStorage.sharedObject.uploadsDir];
}

#pragma mark - Properties & Basic Accessors

- (NSString *)name
{
    return [_lpath lastPathComponent];
}

- (long long)filesize
{
    if (!_filesize || _filesize == 0) {
        _filesize = [Utils fileSizeAtPath1:self.lpath];
    }
    return _filesize;
}

- (NSString *)accountIdentifier
{
    return self.udir.connection.accountIdentifier;
}

- (BOOL)hasCache
{
    return YES;
}

- (BOOL)isImageFile
{
    return [Utils isImageFile:self.name];
}

- (long long)mtime
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.lpath]) {
        return [[NSDate date] timeIntervalSince1970];
    } else {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.lpath error:nil];
        return [[attributes fileModificationDate] timeIntervalSince1970];
    }
}

- (BOOL)editable
{
    return NO;
}

- (BOOL)removed
{
    return !_udir;
}

- (BOOL)uploadHeic {
    return self.udir.connection.isUploadHeicEnabled;
}

#pragma mark - Dentry/Loading Methods

- (void)unload
{
}

- (void)load:(id<SeafDentryDelegate>)delegate force:(BOOL)force
{
    [self checkAsset];
}

- (BOOL)isDownloading
{
    return NO;
}

#pragma mark - Cancel & Cleanup

- (void)cancel
{
    Debug("Cancel uploadFile: %@", self.lpath);
    // Avoid recursively call cancel in SeafDataTaskManager
    if (!self.udir) return;
    SeafConnection *conn = self.udir.connection;
    @synchronized(self) {
        [self.task cancel];
        [self cleanup];
        [self.udir removeUploadItem:self];
        self.udir = nil;
        self.task = nil;
    }
    
    [SeafDataTaskManager.sharedObject removeUploadTask:self forAccount: conn];
}

- (void)cancelAnyLoading
{
}

- (void)cleanup
{
    Debug("Cleanup uploaded disk file: %@", self.lpath);
    [Utils removeFile:self.lpath];
    if (!self.uploadFileAutoSync) {
        [Utils removeDirIfEmpty:[self.lpath stringByDeletingLastPathComponent]];
    }
}

#pragma mark - Finishing & Post-Upload

- (void)finishUpload:(BOOL)result oid:(NSString *)oid error:(NSError *)error
{
    @synchronized(self) {
        if (!self.isUploading) return;
        _uploading = NO;
        self.task = nil;
        self.uploadError = error;
    }
    
    _uploaded = result;
    NSError *err = error;
    if (!err && !result) {
        err = [Utils defaultError];
    }
    
    self.lastFinishTimestamp = [[NSDate new] timeIntervalSince1970];
    
    Debug("result=%d, name=%@, delegate=%@, oid=%@, err=%@\n", result, self.name, _delegate, oid, err);

    if (result) {
        if (self.isEditedFile) {
            if (self.editedFileOid) {
                [Utils removeFile:[SeafStorage.sharedObject documentPath:self.editedFileOid]];
            }
        }
        
        if (_starred && self.udir) {
            NSString* rpath = [_udir.path stringByAppendingPathComponent:self.name];
            [_udir.connection setStarred:YES repo:_udir.repoId path:rpath];
        }
        
        if (!_uploadFileAutoSync) {
            [Utils linkFileAtPath:self.lpath to:[SeafStorage.sharedObject documentPath:oid] error:nil];
            [self saveFileStatusWithOid:oid];
        } else {
            // For auto sync photos, release local cache files immediately.
            [self cleanup];
        }
    }
    [self uploadComplete:oid error:err];
}

- (void)saveFileStatusWithOid:(NSString *)oid {
    if (!oid || oid.length == 0) return;

    SeafFileStatus *fileStatus = [[SeafFileStatus alloc] init];
    fileStatus.uniquePath = [Utils uniquePathWithUniKey:self.udir.uniqueKey fileName:self.name];
    fileStatus.serverOID = oid;
    fileStatus.localMTime = [[NSDate date] timeIntervalSince1970];
    fileStatus.localFilePath = self.lpath;
    fileStatus.fileSize = self.filesize;
    fileStatus.accountIdentifier = self.udir.connection.accountIdentifier;
    
    fileStatus.fileName = self.name;

    [[SeafRealmManager shared] updateFileStatus:fileStatus];
    Debug("Updated file status: %@ with oid: %@", self.lpath, oid);
}

#pragma mark - PHAsset Handling

- (void)setPHAsset:(PHAsset *)asset url:(NSURL *)url {
    _asset = asset;
    _assetURL = url;
    _assetIdentifier = asset.localIdentifier;
    _starred = asset.isFavorite;
}

- (void)checkAsset {
    if (_asset) {
        @synchronized(self) {
            if (![Utils checkMakeDir:[self.lpath stringByDeletingLastPathComponent]]) {
                [self finishUpload:false oid:nil error:nil];
            }
            if (_asset.mediaType == PHAssetMediaTypeVideo) {
                [self getVideoForAsset];
            } else if (_asset.mediaType == PHAssetMediaTypeImage) {
                [self getImageDataForAsset];
            }
        }
        Debug("asset file %@ size: %lld, lpath: %@", _asset.localIdentifier, _filesize, self.lpath);
    }
}

- (void)checkAssetWithCompletion:(void (^)(BOOL success, NSError *error))completion {
    if (_asset) {
        @synchronized(self) {
            if (![Utils checkMakeDir:[self.lpath stringByDeletingLastPathComponent]]) {
                [self finishUpload:false oid:nil error:nil];
                if (completion) {
                    completion(NO, nil); // failed
                }
                return;
            }
            if (_asset.mediaType == PHAssetMediaTypeVideo) {
                [self getVideoForAssetWithCompletion:^(BOOL success, NSError *error) {
                    if (success) {
                        Debug("asset file %@ size: %lld, lpath: %@", self->_asset.localIdentifier, self->_filesize, self.lpath);
                    }
                    if (completion) {
                        completion(success, error);
                    }
                }];
            } else if (_asset.mediaType == PHAssetMediaTypeImage) {
                [self getImageDataForAssetWithCompletion:^(BOOL success, NSError *error) {
                    if (success) {
                        Debug("asset file %@ size: %lld, lpath: %@", self->_asset.localIdentifier, self->_filesize, self.lpath);
                    }
                    if (completion) {
                        completion(success, error);
                    }
                }];
            } else {
                if (completion) {
                    completion(NO, nil); // failed
                }
            }
        }
    } else {
        if (completion) {
            completion(NO, nil); // failed
        }
    }
}

- (void)getVideoForAssetWithCompletion:(void (^)(BOOL success, NSError *error))completion {
    PHVideoRequestOptions *options = [PHVideoRequestOptions new];
    options.networkAccessAllowed = YES;
    options.version = PHVideoRequestOptionsVersionOriginal;
    options.progressHandler = ^(double progress, NSError * _Nullable error, BOOL * _Nonnull stop, NSDictionary * _Nullable info) {
        if (error) {
            Debug("Failed to get video: %@", error);
            [self finishUpload:false oid:nil error:error];
            if (completion) {
                completion(NO, error);
            }
            *stop = YES;
        }
    };
    
    [[PHImageManager defaultManager] requestAVAssetForVideo:_asset options:options resultHandler:^(AVAsset * _Nullable asset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
        if ([asset isKindOfClass:[AVURLAsset class]]) {
            [Utils checkMakeDir:[self.lpath stringByDeletingLastPathComponent]];
            BOOL result = [Utils copyFile:[(AVURLAsset *)asset URL] to:[NSURL fileURLWithPath:self.lpath]];
            if (!result) {
                [self finishUpload:false oid:nil error:nil];
                if (completion) {
                    completion(NO, nil);
                }
                return;
            }
        } else {
            [self finishUpload:false oid:nil error:nil];
            if (completion) {
                completion(NO, nil);
            }
            return;
        }
        self->_filesize = [Utils fileSizeAtPath1:self.lpath];
        self->_asset = nil;
        if (completion) {
            completion(YES, nil);
        }
    }];
}

- (void)getImageDataForAssetWithCompletion:(void (^)(BOOL success, NSError *error))completion {
    PHAssetResource *resource = nil;
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:self.asset];

    // Prefer to choose the modified image resource
    for (PHAssetResource *res in resources) {
        if (res.type == PHAssetResourceTypeAdjustmentData) {
            [self getModifiedImageDataForAssetWithCompletion:^(BOOL success, NSError *error) {
                if (!success) {
                    // if getImage failed, return
                    if (completion) {
                        completion(NO, error);
                    }
                    return;
                }
                self->_filesize = [Utils fileSizeAtPath1:self.lpath];
                if (completion) {
                    completion(YES, nil);
                }
            }];
            return;
        }
    }
    
    if (!resource) {
        for (PHAssetResource *res in resources) {
            if (res.type == PHAssetResourceTypePhoto || res.type == PHAssetResourceTypeFullSizePhoto) {
                resource = res;
                break; // get original image
            }
        }
    }

    NSString *filePath = self.lpath;
    NSOutputStream *stream = [NSOutputStream outputStreamToFileAtPath:filePath append:NO];
    [stream open];

    PHAssetResourceRequestOptions *options = [[PHAssetResourceRequestOptions alloc] init];
    options.networkAccessAllowed = YES; // Allow downloading from iCloud

    [[PHAssetResourceManager defaultManager] requestDataForAssetResource:resource options:options dataReceivedHandler:^(NSData * _Nonnull data) {
        @autoreleasepool {
            [stream write:data.bytes maxLength:data.length];
        }
    } completionHandler:^(NSError * _Nullable error) {
        [stream close];
        if (error) {
            [self finishUpload:false oid:nil error:error];
            if (completion) {
                completion(NO, error);
            }
        } else {
            // Check if format conversion is required
            NSURL *sourceURL = [NSURL fileURLWithPath:self.lpath];
            
            NSString *filename = resource.originalFilename;
            NSString *fileExtension = filename.pathExtension.lowercaseString;
            
            if (![self uploadHeic] && [fileExtension isEqualToString:@"heic"]) { // If HEIC uploads are not enabled
                // Conversion to JPEG is required
                NSString *destinationPath = self.lpath;  // Replace the original file
                NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath];

                if ([self convertHEICToJPEGAtURL:sourceURL destinationURL:destinationURL]) {
                    // Conversion succeeded, update file path and size
                    self.lpath = destinationPath;
                    self->_filesize = [Utils fileSizeAtPath1:self.lpath];
                    if (completion) {
                        completion(YES, nil);
                    }
                } else {
                    // Conversion failed
                    [self finishUpload:false oid:nil error:nil];
                    if (completion) {
                        completion(NO, nil);
                    }
                }
            } else {
                // No conversion required
                self->_filesize = [Utils fileSizeAtPath1:self.lpath];
                if (completion) {
                    completion(YES, nil);
                }
            }
        }
    }];
}

- (BOOL)getImageDataForAsset {
    PHAssetResource *resource = nil;
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:self.asset];

    // Prefer to choose the modified image resource
    for (PHAssetResource *res in resources) {
        if (res.type == PHAssetResourceTypeAdjustmentData) {//if is modifed image,use PHImageManager
            [self getModifiedImageDataForAsset];
            return YES;
        }
    }
    
    if (!resource) {
        for (PHAssetResource *res in resources) {
            if (res.type == PHAssetResourceTypePhoto || res.type == PHAssetResourceTypeFullSizePhoto) {
                resource = res;
                break; // get original image
            }
        }
    }

    if (!resource) {
        resource = resources.firstObject;
    }

    NSString *filePath = self.lpath;
    NSOutputStream *stream = [NSOutputStream outputStreamToFileAtPath:filePath append:NO];
    [stream open];

    // Create a semaphore to wait for the asynchronous task to complete
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL success = NO;

    PHAssetResourceRequestOptions *options = [[PHAssetResourceRequestOptions alloc] init];
    options.networkAccessAllowed = YES; // Allow downloading from iCloud

    [[PHAssetResourceManager defaultManager] requestDataForAssetResource:resource options:options dataReceivedHandler:^(NSData * _Nonnull data) {
        @autoreleasepool {
            [stream write:data.bytes maxLength:data.length];
        }
    } completionHandler:^(NSError * _Nullable error) {
        [stream close];
        if (error) {
            [self finishUpload:false oid:nil error:error];
            success = NO;
        } else {
            // Check if format conversion is needed
            NSURL *sourceURL = [NSURL fileURLWithPath:self.lpath];
            
            NSString *filename = resource.originalFilename;
            NSString *fileExtension = filename.pathExtension.lowercaseString;

            if (![self uploadHeic] && [fileExtension isEqualToString:@"heic"]) {
                // Conversion to JPEG
                NSString *destinationPath = self.lpath;  // replace the original file
                NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath];

                if ([self convertHEICToJPEGAtURL:sourceURL destinationURL:destinationURL]) {
                    // Conversion successful
                    self.lpath = destinationPath;
                    self->_filesize = [Utils fileSizeAtPath1:self.lpath];
                    success = YES;
                } else {
                    // Conversion failed
                    [self finishUpload:false oid:nil error:nil];
                    success = NO;
                }
            } else {
                // No conversion needed
                self->_filesize = [Utils fileSizeAtPath1:self.lpath];
                success = YES;
            }
        }
        // Signal the semaphore to release the wait
        dispatch_semaphore_signal(semaphore);
    }];

    // Wait for the asynchronous operation to complete
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    return success;
}

- (BOOL)convertHEICToJPEGAtURL:(NSURL *)sourceURL destinationURL:(NSURL *)destinationURL {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)sourceURL, NULL);
    if (!source) return NO;
    
    CFStringRef sourceType = CGImageSourceGetType(source);
    BOOL success = NO;

    if (@available(iOS 14.0, macOS 11.0, *)) {
        // Use the new UTType API
        UTType *type = [UTType typeWithIdentifier:(__bridge NSString *)sourceType];
        if ([type conformsToType:UTTypeHEIC]) {
            CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)destinationURL, (__bridge CFStringRef)UTTypeJPEG.identifier, 1, NULL);
            if (destination) {
                NSDictionary *options = @{ (__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @0.8 };
                CGImageDestinationAddImageFromSource(destination, source, 0, (__bridge CFDictionaryRef)options);
                success = CGImageDestinationFinalize(destination);
                CFRelease(destination);
            }
        }
    } else {
        // Use the older UTTypeConformsTo function
        if (UTTypeConformsTo(sourceType, kUTTypeHEIC)) {
            CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)destinationURL, kUTTypeJPEG, 1, NULL);
            if (destination) {
                NSDictionary *options = @{ (__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @0.8 };
                CGImageDestinationAddImageFromSource(destination, source, 0, (__bridge CFDictionaryRef)options);
                success = CGImageDestinationFinalize(destination);
                CFRelease(destination);
            }
        }
    }

    // If the format is not HEIC, just copy the file
    if (!success) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        success = [fileManager copyItemAtURL:sourceURL toURL:destinationURL error:nil];
    }

    CFRelease(source);
    return success;
}

- (void)getModifiedImageDataForAssetWithCompletion:(void (^)(BOOL success, NSError *error))completion {
    __weak typeof(self) weakSelf = self;
    self.requestOptions.progressHandler = ^(double progress, NSError * _Nullable error, BOOL * _Nonnull stop, NSDictionary * _Nullable info) {
        if (error) {
            Debug("Failed to get image data: %@", error);
            if (completion) {
                completion(NO, error);
            }
            [weakSelf finishUpload:false oid:nil error:nil];
            *stop = YES;
        }
    };
    
    [[PHImageManager defaultManager] requestImageDataForAsset:self.asset options:self.requestOptions resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
        if (!imageData) {
            NSError *noDataError = [NSError errorWithDomain:@"SeafUploadFile"
                                                       code:-1
                                                   userInfo:@{NSLocalizedDescriptionKey: @"No image data returned."}];
            if (completion) {
                completion(NO, noDataError);
            }
            [weakSelf finishUpload:false oid:nil error:nil];
            return;
        }
        
        // Check for HEIC format and whether conversion is needed
        if (![weakSelf uploadHeic] && [dataUTI isEqualToString:@"public.heic"]) {
            weakSelf.lpath = [weakSelf.lpath stringByReplacingOccurrencesOfString:@"HEIC" withString:@"JPG"];
            CIImage* ciImage = [CIImage imageWithData:imageData];
            if (![Utils writeCIImage:ciImage toPath:weakSelf.lpath]) {
                if (completion) {
                    completion(NO, nil);
                }
                [weakSelf finishUpload:false oid:nil error:nil];
                return;
            }
        } else {
            NSString *newExtension = [FileMimeType fileExtensionForUTI:dataUTI];
            if (!newExtension) {
                newExtension = self.lpath.pathExtension;
            }
            
            // Update the file extension if needed
            if (newExtension && ![[weakSelf.lpath.pathExtension lowercaseString] isEqualToString:[newExtension lowercaseString]]) {
                weakSelf.lpath = [[weakSelf.lpath stringByDeletingPathExtension] stringByAppendingPathExtension:newExtension];
                Debug(@"Updated file path to: %@", weakSelf.lpath);
            }
            
            // Write the image data to the file
            if (![Utils writeDataWithMeta:imageData toPath:weakSelf.lpath]) {
                if (completion) {
                    completion(NO, nil);
                }
                [weakSelf finishUpload:false oid:nil error:nil];
                return;
            }
        }
        
        weakSelf.filesize = [Utils fileSizeAtPath1:weakSelf.lpath];
        
        // Callback completion once everything is successful
        if (completion) {
            completion(YES, nil);
        }
    }];
}

- (void)getModifiedImageDataForAsset {
    __weak typeof(self) weakSelf = self;
    self.requestOptions.progressHandler = ^(double progress, NSError * _Nullable error, BOOL * _Nonnull stop, NSDictionary * _Nullable info) {
        if (error) {
            Debug("Failed to get image data: %@", error);
            [weakSelf finishUpload:false oid:nil error:nil];
        }
    };
    
    [[PHImageManager defaultManager] requestImageDataForAsset:_asset options:self.requestOptions resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
        if (imageData) {
            if (![self uploadHeic] && [dataUTI isEqualToString:@"public.heic"]) {
                self->_lpath = [self.lpath stringByReplacingOccurrencesOfString:@"HEIC" withString:@"JPG"];
                CIImage* ciImage = [CIImage imageWithData:imageData];
                if (![Utils writeCIImage:ciImage toPath:self.lpath]) {
                    [self finishUpload:false oid:nil error:nil];
                    return;
                }
            } else {
                NSString *newExtension = [FileMimeType fileExtensionForUTI:dataUTI];
                if (!newExtension) {
                    newExtension = self.lpath.pathExtension;
                }

                if (newExtension && ![self.lpath.pathExtension.lowercaseString isEqualToString:newExtension]) {
                    self.lpath = [[self.lpath stringByDeletingPathExtension] stringByAppendingPathExtension:newExtension];
                    Debug(@"Updated file path to: %@", self.lpath);
                }
                
                if (![Utils writeDataWithMeta:imageData toPath:self.lpath]) {
                    [self finishUpload:false oid:nil error:nil];
                    return;
                }
            }
            self->_filesize = [Utils fileSizeAtPath1:self.lpath];
        } else {
            [self finishUpload:false oid:nil error:nil];
        }
    }];
}

#pragma mark - Video Handling

- (void)getVideoForAsset {
    PHVideoRequestOptions *options = [PHVideoRequestOptions new];
    options.networkAccessAllowed = YES;
    options.version = PHVideoRequestOptionsVersionOriginal;
    options.progressHandler = ^(double progress, NSError * _Nullable error, BOOL * _Nonnull stop, NSDictionary * _Nullable info) {
        if (error) {
            Debug("Failed to get video: %@", error);
            [self finishUpload:false oid:nil error:nil];
        }
    };
    
    [[PHImageManager defaultManager] requestAVAssetForVideo:_asset options:options resultHandler:^(AVAsset * _Nullable asset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
        if ([asset isKindOfClass:[AVURLAsset class]]) {
            [Utils checkMakeDir:[self.lpath stringByDeletingLastPathComponent]];
            BOOL result =  [Utils copyFile:[(AVURLAsset *)asset URL] to:[NSURL fileURLWithPath:self.lpath]];
            if (!result) {
                [self finishUpload:false oid:nil error:nil];
            }
        } else {
            [self finishUpload:false oid:nil error:nil];
        }
        self->_filesize = [Utils fileSizeAtPath1:self.lpath];
        self->_asset = nil;
    }];
}

#pragma mark - QLPreviewItem

- (NSString *)previewItemTitle
{
    return self.name;
}

- (NSURL *)previewItemURL
{
    if (_preViewURL)
        return _preViewURL;

    [self checkAsset];
    if (![self.mime hasPrefix:@"text"]) {
        _preViewURL = [NSURL fileURLWithPath:self.lpath];
    } else if ([self.mime hasSuffix:@"markdown"]) {
        _preViewURL = [NSURL fileURLWithPath:[SeafileBundle() pathForResource:@"htmls/view_markdown" ofType:@"html"]];
    } else if ([self.mime hasSuffix:@"seafile"]) {
        _preViewURL = [NSURL fileURLWithPath:[SeafileBundle() pathForResource:@"htmls/view_seaf" ofType:@"html"]];
    } else {
        NSString *utf16Path = [SeafStorage.sharedObject.tempDir stringByAppendingPathComponent:self.name];
        if ([Utils tryTransformEncoding:utf16Path fromFile:self.lpath])
            _preViewURL = [NSURL fileURLWithPath:utf16Path];
    }
    if (!_preViewURL)
        _preViewURL = [NSURL fileURLWithPath:self.lpath];
    return _preViewURL;
}

#pragma mark - Thumbnails & Icons

- (UIImage *)icon {
    UIImage *thumb = [self getThumbImageFromAsset];
    if (thumb) {
        return thumb;
    } else {
        thumb = [self isImageFile] ? self.image : nil;
        return thumb ? [Utils reSizeImage:thumb toSquare:THUMB_SIZE * (int)[UIScreen mainScreen].scale] : [UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString];
    }
}

- (void)iconWithCompletion:(void (^)(UIImage *image))completion {
    [self getThumbImageFromAssetWithCompletion:^(UIImage *thumb) {
        if (thumb) {
            if (completion) {
                completion(thumb);
            }
        } else {
            if ([self isImageFile]) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    UIImage *image = self.image;
                    UIImage *resizedImage = image ? [Utils reSizeImage:image toSquare:THUMB_SIZE * (int)[UIScreen mainScreen].scale] : nil;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) {
                            completion(resizedImage ?: [UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString]);
                        }
                    });
                });
            } else {
                if (completion) {
                    completion([UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString]);
                }
            }
        }
    }];
}

- (UIImage *)thumb
{
    return [self icon];
}

- (void)saveThumbToLocal:(NSString *)oid {
    if (![self isImageFile]) return;
    int size = THUMB_SIZE * (int)[[UIScreen mainScreen] scale];
    NSString *thumbPath = [SeafStorage.sharedObject.thumbsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@-%d", oid, size]];
    if (![Utils fileExistsAtPath:thumbPath]) {
        [self iconWithCompletion:^(UIImage *thumbImage) {
            if (thumbImage) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    NSData *data = UIImageJPEGRepresentation(thumbImage, 1.0);
                    [data writeToFile:thumbPath atomically:true];
                });
            }
        }];
    }
}

- (UIImage *)getThumbImageFromAsset {
    __block UIImage *img = nil;
    if (_asset) {
        CGSize size = CGSizeMake(THUMB_SIZE * (int)[UIScreen mainScreen].scale, THUMB_SIZE * (int)[UIScreen mainScreen].scale);
        [[PHImageManager defaultManager] requestImageForAsset:_asset targetSize:size contentMode:PHImageContentModeDefault options:self.requestOptions resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            img = result;
        }];
    }
    return img;
}

- (void)getThumbImageFromAssetWithCompletion:(void (^)(UIImage *image))completion {
    if (_asset) {
        CGSize size = CGSizeMake(THUMB_SIZE * (int)[UIScreen mainScreen].scale, THUMB_SIZE * (int)[UIScreen mainScreen].scale);
        [[PHImageManager defaultManager] requestImageForAsset:_asset targetSize:size contentMode:PHImageContentModeDefault options:self.requestOptions resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            if (completion) {
                completion(result);
            }
        }];
    } else {
        if (completion) {
            completion(nil);
        }
    }
}

#pragma mark - Image Content

- (UIImage *)image {
    NSString *name = [@"cacheimage-ufile-" stringByAppendingString:self.name];
    NSString *cachePath = [[SeafStorage.sharedObject tempDir] stringByAppendingPathComponent:name];
    return [Utils imageFromPath:self.lpath withMaxSize:IMAGE_MAX_SIZE cachePath:cachePath];
}

- (void)getImageWithCompletion:(void (^)(UIImage *image))completion {
    NSString *name = [@"cacheimage-ufile-" stringByAppendingString:self.name];
    NSString *cachePath = [[SeafStorage.sharedObject tempDir] stringByAppendingPathComponent:name];
    [Utils imageFromPath:self.lpath withMaxSize:IMAGE_MAX_SIZE cachePath:cachePath completion:^(UIImage *image) {
        completion(image);
    }];
}

#pragma mark - Export & MIME

- (NSURL *)exportURL
{
    [self checkAsset];
    return [NSURL fileURLWithPath:self.lpath];
}

- (NSString *)mime
{
    return [FileMimeType mimeType:self.name];
}

- (NSString *)strContent
{
    return [Utils stringContent:self.lpath];
}

- (BOOL)saveStrContent:(NSString *)content
{
    _preViewURL = nil;
    return [content writeToFile:self.lpath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

#pragma mark - Upload Flow

- (void)uploadProgress:(float)progress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate uploadProgress:self progress:progress];
        if (self.taskProgressBlock) {
            self.taskProgressBlock(self, progress);
        }
    });
}

- (void)uploadComplete:(NSString *)oid error:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionBlock) { //看起来可以删掉
            self.completionBlock(self, oid, error);
        }
        //原来SeafDataTask finishBlock逻辑在这里
        if (!error) {
            if (self.retryable) { // Do not remove now, will remove it next time
                [self saveUploadFileToTaskStorage:self];
            }
        } else if (!self.retryable) {
            // Remove upload file local cache
            [self cleanup];
        }
        
        [self.delegate uploadComplete:!error file:self oid:oid];
        if (self.staredFileDelegate) {
            [self.staredFileDelegate uploadComplete:!error file:self oid:oid];
        }
    });

    dispatch_semaphore_signal(_semaphore);
}

- (void)saveUploadFileToTaskStorage:(SeafUploadFile *)ufile {
    NSString *key = [self uploadStorageKey:ufile.accountIdentifier];
    NSDictionary *dict = [SeafDataTaskManager.sharedObject convertTaskToDict:ufile];
    @synchronized(self) {
        NSMutableDictionary *taskStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:key]];
        [taskStorage setObject:dict forKey:ufile.lpath];
        [SeafStorage.sharedObject setObject:taskStorage forKey:key];
    }
}

- (NSString*)uploadStorageKey:(NSString*)accountIdentifier {
     return [NSString stringWithFormat:@"%@/%@",KEY_UPLOAD,accountIdentifier];
}

#pragma mark - Preview Image & PHImageRequestOptions

- (UIImage *)previewImage {
    if (!_previewImage) {
        return [UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString];
    } else {
        return _previewImage;
    }
}

- (PHImageRequestOptions *)requestOptions {
    if (!_requestOptions) {
        _requestOptions = [PHImageRequestOptions new];
        _requestOptions.networkAccessAllowed = YES; // iCloud
        _requestOptions.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
        _requestOptions.synchronous = YES;
    }
    return _requestOptions;
}

- (PHImageRequestOptions *)requestOptionsAsyn {
    if (!_requestOptions) {
        _requestOptions = [PHImageRequestOptions new];
        _requestOptions.networkAccessAllowed = YES; // iCloud
        _requestOptions.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
        _requestOptions.synchronous = NO;
    }
    return _requestOptions;
}

#pragma mark - Upload Preparation

- (void)prepareForUploadWithCompletion:(void (^)(BOOL success, NSError *error))completion {
    [self checkAssetWithCompletion:^(BOOL success, NSError *error) {
        // 检查文件是否存在于本地路径
        if (![[NSFileManager defaultManager] fileExistsAtPath:self.lpath]) {
            NSError *fileNotExistError = [NSError errorWithDomain:@"SeafUploadFile"
                                                             code:-1
                                                         userInfo:@{NSLocalizedDescriptionKey: @"File does not exist at the specified path"}];
            if (completion) {
                completion(NO, fileNotExistError);
            }
            return;
        }
        
        // 获取文件属性
        NSError *fileAttributesError = nil;
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.lpath error:&fileAttributesError];
        if (fileAttributesError) {
            if (completion) {
                completion(NO, fileAttributesError);
            }
            return;
        }
        
        self.filesize = [attrs fileSize];
                
        // 调用 completion 块并传递成功
        if (completion) {
            completion(YES, nil);
        }
    }];
}

@end
