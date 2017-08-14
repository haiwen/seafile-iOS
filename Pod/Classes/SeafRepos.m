//
//  SeafRepos.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafBase.h"
#import "SeafRepos.h"
#import "SeafDir.h"
#import "SeafConnection.h"
#import "SeafDateFormatter.h"


#import "ExtentedString.h"
#import "NSData+Encryption.h"
#import "Debug.h"
#import "Utils.h"

#define KEY_REPOS @"REPOS"

@interface SeafRepo ()

@end
@implementation SeafRepo;

- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    name:(NSString *)aName
                    desc:(NSString *)aDesc
                   owner:(NSString *)aOwner
                    type:(NSString *)aType
                repoType:(NSString *)aRepoType
                    perm:(NSString *)aPerm
                    size:(long long)aSize
                   mtime:(long long)aMtime
               encrypted:(BOOL)aEncrypted
              encVersion:(int)aEncVersion
                   magic:(NSString *)aMagic
                  encKey:(NSString *)aEncKey
{
    NSString *aMime = @"text/directory-documents";
    if (aEncrypted)
        aMime = @"text/directory-documents-encrypted";
    if (self = [super initWithConnection:aConnection oid:anId repoId:aRepoId perm:aPerm name:aName path:@"/" mime:aMime]) {
        _desc = aDesc;
        _owner = aOwner;
        _repoType = aRepoType;
        _size = aSize;
        _mtime = aMtime;
        _encrypted = aEncrypted;
        _type = aType;
        _encVersion = aEncVersion;
        _magic = aMagic;
        _encKey = aEncKey;
    }
    return self;
}

- (BOOL)passwordRequired
{
    //Debug("repoId;%@ %d %@", self.repoId, self.encrypted, [connection getRepoPassword:self.repoId]);
    if (self.encrypted && ![connection getRepoPassword:self.repoId])
        return YES;
    else
        return NO;
}

- (NSString *)key
{
    int index = 0;
    if ([self.repoType isEqualToString:SHARE_REPO]){
        index = 1;
    } else if ([self.repoType isEqualToString:@"grepo"]){
        index = 2;
    }
    return [NSString stringWithFormat:@"%d-%@-%@", index, self.owner, self.repoId ];
}

- (void)updateWithEntry:(SeafBase *)entry
{
    SeafRepo *repo = (SeafRepo *)entry;
    [super updateWithEntry:entry];
    self.name = entry.name;
    _desc = repo.desc;
    _size = repo.size;
    _owner = repo.owner;
    _encrypted = repo.encrypted;
    _mtime = repo.mtime;
}

- (NSString *)detailText
{
    NSString *detail = [SeafDateFormatter stringFromLongLong:self.mtime];
    if ([SHARE_REPO isEqualToString:self.type]) {
        NSString *name = self.owner;
        unsigned long index = [self.owner indexOf:'@'];
        if (index != NSNotFound)
            name = [self.owner substringToIndex:index];
        detail = [detail stringByAppendingFormat:@", %@", name];
    }
    return detail;
}

- (BOOL)isGroupRepo
{
    return [GROUP_REPO isEqualToString:self.type];
}

- (void)checkRepoEncVersion:(void(^)(bool success, id repoInfo))completeBlock
{
    NSString *url = [NSString stringWithFormat:API_URL"/repos/%@/", self.repoId];
    [connection sendRequest:url success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id  _Nonnull JSON) {
        completeBlock(true, JSON);
    } failure:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id  _Nullable JSON, NSError * _Nullable error) {
        completeBlock(false, nil);
    }];
}

- (void)checkOrSetRepoPassword:(NSString *)password delegate:(id<SeafRepoPasswordDelegate>)del
{
    repo_password_set_block_t block = ^(SeafBase *entry, int ret) {
        if (ret == RET_SUCCESS)
            [entry->connection setRepo:entry.repoId password:password];
        [del entry:entry repoPasswordSet:ret];
    };
    [self checkOrSetRepoPassword:password block:block];
}

- (void)doCheckOrSetRepoPassword:(NSString *)password block:(void(^)(SeafBase *entry, int ret))block
{
    if ([connection shouldLocalDecrypt:self.repoId]) {
        [self checkRepoPassword:password block:block];
    } else {
        [self setRepoPassword:password block:block];
    }
}

