//
//  SeafStorage.m
//  Pods
//
//  Created by Wei W on 4/8/17.
//
//

#import "SeafStorage.h"
#import "SecurityUtilities.h"
#import "Utils.h"
#import "Debug.h"


#define OBJECTS_DIR @"objects"
#define AVATARS_DIR @"avatars"
#define CERTS_DIR @"certs"
#define BLOCKS_DIR @"blocks"
#define UPLOADS_DIR @"uploads"
#define EDIT_DIR @"edit"
#define THUMB_DIR @"thumb"
#define TEMP_DIR @"temp"

static SeafStorage *object = nil;

@interface SeafStorage()
@property NSUserDefaults *storage;

@property (retain) NSString * cacheRootPath;

@property NSMutableDictionary *secIdentities;

@end

@implementation SeafStorage

+ (void)registerRootPath:(NSString *)path metadataStorage:(NSUserDefaults *)storage
{
    object = [[SeafStorage alloc] initWithRootPath:path metadataStorage:storage];
}

+ (SeafStorage *)sharedObject
{
    if (!object) {
        object = [[SeafStorage alloc] init];
    }
    return object;
}

- (void)registerMetadataStorage:(NSUserDefaults *)storage
{
    _storage = storage;
    Debug("storage: %@", _storage.dictionaryRepresentation);
}

-(id)initWithRootPath:(NSString *)path metadataStorage:(NSUserDefaults *)storage
{
    if (self = [super init]) {
        [self registerRootPath:path];
        _storage = storage;
        Debug("Storage: %@", storage.dictionaryRepresentation);
        [self loadSecIdentities];
    }
    return self;
}

-(id)init
{
    if (self = [super init]) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        [self registerRootPath:[paths objectAtIndex:0]];
        _storage = [[NSUserDefaults alloc] init];
        [self loadSecIdentities];
    }
    return self;
}

- (void)registerRootPath:(NSString *)path
{
    _cacheRootPath = path;
    [Utils checkMakeDir:self.objectsDir];
    [Utils checkMakeDir:self.avatarsDir];
    [Utils checkMakeDir:self.certsDir];
    [Utils checkMakeDir:self.blocksDir];
    [Utils checkMakeDir:self.uploadsDir];
    [Utils checkMakeDir:self.editDir];
    [Utils checkMakeDir:self.thumbsDir];
    [Utils checkMakeDir:self.tempDir];
}

- (NSURL *)rootURL
{
    return [NSURL fileURLWithPath:_cacheRootPath];
}

- (NSString *)rootPath
{
    return _cacheRootPath;
}

- (NSString *)uploadsDir
{
    return [self.rootPath stringByAppendingPathComponent:UPLOADS_DIR];
}

- (NSString *)avatarsDir
{
    return [self.rootPath stringByAppendingPathComponent:AVATARS_DIR];
}
- (NSString *)certsDir
{
    return [self.rootPath stringByAppendingPathComponent:CERTS_DIR];
}
- (NSString *)editDir
{
    return [self.rootPath stringByAppendingPathComponent:EDIT_DIR];
}
- (NSString *)thumbsDir
{
    return [self.rootPath stringByAppendingPathComponent:THUMB_DIR];
}
- (NSString *)objectsDir
{
    return [self.rootPath stringByAppendingPathComponent:OBJECTS_DIR];
}

- (NSString *)blocksDir
{
    return [self.rootPath stringByAppendingPathComponent:BLOCKS_DIR];
}
- (NSString *)tempDir
{
    return [[self rootPath] stringByAppendingPathComponent:TEMP_DIR];
}

- (NSString *)documentPath:(NSString*)fileId
{
    return [self.objectsDir stringByAppendingPathComponent:fileId];
}

- (NSString *)blockPath:(NSString*)blkId
{
    return [self.blocksDir stringByAppendingPathComponent:blkId];
}

- (long long)cacheSize
{
    return [Utils folderSizeAtPath:self.rootPath];
}

- (void)clearCache
{
    Debug("clear local cache.");
    [Utils clearAllFiles:self.objectsDir];
    [Utils clearAllFiles:self.blocksDir];
    [Utils clearAllFiles:self.editDir];
    [Utils clearAllFiles:self.thumbsDir];
    [Utils clearAllFiles:self.tempDir];
}

+ (NSString *)uniqueDirUnder:(NSString *)dir identify:(NSString *)identify
{
    return [dir stringByAppendingPathComponent:identify];
}

+ (NSString *)uniqueDirUnder:(NSString *)dir
{
    return [SeafStorage uniqueDirUnder:dir identify:[[NSUUID UUID] UUIDString]];
}

- (NSString *)uniqueUploadDir
{
    return [SeafStorage uniqueDirUnder:self.uploadsDir];
}

- (void)setObject:(id)value forKey:(NSString *)defaultName
{
    [_storage setObject:value forKey:defaultName];
}

- (id)objectForKey:(NSString *)key
{
    if (!key) return nil;
    return [_storage objectForKey:key];
}

- (void)removeObjectForKey:(NSString *)defaultName
{
    [_storage removeObjectForKey:defaultName];
}

-(BOOL)synchronize
{
    return [_storage synchronize];
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

- (NSURLCredential *)getCredentialForKey:(NSData *)key
{
    SecIdentityRef identity = (__bridge SecIdentityRef)[_secIdentities objectForKey:key];
    if (identity) {
        return [SecurityUtilities getCredentialFromSecIdentity:identity];
    }
    return nil;
}

@end
