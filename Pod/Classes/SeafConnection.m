//
//  SeafConnection.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//
@import Contacts;

#import <AssertMacros.h>

#import "SeafConnection.h"
#import "SeafRepos.h"
#import "SeafDir.h"
#import "SeafAvatar.h"
#import "SeafUploadFile.h"
#import "SeafFile.h"
#import "SeafStorage.h"
#import "SeafDataTaskManager.h"

#import "ExtentedString.h"
#import "NSData+Encryption.h"
#import "Debug.h"
#import "Utils.h"
#import "Version.h"

enum {
    FLAG_LOCAL_DECRYPT = 0x1,
};

#define CAMERA_UPLOADS_DIR @"Camera Uploads"
#define CONTACTS_UPLOADS_DIR @"Contacts Backup"

#define KEY_STARREDFILES @"STARREDFILES"
#define KEY_CONTACTS @"CONTACTS"
#define TAGDATA @"TagData"

static SecTrustRef AFUTTrustWithCertificate(SecCertificateRef certificate) {
    NSArray *certs  = [NSArray arrayWithObject:(__bridge id)(certificate)];

    SecPolicyRef policy = SecPolicyCreateBasicX509();
    SecTrustRef trust = NULL;
    SecTrustCreateWithCertificates((__bridge CFTypeRef)(certs), policy, &trust);
    CFRelease(policy);

    return trust;
}

static NSArray * AFCertificateTrustChainForServerTrust(SecTrustRef serverTrust) {
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];

    for (CFIndex i = 0; i < certificateCount; i++) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);
        [trustChain addObject:(__bridge_transfer NSData *)SecCertificateCopyData(certificate)];
    }

    return [NSArray arrayWithArray:trustChain];
}

static AFSecurityPolicy *SeafPolicyFromCert(SecCertificateRef cert)
{
    AFSecurityPolicy *policy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModePublicKey];
    policy.allowInvalidCertificates = YES;
    SecTrustRef clientTrust = AFUTTrustWithCertificate(cert);
    NSArray * certificates = AFCertificateTrustChainForServerTrust(clientTrust);
    [policy setPinnedCertificates:certificates];
    return policy;
}
static AFSecurityPolicy *SeafPolicyFromFile(NSString *path)
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        Debug("cert file %@ not exist", path);
        return nil;
    } else
        Debug("Load cert file from %@", path);
    NSData *certData = [NSData dataWithContentsOfFile:path];
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)(certData));
    return SeafPolicyFromCert(cert);
}

BOOL SeafServerTrustIsValid(SecTrustRef serverTrust) {
    BOOL isValid = NO;
    SecTrustResultType result;
    __Require_noErr_Quiet(SecTrustEvaluate(serverTrust, &result), _out);

    isValid = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);

_out:
    return isValid;
}

static AFHTTPRequestSerializer <AFURLRequestSerialization> * _requestSerializer;
@interface SeafConnection ()

@property NSMutableSet *starredFiles;
@property AFSecurityPolicy *policy;
@property NSDate *avatarLastUpdate;
@property NSMutableDictionary *settings;

@property BOOL inCheckPhotoss;
@property BOOL inCheckCert;

@property NSMutableArray *photosArray;
@property NSMutableArray *uploadingArray;
@property SeafDir *syncDir;
@property (readonly) NSString *localUploadDir;
@property NSString *contactsLastBackTime;
@property (readonly) BOOL inContactsSync;
@property (readonly) id<SeafCacheProvider> cacheProvider;

@property (readonly) NSString *platformVersion;
@property (readonly) NSString *tagDataKey;

@property (readwrite, nonatomic, getter=isFirstTimeSync) BOOL firstTimeSync;

@end

@implementation SeafConnection
@synthesize address = _address;
@synthesize info = _info;
@synthesize token = _token;
@synthesize loginDelegate = _loginDelegate;
@synthesize rootFolder = _rootFolder;
@synthesize starredFiles = _starredFiles;
@synthesize policy = _policy;
@synthesize loginMgr = _loginMgr;
@synthesize localUploadDir = _localUploadDir;
@synthesize platformVersion = _platformVersion;
@synthesize accountIdentifier = _accountIdentifier;
@synthesize tagDataKey = _tagDataKey;

- (id)initWithUrl:(NSString *)url cacheProvider:(id<SeafCacheProvider>)cacheProvider
{
    if (self = [super init]) {
        self.address = url;
        _rootFolder = [[SeafRepos alloc] initWithConnection:self];
        _info = [[NSMutableDictionary alloc] init];
        _avatarLastUpdate = [NSDate dateWithTimeIntervalSince1970:0];
        _syncDir = nil;
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        //configuration.TLSMaximumSupportedProtocol = kTLSProtocol12;
        configuration.TLSMinimumSupportedProtocol = kTLSProtocol1;
        _sessionMgr = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:configuration];
        _sessionMgr.responseSerializer = [AFJSONResponseSerializer serializerWithReadingOptions:NSJSONReadingAllowFragments];
        self.policy = [self policyForHost:[self host]];
        _settings = [[NSMutableDictionary alloc] init];
        _inAutoSync = false;
        _inContactsSync = false;
        _cacheProvider = cacheProvider;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateKeyValuePairs:) name:NSUbiquitousKeyValueStoreDidChangeExternallyNotification object:[NSUbiquitousKeyValueStore defaultStore]];
    }
    return self;
}

- (id)initWithUrl:(NSString *)url cacheProvider:(id<SeafCacheProvider>)cacheProvider username:(NSString *)username
{
    self = [self initWithUrl:url cacheProvider:cacheProvider];
    if (url) {
        NSString *infoKey = [NSString stringWithFormat:@"%@/%@", url, username];
        NSDictionary *ainfo = [SeafStorage.sharedObject objectForKey:infoKey];
        if (ainfo) {
            _info = [ainfo mutableCopy];
            Debug("Loaded account info from %@: %@", infoKey, ainfo);
            _token = [_info objectForKey:@"token"];
        } else {
            ainfo = [SeafStorage.sharedObject objectForKey:url];
            if (ainfo) {
                _info = [ainfo mutableCopy];
                [SeafStorage.sharedObject removeObjectForKey:url];
                [SeafStorage.sharedObject setObject:ainfo forKey:infoKey];
            }
        }

        NSDictionary *settings = [SeafStorage.sharedObject objectForKey:[NSString stringWithFormat:@"%@/%@/settings", url, username]];
        if (settings)
            _settings = [settings mutableCopy];
        else
            _settings = [[NSMutableDictionary alloc] init];
    }
    _clientIdentityKey = [_info objectForKey:@"identity"];
    if (_clientIdentityKey) {
        _clientCred = [SeafStorage.sharedObject getCredentialForKey:_clientIdentityKey];
        Debug("Load client identity: %@, %@", _clientIdentityKey, self.clientCred);
    }

    if (self.authorized && ![self serverInfo]) {
        [self getServerInfo:^(bool result) {}];
    }
    if (self.autoClearRepoPasswd) {
        Debug("Clear repo apsswords for %@ %@", url, username);
        [self clearRepoPasswords];
    }
    [_rootFolder loadContent:NO];
    return self;
}


- (NSString *)platformVersion
{
    if (!_platformVersion) {
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        _platformVersion = [infoDictionary objectForKey:@"DTPlatformVersion"];
    }
    return _platformVersion;
}

- (NSString *)localUploadDir
{
    if (!_localUploadDir) {
        _localUploadDir = [self getAttribute:@"UPLOAD_CACHE_DIR"];
        if (!_localUploadDir) {
            _localUploadDir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.uploadsDir];
            [self setAttribute:_localUploadDir forKey:@"UPLOAD_CACHE_DIR"];
        }
        [Utils checkMakeDir:_localUploadDir];
    }

    return _localUploadDir;
}

- (void)saveSettings
{
    [SeafStorage.sharedObject setObject:_settings forKey:[self.accountIdentifier stringByAppendingString:@"/settings"]];
}

- (void)setAttribute:(id)anObject forKey:(NSString *)aKey
{
    [Utils dict:_settings setObject:anObject forKey:aKey];
    [self saveSettings];
}

- (id)getAttribute:(NSString *)aKey
{
    if (!aKey) return nil;
    return [_settings objectForKey:aKey];
}

- (void)setAddress:(NSString *)address
{
    if ([address hasSuffix:@"/"]) {
        _address = [address substringToIndex:address.length-1];
    } else
        _address = address;
}

- (BOOL)authorized
{
    return self.token != nil;
}

- (BOOL)isFeatureEnabled:(NSString *)feature
{
    NSDictionary *serverInfo = [self serverInfo];
    if (!serverInfo)
        return true;
    NSArray *features = [serverInfo objectForKey:@"features"];
    if ([features containsObject:feature])
        return true;
    return false;
}

- (BOOL)isSearchEnabled
{
    return [self isFeatureEnabled:@"file-search"];
}

- (NSString *)serverVersion
{
    NSDictionary *serverInfo = self.serverInfo;
    if (!serverInfo)
        return nil;

    return [serverInfo objectForKey:@"version"];
}

