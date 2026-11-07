//
//  SeafFPIndexer.m
//  seafile
//

#import "SeafFPIndexer.h"
#import <UIKit/UIKit.h>
#import <FileProvider/FileProvider.h>
#import <os/lock.h>
#import <stdatomic.h>
#import "SeafFPStore.h"
#import "SeafFPIdentifier.h"
#import "SeafConstants.h"
#import "SeafGlobal.h"
#import "SeafRepos.h"
#import "SeafDir.h"
#import "SeafFile.h"
#import "Utils.h"
#import "Debug.h"

static NSString * const kSeafFPIndexerEnabledKey = @"SeafFPIndexerEnabled";
static NSString * const kSeafFPActivityIndexEnabledKey = @"SeafFPActivityIndexEnabled";
/// An account's activity log is fetched in the background at most this often.
static const NSTimeInterval kSeafFPActivityFetchInterval = 15 * 60;
/// Gives the library list a moment to load after the app became active.
static const NSTimeInterval kSeafFPActivityFetchDelay = 3.0;
/// Wait before a library list is asked for again because its request seq was unknown.
static const NSTimeInterval kSeafFPRepoReloadDelay = 5.0;
/// Timestamps below this are not unix times (some search APIs send strings).
static const long long kSeafFPMinPlausibleMtime = 946684800;   // 2000-01-01

@interface SeafDir (SeafFPIndexingPrivate)
- (NSString *)url;
- (void)handleResponse:(NSHTTPURLResponse *)response json:(id)JSON;
- (nullable NSArray<NSDictionary *> *)fp_listingSnapshotForResponse:(id)JSON;
@end

@interface SeafFPIndexer ()
{
    dispatch_queue_t _workQueue;
    // Work queue only.
    NSMutableDictionary<NSString *, SeafFPStore *> *_stores;
    NSMutableArray<SeafConnection *> *_changedConnections;
    // Guarded by _lock (read from any thread, never waits on the work queue).
    os_unfair_lock _lock;
    NSMutableSet<NSString *> *_deactivatedDomains;
    NSMutableDictionary<NSString *, NSNumber *> *_domainGenerations;
    NSMutableDictionary<NSString *, NSNumber *> *_pendingMoveCounts;
    NSMutableDictionary<NSString *, NSMutableArray<dispatch_block_t> *> *_deferredDirWork;
    // Main thread only: when each account's activity log was last indexed.
    NSMutableDictionary<NSString *, NSDate *> *_activityFetchedAt;
    // Main thread only: accounts whose activity log is being read (last progress).
    NSMutableDictionary<NSString *, NSDictionary *> *_activitySyncs;
    // Main thread only: directory checks. Accounts whose due checks are being
    // read, "domain|repo|path" of listings in flight (until applied), how many
    // run, and the pending wake-up for deferred ones per account.
    NSMutableSet<NSString *> *_checkQueries;
    NSMutableSet<NSString *> *_checksInFlight;
    NSUInteger _checksRunning;
    NSMutableDictionary<NSString *, NSDate *> *_checkWakeups;
    NSHashTable<SeafConnection *> *_checkWaiting;   // accounts that found every listing slot taken
    // Main thread only: accounts whose library list was asked for again
    // because its request seq was unknown; asked once, not in a loop.
    NSMutableSet<NSString *> *_repoReloads;
    atomic_bool _expired;        // background time ran out: skip queued work
    atomic_bool _inBackground;   // signals must leave before suspension
    BOOL _started;
}
@end

@implementation SeafFPIndexer

+ (instancetype)shared
{
    static SeafFPIndexer *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SeafFPIndexer alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _workQueue = dispatch_queue_create("com.seafile.fpindexer",
                                           dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
        _stores = [NSMutableDictionary dictionary];
        _changedConnections = [NSMutableArray array];
        _lock = OS_UNFAIR_LOCK_INIT;
        _deactivatedDomains = [NSMutableSet set];
        _domainGenerations = [NSMutableDictionary dictionary];
        _pendingMoveCounts = [NSMutableDictionary dictionary];
        _deferredDirWork = [NSMutableDictionary dictionary];
        _activityFetchedAt = [NSMutableDictionary dictionary];
        _activitySyncs = [NSMutableDictionary dictionary];
        _checkQueries = [NSMutableSet set];
        _checksInFlight = [NSMutableSet set];
        _checkWakeups = [NSMutableDictionary dictionary];
        _repoReloads = [NSMutableSet set];
        _checkWaiting = [NSHashTable weakObjectsHashTable];
        atomic_init(&_expired, false);
        atomic_init(&_inBackground, false);
    }
    return self;
}

- (void)start
{
    if (![Utils isMainApp] || _started) return;
    _started = YES;
    SeafConnection.fileProviderIndexer = self;
    [SeafFileProviderDomainManager shared].domainObserver = self;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(appDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [nc addObserver:self selector:@selector(appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(fileProviderShouldSignal:) name:SeafFileProviderShouldSignalNotification object:nil];
    void (^readState)(void) = ^{
        atomic_store(&self->_inBackground, [UIApplication sharedApplication].applicationState == UIApplicationStateBackground);
    };
    if ([NSThread isMainThread]) readState(); else dispatch_async(dispatch_get_main_queue(), readState);
    Debug("Files app indexer started (enabled=%d)", self.enabled);
}

- (void)fileProviderShouldSignal:(NSNotification *)note
{
    SeafConnection *conn = [note.object isKindOfClass:[SeafConnection class]] ? note.object : nil;
    if (!conn) return;
    NSString *type = note.userInfo[SeafFileProviderSignalTypeKey];
    if ([type isEqualToString:SeafFileProviderSignalTypeRoot]) {
        if ([NSThread isMainThread]) {
            [self publishKnownMetadataForConnection:conn];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self publishKnownMetadataForConnection:conn];
            });
        }
    }
}

- (BOOL)isEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kSeafFPIndexerEnabledKey];
    return value == nil || [value boolValue];
}

- (void)appDidEnterBackground:(NSNotification *)note
{
    atomic_store(&_expired, false);
    atomic_store(&_inBackground, true);
}

- (void)appWillEnterForeground:(NSNotification *)note
{
    atomic_store(&_inBackground, false);
    atomic_store(&_expired, false);
}

- (BOOL)isActivityIndexEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kSeafFPActivityIndexEnabledKey];
    return value == nil || [value boolValue];
}

/// Launch and every return to the foreground: read the activity log of each
/// Pro account not read for a while, and go on with pending directory checks.
- (void)appDidBecomeActive:(NSNotification *)note
{
    atomic_store(&_inBackground, false);
    atomic_store(&_expired, false);
    for (SeafConnection *conn in [SeafGlobal.sharedObject.conns copy]) {
        [self publishKnownMetadataForConnection:conn];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSeafFPActivityFetchDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
        for (SeafConnection *conn in [SeafGlobal.sharedObject.conns copy]) {
            [self syncActivitiesForConnection:conn force:NO];
            [self runDirectoryChecksForConnection:conn];
        }
    });
}

- (void)publishKnownMetadataForConnection:(SeafConnection *)conn
{
    NSString *domainId = [self domainIdForConnection:conn repoId:nil];
    if (!domainId) return;
    if (conn.rootFolder.items == nil) [conn.rootFolder loadCache];
    [self fp_indexRepositorySnapshot:[conn.rootFolder fp_repositorySnapshot] connection:conn fromCache:YES requestStartSeq:-1];
    // The repository loader supplies a fresh, value-only snapshot on success.
    [conn.rootFolder loadContentSuccess:nil failure:nil];
}

- (BOOL)canIndexActivitiesOfConnection:(SeafConnection *)conn
{
    return self.activityIndexEnabled && conn.isActivityEnabled && conn.isNewActivitiesApiSupported
        && [self domainIdForConnection:conn repoId:nil] != nil;
}

#pragma mark - Admission

- (BOOL)isDomainDeactivated:(NSString *)domainId
{
    os_unfair_lock_lock(&_lock);
    BOOL deactivated = [_deactivatedDomains containsObject:domainId];
    os_unfair_lock_unlock(&_lock);
    return deactivated;
}

- (uint64_t)generationForDomainId:(NSString *)domainId
{
    if (domainId.length == 0) return 0;
    os_unfair_lock_lock(&_lock);
    uint64_t gen = [_domainGenerations[domainId] unsignedLongLongValue];
    os_unfair_lock_unlock(&_lock);
    return gen;
}

- (BOOL)isDomainActive:(NSString *)domainId generation:(uint64_t)generation
{
    if (domainId.length == 0) return NO;
    os_unfair_lock_lock(&_lock);
    BOOL active = ![_deactivatedDomains containsObject:domainId]
        && [_domainGenerations[domainId] unsignedLongLongValue] == generation;
    os_unfair_lock_unlock(&_lock);
    return active;
}

