//
//  SeafPhotoBackupTool.m
//  Seafile
//
//  Created by three on 2024/1/25.
//

#import "SeafPhotoBackupTool.h"
#import "SeafRealmManager.h"
#import "SeafPhotoAsset.h"
#import "Debug.h"
#import "SeafConnection.h"
#import "AFNetworkReachabilityManager.h"
#import "SeafDir.h"
#import "SeafDataTaskManager.h"
#import <FileProvider/NSFileProviderError.h>
#import "SeafUploadFileModel.h"
#import "SeafFileOperationManager.h"

#define DEFAULT_UPLOADINGARRAY_INTERVAL 10*60 // 10 min

@interface SeafPhotoBackupTool ()<PHPhotoLibraryChangeObserver>

@property (nonatomic, copy) NSString * _Nonnull accountIdentifier;

@property (nonatomic, copy) NSString * _Nonnull localUploadDir;

@property (nonatomic, strong) dispatch_queue_t photoCheckQueue;

@property (nonatomic, strong) dispatch_queue_t photoPickupQueue;

@property (nonatomic, strong) PHFetchResult *fetchResult;

@end

@implementation SeafPhotoBackupTool
@synthesize photosArray = _photosArray;

- (instancetype _Nonnull )initWithConnection:(SeafConnection * _Nonnull)connection andLocalUploadDir:(NSString * _Nonnull)localUploadDir {
    self = [super init];
    if (self) {
        self.connection = connection;
        self.accountIdentifier = connection.accountIdentifier;
        self.localUploadDir = localUploadDir;
        [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.inAutoSync = false;
        self.inCheckPhotos = false;
    }
    return self;
}

- (void)prepareForBackup {
    _photosArray = [[NSMutableArray alloc] init];
}

- (void)resetAll {
    _photosArray = nil;
    _inCheckPhotos = false;
    _fetchResult = nil;
}

- (void)checkPhotos:(BOOL)force {
    if (self.photoCheckQueue == nil) {
        self.photoCheckQueue = dispatch_queue_create("com.seafile.checkPhotos", DISPATCH_QUEUE_CONCURRENT);
    }
    dispatch_async(self.photoCheckQueue, ^{
        [self backGroundCheckPhotos:[NSNumber numberWithBool:force]];
    });
}

- (void)backGroundCheckPhotos:(NSNumber *)forceNumber {
    bool force = [forceNumber boolValue];
    SeafDir *uploadDir = _syncDir;
    //check whether is inAutoSync or firstTimeSync or uploadDir not exist
    bool shouldSkip = !_inAutoSync || (_connection.firstTimeSync && !uploadDir);
    if (shouldSkip) {
        return;
    }
    
    //If true check phone photo gallery.
    if (force) {
        
        [self filterOutNeedUploadPhotos];

        long num = [[SeafRealmManager shared] numOfCachedPhotosWhithAccount:self.accountIdentifier];
        Debug("Filter out %ld photos, cached : %ld photos", (long)_photosArray.count, num);
    }
    
    if (_connection.firstTimeSync) {
        _connection.firstTimeSync = false;
    }
    
    Debug("GroupAll Total %ld photos need to upload: %@", (long)_photosArray.count, _connection.address);
    
    _inCheckPhotos = false;
    [self pickPhotosForUpload];
}

- (void)pickPhotosForUpload {
    SeafDir *dir = _syncDir;
    if (!_inAutoSync || !dir || !self.photosArray || self.photosArray.count == 0) {
        SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection];
        [accountQueue postUploadTaskStatusChangedNotification];
        return;
    }
    
    if (_connection.wifiOnly && ![[AFNetworkReachabilityManager sharedManager] isReachableViaWiFi]) {
        Debug("wifiOnly=%d, isReachableViaWiFi=%d, for server %@", _connection.wifiOnly, [[AFNetworkReachabilityManager sharedManager] isReachableViaWiFi], _connection.address);
        SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection];
        [accountQueue postUploadTaskStatusChangedNotification];
        return;
    }
    
    // Refresh syncDir to get latest file list for case-insensitive matching
    @weakify(self);
    [dir loadContentSuccess:^(SeafDir *refreshedDir) {
        @strongify(self);
        [self doPickPhotosForUploadWithDir:refreshedDir];
    } failure:^(SeafDir *failedDir, NSError *error) {
        @strongify(self);
        Debug("Failed to refresh syncDir: %@", error);
        [self doPickPhotosForUploadWithDir:failedDir];
    }];
}