- (BOOL)isChunkSupported
{
    NSString *version = self.serverVersion;
    if (version && [version compare:@"5.1.0" options:NSNumericSearch] != NSOrderedAscending) {
        return true;
    }
    return false;
}

- (BOOL)isActivityEnabled
{
    return [self isFeatureEnabled:@"seafile-pro"];
}

- (NSDictionary *)serverInfo
{
    return [_settings objectForKey:@"serverInfo"];
}

- (void)setServerInfo:(NSDictionary *)info
{
    [self setAttribute:info forKey:@"serverInfo"];
}

- (BOOL)isWifiOnly
{
    return [[self getAttribute:@"wifiOnly"] booleanValue:true];
}

- (BOOL)isAutoSync
{
    return [[self getAttribute:@"autoSync"] booleanValue:true];
}

- (BOOL)isVideoSync
{
    return [[self getAttribute:@"videoSync"] booleanValue:true];
}

- (BOOL)isBackgroundSync
{
    return [[self getAttribute:@"backgroundSync"] booleanValue:true];
}

- (BOOL)isContactsSync
{
    return [[self getAttribute:@"contactsSync"] booleanValue:true];
}

- (BOOL)isFirstTimeSync
{
    return [[self getAttribute:@"firstTimeSync"] booleanValue:false];
}

- (BOOL)autoClearRepoPasswd
{
    return [[self getAttribute:@"autoClearRepoPasswd"] booleanValue:false];
}

- (BOOL)localDecryptionEnabled
{
    return [[self getAttribute:@"localDecryption"] booleanValue:false];
}

- (void)setLocalDecryptionEnabled:(BOOL)localDecryptionEnabled
{
    if (self.localDecryptionEnabled == localDecryptionEnabled) return;
    [self setAttribute:[NSNumber numberWithBool:localDecryptionEnabled] forKey:@"localDecryption"];
}

- (BOOL)touchIdEnabled
{
    return [[self getAttribute:@"touchIdEnabled"] booleanValue:false];
}

- (void)setTouchIdEnabled:(BOOL)touchIdEnabled
{
    if (self.touchIdEnabled == touchIdEnabled) return;
    [self setAttribute:[NSNumber numberWithBool:touchIdEnabled] forKey:@"touchIdEnabled"];
}

- (void)setAutoClearRepoPasswd:(BOOL)autoClearRepoPasswd
{
    if (self.autoClearRepoPasswd == autoClearRepoPasswd) return;
    [self setAttribute:[NSNumber numberWithBool:autoClearRepoPasswd] forKey:@"autoClearRepoPasswd"];

}
- (void)setAutoSync:(BOOL)autoSync
{
    if (self.isAutoSync == autoSync) return;
    [self setAttribute:[NSNumber numberWithBool:autoSync] forKey:@"autoSync"];
    [self setFirstTimeSync:true];
}

- (void)setVideoSync:(BOOL)videoSync
{
    if (self.isVideoSync == videoSync) return;
    [self setAttribute:[NSNumber numberWithBool:videoSync] forKey:@"videoSync"];
    if (!videoSync) {
        [self clearUploadingVideos];
    } else {
        [self checkPhotos:true];
    }
}

- (void)setWifiOnly:(BOOL)wifiOnly
{
    if (self.wifiOnly == wifiOnly) return;
    [self setAttribute:[NSNumber numberWithBool:wifiOnly] forKey:@"wifiOnly"];
}

- (void)setBackgroundSync:(BOOL)backgroundSync
{
    if (self.backgroundSync == backgroundSync) return;
    [self setAttribute:[NSNumber numberWithBool:backgroundSync] forKey:@"backgroundSync"];
}

- (void)setContactsSync:(BOOL)contactsSync
{
    if (self.isContactsSync == contactsSync) return;
    [self setAttribute:[NSNumber numberWithBool:contactsSync] forKey:@"contactsSync"];
    if (!contactsSync) {
        self.contactsRepo = nil;
        [self setAttribute:nil forKey:@"ContactsLastSyncRepo"];
        [self setAttribute:nil forKey:@"ContactsLastSyncNumber"];
        self.contactsLastBackTime = nil;
    }
}

- (void)setFirstTimeSync:(BOOL)firstTimeSync
{
    if (self.firstTimeSync == firstTimeSync) return;
    [self setAttribute:[NSNumber numberWithBool:firstTimeSync] forKey:@"firstTimeSync"];
}

- (NSString *)autoSyncRepo
{
    return [[self getAttribute:@"autoSyncRepo"] stringValue];
}

- (void)setAutoSyncRepo:(NSString *)repoId
{
    if (!repoId && [repoId isEqualToString:self.autoSyncRepo]) {
        return;
    }
    _syncDir = nil;
    [self setAttribute:repoId forKey:@"autoSyncRepo"];
    if (repoId) {
        [self setFirstTimeSync:true];
    }
}

- (NSString *)contactsRepo
{
    return [[self getAttribute:@"contactsRepo"] stringValue];
}

- (void)setContactsRepo:(NSString *)repoId
{
    [self setAttribute:repoId forKey:@"contactsRepo"];
}

- (NSString *)username
{
    return [_info objectForKey:@"username"];
}

- (NSString *)password
{
    return [_info objectForKey:@"password"];
}

- (NSString *)hostForUrl:(NSString *)urlStr
{
    NSURL *url = [NSURL URLWithString:urlStr];
    return url.host;
}
- (NSString *)accountIdentifier {
    if (!_accountIdentifier)  {
        _accountIdentifier = [NSString stringWithFormat:@"%@/%@", self.address, self.username];
    }
    return _accountIdentifier;
}

- (NSString *)host
{
    return [self hostForUrl:self.address];
}

- (NSString *)certPathForHost:(NSString *)host
{
    NSString *filename = [NSString stringWithFormat:@"%@.cer", host];
    NSString *path = [SeafStorage.sharedObject.certsDir stringByAppendingPathComponent:filename];
    return path;
}

- (BOOL)isShibboleth
{
    return [[_info objectForKey:@"isshibboleth"] boolValue];
}

- (long long)quota
{
    return [[_info objectForKey:@"total"] integerValue:0];
}

- (long long)usage
{
    return [[_info objectForKey:@"usage"] integerValue:-1];
}

- (NSString *)uniqueUploadDir
{
    return [SeafStorage uniqueDirUnder:self.localUploadDir];
}

- (NSString *)tagDataKey {
    if (!_tagDataKey) {
        _tagDataKey = [NSString stringWithFormat:@"%@/%@",TAGDATA,self.accountIdentifier];
    }
    return _tagDataKey;
}

- (void)saveRepo:(NSString *)repoId password:(NSString *)password
{
    Debug("save repo %@ password %@", repoId, password);
    NSMutableDictionary *repopasswds = [NSMutableDictionary dictionaryWithDictionary:(NSDictionary*)[_info objectForKey:@"repopassword"]];
    if (!repopasswds) {
        repopasswds = [[NSMutableDictionary alloc] init];
    }
    [Utils dict:repopasswds setObject:password forKey:repoId];
    [Utils dict:_info setObject:repopasswds forKey:@"repopassword"];
    [self saveAccountInfo];
}
- (void)saveRepo:(NSString *_Nonnull)repoId encInfo:(NSDictionary *_Nonnull)encInfo
{
    Debug("save repo %@ enc info %@", repoId, encInfo);
    NSMutableDictionary *repoInfos = [NSMutableDictionary dictionaryWithDictionary:(NSDictionary*)[_info objectForKey:@"repoInfo"]];
    if (!repoInfos) {
        repoInfos = [[NSMutableDictionary alloc] init];
    }

    [Utils dict:repoInfos setObject:encInfo forKey:repoId];
    [Utils dict:_info setObject:repoInfos forKey:@"repoInfo"];
    [self saveAccountInfo];
}

- (NSDictionary *)getRepoEncInfo:(NSString *)repoId
{
    NSDictionary *repoInfos = (NSDictionary*)[_info objectForKey:@"repoInfo"];
    if (repoInfos)
        return [repoInfos objectForKey:repoId];
    return nil;
}

- (NSString *)getRepoPassword:(NSString *)repoId
{
    NSDictionary *repopasswds = (NSDictionary*)[_info objectForKey:@"repopassword"];
    if (repopasswds)
        return [repopasswds objectForKey:repoId];
    return nil;
}

- (AFSecurityPolicy *)policyForHost:(NSString *)host
{
    NSString *path = [self certPathForHost:host];
    return SeafPolicyFromFile(path);
}

