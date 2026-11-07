//
//  SeafFPCheckScheduleTest.m
//  Standalone macOS check of SeafFPCheckSchedule (run.sh builds and runs it).
//
//  The scenario behind it: five directories that were deleted on the server
//  kept answering 404, were never stamped as checked, and so filled all five
//  slots of every working set pass, once a second, for good.
//

#import <Foundation/Foundation.h>
#import "SeafFPCheckSchedule.h"

static int gFailures = 0;
static int gChecks = 0;

#define CHECK(cond, ...) do { \
    gChecks++; \
    if (!(cond)) { gFailures++; NSLog(@"FAIL %s:%d " #cond " -- %@", __FILE__, __LINE__, [NSString stringWithFormat:__VA_ARGS__]); } \
} while (0)

static const NSUInteger kLimit = 5;
static const NSTimeInterval kInterval = 120.0;

static NSDate *T(NSTimeInterval seconds)
{
    return [NSDate dateWithTimeIntervalSinceReferenceDate:1000000 + seconds];
}

/// The selection as it was before the schedule existed: no memory of failures.
static NSArray<NSString *> *OldSelection(NSSet<NSString *> *candidates, NSDictionary<NSString *, NSDate *> *checkedAt, NSDate *now, NSDate **recheckAt)
{
    NSMutableSet<NSString *> *containers = [candidates mutableCopy];
    NSDate *recent = [now dateByAddingTimeInterval:-kInterval];
    NSDate *earliestSkipped = nil;
    for (NSString *container in containers.allObjects) {
        NSDate *at = checkedAt[container];
        if (!at || [at compare:recent] != NSOrderedDescending) continue;
        [containers removeObject:container];
        if (!earliestSkipped || [at compare:earliestSkipped] == NSOrderedAscending) earliestSkipped = at;
    }
    *recheckAt = earliestSkipped ? [earliestSkipped dateByAddingTimeInterval:kInterval] : nil;
    NSArray<NSString *> *sorted = [containers.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSComparisonResult byDate = [(checkedAt[a] ?: [NSDate distantPast]) compare:(checkedAt[b] ?: [NSDate distantPast])];
        return byDate != NSOrderedSame ? byDate : [a compare:b];
    }];
    if (sorted.count > kLimit) {
        sorted = [sorted subarrayWithRange:NSMakeRange(0, kLimit)];
        *recheckAt = now;
    }
    return sorted;
}

static NSArray<NSString *> *Select(SeafFPCheckSchedule *schedule, NSSet<NSString *> *candidates,
                                   NSDictionary<NSString *, NSDate *> *checkedAt, NSDate *now, NSDate **recheckAt)
{
    return [schedule containersToCheckAmong:candidates checkedAt:checkedAt now:now limit:kLimit interval:kInterval recheckAt:recheckAt];
}

