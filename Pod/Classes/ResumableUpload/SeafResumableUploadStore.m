//
//  SeafResumableUploadStore.m
//  Seafile
//

#import "SeafResumableUploadStore.h"
#import <sqlite3.h>

static const NSTimeInterval kNotEnabledTTL = 24 * 3600;
static const NSTimeInterval kRegressionWindow = 24 * 3600;

static NSString * const kAppTokenPrefix = @"app-";

static NSString * const kColumns =
    @"attempt_id, task_id, account, repo_id, parent_dir, target_name, target_key, staging_name, overwrite, "
    @"file_size, last_modify, file_identity, chunk_size, chunk_hashes, confirmed_offset, inflight_end, inflight_hash, "
    @"state, final_sent_at, committed_name, oid, rename_snapshot, final_name, staging_committed, verified, "
    @"run_token, heartbeat_at, reason, created_at, updated_at, entry, probe_windows";

/// Number of columns in kColumns; bound as ?1...?kColumnCount.
static int ColumnCount(void)
{
    return (int)[kColumns componentsSeparatedByString:@", "].count;
}

@implementation SeafResumableUploadStore {
    sqlite3 *_db;
    dispatch_queue_t _queue;
}

- (instancetype)initWithPath:(NSString *)path
{
    if (!(self = [super init])) return nil;
    _staleAfter = 5 * 60;
    _queue = dispatch_queue_create("com.seafile.resumable-upload-store", DISPATCH_QUEUE_SERIAL);
    int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX;
    if (sqlite3_open_v2(path.fileSystemRepresentation, &_db, flags, NULL) != SQLITE_OK) {
        NSLog(@"[ResumableUpload] cannot open store %@: %s", path, _db ? sqlite3_errmsg(_db) : "");
        if (_db) sqlite3_close(_db);
        _db = NULL;
        return nil;
    }
    sqlite3_busy_timeout(_db, 5000);
    [self exec:@"PRAGMA journal_mode=WAL"];
    if (![self migrate]) {
        sqlite3_close(_db);
        _db = NULL;
        return nil;
    }
    return self;
}

- (void)dealloc
{
    if (_db) sqlite3_close(_db);
}

#pragma mark - SQLite helpers

- (BOOL)exec:(NSString *)sql
{
    char *err = NULL;
    int rc = sqlite3_exec(_db, sql.UTF8String, NULL, NULL, &err);
    if (rc != SQLITE_OK) {
        NSLog(@"[ResumableUpload] sql failed (%d) %@: %s", rc, sql, err ?: "");
        sqlite3_free(err);
        return NO;
    }
    return YES;
}

- (BOOL)migrate
{
    NSString *attempts = @"CREATE TABLE IF NOT EXISTS attempts ("
        "attempt_id TEXT PRIMARY KEY, task_id TEXT NOT NULL, account TEXT NOT NULL, repo_id TEXT NOT NULL, "
        "parent_dir TEXT NOT NULL, target_name TEXT NOT NULL, target_key TEXT NOT NULL, staging_name TEXT NOT NULL, "
        "overwrite INTEGER NOT NULL DEFAULT 0, file_size INTEGER NOT NULL, last_modify TEXT, file_identity TEXT, "
        "chunk_size INTEGER NOT NULL, chunk_hashes TEXT NOT NULL DEFAULT '', confirmed_offset INTEGER NOT NULL DEFAULT 0, "
        "inflight_end INTEGER NOT NULL DEFAULT 0, inflight_hash TEXT, state INTEGER NOT NULL, final_sent_at REAL NOT NULL DEFAULT 0, "
        "committed_name TEXT, oid TEXT, rename_snapshot TEXT, final_name TEXT, staging_committed INTEGER NOT NULL DEFAULT 0, "
        "verified INTEGER NOT NULL DEFAULT 0, run_token TEXT, heartbeat_at REAL NOT NULL DEFAULT 0, reason TEXT, "
        "created_at REAL NOT NULL, updated_at REAL NOT NULL, entry TEXT, probe_windows TEXT)";
    NSString *tombstones = @"CREATE TABLE IF NOT EXISTS tombstones (account TEXT NOT NULL, repo_id TEXT NOT NULL, "
        "parent_dir TEXT NOT NULL, staging_name TEXT NOT NULL, check_until REAL NOT NULL, "
        "PRIMARY KEY (account, repo_id, parent_dir, staging_name))";
    NSString *flags = @"CREATE TABLE IF NOT EXISTS account_flags (account TEXT PRIMARY KEY, "
        "not_enabled_until REAL NOT NULL DEFAULT 0, disabled_until REAL NOT NULL DEFAULT 0, disabled_version TEXT, "
        "disabled_reason TEXT, regressions TEXT NOT NULL DEFAULT '')";
    NSArray *statements = @[
        attempts,
        @"CREATE UNIQUE INDEX IF NOT EXISTS attempts_active_task ON attempts(task_id) WHERE state IN (0,1,2,3)",
        @"CREATE UNIQUE INDEX IF NOT EXISTS attempts_active_target ON attempts(target_key) WHERE state IN (0,1,2,3)",
        @"CREATE INDEX IF NOT EXISTS attempts_task ON attempts(task_id)",
        @"CREATE INDEX IF NOT EXISTS attempts_account ON attempts(account)",
        tombstones,
        flags,
    ];
    for (NSString *sql in statements) {
        if (![self exec:sql]) return NO;
    }
    // Columns added after the first schema; older stores get them here.
    for (NSString *column in @[@"entry", @"probe_windows"]) {
        if (![self addColumnIfMissing:column type:@"TEXT"]) return NO;
    }
    return YES;
}

