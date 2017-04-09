//
//  SeafCacheProvider.h
//  Pods
//
//  Created by Wei W on 4/8/17.
//
//

#ifndef SeafCacheProvider_h
#define SeafCacheProvider_h

#define ENTITY_DIRECTORY @"DirectoryV2"
#define ENTITY_FILE @"ModifiedFileV2"
#define ENTITY_UPLOAD_PHOTO @"UploadedPhotoV2"
#define ENTITY_OBJECT @"SeafCacheObjV2"

@protocol SeafCacheProvider <NSObject>

- (NSString *)objectForKey:(NSString *)key entityName:(NSString *)entity inAccount:(NSString *)account;
- (BOOL)setValue:(NSString *)value forKey:(NSString *)key entityName:(NSString *)entity inAccount:(NSString *)account;
- (void)removeKey:(NSString *)key entityName:(NSString *)entity inAccount:(NSString *)account;
- (long)totalCachedNumForEntity:(NSString *)entity inAccount:(NSString *)account;
- (void)clearCache:(NSString *)entity inAccount:(NSString *)account;

- (void)clearAllCacheInAccount:(NSString *)account;

@end

#endif /* SeafCacheProvider_h */
