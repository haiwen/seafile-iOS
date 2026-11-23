//
//  SeafResumableUploadRecord.h
//  Seafile
//
//  One resumable upload attempt, as stored in SeafResumableUploadStore (plan §5.1).
//

#import <Foundation/Foundation.h>
#import "SeafResumableUploadDefines.h"

NS_ASSUME_NONNULL_BEGIN

/// A small run of non-zero bytes inside one segment, read back from the server
/// before publishing to detect zero-filled holes (plan §6.4). Only its position
/// and hash are kept, so a process without the source file (the sweeper) can
/// run the check too.
@interface SeafProbeWindow : NSObject
@property (nonatomic, readonly) long long offset;
@property (nonatomic, readonly) NSUInteger length;
/// SHA-1 (hex) of the window's bytes.
@property (nonatomic, readonly, copy) NSString *sha1;
+ (instancetype)windowWithOffset:(long long)offset length:(NSUInteger)length sha1:(NSString *)sha1;
/// nil when `dict` is not a valid serialized window.
+ (nullable instancetype)windowWithDictionary:(id)dict;
- (NSDictionary *)dictionaryRepresentation;
/// YES when `data` is exactly the bytes the window was taken from.
- (BOOL)matchesData:(nullable NSData *)data;
@end

@interface SeafResumableUploadRecord : NSObject <NSCopying>

@property (nonatomic, copy) NSString *attemptId;
/// Persistent id of the upload task this attempt belongs to (plan §4.2).
@property (nonatomic, copy) NSString *taskId;
@property (nonatomic, copy) NSString *account;
@property (nonatomic, copy) NSString *repoId;
/// NFC-normalized, starts with "/".
@property (nonatomic, copy) NSString *parentDir;
/// NFC-normalized target file name.
@property (nonatomic, copy) NSString *targetName;
@property (nonatomic, copy) NSString *stagingName;
@property (nonatomic) BOOL overwrite;

@property (nonatomic) long long fileSize;
/// The `last_modify` value sent to the server (RFC 3339), may be nil.
@property (nonatomic, copy, nullable) NSString *lastModify;
/// device:inode:mtime of the local file when hashes were last computed.
@property (nonatomic, copy, nullable) NSString *fileIdentity;
@property (nonatomic) long long chunkSize;
/// SHA-1 (hex) of every confirmed segment, in order.
@property (nonatomic, copy) NSArray<NSString *> *chunkHashes;

@property (nonatomic) long long confirmedOffset;
/// End offset (exclusive) of the segment being sent, 0 when none.
@property (nonatomic) long long inflightEnd;
@property (nonatomic, copy, nullable) NSString *inflightHash;

@property (nonatomic) SeafResumableState state;
@property (nonatomic) NSTimeInterval finalSentAt;

/// Name the server gave the committed staging file (may carry " (n)").
@property (nonatomic, copy, nullable) NSString *committedName;
@property (nonatomic, copy, nullable) NSString *oid;
/// name -> obj_id of target-name candidates seen before the rename.
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *renameSnapshot;
@property (nonatomic, copy, nullable) NSString *finalName;
/// YES once a staging file may exist on the server (it must be deleted when abandoning).
@property (nonatomic) BOOL stagingCommitted;
/// YES once the committed staging file passed the content spot-check (plan §6.4).
@property (nonatomic) BOOL verified;

/// Where the attempt was started (SeafResumableEntry* names); the sweeper
/// takes over attempts whose entry never runs again (plan §9).
@property (nonatomic, copy, nullable) NSString *entry;
/// Spot-check windows (plan §6.4), taken from the source just before the final
/// segment; nil until then. An empty array means the file has no non-zero byte.
@property (nonatomic, copy, nullable) NSArray<SeafProbeWindow *> *probeWindows;

@property (nonatomic, copy, nullable) NSString *runToken;
@property (nonatomic) NSTimeInterval heartbeatAt;
@property (nonatomic, copy, nullable) NSString *reason;
@property (nonatomic) NSTimeInterval createdAt;
@property (nonatomic) NSTimeInterval updatedAt;

/// `account|repo|parentDir|targetName`
@property (nonatomic, readonly) NSString *targetKey;
/// parentDir joined with the staging (or committed) name.
@property (nonatomic, readonly) NSString *stagingPath;
@property (nonatomic, readonly) BOOL isActive;

+ (NSString *)targetKeyForAccount:(NSString *)account repoId:(NSString *)repoId
                        parentDir:(NSString *)parentDir targetName:(NSString *)targetName;

@end

NS_ASSUME_NONNULL_END
