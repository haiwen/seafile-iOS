//
//  SeafConnection.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//
#import <AssertMacros.h>

#import "SeafConnection.h"
#import "SeafRepos.h"
#import "SeafDir.h"
#import "SeafData.h"
#import "SeafAvatar.h"
#import "SeafUploadFile.h"
#import "SeafFile.h"
#import "SeafGlobal.h"

#import "ExtentedString.h"
#import "NSData+Encryption.h"
#import "Debug.h"
#import "Utils.h"

enum {
    FLAG_LOCAL_DECRYPT = 0x1,
};

#define CAMERA_UPLOADS_DIR @"Camera Uploads"
#define KEY_STARREDFILES @"STARREDFILES"
#define KEY_CONTACTS @"CONTACTS"

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
@property NSMutableDictionary *uploadFiles;
@property AFSecurityPolicy *policy;
@property NSDate *avatarLastUpdate;
@property NSMutableDictionary *settings;

@property BOOL inCheckPhotoss;
@property BOOL inCheckCert;

@property NSMutableArray *photosArray;
@property NSMutableArray *uploadingArray;
@property SeafDir *syncDir;
@property (readonly) NSString *localUploadDir;
@property NSURLCredential *clientCred;
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

- (id)init:(NSString *)url
{
    if (self = [super init]) {
        self.address = url;
        _rootFolder = [[SeafRepos alloc] initWithConnection:self];
        self.uploadFiles = [[NSMutableDictionary alloc] init];
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
    }
    return self;
}

- (id)initWithUrl:(NSString *)url username:(NSString *)username
{
    self = [self init:url];
    if (url) {
        NSDictionary *ainfo = [SeafGlobal.sharedObject objectForKey:[NSString stringWithFormat:@"%@/%@", url, username]];
        if (ainfo) {
            _info = [ainfo mutableCopy];
            _token = [_info objectForKey:@"token"];
        } else {
            ainfo = [SeafGlobal.sharedObject objectForKey:url];
            if (ainfo) {
                _info = [ainfo mutableCopy];
                [SeafGlobal.sharedObject removeObjectForKey:url];
                [SeafGlobal.sharedObject setObject:ainfo forKey:[NSString stringWithFormat:@"%@/%@", url, username]];
                [SeafGlobal.sharedObject synchronize];
            }
        }

        NSDictionary *settings = [SeafGlobal.sharedObject objectForKey:[NSString stringWithFormat:@"%@/%@/settings", url, username]];
        if (settings)
            _settings = [settings mutableCopy];
        else
            _settings = [[NSMutableDictionary alloc] init];
    }
    id clientIdentityKey = [_info objectForKey:@"identity"];
    if (clientIdentityKey) {
        self.clientCred = [SeafGlobal.sharedObject getCredentialForKey:clientIdentityKey];
        Debug("Load client dentit");
    }

    if (self.authorized && ![self serverInfo]) {
        [self getServerInfo:^(bool result) {}];
    }
    if (self.autoClearRepoPasswd) {
        Debug("Clear repo apsswords for %@ %@", url, username);
        [self clearRepoPasswords];
    }
    if (self.autoSync)
        [_rootFolder loadContent:NO];
    return self;
}

- (NSString *)localUploadDir
{
    if (!_localUploadDir) {
        _localUploadDir = [self getAttribute:@"UPLOAD_CACHE_DIR"];
        if (!_localUploadDir) {
            _localUploadDir = [SeafGlobal.sharedObject uniqueUploadDir];
            [self setAttribute:_localUploadDir forKey:@"UPLOAD_CACHE_DIR"];
        }
        [Utils checkMakeDir:_localUploadDir];
    }

    return _localUploadDir;
}

- (void)saveSettings
{
    [SeafGlobal.sharedObject setObject:_settings forKey:[NSString stringWithFormat:@"%@/%@/settings", _address, self.username]];
    [SeafGlobal.sharedObject synchronize];
}

- (void)setAttribute:(id)anObject forKey:(NSString *)aKey
{
    [Utils dict:_settings setObject:anObject forKey:aKey];
    [self saveSettings];
}

- (NSString *)getAttribute:(NSString *)aKey
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

- (BOOL)autoClearRepoPasswd
{
    return [[self getAttribute:@"autoClearRepoPasswd"] booleanValue:false];
}

