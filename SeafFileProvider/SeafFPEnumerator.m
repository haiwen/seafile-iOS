//
//  SeafFPEnumerator.m
//  SeafFileProvider
//

#import "SeafFPEnumerator.h"
#import "SeafFPExtension.h"
#import "SeafFPIdentifier.h"
#import "SeafFPItem.h"
#import "SeafFPStore.h"
#import "SeafFPErrors.h"
#import "SeafConnection.h"
#import "SeafRepos.h"
#import "SeafDir.h"
#import "SeafFile.h"
#import "Debug.h"

// A working set change enumeration re-checks the directories its members live
// in, a few at a time, least recently checked first (design §8.2). Listings
// signal the working set, so a pass may follow every browse: a directory
// listed within the re-check interval is left alone by the pass.
static const NSUInteger kSeafFPWorkingSetDirectoryChecksPerPass = 5;
static const NSTimeInterval kSeafFPWorkingSetCheckBudget = 20.0;
static const NSTimeInterval kSeafFPWorkingSetRecheckInterval = 120.0;

// The working set is everything the system has learnt through this extension
// (design §7.4): a full enumeration hands out the library list and then the
// identity table in uuid order, this many rows per page; a change enumeration
// reports at most this many identity rows per pass and asks for another pass.
static const NSInteger kSeafFPWorkingSetPageSize = 200;
static const NSInteger kSeafFPWorkingSetChangesPerPass = 500;
static NSString * const kSeafFPWorkingSetPagePrefix = @"u:";
// Working set anchors are "<generation>:<seq>". An anchor of an earlier
// generation (a bare seq, before the working set covered every known item)
// expires once, which makes the system rescan the full working set.
static NSString * const kSeafFPWorkingSetAnchorPrefix = @"5:";

static NSData *SeafFPAnchorData(NSString *anchor)
{
    return [(anchor ?: @"0") dataUsingEncoding:NSUTF8StringEncoding];
}

static NSString *SeafFPAnchorString(NSData *anchor)
{
    if (anchor.length == 0) return nil;
    return [[NSString alloc] initWithData:anchor encoding:NSUTF8StringEncoding];
}