/// Checked on the calling thread (main thread / network callbacks, where the
/// account list and library list are maintained) before work is queued.
- (nullable NSString *)domainIdForConnection:(SeafConnection *)conn repoId:(nullable NSString *)repoId
{
    if (![Utils isMainApp] || !_started || !conn || !self.enabled) return nil;
    if (![SeafGlobal.sharedObject.conns containsObject:conn]) return nil;          // account still there
    if (!conn.authorized) return nil;                                              // signed in
    if (![SeafFileProviderDomainManager connectionWantsDomain:conn]) return nil;   // no Touch ID
    NSString *domainId = [SeafFileProviderDomainManager domainIdentifierForConnection:conn];
    if (domainId.length == 0 || [self isDomainDeactivated:domainId]) return nil;
    if (repoId.length > 0) {
        // Same rule as the extension's visible libraries. Explicit nil check:
        // !nil.passwordRequired would read as "no password needed".
        SeafRepo *repo = [conn getRepo:repoId];
        if (!repo || repo.passwordRequired) return nil;
    }
    return domainId;
}

/// Main thread. Libraries whose directories can be listed now: loaded and
/// not locked (the same rule as domainIdForConnection:repoId:).
- (NSArray<NSString *> *)indexableRepoIdsOfConnection:(SeafConnection *)conn
{
    NSMutableArray<NSString *> *repoIds = [NSMutableArray array];
    for (id item in [conn.rootFolder.items copy]) {
        if (![item isKindOfClass:[SeafRepo class]]) continue;
        SeafRepo *repo = item;
        if (repo.repoId.length > 0 && !repo.passwordRequired) [repoIds addObject:repo.repoId];
    }
    return repoIds;
}

#pragma mark - Work queue

/// Work queue only. nil once the domain was deactivated or indexing turned off.
- (nullable SeafFPStore *)storeForDomainId:(NSString *)domainId
{
    if (!self.enabled || [self isDomainDeactivated:domainId]) return nil;
    SeafFPStore *store = _stores[domainId];
    if (!store) {
        NSError *error = nil;
        store = [[SeafFPStore alloc] initWithDomainIdentifier:domainId error:&error];
        if (!store) {
            Warning("Files app indexer cannot open the store of %@: %@", domainId, error);
            return nil;
        }
        _stores[domainId] = store;
    }
    return store;
}

/// Work queue only: the account gets a working set signal when the current task ends.
- (void)noteChangedConnection:(SeafConnection *)conn
{
    if (conn && ![_changedConnections containsObject:conn]) [_changedConnections addObject:conn];
}

/// Runs `work` with the store of `domainId` on the work queue, under a
/// background task: the store only holds its sqlite file (and the -shm
/// lock) inside a request, and the app must not be suspended in one
/// (0xDEAD10CC). Each task is one store transaction, so an expiring
/// background task waits for one short transaction at most.
- (void)enqueueForDomainId:(NSString *)domainId work:(void (^)(SeafFPStore *store))work
{
    [self enqueueForDomainId:domainId work:work skipped:nil];
}

/// skipped (optional) runs instead of `work` when the domain went away or
/// background time ran out, so callers can release what they hold for it.
- (void)enqueueForDomainId:(NSString *)domainId work:(void (^)(SeafFPStore *store))work skipped:(nullable dispatch_block_t)skipped
{
    uint64_t generation = [self generationForDomainId:domainId];
    if (![self isDomainActive:domainId generation:generation]) {
        if (skipped) skipped();
        return;
    }
    UIApplication *app = [UIApplication sharedApplication];
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    NSObject *token = [NSObject new];
    void (^endTask)(void) = ^{
        UIBackgroundTaskIdentifier ending;
        @synchronized (token) {
            ending = task;
            task = UIBackgroundTaskInvalid;
        }
        if (ending != UIBackgroundTaskInvalid) [app endBackgroundTask:ending];
    };
    @synchronized (token) {
        task = [app beginBackgroundTaskWithName:@"SeafFPIndexer" expirationHandler:^{
            atomic_store(&self->_expired, true);
            endTask();
        }];
    }
    dispatch_async(_workQueue, ^{
        dispatch_group_t finishGroup = dispatch_group_create();
        void (^signalChanged)(NSArray<SeafConnection *> *) = ^(NSArray<SeafConnection *> *changed) {
            if (changed.count == 0) return;
            // The account list and the domain lookup behind a signal are
            // main-thread state; the background task waits for the hop.
            dispatch_group_enter(finishGroup);
            dispatch_async(dispatch_get_main_queue(), ^{
                SeafFileProviderDomainManager *domains = [SeafFileProviderDomainManager shared];
                for (SeafConnection *conn in changed) {
                    [domains signalWorkingSetForConnection:conn];
                }
                if (atomic_load(&self->_inBackground)) {
                    // The coalesced signal would fire after suspension (the flush in
                    // sceneDidEnterBackground ran before this write): send it now and
                    // keep the background task until the system answered.
                    [domains flushPendingSignalsWithCompletion:^{
                        dispatch_group_leave(finishGroup);
                    }];
                } else {
                    dispatch_group_leave(finishGroup);
                }
            });
        };
        BOOL ran = NO;
        if ((!atomic_load(&self->_expired) || !atomic_load(&self->_inBackground))
            && [self isDomainActive:domainId generation:generation]) {
            SeafFPStore *store = [self storeForDomainId:domainId];
            if (store) {
                ran = YES;
                work(store);
                NSArray<SeafConnection *> *changed = [self->_changedConnections copy];
                [self->_changedConnections removeAllObjects];
                signalChanged(changed);
                if ([store hasPendingRepositoryPublications] && changed.firstObject) {
                    SeafConnection *connection = changed.firstObject;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                        if (![self isDomainActive:domainId generation:generation]) return;
                        [self enqueueForDomainId:domainId work:^(SeafFPStore *nextStore) {
                            [nextStore publishPendingRepositoryRecordsWithLimit:500];
                            [self noteChangedConnection:connection];
                        }];
                    });
                }
            }
        }
        if (!ran && skipped) skipped();
        if (self->_changedConnections.count > 0) {
            NSArray<SeafConnection *> *changed = [self->_changedConnections copy];
            [self->_changedConnections removeAllObjects];
            signalChanged(changed);
        }
        dispatch_group_notify(finishGroup, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), endTask);
    });
}

#pragma mark - Entry helpers

/// Sparse entries grouped by library, dropping values that are not trustworthy.
static NSDictionary<NSString *, NSMutableArray<NSDictionary *> *> *SeafFPGroupSparseEntries(NSArray<NSDictionary *> *entries)
{
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *groups = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *repoId = entry[SeafFPIndexKeyRepoId];
        NSString *path = entry[SeafFPIndexKeyPath];
        if (![repoId isKindOfClass:[NSString class]] || repoId.length == 0) continue;
        if (![path isKindOfClass:[NSString class]] || path.length == 0 || [path isEqualToString:@"/"]) continue;
        NSMutableDictionary *clean = [NSMutableDictionary dictionaryWithCapacity:6];
        clean[SeafFPEntryPath] = path;
        clean[SeafFPEntryIsDir] = @([entry[SeafFPIndexKeyIsDir] boolValue]);
        NSString *oid = entry[SeafFPIndexKeyOid];
        if ([oid isKindOfClass:[NSString class]] && oid.length > 0) clean[SeafFPEntryOid] = oid;
        long long size = [entry[SeafFPIndexKeySize] isKindOfClass:[NSNumber class]] ? [entry[SeafFPIndexKeySize] longLongValue] : -1;
        if (size > 0) clean[SeafFPEntrySize] = @(size);     // 0 usually means "not sent"
        long long mtime = [entry[SeafFPIndexKeyMtime] isKindOfClass:[NSNumber class]] ? [entry[SeafFPIndexKeyMtime] longLongValue] : 0;
        if (mtime >= kSeafFPMinPlausibleMtime) clean[SeafFPEntryMtime] = @(mtime);
        NSMutableArray *group = groups[repoId];
        if (!group) groups[repoId] = group = [NSMutableArray array];
        [group addObject:clean];
    }
    return groups;
}

#pragma mark - SeafFPIndexingSink

- (void)fp_indexRepositorySnapshot:(NSArray<NSDictionary *> *)snapshot
                       connection:(SeafConnection *)conn
                        fromCache:(BOOL)fromCache
                  requestStartSeq:(long long)requestStartSeq
{
    NSString *domainId = [self domainIdForConnection:conn repoId:nil];
    if (!domainId) return;
    NSArray *values = [snapshot copy];
    [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
        BOOL changed = [store applyRepositorySnapshot:values complete:!fromCache fromCache:fromCache requestStartSeq:requestStartSeq];
        changed |= [store publishPendingRepositoryRecordsWithLimit:500];
        if (changed || [store pendingWorkingSetSignalTicket] > 0 || [store hasPendingRepositoryPublications]) [self noteChangedConnection:conn];
        // Libraries may have become listable (loaded, unlocked) or gone.
        if (!fromCache) [self runDirectoryChecksForConnection:conn];
        if (!fromCache) {
            uint64_t generation = [self generationForDomainId:domainId];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (requestStartSeq >= 0) { [self->_repoReloads removeObject:domainId]; return; }
                // The list was requested without a request seq (the store
                // could not be read then), so it could not settle freshness.
                // Ask once more, later; not again until a seq'd list arrived.
                if ([self->_repoReloads containsObject:domainId]) return;
                [self->_repoReloads addObject:domainId];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSeafFPRepoReloadDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if ([self isDomainActive:domainId generation:generation]) [conn.rootFolder loadContentSuccess:nil failure:nil];
                });
            });
        }
    }];
}

