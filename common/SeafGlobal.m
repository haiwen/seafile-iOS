//
//  SeafGlobal.m
//  seafilePro
//
//  Created by Wang Wei on 11/9/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//
#import "SeafGlobal.h"
#import "SeafUploadFile.h"
#import "SeafDir.h"
#import "Utils.h"
#import "Debug.h"

#define GROUP_NAME @"group.com.seafile.seafilePro"

@interface SeafGlobal()
@property (retain) NSMutableArray *ufiles;
@property (retain) NSMutableArray *dfiles;
@property unsigned long downloadnum;
@property unsigned long uploadnum;
@property unsigned long failedNum;
@property NSUserDefaults *storage;

@property NSTimer *autoSyncTimer;

@end

@implementation SeafGlobal
@synthesize managedObjectContext = __managedObjectContext;
@synthesize managedObjectModel = __managedObjectModel;
@synthesize persistentStoreCoordinator = __persistentStoreCoordinator;

-(id)init
{
    if (self = [super init]) {
        _assetsLibrary = [[ALAssetsLibrary alloc] init];
        _ufiles = [[NSMutableArray alloc] init];
        _dfiles = [[NSMutableArray alloc] init];
        _conns = [[NSMutableArray alloc] init];
        _downloadnum = 0;
        _uploadnum = 0;
        _storage = [[NSUserDefaults alloc] initWithSuiteName:GROUP_NAME];
    }
    return self;
}

+ (SeafGlobal *)sharedObject
{
    static SeafGlobal *object = nil;
    if (!object) {
        object = [[SeafGlobal alloc] init];
    }
    return object;
}

- (NSURL *)applicationDocumentsDirectoryURL
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

- (NSString *)applicationDocumentsDirectory
{
    return [[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject] path];
}

- (NSString *)applicationTempDirectory
{
    return [[self applicationDocumentsDirectory] stringByAppendingPathComponent:@"temp"];
}


- (NSString *)documentPath:(NSString*)fileId
{
    return [[[self applicationDocumentsDirectory] stringByAppendingPathComponent:@"objects"] stringByAppendingPathComponent:fileId];
}

- (NSString *)blockPath:(NSString*)blkId
{
    return [[[self applicationDocumentsDirectory] stringByAppendingPathComponent:@"blocks"] stringByAppendingPathComponent:blkId];
}

- (void)migrateUserDefaults
{
    NSUserDefaults *oldDef = [NSUserDefaults standardUserDefaults];
    NSUserDefaults *newDef = [[NSUserDefaults alloc] initWithSuiteName:GROUP_NAME];
    NSArray *accounts = [self objectForKey:@"ACCOUNTS"];
    if (accounts) {
        for(NSString *key in oldDef.dictionaryRepresentation) {
            [newDef setObject:[oldDef objectForKey:key] forKey:key];
        }
        [newDef synchronize];
        [oldDef removeObjectForKey:@"ACCOUNTS"];
        [oldDef synchronize];
    }
}

- (void)migrate
{
    [self migrateUserDefaults];
}

- (void)saveAccounts
{
    NSMutableArray *accounts = [[NSMutableArray alloc] init];
    for (SeafConnection *connection in self.conns) {
        NSMutableDictionary *account = [[NSMutableDictionary alloc] init];
        [account setObject:connection.address forKey:@"url"];
        [account setObject:connection.username forKey:@"username"];
        [accounts addObject:account];
    }
    [self setObject:accounts forKey:@"ACCOUNTS"];
};

- (void)loadAccounts
{
    NSArray *accounts = [self objectForKey:@"ACCOUNTS"];
    Debug("accounts=%ld", accounts.count);
    Debug("accounts=%@", accounts);
    for (NSDictionary *account in accounts) {
        Debug("account=%@", account);
        SeafConnection *conn = [[SeafConnection alloc] initWithUrl:[account objectForKey:@"url"] username:[account objectForKey:@"username"]];
        Debug("conn.username=%@", conn.username);
        if (conn.username)
            [self.conns addObject:conn];
    }
    [self saveAccounts];
}

- (SeafConnection *)getConnection:(NSString *)url username:(NSString *)username
{
    SeafConnection *conn;
    if ([url hasSuffix:@"/"])
        url = [url substringToIndex:url.length-1];
    for (conn in self.conns) {
        if ([conn.address isEqual:url] && [conn.username isEqual:username])
            return conn;
    }
    return nil;
}

#pragma mark - Core Data stack