- (BOOL)addColumnIfMissing:(NSString *)column type:(NSString *)type
{
    sqlite3_stmt *stmt = [self prepare:@"PRAGMA table_info(attempts)"];
    if (!stmt) return NO;
    BOOL found = NO;
    while (!found && sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *name = sqlite3_column_text(stmt, 1);
        found = name && strcmp((const char *)name, column.UTF8String) == 0;
    }
    sqlite3_finalize(stmt);
    if (found) return YES;
    return [self exec:[NSString stringWithFormat:@"ALTER TABLE attempts ADD COLUMN %@ %@", column, type]];
}

static void BindText(sqlite3_stmt *stmt, int idx, NSString *value)
{
    if (value) sqlite3_bind_text(stmt, idx, value.UTF8String, -1, SQLITE_TRANSIENT);
    else sqlite3_bind_null(stmt, idx);
}

static NSString *ColumnText(sqlite3_stmt *stmt, int idx)
{
    const unsigned char *text = sqlite3_column_text(stmt, idx);
    return text ? [NSString stringWithUTF8String:(const char *)text] : nil;
}

- (sqlite3_stmt *)prepare:(NSString *)sql
{
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
        NSLog(@"[ResumableUpload] prepare failed %@: %s", sql, sqlite3_errmsg(_db));
        return NULL;
    }
    return stmt;
}

/// Runs `block` inside BEGIN IMMEDIATE; commits when it returns YES.
- (BOOL)write:(BOOL (^)(void))block
{
    if (!_db) return NO;
    __block BOOL ok = NO;
    dispatch_sync(_queue, ^{
        if (![self exec:@"BEGIN IMMEDIATE"]) return;
        ok = block();
        if (ok) ok = [self exec:@"COMMIT"];
        if (!ok) [self exec:@"ROLLBACK"];
    });
    return ok;
}

- (void)read:(void (^)(void))block
{
    if (!_db) return;
    dispatch_sync(_queue, block);
}

- (int)step:(sqlite3_stmt *)stmt
{
    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE && rc != SQLITE_ROW) {
        NSLog(@"[ResumableUpload] step failed (%d): %s", rc, sqlite3_errmsg(_db));
    }
    return rc;
}

#pragma mark - Row mapping

