//
//  SeafResumableUploadDefines.h
//  Seafile
//
//  Constants and enums shared by the resumable (segmented) upload code.
//  Design: docs/versions/_unreleased/features/upload-resume-plan.md
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Master switch. NO makes every upload take the existing single-request path.
extern BOOL const SeafResumableUploadEnabled;

/// Bytes per segment (plan D3).
extern long long const SeafResumableChunkSize;
/// Files must be strictly larger than this to be segmented (plan D3).
extern long long const SeafResumableMinFileSize;

/// Name prefix of the per-attempt staging file (plan §3.2).
extern NSString * const SeafResumableStagingPrefix;

extern NSString * const SeafResumableErrorDomain;

/// Entry name of uploads started in the share extension. Nothing runs such a
/// task again once the extension is gone, so the sweeper finishes its
/// committed attempts without waiting (plan §4.2, §9).
extern NSString * const SeafResumableEntryShare;

typedef NS_ENUM(NSInteger, SeafResumableErrorCode) {
    /// The server refused the upload for good (quota, size, permission, path gone).
    SeafResumableErrorTerminal = 1,
    /// Worth another attempt later; the record is kept so the next one resumes.
    SeafResumableErrorRetryable = 2,
    /// The upload was cancelled.
    SeafResumableErrorCancelled = 3,
};

/// Attempt states (plan §5.1). Values are stored in SQLite; do not renumber.
typedef NS_ENUM(NSInteger, SeafResumableState) {
    SeafResumableStateUploading = 0,
    SeafResumableStateFinalPending = 1,
    SeafResumableStateCommitted = 2,
    SeafResumableStateRenamePending = 3,
    SeafResumableStateDone = 4,
    SeafResumableStateAbandoned = 5,
};

/// How a session ended, as reported to SeafUploadOperation.
typedef NS_ENUM(NSInteger, SeafResumableOutcome) {
    SeafResumableOutcomeSuccess = 0,
    /// Use the existing single-request upload instead (not enabled, bad response, header stripped ...).
    SeafResumableOutcomeFallback,
    SeafResumableOutcomeRetryable,
    SeafResumableOutcomeTerminal,
    SeafResumableOutcomeCancelled,
};

/// Result of interpreting a file-uploaded-bytes response (plan §6.2, first rows of the table).
typedef NS_ENUM(NSInteger, SeafResumableProbeKind) {
    SeafResumableProbeCancelled = 0,
    /// Network error, timeout, 5xx: try again after a delay.
    SeafResumableProbeTransient,
    /// 404: library or folder gone.
    SeafResumableProbeTerminal,
    /// Other 4xx, or 2xx with an unusable body: this file goes single-request.
    SeafResumableProbeInvalid,
    /// 2xx without `Accept-Ranges: bytes`: the server has resumable upload off.
    SeafResumableProbeNotEnabled,
    SeafResumableProbeSupported,
};

/// Offset alignment against the local record (plan §6.2, remaining rows).
typedef NS_ENUM(NSInteger, SeafResumableAlignment) {
    /// Server offset equals the confirmed offset: send the next segment.
    SeafResumableAlignContinue = 0,
    /// The in-flight segment arrived (its response was lost) and the local bytes still match.
    SeafResumableAlignAdvanceInflight,
    /// The in-flight segment arrived but the local bytes changed: start a new attempt.
    SeafResumableAlignContentChanged,
    /// Offset equals the file size while the final segment is pending: the server is committing.
    SeafResumableAlignCommitting,
    /// Anything else: count an offset regression and start a new attempt.
    SeafResumableAlignUntrusted,
};

/// Classification of one segment POST (plan §6.2, §6.3, §7).
typedef NS_ENUM(NSInteger, SeafResumableChunkOutcome) {
    SeafResumableChunkCancelled = 0,
    /// Intermediate segment stored (`{"success": true}`).
    SeafResumableChunkAccepted,
    /// Final segment committed and validated.
    SeafResumableChunkCommitted,
    /// The server treated a segment as a whole file (Content-Range lost on the way).
    SeafResumableChunkHeaderIgnored,
    SeafResumableChunkOffsetMismatch,
    SeafResumableChunkTokenExpired,
    SeafResumableChunkTerminal,
    /// Other 4xx: go single-request once and let that report the real error.
    SeafResumableChunkFallback,
    /// Intermediate segment: network error or 5xx, query and try again.
    SeafResumableChunkTransient,
    /// Final segment: outcome unknown (network error, timeout, 5xx, unparseable).
    SeafResumableChunkUncertain,
};

/// Next step while confirming an uncertain final segment (plan §6.3).
typedef NS_ENUM(NSInteger, SeafResumableFinalResolution) {
    SeafResumableFinalCommitted = 0,
    /// A staging file of the wrong size exists: delete it and keep confirming.
    SeafResumableFinalDeleteGarbage,
    SeafResumableFinalWait,
    SeafResumableFinalResend,
    /// The request finished without committing: check the staging file once more, then start over.
    SeafResumableFinalRecheck,
    SeafResumableFinalNewAttempt,
};

/// What the main app's sweeper does with one record (plan §9).
typedef NS_ENUM(NSInteger, SeafResumableSweepAction) {
    SeafResumableSweepNone = 0,
    /// Drop the record: an unacknowledged old receipt, or an abandoned attempt that never committed a file.
    SeafResumableSweepDeleteRecord,
    /// Delete the abandoned attempt's staging file, then the record.
    SeafResumableSweepDeleteStaging,
    /// Mark it abandoned; a staging file it left goes on the next pass.
    SeafResumableSweepAbandon,
    /// Hand it to a session that finishes without the source file: confirm the
    /// final segment, spot-check with the saved windows, rename.
    SeafResumableSweepFinish,
};

/// Next step while confirming an uncertain rename (plan §6.5).
typedef NS_ENUM(NSInteger, SeafResumableRenameResolution) {
    SeafResumableRenamePublished = 0,
    SeafResumableRenameRetry,
    SeafResumableRenameLost,
};

NS_ASSUME_NONNULL_END
