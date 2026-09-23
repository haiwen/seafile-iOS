//
//  SeafFileProviderLegacyMigrator.m
//  seafile
//

#import "SeafFileProviderLegacyMigrator.h"
#import "SeafFileProviderDomainManager.h"
#import "SeafFPIdentifier.h"
#import "SeafFPStore.h"
#import "SeafGlobal.h"
#import "SeafConnection.h"
#import "SeafStorage.h"
#import "Constants.h"
#import "Utils.h"
#import "Debug.h"

// Same values SeafConnection uses for its per-account tag dictionary.
static NSString * const kLegacyTagDataPrefix = @"TagData";

@interface SeafFPLegacyEntry : NSObject
@property (nonatomic, strong) SeafConnection *connection;
@property (nonatomic, copy) NSString *repoId;
@property (nonatomic, copy, nullable) NSString *path;      // directory path ("/" for the library root)
@property (nonatomic, copy, nullable) NSString *filename;  // nil for directories
@property (nonatomic, strong, nullable) NSNumber *favoriteRank;
@property (nonatomic, strong, nullable) NSData *tagData;
@property (nonatomic, strong, nullable) NSDate *lastUsedDate;
@end

@implementation SeafFPLegacyEntry
@end

@implementation SeafFileProviderLegacyMigrator

+ (BOOL)parseLegacyIdentifier:(NSString *)identifier
                       server:(NSString **)server
                     username:(NSString **)username
                       repoId:(NSString **)repoId
                         path:(NSString **)path
                     filename:(NSString **)filename
{
    if (server) *server = nil;
    if (username) *username = nil;
    if (repoId) *repoId = nil;
    if (path) *path = nil;
    if (filename) *filename = nil;
    if (identifier.length == 0) return NO;

    NSString *normalized = [identifier hasPrefix:@"/"] ? identifier : [@"/" stringByAppendingString:identifier];
    NSArray<NSString *> *components = normalized.pathComponents;   // "/", encodedDir, filename
    if (components.count < 2) return NO;

    NSString *s = nil, *u = nil, *r = nil, *p = nil;
    [Utils decodePath:components[1] server:&s username:&u repo:&r path:&p];
    if (r.length == 0) return NO;
    if (server) *server = s;
    if (username) *username = u;
    if (repoId) *repoId = r;
    if (path) *path = p.length > 0 ? p : @"/";
    if (filename && components.count >= 3) {
        *filename = [components[2] stringByRemovingPercentEncoding];
    }
    return YES;
}

+ (SeafConnection *)connectionForServer:(NSString *)server username:(NSString *)username in:(NSArray<SeafConnection *> *)connections
{
    if (server.length == 0 || username.length == 0) return nil;
    NSString *wanted = [SeafFPIdentifier normalizedAddress:server];
    for (SeafConnection *conn in connections) {
        if ([[SeafFPIdentifier normalizedAddress:conn.address] isEqualToString:wanted]
            && [conn.username isEqualToString:username]) {
            return conn;
        }
    }
    return nil;
}

+ (NSString *)entryKeyForEntry:(SeafFPLegacyEntry *)entry
{
    NSString *full = entry.filename.length > 0
        ? [(entry.path ?: @"/") stringByAppendingPathComponent:entry.filename]
        : (entry.path ?: @"/");
    return [NSString stringWithFormat:@"%@|%@|%@",
            [SeafFileProviderDomainManager domainIdentifierForConnection:entry.connection],
            entry.repoId,
            [SeafFPIdentifier normalizedPath:full]];
}

+ (NSMutableDictionary<NSString *, SeafFPLegacyEntry *> *)collectEntriesWithConnections:(NSArray<SeafConnection *> *)connections
                                                                               legacyKeys:(NSMutableArray<NSString *> *)legacyKeys
{
    NSMutableDictionary<NSString *, SeafFPLegacyEntry *> *entries = [NSMutableDictionary dictionary];

    // Source 1: the provider's own metadata dictionary.
    NSDictionary *legacy = [SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER];
    if ([legacy isKindOfClass:[NSDictionary class]]) {
        [legacyKeys addObject:SEAF_FILE_PROVIDER];
        [legacy enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, NSDictionary *dict, BOOL *stop) {
            if (![dict isKindOfClass:[NSDictionary class]]) return;
            NSString *server = dict[@"server"], *username = dict[@"username"], *repoId = dict[@"repoId"];
            NSString *path = dict[@"path"], *filename = dict[@"filename"];
            if (repoId.length == 0) {
                if (![self parseLegacyIdentifier:identifier server:&server username:&username repoId:&repoId path:&path filename:&filename]) {
                    Debug("legacy favorite skipped, unparsable identifier %@", identifier);
                    return;
                }
            }
            SeafConnection *conn = [self connectionForServer:server username:username in:connections];
            if (!conn) {
                Debug("legacy favorite skipped, no account for %@ %@", server, username);
                return;
            }
            SeafFPLegacyEntry *entry = [SeafFPLegacyEntry new];
            entry.connection = conn;
            entry.repoId = repoId;
            entry.path = path.length > 0 ? path : @"/";
            entry.filename = filename.length > 0 ? filename : nil;
            id rank = dict[@"favoriteRank"];
            entry.favoriteRank = [rank isKindOfClass:[NSNumber class]] ? rank : nil;
            id tag = dict[@"tagData"];
            entry.tagData = ([tag isKindOfClass:[NSData class]] && ((NSData *)tag).length > 0) ? tag : nil;
            id used = dict[@"lastUsedDate"];
            entry.lastUsedDate = [used isKindOfClass:[NSDate class]] ? used : nil;
            if (!entry.favoriteRank && !entry.tagData) return;
            NSString *key = [self entryKeyForEntry:entry];
            SeafFPLegacyEntry *existing = entries[key];
            if (existing) {
                existing.favoriteRank = existing.favoriteRank ?: entry.favoriteRank;
                existing.tagData = existing.tagData ?: entry.tagData;
                existing.lastUsedDate = existing.lastUsedDate ?: entry.lastUsedDate;
            } else {
                entries[key] = entry;
            }
        }];
    }

    // Source 2: per-account tag dictionaries written by SeafConnection.
    for (SeafConnection *conn in connections) {
        NSString *tagKey = [NSString stringWithFormat:@"%@/%@", kLegacyTagDataPrefix, conn.accountIdentifier];
        NSDictionary *tags = [SeafStorage.sharedObject objectForKey:tagKey];
        if (![tags isKindOfClass:[NSDictionary class]]) continue;
        [legacyKeys addObject:tagKey];
        [tags enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, NSData *tagData, BOOL *stop) {
            if (![tagData isKindOfClass:[NSData class]] || tagData.length == 0) return;
            NSString *server = nil, *username = nil, *repoId = nil, *path = nil, *filename = nil;
            if (![self parseLegacyIdentifier:identifier server:&server username:&username repoId:&repoId path:&path filename:&filename]) {
                Debug("legacy tag skipped, unparsable identifier %@", identifier);
                return;
            }
            SeafFPLegacyEntry *entry = [SeafFPLegacyEntry new];
            entry.connection = conn;
            entry.repoId = repoId;
            entry.path = path;
            entry.filename = filename;
            entry.tagData = tagData;
            NSString *key = [self entryKeyForEntry:entry];
            SeafFPLegacyEntry *existing = entries[key];
            if (existing) {
                existing.tagData = existing.tagData ?: tagData;
            } else {
                entries[key] = entry;
            }
        }];
    }
    return entries;
}