static BOOL SeafFPIsDecimal(NSString *string)
{
    if (string.length == 0) return NO;
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [string rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

/// The seq of a working set anchor of the current generation; -1 for any other.
static long long SeafFPWorkingSetSeqFromAnchor(NSString *anchor)
{
    if (![anchor hasPrefix:kSeafFPWorkingSetAnchorPrefix]) return -1;
    NSString *digits = [anchor substringFromIndex:kSeafFPWorkingSetAnchorPrefix.length];
    return SeafFPIsDecimal(digits) ? digits.longLongValue : -1;
}

/// The libraries Files may see: unlocked, one per id (the SDK lists a library
/// once per type: mine / shared / group).
static NSArray<SeafRepo *> *SeafFPVisibleRepos(SeafRepos *repos)
{
    if (repos && repos.items.count == 0) {
        [repos loadCache];
    }
    NSMutableArray<SeafRepo *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (SeafBase *obj in repos.items) {
        if (![obj isKindOfClass:[SeafRepo class]]) continue;
        SeafRepo *repo = (SeafRepo *)obj;
        if (repo.passwordRequired) continue;
        if (repo.repoId.length == 0 || [seen containsObject:repo.repoId]) continue;
        [seen addObject:repo.repoId];
        [result addObject:repo];
    }
    return result;
}

static NSUInteger SeafFPPathDepth(NSString *path)
{
    NSUInteger depth = 0;
    NSUInteger length = path.length;
    for (NSUInteger i = 0; i < length; i++) {
        if ([path characterAtIndex:i] == '/') depth++;
    }
    return depth;
}

static NSComparisonResult SeafFPCompareRecordsParentFirst(SeafFPRecord *a, SeafFPRecord *b)
{
    NSUInteger depthA = SeafFPPathDepth(a.path);
    NSUInteger depthB = SeafFPPathDepth(b.path);
    if (depthA != depthB) return depthA < depthB ? NSOrderedAscending : NSOrderedDescending;
    if (a.isDir != b.isDir) return a.isDir ? NSOrderedAscending : NSOrderedDescending;
    if (a.seq != b.seq) return a.seq < b.seq ? NSOrderedAscending : NSOrderedDescending;
    NSComparisonResult byRepo = [a.repoId compare:b.repoId];
    if (byRepo != NSOrderedSame) return byRepo;
    NSComparisonResult byPath = [a.path compare:b.path];
    return byPath != NSOrderedSame ? byPath : [a.uuid compare:b.uuid];
}

/// Sorts identity rows parent-before-child (by path depth, directories before
/// files at the same depth, then seq) so working set batches never present a
/// child before its parent directory within the same pass.
static NSArray<SeafFPRecord *> *SeafFPSortRecordsParentFirst(NSArray<SeafFPRecord *> *records)
{
    if (records.count <= 1) return records;
    return [records sortedArrayUsingComparator:^NSComparisonResult(SeafFPRecord *a, SeafFPRecord *b) {
        return SeafFPCompareRecordsParentFirst(a, b);
    }];
}

static NSString * _Nullable SeafFPWorkingSetPageTokenForRecord(SeafFPRecord *record)
{
    if (!record || record.uuid.length == 0) return nil;
    return [NSString stringWithFormat:@"%@%@\n%d\n%lld\n%@\n%@",
            kSeafFPWorkingSetPagePrefix,
            record.uuid,
            record.isDir ? 1 : 0,
            record.seq,
            record.repoId ?: @"",
            record.path ?: @""];
}

static SeafFPRecord * _Nullable SeafFPWorkingSetCursorFromToken(NSString *token, NSString * _Nullable * _Nullable outUUID)
{
    if (![token hasPrefix:kSeafFPWorkingSetPagePrefix]) return nil;
    NSString *payload = [token substringFromIndex:kSeafFPWorkingSetPagePrefix.length];
    if (payload.length == 0) return nil;
    NSArray<NSString *> *parts = [payload componentsSeparatedByString:@"\n"];
    NSString *uuid = parts.firstObject;
    if (outUUID) *outUUID = uuid;
    if (parts.count < 5 || uuid.length == 0) return nil;
    NSString *isDirStr = parts[1];
    NSString *seqStr = parts[2];
    NSString *repoId = parts[3];
    NSString *path = [[parts subarrayWithRange:NSMakeRange(4, parts.count - 4)] componentsJoinedByString:@"\n"];
    if (!SeafFPIsDecimal(isDirStr) || !SeafFPIsDecimal(seqStr) || repoId.length == 0 || path.length == 0) {
        return nil;
    }
    SeafFPRecord *cursor = [SeafFPRecord new];
    cursor.uuid = uuid;
    cursor.isDir = isDirStr.intValue != 0;
    cursor.seq = seqStr.longLongValue;
    cursor.repoId = repoId;
    cursor.path = path;
    return cursor;
}

#pragma mark - Container load result

/// One listing of a container: every current item, the new anchor, and what
/// changed compared with the snapshot stored by the previous listing. A
/// listing served from the offline cache never changes the store's view and
/// reports no changes.
@interface SeafFPContainerLoad : NSObject
@property (nonatomic, copy) NSString *anchor;
@property (nonatomic, assign) BOOL fromCache;
@property (nonatomic, copy) NSArray<SeafFPItem *> *items;
@property (nonatomic, copy) NSArray<SeafFPItem *> *updatedItems;
@property (nonatomic, copy) NSArray<NSFileProviderItemIdentifier> *deletedIdentifiers;
@end

@implementation SeafFPContainerLoad
@end

typedef void (^SeafFPContainerCompletion)(SeafFPContainerLoad * _Nullable load, NSError * _Nullable error);

#pragma mark - Change set

/// Updates and deletions collected for one change enumeration. A deletion
/// wins over an update of the same identifier.
@interface SeafFPChangeSet : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, SeafFPItem *> *updated;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *updatedOrder;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *deleted;
- (NSArray<SeafFPItem *> *)orderedUpdatedItems;
@end

@implementation SeafFPChangeSet

- (instancetype)init
{
    self = [super init];
    if (self) {
        _updated = [NSMutableDictionary dictionary];
        _updatedOrder = [NSMutableOrderedSet orderedSet];
        _deleted = [NSMutableOrderedSet orderedSet];
    }
    return self;
}

- (void)addUpdatedItems:(NSArray<SeafFPItem *> *)items
{
    for (SeafFPItem *item in items) {
        self.updated[item.itemIdentifier] = item;
        [self.updatedOrder addObject:item.itemIdentifier];
    }
}

- (void)addDeletedIdentifiers:(NSArray<NSString *> *)identifiers
{
    [self.deleted addObjectsFromArray:identifiers];
}

- (void)addLoad:(SeafFPContainerLoad *)load
{
    [self addUpdatedItems:load.updatedItems];
    [self addDeletedIdentifiers:load.deletedIdentifiers];
}

- (NSArray<SeafFPItem *> *)orderedUpdatedItems
{
    NSMutableArray<SeafFPItem *> *updates = [NSMutableArray arrayWithCapacity:self.updatedOrder.count];
    NSMutableDictionary<NSString *, NSNumber *> *orderIndex = [NSMutableDictionary dictionaryWithCapacity:self.updatedOrder.count];
    NSUInteger idx = 0;
    for (NSString *identifier in self.updatedOrder) {
        orderIndex[identifier] = @(idx++);
        if (![self.deleted containsObject:identifier]) {
            SeafFPItem *item = self.updated[identifier];
            if (item) [updates addObject:item];
        }
    }
    if (updates.count <= 1) return updates;
    NSMutableDictionary<NSString *, NSNumber *> *depthByID = [NSMutableDictionary dictionaryWithCapacity:updates.count];
    for (SeafFPItem *item in updates) {
        NSUInteger depth = ([SeafFPIdentifier kindOfIdentifier:item.itemIdentifier] == SeafFPIdentifierKindRepo) ? 0 : 1;
        NSString *parentID = item.parentItemIdentifier;
        NSUInteger hops = 0;
        while (parentID.length > 0 && self.updated[parentID] && ![self.deleted containsObject:parentID] && hops < 64) {
            depth++;
            hops++;
            parentID = self.updated[parentID].parentItemIdentifier;
        }
        depthByID[item.itemIdentifier] = @(depth);
    }
    [updates sortUsingComparator:^NSComparisonResult(SeafFPItem *a, SeafFPItem *b) {
        NSUInteger depthA = [depthByID[a.itemIdentifier] unsignedIntegerValue];
        NSUInteger depthB = [depthByID[b.itemIdentifier] unsignedIntegerValue];
        if (depthA != depthB) return depthA < depthB ? NSOrderedAscending : NSOrderedDescending;
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? NSOrderedAscending : NSOrderedDescending;
        NSUInteger idxA = [orderIndex[a.itemIdentifier] unsignedIntegerValue];
        NSUInteger idxB = [orderIndex[b.itemIdentifier] unsignedIntegerValue];
        return idxA < idxB ? NSOrderedAscending : (idxA > idxB ? NSOrderedDescending : NSOrderedSame);
    }];
    return updates;
}

- (void)deliverToObserver:(id<NSFileProviderChangeObserver>)observer
{
    NSArray<SeafFPItem *> *updates = [self orderedUpdatedItems];
    // Batches keep the peak memory of a big pass small (the extension has a
    // tight memory limit).
    for (NSUInteger start = 0; start < updates.count; start += kSeafFPWorkingSetPageSize) {
        NSRange range = NSMakeRange(start, MIN((NSUInteger)kSeafFPWorkingSetPageSize, updates.count - start));
        [observer didUpdateItems:[updates subarrayWithRange:range]];
    }
    if (self.deleted.count > 0) {
        [observer didDeleteItemsWithIdentifiers:self.deleted.array];
    }
}

@end

#pragma mark - Enumerator

@interface SeafFPEnumerator ()
@property (nonatomic, strong) SeafFPExtension *extension;
@property (nonatomic, copy) NSFileProviderItemIdentifier containerIdentifier;
@property (nonatomic, assign) SeafFPIdentifierKind kind;
// seq when the full working set enumeration on this enumerator started; the
// anchor handed out after it, so rows written during the scan are not skipped.
// -1 until a scan started: 0 is a valid seq (a fresh or rebuilt store).
@property (nonatomic, assign) long long scanStartSeq;
@property (nonatomic, copy, nullable) NSArray<SeafFPRecord *> *scanSnapshot;
@end

@implementation SeafFPEnumerator

- (instancetype)initWithExtension:(SeafFPExtension *)extension containerIdentifier:(NSFileProviderItemIdentifier)containerIdentifier
{
    self = [super init];
    if (self) {
        _extension = extension;
        _containerIdentifier = [containerIdentifier copy];
        _kind = [SeafFPIdentifier kindOfIdentifier:containerIdentifier];
        _scanStartSeq = -1;
    }
    return self;
}

- (void)invalidate
{
    Info("invalidate enumerator %@", self.containerIdentifier);
}

#pragma mark - Loading

/// Lists any root / library / directory container from the server (cache
/// when unreachable), updates the store and reports what changed.
- (void)loadContainer:(NSFileProviderItemIdentifier)containerIdentifier completion:(SeafFPContainerCompletion)completion
{
    NSError *access = [self.extension accessError];
    if (access) {
        completion(nil, access);
        return;
    }
    if (![self.extension.store isOpen]) {
        // After invalidate: an empty answer would be taken as "directory is empty".
        completion(nil, [SeafFPErrors cannotSynchronize]);
        return;
    }
    switch ([SeafFPIdentifier kindOfIdentifier:containerIdentifier]) {
        case SeafFPIdentifierKindRoot:
            [self loadRoot:containerIdentifier completion:completion];
            return;
        case SeafFPIdentifierKindRepo:
        case SeafFPIdentifierKindItem:
            [self loadDirectory:containerIdentifier completion:completion];
            return;
        default:
            completion(nil, [SeafFPErrors noSuchItem]);
            return;
    }
}

- (void)loadRoot:(NSFileProviderItemIdentifier)containerIdentifier completion:(SeafFPContainerCompletion)completion
{
    SeafRepos *repos = self.extension.connection.rootFolder;
    __weak typeof(self) weakSelf = self;
    [repos loadContentSuccess:^(SeafDir *dir) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            completion(nil, [SeafFPErrors cannotSynchronize]);
            return;
        }
        [strongSelf deliverRoot:(SeafRepos *)dir fromCache:NO container:containerIdentifier completion:completion];
    } failure:^(SeafDir *dir, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        SeafRepos *r = (SeafRepos *)dir;
        BOOL cached = r.hasCache || [r loadCache];
        if (cached && strongSelf) {
            Info("Library list unreachable, serving cache: %@", error);
            [strongSelf deliverRoot:r fromCache:YES container:containerIdentifier completion:completion];
        } else {
            NSError *mapped = [SeafFPErrors errorForSeafError:error];
            [strongSelf.extension noteError:mapped];
            completion(nil, mapped);
        }
    }];
}

