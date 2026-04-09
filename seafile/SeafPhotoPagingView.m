//
//  SeafPhotoPagingView.m
//  seafileApp
//
//  Created by henry on 2026/4/21.
//  Copyright © 2026 Seafile. All rights reserved.
//

#import "SeafPhotoPagingView.h"
#import "Debug.h"

@interface SeafPhotoPagingView () <UIScrollViewDelegate>

/// Alive containers keyed by page index. Containers outside the alive
/// window are recycled back to the data source.
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIView *> *aliveContainers;

@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, assign) NSUInteger lastNumberOfPages;
@property (nonatomic, assign) CGSize     lastLaidOutSize;

/// Set while the inner zoom scroll view is driving our contentOffset
/// directly (see `beginExternalHandoffFromIndex:`). When true, our own
/// `scrollViewDidScroll:` must NOT emit settle events and must NOT update
/// `currentIndex` from the offset — the inner side is in charge.
@property (nonatomic, assign) BOOL handoffInProgress;

/// Pending programmatic page change deferred until the in-flight handoff ends.
@property (nonatomic, strong, nullable) NSNumber *pendingTargetIndex;
@property (nonatomic, assign) BOOL pendingTargetAnimated;

/// Tracks whether the next `scrollViewDidEndScrollingAnimation:` came from
/// `setCurrentIndex:animated:` (so we tag the settle as non-user).
@property (nonatomic, assign) BOOL programmaticAnimationInProgress;

@end

@implementation SeafPhotoPagingView

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _aliveContainers = [NSMutableDictionary dictionary];
        _currentIndex = 0;
        _lastNumberOfPages = 0;
        _lastLaidOutSize = CGSizeZero;
        _interPageSpacing = 20.0;
        _handoffInProgress = NO;
        _programmaticAnimationInProgress = NO;

        self.pagingEnabled = YES;
        self.bounces = YES;
        self.alwaysBounceHorizontal = YES;
        self.alwaysBounceVertical = NO;
        self.showsHorizontalScrollIndicator = NO;
        self.showsVerticalScrollIndicator = NO;
        self.decelerationRate = UIScrollViewDecelerationRateFast;
        self.directionalLockEnabled = YES;
        self.scrollsToTop = NO;
        self.delegate = self;

        // Patch G: the paging view fills self.view of a controller wrapped
        // in a UINavigationController. If we let UIKit auto-adjust insets,
        // the nav-bar / status-bar safe area gets stacked on top of our
        // contentSize math, pushing pages down and breaking page width.
        // Force-disable to keep contentSize == pageCount * pageWidth.
        if (@available(iOS 11.0, *)) {
            self.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        }
    }
    return self;
}

#pragma mark - Public

- (CGFloat)pageWidth {
    return self.bounds.size.width;
}

- (CGRect)pageFrameForIndex:(NSUInteger)index {
    CGFloat w = self.pageWidth;
    CGFloat h = self.bounds.size.height;
    // Each page occupies pageWidth on the x-axis. The visual gap between
    // photos is rendered by inset-ing the container content (we shrink
    // the page rect by interPageSpacing on the right edge), matching
    // UIPageViewController's interPageSpacing semantics.
    CGFloat halfSpacing = self.interPageSpacing / 2.0;
    CGRect frame = CGRectMake((CGFloat)index * w + halfSpacing,
                              0,
                              MAX(0, w - self.interPageSpacing),
                              h);
    return frame;
}

- (UIView *)pageContainerAtIndex:(NSUInteger)index {
    return self.aliveContainers[@(index)];
}

- (void)reloadPages {
    self.lastLaidOutSize = CGSizeZero;
    self.lastNumberOfPages = NSNotFound;
    [self reloadPagesIfNeeded];
}

