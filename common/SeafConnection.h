//
//  SeafConnection.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFNetworking.h"

#define HTTP_ERR_UNAUTHORIZED                   401
#define HTTP_ERR_LOGIN_INCORRECT_PASSWORD       400
#define HTTP_ERR_REPO_PASSWORD_REQUIRED         440


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

@protocol SeafDownloadDelegate <NSObject>
- (void)download;
@end


@protocol SeafPhotoSyncWatcherDelegate <NSObject>
- (void)photoSyncChanged:(long)remain;
@end

@protocol SeafLoginDelegate <NSObject>
- (void)loginSuccess:(SeafConnection *)connection;
- (void)loginFailed:(SeafConnection *)connection error:(NSInteger)error;
@end

@protocol SeafConnectionDelegate <NSObject>
- (void)loginRequired:(SeafConnection *)connection;
- (BOOL)continueWithInvalidCert:(NSURLProtectionSpace *)protectionSpace;

@end


@interface SeafConnection : NSObject


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
@property (readwrite, nonatomic, getter=isWifiOnly) BOOL wifiOnly;
@property (readwrite, nonatomic, getter=isAutoSync) BOOL autoSync;
@property (readwrite, nonatomic, getter=isVideoSync) BOOL videoSync;
@property (weak) id<SeafPhotoSyncWatcherDelegate> photSyncWatcher;
@property (readonly) BOOL inAutoSync;
@property (readonly) NSString *avatar;


- (id)init:(NSString *)url;
- (id)initWithUrl:(NSString *)url username:(NSString *)username;
- (void)loadRepos:(id)degt;

- (BOOL)localDecrypt:(NSString *)repoId;
- (void)resetUploadedPhotos;
- (void)clearAccount;

- (NSURLRequest *)buildRequest:(NSString *)url method:(NSString *)method form:(NSString *)form;

- (void)sendRequest:(NSString *)url
            success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
            failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error))failure;

- (void)sendDelete:(NSString *)url
           success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
           failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error))failure;

- (void)sendPut:(NSString *)url form:(NSString *)form
        success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
        failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error))failure;

- (void)sendPost:(NSString *)url form:(NSString *)form
         success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
         failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error))failure;

- (void)loginWithUsername:(NSString *)username password:(NSString *)password;
-(void)setToken:(NSString *)token forUser:(NSString *)username isShib:(BOOL)isshib;

- (void)getAccountInfo:(void (^)(bool result, SeafConnection *conn))handler;

- (void)getStarredFiles:(void (^)(NSHTTPURLResponse *response, id JSON))success
                failure:(void (^)(NSHTTPURLResponse *response, NSError *error))failure;

- (void)search:(NSString *)keyword
       success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSMutableArray *results))success
       failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error))failure;


- (BOOL)isStarred:(NSString *)repo path:(NSString *)path;

- (BOOL)setStarred:(BOOL)starred repo:(NSString *)repo path:(NSString *)path;

- (SeafRepo *)getRepo:(NSString *)repo;

- (SeafUploadFile *)getUploadfile:(NSString *)lpath;
- (SeafUploadFile *)getUploadfile:(NSString *)lpath create:(bool)create;

- (void)removeUploadfile:(SeafUploadFile *)ufile;

- (void)registerDevice:(NSData *)deviceToken;

// Cache
- (void)loadCache;
- (id)getCachedObj:(NSString *)key;
- (id)getCachedTimestamp:(NSString *)key;
- (BOOL)savetoCacheKey:(NSString *)key value:(NSString *)content;
- (id)getCachedStarredFiles;

- (NSString *)getAttribute:(NSString *)aKey;
- (void)setAttribute:(id)anObject forKey:(id < NSCopying >)aKey;

- (void)checkAutoSync;
- (void)pickPhotosForUpload;
- (void)fileUploadedSuccess:(SeafUploadFile *)ufile;

- (NSUInteger)photosInSyncing;
- (void)checkSyncDst:(SeafDir *)dir;
- (void)checkPhotoChanges:(NSNotification *)note;

+ (AFHTTPRequestSerializer <AFURLRequestSerialization> *)requestSerializer;

@end
