//
//  SeafFPExtension.m
//  SeafFileProvider
//

#import "SeafFPExtension.h"
#import "SeafFPIdentifier.h"
#import "SeafFPStore.h"
#import "SeafFPItem.h"
#import "SeafFPEnumerator.h"
#import "SeafFPErrors.h"
#import "SeafGlobal.h"
#import "SeafConnection.h"
#import "SeafRepos.h"
#import "SeafDir.h"
#import "SeafFile.h"
#import "SeafThumb.h"
#import "SeafCacheManager+Thumb.h"
#import "SeafDataTaskManager.h"
#import "SeafFileOperationManager.h"
#import "SeafUploadFile.h"
#import "SeafStorage.h"
#import "Utils.h"
#import "Debug.h"
#import <UIKit/UIKit.h>
#import <AFNetworking/AFNetworking.h>

// Thumbnail requests handed to the SDK at the same time (plan §7.9), and how
// long one may hold its slot before it is given up.
static const NSUInteger kSeafFPThumbMaxInFlight = 4;
static const NSTimeInterval kSeafFPThumbTimeout = 60.0;

@interface SeafFPExtension ()
@property (nonatomic, strong) NSFileProviderDomain *domain;
@property (nonatomic, strong) NSFileProviderManager *manager;
@property (strong, nullable) SeafConnection *connection;
@property (strong, nullable) SeafFPStore *store;
@property (nonatomic, strong) NSCache<NSString *, SeafBase *> *seafObjects;
// Content fetches waiting for the one SDK download that serves an item.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *contentWaiters;
@property (atomic, assign) BOOL invalidated;
// Bumped per thumbnail request of an item, so a timer armed for an earlier
// request cannot answer (and release the slot of) a later one.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *thumbGenerations;
@property (nonatomic, strong, nullable) NSError *unresolvedError;
// Thumbnail gate: tasks waiting for a slot, and per-item completion blocks
// waiting for the one SDK task that serves that item.
@property (nonatomic, assign) NSUInteger thumbInFlight;
@property (nonatomic, strong) NSMutableArray<dispatch_block_t> *pendingThumbTasks;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *thumbWaiters;
// A working set re-check timer is armed (design §8.2).
@property (nonatomic, assign) BOOL workingSetRecheckPending;
@end

/// Collects the identifiers handed out by the system's materialized-items enumerator.
@interface SeafFPMaterializedCollector : NSObject <NSFileProviderEnumerationObserver>
@property (nonatomic, strong) NSMutableArray<NSFileProviderItemIdentifier> *identifiers;
@property (nonatomic, copy) void (^completion)(NSArray<NSFileProviderItemIdentifier> * _Nullable identifiers,
                                                NSFileProviderPage _Nullable nextPage,
                                                NSError * _Nullable error);
@end

@implementation SeafFPMaterializedCollector

- (instancetype)init
{
    self = [super init];
    if (self) {
        _identifiers = [NSMutableArray array];
    }
    return self;
}

- (void)didEnumerateItems:(NSArray<id<NSFileProviderItem>> *)updatedItems
{
    for (id<NSFileProviderItem> item in updatedItems) {
        if (item.itemIdentifier) [self.identifiers addObject:item.itemIdentifier];
    }
}

- (void)finishEnumeratingUpToPage:(NSFileProviderPage)nextPage
{
    if (self.completion) self.completion(self.identifiers, nextPage, nil);
}

- (void)finishEnumeratingWithError:(NSError *)error
{
    if (self.completion) self.completion(nil, nil, error);
}

@end

@implementation SeafFPExtension

#pragma mark - Lifecycle

- (instancetype)initWithDomain:(NSFileProviderDomain *)domain
{
    self = [super init];
    if (self) {
        _domain = domain;
        _manager = [NSFileProviderManager managerForDomain:domain];
        _seafObjects = [[NSCache alloc] init];
        _seafObjects.countLimit = 256;
        _pendingThumbTasks = [NSMutableArray array];
        _thumbWaiters = [NSMutableDictionary dictionary];
        _contentWaiters = [NSMutableDictionary dictionary];
        _thumbGenerations = [NSMutableDictionary dictionary];

        [SeafGlobal.sharedObject loadAccounts];
        (void)[SeafDataTaskManager sharedObject];
        _connection = [self lookupConnection];

        NSError *error = nil;
        _store = [[SeafFPStore alloc] initWithDomainIdentifier:domain.identifier error:&error];
        if (!_store) {
            Warning("Cannot open store for domain %@: %@", domain.identifier, error);
        }
        Debug("File provider started for domain %@ (%@), account %@", domain.identifier, domain.displayName,
              _connection ? [NSString stringWithFormat:@"%@ @ %@", _connection.username, _connection.address] : @"<none>");
    }
    return self;
}

- (void)invalidate
{
    Debug("invalidate domain %@", self.domain.identifier);
    self.invalidated = YES;
    [self.store close];   // kept assigned for callbacks in flight; isOpen tells them it is gone
    [self.seafObjects removeAllObjects];
    @synchronized (self.pendingThumbTasks) {
        [self.pendingThumbTasks removeAllObjects];
        self.thumbInFlight = 0;
    }
    @synchronized (self.thumbWaiters) {
        [self.thumbWaiters removeAllObjects];
    }
}

- (SeafConnection *)lookupConnection
{
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        NSString *identifier = [SeafFPIdentifier domainIdentifierForAddress:conn.address username:conn.username];
        if ([identifier isEqualToString:self.domain.identifier]) {
            return conn;
        }
    }
    return nil;
}

- (void)refreshConnectionIfNeeded
{
    SeafConnection *current = self.connection;
    if (!current) {
        [SeafGlobal.sharedObject syncAccountsFromStorage];
        self.connection = [self lookupConnection];
        return;
    }
    // A SeafConnection reads its token once, at init. The app may have
    // signed the account out, in again, or in with a new token while this
    // process was alive. The persisted record is a dictionary lookup in the
    // App Group defaults, cheap enough to compare on every request; the app
    // signals the working set right after a logout / login, and that signal
    // must see the new session, not a throttled stale one.
    // Building a SeafConnection has side effects (server info request, photo
    // library observer, repo password clearing), so one is only created when
    // the session actually changed.
    NSDictionary *info = [SeafStorage.sharedObject objectForKey:current.accountIdentifier];
    if (![info isKindOfClass:[NSDictionary class]]) return;   // unreadable (data protection) or gone: keep what we have
    NSString *persisted = info[@"token"];
    if (![persisted isKindOfClass:[NSString class]]) persisted = nil;
    BOOL tokenChanged = (persisted.length > 0) != (current.token.length > 0)
        || (persisted.length > 0 && ![persisted isEqualToString:current.token]);
    if (!tokenChanged) {
        // Same session, but the app may have unlocked (or cleared) an
        // encrypted library since this connection read its record: the
        // library list is filtered by passwordRequired, which reads the
        // in-memory copy.
        if ([current reloadRepoPasswordsFromInfo:info]) {
            Debug("Account %@ library passwords changed, dropping cached objects", current.username);
            [self.seafObjects removeAllObjects];
        }
        return;
    }
    SeafConnection *fresh = [[SeafConnection alloc] initWithUrl:current.address
                                                  cacheProvider:SeafGlobal.sharedObject.cacheProvider
                                                       username:current.username];
    Debug("Account %@ session changed, refreshing connection", fresh.username);
    self.connection = fresh;
    [self.seafObjects removeAllObjects];
}

/// AFNetworking reports "unknown" (treated as unreachable by the SDK queues)
/// until its first callback after launch; the extension is often launched
/// for a single request, so give it a moment before starting a transfer.
- (void)whenReachabilityKnown:(dispatch_block_t)block
{
    [self whenReachabilityKnown:block remainingChecks:20];
}

- (void)whenReachabilityKnown:(dispatch_block_t)block remainingChecks:(NSInteger)remaining
{
    if (self.invalidated) return;   // nothing waits for the answer any more
    if (remaining <= 0 || [AFNetworkReachabilityManager sharedManager].networkReachabilityStatus != AFNetworkReachabilityStatusUnknown) {
        block();
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf whenReachabilityKnown:block remainingChecks:remaining - 1];
    });
}

/// What every request needs before it may even look at local state: an
/// account, no Touch ID lock, and an open store. Answering NoSuchItem (or
/// "already deleted") for a closed store would make the system discard its
/// copy, favorites included, so the store is checked before any lookup.
- (NSError *)localAccessError
{
    [self refreshConnectionIfNeeded];
    if (!self.connection) {
        return [SeafFPErrors noAccount];
    }
    if (self.connection.touchIdEnabled) {
        // The app removes the domain; until that succeeds, serve nothing.
        return [SeafFPErrors touchIdEnabled];
    }
    if (![self.store isOpen]) {
        return [SeafFPErrors cannotSynchronize];
    }
    return nil;
}

/// localAccessError plus a signed-in session: required for anything that
/// talks to the server.
- (NSError *)accessError
{
    NSError *local = [self localAccessError];
    if (local) return local;
    if (self.connection.token.length == 0) {
        return [SeafFPErrors notAuthenticated];
    }
    return nil;
}

#pragma mark - Error bookkeeping

