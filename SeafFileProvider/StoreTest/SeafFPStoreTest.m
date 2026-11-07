#import <Foundation/Foundation.h>
#import "SeafFPStore.h"
#import <sqlite3.h>
#import "SeafFPIdentifier.h"

static NSString *gTestDir;
static int passes = 0, failures = 0;

@implementation SeafFPIdentifier (StoreTest)
+ (NSURL *)storeDirectoryURL { return [NSURL fileURLWithPath:gTestDir isDirectory:YES]; }
+ (NSURL *)storeURLForDomainIdentifier:(NSString *)domainIdentifier {
    return [[self storeDirectoryURL] URLByAppendingPathComponent:[domainIdentifier stringByAppendingPathExtension:@"sqlite"] isDirectory:NO];
}
@end

#define CHECK(cond, ...) do { if (!(cond)) { failures++; NSLog(@"FAIL line %d: %s -- %@", __LINE__, #cond, [NSString stringWithFormat:@"" __VA_ARGS__]); } else { passes++; } } while (0)

static BOOL eq(NSString *a, NSString *b) { return (a == nil && b == nil) || [a isEqualToString:b]; }

/// Listing entry (name) / sparse entry (path) for the main app indexing API.
static NSDictionary *LE(NSString *name, BOOL isDir, NSString *oid, long long size, long long mtime)
{
    NSMutableDictionary *d = [@{SeafFPEntryName: name, SeafFPEntryIsDir: @(isDir), SeafFPEntrySize: @(size), SeafFPEntryMtime: @(mtime)} mutableCopy];
    if (oid) d[SeafFPEntryOid] = oid;
    return d;
}

static NSDictionary *SE(NSString *path, BOOL isDir, NSString *oid, long long size, long long mtime)
{
    NSMutableDictionary *d = [@{SeafFPEntryPath: path, SeafFPEntryIsDir: @(isDir), SeafFPEntrySize: @(size), SeafFPEntryMtime: @(mtime)} mutableCopy];
    if (oid) d[SeafFPEntryOid] = oid;
    return d;
}

/// Activity log entry.
static NSDictionary *AE(NSString *op, NSString *path, NSString *oldPath, BOOL isDir, long long time)
{
    NSMutableDictionary *d = [@{SeafFPEntryOp: op, SeafFPEntryPath: path, SeafFPEntryIsDir: @(isDir), SeafFPEntryMtime: @(time)} mutableCopy];
    if (oldPath) d[SeafFPEntryOldPath] = oldPath;
    return d;
}

static SeafFPRecord *reviewRow(SeafFPStore *store, NSString *repo, NSString *path, BOOL isDir, NSString *parent, NSString *oid)
{
    return [store upsertRecordForRepo:repo path:path isDir:isDir parentUUID:parent oid:oid mtime:10 size:(isDir ? -1 : 5)];
}

static void reviewFavorite(SeafFPStore *store, SeafFPRecord *record)
{
    SeafFPDecoration *decoration = [SeafFPDecoration new];
    decoration.itemIdentifier = record.itemIdentifier;
    decoration.favoriteRank = @42;
    [store setDecoration:decoration];
    [store addWorkingSetItem:record.itemIdentifier reason:SeafFPWorkingSetReasonFavorite];
}


@interface SeafFPStore (PublicationFailureTest)
- (BOOL)execLocked:(NSString *)sql;
@end
@interface FailingPublicationStore : SeafFPStore
@property BOOL failBegin;
@property BOOL failCommit;
@end
@implementation FailingPublicationStore
- (BOOL)execLocked:(NSString *)sql {
    if (self.failBegin && [sql isEqual:@"BEGIN IMMEDIATE"]) return NO;
    if (self.failCommit && [sql isEqual:@"COMMIT"]) { self.failCommit=NO; return NO; }
    return [super execLocked:sql];
}
@end

@interface SeafFPStore (StatementFailureTest)
- (int)stepLocked:(sqlite3_stmt *)stmt;
- (void)noteFailureLocked:(int)rc;
@end
/// Fails every statement whose expanded SQL the block accepts, like an I/O
/// error would (SQLITE_IOERR, recorded for the enclosing transaction).
@interface FailingStatementStore : SeafFPStore
@property (copy) BOOL (^failStatement)(NSString *sql);
@end
@implementation FailingStatementStore
- (int)stepLocked:(sqlite3_stmt *)stmt {
    if (self.failStatement) {
        char *sql = sqlite3_expanded_sql(stmt);
        BOOL fail = sql && self.failStatement(@(sql));
        sqlite3_free(sql);
        if (fail) { [self noteFailureLocked:SQLITE_IOERR]; return SQLITE_IOERR; }
    }
    return [super stepLocked:stmt];
}
@end

static void runStatementFailureTests(void)
{
    // A failed child write inside a move must not commit the moved parent.
    FailingStatementStore *s = [[FailingStatementStore alloc] initWithDomainIdentifier:@"statement-failure" error:nil];
    SeafFPRecord *d = [s upsertRecordForRepo:@"r1" path:@"/D" isDir:YES parentUUID:nil oid:@"d" mtime:10 size:-1];
    SeafFPRecord *c = [s upsertRecordForRepo:@"r1" path:@"/D/c.txt" isDir:NO parentUUID:d.uuid oid:@"c" mtime:10 size:5];
    long long before = s.currentSeq;
    s.failStatement = ^BOOL(NSString *sql) { return [sql hasPrefix:@"UPDATE identity SET repo_id"] && [sql containsString:@"c.txt"]; };
    SeafFPRecord *moved = [s moveRecordUUID:d.uuid toRepo:@"r2" path:@"/X" parentUUID:nil];
    s.failStatement = nil;
    SeafFPRecord *dAfter = [s recordForUUID:d.uuid], *cAfter = [s recordForUUID:c.uuid];
    CHECK(moved == nil, @"a move whose child write failed reports failure");
    CHECK(eq(dAfter.repoId, @"r1") && eq(dAfter.path, @"/D") && eq(cAfter.repoId, @"r1") && eq(cAfter.path, @"/D/c.txt"),
          @"nothing of the failed move is committed: %@ %@", dAfter, cAfter);
    CHECK(s.currentSeq == before, @"the seq counter is rolled back too (%lld vs %lld)", s.currentSeq, before);

    // A failed read is not "no such row": the listing is not applied at all.
    s.failStatement = ^BOOL(NSString *sql) { return [sql hasPrefix:@"SELECT"] && [sql containsString:@"'/D/b.txt'"]; };
    BOOL applied = [s applyListingOfRepo:@"r1" directoryPath:@"/D"
                                 entries:@[LE(@"a.txt", NO, @"a", 1, 10), LE(@"b.txt", NO, @"b", 1, 10)]
                         requestStartSeq:s.currentSeq];
    s.failStatement = nil;
    CHECK(!applied && ![s recordForRepo:@"r1" path:@"/D/a.txt" includeDeleted:YES] && ![s recordForUUID:c.uuid].deleted,
          @"a listing with a failed read writes nothing");

    // A seq that cannot be handed out never ends up as a row with seq 0.
    s.failStatement = ^BOOL(NSString *sql) { return [sql hasPrefix:@"UPDATE meta SET value = CAST"]; };
    SeafFPRecord *zero = [s upsertRecordForRepo:@"r1" path:@"/zero.txt" isDir:NO parentUUID:nil oid:@"z" mtime:10 size:1];
    s.failStatement = nil;
    CHECK(zero == nil && ![s recordForRepo:@"r1" path:@"/zero.txt" includeDeleted:YES], @"no row without a seq");

    // performBatch reports the failure and keeps nothing of the batch.
    s.failStatement = ^BOOL(NSString *sql) { return [sql hasPrefix:@"INSERT INTO identity"] && [sql containsString:@"/batch-2.txt"]; };
    BOOL committed = [s performBatch:^{
        [s upsertRecordForRepo:@"r1" path:@"/batch-1.txt" isDir:NO parentUUID:nil oid:@"1" mtime:10 size:1];
        [s upsertRecordForRepo:@"r1" path:@"/batch-2.txt" isDir:NO parentUUID:nil oid:@"2" mtime:10 size:1];
    }];
    s.failStatement = nil;
    CHECK(!committed && ![s recordForRepo:@"r1" path:@"/batch-1.txt" includeDeleted:YES], @"failed batch rolled back as a whole");
    CHECK([s upsertRecordForRepo:@"r1" path:@"/after.txt" isDir:NO parentUUID:nil oid:@"3" mtime:10 size:1] != nil,
          @"the next transaction is not affected by the earlier failure");
    [s close];
}

static void runDirectoryCheckTests(void)
{
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"directory-checks" error:nil];
    SeafFPRecord *dir = [s upsertRecordForRepo:@"r" path:@"/Cam" isDir:YES parentUUID:nil oid:@"d" mtime:10 size:-1];
    SeafFPRecord *f = [s upsertRecordForRepo:@"src" path:@"/f.txt" isDir:NO parentUUID:nil oid:@"f" mtime:10 size:5];
    [s moveRecordsOfRepo:@"src" fromDirectory:@"/" names:@[@"f.txt"] toRepo:@"r" toDirectory:@"/Cam"
      destinationEntries:@[LE(@"f.txt", NO, @"f", 5, 10)] requestStartSeq:s.currentSeq];

    // A response already in flight when the check was registered cannot confirm it (P5).
    long long inFlight = s.currentSeq;
    [s applyActivitiesOfRepo:@"r" entries:@[AE(SeafFPActivityOpDelete, @"/Cam/f.txt", nil, NO, 500)]];
    CHECK([[s activityRecheckDirectoryPathsOfRepo:@"r"] isEqual:@[@"/Cam"]] && s.currentSeq > inFlight, @"check registered with a new version");
    [s applyListingOfRepo:@"r" directoryPath:@"/Cam" entries:@[LE(@"f.txt", NO, @"f", 5, 10)] requestStartSeq:inFlight];
    CHECK([[s activityRecheckDirectoryPathsOfRepo:@"r"] isEqual:@[@"/Cam"]], @"older response leaves the check pending");

    // Siblings written while each listing is in flight do not keep the check pending (P12).
    long long S = s.currentSeq;
    [s upsertRecordForRepo:@"r" path:@"/Cam/img.jpg" isDir:NO parentUUID:dir.uuid oid:@"i" mtime:20 size:5];
    CHECK([s applyDirectoryListingOfRepo:@"r" directoryPath:@"/Cam" entries:@[LE(@"f.txt", NO, @"f", 5, 10)] requestStartSeq:S] != SeafFPWriteFailed,
          @"listing applies around the newer sibling");
    SeafFPRecord *img0 = [s recordForRepo:@"r" path:@"/Cam/img.jpg" includeDeleted:NO];
    CHECK(img0 && !img0.deleted && [s recordForUUID:f.uuid] && ![s recordForUUID:f.uuid].deleted, @"newer sibling kept");
    // The sibling the listing could not show is verified by a later listing,
    // not right away (a directory written into continuously is not hammered).
    CHECK([[s activityRecheckDirectoryPathsOfRepo:@"r"] isEqual:@[@"/Cam"]] && [s dueDirectoryChecksAt:[NSDate date] limit:10].count == 0
          && [s dueDirectoryChecksAt:[NSDate dateWithTimeIntervalSinceNow:60] limit:10].count == 1, @"unverified row leaves a delayed check");
    [s applyListingOfRepo:@"r" directoryPath:@"/Cam" entries:@[LE(@"f.txt", NO, @"f", 5, 10), LE(@"img.jpg", NO, @"i", 5, 20)] requestStartSeq:s.currentSeq];
    CHECK([s activityRecheckDirectoryPathsOfRepo:@"r"].count == 0, @"a listing that shows it confirms");

    // Tombstones say why they were written.
    S = s.currentSeq;
    [s applyListingOfRepo:@"r" directoryPath:@"/Cam" entries:@[LE(@"img.jpg", NO, @"i", 5, 20)] requestStartSeq:S];
    SeafFPRecord *absent = [s recordForUUID:f.uuid];
    CHECK(absent.deleted && absent.tombReason == SeafFPTombReasonAbsent && absent.tombTxn == S, @"absent from a listing: %ld %lld", (long)absent.tombReason, absent.tombTxn);
    SeafFPRecord *img = [s recordForRepo:@"r" path:@"/Cam/img.jpg" includeDeleted:NO];
    [s markDeletedUUID:img.uuid];
    CHECK([s recordForUUID:img.uuid].tombReason == SeafFPTombReasonLocal, @"deleted on this device");
    CHECK([s applyListingOfRepo:@"r" directoryPath:@"/Cam" entries:@[LE(@"f.txt", NO, @"f", 5, 10)] requestStartSeq:s.currentSeq]
          && ![s recordForUUID:f.uuid].deleted && [s recordForUUID:f.uuid].tombReason == SeafFPTombReasonNone, @"revived row is live again");
    SeafFPRecord *created = [s upsertRecordForRepo:@"r" path:@"/new.txt" isDir:NO parentUUID:nil oid:@"n" mtime:1 size:1];
    CHECK(created.createdSeq == created.seq && [s recordForUUID:created.uuid].createdSeq == created.seq, @"created seq kept");
    [s upsertRecordForRepo:@"r" path:@"/new.txt" isDir:NO parentUUID:nil oid:@"n2" mtime:2 size:1];
    CHECK([s recordForUUID:created.uuid].createdSeq == created.seq, @"updates keep the created seq");
    [s close];

    // A check asked for again while its listing failed keeps the newer request.
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"directory-check-guards" error:nil];
    [s requestDirectoryCheckOfRepo:@"r" path:@"/a/b"];
    SeafFPDirectoryCheck *read = [s dueDirectoryChecksAt:[NSDate date] limit:10].firstObject;
    [s requestDirectoryCheckOfRepo:@"r" path:@"/a/b"];
    [s deferDirectoryCheck:read until:[NSDate dateWithTimeIntervalSinceNow:600] status:500];
    CHECK([s dueDirectoryChecksAt:[NSDate date] limit:10].count == 1, @"newer request not deferred by an older failure");
    [s moveDirectoryCheckToParent:read];
    CHECK([[s activityRecheckDirectoryPathsOfRepo:@"r"] isEqual:@[@"/a/b"]], @"newer request not moved to the parent");
    read = [s dueDirectoryChecksAt:[NSDate date] limit:10].firstObject;
    CHECK([s moveDirectoryCheckToParent:read] && [[s activityRecheckDirectoryPathsOfRepo:@"r"] isEqual:@[@"/a"]], @"404 hands the check to the parent");
    SeafFPDirectoryCheck *parent = [s dueDirectoryChecksAt:[NSDate date] limit:10].firstObject;
    CHECK(parent.version == read.version, @"the parent check keeps the original version");
    [s applyListingOfRepo:@"r" directoryPath:@"/a" entries:@[] requestStartSeq:read.version - 1];
    CHECK([[s activityRecheckDirectoryPathsOfRepo:@"r"] isEqual:@[@"/a"]], @"a parent listing older than the original request does not confirm it");
    [s deferDirectoryCheck:parent until:[NSDate dateWithTimeIntervalSinceNow:600] status:403];
    CHECK([s dueDirectoryChecksAt:[NSDate date] limit:10].count == 0 && [s nextDirectoryCheckDate].timeIntervalSinceNow > 500
          && [s dueDirectoryChecksAt:[NSDate dateWithTimeIntervalSinceNow:700] limit:10].firstObject.attempts == 1, @"deferred with an attempt counted");
    [s requestDirectoryCheckOfRepo:@"lost" path:@"/q"];
    [s applyActivitiesOfRepo:@"lost" entries:@[AE(SeafFPActivityOpMove, @"/n", @"/o", NO, 10)]];
    CHECK([s dropDirectoryChecksOfRepo:@"lost"] && [s activityRecheckDirectoryPathsOfRepo:@"lost"].count == 0 && [s pendingRenameHintCount] == 0,
          @"a removed library drops its checks and hints");
    [s close];

    // Schema 1 store: columns added, path rechecks become directory checks.
    NSString *path = [SeafFPIdentifier storeURLForDomainIdentifier:@"schema-one"].path;
    sqlite3 *raw = NULL;
    sqlite3_open(path.fileSystemRepresentation, &raw);
    sqlite3_exec(raw, "CREATE TABLE identity (uuid TEXT PRIMARY KEY, repo_id TEXT NOT NULL, path TEXT NOT NULL, is_dir INTEGER NOT NULL,"
                      "name TEXT NOT NULL, parent_uuid TEXT, oid TEXT, mtime INTEGER, size INTEGER,"
                      "deleted INTEGER NOT NULL DEFAULT 0, seq INTEGER NOT NULL, UNIQUE(repo_id, path));"
                      "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);"
                      "INSERT INTO identity VALUES('u1','r','/a',1,'a',NULL,NULL,0,0,0,7);"
                      "INSERT INTO meta VALUES('schema_version','1'),('seq','7'),('activity_recheck:r','[\"/a\",\"/\"]'),"
                      "('activity_log:r','{\"seen\":[],\"gone\":{\"/legacy-dir\":100},\"moves\":{}}');", NULL, NULL, NULL);
    sqlite3_close(raw);
    SeafFPStore *upgraded = [[SeafFPStore alloc] initWithDomainIdentifier:@"schema-one" error:nil];
    CHECK(upgraded && [[upgraded metaValueForKey:@"schema_version"] isEqualToString:@"4"], @"upgraded to schema 4");
    CHECK([upgraded recordForUUID:@"u1"].seq == 7 && [upgraded recordForUUID:@"u1"].createdSeq == 0, @"old rows readable");
    CHECK([[upgraded activityRecheckDirectoryPathsOfRepo:@"r"] isEqual:(@[@"/", @"/a"])] && [upgraded metaValueForKey:@"activity_recheck:r"] == nil,
          @"rechecks migrated: %@", [upgraded activityRecheckDirectoryPathsOfRepo:@"r"]);
    CHECK([upgraded applyListingOfRepo:@"r" directoryPath:@"/a" entries:@[LE(@"x", NO, @"x", 1, 1)] requestStartSeq:upgraded.currentSeq]
          && [[upgraded activityRecheckDirectoryPathsOfRepo:@"r"] isEqual:@[@"/"]], @"migrated check confirmed by a later listing");
    CHECK([upgraded metaValueForKey:@"activity_log:r"] == nil
          && ![upgraded applyListingOfRepo:@"r" directoryPath:@"/legacy-dir" entries:@[LE(@"x.txt", NO, @"x", 5, 10)] requestStartSeq:-1]
          && [upgraded recordForRepo:@"r" path:@"/legacy-dir" includeDeleted:YES] == nil, @"old activity history keeps blocking stale caches");
    [upgraded close];
}

static NSString *hintPath(SeafFPStore *s, SeafFPRecord *r)
{
    SeafFPRecord *now = [s recordForUUID:r.uuid];
    return now.deleted ? [now.path stringByAppendingString:@"(del)"] : now.path;
}

/// Move-in from another library, then a remote rename of the directory.
/// newRename: the rename happened after the move-in (P3 / P4); otherwise it
/// is an older rename arriving late, with /D recreated in between (P6).
static void runRenameAfterMoveIn(BOOL newRename, BOOL tombstone, BOOL destinationFirst)
{
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"hint-%d%d%d", newRename, tombstone, destinationFirst] error:nil];
    SeafFPRecord *d = [s upsertRecordForRepo:@"r" path:@"/D" isDir:YES parentUUID:nil oid:@"d0" mtime:10 size:-1];
    SeafFPRecord *o = [s upsertRecordForRepo:@"r" path:@"/D/old.txt" isDir:NO parentUUID:d.uuid oid:@"o" mtime:10 size:5];
    if (tombstone) [s markDeletedUUID:[s upsertRecordForRepo:@"r" path:@"/D/f.txt" isDir:NO parentUUID:d.uuid oid:@"t" mtime:10 size:5].uuid];
    SeafFPRecord *f = [s upsertRecordForRepo:@"src" path:@"/f.txt" isDir:NO parentUUID:nil oid:@"f" mtime:10 size:5];
    reviewFavorite(s, d);
    reviewFavorite(s, f);
    NSArray *dst = newRename ? @[LE(@"old.txt", NO, @"o", 5, 10), LE(@"f.txt", NO, @"f", 5, 10)] : @[LE(@"f.txt", NO, @"f", 5, 10)];
    [s moveRecordsOfRepo:@"src" fromDirectory:@"/" names:@[@"f.txt"] toRepo:@"r" toDirectory:@"/D" destinationEntries:dst requestStartSeq:s.currentSeq];
    NSArray *acts = newRename
        ? @[AE(SeafFPActivityOpCreate, @"/D/f.txt", nil, NO, 200), AE(SeafFPActivityOpMove, @"/E", @"/D", YES, 400)]
        : @[AE(SeafFPActivityOpMove, @"/E", @"/D", YES, 100), AE(SeafFPActivityOpCreate, @"/D", nil, YES, 150), AE(SeafFPActivityOpCreate, @"/D/f.txt", nil, NO, 200)];
    [s applyActivitiesOfRepo:@"r" entries:acts];
    CHECK([s pendingRenameHintCount] == 1 && [s decideRenameHintsWithLimit:10] == SeafFPWriteChanged && [s pendingRenameHintCount] == 0, @"hint decided");
    if (newRename) {
        [s applyListingOfRepo:@"r" directoryPath:@"/" entries:@[LE(@"E", YES, @"d0", -1, 10)] requestStartSeq:s.currentSeq];
        [s applyListingOfRepo:@"r" directoryPath:@"/E" entries:@[LE(@"old.txt", NO, @"o", 5, 10), LE(@"f.txt", NO, @"f", 5, 10)] requestStartSeq:s.currentSeq];
        CHECK(eq(hintPath(s, d), @"/E") && eq(hintPath(s, o), @"/E/old.txt") && eq(hintPath(s, f), @"/E/f.txt"),
              @"new rename (tombstone %d): %@ %@ %@", tombstone, hintPath(s, d), hintPath(s, o), hintPath(s, f));
    } else {
        [s applyListingOfRepo:@"r" directoryPath:@"/" entries:@[LE(@"D", YES, @"d2", -1, 150), LE(@"E", YES, @"d0", -1, 10)] requestStartSeq:s.currentSeq];
        NSArray *dListing = @[LE(@"f.txt", NO, @"f", 5, 10)], *eListing = @[LE(@"old.txt", NO, @"o", 5, 10)];
        if (destinationFirst) {
            [s applyListingOfRepo:@"r" directoryPath:@"/E" entries:eListing requestStartSeq:s.currentSeq];
            [s applyListingOfRepo:@"r" directoryPath:@"/D" entries:dListing requestStartSeq:s.currentSeq];
        } else {
            [s applyListingOfRepo:@"r" directoryPath:@"/D" entries:dListing requestStartSeq:s.currentSeq];
            [s applyListingOfRepo:@"r" directoryPath:@"/E" entries:eListing requestStartSeq:s.currentSeq];
        }
        CHECK(eq(hintPath(s, d), @"/E") && eq(hintPath(s, o), @"/E/old.txt") && eq(hintPath(s, f), @"/D/f.txt"),
              @"old rename arriving late (E first %d): %@ %@ %@", destinationFirst, hintPath(s, d), hintPath(s, o), hintPath(s, f));
        CHECK(!eq([s recordForRepo:@"r" path:@"/D" includeDeleted:NO].uuid, d.uuid), @"recreated /D is a new identity");
    }
    CHECK([[s decorationForItem:d.itemIdentifier].favoriteRank isEqual:@42] && [[s decorationForItem:f.itemIdentifier].favoriteRank isEqual:@42],
          @"favorites stay with their identities");
    [s close];
}