- (BOOL)localDecryption
{
    return [[self getAttribute:@"localDecryption"] booleanValue:false];
}

- (void)setLocalDecryption:(BOOL)localDecryption
{
    if (self.localDecryption == localDecryption) return;
    [self setAttribute:[NSNumber numberWithBool:localDecryption] forKey:@"localDecryption"];
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
}

- (void)setVideoSync:(BOOL)videoSync
{
    if (self.isVideoSync == videoSync) return;
    [self setAttribute:[NSNumber numberWithBool:videoSync] forKey:@"videoSync"];
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

- (NSString *)autoSyncRepo
{
    return [[self getAttribute:@"autoSyncRepo"] stringValue];
}

- (void)setAutoSyncRepo:(NSString *)repoId
{
    _syncDir = nil;
    [self setAttribute:repoId forKey:@"autoSyncRepo"];
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
- (NSString *)host
{
    return [self hostForUrl:self.address];
}

- (NSString *)certPathForHost:(NSString *)host
{
    NSString *filename = [NSString stringWithFormat:@"%@.cer", host];
    NSString *path = [SeafGlobal.sharedObject.certsDir stringByAppendingPathComponent:filename];
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
- (void)setRepo:(NSString *)repoId password:(NSString *)password
{
    Debug("set repo %@ password %@", repoId, password);
    NSMutableDictionary *repopasswds = [NSMutableDictionary dictionaryWithDictionary:(NSDictionary*)[_info objectForKey:@"repopassword"]];
    if (!repopasswds) {
        repopasswds = [[NSMutableDictionary alloc] init];
    }
    [Utils dict:repopasswds setObject:password forKey:repoId];
    [Utils dict:_info setObject:repopasswds forKey:@"repopassword"];
    [self saveAccountInfo];
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
            if (SeafGlobal.sharedObject.allowInvalidCert) return NSURLSessionAuthChallengeUseCredential;

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
            id key = [self.loginDelegate getClientCertPersistentRef:credential];
            if (key == nil){
                return NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            } else {
                self.clientCred = *credential;
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
            if (SeafGlobal.sharedObject.allowInvalidCert) return NSURLSessionAuthChallengeUseCredential;
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

- (BOOL)localDecrypt:(NSString *)repoId
{
    if (!self.localDecryption)
        return false;
    SeafRepo *repo = [self getRepo:repoId];
    return [repo canLocalDecrypt];
}

- (BOOL)isEncrypted:(NSString *)repoId
{
    SeafRepo *repo = [self getRepo:repoId];
    return repo.encrypted;
}

- (void)clearUploadCache
{
    if (_localUploadDir) {
        [Utils clearAllFiles:_localUploadDir];
        [[NSFileManager defaultManager] removeItemAtPath:_localUploadDir error:nil];
        _localUploadDir = nil;
    }
}
- (void)logout
{
    _token = nil;
    [_info removeObjectForKey:@"token"];
    [_info removeObjectForKey:@"password"];
    [_info removeObjectForKey:@"repopassword"];
    [self saveSettings];
}

- (void)clearAccount
{
    [SeafGlobal.sharedObject removeObjectForKey:_address];
    [SeafGlobal.sharedObject removeObjectForKey:[NSString stringWithFormat:@"%@/%@", _address, self.username]];
    [SeafGlobal.sharedObject synchronize];
    NSString *path = [self certPathForHost:[self host]];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    [SeafAvatar clearCache];
    [self clearUploadCache];
}

- (void)saveAccountInfo
{
    [SeafGlobal.sharedObject setObject:_info forKey:[NSString stringWithFormat:@"%@/%@", _address, self.username]];
    [SeafGlobal.sharedObject synchronize];

}
- (void)getAccountInfo:(void (^)(bool result))handler
{
    [self sendRequest:API_URL"/account/info/"
              success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         NSDictionary *account = JSON;
         Debug("account detail:%@", account);
         NSString *oldUsername = self.username;
         NSString *newUsername = [account objectForKey:@"email"];
         [Utils dict:_info setObject:[account objectForKey:@"total"] forKey:@"total"];
         [Utils dict:_info setObject:[account objectForKey:@"total"] forKey:@"total"];
         [Utils dict:_info setObject:[account objectForKey:@"usage"] forKey:@"usage"];
         [Utils dict:_info setObject:_address forKey:@"link"];
         if (![oldUsername isEqualToString:newUsername]) {
             [SeafGlobal.sharedObject removeObjectForKey:[NSString stringWithFormat:@"%@/%@", _address, self.username]];
             [Utils dict:_info setObject:newUsername forKey:@"username"];
         }
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
    NSString *version = [infoDictionary objectForKey:@"CFBundleVersion"];
    NSString *platform = @"ios";
    NSString *platformName = [infoDictionary objectForKey:@"DTPlatformName"];
    NSString *platformVersion = [infoDictionary objectForKey:@"DTPlatformVersion"];
    NSString *deviceID = [UIDevice currentDevice].identifierForVendor.UUIDString;
    NSString *deviceName = UIDevice.currentDevice.name;

    NSString *formString = [NSString stringWithFormat:@"username=%@&password=%@&platform=%@&platformName=%@&device_id=%@&device_name=%@&client_version=%@&platform_version=%@", username.escapedPostForm, password.escapedPostForm, platform.escapedPostForm, platformName.escapedPostForm, deviceID.escapedPostForm, deviceName.escapedPostForm, version.escapedPostForm, platformVersion.escapedPostForm];
    [request setHTTPBody:[NSData dataWithBytes:formString.UTF8String length:[formString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]]];
    return request;
}

-(void)setToken:(NSString *)token forUser:(NSString *)username isShib:(BOOL)isshib
{
    _token = token;
    [Utils dict:_info setObject:username forKey:@"username"];
    [Utils dict:_info setObject:token forKey:@"token"];
    [Utils dict:_info setObject:_address forKey:@"link"];
    [Utils dict:_info setObject:[NSNumber numberWithBool:isshib] forKey:@"isshibboleth"];
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
- (void)loginWithUsername:(NSString *)username password:(NSString *)password otp:(NSString *)otp
{
    NSString *url = _address;
    NSMutableURLRequest *request = [self loginRequest:url username:username password:password];
    if (otp)
        [request setValue:otp forHTTPHeaderField:@"X-Seafile-OTP"];
    AFHTTPSessionManager *manager = self.loginMgr;
    manager.responseSerializer = [AFJSONResponseSerializer serializer];

    Debug("Login: %@ %@", url, username);
    NSURLSessionDataTask *dataTask = [manager dataTaskWithRequest:request completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
        if (error) {
            Warning("Error: %@, response:%@", error, responseObject);
            [self showDeserializedError:error];
            [self.loginDelegate loginFailed:self response:response error:error];
        } else {
            [Utils dict:_info setObject:password forKey:@"password"];
            [self setToken:[responseObject objectForKey:@"token"] forUser:username isShib:false];
        }
    }];

    [dataTask resume];
}

- (void)loginWithUsername:(NSString *)username password:(NSString *)password
{
    [self loginWithUsername:username password:password otp:nil];
}

- (NSURLRequest *)buildRequest:(NSString *)url method:(NSString *)method form:(NSString *)form
{
    NSString *absoluteUrl = [url hasPrefix:@"http"] ? url : [_address stringByAppendingString:url];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:absoluteUrl]];
    [request setValue:SeafGlobal.sharedObject.clientVersion forHTTPHeaderField:@"X-Seafile-Client-Version"];
    [request setValue:SeafGlobal.sharedObject.platformVersion forHTTPHeaderField:@"X-Seafile-Platform-Version"];

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
            Warning("token=%@, resp=%@, delegate=%@, url=%@, Error: %@", _token, responseObject, self.delegate, url, error);
            failure (request, resp, responseObject, error);
            if (resp.statusCode == HTTP_ERR_UNAUTHORIZED) {
                NSString *wiped = [resp.allHeaderFields objectForKey:@"X-Seafile-Wiped"];
                Debug("wiped: %@", wiped);
                @synchronized(self) {
                    if (![self authorized])   return;
                    _token = nil;
                    [_info removeObjectForKey:@"token"];
                    [self saveAccountInfo];
                    if (wiped)
                        [SeafGlobal.sharedObject clearCache];
                }
                if (self.delegate) [self.delegate loginRequired:self];
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

- (void)loadRepos:(id)degt
{
    _rootFolder.delegate = degt;
    [_rootFolder loadContent:NO];
}

#pragma - Cache managerment
- (SeafCacheObj *)loadSeafCacheObj:(NSString *)key
{
    NSManagedObjectContext *context = SeafGlobal.sharedObject.managedObjectContext;
    NSFetchRequest *fetchRequest=[[NSFetchRequest alloc] init];
    [fetchRequest setEntity:[NSEntityDescription entityForName:@"SeafCacheObj" inManagedObjectContext:context]];
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"url" ascending:YES selector:nil];
    NSArray *descriptor = [NSArray arrayWithObject:sortDescriptor];
    [fetchRequest setSortDescriptors:descriptor];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"url==%@ AND username==%@ AND key==%@", self.address, self.username, key]];
    NSFetchedResultsController *controller = [[NSFetchedResultsController alloc]
                                              initWithFetchRequest:fetchRequest
                                              managedObjectContext:context
                                              sectionNameKeyPath:nil
                                              cacheName:nil];
    NSError *error;
    if (![controller performFetch:&error]) {
        Warning("Fetch cache error %@",[error localizedDescription]);
        return nil;
    }
    NSArray *results = [controller fetchedObjects];
    if ([results count] == 0) {
        return nil;
    }
    return [results objectAtIndex:0];
}

- (BOOL)savetoCacheKey:(NSString *)key value:(NSString *)content
{
    NSManagedObjectContext *context = [[SeafGlobal sharedObject] managedObjectContext];
    SeafCacheObj *obj = [self loadSeafCacheObj:key];
    if (!obj) {
        obj = (SeafCacheObj *)[NSEntityDescription insertNewObjectForEntityForName:@"SeafCacheObj" inManagedObjectContext:context];
        obj.timestamp = [NSDate date];
        obj.key = key;
        obj.url = self.address;
        obj.content = content;
        obj.username = self.username;
    } else {
        obj.content = content;
    }
    [[SeafGlobal sharedObject] saveContext];
    return YES;
}

- (id)getCachedObj:(NSString *)key
{
    SeafCacheObj *obj = [self loadSeafCacheObj:key];
    if (!obj) return nil;

    NSError *error = nil;
    NSData *data = [NSData dataWithBytes:obj.content.UTF8String length:[obj.content lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    id JSON = [Utils JSONDecode:data error:&error];
    if (error) {
        Warning("json error %@", data);
        NSManagedObjectContext *context = [[SeafGlobal sharedObject] managedObjectContext];
        [context deleteObject:obj];
        JSON = nil;
    }
    return JSON;
}

- (id)getCachedTimestamp:(NSString *)key
{
    SeafCacheObj *obj = [self loadSeafCacheObj:key];
    if (!obj) return nil;
    return obj.timestamp;
}

- (id)getCachedStarredFiles
{
    return [self getCachedObj:KEY_STARREDFILES];
}

- (void)handleStarredData:(id)JSON
{
    NSMutableSet *stars = [NSMutableSet set];
    for (NSDictionary *info in JSON) {
        [stars addObject:[NSString stringWithFormat:@"%@-%@", [info objectForKey:@"repo"], [info objectForKey:@"path"]]];
    }
    _starredFiles = stars;
}

- (void)loadCache
{
    [self handleStarredData:[self getCachedObj:KEY_STARREDFILES]];
}

- (void)getStarredFiles:(void (^)(NSHTTPURLResponse *response, id JSON))success
                failure:(void (^)(NSHTTPURLResponse *response, NSError *error))failure
{
    [self sendRequest:API_URL"/starredfiles/"
              success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         @synchronized(self) {
             Debug("Success to get starred files ...\n");
             [self handleStarredData:JSON];
             NSData *data = [Utils JSONEncode:JSON];
             [self savetoCacheKey:KEY_STARREDFILES value:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
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
             Debug("Success to get server info: %@\n", JSON);
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
             Debug("Success to star file %@, %@\n", repo, path);
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
             Debug("Success to unstar file %@, %@\n", repo, path);
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

- (SeafUploadFile *)getUploadfile:(NSString *)lpath create:(bool)create
{
    if (!lpath) return nil;
    @synchronized(self.uploadFiles) {
        SeafUploadFile *ufile = [self.uploadFiles objectForKey:lpath];
        if (!ufile && create) {
            ufile = [[SeafUploadFile alloc] initWithPath:lpath];
            [Utils dict:self.uploadFiles setObject:ufile forKey:lpath];
        }
        return ufile;
    };
}

- (SeafUploadFile *)getUploadfile:(NSString *)lpath
{
    return [self getUploadfile:lpath create:true];
}

- (void)removeUploadfile:(SeafUploadFile *)ufile
{
    @synchronized(self.uploadFiles) {
        [self.uploadFiles removeObjectForKey:ufile.lpath];
    }
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
            if ([[itemInfo objectForKey:@"is_dir"] integerValue]) continue;
            NSString *oid = [itemInfo objectForKey:@"oid"];
            NSString *repoId = [itemInfo objectForKey:@"repo_id"];
            NSString *name = [itemInfo objectForKey:@"name"];
            NSString *path = [itemInfo objectForKey:@"fullpath"];
            SeafFile *file = [[SeafFile alloc] initWithConnection:self oid:oid repoId:repoId name:name path:path mtime:[[itemInfo objectForKey:@"last_modified"] integerValue:0] size:[[itemInfo objectForKey:@"size"] integerValue:0]];
            [results addObject:file];
        }
        success(request, response, JSON, results);
    } failure:failure];
}

- (void)registerDevice:(NSData *)deviceToken
{
#if 0
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDictionary objectForKey:@"CFBundleVersion"];
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
#ifdef SEAFILE_APP
    [self downloadAvatar:false];
#endif
    return [[NSBundle mainBundle] pathForResource:@"account" ofType:@"png"];
}

- (UIImage *)avatarForAccount:(NSString *)email
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"account" ofType:@"png"];
    return [UIImage imageWithContentsOfFile:path];
}

- (void)downloadAvatar:(BOOL)force;
{
    Debug("%@, %d\n", self.address, [self authorized]);
    if (![self authorized])
        return;
    if (!force && self.realAvatar && [self.avatarLastUpdate timeIntervalSinceNow] > -24*3600)
        return;
    if (!force && [self.avatarLastUpdate timeIntervalSinceNow] > -300.0f)
        return;
    SeafUserAvatar *avatar = [[SeafUserAvatar alloc] initWithConnection:self username:self.username];
    [SeafGlobal.sharedObject addDownloadTask:avatar];
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
        [SeafGlobal.sharedObject assetForURL:url
                                 resultBlock:^(ALAsset *asset) {
                                     NSString *filename = asset.defaultRepresentation.filename;
                                     if (!filename) {
                                         [self removeUploadingPhoto:url];
                                         return Warning("Failed to get asset name: %@", asset);
                                     }
                                     NSString *path = [self.localUploadDir stringByAppendingPathComponent:filename];
                                     SeafUploadFile *file = [self getUploadfile:path];
                                     if (!file) {
                                         [self removeUploadingPhoto:url];
                                         return Warning("Failed to init upload file: %@", path);
                                     }
                                     file.autoSync = true;
                                     [file setAsset:asset url:url];
                                     file.udir = dir;
                                     Debug("Add file %@ to upload list: %@ current %u %u", filename, dir.path, (unsigned)_photosArray.count, (unsigned)_uploadingArray.count);
                                     [SeafGlobal.sharedObject addUploadTask:file];
                                 }
                                failureBlock:^(NSError *error){
                                    Debug("!!!!Can not find asset:%@ !", url);
                                    [self removeUploadingPhoto:url];
                                }];
    }
}

- (void)fileUploadedSuccess:(SeafUploadFile *)ufile
{
    if (!_inAutoSync) return;
    if (!ufile || !ufile.assetURL || !ufile.autoSync) return;
    NSManagedObjectContext *context = [[SeafGlobal sharedObject] managedObjectContext];
    UploadedPhotos *obj = (UploadedPhotos *)[NSEntityDescription insertNewObjectForEntityForName:@"UploadedPhotos" inManagedObjectContext:context];
    obj.server = self.address;
    obj.username = self.username;
    obj.url = ufile.assetURL.absoluteString;
    [[SeafGlobal sharedObject] saveContext];
    [self removeUploadingPhoto:ufile.assetURL];
    Debug("Autosync file %@ %@ uploaded %d, remain %u %u", ufile.name, ufile.assetURL, [self IsPhotoUploaded:ufile.assetURL], (unsigned)_photosArray.count, (unsigned)_uploadingArray.count);

    if (!ufile.delegate) [ufile.udir removeUploadFile:ufile];
    if (_photSyncWatcher) [_photSyncWatcher photoSyncChanged:self.photosInSyncing];
}

- (BOOL)IsPhotoUploaded:(NSURL *)url
{
    NSManagedObjectContext *context = [[SeafGlobal sharedObject] managedObjectContext];
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    [fetchRequest setEntity:[NSEntityDescription entityForName:@"UploadedPhotos" inManagedObjectContext:context]];
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"url" ascending:YES selector:nil];
    NSArray *descriptor = [NSArray arrayWithObject:sortDescriptor];
    [fetchRequest setSortDescriptors:descriptor];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"server==%@ AND username==%@ AND url==%@", self.address, self.username, url.absoluteString]];
    NSFetchedResultsController *controller = [[NSFetchedResultsController alloc]
                                              initWithFetchRequest:fetchRequest
                                              managedObjectContext:context
                                              sectionNameKeyPath:nil
                                              cacheName:nil];
    NSError *error;
    if (![controller performFetch:&error]) {
        Warning("error: %@", error);
        return NO;
    }
    NSArray *results = [controller fetchedObjects];
    return results.count > 0;
}