+ (BOOL)migrateIfNeededWithConnections:(NSArray<SeafConnection *> *)connections
{
    if ([SeafStorage.sharedObject objectForKey:SEAF_FP_MIGRATED]) {
        return NO;
    }
    NSMutableArray<NSString *> *legacyKeys = [NSMutableArray array];
    NSDictionary<NSString *, SeafFPLegacyEntry *> *entries = [self collectEntriesWithConnections:connections legacyKeys:legacyKeys];

    NSMutableDictionary<NSString *, SeafFPStore *> *stores = [NSMutableDictionary dictionary];
    NSUInteger migrated = 0;
    BOOL storeFailed = NO;
    for (SeafFPLegacyEntry *entry in entries.allValues) {
        NSString *domainId = [SeafFileProviderDomainManager domainIdentifierForConnection:entry.connection];
        SeafFPStore *store = stores[domainId];
        if (!store) {
            NSError *error = nil;
            store = [[SeafFPStore alloc] initWithDomainIdentifier:domainId error:&error];
            if (!store) {
                Warning("Cannot open store %@ for migration: %@", domainId, error);
                storeFailed = YES;
                continue;
            }
            stores[domainId] = store;
        }
        NSString *itemIdentifier = nil;
        BOOL isRepoRoot = entry.filename.length == 0 && [[SeafFPIdentifier normalizedPath:entry.path] isEqualToString:@"/"];
        if (isRepoRoot) {
            itemIdentifier = [SeafFPIdentifier identifierForRepo:entry.repoId];
        } else {
            NSString *full = entry.filename.length > 0 ? [entry.path stringByAppendingPathComponent:entry.filename] : entry.path;
            SeafFPRecord *record = [store ensureRecordChainForRepo:entry.repoId path:full isDir:(entry.filename.length == 0)];
            if (!record) continue;
            itemIdentifier = record.itemIdentifier;
        }
        SeafFPDecoration *decoration = [store decorationForItem:itemIdentifier] ?: [SeafFPDecoration new];
        decoration.itemIdentifier = itemIdentifier;
        decoration.favoriteRank = entry.favoriteRank ?: decoration.favoriteRank;
        decoration.tagData = entry.tagData ?: decoration.tagData;
        decoration.lastUsedDate = entry.lastUsedDate ?: decoration.lastUsedDate;
        [store setDecoration:decoration];

        SeafFPWorkingSetReason reason = SeafFPWorkingSetReasonMigrated;
        if (decoration.favoriteRank != nil) reason |= SeafFPWorkingSetReasonFavorite;
        if (decoration.tagData.length > 0) reason |= SeafFPWorkingSetReasonTag;
        [store addWorkingSetItem:itemIdentifier reason:reason];
        migrated += 1;
        Debug("migrated legacy favorite %@ (%@ %@/%@) fav=%@ tag=%lu", itemIdentifier, entry.repoId, entry.path, entry.filename ?: @"", entry.favoriteRank, (unsigned long)entry.tagData.length);
    }
    for (SeafFPStore *store in stores.allValues) {
        [store setMetaValue:[NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]] forKey:@"migrated_at"];
        [store close];
    }
    if (storeFailed) {
        // Keep the legacy data and the "not migrated" state: the writes above
        // are idempotent upserts, the next launch tries again.
        Warning("legacy file provider migration incomplete (%lu entries done), retrying next launch", (unsigned long)migrated);
        return migrated > 0;
    }
    for (NSString *key in legacyKeys) {
        [SeafStorage.sharedObject removeObjectForKey:key];
    }
    [SeafStorage.sharedObject setObject:@([[NSDate date] timeIntervalSince1970]) forKey:SEAF_FP_MIGRATED];
    [SeafStorage.sharedObject synchronize];
    Debug("legacy file provider migration done: %lu entries, %lu keys removed", (unsigned long)migrated, (unsigned long)legacyKeys.count);
    return migrated > 0;
}

@end
