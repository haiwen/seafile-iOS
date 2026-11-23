//
//  SeafResumableUploadSweeper.h
//  Seafile
//
//  Housekeeping for resumable uploads (plan §9), run by the main app once per
//  account at launch: deletes staging files of abandoned attempts and late
//  garbage under tombstoned names, finishes attempts nobody else will finish
//  (confirm, spot-check with the saved windows, rename: no source file needed),
//  expires old records and removes stale segment bodies.
//

#import <Foundation/Foundation.h>

@class SeafConnection;

NS_ASSUME_NONNULL_BEGIN

@interface SeafResumableUploadSweeper : NSObject
+ (void)sweepForConnection:(SeafConnection *)connection;
@end

NS_ASSUME_NONNULL_END
