//
//  SeafFPStore.m
//  SeafFileProvider
//

#import "SeafFPStore.h"
#import "SeafFPIdentifier.h"
#import "Debug.h"
#import <sqlite3.h>

static const int kSeafFPSchemaVersion = 1;

static NSString * const kMetaSchemaVersion = @"schema_version";
static NSString * const kMetaSeq = @"seq";

static const char *kRecordColumns = "uuid, repo_id, path, is_dir, name, parent_uuid, oid, mtime, size, deleted, seq";

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

#pragma mark - Store

static const void *kSeafFPStoreQueueKey = &kSeafFPStoreQueueKey;

@interface SeafFPStore ()
{
    sqlite3 *_db;
    NSInteger _transactionDepth;
    BOOL _transactionOpen;
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
}
@property (nonatomic, copy) NSString *domainIdentifier;
@property (nonatomic, copy) NSURL *storeURL;
@property (nonatomic, strong) dispatch_queue_t queue;
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
    self = [super init];
    if (!self) return nil;
    _domainIdentifier = [domainIdentifier copy];
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
    [[NSFileManager defaultManager] createDirectoryAtURL:url.URLByDeletingLastPathComponent
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
    int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX;
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
        // Under contention (the app migrating into the same store) BEGIN can
        // fail even with the busy timeout; then the statements auto-commit
        // and COMMIT must not be issued.
        _transactionOpen = [self execLocked:@"BEGIN IMMEDIATE"];
    }
}

/// Ends the outermost transaction, whether it was committed, rolled back or
/// never opened.
- (BOOL)leaveTransactionLocked
{
    if (--_transactionDepth > 0) return NO;
    if (_transactionDepth < 0) _transactionDepth = 0;   // unbalanced; do not stay wedged
    if (!_transactionOpen) return NO;
    _transactionOpen = NO;
    return YES;
}

- (void)commitLocked
{
    if (![self leaveTransactionLocked]) return;
    if ([self execLocked:@"COMMIT"]) return;
    // A COMMIT that fails (SQLITE_BUSY above all) leaves the transaction open
    // in sqlite. Without this rollback every later BEGIN IMMEDIATE would fail,
    // every later commitLocked would skip its COMMIT, and nothing this process
    // writes would ever reach the file again.
    Warning("sqlite COMMIT failed (%d), rolling back", _lastResultCode);
    [self execLocked:@"ROLLBACK"];
}

- (void)rollbackLocked
{
    if (![self leaveTransactionLocked]) return;
    [self execLocked:@"ROLLBACK"];
}

- (void)performBatch:(void (NS_NOESCAPE ^)(void))block
{
    [self perform:^{
        [self beginLocked];
        @try {
            block();
        } @finally {
            // An exception must not leave the depth counter (and with it every
            // later transaction) unbalanced.
            [self commitLocked];
        }
    }];
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
          "deleted INTEGER NOT NULL DEFAULT 0, seq INTEGER NOT NULL, UNIQUE(repo_id, path))"),
        @"CREATE INDEX IF NOT EXISTS idx_identity_parent ON identity(repo_id, parent_uuid, deleted)",
        @"CREATE INDEX IF NOT EXISTS idx_identity_seq ON identity(seq)",
        (@"CREATE TABLE IF NOT EXISTS decoration ("
          "item_id TEXT PRIMARY KEY, favorite_rank INTEGER, tag_data BLOB, last_used REAL)"),
        (@"CREATE TABLE IF NOT EXISTS container ("
          "container_id TEXT PRIMARY KEY, anchor TEXT, snapshot TEXT, enumerated_at REAL)"),
        (@"CREATE TABLE IF NOT EXISTS working_set ("
          "item_id TEXT PRIMARY KEY, reason INTEGER NOT NULL, seq INTEGER NOT NULL)"),
        @"CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)",
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
    NSString *version = [self metaValueLockedForKey:kMetaSchemaVersion];
    if (version == nil) {
        // First open, or a store that lost its version stamp. Both meta rows
        // are written in one transaction: tables without a schema_version row
        // make the next open seed the seq counter, and a counter below the
        // values the rows already carry silently stops change enumeration.
        [self beginLocked];
        BOOL stamped = [self metaValueLockedForKey:kMetaSchemaVersion] != nil;   // another process got there first
        if (!stamped) {
            stamped = [self setMetaValueLocked:[NSString stringWithFormat:@"%d", kSeafFPSchemaVersion] forKey:kMetaSchemaVersion]
                && [self setMetaValueLocked:[NSString stringWithFormat:@"%lld", [self maxRowSeqLocked]] forKey:kMetaSeq];
        }
        if (!stamped) {
            if (corrupt) *corrupt = SeafFPResultIsCorruption(_lastResultCode);
            [self rollbackLocked];
            return NO;
        }
        [self commitLocked];
    } else if (version.intValue > kSeafFPSchemaVersion) {
        Warning("Store schema %@ is newer than supported %d", version, kSeafFPSchemaVersion);
        if (newerSchema) *newerSchema = YES;
        return NO;
    }
    // Future schema upgrades go here, ordered by version, each in a transaction.
    return YES;
}

