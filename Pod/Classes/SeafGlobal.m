//
//  SeafGlobal.m
//  seafilePro
//
//  Created by Wang Wei on 11/9/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//
@import LocalAuthentication;

#import "SeafGlobal.h"
#import "SeafUploadFile.h"
#import "SeafAvatar.h"
#import "SeafDir.h"
#import "SeafRepos.h"
#import "Utils.h"
#import "Debug.h"
#import "SecurityUtilities.h"
#import "Version.h"
#import "SeafDbCacheProvider.h"

/*
static NSError * NewNSErrorFromException(NSException * exc) {
    NSMutableDictionary * info = [NSMutableDictionary dictionary];
    [info setValue:exc.name forKey:@"SeafExceptionName"];
    [info setValue:exc.reason forKey:@"SeafExceptionReason"];
    [info setValue:exc.callStackReturnAddresses forKey:@"SeafExceptionCallStackReturnAddresses"];
    [info setValue:exc.callStackSymbols forKey:@"SeafExceptionCallStackSymbols"];
    [info setValue:exc.userInfo forKey:@"SeafExceptionUserInfo"];

    return [[NSError alloc] initWithDomain:@"seafile" code:-1 userInfo:info];
}
*/

@interface SeafGlobal()
@property (retain) NSMutableArray *ufiles;
@property (retain) NSMutableArray *dfiles;
@property (retain) NSMutableArray *uploadingfiles;
@property unsigned long downloadnum;
@property unsigned long failedNum;
@property NSUserDefaults *storage;

@property NSTimer *autoSyncTimer;

@property NSMutableDictionary *secIdentities;

@end

@implementation SeafGlobal

@synthesize cacheProvider = _cacheProvider;

-(id)init
{
    if (self = [super init]) {
        _assetsLibrary = [[ALAssetsLibrary alloc] init];
        _ufiles = [[NSMutableArray alloc] init];
        _dfiles = [[NSMutableArray alloc] init];
        _uploadingfiles = [[NSMutableArray alloc] init];
        _conns = [[NSMutableArray alloc] init];
        _downloadnum = 0;
        _storage = [[NSUserDefaults alloc] initWithSuiteName:SEAFILE_SUITE_NAME];
        _saveAlbumSem = dispatch_semaphore_create(1);
         NSURL *rootURL = [[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:SEAFILE_SUITE_NAME] URLByAppendingPathComponent:@"seafile" isDirectory:true];
        [SeafFsCache.sharedObject registerRootPath:rootURL.path];
        _cacheProvider = [[SeafDbCacheProvider alloc] init];
        [self checkSettings];

        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        _platformVersion = [infoDictionary objectForKey:@"DTPlatformVersion"];
        [_storage setObject:SEAFILE_VERSION forKey:@"VERSION"];
        [[AFNetworkReachabilityManager sharedManager] startMonitoring];
        [self loadSecIdentities];
        Debug("Cache root path=%@, clientVersion=%@, platformVersion=%@",  SeafFsCache.sharedObject.rootPath, SEAFILE_VERSION, _platformVersion);
    }
    return self;
}

- (void)checkSettings
{
    NSUserDefaults * standardUserDefaults = [NSUserDefaults standardUserDefaults];
    id obj = [standardUserDefaults objectForKey:@"allow_invalid_cert"];
    if (!obj)
        [self registerDefaultsFromSettingsBundle];
}

- (void)loadSettings:(NSUserDefaults *)standardUserDefaults
{
    _allowInvalidCert = [standardUserDefaults boolForKey:@"allow_invalid_cert"];
}

- (void)defaultsChanged:(NSNotification *)notification
{
    NSUserDefaults *standardUserDefaults = (NSUserDefaults *)[notification object];
    [self loadSettings:standardUserDefaults];
}

+ (SeafGlobal *)sharedObject
{
    static SeafGlobal *object = nil;
    if (!object) {
        object = [[SeafGlobal alloc] init];

    }
    return object;
}

- (NSString *)fileProviderStorageDir
{
    return [[[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:SEAFILE_SUITE_NAME] path] stringByAppendingPathComponent:@"File Provider Storage"];
}

