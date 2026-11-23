//
//  SeafResumableUploadSession.m
//  Seafile
//
//  All state lives on `_queue`; network completions hop onto it. Every write
//  to the record goes through -save, which fails once another execution has
//  taken the attempt over, and the session then stops without touching it.
//

#import "SeafResumableUploadSession.h"
#import "SeafResumableUploadPolicy.h"
#import "SeafResumableUploadStore.h"
#import "SeafChunkRequestBuilder.h"
#import "SeafResumableUploadVerifier.h"
#import "SeafConnection+ResumableUpload.h"
#import "SeafStorage.h"
#import "Debug.h"

static const NSInteger kMaxConsecutiveFailures = 3;
static const NSTimeInterval kHeartbeatInterval = 30;
static const NSTimeInterval kBusyWaitInterval = 30;
static const NSTimeInterval kBusyWaitLimit = 10 * 60;
static const NSTimeInterval kFinalFirstWait = 30;
static const NSTimeInterval kFinalPollInterval = 10;
static const NSTimeInterval kFinalConfirmLimit = 10 * 60;
static const NSUInteger kProbeWindowLength = 64;
static const NSInteger kMaxNewAttemptsPerRun = 2;
static const NSTimeInterval kTombstoneTTL = 24 * 3600;

@interface SeafResumableUploadSession ()
@property (nonatomic, copy) SeafResumableCompletion completion;
@end

@implementation SeafResumableUploadSession {
    __weak SeafConnection *_connection;
    NSString *_repoId;
    NSString *_parentDir;
    NSString *_targetName;
    NSString *_localPath;
    long long _fileSize;
    NSString *_lastModify;
    BOOL _overwrite;
    NSString *_taskId;
    NSString *_entry;
    /// Started by the sweeper for one attempt; there is no source file (plan §9).
    BOOL _finishOnly;
    NSString *_finishAttemptId;

    dispatch_queue_t _queue;
    SeafResumableUploadStore *_store;
    NSString *_runToken;
    SeafResumableUploadRecord *_record;
    NSURLSessionTask *_currentTask;
    dispatch_source_t _heartbeat;
    NSString *_uploadURL;
    NSString *_serverDate;
    BOOL _finished;
    BOOL _cancelled;
    NSInteger _failures;
    NSInteger _newAttempts;
    NSInteger _renameRetries;
    NSDate *_busySince;
    NSDate *_finalConfirmSince;

    SeafResumableUploadVerifier *_verifier;

    // §6.8 log fields
    NSString *_probe;
    long long _startOffset;
    NSString *_reason;
    /// Why the session is waiting or retrying; logged only when it ends without getting further.
    NSString *_waitReason;
}

- (instancetype)initWithConnection:(SeafConnection *)connection
                            repoId:(NSString *)repoId
                         parentDir:(NSString *)parentDir
                        targetName:(NSString *)targetName
                         localPath:(NSString *)localPath
                          fileSize:(long long)fileSize
                        lastModify:(NSString *)lastModify
                         overwrite:(BOOL)overwrite
                            taskId:(NSString *)taskId
                             entry:(NSString *)entry
{
    if (self = [super init]) {
        _connection = connection;
        _repoId = [repoId copy];
        NSString *dir = [SeafResumableUploadPolicy normalizedName:parentDir.length > 0 ? parentDir : @"/"];
        _parentDir = [dir hasPrefix:@"/"] ? dir : [@"/" stringByAppendingString:dir];
        _targetName = [SeafResumableUploadPolicy normalizedName:targetName];
        _localPath = [localPath copy];
        _fileSize = fileSize;
        _lastModify = [lastModify copy];
        _overwrite = overwrite;
        _taskId = [taskId copy];
        _entry = [entry copy];
        _queue = dispatch_queue_create("com.seafile.resumable-upload-session", DISPATCH_QUEUE_SERIAL);
        _runToken = [NSUUID UUID].UUIDString;
        _probe = @"none";
        _startOffset = -1;
    }
    return self;
}

- (instancetype)initToFinishRecord:(SeafResumableUploadRecord *)record connection:(SeafConnection *)connection
{
    NSString *entry = [NSString stringWithFormat:@"sweep:%@", record.entry ?: @"-"];
    if (self = [self initWithConnection:connection repoId:record.repoId parentDir:record.parentDir
                             targetName:record.targetName localPath:@"" fileSize:record.fileSize
                             lastModify:record.lastModify overwrite:record.overwrite
                                 taskId:record.taskId entry:entry]) {
        _finishOnly = YES;
        _finishAttemptId = [record.attemptId copy];
    }
    return self;
}

+ (long long)confirmedBytesForTaskId:(NSString *)taskId
{
    if (taskId.length == 0) return 0;
    SeafResumableUploadRecord *r = [[SeafResumableUploadStore sharedStore] recordForTaskId:taskId];
    return (r && r.isActive) ? r.confirmedOffset : 0;
}

#pragma mark - Entry points

- (void)startWithCompletion:(SeafResumableCompletion)completion
{
    self.completion = completion;
    dispatch_async(_queue, ^{
        self->_store = [SeafResumableUploadStore sharedStore];
        if (!self->_store || !self->_connection || self->_taskId.length == 0) {
            [self finishFallback:@"no-store"];
            return;
        }
        self->_runToken = [self->_store makeRunToken];
        [self recover];
    });
}

- (void)cancel
{
    dispatch_async(_queue, ^{
        if (self->_finished) return;
        self->_cancelled = YES;
        [self->_currentTask cancel];
        [self finishCancelled];
    });
}

#pragma mark - Helpers

- (BOOL)stopped
{
    if (_finished) return YES;
    if (!_cancelled && self.userCancelled && self.userCancelled()) _cancelled = YES;
    if (_cancelled) {
        [self finishCancelled];
        return YES;
    }
    return NO;
}

- (void)after:(NSTimeInterval)seconds do:(void (^)(void))block
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), _queue, ^{
        if ([self stopped]) return;
        block();
    });
}

