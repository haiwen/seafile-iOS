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
    _syncDir = nil;
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
    
    Debug("backGroundCheckPhotos: called with force=%d, inAutoSync=%d, firstTimeSync=%d, uploadDir=%@, isUploadLivePhotoEnabled=%d",
          force, _inAutoSync, _connection.firstTimeSync, uploadDir ? uploadDir.name : @"nil",
          _connection.isUploadLivePhotoEnabled);
    
    //check whether is inAutoSync or firstTimeSync or uploadDir not exist
    bool shouldSkip = !_inAutoSync || (_connection.firstTimeSync && !uploadDir);
    if (shouldSkip) {
        Debug("backGroundCheckPhotos: skip - inAutoSync=%d, firstTimeSync=%d, uploadDir=%@", 
              _inAutoSync, _connection.firstTimeSync, uploadDir);
        return;
    }
    
    Debug("backGroundCheckPhotos: proceeding with photo check, force=%d", force);
    
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
    
    Debug("filterOutNeedUploadPhotos: uploadLivePhotoEnabled=%d, isFirstTimeSync=%d",
          self.connection.isUploadLivePhotoEnabled, self.connection.isFirstTimeSync);
    
    [self.fetchResult enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL * _Nonnull stop) {
        SeafPhotoAsset *photoAsset = [[SeafPhotoAsset alloc] initWithAsset:asset isCompress:NO];
        if (photoAsset.name != nil) {
            BOOL isUploaded = NO;
            BOOL isUploading = [self IsPhotoUploading:photoAsset];
            
            // First time sync: check if photo already exists on server (by base name)
            if (self.connection.isFirstTimeSync) {
                BOOL existsOnServer = [self isPhotoExistsOnServer:photoAsset];
                if (existsOnServer) {
                    [self setPhotoUploadedIdentifier:asset.localIdentifier];
                    isUploaded = YES;
                }
            } else {
                isUploaded = [self IsPhotoUploaded:photoAsset];
            }
            
            if (!isUploaded && !isUploading) {
                [self addUploadPhoto:photoAsset.localIdentifier];
            }
        }
    }];
    
    Debug("filterOutNeedUploadPhotos summary: totalToUpload=%lu", (unsigned long)self.photosArray.count);
}

#pragma mark - First Time Sync Helper

/// Check if photo exists on server by comparing base name (without extension).
/// This allows detecting previously backed up photos regardless of file format.
- (BOOL)isPhotoExistsOnServer:(SeafPhotoAsset *)photoAsset {
    if (!photoAsset.name || !self.syncDir) {
        return NO;
    }
    
    // Check by base name (without extension) for backward compatibility
    // This handles cases where the same photo was backed up with different extensions
    // (e.g., IMG_1234.jpg vs IMG_1234.heic)
    NSString *baseName = [photoAsset.name stringByDeletingPathExtension];
    return [self.syncDir baseNameExist:baseName];
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
        // Handle newly inserted photos
        if (detail.insertedObjects.count > 0) {
            Debug("Inserted items : %@", detail.insertedObjects);
            for (PHAsset *asset in detail.insertedObjects) {
                NSString *localIdentifier = asset.localIdentifier;
                
                // Delay processing by 2 seconds to allow Live Photo paired video resource to be ready.
                // This fixes the timing issue where PHPhotoLibraryChangeObserver fires before
                // the paired video resource is fully available for newly captured Live Photos.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), 
                              dispatch_get_main_queue(), ^{
                    [self processNewlyInsertedAssetWithIdentifier:localIdentifier];
                });
            }
        }
    }
}

/// Process a newly inserted photo after delay.
/// This method is called after a 2-second delay to ensure Live Photo paired video resources are ready.
- (void)processNewlyInsertedAssetWithIdentifier:(NSString *)localIdentifier {
    // Ensure we're still in auto sync mode
    if (!_inAutoSync) {
        Debug("Not in auto sync mode, skip processing: %@", localIdentifier);
        return;
    }
    
    // Re-fetch the asset (it may have been deleted during the delay)
    PHFetchResult *result = [PHAsset fetchAssetsWithLocalIdentifiers:@[localIdentifier] options:nil];
    PHAsset *asset = result.firstObject;
    if (!asset) {
        Debug("Asset no longer exists: %@", localIdentifier);
        return;
    }
    
    // Create SeafPhotoAsset with fresh detection (video resource should be ready now)
    SeafPhotoAsset *photoAsset = [[SeafPhotoAsset alloc] initWithAsset:asset isCompress:NO];
    if (photoAsset.name != nil) {
        // Check if not already uploaded or uploading
        if (![self IsPhotoUploaded:photoAsset] && ![self IsPhotoUploading:photoAsset]) {
            [self addUploadPhoto:photoAsset.localIdentifier];
            [self uploadPhotoByIdentifier:photoAsset.localIdentifier];
        }
    }
    
    SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection];
    [accountQueue postUploadTaskStatusChangedNotification];
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