- (AFHTTPSessionManager *)loginMgr
{
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.TLSMinimumSupportedProtocol = kTLSProtocol1;

    AFHTTPSessionManager *manager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:configuration];
    [manager setSessionDidReceiveAuthenticationChallengeBlock:^NSURLSessionAuthChallengeDisposition(NSURLSession *session, NSURLAuthenticationChallenge *challenge, NSURLCredential *__autoreleasing *credential) {
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            if (SeafStorage.sharedObject.allowInvalidCert) return NSURLSessionAuthChallengeUseCredential;

            *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            BOOL valid = SeafServerTrustIsValid(challenge.protectionSpace.serverTrust);
            Debug("Server cert is valid: %d, delegate=%@, inCheckCert=%d, credential:%@", valid, self.delegate, self.inCheckCert, *credential);
            if (valid) {
                [[NSFileManager defaultManager] removeItemAtPath:[self certPathForHost:challenge.protectionSpace.host] error:nil];
                if ([challenge.protectionSpace.host isEqualToString:self.host]) {
                    SecCertificateRef cer = SecTrustGetCertificateAtIndex(challenge.protectionSpace.serverTrust, 0);
                    self.policy = SeafPolicyFromCert(cer);
                }
                return NSURLSessionAuthChallengeUseCredential;
            } else {
                if (!self.loginDelegate) return NSURLSessionAuthChallengeCancelAuthenticationChallenge;
                @synchronized(self) {
                    if (self.inCheckCert)
                        return NSURLSessionAuthChallengeCancelAuthenticationChallenge;
                    self.inCheckCert = true;
                }
                BOOL yes = [self.loginDelegate authorizeInvalidCert:challenge.protectionSpace];
                NSURLSessionAuthChallengeDisposition dis = yes ? NSURLSessionAuthChallengeUseCredential: NSURLSessionAuthChallengeCancelAuthenticationChallenge;
                if (yes)
                    [self saveCertificate:challenge.protectionSpace];

                self.inCheckCert = false;
                return dis;
            }
        } else if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodClientCertificate]) {
            Debug("Use NSURLAuthenticationMethodClientCertificate");
            if (!self.loginDelegate) return NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            NSData *key = [self.loginDelegate getClientCertPersistentRef:credential];
            if (key == nil){
                return NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            } else {
                _clientIdentityKey = key;
                _clientCred = *credential;
                [Utils dict:_info setObject:key forKey:@"identity"];
                return NSURLSessionAuthChallengeUseCredential;
            }
        } else {
        }
        return NSURLSessionAuthChallengePerformDefaultHandling;
    }];
    return manager;
}

- (AFSecurityPolicy *)policy
{
    return _policy;
}

-(BOOL)validateServerrust:(SecTrustRef)serverTrust withPolicy:(AFSecurityPolicy *)policy forDomain:(NSString *)domain
{
    if (policy) {
        return [policy evaluateServerTrust:serverTrust forDomain:domain];
    } else {
        return SeafServerTrustIsValid(serverTrust);
    }
}

- (void)setPolicy:(AFSecurityPolicy *)policy
{
    _policy = policy;
    _sessionMgr.securityPolicy = _policy;
    __weak typeof(self) weakSelf = self;

    [_sessionMgr setSessionDidReceiveAuthenticationChallengeBlock:^NSURLSessionAuthChallengeDisposition(NSURLSession *session, NSURLAuthenticationChallenge *challenge, NSURLCredential *__autoreleasing *credential) {
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            if (SeafStorage.sharedObject.allowInvalidCert) return NSURLSessionAuthChallengeUseCredential;
            if ([weakSelf validateServerrust:challenge.protectionSpace.serverTrust withPolicy:weakSelf.policy forDomain:challenge.protectionSpace.host]) {
                return NSURLSessionAuthChallengeUseCredential;
            } else {
                return NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        } else if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodClientCertificate]) {
            if (weakSelf.clientCred != nil) {
                *credential = self.clientCred;
                return NSURLSessionAuthChallengeUseCredential;
            } else
                return NSURLSessionAuthChallengePerformDefaultHandling;
        }
        return NSURLSessionAuthChallengePerformDefaultHandling;
    }];
}

- (BOOL)localDecrypt
{
    return self.localDecryptionEnabled && self.isChunkSupported;
}

- (BOOL)isEncrypted:(NSString *)repoId
{
    SeafRepo *repo = [self getRepo:repoId];
    return repo.encrypted;
}

- (BOOL)shouldLocalDecrypt:(NSString * _Nonnull)repoId
{
    SeafRepo *repo = [self getRepo:repoId];
    //Debug("Repo %@ encrypted %d version:%d, magic:%@", repoId, repo.encrypted, repo.encVersion, repo.magic);
    return [self localDecrypt] && repo.encrypted;
}

- (void)clearUploadCache
{
    [Utils clearAllFiles:self.localUploadDir];
}

- (void)logout
{
    _token = nil;
    [_info removeObjectForKey:@"token"];
    [_info removeObjectForKey:@"password"];
    [_info removeObjectForKey:@"repopassword"];
    [_info removeObjectForKey:@"repoInfo"];
    [self saveSettings];
}

- (void)clearAccount
{
    [SeafDataTaskManager.sharedObject removeAccountQueue:self];
    [SeafStorage.sharedObject removeObjectForKey:_address];
    [SeafStorage.sharedObject removeObjectForKey:self.accountIdentifier];
    [SeafStorage.sharedObject removeObjectForKey:[NSString stringWithFormat:@"%@/settings", self.accountIdentifier]];
    [SeafStorage.sharedObject removeObjectForKey:self.tagDataKey];

    NSString *path = [self certPathForHost:[self host]];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    [self clearAccountCache];
    [self clearCache:ENTITY_UPLOAD_PHOTO];
}

- (void)saveAccountInfo
{
    Debug("Save account info to %@: %@", self.accountIdentifier, _info);
    [SeafStorage.sharedObject setObject:_info forKey:self.accountIdentifier];
    [SeafStorage.sharedObject synchronize];
}

- (void)getAccountInfo:(void (^)(bool result))handler
{
    [self sendRequest:API_URL"/account/info/"
              success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         NSDictionary *account = JSON;
         Debug("account detail:%@", account);
         [Utils dict:_info setObject:[account objectForKey:@"total"] forKey:@"total"];
         [Utils dict:_info setObject:[account objectForKey:@"email"] forKey:@"email"];
         [Utils dict:_info setObject:[account objectForKey:@"usage"] forKey:@"usage"];
         [Utils dict:_info setObject:[account objectForKey:@"name"] forKey:@"name"];
         [Utils dict:_info setObject:_address forKey:@"link"];
         [self saveAccountInfo];
         if (handler) handler(true);
     }
              failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         if (handler) handler(false);
     }];
}

- (NSMutableURLRequest *)loginRequest:(NSString *)url username:(NSString *)username password:(NSString *)password
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[url stringByAppendingString:API_URL"/auth-token/"]]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *version = SEAFILE_VERSION;
    NSString *platform = @"ios";
    NSString *platformName = [infoDictionary objectForKey:@"DTPlatformName"];
    NSString *platformVersion = [infoDictionary objectForKey:@"DTPlatformVersion"];
    NSString *deviceID = [UIDevice currentDevice].identifierForVendor.UUIDString;
    NSString *deviceName = UIDevice.currentDevice.name;

    NSString *formString = [NSString stringWithFormat:@"username=%@&password=%@&platform=%@&platformName=%@&device_id=%@&device_name=%@&client_version=%@&platform_version=%@", username.escapedPostForm, password.escapedPostForm, platform.escapedPostForm, platformName.escapedPostForm, deviceID.escapedPostForm, deviceName.escapedPostForm, version.escapedPostForm, platformVersion.escapedPostForm];
    [request setHTTPBody:[NSData dataWithBytes:formString.UTF8String length:[formString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]]];
    return request;
}

-(void)setToken:(NSString *)token forUser:(NSString *)username isShib:(BOOL)isshib s2faToken:(NSString*)s2faToken
{
    _token = token;
    [Utils dict:_info setObject:username forKey:@"username"];
    [Utils dict:_info setObject:token forKey:@"token"];
    [Utils dict:_info setObject:_address forKey:@"link"];
    [Utils dict:_info setObject:[NSNumber numberWithBool:isshib] forKey:@"isshibboleth"];
    [Utils dict:_info setObject:s2faToken forKey:@"s2faToken"];
    [self saveAccountInfo];
    [self.loginDelegate loginSuccess:self];
    
    dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC));
    dispatch_after(delayTime, dispatch_get_main_queue(), ^{
        [self downloadAvatar:true];
    });
}

-(void)showDeserializedError:(NSError *)error
{
    NSData *data = [error.userInfo objectForKey:@"com.alamofire.serialization.response.error.data"];
    if (data && [data isKindOfClass:[NSData class]]) {
        NSString *str __attribute__((unused)) = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        Debug("%@ DeserializedErro: %@", _address, str);
    }
}

/*
 curl -D a.txt --data "username=xx@seafile.com&password=xx" https://seacloud.cc/api2/auth-token/
 */