- (void)noteError:(NSError *)error
{
    if (![error.domain isEqualToString:NSFileProviderErrorDomain]) return;
    switch (error.code) {
        case NSFileProviderErrorServerUnreachable:
        case NSFileProviderErrorNotAuthenticated:
        case NSFileProviderErrorCannotSynchronize:
        case NSFileProviderErrorInsufficientQuota:
            @synchronized (self) {
                self.unresolvedError = error;
            }
            break;
        default:
            break;
    }
}

- (void)noteSuccess
{
    NSError *error = nil;
    @synchronized (self) {
        error = self.unresolvedError;
        self.unresolvedError = nil;
    }
    if (!error) return;
    [self.manager signalErrorResolved:error completionHandler:^(NSError * _Nullable signalError) {
        if (signalError) {
            Debug("signalErrorResolved failed: %@", signalError);
        }
    }];
}

#pragma mark - Model helpers

- (SeafRepo *)repoWithId:(NSString *)repoId
{
    if (repoId.length == 0) return nil;
    return [self.connection getRepo:repoId];
}

- (BOOL)isRepoEditable:(NSString *)repoId
{
    return [self repoWithId:repoId].editable;
}

- (BOOL)repoListUnknownFor:(NSString *)repoId
{
    if (repoId.length == 0) return NO;
    if ([self repoWithId:repoId]) return NO;
    return self.connection.rootFolder.items.count == 0;
}

- (void)ensureRepoListLoaded:(void (^)(BOOL known, BOOL fromNetwork))completion
{
    SeafRepos *repos = self.connection.rootFolder;
    if (!repos) {
        completion(NO, NO);
        return;
    }
    if (repos.items.count > 0) {
        completion(YES, NO);
        return;
    }
    // getRepo: reads the disk cache on demand; loadCache does the same explicitly.
    if ([repos loadCache] && repos.items.count > 0) {
        completion(YES, NO);
        return;
    }
    [repos loadContentSuccess:^(SeafDir *dir) {
        completion(YES, YES);
    } failure:^(SeafDir *dir, NSError *error) {
        SeafRepos *r = (SeafRepos *)dir;
        BOOL cached = r.hasCache || [r loadCache];
        Debug("library list unavailable (%@), cache: %d", error, cached);
        completion(cached, NO);
    }];
}

- (SeafFPItem *)itemForRepo:(SeafRepo *)repo
{
    SeafFPItem *item = [SeafFPItem itemForRepo:repo];
    [item applyDecoration:[self.store decorationForItem:item.itemIdentifier]];
    return item;
}

- (SeafFPItem *)itemForRecord:(SeafFPRecord *)record
{
    SeafFPItem *item = [SeafFPItem itemForRecord:record repoEditable:[self isRepoEditable:record.repoId]];
    [item applyDecoration:[self.store decorationForItem:item.itemIdentifier]];
    return item;
}

- (SeafFPItem *)resolveItem:(NSFileProviderItemIdentifier)identifier error:(NSError **)error
{
    switch ([SeafFPIdentifier kindOfIdentifier:identifier]) {
        case SeafFPIdentifierKindRoot:
            return [SeafFPItem rootItemWithName:self.domain.displayName];
        case SeafFPIdentifierKindTrash:
            return [SeafFPItem trashItem];
        case SeafFPIdentifierKindRepo: {
            SeafRepo *repo = [self repoWithId:[SeafFPIdentifier repoIdFromIdentifier:identifier]];
            if (!repo) break;
            if (repo.passwordRequired) {
                // Hidden from the listing, but the system may still hold items
                // below it: "gone" would make it discard them.
                if (error) *error = [SeafFPErrors notAuthenticated];
                return nil;
            }
            return [self itemForRepo:repo];
        }
        case SeafFPIdentifierKindItem: {
            SeafFPRecord *record = [self.store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:identifier]];
            if (!record || record.deleted) break;
            return [self itemForRecord:record];
        }
        default:
            break;
    }
    if (error) *error = [SeafFPErrors noSuchItem];
    return nil;
}

- (SeafDir *)seafDirForContainer:(NSFileProviderItemIdentifier)containerIdentifier record:(SeafFPRecord **)outRecord
{
    if (outRecord) *outRecord = nil;
    switch ([SeafFPIdentifier kindOfIdentifier:containerIdentifier]) {
        case SeafFPIdentifierKindRoot:
            return self.connection.rootFolder;
        case SeafFPIdentifierKindRepo: {
            SeafRepo *repo = [self repoWithId:[SeafFPIdentifier repoIdFromIdentifier:containerIdentifier]];
            return repo.passwordRequired ? nil : repo;
        }
        case SeafFPIdentifierKindItem: {
            SeafFPRecord *record = [self.store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:containerIdentifier]];
            if (!record || record.deleted || !record.isDir) return nil;
            if (outRecord) *outRecord = record;
            SeafBase *cached = [self.seafObjects objectForKey:containerIdentifier];
            if ([cached isKindOfClass:[SeafDir class]]
                && [((SeafDir *)cached).path isEqualToString:record.path]
                && [((SeafDir *)cached).repoId isEqualToString:record.repoId]) {
                return (SeafDir *)cached;
            }
            SeafRepo *repo = [self repoWithId:record.repoId];
            SeafDir *dir = [[SeafDir alloc] initWithConnection:self.connection
                                                           oid:record.oid
                                                        repoId:record.repoId
                                                          perm:repo.perm
                                                          name:record.name
                                                          path:record.path
                                                         mtime:record.mtime];
            [self.seafObjects setObject:dir forKey:containerIdentifier];
            return dir;
        }
        default:
            return nil;
    }
}

- (SeafFile *)seafFileForRecord:(SeafFPRecord *)record
{
    if (!record || record.isDir) return nil;
    NSString *identifier = record.itemIdentifier;
    SeafBase *cached = [self.seafObjects objectForKey:identifier];
    if ([cached isKindOfClass:[SeafFile class]]
        && [((SeafFile *)cached).path isEqualToString:record.path]
        && [((SeafFile *)cached).repoId isEqualToString:record.repoId]
        && (record.oid.length == 0 || [((SeafFile *)cached).oid isEqualToString:record.oid])) {
        return (SeafFile *)cached;
    }
    SeafFile *file = [[SeafFile alloc] initWithConnection:self.connection
                                                      oid:record.oid
                                                   repoId:record.repoId
                                                     name:record.name
                                                     path:record.path
                                                    mtime:record.mtime
                                                     size:(unsigned long long)MAX(record.size, 0)];
    [self.seafObjects setObject:file forKey:identifier];
    return file;
}

#pragma mark - NSFileProviderReplicatedExtension: items

- (NSProgress *)itemForIdentifier:(NSFileProviderItemIdentifier)identifier
                          request:(NSFileProviderRequest *)request
                completionHandler:(void (^)(NSFileProviderItem _Nullable, NSError * _Nullable))completionHandler
{
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
    NSError *error = [self localAccessError];
    SeafFPItem *item = nil;
    if (error) {
        // No account / Touch ID / closed store: reported as such, never as NoSuchItem.
    } else if ([SeafFPIdentifier kindOfIdentifier:identifier] == SeafFPIdentifierKindRepo
               && [self repoListUnknownFor:[SeafFPIdentifier repoIdFromIdentifier:identifier]]) {
        // Fresh process (after a reboot, or the extension was killed): the
        // library list is not in memory yet. "NoSuchItem" now would make the
        // system drop the whole library, favorites included.
        __weak typeof(self) weakSelf = self;
        [self ensureRepoListLoaded:^(BOOL known, BOOL fromNetwork) {
            typeof(self) strongSelf = weakSelf;
            NSError *resolveError = nil;
            SeafFPItem *resolved = strongSelf ? [strongSelf resolveItem:identifier error:&resolveError] : nil;
            if (!resolved && !known) {
                resolveError = [SeafFPErrors serverUnreachable];   // list unavailable: try again later
            }
            completionHandler(resolved, resolved ? nil : (resolveError ?: [SeafFPErrors noSuchItem]));
            progress.completedUnitCount = 1;
        }];
        return progress;
    } else {
        item = [self resolveItem:identifier error:&error];
    }
    completionHandler(item, item ? nil : (error ?: [SeafFPErrors noSuchItem]));
    progress.completedUnitCount = 1;
    return progress;
}

#pragma mark - NSFileProviderReplicatedExtension: contents

- (NSURL *)stageContentsOfFile:(SeafFile *)file error:(NSError **)error
{
    NSURL *source = file.exportURL;
    if (!source || ![[NSFileManager defaultManager] fileExistsAtPath:source.path]) {
        if (error) *error = [SeafFPErrors serverUnreachable];
        return nil;
    }
    NSError *tmpError = nil;
    NSURL *tmpRoot = [self.manager temporaryDirectoryURLWithError:&tmpError];
    if (!tmpRoot) {
        Warning("temporaryDirectoryURL failed: %@", tmpError);
        if (error) *error = [SeafFPErrors cannotSynchronize];
        return nil;
    }
    NSURL *dir = [tmpRoot URLByAppendingPathComponent:[NSUUID UUID].UUIDString isDirectory:YES];
    NSURL *dest = [dir URLByAppendingPathComponent:(file.name.length > 0 ? file.name : @"file") isDirectory:NO];
    NSError *fsError = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:&fsError]
        || ![fm copyItemAtURL:source toURL:dest error:&fsError]) {
        Warning("Cannot stage %@: %@", file.name, fsError);
        if (error) *error = [SeafFPErrors cannotSynchronize];
        return nil;
    }
    return dest;
}