#pragma mark - Meta

- (NSString *)metaValueLockedForKey:(NSString *)key
{
    NSString *value = nil;
    sqlite3_stmt *stmt = [self prepareLocked:@"SELECT value FROM meta WHERE key = ?"];
    if (!stmt) return nil;
    SeafFPBindText(stmt, 1, key);
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        value = SeafFPColumnText(stmt, 0);
    }
    sqlite3_finalize(stmt);
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
    int rc = sqlite3_step(stmt);
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
    for (NSString *sql in @[@"SELECT MAX(seq) FROM identity", @"SELECT MAX(seq) FROM working_set"]) {
        sqlite3_stmt *stmt = [self prepareLocked:sql];
        if (!stmt) continue;
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            maxSeq = MAX(maxSeq, sqlite3_column_int64(stmt, 0));
        }
        sqlite3_finalize(stmt);
    }
    return maxSeq;
}

- (long long)currentSeqLocked
{
    return [self metaValueLockedForKey:kMetaSeq].longLongValue;
}

- (long long)nextSeqLocked
{
    long long next = [self currentSeqLocked] + 1;
    [self setMetaValueLocked:[NSString stringWithFormat:@"%lld", next] forKey:kMetaSeq];
    return next;
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
    return r;
}

- (NSArray<SeafFPRecord *> *)recordsLockedWithSQL:(NSString *)sql binder:(void (^)(sqlite3_stmt *stmt))binder
{
    NSMutableArray *result = [NSMutableArray array];
    sqlite3_stmt *stmt = [self prepareLocked:sql];
    if (!stmt) return result;
    if (binder) binder(stmt);
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        [result addObject:[self recordFromStatement:stmt]];
    }
    sqlite3_finalize(stmt);
    return result;
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
    __block SeafFPRecord *record = nil;
    [self perform:^{ record = [self recordLockedForUUID:uuid]; }];
    return record;
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
        ? @"INSERT INTO identity(uuid, repo_id, path, is_dir, name, parent_uuid, oid, mtime, size, deleted, seq) VALUES(?,?,?,?,?,?,?,?,?,?,?)"
        : @"UPDATE identity SET repo_id=?, path=?, is_dir=?, name=?, parent_uuid=?, oid=?, mtime=?, size=?, deleted=?, seq=? WHERE uuid=?";
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
    if (!insert) SeafFPBindText(stmt, i++, r.uuid);
    int rc = sqlite3_step(stmt);
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
    NSString *name = normalized.lastPathComponent;
    __block SeafFPRecord *result = nil;
    [self perform:^{
        [self beginLocked];
        SeafFPRecord *existing = [self recordLockedForRepo:repoId path:normalized];
        if (existing) {
            NSString *newOid = oid ?: existing.oid;
            long long newMtime = mtime > 0 ? mtime : existing.mtime;
            long long newSize = size >= 0 ? size : existing.size;
            BOOL changed = existing.deleted
                || existing.isDir != isDir
                || !SeafFPStringsEqual(existing.name, name)
                || !SeafFPStringsEqual(existing.parentUUID, parentUUID)
                || !SeafFPStringsEqual(existing.oid, newOid)
                || existing.mtime != newMtime
                || existing.size != newSize;
            if (changed) {
                existing.deleted = NO;
                existing.isDir = isDir;
                existing.name = name;
                existing.parentUUID = parentUUID;
                existing.oid = newOid;
                existing.mtime = newMtime;
                existing.size = newSize;
                existing.seq = [self nextSeqLocked];
                if (![self writeRecordLocked:existing insert:NO]) {
                    existing = nil;
                }
            }
            result = existing;
        } else {
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
            r.seq = [self nextSeqLocked];
            result = [self writeRecordLocked:r insert:YES] ? r : nil;
        }
        [self commitLocked];
    }];
    return result;
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
    return result;
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
    }];
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

- (void)markDeletedLockedUUID:(NSString *)uuid
{
    SeafFPRecord *record = [self recordLockedForUUID:uuid];
    if (!record) return;
    NSMutableArray<SeafFPRecord *> *targets = [NSMutableArray arrayWithObject:record];
    if (record.isDir) {
        [targets addObjectsFromArray:[self subtreeRecordsLockedOf:record]];
    }
    for (SeafFPRecord *r in targets) {
        if (r.deleted) continue;
        r.deleted = YES;
        r.seq = [self nextSeqLocked];
        [self writeRecordLocked:r insert:NO];
    }
}

