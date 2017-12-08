//
//  SeafStorage.h
//  Pods
//
//  Created by Wei W on 4/8/17.
//
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface SeafStorage : NSObject

@property (readwrite) BOOL allowInvalidCert;

+ (void)registerRootPath:(NSString *)path metadataStorage:(NSUserDefaults *)storage;
+ (SeafStorage *)sharedObject;

// Fs cache
- (NSString *)rootPath;
- (NSURL *)rootURL;

- (NSString *)tempDir;
- (NSString *)uploadsDir;
- (NSString *)avatarsDir;
- (NSString *)certsDir;
- (NSString *)editDir;
- (NSString *)thumbsDir;
- (NSString *)objectsDir;
- (NSString *)blocksDir;

- (NSString *)documentPath:(NSString*)fileId;
- (NSString *)blockPath:(NSString*)blkId;

- (void)clearCache;

- (long long)cacheSize;

+ (NSString *)uniqueDirUnder:(NSString *)dir;

// Metadata storage
- (void)setObject:(id)value forKey:(NSString *)defaultName;
- (id)objectForKey:(NSString *)defaultName;
- (void)removeObjectForKey:(NSString *)defaultName;
- (BOOL)synchronize;


// Client certificate manager
- (NSDictionary *)getAllSecIdentities;
- (BOOL)importCert:(NSString *)certificatePath password:(NSString *)keyPassword;
- (BOOL)removeIdentity:(SecIdentityRef)identity forPersistentRef:(CFDataRef)persistentRef;
- (void)chooseCertFrom:(NSDictionary *)dict handler:(void (^)(CFDataRef persistentRef, SecIdentityRef identity)) completeHandler from:(UIViewController *)c;
- (NSURLCredential *)getCredentialForKey:(NSData *)key;

@end