- (NSProgress *)fetchContentsForItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
                                           version:(NSFileProviderItemVersion *)requestedVersion
                                           request:(NSFileProviderRequest *)request
                                 completionHandler:(void (^)(NSURL * _Nullable, NSFileProviderItem _Nullable, NSError * _Nullable))completionHandler
{
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:100];
    __block BOOL done = NO;
    void (^finish)(NSURL *, SeafFPItem *, NSError *) = ^(NSURL *url, SeafFPItem *item, NSError *error) {
        @synchronized (progress) {
            if (done) return;   // a cancel racing the download must not answer twice
            done = YES;
        }
        progress.completedUnitCount = progress.totalUnitCount;
        completionHandler(url, item, error);
    };

    NSError *access = [self accessError];
    if (access) {
        finish(nil, nil, access);
        return progress;
    }
    SeafFPRecord *record = [self.store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:itemIdentifier]];
    if (!record || record.deleted) {
        finish(nil, nil, [SeafFPErrors noSuchItem]);
        return progress;
    }
    if (record.isDir) {
        // Folders carry no payload. An error here makes iOS 26 flag the whole location.
        finish(nil, [self itemForRecord:record], nil);
        return progress;
    }

    SeafFile *file = [self seafFileForRecord:record];
    __weak typeof(self) weakSelf = self;
    void (^deliver)(void) = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            finish(nil, nil, [SeafFPErrors cannotSynchronize]);
            return;
        }
        // This block may run for a request that joined a download started by
        // another SeafFile instance for the same item (the cache evicted the
        // first one): pick up the finished download's oid before staging.
        [file loadCache];
        NSError *stageError = nil;
        NSURL *url = [strongSelf stageContentsOfFile:file error:&stageError];
        if (!url) {
            [strongSelf noteError:stageError];
            finish(nil, nil, stageError);
            return;
        }
        SeafFPRecord *updated = [strongSelf.store upsertRecordForRepo:record.repoId
                                                                 path:record.path
                                                                isDir:NO
                                                           parentUUID:record.parentUUID
                                                                  oid:(file.ooid.length > 0 ? file.ooid : file.oid)
                                                                mtime:file.mtime
                                                                 size:(long long)file.filesize];
        [strongSelf noteSuccess];
        finish(url, [strongSelf itemForRecord:updated ?: record], nil);
    };

    [file loadCache];
    if (file.hasCache && file.exportURL) {
        deliver();
        return progress;
    }
    // Requests for the same item share one SDK download: a SeafFile keeps a
    // single completion block, so a second request must not replace the first.
    void (^waiter)(NSError *) = [^(NSError *error) {
        if (!error) {
            deliver();
            return;
        }
        if ([error.domain isEqualToString:@"SeafFile"] && error.code == -999) {
            finish(nil, nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
            return;
        }
        NSError *mapped = [SeafFPErrors errorForSeafError:error];
        [weakSelf noteError:mapped];
        finish(nil, nil, mapped);
    } copy];
    BOOL first = [self addContentWaiter:waiter forIdentifier:itemIdentifier];
    progress.cancellationHandler = ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && [strongSelf removeContentWaiter:waiter forIdentifier:itemIdentifier] == 0) {
            [file cancelDownload];   // nobody else is waiting for it
        }
        finish(nil, nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
    };
    if (first) {
        [file setFileDownloadedBlock:^(SeafFile *downloaded, NSError *error) {
            [downloaded setFileDownloadedBlock:nil];   // breaks file -> block -> file
            [weakSelf finishContentForIdentifier:itemIdentifier error:error];
        }];
        [self whenReachabilityKnown:^{
            [file loadContent:YES];
        }];
    }
    return progress;
}

#pragma mark - Content waiters

/// Registers a completion for the item's download; YES when it is the first
/// one and the caller has to start the download.
- (BOOL)addContentWaiter:(void (^)(NSError * _Nullable))waiter forIdentifier:(NSString *)identifier
{
    @synchronized (self.contentWaiters) {
        NSMutableArray *waiters = self.contentWaiters[identifier];
        if (waiters) {
            [waiters addObject:waiter];
            return NO;
        }
        self.contentWaiters[identifier] = [NSMutableArray arrayWithObject:waiter];
        return YES;
    }
}

/// Removes one completion; returns how many are still waiting.
- (NSUInteger)removeContentWaiter:(void (^)(NSError * _Nullable))waiter forIdentifier:(NSString *)identifier
{
    @synchronized (self.contentWaiters) {
        NSMutableArray *waiters = self.contentWaiters[identifier];
        NSUInteger index = waiters ? [waiters indexOfObjectIdenticalTo:waiter] : NSNotFound;
        if (index != NSNotFound) [waiters removeObjectAtIndex:index];
        if (waiters.count == 0) [self.contentWaiters removeObjectForKey:identifier];
        return waiters.count;
    }
}

- (void)finishContentForIdentifier:(NSString *)identifier error:(NSError *)error
{
    NSArray *waiters = nil;
    @synchronized (self.contentWaiters) {
        waiters = [self.contentWaiters[identifier] copy];
        [self.contentWaiters removeObjectForKey:identifier];
    }
    for (void (^waiter)(NSError *) in waiters) {
        waiter(error);
    }
}

#pragma mark - Write helpers

static BOOL SeafFPNamesEqual(NSString *a, NSString *b)
{
    if (a.length == 0 || b.length == 0) return NO;
    return [a.precomposedStringWithCanonicalMapping isEqualToString:b.precomposedStringWithCanonicalMapping];
}

// A replicated extension may only signal the working set; other container
// identifiers are ignored by the system (NSFileProviderManager.h). The
// working set change enumeration re-lists the affected directories.
- (void)signalContainer:(NSFileProviderItemIdentifier)containerIdentifier
{
    if (containerIdentifier.length == 0) return;
    [self.manager signalEnumeratorForContainerItemIdentifier:NSFileProviderWorkingSetContainerItemIdentifier completionHandler:^(NSError * _Nullable error) {
        if (error) {
            Debug("signal working set (for %@) failed: %@", containerIdentifier, error);
        }
    }];
}

- (void)signalWorkingSet
{
    [self signalContainer:NSFileProviderWorkingSetContainerItemIdentifier];
}

// A working set pass leaves directories alone that were listed within the
// re-check interval (their own listing may be what signalled). A change made
// by the app right after such a listing would otherwise wait for whatever
// signals next; the pass asks for one more pass when the window has closed.
// One timer at a time: a pending one fires soon enough, and its pass arms
// the next if needed.
- (void)scheduleWorkingSetRecheckAt:(NSDate *)date
{
    @synchronized (self) {
        if (self.workingSetRecheckPending) return;
        self.workingSetRecheckPending = YES;
    }
    NSTimeInterval delay = MAX(1.0, [date timeIntervalSinceNow]);
    Debug("working set re-check in %.0fs", delay);
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        @synchronized (strongSelf) {
            strongSelf.workingSetRecheckPending = NO;
        }
        if (strongSelf.invalidated) return;
        [strongSelf signalWorkingSet];
    });
}

/// SeafFileOperationManager reports "Renamed file not found" (-5) when the
/// server did rename but the SDK's cached listing was not refreshed (same
/// dir_id); the rename itself succeeded.
static BOOL SeafFPRenameSucceeded(BOOL success, NSError *error)
{
    return success || ([error.domain isEqualToString:@"SeafFileOperation"] && error.code == -5);
}

- (void)forgetSeafObjectsForRecord:(SeafFPRecord *)record
{
    [self.seafObjects removeObjectForKey:record.itemIdentifier];
}

/// Size of a file handed over by the system, -1 when it cannot be read.
- (long long)sizeOfFileAtURL:(NSURL *)url
{
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
    if (scoped) [url stopAccessingSecurityScopedResource];
    return attrs ? (long long)[attrs fileSize] : -1;
}

/// `name` when no entry of `dirs` carries it (case-insensitively, like the
/// server), otherwise a free name picked the way the app does. The entry
/// called `ownName` in `ownDir` is the item being renamed and does not count
/// (a case-only rename, or a retry after the move step failed).
- (NSString *)freeNameFor:(NSString *)name
                   inDirs:(NSArray<SeafDir *> *)dirs
                  ownName:(NSString *)ownName
                    inDir:(SeafDir *)ownDir
{
    BOOL (^taken)(NSString *) = ^BOOL(NSString *candidate) {
        for (SeafDir *dir in dirs) {
            NSString *existing = [dir actualNameForCaseInsensitiveMatch:candidate];
            if (!existing) continue;
            if (dir == ownDir && SeafFPNamesEqual(existing, ownName)) continue;
            return YES;
        }
        return NO;
    };
    NSString *candidate = name;
    NSInteger guard = 0;
    while (taken(candidate) && guard++ < 100) {
        candidate = [Utils creatNewFileName:candidate];
    }
    return candidate;
}

