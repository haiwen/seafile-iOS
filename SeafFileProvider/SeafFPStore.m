//
//  SeafFPStore.m
//  SeafFileProvider
//

#import "SeafFPStore.h"
#import "SeafFPIdentifier.h"
#import "Debug.h"
#import <sqlite3.h>

// 3: move journals carry `confirmed` / `existingDestinationNames` / `startedAt`
// and detached rows sit at `<path>#moved-<seq>`. A build of schema 2 would
// read an unacknowledged journal as a confirmed one, so it declines the store.
// 4: no format change; the upgrade retires the orphaned rows schema 1 left
// (retireOrphanedRecordsLocked), so stores already at 3 get it as well.
static const int kSeafFPSchemaVersion = 4;

static NSString * const kMetaSchemaVersion = @"schema_version";
static NSString * const kMetaSeq = @"seq";
static NSString * const kMetaRepoPublicationPrefix = @"fp_repo_publication_v1:";
static NSString * const kMetaSignal = @"fp_signal_v1";
static NSString * const kMetaRepoList = @"fp_repo_list_v1";
static NSString * const kMetaDirStampPrefix = @"dirstamp:";
static NSString * const kMetaDepartedPathPrefix = @"departed_path:";
static NSString * const kMetaActivityRecheckPrefix = @"activity_recheck:";
/// A listing that left rows it could not verify asks to be repeated this much later.
static const NSTimeInterval kUnverifiedRecheckDelay = 10;
/// BEGIN IMMEDIATE attempts (each waits the busy timeout) for the extension's own operations.
static const int kWriteLockAttempts = 3;

NSString * const SeafFPEntryName = @"name";
NSString * const SeafFPEntryPath = @"path";
NSString * const SeafFPEntryIsDir = @"isDir";
NSString * const SeafFPEntryOid = @"oid";
NSString * const SeafFPEntrySize = @"size";
NSString * const SeafFPEntryMtime = @"mtime";
NSString * const SeafFPEntryOp = @"op";
NSString * const SeafFPEntryOldPath = @"oldPath";
NSString * const SeafFPEntryRepoId = @"repoId";
NSString * const SeafFPEntryActivityHash = @"activityHash";
static NSString *SeafFPMoveRecoveryKey(NSString *uuid);
static NSString *SeafFPMoveDestinationKey(NSString *repoId, NSString *path);

NSString * const SeafFPActivityOpCreate = @"create";
NSString * const SeafFPActivityOpEdit = @"edit";
NSString * const SeafFPActivityOpDelete = @"delete";
NSString * const SeafFPActivityOpMove = @"move";

/// Normalized directory paths from the top down to `normalized`:
/// "/a/b/c" -> ["/a", "/a/b"] (+ "/a/b/c" with includeSelf). Root: none.
static NSArray<NSString *> *SeafFPAncestorPaths(NSString *normalized, BOOL includeSelf)
{
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSArray<NSString *> *components = [normalized componentsSeparatedByString:@"/"];
    NSMutableString *current = [NSMutableString string];
    NSUInteger last = components.count;
    for (NSUInteger i = 0; i < last; i++) {
        NSString *component = components[i];
        if (component.length == 0) continue;
        [current appendFormat:@"/%@", component];
        if (i + 1 == last && !includeSelf) break;
        [paths addObject:[current copy]];
    }
    return paths;
}

static NSString *SeafFPEntryString(NSDictionary *entry, NSString *key)
{
    id value = entry[key];
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? value : nil;
}

static long long SeafFPEntryNumber(NSDictionary *entry, NSString *key, long long fallback)
{
    id value = entry[key];
    return [value isKindOfClass:[NSNumber class]] ? [value longLongValue] : fallback;
}

static const char *kRecordColumns = "uuid, repo_id, path, is_dir, name, parent_uuid, oid, mtime, size, deleted, seq, created_seq, tomb_reason, tomb_txn, confirmed_placement, hint_revived_from, hint_revived_at, placement_time";

static void SeafFPBindText(sqlite3_stmt *stmt, int idx, NSString *value)
{
    if (value) {
        sqlite3_bind_text(stmt, idx, value.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, idx);
    }
}

static NSString *SeafFPColumnText(sqlite3_stmt *stmt, int idx)
{
    const unsigned char *text = sqlite3_column_text(stmt, idx);
    return text ? [NSString stringWithUTF8String:(const char *)text] : nil;
}

#pragma mark - Records

@interface SeafFPRecord ()
// A confirmed relocation or a known reuse of this path needs fresh evidence
// before a path-only activity can move this identity again.
@property (nonatomic, assign) BOOL confirmedPlacement;
@property (nonatomic, assign) long long placementTime;
// A listing's absence evidence can cross a decision batch, but only for
// hints that were already collected when this row was revived.
@property (nonatomic, assign) long long hintRevivedFrom;
@property (nonatomic, assign) long long hintRevivedAt;
@end

@implementation SeafFPRecord

- (NSString *)itemIdentifier
{
    return [SeafFPIdentifier identifierForUUID:self.uuid];
}

- (NSString *)parentItemIdentifier
{
    if (self.parentUUID.length > 0) {
        return [SeafFPIdentifier identifierForUUID:self.parentUUID];
    }
    return [SeafFPIdentifier identifierForRepo:self.repoId];
}

- (NSString *)directoryPath
{
    NSString *dir = self.path.stringByDeletingLastPathComponent;
    return dir.length > 0 ? dir : @"/";
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<SeafFPRecord %@ repo=%@ path=%@ dir=%d oid=%@ deleted=%d seq=%lld>",
            self.uuid, self.repoId, self.path, self.isDir, self.oid, self.deleted, self.seq];
}

@end

@implementation SeafFPDecoration

- (BOOL)isEmpty
{
    return self.favoriteRank == nil && self.tagData.length == 0 && self.lastUsedDate == nil;
}

@end

@implementation SeafFPPublicationBatch
@end

@implementation SeafFPWorkingSetPage
@end

@implementation SeafFPDirectoryCheck
@end

#pragma mark - Store

static const void *kSeafFPStoreQueueKey = &kSeafFPStoreQueueKey;

@interface SeafFPStore ()
{
    sqlite3 *_db;
    NSInteger _transactionDepth;
    BOOL _transactionOpen;
    // A statement inside the current transaction failed (a read included:
    // a failed read must not be taken for "no such row"). The outermost
    // commit then rolls everything back instead of committing a partial write.
    BOOL _transactionFailed;
    // Store seq when the outermost transaction began. Tombstones written in
    // it carry the value, so a row created by the same listing that judged
    // another row absent can be told apart from an older one.
    long long _transactionStartSeq;
    // Result code of the last sqlite call made through execLocked: /
    // prepareLocked: / setMetaValueLocked:, so a failure can be told apart
    // from a corrupt file (see SeafFPResultIsCorruption).
    int _lastResultCode;
    // The sqlite handle is only held while a perform: block runs. A WAL
    // connection keeps a shared lock on the -shm file for its whole lifetime,
    // and an extension suspended while holding a file lock is killed with
    // 0xDEAD10CC. So the outermost perform: opens the file, its block(s) run,
    // and the handle is closed again before the extension can be suspended.
    NSInteger _performDepth;
    BOOL _closed;   // close was called: nothing is ever opened again
    BOOL _createIfMissing;
}
@property (nonatomic, copy) NSString *domainIdentifier;
@property (nonatomic, copy) NSURL *storeURL;
@property (nonatomic, strong) dispatch_queue_t queue;
- (instancetype)initWithDomainIdentifier:(NSString *)identifier createIfMissing:(BOOL)create error:(NSError **)error;
- (BOOL)performCommittedWrite:(BOOL (^)(BOOL *rollback))block requestSignal:(BOOL)signal;
- (BOOL)requestWorkingSetSignalLocked;
- (nullable NSDictionary<NSString *, NSDictionary *> *)repositoryStatesLocked;
@end

@implementation SeafFPStore

+ (void)removeStoreForDomainIdentifier:(NSString *)domainIdentifier
{
    NSURL *url = [SeafFPIdentifier storeURLForDomainIdentifier:domainIdentifier];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *suffix in @[@"", @"-wal", @"-shm", @"-journal"]) {
        NSString *path = [url.path stringByAppendingString:suffix];
        if ([fm fileExistsAtPath:path]) {
            [fm removeItemAtPath:path error:nil];
        }
    }
}

- (instancetype)initWithDomainIdentifier:(NSString *)domainIdentifier error:(NSError **)error
{
    return [self initWithDomainIdentifier:domainIdentifier createIfMissing:YES error:error];
}

+ (instancetype)openExistingStoreForDomainIdentifier:(NSString *)identifier
{
    return [[self alloc] initWithDomainIdentifier:identifier createIfMissing:NO error:nil];
}

- (instancetype)initWithDomainIdentifier:(NSString *)domainIdentifier createIfMissing:(BOOL)create error:(NSError **)error
{
    self = [super init];
    if (!self) return nil;
    _domainIdentifier = [domainIdentifier copy];
    _createIfMissing = create;
    _queue = dispatch_queue_create("com.seafile.fileprovider.store", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(_queue, kSeafFPStoreQueueKey, (void *)kSeafFPStoreQueueKey, NULL);

    NSURL *url = [SeafFPIdentifier storeURLForDomainIdentifier:domainIdentifier];
    if (url.path.length == 0) {
        // No App Group container: sqlite3_open_v2 would happily open a private
        // temporary database and lose everything written to it.
        Warning("No store location for domain %@", domainIdentifier);
        if (error) {
            *error = [NSError errorWithDomain:@"SeafFPStore" code:SQLITE_CANTOPEN
                                     userInfo:@{NSLocalizedDescriptionKey: @"no app group container"}];
        }
        return nil;
    }
    if (create) [[NSFileManager defaultManager] createDirectoryAtURL:url.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    _storeURL = url;
    int rc = [self openHandleLocked];
    if (rc != SQLITE_OK) {
        Warning("Cannot open file provider store %@: %s", url.path, sqlite3_errmsg(_db));
        if (error) {
            *error = [NSError errorWithDomain:@"SeafFPStore" code:rc
                                     userInfo:@{NSLocalizedDescriptionKey: @(sqlite3_errmsg(_db) ?: "sqlite open failed")}];
        }
        [self closeHandleLocked];
        return nil;
    }
    BOOL newerSchema = NO;
    BOOL corrupt = NO;
    if (![self createSchemaLocked:&newerSchema corrupt:&corrupt]) {
        if (newerSchema) {
            // Written by a newer build (downgrade). The identity rows are the
            // only link between the system's items and Seafile paths: deleting
            // them would make every item resolve to NoSuchItem and be dropped
            // together with its favorites. Refuse to open; the caller answers
            // CannotSynchronize until the newer build is back.
            if (error) {
                *error = [NSError errorWithDomain:@"SeafFPStore" code:SQLITE_ERROR
                                         userInfo:@{NSLocalizedDescriptionKey: @"store schema newer than supported"}];
            }
            [self closeHandleLocked];
            return nil;
        }
        if (!corrupt) {
            // Busy (the app writing the same store), I/O error, disk full,
            // data protection: the file is intact and the identity rows and
            // decorations in it are the only copy of the favorites and tags.
            // Refuse to open and let the caller answer CannotSynchronize; the
            // next launch tries again.
            int failure = _lastResultCode;
            Warning("Cannot prepare file provider store %@ (%d), leaving it alone", url.path, failure);
            if (error) {
                *error = [NSError errorWithDomain:@"SeafFPStore" code:failure
                                         userInfo:@{NSLocalizedDescriptionKey: @"store temporarily unusable"}];
            }
            [self closeHandleLocked];
            return nil;
        }
        if (!create) { [self closeHandleLocked]; return nil; }
        // Corrupt: nothing can be read from it, so rebuild. Identity rows and
        // decorations are lost; the system re-learns the tree from the server
        // and drops items it can no longer resolve.
        Warning("Rebuilding broken file provider store %@", url.path);
        [self closeHandleLocked];
        [[self class] removeStoreForDomainIdentifier:domainIdentifier];
        rc = [self openHandleLocked];
        if (rc != SQLITE_OK) {
            if (error) {
                *error = [NSError errorWithDomain:@"SeafFPStore" code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: @"cannot rebuild store"}];
            }
            [self closeHandleLocked];
            return nil;
        }
        if (![self createSchemaLocked:NULL corrupt:NULL]) {
            if (error) {
                *error = [NSError errorWithDomain:@"SeafFPStore" code:SQLITE_ERROR
                                         userInfo:@{NSLocalizedDescriptionKey: @"cannot rebuild store"}];
            }
            [self closeHandleLocked];
            return nil;
        }
    }
    // Schema verified: let go of the file until the first request.
    [self closeHandleLocked];
    return self;
}

- (void)dealloc
{
    [self close];
}

/// Opens the sqlite file and applies the connection settings. Schema
/// creation is separate: init runs it once, later reopens skip it.
- (int)openHandleLocked
{
    int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX;
    if (_createIfMissing) flags |= SQLITE_OPEN_CREATE;
    int rc = sqlite3_open_v2(self.storeURL.path.fileSystemRepresentation, &_db, flags, NULL);
    _lastResultCode = rc;
    if (rc != SQLITE_OK) {
        Warning("Cannot open file provider store %@: %s", self.storeURL.path, _db ? sqlite3_errmsg(_db) : "");
        return rc;
    }
    sqlite3_busy_timeout(_db, 3000);
    [self execLocked:@"PRAGMA journal_mode=WAL"];
    [self execLocked:@"PRAGMA synchronous=NORMAL"];
    return SQLITE_OK;
}

- (void)closeHandleLocked
{
    if (!_db) return;
    // Every statement is finalized by its caller; close_v2 defers instead of
    // failing should one leak, so the handle is never kept by mistake.
    sqlite3_close_v2(_db);
    _db = NULL;
    _transactionDepth = 0;
    _transactionOpen = NO;
}

- (void)close
{
    if (dispatch_get_specific(kSeafFPStoreQueueKey) == kSeafFPStoreQueueKey) {
        _closed = YES;
        if (_performDepth == 0) [self closeHandleLocked];   // else the outermost perform: closes it
        return;
    }
    dispatch_sync(self.queue, ^{
        self->_closed = YES;
        [self closeHandleLocked];
    });
}

- (BOOL)isOpen
{
    __block BOOL open = NO;
    [self perform:^{ open = YES; }];   // the block only runs when the file could be opened
    return open;
}

#pragma mark - Low level

- (void)perform:(void (^)(void))block
{
    if (dispatch_get_specific(kSeafFPStoreQueueKey) == kSeafFPStoreQueueKey) {
        // Already on the store queue (nested call, or inside performBatch:):
        // the outermost perform: holds the handle open.
        if (_db) block();
        return;
    }
    dispatch_sync(self.queue, ^{
        if (self->_closed) return;
        if (!self->_db && [self openHandleLocked] != SQLITE_OK) {
            [self closeHandleLocked];
            return;
        }
        self->_performDepth++;
        @try {
            block();
        } @finally {
            self->_performDepth--;
            if (self->_performDepth == 0) {
                // No transaction (and no lock) may outlive a request; a stray
                // one is rolled back together with the handle.
                if (self->_transactionOpen) {
                    Warning("store transaction left open across perform:, rolling back");
                    [self execLocked:@"ROLLBACK"];
                }
                [self closeHandleLocked];
            }
        }
    });
}

// Transactions nest by depth: only the outermost BEGIN/COMMIT hits sqlite.
// BEGIN IMMEDIATE takes the write lock up front, so the seq counter cannot be
// handed out twice when the app and the extension write at the same time.
- (void)beginLocked
{
    if (_transactionDepth++ == 0) {
        _transactionFailed = NO;
        // Under contention (the app migrating into the same store) BEGIN can
        // fail even with the busy timeout. Every writer then gives up instead
        // of running its statements one by one: a failure halfway could not
        // be rolled back.
        _transactionOpen = [self execLocked:@"BEGIN IMMEDIATE"];
        _transactionStartSeq = _transactionOpen ? [self currentSeqLocked] : 0;
    }
}

/// beginLocked for the extension's own operations (a move, a new item, a
/// favorite): the server already changed, so giving up after one busy
/// timeout would leave the store behind it. Tries a few times more. The
/// main app's index writes use beginLocked and are simply retried later.
- (void)beginRetryingLocked
{
    [self beginLocked];
    for (int attempt = 1; attempt < kWriteLockAttempts && !_transactionOpen && _transactionDepth == 1; attempt++) {
        Info("file provider store busy, waiting for the write lock (%d)", attempt);
        [self leaveTransactionLocked];
        [self beginLocked];
    }
}

/// Ends the outermost transaction, whether it was committed, rolled back or
/// never opened.
- (BOOL)leaveTransactionLocked
{
    if (--_transactionDepth > 0) return NO;
    if (_transactionDepth < 0) _transactionDepth = 0;   // unbalanced; do not stay wedged
    _transactionFailed = NO;
    if (!_transactionOpen) return NO;
    _transactionOpen = NO;
    return YES;
}

/// Inside a transaction: remember that a statement failed (see _transactionFailed).
- (void)noteFailureLocked:(int)rc
{
    _lastResultCode = rc;
    if (_transactionDepth > 0) _transactionFailed = YES;
}

/// sqlite3_step that records a failure (anything but a row or done) for the
/// enclosing transaction.
- (int)stepLocked:(sqlite3_stmt *)stmt
{
    int rc = sqlite3_step(stmt);
    _lastResultCode = rc;
    if (rc != SQLITE_ROW && rc != SQLITE_DONE) {
        Warning("sqlite step failed (%d) %s", rc, sqlite3_errmsg(_db));
        [self noteFailureLocked:rc];
    }
    return rc;
}

/// YES when no statement of the current transaction failed so far.
- (BOOL)transactionHealthyLocked
{
    return !_transactionFailed;
}

/// Nested: YES while the transaction is still healthy (the outermost commit
/// decides). Outermost: YES when everything reached the file, also when BEGIN
/// had failed and every statement auto-committed on its own.
- (BOOL)commitLocked
{
    BOOL failed = _transactionFailed;
    if (![self leaveTransactionLocked]) {
        return _transactionDepth > 0 ? (_transactionOpen && !failed) : !failed;
    }
    if (failed) {
        Warning("store transaction had a failed statement, rolling back");
        [self execLocked:@"ROLLBACK"];
        return NO;
    }
    if ([self execLocked:@"COMMIT"]) return YES;
    // A COMMIT that fails (SQLITE_BUSY above all) leaves the transaction open
    // in sqlite. Without this rollback every later BEGIN IMMEDIATE would fail,
    // every later commitLocked would skip its COMMIT, and nothing this process
    // writes would ever reach the file again.
    Warning("sqlite COMMIT failed (%d), rolling back", _lastResultCode);
    [self execLocked:@"ROLLBACK"];
    return NO;
}

- (void)rollbackLocked
{
    // Nested: the enclosing transaction must not commit the partial work.
    if (_transactionDepth > 1) _transactionFailed = YES;
    if (![self leaveTransactionLocked]) return;
    [self execLocked:@"ROLLBACK"];
}

- (BOOL)performBatch:(void (NS_NOESCAPE ^)(void))block
{
    __block BOOL committed = NO;
    [self perform:^{
        [self beginRetryingLocked];
        if (!self->_transactionOpen) {
            [self leaveTransactionLocked];
            Warning("file provider store busy, batch skipped");
            return;
        }
        @try {
            block();
        } @finally {
            // An exception must not leave the depth counter (and with it every
            // later transaction) unbalanced.
            committed = [self commitLocked];
        }
    }];
    return committed;
}

/// YES when a result code says the file itself is unusable. Everything else
/// sqlite reports (busy, I/O error, disk full, read-only) is transient: the
/// store is intact and a later attempt can succeed.
static BOOL SeafFPResultIsCorruption(int rc)
{
    switch (rc & 0xff) {
        case SQLITE_CORRUPT:
        case SQLITE_NOTADB:
            return YES;
        default:
            return NO;
    }
}

- (BOOL)execLocked:(NSString *)sql
{
    char *err = NULL;
    int rc = sqlite3_exec(_db, sql.UTF8String, NULL, NULL, &err);
    _lastResultCode = rc;
    if (rc != SQLITE_OK) {
        Warning("sqlite exec failed (%d) %s: %@", rc, err ?: "", sql);
        if (err) sqlite3_free(err);
        return NO;
    }
    return YES;
}

- (sqlite3_stmt *)prepareLocked:(NSString *)sql
{
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    _lastResultCode = rc;
    if (rc != SQLITE_OK) {
        Warning("sqlite prepare failed (%d) %s: %@", rc, sqlite3_errmsg(_db), sql);
        [self noteFailureLocked:rc];
        return NULL;
    }
    return stmt;
}

/// newerSchema (optional): set when the store was written by a build with a
/// higher schema version; the store is intact, just not understood.
/// corrupt (optional): set when the failure means the file itself is unusable.
/// Every other failure (busy, I/O, disk full, read-only) is transient and must
/// not cost the caller its identity rows and decorations.
- (BOOL)createSchemaLocked:(BOOL *)newerSchema corrupt:(BOOL *)corrupt
{
    if (newerSchema) *newerSchema = NO;
    if (corrupt) *corrupt = NO;
    NSArray<NSString *> *ddl = @[
        (@"CREATE TABLE IF NOT EXISTS identity ("
          "uuid TEXT PRIMARY KEY, repo_id TEXT NOT NULL, path TEXT NOT NULL, is_dir INTEGER NOT NULL,"
          "name TEXT NOT NULL, parent_uuid TEXT, oid TEXT, mtime INTEGER, size INTEGER,"
          "deleted INTEGER NOT NULL DEFAULT 0, seq INTEGER NOT NULL, created_seq INTEGER NOT NULL DEFAULT 0,"
          "tomb_reason INTEGER NOT NULL DEFAULT 0, tomb_txn INTEGER NOT NULL DEFAULT 0,"
          "confirmed_placement INTEGER NOT NULL DEFAULT 0, hint_revived_from INTEGER NOT NULL DEFAULT 0,"
          "hint_revived_at INTEGER NOT NULL DEFAULT 0, placement_time INTEGER NOT NULL DEFAULT 0, UNIQUE(repo_id, path))"),
        @"CREATE INDEX IF NOT EXISTS idx_identity_parent ON identity(repo_id, parent_uuid, deleted)",
        @"CREATE INDEX IF NOT EXISTS idx_identity_seq ON identity(seq)",
        (@"CREATE TABLE IF NOT EXISTS decoration ("
          "item_id TEXT PRIMARY KEY, favorite_rank INTEGER, tag_data BLOB, last_used REAL)"),
        (@"CREATE TABLE IF NOT EXISTS container ("
          "container_id TEXT PRIMARY KEY, anchor TEXT, snapshot TEXT, enumerated_at REAL)"),
        (@"CREATE TABLE IF NOT EXISTS working_set ("
          "item_id TEXT PRIMARY KEY, reason INTEGER NOT NULL, seq INTEGER NOT NULL)"),
        @"CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)",
        // Directories the main app has to list because the activity log hinted
        // at a change there. A listing whose request started at or after
        // `version` confirms the check.
        (@"CREATE TABLE IF NOT EXISTS fp_check ("
          "repo_id TEXT NOT NULL, dir_path TEXT NOT NULL, version INTEGER NOT NULL,"
          "attempts INTEGER NOT NULL DEFAULT 0, not_before REAL NOT NULL DEFAULT 0, last_status INTEGER NOT NULL DEFAULT 0,"
          "denials INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(repo_id, dir_path))"),
        // Same-library renames and moves from the activity log, decided oldest first.
        (@"CREATE TABLE IF NOT EXISTS fp_hint ("
          "id INTEGER PRIMARY KEY AUTOINCREMENT, repo_id TEXT NOT NULL, old_path TEXT NOT NULL, new_path TEXT NOT NULL,"
          "is_dir INTEGER NOT NULL, event_time INTEGER NOT NULL, event_hash TEXT NOT NULL UNIQUE, version INTEGER NOT NULL,"
          "state INTEGER NOT NULL DEFAULT 0, decided_seq INTEGER NOT NULL DEFAULT 0, close_after REAL NOT NULL DEFAULT 0,"
          "source_uuid TEXT, source_oid TEXT, first_event_time INTEGER NOT NULL DEFAULT 0)"),
        @"CREATE INDEX IF NOT EXISTS idx_hint_repo ON fp_hint(repo_id, state, event_time)",
        @"CREATE INDEX IF NOT EXISTS idx_hint_waiting_target ON fp_hint(repo_id, new_path) WHERE state = 2",
        @"CREATE INDEX IF NOT EXISTS idx_hint_open_source ON fp_hint(repo_id, old_path, version) WHERE state = 0",
        (@"CREATE TABLE IF NOT EXISTS fp_path_replacement ("
          "repo_id TEXT NOT NULL, path TEXT NOT NULL, event_time INTEGER NOT NULL, PRIMARY KEY(repo_id, path))"),
        @"CREATE INDEX IF NOT EXISTS idx_replacement_time ON fp_path_replacement(event_time)",
        @"CREATE TABLE IF NOT EXISTS fp_activity_seen (hash TEXT PRIMARY KEY, event_time INTEGER NOT NULL)",
    ];
    // No transaction around the DDL: on an existing store every statement here
    // is a no-op that needs no write lock, and taking one on every open would
    // make the extension fail to start while the app holds it.
    for (NSString *sql in ddl) {
        if (![self execLocked:sql]) {
            if (corrupt) *corrupt = SeafFPResultIsCorruption(_lastResultCode);
            return NO;
        }
    }
    if (![self ensureStoreColumnsLocked]) {
        if (corrupt) *corrupt = SeafFPResultIsCorruption(_lastResultCode);
        return NO;
    }
    NSString *version = [self metaValueLockedForKey:kMetaSchemaVersion];
    if (version != nil && version.intValue < kSeafFPSchemaVersion) {
        [self beginLocked];
        if (!_transactionOpen) { [self leaveTransactionLocked]; return NO; }
        BOOL migrated = [self migrateLockedFromSchema:version.intValue]
            && [self setMetaValueLocked:[NSString stringWithFormat:@"%d", kSeafFPSchemaVersion] forKey:kMetaSchemaVersion];
        if (!migrated) {
            if (corrupt) *corrupt = SeafFPResultIsCorruption(_lastResultCode);
            [self rollbackLocked];
            return NO;
        }
        if (![self commitLocked]) return NO;
        version = [NSString stringWithFormat:@"%d", kSeafFPSchemaVersion];
    }
    if (version == nil) {
        // First open, or a store that lost its version stamp. Both meta rows
        // are written in one transaction: tables without a schema_version row
        // make the next open seed the seq counter, and a counter below the
        // values the rows already carry silently stops change enumeration.
        [self beginLocked];
        if (!_transactionOpen) { [self leaveTransactionLocked]; return NO; }
        BOOL stamped = [self metaValueLockedForKey:kMetaSchemaVersion] != nil;   // another process got there first
        if (!stamped) {
            // A store that lost its stamp may still hold data of an older
            // schema; the upgrade is idempotent (a new store has nothing to move).
            stamped = [self migrateLockedFromSchema:1]
                && [self setMetaValueLocked:[NSString stringWithFormat:@"%d", kSeafFPSchemaVersion] forKey:kMetaSchemaVersion]
                && [self setMetaValueLocked:[NSString stringWithFormat:@"%lld", [self maxRowSeqLocked]] forKey:kMetaSeq];
        }
        if (!stamped) {
            if (corrupt) *corrupt = SeafFPResultIsCorruption(_lastResultCode);
            [self rollbackLocked];
            return NO;
        }
        if (![self commitLocked]) return NO;
    } else if (version.intValue > kSeafFPSchemaVersion) {
        Warning("Store schema %@ is newer than supported %d", version, kSeafFPSchemaVersion);
        if (newerSchema) *newerSchema = YES;
        return NO;
    }
    // The version stamp may survive while only the sequence row was lost.
    // Repair it before reads: otherwise repository freshness barriers could
    // reject every new response until an unrelated identity write reseeds it.
    if ([self metaValueLockedForKey:kMetaSeq] == nil) {
        [self beginLocked];
        if (!_transactionOpen) { [self leaveTransactionLocked]; return NO; }
        BOOL seeded = [self metaValueLockedForKey:kMetaSeq] != nil
            || [self setMetaValueLocked:[NSString stringWithFormat:@"%lld", [self maxRowSeqLocked]] forKey:kMetaSeq];
        if (!seeded) { [self rollbackLocked]; return NO; }
        if (![self commitLocked]) return NO;
    }
    return YES;
}

/// These columns are additive. Older builds can still read the tables.
- (BOOL)ensureStoreColumnsLocked
{
    NSString *integer = @"INTEGER NOT NULL DEFAULT 0";
    return [self ensureColumnsLocked:@[@"created_seq", @"tomb_reason", @"tomb_txn", @"confirmed_placement", @"hint_revived_from", @"hint_revived_at", @"placement_time"]
                              ofTable:@"identity" type:integer]
        && [self ensureColumnsLocked:@[@"denials"] ofTable:@"fp_check" type:integer]
        && [self ensureColumnsLocked:@[@"source_uuid", @"source_oid"] ofTable:@"fp_hint" type:@"TEXT"]
        && [self ensureColumnsLocked:@[@"first_event_time"] ofTable:@"fp_hint" type:integer];
}

- (nullable NSSet<NSString *> *)columnNamesLockedOfTable:(NSString *)table
{
    sqlite3_stmt *stmt = [self prepareLocked:[NSString stringWithFormat:@"PRAGMA table_info(%@)", table]];
    if (!stmt) return nil;
    NSMutableSet<NSString *> *columns = [NSMutableSet set];
    int rc;
    while ((rc = [self stepLocked:stmt]) == SQLITE_ROW) {
        NSString *name = SeafFPColumnText(stmt, 1);
        if (name) [columns addObject:name];
    }
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? columns : nil;
}

- (BOOL)ensureColumnsLocked:(NSArray<NSString *> *)wanted ofTable:(NSString *)table type:(NSString *)type
{
    NSSet *columns = [self columnNamesLockedOfTable:table];
    if (!columns) return NO;
    if ([[NSSet setWithArray:wanted] isSubsetOfSet:columns]) return YES;
    [self beginLocked];
    if (!_transactionOpen) { [self leaveTransactionLocked]; return NO; }
    // The other process may have added them while we waited for the lock.
    columns = [self columnNamesLockedOfTable:table];
    if (!columns) { [self rollbackLocked]; return NO; }
    for (NSString *column in wanted) {
        if ([columns containsObject:column]) continue;
        NSString *sql = [NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN %@ %@", table, column, type];
        if (![self execLocked:sql]) { [self rollbackLocked]; return NO; }
    }
    return [self commitLocked];
}

/// Upgrades data written by an older schema; runs in the caller's transaction.
- (BOOL)migrateLockedFromSchema:(int)from
{
    if (from < 2) {
        // Activity rechecks were path lists in meta without a version: each
        // becomes a directory check that only a later listing confirms.
        sqlite3_stmt *stmt = [self prepareLocked:@"SELECT key, value FROM meta WHERE key GLOB 'activity_recheck:*'"];
        if (!stmt) return NO;
        NSMutableDictionary<NSString *, NSString *> *rows = [NSMutableDictionary dictionary];
        int rc;
        while ((rc = [self stepLocked:stmt]) == SQLITE_ROW) {
            NSString *key = SeafFPColumnText(stmt, 0), *value = SeafFPColumnText(stmt, 1);
            if (key) rows[key] = value ?: @"";
        }
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) return NO;
        for (NSString *key in rows) {
            NSString *repoId = [key substringFromIndex:kMetaActivityRecheckPrefix.length];
            id paths = [NSJSONSerialization JSONObjectWithData:[rows[key] dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data] options:0 error:nil];
            if (repoId.length > 0 && [paths isKindOfClass:[NSArray class]]) {
                for (id path in paths) {
                    if ([path isKindOfClass:[NSString class]] && [path length] > 0
                        && ![self requestDirectoryCheckLockedForRepo:repoId path:path]) return NO;
                }
            }
            if (![self setMetaValueLocked:nil forKey:key]) return NO;
        }
        // The replayed activity history is gone: the paths it saw vanish
        // keep a durable barrier against stale caches, nothing else.
        stmt = [self prepareLocked:@"SELECT key, value FROM meta WHERE key GLOB 'activity_log:*'"];
        if (!stmt) return NO;
        [rows removeAllObjects];
        while ((rc = [self stepLocked:stmt]) == SQLITE_ROW) {
            NSString *key = SeafFPColumnText(stmt, 0), *value = SeafFPColumnText(stmt, 1);
            if (key) rows[key] = value ?: @"";
        }
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) return NO;
        long long barrier = [self currentSeqLocked];
        for (NSString *key in rows) {
            NSString *repoId = [key substringFromIndex:@"activity_log:".length];
            id log = [NSJSONSerialization JSONObjectWithData:[rows[key] dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data] options:0 error:nil];
            NSDictionary *gone = [log isKindOfClass:[NSDictionary class]] ? log[@"gone"] : nil;
            if (repoId.length > 0 && [gone isKindOfClass:[NSDictionary class]]) {
                for (id path in gone) {
                    if (![path isKindOfClass:[NSString class]] || [path length] == 0) continue;
                    NSString *barrierKey = [self departedPathKeyForRepo:repoId path:[SeafFPIdentifier normalizedPath:path]];
                    if (![self metaValueLockedForKey:barrierKey]
                        && ![self setMetaValueLocked:[NSString stringWithFormat:@"%lld", barrier] forKey:barrierKey]) return NO;
                }
            }
            if (![self setMetaValueLocked:nil forKey:key]) return NO;
        }
    }
    if (from < 3) {
        // Journals of schema 2 carry no start time; without one they would
        // count as expired at once. They were written after the server's
        // acknowledgement, so they start their retention now.
        sqlite3_stmt *stmt = [self prepareLocked:@"SELECT key, value FROM meta WHERE key GLOB 'fp_confirmed_move:*'"];
        if (!stmt) return NO;
        NSMutableDictionary<NSString *, NSString *> *rows = [NSMutableDictionary dictionary];
        int rc;
        while ((rc = [self stepLocked:stmt]) == SQLITE_ROW) {
            NSString *key = SeafFPColumnText(stmt, 0), *value = SeafFPColumnText(stmt, 1);
            if (key) rows[key] = value ?: @"";
        }
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) return NO;
        long long now = (long long)[NSDate date].timeIntervalSince1970;
        for (NSString *key in rows) {
            id journal = [NSJSONSerialization JSONObjectWithData:[rows[key] dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data] options:0 error:nil];
            if (![journal isKindOfClass:[NSDictionary class]] || journal[@"startedAt"]) continue;
            NSMutableDictionary *stamped = [journal mutableCopy];
            stamped[@"startedAt"] = @(now);
            NSData *data = [NSJSONSerialization dataWithJSONObject:stamped options:0 error:nil];
            if (!data || ![self setMetaValueLocked:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] forKey:key]) return NO;
        }
    }
    if (from < 4 && ![self retireOrphanedRecordsLocked]) return NO;
    return YES;
}

