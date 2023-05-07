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
#import "SeafBase.h"

#define HTTP_ERR_UNAUTHORIZED                    401
#define HTTP_ERR_LOGIN_INCORRECT_PASSWORD        400
#define HTTP_ERR_REPO_PASSWORD_REQUIRED          440
#define HTTP_ERR_OPERATION_FAILED                520
#define HTTP_ERR_REPO_UPLOAD_PASSWORD_EXPIRED    500
#define HTTP_ERR_REPO_DOWNLOAD_PASSWORD_EXPIRED  400

#define DEFAULT_TIMEOUT 120
#define LARGE_FILE_SIZE 10*1024*1024

#define REPO_LAST_UPDATE_PASSWORD_TIME @"repoLastPasswordUpdateTsMap"

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

@protocol SeafPhotoSyncWatcherDelegate <NSObject>
- (void)photoSyncChanged:(long)remain;
@end

@protocol SeafLoginDelegate <NSObject>
- (void)loginSuccess:(SeafConnection *_Nonnull)connection;
- (void)loginFailed:(SeafConnection *_Nonnull)connection response:(NSHTTPURLResponse *_Nonnull)response error:(NSError *_Nullable)error;
- (BOOL)authorizeInvalidCert:(NSURLProtectionSpace *_Nonnull)protectionSpace;
- (NSData *_Nullable)getClientCertPersistentRef:(NSURLCredential *_Nullable __autoreleasing *_Nullable)credential; // return the persistentRef

@end

@protocol SeafConnectionDelegate <NSObject>
- (void)loginRequired:(SeafConnection *_Nonnull)connection;
- (void)outOfQuota:(SeafConnection *_Nonnull)connection;
@end


@interface SeafConnection: NSObject


@property (readonly, retain) NSMutableDictionary * _Nonnull info;
@property (readwrite, nonatomic, copy) NSString * _Nullable address;
@property (weak) id <SeafLoginDelegate> _Nullable loginDelegate;
@property (weak) id <SeafConnectionDelegate> _Nullable delegate;
@property (strong) SeafRepos *_Nullable rootFolder;
@property (readonly) AFHTTPSessionManager * _Nonnull sessionMgr;
@property (readonly) AFHTTPSessionManager * _Nonnull loginMgr;
@property (nonatomic, readonly) NSString * _Nonnull accountIdentifier;
@property (readonly) NSString * _Nullable username;
@property (readonly) NSString * _Nullable password;
@property (readonly) NSString * _Nullable host;
@property (readonly) BOOL isShibboleth;
@property (readonly) long long quota;
@property (readonly) long long usage;
@property (readonly, strong) NSString* _Nullable token;
@property (readonly) BOOL authorized;
@property (readonly) BOOL isSearchEnabled;
@property (readonly) BOOL isActivityEnabled;
@property (readonly) BOOL isNewActivitiesApiSupported;
@property (readonly) NSData* _Nullable clientIdentityKey;

@property (readwrite, nonatomic, getter=isWifiOnly) BOOL wifiOnly;
@property (readwrite, nonatomic, getter=isAutoSync) BOOL autoSync;
@property (readwrite, nonatomic, getter=isVideoSync) BOOL videoSync;
@property (readwrite, nonatomic, getter=isBackgroundSync) BOOL backgroundSync;
@property (assign, nonatomic) BOOL uploadHeicEnabled;

@property (readwrite, nonatomic) NSString * _Nullable autoSyncRepo;

@property (readwrite, nonatomic) BOOL autoClearRepoPasswd;
@property (readwrite, nonatomic) BOOL localDecryptionEnabled;
@property (readwrite, nonatomic) BOOL touchIdEnabled;
@property (readonly) NSURLCredential *_Nullable clientCred;

@property (weak) id<SeafPhotoSyncWatcherDelegate> _Nullable photSyncWatcher;
@property (readonly) BOOL inAutoSync;

@property (readonly) NSString *_Nullable avatar;


- (id _Nonnull)initWithUrl:(NSString *_Nonnull)url cacheProvider:(id<SeafCacheProvider> _Nullable )cacheProvider;
- (id _Nonnull)initWithUrl:(NSString * _Nonnull)url cacheProvider:(id<SeafCacheProvider> _Nullable )cacheProvider username:(NSString * _Nonnull)username ;

- (void)loadRepos:(id<SeafDentryDelegate> _Nullable)degt;

- (BOOL)localDecrypt;
- (BOOL)isEncrypted:(NSString * _Nonnull)repoId;
- (BOOL)shouldLocalDecrypt:(NSString * _Nonnull)repoId;

- (void)resetUploadedPhotos;
- (void)clearAccount;
- (void)logout;

- (NSUInteger)autoSyncedNum;
- (NSString * _Nonnull)uniqueUploadDir;

- (NSURLRequest * _Nonnull)buildRequest:(NSString * _Nonnull)url method:(NSString * _Nonnull)method form:(NSString *_Nullable)form;