/// The name a record's entry carries after a server rename / move, read from
/// a live listing of the directory it ended up in. Seafile keeps both
/// operations succeeding on a name clash and picks a free name instead, so
/// the expected name may now belong to another file. Seafile ids are content
/// hashes (identical files share one), so entries the store knows as other
/// live records are never candidates; a record without an id (a folder
/// created from Files) is matched by "not known to the store yet". nil when
/// no single entry can be told apart.
- (NSString *)finalNameForRecord:(SeafFPRecord *)record expected:(NSString *)expected inDir:(SeafDir *)dir
{
    BOOL hasOid = record.oid.length > 0;
    NSMutableArray<SeafBase *> *sameKind = [NSMutableArray array];
    for (SeafBase *obj in dir.items) {
        if ([obj isKindOfClass:[SeafDir class]] == record.isDir) [sameKind addObject:obj];
    }
    NSMutableDictionary<NSString *, NSNumber *> *known = [NSMutableDictionary dictionary];   // path -> another live record sits there
    BOOL (^other)(SeafBase *) = ^BOOL(SeafBase *obj) {
        NSNumber *cached = known[obj.path];
        if (cached) return cached.boolValue;
        SeafFPRecord *live = [self.store recordForRepo:dir.repoId path:obj.path includeDeleted:NO];
        BOOL result = live && ![live.uuid isEqualToString:record.uuid];
        known[obj.path] = @(result);
        return result;
    };
    // The expected name, unless it is known to be another file.
    for (SeafBase *obj in sameKind) {
        if (!SeafFPNamesEqual(obj.name, expected)) continue;
        if ((!hasOid || [obj.oid isEqualToString:record.oid]) && !other(obj)) return obj.name;
        break;
    }
    // Otherwise the one entry with this content id ...
    NSMutableArray<SeafBase *> *pool = [NSMutableArray array];
    if (hasOid) {
        for (SeafBase *obj in sameKind) {
            if ([obj.oid isEqualToString:record.oid] && !other(obj)) [pool addObject:obj];
        }
        if (pool.count == 1) return pool.firstObject.name;
    }
    // ... or the one entry the store has never seen.
    NSMutableArray<SeafBase *> *fresh = [NSMutableArray array];
    for (SeafBase *obj in (pool.count > 0 ? pool : sameKind)) {
        if (![self.store recordForRepo:dir.repoId path:obj.path includeDeleted:NO]) [fresh addObject:obj];
    }
    return fresh.count == 1 ? fresh.firstObject.name : nil;
}

/// Copies the system-provided contents into the App Group temp directory,
/// named like the target file, so the SDK can hard-link it for upload.
- (NSURL *)stageUploadSource:(NSURL *)source name:(NSString *)name error:(NSError **)error
{
    NSString *dir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.tempDir];
    if (![Utils checkMakeDir:dir]) {
        if (error) *error = [SeafFPErrors cannotSynchronize];
        return nil;
    }
    NSURL *dest = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]];
    BOOL scoped = [source startAccessingSecurityScopedResource];
    NSError *copyError = nil;
    BOOL ok = [[NSFileManager defaultManager] copyItemAtURL:source toURL:dest error:&copyError];
    if (scoped) [source stopAccessingSecurityScopedResource];
    if (!ok) {
        Warning("Cannot stage upload %@: %@", name, copyError);
        if (error) *error = [SeafFPErrors cannotSynchronize];
        return nil;
    }
    return dest;
}

- (void)loadDirectory:(SeafDir *)dir completion:(void (^)(BOOL loaded, BOOL fromCache, NSError * _Nullable error))completion
{
    __weak typeof(self) weakSelf = self;
    [dir loadContentSuccess:^(SeafDir *loaded) {
        completion(YES, NO, nil);
    } failure:^(SeafDir *failed, NSError *error) {
        BOOL cached = failed.hasCache || [failed loadCache];
        if (cached) {
            Debug("Directory %@ unreachable, serving cache: %@", failed.path, error);
            completion(YES, YES, nil);
        } else {
            NSError *mapped = [SeafFPErrors errorForSeafError:error];
            [weakSelf noteError:mapped];
            completion(NO, NO, mapped);
        }
    }];
}

- (void)applyDecorationChangesFromItem:(NSFileProviderItem)item
                         changedFields:(NSFileProviderItemFields)changedFields
                                toItem:(SeafFPItem *)current
{
    NSString *identifier = current.itemIdentifier;
    SeafFPIdentifierKind kind = [SeafFPIdentifier kindOfIdentifier:identifier];
    if (kind != SeafFPIdentifierKindRepo && kind != SeafFPIdentifierKindItem) {
        return;   // the domain root and the trash cannot be decorated
    }
    SeafFPDecoration *decoration = [self.store decorationForItem:identifier] ?: [SeafFPDecoration new];
    decoration.itemIdentifier = identifier;
    if (changedFields & NSFileProviderItemFavoriteRank) {
        decoration.favoriteRank = item.favoriteRank;
    }
    if (changedFields & NSFileProviderItemTagData) {
        decoration.tagData = item.tagData.length > 0 ? item.tagData : nil;
    }
    if (changedFields & NSFileProviderItemLastUsedDate) {
        decoration.lastUsedDate = item.lastUsedDate;
    }
    [self.store setDecoration:decoration];

    SeafFPWorkingSetReason reason = 0;
    if (decoration.favoriteRank != nil) reason |= SeafFPWorkingSetReasonFavorite;
    if (decoration.tagData.length > 0) reason |= SeafFPWorkingSetReasonTag;
    SeafFPWorkingSetReason cleared = (SeafFPWorkingSetReasonFavorite | SeafFPWorkingSetReasonTag | SeafFPWorkingSetReasonMigrated) & ~reason;
    if (reason) {
        [self.store addWorkingSetItem:identifier reason:reason];
    }
    if (cleared) {
        [self.store removeWorkingSetItem:identifier reason:cleared];
    }
    [current applyDecoration:decoration];
    Debug("decoration %@ favorite=%@ tag=%lu lastUsed=%@", identifier, decoration.favoriteRank, (unsigned long)decoration.tagData.length, decoration.lastUsedDate);

    // Only the working set changes; signalling the parent is deliberately
    // avoided (see the iOS 26 notes in the design document).
    [self signalContainer:NSFileProviderWorkingSetContainerItemIdentifier];
}

- (void)applyTemplateDecoration:(NSFileProviderItem)itemTemplate fields:(NSFileProviderItemFields)fields toItem:(SeafFPItem *)item
{
    NSFileProviderItemFields decorationFields = NSFileProviderItemFavoriteRank | NSFileProviderItemTagData | NSFileProviderItemLastUsedDate;
    if (fields & decorationFields) {
        [self applyDecorationChangesFromItem:itemTemplate changedFields:(fields & decorationFields) toItem:item];
    }
}