- (void)doPickPhotosForUploadWithDir:(SeafDir *)dir {
    if (!dir) {
        return;
    }
    
    NSArray *photos = [self.photosArray copy];
    
    PHFetchResult *result = [PHAsset fetchAssetsWithLocalIdentifiers:photos options:nil];
    
    NSMutableArray *uploadFilesArray = [[NSMutableArray alloc] init];
    BOOL uploadLivePhotoEnabled = self.connection.isUploadLivePhotoEnabled;
    
    for (PHAsset *asset in result) {
        if (asset) {
            SeafPhotoAsset *photoAsset = [[SeafPhotoAsset alloc] initWithAsset:asset isCompress:NO];
            NSString *filename = [photoAsset uploadNameWithLivePhotoEnabled:uploadLivePhotoEnabled];
            NSString *expectedFilename = filename;
            
            // Use actual server filename for case-insensitive overwrite on Linux
            NSString *actualFilename = [dir actualNameForCaseInsensitiveMatch:filename];
            if (actualFilename) {
                filename = actualFilename;
            }
            
            NSString *path = [self.localUploadDir stringByAppendingPathComponent:filename];
            SeafUploadFile *file = [[SeafUploadFile alloc] initWithPath:path];
            file.lastModified = asset.modificationDate;
            file.retryable = false;
            file.model.uploadFileAutoSync = true;
            file.model.overwrite = true;
            file.model.expectedFilename = expectedFilename;
            if (photoAsset.isLivePhoto && uploadLivePhotoEnabled) {
                file.model.isLivePhoto = YES;
            }
            
            [file setPHAsset:asset url:photoAsset.ALAssetURL];
            file.udir = dir;
            [file setCompletionBlock:^(SeafUploadFile *file, NSString *oid, NSError *error) {
                [self autoSyncFileUploadComplete:file error:error];
            }];
            [self saveUploadingFile:file withIdentifier:asset.localIdentifier];
            Debug("Add file %@ to upload list: %@ current %u", filename, dir.path, (unsigned)self.photosArray.count);
            [uploadFilesArray addObject:file];
        }
    }
    
    [SeafDataTaskManager.sharedObject addUploadTasksInBatch:uploadFilesArray forConnection:self.connection];
}

- (void)uploadPhotoByIdentifier:(NSString *)localIdentifier {
    if (!localIdentifier) {
        return;
    }
    
    SeafDir *dir = _syncDir;
    if (!_inAutoSync || !dir || !self.photosArray || self.photosArray.count == 0) return;
    if (_connection.wifiOnly && ![[AFNetworkReachabilityManager sharedManager] isReachableViaWiFi]) {
        Debug("wifiOnly=%d, isReachableViaWiFi=%d, for server %@", _connection.wifiOnly, [[AFNetworkReachabilityManager sharedManager] isReachableViaWiFi], _connection.address);
        return;
    }
    
    if (self.photoPickupQueue == nil) {
        self.photoPickupQueue = dispatch_queue_create("com.seafile.photoPickup", DISPATCH_QUEUE_CONCURRENT);
    }
    
    @weakify(self);
    dispatch_async(self.photoPickupQueue, ^{
        @strongify(self);
        PHFetchResult *result = [PHAsset fetchAssetsWithLocalIdentifiers:@[localIdentifier] options:nil];
        PHAsset *asset = [result firstObject];
        if (asset) {
            BOOL uploadLivePhotoEnabled = self.connection.isUploadLivePhotoEnabled;
            SeafPhotoAsset *photoAsset = [[SeafPhotoAsset alloc] initWithAsset:asset isCompress:NO];
            NSString *filename = [photoAsset uploadNameWithLivePhotoEnabled:uploadLivePhotoEnabled];
            NSString *expectedFilename = filename;
            
            // Use actual server filename for case-insensitive overwrite on Linux
            NSString *actualFilename = [dir actualNameForCaseInsensitiveMatch:filename];
            if (actualFilename) {
                filename = actualFilename;
            }
            
            NSString *path = [self.localUploadDir stringByAppendingPathComponent:filename];
            SeafUploadFile *file = [[SeafUploadFile alloc] initWithPath:path];
            file.lastModified = asset.modificationDate;
            file.retryable = false;
            file.model.uploadFileAutoSync = true;
            file.model.overwrite = true;
            file.model.expectedFilename = expectedFilename;
            if (photoAsset.isLivePhoto && uploadLivePhotoEnabled) {
                file.model.isLivePhoto = YES;
            }
            
            [file setPHAsset:asset url:photoAsset.ALAssetURL];
            file.udir = dir;
            [file setCompletionBlock:^(SeafUploadFile *file, NSString *oid, NSError *error) {
                [self autoSyncFileUploadComplete:file error:error];
            }];
            [self saveUploadingFile:file withIdentifier:localIdentifier];
            Debug("Add file %@ to upload list: %@ current %u", filename, dir.path, (unsigned)self.photosArray.count);
            [SeafDataTaskManager.sharedObject addUploadTask:file];
        } else {
            @synchronized(self.photosArray) {
                [self.photosArray removeObject:localIdentifier];
            }
        }
    });
}

