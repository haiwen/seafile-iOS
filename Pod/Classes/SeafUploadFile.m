//
//  SeafUploadFile.m
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafUploadFile.h"
#import "SeafUploadFileModel.h"
#import "SeafAssetManager.h"
#import "Debug.h"
#import "Utils.h"
#import "SeafFile.h"
#import "UIImage+FileType.h"
#import "FileMimeType.h"
#import "SeafRepos.h"
#import "SeafDataTaskManager.h"
#import "SeafStorage.h"
#import "SeafRealmManager.h"
#import <MobileCoreServices/MobileCoreServices.h>

#ifndef kUTTypeHEIC
#define kUTTypeHEIC CFSTR("public.heic")
#endif

#ifndef kUTTypeHEIF
#define kUTTypeHEIF CFSTR("public.heif")
#endif

@interface SeafUploadFile ()
@property (readonly) NSString *mime;
@property (strong, nonatomic) NSURL *preViewURL;
@property (nonatomic, strong) PHImageRequestOptions *requestOptions;
@end

@implementation SeafUploadFile

#pragma mark - Initialization

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _model = [[SeafUploadFileModel alloc] initWithPath:path];
        _assetManager = [[SeafAssetManager alloc] init];
        _semaphore = dispatch_semaphore_create(0);
    }
    return self;
}

+ (void)clearCache
{
    [Utils clearAllFiles:SeafStorage.sharedObject.uploadsDir];
}

#pragma mark - Property Forwarding

// Forward model properties
- (NSString *)name {
    return [self.lpath lastPathComponent];
}

- (NSString *)lpath {
    return self.model.lpath;
}

- (long long)filesize {
    if (!self.model.filesize) {
        self.model.filesize = [Utils fileSizeAtPath1:self.lpath];
    }
    return self.model.filesize;
}

- (BOOL)uploading {
    return self.model.uploading;
}

- (BOOL)uploaded {
    return self.model.uploaded;
}

- (NSString *)assetIdentifier {
    return self.model.assetIdentifier;
}

- (BOOL)overwrite {
    return self.model.overwrite;
}

- (PHAsset *)asset {
    return self.model.asset;
}

- (BOOL)uploadFileAutoSync {
    return self.model.uploadFileAutoSync;
}

- (BOOL)isEditedFile {
    return self.model.isEditedFile;
}

- (NSString *)editedFileRepoId {
    return self.model.editedFileRepoId;
}

- (NSString *)editedFilePath {
    return self.model.editedFilePath;
}

- (NSString *)editedFileOid {
    return self.model.editedFileOid;
}

- (BOOL)shouldShowUploadFailure {
    return self.model.shouldShowUploadFailure;
}

#pragma mark - SeafPreView Protocol

- (UIImage *)image {
    if (self.asset) {
        return [self getThumbImageFromAsset];
    }
    
    NSString *cacheName = [@"cacheimage-ufile-" stringByAppendingString:self.name];
    NSString *cachePath = [[SeafStorage.sharedObject tempDir] stringByAppendingPathComponent:cacheName];
    return [Utils imageFromPath:self.lpath withMaxSize:IMAGE_MAX_SIZE cachePath:cachePath];
}

- (void)getImageWithCompletion:(void (^)(UIImage *image))completion {
    if (self.asset) {
        [self getImageFromPHAssetWithCompletion:completion];
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *image = [self image];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(image);
            }
        });
    });
}

- (UIImage *)thumb {
    return [self icon];
}

- (UIImage *)icon {
    // First try to get thumbnail from asset
    UIImage *thumb = [self getThumbImageFromAsset];
    if (thumb) {
        return thumb;
    }
    
    // If no asset thumbnail, try to get from image file
    if ([self isImageFile]) {
        thumb = self.image;
        if (thumb) {
            return [Utils reSizeImage:thumb toSquare:THUMB_SIZE * (int)[UIScreen mainScreen].scale];
        }
    }
    
    // Fallback to mime type icon
    return [UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString];
}

