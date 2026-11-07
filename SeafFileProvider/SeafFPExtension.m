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
#import "SeafFPCheckSchedule.h"
#import "SeafFPErrorResolution.h"
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

/// What the listings say about a journaled move.
typedef NS_ENUM(NSInteger, SeafFPMoveOutcome) {
    SeafFPMoveOutcomeResolved,      // the item is at the destination under `name`
    SeafFPMoveOutcomeUnknown,       // listings unavailable (error) or inconclusive (no error)
};

/// How recoverMoveOfRecord: ended a journal.
typedef NS_ENUM(NSInteger, SeafFPMoveSettlement) {
    SeafFPMoveSettlementRecovered,  // the original identity is at the journal's destination
    SeafFPMoveSettlementExpired,    // past the grace: the source was re-listed and the journal dropped
};

static long long SeafFPServerTime(NSString *date)
{
    if (date.length == 0) return 0;
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss zzz";
    return (long long)[[formatter dateFromString:date] timeIntervalSince1970];
}

/// Transport errors raised before a request could reach the server: a
/// mutation that failed this way was certainly not applied. Timeouts and
/// connection losses are not among them (the request may have arrived).
static BOOL SeafFPRequestNeverReachedServer(NSError *error)
{
    if (![error.domain isEqual:NSURLErrorDomain]) return NO;
    switch (error.code) {
        case NSURLErrorNotConnectedToInternet:
        case NSURLErrorCannotFindHost:
        case NSURLErrorCannotConnectToHost:
        case NSURLErrorDNSLookupFailed:
        case NSURLErrorSecureConnectionFailed:
        case NSURLErrorServerCertificateHasBadDate:
        case NSURLErrorServerCertificateUntrusted:
        case NSURLErrorServerCertificateHasUnknownRoot:
        case NSURLErrorServerCertificateNotYetValid:
        case NSURLErrorClientCertificateRejected:
        case NSURLErrorClientCertificateRequired:
        case NSURLErrorDataNotAllowed:
        case NSURLErrorInternationalRoamingOff:
        case NSURLErrorCallIsActive:
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
        case NSURLErrorUnsupportedURL:
        case NSURLErrorBadURL:
            return YES;
        default:
            return NO;
    }
}

@interface SeafFPExtension ()
@property (nonatomic, strong) NSFileProviderDomain *domain;
@property (nonatomic, strong) NSFileProviderManager *manager;
@property (strong, nullable) SeafConnection *connection;
@property (strong, nullable) SeafFPStore *store;
@property (nonatomic, strong) SeafFPCheckSchedule *checkSchedule;
@property (nonatomic, strong) NSCache<NSString *, SeafBase *> *seafObjects;
// Content fetches waiting for the one SDK download that serves an item.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *contentWaiters;
@property (atomic, assign) BOOL invalidated;
// Bumped per thumbnail request of an item, so a timer armed for an earlier
// request cannot answer (and release the slot of) a later one.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *thumbGenerations;
// Errors answered to the system and not signalled as resolved yet, by error
// code, and when each may be (SeafFPErrorResolution).
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSError *> *unresolvedErrors;
@property (nonatomic, strong) SeafFPErrorResolution *errorResolution;
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
        _checkSchedule = [SeafFPCheckSchedule new];
        _unresolvedErrors = [NSMutableDictionary dictionary];
        _errorResolution = [SeafFPErrorResolution new];

        [SeafGlobal.sharedObject loadAccounts];
        (void)[SeafDataTaskManager sharedObject];
        _connection = [self lookupConnection];

        NSError *error = nil;
        _store = [[SeafFPStore alloc] initWithDomainIdentifier:domain.identifier error:&error];
        if (!_store) {
            Warning("Cannot open store for domain %@: %@", domain.identifier, error);
        }
        Info("File provider started for domain %@ (%@), account %@", domain.identifier, domain.displayName,
              _connection ? [NSString stringWithFormat:@"%@ @ %@", _connection.username, _connection.address] : @"<none>");
    }
    return self;
}

- (void)invalidate
{
    Info("invalidate domain %@", self.domain.identifier);
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
            Info("Account %@ library passwords changed, dropping cached objects", current.username);
            [self.seafObjects removeAllObjects];
        }
        return;
    }
    SeafConnection *fresh = [[SeafConnection alloc] initWithUrl:current.address
                                                  cacheProvider:SeafGlobal.sharedObject.cacheProvider
                                                       username:current.username];
    Info("Account %@ session changed, refreshing connection", fresh.username);
    self.connection = fresh;
    [self.seafObjects removeAllObjects];
    [self.checkSchedule reset];   // what failed for the old session says nothing about this one
    [self.errorResolution forgetWaits];
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
    [self noteError:error aboutOneItem:NO];
}

- (void)noteError:(NSError *)error aboutOneItem:(BOOL)aboutOneItem
{
    if (![error.domain isEqualToString:NSFileProviderErrorDomain]) return;
    switch (error.code) {
        case NSFileProviderErrorServerUnreachable:
        case NSFileProviderErrorNotAuthenticated:
        case NSFileProviderErrorCannotSynchronize:
        case NSFileProviderErrorInsufficientQuota:
            @synchronized (self.unresolvedErrors) {
                self.unresolvedErrors[@(error.code)] = error;
            }
            {
                NSDate *now = [NSDate date];
                [self.errorResolution noteErrorWithCode:error.code aboutOneItem:aboutOneItem at:now];
                NSDate *until = [self.errorResolution resolutionOfCode:error.code heldUntilAt:now];
                if (until) Info("error %ld came back after it was resolved, not resolved again before %@", (long)error.code, until);
            }
            break;
        default:
            break;
    }
}

// Every fresh listing ends here, a working set pass about every two minutes
// among them, and signalErrorResolved: makes the system retry what it
// throttled for that error. A refusal of one item that was resolved and came
// back is therefore held back for a while (SeafFPErrorResolution): the
// listing says nothing about it.
- (void)noteSuccess
{
    for (NSNumber *code in [self.errorResolution codesToResolveAt:[NSDate date]]) {
        NSError *error = nil;
        @synchronized (self.unresolvedErrors) {
            error = self.unresolvedErrors[code];
            [self.unresolvedErrors removeObjectForKey:code];
        }
        if (!error) continue;
        [self.manager signalErrorResolved:error completionHandler:^(NSError * _Nullable signalError) {
            if (signalError) {
                Info("signalErrorResolved failed: %@", signalError);
            }
        }];
    }
}

#pragma mark - Model helpers

- (SeafRepo *)repoWithId:(NSString *)repoId
{
    if (repoId.length == 0) return nil;
    return [self.connection getRepo:repoId];
}