- (void)onQueue:(void (^)(void))block
{
    dispatch_async(_queue, ^{
        if (self->_finished) return;
        block();
    });
}

- (NSString *)account
{
    return _connection.accountIdentifier ?: @"";
}

/// Remembers the request in flight so -cancel can stop it; cancels it at once if the session already ended.
- (void)track:(NSURLSessionTask *)task
{
    dispatch_async(_queue, ^{
        if (self->_finished) {
            [task cancel];
        } else {
            self->_currentTask = task;
        }
    });
}

- (NSString *)chunksDirectory
{
    return [[SeafStorage.sharedObject.rootPath stringByAppendingPathComponent:@"upload-chunks"] stringByAppendingPathComponent:_runToken];
}

/// Persists the record; NO means another execution owns the attempt now.
- (BOOL)save
{
    _record.runToken = _runToken;
    if ([_store saveRecord:_record]) return YES;
    Warning("Resumable upload %@ lost its attempt %@", _targetName, _record.attemptId);
    [self finishWithOutcome:SeafResumableOutcomeRetryable reason:@"lost-ownership" error:nil];
    return NO;
}

- (void)reportProgress:(long long)bytes
{
    if (_fileSize <= 0 || !self.progressHandler) return;
    float value = MIN(1.0f, MAX(0.0f, (float)((double)bytes / (double)_fileSize)));
    void (^handler)(float) = self.progressHandler;
    dispatch_async(dispatch_get_main_queue(), ^{ handler(value); });
}

- (void)startHeartbeat
{
    if (_heartbeat) return;
    _heartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_heartbeat, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kHeartbeatInterval * NSEC_PER_SEC)),
                              (uint64_t)(kHeartbeatInterval * NSEC_PER_SEC), NSEC_PER_SEC);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_heartbeat, ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_finished || !strongSelf->_record) return;
        if (![strongSelf->_store heartbeatAttempt:strongSelf->_record.attemptId runToken:strongSelf->_runToken]) {
            [strongSelf->_currentTask cancel];
            [strongSelf finishWithOutcome:SeafResumableOutcomeRetryable reason:@"lost-ownership" error:nil];
        }
    });
    dispatch_resume(_heartbeat);
}

- (void)stopHeartbeat
{
    if (_heartbeat) {
        dispatch_source_cancel(_heartbeat);
        _heartbeat = nil;
    }
}

- (NSError *)errorWithCode:(SeafResumableErrorCode)code status:(NSInteger)status message:(NSString *)message
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] = message ?: @"Upload failed";
    if (status > 0) info[@"HTTPStatus"] = @(status);
    return [NSError errorWithDomain:SeafResumableErrorDomain code:code userInfo:info];
}

- (void)deleteRemoteFileNamed:(NSString *)name
{
    if (name.length == 0) return;
    SeafConnection *conn = _connection;
    NSString *path = [_parentDir stringByAppendingPathComponent:name];
    NSString *repoId = _repoId;
    dispatch_async(dispatch_get_main_queue(), ^{
        [conn resumable_deleteFileInRepo:repoId path:path completion:^(NSInteger status, NSError *error) {
            if (error && status != 404) Warning("Cannot delete staging file %@: %ld %@", path, (long)status, error);
        }];
    });
}

/// Abandons the current attempt. A staging file that may exist is deleted now if
/// possible; the sweeper retries otherwise (plan §9).
- (void)abandonRecord:(NSString *)reason
{
    if (!_record) return;
    if (_record.stagingCommitted) [self deleteRemoteFileNamed:_record.committedName ?: _record.stagingName];
    if (_record.state == SeafResumableStateFinalPending) {
        // The final segment may still commit the staging name later (old servers): watch for it.
        [_store addTombstoneForAccount:[self account] repoId:_repoId parentDir:_parentDir
                           stagingName:_record.stagingName checkUntil:[NSDate date].timeIntervalSince1970 + kTombstoneTTL];
    }
    [_store abandonAttempt:_record.attemptId reason:reason];
    _record.state = SeafResumableStateAbandoned;
}

#pragma mark - Finishing

- (void)finishWithOutcome:(SeafResumableOutcome)outcome reason:(NSString *)reason error:(NSError *)error
{
    [self finishWithOutcome:outcome oid:nil reason:reason error:error];
}

- (void)finishWithOutcome:(SeafResumableOutcome)outcome oid:(NSString *)oid reason:(NSString *)reason error:(NSError *)error
{
    if (_finished) return;
    _finished = YES;
    [self stopHeartbeat];
    [_currentTask cancel];
    _currentTask = nil;
    [_verifier cancel];
    _verifier = nil;
    [[NSFileManager defaultManager] removeItemAtPath:[self chunksDirectory] error:nil];
    if (reason) _reason = reason;

    // Retryable and cancelled-by-the-system attempts stay, released, so the
    // next execution of this task picks them up at once.
    if (_record && _record.isActive && (outcome == SeafResumableOutcomeRetryable || outcome == SeafResumableOutcomeCancelled)) {
        [_store releaseAttempt:_record.attemptId runToken:_runToken];
    }

    static NSArray *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ names = @[@"success", @"fallback", @"retryable", @"terminal", @"cancelled"]; });
    Info("[ResumableUpload] task=%@ attempt=%@ entry=%@ size=%lld probe=%@ start=%lld resumed=%d end=%lld result=%@ reason=%@",
         _taskId, _record.attemptId ?: @"-", _entry, _fileSize, _probe, _startOffset, _startOffset > 0,
         _record ? _record.confirmedOffset : 0, names[outcome], _reason ?: @"-");

    SeafResumableCompletion completion = self.completion;
    self.completion = nil;
    NSString *serverDate = _serverDate;
    if (!error && outcome == SeafResumableOutcomeRetryable) {
        error = [self errorWithCode:SeafResumableErrorRetryable status:0 message:@"The upload was interrupted"];
    }
    if (!error && outcome == SeafResumableOutcomeCancelled) {
        error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled
                                userInfo:@{NSLocalizedDescriptionKey: @"The upload task was cancelled."}];
    }
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(outcome, oid, serverDate, error); });
    }
}