- (NSUInteger)autoSyncedNum
{
    NSManagedObjectContext *context = [[SeafGlobal sharedObject] managedObjectContext];
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    [request setEntity:[NSEntityDescription entityForName:@"UploadedPhotos" inManagedObjectContext:context]];
    [request setIncludesSubentities:NO];
    [request setPredicate:[NSPredicate predicateWithFormat:@"server==%@ AND username==%@", self.address, self.username]];

    NSError *err;
    NSUInteger count = [context countForFetchRequest:request error:&err];
    if(count == NSNotFound) {
        Warning("Failed to fet synced count");
        return 0;
    }

    return count;
}
- (void)resetUploadedPhotos
{
    self.uploadFiles = [[NSMutableDictionary alloc] init];
    _uploadingArray = [[NSMutableArray alloc] init];
    NSManagedObjectContext *context = [[SeafGlobal sharedObject] managedObjectContext];
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    [fetchRequest setEntity:[NSEntityDescription entityForName:@"UploadedPhotos" inManagedObjectContext:context]];
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"url" ascending:YES selector:nil];
    NSArray *descriptor = [NSArray arrayWithObject:sortDescriptor];
    [fetchRequest setSortDescriptors:descriptor];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"server==%@ AND username==%@", self.address, self.username]];
    NSFetchedResultsController *controller = [[NSFetchedResultsController alloc]
                                              initWithFetchRequest:fetchRequest
                                              managedObjectContext:context
                                              sectionNameKeyPath:nil
                                              cacheName:nil];
    NSError *error;
    if ([controller performFetch:&error]) {
        for (id obj in controller.fetchedObjects) {
             [context deleteObject:obj];
        }
    }
    [[SeafGlobal sharedObject] saveContext];
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
    @synchronized(_photosArray) {
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
    NSURL *url = (NSURL*)asset.defaultRepresentation.url;
    if ([self IsPhotoUploaded:url] || [self IsPhotoUploading:url])
        return nil;

    if([[asset valueForProperty:ALAssetPropertyType] isEqualToString:ALAssetTypePhoto])
        return url;

    if(self.isVideoSync && [[asset valueForProperty:ALAssetPropertyType] isEqualToString:ALAssetTypeVideo])
        return url;
    return nil;
}