/// Tombstones live rows whose parent is missing, a tombstone, not a
/// directory or in another library. Schema 1 builds (4.0.9 and earlier) left
/// them behind: a move onto a stale live directory tombstoned only that
/// directory, and a listing that showed a file where a directory had been
/// flipped the row in place, children and all. The system cannot place such
/// a row, and no listing retires it. It gets the tombstone the current
/// code gives a subtree it replaces, so a later listing that shows the path
/// again revives it. Each pass exposes the level below; it repeats until a
/// pass finds nothing.
- (BOOL)retireOrphanedRecordsLocked
{
    static NSString * const sql =
        @"SELECT c.uuid FROM identity c LEFT JOIN identity p ON p.uuid = c.parent_uuid "
         "WHERE c.deleted = 0 AND c.parent_uuid IS NOT NULL AND c.parent_uuid != '' "
         "AND (p.uuid IS NULL OR p.deleted != 0 OR p.is_dir = 0 OR p.repo_id != c.repo_id)";
    NSUInteger retired = 0;
    for (;;) {
        sqlite3_stmt *stmt = [self prepareLocked:sql];
        if (!stmt) return NO;
        NSMutableArray<NSString *> *uuids = [NSMutableArray array];
        int rc;
        while ((rc = [self stepLocked:stmt]) == SQLITE_ROW) {
            NSString *uuid = SeafFPColumnText(stmt, 0);
            if (uuid) [uuids addObject:uuid];
        }
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) return NO;
        if (uuids.count == 0) break;
        for (NSString *uuid in uuids) {
            SeafFPRecord *record = [self recordLockedForUUID:uuid];
            if (!record) return NO;
            record.deleted = YES;
            record.tombReason = SeafFPTombReasonReplaced;
            record.tombTxn = _transactionStartSeq;
            record.seq = [self nextSeqLocked];
            if (record.seq <= 0 || ![self writeRecordLocked:record insert:NO]) return NO;
        }
        retired += uuids.count;
    }
    if (retired > 0) Warning("Retired %lu rows whose parent chain was broken", (unsigned long)retired);
    return YES;
}

#pragma mark - Meta

- (NSString *)metaValueLockedForKey:(NSString *)key
{
    return [self metaValueLockedForKey:key failed:NULL];
}

/// failed (optional): set when the row could not be read, as opposed to not
/// being there (nil either way). Outside a transaction nothing else records it.
- (NSString *)metaValueLockedForKey:(NSString *)key failed:(BOOL *)failed
{
    if (failed) *failed = YES;
    NSString *value = nil;
    sqlite3_stmt *stmt = [self prepareLocked:@"SELECT value FROM meta WHERE key = ?"];
    if (!stmt) return nil;
    SeafFPBindText(stmt, 1, key);
    int rc = [self stepLocked:stmt];
    if (rc == SQLITE_ROW) {
        value = SeafFPColumnText(stmt, 0);
    }
    sqlite3_finalize(stmt);
    if (failed) *failed = (rc != SQLITE_ROW && rc != SQLITE_DONE);
    return value;
}

- (BOOL)setMetaValueLocked:(NSString *)value forKey:(NSString *)key
{
    sqlite3_stmt *stmt;
    if (value == nil) {
        stmt = [self prepareLocked:@"DELETE FROM meta WHERE key = ?"];
        if (!stmt) return NO;
        SeafFPBindText(stmt, 1, key);
    } else {
        stmt = [self prepareLocked:@"INSERT OR REPLACE INTO meta(key, value) VALUES(?, ?)"];
        if (!stmt) return NO;
        SeafFPBindText(stmt, 1, key);
        SeafFPBindText(stmt, 2, value);
    }
    int rc = [self stepLocked:stmt];
    _lastResultCode = rc;
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        Warning("sqlite meta write failed (%d) %s for %@", rc, sqlite3_errmsg(_db), key);
        return NO;
    }
    return YES;
}

/// The highest seq any row carries. The counter is seeded from it when the
/// meta row is missing, so a store whose version stamp was lost cannot hand
/// out seq values the existing rows already use.
- (long long)maxRowSeqLocked
{
    long long maxSeq = 0;
    // Check and hint versions are seqs too: a counter below them would leave
    // checks no listing can ever confirm.
    for (NSString *sql in @[@"SELECT MAX(seq) FROM identity", @"SELECT MAX(seq) FROM working_set",
                            @"SELECT MAX(version) FROM fp_check", @"SELECT MAX(MAX(version), MAX(decided_seq)) FROM fp_hint"]) {
        sqlite3_stmt *stmt = [self prepareLocked:sql];
        if (!stmt) continue;
        if ([self stepLocked:stmt] == SQLITE_ROW) {
            maxSeq = MAX(maxSeq, sqlite3_column_int64(stmt, 0));
        }
        sqlite3_finalize(stmt);
    }
    for (NSDictionary *state in [self repositoryStatesLocked].allValues) {
        maxSeq = MAX(maxSeq, MAX([state[@"eventSeq"] longLongValue], [state[@"observedSeq"] longLongValue]));
    }
    // Unchanged repository responses still carry ordering evidence. A
    // recovered counter must advance past their accepted request boundary.
    maxSeq = MAX(maxSeq, [[self jsonMetaLocked:kMetaRepoList][@"observedSeq"] longLongValue]);
    return maxSeq;
}

- (long long)currentSeqLocked
{
    return [self metaValueLockedForKey:kMetaSeq].longLongValue;
}

- (long long)nextSeqLocked
{
    // Most writes only update the counter. Computing the recovery floor for
    // every row would repeatedly scan repository metadata during a big pass.
    sqlite3_stmt *increment = [self prepareLocked:@"UPDATE meta SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT) WHERE key = ? RETURNING CAST(value AS INTEGER)"];
    if (!increment) return 0;
    SeafFPBindText(increment, 1, kMetaSeq);
    int result = [self stepLocked:increment];
    long long value = result == SQLITE_ROW ? sqlite3_column_int64(increment, 0) : 0;
    sqlite3_finalize(increment);
    if (result == SQLITE_ROW) return value;
    if (result != SQLITE_DONE) return 0;
    long long recoveryFloor = [self maxRowSeqLocked];
    // One statement: two processes can never be handed the same value, not
    // even when BEGIN IMMEDIATE failed and the caller runs in autocommit. A
    // missing counter row is seeded from the rows, like createSchemaLocked:.
    sqlite3_stmt *stmt = [self prepareLocked:
        @"INSERT INTO meta(key, value) VALUES(?1, CAST((SELECT COALESCE(MAX(s), 0) FROM "
         "(SELECT MAX(seq) AS s FROM identity UNION ALL SELECT MAX(seq) FROM working_set UNION ALL SELECT ?2)) + 1 AS TEXT)) "
         "ON CONFLICT(key) DO UPDATE SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT) "
         "RETURNING CAST(value AS INTEGER)"];
    if (stmt) {
        SeafFPBindText(stmt, 1, kMetaSeq);
        sqlite3_bind_int64(stmt, 2, recoveryFloor);
        int rc = [self stepLocked:stmt];
        _lastResultCode = rc;
        long long next = rc == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0;
        sqlite3_finalize(stmt);
        if (next > 0) return next;
        Warning("sqlite seq increment failed (%d) %s", rc, sqlite3_errmsg(_db));
    }
    // A row written with seq 0 would be invisible to change enumeration.
    [self noteFailureLocked:_lastResultCode == SQLITE_OK ? SQLITE_ERROR : _lastResultCode];
    return 0;
}

- (long long)currentSeq
{
    __block long long seq = 0;
    [self perform:^{ seq = [self currentSeqLocked]; }];
    return seq;
}

- (long long)nextSeq
{
    __block long long seq = 0;
    [self perform:^{ seq = [self nextSeqLocked]; }];
    return seq;
}

- (NSString *)metaValueForKey:(NSString *)key
{
    __block NSString *value = nil;
    [self perform:^{ value = [self metaValueLockedForKey:key]; }];
    return value;
}

- (void)setMetaValue:(NSString *)value forKey:(NSString *)key
{
    [self perform:^{ [self setMetaValueLocked:value forKey:key]; }];
}

#pragma mark - Public File Provider publication

/// Empty when the row is missing; nil when it cannot be read or parsed.
- (NSDictionary *)jsonMetaLocked:(NSString *)key
{
    BOOL failed = NO;
    NSString *raw = [self metaValueLockedForKey:key failed:&failed];
    if (failed) return nil;
    if (!raw) return @{};
    id value = [NSJSONSerialization JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if ([key hasPrefix:@"fp_confirmed_move:"]) {
        BOOL valid = [value isKindOfClass:[NSDictionary class]];
        if (valid && [value count] > 0) {
            for (NSString *field in @[@"sourceRepo", @"sourcePath", @"repo", @"dir", @"name"]) {
                valid &= [value[field] isKindOfClass:[NSString class]] && [value[field] length] > 0;
            }
            for (NSString *field in @[@"sourceSeq", @"start", @"isDir"]) valid &= [value[field] isKindOfClass:[NSNumber class]];
            for (NSString *field in @[@"oid", @"parent", @"requestedName"]) {
                if (value[field]) valid &= [value[field] isKindOfClass:[NSString class]];
            }
            for (NSString *field in @[@"confirmed", @"serverTime", @"startedAt", @"sourceMtime", @"sourceSize"]) {
                if (value[field]) valid &= [value[field] isKindOfClass:[NSNumber class]];
            }
            id names = value[@"existingDestinationNames"], entries = value[@"existingDestinationEntries"];
            if (names) {
                valid &= [names isKindOfClass:[NSArray class]];
                if ([names isKindOfClass:[NSArray class]]) for (id name in names) valid &= [name isKindOfClass:[NSString class]];
            }
            if (entries) {
                valid &= [entries isKindOfClass:[NSDictionary class]];
                if ([entries isKindOfClass:[NSDictionary class]]) for (id name in entries) {
                    valid &= [name isKindOfClass:[NSString class]] && [entries[name] isKindOfClass:[NSDictionary class]];
                    if ([entries[name] isKindOfClass:[NSDictionary class]]) {
                        id oid = entries[name][SeafFPEntryOid], isDir = entries[name][SeafFPEntryIsDir];
                        if (oid) valid &= [oid isKindOfClass:[NSString class]];
                        if (isDir) valid &= [isDir isKindOfClass:[NSNumber class]];
                    }
                }
            }
        }
        if (!valid) {
            // Isolate this row, retaining the exact bytes for diagnosis. The
            // pending marker blocks replay, while ordinary listings can proceed.
            NSString *uuid = [key substringFromIndex:@"fp_confirmed_move:".length];
            BOOL isolated = [self performBatch:^{
                if (![self setMetaValueLocked:raw forKey:[@"fp_quarantined_move:" stringByAppendingString:uuid]]
                    || ![self setMetaValueLocked:@"1" forKey:[@"fp_move_quarantine_pending:" stringByAppendingString:uuid]]
                    || ![self setMetaValueLocked:nil forKey:key]) { self->_transactionFailed = YES; return; }
                sqlite3_stmt *stmt = [self prepareLocked:@"DELETE FROM meta WHERE key GLOB 'fp_move_destination:*' AND value = ?"];
                if (!stmt) { self->_transactionFailed = YES; return; }
                SeafFPBindText(stmt, 1, uuid);
                int rc = [self stepLocked:stmt]; sqlite3_finalize(stmt);
                if (rc != SQLITE_DONE) self->_transactionFailed = YES;
            }];
            return isolated ? @{} : nil;
        }
    }
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (BOOL)writeJSONMetaLocked:(NSDictionary *)value key:(NSString *)key
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    return data && [self setMetaValueLocked:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] forKey:key];
}

- (NSDictionary<NSString *, NSDictionary *> *)repositoryStatesLocked
{
    sqlite3_stmt *stmt = [self prepareLocked:@"SELECT key, value FROM meta WHERE key GLOB 'fp_repo_publication_v1:*'"];
    if (!stmt) return nil;
    NSMutableDictionary *states = [NSMutableDictionary dictionary];
    int rc;
    while ((rc = [self stepLocked:stmt]) == SQLITE_ROW) {
        NSString *key = SeafFPColumnText(stmt, 0), *raw = SeafFPColumnText(stmt, 1);
        if (raw.length == 0) { sqlite3_finalize(stmt); return nil; }
        id state = [NSJSONSerialization JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        NSString *repoId = [key substringFromIndex:kMetaRepoPublicationPrefix.length];
        if (![state isKindOfClass:[NSDictionary class]] || ![state[@"repoId"] isEqual:repoId]
            || ![state[@"eventSeq"] isKindOfClass:[NSNumber class]] || ![state[@"availability"] isKindOfClass:[NSString class]]) {
            sqlite3_finalize(stmt);
            return nil; // Preserve an unreadable/future state instead of treating it as empty.
        }
        states[repoId] = state;
    }
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? states : nil;
}

- (NSDictionary<NSString *, NSDictionary *> *)repositoryStates
{
    __block NSDictionary *states = nil;
    [self perform:^{ states = [self repositoryStatesLocked]; }];
    return states;
}

- (BOOL)hasAuthoritativeRepositoryList
{
    __block BOOL known = NO;
    [self perform:^{ known = [[self jsonMetaLocked:kMetaRepoList][@"known"] boolValue]; }];
    return known;
}

- (BOOL)applyRepositorySnapshot:(NSArray<NSDictionary *> *)repositories complete:(BOOL)complete fromCache:(BOOL)fromCache requestStartSeq:(long long)start
{
    return [self applyRepositorySnapshotResult:repositories complete:complete fromCache:fromCache requestStartSeq:start] == SeafFPWriteChanged;
}

- (long long)beginRepositoryRequest
{
    long long seq = [self nextSeq];
    return seq > 0 ? seq : -1;
}

- (SeafFPWriteResult)applyRepositorySnapshotResult:(NSArray<NSDictionary *> *)repositories complete:(BOOL)complete fromCache:(BOOL)fromCache requestStartSeq:(long long)start
{
    return [self performWrite:^BOOL(BOOL *rollback) {
        NSDictionary *previous = [self repositoryStatesLocked];
        if (!previous) { *rollback = YES; return NO; }
        NSDictionary *catalog = [self jsonMetaLocked:kMetaRepoList];
        if (!catalog) { *rollback = YES; return NO; }
        if (!fromCache && complete && start >= 0 && [catalog[@"known"] boolValue]
            && [catalog[@"observedSeq"] longLongValue] >= start) return NO;
        NSMutableDictionary *incoming = [NSMutableDictionary dictionary];
        for (NSDictionary *info in repositories) {
            if (![info isKindOfClass:[NSDictionary class]] || ![info[@"repoId"] isKindOfClass:[NSString class]] || [info[@"repoId"] length] == 0) {
                *rollback = YES; return NO;
            }
            // A library can occur in multiple groups; publish one stable identity.
            if (!incoming[info[@"repoId"]]) incoming[info[@"repoId"]] = info;
        }
        NSMutableSet *ids = [NSMutableSet setWithArray:incoming.allKeys];
        if (complete && !fromCache && start >= 0) {
            [ids addObjectsFromArray:previous.allKeys];
            // A pre-publication Store may know identities without any library
            // metadata yet. Persist their removal too, rather than relying on
            // an ephemeral root-list diff that can be lost before delivery.
            sqlite3_stmt *known = [self prepareLocked:@"SELECT DISTINCT repo_id FROM identity"];
            if (!known) { *rollback = YES; return NO; }
            int rc;
            while ((rc = [self stepLocked:known]) == SQLITE_ROW) [ids addObject:SeafFPColumnText(known, 0)];
            sqlite3_finalize(known);
            if (rc != SQLITE_DONE) { *rollback = YES; return NO; }
        }
        BOOL changed = NO;
        for (NSString *repoId in [ids.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
            NSDictionary *old = previous[repoId], *info = incoming[repoId];
            if (!old && [catalog[@"known"] boolValue] && (fromCache || start < [catalog[@"observedSeq"] longLongValue])) continue;
            if (old && (fromCache || (start < 0 && [old[@"authoritative"] boolValue])
                || ([old[@"authoritative"] boolValue] && start < [old[@"observedSeq"] longLongValue]))) continue;
            NSString *availability = info ? ([info[@"locked"] boolValue] ? @"locked" : @"visible") : @"removed";
            // A removed library has nothing left to list, also when it was
            // removed before and a late activity asked for it again.
            if ([availability isEqual:@"removed"] && complete && !fromCache && start >= 0
                && (![self dropDirectoryChecksLockedOfRepo:repoId] || ![self dropMoveJournalsLockedOfRepo:repoId])) { *rollback = YES; return NO; }
            NSMutableDictionary *state = old ? [old mutableCopy] : [@{@"name":repoId, @"perm":@"", @"editable":@NO, @"mtime":@0, @"ooid":@""} mutableCopy];
            state[@"repoId"] = repoId;
            state[@"source"] = fromCache ? @"cache" : @"network";
            state[@"availability"] = availability;
            if (info) {
                for (NSString *key in @[@"name", @"perm", @"ooid"]) state[key] = [info[key] isKindOfClass:[NSString class]] ? info[key] : @"";
                state[@"editable"] = @([info[@"editable"] boolValue]);
                state[@"mtime"] = @([info[@"mtime"] longLongValue]);
            }
            BOOL different = !old;
            for (NSString *key in @[@"availability", @"name", @"perm", @"editable", @"mtime", @"ooid"]) {
                if (![old[key] isEqual:state[key]]) different = YES;
            }
            state[@"authoritative"] = @(!fromCache && start >= 0);
            state[@"observedSeq"] = @(start);
            if (different) {
                long long seq = [self nextSeqLocked];
                if (seq <= 0) { *rollback = YES; return NO; }
                state[@"eventSeq"] = @(seq);
                state[@"revision"] = @(seq);
                state[@"eventKind"] = [availability isEqual:@"removed"] ? @"delete" : @"update";
                BOOL republish = [availability isEqual:@"visible"] && (!old || ![old[@"availability"] isEqual:@"visible"]
                    || ![old[@"perm"] isEqual:state[@"perm"]] || ![old[@"editable"] isEqual:state[@"editable"]]);
                if (republish) { state[@"pendingRevision"] = @(seq); state[@"afterUUID"] = @""; }
                if (![availability isEqual:@"visible"]) { [state removeObjectForKey:@"pendingRevision"]; [state removeObjectForKey:@"afterUUID"]; }
                changed = YES;
            }
            if (![state isEqual:old] && ![self writeJSONMetaLocked:state key:[kMetaRepoPublicationPrefix stringByAppendingString:repoId]]) {
                *rollback = YES; return NO;
            }
        }
        if (complete && !fromCache && start >= 0) {
            // Libraries only the activity log knows about (never listed, no
            // identity): their checks and hints go when the list lacks them.
            for (NSString *sql in @[@"SELECT DISTINCT repo_id FROM fp_check", @"SELECT DISTINCT repo_id FROM fp_hint"]) {
                sqlite3_stmt *queued = [self prepareLocked:sql];
                if (!queued) { *rollback = YES; return NO; }
                NSMutableArray<NSString *> *repoIds = [NSMutableArray array];
                int rc;
                while ((rc = [self stepLocked:queued]) == SQLITE_ROW) {
                    NSString *repoId = SeafFPColumnText(queued, 0);
                    if (repoId && !incoming[repoId] && ![ids containsObject:repoId]) [repoIds addObject:repoId];
                }
                sqlite3_finalize(queued);
                if (rc != SQLITE_DONE) { *rollback = YES; return NO; }
                for (NSString *repoId in repoIds) {
                    if (![self dropDirectoryChecksLockedOfRepo:repoId]) { *rollback = YES; return NO; }
                }
            }
            if (![self writeJSONMetaLocked:@{@"known":@YES, @"observedSeq":@(start)} key:kMetaRepoList]) { *rollback = YES; return NO; }
        }
        return changed;
    } requestSignal:YES];
}

- (BOOL)hasPendingRepositoryPublications
{
    for (NSDictionary *state in self.repositoryStates.allValues) if (state[@"pendingRevision"]) return YES;
    return NO;
}

- (BOOL)publishPendingRepositoryRecordsWithLimit:(NSUInteger)limit
{
    if (limit == 0) return NO;
    return [self performIndexWrite:^BOOL(BOOL *rollback) {
        NSDictionary *states = [self repositoryStatesLocked];
        if (!states) { *rollback = YES; return NO; }
        for (NSString *repoId in [states.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            NSMutableDictionary *state = [states[repoId] mutableCopy];
            if (!state[@"pendingRevision"] || ![state[@"availability"] isEqual:@"visible"]) continue;
            sqlite3_stmt *stmt = [self prepareLocked:@"SELECT uuid FROM identity WHERE repo_id = ? AND deleted = 0 AND uuid > ? ORDER BY uuid LIMIT ?"];
            if (!stmt) { *rollback = YES; return NO; }
            SeafFPBindText(stmt, 1, repoId); SeafFPBindText(stmt, 2, state[@"afterUUID"] ?: @"");
            sqlite3_bind_int64(stmt, 3, (sqlite3_int64)MIN(limit, (NSUInteger)500));
            NSMutableArray *uuids = [NSMutableArray array];
            int rc;
            while ((rc = [self stepLocked:stmt]) == SQLITE_ROW) [uuids addObject:SeafFPColumnText(stmt, 0)];
            sqlite3_finalize(stmt);
            if (rc != SQLITE_DONE) { *rollback = YES; return NO; }
            for (NSString *uuid in uuids) {
                long long seq = [self nextSeqLocked];
                stmt = [self prepareLocked:@"UPDATE identity SET seq = ? WHERE uuid = ? AND repo_id = ? AND deleted = 0"];
                if (!stmt || seq <= 0) { if (stmt) sqlite3_finalize(stmt); *rollback = YES; return NO; }
                sqlite3_bind_int64(stmt, 1, seq); SeafFPBindText(stmt, 2, uuid); SeafFPBindText(stmt, 3, repoId);
                rc = [self stepLocked:stmt]; sqlite3_finalize(stmt);
                if (rc != SQLITE_DONE) { *rollback = YES; return NO; }
            }
            if (uuids.count < MIN(limit, (NSUInteger)500)) {
                [state removeObjectForKey:@"pendingRevision"]; [state removeObjectForKey:@"afterUUID"];
            } else state[@"afterUUID"] = uuids.lastObject;
            if (![self writeJSONMetaLocked:state key:[kMetaRepoPublicationPrefix stringByAppendingString:repoId]]) { *rollback = YES; return NO; }
            return uuids.count > 0;
        }
        return NO;
    }];
}

- (nullable NSDictionary<NSString *, SeafFPDecoration *> *)publicationDecorationsLocked
{
    sqlite3_stmt *stmt = [self prepareLocked:@"SELECT item_id, favorite_rank, tag_data, last_used FROM decoration"];
    if (!stmt) return nil;
    NSMutableDictionary *decorations = [NSMutableDictionary dictionary];
    int rc;
    while ((rc = [self stepLocked:stmt]) == SQLITE_ROW) {
        SeafFPDecoration *dec = [self decorationFromStatement:stmt];
        decorations[dec.itemIdentifier] = dec;
    }
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? decorations : nil;
}

- (SeafFPWorkingSetPage *)workingSetPageAfterDepth:(NSUInteger)depth
                                             isDir:(BOOL)isDir
                                               seq:(long long)seq
                                              uuid:(NSString *)uuid
                                             limit:(NSUInteger)limit
{
    if (limit == 0) return nil;
    // Keyset paging in the scan order: no index serves it, but with the LIMIT
    // sqlite keeps only the best `limit + 1` rows while scanning, so a page
    // costs one pass over the table and little memory.
    static NSString * const position = @"length(path) - length(replace(path, '/', '')), is_dir = 0, seq, uuid";
    NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM identity WHERE deleted = 0 AND (%@) > (?, ?, ?, ?) ORDER BY %@ LIMIT ?",
                     kRecordColumns, position, position];
    __block SeafFPWorkingSetPage *page = nil;
    [self perform:^{
        if (![self execLocked:@"BEGIN DEFERRED"]) return;
        @try {
            NSString *sequence = [self metaValueLockedForKey:kMetaSeq];
            if (!sequence) return;
            NSDictionary *states = [self repositoryStatesLocked];
            if (!states) return;
            NSArray<SeafFPRecord *> *records = [self recordsLockedWithSQL:sql binder:^(sqlite3_stmt *stmt) {
                if (uuid) {
                    sqlite3_bind_int64(stmt, 1, (sqlite3_int64)depth);
                    sqlite3_bind_int(stmt, 2, isDir ? 0 : 1);
                    sqlite3_bind_int64(stmt, 3, seq);
                    SeafFPBindText(stmt, 4, uuid);
                } else {
                    sqlite3_bind_int64(stmt, 1, -1);   // rows always have depth >= 1
                    sqlite3_bind_int(stmt, 2, 0);
                    sqlite3_bind_int64(stmt, 3, 0);
                    SeafFPBindText(stmt, 4, @"");
                }
                sqlite3_bind_int64(stmt, 5, (sqlite3_int64)limit + 1);
            }];
            if (!records) return;
            BOOL more = records.count > limit;
            if (more) records = [records subarrayWithRange:NSMakeRange(0, limit)];
            // Ancestors in the same transaction, so the chains match the rows.
            NSString *byUUID = [NSString stringWithFormat:@"SELECT %s FROM identity WHERE uuid = ?", kRecordColumns];
            NSMutableDictionary<NSString *, SeafFPRecord *> *ancestors = [NSMutableDictionary dictionary];
            NSMutableSet<NSString *> *missing = [NSMutableSet set];
            for (SeafFPRecord *record in records) {
                NSString *parentUUID = record.parentUUID;
                // Stops at a uuid already looked up, which also ends a cycle.
                while (parentUUID.length > 0 && !ancestors[parentUUID] && ![missing containsObject:parentUUID]) {
                    NSArray<SeafFPRecord *> *found = [self recordsLockedWithSQL:byUUID binder:^(sqlite3_stmt *stmt) {
                        SeafFPBindText(stmt, 1, parentUUID);
                    }];
                    if (!found) return;
                    SeafFPRecord *parent = found.firstObject;
                    if (!parent) { [missing addObject:parentUUID]; break; }
                    ancestors[parentUUID] = parent;
                    parentUUID = parent.parentUUID;
                }
            }
            NSDictionary *decorations = [self publicationDecorationsLocked];
            if (!decorations) return;
            page = [SeafFPWorkingSetPage new];
            page.sequence = sequence.longLongValue;
            page.records = records;
            page.ancestors = ancestors;
            page.repositories = states;
            page.decorations = decorations;
            page.moreComing = more;
        } @finally {
            if (![self execLocked:@"COMMIT"]) { [self execLocked:@"ROLLBACK"]; page = nil; }
        }
    }];
    return page;
}

- (SeafFPPublicationBatch *)publicationBatchAfterSequence:(long long)sequence limit:(NSUInteger)limit
{
    __block SeafFPPublicationBatch *batch = nil;
    [self perform:^{
        if (![self execLocked:@"BEGIN DEFERRED"]) return;
        @try {
            long long cut = [self currentSeqLocked];
            NSDictionary *states = [self repositoryStatesLocked];
            if (!states) return;
            NSMutableArray<NSDictionary *> *events = [NSMutableArray array];
            NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM identity WHERE seq > ? AND seq <= ? ORDER BY seq LIMIT ?", kRecordColumns];
            sqlite3_stmt *stmt = [self prepareLocked:sql];
            if (!stmt) return;
            sqlite3_bind_int64(stmt, 1, sequence); sqlite3_bind_int64(stmt, 2, cut);
            sqlite3_bind_int64(stmt, 3, limit ? (sqlite3_int64)limit + 1 : -1);
            int rc;
            while ((rc = [self stepLocked:stmt]) == SQLITE_ROW) {
                SeafFPRecord *record = [self recordFromStatement:stmt];
                [events addObject:@{@"seq":@(record.seq), @"record":record}];
            }
            sqlite3_finalize(stmt);
            if (rc != SQLITE_DONE) return;
            for (NSDictionary *state in states.allValues) {
                long long seq = [state[@"eventSeq"] longLongValue];
                if (seq > sequence && seq <= cut) [events addObject:@{@"seq":@(seq), @"repo":state}];
            }
            stmt = [self prepareLocked:@"SELECT item_id, seq FROM working_set WHERE seq > ? AND seq <= ? ORDER BY seq LIMIT ?"];
            if (!stmt) return;
            sqlite3_bind_int64(stmt, 1, sequence); sqlite3_bind_int64(stmt, 2, cut);
            sqlite3_bind_int64(stmt, 3, limit ? (sqlite3_int64)limit + 1 : -1);
            while ((rc = [self stepLocked:stmt]) == SQLITE_ROW)
                [events addObject:@{@"seq":@(sqlite3_column_int64(stmt, 1)), @"decoration":SeafFPColumnText(stmt, 0)}];
            sqlite3_finalize(stmt);
            if (rc != SQLITE_DONE) return;
            [events sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"seq"] compare:b[@"seq"]]; }];
            BOOL more = limit > 0 && events.count > limit;
            if (more) {
                cut = [events[limit - 1][@"seq"] longLongValue];
                NSUInteger count = limit;
                while (count < events.count && [events[count][@"seq"] longLongValue] == cut) count++;
                more = count < events.count;
                events = [[events subarrayWithRange:NSMakeRange(0, count)] mutableCopy];
            }
            NSMutableArray *records = [NSMutableArray array], *repos = [NSMutableArray array], *decorationIDs = [NSMutableArray array];
            for (NSDictionary *event in events) {
                if (event[@"record"]) [records addObject:event[@"record"]];
                if (event[@"repo"]) [repos addObject:event[@"repo"]];
                if (event[@"decoration"]) [decorationIDs addObject:event[@"decoration"]];
            }
            NSDictionary *decorations = [self publicationDecorationsLocked];
            if (!decorations) return;
            batch = [SeafFPPublicationBatch new]; batch.sequence = cut; batch.moreComing = more;
            batch.records = records; batch.repositoryEvents = repos; batch.repositories = states;
            batch.decorationIdentifiers = decorationIDs; batch.decorations = decorations;
        } @finally {
            if (![self execLocked:@"COMMIT"]) { [self execLocked:@"ROLLBACK"]; batch = nil; }
        }
    }];
    return batch;
}

