//
//  SeafBase.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafBase.h"
#import "SeafBaseModel.h"
#import "SeafRepos.h"
#import "SeafConnection.h"

#import "ExtentedString.h"
#import "UIImage+FileType.h"
#import "NSData+Encryption.h"
#import "Utils.h"
#import "Debug.h"

#define REPO_PASSWORD_REFRESH_INTERVAL 300

#pragma mark - NSObjectValue Category

@implementation NSObject (NSObjectValue)

- (long long)integerValue:(int)defaultValue {
    if ([self respondsToSelector:@selector(longLongValue)])
        return [((id)self) longLongValue];
    else
        return defaultValue;
}

- (BOOL)booleanValue:(BOOL)defaultValue {
    if ([self respondsToSelector:@selector(boolValue)])
        return [((id)self) boolValue];
    else
        return defaultValue;
}

- (NSString *)stringValue {
    if ([self isKindOfClass:[NSString class]])
        return (NSString *)self;
    return nil;
}

@end

#pragma mark - SeafBase

@interface SeafBase ()

/**
 * Holds a SeafBaseModel through composition, storing the main data needed for this entry.
 */
@property (nonatomic, strong) SeafBaseModel *model;

@end

@implementation SeafBase

#pragma mark - Initialization

/**
 * Initialize using the Model approach.
 */
- (instancetype)initWithModel:(SeafBaseModel *)model
                   connection:(SeafConnection * _Nullable)connection
{
    self = [super init];
    if (self) {
        _model = model;
        _connection = connection;
        _state = SEAF_DENTRY_INIT;
    }
    return self;
}

/**
 * Compatible with the old initialization method, internally converted to use the Model approach.
 */
- (instancetype)initWithConnection:(SeafConnection *)aConnection
                               oid:(nullable NSString *)anId
                            repoId:(nullable NSString *)aRepoId
                              name:(nullable NSString *)aName
                              path:(nullable NSString *)aPath
                              mime:(nullable NSString *)aMime
{
    SeafBaseModel *model = [[SeafBaseModel alloc] initWithOid:anId
                                                       repoId:aRepoId
                                                         name:aName
                                                         path:aPath
                                                         mime:aMime];
    return [self initWithModel:model connection:aConnection];
}

#pragma mark - Getters/Setters (Mapped to model)

- (NSString * _Nullable)oid {
    return self.model.oid;
}

- (void)setOid:(NSString * _Nullable)oid {
    self.model.oid = oid;
}

- (NSString * _Nullable)repoId {
    return self.model.repoId;
}

- (void)setRepoId:(NSString * _Nullable)repoId {
    self.model.repoId = repoId;
}

- (NSString * _Nullable)name {
    return self.model.name;
}

- (void)setName:(NSString * _Nullable)name {
    self.model.name = name;
}

- (NSString * _Nullable)path {
    return self.model.path;
}

- (void)setPath:(NSString * _Nullable)path {
    self.model.path = path;
}

- (NSString * _Nullable)mime {
    return self.model.mime;
}

- (void)setMime:(NSString * _Nullable)mime {
    self.model.mime = mime;
}

- (NSString * _Nullable)ooid {
    return self.model.ooid;
}

- (void)setOoid:(NSString * _Nullable)ooid {
    self.model.ooid = ooid;
}

- (NSString * _Nullable)shareLink {
    return self.model.shareLink;
}

- (void)setShareLink:(NSString * _Nullable)shareLink {
    self.model.shareLink = shareLink;
}

- (NSString *)cacheKey
{
    return [NSString stringWithFormat:@"%@/%@", self.repoId, self.path];
}

- (NSString *)key
{
    return self.name;
}

#pragma mark - Computed Properties & Logic

- (BOOL)hasCache {
    // Originally in SeafBase, there was a similar judgment: if (_ooid != nil) return YES;
    // Here, it can be determined based on whether self.model.ooid exists.
    return (self.model.ooid != nil);
}

- (void)loadContent:(BOOL)force {
    // If not forced to refresh and the cache has already been loaded, you can directly callback
//    BOOL hasLocalCache = [self loadCacheIfNeeded];
    BOOL hasLocalCache = [self loadCache];

    if (hasLocalCache && !force) {
        [self downloadComplete:YES];
        return;
    }
    
    @synchronized (self) {
        if (self.state == SEAF_DENTRY_LOADING) {
            // Loading in progress, do not trigger again
            return;
        }
        self.state = SEAF_DENTRY_LOADING;
    }
    
    [self realLoadContent];
}

- (BOOL)loadCache
{
    if (!self.hasCache) {
        return [self realLoadCache];
    }
    return false;
}

- (BOOL)realLoadCache
{
    return NO;
}

- (void)realLoadContent {
    // Fetch data according to actual needs here
    // After completion, you need to call downloadComplete: or downloadFailed:
    // [self.connection sendRequest:... success:^(...) {
    //    // Request successful
    //    [self downloadComplete:YES];
    // } failure:^(...) {
    //    [self downloadFailed:error];
    // }];
}

- (void)clearCache {
    // Logic to clear cache, implemented according to business needs
    // You can set self.model.ooid to nil, or delete local cache files, etc.
    self.model.ooid = nil;
}

- (void)downloadComplete:(BOOL)updated {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.state = SEAF_DENTRY_SUCCESS;
        [self.delegate download:self complete:updated];
    });
}

- (void)downloadFailed:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.state = SEAF_DENTRY_FAILURE;
        [self.delegate download:self failed:error];
    });
}

#pragma mark - Star

