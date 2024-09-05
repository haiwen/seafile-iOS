//
//  SeafDentry.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafBase.h"
#import "SeafRepos.h"
#import "SeafConnection.h"

#import "ExtentedString.h"
#import "UIImage+FileType.h"
#import "NSData+Encryption.h"
#import "Utils.h"
#import "Debug.h"

#define REPO_PASSWORD_REFRESH_INTERVAL 300

@implementation NSObject (NSObjectValue)
- (long long)integerValue:(int)defaultValue
{
    if ([self respondsToSelector:@selector(longLongValue)])
        return [((id)self)longLongValue];
    else
        return defaultValue;
}

- (BOOL)booleanValue:(BOOL)defaultValue
{
    if ([self respondsToSelector:@selector(boolValue)])
        return [((id)self)boolValue];
    else
        return defaultValue;
}

- (NSString *)stringValue
{
    if ([self isKindOfClass:[NSString class]])
        return (NSString *)self;
    return nil;
}
@end


@interface SeafBase ()
@end

@implementation SeafBase
@synthesize name = _name, oid = _oid, path = _path, repoId = _repoId, mime=_mime;
@synthesize delegate = _delegate;
@synthesize ooid = _ooid;
@synthesize uniqueKey = _uniqueKey;
@synthesize state;

/**
 * Initializes a new instance of SeafBase with the specified parameters.
 * @param aConnection The SeafConnection instance to use.
 * @param anId The object ID.
 * @param aRepoId The repository ID.
 * @param aName The name of the entry.
 * @param aPath The path of the entry in the repository.
 * @param aMime The MIME type of the entry.
 * @return An initialized SeafBase instance.
 */
- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    name:(NSString *)aName
                    path:(NSString *)aPath
                    mime:(NSString *)aMime
{
    if (self = [super init]) {
        connection = aConnection;
        _oid = anId;
        _name = aName;
        _path = aPath;
        _repoId = aRepoId;
        _mime = aMime;
        _ooid = nil;
        _shareLink = nil;
        self.state = SEAF_DENTRY_INIT;
    }
    return self;
}

- (BOOL)savetoCache:(NSString *)content
{
    return NO;
}

- (void)realLoadContent
{
    // must be override
}

- (BOOL)realLoadCache
{
    return NO;
}

- (void)updateWithEntry:(SeafBase *)entry
{
    if (_oid != entry.oid)
        _oid = entry.oid;
}

- (NSString *)uniqueKey
{
    if (!_uniqueKey) {
        _uniqueKey = [NSString stringWithFormat:@"%@/%@/%@", connection.accountIdentifier, _repoId, _path];
    }
    return _uniqueKey;
}

- (NSString *)key
{
    return self.name;
}

- (UIImage *)icon;
{
    return [UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString];
}

- (BOOL)loadCache
{
    if (!self.hasCache) {
        return [self realLoadCache];
    }
    return false;
}

- (void)clearCache
{
}

- (NSString *)cacheKey
{
    return [NSString stringWithFormat:@"%@/%@", self.repoId, self.path];
}


- (void)loadContent:(BOOL)force {
    BOOL hasCache = [self loadCache];
    @synchronized (self) {
        if (hasCache && !force) {
            return [self downloadComplete:true];
        }
        if (self.state == SEAF_DENTRY_LOADING)
            return;
        self.state = SEAF_DENTRY_LOADING;
    }
    [self realLoadContent];
}

- (BOOL)hasCache
{
    return _ooid != nil;
}

- (void)generateShareLink:(id<SeafShareDelegate>)dg password:(NSString *)password expire_days:(NSString *)expire_days {
    NSString *url = [NSString stringWithFormat:@"%@/share-links/", API_URL_V21];
    NSString *form = [NSString stringWithFormat:@"path=%@&repo_id=%@", [self.path escapedPostForm], self.repoId];
    if (password) {
        [form stringByAppendingString:[NSString stringWithFormat:@"&password=%@", password]];
    }
    if (expire_days) {
        [form stringByAppendingString:[NSString stringWithFormat:@"&expire_days=%@", expire_days]];
    }
    
    [connection sendPost:url form:form success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id  _Nonnull JSON) {
        if (JSON && [JSON objectForKey:@"link"]) {
            NSString *link = [JSON objectForKey:@"link"];
            self->_shareLink = link;
            [dg generateSharelink:self WithResult:YES];
        } else {
            [dg generateSharelink:self WithResult:NO];
        }
    } failure:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id  _Nullable JSON, NSError * _Nullable error) {
        [dg generateSharelink:self WithResult:NO];
    }];
}