- (BOOL)requestWorkingSetSignalLocked
{
    NSMutableDictionary *signal = [[self jsonMetaLocked:kMetaSignal] mutableCopy];
    if (!signal) return NO;
    signal[@"requestedTicket"] = @([signal[@"requestedTicket"] longLongValue] + 1);
    return [self writeJSONMetaLocked:signal key:kMetaSignal];
}

- (BOOL)requestWorkingSetSignal
{
    return [self performCommittedWrite:^BOOL(BOOL *rollback) { BOOL ok = [self requestWorkingSetSignalLocked]; *rollback = !ok; return ok; } requestSignal:NO];
}

- (long long)pendingWorkingSetSignalTicket
{
    __block long long ticket = 0;
    [self perform:^{ NSDictionary *state = [self jsonMetaLocked:kMetaSignal];
        if ([state[@"requestedTicket"] longLongValue] > [state[@"completedTicket"] longLongValue]) ticket = [state[@"requestedTicket"] longLongValue];
    }];
    return ticket;
}

- (BOOL)completeWorkingSetSignalTicket:(long long)ticket
{
    return [self performCommittedWrite:^BOOL(BOOL *rollback) {
        NSMutableDictionary *state = [[self jsonMetaLocked:kMetaSignal] mutableCopy];
        if (!state || ticket <= 0 || ticket > [state[@"requestedTicket"] longLongValue]) return NO;
        state[@"completedTicket"] = @(MAX([state[@"completedTicket"] longLongValue], ticket));
        BOOL ok = [self writeJSONMetaLocked:state key:kMetaSignal]; *rollback = !ok; return ok;
    } requestSignal:NO];
}

#pragma mark - Identity

- (SeafFPRecord *)recordFromStatement:(sqlite3_stmt *)stmt
{
    SeafFPRecord *r = [SeafFPRecord new];
    r.uuid = SeafFPColumnText(stmt, 0);
    r.repoId = SeafFPColumnText(stmt, 1);
    r.path = SeafFPColumnText(stmt, 2);
    r.isDir = sqlite3_column_int(stmt, 3) != 0;
    r.name = SeafFPColumnText(stmt, 4);
    r.parentUUID = SeafFPColumnText(stmt, 5);
    r.oid = SeafFPColumnText(stmt, 6);
    r.mtime = sqlite3_column_int64(stmt, 7);
    r.size = sqlite3_column_int64(stmt, 8);
    r.deleted = sqlite3_column_int(stmt, 9) != 0;
    r.seq = sqlite3_column_int64(stmt, 10);
    r.createdSeq = sqlite3_column_int64(stmt, 11);
    r.tombReason = (SeafFPTombReason)sqlite3_column_int64(stmt, 12);
    r.tombTxn = sqlite3_column_int64(stmt, 13);
    r.confirmedPlacement = sqlite3_column_int(stmt, 14) != 0;
    r.hintRevivedFrom = sqlite3_column_int64(stmt, 15);
    r.hintRevivedAt = sqlite3_column_int64(stmt, 16);
    r.placementTime = sqlite3_column_int64(stmt, 17);
    return r;
}

- (nullable NSArray<SeafFPRecord *> *)recordsLockedWithSQL:(NSString *)sql binder:(void (^)(sqlite3_stmt *stmt))binder
{
    NSMutableArray *result = [NSMutableArray array];
    sqlite3_stmt *stmt = [self prepareLocked:sql];
    if (!stmt) return nil;
    if (binder) binder(stmt);
    int rc;
    while ((rc = [self stepLocked:stmt]) == SQLITE_ROW) {
        [result addObject:[self recordFromStatement:stmt]];
    }
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? result : nil;
}

- (SeafFPRecord *)recordLockedForUUID:(NSString *)uuid
{
    NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM identity WHERE uuid = ?", kRecordColumns];
    return [self recordsLockedWithSQL:sql binder:^(sqlite3_stmt *stmt) {
        SeafFPBindText(stmt, 1, uuid);
    }].firstObject;
}

- (SeafFPRecord *)recordLockedForRepo:(NSString *)repoId path:(NSString *)path
{
    NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM identity WHERE repo_id = ? AND path = ?", kRecordColumns];
    return [self recordsLockedWithSQL:sql binder:^(sqlite3_stmt *stmt) {
        SeafFPBindText(stmt, 1, repoId);
        SeafFPBindText(stmt, 2, path);
    }].firstObject;
}

- (SeafFPRecord *)recordForUUID:(NSString *)uuid
{
    return [self recordForUUID:uuid failed:NULL];
}

- (SeafFPRecord *)recordForUUID:(NSString *)uuid failed:(BOOL *)failed
{
    NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM identity WHERE uuid = ?", kRecordColumns];
    __block NSArray<SeafFPRecord *> *found = nil;
    [self perform:^{
        found = [self recordsLockedWithSQL:sql binder:^(sqlite3_stmt *stmt) { SeafFPBindText(stmt, 1, uuid); }];
    }];
    if (failed) *failed = (found == nil);
    return found.firstObject;
}

- (SeafFPRecord *)recordForRepo:(NSString *)repoId path:(NSString *)path includeDeleted:(BOOL)includeDeleted
{
    NSString *normalized = [SeafFPIdentifier normalizedPath:path];
    __block SeafFPRecord *record = nil;
    [self perform:^{ record = [self recordLockedForRepo:repoId path:normalized]; }];
    if (record.deleted && !includeDeleted) {
        return nil;
    }
    return record;
}

- (BOOL)writeRecordLocked:(SeafFPRecord *)r insert:(BOOL)insert
{
    NSString *sql = insert
        ? @"INSERT INTO identity(uuid, repo_id, path, is_dir, name, parent_uuid, oid, mtime, size, deleted, seq, tomb_reason, tomb_txn, confirmed_placement, hint_revived_from, hint_revived_at, placement_time, created_seq) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
        : @"UPDATE identity SET repo_id=?, path=?, is_dir=?, name=?, parent_uuid=?, oid=?, mtime=?, size=?, deleted=?, seq=?, tomb_reason=?, tomb_txn=?, confirmed_placement=?, hint_revived_from=?, hint_revived_at=?, placement_time=? WHERE uuid=?";
    if (!r.deleted) { r.tombReason = SeafFPTombReasonNone; r.tombTxn = 0; }
    if (insert && r.createdSeq <= 0) r.createdSeq = r.seq;
    sqlite3_stmt *stmt = [self prepareLocked:sql];
    if (!stmt) return NO;
    int i = 1;
    if (insert) SeafFPBindText(stmt, i++, r.uuid);
    SeafFPBindText(stmt, i++, r.repoId);
    SeafFPBindText(stmt, i++, r.path);
    sqlite3_bind_int(stmt, i++, r.isDir ? 1 : 0);
    SeafFPBindText(stmt, i++, r.name);
    SeafFPBindText(stmt, i++, r.parentUUID);
    SeafFPBindText(stmt, i++, r.oid);
    sqlite3_bind_int64(stmt, i++, r.mtime);
    sqlite3_bind_int64(stmt, i++, r.size);
    sqlite3_bind_int(stmt, i++, r.deleted ? 1 : 0);
    sqlite3_bind_int64(stmt, i++, r.seq);
    sqlite3_bind_int64(stmt, i++, r.tombReason);
    sqlite3_bind_int64(stmt, i++, r.tombTxn);
    sqlite3_bind_int(stmt, i++, r.confirmedPlacement);
    sqlite3_bind_int64(stmt, i++, r.hintRevivedFrom);
    sqlite3_bind_int64(stmt, i++, r.hintRevivedFrom > 0 ? r.hintRevivedAt : 0);
    sqlite3_bind_int64(stmt, i++, r.confirmedPlacement ? r.placementTime : 0);
    if (insert) sqlite3_bind_int64(stmt, i++, r.createdSeq);
    if (!insert) SeafFPBindText(stmt, i++, r.uuid);
    int rc = [self stepLocked:stmt];
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        Warning("sqlite write failed (%d) %s for %@", rc, sqlite3_errmsg(_db), r);
        return NO;
    }
    return YES;
}

static BOOL SeafFPStringsEqual(NSString *a, NSString *b)
{
    return (a == nil && b == nil) || (a != nil && [a isEqualToString:b ?: @""]);
}

- (SeafFPRecord *)upsertRecordForRepo:(NSString *)repoId
                                 path:(NSString *)path
                                isDir:(BOOL)isDir
                           parentUUID:(NSString *)parentUUID
                                  oid:(NSString *)oid
                                mtime:(long long)mtime
                                 size:(long long)size
{
    NSString *normalized = [SeafFPIdentifier normalizedPath:path];
    __block SeafFPRecord *result = nil;
    [self perform:^{
        [self beginRetryingLocked];
        if (!self->_transactionOpen) { [self leaveTransactionLocked]; return; }
        result = [self upsertRecordLockedForRepo:repoId path:normalized isDir:isDir parentUUID:parentUUID
                                             oid:oid mtime:mtime size:size changed:NULL];
        if (![self commitLocked]) result = nil;
    }];
    return result;
}

- (long long)prepareFileCreationInRepo:(NSString *)repoId path:(NSString *)path requestStartSeq:(long long)start
{
    if (start < 0) return -1;
    NSString *normalized = [SeafFPIdentifier normalizedPath:path];
    __block long long boundary = -1;
    BOOL committed = [self performBatch:^{
        if ([self destinationReservedLockedForRepo:repoId path:normalized exceptUUID:nil]) return;
        SeafFPRecord *old = [self recordLockedForRepo:repoId path:normalized];
        if (old.seq > start) return;
        if (old) {
            NSDictionary *move = [self jsonMetaLocked:SeafFPMoveRecoveryKey(old.uuid)];
            if (!move) return;
            // A pending move still needs this identity even if its name is free.
            SeafFPTombReason reason = move.count ? SeafFPTombReasonAbsent : SeafFPTombReasonReplaced;
            if (![self detachRecordLocked:old reason:reason]) {
                self->_transactionFailed = YES;
                return;
            }
            [self setDirStampLocked:[self currentSeqLocked] forRepo:repoId parentUUID:old.parentUUID];
        }
        boundary = [self currentSeqLocked];
    }];
    return committed ? boundary : -1;
}

- (SeafFPRecord *)recordCreatedFileInRepo:(NSString *)repoId
                                     path:(NSString *)path
                               parentUUID:(NSString *)parentUUID
                                      oid:(NSString *)oid
                                    mtime:(long long)mtime
                                     size:(long long)size
                          requestStartSeq:(long long)start
                               serverTime:(long long)serverTime
{
    if (start < 0 || oid.length == 0) return nil;
    NSString *normalized = [SeafFPIdentifier normalizedPath:path];
    __block SeafFPRecord *result = nil;
    BOOL committed = [self performBatch:^{
        NSString *directory = normalized.stringByDeletingLastPathComponent;
        SeafFPRecord *parent = parentUUID ? [self recordLockedForUUID:parentUUID] : nil;
        if (parentUUID ? (!parent.isDir || parent.deleted || ![parent.repoId isEqual:repoId] || ![parent.path isEqual:directory])
                       : ![directory isEqual:@"/"]) return;
        SeafFPRecord *occupant = [self recordLockedForRepo:repoId path:normalized];
        if (occupant && occupant.seq > start
            && (occupant.tombReason == SeafFPTombReasonLocal || occupant.tombReason == SeafFPTombReasonReplaced)) return;
        if (occupant && !occupant.deleted && occupant.seq > start) {
            // A browse may have discovered this upload while it was finishing.
            if (occupant.confirmedPlacement || occupant.createdSeq <= start || occupant.isDir || ![oid isEqual:occupant.oid]) return;
        } else if (occupant) {
            // Preflight showed the path free. The old row can still exist in
            // the index while the activity that removed it is in flight.
            if (occupant.isDir && ![self markDeletedLockedUUID:occupant.uuid reason:SeafFPTombReasonReplaced]) return;
            [self evictOccupantLockedOfRepo:repoId path:normalized exceptUUID:nil];
        }
        result = [self upsertRecordLockedForRepo:repoId path:normalized isDir:NO parentUUID:parentUUID
                                             oid:oid mtime:mtime size:size changed:NULL];
        if (result) {
            result.confirmedPlacement = YES;
            result.placementTime = serverTime;
            if ([self writeRecordLocked:result insert:NO]) return;
        }
        self->_transactionFailed = YES;
    }];
    return committed ? result : nil;
}

/// Body of upsertRecordForRepo:; `normalized` must already be normalized.
/// changed (optional): set to YES when the row was inserted or rewritten.
- (SeafFPRecord *)upsertRecordLockedForRepo:(NSString *)repoId
                                       path:(NSString *)normalized
                                      isDir:(BOOL)isDir
                                 parentUUID:(NSString *)parentUUID
                                        oid:(NSString *)oid
                                      mtime:(long long)mtime
                                       size:(long long)size
                                    changed:(BOOL *)outChanged
{
    NSString *name = normalized.lastPathComponent;
    SeafFPRecord *existing = [self recordLockedForRepo:repoId path:normalized];
    if (existing) {
        BOOL typeChanged = (existing.isDir != isDir);
        NSString *newOid = typeChanged ? (isDir ? nil : oid) : (oid ?: existing.oid);
        long long newMtime = mtime > 0 ? mtime : existing.mtime;
        long long newSize = isDir ? 0 : (size >= 0 ? size : (typeChanged ? 0 : existing.size));
        BOOL changed = existing.deleted
            || typeChanged
            || !SeafFPStringsEqual(existing.name, name)
            || !SeafFPStringsEqual(existing.parentUUID, parentUUID)
            || !SeafFPStringsEqual(existing.oid, newOid)
            || existing.mtime != newMtime
            || existing.size != newSize;
        if (changed) {
            if (existing.deleted || typeChanged || !SeafFPStringsEqual(existing.oid, newOid)) {
                existing.hintRevivedFrom = 0;
            }
            if (existing.deleted || typeChanged) {
                existing.confirmedPlacement = !isDir;
                existing.placementTime = 0;
            }
            if (existing.isDir && !isDir) {
                for (SeafFPRecord *sub in [self subtreeRecordsLockedOf:existing]) {
                    if (sub.deleted) continue;
                    sub.deleted = YES;
                    sub.tombReason = SeafFPTombReasonReplaced;
                    sub.tombTxn = _transactionStartSeq;
                    sub.seq = [self nextSeqLocked];
                    [self writeRecordLocked:sub insert:NO];
                }
            }
            existing.deleted = NO;
            existing.isDir = isDir;
            existing.name = name;
            existing.parentUUID = parentUUID;
            existing.oid = newOid;
            existing.mtime = newMtime;
            existing.size = newSize;
            existing.seq = [self nextSeqLocked];
            if (![self writeRecordLocked:existing insert:NO]) {
                return nil;
            }
            if (outChanged) *outChanged = YES;
        }
        return existing;
    }
    SeafFPRecord *r = [SeafFPRecord new];
    r.uuid = [SeafFPIdentifier newUUID];
    r.repoId = repoId;
    r.path = normalized;
    r.name = name;
    r.isDir = isDir;
    r.parentUUID = parentUUID;
    r.oid = oid;
    r.mtime = mtime > 0 ? mtime : 0;
    r.size = size >= 0 ? size : 0;
    r.deleted = NO;
    if (!isDir) {
        r.confirmedPlacement = [self metaValueLockedForKey:[self departedPathKeyForRepo:repoId path:normalized]] != nil;
    }
    r.seq = [self nextSeqLocked];
    if (![self writeRecordLocked:r insert:YES]) {
        return nil;
    }
    if (outChanged) *outChanged = YES;
    return r;
}

- (SeafFPRecord *)ensureRecordChainForRepo:(NSString *)repoId path:(NSString *)path isDir:(BOOL)isDir
{
    NSString *normalized = [SeafFPIdentifier normalizedPath:path];
    if ([normalized isEqualToString:@"/"]) {
        return nil;
    }
    NSString *parentPath = normalized.stringByDeletingLastPathComponent;
    NSString *parentUUID = nil;
    if (parentPath.length > 0 && ![parentPath isEqualToString:@"/"]) {
        parentUUID = [self ensureRecordChainForRepo:repoId path:parentPath isDir:YES].uuid;
    }
    return [self upsertRecordForRepo:repoId path:normalized isDir:isDir parentUUID:parentUUID oid:nil mtime:0 size:-1];
}

- (NSArray<SeafFPRecord *> *)childRecordsOfRepo:(NSString *)repoId parentUUID:(NSString *)parentUUID
{
    NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM identity WHERE repo_id = ? AND deleted = 0 AND parent_uuid IS ?", kRecordColumns];
    __block NSArray *result = @[];
    [self perform:^{
        result = [self recordsLockedWithSQL:sql binder:^(sqlite3_stmt *stmt) {
            SeafFPBindText(stmt, 1, repoId);
            SeafFPBindText(stmt, 2, parentUUID);
        }];
    }];
    return result ?: @[];
}

- (NSArray<SeafFPRecord *> *)subtreeRecordsLockedOf:(SeafFPRecord *)record
{
    // length() and substr() both count characters, unlike NSString.length
    // (UTF-16 units), so the prefix is bound twice instead of passing a length.
    NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM identity WHERE repo_id = ?1 AND substr(path, 1, length(?2)) = ?2", kRecordColumns];
    NSString *prefix = [record.path isEqualToString:@"/"] ? @"/" : [record.path stringByAppendingString:@"/"];
    return [self recordsLockedWithSQL:sql binder:^(sqlite3_stmt *stmt) {
        SeafFPBindText(stmt, 1, record.repoId);
        SeafFPBindText(stmt, 2, prefix);
    }] ?: @[];
}

- (NSArray<SeafFPRecord *> *)subtreeRecordsOfUUID:(NSString *)uuid
{
    __block NSArray<SeafFPRecord *> *result = @[];
    [self perform:^{
        SeafFPRecord *record = [self recordLockedForUUID:uuid];
        if (!record) return;
        NSMutableArray *all = [NSMutableArray arrayWithObject:record];
        if (record.isDir) {
            [all addObjectsFromArray:[self subtreeRecordsLockedOf:record]];
        }
        result = all;
    }];
    return result;
}

/// Tombstones the row and, for a directory, every live row below it.
- (BOOL)markDeletedLockedUUID:(NSString *)uuid reason:(SeafFPTombReason)reason
{
    SeafFPRecord *record = [self recordLockedForUUID:uuid];
    if (!record) return [self transactionHealthyLocked];
    NSMutableArray<SeafFPRecord *> *targets = [NSMutableArray arrayWithObject:record];
    if (record.isDir) {
        [targets addObjectsFromArray:[self subtreeRecordsLockedOf:record]];
    }
    for (SeafFPRecord *r in targets) {
        if (r.deleted) continue;
        r.deleted = YES;
        r.tombReason = reason;
        r.tombTxn = _transactionStartSeq;
        r.seq = [self nextSeqLocked];
        if (r.seq <= 0 || ![self writeRecordLocked:r insert:NO]) return NO;
    }
    return [self transactionHealthyLocked];
}

- (void)markDeletedUUID:(NSString *)uuid
{
    [self markDeletedUUIDs:@[uuid]];
}

