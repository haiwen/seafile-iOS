//
//  SeafRecentDirsStore.m
//  seafile
//

#import "SeafRecentDirsStore.h"

static NSString * const kSeafRecentDirsKeyPrefix = @"seaf_recent_dirs_"; // + account id
static const NSInteger kSeafRecentMaxDefault = 20;

@implementation SeafRecentDirsStore

+ (instancetype)shared
{
    static SeafRecentDirsStore *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [SeafRecentDirsStore new]; });
    return inst;
}

- (NSString *)accountKeyForConnection:(SeafConnection *)connection
{
    NSString *host = connection.address ? : @"";
    NSString *user = connection.username ? : @"";
    return [NSString stringWithFormat:@"%@%@_%@", kSeafRecentDirsKeyPrefix, host, user];
}

- (NSArray<NSDictionary *> *)loadRecordsForConnection:(SeafConnection *)connection
{
    NSString *key = [self accountKeyForConnection:connection];
    NSArray *arr = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (![arr isKindOfClass:[NSArray class]]) return @[];
    return arr;
}

- (void)saveRecords:(NSArray<NSDictionary *> *)records connection:(SeafConnection *)connection
{
    NSString *key = [self accountKeyForConnection:connection];
    [[NSUserDefaults standardUserDefaults] setObject:records forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)addRecentDirectory:(SeafDir *)directory
{
    if (!directory || !directory.connection || directory.repoId.length == 0 || directory.path.length == 0) return;
    SeafConnection *conn = directory.connection;
    NSMutableArray<NSDictionary *> *records = [[self loadRecordsForConnection:conn] mutableCopy];
    if (!records) records = [NSMutableArray array];
    NSString *uid = [NSString stringWithFormat:@"%@|%@", directory.repoId, directory.path];

    // remove existing
    NSInteger existingIndex = NSNotFound;
    for (NSInteger i = 0; i < records.count; i++) {
        NSDictionary *r = records[i];
        NSString *rid = r[@"repoId"]; NSString *pth = r[@"path"];
        if ([rid isKindOfClass:[NSString class]] && [pth isKindOfClass:[NSString class]]) {
            if ([uid isEqualToString:[NSString stringWithFormat:@"%@|%@", rid, pth]]) { existingIndex = i; break; }
        }
    }
    if (existingIndex != NSNotFound) [records removeObjectAtIndex:existingIndex];

    NSDictionary *rec = @{ @"repoId": directory.repoId ?: @"",
                            @"path": directory.path ?: @"/",
                            @"repoName": directory.repoName ?: @"",
                            @"dirName": directory.name ?: @"",
                            @"time": @([[NSDate date] timeIntervalSince1970]) };
    [records insertObject:rec atIndex:0];

    // cap size
    NSInteger max = kSeafRecentMaxDefault;
    if (records.count > max) {
        [records removeObjectsInRange:NSMakeRange(max, records.count - max)];
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
    SeafDir *dir = [[SeafDir alloc] initWithConnection:connection oid:nil repoId:repoId perm:nil name:dirName path:path mtime:0];
    dir.repoName = repoName;
    return dir;
}

@end


