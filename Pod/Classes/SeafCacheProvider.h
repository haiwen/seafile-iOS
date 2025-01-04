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
/**
 * @protocol SeafCacheProvider
 * @discussion Defines an interface for cache operations specific to Seafile entities within user accounts.
 */
@protocol SeafCacheProvider <NSObject>

/**
 * Retrieves the cached object for a given key within a specified entity and account.
 * @param key The key for which the object is stored.
 * @param entity The entity under which the object is stored.
 * @param account The user account.
 * @return The cached object as a string, or nil if not found.
 */
- (NSString *)objectForKey:(NSString *)key entityName:(NSString *)entity inAccount:(NSString *)account;

/**
 * Sets the value for a given key within a specified entity and account.
 * @param value The string to be cached.
 * @param key The key under which to store the value.
 * @param entity The entity under which to store the value.
 * @param account The user account.
 * @return A Boolean indicating whether the operation was successful.
 */
- (BOOL)setValue:(NSString *)value forKey:(NSString *)key entityName:(NSString *)entity inAccount:(NSString *)account;

/**
 * Removes a cached value for a given key within a specified entity and account.
 * @param key The key whose value is to be removed.
 * @param entity The entity under which the key is stored.
 * @param account The user account.
 */
- (void)removeKey:(NSString *)key entityName:(NSString *)entity inAccount:(NSString *)account;

/**
 * Returns the total number of cached items for a specified entity within an account.
 * @param entity The entity for which to count the items.
 * @param account The user account.
 * @return The number of items cached under the specified entity.
 */
- (long)totalCachedNumForEntity:(NSString *)entity inAccount:(NSString *)account;

/**
 * Clears all cache for a specified entity within an account.
 * @param entity The entity for which the cache will be cleared.
 * @param account The user account.
 */
- (void)clearCache:(NSString *)entity inAccount:(NSString *)account;

/**
 * Returns the number of times a specific value is cached for a specified key within an entity and account.
 * @param key The key for the value to count.
 * @param entity The entity under which the key is stored.
 * @param account The user account.
 * @return The number of times the value is cached.
 */
- (long)getCacheNumForValue:(NSString *)key entityName:(NSString *)entity inAccount:(NSString *)account;

/**
 * Returns the number of cached items that match a specific predicate within an entity.
 * @param pre The predicate to match against the cached items.
 * @param entity The entity under which to search.
 * @return The number of cached items that match the predicate.
 */
- (long)getCacheNumByPredicate:(NSPredicate *)pre entityName:(NSString *)entity;

/**
 * Updates the value for a given key only if the current value does not match a specified value.
 * @param value The new value to set if the condition is met.
 * @param defaultValue The value to compare against the current value.
 * @param key The key for which to update the value.
 * @param entity The entity under which the key is stored.
 * @param account The user account.
 * @return A Boolean indicating whether the update was successful.
 */
- (BOOL)updateValue:(NSString *)value whenIsNot:(NSString *)defaultValue forKey:(NSString *)key entityName:(NSString *)entity inAccount:(NSString *)account;

/**
 * Clears all caches across all entities within a specified account.
 * @param account The user account for which all caches will be cleared.
 */
- (void)clearAllCacheInAccount:(NSString *)account;


- (NSArray *)getAllValuesForEntity:(NSString *)entity inAccount:(NSString *)account;

@end

#endif /* SeafCacheProvider_h */