- (void)reloadPagesIfNeeded {
    NSUInteger total = [self.pagingDataSource numberOfPagesInPagingView:self];
    if (CGSizeEqualToSize(self.lastLaidOutSize, self.bounds.size)
     && self.lastNumberOfPages == total) {
        // Patch H: zero-cost early-out. viewDidLayoutSubviews fires for
        // status bar / nav bar alpha changes / keyboard etc., and a
        // non-idempotent reload here would interrupt mid-handoff state
        // and double-fire didBecomeCurrentVisiblePage on the current page.
        return;
    }

    self.lastLaidOutSize   = self.bounds.size;
    self.lastNumberOfPages = total;

    CGFloat w = self.pageWidth;
    self.contentSize = CGSizeMake(w * (CGFloat)total, self.bounds.size.height);

    // Reflow alive containers to their (possibly new) frames; do NOT detach.
    for (NSNumber *key in self.aliveContainers.allKeys) {
        NSUInteger idx = key.unsignedIntegerValue;
        if (idx >= total) {
            // Page count shrank past this index — recycle.
            [self recyclePageAtIndex:idx];
            continue;
        }
        UIView *container = self.aliveContainers[key];
        container.frame = [self pageFrameForIndex:idx];
    }

    [self updateAliveWindowAroundIndex:self.currentIndex];
}

- (void)setCurrentIndex:(NSUInteger)index animated:(BOOL)animated {
    if (self.handoffInProgress) {
        // Patch §3.11.6: queue behind the in-flight handoff. The most recent
        // request wins (e.g. multiple background updates collapse into one).
        self.pendingTargetIndex = @(index);
        self.pendingTargetAnimated = animated;
        return;
    }

    NSUInteger total = [self.pagingDataSource numberOfPagesInPagingView:self];
    if (total == 0) return;
    if (index >= total) index = total - 1;

    // If we're being asked to settle to a page we already think we're on,
    // still snap the contentOffset (e.g. rotation may have left a fractional
    // offset behind even though currentIndex is unchanged).
    CGPoint targetOffset = CGPointMake((CGFloat)index * self.pageWidth, 0);

    if (animated) {
        self.programmaticAnimationInProgress = YES;
        [self setContentOffset:targetOffset animated:YES];
    } else {
        // Suppress our own scrollViewDidScroll → currentIndex side effects
        // by doing the offset write inside a flag window; we set
        // currentIndex explicitly afterwards.
        self.programmaticAnimationInProgress = NO;
        [self setContentOffset:targetOffset animated:NO];
        if (self.currentIndex != index) {
            NSUInteger old = self.currentIndex;
            self.currentIndex = index;
            [self updateAliveWindowAroundIndex:index];
            if (old != index
                && [self.pagingDelegate respondsToSelector:@selector(pagingView:didSettleAtIndex:byUserGesture:)]) {
                [self.pagingDelegate pagingView:self didSettleAtIndex:index byUserGesture:NO];
            }
        } else {
            // currentIndex didn't actually change but we may have just
            // attached the alive window for the first time (initial setup).
            [self updateAliveWindowAroundIndex:index];
        }
    }
}

- (void)jumpToIndexForStripScrub:(NSUInteger)index {
    if (!self.pagingDataSource) return;
    NSUInteger total = [self.pagingDataSource numberOfPagesInPagingView:self];
    if (total == 0) return;
    if (index >= total) index = total - 1;

    CGFloat pw = self.pageWidth;
    if (pw <= 0) return;

    CGPoint targetOffset = CGPointMake((CGFloat)index * pw, 0);

    // Bypass our own setContentOffset:animated: side-effect path entirely.
    // Going through `super` still triggers `scrollViewDidScroll:` (UIKit
    // dispatches it for any setter), which our delegate implementation
    // handles below — but we explicitly do NOT want
    // `didEndScrollingAnimation:` / `didEndDecelerating:` to fire here
    // (no animation is in flight, no deceleration is happening), so the
    // settle path stays dormant until the strip drag actually ends.
    self.programmaticAnimationInProgress = NO;
    [super setContentOffset:targetOffset animated:NO];

    if (self.currentIndex != index) {
        self.currentIndex = index;
        [self updateAliveWindowAroundIndex:index];
    } else {
        [self updateAliveWindowAroundIndex:index];
    }
}

- (void)recycleNonAdjacentPages {
    NSInteger current = (NSInteger)self.currentIndex;
    NSArray<NSNumber *> *keys = [self.aliveContainers.allKeys copy];
    for (NSNumber *k in keys) {
        NSInteger idx = (NSInteger)k.unsignedIntegerValue;
        if (labs(idx - current) > 1) {
            [self recyclePageAtIndex:(NSUInteger)idx];
        }
    }
}

