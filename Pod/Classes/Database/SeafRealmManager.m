//
//  SeafRealmManager.m
//  Seafile
//
//  Created by three on 2023/12/16.
//

#import "SeafRealmManager.h"
#import <Realm/Realm.h>
#import "SeafCachePhoto.h"
#import "SeafStorage.h"
#import "Debug.h"

@interface SeafRealmManager()

@end

@implementation SeafRealmManager

static SeafRealmManager* instance;

+ (instancetype)shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SeafRealmManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        RLMRealmConfiguration *config = [RLMRealmConfiguration defaultConfiguration];

        // Define the new safe directory in Library/Application Support
        NSURL *appSupportURL = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
        NSURL *newFileURL = [appSupportURL URLByAppendingPathComponent:@"default.realm"];

        // Define the original default directory
        NSURL *originalFileURL = [[RLMRealmConfiguration defaultConfiguration].fileURL copy];

        // Ensure the new directory exists
        [[NSFileManager defaultManager] createDirectoryAtURL:appSupportURL withIntermediateDirectories:YES attributes:nil error:nil];

        // Check if the original database exists
        if ([[NSFileManager defaultManager] fileExistsAtPath:originalFileURL.path]) {
            Debug(@"Found existing default.realm at old location, copying to new location...");
            if (![[NSFileManager defaultManager] fileExistsAtPath:newFileURL.path]) {
                NSError *copyError = nil;
                [[NSFileManager defaultManager] copyItemAtURL:originalFileURL toURL:newFileURL error:&copyError];
                if (copyError) {
                    Debug(@"Error copying default.realm to new location: %@", copyError.localizedDescription);
                } else {
                    Debug(@"Successfully copied default.realm to new location.");
                    
                    // Delete original realm file and its auxiliary files
                    NSArray *auxiliaryExtensions = @[@"", @"lock", @"management"];
                    for (NSString *extension in auxiliaryExtensions) {
                        NSURL *fileURL = [[originalFileURL.URLByDeletingPathExtension URLByAppendingPathExtension:@"realm"] URLByAppendingPathExtension:extension];
                        NSError *removeError = nil;
                        if ([[NSFileManager defaultManager] fileExistsAtPath:fileURL.path]) {
                            if ([[NSFileManager defaultManager] removeItemAtURL:fileURL error:&removeError]) {
                                Debug(@"Successfully removed %@", fileURL.lastPathComponent);
                            } else {
                                Debug(@"Error removing %@: %@", fileURL.lastPathComponent, removeError.localizedDescription);
                            }
                        }
                    }
                }
            } else {
                Debug(@"default.realm already exists in the new location.");
            }
        } else {
            Debug(@"No existing default.realm found. A new database will be created at the new location.");
        }

        // Schema version 2: removed uploadedAsLivePhoto property
        config.schemaVersion = 2;
        config.migrationBlock = ^(RLMMigration *migration, uint64_t oldSchemaVersion) {
            if (oldSchemaVersion < 2) {
                Debug(@"Migrating Realm schema from version %llu to 2", oldSchemaVersion);
            }
        };

        // Update the configuration to use the new file URL
        config.fileURL = newFileURL;
        [RLMRealmConfiguration setDefaultConfiguration:config];
    }
    return self;
}

- (void)migrateCachedPhotosFromCoreDataWithIdentifier:(NSString *)identifier forAccount:(NSString *)account andStatus:(NSString *)status {
    Debug("Start to migrate photos from account: %@", account);
    [self updateCachePhotoWithIdentifier:identifier forAccount:account andStatus:status];
}

- (void)updateCachePhotoWithIdentifier:(NSString *)identifier forAccount:(NSString *)account andStatus:(NSString *)status {
    RLMRealm *realm = [RLMRealm defaultRealm];
    
    SeafCachePhoto *cachePhoto = [[SeafCachePhoto alloc] init];
    cachePhoto.identifier = identifier;
    cachePhoto.account = account;
    cachePhoto.status = status;
    
    [realm transactionWithBlock:^{
        [realm addOrUpdateObject:cachePhoto];
    }];
}

- (NSInteger)numOfCachedPhotosWithStatus:(NSString *)status forAccount:(NSString *)account {
    RLMResults<SeafCachePhoto *> *photos = [SeafCachePhoto objectsWhere:@"status == %@ AND account == %@", status, account];
    Debug("%ld photos whit %@ status in account: %@", photos.count, status, account);
    return photos.count;
}

- (NSInteger)numOfCachedPhotosWhithAccount:(NSString *)account {
    RLMResults<SeafCachePhoto *> *photos = [SeafCachePhoto objectsWhere:@"account == %@", account];
    Debug("%ld photos in account: %@", photos.count, account);
    return photos.count;
}

