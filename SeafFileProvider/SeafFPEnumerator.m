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
#import <errno.h>
#import <limits.h>

// A working set change enumeration re-checks the directories its members live
// in, a few at a time, least recently checked first (design §8.2). Listings
// signal the working set, so a pass may follow every browse: a directory
// listed within the re-check interval is left alone by the pass.
static const NSUInteger kSeafFPWorkingSetDirectoryChecksPerPass = 5;
static const NSTimeInterval kSeafFPWorkingSetCheckBudget = 20.0;
static const NSTimeInterval kSeafFPWorkingSetRecheckInterval = 120.0;

// The working set is everything the system has learnt through this extension
// (design §7.4): a full enumeration hands out the library list and then the
// identity table parents first, this many rows per page; a change enumeration
// reports at most this many identity rows per pass and asks for another pass.
static const NSInteger kSeafFPWorkingSetPageSize = 200;
static const NSInteger kSeafFPWorkingSetChangesPerPass = 500;
static NSString * const kSeafFPWorkingSetPagePrefix = @"w2|";
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

static NSUInteger SeafFPPathDepth(NSString *path)
{
    NSUInteger depth = 0;
    NSUInteger length = path.length;
    for (NSUInteger i = 0; i < length; i++) {
        if ([path characterAtIndex:i] == '/') depth++;
    }
    return depth;
}

static NSComparisonResult SeafFPComparePosition(NSUInteger aDepth, BOOL aDir, long long aSeq, NSString *aUUID,
                                              NSUInteger bDepth, BOOL bDir, long long bSeq, NSString *bUUID)
{
    if (aDepth != bDepth) return aDepth < bDepth ? NSOrderedAscending : NSOrderedDescending;
    if (aDir != bDir) return aDir ? NSOrderedAscending : NSOrderedDescending;
    if (aSeq != bSeq) return aSeq < bSeq ? NSOrderedAscending : NSOrderedDescending;
    return [aUUID compare:bUUID];
}