- (NSString *)popUploadPhotoIdentifier {
    @synchronized(self.photosArray) {
        if (!self.photosArray || self.photosArray.count == 0) return nil;
        NSString *localIdentifier = self.photosArray.firstObject;
        [self.photosArray removeObject:localIdentifier];
        Debug("Picked photo identifier: %@ remain: %u", localIdentifier, (unsigned)_photosArray.count);
        return localIdentifier;
    }
}

- (void)autoSyncFileUploadComplete:(SeafUploadFile *)ufile error:(NSError *)error {
    if (!error) {
        // Rename file to normalize case if needed
        NSString *currentName = ufile.name;
        NSString *expectedName = ufile.model.expectedFilename;
        if (expectedName && ![currentName isEqualToString:expectedName]) {
            [[SeafFileOperationManager sharedManager] renameEntry:currentName
                                                          newName:expectedName
                                                            inDir:ufile.udir
                                                       completion:^(BOOL success, SeafBase *renamedFile, NSError *renameError) {
                if (!success) {
                    Warning(@"Failed to rename %@ to %@: %@", currentName, expectedName, renameError);
                }
            }];
        }
        
        [self setPhotoUploadedIdentifier:ufile.assetIdentifier];
        @synchronized(self.photosArray) {
            [self.photosArray removeObject:ufile.assetIdentifier];
        }
    } else {
        Warning("Failed to upload photo %@: %@", ufile.name, error);
        //will retry by SeafAccountTaskQueue timer every 30s.
    }
}

- (void)filterOutNeedUploadPhotos {
    PHFetchResult *result = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumUserLibrary options:nil];
    
    NSPredicate *predicate = [self buildAutoSyncPredicte];
    if (!predicate) {
        return;
    }
    
    @synchronized(self) {
        if (_inCheckPhotos) {
            return;
        }
        _inCheckPhotos = true;
    }
    
    self.photosArray = [[NSMutableArray alloc] init];
    
    SeafAccountTaskQueue *accountQueue =[SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection];
    [accountQueue cancelAutoSyncTasks];
        
    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    fetchOptions.predicate = predicate;
    PHAssetCollection *collection = result.firstObject;
    
    self.fetchResult = [PHAsset fetchAssetsInAssetCollection:collection options:fetchOptions];
    BOOL uploadLivePhotoEnabled = self.connection.isUploadLivePhotoEnabled;
    
    [self.fetchResult enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL * _Nonnull stop) {
        SeafPhotoAsset *photoAsset = [[SeafPhotoAsset alloc] initWithAsset:asset isCompress:NO];
        if (photoAsset.name != nil) {
            // First time sync: check if photo already exists on server
            if (self.connection.isFirstTimeSync) {
                if ([self isPhotoExistsOnServer:photoAsset livePhotoEnabled:uploadLivePhotoEnabled]) {
                    [self setPhotoUploadedIdentifier:asset.localIdentifier];
                    return;
                }
            }
            
            BOOL isUploaded = [self IsPhotoUploaded:photoAsset];
            BOOL isUploading = [self IsPhotoUploading:photoAsset];
            
            // Re-upload Live Photo if server only has static version
            if (isUploaded && photoAsset.isLivePhoto && uploadLivePhotoEnabled) {
                if (![self isMotionPhotoExistsOnServer:photoAsset]) {
                    isUploaded = NO;
                }
            }
            
            if (!isUploaded && !isUploading) {
                [self addUploadPhoto:photoAsset.localIdentifier];
            }
        }
    }];
}

#pragma mark - First Time Sync Helper

