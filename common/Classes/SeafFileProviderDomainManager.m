//
//  SeafFileProviderDomainManager.m
//  seafile
//

#import "SeafFileProviderDomainManager.h"
#import "SeafFPIdentifier.h"
#import "SeafConnection.h"
#import "SeafStorage.h"
#import "SeafConstants.h"
#import "Debug.h"

static NSString * const kSeafFPLegacyStorageCleaned = @"com.seafile.seafilePro.fileprovider.legacyStorageCleaned";
static NSString * const kSeafFPLegacyStorageDirectory = @"File Provider Storage";
static const NSTimeInterval kSeafFPSignalCoalesceInterval = 2.0;

@interface SeafFileProviderDomainManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSFileProviderDomain *> *pendingSignals;   // domainId -> domain
@property (nonatomic, assign) BOOL observingChanges;
// Every domain mutation runs through this queue, one at a time: each one is a
// getDomains round trip followed by a decision, and two of them in flight
// undo each other (a login racing the logout of the same account, a Face ID
// switch flipped twice). Ops are blocks that call their `done` when the
// NSFileProviderManager call they made has answered.
@property (nonatomic, strong) NSMutableArray<void (^)(dispatch_block_t done)> *domainOps;
@property (nonatomic, assign) BOOL domainOpRunning;
@end

@implementation SeafFileProviderDomainManager

+ (instancetype)shared
{
    static SeafFileProviderDomainManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SeafFileProviderDomainManager alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _pendingSignals = [NSMutableDictionary dictionary];
        _domainOps = [NSMutableArray array];
    }
    return self;
}

#pragma mark - Identity

+ (NSString *)domainIdentifierForConnection:(SeafConnection *)conn
{
    return [SeafFPIdentifier domainIdentifierForAddress:conn.address username:conn.username];
}

// Files shows this under the app name when more than one account is
// registered. The server-side display name ("name" from /account/info) reads
// better than the login (usually an e-mail address); the login is the
// fallback until the account info has been fetched.
+ (NSString *)displayNameForConnection:(SeafConnection *)conn
{
    NSString *host = conn.host.length > 0 ? conn.host : [SeafFPIdentifier normalizedAddress:conn.address];
    // The account info is stored as it came from the server: guard against NSNull.
    NSString *name = [conn.name isKindOfClass:[NSString class]]
        ? [conn.name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
    if (name.length == 0) name = conn.username;
    return [NSString stringWithFormat:@"%@ – %@", name ?: @"", host ?: @""];
}

+ (BOOL)connectionWantsDomain:(SeafConnection *)conn
{
    return conn.username.length > 0 && conn.address.length > 0 && !conn.touchIdEnabled;
}

- (NSFileProviderDomain *)domainForConnection:(SeafConnection *)conn
{
    NSFileProviderDomain *domain = [[NSFileProviderDomain alloc] initWithIdentifier:[self.class domainIdentifierForConnection:conn]
                                                                        displayName:[self.class displayNameForConnection:conn]];
    if (@available(iOS 18.0, *)) {
        // Seafile has no client-side trash: a delete in Files must reach the
        // extension as deleteItem, never as a move under the trash container
        // (which the extension cannot serve and would answer CannotSynchronize).
        domain.supportsSyncingTrash = NO;
    }
    return domain;
}

/// A registered domain whose properties differ from what this build wants
/// (a domain registered by an older build, say).
- (BOOL)domainNeedsUpdate:(NSFileProviderDomain *)registered wanted:(NSFileProviderDomain *)wanted
{
    if (![registered.displayName isEqualToString:wanted.displayName]) return YES;
    if (@available(iOS 18.0, *)) {
        if (registered.supportsSyncingTrash != wanted.supportsSyncingTrash) return YES;
    }
    return NO;
}

#pragma mark - Lifecycle

/// keepStore: the account still exists (Touch ID turned on); its favorites,
/// tags and identifiers come back when the domain is registered again.
- (void)removeDomain:(NSFileProviderDomain *)domain keepStore:(BOOL)keepStore completion:(void (^)(NSError * _Nullable))completion
{
    NSString *identifier = domain.identifier;
    // RemoveAll is the only mode iOS offers (PreserveDirtyUserData and
    // PreserveDownloadedUserData are macOS-only), so removing a domain always
    // discards the system's replica -- including a file the user edited in
    // Files that has not been uploaded yet. That is why keepStore:YES only
    // keeps this side's store: there is no way to keep the other side's.
    [NSFileProviderManager removeDomain:domain
                                   mode:NSFileProviderDomainRemovalModeRemoveAll
                      completionHandler:^(NSURL * _Nullable preservedLocation, NSError * _Nullable error) {
        if (error) {
            Warning("removeDomain %@ failed: %@", identifier, error);
        } else {
            Debug("removed file provider domain %@ (store %@)", identifier, keepStore ? @"kept" : @"deleted");
            if (!keepStore) [self removeStoreForDomainIdentifier:identifier];
        }
        if (completion) completion(error);
    }];
}

- (void)addDomain:(NSFileProviderDomain *)domain completion:(void (^)(NSError * _Nullable))completion
{
    [NSFileProviderManager addDomain:domain completionHandler:^(NSError * _Nullable error) {
        if (error) {
            Warning("addDomain %@ failed: %@", domain.identifier, error);
        } else {
            Debug("added file provider domain %@ (%@)", domain.identifier, domain.displayName);
        }
        if (completion) completion(error);
    }];
}

- (void)removeStoreForDomainIdentifier:(NSString *)identifier
{
    NSURL *url = [SeafFPIdentifier storeURLForDomainIdentifier:identifier];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *suffix in @[@"", @"-wal", @"-shm", @"-journal"]) {
        NSString *path = [url.path stringByAppendingString:suffix];
        if ([fm fileExistsAtPath:path]) {
            [fm removeItemAtPath:path error:nil];
        }
    }
}