- (void)loginWithUsername:(NSString *)username password:(NSString *)password otp:(NSString *)otp rememberDevice:(BOOL)remember
{
    NSString *url = _address;
    NSMutableURLRequest *request = [self loginRequest:url username:username password:password];
    if (otp) {
        [request setValue:otp forHTTPHeaderField:@"X-Seafile-OTP"];
    }
    if (remember) {
        [request setValue:@"1" forHTTPHeaderField:@"X-SEAFILE-2FA-TRUST-DEVICE"];
    }
    if ([_info objectForKey:@"s2faToken"]) {
        [request setValue:[_info objectForKey:@"s2faToken"] forHTTPHeaderField:@"X-SEAFILE-S2FA"];
    }
    
    AFHTTPSessionManager *manager = self.loginMgr;
    manager.responseSerializer = [AFJSONResponseSerializer serializer];

    Debug("Login: %@ %@", url, username);
    NSURLSessionDataTask *dataTask = [manager dataTaskWithRequest:request completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
        NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
        if (error) {
            Warning("Error: %@, response:%@", error, responseObject);
            [self showDeserializedError:error];
            [self.loginDelegate loginFailed:self response:resp error:error];
        } else {
            NSString *s2faToken = [resp.allHeaderFields objectForKey:@"X-SEAFILE-S2FA"];
            
            [Utils dict:_info setObject:password forKey:@"password"];
            [self setToken:[responseObject objectForKey:@"token"] forUser:username isShib:false s2faToken:s2faToken];
        }
    }];

    [dataTask resume];
}

- (void)loginWithUsername:(NSString *)username password:(NSString *)password
{
    [self loginWithUsername:username password:password otp:nil rememberDevice:false];
}

- (NSURLRequest *)buildRequest:(NSString *)url method:(NSString *)method form:(NSString *)form
{
    NSString *absoluteUrl = [url hasPrefix:@"http"] ? url : [_address stringByAppendingString:url];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:absoluteUrl]];
    [request setValue:SEAFILE_VERSION forHTTPHeaderField:@"X-Seafile-Client-Version"];
    [request setValue:self.platformVersion forHTTPHeaderField:@"X-Seafile-Platform-Version"];

    [request setTimeoutInterval:DEFAULT_TIMEOUT];
    [request setHTTPMethod:method];
    if (form) {
        [request setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
        NSData *requestData = [NSData dataWithBytes:form.UTF8String length:[form lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
        [request setHTTPBody:requestData];
    }

    if (self.token)
        [request setValue:[NSString stringWithFormat:@"Token %@", self.token] forHTTPHeaderField:@"Authorization"];

    return request;
}

- (void)sendRequestAsync:(NSString *)url method:(NSString *)method form:(NSString *)form
                 success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
                 failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error))failure
{
    NSURLRequest *request = [self buildRequest:url method:method form:form];
    Debug("Request: %@", request.URL);

    NSURLSessionDataTask *task = [_sessionMgr dataTaskWithRequest:request completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
        NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
        if (error) {
            [self showDeserializedError:error];
            Warning("token=%@, resp=%ld %@, delegate=%@, url=%@, Error: %@", _token, (long)resp.statusCode, responseObject, self.delegate, url, error);
            failure (request, resp, responseObject, error);
            if (resp.statusCode == HTTP_ERR_UNAUTHORIZED) {
                NSString *wiped = [resp.allHeaderFields objectForKey:@"X-Seafile-Wiped"];
                Debug("wiped: %@", wiped);
                @synchronized(self) {
                    if (![self authorized])   return;
                    _token = nil;
                    [_info removeObjectForKey:@"token"];
                    [self saveAccountInfo];
                    if (wiped) {
                        [self clearAccountCache];
                    }
                }
                if (self.delegate) [self.delegate loginRequired:self];
            } else if (resp.statusCode == HTTP_ERR_OPERATION_FAILED && [responseObject isKindOfClass:[NSDictionary class]]) {
                NSString *err_msg = [((NSDictionary *)responseObject) objectForKey:@"error_msg"];
                if (err_msg && [@"Above quota" isEqualToString:err_msg]) {
                    Warning("Out of quota.");
                    [self.delegate outOfQuota:self];
                }
            } else if (resp.statusCode == HTTP_ERR_REPO_DOWNLOAD_PASSWORD_EXPIRED) {
                [self refreshRepoPassowrds];
            }
        } else {
            success(request, resp, responseObject);
        }
    }];
    [task resume];
}

- (void)sendRequest:(NSString *)url
            success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
            failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error))failure
{
    [self sendRequestAsync:url method:@"GET" form:nil success:success failure:failure];
}

- (void)sendOptions:(NSString *)url
            success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
            failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error))failure
{
    [self sendRequestAsync:url method:@"OPTIONS" form:nil success:success failure:failure];
}

- (void)sendDelete:(NSString *)url
           success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
           failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error))failure
{
    [self sendRequestAsync:url method:@"DELETE" form:nil success:success failure:failure];
}

- (void)sendPut:(NSString *)url form:(NSString *)form
        success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
        failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error))failure
{
    [self sendRequestAsync:url method:@"PUT" form:form success:success failure:failure];
}

- (void)sendPost:(NSString *)url form:(NSString *)form
         success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
         failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error))failure
{
    [self sendRequestAsync:url method:@"POST" form:form success:success failure:failure];
}

- (void)loadRepos:(id<SeafDentryDelegate>)degt
{
    _rootFolder.delegate = degt;
    [_rootFolder loadContent:NO];
}

- (void)handleStarredData:(id)JSON
{
    NSMutableSet *stars = [NSMutableSet set];
    for (NSDictionary *info in JSON) {
        [stars addObject:[NSString stringWithFormat:@"%@-%@", [info objectForKey:@"repo"], [info objectForKey:@"path"]]];
    }
    _starredFiles = stars;
}

- (void)getStarredFiles:(void (^)(NSHTTPURLResponse *response, id JSON))success
                failure:(void (^)(NSHTTPURLResponse *response, NSError *error))failure
{
    [self sendRequest:API_URL"/starredfiles/"
              success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         @synchronized(self) {
             Debug("Succeeded to get starred files ...\n");
             [self handleStarredData:JSON];
             NSData *data = [Utils JSONEncode:JSON];
             [self setValue:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] forKey:KEY_STARREDFILES entityName:ENTITY_OBJECT];
             if (success)
                 success (response, JSON);
         }
     }
              failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         if (failure)
             failure (response, error);
     }];
}

- (void)getServerInfo:(void (^)(bool result))handler
{
    [self sendRequest:API_URL"/server-info/"
              success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         @synchronized(self) {
             Debug("Succeeded to get server info: %@\n", JSON);
             [self setServerInfo:JSON];
             if (handler)
                 handler (true);
         }
     }
              failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         if (handler)
             handler (false);
     }];
}


- (BOOL)isStarred:(NSString *)repo path:(NSString *)path
{
    NSString *key = [NSString stringWithFormat:@"%@-%@", repo, path];
    if ([_starredFiles containsObject:key])
        return YES;
    return NO;
}

- (BOOL)setStarred:(BOOL)starred repo:(NSString *)repo path:(NSString *)path
{
    NSString *key = [NSString stringWithFormat:@"%@-%@", repo, path];
    if (starred) {
        [_starredFiles addObject:key];
        NSString *form = [NSString stringWithFormat:@"repo_id=%@&p=%@", repo, [path escapedUrl]];
        NSString *url = [NSString stringWithFormat:API_URL"/starredfiles/"];
        [self sendPost:url form:form
               success:
         ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
             Debug("Succeeded to star file %@, %@\n", repo, path);
         }
               failure:
         ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
             Warning("Failed to star file %@, %@\n", repo, path);
         }];
    } else {
        [_starredFiles removeObject:key];
        NSString *url = [NSString stringWithFormat:API_URL"/starredfiles/?repo_id=%@&p=%@", repo, path.escapedUrl];
        [self sendDelete:url
               success:
         ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
             Debug("Succeeded to unstar file %@, %@\n", repo, path);
         }
               failure:
         ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
             Warning("Failed to unstar file %@, %@\n", repo, path);
         }];
    }

    return YES;
}

- (SeafRepo *)getRepo:(NSString *)repo
{
    return [self.rootFolder getRepo:repo];
}

- (void)search:(NSString *)keyword repo:(NSString *)repoId
       success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSMutableArray *results))success
       failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error))failure
{
    NSString *url = [NSString stringWithFormat:API_URL"/search/?q=%@&per_page=100", [keyword escapedUrl]];
    if (repoId)
        url = [url stringByAppendingFormat:@"&search_repo=%@", repoId];
    [self sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        NSMutableArray *results = [[NSMutableArray alloc] init];
        for (NSDictionary *itemInfo in [JSON objectForKey:@"results"]) {
            if ([itemInfo objectForKey:@"name"] == [NSNull null]) continue;
            NSString *oid = [itemInfo objectForKey:@"oid"];
            NSString *repoId = [itemInfo objectForKey:@"repo_id"];
            NSString *name = [itemInfo objectForKey:@"name"];
            NSString *path = [itemInfo objectForKey:@"fullpath"];
            if ([[itemInfo objectForKey:@"is_dir"] integerValue]) {
                SeafDir *dir = [[SeafDir alloc] initWithConnection:self oid:oid repoId:repoId perm:nil name:name path:path];
                [results addObject:dir];
            } else {
                SeafFile *file = [[SeafFile alloc] initWithConnection:self oid:oid repoId:repoId name:name path:path mtime:[[itemInfo objectForKey:@"last_modified"] integerValue:0] size:[[itemInfo objectForKey:@"size"] integerValue:0]];
                [results addObject:file];
            }
        }
        success(request, response, JSON, results);
    } failure:failure];
}