- (void)checkOrSetRepoPassword:(NSString *)password block:(void(^)(SeafBase *entry, int ret))block
{
    if (self.encVersion > 0) {
        Debug("encVersion:%d encKey:%@ magic:%@", self.encVersion, self.encKey, self.magic);
        return [self doCheckOrSetRepoPassword:password block:block];
    }
    [self checkRepoEncVersion:^(bool success, id repoInfo) {
        if (success) {
            _encVersion = (int)[[repoInfo objectForKey:@"enc_version"] integerValue:-1];
            _magic = [[repoInfo objectForKey:@"magic"] stringValue];
            _encKey = [repoInfo objectForKey:@"random_key"];
            Debug("Repo %@ detail: %@", self.repoId, repoInfo);
            return [self doCheckOrSetRepoPassword:password block:block];
        } else {
            block(self, false);
        }
    }];
}

- (void)setRepoPassword:(NSString *)password block:(void(^)(SeafBase *entry, int ret))block
{
    if (!self.repoId) {
        if (block) block(self, RET_FAILED);
        return;
    }
    NSString *request_str = [NSString stringWithFormat:API_URL"/repos/%@/?op=setpassword", self.repoId];
    NSString *formString = [NSString stringWithFormat:@"password=%@", password.escapedPostForm];
    [connection sendPost:request_str form:formString
                 success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
                     Debug("Set repo %@ password success.", self.repoId);
                     [connection setRepo:self.repoId password:password];
                     if (block)  block(self, RET_SUCCESS);
                 } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
                     Debug("Failed to set repo %@ password: %@, %@", self.repoId, JSON, error);
                     int ret = RET_FAILED;
                     if (JSON != nil) {
                         NSString *errMsg = [JSON objectForKey:@"error_msg"];
                         if ([@"Incorrect password" isEqualToString:errMsg]) {
                             Debug("Repo password incorrect.");
                             ret = RET_WRONG_PASSWORD;
                         }
                     }
                     if (block)  block(self, ret);
                 }];
}

- (void)checkRepoPasswordV2:(NSString *)password block:(void(^)(SeafBase *entry, int ret))block
{
    SeafRepo *repo = [connection getRepo:self.repoId];
    Debug("check magic %@, %@", repo.magic, password);
    if (!repo.magic || !repo.encKey) {
        return block(self, RET_FAILED);
    }
    NSString *magic = [NSData passwordMaigc:password repo:self.repoId version:2];
    if ([magic isEqualToString:repo.magic]) {
        block(self, RET_SUCCESS);
    } else {
        block(self, RET_WRONG_PASSWORD);
    }
}

- (void)checkRepoPassword:(NSString *)password block:(repo_password_set_block_t)block
{
    if (!self.repoId) {
        if (block) block(self, RET_FAILED);
        return;
    }
    repo_password_set_block_t handler = ^(SeafBase *entry, int ret) {
        if (ret == RET_SUCCESS)
            [connection setRepo:self.repoId password:password];
        if (block)
            block(entry, ret);
    };

    int version = [[connection getRepo:self.repoId] encVersion];
    if (version == 2)
        return [self checkRepoPasswordV2:password block:handler];
    NSString *magic = [NSData passwordMaigc:password repo:self.repoId version:version];
    NSString *request_str = [NSString stringWithFormat:API_URL"/repos/%@/?op=checkpassword", self.repoId];
    NSString *formString = [NSString stringWithFormat:@"magic=%@", [magic escapedPostForm]];
    [connection sendPost:request_str form:formString
                 success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
                     handler(self, true);
                 } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
                     handler(self, false);
                 } ];
}

@end



@implementation SeafRepos
@synthesize repoGroups = _repoGroups;

- (id)initWithConnection:(SeafConnection *)aConnection
{
    self = [super initWithConnection:aConnection oid:nil repoId:nil name:NSLocalizedString(@"Libraries", @"Seafile") path:nil mime:nil];
    return self;
}

- (void)groupingRepos
{
    int i;
    NSString *owner = connection.username;
    NSMutableArray *repoGroup = [[NSMutableArray alloc] init];
    NSMutableArray *ownRepos = [[NSMutableArray alloc] init];
    NSMutableArray *srepos = [[NSMutableArray alloc] init];
    NSMutableDictionary *grepos = [[NSMutableDictionary alloc] init];

    for (i = 0; i < [self.items count]; ++i) {
        SeafRepo *r = (SeafRepo *)[self.items objectAtIndex:i];
        if (!r.owner) continue;
        if ([owner isEqualToString:r.owner]){
            [ownRepos addObject:r];
        } else if ([SHARE_REPO isEqualToString:r.type]){
            [srepos addObject:r];
        } else {
            NSMutableArray *group = [grepos objectForKey:r.owner];
            if (!group) {
                group = [[NSMutableArray alloc] init];
                [grepos setObject:group forKey:r.owner];
            }
            [group addObject:r];
        }
    }
    [repoGroup addObject:ownRepos];
    if (srepos.count > 0)
        [repoGroup addObject:srepos];

    for (NSString *groupName in grepos) {
        [repoGroup addObject:[grepos objectForKey:groupName]];
    }

    _repoGroups = repoGroup;
    [self reSortItems];
}

