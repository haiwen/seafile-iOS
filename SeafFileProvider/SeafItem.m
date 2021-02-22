//
//  SeafDecodedData.m
//  SeafFileProvider
//
//  Created by Wei W on 11/5/17.
//  Copyright © 2017 Seafile. All rights reserved.
//

#import "SeafItem.h"
#import "SeafGlobal.h"
#import "SeafRepos.h"
#import "APLRUCache.h"
#import "Utils.h"
#import "Debug.h"
#import "ExtentedString.h"

static APLRUCache *_cache = nil;

static APLRUCache *cache() {
    if (!_cache) {
        _cache = [[APLRUCache alloc] initWithCapacity:5000];
    }
    return _cache;
}

#define CACHE cache()

@implementation SeafItem
@synthesize itemIdentifier = _itemIdentifier;
@synthesize server = _server;
@synthesize username = _username;
@synthesize repoId = _repoId;
@synthesize path = _path;
@synthesize filename = _filename;
@synthesize tagData = _tagData;

@synthesize conn = _conn;
@synthesize name = _name;


- (instancetype)initWithServer:server username:(NSString *)username repo:(NSString *)repoId path:(NSString *)path filename:(NSString *)filename
{
    if (self = [super init]) {
        _server = server;
        _username = username;
        _repoId = repoId;
        _path = path;
        _filename = filename;
        _lastUsedDate = [NSDate date];
    }
    return self;
}
- (instancetype)initWithItemIdentity:(NSFileProviderItemIdentifier)identity;
{
     if (self = [super init]) {
         _itemIdentifier = identity;

         NSArray *pathCompoents = identity.pathComponents; // @"/", encodedDir, filename
         if (pathCompoents.count >= 3) {
             _filename = [[pathCompoents objectAtIndex:2] stringByRemovingPercentEncoding];
         }
         if (pathCompoents.count >= 2) {
             NSString *encodedDir = [pathCompoents objectAtIndex:1];
             NSString *server = nil;
             NSString *username = nil;;
             NSString *repoId = nil;
             NSString *path = nil;
             [Utils decodePath:encodedDir server:&server username:&username repo:&repoId path:&path];
             _server = server;
             _username = username;
             _repoId = repoId;
             _path = path;
         }
     }

    return self;
}

- (SeafConnection *)conn
{
    if (!_conn) {
        if (self.server && self.username) {
            _conn = [SeafGlobal.sharedObject getConnection:self.server username:self.username];
        }
    }
    return _conn;
}

- (NSFileProviderItemIdentifier)itemIdentifier
{
    if (!_itemIdentifier) {
        if (self.isRoot) {
            _itemIdentifier = @"/";
        } else {
            NSString *encodedPath = [Utils encodePath:_server username:_username repo:_repoId path:_path];
            if (_filename) {
                //if doesnot encode, ä,ö,ü will encode to a%CC%88%2Co%CC%88%2Cu%CC%88 when upload
                _itemIdentifier = [NSString stringWithFormat:@"/%@/%@", encodedPath, [_filename escapedUrl]];
            } else {
                _itemIdentifier = [NSString stringWithFormat:@"/%@", encodedPath];
            }
        }
    }
    return _itemIdentifier;
}

- (SeafItem *)parentItem
{
    // /account/repo/path
    if (self.isRoot) { // root
        return self;
    } else if (self.isAccountRoot) { // directory, account root(repo list)
        return [[SeafItem alloc] initWithServer:nil username:nil repo:nil path:nil filename:nil];
    } else if (self.isRepoRoot) { // directory, account root(repo list)
        return [[SeafItem alloc] initWithServer:_server username:_username repo:nil path:nil filename:nil];
    } else if (self.isFile) {  // file
        return [[SeafItem alloc] initWithServer:_server username:_username repo:_repoId path:_path filename:nil];
    } else { // directory, not repo root
        return [[SeafItem alloc] initWithServer:_server username:_username repo:_repoId path:_path.stringByDeletingLastPathComponent filename:nil];
    }
}
- (NSString *)name
{
    if (!_name) {
        if (self.isRoot) {
            _name = @"Seafile";
        } else if (self.isAccountRoot) {
            _name = [NSString stringWithFormat:@"%@-%@", self.conn.host, _username];
        } else if (self.isRepoRoot) {
            SeafRepo *repo = [self.conn getRepo:_repoId];
            _name = repo.name;
        } else if (self.isFile) {
            _name = _filename;
        } else {
            _name = _path.lastPathComponent;
        }
        //Debug("identify=%@, _server=%@, _username=%@, repo=%@, path=%@, filename=%@  ===> %@", _itemIdentifier, _server, _username, _repoId, _path, _filename, _name);
    }
    return _name;
}

