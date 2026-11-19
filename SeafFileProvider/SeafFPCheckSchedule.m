//
//  SeafFPCheckSchedule.m
//  SeafFileProvider
//

#import "SeafFPCheckSchedule.h"

const NSTimeInterval SeafFPCheckBackoffBase = 120.0;
const NSTimeInterval SeafFPCheckBackoffMax = 1800.0;

// Entries of directories that are no longer candidates (retired, or no longer
// in the working set) are never cleared by a success; they go once this many
// have piled up and they expired long ago.
static const NSUInteger kSeafFPCheckBackoffPruneCount = 256;

static NSTimeInterval SeafFPCheckBackoffDelay(NSUInteger failures)
{
    if (failures == 0) return 0;
    return MIN(SeafFPCheckBackoffMax, SeafFPCheckBackoffBase * pow(2, MIN(failures - 1, (NSUInteger)20)));
}

@interface SeafFPCheckBackoff : NSObject
@property (nonatomic, assign) NSUInteger failures;
@property (nonatomic, strong) NSDate *until;
@end

@implementation SeafFPCheckBackoff
@end

@implementation SeafFPCheckSchedule {
    NSMutableDictionary<NSString *, SeafFPCheckBackoff *> *_backoffs;
    NSUInteger _passFailures;
    NSDate *_passUntil;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _backoffs = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSArray<NSString *> *)containersToCheckAmong:(NSSet<NSString *> *)candidates
                                      checkedAt:(NSDictionary<NSString *, NSDate *> *)checkedAt
                                            now:(NSDate *)now
                                          limit:(NSUInteger)limit
                                       interval:(NSTimeInterval)interval
                                      recheckAt:(NSDate **)recheckAt
{
    NSDate *recent = [now dateByAddingTimeInterval:-interval];
    NSDate *earliest = nil;   // when the first directory left alone may be checked
    NSMutableArray<NSString *> *due = [NSMutableArray array];
    @synchronized (self) {
        for (NSString *container in candidates) {
            NSDate *wait = nil;
            NSDate *until = _backoffs[container].until;
            NSDate *at = checkedAt[container];
            if (until && [until compare:now] == NSOrderedDescending) {
                wait = until;
            } else if (at && [at compare:recent] == NSOrderedDescending) {
                wait = [at dateByAddingTimeInterval:interval];
            }
            if (!wait) {
                [due addObject:container];
            } else if (!earliest || [wait compare:earliest] == NSOrderedAscending) {
                earliest = wait;
            }
        }
    }
    NSDate *never = [NSDate distantPast];
    [due sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSComparisonResult byDate = [(checkedAt[a] ?: never) compare:(checkedAt[b] ?: never)];
        return byDate != NSOrderedSame ? byDate : [a compare:b];
    }];
    if (due.count > limit) {
        [due removeObjectsInRange:NSMakeRange(limit, due.count - limit)];
        // The ones that did not fit are due now, not in a re-check interval:
        // without a pass of their own they would wait for an unrelated signal.
        earliest = now;
    }
    if (recheckAt) *recheckAt = earliest;
    return due;
}

- (NSDate *)noteFailureOfContainer:(NSString *)container at:(NSDate *)now
{
    if (container.length == 0) return now;
    @synchronized (self) {
        if (_backoffs.count >= kSeafFPCheckBackoffPruneCount) {
            NSDate *stale = [now dateByAddingTimeInterval:-SeafFPCheckBackoffMax];
            for (NSString *key in _backoffs.allKeys) {
                if ([_backoffs[key].until compare:stale] == NSOrderedAscending) [_backoffs removeObjectForKey:key];
            }
        }
        SeafFPCheckBackoff *backoff = _backoffs[container];
        if (!backoff) {
            backoff = [SeafFPCheckBackoff new];
            _backoffs[container] = backoff;
        }
        backoff.failures += 1;
        backoff.until = [now dateByAddingTimeInterval:SeafFPCheckBackoffDelay(backoff.failures)];
        return backoff.until;
    }
}

- (void)noteSuccessOfContainer:(NSString *)container
{
    if (container.length == 0) return;
    @synchronized (self) {
        [_backoffs removeObjectForKey:container];
    }
}

- (BOOL)isContainerBackedOff:(NSString *)container at:(NSDate *)now
{
    @synchronized (self) {
        NSDate *until = _backoffs[container].until;
        return until && [until compare:now] == NSOrderedDescending;
    }
}

- (NSDate *)notePassAbortedAt:(NSDate *)now
{
    @synchronized (self) {
        _passFailures += 1;
        _passUntil = [now dateByAddingTimeInterval:SeafFPCheckBackoffDelay(_passFailures)];
        return _passUntil;
    }
}

- (void)noteServerAnswered
{
    @synchronized (self) {
        _passFailures = 0;
        _passUntil = nil;
    }
}

- (NSDate *)passBlockedUntilAt:(NSDate *)now
{
    @synchronized (self) {
        return (_passUntil && [_passUntil compare:now] == NSOrderedDescending) ? _passUntil : nil;
    }
}

- (void)reset
{
    @synchronized (self) {
        [_backoffs removeAllObjects];
        _passFailures = 0;
        _passUntil = nil;
    }
}

@end