- (void)registerDefaultsFromSettingsBundle
{
    Debug("Registering default values from Settings.bundle");
    NSUserDefaults * defs = [NSUserDefaults standardUserDefaults];

    NSString *settingsBundle = [[NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"Seafile" ofType:@"bundle"]] pathForResource:@"Settings" ofType:@"bundle"];
    if(!settingsBundle) {
        Debug("Could not find Settings.bundle");
        return;
    }

    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:[settingsBundle stringByAppendingPathComponent:@"Root.plist"]];
    NSArray *preferences = [settings objectForKey:@"PreferenceSpecifiers"];
    NSMutableDictionary *defaultsToRegister = [[NSMutableDictionary alloc] initWithCapacity:[preferences count]];

    for (NSDictionary *prefSpecification in preferences) {
        NSString *key = [prefSpecification objectForKey:@"Key"];
        if (key) {
            // check if value readable in userDefaults
            id currentObject = [defs objectForKey:key];
            if (currentObject == nil) {
                // not readable: set value from Settings.bundle
                id objectToSet = [prefSpecification objectForKey:@"DefaultValue"];
                [defaultsToRegister setObject:objectToSet forKey:key];
                Debug("Setting object %@ for key %@", objectToSet, key);
            } else {
                // already readable: don't touch
                Debug("Key %@ is readable (value: %@), nothing written to defaults.", key, currentObject);
            }
        }
    }

    [defs registerDefaults:defaultsToRegister];
}

- (void)migrateUserDefaults
{
    NSUserDefaults *oldDef = [NSUserDefaults standardUserDefaults];
    NSUserDefaults *newDef = [[NSUserDefaults alloc] initWithSuiteName:SEAFILE_SUITE_NAME];
    NSArray *accounts = [oldDef objectForKey:@"ACCOUNTS"];
    if (accounts && accounts.count > 0) {
        for(NSString *key in oldDef.dictionaryRepresentation) {
            [newDef setObject:[oldDef objectForKey:key] forKey:key];
        }
        [newDef synchronize];
        [oldDef removeObjectForKey:@"ACCOUNTS"];
        [oldDef synchronize];
        Debug("accounts:%@\nnew:%@", oldDef.dictionaryRepresentation, newDef.dictionaryRepresentation);
    }
}
- (void)migrateDocuments
{
    NSURL *oldURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *newURL = [[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:SEAFILE_SUITE_NAME] URLByAppendingPathComponent:@"seafile" isDirectory:true];
    if ([Utils fileExistsAtPath:newURL.path])
        return;

    [Utils checkMakeDir:newURL.path];

    if (!newURL) return;

    NSFileManager* manager = [NSFileManager defaultManager];
    NSEnumerator *childFilesEnumerator = [[manager subpathsAtPath:oldURL.path] objectEnumerator];
    NSString* fileName;
    while ((fileName = [childFilesEnumerator nextObject]) != nil){
        NSError *error = nil;
        NSString* src = [oldURL.path stringByAppendingPathComponent:fileName];
        NSString* dest = [newURL.path stringByAppendingPathComponent:fileName];
        if ([Utils fileExistsAtPath:dest]) continue;
        [[NSFileManager defaultManager] moveItemAtPath:src toPath:dest error:&error];
        if (error) {
            Warning("migrate data error=%@", error);
        }
    }
}
- (void)migrate
{
    [self migrateUserDefaults];
    [self migrateDocuments];
}

- (BOOL)isCertInUse:(NSData *)clientIdentityKey
{
    for (SeafConnection *conn in self.conns) {
        if (conn.clientIdentityKey != nil && [clientIdentityKey isEqual:conn.clientIdentityKey])
            return true;
    }
    return false;
}

- (bool)saveAccounts
{
    NSMutableArray *accounts = [[NSMutableArray alloc] init];
    for (SeafConnection *connection in self.conns) {
        NSMutableDictionary *account = [[NSMutableDictionary alloc] init];
        [account setObject:connection.address forKey:@"url"];
        [account setObject:connection.username forKey:@"username"];
        [accounts addObject:account];
    }
    Debug("accounts:%@", accounts);
    [self setObject:accounts forKey:@"ACCOUNTS"];
    return true;
};

- (void)loadAccounts
{
    Debug("storage: %@", _storage.dictionaryRepresentation);
    NSUserDefaults * standardUserDefaults = [NSUserDefaults standardUserDefaults];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(defaultsChanged:)
                   name:NSUserDefaultsDidChangeNotification
                 object:standardUserDefaults];
    [self loadSettings:standardUserDefaults];
    Debug("allowInvalidCert=%d", _allowInvalidCert);

    NSMutableArray *connections = [[NSMutableArray alloc] init];
    NSArray *accounts = [self objectForKey:@"ACCOUNTS"];
    for (NSDictionary *account in accounts) {
        NSString *url = [account objectForKey:@"url"];
        NSString *username = [account objectForKey:@"username"];
        [_cacheProvider migrateUploadedPhotos:url username:username account:[NSString stringWithFormat:@"%@/%@", url, username]];
        SeafConnection *conn = [[SeafConnection alloc] initWithUrl:url cacheProvider:_cacheProvider username:username];
        if (conn.username)
            [connections addObject:conn];
    }
    self.conns = connections;
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

