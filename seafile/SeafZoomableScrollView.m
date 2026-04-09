#import "SeafZoomableScrollView.h"
#import "SeafPhotoPagingView.h"
#import "Debug.h"

/// Fraction of `pageWidth` past which the projected pan endpoint commits
/// to the next/previous page. Mirrors UIPageViewController's ~33% feel.
static const CGFloat kSeafHandoffCommitThresholdRatio = 0.35;

/// Look-ahead in seconds applied to the pan's release velocity to decide
/// whether the user "flicked" past the commit threshold even if their
/// raw translation hasn't crossed it yet. 0.10s matches `UIScrollView`
/// fast deceleration feel.
static const NSTimeInterval kSeafHandoffVelocityProjection = 0.10;

/// Minimum overshoot in points for the inner scroll view to be
/// considered "bouncing past the edge" within the current gesture.
/// Used purely as a detector — once the flag is set we promote the
/// gesture to primed on release; we never enter handoff in the same
/// gesture that first bounced.
static const CGFloat kSeafEdgeBounceDetectionPx = 1.0;

@interface SeafZoomableScrollView ()

/// Mid-pan handoff state. Lives only between `Began` and `Ended/Cancelled`.
@property (nonatomic, assign) BOOL handoffActive;

/// `+1` if handoff started at the right edge (user is panning left toward
/// the next page), `-1` if started at the left edge (user is panning right
/// toward the previous page), `0` when no handoff is in progress.
@property (nonatomic, assign) NSInteger handoffEdge;

/// Raw `translationInView:` of the pan recognizer at the moment we
/// transitioned into handoff. We compute the outer offset delta as
/// `currentTranslation.x - handoffPanStartTranslationX` so the inner pan
/// can move freely *before* the handoff starts without polluting the math.
@property (nonatomic, assign) CGFloat handoffPanStartTranslationX;

/// Outer paging view's `contentOffset.x` captured at the moment handoff
/// began. The inner side then drives the outer offset relative to this.
@property (nonatomic, assign) CGFloat handoffOuterBaseOffsetX;

/// Page index the gallery was settled on when handoff began. Used to
/// resolve the commit target (current / current ± 1) on release.
@property (nonatomic, assign) NSUInteger handoffStartIndex;

/// `contentOffset.y` snapshot taken at the moment handoff began. While
/// the outer paging view is following the pan we pin the inner Y back
/// to this value every frame so the photo cannot drift up/down during
/// the page transition (matches iOS Photos: vertical motion is locked
/// the moment the page-turn handoff takes over).
@property (nonatomic, assign) CGFloat handoffPinY;

/// Cross-gesture flag. Set on the End of a pan that rubber-banded
/// against `primedEdge` without entering handoff. The NEXT pan against
/// the same edge is allowed to enter handoff immediately. Cleared on
/// zoom-out, on handoff completion, and when the inner scroll view is
/// reset (`prepareForReuse` calls `setZoomScale:1.0`, which we override
/// to clear primed too).
@property (nonatomic, assign) BOOL primedForEdgeHandoff;

/// `-1` for left edge, `+1` for right edge, `0` when not primed.
@property (nonatomic, assign) NSInteger primedEdge;

/// Per-handoff flag: YES when the current handoff was entered without a
/// matching primed flag (i.e. the user's FIRST push against the edge in
/// this round). In peek-only mode the outer paging view still follows
/// the finger so the next photo slides into view, but on release the
/// page is forced to snap back regardless of distance/velocity. Promoting
/// the primed flag at the end then unlocks the SECOND gesture to commit
/// normally.
@property (nonatomic, assign) BOOL handoffPeekOnly;

/// `bounces` value captured at the moment handoff began. While handoff
/// is in flight we force `bounces = NO` so UIScrollView's own rubber-band
/// physics don't fight our per-frame edge clamp. Restored on handoff end.
@property (nonatomic, assign) BOOL handoffSavedBounces;

@end

@implementation SeafZoomableScrollView

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Match iOS Photos: shorter inertia distance/time when panning a
        // zoomed image.
        self.decelerationRate = UIScrollViewDecelerationRateFast;

        // Observe our own pan to drive the single-gesture handoff into the
        // enclosing paging view (commit 3 / paging_safeguards J). Adding an
        // extra target does NOT disturb UIScrollView's own pan handling.
        [self.panGestureRecognizer addTarget:self
                                      action:@selector(handlePanForHandoff:)];
    }
    return self;
}

- (void)setZoomScale:(CGFloat)zoomScale animated:(BOOL)animated {
    [super setZoomScale:zoomScale animated:animated];
    // Zooming back to natural size invalidates any primed handoff state
    // captured at a previous zoom level — both for double-tap reset and
    // for `prepareForReuse` (which sets zoomScale = 1.0). Without this,
    // a primed flag on photo A could leak into the very first pan on
    // photo B and skip the required first-bounce.
    if (zoomScale <= self.minimumZoomScale + 0.01) {
        self.primedForEdgeHandoff = NO;
        self.primedEdge           = 0;
    }
}

