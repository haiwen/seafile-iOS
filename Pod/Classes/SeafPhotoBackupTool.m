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
#import "SeafUploadFile.h"
#import "SeafDataTaskManager.h"

#define DEFAULT_UPLOADINGARRAY_INTERVAL 10*60 // 10 min

@interface SeafPhotoBackupTool ()<PHPhotoLibraryChangeObserver>

@property (nonatomic, copy) NSString * _Nonnull accountIdentifier;

@property (nonatomic, copy) NSString * _Nonnull localUploadDir;

@property (nonatomic, strong) dispatch_queue_t photoCheckQueue;

@property (nonatomic, strong) dispatch_queue_t photoPickupQueue;

@property (nonatomic, strong) NSMutableDictionary *uploadingDict;

@property (nonatomic, strong) PHFetchResult *fetchResult;

@property (nonatomic, assign) BOOL firstTimeFilterOut;

@end

@implementation SeafPhotoBackupTool

- (instancetype _Nonnull )initWithConnection:(SeafConnection * _Nonnull)connection andLocalUploadDir:(NSString * _Nonnull)localUploadDir {
    self = [super init];
    if (self) {
        self.connection = connection;
        self.accountIdentifier = connection.accountIdentifier;
        self.localUploadDir = localUploadDir;
        self.firstTimeFilterOut = YES;
        [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.inAutoSync = false;
        self.inCheckPhotoss = false;
    }
    return self;
}

- (void)prepareForBackup {
    _photosArray = [[NSMutableArray alloc] init];
    _uploadingArray = [[NSMutableArray alloc] init];
    _uploadingDict = [[NSMutableDictionary alloc] init];
}

- (void)resetAll {
    _photosArray = nil;
    _inCheckPhotoss = false;
    _uploadingArray = nil;
    _uploadingDict = nil;
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
    bool shouldSkip = !_inAutoSync || (_connection.firstTimeSync && !uploadDir);
    if (shouldSkip) {
        return;
    }
    
    if (force || [self photosInSyncing] == 0) {
        NSArray *photos = [self filterOutUploadedPhotos];
        [photos enumerateObjectsUsingBlock:^(SeafPhotoAsset *photoAsset, NSUInteger idx, BOOL * _Nonnull stop) {
            if (![self IsPhotoUploaded:photoAsset] && ![self IsPhotoUploading:photoAsset]) {
                [self addUploadPhoto:photoAsset.localIdentifier];
            }
        }];
        
        long num = [[SeafRealmManager shared] numOfCachedPhotosWhithAccount:self.accountIdentifier];
        Debug("Filter out %ld photos, cached : %ld photos", (long)photos.count, num);
        
        [self checkPhotosNeedUploadInRealm];
    }
    
    if (_connection.firstTimeSync) {
        _connection.firstTimeSync = false;
    }
    
    Debug("GroupAll Total %ld photos need to upload: %@", (long)_photosArray.count, _connection.address);
    if (_photSyncWatcher) [_photSyncWatcher photoSyncChanged:self.photosInSyncing];
    
    _inCheckPhotoss = false;
    [self pickPhotosForUpload];
}

- (void)checkPhotosNeedUploadInRealm {
    NSArray *array = [[SeafRealmManager shared] getNeedUploadPhotosWithAccount:self.accountIdentifier];
    if (array == nil || array.count == 0) {
        return;
    }
    NSArray *copyArray = [NSArray arrayWithArray:_photosArray];
    [array enumerateObjectsUsingBlock:^(NSString *url, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *localIdentifier = [url stringByReplacingOccurrencesOfString:self.accountIdentifier withString:@""];
        if (localIdentifier != nil && ![copyArray containsObject:localIdentifier]) {
            [self addUploadPhoto:localIdentifier];
        }
    }];
}

- (void)pickPhotosForUpload {
    SeafDir *dir = _syncDir;
    if (!_inAutoSync || !dir || !self.photosArray || self.photosArray.count == 0) return;
    if (_connection.wifiOnly && ![[AFNetworkReachabilityManager sharedManager] isReachableViaWiFi]) {
        Debug("wifiOnly=%d, isReachableViaWiFi=%d, for server %@", _connection.wifiOnly, [[AFNetworkReachabilityManager sharedManager] isReachableViaWiFi], _connection.address);
        return;
    }

    Debug("Current %u, %u photos need to upload, dir=%@", (unsigned)self.photosArray.count, (unsigned)self.uploadingArray.count, dir.path);

    if (self.photoPickupQueue == nil) {
        self.photoPickupQueue = dispatch_queue_create("com.seafile.photoPickup", DISPATCH_QUEUE_CONCURRENT);
    }
    
    @weakify(self);
    dispatch_async(self.photoPickupQueue, ^{
        @strongify(self);
        [self checkAndRemoveFromUploadingArray];
        int count = 0;
        while (self.uploadingArray.count < 5 && count++ < 5) {
            NSString *localIdentifier = [self popUploadPhotoIdentifier];
            if (!localIdentifier) break;
            
            PHFetchResult *result = [PHAsset fetchAssetsWithLocalIdentifiers:@[localIdentifier] options:nil];
            PHAsset *asset = [result firstObject];
            if (asset) {
                SeafPhotoAsset *photoAsset = [[SeafPhotoAsset alloc] initWithAsset:asset isCompress:!self.connection.isUploadHeicEnabled];

                NSString *path = [self.localUploadDir stringByAppendingPathComponent:photoAsset.name];
                SeafUploadFile *file = [[SeafUploadFile alloc] initWithPath:path];
                file.retryable = false;
                file.autoSync = true;
                file.overwrite = true;
                [file setPHAsset:asset url:photoAsset.ALAssetURL];
                file.udir = dir;
                [file setCompletionBlock:^(SeafUploadFile *file, NSString *oid, NSError *error) {
                    [self autoSyncFileUploadComplete:file error:error];
                }];
                
                Debug("Add file %@ to upload list: %@ current %u %u", photoAsset.name, dir.path, (unsigned)self.photosArray.count, (unsigned)self.uploadingArray.count);
                BOOL res = [SeafDataTaskManager.sharedObject addUploadTask:file];
                if (!res) {
                    [self removeUploadingPhoto:localIdentifier];
                    [self removeFromUploadingDictWith:localIdentifier];
                    file = nil;
                }
            } else {
                [self removeUploadingPhoto:localIdentifier];
                [self removeFromUploadingDictWith:localIdentifier];
                [[SeafRealmManager shared] deletePhotoWithIdentifier:[self.accountIdentifier stringByAppendingString:localIdentifier] forAccount:self.accountIdentifier];
                if (self.photSyncWatcher) [self.photSyncWatcher photoSyncChanged:self.photosInSyncing];
            }
        }
        
        if (self.photosArray.count == 0) {
            Debug("Force check if there are new photos after all synced.");
            [self checkPhotos:true];
        }
    });
}

- (NSString *)popUploadPhotoIdentifier {
    @synchronized(self.photosArray) {
        if (!self.photosArray || self.photosArray.count == 0) return nil;
        NSString *localIdentifier = self.photosArray.firstObject;
        [self addUploadingPhotoIdentifier:localIdentifier];
        [self.photosArray removeObject:localIdentifier];
        [self updateUploadingDictWith:localIdentifier];
        Debug("Picked photo identifier: %@ remain: %u %u", localIdentifier, (unsigned)_photosArray.count, (unsigned)_uploadingArray.count);
        return localIdentifier;
    }
}

- (void)autoSyncFileUploadComplete:(SeafUploadFile *)ufile error:(NSError *)error {
    if (!error) {
        [self setPhotoUploadedIdentifier:ufile.assetIdentifier];
        [self removeUploadingPhoto:ufile.assetIdentifier];
        [self removeFromUploadingDictWith:ufile.assetIdentifier];
        Debug("Autosync file %@ %@, remain %u %u", ufile.name, ufile.assetURL, (unsigned)_photosArray.count, (unsigned)_uploadingArray.count);
    } else {
        Warning("Failed to upload photo %@: %@", ufile.name, error);
        // Add photo to the end of queue
        [self removeUploadingPhoto:ufile.assetIdentifier];
        [self addUploadPhoto:ufile.assetIdentifier];
        [self removeFromUploadingDictWith:ufile.assetIdentifier];
    }
    if (_photSyncWatcher) [_photSyncWatcher photoSyncChanged:self.photosInSyncing];
    [self pickPhotosForUpload];
}

- (NSArray *)filterOutUploadedPhotos {
    PHFetchResult *result = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumUserLibrary options:nil];
    
    NSPredicate *predicate = [self buildAutoSyncPredicte];
    if (!predicate) {
        return nil;
    }
    
    @synchronized(self) {
        if (_inCheckPhotoss) {
            return nil;
        }
        _inCheckPhotoss = true;
    }

    __block NSMutableArray *photos = [[NSMutableArray alloc] init];
    __block NSMutableArray *recentPhotos = [[NSMutableArray alloc] init];
    NSArray *oldPhotos;
    if (self.firstTimeFilterOut) {
        oldPhotos = [[SeafRealmManager shared] getNeedUploadPhotosWithAccount:self.accountIdentifier];
    }
    
    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    fetchOptions.predicate = predicate;
    PHAssetCollection *collection = result.firstObject;
    if (!self.fetchResult) {
        self.fetchResult = [PHAsset fetchAssetsInAssetCollection:collection options:fetchOptions];
    }
    
    [self.fetchResult enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL * _Nonnull stop) {
        SeafPhotoAsset *photoAsset = [[SeafPhotoAsset alloc] initWithAsset:asset isCompress:!self.connection.isUploadHeicEnabled];
        if (photoAsset.name == nil) {
            return;
        }
        [self saveNeedUploadPhotoToLocalWithAssetIdentifier:asset.localIdentifier];
        if (self.firstTimeFilterOut) {
            [recentPhotos addObject:[self.accountIdentifier stringByAppendingString:asset.localIdentifier]];
        }
        if (self.connection.isFirstTimeSync) {
            if ([self.syncDir nameExist:photoAsset.name]) {
                [self setPhotoUploadedIdentifier:asset.localIdentifier];
                Debug("First time sync, skip file %@(%@) which has already been uploaded", photoAsset.name, photoAsset.localIdentifier);
                return;
            }
        }
        [photos addObject:photoAsset];
    }];
    
    if (self.firstTimeFilterOut) {
        NSMutableArray *needDeletePhotos = [[NSMutableArray alloc] init];
        for (NSString *identifier in oldPhotos) {
            if (![recentPhotos containsObject:identifier]) {
                [needDeletePhotos addObject:identifier];
            }
        }
        
        for (NSString *cachePhotoId in needDeletePhotos) {
            [[SeafRealmManager shared] deletePhotoWithIdentifier:cachePhotoId forAccount:self.accountIdentifier];
        }
        self.firstTimeFilterOut = NO;
    }

    return photos;
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
    return [[SeafRealmManager shared] numOfCachedPhotosWithStatus:@"false" forAccount:self.accountIdentifier];
}

