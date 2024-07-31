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
        [RLMRealmConfiguration setDefaultConfiguration:config];
    }
    return self;
}

- (void)migrateCachedPhotosFromCoreDataWithIdentifier:(NSString *)identifier forAccount:(NSString *)account andStatus:(NSString *)status {
    Debug("Start to migrate photos from account: %@", account);
    [self updateCachePhotoWithIdentifier:identifier forAccount:account andStatus:status];
}

- (void)savePhotoWithIdentifier:(NSString *)identifier forAccount:(NSString *)account andStatus:(NSString *)status {
    RLMResults<SeafCachePhoto *> *photos = [SeafCachePhoto objectsWhere:@"identifier == %@ AND account == %@", identifier, account];
    if (photos.count > 0) {
        RLMRealm *realm = [RLMRealm defaultRealm];
        SeafCachePhoto *photo = photos.firstObject;
        
        if (![photo.status isEqualToString:@"true"]) {
            [realm transactionWithBlock:^{
                photo.status = status;
                [realm addOrUpdateObject:photo];
            }];
        }
    } else {
        [self updateCachePhotoWithIdentifier:identifier forAccount:account andStatus:status];
    }
}

- (void)updateCachePhotoWithIdentifier:(NSString *)identifier forAccount:(NSString *)account andStatus:(NSString *)status {
    Debug("Add or update photo: %@, status: %@, account: %@", identifier, status, account);
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
    Debug("clear photos in account: %@", account);
    RLMResults<SeafCachePhoto *> *photos = [SeafCachePhoto objectsWhere:@"account == %@", account];
    
    RLMRealm *realm = [RLMRealm defaultRealm];
    
    [realm transactionWithBlock:^{
        [realm deleteObjects:photos];
    }];
}

- (void)clearAllCachedPhotos {
    Debug("clear SeafCachePhoto table");
    RLMResults<SeafCachePhoto *> *photos = [SeafCachePhoto allObjects];
    
    RLMRealm *realm = [RLMRealm defaultRealm];
    
    [realm transactionWithBlock:^{
        [realm deleteObjects:photos];
    }];
}

// Check if a photo exists in the realm. added at 2024.7.30
- (BOOL)isPhotoExistInRealm:(NSString *)identifier forAccount:(NSString *)account{
    return [SeafCachePhoto objectsWhere:@"identifier == %@ AND account == %@", identifier, account].count > 0;
}

//V2.9.27 delete the not uploaded photo in realm.
- (void)deletePhotoWithNotUploadedStatus {
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        RLMResults<SeafCachePhoto *> *objectsToDelete = [SeafCachePhoto objectsWhere:@"status == %@",@"false"];
        [realm deleteObjects:objectsToDelete];
    }];
}

@end