static NSComparisonResult SeafFPCompareRecordsParentFirst(SeafFPRecord *a, SeafFPRecord *b)
{
    return SeafFPComparePosition(SeafFPPathDepth(a.path), a.isDir, a.seq, a.uuid,
                                 SeafFPPathDepth(b.path), b.isDir, b.seq, b.uuid);
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

static NSString * _Nullable SeafFPWorkingSetPageTokenForRecord(SeafFPRecord *record, long long scanStart)
{
    if (!record || record.uuid.length == 0 || scanStart < 0) return nil;
    return [NSString stringWithFormat:@"%@%lld|%lu|%d|%lld|%@", kSeafFPWorkingSetPagePrefix,
            scanStart, (unsigned long)SeafFPPathDepth(record.path), record.isDir ? 1 : 0, record.seq, record.uuid];
}

static BOOL SeafFPParseInteger(NSString *text, unsigned long long maximum, unsigned long long *value)
{
    if (text.length == 0 || text.length > 20
        || [text rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location != NSNotFound) return NO;
    errno = 0;
    unsigned long long parsed = strtoull(text.UTF8String, NULL, 10);
    if (errno == ERANGE || parsed > maximum) return NO;
    *value = parsed;
    return YES;
}

static NSDictionary * _Nullable SeafFPWorkingSetCursorFromToken(NSString *token)
{
    if (![token hasPrefix:kSeafFPWorkingSetPagePrefix] || [token lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 500) return nil;
    NSArray<NSString *> *parts = [token componentsSeparatedByString:@"|"];
    if (parts.count != 6 || parts[5].length != 32
        || [parts[5] rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location != NSNotFound) return nil;
    unsigned long long start = 0, depth = 0, isDir = 0, seq = 0;
    if (!SeafFPParseInteger(parts[1], LLONG_MAX, &start) || !SeafFPParseInteger(parts[2], NSUIntegerMax, &depth)
        || !SeafFPParseInteger(parts[3], 1, &isDir) || !SeafFPParseInteger(parts[4], LLONG_MAX, &seq)) return nil;
    return @{@"start":@(start), @"depth":@(depth), @"isDir":@(isDir), @"seq":@(seq), @"uuid":parts[5]};
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
        NSMutableSet *visited = [NSMutableSet setWithObject:item.itemIdentifier];
        while (parentID.length > 0 && self.updated[parentID] && ![self.deleted containsObject:parentID] && ![visited containsObject:parentID]) {
            [visited addObject:parentID];
            depth++;
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
// seq when the full working set enumeration this enumerator served a page of
// started (carried in the page token); the anchor handed out after it, so rows
// written during the scan are not skipped. -1 until it served a page: 0 is a
// valid seq (a fresh or rebuilt store).
@property (nonatomic, assign) long long scanStartSeq;
@property (nonatomic, assign) BOOL scanFailed;
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
    long long requestStartSeq = [self.extension.store beginRepositoryRequest];
    if (requestStartSeq < 0) { completion(nil, [SeafFPErrors cannotSynchronize]); return; }
    __weak typeof(self) weakSelf = self;
    [repos loadContentSuccess:^(SeafDir *dir) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            completion(nil, [SeafFPErrors cannotSynchronize]);
            return;
        }
        [strongSelf deliverRoot:(SeafRepos *)dir fromCache:NO requestStartSeq:requestStartSeq container:containerIdentifier completion:completion];
    } failure:^(SeafDir *dir, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        SeafRepos *r = (SeafRepos *)dir;
        BOOL cached = r.hasCache || [r loadCache];
        if (cached && strongSelf) {
            Info("Library list unreachable, serving cache: %@", error);
            [strongSelf deliverRoot:r fromCache:YES requestStartSeq:-1 container:containerIdentifier completion:completion];
        } else {
            NSError *mapped = [SeafFPErrors errorForSeafError:error];
            [strongSelf.extension noteError:mapped];
            completion(nil, mapped);
        }
    }];
}

- (void)deliverRoot:(SeafRepos *)repos
          fromCache:(BOOL)fromCache
    requestStartSeq:(long long)requestStartSeq
          container:(NSFileProviderItemIdentifier)containerIdentifier
         completion:(SeafFPContainerCompletion)completion
{
    SeafFPStore *store = self.extension.store;
    SeafFPWriteResult result = [store applyRepositorySnapshotResult:[repos fp_repositorySnapshot]
        complete:!fromCache fromCache:fromCache requestStartSeq:(fromCache ? -1 : requestStartSeq)];
    if (result == SeafFPWriteFailed) { completion(nil, [SeafFPErrors cannotSynchronize]); return; }
    NSString *previousAnchor = [store anchorForContainer:containerIdentifier];
    NSSet<NSString *> *previous = [NSSet setWithArray:[store snapshotForContainer:containerIdentifier]];

    NSMutableArray<SeafFPItem *> *items = [NSMutableArray array];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSDictionary *repositoryStates = [store repositoryStates];
    if (!repositoryStates) { completion(nil, [SeafFPErrors cannotSynchronize]); return; }
    for (NSString *repoId in [repositoryStates.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *state = repositoryStates[repoId];
        if (![state[@"availability"] isEqual:@"visible"]) continue;
        [items addObject:[self.extension itemForRepositoryState:state]];
        [lines addObject:[NSString stringWithFormat:@"%@|%@|%@|%@", repoId, state[@"mtime"], state[@"perm"], state[@"name"]]];
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
            NSString *repoId = [SeafFPIdentifier repoIdFromIdentifier:identifier];
            if (![current containsObject:identifier] && ![repositoryStates[repoId][@"availability"] isEqual:@"locked"]) [gone addObject:identifier];
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
    NSString *repoId = dir.repoId ?: [SeafFPIdentifier repoIdFromIdentifier:containerIdentifier];
    NSError *access = repoId ? [self.extension repositoryAccessError:repoId] : nil;
    if (access) { completion(nil, access); return; }
    if (!dir) {
        completion(nil, [SeafFPErrors noSuchItem]);
        return;
    }
    // Read before the request: rows the main app (or this process) writes
    // while it is in flight are newer than the listing and are left alone.
    long long requestStartSeq = [self.extension.store currentSeq];
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
        [strongSelf deliverDirectory:dir record:record fromCache:fromCache requestStartSeq:requestStartSeq
                           container:containerIdentifier completion:completion];
    }];
}

- (void)deliverDirectory:(SeafDir *)dir
                  record:(SeafFPRecord *)record
               fromCache:(BOOL)fromCache
         requestStartSeq:(long long)requestStartSeq
               container:(NSFileProviderItemIdentifier)containerIdentifier
              completion:(SeafFPContainerCompletion)completion
{
    SeafFPStore *store = self.extension.store;
    NSString *repoId = dir.repoId;
    NSError *access = [self.extension accessError] ?: [self.extension repositoryAccessError:repoId];
    if (access) { completion(nil, access); return; }
    NSString *parentUUID = record.uuid;   // nil for the library root
    BOOL editable = [self.extension isRepoEditable:repoId];

    NSString *previousAnchor = [store anchorForContainer:containerIdentifier];
    NSSet<NSString *> *previous = [NSSet setWithArray:[store snapshotForContainer:containerIdentifier]];
    NSMutableDictionary<NSString *, SeafFPDecoration *> *decorations = [NSMutableDictionary dictionary];
    for (SeafFPDecoration *decoration in [store allDecorations]) {
        decorations[decoration.itemIdentifier] = decoration;
    }
    NSArray<SeafBase *> *entries = [dir.items copy];

    // The same store method as the main app's listings: cached listings only
    // admit unknown paths; fresh ones skip rows written after the request,
    // tombstone the rest of the vanished children as absent (a later rename
    // can bring them back) and confirm pending directory checks.
    NSMutableArray<NSDictionary *> *listing = [NSMutableArray arrayWithCapacity:entries.count];
    for (SeafBase *obj in entries) {
        NSString *name = obj.name ?: obj.path.lastPathComponent;
        if (name.length == 0) continue;
        BOOL isDir = [obj isKindOfClass:[SeafDir class]];
        NSMutableDictionary *entry = [@{
            SeafFPEntryName: name,
            SeafFPEntryIsDir: @(isDir),
            SeafFPEntryMtime: @(isDir ? ((SeafDir *)obj).mtime : ((SeafFile *)obj).mtime),
            SeafFPEntrySize: @(isDir ? -1 : (long long)((SeafFile *)obj).filesize),
        } mutableCopy];
        if (obj.oid.length > 0) entry[SeafFPEntryOid] = obj.oid;
        [listing addObject:entry];
    }
    SeafFPWriteResult result = [store applyDirectoryListingOfRepo:repoId directoryPath:dir.path entries:listing
                                                  requestStartSeq:(fromCache ? -1 : requestStartSeq)];
    // Not applied (busy, or the chain changed while the request was in
    // flight): answer from the store and keep the old anchor, like a cache hit,
    // so the next enumeration lists the directory again.
    if (!fromCache && result == SeafFPWriteFailed) fromCache = YES;

    NSMutableArray<SeafFPItem *> *items = [NSMutableArray array];
    NSMutableArray<SeafFPItem *> *updated = [NSMutableArray array];
    NSMutableDictionary<NSString *, SeafFPRecord *> *byPath = [NSMutableDictionary dictionary];
    for (SeafFPRecord *child in [store childRecordsOfRepo:repoId parentUUID:parentUUID]) {
        byPath[child.path] = child;
    }
    NSMutableArray<SeafFPRecord *> *children = [NSMutableArray arrayWithCapacity:byPath.count];
    for (SeafBase *obj in entries) {
        SeafFPRecord *child = byPath[[SeafFPIdentifier normalizedPath:obj.path]];
        if (!child) continue;
        [children addObject:child];
        [byPath removeObjectForKey:child.path];
    }
    // Live rows the listing did not show were written after the request.
    [children addObjectsFromArray:byPath.allValues];
    for (SeafFPRecord *child in children) {
        SeafFPItem *item = [SeafFPItem itemForRecord:child repoEditable:editable];
        [item applyDecoration:decorations[item.itemIdentifier]];
        [items addObject:item];
        // New to this listing, or its identity row changed since the request.
        if ((requestStartSeq >= 0 && child.seq > requestStartSeq) || ![previous containsObject:item.itemIdentifier]) {
            [updated addObject:item];
        }
    }

    NSString *anchor = dir.ooid.length > 0 ? dir.ooid : (dir.oid.length > 0 ? dir.oid : @"0");
    SeafFPContainerLoad *load = [SeafFPContainerLoad new];
    load.fromCache = fromCache;
    load.items = items;
    if (![store isOpen]) {
        completion(nil, [SeafFPErrors cannotSynchronize]);
        return;
    }
    access = [self.extension accessError] ?: [self.extension repositoryAccessError:repoId];
    if (access) { completion(nil, access); return; }
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
    NSMutableSet *ids = [NSMutableSet set];
    NSDictionary *states = [self.extension.store repositoryStates];
    for (NSString *repoId in states) {
        if ([states[repoId][@"availability"] isEqual:@"visible"]) [ids addObject:repoId];
    }
    return ids;
}

/// One page of the full working set enumeration. Everything the system has
/// learnt through this extension belongs to the working set
/// (NSFileProviderReplicatedExtension.h: an enumerated directory and its
/// children are part of it) and only working set items are indexed for
/// Spotlight, which is what the Tags list and, on iOS 26, the favorites
/// sidebar of Files are built from.
///
/// fileproviderd invalidates the enumerator after every page and asks for the
/// next one on a new enumerator, so each page is read on its own from the
/// position in its token (scan start, then the last row's place in the scan
/// order). Rows unchanged since the scan started keep their place and are
/// delivered exactly once, after their parents. A row written after the start
/// may move behind the position and be missed: the anchor of the scan is the
/// start, so the change enumeration that follows reports it.
- (void)enumerateWorkingSetPage:(NSFileProviderPage)page observer:(id<NSFileProviderEnumerationObserver>)observer
{
    SeafFPStore *store = self.extension.store;
    BOOL firstPage = page.length == 0 || [page isEqual:NSFileProviderInitialPageSortedByDate] || [page isEqual:NSFileProviderInitialPageSortedByName];
    NSDictionary *cursor = firstPage ? nil : SeafFPWorkingSetCursorFromToken(SeafFPAnchorString(page));
    if (!firstPage && !cursor) {
        [observer finishEnumeratingWithError:[SeafFPErrors pageExpired]];
        return;
    }
    if (firstPage) {
        [store applyRepositorySnapshot:[self.extension.connection.rootFolder fp_repositorySnapshot] complete:NO fromCache:YES requestStartSeq:-1];
    }
    SeafFPWorkingSetPage *batch = [store workingSetPageAfterDepth:[cursor[@"depth"] unsignedIntegerValue]
                                                            isDir:[cursor[@"isDir"] boolValue]
                                                              seq:[cursor[@"seq"] longLongValue]
                                                             uuid:cursor[@"uuid"]
                                                            limit:kSeafFPWorkingSetPageSize];
    if (!batch) {
        self.scanFailed = YES;
        [observer finishEnumeratingWithError:[SeafFPErrors cannotSynchronize]];
        return;
    }
    long long start = cursor ? [cursor[@"start"] longLongValue] : batch.sequence;
    if (start > batch.sequence) {
        // The store was rebuilt since the scan started: the position means nothing now.
        [observer finishEnumeratingWithError:[SeafFPErrors pageExpired]];
        return;
    }
    NSDictionary *states = batch.repositories;
    NSMutableArray<SeafFPItem *> *items = [NSMutableArray array];
    NSMutableSet<NSString *> *emitted = [NSMutableSet set];
    void (^emitLibrary)(NSString *) = ^(NSString *repoId) {
        SeafFPItem *item = [SeafFPItem itemForRepositoryMetadata:states[repoId]];
        [item applyDecoration:batch.decorations[item.itemIdentifier]];
        [items addObject:item];
        [emitted addObject:item.itemIdentifier];
    };
    void (^emitRecord)(SeafFPRecord *) = ^(SeafFPRecord *record) {
        SeafFPItem *item = [SeafFPItem itemForRecord:record repoEditable:[states[record.repoId][@"editable"] boolValue]];
        [item applyDecoration:batch.decorations[item.itemIdentifier]];
        [items addObject:item];
        [emitted addObject:item.itemIdentifier];
    };
    if (firstPage) {
        for (NSString *repoId in [states.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if ([states[repoId][@"availability"] isEqual:@"visible"]) emitLibrary(repoId);
        }
    }
    NSUInteger unplaced = 0;
    for (SeafFPRecord *record in batch.records) {
        NSDictionary *state = states[record.repoId];
        if (![state[@"availability"] isEqual:@"visible"]) continue;
        // A library whose state changed after the start may not have been
        // visible on the earlier pages: deliver it and the whole chain again.
        BOOL libraryChanged = [state[@"eventSeq"] longLongValue] > start;
        NSMutableArray<SeafFPRecord *> *chain = [NSMutableArray array];   // nearest parent first
        NSMutableSet<NSString *> *visited = [NSMutableSet setWithObject:record.uuid];
        BOOL placed = YES;
        for (NSString *parentUUID = record.parentUUID; parentUUID.length > 0; ) {
            SeafFPRecord *parent = batch.ancestors[parentUUID];
            if (!parent || parent.deleted || !parent.isDir || ![parent.repoId isEqual:record.repoId] || [visited containsObject:parent.uuid]) {
                placed = NO;
                break;
            }
            [visited addObject:parent.uuid];
            // A parent unchanged since the start sorts before its children
            // and went out on an earlier page or earlier on this one.
            if ((libraryChanged || parent.seq > start) && ![emitted containsObject:parent.itemIdentifier]) [chain addObject:parent];
            parentUUID = parent.parentUUID;
        }
        // The page and its ancestors come from one read, so a broken chain is
        // the store's state, not a race: the row has no place in the
        // hierarchy. Leaving it out keeps one bad row from failing the whole
        // scan on every retry; a write that fixes it is a change of its own.
        if (!placed) { unplaced++; continue; }
        if (libraryChanged && ![emitted containsObject:[SeafFPIdentifier identifierForRepo:record.repoId]]) emitLibrary(record.repoId);
        for (SeafFPRecord *parent in chain.reverseObjectEnumerator) emitRecord(parent);
        if (![emitted containsObject:record.itemIdentifier]) emitRecord(record);
    }
    if (unplaced) Warning("working set scan left out %lu rows without a parent chain", (unsigned long)unplaced);
    NSString *token = batch.moreComing ? SeafFPWorkingSetPageTokenForRecord(batch.records.lastObject, start) : nil;
    if (batch.moreComing && (!token || [token lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 500)) {
        [observer finishEnumeratingWithError:[SeafFPErrors pageExpired]];
        return;
    }
    self.scanStartSeq = start;
    self.scanFailed = NO;
    if (items.count) [observer didEnumerateItems:items];
    [observer finishEnumeratingUpToPage:token ? SeafFPAnchorData(token) : nil];
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
    [store applyRepositorySnapshot:[self.extension.connection.rootFolder fp_repositorySnapshot] complete:NO fromCache:YES requestStartSeq:-1];
    [store publishPendingRepositoryRecordsWithLimit:500];
    SeafFPPublicationBatch *waiting = [store publicationBatchAfterSequence:known limit:kSeafFPWorkingSetChangesPerPass];
    if (!waiting) { [observer finishEnumeratingWithError:[SeafFPErrors cannotSynchronize]]; return; }
    BOOL localChanges = waiting.records.count || waiting.repositoryEvents.count || waiting.decorationIdentifiers.count || [store hasPendingRepositoryPublications];
    NSDate *recheckAt = nil;
    // Already-committed metadata must reach the system without waiting for network IO.
    NSArray<NSString *> *containers = localChanges ? @[] : [self workingSetContainersToCheckRecheckAt:&recheckAt];
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
        [store publishPendingRepositoryRecordsWithLimit:500];
        SeafFPPublicationBatch *batch = [store publicationBatchAfterSequence:known limit:kSeafFPWorkingSetChangesPerPass];
        if (!batch) { [observer finishEnumeratingWithError:[SeafFPErrors cannotSynchronize]]; return; }
        long long cut = batch.sequence;
        BOOL moreComing = batch.moreComing || [store hasPendingRepositoryPublications];
        NSDictionary *states = batch.repositories;
        NSMutableSet *repoIds = [NSMutableSet set];
        for (NSString *repoId in states) if ([states[repoId][@"availability"] isEqual:@"visible"]) [repoIds addObject:repoId];
        NSMutableDictionary<NSString *, SeafFPRecord *> *liveRecordsByUUID = [NSMutableDictionary dictionary];
        __block BOOL readFailed = NO;
        __block NSUInteger unplaced = 0;
        // Adds the row and the ancestors not added yet; NO when the chain
        // breaks (a parent that is gone, a tombstone, a file, in another
        // library, or a cycle) and nothing was added. Such a row has no place
        // the system could put it, so it is left out instead of holding back
        // every other change: a write that fixes it is a change of its own.
        // A parent that could not be read is a failure of this pass.
        BOOL (^includeRecordAndAncestors)(SeafFPRecord *) = ^BOOL(SeafFPRecord *rec) {
            NSMutableArray<SeafFPRecord *> *chain = [NSMutableArray array];
            NSMutableSet *visited = [NSMutableSet set];
            for (SeafFPRecord *cur = rec; cur; ) {
                if ([visited containsObject:cur.uuid] || cur.deleted || ![repoIds containsObject:cur.repoId]) { unplaced++; return NO; }
                [visited addObject:cur.uuid];
                if (liveRecordsByUUID[cur.uuid]) break;
                [chain addObject:cur];
                if (cur.parentUUID.length == 0) break;
                BOOL failed = NO;
                SeafFPRecord *parent = [store recordForUUID:cur.parentUUID failed:&failed];
                if (failed) { readFailed = YES; return NO; }
                if (!parent || !parent.isDir || ![parent.repoId isEqual:rec.repoId]) { unplaced++; return NO; }
                cur = parent;
            }
            for (SeafFPRecord *r in chain) liveRecordsByUUID[r.uuid] = r;
            return YES;
        };
        for (NSString *identifier in [changes.updated.allKeys copy]) {
            if ([SeafFPIdentifier kindOfIdentifier:identifier] == SeafFPIdentifierKindItem) {
                SeafFPRecord *rec = [store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:identifier]];
                if (!rec || rec.deleted || ![repoIds containsObject:rec.repoId] || !includeRecordAndAncestors(rec)) {
                    [changes.updated removeObjectForKey:identifier];
                }
            }
        }
        for (NSDictionary *event in batch.repositoryEvents) {
            NSString *identifier = [SeafFPIdentifier identifierForRepo:event[@"repoId"]];
            if ([event[@"eventKind"] isEqual:@"delete"]) [changes addDeletedIdentifiers:@[identifier]];
            else if ([event[@"availability"] isEqual:@"visible"]) [changes addUpdatedItems:@[[strongSelf.extension itemForRepositoryState:event]]];
        }
        for (SeafFPRecord *record in batch.records) {
            if (record.deleted) { [changes addDeletedIdentifiers:@[record.itemIdentifier]]; continue; }
            if ([repoIds containsObject:record.repoId]) includeRecordAndAncestors(record);
        }
        for (NSString *identifier in batch.decorationIdentifiers) {
            if ([SeafFPIdentifier kindOfIdentifier:identifier] == SeafFPIdentifierKindItem) {
                SeafFPRecord *rec = [store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:identifier]];
                if (rec && !rec.deleted && [repoIds containsObject:rec.repoId]) includeRecordAndAncestors(rec);
            } else if ([SeafFPIdentifier kindOfIdentifier:identifier] == SeafFPIdentifierKindRepo) {
                NSDictionary *state = states[[SeafFPIdentifier repoIdFromIdentifier:identifier]];
                if ([state[@"availability"] isEqual:@"visible"]) [changes addUpdatedItems:@[[strongSelf.extension itemForRepositoryState:state]]];
            }
        }
        if (readFailed) { [observer finishEnumeratingWithError:[SeafFPErrors cannotSynchronize]]; return; }
        if (unplaced) Warning("working set changes left out %lu rows without a parent chain", (unsigned long)unplaced);
        for (SeafFPRecord *record in SeafFPSortRecordsParentFirst(liveRecordsByUUID.allValues)) {
            NSString *repoItemIdentifier = [SeafFPIdentifier identifierForRepo:record.repoId];
            NSDictionary *state = states[record.repoId];
            if (!changes.updated[repoItemIdentifier]) [changes addUpdatedItems:@[[strongSelf.extension itemForRepositoryState:state]]];
            SeafFPItem *item = [SeafFPItem itemForRecord:record repoEditable:[state[@"editable"] boolValue]];
            [item applyDecoration:batch.decorations[item.itemIdentifier]];
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
            completionHandler(self.scanFailed ? nil : SeafFPAnchorData([self workingSetAnchor]));
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