/// Five missing directories listed before their parent, the parent behind them.
static void TestFailingDirectoriesGiveWay(void)
{
    NSSet<NSString *> *candidates = [NSSet setWithArray:@[@"a1", @"a2", @"a3", @"a4", @"a5", @"parent"]];
    NSMutableDictionary<NSString *, NSDate *> *checkedAt = [NSMutableDictionary dictionary];
    NSArray<NSString *> *missing = @[@"a1", @"a2", @"a3", @"a4", @"a5"];
    for (NSUInteger i = 0; i < missing.count; i++) checkedAt[missing[i]] = T(i);
    checkedAt[@"parent"] = T(10);
    NSDate *now = T(600);

    // Before: the same five every pass, and "due now" every time.
    NSDate *oldRecheck = nil;
    NSArray<NSString *> *oldFirst = OldSelection(candidates, checkedAt, now, &oldRecheck);
    NSArray<NSString *> *oldSecond = OldSelection(candidates, checkedAt, [now dateByAddingTimeInterval:1], &oldRecheck);
    CHECK([oldFirst isEqualToArray:missing] && [oldSecond isEqualToArray:missing], @"old selection %@ / %@", oldFirst, oldSecond);
    CHECK([oldRecheck isEqualToDate:[now dateByAddingTimeInterval:1]], @"old recheck %@", oldRecheck);

    SeafFPCheckSchedule *schedule = [SeafFPCheckSchedule new];
    NSDate *recheckAt = nil;
    NSArray<NSString *> *first = Select(schedule, candidates, checkedAt, now, &recheckAt);
    CHECK([first isEqualToArray:missing], @"first pass %@", first);
    CHECK([recheckAt isEqualToDate:now], @"more were due than fit: %@", recheckAt);
    for (NSString *container in first) [schedule noteFailureOfContainer:container at:now];

    // The pass that follows gets to the parent, whose listing retires the five.
    NSDate *later = [now dateByAddingTimeInterval:1];
    NSArray<NSString *> *second = Select(schedule, candidates, checkedAt, later, &recheckAt);
    CHECK([second isEqualToArray:@[@"parent"]], @"second pass %@", second);
    CHECK([recheckAt isEqualToDate:[now dateByAddingTimeInterval:SeafFPCheckBackoffBase]], @"waits for the backoff: %@", recheckAt);
    checkedAt[@"parent"] = later;
    [schedule noteSuccessOfContainer:@"parent"];

    // Nothing is due: no pass "now", the chain has ended.
    NSArray<NSString *> *third = Select(schedule, candidates, checkedAt, [later dateByAddingTimeInterval:1], &recheckAt);
    CHECK(third.count == 0, @"third pass %@", third);
    CHECK([recheckAt compare:[later dateByAddingTimeInterval:1]] == NSOrderedDescending, @"third recheck %@", recheckAt);
}

static void TestEveryDirectoryFailing(void)
{
    NSMutableSet<NSString *> *candidates = [NSMutableSet set];
    for (int i = 0; i < 12; i++) [candidates addObject:[NSString stringWithFormat:@"d%02d", i]];
    SeafFPCheckSchedule *schedule = [SeafFPCheckSchedule new];
    NSDate *now = T(0);
    NSDate *recheckAt = nil;
    NSMutableSet<NSString *> *touched = [NSMutableSet set];
    int passes = 0;
    for (; passes < 10; passes++) {
        NSArray<NSString *> *due = Select(schedule, candidates, @{}, now, &recheckAt);
        if (due.count == 0) break;
        CHECK(![touched intersectsSet:[NSSet setWithArray:due]], @"pass %d repeats %@", passes, due);
        [touched addObjectsFromArray:due];
        for (NSString *container in due) [schedule noteFailureOfContainer:container at:now];
        now = [now dateByAddingTimeInterval:1];
    }
    CHECK(passes == 3, @"12 failing directories take 3 passes, took %d", passes);
    CHECK(touched.count == 12, @"each tried once: %lu", (unsigned long)touched.count);
    CHECK([recheckAt isEqualToDate:T(SeafFPCheckBackoffBase)], @"next pass when the first backoff ends: %@", recheckAt);

    // The backoff over, they are tried again, five at a time.
    NSArray<NSString *> *again = Select(schedule, candidates, @{}, T(SeafFPCheckBackoffBase + 1), &recheckAt);
    CHECK(again.count == 5, @"after the backoff %@", again);
}

static void TestBackoffGrowsAndResets(void)
{
    SeafFPCheckSchedule *schedule = [SeafFPCheckSchedule new];
    NSDate *now = T(0);
    NSArray<NSNumber *> *expected = @[@120, @240, @480, @960, @1800, @1800];
    for (NSNumber *delay in expected) {
        NSDate *until = [schedule noteFailureOfContainer:@"d" at:now];
        CHECK(fabs([until timeIntervalSinceDate:now] - delay.doubleValue) < 0.001, @"delay %@ got %.0f", delay, [until timeIntervalSinceDate:now]);
        CHECK([schedule isContainerBackedOff:@"d" at:[until dateByAddingTimeInterval:-1]], @"backed off before %@", until);
        CHECK(![schedule isContainerBackedOff:@"d" at:until], @"free at %@", until);
        now = until;
    }
    [schedule noteSuccessOfContainer:@"d"];
    CHECK(![schedule isContainerBackedOff:@"d" at:now], @"success clears");
    NSDate *until = [schedule noteFailureOfContainer:@"d" at:now];
    CHECK(fabs([until timeIntervalSinceDate:now] - SeafFPCheckBackoffBase) < 0.001, @"starts over after a success");
    CHECK(![schedule isContainerBackedOff:@"other" at:now], @"other directories are not affected");
}

