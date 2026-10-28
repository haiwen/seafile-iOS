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

static void runActivityTests(SeafFPStore *ix)
{
    // T14 create: unknown paths only, never below or onto a tombstone
    SeafFPRecord *known = [ix upsertRecordForRepo:@"a1" path:@"/known.txt" isDir:NO parentUUID:nil oid:@"ok" mtime:500 size:9];
    SeafFPRecord *deadDir = [ix upsertRecordForRepo:@"a1" path:@"/dead" isDir:YES parentUUID:nil oid:nil mtime:1 size:-1];
    SeafFPRecord *deadFile = [ix upsertRecordForRepo:@"a1" path:@"/dead.txt" isDir:NO parentUUID:nil oid:@"od" mtime:1 size:1];
    [ix markDeletedUUIDs:@[deadDir.uuid, deadFile.uuid]];
    NSArray *creates = @[AE(SeafFPActivityOpCreate, @"/web/new.docx", nil, NO, 1000),
                         AE(SeafFPActivityOpCreate, @"/known.txt", nil, NO, 1000),
                         AE(SeafFPActivityOpCreate, @"/dead/x.txt", nil, NO, 1000),
                         AE(SeafFPActivityOpCreate, @"/dead.txt", nil, NO, 1000)];
    CHECK([ix applyActivitiesOfRepo:@"a1" entries:creates], @"creates applied");
    SeafFPRecord *webNew = [ix recordForRepo:@"a1" path:@"/web/new.docx" includeDeleted:NO];
    CHECK(webNew && webNew.mtime == 1000 && webNew.oid == nil && [ix recordForRepo:@"a1" path:@"/web" includeDeleted:NO].isDir, @"unknown path inserted with its chain");
    SeafFPRecord *known2 = [ix recordForUUID:known.uuid];
    CHECK(known2.seq == known.seq && known2.mtime == 500, @"known row untouched");
    CHECK([ix recordForRepo:@"a1" path:@"/dead/x.txt" includeDeleted:YES] == nil && [ix recordForUUID:deadDir.uuid].deleted, @"nothing below a tombstone");
    CHECK([ix recordForUUID:deadFile.uuid].deleted, @"tombstone not revived by a create");

    // T15 delete: only when the stored row is not newer than the event
    SeafFPRecord *oldFile = [ix upsertRecordForRepo:@"a1" path:@"/old.txt" isDir:NO parentUUID:nil oid:@"o" mtime:900 size:1];
    SeafFPRecord *newFile = [ix upsertRecordForRepo:@"a1" path:@"/recreated.txt" isDir:NO parentUUID:nil oid:@"o" mtime:2000 size:1];
    SeafFPRecord *keepDir = [ix upsertRecordForRepo:@"a1" path:@"/keepdir" isDir:YES parentUUID:nil oid:nil mtime:100 size:-1];
    [ix upsertRecordForRepo:@"a1" path:@"/keepdir/fresh.txt" isDir:NO parentUUID:keepDir.uuid oid:@"o" mtime:3000 size:1];
    SeafFPRecord *goneDir = [ix upsertRecordForRepo:@"a1" path:@"/gonedir" isDir:YES parentUUID:nil oid:nil mtime:100 size:-1];
    SeafFPRecord *goneChild = [ix upsertRecordForRepo:@"a1" path:@"/gonedir/c.txt" isDir:NO parentUUID:goneDir.uuid oid:@"o" mtime:200 size:1];
    NSArray *deletes = @[AE(SeafFPActivityOpDelete, @"/old.txt", nil, NO, 1000),
                         AE(SeafFPActivityOpDelete, @"/recreated.txt", nil, NO, 1000),
                         AE(SeafFPActivityOpDelete, @"/keepdir", nil, YES, 1000),
                         AE(SeafFPActivityOpDelete, @"/gonedir", nil, YES, 1000)];
    CHECK([ix applyActivitiesOfRepo:@"a1" entries:deletes], @"deletes applied");
    CHECK([ix recordForUUID:oldFile.uuid].deleted, @"older row deleted");
    CHECK(![ix recordForUUID:newFile.uuid].deleted, @"row newer than the event kept");
    CHECK(![ix recordForUUID:keepDir.uuid].deleted, @"directory with a newer live row kept");
    CHECK([ix recordForUUID:goneDir.uuid].deleted && [ix recordForUUID:goneChild.uuid].deleted, @"directory subtree deleted");

    // T16 move / rename keep the uuid; guarded like deletes
    SeafFPRecord *mv = [ix upsertRecordForRepo:@"a1" path:@"/m/a.txt" isDir:NO parentUUID:nil oid:@"o" mtime:100 size:1];
    SeafFPRecord *mvNewer = [ix upsertRecordForRepo:@"a1" path:@"/m/b.txt" isDir:NO parentUUID:nil oid:@"o" mtime:5000 size:1];
    SeafFPRecord *mvBlocked = [ix upsertRecordForRepo:@"a1" path:@"/m/c.txt" isDir:NO parentUUID:nil oid:@"o" mtime:100 size:1];
    SeafFPRecord *taken = [ix upsertRecordForRepo:@"a1" path:@"/m/taken.txt" isDir:NO parentUUID:nil oid:@"o" mtime:100 size:1];
    SeafFPRecord *mvToDead = [ix upsertRecordForRepo:@"a1" path:@"/m/d.txt" isDir:NO parentUUID:nil oid:@"o" mtime:100 size:1];
    SeafFPRecord *mvDirWithNewer = [ix upsertRecordForRepo:@"a1" path:@"/m/dir_newer" isDir:YES parentUUID:nil oid:nil mtime:100 size:-1];
    [ix upsertRecordForRepo:@"a1" path:@"/m/dir_newer/child.txt" isDir:NO parentUUID:mvDirWithNewer.uuid oid:@"o" mtime:4000 size:1];
    NSArray *moves = @[AE(SeafFPActivityOpMove, @"/n/a-renamed.txt", @"/m/a.txt", NO, 1000),
                       AE(SeafFPActivityOpMove, @"/n/b.txt", @"/m/b.txt", NO, 1000),
                       AE(SeafFPActivityOpMove, @"/m/taken.txt", @"/m/c.txt", NO, 1000),
                       AE(SeafFPActivityOpMove, @"/dead.txt", @"/m/d.txt", NO, 1000),
                       AE(SeafFPActivityOpMove, @"/n/dir_newer", @"/m/dir_newer", YES, 1000),
                       AE(SeafFPActivityOpMove, @"/n/unknown.txt", @"/m/never-seen.txt", NO, 1000),
                       AE(SeafFPActivityOpCreate, @"/n/tmp.txt", nil, NO, 1100),
                       AE(SeafFPActivityOpMove, @"/n/final.txt", @"/n/tmp.txt", NO, 1200)];
    CHECK([ix applyActivitiesOfRepo:@"a1" entries:moves], @"moves applied");
    SeafFPRecord *nDir = [ix recordForRepo:@"a1" path:@"/n" includeDeleted:NO];
    CHECK(eq([ix recordForUUID:mv.uuid].path, @"/n/a-renamed.txt") && eq([ix recordForUUID:mv.uuid].parentUUID, nDir.uuid), @"moved with its uuid");
    CHECK(eq([ix recordForUUID:mvNewer.uuid].path, @"/m/b.txt"), @"newer row at the old path not moved");
    CHECK(eq([ix recordForUUID:mvBlocked.uuid].path, @"/m/c.txt") && eq([ix recordForUUID:taken.uuid].path, @"/m/taken.txt"), @"taken destination skipped");
    CHECK(eq([ix recordForUUID:mvToDead.uuid].path, @"/m/d.txt") && [ix recordForUUID:deadFile.uuid].deleted, @"tombstoned destination not revived by move");
    CHECK(eq([ix recordForUUID:mvDirWithNewer.uuid].path, @"/m/dir_newer"), @"directory with newer live child not moved");
    CHECK([ix recordForRepo:@"a1" path:@"/n/unknown.txt" includeDeleted:NO] != nil, @"move of an unknown row is a create");
    CHECK([ix recordForRepo:@"a1" path:@"/n/final.txt" includeDeleted:NO] != nil && [ix recordForRepo:@"a1" path:@"/n/tmp.txt" includeDeleted:YES] == nil, @"entries replay in order");

    // T17 (Issue 2): replaying activity pages is idempotent and does not recreate vanished paths
    long long beforeReplay = [ix currentSeq];
    CHECK(![ix applyActivitiesOfRepo:@"a1" entries:moves], @"replaying the same activity page is a no-op");
    CHECK([ix currentSeq] == beforeReplay, @"seq unchanged on activity replay");
    CHECK([ix recordForRepo:@"a1" path:@"/n/tmp.txt" includeDeleted:YES] == nil, @"vanished path /n/tmp.txt not recreated on replay");
    CHECK([ix recordForRepo:@"a1" path:@"/n/final.txt" includeDeleted:NO] != nil, @"/n/final.txt still present");

    // Replaying create + rename on a fresh repo multiple times
    NSArray *createAndRename = @[
        AE(SeafFPActivityOpCreate, @"/a.txt", nil, NO, 100),
        AE(SeafFPActivityOpMove, @"/b.txt", @"/a.txt", NO, 200),
    ];
    CHECK([ix applyActivitiesOfRepo:@"a_replay" entries:createAndRename], @"first replay of create + rename applies");
    CHECK([ix recordForRepo:@"a_replay" path:@"/a.txt" includeDeleted:YES] == nil, @"/a.txt not left behind");
    CHECK([ix recordForRepo:@"a_replay" path:@"/b.txt" includeDeleted:NO] != nil, @"/b.txt exists");
    CHECK(![ix applyActivitiesOfRepo:@"a_replay" entries:createAndRename], @"second replay of create + rename is a no-op");
    CHECK([ix recordForRepo:@"a_replay" path:@"/a.txt" includeDeleted:YES] == nil, @"/a.txt not recreated on second replay");
    CHECK([ix recordForRepo:@"a_replay" path:@"/b.txt" includeDeleted:NO] != nil, @"/b.txt still exists");

    // Overlapping page with a new event and older unseen event on the vanished path
    NSArray *overlappingPage = @[
        AE(SeafFPActivityOpCreate, @"/a.txt", nil, NO, 100),
        AE(SeafFPActivityOpCreate, @"/a.txt", nil, NO, 150),   // unseen edit before the move at t=200
        AE(SeafFPActivityOpMove, @"/b.txt", @"/a.txt", NO, 200),
        AE(SeafFPActivityOpCreate, @"/c.txt", nil, NO, 300),
    ];
    CHECK([ix applyActivitiesOfRepo:@"a_replay" entries:overlappingPage], @"overlapping page applies new event");
    CHECK([ix recordForRepo:@"a_replay" path:@"/a.txt" includeDeleted:YES] == nil, @"older edit before move does not resurrect /a.txt");
    CHECK([ix recordForRepo:@"a_replay" path:@"/c.txt" includeDeleted:NO] != nil, @"new event /c.txt applied");

    // Chained moves and create + move + delete
    NSArray *chainedOps = @[
        AE(SeafFPActivityOpMove, @"/step2.txt", @"/step1.txt", NO, 100),
        AE(SeafFPActivityOpMove, @"/step3.txt", @"/step2.txt", NO, 200),
        AE(SeafFPActivityOpCreate, @"/ephemeral.txt", nil, NO, 100),
        AE(SeafFPActivityOpMove, @"/ephemeral2.txt", @"/ephemeral.txt", NO, 200),
        AE(SeafFPActivityOpDelete, @"/ephemeral2.txt", nil, NO, 300),
    ];
    CHECK([ix applyActivitiesOfRepo:@"a_chain" entries:chainedOps], @"chained ops applied");
    CHECK([ix recordForRepo:@"a_chain" path:@"/step1.txt" includeDeleted:YES] == nil, @"/step1.txt not created");
    CHECK([ix recordForRepo:@"a_chain" path:@"/step2.txt" includeDeleted:YES] == nil, @"/step2.txt not left behind");
    CHECK([ix recordForRepo:@"a_chain" path:@"/step3.txt" includeDeleted:NO] != nil, @"/step3.txt exists");
    CHECK([ix recordForRepo:@"a_chain" path:@"/ephemeral.txt" includeDeleted:YES] == nil, @"/ephemeral.txt not created");
    CHECK([ix recordForRepo:@"a_chain" path:@"/ephemeral2.txt" includeDeleted:YES] == nil, @"/ephemeral2.txt not left behind");
    CHECK(![ix applyActivitiesOfRepo:@"a_chain" entries:chainedOps], @"second replay of chained ops is a no-op");
    CHECK([ix recordForRepo:@"a_chain" path:@"/step2.txt" includeDeleted:YES] == nil, @"/step2.txt still absent");

    // Directory rename in activity log: old directory structure must not reappear on replay
    NSArray *dirOps = @[
        AE(SeafFPActivityOpCreate, @"/old_dir/inner.txt", nil, NO, 100),
        AE(SeafFPActivityOpMove, @"/new_dir", @"/old_dir", YES, 200),
    ];
    CHECK([ix applyActivitiesOfRepo:@"a_dir" entries:dirOps], @"dir ops applied");
    CHECK([ix recordForRepo:@"a_dir" path:@"/old_dir" includeDeleted:YES] == nil, @"/old_dir gone");
    CHECK([ix recordForRepo:@"a_dir" path:@"/old_dir/inner.txt" includeDeleted:YES] == nil, @"/old_dir/inner.txt gone");
    CHECK([ix recordForRepo:@"a_dir" path:@"/new_dir/inner.txt" includeDeleted:NO] != nil, @"/new_dir/inner.txt exists");
    CHECK(![ix applyActivitiesOfRepo:@"a_dir" entries:dirOps], @"dir ops second replay is a no-op");
    CHECK(![ix applyActivitiesOfRepo:@"a_dir" entries:@[AE(SeafFPActivityOpCreate, @"/old_dir/other.txt", nil, NO, 150)]], @"older file under renamed dir ignored");
    CHECK([ix recordForRepo:@"a_dir" path:@"/old_dir" includeDeleted:YES] == nil, @"/old_dir still gone");

    // Historical delete must not delete a file that moved into that path after the delete event
    SeafFPRecord *oldContent = [ix upsertRecordForRepo:@"a_hist" path:@"/b.txt" isDir:NO parentUUID:nil oid:@"o_b" mtime:100 size:10];
    NSArray *histEvents = @[
        AE(SeafFPActivityOpDelete, @"/a.txt", nil, NO, 500),
        AE(SeafFPActivityOpMove, @"/a.txt", @"/b.txt", NO, 600),
    ];
    CHECK([ix applyActivitiesOfRepo:@"a_hist" entries:histEvents], @"hist move applied");
    SeafFPRecord *afterHist = [ix recordForRepo:@"a_hist" path:@"/a.txt" includeDeleted:NO];
    CHECK(afterHist && eq(afterHist.uuid, oldContent.uuid) && !afterHist.deleted, @"moved file at /a.txt survived earlier delete at t=500");

    // Local move followed by activity replay > 512 entries must not resurrect old path or get deleted by historical delete
    SeafFPRecord *localMoved = [ix upsertRecordForRepo:@"a_local_mv" path:@"/orig.txt" isDir:NO parentUUID:nil oid:@"o_lm" mtime:100 size:10];
    [ix moveRecordUUID:localMoved.uuid toRepo:@"a_local_mv" path:@"/target.txt" parentUUID:nil];
    NSMutableArray *largeReplay = [NSMutableArray array];
    [largeReplay addObject:AE(SeafFPActivityOpCreate, @"/orig.txt", nil, NO, 100)];
    [largeReplay addObject:AE(SeafFPActivityOpDelete, @"/target.txt", nil, NO, 200)];
    [largeReplay addObject:AE(SeafFPActivityOpMove, @"/target.txt", @"/orig.txt", NO, 300)];
    for (int i = 0; i < 600; i++) {
        [largeReplay addObject:AE(SeafFPActivityOpCreate, [NSString stringWithFormat:@"/bulk_%d.txt", i], nil, NO, 400 + i)];
    }
    [ix applyActivitiesOfRepo:@"a_local_mv" entries:largeReplay];
    [ix applyActivitiesOfRepo:@"a_local_mv" entries:largeReplay];
    CHECK([ix recordForRepo:@"a_local_mv" path:@"/orig.txt" includeDeleted:YES] == nil, @"departed local move path not resurrected after >512 activity entries");
    CHECK(![ix recordForUUID:localMoved.uuid].deleted && eq([ix recordForUUID:localMoved.uuid].path, @"/target.txt"), @"locally moved record survived historical delete at destination");
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

    // T3 a direct child written after the request rejects the listing; the root is not affected
    S = [ix currentSeq];
    [ix upsertRecordForRepo:@"r1" path:@"/A/B/C/new.txt" isDir:NO parentUUID:cRec.uuid oid:@"on" mtime:5 size:1];
    CHECK([ix applyListingOfRepo:@"r1" directoryPath:@"/" entries:@[LE(@"A", YES, @"dA", -1, 1)] requestStartSeq:S], @"root listing applies despite a deep change");
    CHECK(![ix applyListingOfRepo:@"r1" directoryPath:@"/A/B/C" entries:listC requestStartSeq:S], @"stale listing of C rejected");
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

int main(void) {
    @autoreleasepool {
        gTestDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"seaf-fp-store-test-%@", [NSUUID UUID].UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:gTestDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *domain = @"acct-test";
        NSError *err = nil;
        SeafFPStore *store = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:&err];
        CHECK(store != nil, @"%@", err);
        CHECK([store currentSeq] == 0, @"seq=%lld", [store currentSeq]);
        CHECK([[store metaValueForKey:@"schema_version"] isEqualToString:@"1"], @"schema");

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
