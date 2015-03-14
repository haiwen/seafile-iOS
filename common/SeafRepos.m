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

#import "ExtentedString.h"
#import "Debug.h"
#import "Utils.h"

#define KEY_REPOS @"REPOS"

@interface SeafRepo ()
@property (readonly) NSString *perm;

@end
@implementation SeafRepo;

- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    name:(NSString *)aName
                    desc:(NSString *)aDesc
                   owner:(NSString *)aOwner
                     gid:(NSString *)groupid
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
    if (self = [super initWithConnection:aConnection oid:anId repoId:aRepoId name:aName path:@"/" mime:aMime]) {
        _desc = aDesc;
        _owner = aOwner;
        _repoType = aRepoType;
        _perm = aPerm;
        _size = aSize;
        _mtime = aMtime;
        _encrypted = aEncrypted;
        _gid = groupid;
        _encVersion = aEncVersion;
        _magic = aMagic;
        _encKey = aEncKey;
    }
    return self;
}

- (BOOL)passwordRequired
{
    if (_encrypted && ![SeafGlobal.sharedObject getRepoPassword:self.repoId])
        return YES;
    else
        return NO;
}

- (BOOL)editable
{
    if (_perm && [_perm isKindOfClass:[NSString class]])
        return [_perm.lowercaseString isEqualToString:@"rw"];
    return NO;
}

- (NSString *)key
{
    int index = 0;
    if ([self.repoType isEqualToString:@"srepo"]){
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
}

@end



@implementation SeafRepos
@synthesize repoGroups = _repoGroups;

- (id)initWithConnection:(SeafConnection *)aConnection
{
    self = [super initWithConnection:aConnection oid:nil repoId:nil name:NSLocalizedString(@"Libraries", @"Seafile") path:nil mime:nil];
    return self;
}

- (BOOL)checkSorted:(NSArray *)items
{
    return YES;
}

- (void)groupingRepos
{
    int i;
    NSString *owner = connection.username;
    NSMutableArray *repoGroup = [[NSMutableArray alloc] init];
    _repoGroups = [[NSMutableArray alloc] init];

    for (i = 0; i < [self.items count]; ++i) {
        SeafRepo *r = (SeafRepo *)[self.items objectAtIndex:i];
        if ([owner isEqualToString:r.owner]){
            [repoGroup addObject:r];
        } else {
            if ( [connection.username isEqualToString:r.owner])
                [_repoGroups insertObject:repoGroup atIndex:0];
            else
                [_repoGroups addObject:repoGroup];
            repoGroup = [[NSMutableArray alloc] init];
            [repoGroup addObject:r];
            owner = r.owner;
        }
    }
    if (repoGroup.count > 0) {
        [_repoGroups addObject:repoGroup];
    }
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
                             gid:[repoInfo objectForKey:@"groupid"]
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
    [self.delegate entry:self updated:YES progress:100];
    return YES;
}


- (NSString *)url
{
    return API_URL"/repos/";
}


//$ curl -D a.txt -H 'Cookie:seahubsessionid=7eb567868b5df5b22b2ba2440854589c' http://www.gonggeng.org/seahub/api/repo/list/
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
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
         self.state = SEAF_DENTRY_INIT;
         [self.delegate entry:self downloadingFailed:response.statusCode];
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

@end