static void TestRecentListingsAndBackoffsShareTheWait(void)
{
    SeafFPCheckSchedule *schedule = [SeafFPCheckSchedule new];
    NSDate *now = T(1000);
    NSSet<NSString *> *candidates = [NSSet setWithArray:@[@"recent", @"failed", @"old", @"never"]];
    NSDictionary<NSString *, NSDate *> *checkedAt = @{@"recent": T(950), @"failed": T(100), @"old": T(200)};
    [schedule noteFailureOfContainer:@"failed" at:T(990)];   // until 1110
    NSDate *recheckAt = nil;
    NSArray<NSString *> *due = Select(schedule, candidates, checkedAt, now, &recheckAt);
    CHECK([due isEqualToArray:(@[@"never", @"old"])], @"never listed first, then oldest: %@", due);
    CHECK([recheckAt isEqualToDate:T(1070)], @"the recent listing's window ends first: %@", recheckAt);

    NSArray<NSString *> *afterWindow = Select(schedule, candidates, checkedAt, T(1071), &recheckAt);
    CHECK([afterWindow containsObject:@"recent"] && ![afterWindow containsObject:@"failed"], @"%@", afterWindow);
    CHECK([recheckAt isEqualToDate:T(1110)], @"then the backoff: %@", recheckAt);

    NSArray<NSString *> *afterBackoff = Select(schedule, candidates, checkedAt, T(1110), &recheckAt);
    CHECK([afterBackoff containsObject:@"failed"], @"%@", afterBackoff);
    CHECK(recheckAt == nil, @"nothing left alone: %@", recheckAt);
}

static void TestPassBackoff(void)
{
    SeafFPCheckSchedule *schedule = [SeafFPCheckSchedule new];
    NSDate *now = T(0);
    CHECK([schedule passBlockedUntilAt:now] == nil, @"free at first");
    NSDate *until = [schedule notePassAbortedAt:now];
    CHECK([until isEqualToDate:T(120)], @"first wait %@", until);
    CHECK([[schedule passBlockedUntilAt:T(119)] isEqualToDate:T(120)], @"blocked");
    CHECK([schedule passBlockedUntilAt:T(120)] == nil, @"free when the wait is over");
    until = [schedule notePassAbortedAt:T(120)];
    CHECK([until isEqualToDate:T(360)], @"second wait doubles: %@", until);
    [schedule noteServerAnswered];
    CHECK([schedule passBlockedUntilAt:T(121)] == nil, @"a fresh listing ends the wait");
    until = [schedule notePassAbortedAt:T(121)];
    CHECK([until isEqualToDate:T(241)], @"and the count: %@", until);
}

static void TestPruneKeepsActiveEntriesAndReset(void)
{
    SeafFPCheckSchedule *schedule = [SeafFPCheckSchedule new];
    for (int i = 0; i < 400; i++) [schedule noteFailureOfContainer:[NSString stringWithFormat:@"gone%d", i] at:T(0)];
    NSDate *muchLater = T(10 * SeafFPCheckBackoffMax);
    [schedule noteFailureOfContainer:@"live" at:muchLater];
    CHECK([schedule isContainerBackedOff:@"live" at:[muchLater dateByAddingTimeInterval:1]], @"a new failure survives the prune");
    [schedule notePassAbortedAt:muchLater];
    [schedule reset];
    CHECK(![schedule isContainerBackedOff:@"live" at:[muchLater dateByAddingTimeInterval:1]], @"reset clears directories");
    CHECK([schedule passBlockedUntilAt:[muchLater dateByAddingTimeInterval:1]] == nil, @"reset clears the pass wait");
}

int main(void)
{
    @autoreleasepool {
        TestFailingDirectoriesGiveWay();
        TestEveryDirectoryFailing();
        TestBackoffGrowsAndResets();
        TestRecentListingsAndBackoffsShareTheWait();
        TestPassBackoff();
        TestPruneKeepsActiveEntriesAndReset();
        NSLog(@"RESULT check schedule: %d checks, %d failed", gChecks, gFailures);
    }
    return gFailures == 0 ? 0 : 1;
}