- (NSString *)getPhotoStatusWithIdentifier:(NSString *)identifier forAccount:(NSString *)account {
    RLMResults<SeafCachePhoto *> *photos = [SeafCachePhoto objectsWhere:@"identifier == %@ AND account == %@", identifier, account];
    
    if (photos.count > 0) {
        SeafCachePhoto *photo = photos.firstObject;
        return photo.status;
    } else {
        return nil;
    }
}

- (NSArray *)getNeedUploadPhotosWithAccount:(NSString *)account {
    RLMResults<SeafCachePhoto *> *photos = [SeafCachePhoto objectsWhere:@"account == %@ AND status == %@", account, @"false"];
    
    if (photos.count > 0) {
        NSMutableArray *array = [NSMutableArray array];
        for (SeafCachePhoto* photo in photos) {
            [array addObject:photo.identifier];
        }
        return array;
    } else {
        return nil;
    }
}

//remove uploaded Photo from Realm.
- (void)deletePhotoWithIdentifier:(NSString *)identifier forAccount:(NSString *)account {
    RLMResults<SeafCachePhoto *> *photos = [SeafCachePhoto objectsWhere:@"identifier == %@ AND account == %@", identifier, account];
    
    if (photos.count > 0) {
        RLMRealm *realm = [RLMRealm defaultRealm];
        
        [realm transactionWithBlock:^{
            [realm deleteObjects:photos];
        }];
    }
}

- (void)clearAllCachedPhotosInAccount:(NSString *)account {
    Debug(@"Clearing cached photos for account: %@", account);
    RLMResults<SeafCachePhoto *> *photos = [SeafCachePhoto objectsWhere:@"account == %@", account];
    
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        [realm deleteObjects:photos];
    }];
    Debug(@"Deleted %lu photos for account: %@", (unsigned long)photos.count, account);
}

- (void)clearAllCachedPhotos {
    Debug("clear SeafCachePhoto table");
    RLMResults<SeafCachePhoto *> *photos = [SeafCachePhoto allObjects];
    
    RLMRealm *realm = [RLMRealm defaultRealm];
    
    [realm transactionWithBlock:^{
        [realm deleteObjects:photos];
    }];
}

- (BOOL)isPhotoExistInRealm:(NSString *)identifier forAccount:(NSString *)account{
    RLMResults *results = [SeafCachePhoto objectsWhere:@"identifier == %@ AND account == %@", identifier, account];
    return results.count > 0;
}

//V2.9.27 delete the not uploaded photo in realm.
- (void)deletePhotoWithNotUploadedStatus {
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        RLMResults<SeafCachePhoto *> *objectsToDelete = [SeafCachePhoto objectsWhere:@"status == %@",@"false"];
        [realm deleteObjects:objectsToDelete];
    }];
}


#pragma mark - SeafFileStatus
// Get file status by path
- (SeafFileStatus *)getFileStatusWithPath:(NSString *)path {
    return [SeafFileStatus objectForPrimaryKey:path];
}

// Clear all file statuses
- (void)clearAllFileStatuses {
    RLMRealm *realm = [RLMRealm defaultRealm];
    RLMResults<SeafFileStatus *> *allFileStatuses = [SeafFileStatus allObjects];
    [realm transactionWithBlock:^{
        [realm deleteObjects:allFileStatuses];
    }];
}

// Get all file statuses
- (NSArray<SeafFileStatus *> *)getAllFileStatuses {
    RLMResults<SeafFileStatus *> *allFileStatuses = [SeafFileStatus allObjects];
    return allFileStatuses.count > 0 ? [allFileStatuses valueForKey:@"self"] : @[];
}

- (NSString *)getCachePathWithOid:(NSString *)oid
                            mtime:(float)mtime
                           uniKey:(NSString *)uniKey {
    // Query the SeafFileStatus table by uniKey
    if (!(uniKey && uniKey.length > 0)) {
        return nil;
    }

    SeafFileStatus *fileStatus = [SeafFileStatus objectForPrimaryKey:uniKey];
    if (!fileStatus) {
        return nil;
    }

    if (oid && oid.length > 0) {
        return [fileStatus.serverOID isEqualToString:oid] ? fileStatus.localFilePath : nil;
    }

    if (mtime > 0) {
        if (fileStatus.serverMTime == mtime || fileStatus.localMTime >= mtime) {
            return fileStatus.localFilePath;
        }
    }

    return nil;
}

- (NSString *)getOidForUniKey:(NSString *)uniKey serverMtime:(float)serverMtime{
    if (!uniKey || uniKey.length == 0) {
        Debug(@"Invalid uniqueKey: %@", uniKey);
        return nil;
    }

    NSString *oid = nil;

    SeafFileStatus *fileStatus = [SeafFileStatus objectForPrimaryKey:uniKey];
    if (fileStatus) {
        if (serverMtime == fileStatus.serverMTime || serverMtime <= fileStatus.localMTime) {
            oid = fileStatus.serverOID;
        } else {
            Debug(@"No record found for uniqueKey: %@", uniKey);
        }
    } else {
        Debug(@"No record found for uniqueKey: %@", uniKey);
    }

    return oid;
}