// Returns the managed object context for the application.
// If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
- (NSManagedObjectContext *)managedObjectContext
{
    if (__managedObjectContext != nil) {
        return __managedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        __managedObjectContext = [[NSManagedObjectContext alloc] init];
        [__managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
    return __managedObjectContext;
}

// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (__managedObjectModel != nil) {
        return __managedObjectModel;
    }
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"seafile" withExtension:@"momd"];
    __managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return __managedObjectModel;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (__persistentStoreCoordinator != nil) {
        return __persistentStoreCoordinator;
    }
    NSURL *storeURL = [[self applicationDocumentsDirectoryURL] URLByAppendingPathComponent:@"seafile_pro.sqlite"];
    
    NSError *error = nil;
    __persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    if (![__persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
        /*
         Replace this implementation with code to handle the error appropriately.
         
         abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
         
         Typical reasons for an error here include:
         * The persistent store is not accessible;
         * The schema for the persistent store is incompatible with current managed object model.
         Check the error message to determine what the actual problem was.
         
         
         If the persistent store is not accessible, there is typically something wrong with the file path. Often, a file URL is pointing into the application's resources directory instead of a writeable directory.
         
         If you encounter schema incompatibility errors during development, you can reduce their frequency by:
         * Simply deleting the existing store:
         [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil]
         
         * Performing automatic lightweight migration by passing the following dictionary as the options parameter:
         [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption, [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];
         
         Lightweight migration will only work for a limited set of schema changes; consult "Core Data Model Versioning and Data Migration Programming Guide" for details.
         
         */
        [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil];
        
        if (![__persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        }
    }
    
    return __persistentStoreCoordinator;
}

- (void)saveContext
{
    NSError *error = nil;
    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    if (managedObjectContext != nil) {
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
            // Replace this implementation with code to handle the error appropriately.
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        }
    }
}


- (void)deleteAllObjects:(NSString *)entityDescription
{
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:entityDescription inManagedObjectContext:__managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSError *error;
    NSArray *items = [__managedObjectContext executeFetchRequest:fetchRequest error:&error];
    
    for (NSManagedObject *managedObject in items) {
        [__managedObjectContext deleteObject:managedObject];
        Debug(@"%@ object deleted",entityDescription);
    }
    if (![__managedObjectContext save:&error]) {
        Debug(@"Error deleting %@ - error:%@",entityDescription,error);
    }
}

- (void)incDownloadnum
{
    @synchronized (self) {
        _downloadnum ++;
    }
}
- (void)decDownloadnum
{
    @synchronized (self) {
        _downloadnum --;
    }
}

- (void)incUploadnum
{
    @synchronized (self) {
        _uploadnum ++;
    }
}

- (unsigned long)uploadingnum
{
    return self.uploadnum + self.ufiles.count;
}

- (unsigned long)downloadingnum
{
    return self.downloadnum + self.dfiles.count;
}

- (void)finishDownload:(id<SeafDownloadDelegate>) file result:(BOOL)result
{
    Debug("download %ld, result=%d, failcnt=%ld", self.downloadnum, result, self.failedNum);
    @synchronized (self) {
        self.downloadnum --;
    }

    if (result) {
        self.failedNum = 0;
    } else {
        self.failedNum ++;
        [self.dfiles addObject:file];
        if (self.failedNum >= 3) {
            [self performSelector:@selector(tryDownload) withObject:nil afterDelay:10.0];
            self.failedNum = 2;
            return;
        }
    }
    [self performSelector:@selector(tick:) withObject:_autoSyncTimer afterDelay:0.1];
}

- (void)finishUpload:(SeafUploadFile *)file result:(BOOL)result
{
    Debug("upload %ld, result=%d, udir=%@", self.uploadnum, result, file.udir);
    @synchronized (self) {
        self.uploadnum --;
    }

    if (result) {
        self.failedNum = 0;
        if (file.autoSync) [file.udir->connection fileUploadedSuccess:file];
    } else {
        self.failedNum ++;
        [self.ufiles addObject:file];
        if (self.failedNum >= 3) {
            [self performSelector:@selector(tryUpload) withObject:nil afterDelay:10.0];
            self.failedNum = 2;
            return;
        }
    }
    [self performSelector:@selector(tick:) withObject:_autoSyncTimer afterDelay:0.1];
}

- (void)tryUpload
{
    Debug("tryUpload %ld %ld", (long)self.uploadnum, (long)self.ufiles.count);
    if (self.ufiles.count == 0) return;
    NSMutableArray *todo = [[NSMutableArray alloc] init];
    @synchronized (self) {
        NSMutableArray *arr = [self.ufiles mutableCopy];
        for (SeafUploadFile *file in arr) {
            if (self.uploadnum + todo.count + self.failedNum >= 3) break;
            [self.ufiles removeObject:file];
            if (!file.uploaded) {
                [todo addObject:file];
            }
        }
    }
    for (SeafUploadFile *file in todo) {
        if (file.udir) {
            [file doUpload];
        }
    }
}

