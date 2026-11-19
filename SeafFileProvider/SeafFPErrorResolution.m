//
//  SeafFPErrorResolution.m
//  SeafFileProvider
//

#import "SeafFPErrorResolution.h"

const NSTimeInterval SeafFPResolutionBackoffBase = 120.0;
const NSTimeInterval SeafFPResolutionBackoffMax = 1800.0;

// An error that comes back later than this after its last resolution is a new
// incident. Longer than the longest wait plus the time a retried upload takes,
// or the count would start over while the same item is still failing.
static const NSTimeInterval kSeafFPResolutionIncidentWindow = 2 * 1800.0;

static NSTimeInterval SeafFPResolutionDelay(NSUInteger recurrences)
{
    if (recurrences == 0) return 0;
    return MIN(SeafFPResolutionBackoffMax, SeafFPResolutionBackoffBase * pow(2, MIN(recurrences - 1, (NSUInteger)20)));
}

@interface SeafFPErrorResolutionEntry : NSObject
@property (nonatomic, assign) BOOL pending;              // answered to the system, not resolved yet
@property (nonatomic, assign) BOOL resolvedSinceError;   // resolved after the last time it was noted
@property (nonatomic, assign) NSUInteger recurrences;    // times it came back for one item after a resolution
@property (nonatomic, strong, nullable) NSDate *resolvedAt;
@property (nonatomic, strong, nullable) NSDate *notBefore;
@end

@implementation SeafFPErrorResolutionEntry
@end

@implementation SeafFPErrorResolution {
    NSMutableDictionary<NSNumber *, SeafFPErrorResolutionEntry *> *_entries;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _entries = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)noteErrorWithCode:(NSInteger)code aboutOneItem:(BOOL)aboutOneItem at:(NSDate *)now
{
    @synchronized (self) {
        SeafFPErrorResolutionEntry *entry = _entries[@(code)];
        if (!entry) {
            entry = [SeafFPErrorResolutionEntry new];
            _entries[@(code)] = entry;
        }
        if (!aboutOneItem) {
            // The next fresh answer from the server is the evidence. A wait
            // left by a refused item must not keep the location flagged after
            // the network is back; the item's own next failure resumes it.
            entry.notBefore = nil;
        } else if (entry.resolvedSinceError) {
            // Resolved, retried by the system, and refused again.
            BOOL sameIncident = entry.resolvedAt
                && [now timeIntervalSinceDate:entry.resolvedAt] <= kSeafFPResolutionIncidentWindow;
            entry.recurrences = sameIncident ? entry.recurrences + 1 : 0;
            entry.notBefore = entry.recurrences > 0
                ? [now dateByAddingTimeInterval:SeafFPResolutionDelay(entry.recurrences)] : nil;
        }
        // else: noted again without a resolution in between (the system's own
        // retry, or a second item): the wait already set stands.
        entry.pending = YES;
        entry.resolvedSinceError = NO;
    }
}

- (NSArray<NSNumber *> *)codesToResolveAt:(NSDate *)now
{
    NSMutableArray<NSNumber *> *codes = [NSMutableArray array];
    @synchronized (self) {
        for (NSNumber *code in [_entries.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            SeafFPErrorResolutionEntry *entry = _entries[code];
            if (!entry.pending) continue;
            if (entry.notBefore && [entry.notBefore compare:now] == NSOrderedDescending) continue;
            entry.pending = NO;
            entry.resolvedSinceError = YES;
            entry.resolvedAt = now;
            entry.notBefore = nil;
            [codes addObject:code];
        }
    }
    return codes;
}

- (NSDate *)resolutionOfCode:(NSInteger)code heldUntilAt:(NSDate *)now
{
    @synchronized (self) {
        SeafFPErrorResolutionEntry *entry = _entries[@(code)];
        if (!entry.pending || !entry.notBefore) return nil;
        return [entry.notBefore compare:now] == NSOrderedDescending ? entry.notBefore : nil;
    }
}

- (void)forgetWaits
{
    @synchronized (self) {
        for (SeafFPErrorResolutionEntry *entry in _entries.allValues) {
            entry.recurrences = 0;
            entry.notBefore = nil;
            entry.resolvedSinceError = NO;
        }
    }
}

@end