- (void)finishFallback:(NSString *)reason
{
    if (_record.isActive) [self abandonRecord:reason];
    [self finishWithOutcome:SeafResumableOutcomeFallback reason:reason error:nil];
}

- (void)finishTerminal:(NSInteger)status reason:(NSString *)reason
{
    if (_record.isActive) [self abandonRecord:reason];
    NSString *message = status == 443 ? @"Out of quota" : status == 442 ? @"File too large" : @"Upload failed";
    [self finishWithOutcome:SeafResumableOutcomeTerminal reason:reason
                      error:[self errorWithCode:SeafResumableErrorTerminal status:status message:message]];
}

- (void)finishCancelled
{
    BOOL byUser = self.userCancelled && self.userCancelled();
    if (byUser && _record.isActive) {
        [self abandonRecord:@"user-cancelled"];
    }
    // Logged apart from a cancel by the system (network loss, suspension), which keeps the attempt.
    NSString *reason = byUser ? @"user-cancelled" : (_reason ?: _waitReason ?: @"cancelled");
    [self finishWithOutcome:SeafResumableOutcomeCancelled reason:reason error:nil];
}

- (void)failTransient:(NSString *)reason then:(void (^)(void))retry
{
    _failures += 1;
    _waitReason = reason;
    if (_failures > kMaxConsecutiveFailures) {
        [self finishWithOutcome:SeafResumableOutcomeRetryable reason:reason error:nil];
        return;
    }
    static const NSTimeInterval delays[] = {2, 5, 10};
    [self after:delays[MIN(_failures, 3) - 1] do:retry];
}

#pragma mark - Recovery (plan §6.1)

- (void)recover
{
    if ([self stopped]) return;
    if (_finishOnly) {
        [self recoverToFinish];
        return;
    }
    SeafResumableUploadRecord *existing = [_store recordForTaskId:_taskId];
    if (!existing) {
        [self startNewAttempt];
        return;
    }
    if (existing.state == SeafResumableStateDone) {
        [self checkReceipt:existing];
        return;
    }
    SeafResumableClaim claim = [_store claimAttempt:existing.attemptId runToken:_runToken];
    if (claim == SeafResumableClaimBusy) {
        [self waitForOtherExecution];
        return;
    }
    if (claim != SeafResumableClaimGranted) {
        [self startNewAttempt];
        return;
    }
    [self continueRecord:existing];
}

/// The sweeper's attempt: finish it if it got far enough, otherwise leave it.
- (void)recoverToFinish
{
    SeafResumableUploadRecord *existing = [_store recordWithAttemptId:_finishAttemptId];
    if (!existing.isActive || existing.state == SeafResumableStateUploading) {
        [self finishWithOutcome:SeafResumableOutcomeFallback reason:@"sweep-nothing" error:nil];
        return;
    }
    SeafResumableClaim claim = [_store claimAttempt:existing.attemptId runToken:_runToken];
    if (claim != SeafResumableClaimGranted) {
        [self finishWithOutcome:SeafResumableOutcomeFallback reason:claim == SeafResumableClaimBusy ? @"busy" : @"sweep-nothing" error:nil];
        return;
    }
    [self continueRecord:existing];
}

- (void)continueRecord:(SeafResumableUploadRecord *)existing
{
    _record = [existing copy];
    _record.runToken = _runToken;
    _waitReason = nil;
    [self startHeartbeat];
    // Past the segments nothing is queried, so the start offset is what the record confirmed.
    if (_record.state != SeafResumableStateUploading && _startOffset < 0) _startOffset = _record.confirmedOffset;
    switch (_record.state) {
        case SeafResumableStateFinalPending:
            [self confirmFinal];
            break;
        case SeafResumableStateCommitted:
            [self verifyCommitted];
            break;
        case SeafResumableStateRenamePending:
            [self confirmRename];
            break;
        default:
            [self resumeUploading];
            break;
    }
}

- (void)waitForOtherExecution
{
    if (!_busySince) _busySince = [NSDate date];
    if (-[_busySince timeIntervalSinceNow] > kBusyWaitLimit) {
        [self finishWithOutcome:SeafResumableOutcomeRetryable reason:@"busy" error:nil];
        return;
    }
    _waitReason = @"busy";
    [self after:kBusyWaitInterval do:^{ [self recover]; }];
}

- (BOOL)contentSignatureMatches:(SeafResumableUploadRecord *)r
{
    if (r.fileSize != _fileSize || r.chunkSize != SeafResumableChunkSize) return NO;
    if (!((r.lastModify == nil && _lastModify == nil) || [r.lastModify isEqualToString:_lastModify])) return NO;
    return YES;
}

/// A done record of this task: answer success when the published file is still ours (plan §6.6).
- (void)checkReceipt:(SeafResumableUploadRecord *)receipt
{
    long long firstLen = MIN(SeafResumableChunkSize, _fileSize);
    NSString *firstHash = [SeafChunkRequestBuilder sha1OfFileAtPath:_localPath start:0 length:firstLen];
    BOOL same = [self contentSignatureMatches:receipt] && receipt.chunkHashes.count > 0
        && [receipt.chunkHashes.firstObject isEqualToString:firstHash] && receipt.finalName.length > 0 && receipt.oid.length > 0;
    if (!same) {
        [_store deleteAttempt:receipt.attemptId];
        [self startNewAttempt];
        return;
    }
    NSString *path = [receipt.parentDir stringByAppendingPathComponent:receipt.finalName];
    SeafConnection *conn = _connection;
    NSString *repoId = _repoId;
    dispatch_async(dispatch_get_main_queue(), ^{
        [conn resumable_fileInfoInRepo:repoId path:path completion:^(NSInteger status, NSDictionary *info, NSError *error) {
            [self onQueue:^{
                if (status == 200 && [info[@"obj_id"] isEqual:receipt.oid]) {
                    self->_record = [receipt copy];
                    self->_reason = @"receipt";
                    if (self->_startOffset < 0) self->_startOffset = receipt.confirmedOffset;
                    [self reportProgress:self->_fileSize];
                    [self finishWithOutcome:SeafResumableOutcomeSuccess oid:receipt.oid reason:@"receipt" error:nil];
                } else if (status == 0 || status >= 500) {
                    [self finishWithOutcome:SeafResumableOutcomeRetryable reason:@"receipt-check-failed" error:error];
                } else {
                    // Published file gone or changed since: upload again.
                    [self->_store deleteAttempt:receipt.attemptId];
                    [self startNewAttempt];
                }
            }];
        }];
    });
}