#pragma mark - Serialized mutations

/// Domain mutations run one at a time. Each op is handed a `done` to call when
/// the NSFileProviderManager call it made has answered.
- (void)enqueueDomainOp:(void (^)(dispatch_block_t done))op
{
    @synchronized (self) {
        [self.domainOps addObject:[op copy]];
        if (self.domainOpRunning) return;
        self.domainOpRunning = YES;
    }
    [self runNextDomainOp];
}

- (void)runNextDomainOp
{
    void (^op)(dispatch_block_t) = nil;
    @synchronized (self) {
        if (self.domainOps.count == 0) {
            self.domainOpRunning = NO;
            return;
        }
        op = self.domainOps.firstObject;
        [self.domainOps removeObjectAtIndex:0];
    }
    __weak typeof(self) weakSelf = self;
    op(^{
        [weakSelf runNextDomainOp];
    });
}

- (void)ensureDomainForConnection:(SeafConnection *)conn completion:(void (^)(NSError * _Nullable))completion
{
    // What the account looks like now decides what this op does; ops then run
    // in the order they were asked for.
    NSFileProviderDomain *domain = [self domainForConnection:conn];
    BOOL wants = [self.class connectionWantsDomain:conn];
    [self enqueueDomainOp:^(dispatch_block_t done) {
        [NSFileProviderManager getDomainsWithCompletionHandler:^(NSArray<NSFileProviderDomain *> *domains, NSError *error) {
            void (^finish)(NSError *) = ^(NSError *finishError) {
                if (completion) completion(finishError);
                done();
            };
            if (error) {
                Warning("getDomains failed: %@", error);
                finish(error);
                return;
            }
            NSFileProviderDomain *existing = nil;
            for (NSFileProviderDomain *d in domains) {
                if ([d.identifier isEqualToString:domain.identifier]) {
                    existing = d;
                    break;
                }
            }
            if (wants && !existing) {
                [self addDomain:domain completion:finish];
            } else if (wants && [self domainNeedsUpdate:existing wanted:domain]) {
                // Display name changed (account info fetched after login, or the
                // user renamed the account on the server): update in place.
                [self addDomain:domain completion:finish];
            } else if (!wants && existing) {
                [self removeDomain:existing keepStore:YES completion:finish];
            } else {
                finish(nil);
            }
        }];
    }];
}