- (BOOL)IsPhotoUploaded:(SeafPhotoAsset *)asset {
    NSInteger saveCount = 0;
    if (asset.ALAssetURL && [asset.ALAssetURL respondsToSelector:NSSelectorFromString(@"absoluteString")] && asset.ALAssetURL.absoluteString) {
        NSString *value = [self getCachedPhotoStatuWithIdentifier:[self.accountIdentifier stringByAppendingString:asset.ALAssetURL.absoluteString]];
        if (value != nil) {
            saveCount ++;
        }
    }
    NSString *identifier = [self getCachedPhotoStatuWithIdentifier:[self.accountIdentifier stringByAppendingString:asset.localIdentifier]];
    if (identifier != nil && [identifier isEqualToString:@"true"]) {
        saveCount ++;
    }
    return saveCount > 0;
}

- (BOOL)IsPhotoUploading:(SeafPhotoAsset *)asset {
    if (!asset) {
        return false;
    }
    @synchronized(_photosArray) {
        if ([_photosArray containsObject:asset.localIdentifier]) return true;
    }
    @synchronized(_uploadingArray) {
        if ([_uploadingArray containsObject:asset.localIdentifier]) return true;
    }
    return false;
}

- (void)checkAndRemoveFromUploadingArray {
    if (self.uploadingArray == nil || self.uploadingDict == nil) {
        return;
    }
    if (self.uploadingArray == 0 && self.uploadingDict.count != 0) {
        [self.uploadingDict removeAllObjects];
        return;
    }
    NSDictionary *copyDict = [NSDictionary dictionaryWithDictionary:self.uploadingDict];
    NSArray *copyArray = [NSArray arrayWithArray:self.uploadingArray];
    for (NSString *identifier in copyArray) {
        if ([copyDict valueForKey:identifier]) {
            NSTimeInterval t1 = [[copyDict valueForKey:identifier] doubleValue];
            NSTimeInterval cur = [[NSDate date] timeIntervalSince1970];
            if (cur - t1 > DEFAULT_UPLOADINGARRAY_INTERVAL) {
                [self removeUploadingPhoto:identifier];
                [self addUploadPhoto:identifier];
                [self removeFromUploadingDictWith:identifier];
            }
        }
    }
}