- (long long)fp_requestStartSeqForConnection:(SeafConnection *)conn
{
    NSString *domainId = [self domainIdForConnection:conn repoId:nil];
    if (!domainId) return -1;
    // Own read-only handle: never queued behind this class's write
    // transactions, never creates a store that was removed.
    return [SeafFPStore currentSeqForDomainIdentifier:domainId];
}

- (long long)fp_repositoryRequestStartSeqForConnection:(SeafConnection *)conn
{
    NSString *domainId = [self domainIdForConnection:conn repoId:nil];
    if (!domainId) return -1;
    SeafFPStore *store = [SeafFPStore openExistingStoreForDomainIdentifier:domainId];
    long long start = store ? [store beginRepositoryRequest] : -1;
    [store close];
    return start;
}

- (NSString *)moveKeyForDomainId:(NSString *)domainId repoId:(NSString *)repoId directoryPath:(NSString *)directoryPath
{
    NSString *normDir = [SeafFPIdentifier normalizedPath:directoryPath];
    return [NSString stringWithFormat:@"%@|%@|%@", domainId ?: @"", repoId ?: @"", normDir ?: @"/"];
}

- (void)beginPendingMoveForKey:(NSString *)moveKey
{
    if (moveKey.length == 0) return;
    os_unfair_lock_lock(&_lock);
    NSUInteger count = [_pendingMoveCounts[moveKey] unsignedIntegerValue];
    _pendingMoveCounts[moveKey] = @(count + 1);
    os_unfair_lock_unlock(&_lock);
}

- (void)finishPendingMoveForKey:(NSString *)moveKey
{
    if (moveKey.length == 0) return;
    NSArray<dispatch_block_t> *deferred = nil;
    os_unfair_lock_lock(&_lock);
    NSUInteger count = [_pendingMoveCounts[moveKey] unsignedIntegerValue];
    if (count <= 1) {
        [_pendingMoveCounts removeObjectForKey:moveKey];
        deferred = [_deferredDirWork[moveKey] copy];
        [_deferredDirWork removeObjectForKey:moveKey];
    } else {
        _pendingMoveCounts[moveKey] = @(count - 1);
    }
    os_unfair_lock_unlock(&_lock);
    for (dispatch_block_t block in deferred) {
        block();
    }
}

- (void)fp_indexListing:(NSArray<NSDictionary *> *)entries
                 ofRepo:(NSString *)repoId
              directory:(NSString *)directoryPath
             connection:(SeafConnection *)conn
        requestStartSeq:(long long)requestStartSeq
{
    NSString *domainId = [self domainIdForConnection:conn repoId:repoId];
    if (!domainId || directoryPath.length == 0) return;
    uint64_t generation = [self generationForDomainId:domainId];
    NSArray *snapshot = [entries copy];
    __weak typeof(self) weakSelf = self;
    __weak SeafConnection *weakConn = conn;
    NSString *moveKey = [self moveKeyForDomainId:domainId repoId:repoId directoryPath:directoryPath];
    BOOL defer = NO;
    os_unfair_lock_lock(&_lock);
    if ([_pendingMoveCounts[moveKey] unsignedIntegerValue] > 0) {
        defer = YES;
    }
    dispatch_block_t enqueueListing = ^{
        typeof(self) strongSelf = weakSelf;
        SeafConnection *strongConn = weakConn;
        if (!strongSelf || !strongConn || ![strongSelf isDomainActive:domainId generation:generation]) return;
        [strongSelf enqueueForDomainId:domainId work:^(SeafFPStore *store) {
            if (![strongSelf isDomainActive:domainId generation:generation]) return;
            SeafFPWriteResult result = [store applyDirectoryListingOfRepo:repoId directoryPath:directoryPath entries:snapshot requestStartSeq:requestStartSeq];
            if (result == SeafFPWriteChanged || requestStartSeq >= 0) {
                [strongSelf noteChangedConnection:strongConn];
            }
            // Not applied (busy, or the chain changed while the request was
            // in flight): the directory checks list it again, with backoff.
            if (result == SeafFPWriteFailed && requestStartSeq >= 0) {
                [store requestDirectoryCheckOfRepo:repoId path:directoryPath];
            }
            if (requestStartSeq >= 0) [strongSelf runDirectoryChecksForConnection:strongConn];
        }];
    };
    if (defer) {
        NSMutableArray<dispatch_block_t> *queue = _deferredDirWork[moveKey];
        if (!queue) _deferredDirWork[moveKey] = queue = [NSMutableArray array];
        [queue addObject:[enqueueListing copy]];
    }
    os_unfair_lock_unlock(&_lock);
    if (!defer) {
        enqueueListing();
    }
}

- (void)fp_indexSparseEntries:(NSArray<NSDictionary *> *)entries
                   connection:(SeafConnection *)conn
                  allowRevive:(BOOL)allowRevive
{
    if (![self domainIdForConnection:conn repoId:nil]) return;
    [SeafFPGroupSparseEntries(entries) enumerateKeysAndObjectsUsingBlock:^(NSString *repoId, NSMutableArray<NSDictionary *> *group, BOOL *stop) {
        NSString *domainId = [self domainIdForConnection:conn repoId:repoId];
        if (!domainId) return;
        [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
            if ([store applySparseEntriesOfRepo:repoId entries:group allowRevive:allowRevive]) {
                [self noteChangedConnection:conn];
            }
        }];
    }];
}

- (void)fp_indexStarredItems:(NSArray<NSDictionary *> *)items connection:(SeafConnection *)conn
{
    if (![self domainIdForConnection:conn repoId:nil]) return;
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:items.count];
    for (NSDictionary *info in items) {
        if (![info isKindOfClass:[NSDictionary class]]) continue;
        if ([info[@"deleted"] respondsToSelector:@selector(boolValue)] && [info[@"deleted"] boolValue]) continue;   // gone on the server
        NSString *repoId = info[@"repo_id"];
        NSString *path = info[@"path"];
        if (![repoId isKindOfClass:[NSString class]] || ![path isKindOfClass:[NSString class]]) continue;
        if (path.length == 0 || [path isEqualToString:@"/"]) continue;   // a starred library, not an item
        BOOL isDir = [info[@"is_dir"] respondsToSelector:@selector(boolValue)] && [info[@"is_dir"] boolValue];
        long long mtime = 0;
        id rawMtime = info[@"mtime"];
        if ([rawMtime isKindOfClass:[NSString class]]) {
            mtime = [Utils convertTimeStringToUTC:rawMtime];
        } else if ([rawMtime isKindOfClass:[NSNumber class]]) {
            mtime = [rawMtime longLongValue];
        }
        // No oid and no size in starred items: the stored values are kept.
        [entries addObject:@{SeafFPIndexKeyRepoId: repoId, SeafFPIndexKeyPath: path,
                             SeafFPIndexKeyIsDir: @(isDir), SeafFPIndexKeyMtime: @(mtime)}];
    }
    [self fp_indexSparseEntries:entries connection:conn allowRevive:NO];
}

- (void)fp_indexRenameOf:(NSString *)oldName
                      to:(NSString *)newName
                  ofRepo:(NSString *)repoId
               directory:(NSString *)directoryPath
                 listing:(NSArray<NSDictionary *> *)entries
              connection:(SeafConnection *)conn
         requestStartSeq:(long long)requestStartSeq
{
    NSString *domainId = [self domainIdForConnection:conn repoId:repoId];
    if (!domainId || directoryPath.length == 0) return;
    NSArray *snapshot = [entries copy];
    [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
        BOOL changed = [store renameRecordOfRepo:repoId
                                       directory:directoryPath
                                        fromName:oldName
                                          toName:newName
                                         listing:snapshot
                                 requestStartSeq:requestStartSeq];
        if (!changed && snapshot) {
            // The store did not know the entry: the listing brings in the new name.
            changed = [store applyListingOfRepo:repoId directoryPath:directoryPath entries:snapshot requestStartSeq:requestStartSeq];
        }
        if (!changed && (!snapshot || requestStartSeq < 0 || [store currentSeq] > requestStartSeq)) {
            [self fp_refreshDirectoryOfRepo:repoId path:directoryPath connection:conn];
        }
        if (changed) [self noteChangedConnection:conn];
    }];
}