/// Uploads a staged file to `path` (full path in the library) and reports the new record.
/// Cancelling `progress` aborts the upload and reports NSUserCancelledError.
- (void)uploadStagedFile:(NSURL *)stagedURL
                  repoId:(NSString *)repoId
                    path:(NSString *)path
              parentUUID:(NSString *)parentUUID
                progress:(NSProgress *)progress
              completion:(void (^)(SeafFPRecord * _Nullable record, NSError * _Nullable error))completion
{
    NSURL *stagedDir = stagedURL.URLByDeletingLastPathComponent;
    if (progress.isCancelled) {
        // Cancelled while the directory was being listed: already answered.
        [[NSFileManager defaultManager] removeItemAtURL:stagedDir error:nil];
        completion(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
        return;
    }
    NSString *name = path.lastPathComponent;
    SeafFPRecord *existing = [self.store recordForRepo:repoId path:path includeDeleted:NO];
    SeafFile *file = [[SeafFile alloc] initWithConnection:self.connection
                                                      oid:existing.oid
                                                   repoId:repoId
                                                     name:name
                                                     path:path
                                                    mtime:existing.mtime
                                                     size:(unsigned long long)MAX(existing.size, 0)];
    __block BOOL finished = NO;
    __weak typeof(self) weakSelf = self;
    // The upload block and a cancel can race; whoever gets here first answers.
    BOOL (^claim)(void) = ^BOOL{
        @synchronized (progress) {
            if (finished) return NO;
            finished = YES;
            return YES;
        }
    };
    [file setFileUploadedBlock:^(SeafUploadFile *uploadFile, NSString *oid, NSError *error) {
        if (!claim()) return;
        // The SDK hard-linked the staged file into its own upload directory.
        [[NSFileManager defaultManager] removeItemAtURL:stagedDir error:nil];
        typeof(self) strongSelf = weakSelf;
        if (error || oid.length == 0 || !strongSelf) {
            Warning("Upload %@ failed: %@", name, error);
            NSError *mapped = error ? [SeafFPErrors errorForSeafError:error] : [SeafFPErrors serverUnreachable];
            [strongSelf noteError:mapped];
            completion(nil, mapped);
            return;
        }
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:stagedURL.path error:nil];
        long long size = attrs ? (long long)[attrs fileSize] : (long long)uploadFile.filesize;
        long long mtime = (long long)[[NSDate date] timeIntervalSince1970];
        SeafFPRecord *record = [strongSelf.store upsertRecordForRepo:repoId path:path isDir:NO parentUUID:parentUUID oid:oid mtime:mtime size:size];
        [strongSelf forgetSeafObjectsForRecord:record];
        [strongSelf noteSuccess];
        progress.completedUnitCount = progress.totalUnitCount;
        completion(record, nil);
    }];
    if (![file uploadFromFile:stagedURL]) {
        (void)claim();
        [[NSFileManager defaultManager] removeItemAtURL:stagedDir error:nil];
        completion(nil, [SeafFPErrors cannotSynchronize]);
        return;
    }
    // The system cancels an upload it considers stalled or that the user
    // stopped; it then expects the completion handler right away. The upload
    // operation owns the SeafUploadFile while it is queued or running, so a
    // weak reference is enough: once it is done there is nothing to cancel.
    // (SeafFile declares cancelUpload but never implements it.)
    __weak SeafUploadFile *weakUpload = file.ufile;
    SeafConnection *connection = self.connection;
    progress.cancellationHandler = ^{
        if (!claim()) return;
        SeafUploadFile *upload = weakUpload;
        if (upload) [SeafDataTaskManager.sharedObject removeUploadTask:upload forAccount:connection];
        [[NSFileManager defaultManager] removeItemAtURL:stagedDir error:nil];
        completion(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
    };
}

#pragma mark - NSFileProviderReplicatedExtension: create

- (NSProgress *)createItemBasedOnTemplate:(NSFileProviderItem)itemTemplate
                                   fields:(NSFileProviderItemFields)fields
                                 contents:(NSURL *)url
                                  options:(NSFileProviderCreateItemOptions)options
                                  request:(NSFileProviderRequest *)request
                        completionHandler:(void (^)(NSFileProviderItem _Nullable, NSFileProviderItemFields, BOOL, NSError * _Nullable))completionHandler
{
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:100];
    __block BOOL done = NO;
    void (^finish)(SeafFPItem *, NSError *) = ^(SeafFPItem *item, NSError *error) {
        @synchronized (progress) {
            if (done) return;   // a cancel racing the operation must not answer twice
            done = YES;
        }
        progress.completedUnitCount = progress.totalUnitCount;
        completionHandler(item, 0, NO, error);
    };
    // Until the upload starts (which installs its own handler) a cancel only
    // has to answer; nothing has reached the server yet.
    progress.cancellationHandler = ^{
        finish(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
    };

    NSError *access = [self accessError];
    if (access) {
        finish(nil, access);
        return progress;
    }
    NSFileProviderItemIdentifier parentIdentifier = itemTemplate.parentItemIdentifier;
    SeafFPRecord *parentRecord = nil;
    SeafDir *parentDir = [self seafDirForContainer:parentIdentifier record:&parentRecord];
    SeafFPIdentifierKind parentKind = [SeafFPIdentifier kindOfIdentifier:parentIdentifier];
    if (!parentDir && parentKind == SeafFPIdentifierKindRepo
        && [self repoListUnknownFor:[SeafFPIdentifier repoIdFromIdentifier:parentIdentifier]]) {
        finish(nil, [SeafFPErrors serverUnreachable]);   // cold process: the system retries
        return progress;
    }
    if (!parentDir || (parentKind != SeafFPIdentifierKindRepo && parentKind != SeafFPIdentifierKindItem)) {
        finish(nil, [SeafFPErrors noSuchItem]);
        return progress;
    }
    if (![self isRepoEditable:parentDir.repoId]) {
        finish(nil, [SeafFPErrors cannotSynchronize]);
        return progress;
    }
    BOOL isFolder = [itemTemplate.contentType conformsToType:UTTypeFolder];
    NSString *requestedName = itemTemplate.filename.precomposedStringWithCanonicalMapping;
    if (requestedName.length == 0 || [requestedName containsString:@"/"]) {
        finish(nil, [SeafFPErrors cannotSynchronize]);
        return progress;
    }
    // A re-import (the system lost track of the item) may come without
    // content: the file is dataless on disk and can only be matched by name.
    BOOL mayExist = (options & NSFileProviderCreateItemMayAlreadyExist) != 0;
    if (!isFolder && !url && !mayExist) {
        finish(nil, [SeafFPErrors cannotSynchronize]);
        return progress;
    }
    Debug("createItem %@ (%@) in %@ options=%lu", requestedName, isFolder ? @"folder" : @"file", parentIdentifier, (unsigned long)options);

    NSString *repoId = parentDir.repoId;
    NSString *parentUUID = parentRecord.uuid;
    __weak typeof(self) weakSelf = self;
    [self loadDirectory:parentDir completion:^(BOOL loaded, BOOL fromCache, NSError *loadError) {
        typeof(self) strongSelf = weakSelf;
        if (!loaded || fromCache || !strongSelf) {
            // Name collisions are resolved against the live listing only.
            finish(nil, loadError ?: [SeafFPErrors serverUnreachable]);
            return;
        }
        NSString *name = requestedName;
        NSString *existingName = [parentDir actualNameForCaseInsensitiveMatch:name];
        if (existingName) {
            SeafBase *existingObj = nil;
            for (SeafBase *obj in parentDir.items) {
                if (SeafFPNamesEqual(obj.name, existingName)) { existingObj = obj; break; }
            }
            BOOL existingIsDir = [existingObj isKindOfClass:[SeafDir class]];
            BOOL adopt = NO;
            if (existingObj && existingIsDir == isFolder) {
                if (isFolder) {
                    adopt = YES;   // a folder of that name is that folder
                } else if (mayExist) {
                    // Re-import: the server file is this item when the
                    // system's copy has no content, or the same size
                    // (design §7.6). Anything else is a version the server
                    // has not seen; it goes up under a free name below and
                    // neither side is overwritten.
                    long long localSize = url ? [strongSelf sizeOfFileAtURL:url] : -1;
                    adopt = !url || (localSize >= 0 && localSize == (long long)((SeafFile *)existingObj).filesize);
                }
            }
            if (adopt) {
                long long mtime = existingIsDir ? ((SeafDir *)existingObj).mtime : ((SeafFile *)existingObj).mtime;
                long long size = existingIsDir ? -1 : (long long)((SeafFile *)existingObj).filesize;
                SeafFPRecord *record = [strongSelf.store upsertRecordForRepo:repoId path:existingObj.path isDir:existingIsDir parentUUID:parentUUID oid:existingObj.oid mtime:mtime size:size];
                SeafFPItem *item = [strongSelf itemForRecord:record];
                [strongSelf applyTemplateDecoration:itemTemplate fields:fields toItem:item];
                finish(item, nil);
                return;
            }
            // Same name, different content: pick a free name like the app does.
            NSInteger guard = 0;
            while ([parentDir nameExist:name] && guard++ < 100) {
                name = [Utils creatNewFileName:name];
            }
        }
        if (!isFolder && !url) {
            // A dataless re-import that matches nothing on the server: nil
            // item and no error, the system drops its placeholder
            // (NSFileProviderReplicatedExtension.h, createItem).
            Debug("createItem %@: no content and no server entry, dropping", requestedName);
            finish(nil, nil);
            return;
        }
        NSString *fullPath = [SeafFPIdentifier normalizedPath:[parentDir.path stringByAppendingPathComponent:name]];

        if (isFolder) {
            [[SeafFileOperationManager sharedManager] mkdir:name inDir:parentDir completion:^(BOOL success, NSError *error) {
                if (!success) {
                    NSError *mapped = [SeafFPErrors errorForSeafError:error];
                    [strongSelf noteError:mapped];
                    finish(nil, mapped);
                    return;
                }
                SeafFPRecord *record = [strongSelf.store upsertRecordForRepo:repoId path:fullPath isDir:YES parentUUID:parentUUID oid:nil mtime:(long long)[[NSDate date] timeIntervalSince1970] size:-1];
                SeafFPItem *item = [strongSelf itemForRecord:record];
                [strongSelf applyTemplateDecoration:itemTemplate fields:fields toItem:item];
                [strongSelf noteSuccess];
                finish(item, nil);
            }];
            return;
        }

        NSError *stageError = nil;
        NSURL *staged = [strongSelf stageUploadSource:url name:name error:&stageError];
        if (!staged) {
            finish(nil, stageError);
            return;
        }
        [strongSelf uploadStagedFile:staged repoId:repoId path:fullPath parentUUID:parentUUID progress:progress completion:^(SeafFPRecord *record, NSError *error) {
            if (!record) {
                finish(nil, error);
                return;
            }
            SeafFPItem *item = [strongSelf itemForRecord:record];
            [strongSelf applyTemplateDecoration:itemTemplate fields:fields toItem:item];
            finish(item, nil);
        }];
    }];
    return progress;
}

#pragma mark - NSFileProviderReplicatedExtension: modify

- (NSProgress *)modifyItem:(NSFileProviderItem)item
               baseVersion:(NSFileProviderItemVersion *)version
             changedFields:(NSFileProviderItemFields)changedFields
                  contents:(NSURL *)newContents
                   options:(NSFileProviderModifyItemOptions)options
                   request:(NSFileProviderRequest *)request
         completionHandler:(void (^)(NSFileProviderItem _Nullable, NSFileProviderItemFields, BOOL, NSError * _Nullable))completionHandler
{
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:100];
    __block BOOL done = NO;
    BOOL (^claim)(void) = ^BOOL{
        @synchronized (progress) {
            if (done) return NO;   // a cancel racing the operation must not answer twice
            done = YES;
            return YES;
        }
    };
    void (^finish)(SeafFPItem *, NSError *) = ^(SeafFPItem *result, NSError *error) {
        if (!claim()) return;
        progress.completedUnitCount = progress.totalUnitCount;
        completionHandler(result, 0, NO, error);
    };
    // shouldFetchContent: the system replaces its copy of the file with what
    // fetchContents serves for the returned item.
    void (^finishFetchingContent)(SeafFPItem *) = ^(SeafFPItem *result) {
        if (!claim()) return;
        progress.completedUnitCount = progress.totalUnitCount;
        completionHandler(result, 0, YES, nil);
    };
    // A rename or move that already reached the server is not undone by a
    // cancel; the store and the answer stay in step through the once guard.
    // The upload step installs a handler that also aborts the transfer.
    progress.cancellationHandler = ^{
        finish(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
    };

    // Local state is consulted first (decorations work without a session),
    // but only when it is actually available: a closed store must not turn
    // every item into NoSuchItem.
    NSError *error = [self localAccessError];
    if (error) {
        finish(nil, error);
        return progress;
    }
    SeafFPItem *current = [self resolveItem:item.itemIdentifier error:&error];
    if (!current) {
        finish(nil, error ?: [SeafFPErrors noSuchItem]);
        return progress;
    }

    // Favorite rank, tags and last-used date live on this device only. They
    // are stored locally and the item is answered with the stored values;
    // answering without them would make Files drop the favorite.
    NSFileProviderItemFields decorationFields = NSFileProviderItemFavoriteRank | NSFileProviderItemTagData | NSFileProviderItemLastUsedDate;
    if (changedFields & decorationFields) {
        [self applyDecorationChangesFromItem:item changedFields:changedFields toItem:current];
    }

    SeafFPIdentifierKind kind = [SeafFPIdentifier kindOfIdentifier:item.itemIdentifier];
    SeafFPRecord *record = kind == SeafFPIdentifierKindItem
        ? [self.store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:item.itemIdentifier]] : nil;
    if (!record) {
        // The domain root, libraries and the trash are server-owned containers:
        // renames, moves and uploads targeting them are answered with the
        // unchanged item so the system reverts its local change.
        finish(current, nil);
        return progress;
    }

    BOOL renamed = (changedFields & NSFileProviderItemFilename) != 0
        && item.filename.length > 0
        && !SeafFPNamesEqual(item.filename, record.name);
    BOOL reparented = (changedFields & NSFileProviderItemParentItemIdentifier) != 0
        && item.parentItemIdentifier.length > 0
        && ![item.parentItemIdentifier isEqualToString:record.parentItemIdentifier];
    BOOL contentsChanged = (changedFields & NSFileProviderItemContents) != 0
        && !record.isDir
        && newContents != nil;
    if (!renamed && !reparented && !contentsChanged) {
        finish(current, nil);
        return progress;
    }
    NSError *access = [self accessError];
    if (access) {
        finish(nil, access);
        return progress;
    }
    if ([self repoListUnknownFor:record.repoId]) {
        finish(nil, [SeafFPErrors serverUnreachable]);   // cold process: permissions unknown yet, retry later
        return progress;
    }
    if (![self isRepoEditable:record.repoId]) {
        if (contentsChanged) {
            // Files keeps offering the editor (AllowsWriting stays set, see
            // SeafFPItem). The unchanged item alone would make the system take
            // the edited copy for the server version; the edit is dropped by
            // fetching the server content back instead.
            Debug("modifyItem %@: content change in a read-only library, reverting to the server content", item.itemIdentifier);
            finishFetchingContent(current);
        } else {
            finish(current, nil);
        }
        return progress;
    }
    Debug("modifyItem %@ renamed=%d reparented=%d contents=%d", item.itemIdentifier, renamed, reparented, contentsChanged);

    __weak typeof(self) weakSelf = self;
    void (^uploadIfNeeded)(SeafFPRecord *) = ^(SeafFPRecord *latest) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { finish(nil, [SeafFPErrors cannotSynchronize]); return; }
        if (!contentsChanged) {
            finish([strongSelf itemForRecord:latest], nil);
            return;
        }
        NSError *stageError = nil;
        NSURL *staged = [strongSelf stageUploadSource:newContents name:latest.name error:&stageError];
        if (!staged) {
            finish(nil, stageError);
            return;
        }
        // First version: the device copy wins, the server keeps the history.
        [strongSelf uploadStagedFile:staged repoId:latest.repoId path:latest.path parentUUID:latest.parentUUID progress:progress completion:^(SeafFPRecord *uploaded, NSError *uploadError) {
            if (!uploaded) {
                finish(nil, uploadError);
                return;
            }
            finish([strongSelf itemForRecord:uploaded], nil);
        }];
    };

    if (!renamed && !reparented) {
        uploadIfNeeded(record);
        return progress;
    }

    SeafFPRecord *dstRecord = nil;
    NSString *srcContainer = record.parentItemIdentifier;
    NSString *dstContainer = reparented ? item.parentItemIdentifier : srcContainer;
    SeafDir *srcDir = [self seafDirForContainer:srcContainer record:NULL];
    SeafDir *dstDir = [self seafDirForContainer:dstContainer record:&dstRecord];
    if (!srcDir || !dstDir || ![self isRepoEditable:dstDir.repoId]) {
        finish(nil, [SeafFPErrors cannotSynchronize]);
        return progress;
    }
    NSString *requestedName = renamed ? item.filename.precomposedStringWithCanonicalMapping : record.name;
    NSString *dstParentUUID = dstRecord.uuid;
    NSString *oldName = record.name;

    void (^applyMove)(NSString *) = ^(NSString *finalName) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { finish(nil, [SeafFPErrors cannotSynchronize]); return; }
        NSString *newPath = [SeafFPIdentifier normalizedPath:[dstDir.path stringByAppendingPathComponent:finalName]];
        SeafFPRecord *moved = [strongSelf.store moveRecordUUID:record.uuid toRepo:dstDir.repoId path:newPath parentUUID:dstParentUUID];
        [strongSelf forgetSeafObjectsForRecord:record];
        [strongSelf noteSuccess];
        [strongSelf signalContainer:srcContainer];
        if (![dstContainer isEqualToString:srcContainer]) {
            [strongSelf signalContainer:dstContainer];
        }
        uploadIfNeeded(moved ?: record);
    };
    // The server did rename / move the entry, but under a name the listing
    // cannot tell apart. Binding the record to a guessed name would tombstone
    // whatever really lives there and hand this record's identity (favorite,
    // tags) to that file, so the record is retired instead: the system drops
    // its copy and the next listing of the destination brings the file back
    // as a new item. Its decorations, and a content change made in the same
    // call, are lost.
    void (^giveUp)(void) = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { finish(nil, [SeafFPErrors cannotSynchronize]); return; }
        Warning("modifyItem %@: cannot tell which entry of %@ is %@ now, retiring the record", item.itemIdentifier, dstDir.path, requestedName);
        [strongSelf.store markDeletedUUID:record.uuid];
        [strongSelf forgetSeafObjectsForRecord:record];
        [strongSelf noteSuccess];
        [strongSelf signalWorkingSet];
        finish(nil, nil);
    };
    void (^fail)(NSError *) = ^(NSError *opError) {
        NSError *mapped = [SeafFPErrors errorForSeafError:opError];
        [weakSelf noteError:mapped];
        finish(nil, mapped);
    };
    // Reads the entry's actual name back from a live listing of `dir` and
    // goes on with it; without a live listing nothing can be confirmed.
    void (^settle)(SeafDir *, NSString *, void (^)(NSString *)) = ^(SeafDir *dir, NSString *expected, void (^next)(NSString *)) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { finish(nil, [SeafFPErrors cannotSynchronize]); return; }
        [strongSelf loadDirectory:dir completion:^(BOOL loaded, BOOL fromCache, NSError *listError) {
            typeof(self) listSelf = weakSelf;
            if (!listSelf) { finish(nil, [SeafFPErrors cannotSynchronize]); return; }
            NSString *finalName = nil;
            if (loaded && !fromCache) {
                finalName = [listSelf finalNameForRecord:record expected:expected inDir:dir];
            } else {
                // No live listing right after the operation. The name was
                // checked against one moments ago, so it stands unless the
                // store knows another live file at that path.
                NSString *path = [SeafFPIdentifier normalizedPath:[dir.path stringByAppendingPathComponent:expected]];
                SeafFPRecord *occupant = [listSelf.store recordForRepo:dir.repoId path:path includeDeleted:NO];
                if (!occupant || [occupant.uuid isEqualToString:record.uuid]) finalName = expected;
            }
            if (finalName) next(finalName); else giveUp();
        }];
    };
    void (^moveStep)(NSString *) = ^(NSString *name) {
        [[SeafFileOperationManager sharedManager] moveEntries:@[name] fromDir:srcDir toDir:dstDir completion:^(BOOL success, NSError *moveError) {
            typeof(self) strongSelf = weakSelf;
            if (!success) {
                if (strongSelf && !SeafFPNamesEqual(name, oldName)) {
                    // Renamed but not moved: keep the store in step, the system retries the move.
                    NSString *renamedPath = [SeafFPIdentifier normalizedPath:[srcDir.path stringByAppendingPathComponent:name]];
                    [strongSelf.store moveRecordUUID:record.uuid toRepo:record.repoId path:renamedPath parentUUID:record.parentUUID];
                    [strongSelf forgetSeafObjectsForRecord:record];
                }
                fail(moveError);
                return;
            }
            settle(dstDir, name, applyMove);
        }];
    };
    // The rename goes first so it only ever touches our own entry in the
    // source directory. The SDK looks the renamed entry up by name: one it
    // could not find (-5), or one with another content id, may be a file the
    // server gave a free name to, and is confirmed against a live listing.
    void (^renameStep)(NSString *, void (^)(NSString *)) = ^(NSString *name, void (^next)(NSString *)) {
        [[SeafFileOperationManager sharedManager] renameEntry:oldName newName:name inDir:srcDir completion:^(BOOL success, SeafBase *renamedFile, NSError *renameError) {
            if (!SeafFPRenameSucceeded(success, renameError)) { fail(renameError); return; }
            BOOL confirmed = success && record.oid.length > 0 && [renamedFile.oid isEqualToString:record.oid];
            if (confirmed) next(name); else settle(srcDir, name, next);
        }];
    };
    // Names are settled against live listings before anything changes on the
    // server, so it rarely has to pick one itself: a clash in the destination
    // (a file the system does not know yet) gets a free name the way
    // createItem does, and the system writes that name to disk.
    void (^start)(void) = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { finish(nil, [SeafFPErrors cannotSynchronize]); return; }
        NSArray<SeafDir *> *dirs = reparented ? @[dstDir, srcDir] : @[srcDir];
        NSString *name = [strongSelf freeNameFor:requestedName inDirs:dirs ownName:oldName inDir:srcDir];
        if (!SeafFPNamesEqual(name, requestedName)) {
            Debug("modifyItem %@: %@ is taken in %@, using %@", item.itemIdentifier, requestedName, dstDir.path, name);
        }
        void (^afterRename)(NSString *) = reparented ? moveStep : applyMove;
        if (SeafFPNamesEqual(name, oldName)) afterRename(name); else renameStep(name, afterRename);
    };
    // Unreachable here means nothing has happened on the server yet: the
    // system retries later.
    void (^listThen)(SeafDir *, BOOL, dispatch_block_t) = ^(SeafDir *dir, BOOL needed, dispatch_block_t next) {
        if (!needed) { next(); return; }
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { finish(nil, [SeafFPErrors cannotSynchronize]); return; }
        [strongSelf loadDirectory:dir completion:^(BOOL loaded, BOOL fromCache, NSError *listError) {
            if (!loaded || fromCache) { finish(nil, listError ?: [SeafFPErrors serverUnreachable]); return; }
            next();
        }];
    };
    listThen(dstDir, reparented, ^{
        listThen(srcDir, renamed, start);
    });
    return progress;
}

