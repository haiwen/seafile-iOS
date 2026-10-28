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
static NSString * const kMetaDirStampPrefix = @"dirstamp:";

NSString * const SeafFPEntryName = @"name";
NSString * const SeafFPEntryPath = @"path";
NSString * const SeafFPEntryIsDir = @"isDir";
NSString * const SeafFPEntryOid = @"oid";
NSString * const SeafFPEntrySize = @"size";
NSString * const SeafFPEntryMtime = @"mtime";
NSString * const SeafFPEntryOp = @"op";
NSString * const SeafFPEntryOldPath = @"oldPath";
NSString * const SeafFPActivityOpCreate = @"create";
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
    // One statement: two processes can never be handed the same value, not
    // even when BEGIN IMMEDIATE failed and the caller runs in autocommit. A
    // missing counter row is seeded from the rows, like createSchemaLocked:.
    sqlite3_stmt *stmt = [self prepareLocked:
        @"INSERT INTO meta(key, value) VALUES(?1, CAST((SELECT COALESCE(MAX(s), 0) FROM "
         "(SELECT MAX(seq) AS s FROM identity UNION ALL SELECT MAX(seq) FROM working_set)) + 1 AS TEXT)) "
         "ON CONFLICT(key) DO UPDATE SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT) "
         "RETURNING CAST(value AS INTEGER)"];
    if (stmt) {
        SeafFPBindText(stmt, 1, kMetaSeq);
        int rc = sqlite3_step(stmt);
        _lastResultCode = rc;
        long long next = rc == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0;
        sqlite3_finalize(stmt);
        if (next > 0) return next;
        Warning("sqlite seq increment failed (%d) %s", rc, sqlite3_errmsg(_db));
    }
    // Fallback: the previous read-then-write behaviour.
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
    __block SeafFPRecord *result = nil;
    [self perform:^{
        [self beginLocked];
        result = [self upsertRecordLockedForRepo:repoId path:normalized isDir:isDir parentUUID:parentUUID
                                             oid:oid mtime:mtime size:size changed:NULL];
        [self commitLocked];
    }];
    return result;
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
            BOOL wasDeleted = existing.deleted;
            if (existing.isDir && !isDir) {
                for (SeafFPRecord *sub in [self subtreeRecordsLockedOf:existing]) {
                    if (sub.deleted) continue;
                    sub.deleted = YES;
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
            if (wasDeleted || typeChanged) {
                [self clearRecordedActivityMoveLockedForRepo:repoId uuid:existing.uuid];
            }
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
        result = [self moveRecordLockedUUID:uuid toRepo:repoId path:newPath parentUUID:parentUUID];
    }];
    return result;
}

/// Body of moveRecordUUID:; `newPath` must already be normalized.
- (SeafFPRecord *)moveRecordLockedUUID:(NSString *)uuid toRepo:(NSString *)repoId path:(NSString *)newPath parentUUID:(NSString *)parentUUID
{
    return [self moveRecordLockedUUID:uuid toRepo:repoId path:newPath parentUUID:parentUUID recordActivityMove:YES];
}

- (SeafFPRecord *)moveRecordLockedUUID:(NSString *)uuid
                                toRepo:(NSString *)repoId
                                  path:(NSString *)newPath
                            parentUUID:(NSString *)parentUUID
                    recordActivityMove:(BOOL)recordActivityMove
{
    SeafFPRecord *record = [self recordLockedForUUID:uuid];
    if (!record) return nil;
    BOOL wasTombstoned = record.deleted;
    long long tombstoneSeq = record.seq;
    NSString *oldPath = record.path;
    NSString *oldRepo = record.repoId;
    NSString *oldParentUUID = record.parentUUID;
    SeafFPRecord *priorOccupant = [self recordLockedForRepo:repoId path:newPath];
    BOOL replacedPriorOccupant = (priorOccupant != nil && ![priorOccupant.uuid isEqualToString:uuid]);
    // Whatever previously lived at the destination is stale now.
    [self evictOccupantLockedOfRepo:repoId path:newPath exceptUUID:uuid];
    NSArray<SeafFPRecord *> *children = record.isDir ? [self subtreeRecordsLockedOf:record] : @[];
    record.deleted = NO;
    record.repoId = repoId;
    record.path = newPath;
    record.name = newPath.lastPathComponent;
    record.parentUUID = parentUUID;
    record.seq = [self nextSeqLocked];
    [self writeRecordLocked:record insert:NO];
    if (![oldRepo isEqualToString:repoId] || ![oldPath isEqualToString:newPath]) {
        // The entry left (or was renamed inside) its directory: a listing of
        // that directory requested before now still shows the old name.
        [self setDirStampLocked:record.seq forRepo:oldRepo parentUUID:oldParentUUID];
    }
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
        child.seq = [self nextSeqLocked];
        [self writeRecordLocked:child insert:NO];
    }
    if (recordActivityMove && (![oldRepo isEqualToString:repoId] || ![oldPath isEqualToString:newPath])) {
        [self recordActivityMoveLockedFromRepo:oldRepo
                                       oldPath:oldPath
                                        toRepo:repoId
                                       newPath:newPath
                                        record:record
                                      children:children
                         replacedPriorOccupant:replacedPriorOccupant];
    }
    return record;
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
    [self perform:^{ result = [self decorationLockedForItem:itemIdentifier]; }];
    return result;
}