- (void)checkPhotos
{
    if (!_inAutoSync) return;
    @synchronized(self) {
        if (_inCheckPhotoss) return;
        _inCheckPhotoss = true;
    }

    Debug("Check photos for server %@, current %u %u", _address, (unsigned)_photosArray.count, (unsigned)_uploadingArray.count);
    if (!self.videoSync) [self clearUploadingVideos];

    NSMutableArray *photos = [[NSMutableArray alloc] init];
    void (^assetEnumerator)(ALAsset *, NSUInteger, BOOL *) = ^(ALAsset *asset, NSUInteger index, BOOL *stop) {
        NSURL *url = [self uploadURLForAsset:asset];
        if (url)
            [photos addObject:url];
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
            Debug("GroupAll Total %ld photos need to upload: %@", (long)_photosArray.count, _address);
            if (_photSyncWatcher) [_photSyncWatcher photoSyncChanged:self.photosInSyncing];
            _inCheckPhotoss = false;
            [self pickPhotosForUpload];
        }
    };
    [[[SeafGlobal sharedObject] assetsLibrary] enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos
                                                   usingBlock:assetGroupEnumerator
                                                 failureBlock:^(NSError *error) {
                                                     Debug("There is an error: %@", error);
                                                     _inCheckPhotoss = false;
                                                 }];
}