- (void)iconWithCompletion:(void (^)(UIImage *image))completion {
    [self getThumbImageFromAssetWithCompletion:^(UIImage *thumb) {
        if (thumb) {
            completion(thumb);
            return;
        }
        
        if ([self isImageFile]) {
            [self getImageWithCompletion:^(UIImage *image) {
                UIImage *resizedImage = image ? [Utils reSizeImage:image toSquare:THUMB_SIZE * (int)[UIScreen mainScreen].scale] : nil;
                completion(resizedImage ?: [UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString]);
            }];
        } else {
            completion([UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString]);
        }
    }];
}

- (NSURL *)exportURL {
    [self.assetManager checkAssetWithFile:self completion:nil];
    return [NSURL fileURLWithPath:self.lpath];
}

- (NSString *)mime {
    return [FileMimeType mimeType:self.name];
}

- (BOOL)editable {
    return NO;
}

- (BOOL)uploadHeic {
    return self.udir.connection.isUploadHeicEnabled;
}

- (NSString *)strContent {
    return [Utils stringContent:self.lpath];
}

- (BOOL)saveStrContent:(NSString *)content {
    self.preViewURL = nil;
    return [content writeToFile:self.lpath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (BOOL)hasCache {
    return YES;
}

- (BOOL)isImageFile {
    return [Utils isImageFile:self.name];
}

- (BOOL)isVideoFile {
    return [Utils isVideoFile:self.name];
}

- (long long)mtime {
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.lpath]) {
        return [[NSDate date] timeIntervalSince1970];
    }
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.lpath error:nil];
    return [[attributes fileModificationDate] timeIntervalSince1970];
}

- (void)load:(id<SeafDentryDelegate>)delegate force:(BOOL)force {
    [self.assetManager checkAssetWithFile:self completion:nil];
}

- (void)cancelAnyLoading {
    [self cancel];
}

#pragma mark - SeafTask Protocol

- (NSString *)accountIdentifier {
    return self.udir.connection.accountIdentifier;
}

- (void)setTaskProgressBlock:(TaskProgressBlock)block {
    _taskProgressBlock = block;
}

#pragma mark - Upload Methods

- (void)prepareForUploadWithCompletion:(void (^)(BOOL success, NSError *error))completion {
    Debug(@"Preparing upload for file at path: %@", self.model.lpath);
    
    // If there's an asset, process it first
    if (self.model.asset) {
        [self.assetManager checkAssetWithFile:self completion:^(BOOL success, NSError *error) {
            if (!success) {
                if (completion) completion(NO, error);
                return;
            }
            
            // After asset is processed, validate the file
            [self validateFileAndAttributesWithCompletion:completion];
        }];
    } else {
        // If no asset, directly validate the file
        [self validateFileAndAttributesWithCompletion:completion];
    }
}

// Helper method to validate file existence and attributes
- (void)validateFileAndAttributesWithCompletion:(void (^)(BOOL success, NSError *error))completion {
    if (!self.model.lpath || ![[NSFileManager defaultManager] fileExistsAtPath:self.model.lpath]) {
        Debug(@"File does not exist at path: %@", self.model.lpath);
        NSError *fileNotExistError = [NSError errorWithDomain:@"SeafUploadFile"
                                                       code:-1
                                                   userInfo:@{NSLocalizedDescriptionKey: @"File does not exist at the specified path"}];
        if (completion) completion(NO, fileNotExistError);
        return;
    }
    
    // Get file attributes
    NSError *fileAttributesError = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.model.lpath error:&fileAttributesError];
    if (fileAttributesError) {
        Debug(@"Error getting file attributes: %@", fileAttributesError);
        if (completion) completion(NO, fileAttributesError);
        return;
    }
    
    self.model.filesize = [attrs fileSize];
    Debug(@"File size: %lld", self.model.filesize);
    
    if (completion) completion(YES, nil);
}

- (void)uploadProgress:(float)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate uploadProgress:self progress:progress];
        if (self.taskProgressBlock) {
            self.taskProgressBlock(self, progress);
        }
    });
}