- (void)deliverRoot:(SeafRepos *)repos
          fromCache:(BOOL)fromCache
          container:(NSFileProviderItemIdentifier)containerIdentifier
         completion:(SeafFPContainerCompletion)completion
{
    SeafFPStore *store = self.extension.store;
    NSString *previousAnchor = [store anchorForContainer:containerIdentifier];
    NSSet<NSString *> *previous = [NSSet setWithArray:[store snapshotForContainer:containerIdentifier]];

    NSMutableArray<SeafFPItem *> *items = [NSMutableArray array];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (SeafRepo *repo in SeafFPVisibleRepos(repos)) {
        [items addObject:[self.extension itemForRepo:repo]];
        [lines addObject:[NSString stringWithFormat:@"%@|%lld|%@|%@", repo.repoId, repo.mtime, repo.perm ?: @"", repo.name ?: @""]];
    }
    [lines sortUsingSelector:@selector(compare:)];
    NSString *anchor = [SeafFPIdentifier sha1Hex:[lines componentsJoinedByString:@"\n"]];
    NSMutableArray<NSString *> *snapshot = [NSMutableArray array];
    for (SeafFPItem *item in items) {
        [snapshot addObject:item.itemIdentifier];
    }

    SeafFPContainerLoad *load = [SeafFPContainerLoad new];
    load.fromCache = fromCache;
    load.items = items;
    if (fromCache) {
        // A stale list must not delete libraries the system already knows.
        load.anchor = previousAnchor ?: anchor;
        load.updatedItems = @[];
        load.deletedIdentifiers = @[];
        completion(load, nil);
        return;
    }
    [store setAnchor:anchor snapshot:snapshot forContainer:containerIdentifier];
    load.anchor = anchor;
    if ([anchor isEqualToString:previousAnchor]) {
        load.updatedItems = @[];
        load.deletedIdentifiers = @[];
    } else {
        // The hash covers id, mtime, permission and name of every library;
        // report them all, the system skips those whose version is unchanged.
        load.updatedItems = items;
        NSSet<NSString *> *current = [NSSet setWithArray:snapshot];
        NSMutableArray<NSString *> *gone = [NSMutableArray array];
        for (NSString *identifier in previous) {
            if (![current containsObject:identifier]) [gone addObject:identifier];
        }
        load.deletedIdentifiers = gone;
    }
    [self.extension noteSuccess];
    completion(load, nil);
}