- (SeafDir *)getCameraUploadDir:(SeafDir *)dir
{
    SeafDir *uploadDir = nil;
    for (SeafBase *obj in dir.items) {
        if ([obj isKindOfClass:[SeafDir class]] && [obj.name isEqualToString:CAMERA_UPLOADS_DIR]) {
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
    [self checkPhotos];
}

- (void)checkUploadDir
{
    NSString *autoSyncRepo = self.autoSyncRepo;
    SeafRepo *repo = [self getRepo:autoSyncRepo];
    if (!repo) {
        Warning("No repo %@", self.autoSyncRepo);
        [_rootFolder loadContent:NO];
        _syncDir = nil;
        return;
    }
    [repo loadContent:NO];
    SeafDir *uploadDir = [self getCameraUploadDir:repo];
    if (uploadDir) {
        return [self updateUploadDir:uploadDir];
    }

    [repo downloadContentSuccess:^(SeafDir *rdir) {
        SeafDir *uploadDir = [self getCameraUploadDir:rdir];
        if (uploadDir) {
            return [self updateUploadDir:uploadDir];
        } else {
            [repo mkdir:CAMERA_UPLOADS_DIR success:^(SeafDir *dir) {
                SeafDir *uploadDir = [self getCameraUploadDir:dir];
                [self updateUploadDir:uploadDir];
            } failure:^(SeafDir *dir) {
                Warning("Failed to create %@", CAMERA_UPLOADS_DIR);
                _syncDir = nil;
            }];
        }
    } failure:^(SeafDir *dir) {
        Warning("Failed to get repo file list: %@", dir.repoId);
        _syncDir = nil;
    }];
}

- (void)photosChanged:(NSNotification *)note
{
    if (!_inAutoSync)
        return;
    Debug("photos changed %d for server %@, current: %u %u", _inAutoSync, _address, (unsigned)_photosArray.count, (unsigned)_uploadingArray.count);
    if (!_syncDir) {
        Warning("Sync dir not exists, create.");
        [self checkUploadDir];
    }
    [self checkPhotos];
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
            [SeafGlobal.sharedObject clearAutoSyncPhotos:self];
            [self clearUploadCache];
        }
    }
    _inAutoSync = value;
    if (_inAutoSync) {
        Debug("start auto sync, check photos for server %@", _address);
        [self checkUploadDir];
    }
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
    [SeafGlobal.sharedObject clearAutoSyncVideos:self];
    [self removeVideosFromArray:_photosArray];
    [self removeVideosFromArray:_uploadingArray];
}

