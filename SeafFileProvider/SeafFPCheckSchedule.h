//
//  SeafFPCheckSchedule.h
//  SeafFileProvider
//
//  Which directories a working set pass re-lists, and which ones it leaves
//  alone because their last listing failed (design §8.2). Every directory a
//  pass touches ends up listed (the store stamps it), retired by its parent's
//  listing, or backed off here: that is what makes "the ones that did not fit
//  are due now" terminate. Without it five directories that keep failing take
//  every slot of every pass and the pass repeats once a second.
//
//  Kept in memory: the one-second chain needs the process's own timer, so a
//  new process starts without one, and a directory that still fails there is
//  backed off again after one attempt. Foundation only (StoreTest builds it).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// First wait after a failed listing; doubles per failure up to the maximum.
extern const NSTimeInterval SeafFPCheckBackoffBase;
extern const NSTimeInterval SeafFPCheckBackoffMax;

@interface SeafFPCheckSchedule : NSObject

/// The directories to list now, least recently listed first, at most `limit`.
/// Left alone: directories listed within `interval` and directories backed
/// off. recheckAt: when the first of those may be checked again; now when
/// more were due than fit; nil when nothing is waiting.
- (NSArray<NSString *> *)containersToCheckAmong:(NSSet<NSString *> *)candidates
                                      checkedAt:(NSDictionary<NSString *, NSDate *> *)checkedAt
                                            now:(NSDate *)now
                                          limit:(NSUInteger)limit
                                       interval:(NSTimeInterval)interval
                                      recheckAt:(NSDate * _Nullable * _Nullable)recheckAt;

/// A listing of the directory failed, was only served from the cache, or
/// could not be applied: no pass lists it again before the returned date.
- (NSDate *)noteFailureOfContainer:(NSString *)container at:(NSDate *)now;
/// The server listed the directory and the store took the listing.
- (void)noteSuccessOfContainer:(NSString *)container;
- (BOOL)isContainerBackedOff:(NSString *)container at:(NSDate *)now;

/// A pass stopped because the server (not one directory) did not answer:
/// passes list nothing before the returned date.
- (NSDate *)notePassAbortedAt:(NSDate *)now;
/// Any fresh listing: the server is back, passes may list again.
- (void)noteServerAnswered;
/// nil when a pass may talk to the server.
- (nullable NSDate *)passBlockedUntilAt:(NSDate *)now;

/// Another session (re-login): what failed before says nothing about it.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