- (void)finishUpload:(BOOL)result oid:(NSString *)oid error:(NSError *)error {
    @synchronized(self) {
        if (!self.model.uploading) return;
        self.model.uploading = NO;
        self.task = nil;
        self.uploadError = error;
    }
    self.model.uploaded = result;
    NSError *err = error;
    if (!err && !result) {
        err = [Utils defaultError];
    }
    
    self.lastFinishTimestamp = [[NSDate new] timeIntervalSince1970];
    NSString *fOid = oid;
    
    Debug("result=%d, name=%@, delegate=%@, oid=%@, err=%@\n", result, self.name, _delegate, fOid, err);
    
    if (result) {
        if (self.isEditedFile) {

            if (self.editedFileOid) {
                [Utils removeFile:[SeafStorage.sharedObject documentPath:self.editedFileOid]];
            }
        }
        
        if (_starred && self.udir) {
            NSString* rpath = [_udir.path stringByAppendingPathComponent:self.name];
            [_udir.connection setStarred:YES repo:_udir.repoId path:rpath completion:nil];
        }
        
        if (!self.uploadFileAutoSync) {
            [Utils linkFileAtPath:self.lpath to:[SeafStorage.sharedObject documentPath:fOid] error:nil];
            [self updateSeafFileStatusWithOid:fOid];
        } else {
            // For auto sync photos, release local cache files immediately.
            [self cleanup];
        }
    }
    [self uploadComplete:fOid error:err];
}

#pragma mark - Asset Methods

- (void)setPHAsset:(PHAsset *)asset url:(NSURL *)url {
    [self.assetManager setAsset:asset url:url forFile:self];
}

- (void)getDataForAssociatedAssetWithCompletion:(void (^_Nullable)(NSData * _Nullable data, NSError * _Nullable error))completion {
    if (!self.model.asset) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"SeafUploadFile"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"No PHAsset associated with this file."}];
            completion(nil, error);
        }
        return;
    }

    PHImageManager *manager = [PHImageManager defaultManager];
    PHImageRequestOptions *options = [PHImageRequestOptions new];
    options.networkAccessAllowed = YES; // Allow downloading from iCloud if necessary
    options.version = PHImageRequestOptionsVersionCurrent; // Get the most current version
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;

    if (@available(iOS 13, *)) {
        [manager requestImageDataAndOrientationForAsset:self.model.asset
                                                options:options
                                          resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, CGImagePropertyOrientation orientation, NSDictionary * _Nullable info) {
            NSError *error = [info objectForKey:PHImageErrorKey];
            if (completion) {
                completion(imageData, error);
            }
        }];
    } else {
        [manager requestImageForAsset:self.model.asset
                           targetSize:PHImageManagerMaximumSize
                          contentMode:PHImageContentModeDefault
                              options:options
                        resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            NSError *error = [info objectForKey:PHImageErrorKey];
            NSData *data = nil;
            if (result) {
                if ([[info objectForKey:PHImageResultIsDegradedKey] boolValue]) {
                    // Skip degraded image
                    return;
                }
                // Try to get HEIC data if possible, otherwise JPEG
                NSString *uti = [self.model.asset valueForKey:@"uniformTypeIdentifier"];
                if (uti && (UTTypeConformsTo((__bridge CFStringRef)uti, kUTTypeHEIC) || UTTypeConformsTo((__bridge CFStringRef)uti, kUTTypeHEIF))) {
                    data = UIImageJPEGRepresentation(result, 0.9);
                } else if (CGImageGetAlphaInfo(result.CGImage) == kCGImageAlphaNone || CGImageGetAlphaInfo(result.CGImage) == kCGImageAlphaNoneSkipLast || CGImageGetAlphaInfo(result.CGImage) == kCGImageAlphaNoneSkipFirst) {
                    data = UIImageJPEGRepresentation(result, 0.9);
                } else {
                    data = UIImagePNGRepresentation(result);
                }

            }
            if (completion) {
                completion(data, error);
            }
        }];
    }
}

#pragma mark - Cleanup Methods