- (void)fp_indexMoveOf:(NSArray<NSString *> *)names
              fromRepo:(NSString *)srcRepoId
         fromDirectory:(NSString *)srcDirectoryPath
                toRepo:(NSString *)dstRepoId
           toDirectory:(NSString *)dstDirectoryPath
         sourceListing:(NSArray<NSDictionary *> *)entries
            connection:(SeafConnection *)conn
       requestStartSeq:(long long)requestStartSeq
{
    NSString *srcDomainId = [self domainIdForConnection:conn repoId:srcRepoId];
    BOOL dstVisible = [self domainIdForConnection:conn repoId:dstRepoId] != nil;
    if (!srcDomainId) {
        // Source not indexable (locked library, say): the destination may still be.
        if (dstVisible) [self fp_refreshDirectoryOfRepo:dstRepoId path:dstDirectoryPath connection:conn];
        return;
    }
    uint64_t generation = [self generationForDomainId:srcDomainId];
    NSArray *namesCopy = [names copy];
    NSArray *snapshot = [entries copy];
    if (!dstVisible) {
        [self enqueueForDomainId:srcDomainId work:^(SeafFPStore *store) {
            if (![self isDomainActive:srcDomainId generation:generation]) return;
            BOOL changed = snapshot ? [store applyListingOfRepo:srcRepoId
                                                  directoryPath:srcDirectoryPath
                                                        entries:snapshot
                                                requestStartSeq:requestStartSeq] : NO;
            if (!changed && (!snapshot || requestStartSeq < 0 || [store currentSeq] > requestStartSeq)) {
                [self fp_refreshDirectoryOfRepo:srcRepoId path:srcDirectoryPath connection:conn];
            }
            if (changed) [self noteChangedConnection:conn];
        }];
        return;
    }

    // Fetch the destination directory listing first so moveRecordsOfRepo: can
    // confirm the actual server-assigned filenames (including conflict renames
    // such as "report (1).txt") before migrating any UUID. Concurrent source
    // and destination directory listings are deferred until the destination
    // check finishes so they cannot race against UUID migration.
    NSString *moveKey = [self moveKeyForDomainId:srcDomainId repoId:srcRepoId directoryPath:srcDirectoryPath];
    NSString *dstMoveKey = [self moveKeyForDomainId:srcDomainId repoId:dstRepoId directoryPath:dstDirectoryPath];
    BOOL hasDistinctDstKey = ![dstMoveKey isEqualToString:moveKey];
    [self beginPendingMoveForKey:moveKey];
    if (hasDistinctDstKey) [self beginPendingMoveForKey:dstMoveKey];
    NSString *dstName = [dstDirectoryPath isEqualToString:@"/"] ? @"" : dstDirectoryPath.lastPathComponent;
    SeafDir *dstDir = [[SeafDir alloc] initWithConnection:conn oid:nil repoId:dstRepoId perm:nil name:dstName path:dstDirectoryPath mtime:0];
    __weak typeof(self) weakSelf = self;
    __weak SeafConnection *weakConn = conn;
    [conn sendRequest:dstDir.url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        typeof(self) strongSelf = weakSelf;
        SeafConnection *strongConn = weakConn;
        if (!strongSelf || ![strongSelf isDomainActive:srcDomainId generation:generation]) {
            return;
        }
        if (!strongConn) {
            [strongSelf finishPendingMoveForKey:moveKey];
            if (hasDistinctDstKey) [strongSelf finishPendingMoveForKey:dstMoveKey];
            return;
        }
        [dstDir handleResponse:response json:JSON];
        NSArray<NSDictionary *> *dstSnapshot = [dstDir fp_listingSnapshotForResponse:JSON];
        [strongSelf enqueueForDomainId:srcDomainId work:^(SeafFPStore *store) {
            if (![strongSelf isDomainActive:srcDomainId generation:generation]) return;
            BOOL moved = NO;
            if (dstSnapshot) {
                moved = [store moveRecordsOfRepo:srcRepoId
                                   fromDirectory:srcDirectoryPath
                                           names:namesCopy
                                          toRepo:dstRepoId
                                     toDirectory:dstDirectoryPath
                              destinationEntries:dstSnapshot
                                 requestStartSeq:requestStartSeq];
            }
            if (moved) {
                if (snapshot) {
                    [store applyListingOfRepo:srcRepoId directoryPath:srcDirectoryPath entries:snapshot requestStartSeq:-1];
                }
                [strongSelf noteChangedConnection:strongConn];
                NSString *normSrcDir = [SeafFPIdentifier normalizedPath:srcDirectoryPath];
                for (NSString *name in namesCopy) {
                    if (name.length == 0 || [name containsString:@"/"]) continue;
                    NSString *srcPath = [SeafFPIdentifier normalizedPath:[normSrcDir stringByAppendingFormat:@"/%@", name]];
                    if ([store recordForRepo:srcRepoId path:srcPath includeDeleted:NO]) {
                        [strongSelf fp_refreshDirectoryOfRepo:srcRepoId path:srcDirectoryPath connection:strongConn];
                        break;
                    }
                }
                return;
            }
            BOOL srcApplied = snapshot ? [store applyListingOfRepo:srcRepoId
                                                     directoryPath:srcDirectoryPath
                                                           entries:snapshot
                                                   requestStartSeq:requestStartSeq] : NO;
            BOOL dstApplied = dstSnapshot ? [store applyListingOfRepo:dstRepoId
                                                        directoryPath:dstDirectoryPath
                                                              entries:dstSnapshot
                                                      requestStartSeq:requestStartSeq] : NO;
            if (srcApplied || dstApplied) {
                [strongSelf noteChangedConnection:strongConn];
            }
            BOOL seqAdvanced = (requestStartSeq < 0 || [store currentSeq] > requestStartSeq);
            if (!srcApplied && (!snapshot || seqAdvanced)) {
                [strongSelf fp_refreshDirectoryOfRepo:srcRepoId path:srcDirectoryPath connection:strongConn];
            }
            if (!dstApplied && (!dstSnapshot || seqAdvanced)) {
                [strongSelf fp_refreshDirectoryOfRepo:dstRepoId path:dstDirectoryPath connection:strongConn];
            }
        }];
        [strongSelf finishPendingMoveForKey:moveKey];
        if (hasDistinctDstKey) [strongSelf finishPendingMoveForKey:dstMoveKey];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        SeafConnection *strongConn = weakConn;
        if (!strongSelf || ![strongSelf isDomainActive:srcDomainId generation:generation]) {
            return;
        }
        if (!strongConn) {
            [strongSelf finishPendingMoveForKey:moveKey];
            if (hasDistinctDstKey) [strongSelf finishPendingMoveForKey:dstMoveKey];
            return;
        }
        [strongSelf enqueueForDomainId:srcDomainId work:^(SeafFPStore *store) {
            if (![strongSelf isDomainActive:srcDomainId generation:generation]) return;
            BOOL srcApplied = snapshot ? [store applyListingOfRepo:srcRepoId
                                                     directoryPath:srcDirectoryPath
                                                           entries:snapshot
                                                   requestStartSeq:requestStartSeq] : NO;
            if (srcApplied) [strongSelf noteChangedConnection:strongConn];
            if (!srcApplied && (!snapshot || requestStartSeq < 0 || [store currentSeq] > requestStartSeq)) {
                [strongSelf fp_refreshDirectoryOfRepo:srcRepoId path:srcDirectoryPath connection:strongConn];
            }
        }];
        [strongSelf finishPendingMoveForKey:moveKey];
        if (hasDistinctDstKey) [strongSelf finishPendingMoveForKey:dstMoveKey];
        [strongSelf fp_refreshDirectoryOfRepo:dstRepoId path:dstDirectoryPath connection:strongConn];
    }];
}

/// A persisted directory check: it survives the process, waits while the
/// library cannot be listed, and is listed once even when asked for often.
- (void)fp_refreshDirectoryOfRepo:(NSString *)repoId path:(NSString *)path connection:(SeafConnection *)conn
{
    if (![NSThread isMainThread]) {
        // Also reached from store work blocks; the account and library
        // checks below read main-thread state.
        __weak SeafConnection *weakConn = conn;
        dispatch_async(dispatch_get_main_queue(), ^{ [self fp_refreshDirectoryOfRepo:repoId path:path connection:weakConn]; });
        return;
    }
    NSString *domainId = [self domainIdForConnection:conn repoId:repoId];
    if (!domainId || path.length == 0) return;
    __weak SeafConnection *weakConn = conn;
    [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
        if ([store requestDirectoryCheckOfRepo:repoId path:path]) [self runDirectoryChecksForConnection:weakConn];
    }];
}

- (void)fp_noteDownloadedFileOfRepo:(NSString *)repoId
                               path:(NSString *)path
                                oid:(NSString *)oid
                               size:(long long)size
                         connection:(SeafConnection *)conn
{
    NSString *domainId = [self domainIdForConnection:conn repoId:repoId];
    if (!domainId || oid.length == 0) return;
    [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
        // Fill-in only, never a new row: a stored oid may be newer.
        if ([store noteLastUsedDate:nil forRepo:repoId path:path oid:oid size:size mtime:0 createIfMissing:NO]) {
            [self noteChangedConnection:conn];
        }
    }];
}

#pragma mark - Opened files

- (void)noteFileOpened:(SeafFile *)file
{
    if (![file isKindOfClass:[SeafFile class]]) return;
    SeafConnection *conn = file.connection;
    NSString *repoId = file.repoId;
    NSString *path = file.path;
    if (!conn || repoId.length == 0 || path.length == 0) return;
    NSString *domainId = [self domainIdForConnection:conn repoId:repoId];
    if (!domainId) return;
    NSDate *now = [NSDate date];
    NSString *oid = file.oid;
    long long size = (long long)file.filesize;
    long long mtime = file.mtime;
    [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
        if ([store noteLastUsedDate:now forRepo:repoId path:path oid:oid size:size mtime:mtime createIfMissing:YES]) {
            [self noteChangedConnection:conn];
        }
    }];
}