#pragma mark - NSFileProviderReplicatedExtension: delete

- (NSProgress *)deleteItemWithIdentifier:(NSFileProviderItemIdentifier)identifier
                             baseVersion:(NSFileProviderItemVersion *)version
                                 options:(NSFileProviderDeleteItemOptions)options
                                 request:(NSFileProviderRequest *)request
                       completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
    __block BOOL done = NO;
    void (^finish)(NSError *) = ^(NSError *error) {
        @synchronized (progress) {
            if (done) return;   // a cancel racing the server reply must not answer twice
            done = YES;
        }
        progress.completedUnitCount = 1;
        completionHandler(error);
    };
    // The server request cannot be aborted; a cancel answers at once and the
    // reply, if it still comes, is dropped by the once guard. The store is
    // only updated from that reply, so a late success is picked up by the
    // next listing instead.
    progress.cancellationHandler = ^{
        finish([NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
    };
    SeafFPIdentifierKind kind = [SeafFPIdentifier kindOfIdentifier:identifier];
    if (kind != SeafFPIdentifierKindItem) {
        // Root, libraries and the trash are server-owned: the system puts them back.
        finish(kind == SeafFPIdentifierKindUnknown ? [SeafFPErrors noSuchItem] : [SeafFPErrors deletionRejected]);
        return progress;
    }
    // "Already gone" is only a safe answer when the store could be consulted.
    NSError *access = [self accessError];
    if (access) {
        finish(access);
        return progress;
    }
    SeafFPRecord *record = [self.store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:identifier]];
    if (!record || record.deleted) {
        finish(nil);   // already gone
        return progress;
    }
    if ([self repoListUnknownFor:record.repoId]) {
        finish([SeafFPErrors serverUnreachable]);   // cold process: permissions unknown yet, retry later
        return progress;
    }
    if (![self isRepoEditable:record.repoId]) {
        finish([SeafFPErrors deletionRejected]);
        return progress;
    }
    SeafDir *parentDir = [self seafDirForContainer:record.parentItemIdentifier record:NULL];
    if (!parentDir) {
        finish([SeafFPErrors noSuchItem]);
        return progress;
    }
    Debug("deleteItem %@ (%@) options=%lu", identifier, record.path, (unsigned long)options);

    __weak typeof(self) weakSelf = self;
    void (^deleteOnServer)(void) = ^{
        [[SeafFileOperationManager sharedManager] deleteEntries:@[record.name] inDir:parentDir completion:^(BOOL success, NSError *error) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) { finish([SeafFPErrors cannotSynchronize]); return; }
            NSError *mapped = success ? nil : [SeafFPErrors errorForSeafError:error];
            if (mapped && mapped.code != NSFileProviderErrorNoSuchItem) {
                [strongSelf noteError:mapped];
                finish(mapped);
                return;
            }
            for (SeafFPRecord *gone in [strongSelf.store subtreeRecordsOfUUID:record.uuid]) {
                [strongSelf.store removeDecorationForItem:gone.itemIdentifier];
                [strongSelf.store removeWorkingSetItem:gone.itemIdentifier];
                [strongSelf.seafObjects removeObjectForKey:gone.itemIdentifier];
            }
            [strongSelf.store markDeletedUUID:record.uuid];
            [strongSelf noteSuccess];
            [strongSelf signalContainer:record.parentItemIdentifier];
            finish(nil);
        }];
    };

    if (record.isDir && (options & NSFileProviderDeleteItemRecursive) == 0) {
        // Without the recursive flag only an empty folder may go.
        SeafDir *dir = [self seafDirForContainer:identifier record:NULL];
        [self loadDirectory:dir completion:^(BOOL loaded, BOOL fromCache, NSError *loadError) {
            if (!loaded) { finish(loadError); return; }
            if (fromCache) {
                // "Empty" must come from the server: the delete is recursive there.
                finish([SeafFPErrors serverUnreachable]);
                return;
            }
            if (dir.items.count > 0) {
                finish([NSError errorWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorDirectoryNotEmpty userInfo:nil]);
                return;
            }
            deleteOnServer();
        }];
        return progress;
    }
    deleteOnServer();
    return progress;
}

