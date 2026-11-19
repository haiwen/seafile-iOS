//
//  SeafFPErrorResolution.h
//  SeafFileProvider
//
//  When the system may be told that an error it throttles on is resolved.
//  -[NSFileProviderManager signalErrorResolved:] makes the system retry every
//  item throttled for that error code, and the extension signals it on any
//  success -- including the library list a working set pass fetches about
//  every two minutes. That is right for "the server did not answer": a fresh
//  answer is the evidence. It is wrong for a refusal of one item (403 on a
//  locked file, 413, above quota): the listing says nothing about it, the
//  system retries, the item fails the same way, and the next pass resolves it
//  again -- the same request every two minutes for as long as the process
//  runs.
//
//  So a resolution that did not hold is not repeated right away: once an
//  error code has been resolved and came back for one item, the next
//  resolution waits, 120 s doubling to 30 min.
//
//  Kept in memory, like SeafFPCheckSchedule: a new process resolves a first
//  failure at once and is back in the wait after one attempt. Foundation only
//  (StoreTest builds it).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// First wait before an error that came back is resolved again; doubles per
/// recurrence up to the maximum.
extern const NSTimeInterval SeafFPResolutionBackoffBase;
extern const NSTimeInterval SeafFPResolutionBackoffMax;

@interface SeafFPErrorResolution : NSObject

/// The system was answered with this error code. aboutOneItem: the failure
/// was the server's (or the device's) refusal of that one item; NO when the
/// server or the session did not answer, which the next fresh answer settles.
- (void)noteErrorWithCode:(NSInteger)code aboutOneItem:(BOOL)aboutOneItem at:(NSDate *)now;

/// Something succeeded. The error codes to signal as resolved now; they are
/// no longer waiting afterwards. Codes still in their wait are left out and
/// come with a later success.
- (NSArray<NSNumber *> *)codesToResolveAt:(NSDate *)now;

/// When the code waiting for its resolution may be resolved; nil when it is
/// not waiting or may be resolved at once.
- (nullable NSDate *)resolutionOfCode:(NSInteger)code heldUntilAt:(NSDate *)now;

/// Another session (re-login): what was refused before says nothing about it.
/// Errors not resolved yet stay, and go with the next success.
- (void)forgetWaits;

@end

NS_ASSUME_NONNULL_END