/// Check if photo exists on server (with backward compatibility for HEIC/JPG variants).
- (BOOL)isPhotoExistsOnServer:(SeafPhotoAsset *)photoAsset livePhotoEnabled:(BOOL)livePhotoEnabled {
    if (!photoAsset.name || !self.syncDir) {
        return NO;
    }
    
    // Live Photo: use file size comparison
    if (photoAsset.isLivePhoto && livePhotoEnabled) {
        return [self isMotionPhotoExistsOnServer:photoAsset];
    }
    
    // Check current upload name
    NSString *uploadName = [photoAsset uploadNameWithLivePhotoEnabled:livePhotoEnabled];
    if ([self.syncDir nameExist:uploadName]) {
        return YES;
    }
    
    // Check original filename
    if (![uploadName isEqualToString:photoAsset.name]) {
        if ([self.syncDir nameExist:photoAsset.name]) {
            return YES;
        }
    }
    
    // Check format variants (HEIC ↔ JPG) for backward compatibility
    NSString *baseName = [photoAsset.name stringByDeletingPathExtension];
    NSString *ext = [photoAsset.name.pathExtension lowercaseString];
    
    if ([ext isEqualToString:@"heic"] || [ext isEqualToString:@"heif"]) {
        NSString *jpgVariant = [baseName stringByAppendingPathExtension:@"jpg"];
        if ([self.syncDir nameExist:jpgVariant]) {
            return YES;
        }
    } else if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) {
        NSString *heicVariant = [baseName stringByAppendingPathExtension:@"heic"];
        if ([self.syncDir nameExist:heicVariant]) {
            return YES;
        }
    }
    
    // Check edited photo's JPG variant (iOS exports edited photos as JPEG)
    if (photoAsset.isModified) {
        if (![ext isEqualToString:@"jpg"] && ![ext isEqualToString:@"jpeg"]) {
            NSString *jpgVariant = [baseName stringByAppendingPathExtension:@"jpg"];
            if ([self.syncDir nameExist:jpgVariant]) {
                return YES;
            }
        }
    }
    
    return NO;
}

/// Check if motion photo exists on server using file size comparison.
- (BOOL)isMotionPhotoExistsOnServer:(SeafPhotoAsset *)photoAsset {
    if (!photoAsset.isLivePhoto || !self.syncDir) {
        return NO;
    }
    
    NSString *uploadName = [photoAsset uploadNameWithLivePhotoEnabled:YES];
    NSNumber *serverFileSize = [self.syncDir fileSizeForName:uploadName];
    if (!serverFileSize) {
        return NO;
    }
    
    unsigned long long photoSize = photoAsset.photoResourceSize;
    unsigned long long videoSize = photoAsset.pairedVideoResourceSize;
    if (photoSize == 0 || videoSize == 0) {
        return YES;
    }
    
    // Compare server file size to expected static/motion sizes
    unsigned long long serverSize = [serverFileSize unsignedLongLongValue];
    unsigned long long expectedStaticSize = photoSize;
    unsigned long long expectedMotionSize = photoSize + videoSize;
    
    unsigned long long distanceToStatic = (serverSize > expectedStaticSize) ?
        (serverSize - expectedStaticSize) : (expectedStaticSize - serverSize);
    unsigned long long distanceToMotion = (serverSize > expectedMotionSize) ?
        (serverSize - expectedMotionSize) : (expectedMotionSize - serverSize);
    
    return (distanceToMotion < distanceToStatic);
}

- (NSPredicate *)buildAutoSyncPredicte {
    NSPredicate *predicate = nil;
    NSPredicate *predicateImage = [NSPredicate predicateWithFormat:@"mediaType == %i", PHAssetMediaTypeImage];
    NSPredicate *predicateVideo = [NSPredicate predicateWithFormat:@"mediaType == %i", PHAssetMediaTypeVideo];
    if (_connection.isAutoSync) {
        predicate = predicateImage;
    }
    if (_connection.isAutoSync && _connection.isVideoSync) {
        predicate = [NSCompoundPredicate orPredicateWithSubpredicates:@[predicateImage, predicateVideo]];
    }
    return predicate;
}


- (NSUInteger)photosInSyncing {
    return self.photosArray.count;
}

- (BOOL)IsPhotoUploaded:(SeafPhotoAsset *)asset {
    NSString *realmAssetId = [self.accountIdentifier stringByAppendingString:asset.localIdentifier];
    return [[SeafRealmManager shared] isPhotoExistInRealm:realmAssetId forAccount:self.accountIdentifier];
}

- (BOOL)IsPhotoUploading:(SeafPhotoAsset *)asset {
    if (!asset) {
        return false;
    }
    @synchronized(self.photosArray) {
        if ([self.photosArray containsObject:asset.localIdentifier]) return true;
    }

    return false;
}