- (void)removeDomainForConnection:(SeafConnection *)conn completion:(void (^)(NSError * _Nullable))completion
{
    NSFileProviderDomain *domain = [self domainForConnection:conn];
    [self enqueueDomainOp:^(dispatch_block_t done) {
        [NSFileProviderManager getDomainsWithCompletionHandler:^(NSArray<NSFileProviderDomain *> *domains, NSError *error) {
            void (^finish)(NSError *) = ^(NSError *finishError) {
                if (completion) completion(finishError);
                done();
            };
            if (error) {
                // Unknown state: leave the store alone, the next reconcile retries.
                Warning("getDomains failed: %@", error);
                finish(error);
                return;
            }
            NSFileProviderDomain *existing = nil;
            for (NSFileProviderDomain *d in domains) {
                if ([d.identifier isEqualToString:domain.identifier]) {
                    existing = d;
                    break;
                }
            }
            if (existing) {
                [self removeDomain:existing keepStore:NO completion:finish];
            } else {
                [self removeStoreForDomainIdentifier:domain.identifier];
                finish(nil);
            }
        }];
    }];
}

- (void)reconcileDomainsWithConnections:(NSArray<SeafConnection *> *)conns completion:(void (^)(void))completion
{
    // Snapshot on the caller's thread: conns is the live array SeafGlobal adds
    // to and removes from on the main thread, and copying it from a getDomains
    // callback on another thread is a crash. Anything saved after this point is
    // picked up by the ensureDomain op that saving it queues.
    NSArray<SeafConnection *> *accounts = [conns copy];
    [self enqueueDomainOp:^(dispatch_block_t done) {
        NSMutableDictionary<NSString *, NSFileProviderDomain *> *wanted = [NSMutableDictionary dictionary];
        NSMutableSet<NSString *> *known = [NSMutableSet set];   // every account, domain or not
        for (SeafConnection *conn in accounts) {
            NSFileProviderDomain *domain = [self domainForConnection:conn];
            [known addObject:domain.identifier];
            if ([self.class connectionWantsDomain:conn]) {
                wanted[domain.identifier] = domain;
            }
        }
        [NSFileProviderManager getDomainsWithCompletionHandler:^(NSArray<NSFileProviderDomain *> *domains, NSError *error) {
            void (^finish)(void) = ^{
                if (completion) completion();
                done();
            };
            if (error) {
                Warning("getDomains failed: %@", error);
                dispatch_async(dispatch_get_main_queue(), finish);
                return;
            }
            dispatch_group_t group = dispatch_group_create();
            NSMutableSet<NSString *> *present = [NSMutableSet set];
            for (NSFileProviderDomain *d in domains) {
                if ([SeafFPIdentifier isSeafileDomainIdentifier:d.identifier] && wanted[d.identifier]) {
                    [present addObject:d.identifier];
                    if ([self domainNeedsUpdate:d wanted:wanted[d.identifier]]) {
                        // addDomain with an existing identifier updates the
                        // domain in place (display name, trash handling).
                        dispatch_group_enter(group);
                        [self addDomain:wanted[d.identifier] completion:^(NSError *addError) {
                            dispatch_group_leave(group);
                        }];
                    }
                    continue;
                }
                // Foreign identifiers (old experiments) lose their store; an account
                // that merely turned Touch ID on keeps it.
                BOOL keepStore = [known containsObject:d.identifier];
                dispatch_group_enter(group);
                [self removeDomain:d keepStore:keepStore completion:^(NSError *removeError) {
                    dispatch_group_leave(group);
                }];
            }
            for (NSString *identifier in wanted) {
                if ([present containsObject:identifier]) continue;
                dispatch_group_enter(group);
                [self addDomain:wanted[identifier] completion:^(NSError *addError) {
                    dispatch_group_leave(group);
                }];
            }
            dispatch_group_notify(group, dispatch_get_main_queue(), finish);
        }];
    }];
}

#pragma mark - Signals