- (unsigned long)uploadingnum
{
    return self.uploadingfiles.count + self.ufiles.count;
}

- (unsigned long)downloadingnum
{
    return self.downloadnum + self.dfiles.count;
}

- (void)finishDownload:(id<SeafDownloadDelegate>)file result:(BOOL)result
{
    Debug("file %@ download %ld, result=%d, failcnt=%ld", file.name, self.downloadnum, result, self.failedNum);
    @synchronized (self) {
        self.downloadnum --;
    }

    if (result) {
        self.failedNum = 0;
    } else {
        self.failedNum ++;
        if ([file retryable])
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
    Debug("upload %ld, result=%d, file=%@, udir=%@", (long)self.uploadingfiles.count, result, file.lpath, file.udir.path);
    @synchronized (self) {
        [self.uploadingfiles removeObject:file];
    }

    if (result) {
        self.failedNum = 0;
    } else {
        self.failedNum ++;
        if (!file.removed) {
            [self.ufiles addObject:file];
        } else
            Debug("Upload file %@ removed.", file.name);
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
    Debug("tryUpload uploading:%ld left:%ld", (long)self.uploadingfiles.count, (long)self.ufiles.count);
    if (self.ufiles.count == 0) return;
    NSMutableArray *todo = [[NSMutableArray alloc] init];
    @synchronized (self) {
        NSMutableArray *arr = [self.ufiles mutableCopy];
        for (SeafUploadFile *file in arr) {
            if (self.uploadingfiles.count + todo.count + self.failedNum >= 3) break;
            Debug("ufile %@ canUpload:%d, uploaded:%d", file.lpath, file.canUpload, file.uploaded);
            if (!file.canUpload) continue;
            [self.ufiles removeObject:file];
            if (!file.uploaded) {
                [todo addObject:file];
            }
        }
    }
    double delayInMs = 400.0;
    int uploadingCount = self.uploadingfiles.count;
    for (int i = 0; i < todo.count; i++) {
        SeafUploadFile *file = [todo objectAtIndex:i];
        if (!file.udir) continue;

        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (i+uploadingCount) * delayInMs * NSEC_PER_MSEC);
        dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(void){
            [file doUpload];
        });

        @synchronized (self) {
            [self.uploadingfiles addObject:file];
        }
    }
}

- (void)tryDownload
{
    if (self.dfiles.count == 0) return;
    NSMutableArray *todo = [[NSMutableArray alloc] init];
    @synchronized (self.dfiles) {
        NSMutableArray *arr = [self.dfiles mutableCopy];
        for (id<SeafDownloadDelegate> file in arr) {
            if (self.downloadnum + todo.count + self.failedNum >= 2) break;
            [self.dfiles removeObject:file];
            [todo addObject:file];
        }
    }
    for (id<SeafDownloadDelegate> file in todo) {
        Debug("try download %@", file.name);
        [file download];
    }
}

- (void)removeBackgroundUpload:(SeafUploadFile *)file
{
    @synchronized (self) {
        [self.ufiles removeObject:file];
        [self.uploadingfiles removeObject:file];
    }
}

- (void)removeBackgroundDownload:(id<SeafDownloadDelegate>)file
{
    @synchronized (self.dfiles) {
        [self.dfiles removeObject:file];
    }
}

- (void)clearAutoSyncPhotos:(SeafConnection *)conn
{
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    @synchronized (self) {
        for (SeafUploadFile *ufile in _ufiles) {
            if (ufile.autoSync && ufile.udir->connection == conn) {
                [arr addObject:ufile];
            }
        }
        for (SeafUploadFile *ufile in _uploadingfiles) {
            if (ufile.autoSync && ufile.udir->connection == conn) {
                [arr addObject:ufile];
            }
        }
    }
    Debug("clear %ld photos", (long)arr.count);
    for (SeafUploadFile *ufile in arr) {
        [conn removeUploadfile:ufile];
    }
}

- (void)clearAutoSyncVideos:(SeafConnection *)conn
{
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    @synchronized (self) {
        for (SeafUploadFile *ufile in _ufiles) {
            if (ufile.autoSync && ufile.udir->connection == conn && !ufile.isImageFile) {
                [arr addObject:ufile];
            }
        }
        for (SeafUploadFile *ufile in _uploadingfiles) {
            if (ufile.autoSync && ufile.udir->connection == conn && !ufile.isImageFile) {
                [arr addObject:ufile];
            }
        }
    }
    for (SeafUploadFile *ufile in arr) {
        Debug("Remove autosync video file: %@, %@", ufile.lpath, ufile.assetURL);
        [conn removeUploadfile:ufile];
    }
}