- (void)loadDirectory:(NSFileProviderItemIdentifier)containerIdentifier completion:(SeafFPContainerCompletion)completion
{
    SeafFPIdentifierKind kind = [SeafFPIdentifier kindOfIdentifier:containerIdentifier];
    NSString *repoId = kind == SeafFPIdentifierKindRepo ? [SeafFPIdentifier repoIdFromIdentifier:containerIdentifier] : nil;
    if (repoId && [self.extension repoListUnknownFor:repoId]) {
        // Fresh process: get the library list before deciding the library is gone.
        __weak typeof(self) weakSelf = self;
        [self.extension ensureRepoListLoaded:^(BOOL known, BOOL fromNetwork) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) { completion(nil, [SeafFPErrors cannotSynchronize]); return; }
            if (!known) { completion(nil, [SeafFPErrors serverUnreachable]); return; }
            [strongSelf loadResolvedDirectory:containerIdentifier completion:completion];
        }];
        return;
    }
    [self loadResolvedDirectory:containerIdentifier completion:completion];
}

- (void)loadResolvedDirectory:(NSFileProviderItemIdentifier)containerIdentifier completion:(SeafFPContainerCompletion)completion
{
    SeafFPRecord *record = nil;
    SeafDir *dir = [self.extension seafDirForContainer:containerIdentifier record:&record];
    if (!dir) {
        // A locked library is hidden, not gone: the system keeps what it has below it.
        SeafRepo *repo = [self.extension repoWithId:[SeafFPIdentifier repoIdFromIdentifier:containerIdentifier]];
        completion(nil, repo.passwordRequired ? [SeafFPErrors notAuthenticated] : [SeafFPErrors noSuchItem]);
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self.extension loadDirectory:dir completion:^(BOOL loaded, BOOL fromCache, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!loaded) {
            completion(nil, error ?: [SeafFPErrors serverUnreachable]);
            return;
        }
        if (!strongSelf) {
            completion(nil, [SeafFPErrors cannotSynchronize]);
            return;
        }
        [strongSelf deliverDirectory:dir record:record fromCache:fromCache container:containerIdentifier completion:completion];
    }];
}

- (void)deliverDirectory:(SeafDir *)dir
                  record:(SeafFPRecord *)record
               fromCache:(BOOL)fromCache
               container:(NSFileProviderItemIdentifier)containerIdentifier
              completion:(SeafFPContainerCompletion)completion
{
    SeafFPStore *store = self.extension.store;
    NSString *repoId = dir.repoId;
    NSString *parentUUID = record.uuid;   // nil for the library root
    BOOL editable = [self.extension isRepoEditable:repoId];

    NSString *previousAnchor = [store anchorForContainer:containerIdentifier];
    NSSet<NSString *> *previous = [NSSet setWithArray:[store snapshotForContainer:containerIdentifier]];
    NSMutableDictionary<NSString *, SeafFPDecoration *> *decorations = [NSMutableDictionary dictionary];
    for (SeafFPDecoration *decoration in [store allDecorations]) {
        decorations[decoration.itemIdentifier] = decoration;
    }
    NSArray<SeafBase *> *entries = [dir.items copy];

    NSMutableArray<SeafFPItem *> *items = [NSMutableArray array];
    NSMutableArray<SeafFPItem *> *updated = [NSMutableArray array];
    NSMutableArray<NSString *> *stale = [NSMutableArray array];
    __block long long seqBefore = 0;
    // One queue hop and one transaction for the whole listing.
    [store performBatch:^{
        seqBefore = [store currentSeq];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (SeafBase *obj in entries) {
            BOOL isDir = [obj isKindOfClass:[SeafDir class]];
            long long mtime = isDir ? ((SeafDir *)obj).mtime : ((SeafFile *)obj).mtime;
            long long size = isDir ? -1 : (long long)((SeafFile *)obj).filesize;
            SeafFPRecord *child = nil;
            if (fromCache) {
                // A stale cache must neither revive tombstoned rows nor overwrite
                // fresher ones (an edit uploaded from Files, say): existing rows
                // are served as they are, only unknown entries get a row.
                child = [store recordForRepo:repoId path:obj.path includeDeleted:YES];
                if (child.deleted) continue;
            }
            if (!child) {
                child = [store upsertRecordForRepo:repoId
                                              path:obj.path
                                             isDir:isDir
                                        parentUUID:parentUUID
                                               oid:obj.oid
                                             mtime:mtime
                                              size:size];
            }
            if (!child) continue;
            [seen addObject:child.uuid];
            SeafFPItem *item = [SeafFPItem itemForRecord:child repoEditable:editable];
            [item applyDecoration:decorations[item.itemIdentifier]];
            [items addObject:item];
            // New to this listing, or its identity row changed during this pass.
            if (child.seq > seqBefore || ![previous containsObject:item.itemIdentifier]) {
                [updated addObject:item];
            }
        }
        if (!fromCache) {
            for (SeafFPRecord *gone in [store childRecordsOfRepo:repoId parentUUID:parentUUID]) {
                if (![seen containsObject:gone.uuid]) [stale addObject:gone.uuid];
            }
            [store markDeletedUUIDs:stale];
        }
    }];

    NSString *anchor = dir.ooid.length > 0 ? dir.ooid : (dir.oid.length > 0 ? dir.oid : @"0");
    SeafFPContainerLoad *load = [SeafFPContainerLoad new];
    load.fromCache = fromCache;
    load.items = items;
    if (![store isOpen]) {
        completion(nil, [SeafFPErrors cannotSynchronize]);
        return;
    }
    if (fromCache) {
        load.anchor = previousAnchor ?: anchor;
        load.updatedItems = @[];
        load.deletedIdentifiers = @[];
        completion(load, nil);
        return;
    }

    NSMutableArray<NSString *> *snapshot = [NSMutableArray array];
    for (SeafFPItem *item in items) {
        [snapshot addObject:item.itemIdentifier];
    }
    [store setAnchor:anchor snapshot:snapshot forContainer:containerIdentifier];

    NSSet<NSString *> *current = [NSSet setWithArray:snapshot];
    NSMutableArray<NSString *> *deleted = [NSMutableArray array];
    for (NSString *identifier in previous) {
        if ([current containsObject:identifier]) continue;
        SeafFPRecord *gone = [store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:identifier]];
        if (gone && !gone.deleted) {
            // Moved elsewhere from Files: still alive, report its new parent.
            [updated addObject:[self.extension itemForRecord:gone]];
        } else {
            [deleted addObject:identifier];
        }
    }
    load.anchor = anchor;
    load.updatedItems = updated;
    load.deletedIdentifiers = deleted;
    [self.extension noteSuccess];
    completion(load, nil);
}

