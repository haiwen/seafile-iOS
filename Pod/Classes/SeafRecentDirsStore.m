//
//  SeafRecentDirsStore.m
//  Seafile
//
//  Shared recent-directory history for the main app and share extension.
//  Persisted in the App Group so both targets see the same data.
//

#import "SeafRecentDirsStore.h"
#import "SeafConstants.h"
#import "SeafRepos.h"

static NSString * const kSeafRecentDirsKeyPrefix = @"seaf_recent_dirs_";
// Per-process flag (stored in the process's own standardUserDefaults) gating the
// one-time copy of that process's local recent dirs into the App Group. It MUST be
// per-process: the main app's legacy data lives in its own standardUserDefaults, so a
// shared flag set by the extension (which has no such data) would suppress the main
// app's migration and lose the user's history.
static NSString * const kSeafRecentLocalMigratedKey = @"seaf_recent_local_migrated_v1";
// Shared flag (stored in the App Group) gating the one-time merge of the legacy flat
// share-extension list, which is global rather than per-process.
static NSString * const kSeafRecentShareMigratedKey = @"seaf_recent_share_migrated_v1";
static NSString * const kLegacyShareRecentPathsKey = @"SeafShare_RecentPaths";
static const NSInteger kSeafRecentMaxDefault = 20;

@implementation SeafRecentDirsStore

+ (instancetype)shared
{
    static SeafRecentDirsStore *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [SeafRecentDirsStore new];
        [inst migrateIfNeeded];
    });
    return inst;
}

#pragma mark - Storage

- (NSUserDefaults *)sharedDefaults
{
    return [[NSUserDefaults alloc] initWithSuiteName:SEAFILE_SUITE_NAME];
}

- (NSString *)accountKeyForConnection:(SeafConnection *)connection
{
    NSString *host = connection.address ?: @"";
    NSString *user = connection.username ?: @"";
    return [NSString stringWithFormat:@"%@%@_%@", kSeafRecentDirsKeyPrefix, host, user];
}

- (NSString *)accountKeyForAddress:(NSString *)address username:(NSString *)username
{
    return [NSString stringWithFormat:@"%@%@_%@", kSeafRecentDirsKeyPrefix, address ?: @"", username ?: @""];
}

- (NSArray<NSDictionary *> *)loadRecordsForConnection:(SeafConnection *)connection
{
    NSString *key = [self accountKeyForConnection:connection];
    NSArray *arr = [[self sharedDefaults] objectForKey:key];
    if (![arr isKindOfClass:[NSArray class]]) return @[];
    return arr;
}

- (void)saveRecords:(NSArray<NSDictionary *> *)records connection:(SeafConnection *)connection
{
    NSString *key = [self accountKeyForConnection:connection];
    NSUserDefaults *defaults = [self sharedDefaults];
    [defaults setObject:records forKey:key];
    [defaults synchronize];
}

#pragma mark - Migration

- (void)migrateIfNeeded
{
    NSUserDefaults *group = [self sharedDefaults];

    // 1. Merge this process's local recent dirs into the App Group (per-process flag).
    // Merge (not skip-if-exists): the App Group key may already hold data written by
    // the other process, so an all-or-nothing copy could drop this process's history.
    NSUserDefaults *standard = [NSUserDefaults standardUserDefaults];
    if (![standard boolForKey:kSeafRecentLocalMigratedKey]) {
        for (NSString *key in [standard dictionaryRepresentation]) {
            if (![key hasPrefix:kSeafRecentDirsKeyPrefix]) continue;
            id value = [standard objectForKey:key];
            if (![value isKindOfClass:[NSArray class]]) continue;
            NSArray *merged = [self unionRecords:value with:[group objectForKey:key]];
            [group setObject:merged forKey:key];
        }
        [standard setBool:YES forKey:kSeafRecentLocalMigratedKey];
        [standard synchronize];
    }

    // 2. Merge the legacy flat share-extension list once, globally (shared flag).
    if (![group boolForKey:kSeafRecentShareMigratedKey]) {
        NSArray *legacyPaths = [group objectForKey:kLegacyShareRecentPathsKey];
        if (![legacyPaths isKindOfClass:[NSArray class]]) {
            NSUserDefaults *legacySuite = [[NSUserDefaults alloc] initWithSuiteName:APP_ID];
            legacyPaths = [legacySuite objectForKey:kLegacyShareRecentPathsKey];
        }
        if ([legacyPaths isKindOfClass:[NSArray class]]) {
            [self mergeLegacySharePaths:legacyPaths intoDefaults:group];
        }
        [group removeObjectForKey:kLegacyShareRecentPathsKey];
        [group setBool:YES forKey:kSeafRecentShareMigratedKey];
    }

    [group synchronize];
}