- (SeafFPDecoration *)decorationLockedForItem:(NSString *)itemIdentifier
{
    SeafFPDecoration *result = nil;
    sqlite3_stmt *stmt = [self prepareLocked:@"SELECT item_id, favorite_rank, tag_data, last_used FROM decoration WHERE item_id = ?"];
    if (!stmt) return nil;
    SeafFPBindText(stmt, 1, itemIdentifier);
    if (sqlite3_step(stmt) == SQLITE_ROW) result = [self decorationFromStatement:stmt];
    sqlite3_finalize(stmt);
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
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE;
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
    __block BOOL changed = NO;
    [self perform:^{
        [self beginLocked];
        if (!self->_transactionOpen) {
            [self leaveTransactionLocked];
            Info("file provider store busy, index write skipped");
            return;
        }
        BOOL rollback = NO;
        @try {
            changed = block(&rollback);
        } @finally {
            if (rollback) {
                [self rollbackLocked];
                changed = NO;
            } else {
                [self commitLocked];
            }
        }
    }];
    return changed;
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
    BOOL found = sqlite3_step(stmt) == SQLITE_ROW;
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
    BOOL found = sqlite3_step(stmt) == SQLITE_ROW;
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

- (BOOL)applyListingOfRepo:(NSString *)repoId
             directoryPath:(NSString *)directoryPath
                   entries:(NSArray<NSDictionary *> *)entries
           requestStartSeq:(long long)requestStartSeq
{
    if (repoId.length == 0) return NO;
    NSString *dir = [SeafFPIdentifier normalizedPath:directoryPath];
    BOOL isRoot = [dir isEqualToString:@"/"];
    long long S = requestStartSeq;
    return [self performIndexWrite:^BOOL(BOOL *rollback) {
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
        //    transaction creates can never count as a conflict.
        if (S >= 0) {
            // A direct child was added, edited, renamed or tombstoned.
            if ((isRoot || dirRecord) && [self hasChildLockedOfRepo:repoId parentUUID:(isRoot ? nil : dirRecord.uuid) changedAfter:S]) {
                *rollback = YES;
                return NO;
            }
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
            [seen addObject:child.uuid];
        }

        // 5. Rows the server no longer lists. A directory whose subtree got a
        //    row after the request (the extension just wrote into it) stays.
        if (S >= 0) {
            for (SeafFPRecord *gone in [self childRecordsLockedOfRepo:repoId parentUUID:parentUUID]) {
                if ([seen containsObject:gone.uuid]) continue;
                if (gone.isDir && [self hasSubtreeRecordLockedOf:gone changedAfter:S]) continue;
                [self markDeletedLockedUUID:gone.uuid];
                changed = YES;
            }
        }
        return changed;
    }];
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
static BOOL SeafFPIsConflictSiblingName(NSString *candidate, NSString *expected)
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
    if (occupant.seq <= S) return NO;
    if (occupant.isDir != record.isDir) return NO;
    if (record.oid.length > 0 && occupant.oid.length > 0 && ![occupant.oid isEqualToString:record.oid]) {
        return NO;
    }
    if ([self decorationLockedForItem:occupant.itemIdentifier] != nil) return NO;
    if ([self workingSetReasonLockedForItem:occupant.itemIdentifier] != 0) return NO;
    return YES;
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
        return YES;
    };
    BOOL (^fresh)(NSString *) = ^BOOL(NSString *name) {
        NSString *childPath = [SeafFPIdentifier normalizedPath:[dir stringByAppendingFormat:@"/%@", name]];
        SeafFPRecord *live = [self recordLockedForRepo:repoId path:childPath];
        if (!live || live.deleted) return YES;
        if (S >= 0 && live.seq > S && ![live.uuid isEqualToString:record.uuid]) return YES;
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
            while (sqlite3_step(stmt) == SQLITE_ROW) {
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
            while (sqlite3_step(stmt) == SQLITE_ROW) {
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

- (BOOL)moveRecordsOfRepo:(NSString *)srcRepoId
            fromDirectory:(NSString *)srcDirectoryPath
                    names:(NSArray<NSString *> *)names
                   toRepo:(NSString *)dstRepoId
              toDirectory:(NSString *)dstDirectoryPath
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
        if (![self isDirectoryChainFreshLockedForRepo:srcRepoId directoryPath:srcDir requestStartSeq:S allowedTombstonedPaths:movingPaths allowedDestinationEntries:nil]
            || ![self isDirectoryChainFreshLockedForRepo:dstRepoId directoryPath:dstDir requestStartSeq:S allowedTombstonedPaths:nil allowedDestinationEntries:destinationEntries]) {
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
                                                        expected:name
                                                          inRepo:dstRepoId
                                                       directory:dstDir
                                                         entries:destinationEntries
                                                    claimedNames:claimedNames
                                                 requestStartSeq:S];
            if (finalName.length == 0) continue;
            NSString *dstPath = [SeafFPIdentifier normalizedPath:[dstDir stringByAppendingFormat:@"/%@", finalName]];
            if ([srcRepoId isEqualToString:dstRepoId] && [srcPath isEqualToString:dstPath]) continue;
            SeafFPRecord *occupant = [self recordLockedForRepo:dstRepoId path:dstPath];
            if (occupant && !occupant.deleted && ![occupant.uuid isEqualToString:record.uuid]
                && ![self isProvisionalDestinationOccupantLocked:occupant forMovedRecord:record requestStartSeq:S]) {
                continue;
            }
            if (occupant && occupant.isDir && ![occupant.uuid isEqualToString:record.uuid]) {
                for (SeafFPRecord *sub in [self subtreeRecordsLockedOf:occupant]) {
                    if ([sub.uuid isEqualToString:occupant.uuid] || sub.deleted) continue;
                    sub.deleted = YES;
                    sub.path = [NSString stringWithFormat:@"%@#moved-%lld", sub.path, [self nextSeqLocked]];
                    sub.seq = [self nextSeqLocked];
                    [self writeRecordLocked:sub insert:NO];
                }
            }
            if ([self moveRecordLockedUUID:record.uuid toRepo:dstRepoId path:dstPath parentUUID:dstParentUUID]) {
                [claimedNames addObject:finalName];
                movedAny = YES;
                changed = YES;
            }
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
    if (repoId.length == 0 || oldName.length == 0 || newName.length == 0
        || [oldName containsString:@"/"] || [newName containsString:@"/"] || [oldName isEqualToString:newName]
        || entries.count == 0 || requestStartSeq < 0) {
        return NO;
    }
    NSString *dir = [SeafFPIdentifier normalizedPath:directoryPath];
    NSString *oldPath = [SeafFPIdentifier normalizedPath:[dir stringByAppendingFormat:@"/%@", oldName]];
    long long S = requestStartSeq;
    return [self performIndexWrite:^BOOL(BOOL *rollback) {
        if (![self isDirectoryChainFreshLockedForRepo:repoId directoryPath:dir requestStartSeq:S]) {
            *rollback = YES;
            return NO;
        }
        SeafFPRecord *record = [self recordLockedForRepo:repoId path:oldPath];
        if (!record || record.deleted || record.seq > S
            || (record.isDir && [self hasSubtreeRecordLockedOf:record changedAfter:S])) {
            *rollback = YES;
            return NO;
        }
        NSString *finalName = [self finalNameForRecordLocked:record
                                                    expected:newName
                                                      inRepo:repoId
                                                   directory:dir
                                                     entries:entries
                                                claimedNames:nil
                                             requestStartSeq:-1];
        if (finalName.length == 0) {
            *rollback = YES;
            return NO;
        }
        NSString *newPath = [SeafFPIdentifier normalizedPath:[dir stringByAppendingFormat:@"/%@", finalName]];
        if ([oldPath isEqualToString:newPath]) {
            *rollback = YES;
            return NO;
        }
        SeafFPRecord *occupant = [self recordLockedForRepo:repoId path:newPath];
        if (occupant && !occupant.deleted && ![occupant.uuid isEqualToString:record.uuid]) {
            *rollback = YES;
            return NO;
        }
        if (![self moveRecordLockedUUID:record.uuid toRepo:repoId path:newPath parentUUID:record.parentUUID]) {
            *rollback = YES;
            return NO;
        }
        BOOL changed = YES;
        for (NSDictionary *entry in entries) {
            NSString *entryName = SeafFPEntryString(entry, SeafFPEntryName);
            if (entryName.length == 0 || [entryName containsString:@"/"]) continue;
            NSString *childPath = [SeafFPIdentifier normalizedPath:[dir stringByAppendingFormat:@"/%@", entryName]];
            BOOL isDir = [entry[SeafFPEntryIsDir] boolValue];
            if (![self upsertRecordLockedForRepo:repoId
                                            path:childPath
                                           isDir:isDir
                                      parentUUID:record.parentUUID
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

/// YES when a live row below the directory record carries an mtime after `mtime`.
- (BOOL)hasLiveSubtreeRecordLockedOf:(SeafFPRecord *)record newerThan:(long long)mtime
{
    sqlite3_stmt *stmt = [self prepareLocked:@"SELECT 1 FROM identity WHERE repo_id = ?1 AND substr(path, 1, length(?2)) = ?2 AND deleted = 0 AND mtime > ?3 LIMIT 1"];
    if (!stmt) return YES;   // cannot tell: keep the directory
    SeafFPBindText(stmt, 1, record.repoId);
    SeafFPBindText(stmt, 2, [record.path stringByAppendingString:@"/"]);
    sqlite3_bind_int64(stmt, 3, mtime);
    BOOL found = sqlite3_step(stmt) == SQLITE_ROW;
    sqlite3_finalize(stmt);
    return found;
}

/// Inserts a row for an unknown path below live directories; nothing else.
- (BOOL)insertUnknownLockedForRepo:(NSString *)repoId path:(NSString *)path isDir:(BOOL)isDir mtime:(long long)mtime changed:(BOOL *)changed
{
    if ([self isPathLockedTombstonedForRepo:repoId path:path]) return YES;
    if ([self recordLockedForRepo:repoId path:path]) return YES;
    NSString *parentUUID = nil;
    if (![self ensureDirectoryLockedForRepo:repoId path:path.stringByDeletingLastPathComponent allowRevive:NO uuid:&parentUUID changed:changed]) {
        return YES;   // below a tombstone or live file: skipped
    }
    return [self upsertRecordLockedForRepo:repoId path:path isDir:isDir parentUUID:parentUUID
                                       oid:nil mtime:mtime size:-1 changed:changed] != nil;
}

static NSString * const kMetaActivityLogPrefix = @"activity_log:";
static const NSUInteger kMaxActivitySeenKeys = 8192;
static const NSUInteger kMaxActivityGonePaths = 8192;
static const NSUInteger kMaxActivityMoves = 2048;

- (NSString *)activityStateMetaKeyForRepo:(NSString *)repoId
{
    return [kMetaActivityLogPrefix stringByAppendingString:repoId ?: @""];
}

- (void)loadActivityStateLockedForRepo:(NSString *)repoId
                                  seen:(NSMutableOrderedSet<NSString *> *)seen
                                  gone:(NSMutableDictionary<NSString *, NSNumber *> *)gone
                                 moves:(nullable NSMutableDictionary<NSString *, NSDictionary *> *)moves
{
    NSString *raw = [self metaValueLockedForKey:[self activityStateMetaKeyForRepo:repoId]];
    if (raw.length == 0) return;
    NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return;
    NSArray *seenArr = json[@"seen"];
    if ([seenArr isKindOfClass:[NSArray class]]) {
        for (id key in seenArr) {
            if ([key isKindOfClass:[NSString class]] && [key length] > 0) {
                [seen addObject:key];
            }
        }
    }
    NSDictionary *goneDict = json[@"gone"];
    if ([goneDict isKindOfClass:[NSDictionary class]]) {
        [goneDict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if ([key isKindOfClass:[NSString class]] && [obj respondsToSelector:@selector(longLongValue)]) {
                gone[key] = @([obj longLongValue]);
            }
        }];
    }
    if (moves) {
        NSDictionary *movesDict = json[@"moves"];
        if ([movesDict isKindOfClass:[NSDictionary class]]) {
            [movesDict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                if ([key isKindOfClass:[NSString class]] && [obj isKindOfClass:[NSDictionary class]]) {
                    moves[key] = obj;
                }
            }];
        }
    }
}

- (void)saveActivityStateLockedForRepo:(NSString *)repoId
                                  seen:(NSOrderedSet<NSString *> *)seen
                                  gone:(NSDictionary<NSString *, NSNumber *> *)gone
                                 moves:(nullable NSDictionary<NSString *, NSDictionary *> *)moves
{
    NSArray<NSString *> *seenArr = seen.array;
    if (seenArr.count > kMaxActivitySeenKeys) {
        seenArr = [seenArr subarrayWithRange:NSMakeRange(seenArr.count - kMaxActivitySeenKeys, kMaxActivitySeenKeys)];
    }
    NSDictionary<NSString *, NSNumber *> *goneToSave = gone;
    if (gone.count > kMaxActivityGonePaths) {
        NSArray<NSString *> *sortedPaths = [gone keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            return [a compare:b];
        }];
        NSMutableDictionary<NSString *, NSNumber *> *trimmed = [NSMutableDictionary dictionaryWithCapacity:kMaxActivityGonePaths];
        NSUInteger start = sortedPaths.count - kMaxActivityGonePaths;
        for (NSUInteger i = start; i < sortedPaths.count; i++) {
            NSString *k = sortedPaths[i];
            trimmed[k] = gone[k];
        }
        goneToSave = trimmed;
    }
    NSDictionary<NSString *, NSDictionary *> *movesToSave = moves ?: @{};
    if (movesToSave.count > kMaxActivityMoves) {
        NSMutableDictionary<NSString *, NSDictionary *> *trimmedMoves = [NSMutableDictionary dictionaryWithCapacity:kMaxActivityMoves];
        for (NSString *uuid in movesToSave) {
            SeafFPRecord *rec = [self recordLockedForUUID:uuid];
            if (rec && !rec.deleted) {
                trimmedMoves[uuid] = movesToSave[uuid];
                if (trimmedMoves.count >= kMaxActivityMoves) break;
            }
        }
        movesToSave = trimmedMoves;
    }
    NSDictionary *payload = @{
        @"seen": seenArr ?: @[],
        @"gone": goneToSave ?: @{},
        @"moves": movesToSave,
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!data) return;
    NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (jsonStr.length > 0) {
        [self setMetaValueLocked:jsonStr forKey:[self activityStateMetaKeyForRepo:repoId]];
    }
}

- (long long)maxObservedActivityTimeLockedInSeen:(NSOrderedSet<NSString *> *)seen
                                            gone:(NSDictionary<NSString *, NSNumber *> *)gone
{
    long long maxTime = 0;
    for (NSNumber *t in gone.allValues) {
        long long v = t.longLongValue;
        if (v > maxTime) maxTime = v;
    }
    for (NSString *key in seen) {
        NSArray<NSString *> *parts = [key componentsSeparatedByString:@"|"];
        if (parts.count >= 3) {
            long long v = [parts[2] longLongValue];
            if (v > maxTime) maxTime = v;
        }
    }
    return maxTime;
}

- (void)recordActivityMoveLockedFromRepo:(NSString *)oldRepo
                                 oldPath:(NSString *)oldPath
                                  toRepo:(NSString *)newRepo
                                 newPath:(NSString *)newPath
                                  record:(SeafFPRecord *)record
                                children:(NSArray<SeafFPRecord *> *)children
                   replacedPriorOccupant:(BOOL)replacedPriorOccupant
{
    if (oldRepo.length == 0 || newRepo.length == 0 || !record) return;
    BOOL sameRepo = [oldRepo isEqualToString:newRepo];
    NSMutableOrderedSet<NSString *> *seen = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary<NSString *, NSNumber *> *gone = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *moves = [NSMutableDictionary dictionary];
    [self loadActivityStateLockedForRepo:oldRepo seen:seen gone:gone moves:moves];

    long long departedTime = MAX(record.mtime, [self maxObservedActivityTimeLockedInSeen:seen gone:gone]);
    if (oldPath.length > 0 && ![oldPath isEqualToString:@"/"] && departedTime > 0) {
        long long prevGone = [gone[oldPath] longLongValue];
        if (departedTime >= prevGone) {
            gone[oldPath] = @(departedTime);
        }
    }
    if (!sameRepo) {
        [moves removeObjectForKey:record.uuid];
        for (SeafFPRecord *child in children) {
            [moves removeObjectForKey:child.uuid];
        }
        [self saveActivityStateLockedForRepo:oldRepo seen:seen gone:gone moves:moves];
        [seen removeAllObjects];
        [gone removeAllObjects];
        [moves removeAllObjects];
        [self loadActivityStateLockedForRepo:newRepo seen:seen gone:gone moves:moves];
    }

    moves[record.uuid] = @{
        @"from": (sameRepo && oldPath) ? oldPath : @"",
        @"to": newPath ?: @"",
        @"time": @0,
        @"replaced": @(replacedPriorOccupant),
    };
    NSString *oldPrefix = [oldPath stringByAppendingString:@"/"];
    for (SeafFPRecord *child in children) {
        if (![child.path hasPrefix:[newPath stringByAppendingString:@"/"]]) continue;
        NSString *rel = [child.path substringFromIndex:newPath.length];
        NSString *childOldPath = (sameRepo && oldPrefix.length > 1) ? [oldPath stringByAppendingString:rel] : @"";
        moves[child.uuid] = @{
            @"from": childOldPath,
            @"to": child.path ?: @"",
            @"time": @0,
            @"replaced": @(replacedPriorOccupant),
        };
    }
    [self saveActivityStateLockedForRepo:newRepo seen:seen gone:gone moves:moves];
}

- (void)clearRecordedActivityMoveLockedForRepo:(NSString *)repoId uuid:(NSString *)uuid
{
    if (repoId.length == 0 || uuid.length == 0) return;
    NSMutableOrderedSet<NSString *> *seen = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary<NSString *, NSNumber *> *gone = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *moves = [NSMutableDictionary dictionary];
    [self loadActivityStateLockedForRepo:repoId seen:seen gone:gone moves:moves];
    if (moves[uuid]) {
        [moves removeObjectForKey:uuid];
        [self saveActivityStateLockedForRepo:repoId seen:seen gone:gone moves:moves];
    }
}

- (BOOL)applyActivitiesOfRepo:(NSString *)repoId entries:(NSArray<NSDictionary *> *)entries
{
    if (repoId.length == 0 || entries.count == 0) return NO;
    return [self performIndexWrite:^BOOL(BOOL *rollback) {
        NSMutableOrderedSet<NSString *> *persistedSeen = [NSMutableOrderedSet orderedSet];
        NSMutableDictionary<NSString *, NSNumber *> *persistedGone = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSDictionary *> *persistedMoves = [NSMutableDictionary dictionary];
        [self loadActivityStateLockedForRepo:repoId seen:persistedSeen gone:persistedGone moves:persistedMoves];
        NSMutableDictionary<NSString *, NSNumber *> *inBatchGone = [NSMutableDictionary dictionary];

        NSMutableDictionary<NSString *, NSNumber *> *occurrenceCounts = [NSMutableDictionary dictionaryWithCapacity:entries.count];
        NSMutableArray<NSString *> *entryKeys = [NSMutableArray arrayWithCapacity:entries.count];
        for (NSDictionary *entry in entries) {
            NSString *op = SeafFPEntryString(entry, SeafFPEntryOp) ?: @"";
            NSString *path = [SeafFPIdentifier normalizedPath:SeafFPEntryString(entry, SeafFPEntryPath)];
            NSString *rawOld = SeafFPEntryString(entry, SeafFPEntryOldPath);
            NSString *oldPath = rawOld ? [SeafFPIdentifier normalizedPath:rawOld] : @"";
            BOOL isDir = [entry[SeafFPEntryIsDir] boolValue];
            long long eventTime = SeafFPEntryNumber(entry, SeafFPEntryMtime, 0);
            NSString *baseKey = [NSString stringWithFormat:@"%@|%d|%lld|%@|%@", op, isDir ? 1 : 0, eventTime, path, oldPath];
            NSUInteger occ = [occurrenceCounts[baseKey] unsignedIntegerValue];
            occurrenceCounts[baseKey] = @(occ + 1);
            NSString *fullKey = occ == 0 ? baseKey : [NSString stringWithFormat:@"%@#%lu", baseKey, (unsigned long)occ];
            [entryKeys addObject:fullKey];
        }

        void (^recordGonePath)(NSString *, long long) = ^(NSString *gonePath, long long eventTime) {
            if (gonePath.length == 0 || [gonePath isEqualToString:@"/"] || eventTime <= 0) return;
            long long prevP = [persistedGone[gonePath] longLongValue];
            if (eventTime >= prevP) persistedGone[gonePath] = @(eventTime);
            long long prevB = [inBatchGone[gonePath] longLongValue];
            if (eventTime >= prevB) inBatchGone[gonePath] = @(eventTime);
        };

        void (^clearGonePathIfSuperseded)(NSString *, long long) = ^(NSString *livePath, long long eventTime) {
            if (livePath.length == 0 || [livePath isEqualToString:@"/"]) return;
            NSNumber *pGone = persistedGone[livePath];
            if (pGone && (eventTime <= 0 || eventTime >= pGone.longLongValue)) {
                [persistedGone removeObjectForKey:livePath];
            }
            NSNumber *bGone = inBatchGone[livePath];
            if (bGone && (eventTime <= 0 || eventTime >= bGone.longLongValue)) {
                [inBatchGone removeObjectForKey:livePath];
            }
        };

        BOOL (^isPathGone)(NSString *, long long) = ^BOOL(NSString *candPath, long long eventTime) {
            for (NSString *anc in SeafFPAncestorPaths(candPath, YES)) {
                NSNumber *pGone = persistedGone[anc];
                if (pGone && (eventTime <= 0 || eventTime <= pGone.longLongValue)) {
                    return YES;
                }
                NSNumber *bGone = inBatchGone[anc];
                if (bGone && eventTime > 0 && eventTime < bGone.longLongValue) {
                    return YES;
                }
            }
            return NO;
        };

        BOOL (^isProtectedMovedSingleRecordAt)(SeafFPRecord *, NSUInteger, long long) = ^BOOL(SeafFPRecord *rec, NSUInteger startIndex, long long eventTime) {
            if (!rec || rec.deleted || eventTime <= 0) return NO;
            NSDictionary *mv = persistedMoves[rec.uuid];
            if ([mv isKindOfClass:[NSDictionary class]] && [mv[@"to"] isEqualToString:rec.path]) {
                long long mvTime = [mv[@"time"] longLongValue];
                if (mvTime > eventTime) return YES;
                if (mvTime == 0) {
                    if ([mv[@"replaced"] boolValue]) return YES;
                    NSString *mvFrom = mv[@"from"];
                    for (NSUInteger j = startIndex + 1; j < entries.count; j++) {
                        NSDictionary *later = entries[j];
                        NSString *laterOp = SeafFPEntryString(later, SeafFPEntryOp);
                        if (![laterOp isEqualToString:SeafFPActivityOpMove]) continue;
                        long long laterTime = SeafFPEntryNumber(later, SeafFPEntryMtime, 0);
                        if (laterTime > 0 && laterTime < eventTime) continue;
                        NSString *laterPath = [SeafFPIdentifier normalizedPath:SeafFPEntryString(later, SeafFPEntryPath)];
                        NSString *rawLaterOld = SeafFPEntryString(later, SeafFPEntryOldPath);
                        NSString *laterOld = rawLaterOld ? [SeafFPIdentifier normalizedPath:rawLaterOld] : @"";
                        if ([rec.path isEqualToString:laterPath]
                            && (mvFrom.length == 0 || [mvFrom isEqualToString:laterOld])) {
                            return YES;
                        }
                        if ([rec.path hasPrefix:[laterPath stringByAppendingString:@"/"]]) {
                            return YES;
                        }
                    }
                }
            }
            return NO;
        };

        BOOL (^isProtectedMovedRecordAt)(SeafFPRecord *, NSUInteger, long long) = ^BOOL(SeafFPRecord *rec, NSUInteger startIndex, long long eventTime) {
            if (isProtectedMovedSingleRecordAt(rec, startIndex, eventTime)) return YES;
            if (rec && !rec.deleted && rec.isDir) {
                for (SeafFPRecord *sub in [self subtreeRecordsLockedOf:rec]) {
                    if (!sub.deleted && isProtectedMovedSingleRecordAt(sub, startIndex, eventTime)) {
                        return YES;
                    }
                }
            }
            return NO;
        };

        // Follows subsequent moves and deletes in the same batch for a path that
        // is not yet in the store: returns nil when a later event moves `startPath`
        // itself (that later move entry will handle the target) or deletes it/its
        // ancestor, and rewrites `startPath` when an unindexed ancestor directory
        // is renamed later in the batch.
        NSString * (^resolveUnknownPathInBatch)(NSString *, NSUInteger, long long) = ^NSString *(NSString *startPath, NSUInteger startIndex, long long startTime) {
            NSString *curPath = startPath;
            for (NSUInteger j = startIndex + 1; j < entries.count; j++) {
                NSDictionary *later = entries[j];
                NSString *laterOp = SeafFPEntryString(later, SeafFPEntryOp);
                NSString *laterPath = [SeafFPIdentifier normalizedPath:SeafFPEntryString(later, SeafFPEntryPath)];
                if (!laterOp || [laterPath isEqualToString:@"/"]) continue;
                long long laterTime = SeafFPEntryNumber(later, SeafFPEntryMtime, 0);
                if (startTime > 0 && laterTime > 0 && laterTime < startTime) continue;
                if ([laterOp isEqualToString:SeafFPActivityOpDelete]) {
                    if ([curPath isEqualToString:laterPath]
                        || [curPath hasPrefix:[laterPath stringByAppendingString:@"/"]]) {
                        return nil;
                    }
                } else if ([laterOp isEqualToString:SeafFPActivityOpMove]) {
                    NSString *rawLaterOld = SeafFPEntryString(later, SeafFPEntryOldPath);
                    if (!rawLaterOld) continue;
                    NSString *laterOld = [SeafFPIdentifier normalizedPath:rawLaterOld];
                    if ([laterOld isEqualToString:@"/"]) continue;
                    if ([curPath isEqualToString:laterOld]) {
                        return nil;
                    }
                    NSString *oldPrefix = [laterOld stringByAppendingString:@"/"];
                    if ([curPath hasPrefix:oldPrefix]) {
                        SeafFPRecord *oldDirRec = [self recordLockedForRepo:repoId path:laterOld];
                        if (!oldDirRec || oldDirRec.deleted) {
                            curPath = [SeafFPIdentifier normalizedPath:[laterPath stringByAppendingString:[curPath substringFromIndex:laterOld.length]]];
                        }
                    }
                }
            }
            return curPath;
        };

        BOOL changed = NO;
        BOOL stateDirty = NO;
        for (NSUInteger i = 0; i < entries.count; i++) {
            NSString *entryKey = entryKeys[i];
            if ([persistedSeen containsObject:entryKey]) continue;

            NSDictionary *entry = entries[i];
            NSString *op = SeafFPEntryString(entry, SeafFPEntryOp);
            NSString *path = [SeafFPIdentifier normalizedPath:SeafFPEntryString(entry, SeafFPEntryPath)];
            if (!op || [path isEqualToString:@"/"]) continue;
            BOOL isDir = [entry[SeafFPEntryIsDir] boolValue];
            long long eventTime = SeafFPEntryNumber(entry, SeafFPEntryMtime, 0);
            BOOL ok = YES;
            if ([op isEqualToString:SeafFPActivityOpCreate]) {
                if (![self recordLockedForRepo:repoId path:path]) {
                    NSString *targetPath = resolveUnknownPathInBatch(path, i, eventTime);
                    if (targetPath && !isPathGone(targetPath, eventTime)) {
                        ok = [self insertUnknownLockedForRepo:repoId path:targetPath isDir:isDir mtime:eventTime changed:&changed];
                        if (ok && [targetPath isEqualToString:path]) {
                            clearGonePathIfSuperseded(path, eventTime);
                        }
                    }
                }
            } else if ([op isEqualToString:SeafFPActivityOpDelete]) {
                if (eventTime > 0) {
                    recordGonePath(path, eventTime);
                    stateDirty = YES;
                }
                SeafFPRecord *record = [self recordLockedForRepo:repoId path:path];
                if (record && !record.deleted && eventTime > 0
                    && record.mtime <= eventTime
                    && !isProtectedMovedRecordAt(record, i, eventTime)
                    && !(record.isDir && [self hasLiveSubtreeRecordLockedOf:record newerThan:eventTime])) {
                    [self markDeletedLockedUUID:record.uuid];
                    [persistedMoves removeObjectForKey:record.uuid];
                    changed = YES;
                }
            } else if ([op isEqualToString:SeafFPActivityOpMove]) {
                NSString *oldPath = SeafFPEntryString(entry, SeafFPEntryOldPath);
                NSString *normOldPath = oldPath ? [SeafFPIdentifier normalizedPath:oldPath] : nil;
                if (normOldPath && ![normOldPath isEqualToString:@"/"] && eventTime > 0) {
                    recordGonePath(normOldPath, eventTime);
                    stateDirty = YES;
                }
                SeafFPRecord *record = normOldPath ? [self recordLockedForRepo:repoId path:normOldPath] : nil;
                if (!record || record.deleted || [record.path isEqualToString:@"/"]) {
                    SeafFPRecord *existingTarget = [self recordLockedForRepo:repoId path:path];
                    if (existingTarget && !existingTarget.deleted && normOldPath) {
                        NSDictionary *mv = persistedMoves[existingTarget.uuid];
                        if ([mv isKindOfClass:[NSDictionary class]]
                            && [mv[@"to"] isEqualToString:path]
                            && ([mv[@"from"] length] == 0 || [mv[@"from"] isEqualToString:normOldPath])) {
                            persistedMoves[existingTarget.uuid] = @{
                                @"from": normOldPath,
                                @"to": path,
                                @"time": @(eventTime),
                                @"replaced": @NO,
                            };
                            clearGonePathIfSuperseded(path, eventTime);
                            stateDirty = YES;
                        }
                    } else if (!existingTarget) {
                        NSString *targetPath = resolveUnknownPathInBatch(path, i, eventTime);
                        if (targetPath && !isPathGone(targetPath, eventTime)) {
                            ok = [self insertUnknownLockedForRepo:repoId path:targetPath isDir:isDir mtime:eventTime changed:&changed];
                            if (ok && [targetPath isEqualToString:path]) {
                                clearGonePathIfSuperseded(path, eventTime);
                            }
                        }
                    }
                } else if (eventTime > 0 && (record.mtime > eventTime
                           || isProtectedMovedRecordAt(record, i, eventTime)
                           || (record.isDir && [self hasLiveSubtreeRecordLockedOf:record newerThan:eventTime]))) {
                    // the row at the old path is a later entry, not the one that moved
                } else {
                    SeafFPRecord *occupant = [self recordLockedForRepo:repoId path:path];
                    if (!occupant || (!occupant.deleted && [occupant.uuid isEqualToString:record.uuid])) {
                        NSString *parentUUID = nil;
                        if (![self isPathLockedTombstonedForRepo:repoId path:path]
                            && [self ensureDirectoryLockedForRepo:repoId path:path.stringByDeletingLastPathComponent
                                                      allowRevive:NO uuid:&parentUUID changed:&changed]) {
                            SeafFPRecord *moved = [self moveRecordLockedUUID:record.uuid
                                                                      toRepo:repoId
                                                                        path:path
                                                                  parentUUID:parentUUID
                                                          recordActivityMove:NO];
                            ok = (moved != nil);
                            if (ok) {
                                persistedMoves[record.uuid] = @{
                                    @"from": normOldPath ?: @"",
                                    @"to": path,
                                    @"time": @(eventTime),
                                    @"replaced": @NO,
                                };
                                changed = YES;
                                clearGonePathIfSuperseded(path, eventTime);
                            }
                        }
                    }
                }
            }
            if (!ok) {
                *rollback = YES;
                return NO;
            }
            [persistedSeen addObject:entryKey];
            stateDirty = YES;
        }
        if (stateDirty) {
            [self saveActivityStateLockedForRepo:repoId seen:persistedSeen gone:persistedGone moves:persistedMoves];
        }
        return changed;
    }];
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