#pragma mark - Activity log

/// Pages one sync run reads before it pauses; it goes on 2 s later while the
/// app is active, so a long backlog never needs the user to come back.
static const NSUInteger kSeafFPActivityPagesPerRun = 20;
static const NSTimeInterval kSeafFPActivityContinueDelay = 2.0;
/// Activities this much older than the last boundary are read again: the
/// server writes the log asynchronously and can insert an event late.
static const long long kSeafFPActivityOverlap = 10 * 60;
/// The first sync of an account reads this far back at most.
static const long long kSeafFPActivityFirstSyncWindow = 7 * 24 * 3600;
/// The server's default page size, asked for explicitly: a short page ends a scan.
static const NSUInteger kSeafFPActivityPageSize = 25;
/// A sync that made no progress for this long is considered gone.
static const NSTimeInterval kSeafFPActivitySyncStale = 120;
/// Directory listings in flight at once, all accounts together.
static const NSUInteger kSeafFPCheckConcurrency = 2;
static const NSTimeInterval kSeafFPCheckRetryMin = 30;
static const NSTimeInterval kSeafFPCheckRetryMax = 6 * 3600;
/// A directory the server keeps refusing (403) is given up after this many tries.
static const NSInteger kSeafFPCheckMaxDenied = 8;

static NSString *SeafFPString(id value)
{
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? value : nil;
}

/// A fixed-format UTC formatter. Read-only after creation, so one instance is
/// shared across threads (NSDateFormatter is thread-safe for that use).
static NSDateFormatter *SeafFPFixedFormatter(NSString *format)
{
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = format;
    return formatter;
}

/// Activity times are ISO 8601 with an offset ("2024-05-01T10:00:00+08:00");
/// 0 when the text cannot be read.
static long long SeafFPEventTime(id value)
{
    NSString *text = SeafFPString(value);
    if (!text) return 0;
    static NSDateFormatter *plain;
    static NSISO8601DateFormatter *fractional;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        plain = SeafFPFixedFormatter(@"yyyy-MM-dd'T'HH:mm:ssXXXXX");
        fractional = [NSISO8601DateFormatter new];
        fractional.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    });
    NSDate *date = [plain dateFromString:text] ?: [fractional dateFromString:text];
    return (long long)date.timeIntervalSince1970;
}

/// One activity event as store entries. Field names checked against seahub
/// api2/endpoints/activities.py and seafevents events/handlers.py: path is the
/// path after the operation, old_path the one before a move / rename (same
/// library: moves across libraries are logged as delete + create), details
/// (14.0+) the items of a batch.
static NSArray<NSDictionary *> *SeafFPActivityEntries(NSDictionary *event)
{
    NSString *op = SeafFPString(event[@"op_type"]);
    NSString *objType = SeafFPString(event[@"obj_type"]);
    NSString *path = SeafFPString(event[@"path"]);
    NSString *name = SeafFPString(event[@"name"]) ?: path.lastPathComponent;
    if (!op || !objType || [objType isEqualToString:@"repo"] || [op isEqualToString:@"clean-up-trash"]) return @[];
    if (![op isEqualToString:@"publish"] && ([objType containsString:@"draft"] || [name hasSuffix:@"(draft).md"])) return @[];
    BOOL isDir = [objType isEqualToString:@"dir"];
    long long eventTime = SeafFPEventTime(event[@"time"]);

    NSString *storeOp = nil;
    if ([@[@"edit", @"update"] containsObject:op]) {
        storeOp = SeafFPActivityOpEdit;
    } else if ([@[@"create", @"recover", @"restore", @"publish"] containsObject:op]) {
        storeOp = SeafFPActivityOpCreate;
    } else if ([op isEqualToString:@"delete"]) {
        storeOp = SeafFPActivityOpDelete;
    } else if ([op isEqualToString:@"rename"] || [op isEqualToString:@"move"]) {
        storeOp = SeafFPActivityOpMove;
    } else if ([op isEqualToString:@"batch_create"] || [op isEqualToString:@"batch_delete"]) {
        NSString *itemOp = [op isEqualToString:@"batch_create"] ? SeafFPActivityOpCreate : SeafFPActivityOpDelete;
        NSArray *details = [event[@"details"] isKindOfClass:[NSArray class]] ? event[@"details"] : nil;
        NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
        for (NSDictionary *detail in details) {
            if (![detail isKindOfClass:[NSDictionary class]]) continue;
            NSString *itemPath = SeafFPString(detail[@"path"]);
            if (!itemPath || [itemPath isEqualToString:@"/"]) continue;
            [entries addObject:@{SeafFPEntryOp: itemOp, SeafFPEntryPath: itemPath,
                                 SeafFPEntryIsDir: @(isDir), SeafFPEntryMtime: @(eventTime)}];
        }
        if (entries.count == 0 && path && ![path isEqualToString:@"/"]) {
            [entries addObject:@{SeafFPEntryOp: itemOp, SeafFPEntryPath: path,
                                 SeafFPEntryIsDir: @(isDir), SeafFPEntryMtime: @(eventTime)}];
        }
        return entries;
    }
    if (!storeOp || !path || [path isEqualToString:@"/"]) return @[];
    NSMutableDictionary *entry = [@{SeafFPEntryOp: storeOp, SeafFPEntryPath: path,
                                    SeafFPEntryIsDir: @(isDir), SeafFPEntryMtime: @(eventTime)} mutableCopy];
    if ([storeOp isEqualToString:SeafFPActivityOpMove]) {
        NSString *oldPath = SeafFPString(event[@"old_path"]);
        if (!oldPath && [op isEqualToString:@"rename"]) {
            NSString *oldName = SeafFPString(isDir ? event[@"old_dir_name"] : event[@"old_name"]) ?: SeafFPString(event[@"old_name"]);
            if (oldName && ![oldName containsString:@"/"]) {
                oldPath = [path.stringByDeletingLastPathComponent stringByAppendingPathComponent:oldName];
            }
        }
        if (oldPath) entry[SeafFPEntryOldPath] = oldPath;   // without it: a create of the new path
    }
    return @[entry];
}

/// Identifies an activity by what it says about the files. The server rewrites
/// an aggregated activity (more items, a later time) in place: that version
/// counts as new. Display fields (avatar, nick name) do not count.
static NSString *SeafFPActivityHash(NSDictionary *event)
{
    NSMutableDictionary *semantic = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"repo_id", @"commit_id", @"op_type", @"obj_type", @"path", @"old_path", @"name", @"old_name", @"old_dir_name"]) {
        id value = event[key];
        if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) semantic[key] = value;
    }
    semantic[@"time"] = @(SeafFPEventTime(event[@"time"]));
    if ([event[@"details"] isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSDictionary *> *details = [NSMutableArray array];
        for (id detail in event[@"details"]) {
            if ([detail isKindOfClass:[NSDictionary class]] && [NSJSONSerialization isValidJSONObject:detail]) [details addObject:detail];
        }
        [details sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [(SeafFPString(a[@"path"]) ?: @"") compare:(SeafFPString(b[@"path"]) ?: @"")];
        }];
        semantic[@"details"] = details;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:semantic options:NSJSONWritingSortedKeys error:nil];
    return data ? [SeafFPIdentifier sha1Hex:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]] : nil;
}

static NSArray<NSString *> *SeafFPActivityFingerprints(NSArray *events)
{
    NSMutableArray<NSString *> *fingerprints = [NSMutableArray arrayWithCapacity:events.count];
    for (id event in events) {
        [fingerprints addObject:([event isKindOfClass:[NSDictionary class]] ? SeafFPActivityHash(event) : nil) ?: @""];
    }
    return fingerprints;
}

/// The entries of a page, each tagged with its library and activity.
static NSArray<NSDictionary *> *SeafFPActivityPageEntries(NSArray *events, NSArray<NSString *> *fingerprints)
{
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (NSUInteger i = 0; i < events.count; i++) {
        NSDictionary *event = events[i];
        if (![event isKindOfClass:[NSDictionary class]]) continue;
        NSString *repoId = SeafFPString(event[@"repo_id"]);
        NSString *hash = fingerprints[i];
        if (!repoId || hash.length == 0) continue;
        for (NSDictionary *entry in SeafFPActivityEntries(event)) {
            NSMutableDictionary *tagged = [entry mutableCopy];
            tagged[SeafFPEntryRepoId] = repoId;
            tagged[SeafFPEntryActivityHash] = hash;
            [entries addObject:tagged];
        }
    }
    return entries;
}

/// Server time of a response (its Date header); 0 when it has none.
static long long SeafFPResponseTime(NSHTTPURLResponse *response)
{
    NSString *date = [response isKindOfClass:[NSHTTPURLResponse class]] ? response.allHeaderFields[@"Date"] : nil;
    if (date.length == 0) return 0;
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ formatter = SeafFPFixedFormatter(@"EEE, dd MMM yyyy HH:mm:ss zzz"); });
    return (long long)[[formatter dateFromString:date] timeIntervalSince1970];
}