- (void)startNewAttempt
{
    if ([self stopped]) return;
    if (_finishOnly) {
        // Nothing to upload from: the attempt it had is over.
        [self finishFallback:_reason ?: @"no-source"];
        return;
    }
    if (++_newAttempts > kMaxNewAttemptsPerRun + 1) {
        [self finishFallback:_reason ?: @"too-many-attempts"];
        return;
    }
    if (!_overwrite) {
        [self insertNewAttempt];
        return;
    }
    // Overwriting an existing file is not segmented in phase 1 (plan §3.4).
    SeafConnection *conn = _connection;
    NSString *path = [_parentDir stringByAppendingPathComponent:_targetName];
    NSString *repoId = _repoId;
    dispatch_async(dispatch_get_main_queue(), ^{
        [conn resumable_fileInfoInRepo:repoId path:path completion:^(NSInteger status, NSDictionary *info, NSError *error) {
            [self onQueue:^{
                if (status == 404) {
                    [self insertNewAttempt];
                } else if (status == 200) {
                    [self finishFallback:@"overwrite-existing"];
                } else if ([SeafResumableUploadPolicy isCancellationError:error]) {
                    [self finishCancelled];
                } else if (status == 0 || status >= 500) {
                    [self finishWithOutcome:SeafResumableOutcomeRetryable reason:@"target-check-failed" error:error];
                } else {
                    [self finishFallback:@"target-check-failed"];
                }
            }];
        }];
    });
}

- (void)insertNewAttempt
{
    SeafResumableUploadRecord *r = [SeafResumableUploadRecord new];
    r.taskId = _taskId;
    r.account = [self account];
    r.repoId = _repoId;
    r.parentDir = _parentDir;
    r.targetName = _targetName;
    r.stagingName = [SeafResumableUploadPolicy stagingNameForTargetName:_targetName];
    r.overwrite = _overwrite;
    r.fileSize = _fileSize;
    r.lastModify = _lastModify;
    r.fileIdentity = [SeafChunkRequestBuilder fileIdentityAtPath:_localPath];
    r.chunkSize = SeafResumableChunkSize;
    r.entry = _entry;
    r.runToken = _runToken;

    NSArray<SeafResumableUploadRecord *> *replaced = nil;
    SeafResumableClaim claim = [_store insertAttempt:r replaced:&replaced];
    if (claim == SeafResumableClaimBusy) {
        [self waitForOtherExecution];
        return;
    }
    if (claim != SeafResumableClaimGranted) {
        [self finishFallback:@"store-failed"];
        return;
    }
    for (SeafResumableUploadRecord *old in replaced) {
        if (old.stagingCommitted) [self deleteRemoteFileNamed:old.committedName ?: old.stagingName];
    }
    _record = r;
    _failures = 0;
    _waitReason = nil;
    [self startHeartbeat];
    [self reportProgress:0];
    [self uploadLoop];
}

/// Checks that confirmed segments still match the local file (plan D8).
- (void)resumeUploading
{
    if (![self contentSignatureMatches:_record]) {
        [self abandonRecord:@"content-changed"];
        _record = nil;
        [self startNewAttempt];
        return;
    }
    NSString *identity = [SeafChunkRequestBuilder fileIdentityAtPath:_localPath];
    if (![identity isEqualToString:_record.fileIdentity]) {
        long long count = (long long)_record.chunkHashes.count;
        long long confirmedSegments = (_record.confirmedOffset + _record.chunkSize - 1) / _record.chunkSize;
        BOOL same = count == confirmedSegments;
        for (long long i = 0; same && i < count; i++) {
            long long start = i * _record.chunkSize;
            long long len = MIN(_record.chunkSize, _fileSize - start);
            NSString *hash = [SeafChunkRequestBuilder sha1OfFileAtPath:_localPath start:start length:len];
            same = [hash isEqualToString:_record.chunkHashes[(NSUInteger)i]];
        }
        if (!same) {
            [self abandonRecord:@"content-changed"];
            _record = nil;
            [self startNewAttempt];
            return;
        }
        _record.fileIdentity = identity;
        if (![self save]) return;
    }
    // Show the confirmed part straight away instead of starting from 0 (plan §6.2).
    [self reportProgress:_record.confirmedOffset];
    [self uploadLoop];
}

#pragma mark - Segments (plan §6.2)

- (void)uploadLoop
{
    if ([self stopped]) return;
    if (_finishOnly) {
        [self finishFallback:@"no-source"];
        return;
    }
    if (!_uploadURL) {
        [self fetchUploadLinkThen:^{ [self uploadLoop]; }];
        return;
    }
    [self queryOffsetThen:^(SeafResumableProbeResult *probe) {
        [self handleProbe:probe];
    }];
}

- (void)fetchUploadLinkThen:(void (^)(void))next
{
    SeafConnection *conn = _connection;
    NSString *repoId = _repoId;
    NSString *dir = _parentDir;
    dispatch_async(dispatch_get_main_queue(), ^{
        [conn resumable_uploadLinkInRepo:repoId parentDir:dir completion:^(NSString *url, NSInteger status, NSError *error) {
            [self onQueue:^{
                if (url) {
                    self->_uploadURL = url;
                    next();
                } else if ([SeafResumableUploadPolicy isCancellationError:error]) {
                    [self finishCancelled];
                } else if (status == 0 || status >= 500) {
                    [self failTransient:@"upload-link" then:next];
                } else if (status == 403 || status == 404) {
                    [self finishTerminal:status reason:@"upload-link"];
                } else {
                    [self finishFallback:@"upload-link"];
                }
            }];
        }];
    });
}

