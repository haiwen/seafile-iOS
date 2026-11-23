//
//  SeafResumableUploadStore.h
//  Seafile
//
//  SQLite store for resumable upload attempts, shared by the app and its
//  extensions through the App Group container (plan §5.1). Every write runs
//  in a BEGIN IMMEDIATE transaction, so claims are exclusive across processes.
//

#import <Foundation/Foundation.h>
#import "SeafResumableUploadRecord.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SeafResumableClaim) {
    SeafResumableClaimGranted = 0,
    /// Another live execution owns the task or the target.
    SeafResumableClaimBusy,
    /// The record no longer exists or is no longer active.
    SeafResumableClaimGone,
    SeafResumableClaimFailed,
};

@interface SeafResumableUploadStore : NSObject

/// Heartbeats older than this make a record claimable by another execution.
@property (nonatomic) NSTimeInterval staleAfter;

/// Set in the main app only (nil in extensions): an id of this launch. Only one
/// main app process exists at a time, so an execution whose token names another
/// launch of the main app died with that process and is taken over at once,
/// without waiting for its heartbeat to go stale. Executions of extensions keep
/// the heartbeat rule: the app and an extension can run the same task at once.
@property (nonatomic, copy, nullable) NSString *mainAppLaunchId;

- (nullable instancetype)initWithPath:(NSString *)path;

/// Token for a new execution in this process; it carries `mainAppLaunchId` when set.
- (NSString *)makeRunToken;
/// YES when `runToken` belongs to an earlier launch of the main app, seen from the main app.
- (BOOL)isRunTokenOfEndedLaunch:(nullable NSString *)runToken;
/// YES while some execution still owns the record.
- (BOOL)isRecordLive:(SeafResumableUploadRecord *)record now:(NSTimeInterval)now;
/// Tokens of every execution that still owns an active attempt.
- (NSSet<NSString *> *)liveRunTokens;

#pragma mark Attempts

/// The active attempt of a task, else its newest done receipt, else nil.
- (nullable SeafResumableUploadRecord *)recordForTaskId:(NSString *)taskId;
- (nullable SeafResumableUploadRecord *)recordWithAttemptId:(NSString *)attemptId;

/// Inserts a new attempt owned by `record.runToken`. An active attempt of the
/// same task or target that nobody runs any more is abandoned first (it is
/// returned through `replaced` so the caller can clean its staging file).
- (SeafResumableClaim)insertAttempt:(SeafResumableUploadRecord *)record
                           replaced:(NSArray<SeafResumableUploadRecord *> * _Nullable * _Nullable)replaced;

/// Takes over an existing active attempt for `runToken` (same token, released, or stale).
- (SeafResumableClaim)claimAttempt:(NSString *)attemptId runToken:(NSString *)runToken;

/// Writes every mutable field, only while `record.runToken` still owns the attempt.
- (BOOL)saveRecord:(SeafResumableUploadRecord *)record;
- (BOOL)heartbeatAttempt:(NSString *)attemptId runToken:(NSString *)runToken;
/// Gives up ownership without changing state, so the same task can resume at once.
- (void)releaseAttempt:(NSString *)attemptId runToken:(NSString *)runToken;
- (void)abandonAttempt:(NSString *)attemptId reason:(nullable NSString *)reason;
- (void)deleteAttempt:(NSString *)attemptId;

/// The task layer has persisted the task's completion: drop its receipts.
- (void)acknowledgeTaskId:(NSString *)taskId;
/// Abandon the active attempt of these tasks (user cancelled them).
- (void)abandonTaskIds:(NSArray<NSString *> *)taskIds reason:(NSString *)reason;

- (NSArray<SeafResumableUploadRecord *> *)recordsForAccount:(NSString *)account;
- (void)deleteAllForAccount:(NSString *)account;

#pragma mark Tombstones (plan §9)

- (void)addTombstoneForAccount:(NSString *)account repoId:(NSString *)repoId
                     parentDir:(NSString *)parentDir stagingName:(NSString *)stagingName
                    checkUntil:(NSTimeInterval)checkUntil;
/// dicts with account, repo_id, parent_dir, staging_name, check_until
- (NSArray<NSDictionary *> *)tombstonesForAccount:(NSString *)account;
- (void)removeTombstoneForAccount:(NSString *)account repoId:(NSString *)repoId
                        parentDir:(NSString *)parentDir stagingName:(NSString *)stagingName;

#pragma mark Account flags (plan D6, §8)

- (BOOL)isSegmentingDisabledForAccount:(NSString *)account serverVersion:(nullable NSString *)serverVersion;
/// No `Accept-Ranges`: skip segmenting (and the query) for 24 hours.
- (void)markNotEnabledForAccount:(NSString *)account;
/// Stop segmenting for this account while the server version stays the same.
- (void)disableForAccount:(NSString *)account serverVersion:(nullable NSString *)serverVersion reason:(NSString *)reason;
/// Stop segmenting for this account for 24 hours.
- (void)disableForAccount:(NSString *)account forSeconds:(NSTimeInterval)seconds reason:(NSString *)reason;
/// Records an offset regression and returns how many happened in the last 24 hours.
- (NSInteger)noteOffsetRegressionForAccount:(NSString *)account;

@end

@interface SeafResumableUploadStore (Shared)
/// Store in the App Group root (SeafStorage). Nil if the database cannot be opened.
+ (nullable instancetype)sharedStore;
@end

NS_ASSUME_NONNULL_END
