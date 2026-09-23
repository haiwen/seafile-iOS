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