#pragma mark - NSFileProviderReplicatedExtension: enumeration

- (id<NSFileProviderEnumerator>)enumeratorForContainerItemIdentifier:(NSFileProviderItemIdentifier)containerItemIdentifier
                                                             request:(NSFileProviderRequest *)request
                                                               error:(NSError **)error
{
    SeafFPIdentifierKind kind = [SeafFPIdentifier kindOfIdentifier:containerItemIdentifier];
    switch (kind) {
        case SeafFPIdentifierKindTrash:
            // No item carries AllowsTrashing: the contract for a provider
            // without a trash is NSFeatureUnsupportedError here, not an
            // empty listing (NSFileProviderReplicatedExtension.h).
            if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFeatureUnsupportedError userInfo:nil];
            return nil;
        case SeafFPIdentifierKindWorkingSet:
            return [[SeafFPEnumerator alloc] initWithExtension:self containerIdentifier:containerItemIdentifier];
        case SeafFPIdentifierKindRoot:
        case SeafFPIdentifierKindRepo:
        case SeafFPIdentifierKindItem: {
            NSError *access = [self accessError];
            if (access) {
                if (error) *error = access;
                return nil;
            }
            if (kind == SeafFPIdentifierKindItem) {
                SeafFPRecord *record = [self.store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:containerItemIdentifier]];
                if (!record || record.deleted || !record.isDir) {
                    if (error) *error = [SeafFPErrors noSuchItem];
                    return nil;
                }
            }
            return [[SeafFPEnumerator alloc] initWithExtension:self containerIdentifier:containerItemIdentifier];
        }
        default:
            if (error) *error = [SeafFPErrors noSuchItem];
            return nil;
    }
}

- (void)importDidFinishWithCompletionHandler:(void (^)(void))completionHandler
{
    completionHandler();
}

- (void)pendingItemsDidChangeWithCompletionHandler:(void (^)(void))completionHandler
{
    completionHandler();
}

#pragma mark - Working set maintenance

/// Walks the system's materialized-items enumerator page by page.
- (void)collectMaterializedItemsFrom:(id<NSFileProviderEnumerator>)enumerator
                                page:(NSFileProviderPage)page
                                into:(NSMutableArray<NSFileProviderItemIdentifier> *)all
                          completion:(void (^)(NSError * _Nullable error))completion
{
    SeafFPMaterializedCollector *collector = [SeafFPMaterializedCollector new];
    __weak typeof(self) weakSelf = self;
    __block SeafFPMaterializedCollector *retained = collector;
    collector.completion = ^(NSArray<NSFileProviderItemIdentifier> *identifiers, NSFileProviderPage nextPage, NSError *error) {
        retained.completion = nil;
        retained = nil;
        if (error) {
            completion(error);
            return;
        }
        [all addObjectsFromArray:identifiers];
        typeof(self) strongSelf = weakSelf;
        if (nextPage && strongSelf) {
            [strongSelf collectMaterializedItemsFrom:enumerator page:nextPage into:all completion:completion];
        } else {
            completion(nil);
        }
    };
    [enumerator enumerateItemsForObserver:collector startingAtPage:page];
}