- (void)queryOffsetThen:(void (^)(SeafResumableProbeResult *probe))next
{
    SeafConnection *conn = _connection;
    NSString *repoId = _repoId;
    NSString *dir = _parentDir;
    NSString *name = _record.stagingName;
    NSString *lastModify = _lastModify;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURLSessionDataTask *task = [conn resumable_uploadedBytesInRepo:repoId parentDir:dir fileName:name lastModify:lastModify
                                                              completion:^(NSInteger status, NSString *acceptRanges, id body, NSError *error) {
            SeafResumableProbeResult *probe = [SeafResumableUploadPolicy interpretProbeWithStatus:status acceptRanges:acceptRanges
                                                                                             body:body error:error];
            [self onQueue:^{ next(probe); }];
        }];
        [self track:task];
    });
}

- (void)handleProbe:(SeafResumableProbeResult *)probe
{
    if ([self stopped]) return;
    switch (probe.kind) {
        case SeafResumableProbeCancelled:
            [self finishCancelled];
            return;
        case SeafResumableProbeTransient: {
            _probe = @"transient";
            [self failTransient:@"query" then:^{ [self uploadLoop]; }];
            return;
        }
        case SeafResumableProbeTerminal:
            _probe = @"terminal";
            [self finishTerminal:404 reason:@"query-404"];
            return;
        case SeafResumableProbeInvalid:
            _probe = @"invalid";
            [self finishFallback:@"invalid-response"];
            return;
        case SeafResumableProbeNotEnabled:
            _probe = @"not-enabled";
            [_store markNotEnabledForAccount:[self account]];
            [self finishFallback:@"not-enabled"];
            return;
        case SeafResumableProbeSupported:
            _probe = @"supported";
            break;
    }

    long long q = probe.uploadedBytes;
    NSString *localInflight = nil;
    if (_record.inflightEnd > _record.confirmedOffset && q == _record.inflightEnd) {
        localInflight = [SeafChunkRequestBuilder sha1OfFileAtPath:_localPath start:_record.confirmedOffset
                                                           length:_record.inflightEnd - _record.confirmedOffset];
    }
    SeafResumableAlignment alignment = [SeafResumableUploadPolicy alignServerOffset:q
                                                                    confirmedOffset:_record.confirmedOffset
                                                                        inflightEnd:_record.inflightEnd
                                                                       inflightHash:_record.inflightHash
                                                                  localInflightHash:localInflight
                                                                           fileSize:_fileSize
                                                                       finalPending:_record.state == SeafResumableStateFinalPending];
    switch (alignment) {
        case SeafResumableAlignContinue:
            break;
        case SeafResumableAlignAdvanceInflight:
            _record.chunkHashes = [_record.chunkHashes arrayByAddingObject:_record.inflightHash];
            _record.confirmedOffset = _record.inflightEnd;
            _record.inflightEnd = 0;
            _record.inflightHash = nil;
            if (![self save]) return;
            break;
        case SeafResumableAlignContentChanged:
            [self abandonRecord:@"in-flight-changed"];
            _record = nil;
            _reason = @"in-flight-changed";
            [self startNewAttempt];
            return;
        case SeafResumableAlignCommitting:
            [self confirmFinal];
            return;
        case SeafResumableAlignUntrusted: {
            NSInteger count = [_store noteOffsetRegressionForAccount:[self account]];
            if (count >= 2) [_store disableForAccount:[self account] forSeconds:24 * 3600 reason:@"offset-regression"];
            [self abandonRecord:@"offset-regression"];
            _record = nil;
            _reason = @"offset-regression";
            if (count >= 2) {
                [self finishFallback:@"offset-regression"];
            } else {
                [self startNewAttempt];
            }
            return;
        }
    }
    if (_startOffset < 0) _startOffset = _record.confirmedOffset;
    [self reportProgress:_record.confirmedOffset];
    [self sendNextSegment];
}

- (void)sendNextSegment
{
    if ([self stopped]) return;
    long long start = _record.confirmedOffset;
    long long end = [SeafResumableUploadPolicy segmentEndForStart:start fileSize:_fileSize chunkSize:_record.chunkSize];
    BOOL isLast = end == _fileSize - 1;
    NSURL *url = [NSURL URLWithString:_uploadURL];
    NSError *buildError = nil;
    SeafChunkRequest *req = url ? [SeafChunkRequestBuilder buildRequestForURL:url filePath:_localPath start:start end:end
                                                                    fileSize:_fileSize stagingName:_record.stagingName
                                                                   parentDir:_parentDir lastModify:_lastModify
                                                                 isLastChunk:isLast outputDirectory:[self chunksDirectory]
                                                                       error:&buildError] : nil;
    if (!req) {
        Warning("Cannot build segment for %@: %@", _localPath, buildError);
        [self finishWithOutcome:SeafResumableOutcomeRetryable reason:@"source-unreadable" error:buildError];
        return;
    }
    if (isLast && !_record.probeWindows) {
        // Saved with the final segment so whoever finishes the attempt can spot-check
        // it without the source file (plan §6.4, §9).
        NSError *probeError = nil;
        NSArray<SeafProbeWindow *> *windows = [SeafChunkRequestBuilder probeWindowsForFileAtPath:_localPath fileSize:_fileSize
                                                                                       chunkSize:_record.chunkSize
                                                                                    windowLength:kProbeWindowLength error:&probeError];
        if (!windows) {
            [SeafChunkRequestBuilder removeBodyFile:req];
            [self finishWithOutcome:SeafResumableOutcomeRetryable reason:@"source-unreadable" error:probeError];
            return;
        }
        _record.probeWindows = windows;
    }
    _record.inflightEnd = end + 1;
    _record.inflightHash = req.segmentHash;
    if (isLast) {
        _record.state = SeafResumableStateFinalPending;
        _record.finalSentAt = [NSDate date].timeIntervalSince1970;
    }
    if (![self save]) {
        [SeafChunkRequestBuilder removeBodyFile:req];
        return;
    }

    long long base = start;
    long long segLen = end - start + 1;
    SeafConnection *conn = _connection;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURLSessionUploadTask *task = [conn resumable_uploadSegment:req.request fromFile:req.bodyFileURL progress:^(int64_t sent, int64_t total) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || total <= 0) return;
            [strongSelf reportProgress:base + (long long)((double)segLen * (double)sent / (double)total)];
        } completion:^(NSHTTPURLResponse *response, id body, NSError *error) {
            [SeafChunkRequestBuilder removeBodyFile:req];
            NSString *text = [SeafResumableUploadPolicy bodyStringFromResponseObject:body error:error];
            NSString *date = [response valueForHTTPHeaderField:@"Date"];
            [self onQueue:^{
                if (date) self->_serverDate = date;
                SeafResumableChunkResult *result = [SeafResumableUploadPolicy classifyChunkResponseWithStatus:response.statusCode
                                                                                                          body:error ? nil : body
                                                                                                    bodyString:text error:error
                                                                                                        isLast:isLast fileSize:self->_fileSize
                                                                                                   stagingName:self->_record.stagingName];
                [self handleSegment:req result:result];
            }];
        }];
        [self track:task];
    });
}