- (void)tryDownload
{
    if (self.dfiles.count == 0) return;
    NSMutableArray *todo = [[NSMutableArray alloc] init];
    @synchronized (self) {
        NSMutableArray *arr = [self.dfiles mutableCopy];
        for (id<SeafDownloadDelegate> file in arr) {
            if (self.downloadnum + todo.count + self.failedNum >= 3) break;
            [self.dfiles removeObject:file];
            [todo addObject:file];
        }
    }
    for (id<SeafDownloadDelegate> file in todo) {
        [file download];
    }
}

- (void)removeBackgroundUpload:(SeafUploadFile *)file
{
    @synchronized (self) {
        [self.ufiles removeObject:file];
        
        if (file.udir)
            [file.udir removeUploadFile:file];
        else
            [file doRemove];
    }
}

- (void)backgroundUpload:(SeafUploadFile *)file
{
    @synchronized (self) {
        if (![_ufiles containsObject:file])
            [_ufiles addObject:file];
    }
    [self tryUpload];
}
- (void)backgroundDownload:(id<SeafDownloadDelegate>)file
{
    @synchronized (self) {
        if (![_dfiles containsObject:file])
            [_dfiles addObject:file];
    }
    [self tryDownload];
}

- (void)tick:(NSTimer *)timer
{
    if (![[AFNetworkReachabilityManager sharedManager] isReachable]) {
        return;
    }
    @synchronized(timer) {
        for (SeafConnection *conn in self.conns) {
            [conn pickPhotosForUpload];
        }
        if (self.uploadnum > 0)
            [self tryUpload];
        if (self.downloadnum > 0)
            [self tryDownload];
    }
}

- (void)startTimer
{
    _autoSyncTimer = [NSTimer scheduledTimerWithTimeInterval:5*60
                                                      target:self
                                                    selector:@selector(tick:)
                                                    userInfo:nil
                                                     repeats:YES];
    [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        [self tick:_autoSyncTimer];
    }];
}

- (void)setObject:(id)value forKey:(NSString *)defaultName
{
    [_storage setObject:value forKey:defaultName];
}

- (id)objectForKey:(NSString *)defaultName
{
    return [_storage objectForKey:defaultName];
}

- (void)removeObjectForKey:(NSString *)defaultName
{
    [_storage removeObjectForKey:defaultName];
}

- (BOOL)synchronize
{
    return [_storage synchronize];
}


- (void)setRepo:(NSString *)repoId password:(NSString *)password
{
    if (!password)
        return;
    NSMutableDictionary *repopasswds = [NSMutableDictionary dictionaryWithDictionary:(NSDictionary*)[self objectForKey:@"repopassword"]];
    [repopasswds setObject:password forKey:repoId];
    [self setObject:repopasswds forKey:@"repopassword"];
    [self synchronize];
}

- (NSString *)getRepoPassword:(NSString *)repoId
{
    NSDictionary *repopasswds = (NSDictionary*)[self objectForKey:@"repopassword"];
    return [repopasswds objectForKey:repoId];
}

- (void)clearRepoPasswords
{
    [self removeObjectForKey:@"repopassword"];
    [self synchronize];
}

- (void)assetForURL:(NSURL *)assetURL resultBlock:(ALAssetsLibraryAssetForURLResultBlock)resultBlock failureBlock:(ALAssetsLibraryAccessFailureBlock)failureBlock
{
    [self.assetsLibrary assetForURL:assetURL
                        resultBlock:^(ALAsset *asset) {
                            // Success #1
                            if (asset){
                                resultBlock(asset);
                                
                                // No luck, try another way
                            } else {
                                // Search in the Photo Stream Album
                                [self.assetsLibrary enumerateGroupsWithTypes:ALAssetsGroupPhotoStream
                                                                  usingBlock:^(ALAssetsGroup *group, BOOL *stop)
                                 {
                                     [group enumerateAssetsWithOptions:NSEnumerationReverse usingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
                                         if([result.defaultRepresentation.url isEqual:assetURL])
                                         {
                                             resultBlock(asset);
                                             *stop = YES;
                                         }
                                     }];
                                 }
                                                                failureBlock:^(NSError *error) {
                                                                    failureBlock(error);
                                                                }];
                            }
                            
                        } failureBlock:^(NSError *error) {
                            failureBlock(error);
                        }];
    
}

@end