- (BOOL)isRoot
{
    return !_server;
}
- (BOOL)isAccountRoot
{
    return _server && !_repoId;
}
- (BOOL)isRepoRoot
{
    return _repoId && _path && [_path isEqualToString:@"/"] && !_filename;
}
- (BOOL)isFile
{
    return !!_filename;
}

- (BOOL)isTouchIdEnabled {
    return self.conn.touchIdEnabled;
}

- (SeafBase *)getSeafObj
{
    if (self.isRoot) {
        return nil;
    } else if (self.isAccountRoot) {
        return self.conn.rootFolder;
    } else if (self.isRepoRoot) {
        return [self.conn getRepo:_repoId];
    } else if (self.isFile) {
        NSString *filepath = [self.path stringByAppendingPathComponent:self.filename];
        return [[SeafFile alloc] initWithConnection:self.conn oid:nil repoId:_repoId name:_filename path:filepath mtime:0 size:0];
    } else {
        return [[SeafDir alloc] initWithConnection:self.conn oid:nil repoId:self.repoId perm:nil name:self.filename path:self.path];
    }
}

- (SeafBase *)toSeafObj
{
    if (self.isRoot) {
        return nil;
    } else {
        SeafBase *obj = [CACHE cachedObjectForKey:self.itemIdentifier];
        if (!obj) {
            obj = [self getSeafObj];
            if (obj) {
                [CACHE cacheObject:obj forKey:self.itemIdentifier];
                [obj loadCache];
            }
        }

        return obj;
    }
}

- (void)setTagData:(NSData *)tagData {
    _tagData = tagData;
    [self.conn saveFileProviderTagData:_tagData withItemIdentifier:_itemIdentifier];
}

- (NSData *)tagData {
    if (!_tagData) {
        _tagData = [self.conn loadFileProviderTagDataWithItemIdentifier:_itemIdentifier];
    }
    return _tagData;
}

+ (SeafItem *)fromAccount:(SeafConnection *)conn
{
    return [[SeafItem alloc] initWithServer:conn.address username:conn.username repo:nil path:nil filename:nil];
}

+ (SeafItem *)fromSeafBase:(SeafBase *)obj
{
    SeafItem *item = nil;
    if ([obj isKindOfClass:[SeafRepo class]]) {
       item = [SeafItem fromSeafRepo:(SeafRepo *)obj];
    } else if ([obj isKindOfClass:[SeafFile class]]) {
        item = [SeafItem fromSeafFile:(SeafFile *)obj];
    } else {
        item = [SeafItem fromSeafDir:(SeafDir *)obj];
    }
    [CACHE cacheObject:obj forKey:item.itemIdentifier];
    return item;
}

+ (SeafItem *)fromSeafRepo:(SeafRepo *)repo
{
    return [[SeafItem alloc] initWithServer:repo->connection.address username:repo->connection.username repo:repo.repoId path:@"/" filename:nil];
}
+ (SeafItem *)fromSeafDir:(SeafDir *)dir
{
    return [[SeafItem alloc] initWithServer:dir->connection.address username:dir->connection.username repo:dir.repoId path:dir.path filename:nil];
}
+ (SeafItem *)fromSeafFile:(SeafFile *)file
{
    return [[SeafItem alloc] initWithServer:file->connection.address username:file->connection.username repo:file.repoId path:file.path.stringByDeletingLastPathComponent filename:file.name];
}

- (NSDictionary *)convertToDict {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [Utils dict:dict setObject:self.itemIdentifier forKey:@"itemIdentifier"];
    [Utils dict:dict setObject:self.server forKey:@"server"];
    [Utils dict:dict setObject:self.username forKey:@"username"];
    [Utils dict:dict setObject:self.repoId forKey:@"repoId"];
    [Utils dict:dict setObject:self.path forKey:@"path"];
    [Utils dict:dict setObject:self.filename forKey:@"filename"];
    [Utils dict:dict setObject:self.tagData forKey:@"tagData"];
    [Utils dict:dict setObject:self.name forKey:@"name"];
    [Utils dict:dict setObject:self.lastUsedDate forKey:@"lastUsedDate"];
    [Utils dict:dict setObject:self.favoriteRank forKey:@"favoriteRank"];
    return dict;
}

- (SeafItem *)convertFromDict:(NSDictionary *)dict {
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:[dict objectForKey:@"itemIdentifier"]];
    item.tagData = [dict objectForKey:@"tagData"];
    item.lastUsedDate = [dict objectForKey:@"lastUsedDate"];
    item.favoriteRank = [dict objectForKey:@"favoriteRank"];
    return item;
}

@end