- (void)addUploadTask:(SeafUploadFile *)file
{
    [file resetFailedAttempt];
    @synchronized (self) {
        if (![_ufiles containsObject:file] && ![_uploadingfiles containsObject:file])
            [_ufiles addObject:file];
        else
            Warning("upload task file %@ already exist", file.lpath);
    }
    [self performSelectorInBackground:@selector(tryUpload) withObject:file];
}
- (void)addDownloadTask:(id<SeafDownloadDelegate>)file
{
    @synchronized (self.dfiles) {
        if (![self.dfiles containsObject:file]) {
            [self.dfiles insertObject:file atIndex:0];
            Debug("Added download task %@: %ld", file.name, (unsigned long)self.dfiles.count);
        }
    }
    [self tryDownload];
}

- (void)tick:(NSTimer *)timer
{
#define UPDATE_INTERVAL 1800
    static double lastUpdate = 0;
    if (![[AFNetworkReachabilityManager sharedManager] isReachable]) {
        return;
    }
    @synchronized(timer) {
        double cur = [[NSDate date] timeIntervalSince1970];
        if (cur - lastUpdate > UPDATE_INTERVAL) {
            Debug("%fs has passed, refreshRepoPassowrds", cur - lastUpdate);
            lastUpdate = cur;
            for (SeafConnection *conn in self.conns) {
                [conn refreshRepoPassowrds];
                [conn photosDidChange:nil];
            }
        }
        if (self.ufiles.count > 0)
            [self tryUpload];
        if (self.dfiles.count > 0)
            [self tryDownload];
    }
}

- (void)startTimer
{
    Debug("Start timer.");
    [self tick:nil];
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
    if (!defaultName) return nil;
    return [_storage objectForKey:defaultName];
}

- (void)removeObjectForKey:(NSString *)defaultName
{
    [_storage removeObjectForKey:defaultName];
}

-(BOOL)synchronize
{
    return [_storage synchronize];
}

- (void)noException:(void (^)())block
{
    @try {
        block();
    }
    @catch (NSException *exception) {
        Warning("Failed to run block:%@", block);
    } @finally {
    }

}
- (void)assetForURL:(NSURL *)assetURL resultBlock:(ALAssetsLibraryAssetForURLResultBlock)resultBlock failureBlock:(ALAssetsLibraryAccessFailureBlock)failureBlock
{
    [self.assetsLibrary assetForURL:assetURL
                        resultBlock:^(ALAsset *asset) {
                            // Success #1
                            if (asset){
                                [self noException:^{
                                    resultBlock(asset);
                                }];
                                // No luck, try another way
                            } else {
                                // Search in the Photo Stream Album
                                [self.assetsLibrary enumerateGroupsWithTypes:ALAssetsGroupPhotoStream
                                                                  usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
                                    [group enumerateAssetsWithOptions:NSEnumerationReverse usingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
                                        if([result.defaultRepresentation.url isEqual:assetURL]) {
                                            [self noException:^{
                                                resultBlock(asset);
                                            }];
                                            *stop = YES;
                                        }
                                     }];
                                                                  }
                                                                failureBlock:^(NSError *error) {
                                                                    [self noException:^{
                                                                        failureBlock(error);
                                                                    }];
                                                                }];
                            }
                        } failureBlock:^(NSError *error) {
                            [self noException:^{
                                failureBlock(error);
                            }];
                        }];
}

- (UIImage *)imageFromPath:(NSString *)path withMaxSize:(float)length cachePath:(NSString *)cachePath
{
    const int MAX_SIZE = 2048;
    if ([[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
        return [UIImage imageWithContentsOfFile:cachePath];
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        if (image.size.width > MAX_SIZE || image.size.height > MAX_SIZE) {
            UIImage *img =  [Utils reSizeImage:image toSquare:MAX_SIZE];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND,0), ^{
                [UIImageJPEGRepresentation(img, 1.0) writeToFile:path atomically:YES];
            });
            return img;
        }
        return image;
    }
    return nil;
}

- (NSMutableDictionary *)getExports
{
    NSMutableDictionary *dict = [self objectForKey:@"EXPORTED"];
    if (!dict)
        return [NSMutableDictionary new];
    else
        return [[NSMutableDictionary alloc] initWithDictionary:dict];
}