#pragma mark - Handoff coordination

- (void)beginExternalHandoffFromIndex:(NSUInteger)index {
    self.handoffInProgress = YES;
}

- (void)endExternalHandoffWithTargetIndex:(NSUInteger)targetIndex animated:(BOOL)animated {
    self.handoffInProgress = NO;

    // The target may equal currentIndex (cancelled handoff) — still snap
    // back to integer position in case the inner side left a fractional
    // contentOffset behind.
    NSNumber *pending = self.pendingTargetIndex;
    BOOL pendingAnimated = self.pendingTargetAnimated;
    self.pendingTargetIndex = nil;
    self.pendingTargetAnimated = NO;

    [self setCurrentIndex:targetIndex animated:animated];

    if (pending && pending.unsignedIntegerValue != targetIndex) {
        // Apply the queued background change after the handoff settles.
        // We schedule on the next runloop hop so the in-flight settle
        // animation has a chance to dispatch its delegate callbacks first.
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf setCurrentIndex:pending.unsignedIntegerValue animated:pendingAnimated];
        });
    }
}

- (void)cancelHandoffIfNeeded {
    if (!self.handoffInProgress) return;
    self.handoffInProgress = NO;
    self.pendingTargetIndex = nil;
    self.pendingTargetAnimated = NO;
    // Snap to current index without animation; do not emit a settle event
    // because we never left the current page from the controller's POV.
    CGPoint snap = CGPointMake((CGFloat)self.currentIndex * self.pageWidth, 0);
    [super setContentOffset:snap animated:NO];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    // We deliberately do NOT call reloadPagesIfNeeded here — the gallery
    // owns the cadence (it knows when it's safe vs not, e.g. mid-rotation).
}

#pragma mark - Alive window management

- (void)updateAliveWindowAroundIndex:(NSUInteger)index {
    if (!self.pagingDataSource) return;
    NSUInteger total = [self.pagingDataSource numberOfPagesInPagingView:self];
    if (total == 0) {
        // Recycle everything still attached.
        NSArray<NSNumber *> *keys = [self.aliveContainers.allKeys copy];
        for (NSNumber *k in keys) {
            [self recyclePageAtIndex:k.unsignedIntegerValue];
        }
        return;
    }

    NSInteger lo = (NSInteger)index - 1;
    NSInteger hi = (NSInteger)index + 1;
    if (lo < 0) lo = 0;
    if (hi >= (NSInteger)total) hi = (NSInteger)total - 1;

    // Recycle any alive container outside the [lo..hi] window.
    NSArray<NSNumber *> *keys = [self.aliveContainers.allKeys copy];
    for (NSNumber *k in keys) {
        NSInteger idx = (NSInteger)k.unsignedIntegerValue;
        if (idx < lo || idx > hi) {
            [self recyclePageAtIndex:(NSUInteger)idx];
        }
    }

    // Attach any missing container inside the window.
    BOOL didAttachNewContainer = NO;
    for (NSInteger i = lo; i <= hi; i++) {
        NSNumber *key = @((NSUInteger)i);
        if (self.aliveContainers[key]) {
            // Already alive — keep frame in sync (cheap if unchanged).
            self.aliveContainers[key].frame = [self pageFrameForIndex:(NSUInteger)i];
            continue;
        }
        UIView *container = [self.pagingDataSource pagingView:self pageContainerForIndex:(NSUInteger)i];
        if (!container) continue;
        container.frame = [self pageFrameForIndex:(NSUInteger)i];
        [self addSubview:container];
        self.aliveContainers[key] = container;
        didAttachNewContainer = YES;
    }

    // Warm up Auto Layout on freshly-attached neighbor pages so their
    // viewDidLayoutSubviews fires NOW, not on the first frame the user
    // drags them into the viewport. Without this the next page's image
    // view + scroll-view layout pass piles onto the same midpan frame
    // as the contentOffset write, producing a visible hitch right when
    // the next photo first appears under the finger.
    if (didAttachNewContainer) {
        for (NSInteger i = lo; i <= hi; i++) {
            UIView *c = self.aliveContainers[@((NSUInteger)i)];
            // Skip the page that's already current — it's been laid out
            // long ago. Only warm the genuine neighbors.
            if (!c || (NSUInteger)i == self.currentIndex) continue;
            [c layoutIfNeeded];
        }
    }
}