- (void)registerDevice:(NSData *)deviceToken
{
#if 0
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *version = SEAFILE_VERSION;
    NSString *platform = [infoDictionary objectForKey:@"DTPlatformName"];
    NSString *platformVersion = [infoDictionary objectForKey:@"DTPlatformVersion"];

    NSString *form = [NSString stringWithFormat:@"deviceToken=%@&version=%@&platform=%@&pversion=%@", deviceToken.hexString, version, platform, platformVersion ];
    Debug("form=%@, len=%lu", form, (unsigned long)deviceToken.length);
    [self sendPost:API_URL"/regdevice/" form:form success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
        Debug("Register success");
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        Warning("Failed to register device");
    }];
#endif
}

- (NSString *)realAvatar
{
    NSString *path = [SeafUserAvatar pathForAvatar:self username:self.username];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path])
        return path;
    return nil;
}

- (NSString *)avatar
{
    NSString *path = self.realAvatar;
    if (path) return path;
    [self downloadAvatar:false];
    return [SeafileBundle() pathForResource:@"account" ofType:@"png"];
}

- (UIImage *)avatarForAccount:(NSString *)email
{
    NSString *path = [SeafileBundle() pathForResource:@"account" ofType:@"png"];
    return [UIImage imageWithContentsOfFile:path];
}

- (void)downloadAvatar:(BOOL)force;
{
    if (![self authorized])
        return;
    if (!force && self.realAvatar && [self.avatarLastUpdate timeIntervalSinceNow] > -24*3600)
        return;
    if (!force && [self.avatarLastUpdate timeIntervalSinceNow] > -300.0f)
        return;
    Debug("%@, %d\n", self.address, [self authorized]);
    SeafUserAvatar *avatar = [[SeafUserAvatar alloc] initWithConnection:self username:self.username];
    [SeafDataTaskManager.sharedObject addAvatarTask:avatar];
    self.avatarLastUpdate = [NSDate date];
}

- (void)saveCertificate:(NSURLProtectionSpace *)protectionSpace
{
    SecCertificateRef cer = SecTrustGetCertificateAtIndex(protectionSpace.serverTrust, 0);
    NSData* data = (__bridge NSData*) SecCertificateCopyData(cer);
    NSString *path = [self certPathForHost:protectionSpace.host];
    BOOL ret = [data writeToFile:path atomically:YES];
    if (!ret) {
        Warning("Failed to save certificate to %@", path);
    } else {
        Debug("Save cert for %@ to %@", protectionSpace.host, path);
        self.policy = SeafPolicyFromCert(cer);
    }
}

+ (AFHTTPRequestSerializer <AFURLRequestSerialization> *)requestSerializer
{
    if (!_requestSerializer)
        _requestSerializer = [AFHTTPRequestSerializer serializer];
    return _requestSerializer;
}

- (void)pickPhotosForUpload
{
    SeafDir *dir = _syncDir;
    if (!_inAutoSync || !dir || !self.photosArray || self.photosArray.count == 0) return;
    if (self.wifiOnly && ![[AFNetworkReachabilityManager sharedManager] isReachableViaWiFi]) {
        Debug("wifiOnly=%d, isReachableViaWiFi=%d, for server %@", self.wifiOnly, [[AFNetworkReachabilityManager sharedManager] isReachableViaWiFi], _address);
        return;
    }

    Debug("Current %u, %u photos need to upload, dir=%@", (unsigned)self.photosArray.count, (unsigned)self.uploadingArray.count, dir.path);

    int count = 0;
    while (_uploadingArray.count < 5 && count++ < 5) {
        NSURL *url = [self popUploadPhoto];
        if (!url) break;
        [SeafDataTaskManager.sharedObject assetForURL:url
                                 resultBlock:^(ALAsset *asset) {
                                     NSString *filename = [Utils assertName:asset];
                                     if (!filename) {
                                         [self removeUploadingPhoto:url];
                                         return Warning("Failed to get asset name: %@", asset);
                                     }
                                     NSString *path = [self.localUploadDir stringByAppendingPathComponent:filename];
                                     SeafUploadFile *file = [[SeafUploadFile alloc] initWithPath:path];
                                     file.retryable = false;
                                     file.autoSync = true;
                                     file.overwrite = true;
                                     [file setAsset:asset url:url];
                                     file.udir = dir;
                                     [file setCompletionBlock:^(SeafUploadFile *file, NSString *oid, NSError *error) {
                                         [self autoSyncFileUploadComplete:file error:error];
                                     }];

                                     Debug("Add file %@ to upload list: %@ current %u %u", filename, dir.path, (unsigned)_photosArray.count, (unsigned)_uploadingArray.count);
                                     [SeafDataTaskManager.sharedObject addUploadTask:file];
                                 }
                                failureBlock:^(NSError *error){
                                    Debug("!!!!Can not find asset:%@ !", url);
                                    [self removeUploadingPhoto:url];
                                }];
    }
    if (self.photosArray.count == 0) {
        Debug("Force check if there are new photos after all synced.");
        [self checkPhotos:true];
    }
}

- (void)autoSyncFileUploadComplete:(SeafUploadFile *)ufile error:(NSError *)error
{
    if (!error) {
        [self pickPhotosForUpload];
        [self setPhotoUploaded:ufile.assetURL.absoluteString];
        [self removeUploadingPhoto:ufile.assetURL];
        Debug("Autosync file %@ %@ uploaded %d, remain %u %u", ufile.name, ufile.assetURL, [self IsPhotoUploaded:ufile.assetURL], (unsigned)_photosArray.count, (unsigned)_uploadingArray.count);
        
        if (_photSyncWatcher) [_photSyncWatcher photoSyncChanged:self.photosInSyncing];
    } else {
        Warning("Failed to upload photo %@: %@", ufile.name, error);
        // Add photo to the end of queue
        [self removeUploadingPhoto:ufile.assetURL];
        [self addUploadPhoto:ufile.assetURL];
    }
}

- (NSUInteger)autoSyncedNum
{
    return [self totalCachedNumForEntity:ENTITY_UPLOAD_PHOTO];
}

- (void)resetUploadedPhotos
{
    _uploadingArray = [[NSMutableArray alloc] init];
    [self clearCache:ENTITY_UPLOAD_PHOTO];
}

- (BOOL)IsPhotoUploading:(NSURL *)url
{
    @synchronized(_photosArray) {
        if ([_photosArray containsObject:url]) return true;
    }
    @synchronized(_uploadingArray) {
        if ([_uploadingArray containsObject:url]) return true;
    }
    return false;
}

- (void)addUploadingPhoto:(NSURL *)url {
    @synchronized(_uploadingArray) {
        [_uploadingArray addObject:url];
    }
}

- (void)removeUploadingPhoto:(NSURL *)url {
    @synchronized(_uploadingArray) {
        [_uploadingArray removeObject:url];
    }
}
- (void)addUploadPhoto:(NSURL *)url {
    @synchronized(_photosArray) {
        [_photosArray addObject:url];
    }
}
- (NSURL *)popUploadPhoto{
    @synchronized(self.photosArray) {
        if (!self.photosArray || self.photosArray.count == 0) return nil;
        NSURL *url = [self.photosArray objectAtIndex:0];
        [self addUploadingPhoto:url];
        [self.photosArray removeObject:url];
        Debug("Picked %@ remain: %u %u", url, (unsigned)_photosArray.count, (unsigned)_uploadingArray.count);
        return url;
    }
}

- (NSURL *)uploadURLForAsset:(ALAsset *)asset
{
    if (!asset)
        return nil;

    if(!self.isVideoSync && [[asset valueForProperty:ALAssetPropertyType] isEqualToString:ALAssetTypeVideo])
        return nil;

    NSURL *url = (NSURL*)asset.defaultRepresentation.url;
    if ([self IsPhotoUploaded:url] || [self IsPhotoUploading:url])
        return nil;

    if([[asset valueForProperty:ALAssetPropertyType] isEqualToString:ALAssetTypePhoto]
       || [[asset valueForProperty:ALAssetPropertyType] isEqualToString:ALAssetTypeVideo])
        return url;

    return nil;
}


- (void)firstTimeSyncUpdateSyncedPhotos:(SeafDir *)uploaddir
{
    [self setFirstTimeSync:false];
}

- (void)checkPhotos:(BOOL)force
{
     [self performSelectorInBackground:@selector(backGroundCheckPhotos:) withObject:[NSNumber numberWithBool:force]];
}

