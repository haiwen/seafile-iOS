//
//  SeafResumableUploadVerifier.h
//  Seafile
//
//  Spot-check of a committed staging file before it is published (plan §6.4):
//  reads every saved window back with a Range request and compares its hash.
//  Needs no source file, so the upload session and the main app's sweeper
//  (through a finish-only session) share it.
//

#import <Foundation/Foundation.h>
#import "SeafResumableUploadRecord.h"

@class SeafConnection;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SeafResumableVerifyResult) {
    SeafResumableVerifyPassed = 0,
    /// A window read back differs from the source: a zero-filled hole or other damage.
    SeafResumableVerifyMismatch,
    /// The server answered 200 to a Range request: the check cannot run.
    SeafResumableVerifyRangeUnsupported,
    /// The file is not there (404 for its download link).
    SeafResumableVerifyGone,
    /// Network error or unexpected answer; worth trying again later.
    SeafResumableVerifyTransient,
    SeafResumableVerifyCancelled,
};

@interface SeafResumableUploadVerifier : NSObject

- (instancetype)initWithConnection:(SeafConnection *)connection
                            repoId:(NSString *)repoId
                              path:(NSString *)path
                           windows:(NSArray<SeafProbeWindow *> *)windows NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// `completion` runs once on `queue`, unless -cancel came first. All state
/// lives on `queue`; call -cancel there too.
- (void)startOnQueue:(dispatch_queue_t)queue
          completion:(void (^)(SeafResumableVerifyResult result, NSError * _Nullable error))completion;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
