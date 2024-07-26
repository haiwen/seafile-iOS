//
//  SeafRealmManager.h
//  Seafile
//
//  Created by three on 2023/12/16.
//

#import <Foundation/Foundation.h>
#import "SeafCachePhoto.h"

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

- (void)deletePhotoWithIdSets:(NSSet *)identifierSet forAccount:(NSString *)account;

- (void)clearAllCachedPhotosInAccount:(NSString *)account;

- ( RLMResults<SeafCachePhoto *> *)getRealmAllPhotos;

//- (void)clearAllCachedPhotos;

@end

NS_ASSUME_NONNULL_END