- (void)backGroundCheckPhotos:(NSNumber *)forceNumber
{
    bool force = [forceNumber boolValue];
    SeafDir *uploadDir = _syncDir;
    bool shouldSkip = !_inAutoSync || (!force && [self photosInSyncing] > 0) || (self.firstTimeSync && !uploadDir);
    if (shouldSkip) {
        return;
    }

    @synchronized(self) {
        if (_inCheckPhotoss) return;
        _inCheckPhotoss = true;
    }

    Debug("Check photos for server %@, current %u %u", _address, (unsigned)_photosArray.count, (unsigned)_uploadingArray.count);

    NSMutableArray *photos = [[NSMutableArray alloc] init];
    void (^assetEnumerator)(ALAsset *, NSUInteger, BOOL *) = ^(ALAsset *asset, NSUInteger index, BOOL *stop) {
        if (self.firstTimeSync) {
            NSString *name = [Utils assertName:asset];
            if ([uploadDir nameExist:name]) {
                [self setPhotoUploaded:asset.defaultRepresentation.url.absoluteString];
                Debug("First time sync, skip file %@(%@) which has already been uploaded", name, asset.defaultRepresentation.url);
                return;
            }
        }

        NSURL *url = [self uploadURLForAsset:asset];
        if (url) {
            [photos addObject:url];
        }
    };

    void (^ assetGroupEnumerator) ( ALAssetsGroup *, BOOL *) = ^(ALAssetsGroup *group, BOOL *stop) {
        if(group != nil) {
            [group setAssetsFilter:[ALAssetsFilter allAssets]];
            [group enumerateAssetsUsingBlock:assetEnumerator];
            Debug("Group %@, total %ld photos for server:%@", group, (long)group.numberOfAssets, _address);
        } else {
            for (NSURL *url in photos) {
                if (![self IsPhotoUploaded:url] && ![self IsPhotoUploading:url]) {
                    [self addUploadPhoto:url];
                }
            }
            if (self.firstTimeSync) {
                self.firstTimeSync = false;
            }

            Debug("GroupAll Total %ld photos need to upload: %@", (long)_photosArray.count, _address);
            if (_photSyncWatcher) [_photSyncWatcher photoSyncChanged:self.photosInSyncing];
            _inCheckPhotoss = false;
            [self pickPhotosForUpload];
        }
    };
    [[SeafDataTaskManager.sharedObject assetsLibrary] enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos
                                                                    usingBlock:assetGroupEnumerator
                                                                  failureBlock:^(NSError *error) {
                                                                      Debug("There is an error: %@", error);
                                                                      _inCheckPhotoss = false;
                                                                  }];
}

- (SeafDir *)getSubdirUnderDir:(SeafDir *)dir withName:(NSString *)name
{
    SeafDir *uploadDir = nil;
    for (SeafBase *obj in dir.items) {
        if ([obj isKindOfClass:[SeafDir class]] && [obj.name isEqualToString:name]) {
            uploadDir = (SeafDir *)obj;
            return uploadDir;
        }
    }
    return nil;
}

- (void)checkSyncDst:(SeafDir *)dir
{
    @synchronized(self) {
        if (_syncDir && [_syncDir.repoId isEqualToString:dir.repoId] && [_syncDir.path isEqualToString:dir.path])
            _syncDir = dir;
    }
}

- (NSUInteger)photosInSyncing
{
    return _photosArray.count + _uploadingArray.count;
}

- (void)updateUploadDir:(SeafDir *)dir
{
    BOOL changed = !_syncDir || ![_syncDir.repoId isEqualToString:dir.repoId] || ![_syncDir.path isEqualToString:dir.path];
    if (changed)
        _syncDir = dir;
    Debug("%ld photos remain, syncdir: %@ %@", (long)self.photosArray.count, _syncDir.repoId, _syncDir.name);
    [self checkPhotos:true];
}

- (void)checkPhotosUploadDir:(CompletionBlock)handler
{
    CompletionBlock completionHandler = ^(BOOL success, NSError * _Nullable error){
        if (!success) {
            _syncDir = nil;
        }
        if (handler) {
            handler(success, error);
        }
    };

    [self checkMakeUploadDirectory:self.autoSyncRepo subdir:CAMERA_UPLOADS_DIR completion:^(SeafDir *uploaddir, NSError * _Nullable error) {
        if (!uploaddir) {
            Warning("Failed to create camera sync folder: %@", error);
            completionHandler(false, error);
        } else {
            if (self.firstTimeSync) {
                Debug("First time sync, force fresh uploaddir content.");
                [uploaddir loadContentSuccess:^(SeafDir *dir) {
                    [self updateUploadDir:uploaddir];
                    completionHandler(true, nil);
                } failure:^(SeafDir *dir, NSError *error) {
                    Warning("Failed to get uploaddir items: %@", error);
                    completionHandler(false, error);
                }];
            } else {
                [self updateUploadDir:uploaddir];
                completionHandler(true, nil);
            }
        }
    }];
}

- (void)photosDidChange:(NSNotification *)note
{
    if (!_inAutoSync)
        return;
    Debug("photos changed %d for server %@, current: %u %u, _syncDir:%@", _inAutoSync, _address, (unsigned)_photosArray.count, (unsigned)_uploadingArray.count, _syncDir);
    if (!_syncDir) {
        Warning("Sync dir not exists, create.");
        [self checkPhotosUploadDir:nil];
    } else {
        [self checkPhotos:false];
    }
}

- (void)checkAutoSync
{
    if (!self.authorized) return;
    if (self.isAutoSync && [ALAssetsLibrary authorizationStatus] != ALAuthorizationStatusAuthorized) {
        self.autoSync = false;
        return;
    }

    BOOL value = self.isAutoSync && (self.autoSyncRepo != nil);
    if (_inAutoSync != value) {
        if (value) {
            Debug("Start auto sync for server %@", _address);
            _photosArray = [[NSMutableArray alloc] init];
            _uploadingArray = [[NSMutableArray alloc] init];;
        } else {
            Debug("Stop auto Sync for server %@", _address);
            _photosArray = nil;
            _inCheckPhotoss = false;
            _uploadingArray = nil;
            [SeafDataTaskManager.sharedObject cancelAutoSyncTasks:self];
            [self clearUploadCache];
        }
    }
    _inAutoSync = value;
    if (_inAutoSync) {
        Debug("start auto sync, check photos for server %@", _address);
        [self checkPhotosUploadDir:nil];
    }
}

- (NSMutableArray *)getAllContacts:(CNContactStore *)store
{
    NSMutableArray *contacts = [NSMutableArray array];
    NSError *fetchError;

    CNContactFetchRequest *request = [[CNContactFetchRequest alloc] initWithKeysToFetch:@[[CNContactVCardSerialization descriptorForRequiredKeys], [CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName]]];

    BOOL success = [store enumerateContactsWithFetchRequest:request error:&fetchError usingBlock:^(CNContact *contact, BOOL *stop) {
        [contacts addObject:contact];
    }];
    if (!success) {
        Warning("fetch contacts error = %@", fetchError);
        return nil;
    }
    return contacts;
}

- (void)saveContactsToFile:(NSString *)vCardPath completionHandler:(void(^)(BOOL success, NSArray *contacts, NSError * _Nullable error))handler
{
    CNContactStore *store = [[CNContactStore alloc] init];
    [store requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (!granted) {
            self.contactsSync = false;
            self.contactsRepo = nil;
            Warning("access to contacts denied: %@", error);
            return handler(false, nil, error);
        }
        NSMutableArray *contacts = [self getAllContacts:store];
        if (!contacts) {
            Warning("Failed to get all contacts.");
            return handler(false, nil, nil);
        }
        Info("Contacts count: %ld", contacts.count);
        NSError *err = nil;
        NSData *vcardData = [CNContactVCardSerialization dataWithContacts:contacts error:&err];
        if (err) {
            Warning("Failed to serialize contacts: %@", err);
            return handler(false, nil, err);
        }
        [vcardData writeToFile:vCardPath atomically:YES];
        handler(true, contacts, nil);
    }];
}

- (BOOL)restoreContactsFromFile:(NSString *)vCardPath
{
    Info("Restore contacts from file %@", vCardPath);
    CNContactStore *store = [[CNContactStore alloc] init];
    NSData *data = [NSData dataWithContentsOfFile:vCardPath];
    NSError *error = nil;
    NSArray *contacts = [NSArray arrayWithArray:[CNContactVCardSerialization contactsWithData:data error:&error]];
    if (error) {
        Warning("Failed to retrieve contacts from file %@", vCardPath);
        return false;
    }
    NSArray *currentContacts = [self getAllContacts:store];
    NSMutableDictionary *currentContactsDict = [NSMutableDictionary new];
    NSMutableDictionary *targetContactsDict = [NSMutableDictionary new];
    CNContactFormatter *formatter = [[CNContactFormatter alloc] init];
    Info("Current contacts: %ld restore to: %ld", currentContacts.count, contacts.count);
    for (CNContact *contact in currentContacts) {
        [currentContactsDict setObject:contact forKey:contact.identifier];
    }
    for (CNContact *contact in contacts) {
        NSError *error = nil;
        CNSaveRequest *request = [[CNSaveRequest alloc] init];
        [targetContactsDict setObject:contact forKey:contact.identifier];
        if ([currentContactsDict objectForKey:contact.identifier] != nil) {
            Debug("Update %@ %@", contact.identifier, [formatter stringFromContact:contact]);
            [request updateContact:[contact mutableCopy] ];
        } else {
            Debug("Add %@ %@", contact.identifier, [formatter stringFromContact:contact]);
            [request addContact:[contact mutableCopy] toContainerWithIdentifier:nil];
        }

        [store executeSaveRequest:request error:&error];
        if (error) {
            Warning("Failed to execute request: %@", error);
            return false;
        }
    }
    for (CNContact *contact in currentContacts) {
        if ([targetContactsDict objectForKey:contact.identifier] == nil) {
            NSError *error = nil;

            Debug("Delete %@ %@", contact.identifier, [formatter stringFromContact:contact]);
            CNSaveRequest *request = [[CNSaveRequest alloc] init];
            [request deleteContact:[contact mutableCopy] ];
            [store executeSaveRequest:request error:&error];
            if (error) {
                Warning("Failed to execute delete request: %@", error);
                return false;
            }
        }
    }

    return true;
}