// Private method: Handle single file status update
- (void)handleFileStatusUpdate:(SeafFileStatus *)newStatus inRealm:(RLMRealm *)realm {
    if (!newStatus || newStatus.uniquePath.length == 0) {
        return;
    }
    
    // Query existing file status
    SeafFileStatus *existingStatus = [SeafFileStatus objectInRealm:realm forPrimaryKey:newStatus.uniquePath];
    
    if (!existingStatus) {
        // If not exists, add new status directly
        [realm addOrUpdateObject:newStatus];
        return;
    }
    
    // Check if update is needed
    if (newStatus.serverOID && newStatus.serverOID.length > 0 && ![newStatus.serverOID isEqualToString:existingStatus.serverOID]) {
        [realm addOrUpdateObject:newStatus];
    } else if (newStatus.serverMTime > 0) {
        if ((existingStatus.serverMTime > 0 && newStatus.serverMTime > existingStatus.serverMTime) ||
            (existingStatus.localMTime > 0 && newStatus.serverMTime > existingStatus.localMTime)) {
            [realm addOrUpdateObject:newStatus];
        } else {
            // Update existing status fields
            existingStatus.serverMTime = newStatus.serverMTime;
            
            if (newStatus.serverOID.length > 0 && ![newStatus.serverOID isEqualToString:existingStatus.serverOID]) {
                existingStatus.serverOID = newStatus.serverOID;
            }
            
            if (newStatus.localFilePath.length > 0 && newStatus.localFilePath != existingStatus.localFilePath) {
                existingStatus.localFilePath = newStatus.localFilePath;
            }
            
            if (newStatus.fileSize > 0 && newStatus.fileSize != existingStatus.fileSize) {
                existingStatus.fileSize = newStatus.fileSize;
            }
            
            if (newStatus.dirId.length > 0) {
                existingStatus.dirId = newStatus.dirId;
            }
            
            if (newStatus.dirPath.length > 0) {
                existingStatus.dirPath = newStatus.dirPath;
            }
            
            [realm addOrUpdateObject:existingStatus];
        }
    } else if (newStatus.localMTime > 0) {
        // Update local-related fields
        if (newStatus.serverOID.length > 0 && ![newStatus.serverOID isEqualToString:existingStatus.serverOID]) {
            existingStatus.serverOID = newStatus.serverOID;
        }
        
        if (newStatus.localFilePath.length > 0 && newStatus.localFilePath != existingStatus.localFilePath) {
            existingStatus.localFilePath = newStatus.localFilePath;
        }
        
        if (newStatus.localMTime > 0 && newStatus.localMTime != existingStatus.localMTime) {
            existingStatus.localMTime = newStatus.localMTime;
        }
        
        if (newStatus.fileSize > 0 && newStatus.fileSize != existingStatus.fileSize) {
            existingStatus.fileSize = newStatus.fileSize;
        }
        
        if (newStatus.dirId.length > 0) {
            existingStatus.dirId = newStatus.dirId;
        }
        
        if (newStatus.dirPath.length > 0) {
            existingStatus.dirPath = newStatus.dirPath;
        }
        
        [realm addOrUpdateObject:existingStatus];
    }
}

// Update single file status
- (void)updateFileStatus:(SeafFileStatus *)newStatus {
    if (!newStatus || newStatus.uniquePath.length == 0) {
        Debug(@"Invalid SeafFileStatus object or missing uniquePath.");
        return;
    }
    
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        [self handleFileStatusUpdate:newStatus inRealm:realm];
    }];
}

// Batch update file statuses
- (void)updateFileStatuses:(NSArray<SeafFileStatus *> *)statuses {
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        for (SeafFileStatus *newStatus in statuses) {
            [self handleFileStatusUpdate:newStatus inRealm:realm];
        }
    }];
}

- (void)deleteFileStatusesWithDirIdsNotIn:(NSSet *)dirIds forAccount:(NSString *)account {
    if (!dirIds || !account) {
        Debug(@"Invalid parameters: dirIds or account is nil");
        return;
    }
    
    RLMRealm *realm = [RLMRealm defaultRealm];
    RLMResults<SeafFileStatus *> *allFileStatuses = [SeafFileStatus objectsWhere:@"accountIdentifier == %@", account];
    
    NSMutableArray *statusesToDelete = [NSMutableArray array];
    for (SeafFileStatus *status in allFileStatuses) {
        if (status.dirId && ![dirIds containsObject:status.dirId]) {
            [statusesToDelete addObject:status];
        }
    }
    
    if (statusesToDelete.count > 0) {
        Debug(@"Cleaning up %lu orphaned file statuses for account %@", (unsigned long)statusesToDelete.count, account);
        [realm transactionWithBlock:^{
            [realm deleteObjects:statusesToDelete];
        }];
    }
}

@end