- (BOOL)isRepoEditable:(NSString *)repoId
{
    NSDictionary *state = [self.store repositoryStates][repoId];
    if (state) return [state[@"availability"] isEqual:@"visible"] && [state[@"editable"] boolValue];
    return [self repoWithId:repoId].editable;
}

- (NSError *)repositoryAccessError:(NSString *)repoId
{
    NSDictionary *states = [self.store repositoryStates];
    if (!states) return [SeafFPErrors cannotSynchronize];
    NSDictionary *state = states[repoId];
    if ([state[@"availability"] isEqual:@"removed"]) return [SeafFPErrors noSuchItem];
    if ([state[@"availability"] isEqual:@"locked"] || [self repoWithId:repoId].passwordRequired) return [SeafFPErrors notAuthenticated];
    return nil;
}

- (BOOL)repoListUnknownFor:(NSString *)repoId
{
    if (repoId.length == 0) return NO;
    if ([self.store repositoryStates][repoId]) return NO;
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
    // Shared metadata is sufficient for offline enumeration even if this
    // extension process has never loaded the SDK's in-memory library model.
    if ([self.store repositoryStates].count > 0 || [self.store hasAuthoritativeRepositoryList]) {
        completion(YES, NO);
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
        Info("library list unavailable (%@), cache: %d", error, cached);
        completion(cached, NO);
    }];
}

- (SeafFPItem *)itemForRepo:(SeafRepo *)repo
{
    NSDictionary *state = [self.store repositoryStates][repo.repoId];
    if (state) return [self itemForRepositoryState:state];
    SeafFPItem *item = [SeafFPItem itemForRepo:repo];
    [item applyDecoration:[self.store decorationForItem:item.itemIdentifier]];
    return item;
}