- (void)checkMakeUploadDirectoryInRepo:(SeafRepo *)repo subdir:(NSString *)dirName completion:(void(^)(SeafDir *uploaddir, NSError * _Nullable error))completionHandler
{
    SeafDir *uploaddir = [self getSubdirUnderDir:repo withName:dirName];
    if (!uploaddir) {
        [repo loadContentSuccess:^(SeafDir *dir) {
            SeafDir *uploaddir = [self getSubdirUnderDir:repo withName:dirName];
            if (!uploaddir) {
                Debug("mkdir %@ in repo %@", dirName, repo.repoId);
                [repo mkdir:dirName success:^(SeafDir *dir) {
                    SeafDir *udir = [self getSubdirUnderDir:repo withName:dirName];
                    completionHandler(udir, nil);
                } failure:^(SeafDir *dir, NSError *error) {
                    Warning("Failed to create directory %@", dirName);
                    completionHandler(nil, error);
                }];
            } else {
                completionHandler(uploaddir, nil);
            }
        } failure:^(SeafDir *dir, NSError *error) {
            completionHandler(nil, error);
        }];
    } else {
        completionHandler(uploaddir, nil);
    }
}

- (void)checkMakeUploadDirectory:(NSString *)repoId subdir:(NSString *)dirName completion:(void(^)(SeafDir *uploaddir, NSError * _Nullable error))completionHandler
{
    SeafRepo *repo = [self getRepo:repoId];

    if (!repo) {
        Warning("No such repo %@, force update cache", repoId);
        [_rootFolder loadContentSuccess:^(SeafDir *dir) {
            SeafRepo *repo = [self getRepo:self.contactsRepo];
            if (!repo) {
                completionHandler(nil, nil);
            } else {
                [self checkMakeUploadDirectoryInRepo:repo subdir:dirName completion:completionHandler];
            }
        } failure:^(SeafDir *dir, NSError *error) {
            completionHandler(nil, error);
        }];
    } else {
        [self checkMakeUploadDirectoryInRepo:repo subdir:dirName completion:completionHandler];
    }
}

- (void)uploadFile:(NSString *)path toDir:(SeafDir *)dir completion:(void(^)(BOOL success, NSError * _Nullable error))completionHandler
{
    Debug("upload file %@ to %@", path, dir.path);
    SeafUploadFile *ufile = [[SeafUploadFile alloc] initWithPath:path];
    ufile.udir = dir;
    ufile.overwrite = true;
    ufile.retryable = false;
    [SeafDataTaskManager.sharedObject addUploadTask:ufile];
}

- (BOOL)isContactsChangedSinceLastBackup:(SeafDir *)contactsDir currentContacts:(NSArray *)contacts
{
#if 0
    NSString *serverLastBackupDate = [self getContactsLastBackupDate:contactsDir backupFile:nil];
    NSString *lastSyncRepo = [[self getAttribute:@"ContactsLastSyncRepo"] stringValue];
    int lastSyncNumber = [[self getAttribute:@"ContactsLastSyncNumber"] integerValue:-1];
    if (lastSyncRepo == nil || ![lastSyncRepo isEqualToString:contactsDir.repoId] || serverLastBackupDate == nil) {
        return true;
    }

    if (lastSyncNumber != contacts.count) {
        return true;
    }
    return false;
#else
    return true;
#endif
}

- (void)saveContactsLastBackupInfo:(NSString *)syncDate number:(long)syncNumber
{
    [self setAttribute:self.contactsRepo forKey:@"ContactsLastSyncRepo"];
    [self setAttribute:[NSNumber numberWithLong:syncNumber] forKey:@"ContactsLastSyncNumber"];
    self.contactsLastBackTime = syncDate;
}

- (NSDate *)dateFromYear:(int)year month:(int)month day:(int)day
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setDay:day];
    [components setMonth:month];
    [components setYear:year];
    return [calendar dateFromComponents:components];
}

- (NSString *)getContactsLastBackupDate:(SeafDir *)contactsDir backupFile:(SeafFile **)bfile
{
    NSString *regExPattern = @"^contacts-([0-9]+-[0-9]{2}-[0-9]{2}).vcf$";
    NSRegularExpression *regEx = [[NSRegularExpression alloc] initWithPattern:regExPattern options:NSRegularExpressionCaseInsensitive error:nil];

    SeafFile *backupFile = nil;
    NSString *ans = nil;
    for (id obj in contactsDir.items) {
        if ([obj isKindOfClass:[SeafFile class]]) {
            SeafFile *file = (SeafFile *)obj;
            NSString *name = file.name;
            NSArray *matches = [regEx matchesInString:name options:0 range:NSMakeRange(0, name.length)];
            if (matches.count != 1) {
                continue;
            }
            NSTextCheckingResult *match = [matches objectAtIndex:0];
            NSRange dateRange = [match rangeAtIndex:1];
            NSString *dateStr = [name substringWithRange:dateRange];
            if (ans == nil || [dateStr compare:ans] == NSOrderedDescending) {
                ans = dateStr;
                backupFile = file;
            }
        }
    }
    if (bfile) {
        *bfile = backupFile;
    }
    return ans;
}

- (void)contactStoreDidChange:(NSNotification *)notification
{
    if (self.inContactsSync || !self.contactsSync || !self.contactsRepo)
        return;
    [self backupContacts:false completion:^(BOOL success, NSError * _Nullable error) {
        Debug("Backup contacts %d: %@", success, error);
    }];
}

- (NSString *)backupContacts:(BOOL)force completion:(CompletionBlock)handler
{
    @synchronized(self) {
        if (_inContactsSync) {
            handler(false, nil);
            return nil;
        }
        _inContactsSync = true;
    }

    CompletionBlock completionHandler = ^(BOOL success, NSError * _Nullable error){
        _inContactsSync = false;
        handler(success, error);
    };

    if (!self.contactsSync || !self.contactsRepo) {
        Warning("contacts sync is disabled: %d %@", self.contactsSync, self.contactsRepo);
        completionHandler(false, nil);
        return nil;
    }

    NSDateFormatter *dateformate = [[NSDateFormatter alloc] init];
    [dateformate setDateFormat:@"yyyy-MM-dd"];
    NSDate *now = [NSDate date];
    NSString *backupDate = [dateformate stringFromDate:now];
    NSString *filename = [NSString stringWithFormat:@"contacts-%@.vcf", backupDate];
    NSString *uploadDir = [self uniqueUploadDir];
    [Utils checkMakeDir:uploadDir];
    NSString *path = [uploadDir stringByAppendingPathComponent:filename];
    [self saveContactsToFile:path completionHandler:^(BOOL success, NSArray *contacts, NSError * _Nullable error) {
        if (!success) {
            Warning("Failed to save contacts to vcf file: %@", error);
            return completionHandler(false, error);
        }
        Debug("contacts(%ld) write to file %@ success", contacts.count, path);
        [self checkMakeUploadDirectory:self.contactsRepo subdir:CONTACTS_UPLOADS_DIR completion:^(SeafDir *uploaddir, NSError * _Nullable error) {
            if (!uploaddir) {
                Warning("Failed to create contacts backup folder: %@", error);
                completionHandler(false, error);
            } else {
                BOOL changed = [self isContactsChangedSinceLastBackup:uploaddir currentContacts:contacts];
                Debug("upload %@ to %@, changed:%d force: %d", path, uploaddir.name, changed, force);
                if (!force && !changed) {
                    return completionHandler(true, nil);
                }
                [uploaddir loadContentSuccess:^(SeafDir *dir) {
                    [self uploadFile:path toDir:uploaddir completion:^(BOOL success, NSError * _Nullable error) {
                        if (success) {
                            [self saveContactsLastBackupInfo:backupDate number:contacts.count];
                        }
                        completionHandler(success, nil);
                    }];
                } failure:^(SeafDir *dir, NSError *error) {
                    completionHandler(false, error);
                }];
            }
        }];
    }];
    return filename;
}

- (void)getContactsLastBackFile:(void(^)(SeafFile *file, NSString *dateStr, NSError *error))completionHandler
{
    if (!self.contactsSync || !self.contactsRepo) {
        return completionHandler(nil, nil, nil);
    }

    [self checkMakeUploadDirectory:self.contactsRepo subdir:CONTACTS_UPLOADS_DIR completion:^(SeafDir *uploaddir, NSError * _Nullable error) {
        if (!uploaddir) {
            Warning("Failed to create contacts backup folder: %@", error);
            completionHandler(nil, nil, error);
        } else {
            [uploaddir loadContentSuccess:^(SeafDir *dir) {
                SeafFile *backupFile = nil;
                NSString *dateStr = [self getContactsLastBackupDate:uploaddir backupFile:&backupFile];
                Debug("getContactsLastBackupDate: %@ %@", dateStr, backupFile.name);
                completionHandler(backupFile, dateStr, nil);
            } failure:^(SeafDir *dir, NSError *error) {
                Warning("Failed to get uploaddir items: %@", error);
                completionHandler(nil, nil, error);
            }];
        }
    }];
}

