//
//  SeafRealmManager.h
//  Seafile
//
//  Created by three on 2023/12/16.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafRealmManager : NSObject

+ (instancetype)shared;

- (void)migrateCachedPhotosFromCoreDataWithIdentifier:(NSString *)identifier forAccount:(NSString *)account andStatus:(NSString *)status;

- (void)savePhotoWithIdentifier:(NSString *)identifier forAccount:(NSString *)account andStatus:(NSString *)status;

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

@end

NS_ASSUME_NONNULL_END
