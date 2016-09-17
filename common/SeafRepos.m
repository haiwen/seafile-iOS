//
//  SeafRepos.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafData.h"
#import "SeafRepos.h"
#import "SeafDir.h"
#import "SeafConnection.h"
#import "SeafGlobal.h"
#import "SeafDateFormatter.h"


#import "ExtentedString.h"
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
    if (_encrypted && ![connection getRepoPassword:self.repoId])
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
    _desc = repo.desc;
    _size = repo.size;
    _owner = repo.owner;
    _encrypted = repo.encrypted;
    _mtime = repo.mtime;
    _encVersion = repo.encVersion;
}

- (BOOL)canLocalDecrypt
{
    //Debug("localDecrypt %d version:%d, magic:%@", self.encrypted, self.encVersion, self.magic);
    return self.encrypted && self.encVersion >= 2 && self.magic;
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
                             encVersion:(int)[[repoInfo objectForKey:@"enc_version"] integerValue:1]
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
- (void)realLoadContent
{
    [connection sendRequest:self.url
                    success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         @synchronized(self) {
             self.state = SEAF_DENTRY_UPTODATE;
             if ([self handleData:JSON]) {
                 NSData *data = [Utils JSONEncode:JSON];
                 [self->connection savetoCacheKey:KEY_REPOS value:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
             }
         }
     }
                    failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         self.state = SEAF_DENTRY_INIT;
         [self.delegate download:self failed:error];
     }];
}

- (BOOL)realLoadCache
{
    id JSON = [self->connection getCachedObj:KEY_REPOS];
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

- (void)reSortItems
{
    NSMutableArray *allrepos = [[NSMutableArray alloc] init];
    for (NSMutableArray *repoGroup in _repoGroups) {
        [self sortItems:repoGroup];
        [allrepos addObjectsFromArray:repoGroup];
    }
    self.items = allrepos;
}

- (BOOL)editable
{
    return NO;
}
@end