#pragma mark - Working set

- (NSString *)workingSetAnchor
{
    // After a full enumeration the anchor is the seq the scan started at:
    // rows written while the scan ran are reported by the next change pass.
    long long seq = self.scanStartSeq >= 0 ? self.scanStartSeq : [self.extension.store currentSeq];
    return [NSString stringWithFormat:@"%@%lld", kSeafFPWorkingSetAnchorPrefix, seq];
}

/// Libraries reachable from the root right now; rows of any other library
/// (unshared, or locked) have no parent chain the system could resolve.
- (NSSet<NSString *> *)visibleRepoIds
{
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    for (SeafRepo *repo in SeafFPVisibleRepos(self.extension.connection.rootFolder)) {
        [ids addObject:repo.repoId];
    }
    return ids;
}

/// One page of the full working set enumeration. Everything the system has
/// learnt through this extension belongs to the working set
/// (NSFileProviderReplicatedExtension.h: an enumerated directory and its
/// children are part of it) and only working set items are indexed for
/// Spotlight, which is what the Tags list and, on iOS 26, the favorites
/// sidebar of Files are built from. The first page carries the library list,
/// the identity table follows in uuid order; the page token is the last uuid.
- (void)enumerateWorkingSetPage:(NSFileProviderPage)page observer:(id<NSFileProviderEnumerationObserver>)observer
{
    SeafFPStore *store = self.extension.store;
    NSString *token = SeafFPAnchorString(page);
    BOOL firstPage = ![token hasPrefix:kSeafFPWorkingSetPagePrefix];
    NSString *afterUUID = nil;
    SeafFPRecord *cursorRecord = firstPage ? nil : SeafFPWorkingSetCursorFromToken(token, &afterUUID);

    NSMutableArray<SeafFPItem *> *items = [NSMutableArray array];
    NSArray<SeafFPRecord *> *allRecords = nil;
    if (firstPage) {
        self.scanStartSeq = [store currentSeq];
        allRecords = SeafFPSortRecordsParentFirst([store liveRecordsAfterUUID:nil limit:0]);
        self.scanSnapshot = allRecords;
        for (SeafRepo *repo in SeafFPVisibleRepos(self.extension.connection.rootFolder)) {
            [items addObject:[self.extension itemForRepo:repo]];
        }
    } else if (self.scanSnapshot && self.scanStartSeq >= 0 && [store currentSeq] == self.scanStartSeq) {
        allRecords = self.scanSnapshot;
    } else {
        allRecords = SeafFPSortRecordsParentFirst([store liveRecordsAfterUUID:nil limit:0]);
    }
    NSSet<NSString *> *repoIds = [self visibleRepoIds];
    NSMutableDictionary<NSString *, SeafFPDecoration *> *decorations = [NSMutableDictionary dictionary];
    for (SeafFPDecoration *decoration in [store allDecorations]) {
        decorations[decoration.itemIdentifier] = decoration;
    }
    NSUInteger startIndex = 0;
    if (!firstPage) {
        if (!cursorRecord && afterUUID.length > 0 && self.scanSnapshot.count > 0) {
            for (SeafFPRecord *snap in self.scanSnapshot) {
                if ([snap.uuid isEqualToString:afterUUID]) {
                    cursorRecord = snap;
                    break;
                }
            }
        }
        if (cursorRecord) {
            startIndex = [allRecords indexOfObject:cursorRecord
                                     inSortedRange:NSMakeRange(0, allRecords.count)
                                           options:(NSBinarySearchingInsertionIndex | NSBinarySearchingLastEqual)
                                   usingComparator:^NSComparisonResult(SeafFPRecord *a, SeafFPRecord *b) {
                                       return SeafFPCompareRecordsParentFirst(a, b);
                                   }];
        } else if (afterUUID.length > 0) {
            BOOL found = NO;
            for (NSUInteger i = 0; i < allRecords.count; i++) {
                if ([allRecords[i].uuid isEqualToString:afterUUID]) {
                    startIndex = i + 1;
                    found = YES;
                    break;
                }
            }
            if (!found) {
                [observer finishEnumeratingWithError:[SeafFPErrors syncAnchorExpired]];
                return;
            }
        } else {
            [observer finishEnumeratingWithError:[SeafFPErrors syncAnchorExpired]];
            return;
        }
    }
    NSUInteger remaining = startIndex < allRecords.count ? (allRecords.count - startIndex) : 0;
    NSUInteger pageCount = MIN(remaining, (NSUInteger)kSeafFPWorkingSetPageSize);
    NSArray<SeafFPRecord *> *records = pageCount > 0 ? [allRecords subarrayWithRange:NSMakeRange(startIndex, pageCount)] : @[];
    SeafFPRecord *lastRecord = records.lastObject;
    NSString *nextPageToken = SeafFPWorkingSetPageTokenForRecord(lastRecord);
    BOOL more = (startIndex + pageCount) < allRecords.count && nextPageToken.length > 0;
    for (SeafFPRecord *record in records) {
        if (![repoIds containsObject:record.repoId]) continue;
        SeafFPItem *item = [SeafFPItem itemForRecord:record repoEditable:[self.extension isRepoEditable:record.repoId]];
        [item applyDecoration:decorations[item.itemIdentifier]];
        [items addObject:item];
    }
    Info("working set page after %@: %lu items%@", afterUUID ?: @"(start)", (unsigned long)items.count, more ? @", more" : @", last");
    if (!more) {
        self.scanSnapshot = nil;
    }
    if (items.count > 0) {
        [observer didEnumerateItems:items];
    }
    [observer finishEnumeratingUpToPage:more ? SeafFPAnchorData(nextPageToken) : nil];
}