- (void)handleSegment:(SeafChunkRequest *)req result:(SeafResumableChunkResult *)result
{
    if (_finished) return;
    switch (result.outcome) {
        case SeafResumableChunkCancelled:
            [self finishCancelled];
            return;
        case SeafResumableChunkAccepted:
            _record.chunkHashes = [_record.chunkHashes arrayByAddingObject:req.segmentHash];
            _record.confirmedOffset = req.end + 1;
            _record.inflightEnd = 0;
            _record.inflightHash = nil;
            if (![self save]) return;
            _failures = 0;
            [self uploadLoop];
            return;
        case SeafResumableChunkCommitted:
            _record.chunkHashes = [_record.chunkHashes arrayByAddingObject:req.segmentHash];
            _record.confirmedOffset = _fileSize;
            _record.inflightEnd = 0;
            _record.inflightHash = nil;
            _record.committedName = result.committedName;
            _record.oid = result.committedId;
            _record.stagingCommitted = YES;
            _record.state = SeafResumableStateCommitted;
            if (![self save]) return;
            _failures = 0;
            [self verifyCommitted];
            return;
        case SeafResumableChunkHeaderIgnored:
            // The server took a segment for a whole file: only a staging-named file is affected.
            [self deleteRemoteFileNamed:result.committedName ?: _record.stagingName];
            [_store disableForAccount:[self account] serverVersion:_connection.serverVersion reason:@"header-ignored"];
            [self finishFallback:@"header-ignored"];
            return;
        case SeafResumableChunkOffsetMismatch: {
            [self revertFinalPendingIfNeeded];
            [self failTransient:@"offset-mismatch" then:^{ [self uploadLoop]; }];
            return;
        }
        case SeafResumableChunkTokenExpired: {
            [self revertFinalPendingIfNeeded];
            _uploadURL = nil;
            [self failTransient:@"token-expired" then:^{ [self uploadLoop]; }];
            return;
        }
        case SeafResumableChunkTerminal:
            [self finishTerminal:result.status reason:[NSString stringWithFormat:@"http-%ld", (long)result.status]];
            return;
        case SeafResumableChunkFallback:
            [self finishFallback:[NSString stringWithFormat:@"http-%ld", (long)result.status]];
            return;
        case SeafResumableChunkTransient: {
            [self failTransient:@"segment" then:^{ [self uploadLoop]; }];
            return;
        }
        case SeafResumableChunkUncertain:
            _finalConfirmSince = nil;
            [self confirmFinal];
            return;
    }
}

/// A 4xx on the final segment means it was not committed (plan §6.3).
- (void)revertFinalPendingIfNeeded
{
    if (_record.state == SeafResumableStateFinalPending) {
        _record.state = SeafResumableStateUploading;
        [self save];
    }
}

#pragma mark - Final segment confirmation (plan §6.3)

- (void)confirmFinal
{
    if ([self stopped]) return;
    if (!_finalConfirmSince) {
        _finalConfirmSince = [NSDate date];
        NSTimeInterval sinceSent = [NSDate date].timeIntervalSince1970 - _record.finalSentAt;
        NSTimeInterval wait = MAX(0, kFinalFirstWait - sinceSent);
        if (wait > 0) {
            [self after:wait do:^{ [self confirmFinalStep:NO]; }];
            return;
        }
    }
    [self confirmFinalStep:NO];
}

- (void)confirmFinalStep:(BOOL)recheck
{
    if ([self stopped]) return;
    if (-[_finalConfirmSince timeIntervalSinceNow] > kFinalConfirmLimit) {
        [self finishWithOutcome:SeafResumableOutcomeRetryable reason:@"final-unconfirmed" error:nil];
        return;
    }
    NSString *path = [_parentDir stringByAppendingPathComponent:_record.stagingName];
    SeafConnection *conn = _connection;
    NSString *repoId = _repoId;
    dispatch_async(dispatch_get_main_queue(), ^{
        [conn resumable_fileInfoInRepo:repoId path:path completion:^(NSInteger status, NSDictionary *info, NSError *error) {
            [self onQueue:^{ [self confirmFinalWithInfoStatus:status info:info error:error recheck:recheck]; }];
        }];
    });
}