- (void)bindRecord:(SeafResumableUploadRecord *)r to:(sqlite3_stmt *)stmt
{
    NSString *snapshot = nil;
    if (r.renameSnapshot) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:r.renameSnapshot options:0 error:nil];
        snapshot = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    }
    NSString *windows = nil;
    if (r.probeWindows) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:[r.probeWindows valueForKey:@"dictionaryRepresentation"]
                                                       options:0 error:nil];
        windows = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    }
    BindText(stmt, 1, r.attemptId);
    BindText(stmt, 2, r.taskId);
    BindText(stmt, 3, r.account);
    BindText(stmt, 4, r.repoId);
    BindText(stmt, 5, r.parentDir);
    BindText(stmt, 6, r.targetName);
    BindText(stmt, 7, r.targetKey);
    BindText(stmt, 8, r.stagingName);
    sqlite3_bind_int(stmt, 9, r.overwrite ? 1 : 0);
    sqlite3_bind_int64(stmt, 10, r.fileSize);
    BindText(stmt, 11, r.lastModify);
    BindText(stmt, 12, r.fileIdentity);
    sqlite3_bind_int64(stmt, 13, r.chunkSize);
    BindText(stmt, 14, [r.chunkHashes componentsJoinedByString:@","]);
    sqlite3_bind_int64(stmt, 15, r.confirmedOffset);
    sqlite3_bind_int64(stmt, 16, r.inflightEnd);
    BindText(stmt, 17, r.inflightHash);
    sqlite3_bind_int(stmt, 18, (int)r.state);
    sqlite3_bind_double(stmt, 19, r.finalSentAt);
    BindText(stmt, 20, r.committedName);
    BindText(stmt, 21, r.oid);
    BindText(stmt, 22, snapshot);
    BindText(stmt, 23, r.finalName);
    sqlite3_bind_int(stmt, 24, r.stagingCommitted ? 1 : 0);
    sqlite3_bind_int(stmt, 25, r.verified ? 1 : 0);
    BindText(stmt, 26, r.runToken);
    sqlite3_bind_double(stmt, 27, r.heartbeatAt);
    BindText(stmt, 28, r.reason);
    sqlite3_bind_double(stmt, 29, r.createdAt);
    sqlite3_bind_double(stmt, 30, r.updatedAt);
    BindText(stmt, 31, r.entry);
    BindText(stmt, 32, windows);
}