- (void)saveExports:(NSDictionary *)dict
{
    [self setObject:dict forKey:@"EXPORTED"];
    [self synchronize];
}

- (NSString *)exportKeyFor:(NSURL *)url
{
    NSArray *components = url.pathComponents;
    NSUInteger length = components.count;
    return [NSString stringWithFormat:@"%@/%@", [components objectAtIndex:length-2], [components objectAtIndex:length-1]];
}

- (void)addExportFile:(NSURL *)url data:(NSDictionary *)dict
{
    NSMutableDictionary *exports = [self getExports];
    [exports setObject:dict forKey:[self exportKeyFor:url]];
    Debug("exports: %@", exports);
    [SeafGlobal.sharedObject saveExports:exports];
}

- (void)removeExportFile:(NSURL *)url
{
    NSMutableDictionary *exports = [self getExports];
    [exports removeObjectForKey:[self exportKeyFor:url]];
    Debug("exports: %@", exports);
    [SeafGlobal.sharedObject saveExports:exports];
}
- (NSDictionary *)getExportFile:(NSURL *)url
{
    NSMutableDictionary *exports = [self getExports];
    return [exports objectForKey:[self exportKeyFor:url]];
}

- (void)clearExportFiles
{
    [Utils clearAllFiles:self.fileProviderStorageDir];
    [SeafGlobal.sharedObject saveExports:[NSDictionary new]];
}

- (NSArray *)getSecPersistentRefs {
    NSArray *array = (NSArray *)[self objectForKey:@"SecPersistentRefs"];
    return array;
}

- (void)loadSecIdentities
{
    _secIdentities = [NSMutableDictionary new];
    NSArray *array = [self getSecPersistentRefs];
    if (array) {
        bool flag = false;
        for (NSData *data in array) {
            SecIdentityRef identity = [SecurityUtilities getSecIdentityForPersistentRef:(CFDataRef)data];
            if (identity != nil) {
                [_secIdentities setObject:(__bridge id)identity forKey:data];
            } else {
                Warning("Can not find the identity for %@", data);
                flag = true;
            }
        }
        if (flag)
            [self saveSecIdentities];
    }
}

- (void)saveSecIdentities
{
    NSArray *array = _secIdentities.allKeys;
    [self setObject:array forKey:@"SecPersistentRefs"];
}

- (NSDictionary *)getAllSecIdentities
{
    return _secIdentities;
}

- (BOOL)importCert:(NSString *)certificatePath password:(NSString *)keyPassword
{
    SecIdentityRef identity = [SecurityUtilities copyIdentityAndTrustWithCertFile:certificatePath password:keyPassword];
    if (!identity) {
        Warning("Wrong password");
        return false;
    }

    NSData *data = (__bridge NSData *)[SecurityUtilities saveSecIdentity:identity];
    if (data) {
        [_secIdentities setObject:(__bridge id)identity forKey:data];
        [self saveSecIdentities];
        return true;
    } else {
        Warning("Failed to save to keyChain");
        return false;
    }
}

- (BOOL)removeIdentity:(SecIdentityRef)identity forPersistentRef:(CFDataRef)persistentRef
{
    BOOL ret = [SecurityUtilities removeIdentity:identity forPersistentRef:persistentRef];
    Debug("Remove identity from keychain: %d", ret);
    if (ret) {
        [_secIdentities removeObjectForKey:(__bridge id)persistentRef];
    }
    return ret;
}

- (NSURLCredential *)getCredentialForKey:(NSData *)key
{
    SecIdentityRef identity = (__bridge SecIdentityRef)[_secIdentities objectForKey:key];
    if (identity) {
        return [SecurityUtilities getCredentialFromSecIdentity:identity];
    }
    return nil;
}

-(void)chooseCertFrom:(NSDictionary *)dict handler:(void (^)(CFDataRef persistentRef, SecIdentityRef identity)) completeHandler from:(UIViewController *)c
{
    NSString *title = NSLocalizedString(@"Select a certificate", @"Seafile");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    for(NSData *key in dict) {
        CFDataRef persistentRef = (__bridge CFDataRef)key;
        SecIdentityRef identity = (__bridge SecIdentityRef)dict[key];
        NSString *title = [SecurityUtilities nameForIdentity:identity];
        UIAlertAction *action = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            completeHandler(persistentRef, identity);
        }];
        [alert addAction:action];
    }

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:STR_CANCEL style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        completeHandler(nil, nil);
    }];
    [alert addAction:cancelAction];
    [c presentViewController:alert animated:YES completion:nil];
}

@end
