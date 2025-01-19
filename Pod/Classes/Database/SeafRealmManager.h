//
//  SeafRealmManager.h
//  Seafile
//
//  Created by three on 2023/12/16.
//

#import <Foundation/Foundation.h>
#import "SeafFileStatus.h"

NS_ASSUME_NONNULL_BEGIN

@interface SeafRealmManager : NSObject

+ (instancetype)shared;

- (void)migrateCachedPhotosFromCoreDataWithIdentifier:(NSString *)identifier forAccount:(NSString *)account andStatus:(NSString *)status;

- (void)updateCachePhotoWithIdentifier:(NSString *)identifier forAccount:(NSString *)account andStatus:(NSString *)status;

- (NSInteger)numOfCachedPhotosWithStatus:(NSString *)status forAccount:(NSString *)account;

- (NSInteger)numOfCachedPhotosWhithAccount:(NSString *)account;

- (NSString *)getPhotoStatusWithIdentifier:(NSString *)identifier forAccount:(NSString *)account;

- (NSArray *)getNeedUploadPhotosWithAccount:(NSString *)account;

- (void)deletePhotoWithIdentifier:(NSString *)identifier forAccount:(NSString *)account;

- (void)clearAllCachedPhotosInAccount:(NSString *)account;

- (void)clearAllCachedPhotos;

// Check if a photo exists in the realm. added at 2024.7.30
- (BOOL)isPhotoExistInRealm:(NSString *)identifier forAccount:(NSString *)account;

//Used for version update after 2.9.27,delete the status "false" photo.Only record uploaded photos.
- (void)deletePhotoWithNotUploadedStatus;

//- (void)addOrUpdateFileStatus:(SeafFileStatus *)fileStatus;

// Get file status by path
- (SeafFileStatus *)getFileStatusWithPath:(NSString *)path;

// Clear all file statuses
- (void)clearAllFileStatuses;

// Get all file statuses
- (NSArray<SeafFileStatus *> *)getAllFileStatuses;

// Get cache path
- (NSString *)getCachePathWithOid:(NSString *)oid
                             mtime:(float)mtime
                            uniKey:(NSString *)uniKey;

- (void)updateFileStatus:(SeafFileStatus *)newStatus;

- (NSString *)getOidForUniKey:(NSString *)uniKey serverMtime:(float)serverMtime;

- (void)updateFileStatuses:(NSArray<SeafFileStatus *> *)statuses;

- (void)deleteFileStatusesWithDirIdsNotIn:(NSSet *)dirIds forAccount:(NSString *)account;

@end

NS_ASSUME_NONNULL_END
