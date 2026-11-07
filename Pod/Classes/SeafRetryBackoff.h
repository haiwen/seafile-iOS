//
//  SeafRetryBackoff.h
//  Seafile
//
//  How long to leave something alone after it failed. Several places retried
//  on a fixed timer with no memory of the failure: a photo the server refuses,
//  an upload queue paused for quota, a camera folder that cannot be created
//  were all tried again every 30 seconds for as long as the app ran. With
//  this, every failure makes the next attempt wait longer (30 s doubling to
//  30 min) and a success starts over.
//
//  Header only, Foundation only, state kept in memory by the caller: a new
//  source file in the pod would need a pod install, and Pod/Tests builds this
//  on its own.
//

#import <Foundation/Foundation.h>

static const NSTimeInterval SeafRetryBackoffBase = 30.0;
static const NSTimeInterval SeafRetryBackoffMax = 1800.0;

/// The wait after `failures` failures in a row: 0 for none, then the base,
/// doubling, up to the maximum.
static inline NSTimeInterval SeafRetryBackoffDelay(NSUInteger failures)
{
    if (failures == 0) return 0;
    NSUInteger doublings = failures - 1 < 16 ? failures - 1 : 16;
    NSTimeInterval delay = SeafRetryBackoffBase * (NSTimeInterval)(1UL << doublings);
    return delay < SeafRetryBackoffMax ? delay : SeafRetryBackoffMax;
}

#pragma mark - Failures by key

// `state` maps a key to @[failures, notBefore]. Not thread safe: the caller
// serialises access.

static inline NSUInteger SeafRetryBackoffFailures(NSDictionary<NSString *, NSArray *> *state, NSString *key)
{
    return key ? [state[key].firstObject unsignedIntegerValue] : 0;
}

/// Counts a failure of `key`; returns the moment it may be tried again.
static inline NSDate *SeafRetryBackoffNoteFailure(NSMutableDictionary<NSString *, NSArray *> *state, NSString *key, NSDate *now)
{
    if (!key) return now;
    NSUInteger failures = SeafRetryBackoffFailures(state, key) + 1;
    NSDate *notBefore = [now dateByAddingTimeInterval:SeafRetryBackoffDelay(failures)];
    state[key] = @[@(failures), notBefore];
    return notBefore;
}

static inline void SeafRetryBackoffNoteSuccess(NSMutableDictionary<NSString *, NSArray *> *state, NSString *key)
{
    if (key) [state removeObjectForKey:key];
}

/// YES while `key` is to be left alone.
static inline BOOL SeafRetryBackoffIsWaiting(NSDictionary<NSString *, NSArray *> *state, NSString *key, NSDate *now)
{
    NSDate *notBefore = key ? state[key].lastObject : nil;
    return notBefore && [notBefore compare:now] == NSOrderedDescending;
}

#pragma mark - What a failure says

// The key AFNetworking stores the HTTP response under; spelled out so this
// header does not import AFNetworking.
static NSString * const SeafRetryFailingResponseKey = @"com.alamofire.serialization.response.error.response";

/// The request was cancelled (a pause, a settings change): not a failure.
static inline BOOL SeafRetryErrorIsCancellation(NSError *error)
{
    return [error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled;
}

/// The request never got an answer (offline, timed out, connection lost).
/// That says nothing about the file it was for: every file fails the same
/// way, and all of them can go as soon as the network is back.
static inline BOOL SeafRetryErrorIsNetworkOnly(NSError *error)
{
    if (![error.domain isEqualToString:NSURLErrorDomain]) return NO;
    return ![error.userInfo[SeafRetryFailingResponseKey] isKindOfClass:[NSHTTPURLResponse class]];
}

/// YES when the failure is to be held against the file: the server answered
/// with an error, or the file could not be prepared on the device.
static inline BOOL SeafRetryErrorCountsAgainstFile(NSError *error)
{
    if (!error) return NO;
    return !SeafRetryErrorIsCancellation(error) && !SeafRetryErrorIsNetworkOnly(error);
}