- (SeafFPItem *)itemForRepositoryState:(NSDictionary *)state
{
    SeafFPItem *item = [SeafFPItem itemForRepositoryMetadata:state];
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
            NSString *repoId = [SeafFPIdentifier repoIdFromIdentifier:identifier];
            NSError *access = [self repositoryAccessError:repoId];
            if (access) { if (error) *error = access; return nil; }
            NSDictionary *state = [self.store repositoryStates][repoId];
            if (state) return [self itemForRepositoryState:state];
            SeafRepo *repo = [self repoWithId:repoId];
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
            NSError *access = [self repositoryAccessError:record.repoId];
            if (access) { if (error) *error = access; return nil; }
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
            NSString *repoId = [SeafFPIdentifier repoIdFromIdentifier:containerIdentifier];
            NSDictionary *state = [self.store repositoryStates][repoId];
            NSString *availability = state[@"availability"];
            if ([availability isEqual:@"removed"] || [availability isEqual:@"locked"]) return nil;
            SeafRepo *repo = [self repoWithId:repoId];
            if (repo) return repo.passwordRequired ? nil : repo;
            if (![availability isEqual:@"visible"]) return nil;
            // A library root uses the same directory endpoint and cache key
            // as SeafDir. The other process may have published it first.
            return [[SeafDir alloc] initWithConnection:self.connection
                                                  oid:nil
                                               repoId:repoId
                                                 perm:state[@"perm"]
                                                 name:state[@"name"] ?: repoId
                                                 path:@"/"
                                                mtime:[state[@"mtime"] longLongValue]];
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
    NSError *repositoryAccess = [self repositoryAccessError:record.repoId];
    if (repositoryAccess) { finish(nil, nil, repositoryAccess); return progress; }
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
        NSError *repositoryAccess = [strongSelf repositoryAccessError:record.repoId];
        if (repositoryAccess) { finish(nil, nil, repositoryAccess); return; }
        // This block may run for a request that joined a download started by
        // another SeafFile instance for the same item (the cache evicted the
        // first one): pick up the finished download's oid before staging.
        [file loadCache];
        NSError *stageError = nil;
        NSURL *url = [strongSelf stageContentsOfFile:file error:&stageError];
        if (!url) {
            [strongSelf noteError:stageError aboutOneItem:YES];   // the staged copy, not the server
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
        [weakSelf noteError:mapped aboutOneItem:[SeafFPErrors seafErrorConcernsOneItem:error]];
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

/// Equal content ids; nil and empty are the same (unknown).
static BOOL SeafFPStringsEqual(NSString *a, NSString *b)
{
    return (a.length == 0 && b.length == 0) || [a isEqualToString:b];
}

/// CannotSynchronize is terminal for this version of the item (the system
/// does not retry it in the background). Retain the journal and local edits,
/// and explain the manual exit instead of pretending the move was undone.
static NSError *SeafFPMoveResolutionError(void)
{
    return [NSError errorWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorCannotSynchronize userInfo:@{
        @"reason": @"moveNeedsResolution",
        NSLocalizedDescriptionKey: NSLocalizedString(@"This move needs your attention", @"Seafile"),
        NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Seafile could not safely identify the moved file. Your local changes have been kept. Save a copy outside this Seafile location, then check the source and destination in Seafile before changing this item again.", @"Seafile")
    }];
}

/// Let File Provider retry pending mutations even across extension restarts.
static NSError *SeafFPMovePendingError(NSError *underlyingError)
{
    return [NSError errorWithDomain:NSCocoaErrorDomain code:NSXPCConnectionReplyInvalid userInfo:@{
        @"reason": @"movePending",
        NSUnderlyingErrorKey: underlyingError ?: [SeafFPErrors cannotSynchronize],
        NSLocalizedDescriptionKey: NSLocalizedString(@"An earlier change to this item is still being confirmed", @"Seafile"),
        NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Seafile is checking whether an earlier rename or move of this item reached the server. Your local changes have been kept. Try again later.", @"Seafile")
    }];
}

static BOOL SeafFPIsDirectoryMissing(NSError *error)
{
    return [error.domain isEqual:NSFileProviderErrorDomain] && [error.userInfo[SeafFPErrorReasonKey] isEqual:@"directoryMissing"];
}

// A replicated extension may only signal the working set; other container
// identifiers are ignored by the system (NSFileProviderManager.h). The
// working set change enumeration re-lists the affected directories.
- (void)signalContainer:(NSFileProviderItemIdentifier)containerIdentifier
{
    if (containerIdentifier.length == 0) return;
    [self.store requestWorkingSetSignal];
    long long ticket = [self.store pendingWorkingSetSignalTicket];
    [self.manager signalEnumeratorForContainerItemIdentifier:NSFileProviderWorkingSetContainerItemIdentifier completionHandler:^(NSError * _Nullable error) {
        if (error) {
            Info("signal working set (for %@) failed: %@", containerIdentifier, error);
            [self scheduleWorkingSetRecheckAt:[NSDate dateWithTimeIntervalSinceNow:5]];
        } else if (ticket > 0) [self.store completeWorkingSetSignalTicket:ticket];
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
    Info("working set re-check in %.0fs", delay);
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
    return taken(candidate) ? nil : candidate;
}

/// Distinguish the destination from its pre-dispatch occupants. Without a
/// receipt, also require matching content and an absent original source.
/// Inconclusive listings answer Unknown without an error; the caller waits
/// or, past the grace, expires the journal (expireMoveOfRecord:).
- (void)resolveMovedRecord:(SeafFPRecord *)source recovery:(NSDictionary *)recovery inDir:(SeafDir *)destination
                completion:(void (^)(SeafFPMoveOutcome, NSString *, NSError *))completion
{
    BOOL unacknowledged = [recovery[@"confirmed"] isEqual:@NO];
    dispatch_block_t inconclusive = ^{
        completion(SeafFPMoveOutcomeUnknown, nil, nil);
    };
    if (unacknowledged) {
        NSError *access = [self repositoryAccessError:source.repoId];
        if (access.code == NSFileProviderErrorNoSuchItem) { inconclusive(); return; }
        if (access) { completion(SeafFPMoveOutcomeUnknown, nil, access); return; }
        if (!source.oid.length) { inconclusive(); return; }
    }

    NSString *expected = recovery[@"name"];
    NSDictionary *existingEntries = recovery[@"existingDestinationEntries"];
    NSArray<NSString *> *existingNames = recovery[@"existingDestinationNames"];
    if (!existingNames) existingNames = existingEntries.allKeys;
    NSSet<NSString *> *excludedNames = [NSSet setWithArray:existingNames ?: @[]];
    long long start = [recovery[@"start"] longLongValue];
    NSString *oldName = source.path.lastPathComponent;
    NSString *path = source.directoryPath;
    BOOL sameDirectory = [destination.repoId isEqual:source.repoId] && [destination.path isEqual:path];

    [self loadDirectoryForMove:destination completion:^(BOOL loaded, NSError *error) {
        BOOL missing = !loaded && SeafFPIsDirectoryMissing(error);
        if (!loaded && !missing) { completion(SeafFPMoveOutcomeUnknown, nil, error ?: [SeafFPErrors serverUnreachable]); return; }
        NSArray<SeafBase *> *targetSnapshot = missing ? @[] : [destination.items copy];
        NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
        for (SeafBase *entry in targetSnapshot) {
            if (sameDirectory && SeafFPNamesEqual(entry.name, oldName)) continue;
            NSString *canonicalName = entry.name.precomposedStringWithCanonicalMapping.lowercaseString;
            NSDictionary *indexEntry = SeafFPIndexEntryForBase(entry);
            NSString *previousOid = existingEntries[canonicalName][SeafFPEntryOid];
            NSString *currentOid = indexEntry[SeafFPEntryOid];
            if ([excludedNames containsObject:canonicalName]) {
                // A former conflict name can have been deleted and assigned
                // to this move. Only differing, known content distinguishes
                // it from the former occupant; legacy name-only journals and
                // identical contents remain ambiguous.
                if (!previousOid.length || !source.oid.length || ![currentOid isEqual:source.oid]
                    || [previousOid isEqual:currentOid]) continue;
            }
            if (indexEntry) [candidates addObject:indexEntry];
        }
        NSString *name = [self.store confirmedNameForRecord:source expected:expected inRepo:destination.repoId
            directory:destination.path entries:candidates requestStartSeq:start];
        if (name && !unacknowledged) { completion(SeafFPMoveOutcomeResolved, name, nil); return; }
        if (!unacknowledged) { inconclusive(); return; }

        // A legacy journal without a pre-dispatch listing can only recover the exact name.
        if (name && !existingNames && !SeafFPNamesEqual(name, expected)) name = nil;
        BOOL targetMatchesSource = NO;
        for (NSDictionary *entry in candidates) {
            if (name && SeafFPNamesEqual(entry[SeafFPEntryName], name) && [entry[SeafFPEntryOid] isEqual:source.oid]
                && [entry[SeafFPEntryIsDir] boolValue] == source.isDir) {
                targetMatchesSource = YES;
                break;
            }
        }
        if (!targetMatchesSource) { inconclusive(); return; }

        // Our entry still at the source leaves two candidates (a copy, or a
        // request still running). A directory's id changes with descendants,
        // so for one the name and type alone count.
        void (^settleFromSource)(NSArray<SeafBase *> *) = ^(NSArray<SeafBase *> *sourceSnapshot) {
            for (SeafBase *entry in sourceSnapshot) {
                if (!SeafFPNamesEqual(entry.name, oldName) || [entry isKindOfClass:[SeafDir class]] != source.isDir) continue;
                if (source.isDir || [entry.oid isEqual:source.oid]) { inconclusive(); return; }
            }
            completion(SeafFPMoveOutcomeResolved, name, nil);
        };
        if (sameDirectory) { settleFromSource(targetSnapshot); return; }
        SeafDir *origin = [[SeafDir alloc] initWithConnection:self.connection oid:nil repoId:source.repoId
            perm:nil name:path.lastPathComponent path:path mtime:0];
        [self loadDirectoryForMove:origin completion:^(BOOL sourceLoaded, NSError *sourceError) {
            if (sourceLoaded) settleFromSource([origin.items copy]);
            else if (SeafFPIsDirectoryMissing(sourceError)) settleFromSource(@[]);
            else completion(SeafFPMoveOutcomeUnknown, nil, sourceError ?: [SeafFPErrors serverUnreachable]);
        }];
    }];
}

/// Past the settle grace the move's outcome is no longer awaited. The source
/// directory is listed into the store while the journal still holds the
/// item, so no operation acts on the item without the journal before the
/// store shows the server's state; only then is the journal dropped. The
/// completion gets the item's current row, or nil when it is gone; the
/// caller decides from it (deleteItem rejects, modifyItem compares versions).
/// Whatever landed at the destination is assigned by its own listing.
- (void)expireMoveOfRecord:(SeafFPRecord *)record recovery:(NSDictionary *)recovery
                completion:(void (^)(SeafFPRecord *, SeafFPMoveSettlement, NSError *))completion
{
    NSString *repoId = recovery[@"sourceRepo"];
    NSString *path = [SeafFPIdentifier normalizedPath:[recovery[@"sourcePath"] stringByDeletingLastPathComponent]];
    __weak typeof(self) weakSelf = self;
    // `listed`: NO when the source directory or library is gone, so is the item.
    void (^drop)(BOOL) = ^(BOOL listed) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf.store expireMoveForUUID:record.uuid matchingRecovery:recovery]) {
            completion(nil, SeafFPMoveSettlementRecovered, SeafFPMovePendingError(nil));
            return;
        }
        Info("Expired the unsettled move of %@ to %@:%@/%@", record.uuid, recovery[@"repo"], recovery[@"dir"], recovery[@"name"]);
        [strongSelf.store requestDirectoryCheckOfRepo:recovery[@"repo"] path:recovery[@"dir"]];
        if (!listed) [strongSelf.store requestDirectoryCheckOfRepo:repoId path:path.stringByDeletingLastPathComponent];
        [strongSelf forgetSeafObjectsForRecord:record];
        [strongSelf signalWorkingSet];
        SeafFPRecord *current = listed ? [strongSelf.store recordForUUID:record.uuid] : nil;
        completion(current.deleted ? nil : current, SeafFPMoveSettlementExpired, nil);
    };
    NSError *access = [self repositoryAccessError:repoId];
    if (access.code == NSFileProviderErrorNoSuchItem) { drop(NO); return; }
    if (access) {
        completion(nil, SeafFPMoveSettlementRecovered,
                   access.code == NSFileProviderErrorNotAuthenticated ? access : SeafFPMovePendingError(access));
        return;
    }
    long long start = self.store.currentSeq;
    SeafDir *origin = [[SeafDir alloc] initWithConnection:self.connection oid:nil repoId:repoId
        perm:nil name:path.lastPathComponent path:path mtime:0];
    [self loadDirectoryForMove:origin completion:^(BOOL loaded, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { completion(nil, SeafFPMoveSettlementRecovered, SeafFPMovePendingError(nil)); return; }
        if (!loaded) {
            if (SeafFPIsDirectoryMissing(error)) drop(NO);
            else completion(nil, SeafFPMoveSettlementRecovered, SeafFPMovePendingError(error));
            return;
        }
        NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
        for (SeafBase *entry in [origin.items copy]) {
            NSDictionary *indexEntry = SeafFPIndexEntryForBase(entry);
            if (indexEntry) [entries addObject:indexEntry];
        }
        if ([strongSelf.store applyDirectoryListingOfRepo:repoId directoryPath:path entries:entries
                                          requestStartSeq:start] == SeafFPWriteFailed) {
            // Rejected (a newer local write) or failed: a later attempt lists again.
            completion(nil, SeafFPMoveSettlementRecovered, SeafFPMovePendingError(nil));
            return;
        }
        drop(YES);
    }];
}

/// Settles the item's move journal against the server: Recovered when the
/// original identity is found at its destination, Expired when the settle
/// grace has passed without that (the record is then the item's current
/// row, nil when it is gone). Within the grace an inconclusive outcome is a
/// transient error, so the system retries the operation.
- (void)recoverMoveOfRecord:(SeafFPRecord *)record details:(NSDictionary *)recovery
                 completion:(void (^)(SeafFPRecord *, SeafFPMoveSettlement, NSError *))completion
{
    if ([recovery[@"needsResolution"] boolValue]) { completion(nil, SeafFPMoveSettlementRecovered, SeafFPMoveResolutionError()); return; }
    NSString *parentUUID = [recovery[@"parent"] length] ? recovery[@"parent"] : nil;
    NSString *repoId = recovery[@"repo"];
    long long start = [recovery[@"start"] longLongValue];
    BOOL graceElapsed = [SeafFPStore moveSettleGraceElapsed:recovery now:(long long)[NSDate date].timeIntervalSince1970];
    NSString *container = parentUUID ? [SeafFPIdentifier identifierForUUID:parentUUID] : [SeafFPIdentifier identifierForRepo:repoId];
    NSError *access = [self repositoryAccessError:repoId];
    SeafDir *dir = access ? nil : [self seafDirForContainer:container record:NULL];
    if (!dir || ![dir.repoId isEqual:repoId] || ![dir.path isEqual:recovery[@"dir"]]) {
        if (access.code == NSFileProviderErrorNotAuthenticated) { completion(nil, SeafFPMoveSettlementRecovered, access); return; }
        BOOL destinationUnknown = access.code == NSFileProviderErrorCannotSynchronize || [self repoListUnknownFor:repoId];
        // A missing or relocated parent prevents checking the journal's destination.
        if (graceElapsed && !destinationUnknown) [self expireMoveOfRecord:record recovery:recovery completion:completion];
        else completion(nil, SeafFPMoveSettlementRecovered, SeafFPMovePendingError(access));
        return;
    }
    SeafFPRecord *source = [SeafFPRecord new];
    source.uuid = record.uuid;
    source.repoId = recovery[@"sourceRepo"];
    source.path = recovery[@"sourcePath"];
    source.oid = recovery[@"oid"];
    source.isDir = [recovery[@"isDir"] boolValue];
    source.seq = [recovery[@"sourceSeq"] longLongValue];
    __weak typeof(self) weakSelf = self;
    [self resolveMovedRecord:source recovery:recovery inDir:dir completion:^(SeafFPMoveOutcome outcome, NSString *name, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { completion(nil, SeafFPMoveSettlementRecovered, SeafFPMovePendingError(nil)); return; }
        NSError *repoError = error ?: [strongSelf repositoryAccessError:repoId];
        if (repoError) {
            if ([repoError.domain isEqual:NSFileProviderErrorDomain]
                && (repoError.code == NSFileProviderErrorServerUnreachable || repoError.code == NSFileProviderErrorNoSuchItem
                    || (repoError.code == NSFileProviderErrorCannotSynchronize && !repoError.userInfo[SeafFPErrorReasonKey]))) {
                repoError = SeafFPMovePendingError(repoError);
            }
            completion(nil, SeafFPMoveSettlementRecovered, repoError);
            return;
        }
        if (outcome != SeafFPMoveOutcomeResolved) {
            if (graceElapsed) [strongSelf expireMoveOfRecord:record recovery:recovery completion:completion];
            else completion(nil, SeafFPMoveSettlementRecovered, SeafFPMovePendingError(nil));
            return;
        }
        SeafFPRecord *moved = [strongSelf.store finishPendingMoveOfRecord:source toRepo:repoId path:[dir.path stringByAppendingPathComponent:name]
            parentUUID:parentUUID requestStartSeq:start serverTime:[recovery[@"serverTime"] longLongValue]];
        if (!moved) { completion(nil, SeafFPMoveSettlementRecovered, SeafFPMovePendingError(nil)); return; }
        [strongSelf forgetSeafObjectsForRecord:record];
        [strongSelf signalWorkingSet];
        completion(moved, SeafFPMoveSettlementRecovered, nil);
    }];
}

/// Journal each mutation independently. A combined rename and reparent
/// starts the move only after the intermediate rename has a local identity.
- (void)relocateRecord:(SeafFPRecord *)record fromDir:(SeafDir *)source toDir:(SeafDir *)destination
            parentUUID:(NSString *)parentUUID name:(NSString *)name requestedName:(NSString *)requestedName
                rename:(BOOL)rename completion:(void (^)(SeafFPRecord *, NSError *))completion
{
    NSMutableArray<NSString *> *existingNames = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSDictionary *> *existingEntries = [NSMutableDictionary dictionary];
    NSString *canonicalName = name.precomposedStringWithCanonicalMapping.lowercaseString;
    for (SeafBase *entry in [destination.items copy]) {
        if (rename && SeafFPNamesEqual(entry.name, record.name)) continue;
        NSString *existing = entry.name.precomposedStringWithCanonicalMapping.lowercaseString;
        if ([existing isEqual:canonicalName] || SeafFPIsConflictSiblingName(existing, canonicalName)) {
            [existingNames addObject:existing];
            NSDictionary *snapshot = SeafFPIndexEntryForBase(entry);
            if (snapshot) existingEntries[existing] = snapshot;
        }
    }
    long long start = [self.store beginMoveOfRecord:record toRepo:destination.repoId directory:destination.path
                                       parentUUID:parentUUID expectedName:name requestedName:requestedName
                         existingDestinationNames:existingNames existingDestinationEntries:existingEntries];
    if (start < 0) { completion(nil, [SeafFPErrors cannotSynchronize]); return; }
    __weak typeof(self) weakSelf = self;
    dispatch_block_t defer = ^{
        typeof(self) strongSelf = weakSelf;
        [strongSelf.store requestDirectoryCheckOfRepo:source.repoId path:source.path];
        [strongSelf.store requestDirectoryCheckOfRepo:destination.repoId path:destination.path];
        [strongSelf signalWorkingSet];
    };
    void (^finishRequest)(BOOL, NSError *, NSHTTPURLResponse *) = ^(BOOL success, NSError *error, NSHTTPURLResponse *response) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { completion(nil, [SeafFPErrors cannotSynchronize]); return; }
        if (!success) {
            // An absent or ambiguous reply leaves the intent available for
            // reconciliation. Only errors known to precede the mutation free it.
            NSInteger status = response.statusCode;
            BOOL notSent = !response && SeafFPRequestNeverReachedServer(error);
            // 440 / 441 are seahub's "library password required": checked
            // before anything runs, like 443 ("above quota").
            // A 404 can also come from the directory reload after a successful move.
            BOOL rejected = notSent || status == 400 || status == 401 || status == 403
                || status == 409 || status == 440 || status == 441 || status == 443;
            BOOL cleanupFailed = rejected && ![strongSelf.store discardUnconfirmedMoveForUUID:record.uuid requestStartSeq:start];
            if (!rejected || cleanupFailed) defer();
            NSError *mapped = rejected && !cleanupFailed ? [SeafFPErrors errorForSeafError:error] : SeafFPMovePendingError(error);
            [strongSelf noteError:mapped aboutOneItem:[SeafFPErrors seafErrorConcernsOneItem:error]];
            completion(nil, mapped);
            return;
        }
        long long serverTime = SeafFPServerTime([response valueForHTTPHeaderField:@"Date"]);
        if (![strongSelf.store noteMoveReceiptForUUID:record.uuid requestStartSeq:start serverTime:serverTime]) {
            defer();
            completion(nil, SeafFPMovePendingError(nil));
            return;
        }
        NSDictionary *recovery = [strongSelf.store moveRecoveryForUUID:record.uuid];
        if (!recovery.count || [recovery[@"start"] longLongValue] != start) {
            completion(nil, SeafFPMovePendingError(nil));
            return;
        }
        [strongSelf recoverMoveOfRecord:record details:recovery completion:^(SeafFPRecord *moved, SeafFPMoveSettlement settlement, NSError *resolveError) {
            // The server acknowledged the request, so a journal still open
            // here is only unsettled, never "not executed". (A fresh journal
            // cannot have expired; if it somehow did, the system retries.)
            BOOL applied = moved && !resolveError && settlement == SeafFPMoveSettlementRecovered;
            if (!applied) defer();
            completion(applied ? moved : nil, applied ? nil : (resolveError ?: SeafFPMovePendingError(nil)));
        }];
    };
    if (rename) {
        [[SeafFileOperationManager sharedManager] renameEntry:record.name newName:name inDir:source
            responseCompletion:^(BOOL success, SeafBase *renamedFile, NSError *error, NSHTTPURLResponse *response) {
                finishRequest(SeafFPRenameSucceeded(success, error), error, response);
            }];
    } else {
        [[SeafFileOperationManager sharedManager] moveEntries:@[record.name] fromDir:source toDir:destination responseCompletion:finishRequest];
    }
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

- (void)loadDirectoryForMove:(SeafDir *)dir completion:(void (^)(BOOL, NSError *))completion
{
    [dir loadContentSuccess:^(SeafDir *loaded) {
        completion(YES, nil);
    } failure:^(SeafDir *failed, NSError *error) {
        completion(NO, [SeafFPErrors directoryListingErrorForSeafError:error]);
    } requireListing:YES];
}

- (void)loadDirectory:(SeafDir *)dir completion:(void (^)(BOOL loaded, BOOL fromCache, NSError * _Nullable error))completion
{
    [self loadDirectory:dir listing:^(BOOL loaded, BOOL fromCache, NSError *error, SeafFPListingFailure failure) {
        completion(loaded, fromCache, error);
    }];
}

- (void)loadDirectory:(SeafDir *)dir
              listing:(void (^)(BOOL loaded, BOOL fromCache, NSError * _Nullable error, SeafFPListingFailure failure))completion
{
    __weak typeof(self) weakSelf = self;
    [dir loadContentSuccess:^(SeafDir *loaded) {
        completion(YES, NO, nil, SeafFPListingFailureNone);
    } failure:^(SeafDir *failed, NSError *error) {
        SeafFPListingFailure failure = [SeafFPErrors listingFailureForSeafError:error];
        BOOL cached = failed.hasCache || [failed loadCache];
        if (cached) {
            Info("Directory %@ unreachable, serving cache: %@", failed.path, error);
            completion(YES, YES, nil, failure);
        } else {
            NSError *mapped = [SeafFPErrors errorForSeafError:error];
            [weakSelf noteError:mapped aboutOneItem:[SeafFPErrors seafErrorConcernsOneItem:error]];
            completion(NO, NO, mapped, failure);
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
    Info("decoration %@ favorite=%@ tag=%lu lastUsed=%@", identifier, decoration.favoriteRank, (unsigned long)decoration.tagData.length, decoration.lastUsedDate);

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
        creationStartSeq:(nullable NSNumber *)creationStartSeq
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
    SeafFPRecord *existing = creationStartSeq ? nil : [self.store recordForRepo:repoId path:path includeDeleted:NO];
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
            [strongSelf noteError:mapped aboutOneItem:[SeafFPErrors seafErrorConcernsOneItem:error]];
            completion(nil, mapped);
            return;
        }
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:stagedURL.path error:nil];
        long long size = attrs ? (long long)[attrs fileSize] : (long long)uploadFile.filesize;
        long long mtime = (long long)[[NSDate date] timeIntervalSince1970];
        SeafFPRecord *record = creationStartSeq
            ? [strongSelf.store recordCreatedFileInRepo:repoId path:path parentUUID:parentUUID oid:oid mtime:mtime size:size
                                       requestStartSeq:creationStartSeq.longLongValue serverTime:SeafFPServerTime(uploadFile.serverDateHeader)]
            : [strongSelf.store upsertRecordForRepo:repoId path:path isDir:NO parentUUID:parentUUID oid:oid mtime:mtime size:size];
        if (!record) {
            // Uploaded, but the store could not record it (busy past its
            // retries): an error, not a nil item, so the system does not drop
            // its copy; the parent's next listing gives the file an identity.
            Warning("createItem %@: uploaded, store not updated", path);
            completion(nil, [SeafFPErrors cannotSynchronize]);
            return;
        }
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
    Info("createItem %@ (%@) in %@ options=%lu", requestedName, isFolder ? @"folder" : @"file", parentIdentifier, (unsigned long)options);

    NSString *repoId = parentDir.repoId;
    NSString *parentUUID = parentRecord.uuid;
    long long creationStartSeq = [self.store currentSeq];
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
                if (!record) { finish(nil, [SeafFPErrors cannotSynchronize]); return; }
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
            if ([parentDir nameExist:name]) { finish(nil, [SeafFPErrors filenameCollision]); return; }
        }
        if (!isFolder && !url) {
            // A dataless re-import that matches nothing on the server: nil
            // item and no error, the system drops its placeholder
            // (NSFileProviderReplicatedExtension.h, createItem).
            Info("createItem %@: no content and no server entry, dropping", requestedName);
            finish(nil, nil);
            return;
        }
        NSString *fullPath = [SeafFPIdentifier normalizedPath:[parentDir.path stringByAppendingPathComponent:name]];

        if (isFolder) {
            [[SeafFileOperationManager sharedManager] mkdir:name inDir:parentDir completion:^(BOOL success, NSError *error) {
                if (!success) {
                    NSError *mapped = [SeafFPErrors errorForSeafError:error];
                    [strongSelf noteError:mapped aboutOneItem:[SeafFPErrors seafErrorConcernsOneItem:error]];
                    finish(nil, mapped);
                    return;
                }
                SeafFPRecord *record = [strongSelf.store upsertRecordForRepo:repoId path:fullPath isDir:YES parentUUID:parentUUID oid:nil mtime:(long long)[[NSDate date] timeIntervalSince1970] size:-1];
                if (!record) { finish(nil, [SeafFPErrors cannotSynchronize]); return; }
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
        if (progress.isCancelled) {
            [[NSFileManager defaultManager] removeItemAtURL:staged.URLByDeletingLastPathComponent error:nil];
            return;
        }
        long long uploadStart = [strongSelf.store prepareFileCreationInRepo:repoId path:fullPath requestStartSeq:creationStartSeq];
        if (uploadStart < 0) {
            [[NSFileManager defaultManager] removeItemAtURL:staged.URLByDeletingLastPathComponent error:nil];
            finish(nil, [SeafFPErrors cannotSynchronize]);
            return;
        }
        [strongSelf uploadStagedFile:staged repoId:repoId path:fullPath parentUUID:parentUUID creationStartSeq:@(uploadStart) progress:progress completion:^(SeafFPRecord *record, NSError *error) {
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

/// Continue from the current Store record after any earlier move has settled.
- (void)applyModificationOfRecord:(SeafFPRecord *)record requestedItem:(NSFileProviderItem)item
                    changedFields:(NSFileProviderItemFields)changedFields filenameRecovered:(BOOL)filenameRecovered
                         contents:(NSURL *)newContents progress:(NSProgress *)progress
                           finish:(void (^)(SeafFPItem *, NSError *))finish
             finishFetchingContent:(void (^)(SeafFPItem *))finishFetchingContent
{
    if (progress.isCancelled) return;
    NSString *requestedFilename = (changedFields & NSFileProviderItemFilename) ? item.filename : nil;
    BOOL renamed = !filenameRecovered && requestedFilename.length > 0
        && !SeafFPNamesEqual(requestedFilename, record.name);
    BOOL reparented = (changedFields & NSFileProviderItemParentItemIdentifier) != 0
        && item.parentItemIdentifier.length > 0
        && ![item.parentItemIdentifier isEqualToString:record.parentItemIdentifier];
    BOOL contentsChanged = (changedFields & NSFileProviderItemContents) != 0
        && !record.isDir
        && newContents != nil;
    if (!renamed && !reparented && !contentsChanged) {
        finish([self itemForRecord:record], nil);
        return;
    }
    NSError *access = [self accessError];
    if (access) {
        finish(nil, access);
        return;
    }
    if ([self repoListUnknownFor:record.repoId]) {
        finish(nil, [SeafFPErrors serverUnreachable]);   // cold process: permissions unknown yet, retry later
        return;
    }
    if (![self isRepoEditable:record.repoId]) {
        SeafFPItem *current = [self itemForRecord:record];
        if (contentsChanged) {
            // Files keeps offering the editor (AllowsWriting stays set, see
            // SeafFPItem). The unchanged item alone would make the system take
            // the edited copy for the server version; the edit is dropped by
            // fetching the server content back instead.
            Info("modifyItem %@: content change in a read-only library, reverting to the server content", item.itemIdentifier);
            finishFetchingContent(current);
        } else {
            finish(current, nil);
        }
        return;
    }
    Info("modifyItem %@ renamed=%d reparented=%d contents=%d", item.itemIdentifier, renamed, reparented, contentsChanged);

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
        [strongSelf uploadStagedFile:staged repoId:latest.repoId path:latest.path parentUUID:latest.parentUUID creationStartSeq:nil progress:progress completion:^(SeafFPRecord *uploaded, NSError *uploadError) {
            if (!uploaded) {
                finish(nil, uploadError);
                return;
            }
            finish([strongSelf itemForRecord:uploaded], nil);
        }];
    };

    if (!renamed && !reparented) {
        uploadIfNeeded(record);
        return;
    }

    SeafFPRecord *dstRecord = nil;
    NSString *srcContainer = record.parentItemIdentifier;
    NSString *dstContainer = reparented ? item.parentItemIdentifier : srcContainer;
    SeafDir *srcDir = [self seafDirForContainer:srcContainer record:NULL];
    SeafDir *dstDir = [self seafDirForContainer:dstContainer record:&dstRecord];
    if (!srcDir || !dstDir || ![self isRepoEditable:dstDir.repoId]) {
        finish(nil, [SeafFPErrors cannotSynchronize]);
        return;
    }
    NSString *requestedName = renamed ? requestedFilename.precomposedStringWithCanonicalMapping : record.name;
    NSString *dstParentUUID = dstRecord.uuid;
    void (^relocated)(SeafFPRecord *, NSError *) = ^(SeafFPRecord *moved, NSError *moveError) {
        if (!moved) { finish(nil, moveError ?: [SeafFPErrors cannotSynchronize]); return; }
        [weakSelf noteSuccess];
        uploadIfNeeded(moved);
    };
    void (^start)(void) = ^{
        if (progress.isCancelled) return;
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { finish(nil, [SeafFPErrors cannotSynchronize]); return; }
        SeafBase *origin = nil;
        for (SeafBase *entry in [srcDir.items copy]) {
            if (SeafFPNamesEqual(entry.name, record.name)) { origin = entry; break; }
        }
        if (!origin || [origin isKindOfClass:[SeafDir class]] != record.isDir) {
            [strongSelf.store requestDirectoryCheckOfRepo:record.repoId path:record.directoryPath];
            [strongSelf signalWorkingSet];
            finish(nil, [SeafFPErrors cannotSynchronize]);
            return;
        }
        // The identity is the entry at this path; its contents may have
        // changed since the store last listed the directory (another client
        // edited the file, or anything under the folder changed its id).
        // The fresh listing is adopted so the journal records what moved.
        SeafFPRecord *subject = record;
        if (!SeafFPStringsEqual(origin.oid, record.oid)) {
            BOOL originIsFile = [origin isKindOfClass:[SeafFile class]];
            long long mtime = originIsFile ? ((SeafFile *)origin).mtime : ((SeafDir *)origin).mtime;
            long long size = originIsFile ? (long long)((SeafFile *)origin).filesize : -1;
            subject = [strongSelf.store refreshContentOfRecord:record oid:origin.oid mtime:mtime size:size];
            if (!subject) { finish(nil, [SeafFPErrors cannotSynchronize]); return; }
        }
        NSArray<SeafDir *> *dirs = reparented ? @[dstDir, srcDir] : @[srcDir];
        NSString *name = [strongSelf freeNameFor:requestedName inDirs:dirs ownName:subject.name inDir:srcDir];
        if (!name) { finish(nil, [SeafFPErrors filenameCollision]); return; }
        void (^afterRename)(SeafFPRecord *, NSError *) = ^(SeafFPRecord *source, NSError *renameError) {
            if (!source || !reparented) { relocated(source, renameError); return; }
            void (^move)(void) = ^{
                if (progress.isCancelled) return;
                [strongSelf relocateRecord:source fromDir:srcDir toDir:dstDir parentUUID:dstParentUUID
                                       name:source.name requestedName:requestedFilename rename:NO completion:relocated];
            };
            if (SeafFPNamesEqual(source.name, subject.name)) {
                move();
            } else {
                // The target listing from before the rename can be stale.
                [strongSelf loadDirectoryForMove:dstDir completion:^(BOOL loaded, NSError *listError) {
                    if (!loaded) relocated(nil, listError ?: [SeafFPErrors serverUnreachable]);
                    else move();
                }];
            }
        };
        if (SeafFPNamesEqual(name, subject.name)) {
            afterRename(subject, nil);
        } else if (!progress.isCancelled) {
            [strongSelf relocateRecord:subject fromDir:srcDir toDir:srcDir parentUUID:subject.parentUUID
                                   name:name requestedName:requestedFilename rename:YES completion:afterRename];
        }
    };
    // Unreachable here means nothing has happened on the server yet: the
    // system retries later.
    void (^listThen)(SeafDir *, BOOL, dispatch_block_t) = ^(SeafDir *dir, BOOL needed, dispatch_block_t next) {
        if (!needed) { next(); return; }
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { finish(nil, [SeafFPErrors cannotSynchronize]); return; }
        [strongSelf loadDirectoryForMove:dir completion:^(BOOL loaded, NSError *listError) {
            if (!loaded) { finish(nil, listError ?: [SeafFPErrors serverUnreachable]); return; }
            next();
        }];
    };
    listThen(dstDir, reparented, ^{
        listThen(srcDir, YES, start);
    });
}

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
    NSString *uuid = [SeafFPIdentifier uuidFromIdentifier:item.itemIdentifier];
    NSFileProviderItemFields serverFields = NSFileProviderItemFilename | NSFileProviderItemParentItemIdentifier | NSFileProviderItemContents;
    NSDictionary *recovery = uuid && (changedFields & serverFields) ? [self.store moveRecoveryForUUID:uuid] : @{};
    if (!recovery) { finish(nil, [SeafFPErrors cannotSynchronize]); return progress; }
    SeafFPRecord *record = uuid ? [self.store recordForUUID:uuid] : nil;
    SeafFPItem *current = [self resolveItem:item.itemIdentifier error:&error];
    if (!current && recovery.count && record.tombReason == SeafFPTombReasonAbsent && ![self repositoryAccessError:record.repoId]) {
        current = [self itemForRecord:record];
    }
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

    if (!record) {
        // The domain root, libraries and the trash are server-owned containers:
        // renames, moves and uploads targeting them are answered with the
        // unchanged item so the system reverts its local change.
        finish(current, nil);
        return progress;
    }

    if (!recovery.count) {
        [self applyModificationOfRecord:record requestedItem:item changedFields:changedFields filenameRecovered:NO
                               contents:newContents progress:progress finish:finish finishFetchingContent:finishFetchingContent];
        return progress;
    }

    // Resolve the prior mutation before issuing any remaining changes.
    NSError *access = [self accessError];
    if (access) { finish(nil, access); return progress; }
    __weak typeof(self) weakSelf = self;
    [self recoverMoveOfRecord:record details:recovery completion:^(SeafFPRecord *settled, SeafFPMoveSettlement settlement, NSError *resolveError) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { finish(nil, SeafFPMovePendingError(nil)); return; }
        if (resolveError) { finish(nil, resolveError); return; }
        if (settlement == SeafFPMoveSettlementExpired) {
            // Gone from the fresh source listing: the system drops its copy
            // and re-creates it if it holds local changes.
            if (!settled) { finish(nil, [SeafFPErrors noSuchItem]); return; }
            // The rename or move goes ahead only on the item it was asked
            // for: still where the journal found it, with the contents of
            // then or of the version the system based this change on (a
            // directory's id changes with descendants: location alone).
            NSData *baseContent = version.contentVersion;
            BOOL unchanged = [settled.repoId isEqual:recovery[@"sourceRepo"]] && [settled.path isEqual:recovery[@"sourcePath"]]
                && settled.isDir == [recovery[@"isDir"] boolValue]
                && (settled.isDir || (settled.oid.length && [settled.oid isEqual:recovery[@"oid"]])
                    || (baseContent.length && [[strongSelf itemForRecord:settled].itemVersion.contentVersion isEqual:baseContent]));
            // Otherwise the item answers with the server's name and parent,
            // so the system reverts the local rename or move; contents and
            // other fields still apply as for any edit.
            NSFileProviderItemFields fields = unchanged ? changedFields
                : changedFields & ~(NSFileProviderItemFilename | NSFileProviderItemParentItemIdentifier);
            if (!unchanged) Info("modifyItem %@: expired move, item changed on the server; not replaying the rename or move", item.itemIdentifier);
            [strongSelf applyModificationOfRecord:settled requestedItem:item changedFields:fields filenameRecovered:NO
                                         contents:newContents progress:progress finish:finish finishFetchingContent:finishFetchingContent];
            return;
        }
        if (!settled) { finish(nil, SeafFPMovePendingError(nil)); return; }
        // The old request may have picked a free name before sending or
        // received a conflict name from the server. Keep that result on retry.
        NSString *priorRequestedName = recovery[@"requestedName"] ?: recovery[@"name"];
        BOOL filenameRecovered = SeafFPNamesEqual(item.filename, priorRequestedName);
        [strongSelf applyModificationOfRecord:settled requestedItem:item changedFields:changedFields filenameRecovered:filenameRecovered
                                     contents:newContents progress:progress finish:finish finishFetchingContent:finishFetchingContent];
    }];
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
    NSString *uuid = [SeafFPIdentifier uuidFromIdentifier:identifier];
    SeafFPRecord *record = [self.store recordForUUID:uuid];
    NSDictionary *recovery = [self.store moveRecoveryForUUID:uuid];
    if (!recovery) { finish([SeafFPErrors cannotSynchronize]); return progress; }
    if (!record || (record.deleted && (record.tombReason != SeafFPTombReasonAbsent || !recovery.count))) {
        // An absence tombstone may belong to an item now at the pending
        // move's destination. Resolve that journal before deleting there.
        if (record && ![self.store discardMoveJournalForUUID:uuid]) { finish([SeafFPErrors cannotSynchronize]); return progress; }
        finish(nil);
        return progress;
    }
    __weak typeof(self) weakSelf = self;
    void (^deleteRecord)(SeafFPRecord *) = ^(SeafFPRecord *target) {
        typeof(self) owner = weakSelf;
        if (!owner) { finish([SeafFPErrors cannotSynchronize]); return; }
        if ([owner repoListUnknownFor:target.repoId]) {
            finish([SeafFPErrors serverUnreachable]);   // cold process: permissions unknown yet, retry later
            return;
        }
        if (![owner isRepoEditable:target.repoId]) {
            finish([SeafFPErrors deletionRejected]);
            return;
        }
        SeafDir *parentDir = [owner seafDirForContainer:target.parentItemIdentifier record:NULL];
        if (!parentDir) {
            // The library is locked or its list is not known: the item is not
            // gone, the deletion just cannot be carried out now.
            finish([owner repositoryAccessError:target.repoId] ?: [SeafFPErrors cannotSynchronize]);
            return;
        }
        Info("deleteItem %@ (%@) options=%lu", identifier, target.path, (unsigned long)options);

        void (^deleteOnServer)(void) = ^{
            [[SeafFileOperationManager sharedManager] deleteEntries:@[target.name] inDir:parentDir completion:^(BOOL success, NSError *error) {
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) { finish([SeafFPErrors cannotSynchronize]); return; }
                NSError *mapped = success ? nil : [SeafFPErrors errorForSeafError:error];
                if (mapped && mapped.code != NSFileProviderErrorNoSuchItem) {
                    [strongSelf noteError:mapped aboutOneItem:[SeafFPErrors seafErrorConcernsOneItem:error]];
                    finish(mapped);
                    return;
                }
                for (SeafFPRecord *gone in [strongSelf.store subtreeRecordsOfUUID:target.uuid]) {
                    [strongSelf.store removeDecorationForItem:gone.itemIdentifier];
                    [strongSelf.store removeWorkingSetItem:gone.itemIdentifier];
                    [strongSelf.seafObjects removeObjectForKey:gone.itemIdentifier];
                }
                [strongSelf.store markDeletedUUID:target.uuid];   // also drops any move journal
                [strongSelf noteSuccess];
                [strongSelf signalContainer:target.parentItemIdentifier];
                finish(nil);
            }];
        };

        if (target.isDir && (options & NSFileProviderDeleteItemRecursive) == 0) {
            // Without the recursive flag only an empty folder may go.
            SeafDir *dir = [owner seafDirForContainer:identifier record:NULL];
            [owner loadDirectory:dir completion:^(BOOL loaded, BOOL fromCache, NSError *loadError) {
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
            return;
        }
        deleteOnServer();
    };

    // A move of the item that is still being reconciled decides where the
    // item is before it is deleted there.
    if (!recovery.count) {
        deleteRecord(record);
        return progress;
    }
    [self recoverMoveOfRecord:record details:recovery completion:^(SeafFPRecord *settled, SeafFPMoveSettlement settlement, NSError *resolveError) {
        if (resolveError) { finish(resolveError); return; }
        if (settlement == SeafFPMoveSettlementExpired) {
            // The move was given up without knowing where the item went.
            // Gone from the fresh source listing: nothing left to delete.
            // Still there: not deleted blind; the system restores it from
            // the refreshed row, and a delete after that runs normally.
            finish(settled ? [SeafFPErrors deletionRejected] : nil);
            return;
        }
        if (!settled) { finish(SeafFPMovePendingError(nil)); return; }
        deleteRecord(settled);
    }];
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
            Info("materialized items enumeration failed: %@", error);
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
        Info("materialized items: %lu", (unsigned long)items.count);
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
