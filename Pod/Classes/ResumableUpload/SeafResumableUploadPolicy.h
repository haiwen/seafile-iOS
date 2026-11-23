//
//  SeafResumableUploadPolicy.h
//  Seafile
//
//  Pure decision functions for resumable uploads (plan §5.3). No networking,
//  no storage, no file IO: every rule in the plan's tables lives here so it
//  can be unit tested row by row.
//

#import <Foundation/Foundation.h>
#import "SeafResumableUploadDefines.h"
#import "SeafResumableUploadRecord.h"

NS_ASSUME_NONNULL_BEGIN

@interface SeafResumableProbeResult : NSObject
@property (nonatomic, readonly) SeafResumableProbeKind kind;
@property (nonatomic, readonly) long long uploadedBytes;
+ (instancetype)resultWithKind:(SeafResumableProbeKind)kind uploadedBytes:(long long)bytes;
@end

@interface SeafResumableChunkResult : NSObject
@property (nonatomic, readonly) SeafResumableChunkOutcome outcome;
@property (nonatomic, readonly) NSInteger status;
/// Set when the server committed a file (final segment, or a header-ignored segment).
@property (nonatomic, readonly, copy, nullable) NSString *committedName;
@property (nonatomic, readonly, copy, nullable) NSString *committedId;
@property (nonatomic, readonly) long long committedSize;
+ (instancetype)resultWithOutcome:(SeafResumableChunkOutcome)outcome status:(NSInteger)status;
+ (instancetype)resultWithOutcome:(SeafResumableChunkOutcome)outcome status:(NSInteger)status
                             name:(nullable NSString *)name fileId:(nullable NSString *)fileId size:(long long)size;
@end

@interface SeafResumableUploadPolicy : NSObject

#pragma mark Eligibility and naming

/// Plan §4.1 condition 1.
+ (BOOL)shouldSegmentFileOfSize:(long long)size;

/// `.seafile-upload-<16 hex><.ext>`; `randomHex` must be 16 lowercase hex characters.
+ (NSString *)stagingNameForTargetName:(NSString *)targetName randomHex:(NSString *)randomHex;
/// Same, with fresh random bytes.
+ (NSString *)stagingNameForTargetName:(NSString *)targetName;
+ (BOOL)isStagingName:(nullable NSString *)name;

/// NFC form used for record keys and request fields.
+ (NSString *)normalizedName:(NSString *)name;
/// RFC 3339 with offset, the format the existing single-request upload already sends.
+ (nullable NSString *)lastModifyStringForDate:(nullable NSDate *)date;

/// Number of segments, and the inclusive end byte of the segment that starts at `start`.
+ (long long)segmentCountForFileSize:(long long)fileSize chunkSize:(long long)chunkSize;
+ (long long)segmentEndForStart:(long long)start fileSize:(long long)fileSize chunkSize:(long long)chunkSize;

#pragma mark Query decision table (plan §6.2)

/// First five rows of the table. `acceptRanges` is the raw header value (nil when absent).
+ (SeafResumableProbeResult *)interpretProbeWithStatus:(NSInteger)status
                                          acceptRanges:(nullable NSString *)acceptRanges
                                                  body:(nullable id)body
                                                 error:(nullable NSError *)error;

/// Remaining rows: compare a supported server offset with the local record.
/// `localInflightHash` is the SHA-1 of the local bytes of the in-flight segment, computed now.
+ (SeafResumableAlignment)alignServerOffset:(long long)serverOffset
                            confirmedOffset:(long long)confirmedOffset
                                inflightEnd:(long long)inflightEnd
                               inflightHash:(nullable NSString *)inflightHash
                          localInflightHash:(nullable NSString *)localInflightHash
                                   fileSize:(long long)fileSize
                               finalPending:(BOOL)finalPending;

#pragma mark Segment responses (plan §6.2, §6.3, §7)

+ (SeafResumableChunkResult *)classifyChunkResponseWithStatus:(NSInteger)status
                                                         body:(nullable id)body
                                                   bodyString:(nullable NSString *)bodyString
                                                        error:(nullable NSError *)error
                                                       isLast:(BOOL)isLast
                                                     fileSize:(long long)fileSize
                                                  stagingName:(NSString *)stagingName;

/// Errors that end the upload for good (plan §7, terminal row).
+ (BOOL)isTerminalStatus:(NSInteger)status bodyString:(nullable NSString *)bodyString;

/// Body text from an AFNetworking response object or failure error (plain-text and broken-JSON bodies included).
+ (nullable NSString *)bodyStringFromResponseObject:(nullable id)responseObject error:(nullable NSError *)error;

+ (BOOL)isCancellationError:(nullable NSError *)error;

#pragma mark Final segment confirmation (plan §6.3)

+ (SeafResumableFinalResolution)resolveFinalWithStagingExists:(BOOL)stagingExists
                                                  stagingSize:(long long)stagingSize
                                                 serverOffset:(long long)serverOffset
                                              confirmedOffset:(long long)confirmedOffset
                                                     fileSize:(long long)fileSize
                                         secondsSinceFinalSent:(NSTimeInterval)elapsed;

#pragma mark Rename confirmation (plan §6.5)

/// YES for `target` itself and for the server's auto-renamed forms `base (n).ext`.
+ (BOOL)isName:(NSString *)name candidateForTarget:(NSString *)target;

/// `listing` holds dicts with "name" and "id". `snapshot` maps candidate names to ids before the rename.
+ (SeafResumableRenameResolution)resolveRenameWithStagingExists:(BOOL)stagingExists
                                                        listing:(nullable NSArray<NSDictionary *> *)listing
                                                       snapshot:(nullable NSDictionary<NSString *, NSString *> *)snapshot
                                                     targetName:(NSString *)targetName
                                                            oid:(NSString *)oid
                                                  publishedName:(NSString * _Nullable * _Nullable)publishedName;

/// Candidate names (and their ids) currently in a directory listing.
+ (NSDictionary<NSString *, NSString *> *)renameSnapshotFromListing:(nullable NSArray<NSDictionary *> *)listing
                                                         targetName:(NSString *)targetName;

#pragma mark Sweeping (plan §9)

/// Records untouched this long are given up (receipts: deleted).
+ (NSTimeInterval)recordLifetime;
/// How long an attempt nobody holds is left to its own task before the sweeper takes it over.
+ (NSTimeInterval)takeOverAfter;

/// `live`: another execution holds the attempt and its heartbeat is fresh.
/// `reason` is set for SeafResumableSweepAbandon.
+ (SeafResumableSweepAction)sweepActionForRecord:(SeafResumableUploadRecord *)record
                                            live:(BOOL)live
                                             now:(NSTimeInterval)now
                                          reason:(NSString * _Nullable * _Nullable)reason;

@end

NS_ASSUME_NONNULL_END