- (void)cleanup {
    if (!self.model.lpath) return;
    
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.model.lpath error:&error];
    if (error) {
        Warning("Failed to remove file %@: %@", self.model.lpath, error);
    }
}

- (void)cancel {
    Debug("Cancel uploadFile: %@", self.model.lpath);
    if (!self.udir) return;
    
    @synchronized(self) {
        [self.task cancel];
        [self cleanup];
        [self.udir removeUploadItem:self];
        self.udir = nil;
        self.task = nil;
    }
}

#pragma mark - Properties & Basic Accessors

- (NSString *)previewItemTitle
{
    return self.name;
}

- (NSURL *)previewItemURL
{
    if (_preViewURL)
        return _preViewURL;

    [self load:nil force:NO];
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

- (UIImage *)getThumbImageFromAsset {
    __block UIImage *img = nil;
    if (self.model.asset) {
        CGSize size = CGSizeMake(THUMB_SIZE * (int)[UIScreen mainScreen].scale, THUMB_SIZE * (int)[UIScreen mainScreen].scale);
        [[PHImageManager defaultManager] requestImageForAsset:self.model.asset targetSize:size contentMode:PHImageContentModeDefault options:self.requestOptions resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            img = result;
        }];
    }
    return img;
}

- (void)getThumbImageFromAssetWithCompletion:(void (^)(UIImage *image))completion {
    if (self.model.asset) {
        CGSize size = CGSizeMake(THUMB_SIZE * (int)[UIScreen mainScreen].scale, THUMB_SIZE * (int)[UIScreen mainScreen].scale);
        [[PHImageManager defaultManager] requestImageForAsset:self.model.asset targetSize:size contentMode:PHImageContentModeDefault options:self.requestOptions resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
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

- (void)getImageFromPHAssetWithCompletion:(void (^)(UIImage *image))completion {
    if (self.model.asset) {
        CGSize size = CGSizeMake(IMAGE_MAX_SIZE * (int)[UIScreen mainScreen].scale, IMAGE_MAX_SIZE * (int)[UIScreen mainScreen].scale);
        [[PHImageManager defaultManager] requestImageForAsset:self.model.asset targetSize:size contentMode:PHImageContentModeDefault options:self.requestOptions resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
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

#pragma mark - Upload Flow

- (void)uploadComplete:(NSString *)oid error:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionBlock) { // It seems this can be removed
            self.completionBlock(self, oid, error);
        }
        // Original SeafDataTask finishBlock logic is here
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
    }
    return _previewImage;
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

- (NSTimeInterval)lastFinishTimestamp {
    return self.model.lastFinishTimestamp;
}

- (void)setLastFinishTimestamp:(NSTimeInterval)lastFinishTimestamp {
    self.model.lastFinishTimestamp = lastFinishTimestamp;
}

- (BOOL)retryable {
    return self.model.retryable;
}

- (void)setRetryable:(BOOL)retryable {
    self.model.retryable = retryable;
}

- (NSInteger)retryCount {
    return self.model.retryCount;
}

- (void)setRetryCount:(NSInteger)retryCount {
    self.model.retryCount = retryCount;
}

- (NSString *)uniqueKey
{
    NSString *uniqueKey = [NSString stringWithFormat:@"%@/%@/%@", self.udir.connection.accountIdentifier, self.udir.repoId, self.name];
    return uniqueKey;
}

- (void)updateSeafFileStatusWithOid:(NSString *)oid{
    if (![Utils isMainApp]) return;
    NSString *filePath = [SeafStorage.sharedObject documentPath:oid];
    
    SeafFileStatus *fileStatus = [[SeafFileStatus alloc] init];
    
    fileStatus.uniquePath = self.uniqueKey;
    fileStatus.serverOID = oid;
    fileStatus.localMTime = [[NSDate date] timeIntervalSince1970];
    fileStatus.fileName = self.name;
    fileStatus.dirPath = self.udir.path;
    fileStatus.localFilePath = filePath;

    [[SeafRealmManager shared] updateFileStatus:fileStatus];
}

- (BOOL)waitUpload {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    return self.uploaded;
}

@end