- (void)mergeLegacySharePaths:(NSArray *)legacyPaths intoDefaults:(NSUserDefaults *)group
{
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *legacyByKey = [NSMutableDictionary dictionary];

    for (id obj in legacyPaths) {
        if (![obj isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *item = (NSDictionary *)obj;
        NSString *account = [item[@"account"] isKindOfClass:[NSString class]] ? item[@"account"] : nil;
        NSString *repoId = [item[@"repoId"] isKindOfClass:[NSString class]] ? item[@"repoId"] : nil;
        if (account.length == 0 || repoId.length == 0) continue;

        NSRange slash = [account rangeOfString:@"/" options:NSBackwardsSearch];
        if (slash.location == NSNotFound) continue;
        NSString *address = [account substringToIndex:slash.location];
        NSString *username = [account substringFromIndex:slash.location + 1];
        NSString *key = [self accountKeyForAddress:address username:username];

        NSMutableArray<NSDictionary *> *records = legacyByKey[key];
        if (!records) {
            records = [NSMutableArray array];
            legacyByKey[key] = records;
        }

        NSNumber *time = [item[@"time"] isKindOfClass:[NSNumber class]] ? item[@"time"] : nil;
        if (!time && [item[@"timestamp"] isKindOfClass:[NSNumber class]]) {
            time = item[@"timestamp"];
        }
        NSDictionary *rec = @{
            @"repoId": repoId,
            @"path": [item[@"path"] isKindOfClass:[NSString class]] ? item[@"path"] : @"/",
            @"repoName": [item[@"repoName"] isKindOfClass:[NSString class]] ? item[@"repoName"] : @"",
            @"dirName": [item[@"dirName"] isKindOfClass:[NSString class]] ? item[@"dirName"] : @"",
            @"time": time ?: @([[NSDate date] timeIntervalSince1970]),
        };
        [records addObject:rec];
    }

    for (NSString *key in legacyByKey) {
        NSArray *merged = [self unionRecords:legacyByKey[key] with:[group objectForKey:key]];
        [group setObject:merged forKey:key];
    }
}

// Union two record arrays, dedup by repoId|path keeping the most recent (by "time"),
// sort newest-first, and cap at the max. Never drops entries that only exist in one side.
- (NSArray<NSDictionary *> *)unionRecords:(NSArray *)a with:(NSArray *)b
{
    NSMutableArray<NSDictionary *> *all = [NSMutableArray array];
    if ([a isKindOfClass:[NSArray class]]) [all addObjectsFromArray:a];
    if ([b isKindOfClass:[NSArray class]]) [all addObjectsFromArray:b];

    NSMutableDictionary<NSString *, NSDictionary *> *byUid = [NSMutableDictionary dictionary];
    for (NSDictionary *r in all) {
        if (![r isKindOfClass:[NSDictionary class]]) continue;
        NSString *rid = [r[@"repoId"] isKindOfClass:[NSString class]] ? r[@"repoId"] : nil;
        if (rid.length == 0) continue;
        NSString *pth = [r[@"path"] isKindOfClass:[NSString class]] ? r[@"path"] : @"/";
        NSString *uid = [NSString stringWithFormat:@"%@|%@", rid, pth];

        NSDictionary *existing = byUid[uid];
        if (!existing) {
            byUid[uid] = r;
        } else {
            double te = [existing[@"time"] isKindOfClass:[NSNumber class]] ? [existing[@"time"] doubleValue] : 0;
            double tr = [r[@"time"] isKindOfClass:[NSNumber class]] ? [r[@"time"] doubleValue] : 0;
            if (tr >= te) byUid[uid] = r;
        }
    }

    NSArray<NSDictionary *> *sorted = [byUid.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
        double tx = [x[@"time"] isKindOfClass:[NSNumber class]] ? [x[@"time"] doubleValue] : 0;
        double ty = [y[@"time"] isKindOfClass:[NSNumber class]] ? [y[@"time"] doubleValue] : 0;
        if (tx > ty) return NSOrderedAscending;
        if (tx < ty) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    if (sorted.count > kSeafRecentMaxDefault) {
        sorted = [sorted subarrayWithRange:NSMakeRange(0, kSeafRecentMaxDefault)];
    }
    return sorted;
}

- (void)insertRecord:(NSDictionary *)rec intoRecords:(NSMutableArray<NSDictionary *> *)records
{
    NSString *repoId = rec[@"repoId"];
    NSString *path = rec[@"path"];
    NSString *uid = [NSString stringWithFormat:@"%@|%@", repoId, path];

    for (NSInteger i = records.count - 1; i >= 0; i--) {
        NSDictionary *r = records[i];
        NSString *rid = r[@"repoId"];
        NSString *pth = r[@"path"];
        if ([rid isKindOfClass:[NSString class]] && [pth isKindOfClass:[NSString class]]) {
            if ([uid isEqualToString:[NSString stringWithFormat:@"%@|%@", rid, pth]]) {
                [records removeObjectAtIndex:i];
                break;
            }
        }
    }
    [records insertObject:rec atIndex:0];
}

#pragma mark - Public API

- (void)addRecentDirectory:(SeafDir *)directory
{
    if (!directory || !directory.connection || directory.repoId.length == 0 || directory.path.length == 0) return;
    SeafConnection *conn = directory.connection;
    NSMutableArray<NSDictionary *> *records = [[self loadRecordsForConnection:conn] mutableCopy];
    if (!records) records = [NSMutableArray array];

    NSDictionary *rec = @{ @"repoId": directory.repoId ?: @"",
                           @"path": directory.path ?: @"/",
                           @"repoName": directory.repoName ?: @"",
                           @"dirName": directory.name ?: @"",
                           @"time": @([[NSDate date] timeIntervalSince1970]) };
    [self insertRecord:rec intoRecords:records];

    if (records.count > kSeafRecentMaxDefault) {
        [records removeObjectsInRange:NSMakeRange(kSeafRecentMaxDefault, records.count - kSeafRecentMaxDefault)];
    }
    [self saveRecords:records connection:conn];
}

- (NSArray<NSDictionary *> *)recentDirectoriesForConnection:(SeafConnection *)connection maxCount:(NSInteger)max
{
    NSArray *records = [self loadRecordsForConnection:connection];
    if (max <= 0) max = kSeafRecentMaxDefault;
    if (records.count <= max) return records;
    return [records subarrayWithRange:NSMakeRange(0, max)];
}

- (SeafDir *)directoryFromRecord:(NSDictionary *)record connection:(SeafConnection *)connection
{
    NSString *repoId = record[@"repoId"]; if (![repoId isKindOfClass:[NSString class]]) return nil;
    NSString *path = record[@"path"]; if (![path isKindOfClass:[NSString class]]) return nil;
    NSString *repoName = [record[@"repoName"] isKindOfClass:[NSString class]] ? record[@"repoName"] : @"";
    NSString *dirName = [record[@"dirName"] isKindOfClass:[NSString class]] ? record[@"dirName"] : nil;
    if (dirName.length == 0) {
        dirName = path.lastPathComponent.length > 0 ? path.lastPathComponent : repoName;
    }

    if ([path isEqualToString:@"/"]) {
        SeafRepo *repo = [connection getRepo:repoId];
        if (repo) return repo;
    }

    SeafDir *dir = [[SeafDir alloc] initWithConnection:connection oid:nil repoId:repoId perm:nil name:dirName path:path mtime:0];
    dir.repoName = repoName;
    return dir;
}

@end