- (void)markDeletedUUID:(NSString *)uuid
{
    [self markDeletedUUIDs:@[uuid]];
}

- (void)markDeletedUUIDs:(NSArray<NSString *> *)uuids
{
    if (uuids.count == 0) return;
    [self perform:^{
        [self beginLocked];
        for (NSString *uuid in uuids) {
            [self markDeletedLockedUUID:uuid];
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
    return result;
}

- (NSArray<SeafFPRecord *> *)liveRecordsAfterUUID:(NSString *)uuid limit:(NSInteger)limit
{
    NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM identity WHERE deleted = 0 AND uuid > ? ORDER BY uuid LIMIT ?", kRecordColumns];
    __block NSArray *result = @[];
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
    [self performBatch:^{
        SeafFPRecord *record = [self recordLockedForUUID:uuid];
        if (!record) return;
        NSString *oldPath = record.path;
        NSString *oldRepo = record.repoId;
        // Whatever previously lived at the destination is stale now.
        [self evictOccupantLockedOfRepo:repoId path:newPath exceptUUID:uuid];
        NSArray<SeafFPRecord *> *children = record.isDir ? [self subtreeRecordsLockedOf:record] : @[];
        record.repoId = repoId;
        record.path = newPath;
        record.name = newPath.lastPathComponent;
        record.parentUUID = parentUUID;
        record.seq = [self nextSeqLocked];
        [self writeRecordLocked:record insert:NO];
        NSString *oldPrefix = [oldPath stringByAppendingString:@"/"];
        for (SeafFPRecord *child in children) {
            if (![child.repoId isEqualToString:oldRepo] || ![child.path hasPrefix:oldPrefix]) continue;
            NSString *childPath = [newPath stringByAppendingString:[child.path substringFromIndex:oldPath.length]];
            [self evictOccupantLockedOfRepo:repoId path:childPath exceptUUID:child.uuid];
            child.repoId = repoId;
            child.path = childPath;
            child.seq = [self nextSeqLocked];
            [self writeRecordLocked:child insert:NO];
        }
        result = record;
    }];
    return result;
}

/// Frees (repoId, path) for another record: a live or tombstoned row that
/// still sits there is tombstoned under a unique path so UNIQUE(repo_id, path)
/// cannot reject the move.
- (void)evictOccupantLockedOfRepo:(NSString *)repoId path:(NSString *)path exceptUUID:(NSString *)uuid
{
    SeafFPRecord *occupant = [self recordLockedForRepo:repoId path:path];
    if (!occupant || [occupant.uuid isEqualToString:uuid]) return;
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
        if (sqlite3_step(stmt) == SQLITE_ROW) anchor = SeafFPColumnText(stmt, 0);
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
        if (sqlite3_step(stmt) == SQLITE_ROW) json = SeafFPColumnText(stmt, 0);
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
        if (sqlite3_step(stmt) == SQLITE_ROW) {
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
        while (sqlite3_step(stmt) == SQLITE_ROW) {
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
        sqlite3_step(stmt);
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
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:@"SELECT item_id, favorite_rank, tag_data, last_used FROM decoration WHERE item_id = ?"];
        if (!stmt) return;
        SeafFPBindText(stmt, 1, itemIdentifier);
        if (sqlite3_step(stmt) == SQLITE_ROW) result = [self decorationFromStatement:stmt];
        sqlite3_finalize(stmt);
    }];
    return result;
}

- (NSArray<SeafFPDecoration *> *)allDecorations
{
    NSMutableArray *result = [NSMutableArray array];
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:@"SELECT item_id, favorite_rank, tag_data, last_used FROM decoration"];
        if (!stmt) return;
        while (sqlite3_step(stmt) == SQLITE_ROW) {
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
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:@"INSERT OR REPLACE INTO decoration(item_id, favorite_rank, tag_data, last_used) VALUES(?,?,?,?)"];
        if (!stmt) return;
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
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }];
}

- (void)removeDecorationForItem:(NSString *)itemIdentifier
{
    [self perform:^{
        sqlite3_stmt *stmt = [self prepareLocked:@"DELETE FROM decoration WHERE item_id = ?"];
        if (!stmt) return;
        SeafFPBindText(stmt, 1, itemIdentifier);
        sqlite3_step(stmt);
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
        while (sqlite3_step(stmt) == SQLITE_ROW) {
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
    if (sqlite3_step(stmt) == SQLITE_ROW) reason = sqlite3_column_int64(stmt, 0);
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
    sqlite3_step(stmt);
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
        while (sqlite3_step(stmt) == SQLITE_ROW) {
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
        while (sqlite3_step(stmt) == SQLITE_ROW) {
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

@end