/// Everything a page contributes, computed once off the main thread: the
/// hashes of its activities, the store entries, and the newest / oldest
/// readable event time (0 when none of them can be read).
static NSString *const SeafFPPageFingerprints = @"fingerprints";
static NSString *const SeafFPPageEntries = @"entries";
static NSString *const SeafFPPageNewest = @"newest";
static NSString *const SeafFPPageOldest = @"oldest";
static NSString *const SeafFPPageCount = @"count";

static NSDictionary *SeafFPActivityPageDigest(NSArray *events)
{
    NSArray<NSString *> *fingerprints = SeafFPActivityFingerprints(events);
    long long newest = 0, oldest = LLONG_MAX;
    for (NSDictionary *event in events) {
        long long time = [event isKindOfClass:[NSDictionary class]] ? SeafFPEventTime(event[@"time"]) : 0;
        if (time <= 0) continue;
        if (newest == 0) newest = time;
        oldest = MIN(oldest, time);
    }
    if (oldest == LLONG_MAX) oldest = 0;
    return @{SeafFPPageFingerprints: fingerprints,
             SeafFPPageEntries: SeafFPActivityPageEntries(events, fingerprints),
             SeafFPPageNewest: @(newest),
             SeafFPPageOldest: @(oldest),
             SeafFPPageCount: @(events.count)};
}

/// Work queue. The entries of a locked library the store never indexed are
/// dropped: its plain paths have no business in the shared store. One that
/// was indexed before keeps them, so its checks catch up once it is unlocked.
static NSArray<NSDictionary *> *SeafFPEntriesWithoutUnindexedLockedRepos(NSArray<NSDictionary *> *entries,
                                                                          NSSet<NSString *> *locked,
                                                                          SeafFPStore *store)
{
    if (locked.count == 0) return entries;
    NSMutableDictionary<NSString *, NSNumber *> *indexed = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary *> *kept = [NSMutableArray arrayWithCapacity:entries.count];
    for (NSDictionary *entry in entries) {
        NSString *repoId = entry[SeafFPEntryRepoId];
        if ([locked containsObject:repoId]) {
            NSNumber *has = indexed[repoId];
            if (!has) {
                has = @([store childRecordsOfRepo:repoId parentUUID:nil].count > 0);
                indexed[repoId] = has;
            }
            if (!has.boolValue) continue;
        }
        [kept addObject:entry];
    }
    return kept;
}

/// Main thread. Reads the activity log back to the boundary of the last
/// complete scan, one page per store transaction; the store keeps the
/// position, so a scan interrupted by the app going away continues where it
/// stopped. force: also when the log was read recently (the activity list
/// was refreshed, or a paused scan goes on).
- (void)syncActivitiesForConnection:(SeafConnection *)conn force:(BOOL)force
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self syncActivitiesForConnection:conn force:force]; });
        return;
    }
    if (![self canIndexActivitiesOfConnection:conn]) return;
    NSString *domainId = [SeafFileProviderDomainManager domainIdentifierForConnection:conn];
    uint64_t generation = [self generationForDomainId:domainId];
    if (![self isDomainActive:domainId generation:generation]) return;
    NSDictionary *running;
    @synchronized (_activitySyncs) { running = _activitySyncs[domainId]; }
    if (running && -[running[@"at"] timeIntervalSinceNow] < kSeafFPActivitySyncStale) return;   // one sync per account
    __weak SeafConnection *weakConn = conn;
    NSDate *last = _activityFetchedAt[domainId];
    if (!force && last && -[last timeIntervalSinceNow] < kSeafFPActivityFetchInterval) {
        // Read recently, but a scan paused for its page budget (the app left
        // before it went on) continues right away.
        [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
            if (![store activityProgress][@"scanTop"]) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                SeafConnection *strongConn = weakConn;
                if (strongConn) [self syncActivitiesForConnection:strongConn force:YES];
            });
        }];
        return;
    }
    // A run older than kSeafFPActivitySyncStale is replaced; its callbacks
    // see another token and stop without writing.
    NSString *token = [NSUUID UUID].UUIDString;
    @synchronized (_activitySyncs) { _activitySyncs[domainId] = @{@"token": token, @"at": [NSDate date]}; }
    _activityFetchedAt[domainId] = [NSDate date];
    [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
        NSDictionary *progress = [store activityProgress];
        dispatch_async(dispatch_get_main_queue(), ^{
            SeafConnection *strongConn = weakConn;
            if (![self isActivityRun:token currentOfDomain:domainId]) return;
            if (!progress || !strongConn || ![self isDomainActive:domainId generation:generation]) {
                [self endActivityRun:token ofDomain:domainId retry:YES];
                return;
            }
            NSUInteger nextPage = [progress[@"nextPage"] unsignedIntegerValue];
            if (progress[@"scanTop"] && nextPage > 1) {
                [self fetchVerifiedActivityPage:nextPage progress:progress run:0 token:token connection:strongConn
                                          domain:domainId generation:generation];
            } else {
                [self fetchActivityPage:1 back:0 progress:progress run:0 token:token connection:strongConn
                                  domain:domainId generation:generation];
            }
        });
    } skipped:^{
        dispatch_async(dispatch_get_main_queue(), ^{ [self endActivityRun:token ofDomain:domainId retry:YES]; });
    }];
}

/// Any thread. YES while `token` is the account's running sync.
- (BOOL)isActivityRun:(NSString *)token currentOfDomain:(NSString *)domainId
{
    @synchronized (_activitySyncs) {
        NSDictionary *run = _activitySyncs[domainId];
        if (![run[@"token"] isEqual:token]) return NO;
        _activitySyncs[domainId] = @{@"token": token, @"at": [NSDate date]};   // still making progress
        return YES;
    }
}

/// Main thread.
- (void)endActivityRun:(NSString *)token ofDomain:(NSString *)domainId retry:(BOOL)retry
{
    @synchronized (_activitySyncs) {
        if (![_activitySyncs[domainId][@"token"] isEqual:token]) return;   // a newer run owns the account
        [_activitySyncs removeObjectForKey:domainId];
    }
    if (retry) [_activityFetchedAt removeObjectForKey:domainId];   // try again next time the app is active
}

- (void)requestActivityPage:(NSUInteger)page
                      token:(NSString *)token
                 connection:(SeafConnection *)conn
                     domain:(NSString *)domainId
                 generation:(uint64_t)generation
                 completion:(void (^)(NSArray *, NSHTTPURLResponse *, SeafConnection *))completion
{
    if (![self isActivityRun:token currentOfDomain:domainId]) return;
    NSString *url = [NSString stringWithFormat:API_URL_V21"/activities/?page=%lu&per_page=%lu", (unsigned long)page, (unsigned long)kSeafFPActivityPageSize];
    __weak SeafConnection *weakConn = conn;
    [conn sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self isDomainActive:domainId generation:generation] || ![self isActivityRun:token currentOfDomain:domainId]) return;
            SeafConnection *strongConn = weakConn;
            NSArray *events = [JSON isKindOfClass:[NSDictionary class]] ? JSON[@"events"] : nil;
            if (!strongConn || ![events isKindOfClass:[NSArray class]]) {
                [self endActivityRun:token ofDomain:domainId retry:YES];
                return;
            }
            completion(events, response, strongConn);
        });
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        Debug("activity fetch for the Files index failed: %@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self isDomainActive:domainId generation:generation]) [self endActivityRun:token ofDomain:domainId retry:YES];
        });
    }];
}

/// Main thread. Encrypted libraries that are not unlocked right now.
- (NSSet<NSString *> *)lockedRepoIdsOfConnection:(SeafConnection *)conn
{
    NSMutableSet<NSString *> *locked = [NSMutableSet set];
    for (id item in [conn.rootFolder.items copy]) {
        if (![item isKindOfClass:[SeafRepo class]]) continue;
        SeafRepo *repo = item;
        if (repo.repoId.length > 0 && repo.passwordRequired) [locked addObject:repo.repoId];
    }
    return locked;
}

/// Hashes a page off the main thread and continues on it with the digest,
/// unless the run or the domain ended meanwhile.
- (void)digestActivityPage:(NSArray *)events
                     token:(NSString *)token
                    domain:(NSString *)domainId
                generation:(uint64_t)generation
                completion:(void (^)(NSDictionary *digest))completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *digest = SeafFPActivityPageDigest(events);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self isDomainActive:domainId generation:generation] || ![self isActivityRun:token currentOfDomain:domainId]) return;
            completion(digest);
        });
    });
}