- (void)sendRequest:(NSString * _Nonnull)url
            success:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id _Nonnull JSON))success
            failure:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id _Nullable JSON, NSError * _Nullable error))failure;

- (void)sendDelete:(NSString * _Nonnull)url
           success:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id _Nonnull JSON))success
           failure:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id _Nullable JSON, NSError * _Nullable error))failure;

- (void)sendPut:(NSString * _Nonnull)url form:(NSString * _Nullable)form
        success:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id _Nonnull JSON))success
        failure:(void (^ _Nullable)(NSURLRequest *_Nonnull request, NSHTTPURLResponse * _Nullable response, id _Nullable JSON, NSError * _Nullable error))failure;

- (void)sendPost:(NSString * _Nonnull)url form:(NSString * _Nullable)form
         success:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id _Nonnull JSON))success
         failure:(void (^_Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id _Nullable JSON, NSError * _Nullable error))failure;

- (void)sendOptions:(NSString * _Nonnull)url
            success:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id _Nonnull JSON))success
            failure:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id _Nullable JSON, NSError * _Nullable error))failure;

- (void)loginWithUsername:(NSString * _Nonnull)username password:(NSString * _Nonnull)password;
- (void)loginWithUsername:(NSString * _Nonnull)username password:(NSString * _Nonnull)password otp:(NSString * _Nullable)otp rememberDevice:(BOOL)remember;

-(void)setToken:(NSString * _Nonnull)token forUser:(NSString * _Nonnull)username isShib:(BOOL)isshib s2faToken:(NSString*)s2faToken;

- (void)getAccountInfo:(void (^ _Nullable)(bool result))handler;

- (void)getStarredFiles:(void (^ _Nonnull)(NSHTTPURLResponse *  _Nullable response, id _Nullable JSON))success
                failure:(void (^ _Nonnull)(NSHTTPURLResponse * _Nullable response, NSError * _Nullable error))failure;

- (void)getServerInfo:(void (^ _Nullable)(bool result))handler;

- (void)search:(NSString *_Nonnull)keyword repo:(NSString * _Nonnull)repoId
       success:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id  _Nonnull JSON, NSMutableArray * _Nonnull results))success
       failure:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id _Nullable JSON, NSError * _Nullable error))failure;


- (BOOL)isStarred:(NSString *_Nonnull)repo path:(NSString *_Nonnull)path;

- (BOOL)setStarred:(BOOL)starred repo:(NSString * _Nonnull)repo path:(NSString * _Nonnull)path;

- (SeafRepo * _Nullable)getRepo:(NSString * _Nonnull)repo;

- (void)registerDevice:(NSData * _Nonnull)deviceToken;

- (UIImage * _Nullable)avatarForAccount:(NSString * _Nonnull)email;

// Cache
- (void)clearAccountCache;
- (NSString * _Nullable)objectForKey:(NSString * _Nonnull)key entityName:(NSString * _Nonnull)entity;
- (BOOL)setValue:(NSString * _Nonnull)value forKey:(NSString * _Nonnull)key entityName:(NSString * _Nonnull)entity;
- (void)removeKey:(NSString * _Nonnull)key entityName:(NSString *_Nonnull)entity;
- (long)totalCachedNumForEntity:(NSString * _Nonnull)entity;
- (void)clearCache:(NSString * _Nonnull)entity;

- (id _Nullable)getCachedJson:(NSString * _Nonnull)key entityName:(NSString * _Nonnull)entity;
- (id _Nullable)getCachedStarredFiles;

- (id _Nullable)getAttribute:(NSString * _Nonnull)aKey;
- (void)setAttribute:(id _Nullable )anObject forKey:(NSString * _Nonnull)aKey;

- (void)checkAutoSync;
- (NSUInteger)photosInSyncing;
- (void)checkSyncDst:(SeafDir *_Nonnull)dir;
- (void)photosDidChange:(NSNotification *_Nullable)note;

- (void)saveRepo:(NSString * _Nonnull)repoId password:(NSString * _Nullable)password;
- (void)saveRepo:(NSString *_Nonnull)repoId encInfo:(NSDictionary *_Nonnull)encInfo;
- (NSString * _Nullable)getRepoPassword:(NSString * _Nonnull)repoId;
- (NSDictionary *_Nullable)getRepoEncInfo:(NSString * _Nonnull)repoId;
- (void)downloadDir:(SeafDir * _Nonnull)dir;

- (void)refreshRepoPasswords;
- (void)clearRepoPasswords;
- (NSTimeInterval)getRepoLastRefreshPasswordTime:(NSString *_Nullable)repoId;

// fileProvider tagData
- (void)saveFileProviderTagData:(NSData * _Nullable)tagData withItemIdentifier:(NSString * _Nullable)itemId;
- (NSData * _Nullable)loadFileProviderTagDataWithItemIdentifier:(NSString * _Nullable)itemId;

+ (AFHTTPRequestSerializer <AFURLRequestSerialization> * _Nonnull)requestSerializer;

@end