- (void)startObservingChangeNotifications
{
    if (self.observingChanges) return;
    self.observingChanges = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleChangeNotification:)
                                                 name:SeafFileProviderShouldSignalNotification
                                               object:nil];
}

- (void)handleChangeNotification:(NSNotification *)note
{
    SeafConnection *conn = [note.object isKindOfClass:[SeafConnection class]] ? note.object : nil;
    if (!conn) return;
    NSString *type = note.userInfo[SeafFileProviderSignalTypeKey];
    if ([type isEqualToString:SeafFileProviderSignalTypeAccount]) {
        // Account info (display name) arrived or changed: only the domain's
        // display name may need updating, the contents did not change.
        [self ensureDomainForConnection:conn completion:nil];
        return;
    }
    if ([type isEqualToString:SeafFileProviderSignalTypeRoot]) {
        [self signalRootForConnection:conn];
    } else {
        [self signalWorkingSetForConnection:conn];
    }
}

// Only the working set can be signalled for a replicated extension (other
// container identifiers are ignored by the system), so every signal ends up
// there; the extension re-lists the library list and member directories.
- (void)signalContainer:(NSFileProviderItemIdentifier)container forConnection:(SeafConnection *)conn
{
    if (![self.class connectionWantsDomain:conn]) return;
    NSFileProviderDomain *domain = [self domainForConnection:conn];
    @synchronized (self.pendingSignals) {
        if (self.pendingSignals[domain.identifier]) return;
        self.pendingSignals[domain.identifier] = domain;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSeafFPSignalCoalesceInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self sendPendingSignalForDomainIdentifier:domain.identifier];
    });
}

- (void)sendPendingSignalForDomainIdentifier:(NSString *)identifier
{
    NSFileProviderDomain *domain = nil;
    @synchronized (self.pendingSignals) {
        domain = self.pendingSignals[identifier];
        [self.pendingSignals removeObjectForKey:identifier];
    }
    if (!domain) return;   // already flushed
    NSFileProviderManager *manager = [NSFileProviderManager managerForDomain:domain];
    [manager signalEnumeratorForContainerItemIdentifier:NSFileProviderWorkingSetContainerItemIdentifier completionHandler:^(NSError * _Nullable error) {
        if (error) {
            Debug("signal working set for domain %@ failed: %@", domain.identifier, error);
        }
    }];
}

- (void)flushPendingSignals
{
    NSArray<NSString *> *identifiers = nil;
    @synchronized (self.pendingSignals) {
        identifiers = self.pendingSignals.allKeys;
    }
    for (NSString *identifier in identifiers) {
        [self sendPendingSignalForDomainIdentifier:identifier];
    }
}

- (void)signalWorkingSetForConnection:(SeafConnection *)conn
{
    [self signalContainer:NSFileProviderWorkingSetContainerItemIdentifier forConnection:conn];
}

- (void)signalRootForConnection:(SeafConnection *)conn
{
    [self signalContainer:NSFileProviderRootContainerItemIdentifier forConnection:conn];
}

- (void)signalWorkingSetForConnections:(NSArray<SeafConnection *> *)conns
{
    for (SeafConnection *conn in conns) {
        [self signalWorkingSetForConnection:conn];
    }
}

#pragma mark - Legacy cleanup

- (void)cleanupLegacyStorageIfNeeded
{
    if ([[SeafStorage.sharedObject objectForKey:kSeafFPLegacyStorageCleaned] boolValue]) {
        return;
    }
    NSURL *group = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:SEAFILE_SUITE_NAME];
    NSURL *legacy = [group URLByAppendingPathComponent:kSeafFPLegacyStorageDirectory isDirectory:YES];
    NSError *error = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:legacy.path]) {
        if (![[NSFileManager defaultManager] removeItemAtURL:legacy error:&error]) {
            Warning("Cannot remove legacy file provider storage: %@", error);
            return;
        }
        Debug("Removed legacy file provider storage at %@", legacy.path);
    }
    [SeafStorage.sharedObject setObject:@YES forKey:kSeafFPLegacyStorageCleaned];
}

@end