/// A listing that changed the local view changed the working set; the system
/// pulls the change and indexes the new items.
- (void)signalWorkingSetIfChanged:(SeafFPContainerLoad *)load
{
    if (load.fromCache) return;
    if (load.updatedItems.count == 0 && load.deletedIdentifiers.count == 0) return;
    [self.extension signalWorkingSet];
}

/// Directories the working set members live in (a directory member is its
/// own container), least recently checked first, capped per pass. recheckAt:
/// when directories were left alone because they were listed within the
/// re-check interval, the moment the first of them may be checked again.
- (NSArray<NSFileProviderItemIdentifier> *)workingSetContainersToCheckRecheckAt:(NSDate **)recheckAt
{
    if (recheckAt) *recheckAt = nil;
    SeafFPStore *store = self.extension.store;
    NSMutableSet<NSString *> *containers = [NSMutableSet set];
    for (NSString *identifier in [store workingSetItemIdentifiers]) {
        switch ([SeafFPIdentifier kindOfIdentifier:identifier]) {
            case SeafFPIdentifierKindRepo:
                [containers addObject:identifier];
                break;
            case SeafFPIdentifierKindItem: {
                SeafFPRecord *record = [store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:identifier]];
                if (!record || record.deleted) break;
                [containers addObject:record.isDir ? identifier : record.parentItemIdentifier];
                break;
            }
            default:
                break;
        }
    }
    NSDictionary<NSString *, NSDate *> *checkedAt = [store enumeratedAtByContainer];
    NSDate *never = [NSDate distantPast];
    NSDate *recent = [NSDate dateWithTimeIntervalSinceNow:-kSeafFPWorkingSetRecheckInterval];
    NSDate *earliestSkipped = nil;
    for (NSString *container in containers.allObjects) {
        NSDate *at = checkedAt[container];
        if (!at || [at compare:recent] != NSOrderedDescending) continue;
        [containers removeObject:container];
        if (!earliestSkipped || [at compare:earliestSkipped] == NSOrderedAscending) earliestSkipped = at;
    }
    if (recheckAt && earliestSkipped) {
        *recheckAt = [earliestSkipped dateByAddingTimeInterval:kSeafFPWorkingSetRecheckInterval];
    }
    NSArray<NSString *> *sorted = [containers.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSComparisonResult byDate = [(checkedAt[a] ?: never) compare:(checkedAt[b] ?: never)];
        return byDate != NSOrderedSame ? byDate : [a compare:b];
    }];
    if (sorted.count > kSeafFPWorkingSetDirectoryChecksPerPass) {
        sorted = [sorted subarrayWithRange:NSMakeRange(0, kSeafFPWorkingSetDirectoryChecksPerPass)];
        // The ones that did not fit are due now, not in a re-check interval:
        // without a pass of their own they would wait for an unrelated signal.
        // Each pass stamps what it checked, so the passes that follow move on
        // to the next containers and the chain ends.
        if (recheckAt) *recheckAt = [NSDate date];
    }
    // The library list is always re-checked: the system ignores signals for
    // any container but the working set, so a library that was unlocked,
    // renamed or shared in the app can only reach Files through here.
    return [@[NSFileProviderRootContainerItemIdentifier] arrayByAddingObjectsFromArray:sorted];
}

- (void)checkContainers:(NSArray<NSFileProviderItemIdentifier> *)containers
                  index:(NSUInteger)index
               deadline:(NSDate *)deadline
                changes:(SeafFPChangeSet *)changes
             completion:(dispatch_block_t)completion
{
    if (index >= containers.count || [deadline timeIntervalSinceNow] <= 0) {
        completion();
        return;
    }
    NSString *container = containers[index];
    __weak typeof(self) weakSelf = self;
    [self loadContainer:container completion:^(SeafFPContainerLoad *load, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            completion();
            return;
        }
        if (error) {
            Info("working set check of %@ failed: %@", container, error);
            if (error.code == NSFileProviderErrorNoSuchItem) {
                // Gone locally; the next container may still be fine.
                [strongSelf checkContainers:containers index:index + 1 deadline:deadline changes:changes completion:completion];
            } else {
                // Unreachable: report what was collected, the rest waits for the next pass.
                completion();
            }
            return;
        }
        [changes addLoad:load];
        // A listing served from the cache (one flaky request, or offline) does
        // not stop the pass: the remaining loads fail fast or hit their own
        // cache, and the deadline bounds the total.
        [strongSelf checkContainers:containers index:index + 1 deadline:deadline changes:changes completion:completion];
    }];
}

