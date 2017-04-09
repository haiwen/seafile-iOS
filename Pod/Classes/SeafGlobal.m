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
        _ufiles = [[NSMutableArray alloc] init];
        _dfiles = [[NSMutableArray alloc] init];
        _uploadingfiles = [[NSMutableArray alloc] init];
        _conns = [[NSMutableArray alloc] init];
        _downloadnum = 0;
        _storage = [[NSUserDefaults alloc] initWithSuiteName:SEAFILE_SUITE_NAME];
        _saveAlbumSem = dispatch_semaphore_create(1);
         NSURL *rootURL = [[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:SEAFILE_SUITE_NAME] URLByAppendingPathComponent:@"seafile" isDirectory:true];
        [SeafStorage.sharedObject registerRootPath:rootURL.path];
        _cacheProvider = [[SeafDbCacheProvider alloc] init];
        [self checkSettings];

        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        _platformVersion = [infoDictionary objectForKey:@"DTPlatformVersion"];
        [_storage setObject:SEAFILE_VERSION forKey:@"VERSION"];
        [[AFNetworkReachabilityManager sharedManager] startMonitoring];
        [self loadSecIdentities];
        Debug("Cache root path=%@, clientVersion=%@, platformVersion=%@",  SeafStorage.sharedObject.rootPath, SEAFILE_VERSION, _platformVersion);
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
