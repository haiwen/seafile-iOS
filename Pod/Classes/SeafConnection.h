//
//  SeafConnection.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFNetworking.h"
#import "SeafCacheProvider.h"

#define HTTP_ERR_UNAUTHORIZED                   401
#define HTTP_ERR_LOGIN_INCORRECT_PASSWORD       400
#define HTTP_ERR_REPO_PASSWORD_REQUIRED         440
#define HTTP_ERR_OPERATION_FAILED               520


#define DEFAULT_TIMEOUT 120
#define LARGE_FILE_SIZE 10*1024*1024

enum MSG_TYPE{
    MSG_NONE = 0,
    MSG_GROUP,
    MSG_USER,
    MSG_REPLY,
};
@class SeafConnection;
@class SeafRepos;
@class SeafRepo;
@class SeafUploadFile;
@class SeafDir;

typedef void (^CompletionBlock)(BOOL success, NSError * _Nullable error);

BOOL SeafServerTrustIsValid(SecTrustRef _Nonnull serverTrust);

@protocol SeafDownloadDelegate <NSObject>
- (void)download;
- (NSString *_Nonnull)name;
- (BOOL)retryable;
@end

@protocol SeafPhotoSyncWatcherDelegate <NSObject>
- (void)photoSyncChanged:(long)remain;
@end

@protocol SeafLoginDelegate <NSObject>
- (void)loginSuccess:(SeafConnection *_Nonnull)connection;
- (void)loginFailed:(SeafConnection *_Nonnull)connection response:(NSURLResponse *_Nonnull)response error:(NSError *_Nullable)error;
- (BOOL)authorizeInvalidCert:(NSURLProtectionSpace *_Nonnull)protectionSpace;
- (NSData *_Nullable)getClientCertPersistentRef:(NSURLCredential * _Nonnull __autoreleasing *)credential; // return the persistentRef

@end

@protocol SeafConnectionDelegate <NSObject>
- (void)loginRequired:(SeafConnection *)connection;
- (void)outOfQuota:(SeafConnection *)connection;
@end


@interface SeafConnection: NSObject


@property (readonly, retain) NSMutableDictionary *info;
@property (readwrite, nonatomic, copy) NSString *address;
@property (weak) id <SeafLoginDelegate> loginDelegate;
@property (weak) id <SeafConnectionDelegate> delegate;
@property (strong) SeafRepos *rootFolder;
@property (readonly) AFHTTPSessionManager *sessionMgr;
@property (readonly) AFHTTPSessionManager *loginMgr;
@property (readonly) NSString *username;
@property (readonly) NSString *password;
@property (readonly) NSString *host;
@property (readonly) BOOL isShibboleth;
@property (readonly) long long quota;
@property (readonly) long long usage;
@property (readonly, strong) NSString *token;
@property (readonly) BOOL authorized;
@property (readonly) BOOL isSearchEnabled;
@property (readonly) BOOL isActivityEnabled;
@property (readonly) BOOL isChunkSupported; // upload/download by blocks
@property (readonly) NSData* clientIdentityKey;

@property (readwrite, nonatomic, getter=isWifiOnly) BOOL wifiOnly;
@property (readwrite, nonatomic, getter=isAutoSync) BOOL autoSync;
@property (readwrite, nonatomic, getter=isVideoSync) BOOL videoSync;
@property (readwrite, nonatomic, getter=isBackgroundSync) BOOL backgroundSync;
@property (readwrite, nonatomic, getter=isContactsSync) BOOL contactsSync;

@property (readwrite, nonatomic) NSString *autoSyncRepo;
@property (readwrite, nonatomic) NSString *contactsRepo;

@property (readwrite, nonatomic) BOOL autoClearRepoPasswd;
@property (readwrite, nonatomic) BOOL localDecryption;
@property (readwrite, nonatomic) BOOL touchIdEnabled;
@property (readonly) NSURLCredential *clientCred;

@property (weak) id<SeafPhotoSyncWatcherDelegate> photSyncWatcher;
@property (readonly) BOOL inAutoSync;

@property (readonly) NSString *avatar;