- (void)getShareLink:(void(^)(BOOL result, NSString *link))completionHandler {
    NSString *query = [NSString stringWithFormat:@"path=%@&repo_id=%@", [self.path escapedPostForm], self.repoId];
    NSString *url = [NSString stringWithFormat:@"%@/share-links/?%@", API_URL_V21, query];
    
    [connection sendRequest:url success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id  _Nonnull JSON) {
        if (JSON && [JSON isKindOfClass:[NSArray class]]) {
            NSArray *list = (NSArray *)JSON;
            if (list.count > 0) {
                NSDictionary *dict = (NSDictionary *)list.firstObject;
                if (dict && [dict objectForKey:@"link"]) {
                    NSString *link = [dict objectForKey:@"link"];
                    completionHandler(YES, link);
                } else {
                    completionHandler(NO, nil);
                }
            } else {
                completionHandler(NO, nil);
            }
        } else {
            completionHandler(NO, nil);
        }
    } failure:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id  _Nullable JSON, NSError * _Nullable error) {
        completionHandler(NO, nil);
    }];
}

/**
 * Generates a share link for this entry using the specified delegate.
 * @param dg The delegate to be notified about the share link generation status.
 */
- (void)generateShareLink:(id<SeafShareDelegate>)dg
{
    [self getShareLink:^(BOOL result, NSString *link) {
        if (result && link.length > 0) {
            self->_shareLink = link;
            [dg generateSharelink:self WithResult:YES];
        } else {
            [self generateShareLink:dg password:nil expire_days:nil];
        }
    }];
}

- (void)downloadComplete:(BOOL)updated
{
    [self.delegate download:self complete:updated];

}
- (void)downloadFailed:(NSError *)error
{
    [self.delegate download:self failed:error];
}

- (void)setStarred:(BOOL)starred
{
    [connection setStarred:starred repo:self.repoId path:self.path];
}

- (BOOL)passwordRequiredWithSyncRefresh {
    if (self.encrypted) {
        if ([connection shouldLocalDecrypt:self.repoId]) {
            return [connection getRepoPassword:self.repoId] == nil ? YES : NO;
        } else {
            NSString *password = [connection getRepoPassword:self.repoId];
            if (!password) {
                return YES;
            } else {
                NSTimeInterval cur = [[NSDate date] timeIntervalSince1970];
                if (cur - [connection getRepoLastRefreshPasswordTime:self.repoId] > REPO_PASSWORD_REFRESH_INTERVAL) {
                    __block BOOL result = YES;
                    __block BOOL wait = YES;
                    [self setRepoPassword:password block:^(SeafBase *entry, int ret) {
                        wait = NO;
                        result = ret == RET_SUCCESS ? NO : YES;
                    }];
                    //dispatch_semaphore will block main thread
                    while (wait) {
                        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
                    }
                    return result;
                } else {
                    return NO;
                }
            }
        }
    } else {
        return NO;
    }
}

- (void)setRepoPassword:(NSString *)password block:(void(^)(SeafBase *entry, int ret))block
{
    if (!self.repoId) {
        if (block) block(self, RET_FAILED);
        return;
    }
    NSString *request_str = [NSString stringWithFormat:API_URL"/repos/%@/?op=setpassword", self.repoId];
    NSString *formString = [NSString stringWithFormat:@"password=%@", password.escapedPostForm];
    __weak typeof(self) wself = self;
    [connection sendPost:request_str form:formString
                 success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
                     __strong typeof(self) sself = wself;
                     Debug("Set repo %@ password success.", sself.repoId);
                     [sself->connection saveRepo:sself.repoId password:password];
                     if (block)  block(sself, RET_SUCCESS);
                 } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
                     __strong typeof(self) sself = wself;
                     Debug("Failed to set repo %@ password: %@, %@", sself.repoId, JSON, error);
                     int ret = RET_FAILED;
                     if (JSON != nil) {
                         NSString *errMsg = [JSON objectForKey:@"error_msg"];
                         if ([@"Incorrect password" isEqualToString:errMsg]) {
                             Debug("Repo password incorrect.");
                             ret = RET_WRONG_PASSWORD;
                         }
                     }
                     if (block)  block(sself, ret);
                 }];
}
@end
