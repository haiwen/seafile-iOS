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


- (void)loadContent:(BOOL)force;
{
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

- (void)generateShareLink:(id<SeafShareDelegate>)dg
{
    return [self generateShareLink:dg password:nil expire_days:nil];
}

- (void)downloadComplete:(BOOL)updated
{
    [self.delegate download:self complete:updated];

}
- (void)downloadFailed:(NSError *)error
{
    [self.delegate download:self failed:error];
}

@end