static void runRenameHintTests(void)
{
    runRenameAfterMoveIn(YES, NO, NO);
    runRenameAfterMoveIn(YES, YES, NO);
    runRenameAfterMoveIn(NO, NO, NO);
    runRenameAfterMoveIn(NO, NO, YES);

    // P8: a listing saw the rename before the activity did (both writers use
    // the same listing method). The identity comes back, favorite included.
    for (int browsedTarget = 0; browsedTarget < 2; browsedTarget++) {
        SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"hint-p8-%d", browsedTarget] error:nil];
        SeafFPRecord *d = [s upsertRecordForRepo:@"r" path:@"/D" isDir:YES parentUUID:nil oid:@"d0" mtime:10 size:-1];
        SeafFPRecord *c = [s upsertRecordForRepo:@"r" path:@"/D/c.txt" isDir:NO parentUUID:d.uuid oid:@"c" mtime:10 size:5];
        reviewFavorite(s, d);
        reviewFavorite(s, c);
        [s applyListingOfRepo:@"r" directoryPath:@"/" entries:@[LE(@"E", YES, @"d0", -1, 10)] requestStartSeq:s.currentSeq];
        CHECK([s recordForUUID:d.uuid].deleted && [s recordForUUID:d.uuid].tombReason == SeafFPTombReasonAbsent, @"listing first: D judged absent");
        SeafFPRecord *provisional = [s recordForRepo:@"r" path:@"/E" includeDeleted:NO];
        SeafFPRecord *provisionalChild = nil;
        if (browsedTarget) {
            [s applyListingOfRepo:@"r" directoryPath:@"/E" entries:@[LE(@"c.txt", NO, @"c", 5, 10)] requestStartSeq:s.currentSeq];
            provisionalChild = [s recordForRepo:@"r" path:@"/E/c.txt" includeDeleted:NO];
            SeafFPDecoration *tag = [SeafFPDecoration new]; tag.itemIdentifier = provisionalChild.itemIdentifier; tag.tagData = [@"tag" dataUsingEncoding:NSUTF8StringEncoding];
            [s setDecoration:tag];
        }
        [s applyActivitiesOfRepo:@"r" entries:@[AE(SeafFPActivityOpMove, @"/E", @"/D", YES, 400)]];
        [s decideRenameHintsWithLimit:10];
        [s applyListingOfRepo:@"r" directoryPath:@"/E" entries:@[LE(@"c.txt", NO, @"c", 5, 10)] requestStartSeq:s.currentSeq];
        CHECK(eq(hintPath(s, d), @"/E") && eq(hintPath(s, c), @"/E/c.txt"), @"identities relinked (browsed %d): %@ %@", browsedTarget, hintPath(s, d), hintPath(s, c));
        CHECK([[s decorationForItem:d.itemIdentifier].favoriteRank isEqual:@42] && [[s decorationForItem:c.itemIdentifier].favoriteRank isEqual:@42], @"favorites back");
        CHECK([s recordForUUID:provisional.uuid].deleted && [s decorationForItem:provisional.itemIdentifier] == nil, @"provisional identity retired");
        if (browsedTarget) {
            CHECK([s decorationForItem:c.itemIdentifier].tagData.length == 3 && [s decorationForItem:provisionalChild.itemIdentifier] == nil,
                  @"a tag set on the provisional child moves to the original");
        }
        [s close];
    }

    // P9: a rename chain split across pages, the newer page recorded first.
    for (int listedFirst = 0; listedFirst < 2; listedFirst++) {
        SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"hint-p9-%d", listedFirst] error:nil];
        SeafFPRecord *a = [s upsertRecordForRepo:@"r" path:@"/A" isDir:YES parentUUID:nil oid:@"a0" mtime:10 size:-1];
        if (listedFirst) [s applyListingOfRepo:@"r" directoryPath:@"/" entries:@[LE(@"C", YES, @"a0", -1, 10)] requestStartSeq:s.currentSeq];
        [s applyActivitiesOfRepo:@"r" entries:@[AE(SeafFPActivityOpMove, @"/C", @"/B", YES, 200)]];
        [s applyActivitiesOfRepo:@"r" entries:@[AE(SeafFPActivityOpMove, @"/B", @"/A", YES, 100)]];
        [s decideRenameHintsWithLimit:10];
        [s applyListingOfRepo:@"r" directoryPath:@"/" entries:@[LE(@"C", YES, @"a0", -1, 10)] requestStartSeq:s.currentSeq];
        CHECK(eq(hintPath(s, a), @"/C") && [s recordForRepo:@"r" path:@"/B" includeDeleted:NO] == nil, @"chain decided oldest first (listed first %d): %@", listedFirst, hintPath(s, a));
        [s close];
    }

    // Same second, dependent: B -> C must run before A -> B.
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"hint-same-second" error:nil];
    SeafFPRecord *a = [s upsertRecordForRepo:@"r" path:@"/A" isDir:NO parentUUID:nil oid:@"a" mtime:10 size:1];
    SeafFPRecord *b = [s upsertRecordForRepo:@"r" path:@"/B" isDir:NO parentUUID:nil oid:@"b" mtime:10 size:1];
    [s applyActivitiesOfRepo:@"r" entries:@[AE(SeafFPActivityOpMove, @"/B", @"/A", NO, 300), AE(SeafFPActivityOpMove, @"/C", @"/B", NO, 300)]];
    [s decideRenameHintsWithLimit:10];
    CHECK(eq(hintPath(s, a), @"/B") && eq(hintPath(s, b), @"/C"), @"same-second chain: %@ %@", hintPath(s, a), hintPath(s, b));

    // A later entry at the old path, and a target taken by an older, decorated row.
    // (A directory's mtime is the server's: it tells a later entry. A file's
    // comes from the uploading client and is not trusted for that.)
    SeafFPRecord *later = [s upsertRecordForRepo:@"r" path:@"/later.txt" isDir:YES parentUUID:nil oid:@"l" mtime:900 size:-1];
    SeafFPRecord *src = [s upsertRecordForRepo:@"r" path:@"/src.txt" isDir:NO parentUUID:nil oid:@"s" mtime:10 size:1];
    SeafFPRecord *taken = [s upsertRecordForRepo:@"r" path:@"/taken.txt" isDir:NO parentUUID:nil oid:@"t" mtime:10 size:1];
    reviewFavorite(s, taken);
    [s applyActivitiesOfRepo:@"r" entries:@[AE(SeafFPActivityOpMove, @"/moved.txt", @"/later.txt", YES, 500),
                                             AE(SeafFPActivityOpMove, @"/taken.txt", @"/src.txt", NO, 500)]];
    [s decideRenameHintsWithLimit:10];
    CHECK(eq(hintPath(s, later), @"/later.txt") && eq(hintPath(s, src), @"/src.txt") && eq(hintPath(s, taken), @"/taken.txt")
          && [s pendingRenameHintCount] == 0, @"later entry and older decorated occupant are left to the listings");
    [s close];

    // Decisions wait for the whole transaction: a failed write keeps the hint.
    FailingStatementStore *fail = [[FailingStatementStore alloc] initWithDomainIdentifier:@"hint-failure" error:nil];
    SeafFPRecord *x = [fail upsertRecordForRepo:@"r" path:@"/x" isDir:NO parentUUID:nil oid:@"x" mtime:10 size:1];
    [fail applyActivitiesOfRepo:@"r" entries:@[AE(SeafFPActivityOpMove, @"/y", @"/x", NO, 100)]];
    fail.failStatement = ^BOOL(NSString *sql) { return [sql hasPrefix:@"UPDATE fp_hint"]; };
    CHECK([fail decideRenameHintsWithLimit:10] == SeafFPWriteFailed && eq(hintPath(fail, x), @"/x") && [fail pendingRenameHintCount] == 1, @"failed decision rolled back");
    fail.failStatement = nil;
    CHECK([fail decideRenameHintsWithLimit:10] == SeafFPWriteChanged && eq(hintPath(fail, x), @"/y"), @"decided on retry");
    [fail close];
}

@interface BeginFailingStore : FailingStatementStore
@property BOOL failBegin;
@property NSInteger failBeginTimes;   // the next n BEGINs fail
@end
@implementation BeginFailingStore
- (BOOL)execLocked:(NSString *)sql {
    if ([sql isEqual:@"BEGIN IMMEDIATE"]) {
        if (self.failBegin) return NO;
        if (self.failBeginTimes > 0) { self.failBeginTimes--; return NO; }
    }
    return [super execLocked:sql];
}
@end

static void rawStoreSQL(NSString *domain, const char *sql)
{
    sqlite3 *db = NULL;
    sqlite3_open([SeafFPIdentifier storeURLForDomainIdentifier:domain].path.fileSystemRepresentation, &db);
    sqlite3_exec(db, sql, NULL, NULL, NULL);
    sqlite3_close(db);
}

static void runLateRenameAndBatchTests(void)
{
    NSString *domain = @"late-rename";
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    SeafFPRecord *y = reviewRow(s, @"r", @"/imported.txt", NO, nil, @"y");
    reviewFavorite(s, y);
    [s moveRecordUUID:y.uuid toRepo:@"r" path:@"/A.txt" parentUUID:nil];
    [s close];
    s = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    [s applyActivitiesOfRepo:@"r" entries:@[AE(SeafFPActivityOpMove, @"/B.txt", @"/A.txt", NO, 200)]];
    [s decideRenameHintsWithLimit:100];
    CHECK(eq(hintPath(s, y), @"/A.txt"), @"a delayed event cannot move the file placed at A");
    [s applyListingOfRepo:@"r" directoryPath:@"/" entries:@[LE(@"A.txt", NO, @"y", 5, 10), LE(@"B.txt", NO, @"x", 5, 10)] requestStartSeq:s.currentSeq];
    SeafFPRecord *b = [s recordForRepo:@"r" path:@"/B.txt" includeDeleted:NO];
    CHECK(eq(hintPath(s, y), @"/A.txt") && [[s decorationForItem:y.itemIdentifier].favoriteRank isEqual:@42]
          && b && ![s decorationForItem:b.itemIdentifier].favoriteRank, @"the authoritative listing keeps the two identities separate");

    // A newer remote rename of that same file can still be verified.
    [s applyActivitiesOfRepo:@"r" entries:@[AE(SeafFPActivityOpMove, @"/C.txt", @"/A.txt", NO, 300),
                                            AE(SeafFPActivityOpMove, @"/D.txt", @"/C.txt", NO, 400)]];
    [s decideRenameHintsWithLimit:1];
    [s decideRenameHintsWithLimit:1];
    CHECK(eq(hintPath(s, y), @"/A.txt"), @"wait for a listing before moving the placed file");
    [s applyListingOfRepo:@"r" directoryPath:@"/" entries:@[LE(@"B.txt", NO, @"x", 5, 10), LE(@"D.txt", NO, @"y", 5, 10)] requestStartSeq:s.currentSeq];
    CHECK(eq(hintPath(s, y), @"/D.txt") && [[s decorationForItem:y.itemIdentifier].favoriteRank isEqual:@42],
          @"a confirmed remote chain retains the identity through an unobserved intermediate path");
    [s close];

    domain = @"rename-across-batches";
    s = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    SeafFPRecord *a = reviewRow(s, @"r", @"/A", NO, nil, @"content");
    reviewFavorite(s, a);
    [s applyListingOfRepo:@"r" directoryPath:@"/" entries:@[LE(@"C", NO, @"content", 5, 10)] requestStartSeq:s.currentSeq];
    NSMutableArray *hints = [NSMutableArray array];
    for (int i = 0; i < 99; i++) {
        [hints addObject:AE(SeafFPActivityOpMove, [NSString stringWithFormat:@"/new-%d", i],
                           [NSString stringWithFormat:@"/old-%d", i], NO, i + 1)];
    }
    [hints addObject:AE(SeafFPActivityOpMove, @"/B", @"/A", NO, 200)];
    [hints addObject:AE(SeafFPActivityOpMove, @"/C", @"/B", NO, 300)];
    [s applyActivitiesOfRepo:@"r" entries:hints];
    CHECK([s decideRenameHintsWithLimit:100] == SeafFPWriteChanged && [s pendingRenameHintCount] == 1
          && eq(hintPath(s, a), @"/B"), @"first batch revives A at B");
    SeafFPStore *refresher = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    [refresher applyListingOfRepo:@"r" directoryPath:@"/" entries:@[LE(@"C", NO, @"content", 5, 10)] requestStartSeq:refresher.currentSeq];
    CHECK([refresher recordForUUID:a.uuid].deleted, @"another process tombstones the intermediate path again");
    [refresher close];
    [s close];
    s = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    CHECK([s decideRenameHintsWithLimit:100] == SeafFPWriteChanged && [s pendingRenameHintCount] == 0,
          @"the next process can decide the remaining hint");
    [s applyListingOfRepo:@"r" directoryPath:@"/" entries:@[LE(@"C", NO, @"content", 5, 10)] requestStartSeq:s.currentSeq];
    CHECK(eq(hintPath(s, a), @"/C") && [[s decorationForItem:a.itemIdentifier].favoriteRank isEqual:@42],
          @"the original identity and favorite survive the batch and process boundary");
    [s close];
}

static void runConfirmedPlacementTests(void)
{
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"confirmed-upload" error:nil];
    SeafFPRecord *old = reviewRow(s, @"r", @"/A", NO, nil, @"x");
    SeafFPRecord *uploaded = [s recordCreatedFileInRepo:@"r" path:@"/A" parentUUID:nil oid:@"y"
                                                mtime:10 size:5 requestStartSeq:s.currentSeq serverTime:0];
    CHECK(uploaded && !eq(uploaded.uuid, old.uuid) && [s recordForUUID:old.uuid].deleted,
          @"a successful upload at a free server path replaces a stale indexed identity");
    reviewFavorite(s, uploaded);
    [s applyActivitiesOfRepo:@"r" entries:@[AE(SeafFPActivityOpMove, @"/B", @"/A", NO, 200)]];
    [s decideRenameHintsWithLimit:100];
    [s applyListingOfRepo:@"r" directoryPath:@"/" entries:@[LE(@"A", NO, @"y", 5, 10), LE(@"B", NO, @"x", 5, 10)] requestStartSeq:s.currentSeq];
    SeafFPRecord *b = [s recordForRepo:@"r" path:@"/B" includeDeleted:NO];
    CHECK(eq(hintPath(s, uploaded), @"/A") && [[s decorationForItem:uploaded.itemIdentifier].favoriteRank isEqual:@42]
          && b && ![s decorationForItem:b.itemIdentifier].favoriteRank, @"a late rename leaves the uploaded UUID and favorite at A");
    [s close];

    for (int afterPlacement = 0; afterPlacement < 2; afterPlacement++) {
        NSString *domain = [NSString stringWithFormat:@"renamed-then-edited-%d", afterPlacement];
        s = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPRecord *source = reviewRow(s, @"r", @"/import", NO, nil, @"before");
        reviewFavorite(s, source);
        CHECK([s confirmMoveOfRecord:source toRepo:@"r" path:@"/A" parentUUID:nil requestStartSeq:s.currentSeq serverTime:200],
              @"server-confirmed Files placement");
        [s close];
        s = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        [s applyActivitiesOfRepo:@"r" entries:@[AE(SeafFPActivityOpMove, @"/B", @"/A", NO, afterPlacement ? 300 : 100)]];
        [s decideRenameHintsWithLimit:100];
        [s applyListingOfRepo:@"r" directoryPath:@"/" entries:@[LE(@"B", NO, @"after", 10, 10)] requestStartSeq:s.currentSeq];
        b = [s recordForRepo:@"r" path:@"/B" includeDeleted:NO];
        CHECK(eq(b.oid, @"after") && b.size == 10 && eq(b.uuid, source.uuid) == afterPlacement
              && [[s decorationForItem:b.itemIdentifier].favoriteRank isEqual:@42] == afterPlacement,
              @"only a rename after placement can carry the favorite to the edited result");
        [s close];
    }
}

static void runPendingMoveRecoveryTests(void)
{
    NSString *domain = @"pending-move-recovery";
    FailingPublicationStore *s = [[FailingPublicationStore alloc] initWithDomainIdentifier:domain error:nil];
    SeafFPRecord *source = reviewRow(s, @"r", @"/src", YES, nil, @"d");
    long long start = s.currentSeq;
    CHECK([s rememberMoveOfRecord:source toRepo:@"r" directory:@"/" parentUUID:nil
                     expectedName:@"dst" requestStartSeq:start serverTime:200], @"server success durably recorded before confirmation");

    SeafFPStore *other = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    SeafFPRecord *target = reviewRow(other, @"r", @"/dst", YES, nil, @"d");
    SeafFPRecord *child = reviewRow(other, @"r", @"/dst/file", NO, target.uuid, @"child");
    reviewFavorite(other, target);
    s.failCommit = YES;
    CHECK(![s confirmMoveOfRecord:source toRepo:@"r" path:@"/dst" parentUUID:nil requestStartSeq:start serverTime:200],
          @"failed commit reports an error");
    CHECK(eq(hintPath(other, source), @"/src") && eq([other recordForUUID:child.uuid].parentUUID, target.uuid)
          && [other moveRecoveryForUUID:source.uuid].count && ![other decorationForItem:source.itemIdentifier].favoriteRank,
          @"subtree, favorites and recovery entry roll back together");
    [s close];
    [other close];
    SeafFPStore *reopened = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    NSDictionary *pending = [reopened moveRecoveryForUUID:source.uuid];
    CHECK([pending[@"name"] isEqual:@"dst"] && [pending[@"serverTime"] longLongValue] == 200,
          @"restart finds the operation to reconcile without resending the move");
    CHECK([reopened confirmMoveOfRecord:source toRepo:@"r" path:@"/dst" parentUUID:nil requestStartSeq:start serverTime:200]
          && [reopened moveRecoveryForUUID:source.uuid].count == 0
          && eq([reopened recordForUUID:child.uuid].parentUUID, source.uuid)
          && [[reopened decorationForItem:source.itemIdentifier].favoriteRank isEqual:@42],
          @"retry publishes the merged subtree and clears the recovery entry atomically");
    [reopened close];

    // A failed cleanup must keep the journal and reservation together.
    s = [[FailingPublicationStore alloc] initWithDomainIdentifier:@"move-rejection-rollback" error:nil];
    source = reviewRow(s, @"r", @"/src", NO, nil, @"file");
    SeafFPRecord *competitor = reviewRow(s, @"r", @"/competitor", NO, nil, @"file");
    start = [s beginMoveOfRecord:source toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"dst" requestedName:nil existingDestinationNames:@[]];
    CHECK(start > 0, @"persisted move before dispatch");
    s.failCommit = YES;
    CHECK(![s discardUnconfirmedMoveForUUID:source.uuid requestStartSeq:start], @"cleanup reports the failed transaction");
    CHECK([s moveRecoveryForUUID:source.uuid].count > 0
          && [s beginMoveOfRecord:competitor toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"dst" requestedName:nil existingDestinationNames:@[]] < 0,
          @"failed cleanup kept both journal and destination reservation");
    CHECK([s discardUnconfirmedMoveForUUID:source.uuid requestStartSeq:start]
          && [s moveRecoveryForUUID:source.uuid].count == 0
          && [s beginMoveOfRecord:competitor toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"dst" requestedName:nil existingDestinationNames:@[]] > start,
          @"committed cleanup released the journal and reservation");
    [s close];
}

