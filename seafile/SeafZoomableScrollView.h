#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// `UIScrollView` subclass used to host a single zoomable photo. When the
/// content is zoomed in and the pan reaches a horizontal edge, this class
/// transparently hands the *same* gesture off to the enclosing
/// `SeafPhotoPagingView` so the user can flick to the next/previous photo
/// without lifting their finger — matching the iOS Photos experience.
///
/// The handoff is performed by:
///   1. Observing our own `panGestureRecognizer` via an additional target.
///   2. Detecting the moment the inner content sits at an edge and the pan
///      continues toward that edge.
///   3. Calling `beginExternalHandoffFromIndex:` on the enclosing paging view
///      and then directly driving its `contentOffset` from the pan's
///      translation, while pinning our own `contentOffset` at the edge.
///   4. On gesture end, deciding the target page (current ± 0/1) using the
///      pan's projected end position and calling
///      `endExternalHandoffWithTargetIndex:animated:`.
@interface SeafZoomableScrollView : UIScrollView

/// True while this view is actively driving the enclosing paging view's
/// contentOffset from a single in-flight pan. Exposed mainly for tests /
/// debugging.
@property (nonatomic, assign, readonly) BOOL handoffActive;

@end

NS_ASSUME_NONNULL_END
