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
#import "SeafStorage.h"
#import "Constants.h"

static APLRUCache *_cache = nil;

static APLRUCache *cache(void) {
    if (!_cache) {
        _cache = [[APLRUCache alloc] initWithCapacity:5000];
    }
    return _cache;
}

#define CACHE cache()

@implementation SeafItem {
    NSString *_fallbackName;
}
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
+ (NSFileProviderItemIdentifier)canonicalIdentifier:(NSFileProviderItemIdentifier)identifier
{
    if (identifier.length == 0) {
        return NSFileProviderRootContainerItemIdentifier;
    }
    if ([identifier isEqualToString:NSFileProviderRootContainerItemIdentifier]
        || [identifier isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier]) {
        return identifier;
    }
    // The system normalizes identifiers that look like paths (sidebar bookmarks, Spotlight),
    // which strips a leading slash. A slash-prefixed identifier therefore resurfaces without
    // the slash and reads as a different item, so the canonical form must carry no slash.
    while ([identifier hasPrefix:@"/"]) {
        identifier = [identifier substringFromIndex:1];
    }
    if (identifier.length == 0) {
        return NSFileProviderRootContainerItemIdentifier;
    }
    return identifier;
}

- (instancetype)initWithItemIdentity:(NSFileProviderItemIdentifier)identity;
{
     if (self = [super init]) {
         _itemIdentifier = [SeafItem canonicalIdentifier:identity];

         // The system container constants carry no encoded identity; decoding them would
         // misread the constant string as a server and break the isRoot checks.
         BOOL isSystemContainer = [_itemIdentifier isEqualToString:NSFileProviderRootContainerItemIdentifier]
                               || [_itemIdentifier isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier];
         if (!isSystemContainer) {
             NSArray *pathCompoents = _itemIdentifier.pathComponents; // encodedDir, filename
             if (pathCompoents.count >= 2) {
                 // A malformed legacy escape decodes to nil; falling back to the raw
                 // component keeps the item a file instead of silently flipping it into
                 // a container.
                 NSString *nameComponent = [pathCompoents objectAtIndex:1];
                 _filename = [nameComponent stringByRemovingPercentEncoding] ?: nameComponent;
             }
             if (pathCompoents.count >= 1) {
                 NSString *encodedDir = [pathCompoents objectAtIndex:0];
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
            _itemIdentifier = NSFileProviderRootContainerItemIdentifier;
        } else {
            NSString *encodedPath = [Utils encodePath:_server username:_username repo:_repoId path:_path];
            if (_filename) {
                //if doesnot encode, ä,ö,ü will encode to a%CC%88%2Co%CC%88%2Cu%CC%88 when upload
                _itemIdentifier = [NSString stringWithFormat:@"%@/%@", encodedPath, [_filename escapedUrl]];
            } else {
                _itemIdentifier = encodedPath;
            }
        }
    }
    return _itemIdentifier;
}

- (SeafItem *)parentItem
{
    // /account/repo/path
    if (self.isRoot) { // root
        return nil;
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
        if (_name.length == 0) {
            // A library root resolves to nil until the library list has been loaded.
            _name = _fallbackName;
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
        NSString *dirName = self.path.lastPathComponent;
        if (dirName.length == 0 || [dirName isEqualToString:@"/"]) {
            dirName = _fallbackName;
        }
        return [[SeafDir alloc] initWithConnection:self.conn oid:nil repoId:self.repoId perm:nil name:dirName path:self.path mtime:0];
    }
}

- (SeafBase *)toSeafObj
{
    if (self.isRoot) {
        return nil;
    } else {
        SeafBase *obj = [CACHE cachedObjectForKey:self.itemIdentifier];
        if (obj && ![self cachedObjectMatchesIdentity:obj]) {
            obj = nil;
        }
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

- (BOOL)cachedObjectMatchesIdentity:(SeafBase *)obj
{
    if (!obj) {
        return NO;
    }
    // An object built before the account list was loaded carries no connection and can never
    // load its content. Without this it would stay in the cache and keep failing long after
    // signing in, because the identity checks below say nothing about the connection.
    if (obj.connection != self.conn) {
        return NO;
    }
    if (self.isAccountRoot) {
        return [obj isKindOfClass:[SeafRepos class]];
    }
    if (self.isRepoRoot) {
        return [obj isKindOfClass:[SeafRepo class]]
            && [self.repoId isEqualToString:((SeafRepo *)obj).repoId];
    }
    if (self.isFile) {
        if (![obj isKindOfClass:[SeafFile class]]) {
            return NO;
        }
        SeafFile *file = (SeafFile *)obj;
        NSString *expectedPath = [self.path stringByAppendingPathComponent:self.filename];
        return [self.repoId isEqualToString:file.repoId]
            && [expectedPath isEqualToString:file.path];
    }
    if (![obj isKindOfClass:[SeafDir class]]) {
        return NO;
    }
    SeafDir *dir = (SeafDir *)obj;
    return [self.repoId isEqualToString:dir.repoId]
        && [self.path isEqualToString:dir.path];
}

- (void)updateCacheWithSubItem:(SeafItem *)item {
    SeafBase *obj = [CACHE cachedObjectForKey:self.itemIdentifier];
    if (obj != nil && item != nil && [obj isKindOfClass:[SeafDir class]]) {
        SeafDir *dir = (SeafDir *)obj;
        SeafBase *file = [item toSeafObj];
        NSMutableArray *mArr = [NSMutableArray arrayWithArray:dir.items];
        [mArr addObject:file];
        [dir loadedItems:mArr];
        [CACHE cacheObject:dir forKey:self.itemIdentifier];
    }
}

- (void)setTagData:(NSData *)tagData {
    _tagData = tagData;
    [self.conn saveFileProviderTagData:_tagData withItemIdentifier:self.itemIdentifier];
    if (tagData.length == 0) {
        // Clear the slash-prefixed key written by older builds too, or the getter's legacy
        // fallback below resurrects the cleared tag on the next rehydrate.
        [self.conn saveFileProviderTagData:nil withItemIdentifier:[@"/" stringByAppendingString:self.itemIdentifier]];
    }
}

- (NSData *)tagData {
    if (!_tagData) {
        _tagData = [self.conn loadFileProviderTagDataWithItemIdentifier:self.itemIdentifier];
        if (!_tagData) {
            // Tags written by older builds are keyed by the slash-prefixed identifier.
            NSString *legacyIdentifier = [@"/" stringByAppendingString:self.itemIdentifier];
            _tagData = [self.conn loadFileProviderTagDataWithItemIdentifier:legacyIdentifier];
        }
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
    return [[SeafItem alloc] initWithServer:repo.connection.address username:repo.connection.username repo:repo.repoId path:@"/" filename:nil];
}
+ (SeafItem *)fromSeafDir:(SeafDir *)dir
{
    return [[SeafItem alloc] initWithServer:dir.connection.address username:dir.connection.username repo:dir.repoId path:dir.path filename:nil];
}
+ (SeafItem *)fromSeafFile:(SeafFile *)file
{
    return [[SeafItem alloc] initWithServer:file.connection.address username:file.connection.username repo:file.repoId path:file.path.stringByDeletingLastPathComponent filename:file.name];
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

+ (SeafItem *)itemFromDict:(NSDictionary *)dict {
    NSString *identifier = [dict objectForKey:@"itemIdentifier"];
    if (identifier.length == 0) return nil;

    NSString *server = [dict objectForKey:@"server"];
    NSString *username = [dict objectForKey:@"username"];
    NSString *repoId = [dict objectForKey:@"repoId"];
    NSString *path = [dict objectForKey:@"path"];
    NSString *filename = [dict objectForKey:@"filename"];

    SeafItem *item = nil;
    if (server.length > 0) {
        item = [[SeafItem alloc] initWithServer:server username:username repo:repoId path:path filename:filename];
        item->_itemIdentifier = [SeafItem canonicalIdentifier:identifier];
    } else {
        item = [[SeafItem alloc] initWithItemIdentity:identifier];
        [item applyPersistedIdentityFromDict:dict];
    }

    // Assign the ivar directly: the tagData setter writes through to storage and kicks off
    // an iCloud sync, which must not happen while merely rehydrating a stored item.
    item->_tagData = [dict objectForKey:@"tagData"];
    item.lastUsedDate = [dict objectForKey:@"lastUsedDate"];
    item.favoriteRank = [dict objectForKey:@"favoriteRank"];
    [item applyFallbackName:[dict objectForKey:@"name"]];
    return item;
}

+ (NSDictionary *)localMetadataStore {
    NSDictionary *store = [SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER];
    return [store isKindOfClass:[NSDictionary class]] ? store : nil;
}

- (void)applyLocalMetadataFromStore:(NSDictionary *)store {
    if (store.count == 0) return;

    NSDictionary *dict = [store objectForKey:self.itemIdentifier];
    if (!dict) {
        dict = [store objectForKey:[SeafItem canonicalIdentifier:self.itemIdentifier]];
    }
    if (![dict isKindOfClass:[NSDictionary class]]) return;

    [self applyPersistedIdentityFromDict:dict];

    if (!self.favoriteRank) {
        self.favoriteRank = [dict objectForKey:@"favoriteRank"];
    }
    if (!self.lastUsedDate) {
        self.lastUsedDate = [dict objectForKey:@"lastUsedDate"];
    }
    [self applyFallbackName:[dict objectForKey:@"name"]];
}

/// Restores server-side identity from the metadata store. The display name alone is not
/// enough to enumerate a favorite after a cold start when identifier decoding fails or
/// when the on-disk bookmark slug no longer matches the encoded path component.
- (void)applyPersistedIdentityFromDict:(NSDictionary *)dict {
    NSString *server = [dict objectForKey:@"server"];
    if (server.length > 0) {
        _server = server;
        _conn = nil;
    }
    NSString *username = [dict objectForKey:@"username"];
    if (username.length > 0) {
        _username = username;
        _conn = nil;
    }
    NSString *repoId = [dict objectForKey:@"repoId"];
    if (repoId.length > 0) {
        _repoId = repoId;
    }
    NSString *path = [dict objectForKey:@"path"];
    if (path.length > 0) {
        _path = path;
    }
    NSString *filename = [dict objectForKey:@"filename"];
    if (filename.length > 0) {
        _filename = filename;
    }
}

/// Only used when the live name cannot be resolved, e.g. a library root whose library list
/// has not been loaded yet.
- (void)applyFallbackName:(NSString *)name {
    if (name.length > 0) {
        _fallbackName = name;
    }
}

@end
