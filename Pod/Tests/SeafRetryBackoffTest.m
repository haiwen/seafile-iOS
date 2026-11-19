//
//  SeafRetryBackoffTest.m
//  Standalone macOS check of SeafRetryBackoff.h (run.sh builds and runs it).
//
//  The scenario behind it: the account queue's timer fires every 30 seconds
//  and, with photos still queued and nothing running, queued every one of
//  them again. A photo the server refuses, or one that cannot be exported,
//  was tried on every tick for as long as the app ran. The same timer ended
//  every pause of the upload queue 30 seconds after it began.
//
//  This checks the waiting rules, not the queue or the backup tool that use
//  them.
//

#import <Foundation/Foundation.h>
#import "SeafRetryBackoff.h"

static int gFailures = 0;
static int gChecks = 0;

#define CHECK(cond, ...) do { \
    gChecks++; \
    if (!(cond)) { gFailures++; NSLog(@"FAIL %s:%d " #cond " -- %@", __FILE__, __LINE__, [NSString stringWithFormat:__VA_ARGS__]); } \
} while (0)

static const NSTimeInterval kTick = 30.0;

static NSDate *T(NSTimeInterval seconds)
{
    return [NSDate dateWithTimeIntervalSinceReferenceDate:3000000 + seconds];
}

static NSError *HTTPError(NSInteger status)
{
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.invalid/api2/x"]
                                                              statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:nil];
    return [NSError errorWithDomain:@"com.alamofire.error.serialization.response" code:NSURLErrorBadServerResponse
                           userInfo:@{SeafRetryFailingResponseKey: response}];
}

static void TestDelay(void)
{
    CHECK(SeafRetryBackoffDelay(0) == 0, @"no failure, no wait");
    NSTimeInterval expected = SeafRetryBackoffBase;
    for (NSUInteger failures = 1; failures <= 12; failures++) {
        CHECK(SeafRetryBackoffDelay(failures) == MIN(expected, SeafRetryBackoffMax), @"failure %lu waits %.0f s", (unsigned long)failures, SeafRetryBackoffDelay(failures));
        expected *= 2;
    }
    CHECK(SeafRetryBackoffDelay(1000) == SeafRetryBackoffMax, @"capped however often it failed");
    CHECK(SeafRetryBackoffDelay(NSUIntegerMax) == SeafRetryBackoffMax, @"and does not overflow");
}

static void TestFailuresByKey(void)
{
    NSMutableDictionary<NSString *, NSArray *> *state = [NSMutableDictionary dictionary];
    CHECK(!SeafRetryBackoffIsWaiting(state, @"a", T(0)), @"unknown key is not waiting");
    CHECK(!SeafRetryBackoffIsWaiting(state, nil, T(0)), @"nil key is not waiting");
    NSDate *until = SeafRetryBackoffNoteFailure(state, @"a", T(0));
    CHECK([until isEqualToDate:T(SeafRetryBackoffBase)], @"first failure: the base wait");
    CHECK(SeafRetryBackoffIsWaiting(state, @"a", T(SeafRetryBackoffBase - 1)), @"waiting inside it");
    CHECK(!SeafRetryBackoffIsWaiting(state, @"a", T(SeafRetryBackoffBase)), @"due when it is over");
    CHECK(!SeafRetryBackoffIsWaiting(state, @"b", T(1)), @"another key is not affected");
    until = SeafRetryBackoffNoteFailure(state, @"a", T(40));
    CHECK([until isEqualToDate:T(40 + 2 * SeafRetryBackoffBase)], @"second failure: doubled");
    CHECK(SeafRetryBackoffFailures(state, @"a") == 2, @"counted");
    SeafRetryBackoffNoteSuccess(state, @"a");
    CHECK(!SeafRetryBackoffIsWaiting(state, @"a", T(41)) && SeafRetryBackoffFailures(state, @"a") == 0, @"a success starts over");
    CHECK([SeafRetryBackoffNoteFailure(state, @"a", T(50)) isEqualToDate:T(50 + SeafRetryBackoffBase)], @"the base wait again");
    CHECK([SeafRetryBackoffNoteFailure(state, nil, T(60)) isEqualToDate:T(60)] && state.count == 1, @"nil key is ignored");
}