- (void)enumerateWorkingSetChangesSinceSeq:(long long)known observer:(id<NSFileProviderChangeObserver>)observer
{
    SeafFPStore *store = self.extension.store;
    SeafFPChangeSet *changes = [SeafFPChangeSet new];
    // A long backlog (a big listing just came in, or the first pass after an
    // upgrade) is reported in slices without re-listing anything.
    NSArray<SeafFPRecord *> *backlog = [store recordsChangedSinceSeq:known limit:kSeafFPWorkingSetChangesPerPass];
    BOOL backlogMode = backlog.count == (NSUInteger)kSeafFPWorkingSetChangesPerPass;
    NSDate *recheckAt = nil;
    NSArray<NSString *> *containers = nil;
    if (backlog.count > 0) {
        // Local store rows are already waiting to be reported (a directory was
        // just browsed in the app): deliver them immediately without blocking on
        // network container checks unless a record belongs to an unknown library
        // or the library list was never anchored.
        NSSet<NSString *> *knownRepos = [self visibleRepoIds];
        BOOL needsRootRefresh = ([store anchorForContainer:NSFileProviderRootContainerItemIdentifier].length == 0);
        if (!needsRootRefresh) {
            for (SeafFPRecord *rec in backlog) {
                if (!rec.deleted && rec.repoId.length > 0 && ![knownRepos containsObject:rec.repoId]) {
                    needsRootRefresh = YES;
                    break;
                }
            }
        }
        containers = (backlogMode || !needsRootRefresh) ? @[] : @[NSFileProviderRootContainerItemIdentifier];
    } else {
        containers = [self workingSetContainersToCheckRecheckAt:&recheckAt];
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:kSeafFPWorkingSetCheckBudget];
    __weak typeof(self) weakSelf = self;
    // Directories are re-listed first so every row they touch (including
    // tombstoned subtrees) is still above the anchor when the changes are read.
    [self checkContainers:containers index:0 deadline:deadline changes:changes completion:^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            [observer finishEnumeratingWithError:[SeafFPErrors cannotSynchronize]];
            return;
        }
        // Every identity row written since the anchor is reported: the whole
        // local view is the working set (see enumerateWorkingSetPage:).
        long long cut = [store currentSeq];
        NSArray<SeafFPRecord *> *records = backlogMode ? backlog : [store recordsChangedSinceSeq:known limit:kSeafFPWorkingSetChangesPerPass];
        BOOL moreComing = records.count == (NSUInteger)kSeafFPWorkingSetChangesPerPass && records.lastObject.seq < cut;
        if (moreComing) cut = records.lastObject.seq;
        NSSet<NSString *> *repoIds = [strongSelf visibleRepoIds];
        NSMutableDictionary<NSString *, SeafFPDecoration *> *decorations = [NSMutableDictionary dictionary];
        for (SeafFPDecoration *decoration in [store allDecorations]) {
            decorations[decoration.itemIdentifier] = decoration;
        }
        NSMutableDictionary<NSString *, SeafFPRecord *> *liveRecordsByUUID = [NSMutableDictionary dictionary];
        void (^includeRecordAndAncestors)(SeafFPRecord *) = ^(SeafFPRecord *rec) {
            SeafFPRecord *cur = rec;
            NSUInteger hops = 0;
            while (cur && !cur.deleted && cur.uuid.length > 0 && !liveRecordsByUUID[cur.uuid] && hops < 64) {
                if (![repoIds containsObject:cur.repoId]) break;
                liveRecordsByUUID[cur.uuid] = cur;
                hops++;
                if (cur.parentUUID.length == 0) break;
                cur = [store recordForUUID:cur.parentUUID];
            }
        };
        for (NSString *existingId in [changes.updated.allKeys copy]) {
            if ([SeafFPIdentifier kindOfIdentifier:existingId] == SeafFPIdentifierKindItem) {
                SeafFPRecord *rec = [store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:existingId]];
                if (rec && !rec.deleted) includeRecordAndAncestors(rec);
            }
        }
        for (SeafFPRecord *record in records) {
            if (record.seq > cut) continue;   // written after the cut, next pass
            if (record.deleted) {
                [changes addDeletedIdentifiers:@[record.itemIdentifier]];
                continue;
            }
            if (![repoIds containsObject:record.repoId]) continue;
            includeRecordAndAncestors(record);
        }
        // Favorite / tag changes of rows whose identity did not change.
        for (NSString *identifier in [store workingSetItemIdentifiersChangedSinceSeq:known]) {
            if ([SeafFPIdentifier kindOfIdentifier:identifier] == SeafFPIdentifierKindItem) {
                SeafFPRecord *rec = [store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:identifier]];
                if (rec && !rec.deleted && [repoIds containsObject:rec.repoId]) {
                    includeRecordAndAncestors(rec);
                    continue;
                }
            }
            SeafFPItem *item = [strongSelf.extension resolveItem:identifier error:nil];
            if (item) {
                [changes addUpdatedItems:@[item]];
            }
        }
        for (SeafFPRecord *record in SeafFPSortRecordsParentFirst(liveRecordsByUUID.allValues)) {
            NSString *repoItemIdentifier = [SeafFPIdentifier identifierForRepo:record.repoId];
            if (!changes.updated[repoItemIdentifier]) {
                SeafRepo *repo = [strongSelf.extension repoWithId:record.repoId];
                if (repo && !repo.passwordRequired) {
                    [changes addUpdatedItems:@[[strongSelf.extension itemForRepo:repo]]];
                }
            }
            SeafFPItem *item = [SeafFPItem itemForRecord:record repoEditable:[strongSelf.extension isRepoEditable:record.repoId]];
            [item applyDecoration:decorations[item.itemIdentifier]];
            [changes addUpdatedItems:@[item]];
        }
        [changes deliverToObserver:observer];
        NSString *anchor = [NSString stringWithFormat:@"%@%lld", kSeafFPWorkingSetAnchorPrefix, cut];
        Info("working set changes since %lld: %lu updated, %lu deleted, checked %lu containers, anchor %@%@",
              known, (unsigned long)changes.updated.count, (unsigned long)changes.deleted.count,
              (unsigned long)containers.count, anchor, moreComing ? @", more coming" : @"");
        [observer finishEnumeratingChangesUpToSyncAnchor:SeafFPAnchorData(anchor) moreComing:moreComing];
        // Directories skipped for being listed just now (possibly by the
        // listing that signalled), or left over when this pass ran out of its
        // budget, get their turn in a pass of their own.
        NSDate *nextPass = recheckAt;
        if ([deadline timeIntervalSinceNow] <= 0) {
            nextPass = [NSDate date];
        }
        if (nextPass && !moreComing) {
            [strongSelf.extension scheduleWorkingSetRecheckAt:nextPass];
        }
    }];
}