- (SeafResumableUploadRecord *)recordFromStatement:(sqlite3_stmt *)stmt
{
    SeafResumableUploadRecord *r = [SeafResumableUploadRecord new];
    r.attemptId = ColumnText(stmt, 0) ?: @"";
    r.taskId = ColumnText(stmt, 1) ?: @"";
    r.account = ColumnText(stmt, 2) ?: @"";
    r.repoId = ColumnText(stmt, 3) ?: @"";
    r.parentDir = ColumnText(stmt, 4) ?: @"/";
    r.targetName = ColumnText(stmt, 5) ?: @"";
    r.stagingName = ColumnText(stmt, 7) ?: @"";
    r.overwrite = sqlite3_column_int(stmt, 8) != 0;
    r.fileSize = sqlite3_column_int64(stmt, 9);
    r.lastModify = ColumnText(stmt, 10);
    r.fileIdentity = ColumnText(stmt, 11);
    r.chunkSize = sqlite3_column_int64(stmt, 12);
    NSString *hashes = ColumnText(stmt, 13);
    r.chunkHashes = hashes.length > 0 ? [hashes componentsSeparatedByString:@","] : @[];
    r.confirmedOffset = sqlite3_column_int64(stmt, 14);
    r.inflightEnd = sqlite3_column_int64(stmt, 15);
    r.inflightHash = ColumnText(stmt, 16);
    r.state = (SeafResumableState)sqlite3_column_int(stmt, 17);
    r.finalSentAt = sqlite3_column_double(stmt, 18);
    r.committedName = ColumnText(stmt, 19);
    r.oid = ColumnText(stmt, 20);
    NSString *snapshot = ColumnText(stmt, 21);
    if (snapshot.length > 0) {
        id obj = [NSJSONSerialization JSONObjectWithData:[snapshot dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        r.renameSnapshot = [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
    }
    r.finalName = ColumnText(stmt, 22);
    r.stagingCommitted = sqlite3_column_int(stmt, 23) != 0;
    r.verified = sqlite3_column_int(stmt, 24) != 0;
    r.runToken = ColumnText(stmt, 25);
    r.heartbeatAt = sqlite3_column_double(stmt, 26);
    r.reason = ColumnText(stmt, 27);
    r.createdAt = sqlite3_column_double(stmt, 28);
    r.updatedAt = sqlite3_column_double(stmt, 29);
    r.entry = ColumnText(stmt, 30);
    NSString *windows = ColumnText(stmt, 31);
    if (windows.length > 0) {
        id obj = [NSJSONSerialization JSONObjectWithData:[windows dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if ([obj isKindOfClass:[NSArray class]]) {
            NSMutableArray *list = [NSMutableArray array];
            for (id item in obj) {
                SeafProbeWindow *w = [SeafProbeWindow windowWithDictionary:item];
                if (!w) { list = nil; break; }
                [list addObject:w];
            }
            // A damaged list is dropped: the check then needs the source file again.
            r.probeWindows = list;
        }
    }
    return r;
}

- (NSArray<SeafResumableUploadRecord *> *)selectWhere:(NSString *)where bind:(void (^)(sqlite3_stmt *stmt))bind
{
    NSMutableArray *rows = [NSMutableArray array];
    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM attempts WHERE %@", kColumns, where];
    sqlite3_stmt *stmt = [self prepare:sql];
    if (!stmt) return rows;
    if (bind) bind(stmt);
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        [rows addObject:[self recordFromStatement:stmt]];
    }
    sqlite3_finalize(stmt);
    return rows;
}

- (NSString *)makeRunToken
{
    NSString *uuid = [NSUUID UUID].UUIDString;
    NSString *launch = self.mainAppLaunchId;
    return launch.length > 0 ? [NSString stringWithFormat:@"%@%@-%@", kAppTokenPrefix, launch, uuid] : uuid;
}

- (BOOL)isRunTokenOfEndedLaunch:(NSString *)runToken
{
    NSString *launch = self.mainAppLaunchId;
    if (launch.length == 0 || ![runToken hasPrefix:kAppTokenPrefix]) return NO;
    NSString *own = [NSString stringWithFormat:@"%@%@-", kAppTokenPrefix, launch];
    return ![runToken hasPrefix:own];
}

- (BOOL)isLive:(SeafResumableUploadRecord *)r now:(NSTimeInterval)now
{
    if (r.runToken.length == 0 || now - r.heartbeatAt >= self.staleAfter) return NO;
    return ![self isRunTokenOfEndedLaunch:r.runToken];
}

- (BOOL)isRecordLive:(SeafResumableUploadRecord *)record now:(NSTimeInterval)now
{
    return [self isLive:record now:now];
}

- (NSSet<NSString *> *)liveRunTokens
{
    NSMutableSet *tokens = [NSMutableSet set];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    [self read:^{
        for (SeafResumableUploadRecord *r in [self selectWhere:@"state IN (0,1,2,3) AND run_token IS NOT NULL" bind:nil]) {
            if ([self isLive:r now:now]) [tokens addObject:r.runToken];
        }
    }];
    return tokens;
}

- (BOOL)updateState:(SeafResumableState)state reason:(NSString *)reason forAttempt:(NSString *)attemptId
{
    sqlite3_stmt *stmt = [self prepare:@"UPDATE attempts SET state = ?, reason = ?, run_token = NULL, updated_at = ? WHERE attempt_id = ?"];
    if (!stmt) return NO;
    sqlite3_bind_int(stmt, 1, (int)state);
    BindText(stmt, 2, reason);
    sqlite3_bind_double(stmt, 3, [NSDate date].timeIntervalSince1970);
    BindText(stmt, 4, attemptId);
    BOOL ok = [self step:stmt] == SQLITE_DONE;
    sqlite3_finalize(stmt);
    return ok;
}

#pragma mark - Attempts

- (SeafResumableUploadRecord *)recordForTaskId:(NSString *)taskId
{
    __block SeafResumableUploadRecord *found = nil;
    [self read:^{
        NSArray *rows = [self selectWhere:@"task_id = ? AND state IN (0,1,2,3,4) ORDER BY (state = 4) ASC, updated_at DESC LIMIT 1"
                                     bind:^(sqlite3_stmt *stmt) { BindText(stmt, 1, taskId); }];
        found = rows.firstObject;
    }];
    return found;
}

- (SeafResumableUploadRecord *)recordWithAttemptId:(NSString *)attemptId
{
    __block SeafResumableUploadRecord *found = nil;
    [self read:^{
        found = [self selectWhere:@"attempt_id = ?" bind:^(sqlite3_stmt *stmt) { BindText(stmt, 1, attemptId); }].firstObject;
    }];
    return found;
}

- (SeafResumableClaim)insertAttempt:(SeafResumableUploadRecord *)record
                           replaced:(NSArray<SeafResumableUploadRecord *> **)replaced
{
    __block SeafResumableClaim result = SeafResumableClaimFailed;
    NSMutableArray *abandoned = [NSMutableArray array];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    record.createdAt = now;
    record.updatedAt = now;
    record.heartbeatAt = now;
    BOOL ok = [self write:^BOOL{
        NSArray *conflicts = [self selectWhere:@"state IN (0,1,2,3) AND (task_id = ? OR target_key = ?)" bind:^(sqlite3_stmt *stmt) {
            BindText(stmt, 1, record.taskId);
            BindText(stmt, 2, record.targetKey);
        }];
        for (SeafResumableUploadRecord *other in conflicts) {
            if ([self isLive:other now:now] && ![other.runToken isEqualToString:record.runToken]) {
                result = SeafResumableClaimBusy;
                return NO;
            }
        }
        for (SeafResumableUploadRecord *other in conflicts) {
            if (![self updateState:SeafResumableStateAbandoned reason:@"replaced" forAttempt:other.attemptId]) return NO;
            other.state = SeafResumableStateAbandoned;
            [abandoned addObject:other];
        }
        NSMutableArray *marks = [NSMutableArray array];
        for (int i = 0; i < ColumnCount(); i++) [marks addObject:@"?"];
        NSString *sql = [NSString stringWithFormat:@"INSERT INTO attempts (%@) VALUES (%@)", kColumns,
                         [marks componentsJoinedByString:@","]];
        sqlite3_stmt *stmt = [self prepare:sql];
        if (!stmt) return NO;
        [self bindRecord:record to:stmt];
        BOOL inserted = [self step:stmt] == SQLITE_DONE;
        sqlite3_finalize(stmt);
        return inserted;
    }];
    if (ok) {
        result = SeafResumableClaimGranted;
        if (replaced) *replaced = abandoned;
    }
    return result;
}

- (SeafResumableClaim)claimAttempt:(NSString *)attemptId runToken:(NSString *)runToken
{
    __block SeafResumableClaim result = SeafResumableClaimFailed;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    [self write:^BOOL{
        SeafResumableUploadRecord *r = [self selectWhere:@"attempt_id = ?" bind:^(sqlite3_stmt *stmt) {
            BindText(stmt, 1, attemptId);
        }].firstObject;
        if (!r || !r.isActive) { result = SeafResumableClaimGone; return NO; }
        if ([self isLive:r now:now] && ![r.runToken isEqualToString:runToken]) { result = SeafResumableClaimBusy; return NO; }
        sqlite3_stmt *stmt = [self prepare:@"UPDATE attempts SET run_token = ?, heartbeat_at = ?, updated_at = ? WHERE attempt_id = ?"];
        if (!stmt) return NO;
        BindText(stmt, 1, runToken);
        sqlite3_bind_double(stmt, 2, now);
        sqlite3_bind_double(stmt, 3, now);
        BindText(stmt, 4, attemptId);
        BOOL ok = [self step:stmt] == SQLITE_DONE;
        sqlite3_finalize(stmt);
        if (ok) result = SeafResumableClaimGranted;
        return ok;
    }];
    return result;
}

- (BOOL)saveRecord:(SeafResumableUploadRecord *)record
{
    if (record.runToken.length == 0) return NO;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    record.updatedAt = now;
    record.heartbeatAt = now;
    __block BOOL changed = NO;
    [self write:^BOOL{
        // UPDATE rather than REPLACE: REPLACE would silently delete any other
        // row that collides with the partial unique indexes.
        NSMutableArray *assignments = [NSMutableArray array];
        NSArray *columns = [kColumns componentsSeparatedByString:@", "];
        for (NSUInteger i = 0; i < columns.count; i++) {
            [assignments addObject:[NSString stringWithFormat:@"%@ = ?%lu", columns[i], (unsigned long)(i + 1)]];
        }
        int n = ColumnCount();
        NSString *sql = [NSString stringWithFormat:@"UPDATE attempts SET %@ WHERE attempt_id = ?%d AND run_token = ?%d",
                         [assignments componentsJoinedByString:@", "], n + 1, n + 2];
        sqlite3_stmt *stmt = [self prepare:sql];
        if (!stmt) return NO;
        [self bindRecord:record to:stmt];
        BindText(stmt, n + 1, record.attemptId);
        BindText(stmt, n + 2, record.runToken);
        BOOL ok = [self step:stmt] == SQLITE_DONE;
        changed = ok && sqlite3_changes(self->_db) > 0;
        sqlite3_finalize(stmt);
        return ok;
    }];
    return changed;
}

- (BOOL)heartbeatAttempt:(NSString *)attemptId runToken:(NSString *)runToken
{
    __block BOOL changed = NO;
    [self write:^BOOL{
        sqlite3_stmt *stmt = [self prepare:@"UPDATE attempts SET heartbeat_at = ? WHERE attempt_id = ? AND run_token = ?"];
        if (!stmt) return NO;
        sqlite3_bind_double(stmt, 1, [NSDate date].timeIntervalSince1970);
        BindText(stmt, 2, attemptId);
        BindText(stmt, 3, runToken);
        BOOL ok = [self step:stmt] == SQLITE_DONE;
        changed = ok && sqlite3_changes(self->_db) > 0;
        sqlite3_finalize(stmt);
        return ok;
    }];
    return changed;
}

- (void)releaseAttempt:(NSString *)attemptId runToken:(NSString *)runToken
{
    [self write:^BOOL{
        sqlite3_stmt *stmt = [self prepare:@"UPDATE attempts SET run_token = NULL WHERE attempt_id = ? AND run_token = ?"];
        if (!stmt) return NO;
        BindText(stmt, 1, attemptId);
        BindText(stmt, 2, runToken);
        BOOL ok = [self step:stmt] == SQLITE_DONE;
        sqlite3_finalize(stmt);
        return ok;
    }];
}

- (void)abandonAttempt:(NSString *)attemptId reason:(NSString *)reason
{
    [self write:^BOOL{
        return [self updateState:SeafResumableStateAbandoned reason:reason forAttempt:attemptId];
    }];
}

- (void)deleteAttempt:(NSString *)attemptId
{
    [self write:^BOOL{
        sqlite3_stmt *stmt = [self prepare:@"DELETE FROM attempts WHERE attempt_id = ?"];
        if (!stmt) return NO;
        BindText(stmt, 1, attemptId);
        BOOL ok = [self step:stmt] == SQLITE_DONE;
        sqlite3_finalize(stmt);
        return ok;
    }];
}

- (void)acknowledgeTaskId:(NSString *)taskId
{
    if (taskId.length == 0) return;
    [self write:^BOOL{
        sqlite3_stmt *stmt = [self prepare:@"DELETE FROM attempts WHERE task_id = ? AND state = 4"];
        if (!stmt) return NO;
        BindText(stmt, 1, taskId);
        BOOL ok = [self step:stmt] == SQLITE_DONE;
        sqlite3_finalize(stmt);
        return ok;
    }];
}

- (void)abandonTaskIds:(NSArray<NSString *> *)taskIds reason:(NSString *)reason
{
    if (taskIds.count == 0) return;
    [self write:^BOOL{
        for (NSString *taskId in taskIds) {
            sqlite3_stmt *stmt = [self prepare:@"UPDATE attempts SET state = 5, reason = ?, run_token = NULL, updated_at = ? "
                                                "WHERE task_id = ? AND state IN (0,1,2,3)"];
            if (!stmt) return NO;
            BindText(stmt, 1, reason);
            sqlite3_bind_double(stmt, 2, [NSDate date].timeIntervalSince1970);
            BindText(stmt, 3, taskId);
            BOOL ok = [self step:stmt] == SQLITE_DONE;
            sqlite3_finalize(stmt);
            if (!ok) return NO;
        }
        return YES;
    }];
}

- (NSArray<SeafResumableUploadRecord *> *)recordsForAccount:(NSString *)account
{
    __block NSArray *rows = @[];
    [self read:^{
        rows = [self selectWhere:@"account = ? ORDER BY updated_at" bind:^(sqlite3_stmt *stmt) { BindText(stmt, 1, account); }];
    }];
    return rows;
}

- (void)deleteAllForAccount:(NSString *)account
{
    [self write:^BOOL{
        for (NSString *sql in @[@"DELETE FROM attempts WHERE account = ?",
                                @"DELETE FROM tombstones WHERE account = ?",
                                @"DELETE FROM account_flags WHERE account = ?"]) {
            sqlite3_stmt *stmt = [self prepare:sql];
            if (!stmt) return NO;
            BindText(stmt, 1, account);
            BOOL ok = [self step:stmt] == SQLITE_DONE;
            sqlite3_finalize(stmt);
            if (!ok) return NO;
        }
        return YES;
    }];
}

#pragma mark - Tombstones

- (void)addTombstoneForAccount:(NSString *)account repoId:(NSString *)repoId
                     parentDir:(NSString *)parentDir stagingName:(NSString *)stagingName
                    checkUntil:(NSTimeInterval)checkUntil
{
    [self write:^BOOL{
        sqlite3_stmt *stmt = [self prepare:@"INSERT OR REPLACE INTO tombstones (account, repo_id, parent_dir, staging_name, check_until) VALUES (?,?,?,?,?)"];
        if (!stmt) return NO;
        BindText(stmt, 1, account);
        BindText(stmt, 2, repoId);
        BindText(stmt, 3, parentDir);
        BindText(stmt, 4, stagingName);
        sqlite3_bind_double(stmt, 5, checkUntil);
        BOOL ok = [self step:stmt] == SQLITE_DONE;
        sqlite3_finalize(stmt);
        return ok;
    }];
}

- (NSArray<NSDictionary *> *)tombstonesForAccount:(NSString *)account
{
    __block NSMutableArray *rows = [NSMutableArray array];
    [self read:^{
        sqlite3_stmt *stmt = [self prepare:@"SELECT account, repo_id, parent_dir, staging_name, check_until FROM tombstones WHERE account = ?"];
        if (!stmt) return;
        BindText(stmt, 1, account);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [rows addObject:@{ @"account": ColumnText(stmt, 0) ?: @"",
                               @"repo_id": ColumnText(stmt, 1) ?: @"",
                               @"parent_dir": ColumnText(stmt, 2) ?: @"/",
                               @"staging_name": ColumnText(stmt, 3) ?: @"",
                               @"check_until": @(sqlite3_column_double(stmt, 4)) }];
        }
        sqlite3_finalize(stmt);
    }];
    return rows;
}

- (void)removeTombstoneForAccount:(NSString *)account repoId:(NSString *)repoId
                        parentDir:(NSString *)parentDir stagingName:(NSString *)stagingName
{
    [self write:^BOOL{
        sqlite3_stmt *stmt = [self prepare:@"DELETE FROM tombstones WHERE account = ? AND repo_id = ? AND parent_dir = ? AND staging_name = ?"];
        if (!stmt) return NO;
        BindText(stmt, 1, account);
        BindText(stmt, 2, repoId);
        BindText(stmt, 3, parentDir);
        BindText(stmt, 4, stagingName);
        BOOL ok = [self step:stmt] == SQLITE_DONE;
        sqlite3_finalize(stmt);
        return ok;
    }];
}

#pragma mark - Account flags

- (BOOL)isSegmentingDisabledForAccount:(NSString *)account serverVersion:(NSString *)serverVersion
{
    __block BOOL disabled = NO;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    [self read:^{
        sqlite3_stmt *stmt = [self prepare:@"SELECT not_enabled_until, disabled_until, disabled_version FROM account_flags WHERE account = ?"];
        if (!stmt) return;
        BindText(stmt, 1, account);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            double notEnabledUntil = sqlite3_column_double(stmt, 0);
            double disabledUntil = sqlite3_column_double(stmt, 1);
            NSString *version = ColumnText(stmt, 2);
            disabled = now < notEnabledUntil || now < disabledUntil
                || (version.length > 0 && [version isEqualToString:serverVersion ?: @""]);
        }
        sqlite3_finalize(stmt);
    }];
    return disabled;
}

- (void)upsertFlagsForAccount:(NSString *)account set:(NSString *)assignments bind:(void (^)(sqlite3_stmt *stmt))bind
{
    [self write:^BOOL{
        sqlite3_stmt *ins = [self prepare:@"INSERT OR IGNORE INTO account_flags (account) VALUES (?)"];
        if (!ins) return NO;
        BindText(ins, 1, account);
        BOOL ok = [self step:ins] == SQLITE_DONE;
        sqlite3_finalize(ins);
        if (!ok) return NO;
        sqlite3_stmt *stmt = [self prepare:[NSString stringWithFormat:@"UPDATE account_flags SET %@ WHERE account = ?99", assignments]];
        if (!stmt) return NO;
        bind(stmt);
        BindText(stmt, 99, account);
        ok = [self step:stmt] == SQLITE_DONE;
        sqlite3_finalize(stmt);
        return ok;
    }];
}

- (void)markNotEnabledForAccount:(NSString *)account
{
    NSTimeInterval until = [NSDate date].timeIntervalSince1970 + kNotEnabledTTL;
    [self upsertFlagsForAccount:account set:@"not_enabled_until = ?1" bind:^(sqlite3_stmt *stmt) {
        sqlite3_bind_double(stmt, 1, until);
    }];
}

- (void)disableForAccount:(NSString *)account serverVersion:(NSString *)serverVersion reason:(NSString *)reason
{
    [self upsertFlagsForAccount:account set:@"disabled_version = ?1, disabled_reason = ?2" bind:^(sqlite3_stmt *stmt) {
        BindText(stmt, 1, serverVersion.length > 0 ? serverVersion : @"unknown");
        BindText(stmt, 2, reason);
    }];
}

- (void)disableForAccount:(NSString *)account forSeconds:(NSTimeInterval)seconds reason:(NSString *)reason
{
    NSTimeInterval until = [NSDate date].timeIntervalSince1970 + seconds;
    [self upsertFlagsForAccount:account set:@"disabled_until = ?1, disabled_reason = ?2" bind:^(sqlite3_stmt *stmt) {
        sqlite3_bind_double(stmt, 1, until);
        BindText(stmt, 2, reason);
    }];
}

- (NSInteger)noteOffsetRegressionForAccount:(NSString *)account
{
    __block NSInteger count = 0;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    [self write:^BOOL{
        NSString *existing = @"";
        sqlite3_stmt *sel = [self prepare:@"SELECT regressions FROM account_flags WHERE account = ?"];
        if (!sel) return NO;
        BindText(sel, 1, account);
        if (sqlite3_step(sel) == SQLITE_ROW) existing = ColumnText(sel, 0) ?: @"";
        sqlite3_finalize(sel);
        NSMutableArray *kept = [NSMutableArray array];
        for (NSString *t in [existing componentsSeparatedByString:@","]) {
            if (t.length > 0 && now - t.doubleValue < kRegressionWindow) [kept addObject:t];
        }
        [kept addObject:[NSString stringWithFormat:@"%.0f", now]];
        count = kept.count;
        sqlite3_stmt *ins = [self prepare:@"INSERT OR IGNORE INTO account_flags (account) VALUES (?)"];
        if (!ins) return NO;
        BindText(ins, 1, account);
        BOOL ok = [self step:ins] == SQLITE_DONE;
        sqlite3_finalize(ins);
        if (!ok) return NO;
        sqlite3_stmt *upd = [self prepare:@"UPDATE account_flags SET regressions = ? WHERE account = ?"];
        if (!upd) return NO;
        BindText(upd, 1, [kept componentsJoinedByString:@","]);
        BindText(upd, 2, account);
        ok = [self step:upd] == SQLITE_DONE;
        sqlite3_finalize(upd);
        return ok;
    }];
    return count;
}

@end