- (void)markDeletedUUIDs:(NSArray<NSString *> *)uuids
{
    if (uuids.count == 0) return;
    [self perform:^{
        [self beginRetryingLocked];
        if (!self->_transactionOpen) { [self leaveTransactionLocked]; return; }
        for (NSString *uuid in uuids) {
            // The deletion supersedes any move of the item that is still being
            // reconciled: its journal would otherwise reserve the destination
            // name for good.
            SeafFPRecord *record = [self recordLockedForUUID:uuid];
            NSArray<SeafFPRecord *> *subtree = record.isDir ? [self subtreeRecordsLockedOf:record] : @[];
            if (![self markDeletedLockedUUID:uuid reason:SeafFPTombReasonLocal]
                || ![self clearMoveJournalLockedForUUID:uuid]) { self->_transactionFailed = YES; break; }
            for (SeafFPRecord *child in subtree) {
                if (![self clearMoveJournalLockedForUUID:child.uuid]) { self->_transactionFailed = YES; break; }
            }
        }
        [self commitLocked];
    }];
}

- (NSArray<SeafFPRecord *> *)recordsChangedSinceSeq:(long long)seq
{
    return [self recordsChangedSinceSeq:seq limit:0];
}

- (NSArray<SeafFPRecord *> *)recordsChangedSinceSeq:(long long)seq limit:(NSInteger)limit
{
    NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM identity WHERE seq > ? ORDER BY seq LIMIT ?", kRecordColumns];
    __block NSArray *result = @[];
    [self perform:^{
        result = [self recordsLockedWithSQL:sql binder:^(sqlite3_stmt *stmt) {
            sqlite3_bind_int64(stmt, 1, seq);
            sqlite3_bind_int64(stmt, 2, limit > 0 ? limit : -1);
        }];
    }];
    return result ?: @[];
}

- (NSArray<SeafFPRecord *> *)liveRecordsAfterUUID:(NSString *)uuid limit:(NSInteger)limit
{
    NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM identity WHERE deleted = 0 AND uuid > ? ORDER BY uuid LIMIT ?", kRecordColumns];
    __block NSArray *result = nil;
    [self perform:^{
        result = [self recordsLockedWithSQL:sql binder:^(sqlite3_stmt *stmt) {
            SeafFPBindText(stmt, 1, uuid ?: @"");
            sqlite3_bind_int64(stmt, 2, limit > 0 ? limit : -1);
        }];
    }];
    return result;
}

- (SeafFPRecord *)moveRecordUUID:(NSString *)uuid toRepo:(NSString *)repoId path:(NSString *)path parentUUID:(NSString *)parentUUID
{
    NSString *newPath = [SeafFPIdentifier normalizedPath:path];
    __block SeafFPRecord *result = nil;
    // The row and its subtree are read inside the transaction: the other
    // process may be moving or tombstoning the same rows.
    BOOL committed = [self performBatch:^{
        SeafFPRecord *record = [self recordLockedForUUID:uuid];
        if (!record) return;
        SeafFPRecord *occupant = [self recordLockedForRepo:repoId path:newPath];
        BOOL merge = record.isDir && occupant.isDir && record.oid.length > 0 && [record.oid isEqualToString:occupant.oid];
        record.confirmedPlacement = YES;
        record.placementTime = 0;
        record.hintRevivedFrom = 0;
        result = [self moveRecordLocked:record toRepo:repoId path:newPath parentUUID:parentUUID
                        mergeDestination:merge detachedFromPath:nil];
        if (!result) self->_transactionFailed = YES;
    }];
    return committed ? result : nil;
}

/// The caller has verified any live destination that it wants to merge.
- (nullable SeafFPRecord *)moveRecordLocked:(SeafFPRecord *)record
                                    toRepo:(NSString *)repoId
                                      path:(NSString *)path
                                parentUUID:(NSString *)parentUUID
                          mergeDestination:(BOOL)mergeDestination
                           detachedFromPath:(NSString *)detachedFromPath
{
    SeafFPRecord *occupant = [self recordLockedForRepo:repoId path:path];
    NSArray<SeafFPRecord *> *children = @[];
    if (occupant && !occupant.deleted && ![occupant.uuid isEqualToString:record.uuid]) {
        if (mergeDestination) {
            if (occupant.isDir) children = [self subtreeRecordsLockedOf:occupant];
            if (![self mergeDecorationsLockedFrom:occupant into:record]) return nil;
        } else if (occupant.isDir && ![self markDeletedLockedUUID:occupant.uuid reason:SeafFPTombReasonReplaced]) {
            return nil;
        }
    }
    SeafFPRecord *moved = [self relocateRecordAndChildrenLocked:record toRepo:repoId path:path parentUUID:parentUUID
                                             detachedFromPath:detachedFromPath];
    return moved && [self adoptProvisionalChildrenLocked:children intoRepo:repoId] ? moved : nil;
}

/// `newPath` must already be normalized. A
/// tombstoned record (and the part of its subtree tombstoned with it) comes
/// back to life. nil when the record is unknown or a write failed.
- (SeafFPRecord *)relocateRecordAndChildrenLocked:(SeafFPRecord *)record
                                          toRepo:(NSString *)repoId
                                            path:(NSString *)newPath
                                      parentUUID:(NSString *)parentUUID
                                 detachedFromPath:(NSString *)detachedFromPath
{
    BOOL wasTombstoned = record.deleted;
    long long tombstoneSeq = record.seq;
    NSString *oldPath = record.path;
    NSString *oldRepo = record.repoId;
    NSString *oldParentUUID = record.parentUUID;
    // Whatever previously lived at the destination is stale now.
    [self evictOccupantLockedOfRepo:repoId path:newPath exceptUUID:record.uuid];
    NSArray<SeafFPRecord *> *children = record.isDir ? [self subtreeRecordsLockedOf:record] : @[];
    record.deleted = NO;
    record.repoId = repoId;
    record.path = newPath;
    record.name = newPath.lastPathComponent;
    record.parentUUID = parentUUID;
    record.seq = [self nextSeqLocked];
    if (record.seq <= 0 || ![self writeRecordLocked:record insert:NO]) return nil;
    if (![oldRepo isEqualToString:repoId] || ![oldPath isEqualToString:newPath]) {
        // The entry left (or was renamed inside) its directory: a listing of
        // that directory requested before now still shows the old name.
        [self setDirStampLocked:record.seq forRepo:oldRepo parentUUID:oldParentUUID];
        // Keep a path barrier as well as the UUID-based directory stamp. A
        // cached listing has no request seq and the old path no longer has a
        // row, so neither the stamp nor a tombstone can otherwise reject it.
        // A detached row (`#moved-`) never was a listed path: no barrier.
        if (!wasTombstoned || [oldPath rangeOfString:@"#moved-"].location == NSNotFound) {
            [self setMetaValueLocked:[NSString stringWithFormat:@"%lld", record.seq]
                              forKey:[NSString stringWithFormat:@"%@%@:%@", kMetaDepartedPathPrefix, oldRepo, oldPath]];
        }
    }
    // Detached rows have temporary paths. Journals still use the original
    // path, which may now also belong to an unrelated replacement subtree.
    NSMutableSet<NSString *> *movedUUIDs = detachedFromPath ? [NSMutableSet setWithObject:record.uuid] : nil;
    NSString *oldPrefix = [oldPath stringByAppendingString:@"/"];
    for (SeafFPRecord *child in children) {
        if (![child.repoId isEqualToString:oldRepo] || ![child.path hasPrefix:oldPrefix]) continue;
        NSString *childPath = [newPath stringByAppendingString:[child.path substringFromIndex:oldPath.length]];
        [self evictOccupantLockedOfRepo:repoId path:childPath exceptUUID:child.uuid];
        if (wasTombstoned && child.deleted && child.seq >= tombstoneSeq) {
            child.deleted = NO;
        }
        child.repoId = repoId;
        child.path = childPath;
        child.confirmedPlacement = record.confirmedPlacement;
        child.placementTime = record.placementTime;
        child.hintRevivedFrom = 0;
        child.seq = [self nextSeqLocked];
        if (child.seq <= 0 || ![self writeRecordLocked:child insert:NO]) return nil;
        [movedUUIDs addObject:child.uuid];
    }
    if (record.isDir && ![self relocateMoveJournalsLockedFromRepo:oldRepo path:(detachedFromPath ?: oldPath)
        toRepo:repoId path:newPath excludingUUID:record.uuid subtreeUUIDs:movedUUIDs]) return nil;
    return [self transactionHealthyLocked] ? record : nil;
}

/// A stable parent UUID can move while a child's server receipt is pending.
/// Migrate both sides of those journals and their reservations in this same
/// transaction. The directory's own journal is settled by its caller.
- (BOOL)relocateMoveJournalsLockedFromRepo:(NSString *)oldRepo path:(NSString *)oldPath
                                   toRepo:(NSString *)repoId path:(NSString *)newPath excludingUUID:(NSString *)ownUUID
                             subtreeUUIDs:(NSSet<NSString *> *)subtreeUUIDs
{
    sqlite3_stmt *stmt = [self prepareLocked:@"SELECT key FROM meta WHERE key GLOB 'fp_confirmed_move:*'"];
    if (!stmt) return NO;
    NSMutableArray<NSString *> *keys = [NSMutableArray array]; int rc;
    while ((rc = [self stepLocked:stmt]) == SQLITE_ROW) [keys addObject:SeafFPColumnText(stmt, 0)];
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) return NO;
    NSString *prefix = [oldPath stringByAppendingString:@"/"];
    for (NSString *key in keys) {
        NSString *uuid = [key substringFromIndex:@"fp_confirmed_move:".length];
        if ([uuid isEqual:ownUUID]) continue;
        NSDictionary *before = [self jsonMetaLocked:key];
        if (!before) return NO;
        if (!before.count) continue;
        NSMutableDictionary *after = [before mutableCopy];
        for (NSArray *fields in @[@[@"sourceRepo", @"sourcePath"], @[@"repo", @"dir"]]) {
            if (subtreeUUIDs) {
                NSString *endpointUUID = [fields[0] isEqual:@"sourceRepo"] ? uuid : before[@"parent"];
                if (![subtreeUUIDs containsObject:endpointUUID ?: @""]) continue;
            }
            NSString *path = before[fields[1]];
            if ([before[fields[0]] isEqual:oldRepo] && ([path isEqual:oldPath] || [path hasPrefix:prefix])) {
                after[fields[0]] = repoId;
                after[fields[1]] = [newPath stringByAppendingString:[path substringFromIndex:oldPath.length]];
            }
        }
        if ([after isEqual:before]) continue;
        NSString *oldKey = [self moveDestinationKeyForRecovery:before], *newKey = [self moveDestinationKeyForRecovery:after];
        if (![oldKey isEqual:newKey]) {
            NSString *destination = [after[@"dir"] stringByAppendingPathComponent:after[@"name"]];
            if ([self destinationReservedLockedForRepo:after[@"repo"] path:destination exceptUUID:uuid]) return NO;
            NSString *owner = [self metaValueLockedForKey:oldKey];
            if ([owner isEqual:uuid] && ![self setMetaValueLocked:nil forKey:oldKey]) return NO;
            if (![SeafFPStore moveJournalExpired:after now:(long long)[NSDate date].timeIntervalSince1970]
                && ![self setMetaValueLocked:uuid forKey:newKey]) return NO;
        }
        if (![self writeJSONMetaLocked:after key:key]) return NO;
    }
    return [self transactionHealthyLocked];
}

/// Frees (repoId, path) for another record: a live or tombstoned row that
/// still sits there is tombstoned under a unique path so UNIQUE(repo_id, path)
/// cannot reject the move.
- (BOOL)detachRecordLocked:(SeafFPRecord *)record reason:(SeafFPTombReason)reason
{
    NSString *oldPath = record.path;
    if (![self markDeletedLockedUUID:record.uuid reason:reason]) return NO;
    SeafFPRecord *root = [self recordLockedForUUID:record.uuid];
    if (!root) return NO;
    NSArray<SeafFPRecord *> *children = root.isDir ? [self subtreeRecordsLockedOf:root] : @[];
    long long tombstoneSeq = root.seq;
    long long suffix = [self nextSeqLocked];
    if (suffix <= 0) return NO;
    root.path = [NSString stringWithFormat:@"%@#moved-%lld", oldPath, suffix];
    // The suffix is kept as the row's seq: a counter reseeded from the rows
    // can then never hand it out again for the same path. Children that went
    // with this tombstone move above it, so subtree recovery still finds them.
    root.seq = suffix;
    if (![self writeRecordLocked:root insert:NO]) return NO;
    for (SeafFPRecord *child in children) {
        child.path = [root.path stringByAppendingString:[child.path substringFromIndex:oldPath.length]];
        if (child.seq >= tombstoneSeq) {
            child.seq = [self nextSeqLocked];
            if (child.seq <= 0) return NO;
        }
        if (![self writeRecordLocked:child insert:NO]) return NO;
    }
    return [self transactionHealthyLocked];
}

static BOOL SeafFPRecordDetachedFromPath(SeafFPRecord *record, NSString *path)
{
    return record.deleted && record.tombReason == SeafFPTombReasonAbsent
        && [record.path hasPrefix:[path stringByAppendingString:@"#moved-"]];
}

- (void)evictOccupantLockedOfRepo:(NSString *)repoId path:(NSString *)path exceptUUID:(NSString *)uuid
{
    SeafFPRecord *occupant = [self recordLockedForRepo:repoId path:path];
    if (!occupant || [occupant.uuid isEqualToString:uuid]) return;
    if (!occupant.deleted) {
        occupant.tombReason = SeafFPTombReasonReplaced;
        occupant.tombTxn = _transactionStartSeq;
    }
    occupant.deleted = YES;
    occupant.path = [NSString stringWithFormat:@"%@#moved-%lld", path, [self nextSeqLocked]];
    occupant.seq = [self nextSeqLocked];
    [self writeRecordLocked:occupant insert:NO];
}

#pragma mark - Container

- (NSString *)anchorForContainer:(NSString *)containerIdentifier
{
    __block NSString *anchor = nil;
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:@"SELECT anchor FROM container WHERE container_id = ?"];
        if (!stmt) return;
        SeafFPBindText(stmt, 1, containerIdentifier);
        if ([self stepLocked:stmt] == SQLITE_ROW) anchor = SeafFPColumnText(stmt, 0);
        sqlite3_finalize(stmt);
    }];
    return anchor;
}

- (NSArray<NSString *> *)snapshotForContainer:(NSString *)containerIdentifier
{
    __block NSString *json = nil;
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:@"SELECT snapshot FROM container WHERE container_id = ?"];
        if (!stmt) return;
        SeafFPBindText(stmt, 1, containerIdentifier);
        if ([self stepLocked:stmt] == SQLITE_ROW) json = SeafFPColumnText(stmt, 0);
        sqlite3_finalize(stmt);
    }];
    if (json.length == 0) return @[];
    id parsed = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    return [parsed isKindOfClass:[NSArray class]] ? parsed : @[];
}

- (NSDate *)enumeratedAtForContainer:(NSString *)containerIdentifier
{
    __block double ts = 0;
    __block BOOL found = NO;
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:@"SELECT enumerated_at FROM container WHERE container_id = ?"];
        if (!stmt) return;
        SeafFPBindText(stmt, 1, containerIdentifier);
        if ([self stepLocked:stmt] == SQLITE_ROW) {
            found = YES;
            ts = sqlite3_column_double(stmt, 0);
        }
        sqlite3_finalize(stmt);
    }];
    return found ? [NSDate dateWithTimeIntervalSince1970:ts] : nil;
}

- (NSDictionary<NSString *, NSDate *> *)enumeratedAtByContainer
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:@"SELECT container_id, enumerated_at FROM container"];
        if (!stmt) return;
        while ([self stepLocked:stmt] == SQLITE_ROW) {
            NSString *identifier = SeafFPColumnText(stmt, 0);
            if (identifier) result[identifier] = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(stmt, 1)];
        }
        sqlite3_finalize(stmt);
    }];
    return result;
}

- (void)setAnchor:(NSString *)anchor snapshot:(NSArray<NSString *> *)snapshot forContainer:(NSString *)containerIdentifier
{
    NSString *json = nil;
    if (snapshot) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
        json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    }
    double now = [[NSDate date] timeIntervalSince1970];
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:@"INSERT OR REPLACE INTO container(container_id, anchor, snapshot, enumerated_at) VALUES(?,?,?,?)"];
        if (!stmt) return;
        SeafFPBindText(stmt, 1, containerIdentifier);
        SeafFPBindText(stmt, 2, anchor);
        SeafFPBindText(stmt, 3, json);
        sqlite3_bind_double(stmt, 4, now);
        [self stepLocked:stmt];
        sqlite3_finalize(stmt);
    }];
}

#pragma mark - Decoration

- (SeafFPDecoration *)decorationFromStatement:(sqlite3_stmt *)stmt
{
    SeafFPDecoration *d = [SeafFPDecoration new];
    d.itemIdentifier = SeafFPColumnText(stmt, 0);
    if (sqlite3_column_type(stmt, 1) != SQLITE_NULL) {
        d.favoriteRank = @(sqlite3_column_int64(stmt, 1));
    }
    if (sqlite3_column_type(stmt, 2) != SQLITE_NULL) {
        const void *bytes = sqlite3_column_blob(stmt, 2);
        int length = sqlite3_column_bytes(stmt, 2);
        if (bytes && length > 0) {
            d.tagData = [NSData dataWithBytes:bytes length:length];
        }
    }
    if (sqlite3_column_type(stmt, 3) != SQLITE_NULL) {
        d.lastUsedDate = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(stmt, 3)];
    }
    return d;
}

- (SeafFPDecoration *)decorationForItem:(NSString *)itemIdentifier
{
    __block SeafFPDecoration *result = nil;
    [self perform:^{ result = [self decorationLockedForItem:itemIdentifier]; }];
    return result;
}

- (SeafFPDecoration *)decorationLockedForItem:(NSString *)itemIdentifier
{
    SeafFPDecoration *result = nil;
    sqlite3_stmt *stmt = [self prepareLocked:@"SELECT item_id, favorite_rank, tag_data, last_used FROM decoration WHERE item_id = ?"];
    if (!stmt) return nil;
    SeafFPBindText(stmt, 1, itemIdentifier);
    if ([self stepLocked:stmt] == SQLITE_ROW) result = [self decorationFromStatement:stmt];
    sqlite3_finalize(stmt);
    return result;
}

- (NSArray<SeafFPDecoration *> *)allDecorations
{
    NSMutableArray *result = [NSMutableArray array];
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:@"SELECT item_id, favorite_rank, tag_data, last_used FROM decoration"];
        if (!stmt) return;
        while ([self stepLocked:stmt] == SQLITE_ROW) {
            [result addObject:[self decorationFromStatement:stmt]];
        }
        sqlite3_finalize(stmt);
    }];
    return result;
}

- (void)setDecoration:(SeafFPDecoration *)decoration
{
    if (decoration.isEmpty) {
        [self removeDecorationForItem:decoration.itemIdentifier];
        return;
    }
    [self perform:^{ [self setDecorationLocked:decoration]; }];
}

/// Writes a non-empty decoration row (INSERT OR REPLACE of the whole row).
- (BOOL)setDecorationLocked:(SeafFPDecoration *)decoration
{
    sqlite3_stmt *stmt = [self prepareLocked:@"INSERT OR REPLACE INTO decoration(item_id, favorite_rank, tag_data, last_used) VALUES(?,?,?,?)"];
    if (!stmt) return NO;
    SeafFPBindText(stmt, 1, decoration.itemIdentifier);
    if (decoration.favoriteRank) {
        sqlite3_bind_int64(stmt, 2, decoration.favoriteRank.longLongValue);
    } else {
        sqlite3_bind_null(stmt, 2);
    }
    if (decoration.tagData.length > 0) {
        sqlite3_bind_blob(stmt, 3, decoration.tagData.bytes, (int)decoration.tagData.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    if (decoration.lastUsedDate) {
        sqlite3_bind_double(stmt, 4, decoration.lastUsedDate.timeIntervalSince1970);
    } else {
        sqlite3_bind_null(stmt, 4);
    }
    int rc = [self stepLocked:stmt];
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE;
}

- (void)removeDecorationForItem:(NSString *)itemIdentifier
{
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:@"DELETE FROM decoration WHERE item_id = ?"];
        if (!stmt) return;
        SeafFPBindText(stmt, 1, itemIdentifier);
        [self stepLocked:stmt];
        sqlite3_finalize(stmt);
    }];
}

#pragma mark - Working set

- (NSArray<NSString *> *)workingSetItemIdentifiers
{
    NSMutableArray *result = [NSMutableArray array];
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:@"SELECT item_id FROM working_set ORDER BY seq"];
        if (!stmt) return;
        while ([self stepLocked:stmt] == SQLITE_ROW) {
            NSString *identifier = SeafFPColumnText(stmt, 0);
            if (identifier) [result addObject:identifier];
        }
        sqlite3_finalize(stmt);
    }];
    return result;
}

- (SeafFPWorkingSetReason)workingSetReasonLockedForItem:(NSString *)itemIdentifier
{
    SeafFPWorkingSetReason reason = 0;
    sqlite3_stmt *stmt = [self prepareLocked:@"SELECT reason FROM working_set WHERE item_id = ?"];
    if (!stmt) return 0;
    SeafFPBindText(stmt, 1, itemIdentifier);
    if ([self stepLocked:stmt] == SQLITE_ROW) reason = sqlite3_column_int64(stmt, 0);
    sqlite3_finalize(stmt);
    return reason;
}

- (SeafFPWorkingSetReason)workingSetReasonForItem:(NSString *)itemIdentifier
{
    __block SeafFPWorkingSetReason reason = 0;
    [self perform:^{ reason = [self workingSetReasonLockedForItem:itemIdentifier]; }];
    return reason;
}

- (void)writeWorkingSetLockedItem:(NSString *)itemIdentifier reason:(SeafFPWorkingSetReason)reason seq:(long long)seq
{
    sqlite3_stmt *stmt;
    if (reason == 0) {
        stmt = [self prepareLocked:@"DELETE FROM working_set WHERE item_id = ?"];
        if (!stmt) return;
        SeafFPBindText(stmt, 1, itemIdentifier);
    } else {
        stmt = [self prepareLocked:@"INSERT OR REPLACE INTO working_set(item_id, reason, seq) VALUES(?,?,?)"];
        if (!stmt) return;
        SeafFPBindText(stmt, 1, itemIdentifier);
        sqlite3_bind_int64(stmt, 2, reason);
        sqlite3_bind_int64(stmt, 3, seq);
    }
    [self stepLocked:stmt];
    sqlite3_finalize(stmt);
}

- (void)writeWorkingSetLockedItem:(NSString *)itemIdentifier reason:(SeafFPWorkingSetReason)reason
{
    [self writeWorkingSetLockedItem:itemIdentifier reason:reason seq:(reason == 0 ? 0 : [self nextSeqLocked])];
}

- (NSArray<NSString *> *)workingSetItemIdentifiersChangedSinceSeq:(long long)seq
{
    NSMutableArray *result = [NSMutableArray array];
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:@"SELECT item_id FROM working_set WHERE seq > ? ORDER BY seq"];
        if (!stmt) return;
        sqlite3_bind_int64(stmt, 1, seq);
        while ([self stepLocked:stmt] == SQLITE_ROW) {
            NSString *identifier = SeafFPColumnText(stmt, 0);
            if (identifier) [result addObject:identifier];
        }
        sqlite3_finalize(stmt);
    }];
    return result;
}

- (void)replaceMaterializedItemIdentifiers:(NSArray<NSString *> *)identifiers
{
    NSSet<NSString *> *wanted = [NSSet setWithArray:identifiers];
    // The rows are read inside the transaction: the write below replaces a
    // whole row, and the app (migrating favorites) writes the same table, so a
    // snapshot taken before BEGIN IMMEDIATE would clobber its reason bits.
    [self performBatch:^{
        NSMutableDictionary<NSString *, NSNumber *> *rows = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSNumber *> *seqs = [NSMutableDictionary dictionary];
        sqlite3_stmt *stmt = [self prepareLocked:@"SELECT item_id, reason, seq FROM working_set"];
        if (!stmt) return;
        while ([self stepLocked:stmt] == SQLITE_ROW) {
            NSString *identifier = SeafFPColumnText(stmt, 0);
            if (!identifier) continue;
            rows[identifier] = @(sqlite3_column_int64(stmt, 1));
            seqs[identifier] = @(sqlite3_column_int64(stmt, 2));
        }
        sqlite3_finalize(stmt);
        long long current = [self currentSeqLocked];
        for (NSString *identifier in rows) {
            SeafFPWorkingSetReason reason = rows[identifier].integerValue;
            if ((reason & SeafFPWorkingSetReasonMaterialized) && ![wanted containsObject:identifier]) {
                [self writeWorkingSetLockedItem:identifier
                                         reason:(reason & ~SeafFPWorkingSetReasonMaterialized)
                                            seq:seqs[identifier].longLongValue];
            }
        }
        for (NSString *identifier in wanted) {
            SeafFPWorkingSetReason reason = rows[identifier].integerValue;
            if (!(reason & SeafFPWorkingSetReasonMaterialized)) {
                [self writeWorkingSetLockedItem:identifier
                                         reason:(reason | SeafFPWorkingSetReasonMaterialized)
                                            seq:(seqs[identifier] ? seqs[identifier].longLongValue : current)];
            }
        }
    }];
}

// Both writers below hand out a seq, so they run inside BEGIN IMMEDIATE like
// the identity writers: outside a transaction the read and the update of the
// counter are separate statements, and the app (migrating) could write a
// value the extension had already moved past, making later rows reuse it.
- (void)addWorkingSetItem:(NSString *)itemIdentifier reason:(SeafFPWorkingSetReason)reason
{
    [self performBatch:^{
        SeafFPWorkingSetReason current = [self workingSetReasonLockedForItem:itemIdentifier];
        SeafFPWorkingSetReason merged = current | reason;
        if (merged != current || current == 0) {
            [self writeWorkingSetLockedItem:itemIdentifier reason:merged];
        }
    }];
}

- (void)removeWorkingSetItem:(NSString *)itemIdentifier reason:(SeafFPWorkingSetReason)reason
{
    [self performBatch:^{
        SeafFPWorkingSetReason current = [self workingSetReasonLockedForItem:itemIdentifier];
        if (current == 0) return;
        SeafFPWorkingSetReason remaining = current & ~reason;
        if (remaining != current) {
            [self writeWorkingSetLockedItem:itemIdentifier reason:remaining];
        }
    }];
}

- (void)removeWorkingSetItem:(NSString *)itemIdentifier
{
    [self perform:^{
        if ([self workingSetReasonLockedForItem:itemIdentifier] != 0) {
            [self writeWorkingSetLockedItem:itemIdentifier reason:0];
        }
    }];
}

#pragma mark - Main app indexing

+ (long long)currentSeqForDomainIdentifier:(NSString *)domainIdentifier
{
    if (domainIdentifier.length == 0) return -1;
    NSURL *url = [SeafFPIdentifier storeURLForDomainIdentifier:domainIdentifier];
    if (url.path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) return -1;
    // No SQLITE_OPEN_CREATE: a store removed together with its domain must
    // not come back as an empty file. No PRAGMA: journal_mode is persistent.
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(url.path.fileSystemRepresentation, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        if (db) sqlite3_close_v2(db);
        return -1;
    }
    sqlite3_busy_timeout(db, 200);
    long long seq = -1;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = 'seq'", -1, &stmt, NULL) == SQLITE_OK
        && sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *text = sqlite3_column_text(stmt, 0);
        if (text) seq = atoll((const char *)text);
    }
    sqlite3_finalize(stmt);
    sqlite3_close_v2(db);
    return seq;
}

/// Runs `block` on the store queue inside BEGIN IMMEDIATE. When the write
/// lock cannot be taken nothing runs (the main app's writes are best effort;
/// unlike performBatch: they never fall back to autocommit). The block sets
/// *rollback to discard everything it wrote. Returns the block's result.
- (BOOL)performIndexWrite:(BOOL (^)(BOOL *rollback))block
{
    return [self performCommittedWrite:block requestSignal:YES];
}

- (BOOL)performCommittedWrite:(BOOL (^)(BOOL *rollback))block requestSignal:(BOOL)signal
{
    return [self performWrite:block requestSignal:signal] == SeafFPWriteChanged;
}

