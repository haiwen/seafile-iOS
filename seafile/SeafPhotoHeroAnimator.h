//
//  SeafPhotoHeroAnimator.h
//  seafileApp
//
//  Custom UIKit transition that animates the gallery's currently
//  displayed photo back to its source thumbnail in the presenter.
//  Two cooperating objects:
//    - SeafPhotoHeroAnimator implements UIViewControllerAnimatedTransitioning
//      and is used for the non-interactive dismiss path (e.g. tap close,
//      programmatic dismiss).
//    - SeafPhotoInteractiveDismiss implements UIViewControllerInteractiveTransitioning
//      and is used for the pull-down-to-dismiss gesture. It manages a
//      snapshot view itself so the picture follows the finger directly,
//      then runs a spring animation to the target frame on finish (or
//      back to the start frame on cancel).
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Snapshot of all parameters needed at the moment dismiss begins.
@interface SeafPhotoHeroContext : NSObject
/// The image to fly back. Should be the picture currently visible to the user
/// (placeholder/error image is acceptable when the real image is still loading).
@property (nonatomic, strong, nullable) UIImage *image;
/// The image's aspect-fit frame inside the gallery, in window coordinates.
@property (nonatomic, assign) CGRect startFrameInWindow;
/// The destination frame in window coordinates — typically the source cell's
/// thumbnail rect. When CGRectIsEmpty, the animator falls back to a generic
/// "shrink toward bottom + fade out" animation.
@property (nonatomic, assign) CGRect targetFrameInWindow;
/// The on-screen view that represents the destination thumbnail. Hidden
/// during the transition so the snapshot is the only visible representation;
/// restored on completion. Optional.
@property (nonatomic, weak, nullable) UIView *targetView;
/// Optional corner radius of the destination view, interpolated during the
/// flight so the snapshot lands matching the cell's rounded corners.
@property (nonatomic, assign) CGFloat targetCornerRadius;
/// Optional content mode of the destination view. Defaults to
/// UIViewContentModeScaleAspectFill (typical for thumbnail cells).
@property (nonatomic, assign) UIViewContentMode targetContentMode;
@end

#pragma mark - Non-interactive animator

/// Performs a single spring animation from the start frame to the target frame
/// and dismisses the view. Used when the user taps the close button or when
/// the gallery dismisses itself programmatically.
@interface SeafPhotoHeroAnimator : NSObject <UIViewControllerAnimatedTransitioning>

- (instancetype)initWithContext:(SeafPhotoHeroContext *)context NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark - Interactive dismiss

/// Drives the dismiss transition while the user's finger is on the screen.
/// The content view controller calls -updateWithTranslation:progress: every
/// time the pan changes, then -finishWithVelocity: (or -cancelWithVelocity:)
/// when the gesture ends.
@interface SeafPhotoInteractiveDismiss : NSObject <UIViewControllerInteractiveTransitioning>

- (instancetype)initWithContext:(SeafPhotoHeroContext *)context NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, strong, readonly) SeafPhotoHeroContext *context;

/// Snapshot view that the gesture moves around. Lives in the transition's
/// containerView once -startInteractiveTransition: has fired.
@property (nonatomic, strong, readonly, nullable) UIView *snapshotView;

/// YES once -startInteractiveTransition: has been called by UIKit.
@property (nonatomic, assign, readonly) BOOL hasStarted;

/// Block called when the snapshot view first becomes available (it is created
/// inside startInteractiveTransition:). The gallery uses this to apply any
/// translation it received between the gesture's `Began` and the runtime's
/// startInteractiveTransition: callback.
@property (nonatomic, copy, nullable) void (^onSnapshotReady)(SeafPhotoInteractiveDismiss *interactive);

/// Update the snapshot's frame. Only valid after -startInteractiveTransition:.
- (void)updateWithTranslation:(CGPoint)translation
                     progress:(CGFloat)progress;

/// Commit the dismiss: spring-animate the snapshot to the target frame,
/// then complete the transition.
- (void)finishWithVelocity:(CGPoint)velocity;

/// Cancel the dismiss: spring-animate the snapshot back to the start frame,
/// then complete the transition with !finished.
- (void)cancelWithVelocity:(CGPoint)velocity;

@end

NS_ASSUME_NONNULL_END