- (void)confirmFinalWithInfoStatus:(NSInteger)status info:(NSDictionary *)info error:(NSError *)error recheck:(BOOL)recheck
{
    if ([self stopped]) return;
    if (status != 200 && status != 404) {
        [self after:kFinalPollInterval do:^{ [self confirmFinalStep:recheck]; }];
        return;
    }
    BOOL exists = status == 200;
    long long size = [info[@"size"] respondsToSelector:@selector(longLongValue)] ? [info[@"size"] longLongValue] : -1;
    if (exists) {
        SeafResumableFinalResolution r = [SeafResumableUploadPolicy resolveFinalWithStagingExists:YES stagingSize:size serverOffset:0
                                                                                  confirmedOffset:_record.confirmedOffset
                                                                                         fileSize:_fileSize secondsSinceFinalSent:0];
        if (r == SeafResumableFinalCommitted) {
            [self markCommittedWithName:info[@"obj_name"] fileId:info[@"obj_id"]];
        } else {
            [self deleteRemoteFileNamed:_record.stagingName];
            [self after:kFinalPollInterval do:^{ [self confirmFinalStep:recheck]; }];
        }
        return;
    }
    if (recheck) {
        // The request ended and nothing was committed: start over (plan §6.3, q == 0).
        [self abandonRecord:@"final-not-committed"];
        _record = nil;
        _reason = @"final-not-committed";
        [self startNewAttempt];
        return;
    }
    [self queryOffsetThen:^(SeafResumableProbeResult *probe) {
        if (probe.kind == SeafResumableProbeCancelled) { [self finishCancelled]; return; }
        if (probe.kind == SeafResumableProbeTerminal) { [self finishTerminal:404 reason:@"query-404"]; return; }
        if (probe.kind == SeafResumableProbeTransient || probe.kind == SeafResumableProbeInvalid) {
            [self after:kFinalPollInterval do:^{ [self confirmFinalStep:NO]; }];
            return;
        }
        // Supported or not enabled: only the offset matters here.
        NSTimeInterval elapsed = [NSDate date].timeIntervalSince1970 - self->_record.finalSentAt;
        SeafResumableFinalResolution r = [SeafResumableUploadPolicy resolveFinalWithStagingExists:NO stagingSize:-1
                                                                                     serverOffset:probe.uploadedBytes
                                                                                  confirmedOffset:self->_record.confirmedOffset
                                                                                         fileSize:self->_fileSize
                                                                            secondsSinceFinalSent:elapsed];
        switch (r) {
            case SeafResumableFinalWait: {
                [self after:kFinalPollInterval do:^{ [self confirmFinalStep:NO]; }];
                break;
            }
            case SeafResumableFinalResend:
                if (self->_finishOnly) {
                    [self finishFallback:@"final-resend-no-source"];
                    break;
                }
                self->_record.state = SeafResumableStateUploading;
                if (![self save]) return;
                self->_finalConfirmSince = nil;
                [self uploadLoop];
                break;
            case SeafResumableFinalRecheck:
                [self confirmFinalStep:YES];
                break;
            default:
                [self abandonRecord:@"final-untrusted"];
                self->_record = nil;
                self->_reason = @"final-untrusted";
                [self startNewAttempt];
                break;
        }
    }];
}

- (void)markCommittedWithName:(NSString *)name fileId:(NSString *)fileId
{
    _record.committedName = [name isKindOfClass:[NSString class]] ? name : _record.stagingName;
    _record.oid = [fileId isKindOfClass:[NSString class]] ? fileId : nil;
    _record.confirmedOffset = _fileSize;
    _record.inflightEnd = 0;
    _record.inflightHash = nil;
    _record.stagingCommitted = YES;
    _record.state = SeafResumableStateCommitted;
    if (![self save]) return;
    [self verifyCommitted];
}

#pragma mark - Spot-check (plan §6.4)

- (void)verifyCommitted
{
    if ([self stopped]) return;
    if (_record.verified) {
        [self prepareRename];
        return;
    }
    NSArray<SeafProbeWindow *> *windows = _record.probeWindows;
    if (!windows) {
        // Committed before the windows were saved: take them from the source now.
        NSError *error = nil;
        windows = [SeafChunkRequestBuilder probeWindowsForFileAtPath:_localPath fileSize:_fileSize
                                                           chunkSize:_record.chunkSize
                                                        windowLength:kProbeWindowLength error:&error];
        if (!windows) {
            // Unchecked, the staging file must not be published.
            [self abandonRecord:@"verify-no-source"];
            [self finishWithOutcome:SeafResumableOutcomeRetryable reason:@"verify-no-source" error:error];
            return;
        }
        _record.probeWindows = windows;
        if (![self save]) return;
    }
    NSString *path = [_parentDir stringByAppendingPathComponent:_record.committedName ?: _record.stagingName];
    SeafResumableUploadVerifier *verifier = [[SeafResumableUploadVerifier alloc] initWithConnection:_connection repoId:_repoId
                                                                                              path:path windows:windows];
    _verifier = verifier;
    [verifier startOnQueue:_queue completion:^(SeafResumableVerifyResult result, NSError *error) {
        if (self->_verifier != verifier) return;
        self->_verifier = nil;
        if (self->_finished) return;
        switch (result) {
            case SeafResumableVerifyPassed:
                [self verificationPassed];
                break;
            case SeafResumableVerifyMismatch:
                [self rejectStaging:@"holes"];
                break;
            case SeafResumableVerifyRangeUnsupported:
                [self rejectStaging:@"range-unsupported"];
                break;
            case SeafResumableVerifyGone:
                // The staging file vanished: nothing to publish, start over.
                self->_record.stagingCommitted = NO;
                [self abandonRecord:@"staging-gone"];
                self->_record = nil;
                [self startNewAttempt];
                break;
            case SeafResumableVerifyCancelled:
                [self finishCancelled];
                break;
            case SeafResumableVerifyTransient:
                [self failTransient:@"verify-read" then:^{ [self verifyCommitted]; }];
                break;
        }
    }];
}

- (void)rejectStaging:(NSString *)reason
{
    Warning("Resumable upload %@: staging file rejected (%@)", _targetName, reason);
    [_store disableForAccount:[self account] serverVersion:_connection.serverVersion reason:reason];
    [self finishFallback:reason];
}

- (void)verificationPassed
{
    _record.verified = YES;
    if (![self save]) return;
    _failures = 0;
    [self prepareRename];
}

#pragma mark - Rename (plan §6.5)