/// Failed when the write lock could not be taken, the block asked for a
/// rollback, any statement failed (reads included) or COMMIT failed: then
/// nothing the block wrote reached the file.
- (SeafFPWriteResult)performWrite:(BOOL (^)(BOOL *rollback))block requestSignal:(BOOL)signal
{
    __block SeafFPWriteResult result = SeafFPWriteFailed;
    [self perform:^{
        [self beginLocked];
        if (!self->_transactionOpen) {
            [self leaveTransactionLocked];
            Info("file provider store busy, index write skipped");
            return;
        }
        BOOL rollback = NO, changed = NO;
        @try {
            changed = block(&rollback);
            if (changed && !rollback && signal && ![self requestWorkingSetSignalLocked]) rollback = YES;
        } @finally {
            if (rollback) {
                [self rollbackLocked];
            } else if ([self commitLocked]) {
                result = changed ? SeafFPWriteChanged : SeafFPWriteUnchanged;
            }
        }
    }];
    return result;
}

- (NSString *)dirStampKeyForRepo:(NSString *)repoId parentUUID:(NSString *)parentUUID
{
    return [NSString stringWithFormat:@"%@%@:%@", kMetaDirStampPrefix, repoId ?: @"", parentUUID.length > 0 ? parentUUID : @"/"];
}

- (long long)dirStampLockedForRepo:(NSString *)repoId parentUUID:(NSString *)parentUUID
{
    return [self metaValueLockedForKey:[self dirStampKeyForRepo:repoId parentUUID:parentUUID]].longLongValue;
}

- (void)setDirStampLocked:(long long)seq forRepo:(NSString *)repoId parentUUID:(NSString *)parentUUID
{
    [self setMetaValueLocked:[NSString stringWithFormat:@"%lld", seq] forKey:[self dirStampKeyForRepo:repoId parentUUID:parentUUID]];
}

- (long long)directoryStampForRepo:(NSString *)repoId parentUUID:(NSString *)parentUUID
{
    __block long long seq = 0;
    [self perform:^{ seq = [self dirStampLockedForRepo:repoId parentUUID:parentUUID]; }];
    return seq;
}

- (NSArray<SeafFPRecord *> *)childRecordsLockedOfRepo:(NSString *)repoId parentUUID:(NSString *)parentUUID
{
    NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM identity WHERE repo_id = ? AND deleted = 0 AND parent_uuid IS ?", kRecordColumns];
    return [self recordsLockedWithSQL:sql binder:^(sqlite3_stmt *stmt) {
        SeafFPBindText(stmt, 1, repoId);
        SeafFPBindText(stmt, 2, parentUUID);
    }];
}

/// YES when a direct child of the directory (live or tombstoned) was written after `seq`.
- (BOOL)hasChildLockedOfRepo:(NSString *)repoId parentUUID:(NSString *)parentUUID changedAfter:(long long)seq
{
    sqlite3_stmt *stmt = [self prepareLocked:@"SELECT 1 FROM identity WHERE repo_id = ?1 AND parent_uuid IS ?2 AND seq > ?3 LIMIT 1"];
    if (!stmt) return YES;   // cannot tell: treat as changed, the caller gives up
    SeafFPBindText(stmt, 1, repoId);
    SeafFPBindText(stmt, 2, parentUUID);
    sqlite3_bind_int64(stmt, 3, seq);
    BOOL found = [self stepLocked:stmt] == SQLITE_ROW;
    sqlite3_finalize(stmt);
    return found;
}

/// YES when a row below the directory record was written after `seq`. Uses
/// substr like subtreeRecordsLockedOf: (LIKE would treat % and _ in names as wildcards).
- (BOOL)hasSubtreeRecordLockedOf:(SeafFPRecord *)record changedAfter:(long long)seq
{
    sqlite3_stmt *stmt = [self prepareLocked:@"SELECT 1 FROM identity WHERE repo_id = ?1 AND substr(path, 1, length(?2)) = ?2 AND seq > ?3 LIMIT 1"];
    if (!stmt) return YES;
    SeafFPBindText(stmt, 1, record.repoId);
    SeafFPBindText(stmt, 2, [record.path stringByAppendingString:@"/"]);
    sqlite3_bind_int64(stmt, 3, seq);
    BOOL found = [self stepLocked:stmt] == SQLITE_ROW;
    sqlite3_finalize(stmt);
    return found;
}

/// Makes sure the directory `dirPath` and all of its ancestors have live rows.
/// NO when one of them is tombstoned and allowRevive is NO, or a write failed.
/// uuid: the directory's uuid (nil for the library root).
- (BOOL)ensureDirectoryLockedForRepo:(NSString *)repoId
                                path:(NSString *)dirPath
                         allowRevive:(BOOL)allowRevive
                                uuid:(NSString **)outUUID
                             changed:(BOOL *)changed
{
    NSArray<NSString *> *ancestors = SeafFPAncestorPaths(dirPath, YES);
    for (NSString *path in ancestors) {
        SeafFPRecord *existing = [self recordLockedForRepo:repoId path:path];
        if (existing.deleted && !allowRevive) return NO;
        if (existing && !existing.deleted && !existing.isDir && !allowRevive) return NO;
    }
    NSString *parent = nil;
    for (NSString *path in ancestors) {
        SeafFPRecord *record = [self upsertRecordLockedForRepo:repoId path:path isDir:YES parentUUID:parent
                                                          oid:nil mtime:0 size:-1 changed:changed];
        if (!record) return NO;
        parent = record.uuid;
    }
    if (outUUID) *outUUID = parent;
    return YES;
}

/// YES when the path or one of its ancestors has a tombstoned row.
- (BOOL)isPathLockedTombstonedForRepo:(NSString *)repoId path:(NSString *)normalized
{
    for (NSString *path in SeafFPAncestorPaths(normalized, YES)) {
        if ([self recordLockedForRepo:repoId path:path].deleted) return YES;
    }
    return NO;
}

- (BOOL)isDepartedPathLockedForRepo:(NSString *)repoId path:(NSString *)path
{
    for (NSString *ancestor in SeafFPAncestorPaths(path, YES)) {
        if ([self metaValueLockedForKey:[self departedPathKeyForRepo:repoId path:ancestor]] != nil) return YES;
    }
    return NO;
}

- (NSString *)departedPathKeyForRepo:(NSString *)repoId path:(NSString *)path
{
    return [NSString stringWithFormat:@"%@%@:%@", kMetaDepartedPathPrefix, repoId, path];
}

- (NSArray<NSString *> *)activityRecheckDirectoryPathsLockedOfRepo:(NSString *)repoId
{
    sqlite3_stmt *stmt = [self prepareLocked:@"SELECT dir_path FROM fp_check WHERE repo_id = ? ORDER BY dir_path"];
    if (!stmt) return @[];
    SeafFPBindText(stmt, 1, repoId);
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    while ([self stepLocked:stmt] == SQLITE_ROW) {
        NSString *path = SeafFPColumnText(stmt, 0);
        if (path) [result addObject:path];
    }
    sqlite3_finalize(stmt);
    return result;
}

- (NSArray<NSString *> *)activityRecheckDirectoryPathsOfRepo:(NSString *)repoId
{
    if (repoId.length == 0) return @[];
    __block NSArray<NSString *> *result = @[];
    [self perform:^{ result = [self activityRecheckDirectoryPathsLockedOfRepo:repoId]; }];
    return result;
}

/// Asks for a fresh listing of the directory. The check gets a new version
/// (a seq) every time: only a listing whose request started at or after it
/// can confirm the check, so a response already in flight cannot.
- (BOOL)requestDirectoryCheckLockedForRepo:(NSString *)repoId path:(NSString *)path
{
    return [self requestDirectoryCheckLockedForRepo:repoId path:path delay:0];
}

/// delay: seconds before the check is due.
- (BOOL)requestDirectoryCheckLockedForRepo:(NSString *)repoId path:(NSString *)path delay:(NSTimeInterval)delay
{
    if (repoId.length == 0 || path.length == 0) return NO;
    long long version = [self nextSeqLocked];
    if (version <= 0) return NO;
    sqlite3_stmt *stmt = [self prepareLocked:
        @"INSERT INTO fp_check(repo_id, dir_path, version, not_before) VALUES(?, ?, ?, ?) "
         "ON CONFLICT(repo_id, dir_path) DO UPDATE SET version = excluded.version, attempts = 0, denials = 0, "
         "not_before = excluded.not_before, last_status = 0"];
    if (!stmt) return NO;
    SeafFPBindText(stmt, 1, repoId);
    SeafFPBindText(stmt, 2, [SeafFPIdentifier normalizedPath:path]);
    sqlite3_bind_int64(stmt, 3, version);
    sqlite3_bind_double(stmt, 4, delay > 0 ? [NSDate date].timeIntervalSince1970 + delay : 0);
    int rc = [self stepLocked:stmt];
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE;
}

- (BOOL)requestDirectoryCheckOfRepo:(NSString *)repoId path:(NSString *)path
{
    if (repoId.length == 0 || path.length == 0) return NO;
    return [self performWrite:^BOOL(BOOL *rollback) {
        if (![self requestDirectoryCheckLockedForRepo:repoId path:path]) { *rollback = YES; return NO; }
        return YES;
    } requestSignal:NO] == SeafFPWriteChanged;
}

- (NSArray<SeafFPDirectoryCheck *> *)dueDirectoryChecksAt:(NSDate *)date limit:(NSUInteger)limit
{
    return [self dueDirectoryChecksAt:date limit:limit repoIds:nil];
}

- (NSArray<SeafFPDirectoryCheck *> *)dueDirectoryChecksAt:(NSDate *)date limit:(NSUInteger)limit repoIds:(NSArray<NSString *> *)repoIds
{
    __block NSMutableArray<SeafFPDirectoryCheck *> *checks = nil;
    [self perform:^{
        // Only libraries that can be listed now: a locked one with many
        // checks must not fill the page and starve the others.
        NSMutableString *sql = [@"SELECT repo_id, dir_path, version, attempts, denials FROM fp_check WHERE not_before <= ?" mutableCopy];
        if (repoIds) {
            [sql appendString:@" AND repo_id IN (SELECT value FROM json_each(?))"];
        }
        [sql appendString:@" ORDER BY attempts, not_before, version LIMIT ?"];
        sqlite3_stmt *stmt = [self prepareLocked:sql];
        if (!stmt) return;
        int index = 1;
        sqlite3_bind_double(stmt, index++, date.timeIntervalSince1970);
        if (repoIds) {
            NSData *json = [NSJSONSerialization dataWithJSONObject:repoIds options:0 error:nil];
            SeafFPBindText(stmt, index++, json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]");
        }
        sqlite3_bind_int64(stmt, index, limit > 0 ? (sqlite3_int64)limit : -1);
        NSMutableArray *result = [NSMutableArray array];
        int rc;
        while ((rc = [self stepLocked:stmt]) == SQLITE_ROW) {
            SeafFPDirectoryCheck *check = [SeafFPDirectoryCheck new];
            check.repoId = SeafFPColumnText(stmt, 0);
            check.path = SeafFPColumnText(stmt, 1);
            check.version = sqlite3_column_int64(stmt, 2);
            check.attempts = (NSInteger)sqlite3_column_int64(stmt, 3);
            check.denials = (NSInteger)sqlite3_column_int64(stmt, 4);
            if (check.repoId && check.path) [result addObject:check];
        }
        sqlite3_finalize(stmt);
        if (rc == SQLITE_DONE) checks = result;
    }];
    return checks;
}

- (NSDate *)nextDirectoryCheckDate
{
    return [self nextDirectoryCheckDateOfRepos:nil];
}

- (NSDate *)nextDirectoryCheckDateOfRepos:(NSArray<NSString *> *)repoIds
{
    __block NSDate *date = nil;
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:repoIds ? @"SELECT MIN(not_before) FROM fp_check WHERE repo_id IN (SELECT value FROM json_each(?))"
                                                         : @"SELECT MIN(not_before) FROM fp_check"];
        if (!stmt) return;
        if (repoIds) {
            NSData *json = [NSJSONSerialization dataWithJSONObject:repoIds options:0 error:nil];
            SeafFPBindText(stmt, 1, json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]");
        }
        if ([self stepLocked:stmt] == SQLITE_ROW && sqlite3_column_type(stmt, 0) != SQLITE_NULL) {
            date = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(stmt, 0)];
        }
        sqlite3_finalize(stmt);
    }];
    return date;
}

/// Runs `sql` with (repo, path, version) bound last, in a transaction.
- (BOOL)updateDirectoryCheck:(SeafFPDirectoryCheck *)check sql:(NSString *)sql binder:(nullable void (^)(sqlite3_stmt *stmt))binder
{
    return [self performWrite:^BOOL(BOOL *rollback) {
        sqlite3_stmt *stmt = [self prepareLocked:sql];
        if (!stmt) { *rollback = YES; return NO; }
        int next = 1;
        if (binder) { binder(stmt); next = sqlite3_bind_parameter_count(stmt) - 2; }
        SeafFPBindText(stmt, next, check.repoId);
        SeafFPBindText(stmt, next + 1, check.path);
        sqlite3_bind_int64(stmt, next + 2, check.version);
        int rc = [self stepLocked:stmt];
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) { *rollback = YES; return NO; }
        return sqlite3_changes(self->_db) > 0;
    } requestSignal:NO] != SeafFPWriteFailed;
}

- (BOOL)deferDirectoryCheck:(SeafFPDirectoryCheck *)check until:(NSDate *)date status:(NSInteger)status
{
    return [self updateDirectoryCheck:check
                                  sql:@"UPDATE fp_check SET attempts = attempts + 1, denials = denials + ?, not_before = ?, last_status = ? "
                                       "WHERE repo_id = ? AND dir_path = ? AND version = ?"
                               binder:^(sqlite3_stmt *stmt) {
        sqlite3_bind_int64(stmt, 1, status == 403 ? 1 : 0);
        sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970);
        sqlite3_bind_int64(stmt, 3, status);
    }];
}

- (BOOL)dropDirectoryCheck:(SeafFPDirectoryCheck *)check
{
    return [self updateDirectoryCheck:check sql:@"DELETE FROM fp_check WHERE repo_id = ? AND dir_path = ? AND version = ?" binder:nil];
}

- (BOOL)moveDirectoryCheckToParent:(SeafFPDirectoryCheck *)check
{
    NSString *path = [SeafFPIdentifier normalizedPath:check.path];
    if ([path isEqualToString:@"/"]) return [self dropDirectoryChecksOfRepo:check.repoId];
    return [self performWrite:^BOOL(BOOL *rollback) {
        sqlite3_stmt *stmt = [self prepareLocked:@"DELETE FROM fp_check WHERE repo_id = ? AND dir_path = ? AND version = ?"];
        if (!stmt) { *rollback = YES; return NO; }
        SeafFPBindText(stmt, 1, check.repoId);
        SeafFPBindText(stmt, 2, path);
        sqlite3_bind_int64(stmt, 3, check.version);
        int rc = [self stepLocked:stmt];
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) { *rollback = YES; return NO; }
        if (sqlite3_changes(self->_db) == 0) return NO;   // asked for again meanwhile: list it once more
        // Keeps the version: only a parent listing that started after the
        // original request may say the directory is gone.
        stmt = [self prepareLocked:@"INSERT INTO fp_check(repo_id, dir_path, version) VALUES(?, ?, ?) "
                                    "ON CONFLICT(repo_id, dir_path) DO UPDATE SET version = MAX(version, excluded.version), attempts = 0, not_before = 0"];
        if (!stmt) { *rollback = YES; return NO; }
        SeafFPBindText(stmt, 1, check.repoId);
        SeafFPBindText(stmt, 2, path.stringByDeletingLastPathComponent);
        sqlite3_bind_int64(stmt, 3, check.version);
        rc = [self stepLocked:stmt];
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) { *rollback = YES; return NO; }
        return YES;
    } requestSignal:NO] != SeafFPWriteFailed;
}

- (BOOL)dropDirectoryChecksLockedOfRepo:(NSString *)repoId
{
    for (NSString *sql in @[@"DELETE FROM fp_check WHERE repo_id = ?", @"DELETE FROM fp_hint WHERE repo_id = ?"]) {
        sqlite3_stmt *stmt = [self prepareLocked:sql];
        if (!stmt) return NO;
        SeafFPBindText(stmt, 1, repoId);
        int rc = [self stepLocked:stmt];
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) return NO;
    }
    return YES;
}

- (BOOL)dropDirectoryChecksOfRepo:(NSString *)repoId
{
    return [self performWrite:^BOOL(BOOL *rollback) {
        if (![self dropDirectoryChecksLockedOfRepo:repoId]) { *rollback = YES; return NO; }
        return YES;
    } requestSignal:NO] != SeafFPWriteFailed;
}

/// A fresh listing of (repoId, dir) whose request started at `S` confirms
/// the checks registered before it.
- (BOOL)confirmDirectoryChecksLockedForRepo:(NSString *)repoId path:(NSString *)dir requestStartSeq:(long long)S
{
    sqlite3_stmt *stmt = [self prepareLocked:@"DELETE FROM fp_check WHERE repo_id = ? AND dir_path = ? AND version <= ?"];
    if (!stmt) return NO;
    SeafFPBindText(stmt, 1, repoId);
    SeafFPBindText(stmt, 2, dir);
    sqlite3_bind_int64(stmt, 3, S);
    int rc = [self stepLocked:stmt];
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE;
}

- (BOOL)applyListingOfRepo:(NSString *)repoId
             directoryPath:(NSString *)directoryPath
                   entries:(NSArray<NSDictionary *> *)entries
           requestStartSeq:(long long)requestStartSeq
{
    return [self applyDirectoryListingOfRepo:repoId directoryPath:directoryPath entries:entries
                             requestStartSeq:requestStartSeq] == SeafFPWriteChanged;
}

/// Preserve an identity with a pending destination when the source name
/// is observed with different contents. Its replacement gets a fresh UUID.
- (BOOL)separateListingOccupantLocked:(SeafFPRecord *)record isDir:(BOOL)isDir oid:(NSString *)oid changed:(BOOL *)changed
{
    if (!record) return YES;
    BOOL previouslyAbsent = record.deleted && record.tombReason == SeafFPTombReasonAbsent;
    BOOL differentEntry = record.isDir != isDir || (record.oid.length && oid.length && ![record.oid isEqual:oid]);
    if (!previouslyAbsent && !differentEntry) return YES;
    NSDictionary *move = [self jsonMetaLocked:SeafFPMoveRecoveryKey(record.uuid)];
    if (!move) return NO;
    // Only a move the server acknowledged can explain different contents at
    // the source: before the receipt the request may never have run, and the
    // identity stays where the listing shows it (the journal is reconciled
    // or dropped from the item itself).
    BOOL acknowledged = move.count > 0 && ![move[@"confirmed"] isEqual:@NO];
    BOOL preserve = acknowledged && [move[@"sourceRepo"] isEqual:record.repoId] && [move[@"sourcePath"] isEqual:record.path];
    if (!preserve && record.hintRevivedFrom > 0) {
        // A later hint may be in the next decision batch. Bind it before
        // the listing assigns this old name to the replacement.
        sqlite3_stmt *stmt = [self prepareLocked:
            @"UPDATE fp_hint SET source_uuid = ? WHERE repo_id = ? AND old_path = ? AND state = 0 AND version <= ? AND source_uuid IS NULL"];
        if (!stmt) return NO;
        SeafFPBindText(stmt, 1, record.uuid);
        SeafFPBindText(stmt, 2, record.repoId);
        SeafFPBindText(stmt, 3, record.path);
        sqlite3_bind_int64(stmt, 4, record.hintRevivedAt);
        int rc = [self stepLocked:stmt];
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) return NO;
        preserve = sqlite3_changes(_db) > 0;
    }
    if (!preserve) return YES;
    if (![self detachRecordLocked:record reason:SeafFPTombReasonAbsent]) return NO;
    *changed = YES;
    return YES;
}

- (SeafFPWriteResult)applyDirectoryListingOfRepo:(NSString *)repoId
                                   directoryPath:(NSString *)directoryPath
                                         entries:(NSArray<NSDictionary *> *)entries
                                 requestStartSeq:(long long)requestStartSeq
{
    if (repoId.length == 0) return SeafFPWriteFailed;
    NSString *dir = [SeafFPIdentifier normalizedPath:directoryPath];
    BOOL isRoot = [dir isEqualToString:@"/"];
    long long S = requestStartSeq;
    return [self performWrite:^BOOL(BOOL *rollback) {
        if (S < 0 && [self isDepartedPathLockedForRepo:repoId path:dir]) return NO;
        // 1. Read-only: the chain from the top down to the directory itself.
        //    A tombstone written after the request (or any tombstone when the
        //    request time is unknown) means the listing must not resurrect it.
        NSMutableArray<SeafFPRecord *> *chain = [NSMutableArray array];
        SeafFPRecord *dirRecord = nil;
        for (NSString *path in SeafFPAncestorPaths(dir, YES)) {
            SeafFPRecord *record = [self recordLockedForRepo:repoId path:path];
            if (record.deleted && (S < 0 || record.seq > S)) {
                *rollback = YES;
                return NO;
            }
            if (record && !record.deleted && !record.isDir && (S < 0 || record.seq > S)) {
                *rollback = YES;
                return NO;
            }
            if (record) [chain addObject:record];
            dirRecord = record;   // after the loop: the directory's own row (or nil)
        }

        // 2. Read-only conflict check against what changed after the request
        //    was sent. Done before anything is written, so the rows this very
        //    transaction creates can never count as a conflict. Children
        //    written after the request are skipped one by one below instead:
        //    rejecting the whole listing for them would never let a directory
        //    the extension keeps writing into (an import, say) be confirmed.
        if (S >= 0) {
            // An entry was renamed or moved away from the directory or from
            // one of its ancestors (a renamed ancestor makes this path stale).
            if ([self dirStampLockedForRepo:repoId parentUUID:nil] > S) {
                *rollback = YES;
                return NO;
            }
            for (SeafFPRecord *record in chain) {
                if ([self dirStampLockedForRepo:repoId parentUUID:record.uuid] > S) {
                    *rollback = YES;
                    return NO;
                }
            }
        }

        // 3. The directory chain: the server just listed it, so it exists.
        BOOL changed = NO;
        NSString *parentUUID = nil;
        if (!isRoot && ![self ensureDirectoryLockedForRepo:repoId path:dir allowRevive:YES uuid:&parentUUID changed:&changed]) {
            *rollback = YES;
            return NO;
        }

        // 4. The entries.
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        NSMutableArray<SeafFPRecord *> *inserted = [NSMutableArray array], *absent = [NSMutableArray array];
        // A row left alone because it was written after the request, where the
        // listing disagrees with it (absent, deleted, another type): this
        // listing cannot verify it, a later one has to.
        BOOL unverified = NO;
        for (NSDictionary *entry in entries) {
            NSString *name = SeafFPEntryString(entry, SeafFPEntryName);
            if (name.length == 0 || [name containsString:@"/"]) continue;
            NSString *childPath = [SeafFPIdentifier normalizedPath:[dir stringByAppendingFormat:@"/%@", name]];
            BOOL isDir = [entry[SeafFPEntryIsDir] boolValue];
            if (S < 0) {
                // Unknown request time: like a listing served from the cache,
                // existing rows are left exactly as they are.
                SeafFPRecord *existing = [self recordLockedForRepo:repoId path:childPath];
                if (existing) {
                    if (!existing.deleted) [seen addObject:existing.uuid];
                    continue;
                }
                if ([self isDepartedPathLockedForRepo:repoId path:childPath]) continue;
            } else {
                // Written after the request was sent (added, edited, moved in
                // or deleted on this device): newer than what the server listed.
                SeafFPRecord *existing = [self recordLockedForRepo:repoId path:childPath];
                if (existing.seq > S) {
                    if (!existing.deleted) [seen addObject:existing.uuid];
                    if (existing.deleted || existing.isDir != isDir) unverified = YES;
                    continue;
                }
                // A directory the listing shows as a file: rows written below
                // it after the request are newer than that view.
                if (existing && !existing.deleted && existing.isDir && !isDir && [self hasSubtreeRecordLockedOf:existing changedAfter:S]) {
                    [seen addObject:existing.uuid];
                    unverified = YES;
                    continue;
                }
                if (![self separateListingOccupantLocked:existing isDir:isDir oid:SeafFPEntryString(entry, SeafFPEntryOid)
                                                  changed:&changed]) {
                    *rollback = YES;
                    return NO;
                }
            }
            SeafFPRecord *child = [self upsertRecordLockedForRepo:repoId
                                                             path:childPath
                                                            isDir:isDir
                                                       parentUUID:parentUUID
                                                              oid:SeafFPEntryString(entry, SeafFPEntryOid)
                                                            mtime:SeafFPEntryNumber(entry, SeafFPEntryMtime, 0)
                                                             size:(isDir ? -1 : SeafFPEntryNumber(entry, SeafFPEntrySize, -1))
                                                          changed:&changed];
            if (!child) {
                *rollback = YES;
                return NO;
            }
            if (child.createdSeq > self->_transactionStartSeq) [inserted addObject:child];
            [seen addObject:child.uuid];
        }

        // 5. Rows the server no longer lists. A directory whose subtree got a
        //    row after the request (the extension just wrote into it) stays.
        if (S >= 0) {
            for (SeafFPRecord *gone in [self childRecordsLockedOfRepo:repoId parentUUID:parentUUID]) {
                if ([seen containsObject:gone.uuid]) continue;
                if (gone.seq > S || (gone.isDir && [self hasSubtreeRecordLockedOf:gone changedAfter:S])) {
                    unverified = YES;
                    continue;
                }
                if (![self markDeletedLockedUUID:gone.uuid reason:SeafFPTombReasonAbsent]) { *rollback = YES; return NO; }
                [absent addObject:gone];
                changed = YES;
            }
            if (![self confirmDirectoryChecksLockedForRepo:repoId path:dir requestStartSeq:S]) { *rollback = YES; return NO; }
            if (![self correctRenameHintsLockedForRepo:repoId directory:dir requestStartSeq:S
                                               entries:entries inserted:inserted absent:absent changed:&changed]) { *rollback = YES; return NO; }
            // A little later, so a directory written into continuously is not
            // listed back to back.
            if (unverified && ![self requestDirectoryCheckLockedForRepo:repoId path:dir delay:kUnverifiedRecheckDelay]) { *rollback = YES; return NO; }
        }
        return changed;
    } requestSignal:YES];
}

- (BOOL)applySparseEntriesOfRepo:(NSString *)repoId
                         entries:(NSArray<NSDictionary *> *)entries
                     allowRevive:(BOOL)allowRevive
{
    if (repoId.length == 0 || entries.count == 0) return NO;
    return [self performIndexWrite:^BOOL(BOOL *rollback) {
        BOOL changed = NO;
        for (NSDictionary *entry in entries) {
            NSString *path = [SeafFPIdentifier normalizedPath:SeafFPEntryString(entry, SeafFPEntryPath)];
            if ([path isEqualToString:@"/"]) continue;
            if (!allowRevive && [self isPathLockedTombstonedForRepo:repoId path:path]) continue;
            NSString *parentPath = path.stringByDeletingLastPathComponent;
            BOOL ancestorIsFile = NO;
            for (NSString *ancPath in SeafFPAncestorPaths(parentPath, YES)) {
                SeafFPRecord *anc = [self recordLockedForRepo:repoId path:ancPath];
                if (anc && !anc.deleted && !anc.isDir) {
                    ancestorIsFile = YES;
                    break;
                }
            }
            if (ancestorIsFile) continue;
            NSString *parentUUID = nil;
            if (![self ensureDirectoryLockedForRepo:repoId path:parentPath allowRevive:allowRevive uuid:&parentUUID changed:&changed]) {
                continue;
            }
            BOOL isDir = [entry[SeafFPEntryIsDir] boolValue];
            NSString *entryOid = SeafFPEntryString(entry, SeafFPEntryOid);
            long long entryMtime = SeafFPEntryNumber(entry, SeafFPEntryMtime, 0);
            long long entrySize = isDir ? -1 : SeafFPEntryNumber(entry, SeafFPEntrySize, -1);
            SeafFPRecord *existing = [self recordLockedForRepo:repoId path:path];
            if (existing && !existing.deleted) {
                if (existing.isDir != isDir) {
                    if (!allowRevive || entryMtime <= 0 || (existing.mtime > 0 && entryMtime <= existing.mtime)) {
                        continue;
                    }
                } else {
                    if (existing.mtime > 0 && (entryMtime <= 0 || entryMtime < existing.mtime)) {
                        entryOid = existing.oid;
                        entryMtime = existing.mtime;
                        entrySize = existing.size;
                    } else if (existing.oid.length > 0 && entryOid.length == 0 && entryMtime == existing.mtime && existing.size >= 0) {
                        entrySize = existing.size;
                    }
                }
            }
            SeafFPRecord *record = [self upsertRecordLockedForRepo:repoId
                                                              path:path
                                                             isDir:isDir
                                                        parentUUID:parentUUID
                                                               oid:entryOid
                                                             mtime:entryMtime
                                                              size:entrySize
                                                           changed:&changed];
            if (!record) {
                *rollback = YES;
                return NO;
            }
        }
        return changed;
    }];
}