/// Fetch the candidate before checking the preceding page. If the offset
/// shifted before the candidate arrived, the later probe will detect it.
- (void)fetchVerifiedActivityPage:(NSUInteger)page
                        progress:(NSDictionary *)progress
                             run:(NSUInteger)run
                           token:(NSString *)token
                      connection:(SeafConnection *)conn
                          domain:(NSString *)domainId
                      generation:(uint64_t)generation
{
    [self requestActivityPage:page token:token connection:conn domain:domainId generation:generation
                    completion:^(NSArray *events, NSHTTPURLResponse *response, SeafConnection *connection) {
        [self requestActivityPage:page - 1 token:token connection:connection domain:domainId generation:generation
                        completion:^(NSArray *previous, NSHTTPURLResponse *probeResponse, SeafConnection *current) {
            [self digestActivityPage:previous token:token domain:domainId generation:generation completion:^(NSDictionary *previousDigest) {
                NSArray *saved = progress[@"lastPage"];
                if (saved && [saved isEqual:previousDigest[SeafFPPageFingerprints]]) {
                    [self digestActivityPage:events token:token domain:domainId generation:generation completion:^(NSDictionary *digest) {
                        [self handleActivityPage:digest page:page back:0 response:response progress:progress run:run
                                           token:token connection:current domain:domainId generation:generation];
                    }];
                } else {
                    [self handleActivityPage:previousDigest page:page - 1 back:1 response:probeResponse progress:progress run:run
                                       token:token connection:current domain:domainId generation:generation];
                }
            }];
        }];
    }];
}

/// Main thread. A nonzero `back` is a probe before a paused scan's next page.
- (void)fetchActivityPage:(NSUInteger)page
                     back:(NSUInteger)back
                 progress:(NSDictionary *)progress
                      run:(NSUInteger)run
                    token:(NSString *)token
               connection:(SeafConnection *)conn
                   domain:(NSString *)domainId
               generation:(uint64_t)generation
{
    [self requestActivityPage:page token:token connection:conn domain:domainId generation:generation
                    completion:^(NSArray *events, NSHTTPURLResponse *response, SeafConnection *connection) {
        [self digestActivityPage:events token:token domain:domainId generation:generation completion:^(NSDictionary *digest) {
            [self handleActivityPage:digest page:page back:back response:response progress:progress run:run
                               token:token connection:connection domain:domainId generation:generation];
        }];
    }];
}

/// Main thread, with the page's digest. Resume by checking the last
/// committed page. If it shifted, replay from a page that overlaps the saved
/// one or starts earlier in the scan order. Probe requests do not spend the
/// forward page budget.
- (void)handleActivityPage:(NSDictionary *)digest
                      page:(NSUInteger)page
                      back:(NSUInteger)back
                  response:(NSHTTPURLResponse *)response
                  progress:(NSDictionary *)progress
                       run:(NSUInteger)run
                     token:(NSString *)token
                connection:(SeafConnection *)conn
                    domain:(NSString *)domainId
                generation:(uint64_t)generation
{
    NSArray<NSString *> *fingerprints = digest[SeafFPPageFingerprints];
    NSUInteger count = [digest[SeafFPPageCount] unsignedIntegerValue];
    long long newest = [digest[SeafFPPageNewest] longLongValue];
    long long oldest = [digest[SeafFPPageOldest] longLongValue];
    if (count >= kSeafFPActivityPageSize && newest == 0) {
        // An unreadable full page cannot establish that the scan reached its
        // boundary. Keep the last committed position and retry later, rather
        // than acknowledge activities on pages we have not collected.
        [self endActivityRun:token ofDomain:domainId retry:YES];
        return;
    }
    BOOL resuming = progress[@"scanTop"] != nil;
    if (back > 0) {
        NSArray *saved = progress[@"lastPage"];
        NSMutableSet *overlap = [NSMutableSet setWithArray:fingerprints];
        [overlap removeObject:@""];
        if (page > 1 && newest <= [progress[@"lastTime"] longLongValue]
            && ![overlap intersectsSet:[NSSet setWithArray:saved ?: @[]]]) {
            NSUInteger resumePage = [progress[@"nextPage"] unsignedIntegerValue];
            NSUInteger step = back >= resumePage / 2 ? resumePage : back * 2;
            [self fetchActivityPage:(resumePage > step ? resumePage - step : 1) back:step progress:progress run:run
                              token:token connection:conn domain:domainId generation:generation];
            return;
        }
    }

    NSMutableDictionary *next = [progress mutableCopy];
    if (!resuming) {
        next[@"scanTop"] = @(newest > 0 ? newest : SeafFPResponseTime(response));
    }
    BOOL hasBoundary = progress[@"boundary"] != nil;
    long long boundary = [progress[@"boundary"] longLongValue];
    long long now = SeafFPResponseTime(response) ?: (long long)[NSDate date].timeIntervalSince1970;
    BOOL done = count < kSeafFPActivityPageSize
        || (hasBoundary && oldest > 0 && oldest < boundary - kSeafFPActivityOverlap)
        || (!hasBoundary && oldest > 0 && oldest < now - kSeafFPActivityFirstSyncWindow);
    if (done) {
        long long top = [next[@"scanTop"] longLongValue];
        // An empty log: start from the server's present (or an hour back).
        if (top <= 0) top = SeafFPResponseTime(response) ?: (long long)[NSDate date].timeIntervalSince1970 - 3600;
        next = [@{@"boundary": @(top)} mutableCopy];
    } else {
        next[@"nextPage"] = @(page + 1);
        next[@"lastPage"] = fingerprints;
        if (oldest > 0) next[@"lastTime"] = @(oldest);
    }
    NSArray<NSDictionary *> *entries = digest[SeafFPPageEntries];
    NSSet<NSString *> *locked = [self lockedRepoIdsOfConnection:conn];
    NSDictionary *stored = [next copy];
    __weak SeafConnection *weakConn = conn;
    [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
        // A replaced run must not write its older position over the new one.
        if (![self isActivityRun:token currentOfDomain:domainId]) return;
        SeafFPWriteResult result = [store recordActivityEntries:SeafFPEntriesWithoutUnindexedLockedRepos(entries, locked, store)
                                                       progress:stored];
        if (result != SeafFPWriteFailed && done) {
            // The scan reached the boundary: every rename it found can be
            // decided in order now (and expired verifications are dropped).
            NSUInteger round = 0;
            do {
                SeafFPWriteResult decided = [store decideRenameHintsWithLimit:100];
                if (decided == SeafFPWriteFailed) break;
                if (decided == SeafFPWriteChanged) [self noteChangedConnection:weakConn];
            } while (++round < 50 && [store pendingRenameHintCount] > 0);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            SeafConnection *strongConn = weakConn;
            if (![self isDomainActive:domainId generation:generation] || ![self isActivityRun:token currentOfDomain:domainId]) return;
            if (result == SeafFPWriteFailed || !strongConn) {
                [self endActivityRun:token ofDomain:domainId retry:YES];
                return;
            }
            [self runDirectoryChecksForConnection:strongConn];
            if (done) {
                [self endActivityRun:token ofDomain:domainId retry:NO];
            } else if (run + 1 >= kSeafFPActivityPagesPerRun) {
                [self endActivityRun:token ofDomain:domainId retry:NO];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSeafFPActivityContinueDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    SeafConnection *later = weakConn;
                    if (later && [UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
                        [self syncActivitiesForConnection:later force:YES];
                    }
                });
            } else {
                [self fetchVerifiedActivityPage:page + 1 progress:stored run:run + 1 token:token
                                     connection:strongConn domain:domainId generation:generation];
            }
        });
    } skipped:^{
        dispatch_async(dispatch_get_main_queue(), ^{ [self endActivityRun:token ofDomain:domainId retry:YES]; });
    }];
}

#pragma mark - Directory checks

/// Main thread. Starts listings for the account's due directory checks
/// (registered by the activity log, rename decisions and refresh requests).
- (void)runDirectoryChecksForConnection:(SeafConnection *)conn
{
    if (!conn) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self runDirectoryChecksForConnection:conn]; });
        return;
    }
    NSString *domainId = [self domainIdForConnection:conn repoId:nil];
    if (!domainId || [_checkQueries containsObject:domainId]) return;
    if (_checksRunning >= kSeafFPCheckConcurrency) {
        [_checkWaiting addObject:conn];   // runs when any listing finishes, whichever account
        return;
    }
    uint64_t generation = [self generationForDomainId:domainId];
    // Only libraries that can be listed now (loaded, not locked): the others
    // keep their checks without taking the places of these.
    NSArray<NSString *> *repoIds = [self indexableRepoIdsOfConnection:conn];
    [_checkQueries addObject:domainId];
    __weak SeafConnection *weakConn = conn;
    [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
        NSArray<SeafFPDirectoryCheck *> *due = [store dueDirectoryChecksAt:[NSDate date] limit:16 repoIds:repoIds];
        NSDate *later = due.count == 0 ? [store nextDirectoryCheckDateOfRepos:repoIds] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_checkQueries removeObject:domainId];
            SeafConnection *strongConn = weakConn;
            if (!strongConn || ![self isDomainActive:domainId generation:generation]) return;
            [self startDirectoryChecks:due connection:strongConn domain:domainId generation:generation];
            if (later) [self runDirectoryChecksForConnection:strongConn at:later];
        });
    } skipped:^{
        dispatch_async(dispatch_get_main_queue(), ^{ [self->_checkQueries removeObject:domainId]; });
    }];
}