#pragma mark - Helpers

- (nullable SeafPhotoPagingView *)enclosingPagingView {
    UIView *v = self.superview;
    while (v) {
        if ([v isKindOfClass:[SeafPhotoPagingView class]]) {
            return (SeafPhotoPagingView *)v;
        }
        v = v.superview;
    }
    return nil;
}

/// Returns the inset that UIScrollView actually applies to its scrollable
/// range. On iOS 11+ this includes safe-area / system additions; on older
/// systems we fall back to the raw `contentInset`. Centering is implemented
/// via `contentInset` (see `SeafPhotoContentViewController centerImageInScrollView`),
/// so any edge math that ignores this value will compute the wrong edges
/// for content smaller than `bounds` on the relevant axis.
- (UIEdgeInsets)effectiveContentInset {
    if (@available(iOS 11.0, *)) {
        return self.adjustedContentInset;
    }
    return self.contentInset;
}

- (BOOL)isAtLeftHorizontalEdge {
    UIEdgeInsets inset = [self effectiveContentInset];
    CGFloat minOffsetX = -inset.left;
    CGFloat maxOffsetX = self.contentSize.width + inset.right - self.bounds.size.width;
    // When the content is not horizontally scrollable (e.g. a portrait image
    // shown in landscape, where `contentSize.width <= bounds.size.width`),
    // there is no edge to push past — the inner view cannot absorb a
    // horizontal pan in either direction. Refuse to count this as "at the
    // edge", otherwise a centered photo's negative `contentOffset.x` (a
    // consequence of `contentInset.left > 0`) would satisfy a naive
    // `contentOffset.x <= 0.5` check and trip the handoff state machine.
    // That used to yank the photo to the left during a two-finger pinch
    // because `updateHandoffWithTranslation:` clamps `bounds.origin.x = 0`
    // and thereby zeroes `contentOffset.x` — visually a snap to the left
    // edge of the screen.
    if (maxOffsetX <= minOffsetX) return NO;
    return self.contentOffset.x <= minOffsetX + 0.5;
}

- (BOOL)isAtRightHorizontalEdge {
    UIEdgeInsets inset = [self effectiveContentInset];
    CGFloat minOffsetX = -inset.left;
    CGFloat maxOffsetX = self.contentSize.width + inset.right - self.bounds.size.width;
    if (maxOffsetX <= minOffsetX) return NO;
    return self.contentOffset.x >= maxOffsetX - 0.5;
}

- (BOOL)isZoomedIn {
    return self.zoomScale > self.minimumZoomScale + 0.01;
}

#pragma mark - Gesture coordination

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    // Pre-commit-3 we used to reject the inner pan up front when it was
    // headed off the edge, forcing the user to lift their finger and swipe
    // again so the parent UIPageViewController's pan could engage. With the
    // new handoff state machine we always allow the inner pan to start —
    // the handoff is performed live in `handlePanForHandoff:` without ever
    // ending or restarting the pan recognizer.
    return [super gestureRecognizerShouldBegin:gestureRecognizer];
}

#pragma mark - Handoff state machine

- (void)handlePanForHandoff:(UIPanGestureRecognizer *)pan {
    if (pan != self.panGestureRecognizer) return;

    SeafPhotoPagingView *paging = [self enclosingPagingView];
    if (!paging) {
        if (self.handoffActive) {
            self.handoffActive = NO;
            self.handoffEdge   = 0;
        }
        return;
    }

    // Handoff is meaningless at the natural zoom — the outer paging view
    // owns navigation directly and its own pan recognizer fires.
    if (![self isZoomedIn]) {
        if (self.handoffActive) {
            [self abortHandoffSnapToCurrent:paging];
        }
        // Drop any primed flag carried over from a previous zoomed-in
        // gesture so re-zooming doesn't grant a free handoff.
        self.primedForEdgeHandoff = NO;
        self.primedEdge           = 0;
        return;
    }

    switch (pan.state) {
        case UIGestureRecognizerStateBegan: {
            // Reset transient state at the start of every gesture.
            self.handoffActive   = NO;
            self.handoffEdge     = 0;
            self.handoffPeekOnly = NO;
            break;
        }

        case UIGestureRecognizerStateChanged: {
            CGPoint translation = [pan translationInView:self];
            CGPoint velocity    = [pan velocityInView:self];

            if (!self.handoffActive) {
                [self maybeBeginHandoffWithTranslation:translation
                                              velocity:velocity
                                                paging:paging];
            }

            if (self.handoffActive) {
                [self updateHandoffWithTranslation:translation paging:paging];
            }
            break;
        }

        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            if (!self.handoffActive) return;
            [self finishHandoffWithPan:pan paging:paging cancelled:(pan.state != UIGestureRecognizerStateEnded)];
            break;
        }

        default:
            break;
    }
}