static BOOL SeafFPNamesEqual(NSString * _Nullable a, NSString * _Nullable b)
{
    if (!a || !b) return NO;
    return [a.precomposedStringWithCanonicalMapping isEqualToString:b.precomposedStringWithCanonicalMapping];
}

/// YES when `candidate` is a conflict-renamed sibling of `expected`, such as
/// "report (1).txt" or "report(1).txt" for "report.txt", or "Photos (2)" for "Photos".
BOOL SeafFPIsConflictSiblingName(NSString *candidate, NSString *expected)
{
    if (candidate.length == 0 || expected.length == 0 || SeafFPNamesEqual(candidate, expected)) return NO;
    NSString *candNorm = candidate.precomposedStringWithCanonicalMapping;
    NSString *expNorm = expected.precomposedStringWithCanonicalMapping;
    NSString *candExt = candNorm.pathExtension;
    NSString *expExt = expNorm.pathExtension;
    if (![candExt isEqualToString:expExt]) return NO;
    NSString *candStem = candExt.length > 0 ? candNorm.stringByDeletingPathExtension : candNorm;
    NSString *expStem = expExt.length > 0 ? expNorm.stringByDeletingPathExtension : expNorm;
    if (![candStem hasPrefix:expStem] || candStem.length <= expStem.length) return NO;
    NSString *suffix = [candStem substringFromIndex:expStem.length];
    if ([suffix hasPrefix:@" ("]) {
        suffix = [suffix substringFromIndex:2];
    } else if ([suffix hasPrefix:@"("]) {
        suffix = [suffix substringFromIndex:1];
    } else {
        return NO;
    }
    if (![suffix hasSuffix:@")"] || suffix.length < 2) return NO;
    NSString *digits = [suffix substringToIndex:suffix.length - 1];
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return digits.length > 0 && [digits rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

/// YES when `occupant` is a provisional row created after `S` by a concurrent
/// destination directory refresh for the same item as `record`.
- (BOOL)isProvisionalDestinationOccupantLocked:(SeafFPRecord *)occupant
                                forMovedRecord:(SeafFPRecord *)record
                               requestStartSeq:(long long)S
{
    if (!occupant || occupant.deleted || !record || S < 0) return NO;
    if ([occupant.uuid isEqualToString:record.uuid]) return YES;
    if (occupant.createdSeq <= S || occupant.confirmedPlacement) return NO;
    if (occupant.isDir != record.isDir) return NO;
    if (record.oid.length > 0 && occupant.oid.length > 0 && ![occupant.oid isEqualToString:record.oid]) {
        return NO;
    }
    return YES;
}

static NSString *SeafFPMoveRecoveryKey(NSString *uuid)
{
    return [@"fp_confirmed_move:" stringByAppendingString:uuid];
}

/// The fresh destination matched the moved content, but the Store may still
/// contain the former occupant observed before dispatch. Only retire that
/// exact, unchanged occupant; a later local write or an identical oid leaves
/// the ownership ambiguous.
- (BOOL)isFormerMoveDestinationLocked:(SeafFPRecord *)occupant source:(SeafFPRecord *)source
                             recovery:(NSDictionary *)recovery requestStartSeq:(long long)start
{
    if (!occupant || occupant.deleted || occupant.seq > start || !source.oid.length
        || ![recovery[@"sourceRepo"] isEqual:source.repoId] || ![recovery[@"sourcePath"] isEqual:source.path]
        || [recovery[@"start"] longLongValue] != start || ![recovery[@"repo"] isEqual:occupant.repoId]
        || ![recovery[@"dir"] isEqual:occupant.directoryPath]) return NO;
    NSString *canonical = occupant.name.precomposedStringWithCanonicalMapping.lowercaseString;
    NSDictionary *before = recovery[@"existingDestinationEntries"][canonical];
    if (![before isKindOfClass:[NSDictionary class]]) return NO;
    NSString *oldOid = SeafFPEntryString(before, SeafFPEntryOid);
    return oldOid.length && [oldOid isEqual:occupant.oid] && ![oldOid isEqual:source.oid]
        && [before[SeafFPEntryIsDir] boolValue] == occupant.isDir
        && !(occupant.isDir && [self hasSubtreeRecordLockedOf:occupant changedAfter:start]);
}

static NSString *SeafFPMoveDestinationKey(NSString *repoId, NSString *path)
{
    NSString *canonical = path.precomposedStringWithCanonicalMapping.lowercaseString;
    return [NSString stringWithFormat:@"fp_move_destination:%@:%@", repoId, canonical];
}

- (NSString *)moveDestinationKeyForRecovery:(NSDictionary *)recovery
{
    NSString *path = [SeafFPIdentifier normalizedPath:[recovery[@"dir"] stringByAppendingPathComponent:recovery[@"name"]]];
    return SeafFPMoveDestinationKey(recovery[@"repo"], path);
}

/// Reservations stop excluding other operations after a week. The journal
/// remains available to recover the original identity, even after long idle
/// periods or while another operation holds the destination reservation.
static const long long kMoveJournalRetention = 7 * 24 * 3600;
/// How long a move's outcome is awaited. The api2 move and rename endpoints
/// run synchronously and seahub's worker timeout is 20 minutes, so an hour
/// later the request has finished or never will. After it the journal is
/// expired against a fresh listing of the source (SeafFPExtension).
/// Unacknowledged reservations lapse at the same point.
static const long long kMoveSettleGrace = 3600;

static long long SeafFPMoveJournalAge(NSDictionary *recovery, long long now)
{
    long long startedAt = [recovery[@"startedAt"] longLongValue];
    // Journals written before the field existed have no retry window left.
    return startedAt > 0 ? now - startedAt : kMoveJournalRetention + 1;
}

+ (BOOL)moveJournalExpired:(NSDictionary *)recovery now:(long long)now
{
    if (recovery.count == 0) return NO;
    long long retention = [recovery[@"confirmed"] isEqual:@NO] ? kMoveSettleGrace : kMoveJournalRetention;
    return SeafFPMoveJournalAge(recovery, now) > retention;
}

+ (BOOL)moveSettleGraceElapsed:(NSDictionary *)recovery now:(long long)now
{
    return recovery.count > 0 && SeafFPMoveJournalAge(recovery, now) > kMoveSettleGrace;
}

/// The uuid holding the reservation of `destinationKey`, after dropping one
/// whose journal is gone or expired. nil when free; sets failed on a read
/// or write error.
- (NSString *)liveReservationOwnerLockedForKey:(NSString *)destinationKey now:(long long)now failed:(BOOL *)failed
{
    BOOL readFailed = NO;
    NSString *owner = [self metaValueLockedForKey:destinationKey failed:&readFailed];
    if (readFailed) { *failed = YES; return nil; }
    if (!owner) return nil;
    NSDictionary *recovery = [self jsonMetaLocked:SeafFPMoveRecoveryKey(owner)];
    if (!recovery) { *failed = YES; return nil; }
    BOOL orphan = recovery.count == 0 || ![[self moveDestinationKeyForRecovery:recovery] isEqual:destinationKey];
    if (!orphan && ![SeafFPStore moveJournalExpired:recovery now:now]) return owner;
    if (![self setMetaValueLocked:nil forKey:destinationKey]) { *failed = YES; return nil; }
    return nil;
}

- (BOOL)destinationReservedLockedForRepo:(NSString *)repoId path:(NSString *)path exceptUUID:(NSString *)uuid
{
    BOOL failed = NO;
    NSString *owner = [self liveReservationOwnerLockedForKey:SeafFPMoveDestinationKey(repoId, path)
                                                         now:(long long)[NSDate date].timeIntervalSince1970 failed:&failed];
    if (failed) { _transactionFailed = YES; return YES; }
    return owner && ![owner isEqual:uuid];
}

/// Drops the journal of `uuid` and the reservation it holds; a missing
/// journal is not an error.
- (BOOL)clearMoveJournalLockedForUUID:(NSString *)uuid
{
    NSDictionary *recovery = [self jsonMetaLocked:SeafFPMoveRecoveryKey(uuid)];
    if (!recovery) return NO;
    if (![self setMetaValueLocked:nil forKey:[@"fp_move_quarantine_pending:" stringByAppendingString:uuid]]) return NO;
    return recovery.count == 0 || [self clearMoveLocked:recovery uuid:uuid];
}

/// Every journal that starts in or targets `repoId`, with its reservation.
- (BOOL)dropMoveJournalsLockedOfRepo:(NSString *)repoId
{
    NSMutableArray<NSString *> *uuids = [NSMutableArray array];
    sqlite3_stmt *stmt = [self prepareLocked:@"SELECT key, value FROM meta WHERE key GLOB 'fp_confirmed_move:*'"];
    if (!stmt) return NO;
    int rc;
    while ((rc = [self stepLocked:stmt]) == SQLITE_ROW) {
        NSString *key = SeafFPColumnText(stmt, 0);
        NSData *data = [SeafFPColumnText(stmt, 1) dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *recovery = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![recovery isKindOfClass:[NSDictionary class]]) continue;
        if ([recovery[@"repo"] isEqual:repoId] || [recovery[@"sourceRepo"] isEqual:repoId]) {
            [uuids addObject:[key substringFromIndex:@"fp_confirmed_move:".length]];
        }
    }
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) return NO;
    for (NSString *uuid in uuids) {
        if (![self clearMoveJournalLockedForUUID:uuid]) return NO;
    }
    stmt = [self prepareLocked:@"DELETE FROM meta WHERE key GLOB ?"];
    if (!stmt) return NO;
    SeafFPBindText(stmt, 1, [NSString stringWithFormat:@"fp_move_destination:%@:*", repoId]);
    rc = [self stepLocked:stmt];
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE;
}

- (long long)beginMoveOfRecord:(SeafFPRecord *)record toRepo:(NSString *)repoId
                     directory:(NSString *)directoryPath parentUUID:(NSString *)parentUUID expectedName:(NSString *)name
                  requestedName:(NSString *)requestedName existingDestinationNames:(NSArray<NSString *> *)existingDestinationNames
{
    return [self beginMoveOfRecord:record toRepo:repoId directory:directoryPath parentUUID:parentUUID
                      expectedName:name requestedName:requestedName existingDestinationNames:existingDestinationNames
        existingDestinationEntries:nil];
}

- (long long)beginMoveOfRecord:(SeafFPRecord *)record toRepo:(NSString *)repoId
                     directory:(NSString *)directoryPath parentUUID:(NSString *)parentUUID expectedName:(NSString *)name
                  requestedName:(NSString *)requestedName existingDestinationNames:(NSArray<NSString *> *)existingDestinationNames
     existingDestinationEntries:(NSDictionary<NSString *, NSDictionary *> *)existingDestinationEntries
{
    __block long long start = -1;
    BOOL committed = [self performBatch:^{
        SeafFPRecord *current = [self recordLockedForUUID:record.uuid];
        if (!current || current.deleted || ![current.repoId isEqual:record.repoId] || ![current.path isEqual:record.path]
            || current.isDir != record.isDir || !SeafFPStringsEqual(current.oid, record.oid)) return;
        SeafFPRecord *parent = parentUUID ? [self recordLockedForUUID:parentUUID] : nil;
        if (parentUUID ? (!parent.isDir || parent.deleted || ![parent.repoId isEqual:repoId] || ![parent.path isEqual:directoryPath])
                       : ![directoryPath isEqual:@"/"]) return;
        NSString *key = SeafFPMoveRecoveryKey(record.uuid);
        NSDictionary *previous = [self jsonMetaLocked:key];
        NSString *destination = [SeafFPIdentifier normalizedPath:[directoryPath stringByAppendingPathComponent:name]];
        NSString *destinationKey = SeafFPMoveDestinationKey(repoId, destination);
        if (!previous || previous.count || [self metaValueLockedForKey:[@"fp_move_quarantine_pending:" stringByAppendingString:record.uuid]]) return;
        if ([self destinationReservedLockedForRepo:repoId path:destination exceptUUID:record.uuid]) return;
        long long seq = [self nextSeqLocked];
        if (seq <= 0) return;
        NSMutableDictionary *recovery = [@{@"sourceRepo": record.repoId, @"sourcePath": record.path, @"sourceSeq": @(record.seq),
            @"oid": record.oid ?: @"", @"isDir": @(record.isDir), @"repo": repoId, @"dir": directoryPath,
            @"sourceMtime": @(record.mtime), @"sourceSize": @(record.size),
            @"parent": parentUUID ?: @"", @"name": name, @"requestedName": requestedName ?: @"",
            @"start": @(seq), @"confirmed": @NO, @"existingDestinationNames": existingDestinationNames,
            @"startedAt": @((long long)[NSDate date].timeIntervalSince1970)} mutableCopy];
        if (existingDestinationEntries) recovery[@"existingDestinationEntries"] = existingDestinationEntries;
        if ([self writeJSONMetaLocked:recovery key:key] && [self setMetaValueLocked:record.uuid forKey:destinationKey]) start = seq;
        else self->_transactionFailed = YES;
    }];
    return committed ? start : -1;
}

- (BOOL)noteMoveReceiptForUUID:(NSString *)uuid requestStartSeq:(long long)start serverTime:(long long)serverTime
{
    __block BOOL saved = NO;
    BOOL committed = [self performBatch:^{
        NSString *key = SeafFPMoveRecoveryKey(uuid);
        NSMutableDictionary *recovery = [[self jsonMetaLocked:key] mutableCopy];
        if (!recovery.count || [recovery[@"start"] longLongValue] != start) return;
        recovery[@"confirmed"] = @YES;
        recovery[@"serverTime"] = @(serverTime);
        saved = [self writeJSONMetaLocked:recovery key:key];
    }];
    return committed && saved;
}

- (BOOL)clearMoveLocked:(NSDictionary *)recovery uuid:(NSString *)uuid
{
    NSString *destinationKey = [self moveDestinationKeyForRecovery:recovery];
    NSString *owner = [self metaValueLockedForKey:destinationKey];
    return (![owner isEqual:uuid] || [self setMetaValueLocked:nil forKey:destinationKey])
        && [self setMetaValueLocked:nil forKey:SeafFPMoveRecoveryKey(uuid)];
}

- (BOOL)discardUnconfirmedMoveForUUID:(NSString *)uuid requestStartSeq:(long long)start
{
    __block BOOL discarded = NO;
    BOOL committed = [self performBatch:^{
        NSDictionary *recovery = [self jsonMetaLocked:SeafFPMoveRecoveryKey(uuid)];
        if (!recovery) return;
        if (!recovery.count) { discarded = YES; return; }
        if (![recovery[@"confirmed"] isEqual:@NO] || [recovery[@"start"] longLongValue] != start) return;
        discarded = [self clearMoveLocked:recovery uuid:uuid];
        if (!discarded) self->_transactionFailed = YES;
    }];
    return committed && discarded;
}

- (BOOL)expireMoveForUUID:(NSString *)uuid matchingRecovery:(NSDictionary *)expected
{
    if (expected.count == 0) return NO;
    __block BOOL cleared = NO;
    BOOL committed = [self performBatch:^{
        NSDictionary *recovery = [self jsonMetaLocked:SeafFPMoveRecoveryKey(uuid)];
        // Replaced, settled or receipted since the caller read it.
        if (![recovery isEqualToDictionary:expected]) return;
        cleared = [self clearMoveLocked:recovery uuid:uuid];
        if (!cleared) self->_transactionFailed = YES;
    }];
    return committed && cleared;
}

- (NSDictionary *)moveRecoveryForUUID:(NSString *)uuid
{
    __block NSDictionary *recovery = nil;
    [self perform:^{
        recovery = [self jsonMetaLocked:SeafFPMoveRecoveryKey(uuid)];
        if (recovery && !recovery.count && [self metaValueLockedForKey:[@"fp_move_quarantine_pending:" stringByAppendingString:uuid]]) {
            recovery = @{@"needsResolution": @YES};
        }
    }];
    return recovery;
}

- (BOOL)discardMoveJournalForUUID:(NSString *)uuid
{
    __block BOOL discarded = NO;
    BOOL committed = [self performBatch:^{
        discarded = [self clearMoveJournalLockedForUUID:uuid];
        if (!discarded) self->_transactionFailed = YES;
    }];
    return committed && discarded;
}

- (SeafFPRecord *)refreshContentOfRecord:(SeafFPRecord *)record oid:(NSString *)oid mtime:(long long)mtime size:(long long)size
{
    __block SeafFPRecord *result = nil;
    BOOL committed = [self performBatch:^{
        SeafFPRecord *current = [self recordLockedForUUID:record.uuid];
        if (!current || current.deleted || ![current.repoId isEqual:record.repoId] || ![current.path isEqual:record.path]
            || current.isDir != record.isDir || current.seq != record.seq) return;
        if (SeafFPStringsEqual(current.oid, oid) && (mtime <= 0 || current.mtime == mtime)) { result = current; return; }
        current.oid = oid;
        if (mtime > 0) current.mtime = mtime;
        if (!current.isDir && size >= 0) current.size = size;
        current.seq = [self nextSeqLocked];
        if (current.seq <= 0 || ![self writeRecordLocked:current insert:NO]) { self->_transactionFailed = YES; return; }
        result = current;
    }];
    return committed ? result : nil;
}

- (BOOL)rememberMoveOfRecord:(SeafFPRecord *)record toRepo:(NSString *)repoId
                    directory:(NSString *)directoryPath parentUUID:(NSString *)parentUUID
                 expectedName:(NSString *)name requestStartSeq:(long long)start serverTime:(long long)serverTime
{
    NSString *key = SeafFPMoveRecoveryKey(record.uuid);
    NSDictionary *recovery = @{@"sourceRepo": record.repoId, @"sourcePath": record.path, @"sourceSeq": @(record.seq),
        @"oid": record.oid ?: @"", @"isDir": @(record.isDir), @"repo": repoId, @"dir": directoryPath,
        @"parent": parentUUID ?: @"", @"name": name, @"start": @(start), @"serverTime": @(serverTime),
        @"startedAt": @((long long)[NSDate date].timeIntervalSince1970)};
    __block BOOL saved = NO;
    BOOL committed = [self performBatch:^{
        NSDictionary *previous = [self jsonMetaLocked:key];
        if (!previous) return;
        if (previous.count) {
            NSMutableDictionary *stored = [previous mutableCopy], *wanted = [recovery mutableCopy];
            [stored removeObjectForKey:@"startedAt"];
            [wanted removeObjectForKey:@"startedAt"];
            saved = [stored isEqual:wanted];
            return;
        }
        SeafFPRecord *current = [self recordLockedForUUID:record.uuid];
        if (![current.repoId isEqual:record.repoId] || ![current.path isEqual:record.path]
            || current.isDir != record.isDir || (current.deleted && current.tombReason != SeafFPTombReasonAbsent)) return;
        NSString *destination = [SeafFPIdentifier normalizedPath:[directoryPath stringByAppendingPathComponent:name]];
        if ([self destinationReservedLockedForRepo:repoId path:destination exceptUUID:record.uuid]) return;
        NSString *destinationKey = [self moveDestinationKeyForRecovery:recovery];
        saved = [self writeJSONMetaLocked:recovery key:key] && [self setMetaValueLocked:record.uuid forKey:destinationKey];
        if (!saved) self->_transactionFailed = YES;
    }];
    return committed && saved;
}

- (SeafFPRecord *)confirmMoveOfRecord:(SeafFPRecord *)source
                               toRepo:(NSString *)repoId
                                 path:(NSString *)path
                           parentUUID:(NSString *)parentUUID
                      requestStartSeq:(long long)start
{
    return [self confirmMoveOfRecord:source toRepo:repoId path:path parentUUID:parentUUID requestStartSeq:start serverTime:0];
}

- (SeafFPRecord *)confirmMoveOfRecord:(SeafFPRecord *)source
                               toRepo:(NSString *)repoId
                                 path:(NSString *)path
                           parentUUID:(NSString *)parentUUID
                      requestStartSeq:(long long)start
                           serverTime:(long long)serverTime
{
    return [self confirmMoveOfRecord:source toRepo:repoId path:path parentUUID:parentUUID
                    requestStartSeq:start serverTime:serverTime requireRecovery:NO];
}

- (SeafFPRecord *)finishPendingMoveOfRecord:(SeafFPRecord *)source toRepo:(NSString *)repoId path:(NSString *)path
                                 parentUUID:(NSString *)parentUUID requestStartSeq:(long long)start serverTime:(long long)serverTime
{
    return [self confirmMoveOfRecord:source toRepo:repoId path:path parentUUID:parentUUID
                    requestStartSeq:start serverTime:serverTime requireRecovery:YES];
}

- (SeafFPRecord *)confirmMoveOfRecord:(SeafFPRecord *)source toRepo:(NSString *)repoId path:(NSString *)path
                           parentUUID:(NSString *)parentUUID requestStartSeq:(long long)start serverTime:(long long)serverTime
                     requireRecovery:(BOOL)requireRecovery
{
    if (start < source.seq || start < 0) return nil;
    NSString *destination = [SeafFPIdentifier normalizedPath:path];
    __block SeafFPRecord *result = nil;
    BOOL committed = [self performBatch:^{
        NSString *recoveryKey = SeafFPMoveRecoveryKey(source.uuid);
        NSDictionary *recovery = [self jsonMetaLocked:recoveryKey];
        if (!recovery || (requireRecovery && !recovery.count)) return;
        if (recovery.count && (![recovery[@"sourceRepo"] isEqual:source.repoId] || ![recovery[@"sourcePath"] isEqual:source.path]
            || [recovery[@"start"] longLongValue] != start || ![recovery[@"repo"] isEqual:repoId]
            || ![recovery[@"dir"] isEqual:destination.stringByDeletingLastPathComponent]
            || ![recovery[@"parent"] isEqual:parentUUID ?: @""])) return;
        if ([self destinationReservedLockedForRepo:repoId path:destination exceptUUID:source.uuid]) return;
        SeafFPRecord *current = [self recordLockedForUUID:source.uuid];
        if (!current.deleted && current.isDir == source.isDir && [current.repoId isEqual:repoId] && [current.path isEqual:destination]
            && SeafFPStringsEqual(current.parentUUID, parentUUID)) {
            result = current;
            if (recovery.count && ![self clearMoveLocked:recovery uuid:source.uuid]) self->_transactionFailed = YES;
            return;
        }
        BOOL detached = recovery.count && SeafFPRecordDetachedFromPath(current, source.path);
        if (![current.repoId isEqual:source.repoId] || (![current.path isEqual:source.path] && !detached)
            || current.isDir != source.isDir || (current.deleted && current.tombReason != SeafFPTombReasonAbsent)) return;
        BOOL sourceReused = current.oid.length && source.oid.length && ![current.oid isEqual:source.oid];
        // A lost receipt leaves the UUID at the source until reconciliation.
        // A newer listing may already describe a replacement there. Only the
        // pending-move recovery path, after proving the destination, may split
        // those two identities. Ordinary move confirmations stay conservative.
        if (sourceReused && (!requireRecovery || current.isDir || current.seq <= start
            || ![current.path isEqual:source.path]
            || ![recovery[@"oid"] isEqual:source.oid])) return;
        NSString *directory = destination.stringByDeletingLastPathComponent;
        if (parentUUID) {
            SeafFPRecord *parent = [self recordLockedForUUID:parentUUID];
            if (!parent.isDir || parent.deleted || ![parent.repoId isEqual:repoId] || ![parent.path isEqual:directory]) return;
        } else if (![directory isEqual:@"/"]) {
            return;
        }
        SeafFPRecord *occupant = [self recordLockedForRepo:repoId path:destination];
        BOOL formerDestination = requireRecovery && [self isFormerMoveDestinationLocked:occupant source:source
                                                                                recovery:recovery requestStartSeq:start];
        if (occupant && !occupant.deleted && !formerDestination
            && ![self isProvisionalDestinationOccupantLocked:occupant forMovedRecord:source requestStartSeq:start]) return;
        if (formerDestination && ![self detachRecordLocked:occupant reason:SeafFPTombReasonReplaced]) {
            self->_transactionFailed = YES;
            return;
        }
        if (sourceReused) {
            if (!current.deleted) {
                NSString *replacementOid = current.oid;
                long long replacementMtime = current.mtime, replacementSize = current.size;
                NSString *sourceParent = current.parentUUID;
                if (![self detachRecordLocked:current reason:SeafFPTombReasonAbsent]
                    || ![self upsertRecordLockedForRepo:source.repoId path:source.path isDir:NO parentUUID:sourceParent
                        oid:replacementOid mtime:replacementMtime size:replacementSize changed:NULL]) {
                    self->_transactionFailed = YES;
                    return;
                }
                current = [self recordLockedForUUID:source.uuid];
            }
            current.oid = source.oid;
            if (recovery[@"sourceMtime"]) current.mtime = [recovery[@"sourceMtime"] longLongValue];
            if (recovery[@"sourceSize"]) current.size = [recovery[@"sourceSize"] longLongValue];
        }
        current.confirmedPlacement = YES;
        current.placementTime = serverTime;
        current.hintRevivedFrom = 0;
        result = [self moveRecordLocked:current toRepo:repoId path:destination parentUUID:parentUUID
                        mergeDestination:YES detachedFromPath:(current.isDir && detached ? source.path : nil)];
        if (!result) self->_transactionFailed = YES;
        else if (recovery.count && ![self clearMoveLocked:recovery uuid:source.uuid]) self->_transactionFailed = YES;
    }];
    return committed ? result : nil;
}

- (NSString *)confirmedNameForRecord:(SeafFPRecord *)record
                             expected:(NSString *)expected
                               inRepo:(NSString *)repoId
                            directory:(NSString *)directoryPath
                              entries:(NSArray<NSDictionary *> *)entries
                      requestStartSeq:(long long)start
{
    __block NSString *name = nil;
    [self perform:^{
        name = [self finalNameForRecordLocked:record expected:expected inRepo:repoId directory:directoryPath
                                     entries:entries claimedNames:nil requestStartSeq:start];
    }];
    return name;
}

/// Resolves the actual filename on the server for a moved or renamed `record`
/// whose requested target name in `(repoId, dir)` is `expected`, given the
/// directory's current server `entries`. Returns nil when the target cannot be
/// determined unambiguously (never guesses).
- (nullable NSString *)finalNameForRecordLocked:(SeafFPRecord *)record
                                       expected:(NSString *)expected
                                         inRepo:(NSString *)repoId
                                      directory:(NSString *)dir
                                        entries:(NSArray<NSDictionary *> *)entries
                                   claimedNames:(nullable NSSet<NSString *> *)claimedNames
                                requestStartSeq:(long long)S
{
    if (!record || expected.length == 0 || [expected containsString:@"/"] || entries.count == 0) return nil;
    NSDictionary *recovery = record.uuid.length ? [self jsonMetaLocked:SeafFPMoveRecoveryKey(record.uuid)] : @{};
    if (!recovery) return nil;
    BOOL (^isClaimed)(NSString *) = ^BOOL(NSString *name) {
        for (NSString *claimed in claimedNames) {
            if (SeafFPNamesEqual(claimed, name)) return YES;
        }
        return NO;
    };
    BOOL (^other)(NSString *) = ^BOOL(NSString *name) {
        NSString *childPath = [SeafFPIdentifier normalizedPath:[dir stringByAppendingFormat:@"/%@", name]];
        SeafFPRecord *live = [self recordLockedForRepo:repoId path:childPath];
        if (!live || live.deleted || [live.uuid isEqualToString:record.uuid]) return NO;
        if ([self isProvisionalDestinationOccupantLocked:live forMovedRecord:record requestStartSeq:S]) return NO;
        if ([self isFormerMoveDestinationLocked:live source:record recovery:recovery requestStartSeq:S]) {
            for (NSDictionary *entry in entries) {
                if (SeafFPNamesEqual(SeafFPEntryString(entry, SeafFPEntryName), name)
                    && [SeafFPEntryString(entry, SeafFPEntryOid) isEqual:record.oid]
                    && [entry[SeafFPEntryIsDir] boolValue] == record.isDir) return NO;
            }
        }
        return YES;
    };
    BOOL (^fresh)(NSString *) = ^BOOL(NSString *name) {
        NSString *childPath = [SeafFPIdentifier normalizedPath:[dir stringByAppendingFormat:@"/%@", name]];
        SeafFPRecord *live = [self recordLockedForRepo:repoId path:childPath];
        if (!live || live.deleted) return YES;
        if (S >= 0 && live.createdSeq > S && ![live.uuid isEqualToString:record.uuid]) return YES;
        return NO;
    };

    // Only `expected` or a server conflict sibling ("name (1).ext") can be the
    // result of moving or renaming `expected`.
    NSMutableArray<NSDictionary *> *plausible = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
        NSString *name = SeafFPEntryString(entry, SeafFPEntryName);
        if (name.length == 0 || [name containsString:@"/"]) continue;
        BOOL isDir = [entry[SeafFPEntryIsDir] boolValue];
        if (isDir != record.isDir) continue;
        if (isClaimed(name)) continue;
        if (SeafFPNamesEqual(name, expected) || SeafFPIsConflictSiblingName(name, expected)) {
            [plausible addObject:entry];
        }
    }
    if (plausible.count == 0) return nil;

    BOOL hasOid = record.oid.length > 0;
    if (hasOid) {
        NSMutableArray<NSString *> *oidMatches = [NSMutableArray array];
        BOOL hasFreshWithoutOid = NO;
        for (NSDictionary *entry in plausible) {
            NSString *name = SeafFPEntryString(entry, SeafFPEntryName);
            if (other(name)) continue;
            NSString *entryOid = SeafFPEntryString(entry, SeafFPEntryOid);
            if (entryOid.length > 0) {
                if ([entryOid isEqualToString:record.oid]) {
                    [oidMatches addObject:name];
                }
            } else if (fresh(name)) {
                hasFreshWithoutOid = YES;
            }
        }
        if (oidMatches.count == 1 && !hasFreshWithoutOid) {
            return oidMatches[0];
        }
        if (oidMatches.count > 1) {
            // Multiple plausible entries share the same oid and are not owned by
            // another live record: cannot tell which was pre-existing without guessing.
            return nil;
        }
        // oidMatches.count == 0: fall through only for entries that carry no oid
        // (e.g. directories). Never match an entry whose non-empty oid differs.
    }

    NSString *expectedMatch = nil;
    NSMutableArray<NSString *> *freshConflictSiblings = [NSMutableArray array];
    BOOL hasAnyFreshConflictSibling = NO;
    for (NSDictionary *entry in plausible) {
        NSString *name = SeafFPEntryString(entry, SeafFPEntryName);
        NSString *entryOid = SeafFPEntryString(entry, SeafFPEntryOid);
        BOOL isSibling = SeafFPIsConflictSiblingName(name, expected);
        if (isSibling && fresh(name)) {
            hasAnyFreshConflictSibling = YES;
        }
        if (other(name)) continue;
        if (hasOid && entryOid.length > 0) continue;
        if (SeafFPNamesEqual(name, expected)) {
            expectedMatch = name;
        } else if (isSibling && fresh(name)) {
            [freshConflictSiblings addObject:name];
        }
    }
    if (expectedMatch) {
        // Without a distinguishing oid, if an unindexed conflict sibling ("name (1)")
        // also exists, do not guess whether `expected` or `expected (1)` is ours.
        return hasAnyFreshConflictSibling ? nil : expectedMatch;
    }
    if (freshConflictSiblings.count == 1) {
        return freshConflictSiblings[0];
    }
    return nil;
}