/// Regressions of the local review of PR #558 (docs/versions/_unreleased/fixes/pr558-local-review-fixes.md).
static void runMoveJournalTerminalStateTests(void)
{
    // A1: a local delete of the item ends its journal and frees the destination.
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"journal-local-delete" error:nil];
    SeafFPRecord *source = reviewRow(s, @"r", @"/src", NO, nil, @"file");
    SeafFPRecord *competitor = reviewRow(s, @"r", @"/competitor", NO, nil, @"other");
    long long start = [s beginMoveOfRecord:source toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"dst" requestedName:nil existingDestinationNames:@[]];
    CHECK(start > 0 && [s noteMoveReceiptForUUID:source.uuid requestStartSeq:start serverTime:200], @"acknowledged move journaled");
    CHECK([[s moveRecoveryForUUID:source.uuid][@"startedAt"] longLongValue] > 0, @"journal carries its start time");
    CHECK([s prepareFileCreationInRepo:@"r" path:@"/dst" requestStartSeq:s.currentSeq] < 0, @"reserved destination refuses a creation");
    [s markDeletedUUID:source.uuid];
    CHECK([s moveRecoveryForUUID:source.uuid].count == 0, @"delete dropped the journal");
    CHECK([s prepareFileCreationInRepo:@"r" path:@"/dst" requestStartSeq:s.currentSeq] > 0, @"delete freed the destination for a creation");
    CHECK([s beginMoveOfRecord:competitor toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"dst" requestedName:nil existingDestinationNames:@[]] > 0,
          @"delete freed the destination for a move");
    [s close];

    // A1 (directory): deleting the parent ends the journals of the subtree.
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"journal-subtree-delete" error:nil];
    SeafFPRecord *dir = reviewRow(s, @"r", @"/dir", YES, nil, @"d");
    SeafFPRecord *inner = reviewRow(s, @"r", @"/dir/inner", NO, dir.uuid, @"file");
    competitor = reviewRow(s, @"r", @"/competitor", NO, nil, @"other");
    CHECK([s beginMoveOfRecord:inner toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"out" requestedName:nil existingDestinationNames:@[]] > 0, @"child move journaled");
    [s markDeletedUUID:dir.uuid];
    CHECK([s moveRecoveryForUUID:inner.uuid].count == 0
          && [s beginMoveOfRecord:competitor toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"out" requestedName:nil existingDestinationNames:@[]] > 0,
          @"parent delete dropped the child's journal and reservation");
    [s close];

    // A2: a library that left the account takes its journals and reservations with it.
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"journal-repo-removed" error:nil];
    NSDictionary *keep = @{@"repoId":@"keep",@"name":@"Keep",@"perm":@"rw",@"editable":@YES,@"mtime":@10,@"ooid":@"k",@"locked":@NO};
    NSDictionary *gone = @{@"repoId":@"gone",@"name":@"Gone",@"perm":@"rw",@"editable":@YES,@"mtime":@10,@"ooid":@"g",@"locked":@NO};
    [s applyRepositorySnapshot:@[keep, gone] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    source = reviewRow(s, @"gone", @"/src", NO, nil, @"file");
    SeafFPRecord *crossing = reviewRow(s, @"keep", @"/crossing", NO, nil, @"file2");
    competitor = reviewRow(s, @"keep", @"/competitor", NO, nil, @"other");
    CHECK([s beginMoveOfRecord:source toRepo:@"gone" directory:@"/" parentUUID:nil expectedName:@"dst" requestedName:nil existingDestinationNames:@[]] > 0, @"move inside the leaving library");
    CHECK([s beginMoveOfRecord:crossing toRepo:@"gone" directory:@"/" parentUUID:nil expectedName:@"landed" requestedName:nil existingDestinationNames:@[]] > 0, @"move into the leaving library");
    [s applyRepositorySnapshot:@[keep] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    CHECK([s moveRecoveryForUUID:source.uuid].count == 0 && [s moveRecoveryForUUID:crossing.uuid].count == 0, @"journals of the removed library dropped");
    CHECK([s beginMoveOfRecord:competitor toRepo:@"gone" directory:@"/" parentUUID:nil expectedName:@"dst" requestedName:nil existingDestinationNames:@[]] > 0,
          @"its destination reservations are gone too");
    [s close];

    // A6: a journal older than the retention no longer holds its destination.
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"journal-expired" error:nil];
    source = reviewRow(s, @"r", @"/src", NO, nil, @"file");
    competitor = reviewRow(s, @"r", @"/competitor", NO, nil, @"other");
    start = [s beginMoveOfRecord:source toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"dst" requestedName:nil existingDestinationNames:@[]];
    CHECK(start > 0 && [s beginMoveOfRecord:competitor toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"dst" requestedName:nil existingDestinationNames:@[]] < 0,
          @"fresh journal holds the destination");
    NSMutableDictionary *journal = [[s moveRecoveryForUUID:source.uuid] mutableCopy];
    long long now = (long long)[NSDate date].timeIntervalSince1970;
    CHECK(![SeafFPStore moveJournalExpired:journal now:now] && [SeafFPStore moveJournalExpired:journal now:now + 8 * 24 * 3600]
          && [SeafFPStore moveJournalExpired:@{@"name": @"legacy"} now:now], @"retention is seven days; a journal without a start is expired");
    CHECK(![SeafFPStore moveJournalExpired:journal now:now + 3500] && [SeafFPStore moveJournalExpired:journal now:now + 3700]
          && ![SeafFPStore moveSettleGraceElapsed:journal now:now + 3500] && [SeafFPStore moveSettleGraceElapsed:journal now:now + 3700],
          @"an unanswered move becomes eligible to settle and frees its destination after an hour");
    NSMutableDictionary *acknowledged = [journal mutableCopy];
    acknowledged[@"confirmed"] = @YES;
    CHECK(![SeafFPStore moveJournalExpired:acknowledged now:now + 3700] && [SeafFPStore moveSettleGraceElapsed:acknowledged now:now + 3700],
          @"an acknowledged move keeps its destination for the week");
    journal[@"startedAt"] = @(now - 8 * 24 * 3600);
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:journal options:0 error:nil];
    [s setMetaValue:[[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding] forKey:[@"fp_confirmed_move:" stringByAppendingString:source.uuid]];
    CHECK([s beginMoveOfRecord:competitor toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"dst" requestedName:nil existingDestinationNames:@[]] > 0
          && [s moveRecoveryForUUID:source.uuid].count > 0, @"expired reservation is released without losing recovery evidence");
    CHECK([s expireMoveForUUID:source.uuid matchingRecovery:journal] && [s moveRecoveryForUUID:source.uuid].count == 0
          && [s prepareFileCreationInRepo:@"r" path:@"/dst" requestStartSeq:s.currentSeq] < 0,
          @"expiring an old journal preserves the new owner's reservation");
    CHECK([s discardMoveJournalForUUID:competitor.uuid] && [s moveRecoveryForUUID:competitor.uuid].count == 0
          && [s prepareFileCreationInRepo:@"r" path:@"/dst" requestStartSeq:s.currentSeq] > 0, @"discardMoveJournalForUUID: drops journal and reservation");
    [s close];

    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"journal-expire-race" error:nil];
    source = reviewRow(s, @"r", @"/src", NO, nil, @"file");
    start = [s beginMoveOfRecord:source toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"dst" requestedName:nil existingDestinationNames:@[]];
    NSDictionary *beforeReceipt = [s moveRecoveryForUUID:source.uuid];
    CHECK([s noteMoveReceiptForUUID:source.uuid requestStartSeq:start serverTime:100]
          && ![s expireMoveForUUID:source.uuid matchingRecovery:beforeReceipt]
          && [[s moveRecoveryForUUID:source.uuid][@"confirmed"] boolValue], @"a receipt that arrives meanwhile prevents expiry");
    NSDictionary *receipted = [s moveRecoveryForUUID:source.uuid];
    CHECK(![s expireMoveForUUID:source.uuid matchingRecovery:@{}] && [s moveRecoveryForUUID:source.uuid].count > 0,
          @"an empty expectation never expires a journal");
    CHECK([s expireMoveForUUID:source.uuid matchingRecovery:receipted] && [s moveRecoveryForUUID:source.uuid].count == 0
          && [s prepareFileCreationInRepo:@"r" path:@"/dst" requestStartSeq:s.currentSeq] > 0,
          @"an acknowledged journal expires too, with its reservation");
    CHECK(![s expireMoveForUUID:source.uuid matchingRecovery:receipted], @"expiry happens once");
    [s close];

    // 2.3: before the receipt, different contents at the source do not split
    // the identity; after it, they do.
    for (int acknowledged = 0; acknowledged < 2; acknowledged++) {
        s = [[SeafFPStore alloc] initWithDomainIdentifier:acknowledged ? @"occupant-acknowledged" : @"occupant-unacknowledged" error:nil];
        source = reviewRow(s, @"r", @"/a.txt", NO, nil, @"old");
        start = [s beginMoveOfRecord:source toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"b.txt" requestedName:nil existingDestinationNames:@[]];
        if (acknowledged) CHECK([s noteMoveReceiptForUUID:source.uuid requestStartSeq:start serverTime:200], @"receipt noted");
        CHECK([s applyListingOfRepo:@"r" directoryPath:@"/" entries:@[LE(@"a.txt", NO, @"new", 5, 11)] requestStartSeq:s.currentSeq], @"listing applied");
        SeafFPRecord *live = [s recordForRepo:@"r" path:@"/a.txt" includeDeleted:NO];
        if (acknowledged) {
            CHECK(![live.uuid isEqual:source.uuid] && [s recordForUUID:source.uuid].deleted
                  && [[s recordForUUID:source.uuid].path hasPrefix:@"/a.txt#moved-"], @"acknowledged: identity kept for the destination");
            // #8: the detached row's seq covers its suffix, so a reseeded counter cannot reuse it.
            SeafFPRecord *detached = [s recordForUUID:source.uuid];
            CHECK([[detached.path componentsSeparatedByString:@"#moved-"].lastObject longLongValue] == detached.seq, @"detached row seq is its suffix");
        } else {
            CHECK([live.uuid isEqual:source.uuid] && [live.oid isEqual:@"new"], @"unacknowledged: same identity, fresh contents");
        }
        [s close];
    }

    // 2.4: refreshContentOfRecord: keeps the identity and bumps the seq.
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"refresh-content" error:nil];
    source = reviewRow(s, @"r", @"/a.txt", NO, nil, @"old");
    long long before = source.seq;
    SeafFPRecord *refreshed = [s refreshContentOfRecord:source oid:@"new" mtime:99 size:7];
    CHECK([refreshed.uuid isEqual:source.uuid] && [refreshed.oid isEqual:@"new"] && refreshed.mtime == 99 && refreshed.size == 7 && refreshed.seq > before,
          @"content refreshed in place");
    CHECK(![s refreshContentOfRecord:source oid:@"stale" mtime:1 size:1]
          && [[s recordForUUID:source.uuid].oid isEqual:@"new"], @"a stale preflight cannot overwrite a newer record");
    [s close];

    // #9: relocating a detached (`#moved-`) row leaves no departed-path barrier for that path.
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"departed-moved" error:nil];
    source = reviewRow(s, @"r", @"/D", YES, nil, @"d");
    start = [s beginMoveOfRecord:source toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"E" requestedName:nil existingDestinationNames:@[]];
    CHECK([s noteMoveReceiptForUUID:source.uuid requestStartSeq:start serverTime:200], @"receipt noted");
    NSArray *replaced = @[LE(@"D", NO, @"file", 5, 11), LE(@"E", YES, nil, -1, 11)];
    CHECK([s applyListingOfRepo:@"r" directoryPath:@"/" entries:replaced requestStartSeq:s.currentSeq], @"listing applied");
    NSString *detachedPath = [s recordForUUID:source.uuid].path;
    CHECK([detachedPath hasPrefix:@"/D#moved-"], @"identity detached: %@", detachedPath);
    // The extension confirms with the journaled source, not the detached row.
    NSDictionary *journaled = [s moveRecoveryForUUID:source.uuid];
    SeafFPRecord *journaledSource = [SeafFPRecord new];
    journaledSource.uuid = source.uuid; journaledSource.repoId = journaled[@"sourceRepo"]; journaledSource.path = journaled[@"sourcePath"];
    journaledSource.oid = journaled[@"oid"]; journaledSource.isDir = [journaled[@"isDir"] boolValue]; journaledSource.seq = [journaled[@"sourceSeq"] longLongValue];
    CHECK([s finishPendingMoveOfRecord:journaledSource toRepo:@"r" path:@"/E" parentUUID:nil requestStartSeq:start serverTime:200], @"move confirmed");
    CHECK([s metaValueForKey:[@"departed_path:r:" stringByAppendingString:detachedPath]] == nil, @"no barrier for the detached path");
    CHECK([s directoryStampForRepo:@"r" parentUUID:nil] >= [s recordForUUID:source.uuid].seq, @"the directory stamp still covers the departure");
    [s close];

    // A recovered move may split the original UUID from a replacement at
    // its source. Every stage, including the journal cleanup, is atomic.
    for (int failure = 0; failure < 3; failure++) {
        FailingStatementStore *store = [[FailingStatementStore alloc]
            initWithDomainIdentifier:[NSString stringWithFormat:@"recovery-split-failure-%d", failure] error:nil];
        SeafFPRecord *original = reviewRow(store, @"r", @"/A", NO, nil, @"original");
        reviewFavorite(store, original);
        long long boundary = [store beginMoveOfRecord:original toRepo:@"r" directory:@"/" parentUUID:nil
            expectedName:@"B" requestedName:nil existingDestinationNames:@[]];
        CHECK(([store applyListingOfRepo:@"r" directoryPath:@"/"
            entries:@[LE(@"A", NO, @"replacement", 9, 20), LE(@"B", NO, @"original", 5, 10)]
            requestStartSeq:store.currentSeq]), @"source reuse listed");
        SeafFPRecord *provisional = [store recordForRepo:@"r" path:@"/B" includeDeleted:NO];
        NSDictionary *pending = [store moveRecoveryForUUID:original.uuid];
        long long beforeSplit = store.currentSeq;
        __block BOOL injected = NO;
        store.failStatement = ^BOOL(NSString *sql) {
            BOOL fail = failure == 0 ? [sql hasPrefix:@"INSERT INTO identity"]
                : failure == 1 ? ([sql hasPrefix:@"UPDATE identity"] && [sql containsString:@"path='/B'"])
                : ([sql hasPrefix:@"DELETE FROM meta"] && [sql containsString:@"fp_confirmed_move:"]);
            injected |= fail;
            return fail;
        };
        SeafFPRecord *failed = [store finishPendingMoveOfRecord:original toRepo:@"r" path:@"/B"
            parentUUID:nil requestStartSeq:boundary serverTime:200];
        store.failStatement = nil;
        SeafFPRecord *unchanged = [store recordForUUID:original.uuid];
        CHECK(injected && !failed && !unchanged.deleted && eq(unchanged.path, @"/A")
              && eq(unchanged.oid, @"replacement") && store.currentSeq == beforeSplit, @"failed split rolls back identities and seq");
        CHECK([[store moveRecoveryForUUID:original.uuid] isEqual:pending]
              && eq([store recordForRepo:@"r" path:@"/B" includeDeleted:NO].uuid, provisional.uuid)
              && [[store decorationForItem:original.itemIdentifier].favoriteRank isEqual:@42], @"failed split preserves recovery and decoration");
        SeafFPRecord *recovered = [store finishPendingMoveOfRecord:original toRepo:@"r" path:@"/B"
            parentUUID:nil requestStartSeq:boundary serverTime:200];
        SeafFPRecord *replacement = [store recordForRepo:@"r" path:@"/A" includeDeleted:NO];
        CHECK(recovered && eq(recovered.uuid, original.uuid) && eq(recovered.oid, @"original")
              && recovered.mtime == 10 && recovered.size == 5 && ![store moveRecoveryForUUID:original.uuid].count, @"retry restores original identity and metadata");
        CHECK(replacement && !eq(replacement.uuid, original.uuid) && eq(replacement.oid, @"replacement")
              && replacement.mtime == 20 && replacement.size == 9, @"source replacement retains its own metadata");
        [store close];
    }
}

/// Lists every pending check of the library from `server` (path -> entries;
/// a missing path is gone), the way the scheduler would, until none is left.
static void listPendingChecks(SeafFPStore *s, NSString *repo, NSDictionary<NSString *, NSArray *> *server)
{
    for (int round = 0; round < 10; round++) {
        NSArray<SeafFPDirectoryCheck *> *due = [s dueDirectoryChecksAt:[NSDate dateWithTimeIntervalSinceNow:3600] limit:100 repoIds:@[repo]];
        if (due.count == 0) return;
        for (SeafFPDirectoryCheck *check in due) {
            NSArray *entries = server[check.path];
            if (entries) [s applyListingOfRepo:repo directoryPath:check.path entries:entries requestStartSeq:s.currentSeq];
            else [s moveDirectoryCheckToParent:check];
        }
    }
}

/// Regressions from the third review (2026-11-03), one per finding.
static void runReviewFollowupTests(void)
{
    // #1 BEGIN failed: nothing runs, nothing half-written.
    BeginFailingStore *b = [[BeginFailingStore alloc] initWithDomainIdentifier:@"followup-begin" error:nil];
    SeafFPRecord *bd = [b upsertRecordForRepo:@"r" path:@"/D" isDir:YES parentUUID:nil oid:@"d" mtime:1 size:-1];
    SeafFPRecord *bc = [b upsertRecordForRepo:@"r" path:@"/D/c" isDir:NO parentUUID:bd.uuid oid:@"c" mtime:1 size:1];
    b.failBegin = YES;
    b.failStatement = ^BOOL(NSString *sql) { return [sql hasPrefix:@"UPDATE identity SET repo_id"] && [sql containsString:@"/E/c"]; };
    SeafFPRecord *bm = [b moveRecordUUID:bd.uuid toRepo:@"r" path:@"/E" parentUUID:nil];
    SeafFPRecord *bu = [b upsertRecordForRepo:@"r" path:@"/x" isDir:NO parentUUID:nil oid:@"x" mtime:1 size:1];
    [b markDeletedUUIDs:@[bc.uuid]];
    b.failBegin = NO; b.failStatement = nil;
    CHECK(!bm && !bu && eq(hintPath(b, bd), @"/D") && eq(hintPath(b, bc), @"/D/c") && ![b recordForRepo:@"r" path:@"/x" includeDeleted:YES],
          @"busy store: no write at all (%@ %@)", hintPath(b, bd), hintPath(b, bc));
    // The extension's own operations wait out a short contention instead of
    // losing a move the server already made.
    b.failBeginTimes = 2;
    SeafFPRecord *retried = [b moveRecordUUID:bd.uuid toRepo:@"r" path:@"/E" parentUUID:nil];
    CHECK(retried && eq(hintPath(b, bd), @"/E") && eq(hintPath(b, bc), @"/E/c") && b.failBeginTimes == 0, @"move recorded after two busy attempts");
    b.failBeginTimes = 2;
    CHECK([b upsertRecordForRepo:@"r" path:@"/y" isDir:NO parentUUID:nil oid:@"y" mtime:1 size:1] != nil, @"upsert recorded after two busy attempts");
    b.failBeginTimes = 2;
    CHECK([b applyListingOfRepo:@"r" directoryPath:@"/" entries:@[] requestStartSeq:b.currentSeq] == NO && b.failBeginTimes == 1,
          @"main app index writes still give up after one busy timeout");
    b.failBeginTimes = 0;
    [b close];

    // #2 a progress row that cannot be read is not "no progress".
    FailingStatementStore *p = [[FailingStatementStore alloc] initWithDomainIdentifier:@"followup-progress" error:nil];
    [p recordActivityEntries:@[] progress:@{@"boundary": @1000}];
    p.failStatement = ^BOOL(NSString *sql) { return [sql hasPrefix:@"SELECT value FROM meta"] && [sql containsString:@"fp_activity_progress_v1"]; };
    CHECK([p activityProgress] == nil, @"unreadable progress is nil");
    p.failStatement = nil;
    CHECK([[p activityProgress][@"boundary"] isEqual:@1000] && [p activityProgress] != nil, @"readable again");
    [p close];

    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"followup-store" error:nil];
    // #3 a stale listing showing a directory as a file keeps rows written below it later.
    SeafFPRecord *dir = [s upsertRecordForRepo:@"t" path:@"/D" isDir:YES parentUUID:nil oid:@"dir" mtime:1 size:-1];
    long long S = s.currentSeq;
    [s applyListingOfRepo:@"t" directoryPath:@"/D" entries:@[LE(@"local.txt", NO, @"new", 5, 10)] requestStartSeq:s.currentSeq];
    SeafFPRecord *child = [s recordForRepo:@"t" path:@"/D/local.txt" includeDeleted:NO];
    [s applyListingOfRepo:@"t" directoryPath:@"/" entries:@[LE(@"D", NO, @"old-file", 1, 10)] requestStartSeq:S];
    CHECK(child && ![s recordForUUID:child.uuid].deleted && [s recordForUUID:dir.uuid].isDir
          && [[s activityRecheckDirectoryPathsOfRepo:@"t"] containsObject:@"/"], @"newer subtree kept, root to be listed again");

    // #4 one item renamed twice in one second.
    SeafFPRecord *one = [s upsertRecordForRepo:@"u" path:@"/A" isDir:NO parentUUID:nil oid:@"content" mtime:10 size:5];
    reviewFavorite(s, one);
    [s applyActivitiesOfRepo:@"u" entries:@[AE(SeafFPActivityOpMove, @"/C", @"/B", NO, 300), AE(SeafFPActivityOpMove, @"/B", @"/A", NO, 300)]];
    [s decideRenameHintsWithLimit:100];
    [s applyListingOfRepo:@"u" directoryPath:@"/" entries:@[LE(@"C", NO, @"content", 5, 10)] requestStartSeq:s.currentSeq];
    CHECK(eq(hintPath(s, one), @"/C") && [[s decorationForItem:one.itemIdentifier].favoriteRank isEqual:@42], @"same-second chain of one item: %@", hintPath(s, one));
    // ...and a same-second group is never split by the decision limit.
    SeafFPRecord *two = [s upsertRecordForRepo:@"u2" path:@"/A" isDir:NO parentUUID:nil oid:@"c2" mtime:10 size:5];
    [s applyActivitiesOfRepo:@"u2" entries:@[AE(SeafFPActivityOpMove, @"/C", @"/B", NO, 300), AE(SeafFPActivityOpMove, @"/B", @"/A", NO, 300)]];
    [s decideRenameHintsWithLimit:1];
    CHECK(eq(hintPath(s, two), @"/C") && [s pendingRenameHintCount] == 0, @"limit 1 still decides the whole second: %@", hintPath(s, two));

    // #5 moved into a directory a listing already judged absent because it was renamed later.
    SeafFPRecord *va = [s upsertRecordForRepo:@"v" path:@"/A" isDir:YES parentUUID:nil oid:@"a" mtime:1 size:-1];
    [s upsertRecordForRepo:@"v" path:@"/B" isDir:YES parentUUID:nil oid:@"b" mtime:1 size:-1];
    SeafFPRecord *vf = [s upsertRecordForRepo:@"v" path:@"/A/f" isDir:NO parentUUID:va.uuid oid:@"f" mtime:1 size:5];
    reviewFavorite(s, vf);
    [s applyListingOfRepo:@"v" directoryPath:@"/" entries:@[LE(@"A", YES, @"a", -1, 1), LE(@"C", YES, @"b", -1, 1)] requestStartSeq:s.currentSeq];
    [s applyActivitiesOfRepo:@"v" entries:@[AE(SeafFPActivityOpMove, @"/C", @"/B", YES, 200), AE(SeafFPActivityOpMove, @"/B/f", @"/A/f", NO, 100)]];
    [s decideRenameHintsWithLimit:100];
    listPendingChecks(s, @"v", @{@"/": @[LE(@"A", YES, @"a", -1, 1), LE(@"C", YES, @"b", -1, 1)], @"/A": @[], @"/C": @[LE(@"f", NO, @"f", 5, 1)]});
    CHECK(eq(hintPath(s, vf), @"/C/f") && [[s decorationForItem:vf.itemIdentifier].favoriteRank isEqual:@42], @"carried through the later rename: %@", hintPath(s, vf));

    // #6 the scheduler lists the old path of a renamed directory itself (P6 without help).
    SeafFPRecord *wd = [s upsertRecordForRepo:@"w" path:@"/D" isDir:YES parentUUID:nil oid:@"d" mtime:1 size:-1];
    SeafFPRecord *wf = [s upsertRecordForRepo:@"w" path:@"/D/f" isDir:NO parentUUID:wd.uuid oid:@"f" mtime:1 size:5];
    reviewFavorite(s, wf);
    [s applyActivitiesOfRepo:@"w" entries:@[AE(SeafFPActivityOpMove, @"/E", @"/D", YES, 100)]];
    [s decideRenameHintsWithLimit:100];
    CHECK([[s activityRecheckDirectoryPathsOfRepo:@"w"] containsObject:@"/D"], @"old path of a renamed directory is checked");
    listPendingChecks(s, @"w", @{@"/": @[LE(@"D", YES, @"newD", -1, 150), LE(@"E", YES, @"d", -1, 1)], @"/E": @[], @"/D": @[LE(@"f", NO, @"f", 5, 1)]});
    CHECK(eq(hintPath(s, wd), @"/E") && eq(hintPath(s, wf), @"/D/f") && [[s decorationForItem:wf.itemIdentifier].favoriteRank isEqual:@42],
          @"f found back at the old path: %@ %@", hintPath(s, wd), hintPath(s, wf));

    // #7 a row skipped as newer keeps its check: the delete is verified later.
    SeafFPRecord *xf = [s upsertRecordForRepo:@"x" path:@"/f" isDir:NO parentUUID:nil oid:@"f" mtime:1 size:5];
    [s applyActivitiesOfRepo:@"x" entries:@[AE(SeafFPActivityOpDelete, @"/f", nil, NO, 100)]];
    S = s.currentSeq;
    [s noteLastUsedDate:[NSDate date] forRepo:@"x" path:@"/f" oid:@"f" size:5 mtime:1 createIfMissing:NO];
    [s applyListingOfRepo:@"x" directoryPath:@"/" entries:@[] requestStartSeq:S];
    CHECK(![s recordForUUID:xf.uuid].deleted && [[s activityRecheckDirectoryPathsOfRepo:@"x"] isEqual:@[@"/"]], @"skipped row still to be verified");
    listPendingChecks(s, @"x", @{@"/": @[]});
    CHECK([s recordForUUID:xf.uuid].deleted, @"the later listing applies the delete");

    // #10 an expired verification no longer relinks.
    SeafFPRecord *ya = [s upsertRecordForRepo:@"y" path:@"/A" isDir:NO parentUUID:nil oid:@"same" mtime:1 size:5];
    [s applyActivitiesOfRepo:@"y" entries:@[AE(SeafFPActivityOpMove, @"/B", @"/A", NO, 100)]];
    [s decideRenameHintsWithLimit:100];
    [s close];
    rawStoreSQL(@"followup-store", "UPDATE fp_hint SET close_after = 1");
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"followup-store" error:nil];
    [s applyListingOfRepo:@"y" directoryPath:@"/" entries:@[LE(@"A", NO, @"same", 5, 1000)] requestStartSeq:s.currentSeq];
    CHECK(!eq([s recordForRepo:@"y" path:@"/A" includeDeleted:NO].uuid, ya.uuid), @"no correction after the window");

    // Risk: a file whose (client-given) mtime is after the rename still moves.
    SeafFPRecord *za = [s upsertRecordForRepo:@"z" path:@"/A" isDir:NO parentUUID:nil oid:@"same" mtime:1000 size:5];
    [s applyActivitiesOfRepo:@"z" entries:@[AE(SeafFPActivityOpMove, @"/B", @"/A", NO, 100)]];
    [s decideRenameHintsWithLimit:100];
    CHECK(eq(hintPath(s, za), @"/B"), @"file mtime is not taken for a later entry");

    // Risk: an undecorated row older than the hint at the target is not taken over.
    SeafFPRecord *src = [s upsertRecordForRepo:@"q" path:@"/src" isDir:NO parentUUID:nil oid:@"s" mtime:1 size:1];
    SeafFPRecord *dst = [s upsertRecordForRepo:@"q" path:@"/dst" isDir:NO parentUUID:nil oid:@"d" mtime:1 size:1];
    [s applyActivitiesOfRepo:@"q" entries:@[AE(SeafFPActivityOpMove, @"/dst", @"/src", NO, 100)]];
    [s decideRenameHintsWithLimit:100];
    CHECK(eq(hintPath(s, src), @"/src") && eq(hintPath(s, dst), @"/dst"), @"older target row keeps its identity");

    // #14 checks and hints of a library only the activity log knew go with a complete list.
    [s applyRepositorySnapshot:@[] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    [s applyActivitiesOfRepo:@"unknown" entries:@[AE(SeafFPActivityOpCreate, @"/f", nil, NO, 100), AE(SeafFPActivityOpMove, @"/b", @"/a", NO, 200)]];
    [s applyRepositorySnapshot:@[] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    CHECK([s activityRecheckDirectoryPathsOfRepo:@"unknown"].count == 0 && [s pendingRenameHintCount] == 0, @"queued library dropped");
    [s close];

    // #12 a schema 1 store without its version stamp is migrated too.
    rawStoreSQL(@"followup-unstamped",
        "CREATE TABLE identity(uuid TEXT PRIMARY KEY, repo_id TEXT NOT NULL, path TEXT NOT NULL, is_dir INTEGER NOT NULL, name TEXT NOT NULL,"
        " parent_uuid TEXT, oid TEXT, mtime INTEGER, size INTEGER, deleted INTEGER NOT NULL DEFAULT 0, seq INTEGER NOT NULL, UNIQUE(repo_id,path));"
        "CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT);"
        "INSERT INTO meta VALUES('seq','7'),('activity_recheck:r','[\"/A\"]'),('activity_log:r','{\"gone\":{\"/gone\":100}}');");
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"followup-unstamped" error:nil];
    CHECK([[s metaValueForKey:@"schema_version"] isEqual:@"4"] && [[s activityRecheckDirectoryPathsOfRepo:@"r"] isEqual:@[@"/A"]]
          && [s metaValueForKey:@"activity_recheck:r"] == nil && [s metaValueForKey:@"departed_path:r:/gone"] != nil, @"unstamped store migrated");
    [s close];

    // #13 a lost counter is restored above check and hint versions.
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"followup-seq" error:nil];
    [s requestDirectoryCheckOfRepo:@"r" path:@"/"];
    [s close];
    rawStoreSQL(@"followup-seq", "DELETE FROM meta WHERE key = 'seq'");
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"followup-seq" error:nil];
    [s applyListingOfRepo:@"r" directoryPath:@"/" entries:@[] requestStartSeq:s.currentSeq];
    CHECK(s.currentSeq >= 1 && [s activityRecheckDirectoryPathsOfRepo:@"r"].count == 0, @"check confirmable after counter repair");
    [s close];
}