- (void)downloadDir:(SeafDir *)dir
{
    [dir downloadContentSuccess:^(SeafDir *dir) {
        Debug("dir %@ items: %lu", dir.path, (unsigned long)dir.items.count);
        long delay = 1;
        for (SeafBase *item in dir.items) {
            delay += 1;
            if ([item isKindOfClass:[SeafFile class]]) {
                SeafFile *file = (SeafFile *)item;
                Debug("download file: %@, %@ after %ld ms", item.repoId, item.path, delay);
                [SeafGlobal.sharedObject performSelector:@selector(addDownloadTask:) withObject:file afterDelay:delay];
            } else if ([item isKindOfClass:[SeafDir class]]) {
                Debug("download dir: %@, %@ after %ld ms", item.repoId, item.path, delay);
                [self performSelector:@selector(downloadDir:) withObject:(SeafDir *)item afterDelay:delay];
            }
        }
    } failure:^(SeafDir *dir) {
        Warning("Failed to download dir: %@ %@", dir.repoId, dir.path);
    }];
}

- (void)refreshRepoPassowrds
{
     NSDictionary *repopasswds = [_info objectForKey:@"repopassword"];
    if (repopasswds == nil)
        return;
    for (NSString *key in repopasswds) {
        NSString *repoId = key;
        Debug("refresh repo %@ password", repoId);
        SeafRepo *repo = [self getRepo:repoId];
        if (!repo) continue;
        id block = ^(SeafBase *entry, int ret) {
            if (ret == RET_WRONG_PASSWORD) {
                Debug("Repo password incorrect, clear password.");
                [self setRepo:repoId password:nil];
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
    [self saveAccountInfo];
}

@end