- (void)getContactsLastBackTime:(void(^)(BOOL success, NSString *dateStr))completionHandler
{
    if (self.contactsLastBackTime) {
        return completionHandler(true, self.contactsLastBackTime);
    }
    [self getContactsLastBackFile:^(SeafFile *file, NSString *dateStr, NSError *error) {
        completionHandler(dateStr != nil, dateStr);
        if (dateStr) {
            self.contactsLastBackTime = dateStr;
        }
    }];
}

- (void)restoreContacts:(void(^)(BOOL success, NSError *error))handler
{
    @synchronized(self) {
        if (_inContactsSync) {
            return handler(false, nil);
        }
        _inContactsSync = true;
    }

    CompletionBlock completionHandler = ^(BOOL success, NSError * _Nullable error){
        _inContactsSync = false;
        handler(success, error);
    };

    [self getContactsLastBackFile:^(SeafFile *file, NSString *dateStr, NSError *error) {
        if (!file) {
            return completionHandler(false, error);
        }
        [file setFileDownloadedBlock:^(SeafFile * _Nonnull file, NSError *err) {
            NSString *path = [[file exportURL] path];
            if (err || !path) {
                completionHandler(false, err);
            } else {
                BOOL ret = [self restoreContactsFromFile:path];
                completionHandler(ret, nil);
            }
        }];
        [file loadContent:false];
    }];
}

- (void)removeVideosFromArray:(NSMutableArray *)arr {
    if (arr.count  == 0)
        return;
    @synchronized(arr) {
        NSMutableArray *videos = [[NSMutableArray alloc] init];
        for (NSURL *url in arr) {
            if ([Utils isVideoExt:url.pathExtension])
                [videos addObject:url];
        }
        [arr removeObjectsInArray:videos];
    }
}

- (void)clearUploadingVideos
{
    [SeafDataTaskManager.sharedObject cancelAutoSyncVideoTasks:self];
    [self removeVideosFromArray:_photosArray];
    [self removeVideosFromArray:_uploadingArray];
}

- (void)downloadDir:(SeafDir *)dir
{
    [dir loadContentSuccess:^(SeafDir *dir) {
        Debug("dir %@ items: %lu", dir.path, (unsigned long)dir.items.count);
        for (SeafBase *item in dir.items) {
            if ([item isKindOfClass:[SeafFile class]]) {
                SeafFile *file = (SeafFile *)item;
                Debug("download file: %@, %@", item.repoId, item.path);
                [SeafDataTaskManager.sharedObject addFileDownloadTask:file];
            } else if ([item isKindOfClass:[SeafDir class]]) {
                Debug("download dir: %@, %@", item.repoId, item.path);
                [self performSelector:@selector(downloadDir:) withObject:(SeafDir *)item];
            }
        }
    } failure:^(SeafDir *dir, NSError *error) {
        Warning("Failed to download dir %@ %@:  %@", dir.repoId, dir.path, error);
    }];
}

- (void)refreshRepoPassowrds
{
     NSDictionary *repopasswds = [_info objectForKey:@"repopassword"];
    if (repopasswds == nil)
        return;
    for (NSString *key in repopasswds) {
        NSString *repoId = key;
        SeafRepo *repo = [self getRepo:repoId];
        if (!repo) continue;
        Debug("refresh server %@ repo %@ password", _address, repoId);
        id block = ^(SeafBase *entry, int ret) {
            Debug("refresh repo %@ password: %d", entry.repoId, ret);
            if (ret == RET_WRONG_PASSWORD) {
                Debug("Repo password incorrect, clear password.");
                [self saveRepo:repoId password:nil];
            }
        };

        NSString *password = [repopasswds objectForKey:repoId];
        [repo checkOrSetRepoPassword:password block:block];
    }
}
- (void)clearRepoPasswords
{
    NSDictionary *repopasswds = [_info objectForKey:@"repopassword"];
    if (repopasswds == nil)
        return;
    [Utils dict:_info setObject:[[NSDictionary alloc] init] forKey:@"repopassword"];
    [Utils dict:_info setObject:[[NSDictionary alloc] init] forKey:@"repoInfo"];
    [self saveAccountInfo];
}

#pragma - Cache managerment
- (NSString *)objectForKey:(NSString *)key entityName:(NSString *)entity
{
    return [_cacheProvider objectForKey:key entityName:entity inAccount:self.accountIdentifier];
}

- (BOOL)setValue:(NSString *)value forKey:(NSString *)key entityName:(NSString *)entity
{
    return [_cacheProvider setValue:value forKey:key entityName:entity inAccount:self.accountIdentifier];
}

- (void)removeKey:(NSString *)key entityName:(NSString *)entity
{
    [_cacheProvider removeKey:key entityName:entity inAccount:self.accountIdentifier];
}

- (long)totalCachedNumForEntity:(NSString *)entity
{
    return [_cacheProvider totalCachedNumForEntity:entity inAccount:self.accountIdentifier];
}

- (void)clearCache:(NSString *)entity
{
    [_cacheProvider clearCache:entity inAccount:self.accountIdentifier];
}

- (id)getCachedJson:(NSString *)key entityName:(NSString *)entity
{
    NSString *value = [self objectForKey:key entityName:entity];
    if (!value) {
        return nil;
    }

    NSError *error = nil;
    NSData *data = [NSData dataWithBytes:value.UTF8String length:[value lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    id JSON = [Utils JSONDecode:data error:&error];
    if (error) {
        Warning("json error %@", data);
        JSON = nil;
    }
    return JSON;
}

- (id)getCachedStarredFiles
{
    id JSON = [self getCachedJson:KEY_STARREDFILES entityName:ENTITY_OBJECT];
    if (JSON) {
        [self handleStarredData:JSON];
    }
    return JSON;
}

- (void)setPhotoUploaded:(NSString *)url
{
    [self setValue:@"true" forKey:[self.accountIdentifier stringByAppendingString:url] entityName:ENTITY_UPLOAD_PHOTO];
}

- (BOOL)IsPhotoUploaded:(NSURL *)url
{
    NSString *value = [self objectForKey:[self.accountIdentifier stringByAppendingString:url.absoluteString] entityName:ENTITY_UPLOAD_PHOTO];
    return value != nil;
}

- (void)clearAccountCache
{
    [SeafStorage.sharedObject clearCache];
    [_cacheProvider clearAllCacheInAccount:self.accountIdentifier];
    [SeafAvatar clearCache];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"clearCache" object:nil];
    [self clearUploadCache];
    // CLear old versiond data
    NSString *attrsFile = [[SeafStorage.sharedObject rootPath] stringByAppendingPathComponent:@"uploadfiles.plist"];
    [Utils removeFile:attrsFile];
}

// fileProvider tagData
- (void)saveFileProviderTagData:(NSData*)tagData withItemIdentifier:(NSString*)itemId {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:self.tagDataKey]];
    if (tagData) {
        [dict setObject:tagData forKey:itemId];
    } else {
        [dict removeObjectForKey:itemId];
    }
    
    [SeafStorage.sharedObject setObject:dict forKey:self.tagDataKey];
    // Save to iCloud
    [self performSelectorInBackground:@selector(saveTagDataToICloudWithObject:) withObject:dict];
}

- (void)saveTagDataToICloudWithObject:(id)object{
    NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    [store setObject:object forKey:self.tagDataKey];
    [store synchronize];
}

- (NSData*)loadFileProviderTagDataWithItemIdentifier:(NSString*)itemId {
    NSDictionary *dict = [SeafStorage.sharedObject objectForKey:self.tagDataKey];
    if (dict) {
        return [dict objectForKey:itemId];
    } else {
        return nil;
    }
}

- (void)updateKeyValuePairs:(NSNotification*)notification {
    if ([notification.userInfo objectForKey:NSUbiquitousKeyValueStoreChangeReasonKey]) {
        NSInteger changeReason = [[notification.userInfo objectForKey:NSUbiquitousKeyValueStoreChangeReasonKey] integerValue];
        if (changeReason == NSUbiquitousKeyValueStoreServerChange || changeReason == NSUbiquitousKeyValueStoreInitialSyncChange) {
            NSArray *changeKeys = [notification.userInfo objectForKey:NSUbiquitousKeyValueStoreChangedKeysKey];
            @synchronized (changeKeys) {
                NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
                for (NSString *key in changeKeys) {
                    if ([key isEqualToString:self.tagDataKey]) {
                        NSDictionary *dict = [store objectForKey:key];
                        [SeafStorage.sharedObject setObject:dict forKey:self.tagDataKey];
                    }
                }
            }
        }
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSUbiquitousKeyValueStoreDidChangeExternallyNotification object:[NSUbiquitousKeyValueStore defaultStore]];
}

@end