- (id)initWithUrl:(NSString *)url cacheProvider:(id<SeafCacheProvider>)cacheProvider;
- (id)initWithUrl:(NSString *)url cacheProvider:(id<SeafCacheProvider>)cacheProvider username:(NSString *)username ;

- (void)loadRepos:(id)degt;

- (BOOL)localDecrypt:(NSString *)repoId;
- (BOOL)isEncrypted:(NSString *)repoId;

- (void)resetUploadedPhotos;
- (void)clearAccount;
- (void)logout;

- (NSUInteger)autoSyncedNum;

- (NSURLRequest *)buildRequest:(NSString *)url method:(NSString *)method form:(NSString *)form;

- (void)sendRequest:(NSString *)url
            success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
            failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error))failure;

- (void)sendDelete:(NSString *)url
           success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
           failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error))failure;

- (void)sendPut:(NSString *)url form:(NSString *)form
        success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
        failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error))failure;

- (void)sendPost:(NSString *)url form:(NSString *)form
         success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
         failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error))failure;

- (void)sendOptions:(NSString *)url
            success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
            failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error))failure;

- (void)loginWithUsername:(NSString *)username password:(NSString *)password;
- (void)loginWithUsername:(NSString *)username password:(NSString *)password otp:(NSString *)otp;

-(void)setToken:(NSString *)token forUser:(NSString *)username isShib:(BOOL)isshib;

- (void)getAccountInfo:(void (^)(bool result))handler;

- (void)getStarredFiles:(void (^)(NSHTTPURLResponse *response, id JSON))success
                failure:(void (^)(NSHTTPURLResponse *response, NSError *error))failure;

- (void)getServerInfo:(void (^)(bool result))handler;

- (void)search:(NSString *)keyword repo:(NSString *)repoId
       success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSMutableArray *results))success
       failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error))failure;


- (BOOL)isStarred:(NSString *)repo path:(NSString *)path;

- (BOOL)setStarred:(BOOL)starred repo:(NSString *)repo path:(NSString *)path;

- (SeafRepo *)getRepo:(NSString *)repo;

- (SeafUploadFile *)getUploadfile:(NSString *)lpath;
- (SeafUploadFile *)getUploadfile:(NSString *)lpath create:(bool)create;

- (void)removeUploadfile:(SeafUploadFile *)ufile;

- (void)registerDevice:(NSData *)deviceToken;

- (UIImage *)avatarForAccount:(NSString *)email;

// Cache
- (void)clearAccountCache;
- (NSString *)objectForKey:(NSString *)key entityName:(NSString *)entity;
- (BOOL)setValue:(NSString *)value forKey:(NSString *)key entityName:(NSString *)entity;
- (void)removeKey:(NSString *)key entityName:(NSString *)entity;
- (long)totalCachedNumForEntity:(NSString *)entity;
- (void)clearCache:(NSString *)entity;

- (id)getCachedJson:(NSString *)key entityName:(NSString *)entity;
- (id)getCachedStarredFiles;

- (id)getAttribute:(NSString *)aKey;
- (void)setAttribute:(id)anObject forKey:(NSString *)aKey;

- (void)checkAutoSync;
- (NSUInteger)photosInSyncing;
- (void)checkSyncDst:(SeafDir *)dir;
- (void)photosDidChange:(NSNotification *)note;
- (void)contactStoreDidChange:(NSNotification *)notification;
- (NSString *)backupContacts:(BOOL)force completion:(CompletionBlock)completionHandler;
- (void)restoreContacts:(void(^)(BOOL success, NSError *error))completionHandler;
- (void)getContactsLastBackTime:(void(^)(BOOL success, NSString *dateStr))completionHandler;

- (void)setRepo:(NSString *)repoId password:(NSString *)password;
- (NSString *)getRepoPassword:(NSString *)repoId;
- (void)downloadDir:(SeafDir *)dir;

- (void)refreshRepoPassowrds;
- (void)clearRepoPasswords;

+ (AFHTTPRequestSerializer <AFURLRequestSerialization> *)requestSerializer;

@end