- (BOOL)handleData:(id)JSON
{
    NSMutableArray *newRepos = [NSMutableArray array];
    for (NSDictionary *repoInfo in JSON) {
        if ([repoInfo objectForKey:@"name"] == [NSNull null])
            continue;
        SeafRepo *newRepo = [[SeafRepo alloc]
                             initWithConnection:connection
                             oid:[repoInfo objectForKey:@"root"]
                             repoId:[repoInfo objectForKey:@"id"]
                             name:[repoInfo objectForKey:@"name"]
                             desc:[repoInfo objectForKey:@"desc"]
                             owner:[repoInfo objectForKey:@"owner"]
                             type:[repoInfo objectForKey:@"type"]
                             repoType:[repoInfo objectForKey:@"type"]
                             perm:[repoInfo objectForKey:@"permission"]
                             size:[[repoInfo objectForKey:@"size"] integerValue:0]
                             mtime:[[repoInfo objectForKey:@"mtime"] integerValue:0]
                             encrypted:[[repoInfo objectForKey:@"encrypted"] booleanValue:NO]
                             encVersion:(int)[[repoInfo objectForKey:@"enc_version"] integerValue:0]
                             magic:[[repoInfo objectForKey:@"magic"] stringValue]
                             encKey:[repoInfo objectForKey:@"random_key"]
                             ];
        newRepo.delegate = self.delegate;
        [newRepos addObject:newRepo];
    }
    [self loadedItems:newRepos];
    [self groupingRepos];
    [self.delegate download:self complete:true];
    return YES;
}


- (NSString *)url
{
    return API_URL"/repos/";
}


//$ curl -D a.txt -H 'Cookie:seahubsessionid=7eb567868b5df5b22b2ba2440854589c' https://seacloud.cc/api/repo/list/
// [{"password_need": false, "name": "test", "mtime": null, "owner": "pithier@163.com", "root": "e6098c7bfc18bb0221eac54988649ed3b884f901", "size": [7224782], "type": "repo", "id": "640fd90d-ef4e-490d-be1c-b34c24040da7", "desc": "dasdadwd"}]
- (void)downloadContentSuccess:(void (^)(SeafDir *dir)) success failure:(void (^)(SeafDir *dir, NSError *error))failure
{
    [connection sendRequest:self.url
                    success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         @synchronized(self) {
             self.state = SEAF_DENTRY_UPTODATE;
             if ([self handleData:JSON]) {
                 NSData *data = [Utils JSONEncode:JSON];
                 [self->connection setValue:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] forKey:KEY_REPOS entityName:ENTITY_OBJECT];
                 if (success)
                     success(self);
             }
         }
     }
                    failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         Warning("Failed to get dir content: %@", error);
         self.state = SEAF_DENTRY_INIT;
         if (failure)
             failure(self, error);
         [self.delegate download:self failed:error];
     }];
}

- (BOOL)realLoadCache
{
    id JSON = [self->connection getCachedJson:KEY_REPOS entityName:ENTITY_OBJECT];
    if (!JSON)
        return NO;
    [self handleData:JSON];
    return YES;
}

- (BOOL)hasCache
{
    return self.items.count > 0;
}

- (SeafRepo *)getRepo:(NSString *)repo
{
    if (!repo) return nil;
    int i;
    for (i = 0; i < [self.items count]; ++i) {
        SeafRepo *r = (SeafRepo *)[self.items objectAtIndex:i];
        if ([r.repoId isEqualToString:repo])
            return r;
    }
    return nil;
}

- (NSString *)configKeyForSort
{
    return @"SORT_KEY_REPO";
}

- (void)reSortItems
{
    NSMutableArray *allrepos = [[NSMutableArray alloc] init];
    for (NSMutableArray *repoGroup in _repoGroups) {
        [self sortItems:repoGroup];
        [allrepos addObjectsFromArray:repoGroup];
    }
    self.items = allrepos;
}

- (void)reSortItemsByName
{
    [super reSortItemsByName];
    [self reSortItems];
}

- (void)reSortItemsByMtime
{
    [super reSortItemsByMtime];
    [self reSortItems];
}

- (BOOL)editable
{
    return NO;
}
@end