/// Read-only check that `dir` (normalized) and its ancestor chain have no
/// tombstones and no direct child or directory stamp newer than `S` (except
/// direct children in `allowedTombstonedPaths` that were tombstoned after `S`
/// when a source directory refresh completed before move confirmation, or
/// direct children matching `allowedDestinationEntries` when a destination
/// directory refresh completed before move confirmation).
- (BOOL)isDirectoryChainFreshLockedForRepo:(NSString *)repoId
                             directoryPath:(NSString *)dir
                           requestStartSeq:(long long)S
                    allowedTombstonedPaths:(nullable NSSet<NSString *> *)allowedTombstonedPaths
                 allowedDestinationEntries:(nullable NSArray<NSDictionary *> *)allowedDestinationEntries
{
    if (S < 0) return NO;
    BOOL isRoot = [dir isEqualToString:@"/"];
    NSMutableArray<SeafFPRecord *> *chain = [NSMutableArray array];
    SeafFPRecord *dirRecord = nil;
    for (NSString *path in SeafFPAncestorPaths(dir, YES)) {
        SeafFPRecord *record = [self recordLockedForRepo:repoId path:path];
        if (record.deleted) return NO;
        if (record && !record.isDir) return NO;
        if (record) [chain addObject:record];
        dirRecord = record;
    }
    if (isRoot || dirRecord) {
        NSString *parentUUID = isRoot ? nil : dirRecord.uuid;
        if (allowedDestinationEntries.count > 0) {
            NSMutableDictionary<NSString *, NSDictionary *> *dstEntryByPath = [NSMutableDictionary dictionaryWithCapacity:allowedDestinationEntries.count];
            for (NSDictionary *entry in allowedDestinationEntries) {
                NSString *entryName = SeafFPEntryString(entry, SeafFPEntryName);
                if (entryName.length == 0 || [entryName containsString:@"/"]) continue;
                NSString *entryPath = [SeafFPIdentifier normalizedPath:[dir stringByAppendingFormat:@"/%@", entryName]];
                dstEntryByPath[entryPath] = entry;
            }
            sqlite3_stmt *stmt = [self prepareLocked:@"SELECT path, is_dir, oid, deleted FROM identity WHERE repo_id = ?1 AND parent_uuid IS ?2 AND seq > ?3"];
            if (!stmt) return NO;
            SeafFPBindText(stmt, 1, repoId);
            SeafFPBindText(stmt, 2, parentUUID);
            sqlite3_bind_int64(stmt, 3, S);
            BOOL conflict = NO;
            while ([self stepLocked:stmt] == SQLITE_ROW) {
                NSString *childPath = SeafFPColumnText(stmt, 0);
                BOOL childIsDir = sqlite3_column_int(stmt, 1) != 0;
                NSString *childOid = SeafFPColumnText(stmt, 2);
                BOOL deleted = sqlite3_column_int(stmt, 3) != 0;
                if (deleted) {
                    if (![allowedTombstonedPaths containsObject:childPath]) {
                        conflict = YES;
                        break;
                    }
                    continue;
                }
                NSDictionary *dstEntry = dstEntryByPath[childPath];
                if (!dstEntry) {
                    conflict = YES;
                    break;
                }
                BOOL entryIsDir = [dstEntry[SeafFPEntryIsDir] boolValue];
                NSString *entryOid = SeafFPEntryString(dstEntry, SeafFPEntryOid);
                if (childIsDir != entryIsDir || (entryOid.length > 0 && childOid.length > 0 && ![entryOid isEqualToString:childOid])) {
                    conflict = YES;
                    break;
                }
            }
            sqlite3_finalize(stmt);
            if (conflict) return NO;
        } else if (allowedTombstonedPaths.count > 0) {
            sqlite3_stmt *stmt = [self prepareLocked:@"SELECT path, deleted FROM identity WHERE repo_id = ?1 AND parent_uuid IS ?2 AND seq > ?3"];
            if (!stmt) return NO;
            SeafFPBindText(stmt, 1, repoId);
            SeafFPBindText(stmt, 2, parentUUID);
            sqlite3_bind_int64(stmt, 3, S);
            BOOL conflict = NO;
            while ([self stepLocked:stmt] == SQLITE_ROW) {
                NSString *childPath = SeafFPColumnText(stmt, 0);
                BOOL deleted = sqlite3_column_int(stmt, 1) != 0;
                if ([allowedTombstonedPaths containsObject:childPath] && !deleted) {
                    conflict = YES;
                    break;
                }
            }
            sqlite3_finalize(stmt);
            if (conflict) return NO;
        } else if ([self hasChildLockedOfRepo:repoId parentUUID:parentUUID changedAfter:S]) {
            return NO;
        }
    }
    if ([self dirStampLockedForRepo:repoId parentUUID:nil] > S) {
        return NO;
    }
    for (SeafFPRecord *record in chain) {
        if ([self dirStampLockedForRepo:repoId parentUUID:record.uuid] > S) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)isDirectoryChainFreshLockedForRepo:(NSString *)repoId
                             directoryPath:(NSString *)dir
                           requestStartSeq:(long long)S
                    allowedTombstonedPaths:(nullable NSSet<NSString *> *)allowedTombstonedPaths
{
    return [self isDirectoryChainFreshLockedForRepo:repoId
                                      directoryPath:dir
                                    requestStartSeq:S
                             allowedTombstonedPaths:allowedTombstonedPaths
                          allowedDestinationEntries:nil];
}

- (BOOL)isDirectoryChainFreshLockedForRepo:(NSString *)repoId
                             directoryPath:(NSString *)dir
                           requestStartSeq:(long long)S
{
    return [self isDirectoryChainFreshLockedForRepo:repoId
                                      directoryPath:dir
                                    requestStartSeq:S
                             allowedTombstonedPaths:nil
                          allowedDestinationEntries:nil];
}

/// A destination browse may have learnt children the source never enumerated.
/// Keep those UUIDs and reparent them to the confirmed directory. When both
/// sides knew a child, the source UUID wins and inherits destination metadata
/// and any decorations it did not already have.
- (BOOL)adoptProvisionalChildrenLocked:(NSArray<SeafFPRecord *> *)children
                              intoRepo:(NSString *)repoId
{
    NSArray<SeafFPRecord *> *ordered = [children sortedArrayUsingComparator:^NSComparisonResult(SeafFPRecord *a, SeafFPRecord *b) {
        if (a.path.length == b.path.length) return [a.path compare:b.path];
        return a.path.length < b.path.length ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (SeafFPRecord *child in ordered) {
        if (child.deleted) continue;
        SeafFPRecord *parent = [self recordLockedForRepo:repoId path:child.directoryPath];
        if (!parent || parent.deleted || !parent.isDir) return NO;
        BOOL changed = NO;
        SeafFPRecord *adopted = [self upsertRecordLockedForRepo:repoId path:child.path isDir:child.isDir
                                                   parentUUID:parent.uuid oid:child.oid mtime:child.mtime size:child.size changed:&changed];
        if (!adopted) return NO;
        if ([adopted.uuid isEqualToString:child.uuid]) continue;
        if (![self mergeDecorationsLockedFrom:child into:adopted]) return NO;
    }
    return YES;
}

/// `from` loses its identity to `into`: favorite, tags and working set
/// membership move over where `into` has none of its own.
- (BOOL)mergeDecorationsLockedFrom:(SeafFPRecord *)from into:(SeafFPRecord *)into
{
    SeafFPDecoration *source = [self decorationLockedForItem:from.itemIdentifier];
    if (source) {
        SeafFPDecoration *to = [self decorationLockedForItem:into.itemIdentifier] ?: [SeafFPDecoration new];
        to.itemIdentifier = into.itemIdentifier;
        if (!to.favoriteRank) to.favoriteRank = source.favoriteRank;
        if (to.tagData.length == 0) to.tagData = source.tagData;
        if (source.lastUsedDate && (!to.lastUsedDate || [to.lastUsedDate compare:source.lastUsedDate] == NSOrderedAscending)) {
            to.lastUsedDate = source.lastUsedDate;
        }
        if (![self setDecorationLocked:to]) return NO;
        [self removeDecorationForItem:from.itemIdentifier];
    }
    SeafFPWorkingSetReason reason = [self workingSetReasonLockedForItem:from.itemIdentifier];
    if (reason != 0) {
        [self addWorkingSetItem:into.itemIdentifier reason:reason];
        [self writeWorkingSetLockedItem:from.itemIdentifier reason:0];
    }
    return [self transactionHealthyLocked];
}

- (BOOL)moveRecordsOfRepo:(NSString *)srcRepoId
            fromDirectory:(NSString *)srcDirectoryPath
                    names:(NSArray<NSString *> *)names
                   toRepo:(NSString *)dstRepoId
              toDirectory:(NSString *)dstDirectoryPath
       destinationEntries:(NSArray<NSDictionary *> *)destinationEntries
          requestStartSeq:(long long)requestStartSeq
{
    return [self relocateRecordsOfRepo:srcRepoId fromDirectory:srcDirectoryPath names:names
                               toRepo:dstRepoId toDirectory:dstDirectoryPath
                     destinationNames:nil destinationEntries:destinationEntries requestStartSeq:requestStartSeq];
}

/// Shared move/rename confirmation so both operations reconcile source
/// tombstones and provisional destination rows created by an earlier refresh.
- (BOOL)relocateRecordsOfRepo:(NSString *)srcRepoId
               fromDirectory:(NSString *)srcDirectoryPath
                       names:(NSArray<NSString *> *)names
                      toRepo:(NSString *)dstRepoId
                 toDirectory:(NSString *)dstDirectoryPath
            destinationNames:(nullable NSDictionary<NSString *, NSString *> *)destinationNames
          destinationEntries:(NSArray<NSDictionary *> *)destinationEntries
             requestStartSeq:(long long)requestStartSeq
{
    if (srcRepoId.length == 0 || dstRepoId.length == 0 || names.count == 0
        || destinationEntries.count == 0 || requestStartSeq < 0) {
        return NO;
    }
    NSString *srcDir = [SeafFPIdentifier normalizedPath:srcDirectoryPath];
    NSString *dstDir = [SeafFPIdentifier normalizedPath:dstDirectoryPath];
    long long S = requestStartSeq;
    NSMutableSet<NSString *> *movingPaths = [NSMutableSet setWithCapacity:names.count];
    for (NSString *name in names) {
        if (name.length == 0 || [name containsString:@"/"]) continue;
        [movingPaths addObject:[SeafFPIdentifier normalizedPath:[srcDir stringByAppendingFormat:@"/%@", name]]];
    }
    return [self performIndexWrite:^BOOL(BOOL *rollback) {
        // 1. Read-only conflict check against changes after requestStartSeq.
        //    A source directory refresh that finished while destination confirmation
        //    was in flight may have already tombstoned the moved entries at seq > S;
        //    a destination directory refresh may have inserted provisional rows for
        //    destinationEntries at seq > S. Both are reconciled so moved UUIDs survive.
        BOOL sameDirectory = [srcRepoId isEqualToString:dstRepoId] && [srcDir isEqualToString:dstDir];
        NSArray<NSDictionary *> *sameDirectoryEntries = destinationEntries;
        if (sameDirectory && destinationNames.count > 0) {
            NSMutableArray<NSDictionary *> *renameTargets = [NSMutableArray array];
            for (NSDictionary *entry in destinationEntries) {
                NSString *candidate = SeafFPEntryString(entry, SeafFPEntryName);
                for (NSString *expected in destinationNames.allValues) {
                    if (SeafFPNamesEqual(candidate, expected) || SeafFPIsConflictSiblingName(candidate, expected)) {
                        [renameTargets addObject:entry];
                        break;
                    }
                }
            }
            sameDirectoryEntries = renameTargets;
        }
        if (![self isDirectoryChainFreshLockedForRepo:srcRepoId directoryPath:srcDir requestStartSeq:S allowedTombstonedPaths:movingPaths allowedDestinationEntries:(sameDirectory ? sameDirectoryEntries : nil)]
            || (!sameDirectory && ![self isDirectoryChainFreshLockedForRepo:dstRepoId directoryPath:dstDir requestStartSeq:S allowedTombstonedPaths:nil allowedDestinationEntries:destinationEntries])) {
            *rollback = YES;
            return NO;
        }
        for (NSString *name in names) {
            if (name.length == 0 || [name containsString:@"/"]) continue;
            NSString *srcPath = [SeafFPIdentifier normalizedPath:[srcDir stringByAppendingFormat:@"/%@", name]];
            SeafFPRecord *record = [self recordLockedForRepo:srcRepoId path:srcPath];
            if (!record) continue;
            if (!record.deleted) {
                if (record.seq > S || (record.isDir && [self hasSubtreeRecordLockedOf:record changedAfter:S])) {
                    *rollback = YES;
                    return NO;
                }
            } else if (record.seq > S && record.isDir) {
                for (SeafFPRecord *sub in [self subtreeRecordsLockedOf:record]) {
                    if (!sub.deleted || (sub.seq > S && sub.seq < record.seq)) {
                        *rollback = YES;
                        return NO;
                    }
                }
            }
        }

        // 2. Ensure destination directory chain.
        BOOL changed = NO;
        NSString *dstParentUUID = nil;
        if (![self ensureDirectoryLockedForRepo:dstRepoId path:dstDir allowRevive:NO uuid:&dstParentUUID changed:&changed]) {
            *rollback = YES;
            return NO;
        }

        // 3. Move records whose destination name in destinationEntries is confirmed.
        BOOL movedAny = NO;
        NSMutableSet<NSString *> *claimedNames = [NSMutableSet set];
        for (NSString *name in names) {
            if (name.length == 0 || [name containsString:@"/"]) continue;
            NSString *srcPath = [SeafFPIdentifier normalizedPath:[srcDir stringByAppendingFormat:@"/%@", name]];
            SeafFPRecord *record = [self recordLockedForRepo:srcRepoId path:srcPath];
            if (!record || (record.deleted && record.seq <= S)) continue;
            NSString *finalName = [self finalNameForRecordLocked:record
                                                        expected:(destinationNames[name] ?: name)
                                                          inRepo:dstRepoId
                                                       directory:dstDir
                                                         entries:destinationEntries
                                                    claimedNames:claimedNames
                                                 requestStartSeq:S];
            if (finalName.length == 0) continue;
            NSString *dstPath = [SeafFPIdentifier normalizedPath:[dstDir stringByAppendingFormat:@"/%@", finalName]];
            if ([srcRepoId isEqualToString:dstRepoId] && [srcPath isEqualToString:dstPath]) continue;
            if ([self destinationReservedLockedForRepo:dstRepoId path:dstPath exceptUUID:record.uuid]) continue;
            SeafFPRecord *occupant = [self recordLockedForRepo:dstRepoId path:dstPath];
            if (occupant && !occupant.deleted && ![occupant.uuid isEqualToString:record.uuid]
                && ![self isProvisionalDestinationOccupantLocked:occupant forMovedRecord:record requestStartSeq:S]) {
                continue;
            }
            record.confirmedPlacement = YES;
            record.placementTime = 0;
            record.hintRevivedFrom = 0;
            SeafFPRecord *moved = [self moveRecordLocked:record toRepo:dstRepoId path:dstPath parentUUID:dstParentUUID
                                        mergeDestination:YES detachedFromPath:nil];
            if (!moved) {
                *rollback = YES;
                return NO;
            }
            [claimedNames addObject:finalName];
            movedAny = YES;
            changed = YES;
        }
        if (!movedAny) {
            *rollback = YES;
            return NO;
        }

        // 4. Upsert destinationEntries so pre-existing unindexed siblings (e.g. a
        //    file that caused the server to rename ours to "name (1)") get their
        //    own UUIDs and moved records get updated metadata.
        for (NSDictionary *entry in destinationEntries) {
            NSString *entryName = SeafFPEntryString(entry, SeafFPEntryName);
            if (entryName.length == 0 || [entryName containsString:@"/"]) continue;
            NSString *childPath = [SeafFPIdentifier normalizedPath:[dstDir stringByAppendingFormat:@"/%@", entryName]];
            BOOL isDir = [entry[SeafFPEntryIsDir] boolValue];
            if (![self upsertRecordLockedForRepo:dstRepoId
                                            path:childPath
                                           isDir:isDir
                                      parentUUID:dstParentUUID
                                             oid:SeafFPEntryString(entry, SeafFPEntryOid)
                                           mtime:SeafFPEntryNumber(entry, SeafFPEntryMtime, 0)
                                            size:(isDir ? -1 : SeafFPEntryNumber(entry, SeafFPEntrySize, -1))
                                         changed:&changed]) {
                *rollback = YES;
                return NO;
            }
        }
        return changed;
    }];
}

- (BOOL)renameRecordOfRepo:(NSString *)repoId
                 directory:(NSString *)directoryPath
                  fromName:(NSString *)oldName
                    toName:(NSString *)newName
                   listing:(NSArray<NSDictionary *> *)entries
           requestStartSeq:(long long)requestStartSeq
{
    if (oldName.length == 0 || newName.length == 0 || [newName containsString:@"/"]
        || [oldName isEqualToString:newName]) return NO;
    return [self relocateRecordsOfRepo:repoId fromDirectory:directoryPath names:@[oldName]
                               toRepo:repoId toDirectory:directoryPath
                     destinationNames:@{oldName: newName} destinationEntries:entries requestStartSeq:requestStartSeq];
}

#pragma mark - Activity clues

static NSString * const kMetaActivityProgress = @"fp_activity_progress_v1";
/// Seen activities are kept this long behind the collection boundary (the
/// overlap a later scan re-reads is much shorter).
static const long long kActivitySeenRetention = 24 * 3600;
// Replacement evidence must survive the initial week's scan and the next
// day's rename verification even though duplicate-event hashes expire sooner.
static const long long kPathReplacementRetention = 8 * 24 * 3600;

- (nullable NSDictionary *)activityProgress
{
    __block NSDictionary *progress = nil;
    [self perform:^{ progress = [self jsonMetaLocked:kMetaActivityProgress]; }];
    return progress;
}

/// The checks and the rename hint one activity entry asks for. `requested`
/// holds the directories already asked for by the same page: their version
/// moves once per page.
- (BOOL)recordActivityEntryLocked:(NSDictionary *)entry requested:(NSMutableSet<NSString *> *)requested
{
    NSString *repoId = SeafFPEntryString(entry, SeafFPEntryRepoId);
    NSString *op = SeafFPEntryString(entry, SeafFPEntryOp);
    NSString *path = [SeafFPIdentifier normalizedPath:SeafFPEntryString(entry, SeafFPEntryPath)];
    if (repoId.length == 0 || !op || [path isEqualToString:@"/"]) return YES;
    long long eventTime = SeafFPEntryNumber(entry, SeafFPEntryMtime, 0);
    if (eventTime > 0 && ([op isEqual:SeafFPActivityOpCreate] || [op isEqual:SeafFPActivityOpDelete])) {
        sqlite3_stmt *stmt = [self prepareLocked:
            @"INSERT INTO fp_path_replacement(repo_id,path,event_time) VALUES(?,?,?) "
             "ON CONFLICT(repo_id,path) DO UPDATE SET event_time = MAX(event_time, excluded.event_time)"];
        if (!stmt) return NO;
        SeafFPBindText(stmt, 1, repoId);
        SeafFPBindText(stmt, 2, path);
        sqlite3_bind_int64(stmt, 3, eventTime);
        int rc = [self stepLocked:stmt];
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) return NO;
    }
    BOOL (^check)(NSString *) = ^BOOL(NSString *dir) {
        NSString *key = [NSString stringWithFormat:@"%@\n%@", repoId, dir];
        if ([requested containsObject:key]) return YES;
        [requested addObject:key];
        return [self requestDirectoryCheckLockedForRepo:repoId path:dir];
    };
    if ([op isEqualToString:SeafFPActivityOpDelete]) {
        // Only a fresh listing deletes. The event's time cannot tell whether
        // the row is what was deleted: the path may have been uploaded again,
        // moved into from another library, or be one item of an aggregated
        // batch whose time is that of its newest member.
        SeafFPRecord *record = [self recordLockedForRepo:repoId path:path];
        if (!record || record.deleted) return [self transactionHealthyLocked];
        return check(record.directoryPath);
    }
    NSString *rawOld = SeafFPEntryString(entry, SeafFPEntryOldPath);
    NSString *oldPath = rawOld ? [SeafFPIdentifier normalizedPath:rawOld] : nil;
    if ([op isEqualToString:SeafFPActivityOpMove] && oldPath && ![oldPath isEqualToString:@"/"] && ![oldPath isEqualToString:path]) {
        long long version = [self nextSeqLocked];
        if (version <= 0) return NO;
        sqlite3_stmt *stmt = [self prepareLocked:@"INSERT OR IGNORE INTO fp_hint(repo_id, old_path, new_path, is_dir, event_time, event_hash, version) VALUES(?,?,?,?,?,?,?)"];
        if (!stmt) return NO;
        SeafFPBindText(stmt, 1, repoId);
        SeafFPBindText(stmt, 2, oldPath);
        SeafFPBindText(stmt, 3, path);
        sqlite3_bind_int(stmt, 4, [entry[SeafFPEntryIsDir] boolValue] ? 1 : 0);
        sqlite3_bind_int64(stmt, 5, SeafFPEntryNumber(entry, SeafFPEntryMtime, 0));
        SeafFPBindText(stmt, 6, SeafFPEntryString(entry, SeafFPEntryActivityHash)
                       ?: [NSString stringWithFormat:@"move|%@|%@|%@|%lld", repoId, oldPath, path, SeafFPEntryNumber(entry, SeafFPEntryMtime, 0)]);
        sqlite3_bind_int64(stmt, 7, version);
        int rc = [self stepLocked:stmt];
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) return NO;
        // A cached listing from before the rename must not bring the old path back.
        if (![self setMetaValueLocked:[NSString stringWithFormat:@"%lld", version] forKey:[self departedPathKeyForRepo:repoId path:oldPath]]) return NO;
        return check(oldPath.stringByDeletingLastPathComponent) && check(path.stringByDeletingLastPathComponent);
    }
    // create, edit, restore, publish -- and a rename that came without its old path
    return check(path.stringByDeletingLastPathComponent);
}

- (SeafFPWriteResult)recordActivityEntries:(NSArray<NSDictionary *> *)entries progress:(nullable NSDictionary *)progress
{
    return [self performWrite:^BOOL(BOOL *rollback) {
        NSMutableSet<NSString *> *requested = [NSMutableSet set];
        NSMutableDictionary<NSString *, NSNumber *> *isNew = [NSMutableDictionary dictionary];
        BOOL recorded = NO;
        for (NSDictionary *entry in entries) {
            NSString *hash = SeafFPEntryString(entry, SeafFPEntryActivityHash);
            if (hash) {
                NSNumber *fresh = isNew[hash];
                if (!fresh) {
                    sqlite3_stmt *stmt = [self prepareLocked:@"INSERT OR IGNORE INTO fp_activity_seen(hash, event_time) VALUES(?, ?)"];
                    if (!stmt) { *rollback = YES; return NO; }
                    SeafFPBindText(stmt, 1, hash);
                    sqlite3_bind_int64(stmt, 2, SeafFPEntryNumber(entry, SeafFPEntryMtime, 0));
                    int rc = [self stepLocked:stmt];
                    sqlite3_finalize(stmt);
                    if (rc != SQLITE_DONE) { *rollback = YES; return NO; }
                    // One row inserted: never seen before.
                    fresh = isNew[hash] = @(sqlite3_changes(self->_db) > 0);
                }
                if (!fresh.boolValue) continue;
            }
            if (![self recordActivityEntryLocked:entry requested:requested]) { *rollback = YES; return NO; }
            recorded = YES;
        }
        if (progress) {
            if (![self writeJSONMetaLocked:progress key:kMetaActivityProgress]) { *rollback = YES; return NO; }
            long long boundary = [progress[@"boundary"] longLongValue];
            if (boundary > kActivitySeenRetention) {
                NSDictionary<NSString *, NSNumber *> *retention = @{
                    @"DELETE FROM fp_activity_seen WHERE event_time < ?": @(kActivitySeenRetention),
                    @"DELETE FROM fp_path_replacement WHERE event_time < ?": @(kPathReplacementRetention),
                };
                for (NSString *sql in retention) {
                    sqlite3_stmt *stmt = [self prepareLocked:sql];
                    if (!stmt) { *rollback = YES; return NO; }
                    sqlite3_bind_int64(stmt, 1, boundary - retention[sql].longLongValue);
                    int rc = [self stepLocked:stmt];
                    sqlite3_finalize(stmt);
                    if (rc != SQLITE_DONE) { *rollback = YES; return NO; }
                }
            }
        }
        return recorded;
    } requestSignal:NO];
}

- (BOOL)applyActivitiesOfRepo:(NSString *)repoId entries:(NSArray<NSDictionary *> *)entries
{
    if (repoId.length == 0 || entries.count == 0) return NO;
    NSMutableArray<NSDictionary *> *tagged = [NSMutableArray arrayWithCapacity:entries.count];
    for (NSDictionary *entry in entries) {
        NSMutableDictionary *copy = [entry mutableCopy];
        copy[SeafFPEntryRepoId] = repoId;
        if (!copy[SeafFPEntryActivityHash]) {
            copy[SeafFPEntryActivityHash] = [NSString stringWithFormat:@"%@|%@|%d|%lld|%@|%@", repoId, SeafFPEntryString(entry, SeafFPEntryOp) ?: @"",
                                             [entry[SeafFPEntryIsDir] boolValue] ? 1 : 0, SeafFPEntryNumber(entry, SeafFPEntryMtime, 0),
                                             SeafFPEntryString(entry, SeafFPEntryPath) ?: @"", SeafFPEntryString(entry, SeafFPEntryOldPath) ?: @""];
        }
        [tagged addObject:copy];
    }
    return [self recordActivityEntries:tagged progress:nil] == SeafFPWriteChanged;
}

#pragma mark - Rename hints

typedef NS_ENUM(NSInteger, SeafFPHintState) {
    SeafFPHintOpen = 0,        // collected, not decided yet
    SeafFPHintVerifying = 1,   // decided; listings may still correct it
    SeafFPHintAwaitingListing = 2, // an explicit move placed this file at old_path
};
/// How long listings may still correct a decided hint.
static const NSTimeInterval kHintVerificationWindow = 24 * 3600;
/// Event times are whole seconds; a row that is newer than this is a later entry.
static const long long kHintTimeSlack = 2;
static NSString * const kRenameHintSelect =
    @"SELECT id, repo_id, old_path, new_path, is_dir, event_time, version, decided_seq, state, source_uuid, source_oid, first_event_time FROM fp_hint";

- (NSUInteger)pendingRenameHintCount
{
    __block NSUInteger count = 0;
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:@"SELECT COUNT(*) FROM fp_hint WHERE state = 0"];
        if (!stmt) return;
        if ([self stepLocked:stmt] == SQLITE_ROW) count = (NSUInteger)sqlite3_column_int64(stmt, 0);
        sqlite3_finalize(stmt);
    }];
    return count;
}

