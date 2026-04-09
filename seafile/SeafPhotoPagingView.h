//
//  SeafPhotoPagingView.h
//  seafileApp
//
//  A self-managed horizontal paging UIScrollView replacement for
//  UIPageViewController, designed to support iOS Photos-style
//  single-gesture handoff between an inner zoomed scroll view
//  and the outer paging container.
//
//  Created by henry on 2026/4/21.
//  Copyright © 2026 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SeafPhotoPagingView;

@protocol SeafPhotoPagingViewDataSource <NSObject>
- (NSUInteger)numberOfPagesInPagingView:(SeafPhotoPagingView *)view;
/// The container view returned here will be added as a subview of the paging
/// scroll view. Implementations should be idempotent: if a container for
/// `index` is already alive, returning the existing one is recommended so
/// child VC re-attach does not trigger UIKit assertions.
- (UIView *)pagingView:(SeafPhotoPagingView *)view pageContainerForIndex:(NSUInteger)index;
- (void)pagingView:(SeafPhotoPagingView *)view recyclePageContainer:(UIView *)container atIndex:(NSUInteger)index;
@end

@protocol SeafPhotoPagingViewDelegate <NSObject>
@optional
/// Called when the user starts dragging the paging view (not fired for
/// programmatic page changes).
- (void)pagingView:(SeafPhotoPagingView *)view willBeginNavigatingFromIndex:(NSUInteger)index;
/// Settle callback emitted once the page has stopped at an integer page
/// position, regardless of whether it arrived via user gesture or via
/// `setCurrentIndex:animated:` (use `byUserGesture` to distinguish).
- (void)pagingView:(SeafPhotoPagingView *)view didSettleAtIndex:(NSUInteger)index byUserGesture:(BOOL)byUser;
/// Forwarded so the outer controller can update chrome alpha while the user
/// is mid-drag (mirrors UIPageViewController's transition coordinator).
- (void)pagingView:(SeafPhotoPagingView *)view didScrollToOffset:(CGPoint)contentOffset;
@end

/// Self-managed horizontal paging UIScrollView. Replaces UIPageViewController.
///
/// Key behavioral guarantees:
///  * `contentInsetAdjustmentBehavior` is forced to `Never` so safe-area
///    insets from a parent navigation/status bar do not push pages around.
///  * `reloadPagesIfNeeded` is idempotent — calling it from
///    `viewDidLayoutSubviews` is cheap unless bounds.size or page count
///    actually changed.
///  * Pages outside the alive range (current ± 1) are recycled via the
///    data-source callback; pages inside are kept attached.
///  * Programmatic page changes via `setCurrentIndex:animated:` queue
///    behind any in-flight handoff so a background event (file update,
///    delete) cannot interrupt the user's gesture.
@interface SeafPhotoPagingView : UIScrollView

@property (nonatomic, weak, nullable) id<SeafPhotoPagingViewDataSource> pagingDataSource;
@property (nonatomic, weak, nullable) id<SeafPhotoPagingViewDelegate>   pagingDelegate;

/// Spacing between adjacent pages, in points. Pages render at full
/// `bounds.width` and the spacing is built into the next page's origin
/// (matches UIPageViewController's `interPageSpacing` semantics).
/// Default 20pt to mirror the previous UIPageViewController setup.
@property (nonatomic, assign) CGFloat interPageSpacing;

/// Index of the page currently snapped at integer position. Updated only
/// when `scrollViewDidEndDecelerating:` / `scrollViewDidEndScrollingAnimation:`
/// fires, or when set programmatically via `setCurrentIndex:animated:`.
@property (nonatomic, assign, readonly) NSUInteger currentIndex;

/// True while the inner zoom scroll view is driving the paging contentOffset
/// directly (i.e. mid-handoff). Programmatic page changes are queued.
@property (nonatomic, assign, readonly) BOOL handoffInProgress;

/// Initial reload (typically called once from viewDidLoad / setup).
- (void)reloadPages;
/// Idempotent. Safe to call from every viewDidLayoutSubviews.
- (void)reloadPagesIfNeeded;

/// Programmatic page change. Queued behind in-flight handoff.
- (void)setCurrentIndex:(NSUInteger)index animated:(BOOL)animated;

/// Mid-gesture page jump used by the bottom thumbnail strip's "scrubber"
/// behavior (matches iOS Photos: dragging the strip swaps the big photo
/// discretely, one whole image at a time, instead of co-scrolling the
/// pager fractionally).
///
/// Snaps the pager's contentOffset to the integer position for `index`
/// without animation, updates `currentIndex` and the alive container
/// window, but DOES NOT emit `didSettleAtIndex:` — the strip drag is
/// still in progress and the gallery's settle bookkeeping must wait for
/// the drag to actually end (handled by the strip's
/// `scrollViewDidEndDecelerating:` / `scrollViewDidEndDragging:` path).
- (void)jumpToIndexForStripScrub:(NSUInteger)index;

/// Returns the alive container for `index`, or nil if not currently attached.
- (nullable UIView *)pageContainerAtIndex:(NSUInteger)index;

/// Frame of a page in the paging view's content coordinate space (regardless
/// of whether the page is currently alive).
- (CGRect)pageFrameForIndex:(NSUInteger)index;

/// Width of a single page (== bounds.width). Convenience for handoff math.
@property (nonatomic, assign, readonly) CGFloat pageWidth;

/// Recycle every alive container outside the alive ± 1 window of `currentIndex`.
/// Used by `aggressiveMemoryCleanup`.
- (void)recycleNonAdjacentPages;

#pragma mark - Handoff coordination (called by SeafZoomableScrollView)

/// Called by the inner zoom scroll view when it begins driving the paging
/// contentOffset directly. Disables our own bounce logic so the inner side
/// can manage the transition cleanly. Also serves as the gate for queueing
/// background `setCurrentIndex:animated:` calls.
- (void)beginExternalHandoffFromIndex:(NSUInteger)index;

/// Called by the inner zoom scroll view when the handoff gesture ends. If a
/// programmatic page change was queued during the handoff window, it will be
/// applied here.
- (void)endExternalHandoffWithTargetIndex:(NSUInteger)targetIndex animated:(BOOL)animated;

/// Cancel any in-flight handoff and snap back to currentIndex without animation.
/// Called by the gallery from `viewWillTransitionToSize:` (rotation) and any
/// other forced-recovery path.
- (void)cancelHandoffIfNeeded;

@end

NS_ASSUME_NONNULL_END