// Keeps the "materialized" bit of the working set in step with what the
// system holds on disk, so those directories take part in the working set
// checks (design §7.10).
- (void)materializedItemsDidChangeWithCompletionHandler:(void (^)(void))completionHandler
{
    id<NSFileProviderEnumerator> enumerator = [self.manager enumeratorForMaterializedItems];
    if (!enumerator || !self.store) {
        completionHandler();
        return;
    }
    NSMutableArray<NSFileProviderItemIdentifier> *all = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    [self collectMaterializedItemsFrom:enumerator page:NSFileProviderInitialPageSortedByName into:all completion:^(NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (error || !strongSelf) {
            Debug("materialized items enumeration failed: %@", error);
            completionHandler();
            return;
        }
        NSMutableArray<NSFileProviderItemIdentifier> *items = [NSMutableArray array];
        for (NSFileProviderItemIdentifier identifier in all) {
            SeafFPIdentifierKind kind = [SeafFPIdentifier kindOfIdentifier:identifier];
            if (kind == SeafFPIdentifierKindRepo || kind == SeafFPIdentifierKindItem) {
                [items addObject:identifier];
            }
        }
        [strongSelf.store replaceMaterializedItemIdentifiers:items];
        Debug("materialized items: %lu", (unsigned long)items.count);
        completionHandler();
    }];
}

#pragma mark - NSFileProviderThumbnailing

+ (NSData *)thumbnailJPEGFromImage:(UIImage *)image requestedSize:(CGSize)requestedSize
{
    if (!image) return nil;
    CGSize source = image.size;
    if (source.width <= 0 || source.height <= 0) return nil;
    CGFloat maxSide = MAX(requestedSize.width, requestedSize.height);
    if (maxSide <= 0) maxSide = 256;
    CGFloat scale = MIN(1.0, maxSide / MAX(source.width, source.height));
    CGSize target = CGSizeMake(MAX(1, floor(source.width * scale)), MAX(1, floor(source.height * scale)));
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
    UIImage *scaled = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    }];
    return UIImageJPEGRepresentation(scaled, 0.85);
}

- (NSProgress *)fetchThumbnailsForItemIdentifiers:(NSArray<NSFileProviderItemIdentifier> *)itemIdentifiers
                                    requestedSize:(CGSize)size
                    perThumbnailCompletionHandler:(void (^)(NSFileProviderItemIdentifier, NSData * _Nullable, NSError * _Nullable))perThumbnailCompletionHandler
                                completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:itemIdentifiers.count];
    if (itemIdentifiers.count == 0) {
        completionHandler(nil);
        return progress;
    }
    __block NSInteger remaining = itemIdentifiers.count;
    __block BOOL answered = NO;
    NSObject *lock = [NSObject new];
    void (^finishOne)(void) = ^{
        BOOL done = NO;
        @synchronized (lock) {
            progress.completedUnitCount += 1;
            remaining -= 1;
            done = (remaining == 0 && !answered);
            if (done) answered = YES;
        }
        if (done) completionHandler(nil);
    };
    // Queued requests see isCancelled and answer their items with nil; the
    // batch itself is answered here, once, as the system expects.
    progress.cancellationHandler = ^{
        @synchronized (lock) {
            if (answered) return;
            answered = YES;
        }
        completionHandler([NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
    };

    for (NSFileProviderItemIdentifier identifier in itemIdentifiers) {
        SeafFPRecord *record = [self.store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:identifier]];
        SeafFile *file = record.isDir ? nil : [self seafFileForRecord:record];
        if (!file || ![Utils isServerThumbFile:file.name]) {
            perThumbnailCompletionHandler(identifier, nil, nil);   // no thumbnail for this item
            finishOne();
            continue;
        }
        UIImage *thumb = file.thumb;
        if (thumb) {
            perThumbnailCompletionHandler(identifier, [self.class thumbnailJPEGFromImage:thumb requestedSize:size], nil);
            finishOne();
            continue;
        }
        [self requestThumbnailForFile:file identifier:identifier progress:progress completion:^(UIImage * _Nullable image) {
            NSData *data = [self.class thumbnailJPEGFromImage:image requestedSize:size];
            if (data) {
                perThumbnailCompletionHandler(identifier, data, nil);
            } else {
                // A thumbnail that could not be fetched is a per-item, cosmetic
                // failure. NSFileProviderErrorServerUnreachable here makes
                // fileproviderd throttle the whole domain ("!" on the location,
                // "Sync paused"), so report a generic error instead.
                perThumbnailCompletionHandler(identifier, nil, [NSError errorWithDomain:NSCocoaErrorDomain
                                                                                    code:NSFileReadUnknownError
                                                                                userInfo:nil]);
            }
            finishOne();
        }];
    }
    return progress;
}

#pragma mark - Thumbnail requests

// Files asks for a screenful of thumbnails at once. Requests for the same
// item share one SDK task, and at most kSeafFPThumbMaxInFlight tasks are
// handed to the SDK at a time so the extension stays inside its memory and
// time budget.
- (void)requestThumbnailForFile:(SeafFile *)file
                     identifier:(NSFileProviderItemIdentifier)identifier
                       progress:(NSProgress *)progress
                     completion:(void (^)(UIImage * _Nullable))completion
{
    NSUInteger generation = 0;
    @synchronized (self.thumbWaiters) {
        NSMutableArray *waiters = self.thumbWaiters[identifier];
        if (waiters) {
            [waiters addObject:[completion copy]];
            return;   // a task for this item is already queued or running
        }
        self.thumbWaiters[identifier] = [NSMutableArray arrayWithObject:[completion copy]];
        generation = self.thumbGenerations[identifier].unsignedIntegerValue + 1;
        self.thumbGenerations[identifier] = @(generation);
    }
    __weak typeof(self) weakSelf = self;
    __weak SeafFile *weakFile = file;
    [self enqueueThumbTask:^{
        typeof(self) strongSelf = weakSelf;
        SeafFile *strongFile = weakFile;
        // Tasks reach here asynchronously; after invalidate the waiters are
        // gone and nothing must be handed to the SDK any more.
        if (!strongSelf || strongSelf.invalidated) return;
        if (!strongFile || progress.isCancelled) {
            [strongSelf finishThumbnailForIdentifier:identifier image:nil generation:generation];
            return;
        }
        [strongFile setThumbCompleteBlock:^(BOOL ret) {
            SeafFile *doneFile = weakFile;
            [doneFile setThumbCompleteBlock:nil];
            UIImage *image = ret ? doneFile.thumb : nil;   // cached decode, corrupt files are dropped
            [weakSelf finishThumbnailForIdentifier:identifier image:image generation:generation];
        }];
        [strongSelf whenReachabilityKnown:^{
            [SeafDataTaskManager.sharedObject addThumbTask:[[SeafThumb alloc] initWithSeafFile:strongFile]];
        }];
        // A cancelled or dropped SDK operation never reports back; do not let
        // it keep a slot forever.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSeafFPThumbTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf finishThumbnailForIdentifier:identifier image:nil generation:generation];
        });
    }];
}

- (void)finishThumbnailForIdentifier:(NSFileProviderItemIdentifier)identifier image:(UIImage *)image generation:(NSUInteger)generation
{
    NSArray *waiters = nil;
    @synchronized (self.thumbWaiters) {
        waiters = [self.thumbWaiters[identifier] copy];
        // Already answered (or timed out): the slot was released then. A timer
        // from an earlier request of the same item must not touch a newer one.
        if (!waiters || self.thumbGenerations[identifier].unsignedIntegerValue != generation) return;
        [self.thumbWaiters removeObjectForKey:identifier];
    }
    for (void (^waiter)(UIImage *) in waiters) {
        waiter(image);
    }
    [self thumbTaskDidFinish];
}

- (void)enqueueThumbTask:(dispatch_block_t)task
{
    BOOL runNow = NO;
    @synchronized (self.pendingThumbTasks) {
        if (self.thumbInFlight < kSeafFPThumbMaxInFlight) {
            self.thumbInFlight += 1;
            runNow = YES;
        } else {
            [self.pendingThumbTasks addObject:[task copy]];
        }
    }
    // SeafFile's thumb bookkeeping is main-queue affine: every task runs
    // there, whether it starts now or is handed a slot later.
    if (runNow) dispatch_async(dispatch_get_main_queue(), task);
}

// Hands the finished task's slot to the next queued one, or frees it.
- (void)thumbTaskDidFinish
{
    dispatch_block_t next = nil;
    @synchronized (self.pendingThumbTasks) {
        if (self.pendingThumbTasks.count > 0) {
            next = self.pendingThumbTasks.firstObject;
            [self.pendingThumbTasks removeObjectAtIndex:0];
        } else if (self.thumbInFlight > 0) {
            self.thumbInFlight -= 1;
        }
    }
    if (next) {
        // SeafFile's thumb bookkeeping is main-queue affine.
        dispatch_async(dispatch_get_main_queue(), next);
    }
}

@end