/// `photos` photos the server refuses every time, a tick every 30 seconds.
/// Returns the attempts made in `duration`, and the ticks that had anything to do.
static NSUInteger RunRefusedPhotos(NSUInteger photos, NSTimeInterval duration, BOOL backoff, NSUInteger *busyTicks)
{
    NSMutableDictionary<NSString *, NSArray *> *failures = [NSMutableDictionary dictionary];
    NSUInteger attempts = 0, busy = 0;
    for (NSTimeInterval t = 0; t < duration; t += kTick) {
        NSUInteger attempted = 0;
        for (NSUInteger i = 0; i < photos; i++) {
            NSString *photo = [NSString stringWithFormat:@"photo%lu", (unsigned long)i];
            if (backoff && SeafRetryBackoffIsWaiting(failures, photo, T(t))) continue;
            attempted++;
            if (backoff) SeafRetryBackoffNoteFailure(failures, photo, T(t + 2));   // refused two seconds later
        }
        attempts += attempted;
        if (attempted > 0) busy++;
    }
    if (busyTicks) *busyTicks = busy;
    return attempts;
}

static void TestRefusedPhotosAreNotRetriedEveryTick(void)
{
    const NSUInteger photos = 20;
    const NSTimeInterval sixHours = 6 * 3600.0;
    NSUInteger busyBefore = 0, busyAfter = 0;
    NSUInteger before = RunRefusedPhotos(photos, sixHours, NO, &busyBefore);
    NSUInteger after = RunRefusedPhotos(photos, sixHours, YES, &busyAfter);
    CHECK(before == photos * 720 && busyBefore == 720, @"before: every photo on every tick (%lu attempts)", (unsigned long)before);
    NSUInteger perPhoto = after / photos;
    CHECK(perPhoto >= 10 && perPhoto <= 20, @"after: %lu attempts per photo in six hours", (unsigned long)perPhoto);
    CHECK(after * 30 <= before, @"at least thirty times fewer requests (%lu vs %lu)", (unsigned long)after, (unsigned long)before);
    CHECK(busyAfter <= 20, @"and the tick has nothing to do most of the time (%lu of 720)", (unsigned long)busyAfter);

    // Once capped a photo is still tried about twice an hour, so a folder
    // that was restored or a quota that was cleared is picked up.
    NSUInteger lateAttempts = RunRefusedPhotos(1, 10 * 3600.0, YES, NULL) - RunRefusedPhotos(1, 6 * 3600.0, YES, NULL);
    CHECK(lateAttempts >= 7 && lateAttempts <= 9, @"%lu attempts in four hours once capped", (unsigned long)lateAttempts);
}

static void TestErrorPauseOfTheQueue(void)
{
    // The queue pauses on every failure once the same status was seen five
    // times; the tick ends the pause when it is over, the next upload fails,
    // and the queue pauses again.
    NSUInteger pauses = 0, resumes = 0;
    NSDate *until = nil;
    NSMutableArray<NSNumber *> *resumedAt = [NSMutableArray array];
    for (NSTimeInterval t = 0; t < 3 * 3600.0; t += kTick) {
        if (until && [until compare:T(t)] == NSOrderedDescending) continue;   // pause not over
        if (until) { resumes++; [resumedAt addObject:@(t)]; }
        pauses++;
        until = [T(t + 1) dateByAddingTimeInterval:SeafRetryBackoffDelay(pauses)];
    }
    CHECK(resumes >= 9 && resumes <= 13, @"%lu resumes in three hours, not 360", (unsigned long)resumes);
    for (NSUInteger i = 1; i < resumedAt.count; i++) {
        NSTimeInterval gap = resumedAt[i].doubleValue - resumedAt[i - 1].doubleValue;
        CHECK(gap >= SeafRetryBackoffDelay(i + 1), @"pause %lu lasted %.0f s, at least %.0f s", (unsigned long)(i + 1), gap, SeafRetryBackoffDelay(i + 1));
        CHECK(gap <= SeafRetryBackoffDelay(i + 1) + 2 * kTick, @"and ended within two ticks of its wait (%.0f s)", gap);
    }
    // An upload that went through: the next pause is short again.
    pauses = 0;
    CHECK(SeafRetryBackoffDelay(pauses + 1) == SeafRetryBackoffBase, @"after a success the first pause is the base wait");
}