static NSDictionary *RP(NSString *name, BOOL editable) {
    return @{@"repoId":@"publication",@"name":name,@"perm":editable?@"rw":@"r",@"editable":@(editable),@"mtime":@10,@"ooid":@"root",@"locked":@NO};
}
static void runPublicationTests(void) {
    SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:@"publication" error:nil];
    [s performBatch:^{ for(NSUInteger i=0;i<1100;i++) [s upsertRecordForRepo:@"publication" path:[NSString stringWithFormat:@"/f%04lu.txt",(unsigned long)i] isDir:NO parentUUID:nil oid:@"content" mtime:10 size:5]; }];
    SeafFPRecord *original=[s recordForRepo:@"publication" path:@"/f0000.txt" includeDeleted:NO];
    reviewFavorite(s,original);
    CHECK([s applyRepositorySnapshot:@[RP(@"Library",YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq], @"initial library event");
    while(s.hasPendingRepositoryPublications) [s publishPendingRepositoryRecordsWithLimit:500];
    long long before=s.currentSeq;
    long long childSeq=[s recordForUUID:original.uuid].seq;
    CHECK([s applyRepositorySnapshot:@[RP(@"Renamed",YES)] complete:YES fromCache:NO requestStartSeq:before], @"library-only rename publishes");
    SeafFPPublicationBatch *batch=[s publicationBatchAfterSequence:before limit:1];
    CHECK(batch.repositoryEvents.count==1 && batch.records.count==0 && !batch.moreComing, @"root event appears independently of children");
    CHECK([s recordForUUID:original.uuid].seq==childSeq && !s.hasPendingRepositoryPublications, @"rename does not republish whole library");
    before=s.currentSeq;
    CHECK([s applyRepositorySnapshot:@[RP(@"Renamed",NO)] complete:YES fromCache:NO requestStartSeq:before], @"permission change accepted");
    CHECK([s publishPendingRepositoryRecordsWithLimit:3] && s.hasPendingRepositoryPublications, @"one bounded pass");
    CHECK([s recordsChangedSinceSeq:before limit:0].count==3, @"only three identities touched");
    [s close]; s=[[SeafFPStore alloc] initWithDomainIdentifier:@"publication" error:nil];
    CHECK(s.hasPendingRepositoryPublications, @"reopen resumes cursor");
    while(s.hasPendingRepositoryPublications) [s publishPendingRepositoryRecordsWithLimit:500];
    NSMutableSet *seen=[NSMutableSet set]; long long anchor=before; NSUInteger rootCount=0;
    do {
        batch=[s publicationBatchAfterSequence:anchor limit:127];
        for(SeafFPRecord *r in batch.records) [seen addObject:r.uuid];
        rootCount+=batch.repositoryEvents.count; anchor=batch.sequence;
    } while(batch.moreComing);
    CHECK(seen.count==1100 && rootCount==1 && anchor==s.currentSeq, @"bounded union drains all identities and root event");
    CHECK([[s decorationForItem:original.itemIdentifier].favoriteRank isEqual:@42] && [[s recordForUUID:original.uuid].oid isEqual:@"content"], @"republish preserves content and decoration");
    SeafFPStore *other=[[SeafFPStore alloc] initWithDomainIdentifier:@"publication" error:nil];
    CHECK(![other applyRepositorySnapshot:@[RP(@"Old",YES)] complete:YES fromCache:YES requestStartSeq:-1], @"cache cannot roll permissions back");
    CHECK(![other applyRepositorySnapshot:@[RP(@"Old",YES)] complete:YES fromCache:NO requestStartSeq:before], @"old response rejected across processes");
    CHECK(![s.repositoryStates[@"publication"][@"editable"] boolValue], @"new permission survives");
    CHECK(![s applyRepositorySnapshot:@[] complete:NO fromCache:NO requestStartSeq:s.currentSeq], @"partial list cannot remove");
    CHECK(![s applyRepositorySnapshot:@[] complete:YES fromCache:YES requestStartSeq:-1], @"cached empty list cannot remove");
    before=s.currentSeq;
    CHECK([s applyRepositorySnapshot:@[] complete:YES fromCache:NO requestStartSeq:before], @"complete fresh list confirms removal");
    batch=[s publicationBatchAfterSequence:before limit:1];
    CHECK([batch.repositoryEvents.firstObject[@"eventKind"] isEqual:@"delete"] && ![s recordForUUID:original.uuid].deleted, @"library removal preserves local identity");
    CHECK([s applyRepositorySnapshot:@[RP(@"Back",NO)] complete:YES fromCache:NO requestStartSeq:s.currentSeq] && s.hasPendingRepositoryPublications, @"restored library republishes existing UUIDs");
    [s publishPendingRepositoryRecordsWithLimit:5];
    CHECK([s applyRepositorySnapshot:@[RP(@"Back",YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq], @"new revision replaces unfinished permission pass");
    while(s.hasPendingRepositoryPublications) [s publishPendingRepositoryRecordsWithLimit:500];
    CHECK([s.repositoryStates[@"publication"][@"editable"] boolValue] && !s.hasPendingRepositoryPublications, @"latest revision finishes");
    NSMutableDictionary *locked=[RP(@"Back",YES) mutableCopy]; locked[@"locked"]=@YES;
    CHECK([s applyRepositorySnapshot:@[locked] complete:YES fromCache:NO requestStartSeq:s.currentSeq], @"lock is a state transition");
    CHECK([s.repositoryStates[@"publication"][@"availability"] isEqual:@"locked"] && ![s.repositoryStates[@"publication"][@"eventKind"] isEqual:@"delete"], @"lock is not deletion");
    CHECK(![s recordForUUID:original.uuid].deleted, @"lock preserves identity");
    [other close];
    // Only repository events move the recovery floor beyond all identity rows.
    for(NSUInteger i=0;i<5;i++) [s applyRepositorySnapshot:@[RP([NSString stringWithFormat:@"Library%lu",(unsigned long)i],YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    long long floor=s.currentSeq;
    [s close]; sqlite3 *raw=NULL; NSString *path=[SeafFPIdentifier storeURLForDomainIdentifier:@"publication"].path;
    sqlite3_open(path.fileSystemRepresentation,&raw);
    sqlite3_exec(raw,"DELETE FROM meta WHERE key IN ('seq', 'schema_version')",NULL,NULL,NULL); sqlite3_close(raw);
    s=[[SeafFPStore alloc] initWithDomainIdentifier:@"publication" error:nil];
    CHECK(s.currentSeq>=floor && s.nextSeq>floor, @"repo event participates in sequence recovery");
    [s close];
    sqlite3_open(path.fileSystemRepresentation,&raw);
    sqlite3_exec(raw,"DELETE FROM meta WHERE key = 'seq'",NULL,NULL,NULL); sqlite3_close(raw);
    s=[[SeafFPStore alloc] initWithDomainIdentifier:@"publication" error:nil];
    CHECK(s.currentSeq>=floor, @"missing counter alone is repaired before freshness comparisons");
    [s close];
    SeafFPStore *legacy=[[SeafFPStore alloc] initWithDomainIdentifier:@"publication-legacy" error:nil];
    SeafFPRecord *hidden=[legacy upsertRecordForRepo:@"old-library" path:@"/file.txt" isDir:NO parentUUID:nil oid:@"old" mtime:10 size:5];
    long long legacyBefore=legacy.currentSeq;
    CHECK([legacy applyRepositorySnapshot:@[] complete:YES fromCache:NO requestStartSeq:legacyBefore], @"fresh empty catalog publishes legacy library removal");
    CHECK(legacy.hasAuthoritativeRepositoryList && ![legacy recordForUUID:hidden.uuid].deleted, @"empty and unknown catalogs remain distinct without losing identity");
    CHECK([legacy publicationBatchAfterSequence:legacyBefore limit:10].repositoryEvents.count==1, @"legacy removal survives in the sequence stream");
    CHECK(![legacy applyRepositorySnapshot:@[RP(@"Stale cached library",YES)] complete:YES fromCache:YES requestStartSeq:-1], @"cache cannot introduce an unknown library after a complete empty catalog");
    CHECK(legacy.repositoryStates[@"publication"]==nil, @"unknown stale library stays absent");
    [legacy close];
    FailingPublicationStore *f=[[FailingPublicationStore alloc] initWithDomainIdentifier:@"publication-failure" error:nil];
    f.failBegin=YES;
    CHECK(![f applyRepositorySnapshot:@[RP(@"Library",YES)] complete:YES fromCache:NO requestStartSeq:0] && f.repositoryStates.count==0, @"failed lock never autocommits half a publication");
    f.failBegin=NO; f.failCommit=YES;
    CHECK(![f applyRepositorySnapshot:@[RP(@"Library",YES)] complete:YES fromCache:NO requestStartSeq:0], @"failed commit is not reported as success");
    CHECK(f.currentSeq==0 && f.repositoryStates.count==0 && f.pendingWorkingSetSignalTicket==0, @"failed commit rolls state, seq and signal back");
    CHECK([f requestWorkingSetSignal], @"outbox commit"); long long first=f.pendingWorkingSetSignalTicket;
    [f requestWorkingSetSignal]; long long second=f.pendingWorkingSetSignalTicket;
    CHECK([f completeWorkingSetSignalTicket:first] && f.pendingWorkingSetSignalTicket==second, @"old callback preserves a newer request");
    CHECK([f completeWorkingSetSignalTicket:second] && f.pendingWorkingSetSignalTicket==0 && f.currentSeq==0, @"signal completion does not generate content changes");
    [f close];
    CHECK([SeafFPStore openExistingStoreForDomainIdentifier:@"never-created"]==nil && ![[NSFileManager defaultManager] fileExistsAtPath:[SeafFPIdentifier storeURLForDomainIdentifier:@"never-created"].path], @"retry cannot create a missing store");
}

static void runReviewRegressionTests(SeafFPStore *ix)
{
    // A destination browse learnt children (and favorites) while a directory
    // move was in flight. Unique children keep their UUID; overlapping children
    // keep the source UUID and inherit destination decorations and metadata.
    NSString *repo = @"review-subtree";
    SeafFPRecord *src = reviewRow(ix, repo, @"/src", YES, nil, nil);
    reviewRow(ix, repo, @"/dst", YES, nil, nil);
    SeafFPRecord *folder = reviewRow(ix, repo, @"/src/folder", YES, src.uuid, @"folder");
    SeafFPRecord *known = reviewRow(ix, repo, @"/src/folder/known", YES, folder.uuid, @"known");
    SeafFPRecord *knownFile = reviewRow(ix, repo, @"/src/folder/known/shared.txt", NO, known.uuid, @"shared");
    long long start = ix.currentSeq;
    NSArray *destination = @[LE(@"folder", YES, @"folder", -1, 10)];
    CHECK([ix applyListingOfRepo:repo directoryPath:@"/dst" entries:destination requestStartSeq:start], @"destination learnt moved directory first");
    SeafFPRecord *provisional = [ix recordForRepo:repo path:@"/dst/folder" includeDeleted:NO];
    SeafFPRecord *provisionalKnown = reviewRow(ix, repo, @"/dst/folder/known", YES, provisional.uuid, @"known");
    SeafFPRecord *duplicate = reviewRow(ix, repo, @"/dst/folder/known/shared.txt", NO, provisionalKnown.uuid, @"shared");
    SeafFPRecord *unique = reviewRow(ix, repo, @"/dst/folder/known/new.txt", NO, provisionalKnown.uuid, @"unique");
    SeafFPRecord *uniqueDir = reviewRow(ix, repo, @"/dst/folder/new-dir", YES, provisional.uuid, @"new-dir");
    SeafFPRecord *nested = reviewRow(ix, repo, @"/dst/folder/new-dir/nested.txt", NO, uniqueDir.uuid, @"nested");
    reviewFavorite(ix, duplicate);
    reviewFavorite(ix, unique);
    reviewFavorite(ix, nested);
    CHECK([ix moveRecordsOfRepo:repo fromDirectory:@"/src" names:@[@"folder"] toRepo:repo toDirectory:@"/dst" destinationEntries:destination requestStartSeq:start], @"directory move merges browsed destination subtree");
    CHECK(eq([ix recordForRepo:repo path:@"/dst/folder" includeDeleted:NO].uuid, folder.uuid), @"directory keeps source UUID");
    CHECK(eq([ix recordForRepo:repo path:@"/dst/folder/known/shared.txt" includeDeleted:NO].uuid, knownFile.uuid), @"overlap keeps source child UUID");
    CHECK([[ix decorationForItem:knownFile.itemIdentifier].favoriteRank isEqual:@42], @"overlap inherits destination favorite");
    CHECK(([ix workingSetReasonForItem:knownFile.itemIdentifier] & SeafFPWorkingSetReasonFavorite) != 0, @"overlap inherits working set reason");
    CHECK([ix recordForUUID:duplicate.uuid].deleted && [ix decorationForItem:duplicate.itemIdentifier] == nil, @"provisional duplicate retired without orphan favorite");
    CHECK(![ix recordForUUID:unique.uuid].deleted && eq([ix recordForUUID:unique.uuid].parentUUID, known.uuid), @"destination-only file survives and is reparented");
    CHECK(![ix recordForUUID:uniqueDir.uuid].deleted && eq([ix recordForUUID:uniqueDir.uuid].parentUUID, folder.uuid), @"destination-only directory survives and is reparented");
    CHECK(![ix recordForUUID:nested.uuid].deleted && eq([ix recordForUUID:nested.uuid].parentUUID, uniqueDir.uuid), @"destination-only nested identity survives");
    CHECK([[ix decorationForItem:unique.itemIdentifier].favoriteRank isEqual:@42] && [[ix decorationForItem:nested.itemIdentifier].favoriteRank isEqual:@42], @"destination-only favorites survive");

    // Caches cannot recreate a moved file or a renamed ancestor, even through
    // a second store instance. A fresh server listing can reuse an old path.
    repo = @"review-cache";
    SeafFPRecord *cached = reviewRow(ix, repo, @"/old.txt", NO, nil, @"old");
    [ix moveRecordUUID:cached.uuid toRepo:repo path:@"/new.txt" parentUUID:nil];
    SeafFPStore *other = [[SeafFPStore alloc] initWithDomainIdentifier:ix.domainIdentifier error:nil];
    CHECK(![other applyListingOfRepo:repo directoryPath:@"/" entries:@[LE(@"old.txt", NO, @"old", 5, 10)] requestStartSeq:-1], @"cache after move is ignored across instances");
    CHECK([ix recordForRepo:repo path:@"/old.txt" includeDeleted:YES] == nil && ![ix recordForUUID:cached.uuid].deleted, @"cache does not create duplicate old path");
    SeafFPRecord *cachedDir = reviewRow(ix, repo, @"/old-dir", YES, nil, nil);
    [ix moveRecordUUID:cachedDir.uuid toRepo:repo path:@"/new-dir" parentUUID:nil];
    CHECK(![other applyListingOfRepo:repo directoryPath:@"/old-dir/deep" entries:@[LE(@"x.txt", NO, @"x", 5, 10)] requestStartSeq:-1], @"cache under renamed ancestor ignored");
    CHECK([ix recordForRepo:repo path:@"/old-dir" includeDeleted:YES] == nil, @"cache does not reconstruct vanished directory chain");
    NSArray *recreatedListing = @[LE(@"new.txt", NO, @"old", 5, 10), LE(@"new-dir", YES, nil, -1, 10), LE(@"old.txt", NO, @"replacement", 5, 20)];
    CHECK([ix applyListingOfRepo:repo directoryPath:@"/" entries:recreatedListing requestStartSeq:ix.currentSeq], @"fresh server listing can recreate old path");
    CHECK(!eq([ix recordForRepo:repo path:@"/old.txt" includeDeleted:NO].uuid, cached.uuid), @"reused path gets its own identity");
    [other close];

    [ix applyActivitiesOfRepo:@"review-log-cache" entries:@[AE(SeafFPActivityOpMove, @"/new.txt", @"/unknown-old.txt", NO, 200)]];
    // A rename seen only in the activity log leaves a barrier for its old path.
    CHECK(![ix applyListingOfRepo:@"review-log-cache" directoryPath:@"/" entries:@[LE(@"unknown-old.txt", NO, @"x", 5, 10)] requestStartSeq:-1], @"activity-only move barrier survives replay history pruning");
    CHECK([ix recordForRepo:@"review-log-cache" path:@"/unknown-old.txt" includeDeleted:YES] == nil, @"unknown old activity path not recreated");

    // Cross-library moves do not have a matching move event. An ambiguous
    // delete must persist a live-directory recheck, not silently keep the row.
    SeafFPRecord *old = reviewRow(ix, @"review-cross-dst", @"/a.txt", NO, nil, @"old");
    [ix markDeletedUUID:old.uuid];
    SeafFPRecord *cross = reviewRow(ix, @"review-cross-src", @"/a.txt", NO, nil, @"new");
    CHECK([ix moveRecordsOfRepo:@"review-cross-src" fromDirectory:@"/" names:@[@"a.txt"] toRepo:@"review-cross-dst" toDirectory:@"/" destinationEntries:@[LE(@"a.txt", NO, @"new", 5, 10)] requestStartSeq:ix.currentSeq], @"cross-library move replaces old tombstone");
    [ix applyActivitiesOfRepo:@"review-cross-src" entries:@[AE(SeafFPActivityOpDelete, @"/a.txt", nil, NO, 200)]];
    [ix applyActivitiesOfRepo:@"review-cross-dst" entries:@[AE(SeafFPActivityOpCreate, @"/a.txt", nil, NO, 200)]];
    [ix applyActivitiesOfRepo:@"review-cross-dst" entries:@[AE(SeafFPActivityOpDelete, @"/a.txt", nil, NO, 300)]];
    CHECK(![ix recordForUUID:cross.uuid].deleted && [[ix activityRecheckDirectoryPathsOfRepo:@"review-cross-dst"] containsObject:@"/"], @"unacknowledged move requests authoritative delete check");
    other = [[SeafFPStore alloc] initWithDomainIdentifier:ix.domainIdentifier error:nil];
    CHECK([[other activityRecheckDirectoryPathsOfRepo:@"review-cross-dst"] containsObject:@"/"], @"pending recheck persists across store instances");
    CHECK(![ix applyListingOfRepo:@"review-cross-dst" directoryPath:@"/" entries:@[] requestStartSeq:-1], @"cached empty directory cannot confirm deletion");
    CHECK([[ix activityRecheckDirectoryPathsOfRepo:@"review-cross-dst"] containsObject:@"/"], @"cache does not acknowledge recheck");
    CHECK(![ix applyListingOfRepo:@"review-cross-dst" directoryPath:@"/" entries:@[] requestStartSeq:0], @"stale network listing rejected");
    CHECK([[ix activityRecheckDirectoryPathsOfRepo:@"review-cross-dst"] containsObject:@"/"], @"rejected listing does not acknowledge recheck");
    CHECK([ix applyListingOfRepo:@"review-cross-dst" directoryPath:@"/" entries:@[] requestStartSeq:ix.currentSeq], @"fresh listing confirms real deletion");
    CHECK([ix recordForUUID:cross.uuid].deleted && [ix activityRecheckDirectoryPathsOfRepo:@"review-cross-dst"].count == 0, @"real deletion is applied and recheck acknowledged");
    [other close];

    // History and the move acknowledgement can arrive in separate pages.
    repo = @"review-split";
    SeafFPRecord *split = reviewRow(ix, repo, @"/source.txt", NO, nil, @"same");
    reviewFavorite(ix, split);
    [ix moveRecordUUID:split.uuid toRepo:repo path:@"/destination.txt" parentUUID:nil];
    [ix applyActivitiesOfRepo:repo entries:@[AE(SeafFPActivityOpDelete, @"/destination.txt", nil, NO, 100)]];
    CHECK(![ix recordForUUID:split.uuid].deleted, @"first activity page cannot delete later moved identity");
    CHECK([[ix activityRecheckDirectoryPathsOfRepo:repo] containsObject:@"/"], @"ambiguous first page schedules recheck");
    [ix applyActivitiesOfRepo:repo entries:@[AE(SeafFPActivityOpMove, @"/destination.txt", @"/source.txt", NO, 200)]];
    CHECK(![ix recordForUUID:split.uuid].deleted && [[ix decorationForItem:split.itemIdentifier].favoriteRank isEqual:@42], @"next-page move acknowledgement preserves UUID and favorite");
    [ix applyListingOfRepo:repo directoryPath:@"/" entries:@[LE(@"destination.txt", NO, @"same", 5, 10)] requestStartSeq:ix.currentSeq];
    CHECK([ix activityRecheckDirectoryPathsOfRepo:repo].count == 0, @"unchanged fresh listing also acknowledges recheck");
    CHECK([ix applyActivitiesOfRepo:repo entries:@[AE(SeafFPActivityOpDelete, @"/destination.txt", nil, NO, 300)]]
          && ![ix recordForUUID:split.uuid].deleted, @"a later delete asks for a listing instead of deleting");
    [ix applyListingOfRepo:repo directoryPath:@"/" entries:@[] requestStartSeq:ix.currentSeq];
    CHECK([ix recordForUUID:split.uuid].deleted, @"the fresh listing applies the real delete");

    // Rename shares move's reconciliation when the refreshed new name and
    // source tombstone reach the store before the operation acknowledgement.
    repo = @"review-rename";
    SeafFPRecord *renamed = reviewRow(ix, repo, @"/old.txt", NO, nil, @"same");
    reviewFavorite(ix, renamed);
    start = ix.currentSeq;
    NSArray *renamedListing = @[LE(@"new.txt", NO, @"same", 5, 10)];
    CHECK([ix applyListingOfRepo:repo directoryPath:@"/" entries:renamedListing requestStartSeq:start], @"refresh observes rename before acknowledgement");
    CHECK([ix renameRecordOfRepo:repo directory:@"/" fromName:@"old.txt" toName:@"new.txt" listing:renamedListing requestStartSeq:start], @"rename reconciles refreshed rows");
    CHECK(![ix recordForUUID:renamed.uuid].deleted && eq([ix recordForRepo:repo path:@"/new.txt" includeDeleted:NO].uuid, renamed.uuid), @"rename retains original UUID");
    CHECK([[ix decorationForItem:renamed.itemIdentifier].favoriteRank isEqual:@42], @"rename retains favorite");

    repo = @"review-rename-dir";
    SeafFPRecord *renamedDir = reviewRow(ix, repo, @"/old", YES, nil, nil);
    SeafFPRecord *renamedChild = reviewRow(ix, repo, @"/old/a.txt", NO, renamedDir.uuid, @"a");
    reviewFavorite(ix, renamedChild);
    start = ix.currentSeq;
    NSArray *dirListing = @[LE(@"new", YES, nil, -1, 10)];
    [ix applyListingOfRepo:repo directoryPath:@"/" entries:dirListing requestStartSeq:start];
    CHECK([ix renameRecordOfRepo:repo directory:@"/" fromName:@"old" toName:@"new" listing:dirListing requestStartSeq:start], @"directory rename reconciles refreshed tombstone subtree");
    CHECK(![ix recordForUUID:renamedChild.uuid].deleted && eq([ix recordForUUID:renamedChild.uuid].path, @"/new/a.txt"), @"directory rename preserves child UUID");
    CHECK([[ix decorationForItem:renamedChild.itemIdentifier].favoriteRank isEqual:@42], @"directory rename preserves child favorite");
}

static NSDictionary *activityEntry(NSString *repo, NSString *hash, NSString *op, NSString *path, NSString *oldPath, BOOL isDir, long long time)
{
    NSMutableDictionary *d = [AE(op, path, oldPath, isDir, time) mutableCopy];
    d[SeafFPEntryRepoId] = repo;
    d[SeafFPEntryActivityHash] = hash;
    return d;
}

static void runActivityTests(SeafFPStore *ix)
{
    // The activity log writes no identity: it only asks for listings.
    SeafFPRecord *known = [ix upsertRecordForRepo:@"a1" path:@"/known.txt" isDir:NO parentUUID:nil oid:@"ok" mtime:500 size:9];
    [ix upsertRecordForRepo:@"a1" path:@"/web" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    long long before = ix.currentSeq;
    NSArray *page = @[AE(SeafFPActivityOpCreate, @"/web/new.docx", nil, NO, 1000),
                      AE(SeafFPActivityOpCreate, @"/web/other.docx", nil, NO, 1001),
                      AE(SeafFPActivityOpDelete, @"/known.txt", nil, NO, 1002),
                      AE(SeafFPActivityOpDelete, @"/never-seen.txt", nil, NO, 1003),
                      AE(SeafFPActivityOpMove, @"/deep/b", @"/deep/a", YES, 1004)];
    CHECK([ix applyActivitiesOfRepo:@"a1" entries:page], @"page recorded");
    CHECK([ix recordForRepo:@"a1" path:@"/web/new.docx" includeDeleted:YES] == nil && ![ix recordForUUID:known.uuid].deleted
          && [ix recordsChangedSinceSeq:before].count == 0, @"no identity written by the activity log");
    CHECK([[ix activityRecheckDirectoryPathsOfRepo:@"a1"] isEqual:(@[@"/", @"/deep", @"/web"])], @"checks %@", [ix activityRecheckDirectoryPathsOfRepo:@"a1"]);
    CHECK(![ix applyActivitiesOfRepo:@"a1" entries:page], @"replaying the page records nothing");
    [ix applyListingOfRepo:@"a1" directoryPath:@"/web" entries:@[LE(@"new.docx", NO, @"n", 1, 1000)] requestStartSeq:ix.currentSeq];
    [ix applyListingOfRepo:@"a1" directoryPath:@"/" entries:@[LE(@"web", YES, nil, -1, 1)] requestStartSeq:ix.currentSeq];
    CHECK([ix recordForUUID:known.uuid].deleted && [ix recordForRepo:@"a1" path:@"/web/new.docx" includeDeleted:NO]
          && [[ix activityRecheckDirectoryPathsOfRepo:@"a1"] isEqual:@[@"/deep"]], @"listings answer the checks");

    // Delete, then upload again (P10a), and a delete that arrives after the
    // upload was already confirmed (P10b): the listing keeps the file.
    SeafFPRecord *again = [ix upsertRecordForRepo:@"a2" path:@"/f.txt" isDir:NO parentUUID:nil oid:@"x" mtime:100 size:5];
    reviewFavorite(ix, again);
    [ix applyActivitiesOfRepo:@"a2" entries:@[AE(SeafFPActivityOpDelete, @"/f.txt", nil, NO, 200), AE(SeafFPActivityOpCreate, @"/f.txt", nil, NO, 300)]];
    CHECK(![ix recordForUUID:again.uuid].deleted, @"delete + upload does not delete");
    [ix applyListingOfRepo:@"a2" directoryPath:@"/" entries:@[LE(@"f.txt", NO, @"x", 5, 100)] requestStartSeq:ix.currentSeq];
    [ix applyActivitiesOfRepo:@"a2" entries:@[AE(SeafFPActivityOpDelete, @"/f.txt", nil, NO, 150)]];
    [ix applyListingOfRepo:@"a2" directoryPath:@"/" entries:@[LE(@"f.txt", NO, @"x", 5, 100)] requestStartSeq:ix.currentSeq];
    CHECK(![ix recordForUUID:again.uuid].deleted && [[ix decorationForItem:again.itemIdentifier].favoriteRank isEqual:@42]
          && [ix activityRecheckDirectoryPathsOfRepo:@"a2"].count == 0, @"re-uploaded file keeps its identity and favorite");

    // An aggregated delete whose items carry the batch's newest time (P7).
    SeafFPRecord *a = [ix upsertRecordForRepo:@"a3" path:@"/a.txt" isDir:NO parentUUID:nil oid:@"a" mtime:100 size:5];
    SeafFPRecord *c = [ix upsertRecordForRepo:@"a3" path:@"/c.txt" isDir:NO parentUUID:nil oid:@"c" mtime:100 size:5];
    NSArray *batch = @[activityEntry(@"a3", @"batch", SeafFPActivityOpDelete, @"/a.txt", nil, NO, 500),
                       activityEntry(@"a3", @"batch", SeafFPActivityOpDelete, @"/c.txt", nil, NO, 500)];
    CHECK([ix recordActivityEntries:batch progress:nil] == SeafFPWriteChanged, @"aggregated delete recorded");
    [ix applyListingOfRepo:@"a3" directoryPath:@"/" entries:@[LE(@"a.txt", NO, @"a2", 5, 100)] requestStartSeq:ix.currentSeq];
    CHECK(![ix recordForUUID:a.uuid].deleted && [ix recordForUUID:c.uuid].deleted, @"only the item really gone is deleted");
    // The same activity again is skipped; an aggregated update (new hash) is not.
    CHECK([ix recordActivityEntries:@[activityEntry(@"a3", @"batch", SeafFPActivityOpDelete, @"/a.txt", nil, NO, 500)] progress:nil] == SeafFPWriteUnchanged
          && [ix activityRecheckDirectoryPathsOfRepo:@"a3"].count == 0, @"seen activity skipped");
    CHECK([ix recordActivityEntries:@[activityEntry(@"a3", @"batch+1", SeafFPActivityOpDelete, @"/a.txt", nil, NO, 600)] progress:nil] == SeafFPWriteChanged
          && [[ix activityRecheckDirectoryPathsOfRepo:@"a3"] isEqual:@[@"/"]], @"updated aggregate recorded again");

    // Progress is stored with the page; the boundary prunes seen activities.
    NSDictionary *progress = @{@"boundary": @(500 + 2 * 86400), @"nextPage": @3};
    CHECK([ix recordActivityEntries:@[] progress:progress] != SeafFPWriteFailed && [[ix activityProgress] isEqual:progress], @"progress stored");
    CHECK([ix recordActivityEntries:@[activityEntry(@"a3", @"batch", SeafFPActivityOpDelete, @"/a.txt", nil, NO, 500)] progress:nil] == SeafFPWriteChanged,
          @"pruned activity counts as new again");

    // Activities seen by this instance are seen by any other on the same file.
    [ix applyActivitiesOfRepo:@"a_replay" entries:@[AE(SeafFPActivityOpCreate, @"/a.txt", nil, NO, 100),
                                                     AE(SeafFPActivityOpMove, @"/b.txt", @"/a.txt", NO, 200)]];

    // A failed write keeps nothing of the page, progress included.
    FailingStatementStore *f = [[FailingStatementStore alloc] initWithDomainIdentifier:@"activity-failure" error:nil];
    [f upsertRecordForRepo:@"r" path:@"/x.txt" isDir:NO parentUUID:nil oid:@"x" mtime:1 size:1];
    f.failStatement = ^BOOL(NSString *sql) { return [sql containsString:@"fp_activity_progress_v1"]; };
    CHECK([f recordActivityEntries:@[activityEntry(@"r", @"h1", SeafFPActivityOpDelete, @"/x.txt", nil, NO, 10)] progress:@{@"nextPage": @2}] == SeafFPWriteFailed,
          @"page with a failed progress write fails");
    f.failStatement = nil;
    CHECK([f activityRecheckDirectoryPathsOfRepo:@"r"].count == 0 && [f activityProgress].count == 0, @"nothing of the failed page kept");
    CHECK([f recordActivityEntries:@[activityEntry(@"r", @"h1", SeafFPActivityOpDelete, @"/x.txt", nil, NO, 10)] progress:@{@"nextPage": @2}] == SeafFPWriteChanged,
          @"the page is recorded when retried (its activities were not marked seen)");
    [f close];
}

static void runIndexingTests(void)
{
    NSError *err = nil;
    NSString *ixDomain = @"acct-index";
    SeafFPStore *ix = [[SeafFPStore alloc] initWithDomainIdentifier:ixDomain error:&err];
    CHECK(ix != nil, @"index store %@", err);

    // T13 read-only seq: never creates a store
    CHECK([SeafFPStore currentSeqForDomainIdentifier:@"acct-missing"] == -1, @"missing store reads -1");
    NSString *missingPath = [SeafFPIdentifier storeURLForDomainIdentifier:@"acct-missing"].path;
    CHECK(![[NSFileManager defaultManager] fileExistsAtPath:missingPath], @"reading did not create a store file");
    CHECK([SeafFPStore currentSeqForDomainIdentifier:ixDomain] == [ix currentSeq], @"read-only seq matches");

    // T1 atomic nextSeq, seeded from the rows when the counter row is missing
    long long s0 = [ix currentSeq];
    long long n1 = [ix nextSeq];
    long long n2 = [ix nextSeq];
    CHECK(n1 == s0 + 1 && n2 == s0 + 2 && [ix currentSeq] == n2, @"nextSeq %lld %lld (from %lld)", n1, n2, s0);
    SeafFPRecord *seedRow = [ix upsertRecordForRepo:@"rs" path:@"/seed" isDir:NO parentUUID:nil oid:@"o" mtime:1 size:1];
    [ix setMetaValue:nil forKey:@"seq"];
    long long n3 = [ix nextSeq];
    CHECK(n3 == seedRow.seq + 1, @"reseeded nextSeq %lld (rows up to %lld)", n3, seedRow.seq);
    CHECK([SeafFPStore currentSeqForDomainIdentifier:ixDomain] == n3, @"read-only seq after reseed");

    // T2 first sync of a never-seen deep directory, then idempotent
    long long S = [ix currentSeq];
    NSArray *listC = @[LE(@"f1.txt", NO, @"o1", 10, 100), LE(@"sub", YES, @"d1", -1, 100)];
    CHECK([ix applyListingOfRepo:@"r1" directoryPath:@"/A/B/C" entries:listC requestStartSeq:S], @"first sync applies");
    SeafFPRecord *aRec = [ix recordForRepo:@"r1" path:@"/A" includeDeleted:NO];
    SeafFPRecord *bRec = [ix recordForRepo:@"r1" path:@"/A/B" includeDeleted:NO];
    SeafFPRecord *cRec = [ix recordForRepo:@"r1" path:@"/A/B/C" includeDeleted:NO];
    SeafFPRecord *f1 = [ix recordForRepo:@"r1" path:@"/A/B/C/f1.txt" includeDeleted:NO];
    CHECK(aRec && bRec && cRec && aRec.isDir && aRec.parentUUID == nil && eq(bRec.parentUUID, aRec.uuid) && eq(cRec.parentUUID, bRec.uuid), @"chain created");
    CHECK(f1 && eq(f1.parentUUID, cRec.uuid) && eq(f1.oid, @"o1") && f1.size == 10 && f1.mtime == 100, @"child %@", f1);
    CHECK([ix recordForRepo:@"r1" path:@"/A/B/C/sub" includeDeleted:NO].isDir, @"dir child");
    long long afterFirst = [ix currentSeq];
    CHECK(![ix applyListingOfRepo:@"r1" directoryPath:@"/A/B/C" entries:listC requestStartSeq:afterFirst] && [ix currentSeq] == afterFirst, @"same listing again is a no-op");

    // T3 a direct child written after the request is left alone; the rest of the listing applies
    S = [ix currentSeq];
    [ix upsertRecordForRepo:@"r1" path:@"/A/B/C/new.txt" isDir:NO parentUUID:cRec.uuid oid:@"on" mtime:5 size:1];
    CHECK([ix applyListingOfRepo:@"r1" directoryPath:@"/" entries:@[LE(@"A", YES, @"dA", -1, 1)] requestStartSeq:S], @"root listing applies despite a deep change");
    CHECK([ix applyDirectoryListingOfRepo:@"r1" directoryPath:@"/A/B/C" entries:listC requestStartSeq:S] == SeafFPWriteUnchanged, @"stale listing of C applies around the newer child");
    CHECK([ix recordForRepo:@"r1" path:@"/A/B/C/new.txt" includeDeleted:NO] != nil, @"new file kept");

    // T4 an entry moved out of the directory after the request: the stamp rejects the listing
    S = [ix currentSeq];
    [ix moveRecordUUID:f1.uuid toRepo:@"r1" path:@"/A/B/f1.txt" parentUUID:bRec.uuid];
    CHECK([ix directoryStampForRepo:@"r1" parentUUID:cRec.uuid] > S, @"stamp on the directory the entry left");
    NSArray *staleC = @[LE(@"f1.txt", NO, @"o1", 10, 100), LE(@"sub", YES, @"d1", -1, 100), LE(@"new.txt", NO, @"on", 1, 5)];
    CHECK(![ix applyListingOfRepo:@"r1" directoryPath:@"/A/B/C" entries:staleC requestStartSeq:S], @"listing from before the move rejected");
    CHECK([ix recordForRepo:@"r1" path:@"/A/B/C/f1.txt" includeDeleted:YES] == nil, @"no ghost at the old path");
    // renaming an ancestor makes the path stale as well
    S = [ix currentSeq];
    [ix moveRecordUUID:bRec.uuid toRepo:@"r1" path:@"/A/B2" parentUUID:aRec.uuid];
    CHECK(![ix applyListingOfRepo:@"r1" directoryPath:@"/A/B/C" entries:staleC requestStartSeq:S], @"listing under a renamed ancestor rejected");
    CHECK([ix recordForRepo:@"r1" path:@"/A/B" includeDeleted:YES] == nil && [ix recordForRepo:@"r1" path:@"/A/B/C" includeDeleted:YES] == nil, @"no ghost chain");
    // a fresh listing after the change applies again
    S = [ix currentSeq];
    CHECK([ix applyListingOfRepo:@"r1" directoryPath:@"/A/B2/C" entries:@[LE(@"z.txt", NO, @"oz", 1, 1)] requestStartSeq:S], @"fresh listing applies");
    CHECK([ix recordForRepo:@"r1" path:@"/A/B2/C/new.txt" includeDeleted:YES].deleted, @"entry missing from the fresh listing tombstoned");

    // T5 subtree guard of a vanished directory; % and _ are no wildcards
    SeafFPRecord *pd = [ix upsertRecordForRepo:@"r5" path:@"/100%_dir" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    SeafFPRecord *pSub = [ix upsertRecordForRepo:@"r5" path:@"/100%_dir/sub" isDir:YES parentUUID:pd.uuid oid:nil mtime:1 size:-1];
    SeafFPRecord *pFile = [ix upsertRecordForRepo:@"r5" path:@"/100%_dir/sub/f.txt" isDir:NO parentUUID:pSub.uuid oid:@"of" mtime:1 size:1];
    S = [ix currentSeq];
    SeafFPRecord *lookAlike = [ix ensureRecordChainForRepo:@"r5" path:@"/100a_dir/sub/z.txt" isDir:NO];   // newer row a LIKE would match
    CHECK([ix applyListingOfRepo:@"r5" directoryPath:@"/100%_dir" entries:@[] requestStartSeq:S], @"vanished subdirectory removed");
    CHECK([ix recordForUUID:pSub.uuid].deleted && [ix recordForUUID:pFile.uuid].deleted, @"subtree tombstoned");
    CHECK(![ix recordForUUID:lookAlike.uuid].deleted, @"look-alike path untouched");
    SeafFPRecord *qd = [ix upsertRecordForRepo:@"r5" path:@"/q%_d" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    SeafFPRecord *qSub = [ix upsertRecordForRepo:@"r5" path:@"/q%_d/sub" isDir:YES parentUUID:qd.uuid oid:nil mtime:1 size:-1];
    SeafFPRecord *qFile = [ix upsertRecordForRepo:@"r5" path:@"/q%_d/sub/f.txt" isDir:NO parentUUID:qSub.uuid oid:@"o1" mtime:1 size:1];
    S = [ix currentSeq];
    [ix upsertRecordForRepo:@"r5" path:@"/q%_d/sub/f.txt" isDir:NO parentUUID:qSub.uuid oid:@"o2" mtime:2 size:2];   // written into the subtree after the request
    [ix applyListingOfRepo:@"r5" directoryPath:@"/q%_d" entries:@[] requestStartSeq:S];
    CHECK(![ix recordForUUID:qSub.uuid].deleted && ![ix recordForUUID:qFile.uuid].deleted, @"subdirectory with a newer row kept");

    // T6 an ancestor tombstoned after the request: nothing is written
    [ix ensureRecordChainForRepo:@"r6" path:@"/A/B/C/x.txt" isDir:NO];
    SeafFPRecord *r6a = [ix recordForRepo:@"r6" path:@"/A" includeDeleted:NO];
    S = [ix currentSeq];
    [ix markDeletedUUID:r6a.uuid];
    long long beforeT6 = [ix currentSeq];
    CHECK(![ix applyListingOfRepo:@"r6" directoryPath:@"/A/B/C" entries:@[LE(@"x.txt", NO, @"ox", 1, 1)] requestStartSeq:S], @"rejected");
    CHECK([ix currentSeq] == beforeT6 && [ix recordForUUID:r6a.uuid].deleted && [ix recordForRepo:@"r6" path:@"/A/B/C" includeDeleted:YES].deleted, @"no write, no revive");

    // T7 unknown request time: insert unknown paths only
    SeafFPRecord *dDir = [ix upsertRecordForRepo:@"r7" path:@"/D" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    SeafFPRecord *dA = [ix upsertRecordForRepo:@"r7" path:@"/D/a.txt" isDir:NO parentUUID:dDir.uuid oid:@"o1" mtime:1 size:1];
    SeafFPRecord *dB = [ix upsertRecordForRepo:@"r7" path:@"/D/b.txt" isDir:NO parentUUID:dDir.uuid oid:@"ob" mtime:1 size:1];
    SeafFPRecord *dKeep = [ix upsertRecordForRepo:@"r7" path:@"/D/keep.txt" isDir:NO parentUUID:dDir.uuid oid:@"ok" mtime:1 size:1];
    [ix markDeletedUUID:dB.uuid];
    NSArray *listD = @[LE(@"a.txt", NO, @"o2", 2, 2), LE(@"b.txt", NO, @"ob", 1, 1), LE(@"c.txt", NO, @"oc", 1, 1)];
    CHECK([ix applyListingOfRepo:@"r7" directoryPath:@"/D" entries:listD requestStartSeq:-1], @"unknown paths inserted");
    CHECK(eq([ix recordForUUID:dA.uuid].oid, @"o1"), @"existing row not updated");
    CHECK([ix recordForUUID:dB.uuid].deleted, @"tombstone not revived");
    CHECK(![ix recordForUUID:dKeep.uuid].deleted, @"nothing tombstoned");
    CHECK([ix recordForRepo:@"r7" path:@"/D/c.txt" includeDeleted:NO] != nil, @"new row inserted");

    // T8 sparse entries keep oid / size, never revive unless allowed
    SeafFPRecord *doc = [ix upsertRecordForRepo:@"r8" path:@"/doc.pdf" isDir:NO parentUUID:nil oid:@"sha1_abc" mtime:100 size:4096];
    CHECK([ix applySparseEntriesOfRepo:@"r8" entries:@[SE(@"/doc.pdf", NO, nil, -1, 200)] allowRevive:NO], @"sparse update");
    SeafFPRecord *doc2 = [ix recordForUUID:doc.uuid];
    CHECK(eq(doc2.oid, @"sha1_abc") && doc2.size == 4096 && doc2.mtime == 200, @"oid and size kept: %@", doc2);
    [ix markDeletedUUID:doc.uuid];
    CHECK(![ix applySparseEntriesOfRepo:@"r8" entries:@[SE(@"/doc.pdf", NO, nil, -1, 300)] allowRevive:NO] && [ix recordForUUID:doc.uuid].deleted, @"no revive");
    CHECK([ix applySparseEntriesOfRepo:@"r8" entries:@[SE(@"/doc.pdf", NO, @"sha1_new", 5, 300)] allowRevive:YES] && ![ix recordForUUID:doc.uuid].deleted, @"revive allowed");
    SeafFPRecord *goneDir = [ix upsertRecordForRepo:@"r8" path:@"/gone" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    [ix markDeletedUUID:goneDir.uuid];
    [ix applySparseEntriesOfRepo:@"r8" entries:@[SE(@"/gone/x.txt", NO, nil, 1, 1)] allowRevive:NO];
    CHECK([ix recordForRepo:@"r8" path:@"/gone/x.txt" includeDeleted:YES] == nil && [ix recordForUUID:goneDir.uuid].deleted, @"nothing below a tombstone");
    CHECK([ix applySparseEntriesOfRepo:@"r8" entries:@[SE(@"/n1/n2/f.txt", NO, nil, 3, 1)] allowRevive:NO], @"deep sparse entry");
    SeafFPRecord *sparseDeep = [ix recordForRepo:@"r8" path:@"/n1/n2/f.txt" includeDeleted:NO];
    CHECK(sparseDeep && sparseDeep.oid == nil && sparseDeep.size == 3 && eq(sparseDeep.parentUUID, [ix recordForRepo:@"r8" path:@"/n1/n2" includeDeleted:NO].uuid), @"chain for sparse entry: %@", sparseDeep);

    // T9 moves keep the uuid, subtrees follow, occupied destinations are skipped
    SeafFPRecord *srcDir = [ix upsertRecordForRepo:@"r9" path:@"/src" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    SeafFPRecord *mvA = [ix upsertRecordForRepo:@"r9" path:@"/src/a.txt" isDir:NO parentUUID:srcDir.uuid oid:@"oa" mtime:1 size:1];
    SeafFPRecord *mvDir = [ix upsertRecordForRepo:@"r9" path:@"/src/dirx" isDir:YES parentUUID:srcDir.uuid oid:nil mtime:1 size:-1];
    SeafFPRecord *mvInner = [ix upsertRecordForRepo:@"r9" path:@"/src/dirx/inner.txt" isDir:NO parentUUID:mvDir.uuid oid:@"oi" mtime:1 size:1];
    SeafFPRecord *mvB = [ix upsertRecordForRepo:@"r9" path:@"/src/b.txt" isDir:NO parentUUID:srcDir.uuid oid:@"ob" mtime:1 size:1];
    [ix ensureRecordChainForRepo:@"r9" path:@"/dst/b.txt" isDir:NO];
    SeafFPDecoration *mvFav = [SeafFPDecoration new];
    mvFav.itemIdentifier = mvA.itemIdentifier;
    mvFav.favoriteRank = @3;
    [ix setDecoration:mvFav];
    NSArray *mvNames = @[@"a.txt", @"dirx", @"b.txt", @"missing"];
    NSArray *dstListingT9 = @[
        LE(@"a.txt", NO, @"oa", 1, 1),
        LE(@"dirx", YES, nil, -1, 1),
        LE(@"b.txt", NO, @"ob_existing", 1, 1),
    ];
    S = [ix currentSeq];
    CHECK([ix moveRecordsOfRepo:@"r9" fromDirectory:@"/src" names:mvNames toRepo:@"r9" toDirectory:@"/dst" destinationEntries:dstListingT9 requestStartSeq:S], @"moved");
    SeafFPRecord *dstDir = [ix recordForRepo:@"r9" path:@"/dst" includeDeleted:NO];
    CHECK(eq([ix recordForUUID:mvA.uuid].path, @"/dst/a.txt") && eq([ix recordForUUID:mvA.uuid].parentUUID, dstDir.uuid), @"uuid kept");
    CHECK(eq([ix recordForUUID:mvInner.uuid].path, @"/dst/dirx/inner.txt"), @"subtree followed");
    CHECK(eq([ix recordForUUID:mvB.uuid].path, @"/src/b.txt"), @"occupied destination skipped");
    CHECK([[ix decorationForItem:mvA.itemIdentifier].favoriteRank isEqual:@3], @"favorite survived the move");
    CHECK([ix directoryStampForRepo:@"r9" parentUUID:srcDir.uuid] > 0, @"source directory stamped");
    // rename keeps the uuid; a taken name or an unknown record is refused
    NSArray *renameListingT9 = @[
        LE(@"a2.txt", NO, @"oa", 1, 1),
        LE(@"dirx", YES, nil, -1, 1),
        LE(@"b.txt", NO, @"ob_existing", 1, 1),
    ];
    S = [ix currentSeq];
    CHECK([ix renameRecordOfRepo:@"r9" directory:@"/dst" fromName:@"a.txt" toName:@"a2.txt" listing:renameListingT9 requestStartSeq:S], @"renamed");
    CHECK(eq([ix recordForUUID:mvA.uuid].path, @"/dst/a2.txt") && eq([ix recordForUUID:mvA.uuid].parentUUID, dstDir.uuid), @"rename kept uuid and parent");
    S = [ix currentSeq];
    CHECK(![ix renameRecordOfRepo:@"r9" directory:@"/dst" fromName:@"a2.txt" toName:@"b.txt" listing:renameListingT9 requestStartSeq:S], @"taken name refused");
    CHECK(![ix renameRecordOfRepo:@"r9" directory:@"/dst" fromName:@"nope.txt" toName:@"x.txt" listing:renameListingT9 requestStartSeq:S], @"unknown record refused");

    // T9b (Issue 1): move when server auto-renames due to an unindexed conflict at destination
    SeafFPRecord *cSrcDir = [ix upsertRecordForRepo:@"r9_conflict" path:@"/src" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    SeafFPRecord *cMoved = [ix upsertRecordForRepo:@"r9_conflict" path:@"/src/report.txt" isDir:NO parentUUID:cSrcDir.uuid oid:@"oid_moved" mtime:10 size:200];
    SeafFPDecoration *cFav = [SeafFPDecoration new];
    cFav.itemIdentifier = cMoved.itemIdentifier;
    cFav.favoriteRank = @9;
    [ix setDecoration:cFav];
    // Target directory /dst already had an unindexed report.txt (oid_existing), so server named the moved file "report (1).txt"
    NSArray *cDstListing = @[
        LE(@"report.txt", NO, @"oid_existing", 100, 5),
        LE(@"report (1).txt", NO, @"oid_moved", 200, 10),
    ];
    S = [ix currentSeq];
    CHECK([ix moveRecordsOfRepo:@"r9_conflict" fromDirectory:@"/src" names:@[@"report.txt"] toRepo:@"r9_conflict" toDirectory:@"/dst" destinationEntries:cDstListing requestStartSeq:S], @"move with server conflict rename succeeded");
    CHECK(eq([ix recordForUUID:cMoved.uuid].path, @"/dst/report (1).txt"), @"moved UUID bound to server-renamed report (1).txt, got %@", [ix recordForUUID:cMoved.uuid].path);
    CHECK(eq([ix recordForUUID:cMoved.uuid].oid, @"oid_moved"), @"moved record keeps its content oid");
    CHECK([[ix decorationForItem:cMoved.itemIdentifier].favoriteRank isEqual:@9], @"favorite stayed with moved file");
    SeafFPRecord *cPreExisting = [ix recordForRepo:@"r9_conflict" path:@"/dst/report.txt" includeDeleted:NO];
    CHECK(cPreExisting && !eq(cPreExisting.uuid, cMoved.uuid) && eq(cPreExisting.oid, @"oid_existing"), @"pre-existing /dst/report.txt got its own distinct UUID");

    // Ambiguous conflict (moved record has no oid, and both report.txt and report (1).txt are unindexed): must not guess
    SeafFPRecord *ambSrc = [ix upsertRecordForRepo:@"r9_amb" path:@"/src" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    SeafFPRecord *ambFile = [ix upsertRecordForRepo:@"r9_amb" path:@"/src/report.txt" isDir:NO parentUUID:ambSrc.uuid oid:nil mtime:10 size:-1];
    S = [ix currentSeq];
    CHECK(![ix moveRecordsOfRepo:@"r9_amb" fromDirectory:@"/src" names:@[@"report.txt"] toRepo:@"r9_amb" toDirectory:@"/dst" destinationEntries:cDstListing requestStartSeq:S], @"ambiguous move without oid refuses to guess");
    CHECK(eq([ix recordForUUID:ambFile.uuid].path, @"/src/report.txt"), @"ambiguous record not wrongly bound to /dst/report.txt");

    // Rename when server auto-renames due to an unindexed conflict in the same directory
    SeafFPRecord *rConflictDir = [ix upsertRecordForRepo:@"r9_ren" path:@"/dir" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    SeafFPRecord *rConflictFile = [ix upsertRecordForRepo:@"r9_ren" path:@"/dir/draft.txt" isDir:NO parentUUID:rConflictDir.uuid oid:@"oid_draft" mtime:10 size:50];
    NSArray *rConflictListing = @[
        LE(@"final.txt", NO, @"oid_other", 80, 5),
        LE(@"final (1).txt", NO, @"oid_draft", 50, 10),
    ];
    S = [ix currentSeq];
    CHECK([ix renameRecordOfRepo:@"r9_ren" directory:@"/dir" fromName:@"draft.txt" toName:@"final.txt" listing:rConflictListing requestStartSeq:S], @"rename with server conflict rename succeeded");
    CHECK(eq([ix recordForUUID:rConflictFile.uuid].path, @"/dir/final (1).txt"), @"renamed UUID bound to final (1).txt");
    SeafFPRecord *rOther = [ix recordForRepo:@"r9_ren" path:@"/dir/final.txt" includeDeleted:NO];
    CHECK(rOther && !eq(rOther.uuid, rConflictFile.uuid) && eq(rOther.oid, @"oid_other"), @"pre-existing final.txt got its own UUID");

    // T9c (Issue 3): rename and move must validate requestStartSeq and protect newer records
    SeafFPRecord *seqDir = [ix upsertRecordForRepo:@"r9_seq" path:@"/d" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    SeafFPRecord *origA = [ix upsertRecordForRepo:@"r9_seq" path:@"/d/a.txt" isDir:NO parentUUID:seqDir.uuid oid:@"oid_orig" mtime:10 size:10];
    long long renameStartSeq = [ix currentSeq];
    // Before the rename callback arrives, Files replaces /d/a.txt with newer content
    [ix markDeletedUUID:origA.uuid];
    SeafFPRecord *replacementA = [ix upsertRecordForRepo:@"r9_seq" path:@"/d/a.txt" isDir:NO parentUUID:seqDir.uuid oid:@"oid_replacement" mtime:20 size:99];
    CHECK(replacementA.seq > renameStartSeq, @"replacement has newer seq");
    NSArray *staleRenameListing = @[LE(@"b.txt", NO, @"oid_orig", 10, 10)];
    CHECK(![ix renameRecordOfRepo:@"r9_seq" directory:@"/d" fromName:@"a.txt" toName:@"b.txt" listing:staleRenameListing requestStartSeq:renameStartSeq], @"stale rename rejected when source changed after requestStartSeq");
    CHECK(eq([ix recordForUUID:replacementA.uuid].path, @"/d/a.txt") && eq([ix recordForUUID:replacementA.uuid].oid, @"oid_replacement"), @"replacement file stayed at /d/a.txt with its content oid");
    CHECK([ix recordForRepo:@"r9_seq" path:@"/d/b.txt" includeDeleted:YES] == nil, @"replacement was not moved to /d/b.txt");

    // Stale move rejected when source record or directory changed after requestStartSeq
    SeafFPRecord *mSeqSrc = [ix upsertRecordForRepo:@"r9_mseq" path:@"/src" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    [ix upsertRecordForRepo:@"r9_mseq" path:@"/src/x.txt" isDir:NO parentUUID:mSeqSrc.uuid oid:@"oid_v1" mtime:10 size:10];
    long long moveStartSeq = [ix currentSeq];
    // Replacement written at /src/x.txt after moveStartSeq
    SeafFPRecord *xNewer = [ix upsertRecordForRepo:@"r9_mseq" path:@"/src/x.txt" isDir:NO parentUUID:mSeqSrc.uuid oid:@"oid_v2" mtime:30 size:30];
    NSArray *staleMoveDstListing = @[LE(@"x.txt", NO, @"oid_v1", 10, 10)];
    CHECK(![ix moveRecordsOfRepo:@"r9_mseq" fromDirectory:@"/src" names:@[@"x.txt"] toRepo:@"r9_mseq" toDirectory:@"/dst" destinationEntries:staleMoveDstListing requestStartSeq:moveStartSeq], @"stale move rejected when source record changed after requestStartSeq");
    CHECK(eq([ix recordForUUID:xNewer.uuid].path, @"/src/x.txt") && eq([ix recordForUUID:xNewer.uuid].oid, @"oid_v2"), @"newer record at /src/x.txt untouched by stale move");
    CHECK([ix recordForRepo:@"r9_mseq" path:@"/dst/x.txt" includeDeleted:YES] == nil, @"/dst/x.txt not created by rejected move");

    // T9d: source directory refresh returning before destination confirmation preserves moved UUIDs
    SeafFPRecord *raceSrc = [ix upsertRecordForRepo:@"r9_race" path:@"/src" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    SeafFPRecord *raceFile = [ix upsertRecordForRepo:@"r9_race" path:@"/src/doc.txt" isDir:NO parentUUID:raceSrc.uuid oid:@"oid_doc" mtime:10 size:42];
    SeafFPRecord *raceDir = [ix upsertRecordForRepo:@"r9_race" path:@"/src/folder" isDir:YES parentUUID:raceSrc.uuid oid:nil mtime:10 size:-1];
    SeafFPRecord *raceChild = [ix upsertRecordForRepo:@"r9_race" path:@"/src/folder/nested.txt" isDir:NO parentUUID:raceDir.uuid oid:@"oid_nested" mtime:10 size:7];
    SeafFPRecord *raceKeep = [ix upsertRecordForRepo:@"r9_race" path:@"/src/stay.txt" isDir:NO parentUUID:raceSrc.uuid oid:@"oid_stay" mtime:10 size:5];
    SeafFPDecoration *raceFav = [SeafFPDecoration new];
    raceFav.itemIdentifier = raceFile.itemIdentifier;
    raceFav.favoriteRank = @11;
    [ix setDecoration:raceFav];
    long long raceStartSeq = [ix currentSeq];
    // 1. Source directory refresh finishes first: doc.txt and folder are gone from /src
    CHECK([ix applyListingOfRepo:@"r9_race" directoryPath:@"/src" entries:@[LE(@"stay.txt", NO, @"oid_stay", 5, 10)] requestStartSeq:raceStartSeq], @"source refresh applies");
    CHECK([ix recordForUUID:raceFile.uuid].deleted && [ix recordForUUID:raceDir.uuid].deleted && [ix recordForUUID:raceChild.uuid].deleted, @"source refresh tombstoned moved rows");
    // 2. Destination listing returns and confirms the moved entries
    NSArray *raceDstListing = @[
        LE(@"doc.txt", NO, @"oid_doc", 42, 10),
        LE(@"folder", YES, nil, -1, 10),
    ];
    NSArray *raceMoveNames = @[@"doc.txt", @"folder"];
    CHECK([ix moveRecordsOfRepo:@"r9_race" fromDirectory:@"/src" names:raceMoveNames toRepo:@"r9_race" toDirectory:@"/dst" destinationEntries:raceDstListing requestStartSeq:raceStartSeq], @"move succeeds even after source refresh tombstoned source records");
    SeafFPRecord *movedRaceFile = [ix recordForUUID:raceFile.uuid];
    SeafFPRecord *movedRaceDir = [ix recordForUUID:raceDir.uuid];
    SeafFPRecord *movedRaceChild = [ix recordForUUID:raceChild.uuid];
    CHECK(!movedRaceFile.deleted && eq(movedRaceFile.path, @"/dst/doc.txt"), @"moved file revived at /dst/doc.txt with original UUID");
    CHECK(!movedRaceDir.deleted && eq(movedRaceDir.path, @"/dst/folder"), @"moved dir revived at /dst/folder with original UUID");
    CHECK(!movedRaceChild.deleted && eq(movedRaceChild.path, @"/dst/folder/nested.txt"), @"moved dir subtree revived at /dst/folder/nested.txt with original UUID");
    CHECK([[ix decorationForItem:raceFile.itemIdentifier].favoriteRank isEqual:@11], @"favorite preserved on moved UUID");
    CHECK(![ix recordForUUID:raceKeep.uuid].deleted, @"remaining source file untouched");

    // Moving into a child directory (/src -> /src/sub) when /src refresh updates /src/sub's mtime first
    SeafFPRecord *subSrc = [ix upsertRecordForRepo:@"r9_subrace" path:@"/src" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    SeafFPRecord *subTargetDir = [ix upsertRecordForRepo:@"r9_subrace" path:@"/src/sub" isDir:YES parentUUID:subSrc.uuid oid:nil mtime:10 size:-1];
    SeafFPRecord *subMovFile = [ix upsertRecordForRepo:@"r9_subrace" path:@"/src/note.txt" isDir:NO parentUUID:subSrc.uuid oid:@"oid_note" mtime:10 size:20];
    long long subRaceStartSeq = [ix currentSeq];
    CHECK([ix applyListingOfRepo:@"r9_subrace" directoryPath:@"/src" entries:@[LE(@"sub", YES, nil, -1, 20)] requestStartSeq:subRaceStartSeq], @"parent dir refresh tombstoned note.txt and bumped sub mtime");
    CHECK([ix recordForUUID:subMovFile.uuid].deleted && [ix recordForUUID:subTargetDir.uuid].seq > subRaceStartSeq, @"note.txt tombstoned and sub seq bumped");
    CHECK([ix moveRecordsOfRepo:@"r9_subrace" fromDirectory:@"/src" names:@[@"note.txt"] toRepo:@"r9_subrace" toDirectory:@"/src/sub" destinationEntries:@[LE(@"note.txt", NO, @"oid_note", 20, 10)] requestStartSeq:subRaceStartSeq], @"move into subfolder succeeds after parent refresh");
    CHECK(![ix recordForUUID:subMovFile.uuid].deleted && eq([ix recordForUUID:subMovFile.uuid].path, @"/src/sub/note.txt"), @"note.txt revived at /src/sub/note.txt with original UUID");

    // Destination directory refresh completes before move confirmation: provisional row reconciled, original UUID + favorite preserved
    SeafFPRecord *dstRaceSrc = [ix upsertRecordForRepo:@"r9_dstrace" path:@"/src" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    [ix upsertRecordForRepo:@"r9_dstrace" path:@"/dst" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    SeafFPRecord *dstRaceFile = [ix upsertRecordForRepo:@"r9_dstrace" path:@"/src/fav.txt" isDir:NO parentUUID:dstRaceSrc.uuid oid:@"oid_fav" mtime:10 size:55];
    SeafFPDecoration *dstRaceDec = [SeafFPDecoration new];
    dstRaceDec.itemIdentifier = dstRaceFile.itemIdentifier;
    dstRaceDec.favoriteRank = @99;
    [ix setDecoration:dstRaceDec];
    long long dstRaceStartSeq = [ix currentSeq];
    NSArray *dstRaceEntries = @[LE(@"fav.txt", NO, @"oid_fav", 55, 10)];
    CHECK([ix applyListingOfRepo:@"r9_dstrace" directoryPath:@"/dst" entries:dstRaceEntries requestStartSeq:dstRaceStartSeq], @"destination dir refreshed before move confirmation");
    CHECK([ix moveRecordsOfRepo:@"r9_dstrace" fromDirectory:@"/src" names:@[@"fav.txt"] toRepo:@"r9_dstrace" toDirectory:@"/dst" destinationEntries:dstRaceEntries requestStartSeq:dstRaceStartSeq], @"move succeeds when destination refreshed first");
    SeafFPRecord *dstRaceFinal = [ix recordForRepo:@"r9_dstrace" path:@"/dst/fav.txt" includeDeleted:NO];
    CHECK(dstRaceFinal && eq(dstRaceFinal.uuid, dstRaceFile.uuid), @"moved file keeps original UUID when destination refreshed first");
    CHECK([[ix decorationForItem:dstRaceFinal.itemIdentifier].favoriteRank isEqual:@99], @"favorite preserved when destination refreshed first");

    // Sparse entries must not overwrite newer mtime/size or convert a live regular file into an ancestor directory
    SeafFPRecord *freshAuth = [ix upsertRecordForRepo:@"r_sparse_guard" path:@"/doc.txt" isDir:NO parentUUID:nil oid:@"oid_new" mtime:200 size:500];
    CHECK(![ix applySparseEntriesOfRepo:@"r_sparse_guard" entries:@[SE(@"/doc.txt", NO, nil, 100, 100)] allowRevive:YES], @"stale sparse entry does not downgrade newer live record");
    SeafFPRecord *afterStaleSparse = [ix recordForUUID:freshAuth.uuid];
    CHECK(afterStaleSparse.mtime == 200 && afterStaleSparse.size == 500 && eq(afterStaleSparse.oid, @"oid_new"), @"authoritative mtime/size/oid preserved");
    CHECK(![ix applySparseEntriesOfRepo:@"r_sparse_guard" entries:@[SE(@"/doc.txt/child.txt", NO, @"oid_c", 10, 300)] allowRevive:NO], @"sparse entry under live regular file rejected");
    CHECK(!([ix recordForUUID:freshAuth.uuid].isDir), @"/doc.txt remains a regular file");

    // T10 last-used date: decoration kept, row bumped, 60 s window
    SeafFPRecord *lu = [ix upsertRecordForRepo:@"r10" path:@"/n.txt" isDir:NO parentUUID:nil oid:@"o" mtime:1 size:3];
    SeafFPDecoration *luDec = [SeafFPDecoration new];
    luDec.itemIdentifier = lu.itemIdentifier;
    luDec.favoriteRank = @1;
    luDec.tagData = [@"tag" dataUsingEncoding:NSUTF8StringEncoding];
    [ix setDecoration:luDec];
    long long beforeLU = [ix currentSeq];
    NSDate *d1 = [NSDate dateWithTimeIntervalSince1970:1700000000];
    CHECK([ix noteLastUsedDate:d1 forRepo:@"r10" path:@"/n.txt" oid:nil size:-1 mtime:0 createIfMissing:YES], @"last used noted");
    SeafFPDecoration *luDec2 = [ix decorationForItem:lu.itemIdentifier];
    CHECK([luDec2.favoriteRank isEqual:@1] && [luDec2.tagData isEqualToData:luDec.tagData] && fabs([luDec2.lastUsedDate timeIntervalSinceDate:d1]) < 0.001, @"favorite and tag kept");
    BOOL reported = NO;
    for (SeafFPRecord *r in [ix recordsChangedSinceSeq:beforeLU]) reported = reported || eq(r.uuid, lu.uuid);
    CHECK(reported, @"row bumped so the change pass reports it");
    long long afterLU = [ix currentSeq];
    CHECK(![ix noteLastUsedDate:[d1 dateByAddingTimeInterval:10] forRepo:@"r10" path:@"/n.txt" oid:nil size:-1 mtime:0 createIfMissing:YES] && [ix currentSeq] == afterLU, @"within 60 s: nothing written");
    SeafFPRecord *luDead = [ix upsertRecordForRepo:@"r10" path:@"/dead.txt" isDir:NO parentUUID:nil oid:@"o" mtime:1 size:1];
    [ix markDeletedUUID:luDead.uuid];
    CHECK(![ix noteLastUsedDate:d1 forRepo:@"r10" path:@"/dead.txt" oid:nil size:-1 mtime:0 createIfMissing:YES] && [ix recordForUUID:luDead.uuid].deleted, @"never revives");

    // T11 content fill-in: only into rows without an oid
    CHECK(![ix noteLastUsedDate:nil forRepo:@"r10" path:@"/n.txt" oid:@"older" size:9 mtime:0 createIfMissing:NO] && eq([ix recordForUUID:lu.uuid].oid, @"o"), @"stored oid kept");
    [ix applySparseEntriesOfRepo:@"r10" entries:@[SE(@"/e.txt", NO, nil, -1, 1)] allowRevive:NO];
    CHECK([ix noteLastUsedDate:nil forRepo:@"r10" path:@"/e.txt" oid:@"oe" size:7 mtime:0 createIfMissing:NO], @"fill-in");
    SeafFPRecord *filled = [ix recordForRepo:@"r10" path:@"/e.txt" includeDeleted:NO];
    CHECK(eq(filled.oid, @"oe") && filled.size == 7, @"filled %@", filled);
    CHECK(![ix noteLastUsedDate:nil forRepo:@"r10" path:@"/unknown.txt" oid:@"ou" size:1 mtime:0 createIfMissing:NO] && [ix recordForRepo:@"r10" path:@"/unknown.txt" includeDeleted:YES] == nil, @"no create");
    CHECK([ix noteLastUsedDate:d1 forRepo:@"r10" path:@"/new/deep.txt" oid:@"od" size:4 mtime:5 createIfMissing:YES], @"created on open");
    SeafFPRecord *opened = [ix recordForRepo:@"r10" path:@"/new/deep.txt" includeDeleted:NO];
    CHECK(opened && eq(opened.oid, @"od") && [ix decorationForItem:opened.itemIdentifier].lastUsedDate != nil, @"opened %@", opened);

    // T12 two store instances on the same file never share a seq
    runActivityTests(ix);
    runReviewRegressionTests(ix);
    SeafFPStore *other = [[SeafFPStore alloc] initWithDomainIdentifier:ixDomain error:&err];
    // Activity state persists across store instances: replaying on `other` must also be a no-op
    NSArray *persistedReplay = @[
        AE(SeafFPActivityOpCreate, @"/a.txt", nil, NO, 100),
        AE(SeafFPActivityOpMove, @"/b.txt", @"/a.txt", NO, 200),
    ];
    CHECK(![other applyActivitiesOfRepo:@"a_replay" entries:persistedReplay], @"activity replay across store instances is a no-op");
    CHECK([other recordForRepo:@"a_replay" path:@"/a.txt" includeDeleted:YES] == nil, @"/a.txt stays absent across reopened store");
    long long beforeT12 = [ix currentSeq];
    for (int i = 0; i < 20; i++) {
        [ix upsertRecordForRepo:@"r12" path:[NSString stringWithFormat:@"/a%d", i] isDir:NO parentUUID:nil oid:@"o" mtime:1 size:1];
        [other applySparseEntriesOfRepo:@"r12" entries:@[SE([NSString stringWithFormat:@"/b%d", i], NO, @"o", 1, 1)] allowRevive:NO];
    }
    NSArray<SeafFPRecord *> *t12 = [ix recordsChangedSinceSeq:beforeT12];
    NSMutableSet *t12Seqs = [NSMutableSet set];
    for (SeafFPRecord *r in t12) [t12Seqs addObject:@(r.seq)];
    CHECK(t12.count == 40 && t12Seqs.count == 40, @"40 rows, 40 distinct seqs (%lu, %lu)", (unsigned long)t12.count, (unsigned long)t12Seqs.count);
    [other close];
    [ix close];
}

/// Schema 1 builds (4.0.9) left live rows under a tombstoned or flipped
/// parent. The upgrade retires them level by level and touches nothing else.
static void runLegacyOrphanMigrationTests(void)
{
    rawStoreSQL(@"legacy-orphans",
        "CREATE TABLE identity(uuid TEXT PRIMARY KEY, repo_id TEXT NOT NULL, path TEXT NOT NULL, is_dir INTEGER NOT NULL, name TEXT NOT NULL,"
        " parent_uuid TEXT, oid TEXT, mtime INTEGER, size INTEGER, deleted INTEGER NOT NULL DEFAULT 0, seq INTEGER NOT NULL, UNIQUE(repo_id,path));"
        "CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT);"
        // /A moved onto a stale live /B/A: 4.0.9 tombstoned only the stale directory.
        "INSERT INTO identity VALUES('B','r','/B',1,'B',NULL,'dB',100,0,0,1);"
        "INSERT INTO identity VALUES('stale','r','/B/A#moved-9',1,'A','B','old',100,0,1,10);"
        "INSERT INTO identity VALUES('x','r','/B/A/x.txt',0,'x.txt','stale','ox',100,1,0,3);"
        "INSERT INTO identity VALUES('sub','r','/B/A/sub',1,'sub','stale','ds',100,0,0,4);"
        "INSERT INTO identity VALUES('z','r','/B/A/sub/z.txt',0,'z.txt','sub','oz',100,1,0,5);"
        "INSERT INTO identity VALUES('A','r','/B/A',1,'A','B','dA',100,0,0,11);"
        "INSERT INTO identity VALUES('y','r','/B/A/y.txt',0,'y.txt','A','oy',100,1,0,12);"
        // A browsed folder replaced on the server by a file: 4.0.9 flipped the row in place.
        "INSERT INTO identity VALUES('D','r','/D',0,'D',NULL,'fD',200,5,0,13);"
        "INSERT INTO identity VALUES('c','r','/D/c.txt',0,'c.txt','D','oc',100,1,0,7);"
        "INSERT INTO identity VALUES('t','r','/top.txt',0,'top.txt',NULL,'ot',100,1,0,8);"
        "INSERT INTO identity VALUES('gone','r','/gone.txt',0,'gone.txt',NULL,'og',100,1,1,6);"
        "INSERT INTO identity VALUES('cross','r2','/q.txt',0,'q.txt','B','oq',100,1,0,2);"
        "INSERT INTO identity VALUES('lost','r','/L/l.txt',0,'l.txt','nowhere','ol',100,1,0,9);"
        "INSERT INTO meta VALUES('schema_version','1'),('seq','13');");
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"legacy-orphans" error:nil];
    CHECK(s && [[s metaValueForKey:@"schema_version"] isEqual:@"4"], @"upgraded");
    for (NSString *uuid in @[@"x", @"sub", @"z", @"c", @"cross", @"lost"]) {
        SeafFPRecord *r = [s recordForUUID:uuid];
        CHECK(r.deleted && r.tombReason == SeafFPTombReasonReplaced && r.seq > 13, @"%@ retired: %@", uuid, r);
    }
    NSDictionary<NSString *, NSNumber *> *kept = @{@"B": @1, @"A": @11, @"y": @12, @"D": @13, @"t": @8};
    for (NSString *uuid in kept) {
        SeafFPRecord *r = [s recordForUUID:uuid];
        CHECK(r && !r.deleted && r.seq == kept[uuid].longLongValue, @"%@ untouched: %@", uuid, r);
    }
    CHECK([s recordForUUID:@"gone"].seq == 6 && [s recordForUUID:@"stale"].seq == 10, @"tombstones untouched");
    CHECK([s recordsChangedSinceSeq:13].count == 6 && s.currentSeq == 19, @"one change per retired row: %lld", s.currentSeq);
    // The moved folder holds an x.txt on the server: its listing revives the row there.
    NSArray *listing = @[LE(@"x.txt", NO, @"ox", 1, 100), LE(@"y.txt", NO, @"oy", 1, 100)];
    CHECK([s applyListingOfRepo:@"r" directoryPath:@"/B/A" entries:listing requestStartSeq:s.currentSeq], @"listing of the moved folder");
    SeafFPRecord *x = [s recordForUUID:@"x"];
    CHECK(x && !x.deleted && eq(x.parentUUID, @"A") && eq(x.path, @"/B/A/x.txt"), @"revived under the moved folder: %@", x);
    [s close];

    // A schema 3 store (this branch opened the 4.0.9 data before the repair)
    // is repaired as well; from then on the store is not scanned on open.
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"schema-three-orphans" error:nil];
    SeafFPRecord *P = [s upsertRecordForRepo:@"r" path:@"/P" isDir:YES parentUUID:nil oid:@"dP" mtime:1 size:-1];
    SeafFPRecord *k = [s upsertRecordForRepo:@"r" path:@"/P/k.txt" isDir:NO parentUUID:P.uuid oid:@"ok" mtime:1 size:1];
    SeafFPRecord *Q = [s upsertRecordForRepo:@"r" path:@"/Q" isDir:YES parentUUID:nil oid:@"dQ" mtime:1 size:-1];
    SeafFPRecord *m = [s upsertRecordForRepo:@"r" path:@"/Q/m.txt" isDir:NO parentUUID:Q.uuid oid:@"om" mtime:1 size:1];
    [s close];
    rawStoreSQL(@"schema-three-orphans", [NSString stringWithFormat:@"UPDATE identity SET deleted = 1 WHERE uuid = '%@';"
                                          "UPDATE meta SET value = '3' WHERE key = 'schema_version'", P.uuid].UTF8String);
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"schema-three-orphans" error:nil];
    CHECK([[s metaValueForKey:@"schema_version"] isEqual:@"4"] && [s recordForUUID:k.uuid].deleted && ![s recordForUUID:Q.uuid].deleted,
          @"schema 3 orphan retired");
    [s close];
    rawStoreSQL(@"schema-three-orphans", [NSString stringWithFormat:@"UPDATE identity SET is_dir = 0 WHERE uuid = '%@'", Q.uuid].UTF8String);
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"schema-three-orphans" error:nil];
    CHECK(![s recordForUUID:m.uuid].deleted, @"a current store is not rescanned on open");
    [s close];
}

int main(void) {
    @autoreleasepool {
        gTestDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"seaf-fp-store-test-%@", [NSUUID UUID].UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:gTestDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *domain = @"acct-test";
        NSError *err = nil;
        SeafFPStore *store = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:&err];
        CHECK(store != nil, @"%@", err);
        CHECK([store currentSeq] == 0, @"seq=%lld", [store currentSeq]);
        CHECK([[store metaValueForKey:@"schema_version"] isEqualToString:@"4"], @"schema");

        // identity: create, idempotent upsert, keep-values semantics, change bumps seq
        SeafFPRecord *a = [store upsertRecordForRepo:@"repo1" path:@"/A" isDir:YES parentUUID:nil oid:@"d1" mtime:10 size:-1];
        CHECK(a.seq == 1 && a.isDir && eq(a.path, @"/A") && a.parentUUID == nil && eq(a.name, @"A"), @"%@", a);
        SeafFPRecord *a2 = [store upsertRecordForRepo:@"repo1" path:@"/A/" isDir:YES parentUUID:nil oid:@"d1" mtime:10 size:-1];
        CHECK(eq(a2.uuid, a.uuid) && a2.seq == 1, @"trailing slash should normalize, seq %lld", a2.seq);
        SeafFPRecord *a3 = [store upsertRecordForRepo:@"repo1" path:@"/A" isDir:YES parentUUID:nil oid:nil mtime:0 size:-1];
        CHECK(a3.seq == 1 && eq(a3.oid, @"d1") && a3.mtime == 10, @"nil/0/-1 keep values: %@", a3);
        SeafFPRecord *a4 = [store upsertRecordForRepo:@"repo1" path:@"/A" isDir:YES parentUUID:nil oid:@"d2" mtime:10 size:-1];
        CHECK(a4.seq == 2 && eq(a4.oid, @"d2"), @"oid change bumps seq: %@", a4);
        CHECK(eq([store recordForUUID:a.uuid].oid, @"d2"), @"persisted");

        SeafFPRecord *f = [store upsertRecordForRepo:@"repo1" path:@"/A/f.txt" isDir:NO parentUUID:a.uuid oid:@"o1" mtime:20 size:5];
        SeafFPRecord *g = [store upsertRecordForRepo:@"repo1" path:@"/A/sub" isDir:YES parentUUID:a.uuid oid:@"d3" mtime:21 size:-1];
        SeafFPRecord *h = [store upsertRecordForRepo:@"repo1" path:@"/A/sub/h.txt" isDir:NO parentUUID:g.uuid oid:@"o2" mtime:22 size:7];
        CHECK(f.seq == 3 && g.seq == 4 && h.seq == 5, @"seqs %lld %lld %lld", f.seq, g.seq, h.seq);
        CHECK(eq(f.parentItemIdentifier, [SeafFPIdentifier identifierForUUID:a.uuid]), @"parent id");
        CHECK(eq(a.parentItemIdentifier, @"r:repo1"), @"root child parent id %@", a.parentItemIdentifier);
        CHECK([store childRecordsOfRepo:@"repo1" parentUUID:a.uuid].count == 2, @"children of A");
        CHECK([store childRecordsOfRepo:@"repo1" parentUUID:nil].count == 1, @"children of root");
        CHECK([store recordsChangedSinceSeq:2].count == 3, @"changed since 2: %lu", (unsigned long)[store recordsChangedSinceSeq:2].count);
        CHECK([store subtreeRecordsOfUUID:a.uuid].count == 4, @"subtree of A incl. self: %lu", (unsigned long)[store subtreeRecordsOfUUID:a.uuid].count);

        // move: directory subtree follows, uuid stable
        SeafFPRecord *moved = [store moveRecordUUID:a.uuid toRepo:@"repo1" path:@"/B" parentUUID:nil];
        CHECK(eq(moved.path, @"/B") && eq(moved.uuid, a.uuid) && eq(moved.name, @"B"), @"%@", moved);
        CHECK(eq([store recordForUUID:h.uuid].path, @"/B/sub/h.txt"), @"subtree path: %@", [store recordForUUID:h.uuid].path);
        CHECK([store recordForRepo:@"repo1" path:@"/A/f.txt" includeDeleted:YES] == nil, @"old path gone");
        CHECK(eq([store recordForRepo:@"repo1" path:@"/B/f.txt" includeDeleted:NO].uuid, f.uuid), @"new path resolves");
        // parent_uuid of direct children is unchanged by a rename of the parent
        CHECK(eq([store recordForUUID:f.uuid].parentUUID, a.uuid), @"parent uuid kept");

        // move onto an occupied destination tombstones the occupant
        SeafFPRecord *x = [store upsertRecordForRepo:@"repo1" path:@"/B/x.txt" isDir:NO parentUUID:a.uuid oid:@"ox" mtime:1 size:1];
        SeafFPRecord *y = [store upsertRecordForRepo:@"repo1" path:@"/B/y.txt" isDir:NO parentUUID:a.uuid oid:@"oy" mtime:1 size:1];
        [store moveRecordUUID:x.uuid toRepo:@"repo1" path:@"/B/y.txt" parentUUID:a.uuid];
        CHECK([store recordForUUID:y.uuid].deleted, @"occupant tombstoned");
        CHECK(eq([store recordForRepo:@"repo1" path:@"/B/y.txt" includeDeleted:NO].uuid, x.uuid), @"mover owns the path");
        CHECK([store childRecordsOfRepo:@"repo1" parentUUID:a.uuid].count == 3, @"live children of B: f, sub, y(x)");

        // cross-library move
        [store moveRecordUUID:g.uuid toRepo:@"repo2" path:@"/sub" parentUUID:nil];
        SeafFPRecord *h2 = [store recordForUUID:h.uuid];
        CHECK(eq(h2.repoId, @"repo2") && eq(h2.path, @"/sub/h.txt"), @"cross-repo subtree: %@", h2);
        CHECK([store childRecordsOfRepo:@"repo2" parentUUID:nil].count == 1, @"repo2 root child");

        // tombstone subtree; other library untouched; revive by upsert
        long long beforeDelete = [store currentSeq];
        [store markDeletedUUID:a.uuid];
        CHECK([store recordForUUID:a.uuid].deleted && [store recordForUUID:f.uuid].deleted && [store recordForUUID:x.uuid].deleted, @"subtree deleted");
        CHECK(![store recordForUUID:h.uuid].deleted, @"repo2 record untouched");
        CHECK([store recordForRepo:@"repo1" path:@"/B" includeDeleted:NO] == nil, @"deleted hidden");
        CHECK([store recordForRepo:@"repo1" path:@"/B" includeDeleted:YES].deleted, @"deleted visible with flag");
        NSArray *changed = [store recordsChangedSinceSeq:beforeDelete];
        CHECK(changed.count == 3, @"tombstones are changes: %lu", (unsigned long)changed.count);
        for (SeafFPRecord *r in changed) CHECK(r.deleted, @"%@", r);
        SeafFPRecord *revived = [store upsertRecordForRepo:@"repo1" path:@"/B" isDir:YES parentUUID:nil oid:@"d9" mtime:30 size:-1];
        CHECK(!revived.deleted && eq(revived.uuid, a.uuid) && revived.seq > beforeDelete, @"revived %@", revived);
        CHECK([store childRecordsOfRepo:@"repo1" parentUUID:a.uuid].count == 0, @"children stay tombstoned until listed");

        // non-BMP characters in a directory name: subtree operations must still match
        SeafFPRecord *emo = [store upsertRecordForRepo:@"repo4" path:@"/\U0001F4C1work" isDir:YES parentUUID:nil oid:@"e1" mtime:1 size:-1];
        SeafFPRecord *emoChild = [store upsertRecordForRepo:@"repo4" path:@"/\U0001F4C1work/child.txt" isDir:NO parentUUID:emo.uuid oid:@"e2" mtime:1 size:1];
        CHECK([store subtreeRecordsOfUUID:emo.uuid].count == 2, @"emoji subtree count %lu", (unsigned long)[store subtreeRecordsOfUUID:emo.uuid].count);
        [store moveRecordUUID:emo.uuid toRepo:@"repo4" path:@"/\U0001F4C1moved" parentUUID:nil];
        CHECK(eq([store recordForUUID:emoChild.uuid].path, @"/\U0001F4C1moved/child.txt"), @"emoji child path after move: %@", [store recordForUUID:emoChild.uuid].path);
        [store markDeletedUUID:emo.uuid];
        CHECK([store recordForUUID:emoChild.uuid].deleted, @"emoji child tombstoned with parent");

        // performBatch: nested store calls run inline and share one transaction
        __block SeafFPRecord *b1 = nil, *b2 = nil;
        long long sb = [store currentSeq];
        [store performBatch:^{
            b1 = [store upsertRecordForRepo:@"repo5" path:@"/one" isDir:YES parentUUID:nil oid:@"x" mtime:1 size:-1];
            b2 = [store upsertRecordForRepo:@"repo5" path:@"/one/two.txt" isDir:NO parentUUID:b1.uuid oid:@"y" mtime:1 size:1];
            [store markDeletedUUID:b2.uuid];
            (void)[store recordForUUID:b1.uuid];
        }];
        CHECK(b1 && b2 && [store recordForUUID:b2.uuid].deleted && [store currentSeq] == sb + 3, @"batch: seq %lld vs %lld", [store currentSeq], sb + 3);
        // move onto a path held by a tombstoned child row must not be rejected by UNIQUE
        SeafFPRecord *m1 = [store upsertRecordForRepo:@"repo6" path:@"/src" isDir:YES parentUUID:nil oid:@"s" mtime:1 size:-1];
        SeafFPRecord *m1c = [store upsertRecordForRepo:@"repo6" path:@"/src/c.txt" isDir:NO parentUUID:m1.uuid oid:@"c" mtime:1 size:1];
        SeafFPRecord *dead = [store upsertRecordForRepo:@"repo6" path:@"/dst/c.txt" isDir:NO parentUUID:nil oid:@"old" mtime:1 size:1];
        [store markDeletedUUID:dead.uuid];
        [store moveRecordUUID:m1.uuid toRepo:@"repo6" path:@"/dst" parentUUID:nil];
        CHECK(eq([store recordForUUID:m1c.uuid].path, @"/dst/c.txt"), @"child moved over tombstone: %@", [store recordForUUID:m1c.uuid].path);
        CHECK(eq([store recordForRepo:@"repo6" path:@"/dst/c.txt" includeDeleted:NO].uuid, m1c.uuid), @"path now owned by the moved child");
        CHECK([store recordForUUID:dead.uuid].deleted && ![[store recordForUUID:dead.uuid].path isEqualToString:@"/dst/c.txt"], @"old occupant renamed away");
        // batch tombstones
        SeafFPRecord *t1 = [store upsertRecordForRepo:@"repo7" path:@"/t1" isDir:NO parentUUID:nil oid:@"a" mtime:1 size:1];
        SeafFPRecord *t2 = [store upsertRecordForRepo:@"repo7" path:@"/t2" isDir:NO parentUUID:nil oid:@"b" mtime:1 size:1];
        [store markDeletedUUIDs:@[t1.uuid, t2.uuid, @"nope"]];
        CHECK([store recordForUUID:t1.uuid].deleted && [store recordForUUID:t2.uuid].deleted, @"batch tombstone");
        CHECK([store enumeratedAtByContainer].count == 0, @"no containers yet");

        // ensureRecordChain
        SeafFPRecord *deep = [store ensureRecordChainForRepo:@"repo3" path:@"/p/q/r.txt" isDir:NO];
        SeafFPRecord *q = [store recordForRepo:@"repo3" path:@"/p/q" includeDeleted:NO];
        SeafFPRecord *p = [store recordForRepo:@"repo3" path:@"/p" includeDeleted:NO];
        CHECK(deep && q.isDir && p.isDir && eq(deep.parentUUID, q.uuid) && eq(q.parentUUID, p.uuid) && p.parentUUID == nil, @"chain");
        CHECK([store ensureRecordChainForRepo:@"repo3" path:@"/" isDir:YES] == nil, @"root has no record");
        CHECK(eq([store ensureRecordChainForRepo:@"repo3" path:@"p/q/r.txt" isDir:NO].uuid, deep.uuid), @"idempotent without leading slash");

        // containers
        [store setAnchor:@"a1" snapshot:@[@"i:1", @"i:2"] forContainer:@"r:repo1"];
        CHECK(eq([store anchorForContainer:@"r:repo1"], @"a1"), @"anchor");
        CHECK([store snapshotForContainer:@"r:repo1"].count == 2, @"snapshot");
        NSDate *at = [store enumeratedAtForContainer:@"r:repo1"];
        CHECK(at && fabs([at timeIntervalSinceNow]) < 5, @"enumerated_at");
        CHECK([store anchorForContainer:@"nope"] == nil && [store snapshotForContainer:@"nope"].count == 0 && [store enumeratedAtForContainer:@"nope"] == nil, @"unknown container");
        [store setAnchor:@"a2" snapshot:nil forContainer:@"r:repo1"];
        CHECK([store snapshotForContainer:@"r:repo1"].count == 0 && eq([store anchorForContainer:@"r:repo1"], @"a2"), @"nil snapshot clears");

        // paged live records (working set enumeration): uuid order, no tombstones, no gaps
        NSArray<SeafFPRecord *> *allLive = [store liveRecordsAfterUUID:nil limit:0];
        CHECK(allLive.count > 3, @"live records %lu", (unsigned long)allLive.count);
        for (SeafFPRecord *r in allLive) CHECK(!r.deleted, @"live only: %@", r);
        NSMutableArray<NSString *> *paged = [NSMutableArray array];
        NSString *after = nil;
        for (int guard = 0; guard < 100; guard++) {
            NSArray<SeafFPRecord *> *pg = [store liveRecordsAfterUUID:after limit:3];
            CHECK(pg.count <= 3, @"page size");
            for (SeafFPRecord *r in pg) {
                CHECK(after == nil || [r.uuid compare:after] == NSOrderedDescending, @"uuid order");
                [paged addObject:r.uuid];
                after = r.uuid;
            }
            if (pg.count < 3) break;
        }
        CHECK(paged.count == allLive.count && [NSSet setWithArray:paged].count == paged.count, @"paging covers all live records once: %lu vs %lu", (unsigned long)paged.count, (unsigned long)allLive.count);
        // limited change query keeps seq order and matches the unlimited one
        NSArray<SeafFPRecord *> *first2 = [store recordsChangedSinceSeq:0 limit:2];
        NSArray<SeafFPRecord *> *all0 = [store recordsChangedSinceSeq:0];
        CHECK(first2.count == 2 && first2[0].seq < first2[1].seq && eq(first2[0].uuid, all0[0].uuid) && eq(first2[1].uuid, all0[1].uuid), @"limited change query");
        CHECK([store recordsChangedSinceSeq:0 limit:0].count == all0.count, @"limit 0 means no limit");

        // decorations
        SeafFPDecoration *d = [SeafFPDecoration new];
        d.itemIdentifier = f.itemIdentifier;
        d.favoriteRank = @5;
        d.tagData = [@"tag" dataUsingEncoding:NSUTF8StringEncoding];
        d.lastUsedDate = [NSDate dateWithTimeIntervalSince1970:1234.5];
        [store setDecoration:d];
        SeafFPDecoration *d2 = [store decorationForItem:f.itemIdentifier];
        CHECK(d2 && [d2.favoriteRank isEqual:@5] && [d2.tagData isEqualToData:d.tagData] && fabs([d2.lastUsedDate timeIntervalSince1970] - 1234.5) < 0.001, @"decoration round trip");
        CHECK([store allDecorations].count == 1, @"all decorations");
        d.favoriteRank = nil; d.tagData = nil; d.lastUsedDate = nil;
        CHECK(d.isEmpty, @"empty");
        [store setDecoration:d];
        CHECK([store decorationForItem:f.itemIdentifier] == nil, @"empty decoration deletes row");

        // working set
        long long s0 = [store currentSeq];
        [store addWorkingSetItem:f.itemIdentifier reason:SeafFPWorkingSetReasonFavorite];
        CHECK([store workingSetReasonForItem:f.itemIdentifier] == SeafFPWorkingSetReasonFavorite, @"reason");
        CHECK([store currentSeq] == s0 + 1, @"add bumps seq once");
        CHECK([[store workingSetItemIdentifiersChangedSinceSeq:s0] isEqualToArray:@[f.itemIdentifier]], @"changed since");
        [store addWorkingSetItem:f.itemIdentifier reason:SeafFPWorkingSetReasonFavorite];
        CHECK([store currentSeq] == s0 + 1, @"same reason again is a no-op");
        [store addWorkingSetItem:f.itemIdentifier reason:SeafFPWorkingSetReasonTag];
        CHECK([store workingSetReasonForItem:f.itemIdentifier] == (SeafFPWorkingSetReasonFavorite | SeafFPWorkingSetReasonTag), @"merged");
        [store removeWorkingSetItem:f.itemIdentifier reason:SeafFPWorkingSetReasonFavorite];
        CHECK([store workingSetReasonForItem:f.itemIdentifier] == SeafFPWorkingSetReasonTag, @"bit cleared");
        [store removeWorkingSetItem:f.itemIdentifier];
        CHECK([store workingSetReasonForItem:f.itemIdentifier] == 0 && [store workingSetItemIdentifiers].count == 0, @"row removed");
        [store removeWorkingSetItem:@"i:missing" reason:SeafFPWorkingSetReasonTag];
        CHECK([store workingSetItemIdentifiers].count == 0, @"remove on missing row is harmless");

        // materialized bit never advances seq
        [store addWorkingSetItem:g.itemIdentifier reason:SeafFPWorkingSetReasonFavorite];
        long long s1 = [store currentSeq];
        [store replaceMaterializedItemIdentifiers:@[g.itemIdentifier, h.itemIdentifier]];
        CHECK([store currentSeq] == s1, @"materialized: seq unchanged (%lld vs %lld)", [store currentSeq], s1);
        CHECK([store workingSetReasonForItem:g.itemIdentifier] == (SeafFPWorkingSetReasonFavorite | SeafFPWorkingSetReasonMaterialized), @"g reason %ld", (long)[store workingSetReasonForItem:g.itemIdentifier]);
        CHECK([store workingSetReasonForItem:h.itemIdentifier] == SeafFPWorkingSetReasonMaterialized, @"h reason");
        CHECK([store workingSetItemIdentifiersChangedSinceSeq:s1].count == 0, @"no working set change reported for materialization");
        CHECK([store workingSetItemIdentifiers].count == 2, @"two rows");
        [store replaceMaterializedItemIdentifiers:@[]];
        CHECK([store workingSetReasonForItem:g.itemIdentifier] == SeafFPWorkingSetReasonFavorite, @"g keeps favorite");
        CHECK([store workingSetReasonForItem:h.itemIdentifier] == 0, @"h dropped");
        CHECK([store currentSeq] == s1, @"still no seq change");
        [store replaceMaterializedItemIdentifiers:@[g.itemIdentifier]];
        [store replaceMaterializedItemIdentifiers:@[g.itemIdentifier]];
        CHECK([store workingSetReasonForItem:g.itemIdentifier] == (SeafFPWorkingSetReasonFavorite | SeafFPWorkingSetReasonMaterialized) && [store currentSeq] == s1, @"idempotent");

        // meta
        [store setMetaValue:@"x" forKey:@"k"];
        CHECK(eq([store metaValueForKey:@"k"], @"x"), @"meta set");
        [store setMetaValue:nil forKey:@"k"];
        CHECK([store metaValueForKey:@"k"] == nil, @"meta removed");

        // isOpen flips on close and nested perform on the queue stays safe
        CHECK([store isOpen], @"open before close");


        // persistence across close/reopen, and removeStore
        long long finalSeq = [store currentSeq];
        [store close];
        SeafFPStore *store2 = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:&err];
        CHECK(store2 && [store2 currentSeq] == finalSeq, @"reopened seq %lld", [store2 currentSeq]);
        CHECK(eq([store2 recordForUUID:f.uuid].path, @"/B/f.txt"), @"records persisted");
        CHECK([store2 workingSetReasonForItem:g.itemIdentifier] != 0, @"working set persisted");
        [store2 close];
        CHECK(![store2 isOpen], @"closed store reports not open");
        CHECK([store2 recordForUUID:f.uuid] == nil && [store2 currentSeq] == 0, @"closed store answers empty, not crash");
        [SeafFPStore removeStoreForDomainIdentifier:domain];
        CHECK(![[NSFileManager defaultManager] fileExistsAtPath:[SeafFPIdentifier storeURLForDomainIdentifier:domain].path], @"store removed");

        // a file that is not a database at all is rebuilt
        NSString *badDomain = @"acct-notadb";
        NSString *badPath = [SeafFPIdentifier storeURLForDomainIdentifier:badDomain].path;
        [@"this is not a database" writeToFile:badPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        SeafFPStore *rebuilt = [[SeafFPStore alloc] initWithDomainIdentifier:badDomain error:&err];
        CHECK(rebuilt != nil, @"not-a-database rebuilt: %@", err);
        CHECK([rebuilt upsertRecordForRepo:@"r" path:@"/x" isDir:NO parentUUID:nil oid:@"o" mtime:1 size:1] != nil, @"rebuilt store is writable");
        [rebuilt close];

        // a failure that is not corruption must leave the store (and the
        // favorites in it) alone
        NSString *roDomain = @"acct-transient";
        NSString *roPath = [SeafFPIdentifier storeURLForDomainIdentifier:roDomain].path;
        SeafFPStore *ro = [[SeafFPStore alloc] initWithDomainIdentifier:roDomain error:&err];
        SeafFPRecord *keep = [ro upsertRecordForRepo:@"r" path:@"/keep.txt" isDir:NO parentUUID:nil oid:@"o1" mtime:5 size:9];
        SeafFPDecoration *fav = [SeafFPDecoration new];
        fav.itemIdentifier = keep.itemIdentifier;
        fav.favoriteRank = @7;
        [ro setDecoration:fav];
        long long keptSeq = [ro currentSeq];
        [ro close];
        // Put a meta table with the wrong columns in the way: reads and writes
        // of it fail with SQLITE_ERROR, which says nothing about the file being
        // unusable. The identity rows and decorations must survive it.
        sqlite3 *raw = NULL;
        sqlite3_open(roPath.fileSystemRepresentation, &raw);
        sqlite3_exec(raw, "ALTER TABLE meta RENAME TO meta_aside", NULL, NULL, NULL);
        sqlite3_exec(raw, "CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT)", NULL, NULL, NULL);
        sqlite3_close(raw);
        SeafFPStore *denied = [[SeafFPStore alloc] initWithDomainIdentifier:roDomain error:&err];
        CHECK(denied == nil, @"a store that cannot be prepared must not open");
        CHECK([[NSFileManager defaultManager] fileExistsAtPath:roPath], @"store kept after a failure that is not corruption");
        sqlite3_open(roPath.fileSystemRepresentation, &raw);
        sqlite3_exec(raw, "DROP TABLE meta", NULL, NULL, NULL);
        sqlite3_exec(raw, "ALTER TABLE meta_aside RENAME TO meta", NULL, NULL, NULL);
        sqlite3_close(raw);
        SeafFPStore *back = [[SeafFPStore alloc] initWithDomainIdentifier:roDomain error:&err];
        CHECK(back != nil, @"reopens once the failure is gone: %@", err);
        CHECK(eq([back recordForUUID:keep.uuid].path, @"/keep.txt"), @"identity rows survived");
        CHECK([[back decorationForItem:keep.itemIdentifier].favoriteRank isEqual:@7], @"favorite survived");
        CHECK([back currentSeq] == keptSeq, @"seq untouched (%lld)", [back currentSeq]);
        [back close];

        // a store that lost its version stamp seeds the counter from the rows,
        // it does not restart at 0 below seq values the rows already carry
        sqlite3_open(roPath.fileSystemRepresentation, &raw);
        sqlite3_exec(raw, "DELETE FROM meta WHERE key = 'schema_version'", NULL, NULL, NULL);
        sqlite3_exec(raw, "DELETE FROM meta WHERE key = 'seq'", NULL, NULL, NULL);
        sqlite3_close(raw);
        SeafFPStore *reseeded = [[SeafFPStore alloc] initWithDomainIdentifier:roDomain error:&err];
        CHECK(reseeded != nil, @"reopens without a version stamp: %@", err);
        CHECK([reseeded currentSeq] >= keep.seq, @"seq reseeded to %lld (rows go up to %lld)", [reseeded currentSeq], keep.seq);
        SeafFPRecord *afterReseed = [reseeded upsertRecordForRepo:@"r" path:@"/after.txt" isDir:NO parentUUID:nil oid:@"o2" mtime:6 size:3];
        CHECK(afterReseed.seq > keep.seq, @"new rows get a higher seq (%lld > %lld)", afterReseed.seq, keep.seq);
        [reseeded close];

        runIndexingTests();
        runPublicationTests();
        runStatementFailureTests();
        runDirectoryCheckTests();
        runRenameHintTests();
        runLateRenameAndBatchTests();
        runConfirmedPlacementTests();
        runPendingMoveRecoveryTests();
        runMoveJournalTerminalStateTests();
        runReviewFollowupTests();
        runLegacyOrphanMigrationTests();


        // identifier helpers
        CHECK(eq([SeafFPIdentifier normalizedPath:nil], @"/"), @"nil path");
        CHECK(eq([SeafFPIdentifier normalizedPath:@"a//b/"], @"/a/b"), @"%@", [SeafFPIdentifier normalizedPath:@"a//b/"]);
        CHECK(eq([SeafFPIdentifier normalizedPath:@"/"], @"/"), @"root");
        NSString *nfd = [@"é" decomposedStringWithCanonicalMapping];
        CHECK(eq([SeafFPIdentifier normalizedPath:nfd], @"/é"), @"NFC");
        CHECK([SeafFPIdentifier kindOfIdentifier:@"r:"] == SeafFPIdentifierKindUnknown, @"bare prefix");
        CHECK([SeafFPIdentifier kindOfIdentifier:@"i:abc"] == SeafFPIdentifierKindItem, @"item");
        CHECK([SeafFPIdentifier kindOfIdentifier:@"NSFileProviderRootContainerItemIdentifier"] == SeafFPIdentifierKindRoot, @"root const value");
        CHECK([SeafFPIdentifier kindOfIdentifier:@"NSFileProviderWorkingSetContainerItemIdentifier"] == SeafFPIdentifierKindWorkingSet, @"working set const value");
        NSString *dom1 = [SeafFPIdentifier domainIdentifierForAddress:@"https://x.example/" username:@"u"];
        NSString *dom2 = [SeafFPIdentifier domainIdentifierForAddress:@"https://x.example" username:@"u"];
        NSString *dom3 = [SeafFPIdentifier domainIdentifierForAddress:@"https://X.example" username:@"u"];
        CHECK(eq(dom1, dom2) && !eq(dom1, dom3) && [dom1 hasPrefix:@"acct-"] && dom1.length == 21, @"%@ %@ %@", dom1, dom2, dom3);
        CHECK([SeafFPIdentifier newUUID].length == 32 && ![[SeafFPIdentifier newUUID] containsString:@"-"], @"uuid");

        // item version components: 128-byte limit, short ones byte-identical
        NSString *shortMeta = @"1700000000|1234|report.pdf";
        CHECK([[SeafFPIdentifier versionComponentData:shortMeta] isEqualToData:[shortMeta dataUsingEncoding:NSUTF8StringEncoding]], @"short component unchanged");
        NSString *exact = [@"" stringByPaddingToLength:128 withString:@"x" startingAtIndex:0];
        CHECK([SeafFPIdentifier versionComponentData:exact].length == 128, @"128 bytes kept");
        NSString *longName = [@"1700000000|1234|" stringByAppendingString:[@"" stringByPaddingToLength:60 withString:@"文" startingAtIndex:0]];
        CHECK([longName dataUsingEncoding:NSUTF8StringEncoding].length > 128, @"fixture exceeds the limit");
        NSData *digested = [SeafFPIdentifier versionComponentData:longName];
        CHECK(digested.length == 40 && [digested isEqualToData:[[SeafFPIdentifier sha1Hex:longName] dataUsingEncoding:NSUTF8StringEncoding]], @"long component digested (%lu)", (unsigned long)digested.length);
        CHECK(![digested isEqualToData:[SeafFPIdentifier versionComponentData:[longName stringByAppendingString:@"2"]]], @"digest still distinguishes versions");

        [[NSFileManager defaultManager] removeItemAtPath:gTestDir error:nil];
        NSLog(@"RESULT: %d passed, %d failed", passes, failures);
        return failures == 0 ? 0 : 1;
    }
}
