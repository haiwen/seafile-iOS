//
//  SeafStorage.h
//  Pods
//
//  Created by Wei W on 4/8/17.
//
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/**
 * `SeafStorage` manages the local filesystem storage for cache and temporary files used by the Seafile client.
 */
@interface SeafStorage : NSObject

@property (readwrite) BOOL allowInvalidCert;/// Indicates whether the client allows invalid certificates. Used for SSL pinning.

/**
 * Registers the root path and metadata storage defaults used by `SeafStorage`.
 * @param path The root path where `SeafStorage` should save files.
 * @param storage The `NSUserDefaults` instance used for metadata storage.
 */
+ (void)registerRootPath:(NSString *)path metadataStorage:(NSUserDefaults *)storage;


+ (SeafStorage *)sharedObject;///shared singleton instance

// Fs cache
/// Returns the root path for storage.
- (NSString *)rootPath;
/// Returns the root URL for storage.
- (NSURL *)rootURL;

/// Returns the path to the temporary directory.
- (NSString *)tempDir;
/// Returns the path to the uploads directory.
- (NSString *)uploadsDir;
/// Returns the path to the avatars directory.
- (NSString *)avatarsDir;
/// Returns the path to the certificates directory.
- (NSString *)certsDir;
/// Returns the path to the edit directory.
- (NSString *)editDir;
/// Returns the path to the thumbnails directory.
- (NSString *)thumbsDir;
/// Returns the path to the objects directory.
- (NSString *)objectsDir;
/// Returns the path to the blocks directory.
- (NSString *)blocksDir;

/**
 * Returns the path for a specific document.
 * @param fileId The identifier for the document.
 * @return The path to the document.
 */
- (NSString *)documentPath:(NSString*)fileId;

/**
 * Returns the path for a specific block.
 * @param blkId The identifier for the block.
 * @return The path to the block.
 */
- (NSString *)blockPath:(NSString*)blkId;

/// Clears all cached data.
- (void)clearCache;

/**
 * Returns the total size of the cache directory.
 * @return The size of the cache in bytes.
 */
- (long long)cacheSize;

/**
 * Creates a unique directory under a specified directory.
 * @param dir The parent directory.
 * @return The path to the newly created unique directory.
 */
+ (NSString *)uniqueDirUnder:(NSString *)dir;

// Metadata storage
/**
 * Sets a value for the specified default name in the metadata storage.
 * @param value The value to store.
 * @param defaultName The key under which to store the value.
 */
- (void)setObject:(id)value forKey:(NSString *)defaultName;

/**
 * Returns the value associated with a specified key in the metadata storage.
 * @param defaultName The key associated with the value.
 * @return The value associated with the key.
 */
- (id)objectForKey:(NSString *)defaultName;

/**
 * Removes the value associated with a specified key in the metadata storage.
 * @param defaultName The key for which the value should be removed.
 */
- (void)removeObjectForKey:(NSString *)defaultName;

/**
 * Forces the synchronization of the metadata storage.
 * @return YES if the synchronization was successful, otherwise NO.
 */
- (BOOL)synchronize;


// Client certificate manager
/**
 * Returns all security identities.
 * @return A dictionary of all identities.
 */
- (NSDictionary *)getAllSecIdentities;

/**
 * Imports a client certificate into the application.
 * @param certificatePath The file path to the certificate.
 * @param keyPassword The password for the certificate, if any.
 * @return YES if the certificate was successfully imported, otherwise NO.
 */
- (BOOL)importCert:(NSString *)certificatePath password:(NSString *)keyPassword;

/**
 * Removes a client certificate from the application.
 * @param identity The identity to remove.
 * @param persistentRef A reference to the persistent identity.
 * @return YES if the certificate was successfully removed, otherwise NO.
 */
- (BOOL)removeIdentity:(SecIdentityRef)identity forPersistentRef:(CFDataRef)persistentRef;

/**
 * Presents a user interface for selecting a client certificate.
 * @param dict A dictionary of identities to choose from.
 * @param completeHandler A block called when an identity is selected or the selection is cancelled.
 * @param c The view controller from which to present the selection interface.
 */
- (void)chooseCertFrom:(NSDictionary *)dict handler:(void (^)(CFDataRef persistentRef, SecIdentityRef identity)) completeHandler from:(UIViewController *)c;

/**
 * Retrieves the URL credential for a specific key.
 * @param key The key for which to retrieve the credential.
 * @return The retrieved URL credential.
 */
- (NSURLCredential *)getCredentialForKey:(NSData *)key;

@end