- (void)maybeBeginHandoffWithTranslation:(CGPoint)translation
                                velocity:(CGPoint)velocity
                                  paging:(SeafPhotoPagingView *)paging {
    // Need a horizontally dominant pan; otherwise the user is panning the
    // zoomed image vertically (e.g. exploring a tall photo).
    BOOL horizontalDominant = fabs(velocity.x) > fabs(velocity.y);
    if (!horizontalDominant) return;

    BOOL panRight = translation.x > 0; // finger moving right
    BOOL panLeft  = translation.x < 0; // finger moving left
    if (!panRight && !panLeft) return;

    BOOL atLeft  = [self isAtLeftHorizontalEdge];
    BOOL atRight = [self isAtRightHorizontalEdge];

    // Only commit when the inner content can no longer absorb the pan in
    // the gesture's direction (i.e. we're at the edge being pushed against).
    NSInteger candidateEdge = (atLeft && panRight)  ? -1
                            : (atRight && panLeft)  ? +1
                            : 0;
    if (candidateEdge == 0) return;

    // Measure rubber-band overshoot relative to the inset-adjusted edges,
    // not relative to 0 / contentSize.width - bounds.width. The two are only
    // equivalent when contentInset.{left,right} == 0; when the photo is
    // centered via contentInset (the path used by SeafPhotoContentViewController),
    // the natural left edge is at contentOffset.x = -inset.left.
    UIEdgeInsets inset = [self effectiveContentInset];
    CGFloat overshoot = 0.0;
    if (candidateEdge < 0) {
        overshoot = MAX(0.0, -inset.left - self.contentOffset.x);
    } else {
        CGFloat maxOffsetX = self.contentSize.width + inset.right - self.bounds.size.width;
        overshoot = MAX(0.0, self.contentOffset.x - maxOffsetX);
    }

    // We always enter handoff once the inner scroll view actually starts
    // to rubber-band — that is what makes the next photo "peek" into
    // view as the user pushes past the edge. The peekOnly flag below
    // decides whether that gesture is *allowed to commit* the page turn
    // (primed = second push) or must always snap back (un-primed = first
    // push), giving the user the strict two-stage behavior they want
    // while still rendering the next photo behind the finger.
    if (overshoot < kSeafEdgeBounceDetectionPx) return;

    BOOL primedMatch = self.primedForEdgeHandoff
                    && self.primedEdge == candidateEdge;

    self.handoffActive               = YES;
    self.handoffEdge                 = candidateEdge;
    self.handoffPeekOnly             = !primedMatch;
    self.handoffPanStartTranslationX = translation.x;
    self.handoffOuterBaseOffsetX     = paging.contentOffset.x;
    self.handoffStartIndex           = paging.currentIndex;
    // Capture the inner Y position at handoff start so we can pin it for
    // the duration of the page transition (problem 4: lock vertical drift
    // while the outer paging view follows the same pan).
    self.handoffPinY                 = self.contentOffset.y;

    // Suppress UIScrollView's own rubber-band so it stops fighting our
    // per-frame clamp in `updateHandoffWithTranslation:`. Without this,
    // the inner bounces back ~1px past the edge each frame and our pin
    // writes a counter-offset, multiplying delegate dispatches per pan
    // event. Restored to its prior value on handoff end / abort.
    self.handoffSavedBounces = self.bounces;
    self.bounces             = NO;

    [paging beginExternalHandoffFromIndex:paging.currentIndex];
}

