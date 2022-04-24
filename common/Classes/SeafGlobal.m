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
#import "SeafStorage.h"


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

@property NSTimer *autoSyncTimer;

@end

@implementation SeafGlobal

@synthesize cacheProvider = _cacheProvider;

-(id)init
{
    if (self = [super init]) {
        _conns = [[NSMutableArray alloc] init];
        _saveAlbumSem = dispatch_semaphore_create(1);
//         NSURL *rootURL = [[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:SEAFILE_SUITE_NAME] URLByAppendingPathComponent:@"seafile" isDirectory:true];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *rootURL = [[fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil] URLByAppendingPathComponent:@"seafile" isDirectory:true];
        [SeafStorage registerRootPath:rootURL.path metadataStorage:[[NSUserDefaults alloc] initWithSuiteName:SEAFILE_SUITE_NAME]];

        _cacheProvider = [[SeafDbCacheProvider alloc] init];
        [self checkSystemSettings];

        [SeafStorage.sharedObject setObject:SEAFILE_VERSION forKey:@"VERSION"];
        [[AFNetworkReachabilityManager sharedManager] startMonitoring];
        [SeafStorage.sharedObject removeObjectForKey:@"EXPORTED"];
        Debug("Cache root path=%@, clientVersion=%@",  SeafStorage.sharedObject.rootPath, SEAFILE_VERSION);
    }
    return self;
}

- (void)checkSystemSettings
{
    NSUserDefaults * standardUserDefaults = [NSUserDefaults standardUserDefaults];
    id obj = [standardUserDefaults objectForKey:@"allow_invalid_cert"];
    if (!obj) {
        [self registerDefaultsFromSettingsBundle];
    }
}

- (void)loadSystemSettings:(NSUserDefaults *)standardUserDefaults
{
    SeafStorage.sharedObject.allowInvalidCert = [standardUserDefaults boolForKey:@"allow_invalid_cert"];
}

- (void)defaultsChanged:(NSNotification *)notification
{
    NSUserDefaults *standardUserDefaults = (NSUserDefaults *)[notification object];
    [self loadSystemSettings:standardUserDefaults];
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
        Debug("Start migrate: %@", accounts);
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

- (BOOL)saveAccounts
{
    NSMutableArray *accounts = [[NSMutableArray alloc] init];
    for (SeafConnection *connection in self.conns) {
        NSMutableDictionary *account = [[NSMutableDictionary alloc] init];
        [account setObject:connection.address forKey:@"url"];
        [account setObject:connection.username forKey:@"username"];
        [accounts addObject:account];
    }
    Debug("accounts:%@", accounts);
    [SeafStorage.sharedObject setObject:accounts forKey:@"ACCOUNTS"];
    return true;
};

- (void)loadAccounts
{
    NSUserDefaults * standardUserDefaults = [NSUserDefaults standardUserDefaults];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(defaultsChanged:)
                   name:NSUserDefaultsDidChangeNotification
                 object:standardUserDefaults];
    [self loadSystemSettings:standardUserDefaults];
    Debug("allowInvalidCert=%d", SeafStorage.sharedObject.allowInvalidCert);

    NSMutableArray *connections = [[NSMutableArray alloc] init];
    NSArray *accounts = [SeafStorage.sharedObject objectForKey:@"ACCOUNTS"];
    for (NSDictionary *account in accounts) {
        NSString *url = [account objectForKey:@"url"];
        NSString *username = [account objectForKey:@"username"];
        [_cacheProvider migrateUploadedPhotos:url username:username account:[NSString stringWithFormat:@"%@/%@", url, username]];
        SeafConnection *conn = [[SeafConnection alloc] initWithUrl:url cacheProvider:_cacheProvider username:username];
        if (conn.username)
            [connections addObject:conn];
    }
    _conns = connections;
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

- (BOOL)saveConnection:(SeafConnection *)conn
{
    NSString *address = conn.address;
    if ([address hasSuffix:@"/"]) {
        address = [address substringToIndex:address.length-1];
    }
    BOOL existed = false;
    for (int i = 0; i < self.conns.count; ++i) {
        SeafConnection *c = self.conns[i];
        if ([c.address isEqual:address] && [conn.username isEqual:c.username]) {
            self.conns[i] = conn;
            existed = true;
            break;
        }
    }
    if (!existed) [self.conns addObject: conn];
    return [self saveAccounts];
}

- (BOOL)removeConnection:(SeafConnection *)conn
{
    [self.conns removeObject:conn];
    return [self saveAccounts];
}

- (NSArray *)publicAccounts {
    return self.conns;
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
                [conn refreshRepoPasswords];
                [conn photosDidChange:nil];
            }
        }
    }
}

- (void)startTimer
{
    Debug("Start timer.");
    [self tick:nil];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        self->_autoSyncTimer = [NSTimer scheduledTimerWithTimeInterval:15*30
                                                          target:self
                                                        selector:@selector(tick:)
                                                        userInfo:nil
                                                         repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:self->_autoSyncTimer forMode:NSRunLoopCommonModes];
        //use this method to ensure that the timer working
        [[NSRunLoop currentRunLoop] run];
    });
    [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        [self tick:self->_autoSyncTimer];
    }];
}


- (void)enterBackground
{
    
}
- (void)enterForeground
{
    [SeafGlobal.sharedObject loadSystemSettings:[NSUserDefaults standardUserDefaults]];
}

@end
