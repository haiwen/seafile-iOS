//
//  SeafConnection.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFNetworking.h"

#define HTTP_ERR_LOGIN_REUIRED                  403
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

@protocol SeafDownloadDelegate <NSObject>
- (void)download;
@end

@protocol SSConnectionDelegate <NSObject>
- (void)connectionLinkingSuccess:(SeafConnection *)connection;
- (void)connectionLinkingFailed:(SeafConnection *)connection error:(int)error;
@end

@protocol SSConnectionAccountDelegate <NSObject>
- (void)getAccountInfoResult:(BOOL)result connection:(SeafConnection *)conn;
@end

@interface SeafConnection : NSObject
{
@private
    NSOperationQueue *queue;
}

@property (readonly, retain) NSMutableDictionary *info;
@property (readonly, nonatomic, copy) NSString *address;
@property (weak) id <SSConnectionDelegate> delegate;
@property (strong) SeafRepos *rootFolder;
@property (readonly) NSString *username;
@property (readonly) NSString *password;
@property (readonly) NSString *host;
@property (readonly) long long quota;
@property (readonly) long long usage;
@property (readonly, strong) NSString *token;
@property (readonly) BOOL authorized;
@property (readwrite, nonatomic, getter=isWifiOnly) BOOL wifiOnly;
@property (readwrite, nonatomic, getter=isAutoSync) BOOL autoSync;
@property (readonly) NSArray *seafGroups;
@property (readonly) NSArray *seafContacts;
@property (readwrite) NSMutableArray *seafReplies;
@property (readwrite) long long newmsgnum;


- (id)initWithUrl:(NSString *)url username:(NSString *)username;
- (void)loadRepos:(id)degt;

- (BOOL)localDecrypt:(NSString *)repoId;
- (void)clearAccount;

- (void)sendRequest:(NSString *)url
            success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data))success
            failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure;

- (void)sendDelete:(NSString *)url
           success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data))success
           failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure;

- (void)sendPut:(NSString *)url form:(NSString *)form
        success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data))success
        failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure;

- (void)sendPost:(NSString *)url form:(NSString *)form
         success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data))success
         failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure;

- (void)loginWithAddress:(NSString *)anAddress username:(NSString *)username password:(NSString *)password;

- (void)getAccountInfo:(id<SSConnectionAccountDelegate>)degt;


- (void)getStarredFiles:(void (^)(NSHTTPURLResponse *response, id JSON, NSData *data))success
                failure:(void (^)(NSHTTPURLResponse *response, NSError *error, id JSON))failure;


- (void)getSeafGroupAndContacts:(void (^)(NSHTTPURLResponse *response, id JSON, NSData *data))success
                        failure:(void (^)(NSHTTPURLResponse *response, NSError *error, id JSON))failure;


- (BOOL)isStarred:(NSString *)repo path:(NSString *)path;

- (BOOL)setStarred:(BOOL)starred repo:(NSString *)repo path:(NSString *)path;

- (SeafRepo *)getRepo:(NSString *)repo;

- (SeafUploadFile *)getUploadfile:(NSString *)lpath;
- (void)removeUploadfile:(SeafUploadFile *)ufile;

- (void)search:(NSString *)keyword
       success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSMutableArray *results))success
       failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure;

- (void)registerDevice:(NSData *)deviceToken;

- (void)handleOperation:(AFHTTPRequestOperation *)operation;

- (void)downloadAvatars:(NSNumber *)force;

- (NSString *)nickForEmail:(NSString *)email;
- (NSString *)avatarForEmail:(NSString *)email;
- (NSString *)avatarForGroup:(NSString *)gid;

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

+ (AFHTTPRequestSerializer <AFURLRequestSerialization> *)requestSerializer;

@end