- (void)clearUploadingVideos {
    SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection];
    [accountQueue cancelAutoSyncVideoTasks];
    @synchronized(self.photosArray) {
        [self removeVideosFromArray:_photosArray];
    }
}

- (void)addUploadPhoto:(NSString *)localIdentifier {
    @synchronized(self.photosArray) {
        [self.photosArray addObject:localIdentifier];
    }
}

- (void)removeNeedUploadPhoto:(NSString *)localIdentifier {
    @synchronized(self.photosArray) {
        [self.photosArray removeObject:localIdentifier];
    }
}

- (void)saveUploadingFile:(SeafUploadFile *)file withIdentifier:(NSString *)identifier {
    if (identifier) {
        @synchronized (self) {
            NSTimeInterval cur = [[NSDate date] timeIntervalSince1970];
        }
    }
}

- (void)removeVideosFromArray:(NSMutableArray *)arr {
    if (arr.count == 0)
        return;
    @synchronized(self) {
        NSMutableArray *videos = [[NSMutableArray alloc] init];
        for (NSURL *url in arr) {
            if ([Utils isVideoExt:url.pathExtension])
                [videos addObject:url];
        }
        [arr removeObjectsInArray:videos];
    }
}

- (void)resetUploadedPhotos
{
    @synchronized(self.photosArray) {
        _photosArray = [[NSMutableArray alloc] init];
    }
    [[SeafRealmManager shared] clearAllCachedPhotosInAccount:self.accountIdentifier];
}

- (void)resetUploadingArray {
    @synchronized(self.photosArray) {
        self.photosArray = nil;
        self.photosArray = [[NSMutableArray alloc] init];
    }
}

#pragma mark- cache
- (NSString *)getCachedPhotoStatuWithIdentifier:(NSString *)identifier {
    return [[SeafRealmManager shared] getPhotoStatusWithIdentifier:identifier forAccount:self.accountIdentifier];
}

- (void)setPhotoUploadedIdentifier:(NSString *)localIdentifier {
    NSString *key = [self.accountIdentifier stringByAppendingString:localIdentifier];
    [[SeafRealmManager shared] updateCachePhotoWithIdentifier:key forAccount:self.accountIdentifier andStatus:@"true"];
}

#pragma mark - PHPhotoLibraryChangeObserver
// Observes changes to the photo library and triggers synchronization if necessary.
- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    if (!_inAutoSync) {
        return;
    }
    Debug("Photos library changed.");
    PHFetchResultChangeDetails *detail = [changeInstance changeDetailsForFetchResult:self.fetchResult];
    if (detail && detail.fetchResultAfterChanges) {
        self.fetchResult = detail.fetchResultAfterChanges;
        //delete photo
        if (detail.removedObjects.count > 0) {
            NSMutableArray *localIdentifiersNeedRemove = [[NSMutableArray alloc] init];
            for (PHAsset *asset in detail.removedObjects) {
                NSString *localIdentifier = asset.localIdentifier;
                [self removeNeedUploadPhoto:localIdentifier];
                [localIdentifiersNeedRemove addObject:localIdentifier];
            }
            SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection];
            [accountQueue cancelUploadTasksForLocalIdentifier:localIdentifiersNeedRemove];
        }
        //
        if (detail.insertedObjects.count > 0) {
            Debug("Inserted items : %@", detail.insertedObjects);
            for (PHAsset *asset in detail.insertedObjects) {
                SeafPhotoAsset *photoAsset = [[SeafPhotoAsset alloc] initWithAsset:asset isCompress:NO];
                if (photoAsset.name != nil) {
                    //if not exist in realm,add to photos.
                    if (![self IsPhotoUploaded:photoAsset] &&![self IsPhotoUploading:photoAsset]) {
                        [self addUploadPhoto:photoAsset.localIdentifier];
                        [self uploadPhotoByIdentifier:photoAsset.localIdentifier];
                    }
                }
            }
            SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection];
            [accountQueue postUploadTaskStatusChangedNotification];
        }
    }
}

#pragma mark - getter & setter
- (NSMutableArray *)photosArray {
    if (!_photosArray) {
        _photosArray = [[NSMutableArray alloc] init];
    }
    return _photosArray;
}

- (void)setPhotosArray:(NSMutableArray *)photosArray {
    if (_photosArray != photosArray) {
        _photosArray = photosArray;
    }
}

@end
