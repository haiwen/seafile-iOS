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
#import "SeafGlobal.h"

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
@property BOOL cacheLoaded;
@end

@implementation SeafBase
@synthesize name = _name, oid = _oid, path = _path, repoId = _repoId, mime=_mime;
@synthesize delegate = _delegate;
@synthesize ooid = _ooid;
@synthesize state;
@synthesize cacheLoaded;


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
        self.cacheLoaded = NO;
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
    @synchronized (self) {
        if (self.cacheLoaded) {
            [_delegate entry:self updated:YES progress:100];
            return YES;
        }
        self.cacheLoaded = YES;
    }
    return [self realLoadCache];
}

- (void)clearCache
{
}

- (void)loadContent:(BOOL)force;
{
    [self loadCache];
    @synchronized (self) {
        if (self.state == SEAF_DENTRY_UPTODATE && !force) {
            [_delegate entry:self updated:NO progress:0];
            return;
        }
        if (self.state == SEAF_DENTRY_LOADING)
            return;
        self.state = SEAF_DENTRY_LOADING;
    }
    [self realLoadContent];
}

- (void)setRepoPassword:(NSString *)password
{
    if (!self.repoId) {
        [self.delegate entry:self repoPasswordSet:NO];
        return;
    }
    NSString *request_str = [NSString stringWithFormat:API_URL"/repos/%@/?op=setpassword", self.repoId];
    NSString *formString = [NSString stringWithFormat:@"password=%@", password];
    [connection sendPost:request_str form:formString
                 success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
                     [SeafGlobal.sharedObject setRepo:self.repoId password:password];
                     [self.delegate entry:self repoPasswordSet:YES];
                 } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
                     [self.delegate entry:self repoPasswordSet:NO];
                 }];
}

- (void)checkRepoPasswordV2:(NSString *)password
{
    SeafRepo *repo = [connection getRepo:self.repoId];
    Debug("check magic %@, %@", repo.magic, password);
    if (!repo.magic || !repo.encKey) {
        [self.delegate entry:self repoPasswordSet:NO];
        return;
    }
    NSString *magic = [NSData passwordMaigc:password repo:self.repoId version:2];
    if ([magic isEqualToString:repo.magic]) {
        [SeafGlobal.sharedObject setRepo:self.repoId password:password];
        [self.delegate entry:self repoPasswordSet:YES];
    } else
        [self.delegate entry:self repoPasswordSet:NO];
}

- (void)checkRepoPassword:(NSString *)password
{
    if (!self.repoId) {
        [self.delegate entry:self repoPasswordSet:NO];
        return;
    }
    int version = [[connection getRepo:self.repoId] encVersion];
    if (version == 2)
        return [self checkRepoPasswordV2:password];
    NSString *magic = [NSData passwordMaigc:password repo:self.repoId version:version];
    NSString *request_str = [NSString stringWithFormat:API_URL"/repos/%@/?op=checkpassword", self.repoId];
    NSString *formString = [NSString stringWithFormat:@"magic=%@", [magic escapedPostForm]];
    [connection sendPost:request_str form:formString
                 success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
                     [SeafGlobal.sharedObject setRepo:self.repoId password:password];
                     [self.delegate entry:self repoPasswordSet:YES];
                 } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
                     [self.delegate entry:self repoPasswordSet:NO];
                 } ];
}

- (BOOL)hasCache
{
    return _ooid != nil;
}

- (void)generateShareLink:(id<SeafShareDelegate>)dg type:(NSString *)type
{
    NSString *url = [NSString stringWithFormat:API_URL"/repos/%@/file/shared-link/", self.repoId];
    NSString *form = [NSString stringWithFormat:@"p=%@&type=%@", [self.path escapedPostForm], type];
    [connection sendPut:url form:form
                success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         NSString *link = [[response allHeaderFields] objectForKey:@"Location"];
         Debug("delegate=%@, share link = %@\n", dg, link);
         if ([link hasPrefix:@"\""])
             _shareLink = [link substringWithRange:NSMakeRange(1, link.length-2)];
         else
             _shareLink = link;
         [dg generateSharelink:self WithResult:YES];
     }
                failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
         [dg generateSharelink:self WithResult:NO];
     }];
}

- (void)generateShareLink:(id<SeafShareDelegate>)dg
{
    return [self generateShareLink:dg type:@"f"];
}


@end