- (void)prepareRename
{
    if ([self stopped]) return;
    SeafConnection *conn = _connection;
    NSString *repoId = _repoId;
    NSString *dir = _parentDir;
    void (^listAndRename)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [conn resumable_listDirInRepo:repoId path:dir completion:^(NSInteger status, NSArray<NSDictionary *> *entries, NSError *error) {
                [self onQueue:^{
                    if (!entries) {
                        if ([SeafResumableUploadPolicy isCancellationError:error]) { [self finishCancelled]; return; }
                        [self failTransient:@"list-dir" then:^{ [self prepareRename]; }];
                        return;
                    }
                    self->_record.renameSnapshot = [SeafResumableUploadPolicy renameSnapshotFromListing:entries targetName:self->_targetName];
                    self->_record.state = SeafResumableStateRenamePending;
                    if (![self save]) return;
                    [self sendRename];
                }];
            }];
        });
    };
    if (!_overwrite) {
        listAndRename();
        return;
    }
    NSString *targetPath = [_parentDir stringByAppendingPathComponent:_targetName];
    dispatch_async(dispatch_get_main_queue(), ^{
        [conn resumable_fileInfoInRepo:repoId path:targetPath completion:^(NSInteger status, NSDictionary *info, NSError *error) {
            [self onQueue:^{
                if (status == 404) {
                    listAndRename();
                } else if (status == 200) {
                    // Someone created the target meanwhile; it cannot be replaced atomically (plan §6.5).
                    [self finishFallback:@"target-appeared"];
                } else if ([SeafResumableUploadPolicy isCancellationError:error]) {
                    [self finishCancelled];
                } else {
                    [self failTransient:@"target-check" then:^{ [self prepareRename]; }];
                }
            }];
        }];
    });
}

- (void)sendRename
{
    if ([self stopped]) return;
    NSString *stagingPath = [_parentDir stringByAppendingPathComponent:_record.committedName ?: _record.stagingName];
    SeafConnection *conn = _connection;
    NSString *repoId = _repoId;
    NSString *target = _targetName;
    dispatch_async(dispatch_get_main_queue(), ^{
        [conn resumable_renameFileInRepo:repoId path:stagingPath newName:target completion:^(NSInteger status, NSDictionary *info, NSError *error) {
            [self onQueue:^{
                if ([SeafResumableUploadPolicy isCancellationError:error]) { [self finishCancelled]; return; }
                if (status >= 200 && status < 300 && [info[@"obj_name"] isKindOfClass:[NSString class]]) {
                    NSString *fileId = info[@"obj_id"];
                    if (fileId.length > 0 && self->_record.oid.length > 0 && ![fileId isEqualToString:self->_record.oid]) {
                        [self confirmRename];
                        return;
                    }
                    [self publishedAs:info[@"obj_name"]];
                } else if (status >= 400 && status < 500) {
                    [self finishFallback:[NSString stringWithFormat:@"rename-%ld", (long)status]];
                } else {
                    [self confirmRename];
                }
            }];
        }];
    });
}

- (void)confirmRename
{
    if ([self stopped]) return;
    NSString *stagingPath = [_parentDir stringByAppendingPathComponent:_record.committedName ?: _record.stagingName];
    SeafConnection *conn = _connection;
    NSString *repoId = _repoId;
    NSString *dir = _parentDir;
    dispatch_async(dispatch_get_main_queue(), ^{
        [conn resumable_fileInfoInRepo:repoId path:stagingPath completion:^(NSInteger status, NSDictionary *info, NSError *error) {
            [self onQueue:^{
                if (status == 200) {
                    if (++self->_renameRetries > kMaxConsecutiveFailures) {
                        [self finishWithOutcome:SeafResumableOutcomeRetryable reason:@"rename-failed" error:nil];
                        return;
                    }
                    [self after:2 do:^{ [self prepareRename]; }];
                    return;
                }
                if (status != 404) {
                    if ([SeafResumableUploadPolicy isCancellationError:error]) { [self finishCancelled]; return; }
                    [self failTransient:@"rename-confirm" then:^{ [self confirmRename]; }];
                    return;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    [conn resumable_listDirInRepo:repoId path:dir completion:^(NSInteger listStatus, NSArray<NSDictionary *> *entries, NSError *listError) {
                        [self onQueue:^{
                            if (!entries) {
                                [self failTransient:@"rename-confirm" then:^{ [self confirmRename]; }];
                                return;
                            }
                            NSString *published = nil;
                            SeafResumableRenameResolution r = [SeafResumableUploadPolicy resolveRenameWithStagingExists:NO listing:entries
                                                                                                               snapshot:self->_record.renameSnapshot
                                                                                                             targetName:self->_targetName
                                                                                                                    oid:self->_record.oid ?: @""
                                                                                                          publishedName:&published];
                            if (r == SeafResumableRenamePublished) {
                                [self publishedAs:published];
                            } else {
                                // Staging file gone and no published copy: someone removed it.
                                self->_record.stagingCommitted = NO;
                                [self abandonRecord:@"staging-gone"];
                                self->_record = nil;
                                [self startNewAttempt];
                            }
                        }];
                    }];
                });
            }];
        }];
    });
}

- (void)publishedAs:(NSString *)name
{
    if (_overwrite && ![name isEqualToString:_targetName]) {
        // Auto-renamed while the task wanted to overwrite: fall back and remove our copy.
        _record.committedName = name;
        [self finishFallback:@"rename-collided"];
        return;
    }
    _record.finalName = name;
    _record.state = SeafResumableStateDone;
    _record.stagingCommitted = NO;
    if (![self save]) return;
    [_store addTombstoneForAccount:[self account] repoId:_repoId parentDir:_parentDir
                       stagingName:_record.stagingName checkUntil:[NSDate date].timeIntervalSince1970 + kTombstoneTTL];
    [self reportProgress:_fileSize];
    [self finishWithOutcome:SeafResumableOutcomeSuccess oid:_record.oid reason:_reason error:nil];
}

@end
