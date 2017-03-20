//
//  SeafGlobal.h
//  seafilePro
//
//  Created by Wang Wei on 11/9/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//


#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "SeafConnection.h"
#import "SeafPreView.h"
#import "SeafFsCache.h"


#define SEAFILE_SUITE_NAME @"group.com.seafile.seafilePro"
#define APP_ID @"com.seafile.seafilePro"

#define THUMB_SIZE 96

@interface SeafGlobal : NSObject

@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;

@property (readonly) ALAssetsLibrary *assetsLibrary;

@property (readonly) BOOL allowInvalidCert;

@property (retain) NSMutableArray *conns;
@property (readwrite) SeafConnection *connection;
@property (readonly) NSString *platformVersion;
@property (readonly) dispatch_semaphore_t saveAlbumSem;
@property (readwrite) BOOL isAppExtension;

+ (SeafGlobal *)sharedObject;

- (NSString *)documentStorageDir;


- (void)loadSettings:(NSUserDefaults *)standardUserDefaults;

- (BOOL)isCertInUse:(NSData*)clientIdentityKey;
- (void)loadAccounts;
- (bool)saveAccounts;
- (SeafConnection *)getConnection:(NSString *)url username:(NSString *)username;

- (void)startTimer;

- (void)saveContext;
- (void)deleteAllObjects: (NSString *)entityDescription;

- (void)incDownloadnum;
- (void)decDownloadnum;
- (unsigned long)uploadingnum;
- (unsigned long)downloadingnum;

- (void)finishDownload:(id<SeafDownloadDelegate>)file result:(BOOL)result;
- (void)finishUpload:(SeafUploadFile *)file result:(BOOL)result;

- (void)addUploadTask:(SeafUploadFile *)file;
- (void)addDownloadTask:(id<SeafDownloadDelegate>)file;
- (void)removeBackgroundUpload:(SeafUploadFile *)file;
- (void)removeBackgroundDownload:(id<SeafDownloadDelegate>)file;
- (void)clearAutoSyncPhotos:(SeafConnection *)conn;
- (void)clearAutoSyncVideos:(SeafConnection *)conn;

- (void)setObject:(id)value forKey:(NSString *)defaultName;
- (id)objectForKey:(NSString *)defaultName;
- (void)removeObjectForKey:(NSString *)defaultName;
- (BOOL)synchronize;

- (void)migrate;
- (void)assetForURL:(NSURL *)assetURL resultBlock:(ALAssetsLibraryAssetForURLResultBlock)resultBlock failureBlock:(ALAssetsLibraryAccessFailureBlock)failureBlock;

- (UIImage *)imageFromPath:(NSString *)path withMaxSize:(float)length cachePath:(NSString *)cachePath;

- (void)addExportFile:(NSURL *)url data:(NSDictionary *)dict;
- (void)removeExportFile:(NSURL *)url;
- (NSDictionary *)getExportFile:(NSURL *)url;
- (void)clearExportFiles;

- (void)clearCache;

- (NSDictionary *)getAllSecIdentities;
- (BOOL)importCert:(NSString *)certificatePath password:(NSString *)keyPassword;
- (BOOL)removeIdentity:(SecIdentityRef)identity forPersistentRef:(CFDataRef)persistentRef;
- (void)chooseCertFrom:(NSDictionary *)dict handler:(void (^)(CFDataRef persistentRef, SecIdentityRef identity)) completeHandler from:(UIViewController *)c;
- (NSURLCredential *)getCredentialForKey:(NSData *)key;

@end