/// Main thread. One wake-up per account for the earliest deferred check.
- (void)runDirectoryChecksForConnection:(SeafConnection *)conn at:(NSDate *)date
{
    NSString *domainId = [SeafFileProviderDomainManager domainIdentifierForConnection:conn];
    NSDate *scheduled = _checkWakeups[domainId];
    if (scheduled && [scheduled compare:date] != NSOrderedDescending) return;
    _checkWakeups[domainId] = date;
    __weak SeafConnection *weakConn = conn;
    NSTimeInterval delay = MAX(1.0, [date timeIntervalSinceNow]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_checkWakeups[domainId] != date) return;   // superseded by an earlier one
        [self->_checkWakeups removeObjectForKey:domainId];
        [self runDirectoryChecksForConnection:weakConn];
    });
}

/// Main thread. Libraries take turns, so one big backlog does not starve the others.
- (void)startDirectoryChecks:(NSArray<SeafFPDirectoryCheck *> *)due
                  connection:(SeafConnection *)conn
                      domain:(NSString *)domainId
                  generation:(uint64_t)generation
{
    NSMutableArray<NSString *> *repoOrder = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<SeafFPDirectoryCheck *> *> *byRepo = [NSMutableDictionary dictionary];
    for (SeafFPDirectoryCheck *check in due) {
        if (!byRepo[check.repoId]) { byRepo[check.repoId] = [NSMutableArray array]; [repoOrder addObject:check.repoId]; }
        [byRepo[check.repoId] addObject:check];
    }
    BOOL progress = YES;
    while (_checksRunning < kSeafFPCheckConcurrency && progress) {
        progress = NO;
        for (NSString *repoId in repoOrder) {
            if (_checksRunning >= kSeafFPCheckConcurrency) break;
            NSMutableArray<SeafFPDirectoryCheck *> *queue = byRepo[repoId];
            // Locked or not loaded yet: it stays pending until the library can be listed.
            if (queue.count == 0 || ![self domainIdForConnection:conn repoId:repoId]) continue;
            SeafFPDirectoryCheck *check = queue.firstObject;
            [queue removeObjectAtIndex:0];
            progress = YES;
            NSString *key = [NSString stringWithFormat:@"%@|%@|%@", domainId, check.repoId, check.path];
            if ([_checksInFlight containsObject:key]) continue;
            [self performDirectoryCheck:check key:key connection:conn domain:domainId generation:generation];
        }
    }
}

static NSDate *SeafFPCheckRetryDate(NSInteger attempts)
{
    return [NSDate dateWithTimeIntervalSinceNow:MIN(kSeafFPCheckRetryMax, kSeafFPCheckRetryMin * pow(2, MIN(attempts, 20)))];
}

/// Main thread. Lists the directory, keeping it marked as in flight until
/// the listing is applied, so it is never requested twice at once; a check
/// asked for again meanwhile has a newer version and runs once more after.
- (void)performDirectoryCheck:(SeafFPDirectoryCheck *)check
                          key:(NSString *)key
                   connection:(SeafConnection *)conn
                       domain:(NSString *)domainId
                   generation:(uint64_t)generation
{
    [_checksInFlight addObject:key];
    _checksRunning++;
    __weak SeafConnection *weakConn = conn;
    void (^finish)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_checksInFlight removeObject:key];
            if (self->_checksRunning > 0) self->_checksRunning--;
            // Accounts that found every slot taken go first, then this one.
            NSArray<SeafConnection *> *waiting = self->_checkWaiting.allObjects;
            [self->_checkWaiting removeAllObjects];
            for (SeafConnection *other in waiting) {
                if (other != weakConn) [self runDirectoryChecksForConnection:other];
            }
            [self runDirectoryChecksForConnection:weakConn];
        });
    };
    long long requestStartSeq = [self fp_requestStartSeqForConnection:conn];
    if (requestStartSeq < 0) {
        // The store could not say where we are. A listing applied without a
        // request seq confirms nothing, and the check would run again at
        // once: back off instead.
        [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
            [store deferDirectoryCheck:check until:SeafFPCheckRetryDate(check.attempts) status:0];
            finish();
        } skipped:finish];
        return;
    }
    NSString *name = [check.path isEqualToString:@"/"] ? @"" : check.path.lastPathComponent;
    SeafDir *dir = [[SeafDir alloc] initWithConnection:conn oid:nil repoId:check.repoId perm:nil name:name path:check.path mtime:0];
    [conn sendRequest:dir.url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        if (![self isDomainActive:domainId generation:generation]) { finish(); return; }
        [dir handleResponse:response json:JSON];
        NSArray<NSDictionary *> *entries = [dir fp_listingSnapshotForResponse:JSON];
        [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
            SeafFPWriteResult result = entries ? [store applyDirectoryListingOfRepo:check.repoId directoryPath:check.path
                                                                            entries:entries requestStartSeq:requestStartSeq]
                                               : SeafFPWriteFailed;
            if (result == SeafFPWriteChanged) [self noteChangedConnection:weakConn];
            // Not applied (busy, a write raced the request, unreadable
            // response): back off. A check asked for again meanwhile keeps
            // its newer version and is simply listed again.
            if (result == SeafFPWriteFailed) [store deferDirectoryCheck:check until:SeafFPCheckRetryDate(check.attempts) status:0];
            finish();
        } skipped:finish];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? response.statusCode : 0;
        NSString *message = [JSON isKindOfClass:[NSDictionary class]] ? SeafFPString(JSON[@"error_msg"]) : nil;
        if (![self isDomainActive:domainId generation:generation]) { finish(); return; }
        // Only seahub's own 404 ("Library … not found.", "Folder … not found.")
        // says the path is gone; a proxy's or an HTML page's 404 says nothing,
        // and must not walk the check up to the root and drop the library.
        BOOL libraryGone = status == 404 && ([message hasPrefix:@"Library"] || ([message hasPrefix:@"Folder"] && [check.path isEqualToString:@"/"]));
        BOOL folderGone = status == 404 && !libraryGone && [message hasPrefix:@"Folder"];
        [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
            if (libraryGone) {
                [store dropDirectoryChecksOfRepo:check.repoId];
            } else if (folderGone) {
                // Gone (or renamed): the parent's listing tells, and tombstones it.
                [store moveDirectoryCheckToParent:check];
            } else if (status == 403 && check.denials + 1 >= kSeafFPCheckMaxDenied) {
                [store dropDirectoryCheck:check];
            } else {
                [store deferDirectoryCheck:check until:SeafFPCheckRetryDate(check.attempts) status:status];
            }
            finish();
        } skipped:finish];
    }];
}

#pragma mark - SeafFileProviderDomainObserver

- (void)fileProviderDomainDidActivate:(NSString *)domainIdentifier
{
    if (domainIdentifier.length == 0) return;
    os_unfair_lock_lock(&_lock);
    if ([_deactivatedDomains containsObject:domainIdentifier]) {
        [_deactivatedDomains removeObject:domainIdentifier];
        uint64_t nextGen = [_domainGenerations[domainIdentifier] unsignedLongLongValue] + 1;
        _domainGenerations[domainIdentifier] = @(nextGen);
    }
    os_unfair_lock_unlock(&_lock);
    dispatch_async(dispatch_get_main_queue(), ^{
        for (SeafConnection *conn in [SeafGlobal.sharedObject.conns copy]) {
            if ([[SeafFileProviderDomainManager domainIdentifierForConnection:conn] isEqualToString:domainIdentifier]) {
                [self runDirectoryChecksForConnection:conn];
            }
        }
    });
}

- (void)fileProviderDomainWillDeactivate:(NSString *)domainIdentifier
{
    if (domainIdentifier.length == 0) return;
    [self deactivateDomain:domainIdentifier then:nil];
}

- (void)fileProviderDomainWillRemoveStore:(NSString *)domainIdentifier removeStore:(dispatch_block_t)removeStore
{
    if (domainIdentifier.length == 0) {
        if (removeStore) removeStore();
        return;
    }
    [self deactivateDomain:domainIdentifier then:removeStore];
}

/// Blocks new and queued writes right away (lock, no waiting on the work
/// queue), then closes the domain's store on the work queue -- after every
/// task queued before -- and runs `then` there.
- (void)deactivateDomain:(NSString *)domainIdentifier then:(nullable dispatch_block_t)then
{
    os_unfair_lock_lock(&_lock);
    [_deactivatedDomains addObject:domainIdentifier];
    uint64_t nextGen = [_domainGenerations[domainIdentifier] unsignedLongLongValue] + 1;
    _domainGenerations[domainIdentifier] = @(nextGen);
    NSString *movePrefix = [domainIdentifier stringByAppendingString:@"|"];
    for (NSString *key in [_pendingMoveCounts.allKeys copy]) {
        if ([key hasPrefix:movePrefix]) {
            [_pendingMoveCounts removeObjectForKey:key];
            [_deferredDirWork removeObjectForKey:key];
        }
    }
    os_unfair_lock_unlock(&_lock);
    // Requests of the old generation still finish and release what they hold.
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized (self->_activitySyncs) { [self->_activitySyncs removeObjectForKey:domainIdentifier]; }
        [self->_checkQueries removeObject:domainIdentifier];
        [self->_checkWakeups removeObjectForKey:domainIdentifier];
    });
    dispatch_async(_workQueue, ^{
        SeafFPStore *store = self->_stores[domainIdentifier];
        [store close];
        [self->_stores removeObjectForKey:domainIdentifier];
        if (then) then();
    });
}

@end