- (void)setStarred:(BOOL)starred {
    [self.connection setStarred:starred repo:self.repoId path:self.path];
}

#pragma mark - Repo Password

- (BOOL)passwordRequiredWithSyncRefresh {
    if (!self.encrypted) return NO;
    NSString *savedPassword = [self.connection getRepoPassword:self.repoId];
    if (!savedPassword) return YES;
    
    // Check if the password has been refreshed within the specified time
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval lastRefresh = [self.connection getRepoLastRefreshPasswordTime:self.repoId];
    if (now - lastRefresh > REPO_PASSWORD_REFRESH_INTERVAL) {
        __block BOOL result = YES;
        __block BOOL waiting = YES;
        [self setRepoPassword:savedPassword block:^(SeafBase *entry, int ret) {
            waiting = NO;
            result = (ret == RET_SUCCESS) ? NO : YES;
        }];
        // Wait for the asynchronous callback to finish (avoid blocking if on the main thread, this is just an example)
        while (waiting) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
        return result;
    }
    return NO;
}

- (void)setRepoPassword:(NSString *)password block:(void(^)(SeafBase *entry, int ret))block {
    if (!self.repoId) {
        if (block) block(self, RET_FAILED);
        return;
    }
    NSString *url = [NSString stringWithFormat:API_URL"/repos/%@/?op=setpassword", self.repoId];
    NSString *formString = [NSString stringWithFormat:@"password=%@", password.escapedPostForm];
    
    __weak typeof(self) wself = self;
    [self.connection sendPost:url form:formString success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        __strong typeof(self) sself = wself;
        Debug("Set repo %@ password success.", sself.repoId);
        [sself.connection saveRepo:sself.repoId password:password];
        if (block) block(sself, RET_SUCCESS);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        __strong typeof(self) sself = wself;
        Debug("Failed to set repo %@ password: %@, %@", sself.repoId, JSON, error);
        int ret = RET_FAILED;
        if (JSON != nil) {
            NSString *errMsg = [JSON objectForKey:@"error_msg"];
            if ([errMsg isEqualToString:@"Incorrect password"]) {
                ret = RET_WRONG_PASSWORD;
            }
        }
        if (block) block(sself, ret);
    }];
}

#pragma mark - Share Link

- (void)generateShareLink:(id<SeafShareDelegate>)dg {
    [self getShareLink:^(BOOL result, NSString * _Nullable link) {
        if (result && link.length > 0) {
            self.model.shareLink = link;
            if (dg) [dg generateSharelink:self WithResult:YES];
        } else {
            // If no link is obtained, go through the creation process
            [self generateShareLink:dg password:nil expire_days:nil];
        }
    }];
}

- (void)generateShareLink:(id<SeafShareDelegate>)dg
                 password:(NSString *)password
              expire_days:(NSString *)expire_days
{
    NSString *url = [NSString stringWithFormat:@"%@/share-links/", API_URL_V21];
    // eg：path=/test&repo_id=xxxx
    NSMutableString *form = [NSMutableString stringWithFormat:@"path=%@&repo_id=%@", [self.model.path escapedPostForm], self.model.repoId];
    if (password) {
        [form appendFormat:@"&password=%@", password.escapedPostForm];
    }
    if (expire_days) {
        [form appendFormat:@"&expire_days=%@", expire_days];
    }
    
    __weak typeof(self) wself = self;
    [self.connection sendPost:url form:form success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        __strong typeof(self) sself = wself;
        if ([JSON isKindOfClass:[NSDictionary class]]) {
            NSString *link = JSON[@"link"];
            if (link) {
                sself.model.shareLink = link;
                if (dg) [dg generateSharelink:sself WithResult:YES];
                return;
            }
        }
        if (dg) [dg generateSharelink:sself WithResult:NO];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        __strong typeof(self) sself = wself;
        if (dg) [dg generateSharelink:sself WithResult:NO];
    }];
}

/**
 * Helper method to check if a share link already exists
 */
- (void)getShareLink:(void(^)(BOOL result, NSString *_Nullable link))completionHandler {
    NSString *query = [NSString stringWithFormat:@"path=%@&repo_id=%@", [self.model.path escapedPostForm], self.model.repoId ?: @""];
    NSString *url = [NSString stringWithFormat:@"%@/share-links/?%@", API_URL_V21, query];
    
    [self.connection sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        if ([JSON isKindOfClass:[NSArray class]]) {
            NSArray *list = (NSArray *)JSON;
            if (list.count > 0) {
                id firstObject = list.firstObject;
                if ([firstObject isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *dict = (NSDictionary *)firstObject;
                    NSString *link = dict[@"link"];
                    if (link) {
                        completionHandler(YES, link);
                        return;
                    }
                }
            }
        }
        completionHandler(NO, nil);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        completionHandler(NO, nil);
    }];
}

#pragma mark - UI

- (UIImage *)icon {
    // For example, generate the corresponding icon based on mimeType or file extension
    return [UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString];
}

#pragma mark - Other Helpler

- (NSString *)uniqueKey {
    if (!_uniqueKey) {
        // Create a unique key based on accountIdentifier + repoId + path
        NSString *accountIdentifier = self.connection.accountIdentifier ?: @"";
        _uniqueKey = [NSString stringWithFormat:@"%@/%@/%@", accountIdentifier, self.model.repoId ?: @"", self.model.name];
    }
    return _uniqueKey;
}

- (void)updateWithEntry:(SeafBase *)entry
{
    if (self.oid != entry.oid)
        self.oid = entry.oid;
}
@end
