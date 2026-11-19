//
//  SeafFPErrorResolutionTest.m
//  Standalone macOS check of SeafFPErrorResolution and of the classification
//  that feeds it (run.sh builds and runs it).
//
//  The scenario behind it: a delete of a file somebody else has locked is
//  refused with 403. The extension answers NotAuthenticated, and signals the
//  error as resolved after the next fresh listing -- which a working set pass
//  provides about every two minutes. The system retries the delete, it is
//  refused again, and so on for as long as the process runs.
//

#import <Foundation/Foundation.h>
#import <FileProvider/FileProvider.h>
#import "SeafFPErrorResolution.h"
#import "SeafFPErrors.h"

static int gFailures = 0;
static int gChecks = 0;

#define CHECK(cond, ...) do { \
    gChecks++; \
    if (!(cond)) { gFailures++; NSLog(@"FAIL %s:%d " #cond " -- %@", __FILE__, __LINE__, [NSString stringWithFormat:__VA_ARGS__]); } \
} while (0)

static const NSInteger kDenied = NSFileProviderErrorNotAuthenticated;
static const NSInteger kUnreachable = NSFileProviderErrorServerUnreachable;
static const NSInteger kQuota = NSFileProviderErrorInsufficientQuota;
// A working set pass lists the library list this often while the process runs.
static const NSTimeInterval kPassInterval = 120.0;

static NSDate *T(NSTimeInterval seconds)
{
    return [NSDate dateWithTimeIntervalSinceReferenceDate:2000000 + seconds];
}

/// One item the server keeps refusing, a fresh listing every pass interval,
/// and a system that retries the item as soon as its error is resolved.
/// Returns the times at which the error was signalled as resolved.
static NSArray<NSNumber *> *RunRefusedItem(SeafFPErrorResolution *resolution, NSTimeInterval duration)
{
    NSMutableArray<NSNumber *> *resolvedAt = [NSMutableArray array];
    [resolution noteErrorWithCode:kDenied aboutOneItem:YES at:T(0)];
    for (NSTimeInterval t = kPassInterval; t <= duration; t += kPassInterval) {
        if ([[resolution codesToResolveAt:T(t)] containsObject:@(kDenied)]) {
            [resolvedAt addObject:@(t)];
            // The retry is refused a few seconds later.
            [resolution noteErrorWithCode:kDenied aboutOneItem:YES at:T(t + 5)];
        }
    }
    return resolvedAt;
}

static void TestFirstFailureResolvesAtOnce(void)
{
    SeafFPErrorResolution *resolution = [SeafFPErrorResolution new];
    CHECK([resolution codesToResolveAt:T(0)].count == 0, @"nothing to resolve before any error");
    [resolution noteErrorWithCode:kDenied aboutOneItem:YES at:T(0)];
    CHECK([resolution resolutionOfCode:kDenied heldUntilAt:T(1)] == nil, @"a first failure is not held back");
    NSArray *codes = [resolution codesToResolveAt:T(1)];
    CHECK([codes isEqualToArray:@[@(kDenied)]], @"resolved by the next success: %@", codes);
    CHECK([resolution codesToResolveAt:T(2)].count == 0, @"resolved once, not on every success");
}

static void TestRefusedItemIsNotRetriedEveryPass(void)
{
    // Before: every pass resolved the error, one retry per pass.
    NSUInteger before = (NSUInteger)(3600.0 / kPassInterval);
    NSArray<NSNumber *> *resolvedAt = RunRefusedItem([SeafFPErrorResolution new], 3600.0);
    CHECK(resolvedAt.count >= 4 && resolvedAt.count <= 7, @"a handful of retries in the first hour, not %lu: %@", (unsigned long)before, resolvedAt);
    CHECK(resolvedAt.count * 4 <= before, @"at least four times fewer than one per pass (%lu vs %lu)", (unsigned long)resolvedAt.count, (unsigned long)before);
    for (NSUInteger i = 1; i < resolvedAt.count; i++) {
        NSTimeInterval gap = resolvedAt[i].doubleValue - resolvedAt[i - 1].doubleValue;
        NSTimeInterval expected = MIN(SeafFPResolutionBackoffMax, SeafFPResolutionBackoffBase * pow(2, i - 1));
        CHECK(gap >= expected, @"gap %lu is %.0f s, at least %.0f s", (unsigned long)i, gap, expected);
        CHECK(gap <= expected + 2 * kPassInterval, @"gap %lu is %.0f s, no more than a pass or two late", (unsigned long)i, gap);
    }

    // Capped: it keeps being retried, every half hour or so, so a lock that
    // was released or a quota that was cleared is picked up without the user.
    resolvedAt = RunRefusedItem([SeafFPErrorResolution new], 6 * 3600.0);
    NSUInteger lastHours = 0;
    for (NSNumber *at in resolvedAt) if (at.doubleValue > 2 * 3600.0) lastHours++;
    CHECK(lastHours >= 6 && lastHours <= 8, @"about two retries an hour once capped: %lu in four hours", (unsigned long)lastHours);
}

static void TestHeldBackWhileWaiting(void)
{
    SeafFPErrorResolution *resolution = [SeafFPErrorResolution new];
    [resolution noteErrorWithCode:kDenied aboutOneItem:YES at:T(0)];
    [resolution codesToResolveAt:T(10)];
    [resolution noteErrorWithCode:kDenied aboutOneItem:YES at:T(20)];
    NSDate *until = [resolution resolutionOfCode:kDenied heldUntilAt:T(21)];
    CHECK(until && fabs([until timeIntervalSinceDate:T(20)] - SeafFPResolutionBackoffBase) < 0.001, @"held for the base wait: %@", until);
    CHECK([resolution codesToResolveAt:T(20 + SeafFPResolutionBackoffBase - 1)].count == 0, @"a success inside the wait resolves nothing");
    // The system's own retry, or a second refused item, does not extend it.
    [resolution noteErrorWithCode:kDenied aboutOneItem:YES at:T(100)];
    CHECK([[resolution resolutionOfCode:kDenied heldUntilAt:T(101)] isEqualToDate:until], @"noted again without a resolution: the wait stands");
    CHECK([[resolution codesToResolveAt:T(20 + SeafFPResolutionBackoffBase)] isEqualToArray:@[@(kDenied)]], @"resolved when the wait is over");
    CHECK([resolution resolutionOfCode:kDenied heldUntilAt:T(200)] == nil, @"not waiting once resolved");
}

static void TestServerFailuresAreNotHeldBack(void)
{
    // Offline, back, offline again: the fresh answer is the evidence, every time.
    SeafFPErrorResolution *resolution = [SeafFPErrorResolution new];
    for (int i = 0; i < 10; i++) {
        [resolution noteErrorWithCode:kUnreachable aboutOneItem:NO at:T(i * 30)];
        CHECK([[resolution codesToResolveAt:T(i * 30 + 10)] isEqualToArray:@[@(kUnreachable)]], @"round %d resolved at once", i);
    }

    // A refused item is waiting, then the session fails (same error code):
    // the next fresh answer resolves it, the location must not stay flagged.
    resolution = [SeafFPErrorResolution new];
    [resolution noteErrorWithCode:kDenied aboutOneItem:YES at:T(0)];
    [resolution codesToResolveAt:T(10)];
    [resolution noteErrorWithCode:kDenied aboutOneItem:YES at:T(20)];
    CHECK([resolution resolutionOfCode:kDenied heldUntilAt:T(21)] != nil, @"the item is waiting");
    [resolution noteErrorWithCode:kDenied aboutOneItem:NO at:T(30)];
    CHECK([resolution resolutionOfCode:kDenied heldUntilAt:T(31)] == nil, @"a failure of the session lifts the wait");
    CHECK([[resolution codesToResolveAt:T(40)] isEqualToArray:@[@(kDenied)]], @"resolved by the next fresh answer");
    // The item is retried with it, refused again, and its wait goes on growing.
    [resolution noteErrorWithCode:kDenied aboutOneItem:YES at:T(45)];
    NSDate *until = [resolution resolutionOfCode:kDenied heldUntilAt:T(46)];
    CHECK(until && fabs([until timeIntervalSinceDate:T(45)] - 2 * SeafFPResolutionBackoffBase) < 0.001, @"second recurrence, doubled: %@", until);
}

static void TestCodesAreIndependent(void)
{
    SeafFPErrorResolution *resolution = [SeafFPErrorResolution new];
    [resolution noteErrorWithCode:kDenied aboutOneItem:YES at:T(0)];
    [resolution codesToResolveAt:T(10)];
    [resolution noteErrorWithCode:kDenied aboutOneItem:YES at:T(20)];      // waiting
    [resolution noteErrorWithCode:kQuota aboutOneItem:YES at:T(25)];       // first time
    [resolution noteErrorWithCode:kUnreachable aboutOneItem:NO at:T(26)];
    NSArray *codes = [resolution codesToResolveAt:T(30)];
    CHECK(codes.count == 2 && [codes containsObject:@(kQuota)] && [codes containsObject:@(kUnreachable)], @"the other codes go, the waiting one stays: %@", codes);
    CHECK([[resolution codesToResolveAt:T(20 + SeafFPResolutionBackoffBase)] isEqualToArray:@[@(kDenied)]], @"and follows after its wait");
}

static void TestNewIncidentStartsOver(void)
{
    SeafFPErrorResolution *resolution = [SeafFPErrorResolution new];
    NSArray<NSNumber *> *resolvedAt = RunRefusedItem(resolution, 3600.0);
    NSTimeInterval last = resolvedAt.lastObject.doubleValue;
    // The item was fixed: nothing comes back. Hours later something else is refused.
    NSTimeInterval later = last + 5 + 3 * 3600.0;
    [resolution codesToResolveAt:T(last + 5 + SeafFPResolutionBackoffMax + 1)];
    [resolution noteErrorWithCode:kDenied aboutOneItem:YES at:T(later)];
    CHECK([resolution resolutionOfCode:kDenied heldUntilAt:T(later + 1)] == nil, @"a new incident is not held back");
    CHECK([[resolution codesToResolveAt:T(later + 10)] isEqualToArray:@[@(kDenied)]], @"and is resolved at once");
    [resolution noteErrorWithCode:kDenied aboutOneItem:YES at:T(later + 15)];
    NSDate *until = [resolution resolutionOfCode:kDenied heldUntilAt:T(later + 16)];
    CHECK(until && fabs([until timeIntervalSinceDate:T(later + 15)] - SeafFPResolutionBackoffBase) < 0.001, @"its first recurrence waits the base again: %@", until);
}

static void TestForgetWaitsKeepsPendingErrors(void)
{
    SeafFPErrorResolution *resolution = [SeafFPErrorResolution new];
    RunRefusedItem(resolution, 3600.0);
    // After the run the error is either waiting or was just noted again.
    CHECK([resolution codesToResolveAt:T(3601)].count == 0, @"still waiting at the end of the run");
    [resolution forgetWaits];
    CHECK([resolution resolutionOfCode:kDenied heldUntilAt:T(3602)] == nil, @"another session: no wait");
    CHECK([[resolution codesToResolveAt:T(3603)] isEqualToArray:@[@(kDenied)]], @"the error itself is still resolved by the next success");
    [resolution noteErrorWithCode:kDenied aboutOneItem:YES at:T(3610)];
    NSDate *until = [resolution resolutionOfCode:kDenied heldUntilAt:T(3611)];
    CHECK(until && fabs([until timeIntervalSinceDate:T(3610)] - SeafFPResolutionBackoffBase) < 0.001, @"and the count started over: %@", until);
}

static NSError *SeafError(NSInteger status)
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (status > 0) {
        userInfo[@"com.alamofire.serialization.response.error.response"] =
            [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.invalid/api2/x"] statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:nil];
    }
    return [NSError errorWithDomain:@"com.alamofire.error.serialization.response" code:-1011 userInfo:userInfo];
}

/// What AFNetworking's JSON serializer hands back for a refusal in plain text
/// (the file server's "Out of quota."): its parse failure on top, the error
/// with the response underneath.
static NSError *SeafPlainTextError(NSInteger status)
{
    return [NSError errorWithDomain:NSCocoaErrorDomain code:3840 userInfo:@{NSUnderlyingErrorKey: SeafError(status)}];
}

static void TestPlainTextRefusals(void)
{
    for (NSNumber *status in @[@443, @507]) {
        NSError *error = SeafPlainTextError(status.integerValue);
        CHECK([SeafFPErrors errorForSeafError:error].code == NSFileProviderErrorInsufficientQuota, @"plain text %@ is quota", status);
        CHECK([SeafFPErrors seafErrorConcernsOneItem:error], @"plain text %@ is a refusal of the item", status);
    }
    // Only quota is read from the underlying error: everything else stays as it was.
    for (NSNumber *status in @[@400, @403, @404, @500]) {
        NSError *error = SeafPlainTextError(status.integerValue);
        CHECK([SeafFPErrors errorForSeafError:error].code == NSFileProviderErrorServerUnreachable, @"plain text %@ is not reclassified", status);
        CHECK(![SeafFPErrors seafErrorConcernsOneItem:error], @"plain text %@ is not held against the item", status);
    }
    NSError *parseOnly = [NSError errorWithDomain:NSCocoaErrorDomain code:3840 userInfo:nil];
    CHECK([SeafFPErrors errorForSeafError:parseOnly].code == NSFileProviderErrorServerUnreachable, @"a parse failure without a response");
    CHECK(![SeafFPErrors seafErrorConcernsOneItem:parseOnly], @"a parse failure without a response");
}

static void TestClassification(void)
{
    for (NSNumber *status in @[@400, @403, @409, @413, @440, @443, @507, @520]) {
        CHECK([SeafFPErrors seafErrorConcernsOneItem:SeafError(status.integerValue)], @"%@ is a refusal of the item", status);
    }
    for (NSNumber *status in @[@0, @401, @408, @429, @500, @502, @503, @504]) {
        CHECK(![SeafFPErrors seafErrorConcernsOneItem:SeafError(status.integerValue)], @"%@ is the server or the session", status);
    }
    CHECK(![SeafFPErrors seafErrorConcernsOneItem:nil], @"no error at all");
    CHECK(![SeafFPErrors seafErrorConcernsOneItem:[SeafFPErrors serverUnreachable]], @"an error that carries no response");
    // Every refusal the extension notes for resolution maps to a code the system throttles on.
    CHECK([SeafFPErrors errorForSeafError:SeafError(403)].code == NSFileProviderErrorNotAuthenticated, @"403");
    CHECK([SeafFPErrors errorForSeafError:SeafError(443)].code == NSFileProviderErrorInsufficientQuota, @"443");
    CHECK([SeafFPErrors errorForSeafError:SeafError(413)].code == NSFileProviderErrorCannotSynchronize, @"413");
}

int main(void)
{
    @autoreleasepool {
        TestFirstFailureResolvesAtOnce();
        TestRefusedItemIsNotRetriedEveryPass();
        TestHeldBackWhileWaiting();
        TestServerFailuresAreNotHeldBack();
        TestCodesAreIndependent();
        TestNewIncidentStartsOver();
        TestForgetWaitsKeepsPendingErrors();
        TestClassification();
        TestPlainTextRefusals();
        NSLog(@"RESULT error resolution: %d checks, %d failed", gChecks, gFailures);
    }
    return gFailures == 0 ? 0 : 1;
}