- (void)clearUploadingVideos {
    [SeafDataTaskManager.sharedObject cancelAutoSyncVideoTasks:self.connection];
    [self removeVideosFromArray:_photosArray];
    [self removeVideosFromArray:_uploadingArray];
}

- (void)addUploadPhoto:(NSString *)localIdentifier {
    @synchronized(_photosArray) {
        [_photosArray addObject:localIdentifier];
    }
}

- (void)addUploadingPhotoIdentifier:(NSString *)localIdentifier {
    @synchronized(_uploadingArray) {
        [_uploadingArray addObject:localIdentifier];
    }
}

- (void)removeUploadingPhoto:(NSString *)localIdentifier {
    @synchronized(_uploadingArray) {
        [_uploadingArray removeObject:localIdentifier];
    }
}

- (void)updateUploadingDictWith:(NSString *)identifier {
    if (identifier) {
        @synchronized (self) {
            NSTimeInterval cur = [[NSDate date] timeIntervalSince1970];
            [self.uploadingDict setValue:[NSNumber numberWithDouble:cur] forKey:identifier];
        }
    }
}

- (void)removeFromUploadingDictWith:(NSString *)identifier {
    if (identifier) {
        @synchronized(self.uploadingDict) {
            [self.uploadingDict removeObjectForKey:identifier];
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
    _uploadingArray = [[NSMutableArray alloc] init];
    [[SeafRealmManager shared] clearAllCachedPhotosInAccount:self.accountIdentifier];
}

- (NSUInteger)photosInUploadingArray {
    return self.uploadingArray.count;
}

#pragma mark- cache
- (void)saveNeedUploadPhotoToLocalWithAssetIdentifier:(NSString *)assetIdentifier {
    NSString *key = [self.accountIdentifier stringByAppendingString:assetIdentifier];
    [[SeafRealmManager shared] savePhotoWithIdentifier:key forAccount:self.accountIdentifier andStatus:@"false"];
}

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
    Debug("Photos library changed.");
    PHFetchResultChangeDetails *detail = [changeInstance changeDetailsForFetchResult:self.fetchResult];
    if (detail && detail.fetchResultAfterChanges) {
        self.fetchResult = detail.fetchResultAfterChanges;
    }
    if (detail.removedObjects.count > 0) {
        for (PHAsset *asset in detail.removedObjects) {
            NSString *localIdentifier = asset.localIdentifier;
            [self removeUploadingPhoto:localIdentifier];
            [self removeFromUploadingDictWith:localIdentifier];
            [[SeafRealmManager shared] deletePhotoWithIdentifier:[self.accountIdentifier stringByAppendingString:localIdentifier] forAccount:self.accountIdentifier];
        }
        if (self.photSyncWatcher) [self.photSyncWatcher photoSyncChanged:self.photosInSyncing];
    }
    [self checkPhotos:YES];
}

@end