- (nullable NSArray<NSDictionary *> *)renameHintsLockedWithSQL:(NSString *)sql binder:(void (^)(sqlite3_stmt *stmt))binder
{
    sqlite3_stmt *stmt = [self prepareLocked:sql];
    if (!stmt) return nil;
    if (binder) binder(stmt);
    NSMutableArray<NSDictionary *> *hints = [NSMutableArray array];
    int rc;
    while ((rc = [self stepLocked:stmt]) == SQLITE_ROW) {
        [hints addObject:@{@"id": @(sqlite3_column_int64(stmt, 0)), @"repo": SeafFPColumnText(stmt, 1) ?: @"",
                           @"old": SeafFPColumnText(stmt, 2) ?: @"/", @"new": SeafFPColumnText(stmt, 3) ?: @"/",
                           @"isDir": @(sqlite3_column_int(stmt, 4) != 0), @"time": @(sqlite3_column_int64(stmt, 5)),
                           @"version": @(sqlite3_column_int64(stmt, 6)), @"decided": @(sqlite3_column_int64(stmt, 7)),
                           @"state": @(sqlite3_column_int(stmt, 8)), @"uuid": SeafFPColumnText(stmt, 9) ?: @"",
                           @"oid": SeafFPColumnText(stmt, 10) ?: @"", @"firstTime": @(sqlite3_column_int64(stmt, 11))}];
    }
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? hints : nil;
}

/// The next hint of a group sharing one second to decide, judged by what the
/// store holds now: a hint whose old path is still empty waits for the one
/// that moves something there (A -> B, B -> C of one item), and a hint whose
/// target is taken waits for the one that moves the occupant away (B -> C,
/// then A -> B of two items). A cycle cannot come from one file system; then
/// the log's order is kept and occupied targets fail as conflicts.
- (NSUInteger)nextSameSecondHintLockedIn:(NSArray<NSDictionary *> *)group
{
    for (NSUInteger k = 0; k < group.count; k++) {
        NSDictionary *hint = group[k];
        SeafFPRecord *source = [self recordLockedForRepo:hint[@"repo"] path:hint[@"old"]];
        BOOL hasSource = source && (!source.deleted || source.tombReason == SeafFPTombReasonAbsent);
        SeafFPRecord *target = [self recordLockedForRepo:hint[@"repo"] path:hint[@"new"]];
        BOOL occupied = target && !target.deleted;
        BOOL waits = NO;
        for (NSDictionary *other in group) {
            if (other == hint) continue;
            if (!hasSource && [other[@"new"] isEqual:hint[@"old"]]) waits = YES;
            if (occupied && [other[@"old"] isEqual:hint[@"new"]]) waits = YES;
        }
        if (!waits) return k;
    }
    return 0;
}

/// YES when the live row at a rename's target is the renamed item under an
/// identity a listing gave it: it was created after the hint was collected,
/// or by the listing that judged the renamed record absent (or later).
/// tombTxn also covers a record an earlier hint revived along a rename chain.
- (BOOL)isProvisionalRenameOccupantLocked:(SeafFPRecord *)occupant forRecord:(SeafFPRecord *)record
                              hintVersion:(long long)version tombTxn:(long long)tombTxn
{
    if (occupant.isDir != record.isDir || occupant.confirmedPlacement) return NO;
    if (!record.isDir && record.oid.length && occupant.oid.length && ![record.oid isEqual:occupant.oid]) return NO;
    if (occupant.createdSeq > version) return YES;
    return tombTxn > 0 && occupant.createdSeq > tombTxn;
}

- (BOOL)closeRenameHintLocked:(NSDictionary *)hint
{
    sqlite3_stmt *stmt = [self prepareLocked:@"DELETE FROM fp_hint WHERE id = ?"];
    if (!stmt) return NO;
    sqlite3_bind_int64(stmt, 1, [hint[@"id"] longLongValue]);
    int rc = [self stepLocked:stmt];
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE;
}

- (BOOL)saveRenameHintLocked:(NSDictionary *)hint state:(SeafFPHintState)state record:(SeafFPRecord *)record
{
    sqlite3_stmt *stmt = [self prepareLocked:@"UPDATE fp_hint SET state = ?, decided_seq = ?, close_after = ?, source_uuid = ?, source_oid = ?, first_event_time = ? WHERE id = ?"];
    if (!stmt) return NO;
    sqlite3_bind_int(stmt, 1, (int)state);
    sqlite3_bind_int64(stmt, 2, [self currentSeqLocked]);
    sqlite3_bind_double(stmt, 3, [NSDate date].timeIntervalSince1970 + kHintVerificationWindow);
    SeafFPBindText(stmt, 4, state == SeafFPHintAwaitingListing ? record.uuid : nil);
    SeafFPBindText(stmt, 5, state == SeafFPHintAwaitingListing ? record.oid : nil);
    sqlite3_bind_int64(stmt, 6, [hint[@"time"] longLongValue]);
    sqlite3_bind_int64(stmt, 7, [hint[@"id"] longLongValue]);
    int rc = [self stepLocked:stmt];
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE;
}

/// Keep a deferred source tied to the end of its chain when the intermediate
/// path was never indexed. Only one predecessor can provide this identity.
- (BOOL)advanceAwaitingRenameLockedWithHint:(NSDictionary *)hint
{
    NSArray<NSDictionary *> *predecessors = [self renameHintsLockedWithSQL:[kRenameHintSelect stringByAppendingString:
        @" WHERE state = 2 AND repo_id = ? AND new_path = ? AND event_time <= ? AND close_after >= ? LIMIT 2"] binder:^(sqlite3_stmt *stmt) {
        SeafFPBindText(stmt, 1, hint[@"repo"]);
        SeafFPBindText(stmt, 2, hint[@"old"]);
        sqlite3_bind_int64(stmt, 3, [hint[@"time"] longLongValue]);
        sqlite3_bind_double(stmt, 4, [NSDate date].timeIntervalSince1970);
    }];
    if (!predecessors) return NO;
    NSDictionary *predecessor = predecessors.firstObject;
    if (predecessors.count != 1 || [predecessor[@"old"] isEqual:hint[@"new"]]) return [self closeRenameHintLocked:hint];
    sqlite3_stmt *stmt = [self prepareLocked:@"UPDATE fp_hint SET new_path = ?, event_time = ?, decided_seq = ? WHERE id = ?"];
    if (!stmt) return NO;
    SeafFPBindText(stmt, 1, hint[@"new"]);
    sqlite3_bind_int64(stmt, 2, [hint[@"time"] longLongValue]);
    sqlite3_bind_int64(stmt, 3, [self currentSeqLocked]);
    sqlite3_bind_int64(stmt, 4, [predecessor[@"id"] longLongValue]);
    int rc = [self stepLocked:stmt];
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) return NO;
    return [self closeRenameHintLocked:hint]
        && [self requestDirectoryCheckLockedForRepo:hint[@"repo"] path:[predecessor[@"old"] stringByDeletingLastPathComponent]]
        && [self requestDirectoryCheckLockedForRepo:hint[@"repo"] path:[hint[@"new"] stringByDeletingLastPathComponent]];
}

/// Decides one rename. An activity for an explicitly placed file first needs
/// evidence that the file left that path, since the event may predate it.
- (BOOL)decideRenameHintLocked:(NSDictionary *)hint changed:(BOOL *)changed
{
    NSString *repoId = hint[@"repo"], *oldPath = hint[@"old"], *newPath = hint[@"new"];
    long long eventTime = [hint[@"time"] longLongValue], version = [hint[@"version"] longLongValue];
    NSString *boundUUID = hint[@"uuid"];
    SeafFPRecord *record = boundUUID.length ? [self recordLockedForUUID:boundUUID] : [self recordLockedForRepo:repoId path:oldPath];
    if (boundUUID.length && (![record.repoId isEqual:repoId] || !SeafFPRecordDetachedFromPath(record, oldPath))) {
        return [self closeRenameHintLocked:hint];
    }
    if (![self transactionHealthyLocked]) return NO;
    if (!record && ![hint[@"isDir"] boolValue]) return [self advanceAwaitingRenameLockedWithHint:hint];
    // Only a live row, or one a listing judged absent, can be what moved.
    if (!record || record.isDir != [hint[@"isDir"] boolValue] || (record.deleted && record.tombReason != SeafFPTombReasonAbsent)) {
        return [self closeRenameHintLocked:hint];
    }
    NSDictionary *localMove = [self jsonMetaLocked:SeafFPMoveRecoveryKey(record.uuid)];
    if (!localMove) return NO;
    if ([localMove[@"sourceRepo"] isEqual:repoId] && [localMove[@"sourcePath"] isEqual:oldPath]) {
        // The confirmed server operation owns recovery for this source.
        return [self closeRenameHintLocked:hint];
    }
    if (eventTime > 0 && record.placementTime > eventTime && record.placementTime - eventTime > kHintTimeSlack) {
        return [self closeRenameHintLocked:hint];
    }
    // A live directory the server showed as modified after the rename is a
    // later entry at the old path, not the one that moved. (A directory's
    // mtime is the server's; a file's comes from the uploading client.)
    if (!record.deleted && record.isDir && eventTime > 0 && record.mtime > eventTime + kHintTimeSlack) return [self closeRenameHintLocked:hint];
    SeafFPRecord *occupant = [self recordLockedForRepo:repoId path:newPath];
    if ([self destinationReservedLockedForRepo:repoId path:newPath exceptUUID:record.uuid]) return [self closeRenameHintLocked:hint];
    BOOL absentWithEditedTarget = record.deleted && !occupant.deleted && occupant.oid.length
        && ![record.oid isEqual:occupant.oid] && record.tombTxn >= version;
    if (!record.isDir && record.confirmedPlacement && (!record.deleted || absentWithEditedTarget)) {
        return [self saveRenameHintLocked:hint state:SeafFPHintAwaitingListing record:record]
            && [self requestDirectoryCheckLockedForRepo:repoId path:record.directoryPath]
            && [self requestDirectoryCheckLockedForRepo:repoId path:newPath.stringByDeletingLastPathComponent];
    }
    long long tombTxn = record.deleted ? record.tombTxn : 0;
    BOOL carriedRecovery = record.hintRevivedFrom > 0 && version <= record.hintRevivedAt;
    if (carriedRecovery) tombTxn = record.deleted ? MIN(tombTxn, record.hintRevivedFrom) : record.hintRevivedFrom;
    if (occupant && !occupant.deleted && ![occupant.uuid isEqualToString:record.uuid]) {
        if (![self isProvisionalRenameOccupantLocked:occupant forRecord:record hintVersion:version tombTxn:tombTxn]) {
            return [self closeRenameHintLocked:hint];
        }
    }
    // The target's directory existed when the rename happened. A listing may
    // have judged it absent since (renamed on itself later: a later hint
    // carries it on, or really gone: the checks below find out); a row
    // deleted on this device or a file in the chain ends the hint.
    NSString *targetDir = newPath.stringByDeletingLastPathComponent;
    NSMutableArray<SeafFPRecord *> *revivedAncestors = [NSMutableArray array];
    for (NSString *path in SeafFPAncestorPaths(targetDir, YES)) {
        SeafFPRecord *ancestor = [self recordLockedForRepo:repoId path:path];
        if ((ancestor.deleted && ancestor.tombReason != SeafFPTombReasonAbsent)
            || (ancestor && !ancestor.deleted && !ancestor.isDir)) return [self closeRenameHintLocked:hint];
        if (ancestor.deleted) [revivedAncestors addObject:ancestor];
    }
    if (![self transactionHealthyLocked]) return NO;
    NSString *parentUUID = nil;
    BOOL dirChanged = NO;
    if (![self ensureDirectoryLockedForRepo:repoId path:targetDir allowRevive:YES uuid:&parentUUID changed:&dirChanged]) return NO;
    for (SeafFPRecord *ancestor in revivedAncestors) {
        SeafFPRecord *revived = [self recordLockedForUUID:ancestor.uuid];
        if (!revived) return NO;
        revived.hintRevivedFrom = ancestor.tombTxn;
        revived.hintRevivedAt = _transactionStartSeq;
        if (![self writeRecordLocked:revived insert:NO]) return NO;
    }
    if (record.deleted && !carriedRecovery) record.hintRevivedAt = _transactionStartSeq;
    record.hintRevivedFrom = tombTxn;
    record.confirmedPlacement = NO;
    SeafFPRecord *moved = [self moveRecordLocked:record toRepo:repoId path:newPath parentUUID:parentUUID
                                mergeDestination:YES detachedFromPath:nil];
    if (!moved) return NO;
    // Listings now tell whether the rename really carried everything; for a
    // directory that includes the old path itself (recreated, it may hold a
    // carried row that really stayed: see the verification below).
    for (NSString *dir in moved.isDir ? @[targetDir, newPath, oldPath.stringByDeletingLastPathComponent, oldPath]
                                      : @[targetDir, oldPath.stringByDeletingLastPathComponent]) {
        if (![self requestDirectoryCheckLockedForRepo:repoId path:dir]) return NO;
    }
    if (changed) *changed = YES;
    return [self saveRenameHintLocked:hint state:SeafFPHintVerifying record:moved];
}

- (SeafFPWriteResult)decideRenameHintsWithLimit:(NSUInteger)limit
{
    if (limit == 0) return SeafFPWriteUnchanged;
    return [self performWrite:^BOOL(BOOL *rollback) {
        sqlite3_stmt *expire = [self prepareLocked:@"DELETE FROM fp_hint WHERE state IN (1, 2) AND close_after < ?"];
        if (!expire) { *rollback = YES; return NO; }
        sqlite3_bind_double(expire, 1, [NSDate date].timeIntervalSince1970);
        int rc = [self stepLocked:expire];
        sqlite3_finalize(expire);
        if (rc != SQLITE_DONE) { *rollback = YES; return NO; }
        NSArray<NSDictionary *> *hints = [self renameHintsLockedWithSQL:[kRenameHintSelect stringByAppendingString:@" WHERE state = 0 ORDER BY repo_id, event_time, id LIMIT ?"]
                                                               binder:^(sqlite3_stmt *stmt) { sqlite3_bind_int64(stmt, 1, (sqlite3_int64)limit); }];
        if (!hints) { *rollback = YES; return NO; }
        if (hints.count == limit) {
            // Never split hints of one library that share a second: their
            // order is only known from all of them together.
            NSDictionary *last = hints.lastObject;
            NSArray<NSDictionary *> *rest = [self renameHintsLockedWithSQL:[kRenameHintSelect stringByAppendingString:@" WHERE state = 0 AND repo_id = ? AND event_time = ? AND id > ? ORDER BY id"]
                                                                   binder:^(sqlite3_stmt *stmt) {
                SeafFPBindText(stmt, 1, last[@"repo"]);
                sqlite3_bind_int64(stmt, 2, [last[@"time"] longLongValue]);
                sqlite3_bind_int64(stmt, 3, [last[@"id"] longLongValue]);
            }];
            if (!rest) { *rollback = YES; return NO; }
            hints = [hints arrayByAddingObjectsFromArray:rest];
        }
        BOOL changed = NO;
        NSUInteger i = 0;
        while (i < hints.count) {
            NSUInteger j = i;
            while (j < hints.count && [hints[j][@"repo"] isEqual:hints[i][@"repo"]] && [hints[j][@"time"] isEqual:hints[i][@"time"]]) j++;
            NSMutableArray<NSDictionary *> *group = [[hints subarrayWithRange:NSMakeRange(i, j - i)] mutableCopy];
            while (group.count > 0) {
                NSUInteger pick = [self nextSameSecondHintLockedIn:group];
                if (![self decideRenameHintLocked:group[pick] changed:&changed]) { *rollback = YES; return NO; }
                [group removeObjectAtIndex:pick];
            }
            i = j;
        }
        return changed;
    } requestSignal:YES];
}

- (BOOL)verifyPlacedFileRenameLocked:(NSDictionary *)hint directory:(NSString *)dir requestStartSeq:(long long)start
                            entries:(NSArray<NSDictionary *> *)entries changed:(BOOL *)changed
{
    NSString *oldPath = hint[@"old"], *newPath = hint[@"new"], *repoId = hint[@"repo"];
    BOOL sourceListing = [dir isEqual:oldPath.stringByDeletingLastPathComponent];
    if (start < [hint[@"decided"] longLongValue] || (!sourceListing && ![dir isEqual:newPath.stringByDeletingLastPathComponent])) return YES;
    SeafFPRecord *source = [self recordLockedForRepo:repoId path:oldPath];
    if (![source.uuid isEqual:hint[@"uuid"]] || source.isDir) return [self closeRenameHintLocked:hint];
    if (!source.deleted) {
        // A fresh listing still shows the file where the explicit move put it.
        return !sourceListing || source.seq > start || [self closeRenameHintLocked:hint];
    }
    if (source.tombReason != SeafFPTombReasonAbsent || ![source.oid isEqual:hint[@"oid"]]) return [self closeRenameHintLocked:hint];
    SeafFPRecord *target = [self recordLockedForRepo:repoId path:newPath];
    if (!target || target.deleted || target.isDir || target.confirmedPlacement) return YES;
    if ([self destinationReservedLockedForRepo:repoId path:newPath exceptUUID:source.uuid]) return [self closeRenameHintLocked:hint];
    long long version = [hint[@"version"] longLongValue];
    if ([source.oid isEqual:target.oid]) {
        if (![self isProvisionalRenameOccupantLocked:target forRecord:source hintVersion:version tombTxn:source.tombTxn]) return YES;
    } else {
        // An edit changes the content ID. Only accept it when the rename
        // postdates the server-confirmed placement and one fresh listing
        // sees both the absence at the source and the new content.
        long long event = [hint[@"firstTime"] longLongValue];
        if (source.placementTime <= 0 || event <= source.placementTime || event - source.placementTime <= kHintTimeSlack
            || source.tombTxn < version || target.createdSeq <= version
            || !sourceListing || ![dir isEqual:target.directoryPath] || target.oid.length == 0) return YES;
        sqlite3_stmt *stmt = [self prepareLocked:@"SELECT event_time FROM fp_path_replacement WHERE repo_id = ? AND path = ?"];
        if (!stmt) return NO;
        SeafFPBindText(stmt, 1, repoId);
        SeafFPBindText(stmt, 2, newPath);
        int rc = [self stepLocked:stmt];
        BOOL replaced = rc == SQLITE_ROW && sqlite3_column_int64(stmt, 0) >= [hint[@"time"] longLongValue];
        sqlite3_finalize(stmt);
        if (rc != SQLITE_ROW && rc != SQLITE_DONE) return NO;
        if (replaced) return [self closeRenameHintLocked:hint];
        BOOL listed = NO;
        for (NSDictionary *entry in entries) {
            if ([SeafFPEntryString(entry, SeafFPEntryName) isEqual:target.name]
                && ![entry[SeafFPEntryIsDir] boolValue] && [SeafFPEntryString(entry, SeafFPEntryOid) isEqual:target.oid]) {
                listed = YES;
                break;
            }
        }
        if (!listed) return YES;
    }
    source.hintRevivedFrom = 0;
    source.placementTime = MAX(source.placementTime, [hint[@"time"] longLongValue]);
    if (![self moveRecordLocked:source toRepo:repoId path:newPath parentUUID:target.parentUUID
               mergeDestination:YES detachedFromPath:nil]) return NO;
    if (![self upsertRecordLockedForRepo:repoId path:newPath isDir:NO parentUUID:target.parentUUID
                                    oid:target.oid mtime:target.mtime size:target.size changed:NULL]) return NO;
    *changed = YES;
    return [self closeRenameHintLocked:hint];
}

- (BOOL)correctRenameHintsLockedForRepo:(NSString *)repoId
                              directory:(NSString *)dir
                        requestStartSeq:(long long)start
                                entries:(NSArray<NSDictionary *> *)entries
                               inserted:(NSArray<SeafFPRecord *> *)inserted
                                 absent:(NSArray<SeafFPRecord *> *)absent
                                changed:(BOOL *)changed
{
    NSString *states = inserted.count || absent.count ? @"state IN (1, 2)" : @"state = 2";
    NSString *sql = [NSString stringWithFormat:@"%@ WHERE %@ AND repo_id = ? AND close_after >= ? ORDER BY event_time, id", kRenameHintSelect, states];
    NSArray<NSDictionary *> *hints = [self renameHintsLockedWithSQL:sql binder:^(sqlite3_stmt *stmt) {
        SeafFPBindText(stmt, 1, repoId);
        sqlite3_bind_double(stmt, 2, [NSDate date].timeIntervalSince1970);
    }];
    if (!hints) return NO;
    // Maps `path` below `from` to the same place below `to`, or nil.
    NSString *(^counterpart)(NSString *, NSString *, NSString *) = ^NSString *(NSString *path, NSString *from, NSString *to) {
        if ([path isEqualToString:from]) return to;
        NSString *prefix = [from isEqualToString:@"/"] ? @"/" : [from stringByAppendingString:@"/"];
        return [path hasPrefix:prefix] ? [to stringByAppendingString:[path substringFromIndex:from.length]] : nil;
    };
    BOOL (^relink)(SeafFPRecord *, SeafFPRecord *, long long) = ^BOOL(SeafFPRecord *carried, SeafFPRecord *fresh, long long decided) {
        if (!carried.deleted || carried.tombReason != SeafFPTombReasonAbsent || carried.tombTxn < decided) return YES;
        if (fresh.deleted || fresh.createdSeq <= decided || fresh.isDir != carried.isDir) return YES;
        if (carried.oid.length == 0 || ![carried.oid isEqualToString:fresh.oid]) return YES;
        if ([self destinationReservedLockedForRepo:repoId path:fresh.path exceptUUID:carried.uuid]) return YES;
        carried.hintRevivedFrom = 0;
        if (![self moveRecordLocked:carried toRepo:repoId path:fresh.path parentUUID:fresh.parentUUID
                   mergeDestination:YES detachedFromPath:nil]) return NO;
        *changed = YES;
        return YES;
    };
    for (NSDictionary *hint in hints) {
        if ([hint[@"state"] integerValue] == SeafFPHintAwaitingListing) {
            if (![self verifyPlacedFileRenameLocked:hint directory:dir requestStartSeq:start entries:entries changed:changed]) return NO;
            continue;
        }
        long long decided = [hint[@"decided"] longLongValue];
        for (SeafFPRecord *fresh in inserted) {
            NSString *path = counterpart(fresh.path, hint[@"old"], hint[@"new"]);
            SeafFPRecord *carried = path ? [self recordLockedForRepo:repoId path:path] : nil;
            if (carried && !relink(carried, [self recordLockedForUUID:fresh.uuid], decided)) return NO;
        }
        for (SeafFPRecord *gone in absent) {
            NSString *path = counterpart(gone.path, hint[@"new"], hint[@"old"]);
            SeafFPRecord *fresh = path ? [self recordLockedForRepo:repoId path:path] : nil;
            if (fresh && !relink([self recordLockedForUUID:gone.uuid], fresh, decided)) return NO;
        }
    }
    return [self transactionHealthyLocked];
}

- (BOOL)noteLastUsedDate:(NSDate *)lastUsedDate
                 forRepo:(NSString *)repoId
                    path:(NSString *)path
                     oid:(NSString *)oid
                    size:(long long)size
                   mtime:(long long)mtime
         createIfMissing:(BOOL)createIfMissing
{
    if (repoId.length == 0) return NO;
    NSString *normalized = [SeafFPIdentifier normalizedPath:path];
    if ([normalized isEqualToString:@"/"]) return NO;
    NSString *contentOid = oid.length > 0 ? oid : nil;
    return [self performIndexWrite:^BOOL(BOOL *rollback) {
        if ([self isPathLockedTombstonedForRepo:repoId path:normalized]) return NO;
        BOOL identityChanged = NO;
        SeafFPRecord *record = [self recordLockedForRepo:repoId path:normalized];
        if (!record) {
            if (!createIfMissing) return NO;
            NSString *parentUUID = nil;
            if (![self ensureDirectoryLockedForRepo:repoId path:normalized.stringByDeletingLastPathComponent
                                        allowRevive:NO uuid:&parentUUID changed:&identityChanged]) {
                *rollback = YES;
                return NO;
            }
            record = [self upsertRecordLockedForRepo:repoId path:normalized isDir:NO parentUUID:parentUUID
                                                 oid:contentOid mtime:mtime size:size changed:&identityChanged];
        } else if (record.oid.length == 0 && contentOid) {
            // Fill in only: a stored oid may be newer than what the app has.
            record = [self upsertRecordLockedForRepo:repoId path:normalized isDir:record.isDir parentUUID:record.parentUUID
                                                 oid:contentOid mtime:mtime size:size changed:&identityChanged];
        }
        if (!record) {
            *rollback = YES;
            return NO;
        }
        if (!lastUsedDate) return identityChanged;

        // Read-modify-write inside this transaction: a favorite or tag the
        // extension stores at the same moment is kept.
        SeafFPDecoration *decoration = [self decorationLockedForItem:record.itemIdentifier] ?: [SeafFPDecoration new];
        if (!identityChanged && decoration.lastUsedDate
            && fabs([lastUsedDate timeIntervalSinceDate:decoration.lastUsedDate]) < 60.0) {
            return NO;
        }
        decoration.itemIdentifier = record.itemIdentifier;
        decoration.lastUsedDate = lastUsedDate;
        if (![self setDecorationLocked:decoration]) {
            *rollback = YES;
            return NO;
        }
        if (!identityChanged) {
            // Decorations carry no seq: bump the row so the next working set
            // change pass reports the item, with its new last-used date.
            record.seq = [self nextSeqLocked];
            if (![self writeRecordLocked:record insert:NO]) {
                *rollback = YES;
                return NO;
            }
        }
        return YES;
    }];
}

@end
