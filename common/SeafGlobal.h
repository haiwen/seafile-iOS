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

#define OBJECTS_DIR @"objects"
#define AVATARS_DIR @"avatars"
#define CERTS_DIR @"certs"
#define BLOCKS_DIR @"blocks"
#define UPLOADS_DIR @"uploads"
#define EDIT_DIR @"edit"
#define THUMB_DIR @"thumb"
#define TEMP_DIR @"temp"

#define THUMB_SIZE 32

@interface SeafGlobal : NSObject

@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;

@property (readonly) ALAssetsLibrary *assetsLibrary;

@property (readonly) BOOL allowInvalidCert;

@property (retain) NSMutableArray *conns;
@property (readwrite) SeafConnection *connection;


+ (SeafGlobal *)sharedObject;

- (NSString *)applicationDocumentsDirectory;
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

- (void)loadSettings:(NSUserDefaults *)standardUserDefaults;

- (void)loadAccounts;
- (void)saveAccounts;
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

- (void)setRepo:(NSString *)repoId password:(NSString *)password;
- (NSString *)getRepoPassword:(NSString *)repoId;
- (void)clearRepoPasswords;

- (void)migrate;
- (void)assetForURL:(NSURL *)assetURL resultBlock:(ALAssetsLibraryAssetForURLResultBlock)resultBlock failureBlock:(ALAssetsLibraryAccessFailureBlock)failureBlock;

- (NSComparisonResult)compare:(id<SeafPreView>)item with:(id<SeafPreView>)other;

@end