- (void)recyclePageAtIndex:(NSUInteger)index {
    NSNumber *key = @(index);
    UIView *container = self.aliveContainers[key];
    if (!container) return;
    [self.aliveContainers removeObjectForKey:key];
    [container removeFromSuperview];
    if ([self.pagingDataSource respondsToSelector:@selector(pagingView:recyclePageContainer:atIndex:)]) {
        [self.pagingDataSource pagingView:self recyclePageContainer:container atIndex:index];
    }
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    // While the inner zoom view is driving contentOffset directly we still
    // get this callback (UIKit dispatches it for any setter). Suppress the
    // alive-window update to avoid attaching/recycling mid-handoff —
    // the inner side will deliver a single end-of-handoff settle.
    if (self.handoffInProgress) {
        if ([self.pagingDelegate respondsToSelector:@selector(pagingView:didScrollToOffset:)]) {
            [self.pagingDelegate pagingView:self didScrollToOffset:self.contentOffset];
        }
        return;
    }

    // Keep alive window in step with whatever page is closest to view.
    if (self.pageWidth > 0) {
        NSUInteger nearest = (NSUInteger)round(self.contentOffset.x / self.pageWidth);
        NSUInteger total = [self.pagingDataSource numberOfPagesInPagingView:self];
        if (total > 0 && nearest >= total) nearest = total - 1;
        // Update the alive window when the visually-dominant page changes,
        // but do NOT change `currentIndex` — that only updates on settle.
        if (nearest != self.currentIndex) {
            [self updateAliveWindowAroundIndex:nearest];
        }
    }

    if ([self.pagingDelegate respondsToSelector:@selector(pagingView:didScrollToOffset:)]) {
        [self.pagingDelegate pagingView:self didScrollToOffset:self.contentOffset];
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if ([self.pagingDelegate respondsToSelector:@selector(pagingView:willBeginNavigatingFromIndex:)]) {
        [self.pagingDelegate pagingView:self willBeginNavigatingFromIndex:self.currentIndex];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (self.handoffInProgress) return;       // inner side will close out
    [self emitSettleByUserGesture:YES];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    BOOL byUser = !self.programmaticAnimationInProgress;
    self.programmaticAnimationInProgress = NO;
    if (self.handoffInProgress) return;
    [self emitSettleByUserGesture:byUser];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (decelerate) return;                    // settle will fire from didEndDecelerating
    if (self.handoffInProgress) return;
    [self emitSettleByUserGesture:YES];
}

- (void)emitSettleByUserGesture:(BOOL)byUser {
    if (self.pageWidth <= 0) return;
    NSUInteger nearest = (NSUInteger)round(self.contentOffset.x / self.pageWidth);
    NSUInteger total = [self.pagingDataSource numberOfPagesInPagingView:self];
    if (total == 0) return;
    if (nearest >= total) nearest = total - 1;

    if (nearest == self.currentIndex) {
        // Re-confirm the alive window in case rotations / size changes
        // caused the visually-dominant page to drift.
        [self updateAliveWindowAroundIndex:nearest];
        return;
    }
    self.currentIndex = nearest;
    [self updateAliveWindowAroundIndex:nearest];
    if ([self.pagingDelegate respondsToSelector:@selector(pagingView:didSettleAtIndex:byUserGesture:)]) {
        [self.pagingDelegate pagingView:self didSettleAtIndex:nearest byUserGesture:byUser];
    }
}

#pragma mark - Accessibility (Patch L)

- (BOOL)isAccessibilityElement { return NO; }

- (BOOL)accessibilityScroll:(UIAccessibilityScrollDirection)direction {
    NSUInteger total = [self.pagingDataSource numberOfPagesInPagingView:self];
    if (total == 0) return NO;
    NSUInteger target = self.currentIndex;
    if (direction == UIAccessibilityScrollDirectionRight && target > 0) {
        target--;
    } else if (direction == UIAccessibilityScrollDirectionLeft && target + 1 < total) {
        target++;
    } else {
        return NO;
    }
    [self setCurrentIndex:target animated:YES];
    return YES;
}

@end
