//
//  SeafResumableUploadSession.h
//  Seafile
//
//  One execution of a resumable upload (plan §6): recovers the task's previous
//  state, queries the server before every segment, sends 8 MiB segments to a
//  unique staging name, confirms an uncertain final segment, spot-checks the
//  committed file, renames it to the target and leaves a receipt.
//

#import <Foundation/Foundation.h>
#import "SeafResumableUploadDefines.h"

@class SeafConnection, SeafResumableUploadRecord;

NS_ASSUME_NONNULL_BEGIN

typedef void (^SeafResumableCompletion)(SeafResumableOutcome outcome, NSString * _Nullable oid,
                                        NSString * _Nullable serverDate, NSError * _Nullable error);

@interface SeafResumableUploadSession : NSObject

- (instancetype)initWithConnection:(SeafConnection *)connection
                            repoId:(NSString *)repoId
                         parentDir:(NSString *)parentDir
                        targetName:(NSString *)targetName
                         localPath:(NSString *)localPath
                          fileSize:(long long)fileSize
                        lastModify:(nullable NSString *)lastModify
                         overwrite:(BOOL)overwrite
                            taskId:(NSString *)taskId
                             entry:(NSString *)entry NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// For the sweeper (plan §9): finishes one attempt that no task will run again,
/// without the source file. A pending final segment is confirmed, a committed
/// file spot-checked with the saved windows, then renamed. Anything that would
/// need the source (resending, a new attempt) abandons the attempt instead.
- (instancetype)initToFinishRecord:(SeafResumableUploadRecord *)record connection:(SeafConnection *)connection;

/// Overall progress 0...1, on the main queue.
@property (nonatomic, copy, nullable) void (^progressHandler)(float progress);
/// YES when the user removed the task: the attempt is abandoned instead of kept.
@property (nonatomic, copy, nullable) BOOL (^userCancelled)(void);

/// The completion runs once, on the main queue.
- (void)startWithCompletion:(SeafResumableCompletion)completion;
- (void)cancel;

/// Confirmed bytes of this task's resumable attempt, for showing progress before it starts (plan §6.2).
+ (long long)confirmedBytesForTaskId:(nullable NSString *)taskId;

@end

NS_ASSUME_NONNULL_END