- (void)updateHandoffWithTranslation:(CGPoint)translation
                              paging:(SeafPhotoPagingView *)paging {
    CGFloat dx        = translation.x - self.handoffPanStartTranslationX;
    CGFloat newOuterX = self.handoffOuterBaseOffsetX - dx;

    CGFloat maxOuterX = paging.contentSize.width - paging.bounds.size.width;
    if (maxOuterX < 0) maxOuterX = 0;
    if (newOuterX < 0)         newOuterX = 0;
    if (newOuterX > maxOuterX) newOuterX = maxOuterX;

    paging.contentOffset = CGPointMake(newOuterX, 0);

    // Pin our own contentOffset at the originating edge so the inner image
    // does not rubber-band away from the user's finger while the outer
    // paging view is following the same translation. Y is pinned to the
    // snapshot taken at handoff start so the photo cannot drift vertically
    // during the page transition (matches iOS Photos vertical lock).
    //
    // Note: with `bounces = NO` (set in `maybeBeginHandoffWithTranslation:`),
    // UIScrollView itself stops trying to rubber-band the offset past the
    // edge, so the clamp below is mostly a defensive no-op. We still write
    // bounds.origin directly (instead of `setContentOffset:animated:`) when
    // a drift slips through, to avoid the extra `scrollViewDidScroll:`
    // dispatch chain that fires on every contentOffset setter call.
    // Clamp to the inset-adjusted edge of the content, not to 0 /
    // contentSize.width - bounds.width. When the inner content is centered
    // via contentInset, contentOffset.x at the left edge is -inset.left
    // (negative), so clamping to 0 here would yank the photo sideways.
    UIEdgeInsets inset = [self effectiveContentInset];
    CGFloat minOffsetX = -inset.left;
    CGFloat maxOffsetX = self.contentSize.width + inset.right - self.bounds.size.width;
    CGFloat clampX = (self.handoffEdge > 0)
        ? MAX(minOffsetX, maxOffsetX)
        : minOffsetX;
    CGFloat clampY = self.handoffPinY;
    CGRect b = self.bounds;
    if (fabs(b.origin.x - clampX) > 0.01
     || fabs(b.origin.y - clampY) > 0.01) {
        b.origin = CGPointMake(clampX, clampY);
        self.bounds = b;
    }
}

- (void)finishHandoffWithPan:(UIPanGestureRecognizer *)pan
                      paging:(SeafPhotoPagingView *)paging
                   cancelled:(BOOL)cancelled {
    CGPoint translation = [pan translationInView:self];
    CGPoint velocity    = [pan velocityInView:self];

    CGFloat pageW = paging.pageWidth;
    NSUInteger total = (pageW > 0)
        ? (NSUInteger)round(paging.contentSize.width / pageW)
        : 0;
    NSUInteger startIdx  = self.handoffStartIndex;
    NSInteger  edgeAtStart = self.handoffEdge;
    BOOL       peekOnly  = self.handoffPeekOnly;
    NSUInteger target    = startIdx;

    if (peekOnly) {
        // Strict two-stage: the user's first push is only allowed to
        // peek the next photo into view. Force snap back regardless of
        // how far / how fast they pulled, then promote primed so the
        // NEXT gesture against the same edge can commit normally.
        target = startIdx;
    } else if (!cancelled && pageW > 0 && total > 0) {
        CGFloat dx          = translation.x - self.handoffPanStartTranslationX;
        CGFloat predictedDx = dx + velocity.x * kSeafHandoffVelocityProjection;
        CGFloat threshold   = pageW * kSeafHandoffCommitThresholdRatio;

        if (predictedDx <= -threshold && startIdx + 1 < total) {
            target = startIdx + 1;
        } else if (predictedDx >= threshold && startIdx > 0) {
            target = startIdx - 1;
        } else {
            target = startIdx;
        }
    }

    self.handoffActive   = NO;
    self.handoffEdge     = 0;
    self.handoffPeekOnly = NO;
    // Restore the original bounces flag we suppressed at handoff start
    // (defensive: if the handoff was never entered we still want the
    // value to be untouched).
    self.bounces         = self.handoffSavedBounces;

    if (peekOnly) {
        // Promote: next gesture against the same edge enters non-peek
        // handoff and is allowed to commit the page turn.
        self.primedForEdgeHandoff = YES;
        self.primedEdge           = edgeAtStart;
    } else {
        // Either the primed gesture committed/aborted normally — either
        // way the user has "spent" the primed state and a fresh bounce
        // is required again next time.
        self.primedForEdgeHandoff = NO;
        self.primedEdge           = 0;
    }

    [paging endExternalHandoffWithTargetIndex:target animated:YES];
}

- (void)abortHandoffSnapToCurrent:(SeafPhotoPagingView *)paging {
    NSUInteger target      = self.handoffStartIndex;
    NSInteger  edgeAtStart = self.handoffEdge;
    BOOL       peekOnly    = self.handoffPeekOnly;

    self.handoffActive   = NO;
    self.handoffEdge     = 0;
    self.handoffPeekOnly = NO;
    self.bounces         = self.handoffSavedBounces;

    if (peekOnly) {
        // Even if the peek was aborted (e.g. zoom-out interrupted it),
        // promote primed so the user's intent ("I pushed against this
        // edge once") still counts toward the second-gesture rule. If
        // zoom-out was the cause, the `![self isZoomedIn]` branch in
        // `handlePanForHandoff:` will clear it on the next pan event.
        self.primedForEdgeHandoff = YES;
        self.primedEdge           = edgeAtStart;
    } else {
        self.primedForEdgeHandoff = NO;
        self.primedEdge           = 0;
    }

    [paging endExternalHandoffWithTargetIndex:target animated:YES];
}

@end