#pragma mark - NSFileProviderEnumerator

- (void)enumerateItemsForObserver:(id<NSFileProviderEnumerationObserver>)observer startingAtPage:(NSFileProviderPage)page
{
    Info("enumerate %@", self.containerIdentifier);
    switch (self.kind) {
        case SeafFPIdentifierKindWorkingSet: {
            NSError *access = [self.extension accessError];
            if (access) {
                [observer finishEnumeratingWithError:access];
                return;
            }
            // The library list heads the working set: every item's parent chain
            // must be part of it for the system to index the item.
            __weak typeof(self) weakSelf = self;
            [self.extension ensureRepoListLoaded:^(BOOL known, BOOL fromNetwork) {
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) { [observer finishEnumeratingWithError:[SeafFPErrors cannotSynchronize]]; return; }
                if (!known) { [observer finishEnumeratingWithError:[SeafFPErrors serverUnreachable]]; return; }
                [strongSelf enumerateWorkingSetPage:page observer:observer];
            }];
            return;
        }
        case SeafFPIdentifierKindRoot:
        case SeafFPIdentifierKindRepo:
        case SeafFPIdentifierKindItem: {
            [self loadContainer:self.containerIdentifier completion:^(SeafFPContainerLoad *load, NSError *error) {
                if (error) {
                    Warning("enumerate %@ failed: %@", self.containerIdentifier, error);
                    [observer finishEnumeratingWithError:error];
                    return;
                }
                [observer didEnumerateItems:load.items];
                [observer finishEnumeratingUpToPage:nil];
                [self signalWorkingSetIfChanged:load];
            }];
            return;
        }
        default:
            [observer finishEnumeratingWithError:[SeafFPErrors noSuchItem]];
            return;
    }
}

- (void)enumerateChangesForObserver:(id<NSFileProviderChangeObserver>)observer fromSyncAnchor:(NSFileProviderSyncAnchor)syncAnchor
{
    NSString *known = SeafFPAnchorString(syncAnchor);
    Info("enumerate changes %@ from %@", self.containerIdentifier, known);
    switch (self.kind) {
        case SeafFPIdentifierKindWorkingSet: {
            NSError *access = [self.extension accessError];
            if (access) {
                [observer finishEnumeratingWithError:access];
                return;
            }
            long long current = [self.extension.store currentSeq];
            long long knownSeq = SeafFPWorkingSetSeqFromAnchor(known);
            if (knownSeq < 0 || knownSeq > current) {
                // Another generation, unparseable, or from a store that has
                // since been rebuilt: the system rescans the full working set.
                [observer finishEnumeratingWithError:[SeafFPErrors syncAnchorExpired]];
                return;
            }
            __weak typeof(self) weakSelf = self;
            [self.extension ensureRepoListLoaded:^(BOOL listKnown, BOOL fromNetwork) {
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) { [observer finishEnumeratingWithError:[SeafFPErrors cannotSynchronize]]; return; }
                if (!listKnown) { [observer finishEnumeratingWithError:[SeafFPErrors serverUnreachable]]; return; }
                [strongSelf enumerateWorkingSetChangesSinceSeq:knownSeq observer:observer];
            }];
            return;
        }
        case SeafFPIdentifierKindRoot:
        case SeafFPIdentifierKindRepo:
        case SeafFPIdentifierKindItem: {
            NSString *stored = [self.extension.store anchorForContainer:self.containerIdentifier];
            if (known.length == 0 || stored.length == 0 || ![known isEqualToString:stored]) {
                // The stored snapshot no longer matches what this observer saw
                // (a working set check or another listing moved it on): start over.
                [observer finishEnumeratingWithError:[SeafFPErrors syncAnchorExpired]];
                return;
            }
            [self loadContainer:self.containerIdentifier completion:^(SeafFPContainerLoad *load, NSError *error) {
                if (error) {
                    [observer finishEnumeratingWithError:error];
                    return;
                }
                if (load.fromCache || [load.anchor isEqualToString:known]) {
                    [observer finishEnumeratingChangesUpToSyncAnchor:syncAnchor moreComing:NO];
                    return;
                }
                SeafFPChangeSet *changes = [SeafFPChangeSet new];
                [changes addLoad:load];
                Info("changes in %@: %lu updated, %lu deleted", self.containerIdentifier,
                      (unsigned long)changes.updated.count, (unsigned long)changes.deleted.count);
                [changes deliverToObserver:observer];
                [observer finishEnumeratingChangesUpToSyncAnchor:SeafFPAnchorData(load.anchor) moreComing:NO];
                [self signalWorkingSetIfChanged:load];
            }];
            return;
        }
        default:
            [observer finishEnumeratingWithError:[SeafFPErrors noSuchItem]];
            return;
    }
}

- (void)currentSyncAnchorWithCompletionHandler:(void (^)(NSFileProviderSyncAnchor _Nullable))completionHandler
{
    switch (self.kind) {
        case SeafFPIdentifierKindWorkingSet:
            completionHandler(SeafFPAnchorData([self workingSetAnchor]));
            return;
        case SeafFPIdentifierKindRoot:
        case SeafFPIdentifierKindRepo:
        case SeafFPIdentifierKindItem:
            completionHandler(SeafFPAnchorData([self.extension.store anchorForContainer:self.containerIdentifier]));
            return;
        default:
            completionHandler(SeafFPAnchorData(@"0"));
            return;
    }
}

@end