static void TestWhatCountsAgainstAFile(void)
{
    NSError *cancelled = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
    NSError *offline = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
    NSError *timedOut = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
    NSError *local = [NSError errorWithDomain:@"Seafile" code:-1 userInfo:nil];
    NSError *missingFile = [NSError errorWithDomain:@"SeafUploadFile" code:-1 userInfo:nil];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.invalid/"]
                                                              statusCode:502 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    NSError *answeredURLError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadServerResponse
                                                userInfo:@{SeafRetryFailingResponseKey: response}];

    CHECK(SeafRetryErrorIsCancellation(cancelled) && !SeafRetryErrorCountsAgainstFile(cancelled), @"a cancelled upload is not a failure");
    CHECK(SeafRetryErrorIsNetworkOnly(offline) && !SeafRetryErrorCountsAgainstFile(offline), @"offline says nothing about the file");
    CHECK(SeafRetryErrorIsNetworkOnly(timedOut) && !SeafRetryErrorCountsAgainstFile(timedOut), @"neither does a timeout");
    CHECK(!SeafRetryErrorCountsAgainstFile(nil), @"no error");
    for (NSNumber *status in @[@400, @403, @404, @413, @443, @500, @502]) {
        CHECK(SeafRetryErrorCountsAgainstFile(HTTPError(status.integerValue)), @"the server answered %@", status);
    }
    CHECK(SeafRetryErrorCountsAgainstFile(answeredURLError), @"an answer delivered as a URL error still counts");
    CHECK(SeafRetryErrorCountsAgainstFile(local), @"the library is gone / the operation failed on the device");
    CHECK(SeafRetryErrorCountsAgainstFile(missingFile), @"the file could not be prepared");
}

static void TestOfflineDoesNotDelayPhotos(void)
{
    // Ten ticks offline, then the network is back: the photo goes at once.
    NSMutableDictionary<NSString *, NSArray *> *failures = [NSMutableDictionary dictionary];
    NSError *offline = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
    NSUInteger attempts = 0;
    for (NSUInteger tick = 0; tick < 10; tick++) {
        NSDate *now = T(tick * kTick);
        if (SeafRetryBackoffIsWaiting(failures, @"photo", now)) continue;
        attempts++;
        if (SeafRetryErrorCountsAgainstFile(offline)) SeafRetryBackoffNoteFailure(failures, @"photo", now);
    }
    CHECK(attempts == 10, @"tried on every tick while offline, as before (%lu)", (unsigned long)attempts);
    CHECK(!SeafRetryBackoffIsWaiting(failures, @"photo", T(10 * kTick)), @"and not waiting when the network is back");
}

int main(void)
{
    @autoreleasepool {
        TestDelay();
        TestFailuresByKey();
        TestRefusedPhotosAreNotRetriedEveryTick();
        TestErrorPauseOfTheQueue();
        TestWhatCountsAgainstAFile();
        TestOfflineDoesNotDelayPhotos();
        NSLog(@"RESULT retry backoff: %d checks, %d failed", gChecks, gFailures);
    }
    return gFailures == 0 ? 0 : 1;
}
