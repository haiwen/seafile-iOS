//
//  SeafPhotoHeroAnimator.m
//  seafileApp
//

#import "SeafPhotoHeroAnimator.h"

#pragma mark - Context

@implementation SeafPhotoHeroContext

- (instancetype)init {
    if ((self = [super init])) {
        _startFrameInWindow = CGRectZero;
        _targetFrameInWindow = CGRectZero;
        _targetCornerRadius = 0;
        _targetContentMode = UIViewContentModeScaleAspectFill;
    }
    return self;
}

@end

#pragma mark - Helpers

/// Build a snapshot wrapper containing a UIImageView at the given start frame.
/// The wrapper clips to bounds so corner-radius and content-mode interpolation
/// produces a smooth crop transition matching iOS Photos.
static UIView *SeafPhotoHero_BuildSnapshot(SeafPhotoHeroContext *ctx) {
    UIView *wrapper = [[UIView alloc] initWithFrame:ctx.startFrameInWindow];
    wrapper.backgroundColor = [UIColor clearColor];
    wrapper.clipsToBounds = YES;
    wrapper.layer.cornerRadius = 0;

    UIImageView *imageView = [[UIImageView alloc] initWithFrame:wrapper.bounds];
    imageView.image = ctx.image;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [wrapper addSubview:imageView];
    return wrapper;
}

/// Resolve the destination rect for the given context, applying the bottom-
/// fallback when no source thumbnail is available.
static CGRect SeafPhotoHero_ResolveTargetFrame(SeafPhotoHeroContext *ctx, UIView *containerView, BOOL *outHasTarget) {
    CGRect targetFrame = ctx.targetFrameInWindow;
    BOOL hasTarget = !CGRectIsEmpty(targetFrame);
    if (!hasTarget) {
        CGRect screen = containerView.bounds;
        CGFloat fallbackSide = MIN(screen.size.width, screen.size.height) * 0.25;
        targetFrame = CGRectMake((screen.size.width - fallbackSide) / 2.0,
                                  screen.size.height - fallbackSide - 40,
                                  fallbackSide,
                                  fallbackSide);
    }
    if (outHasTarget) *outHasTarget = hasTarget;
    return targetFrame;
}

#pragma mark - Non-interactive Animator

@interface SeafPhotoHeroAnimator ()
@property (nonatomic, strong) SeafPhotoHeroContext *context;
@end

@implementation SeafPhotoHeroAnimator

- (instancetype)initWithContext:(SeafPhotoHeroContext *)context {
    if ((self = [super init])) {
        _context = context;
    }
    return self;
}

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext {
    return 0.32;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    UIView *containerView = [transitionContext containerView];
    UIViewController *fromVC = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIView *fromView = fromVC.view;

    if (fromView && fromView.superview != containerView) {
        [containerView insertSubview:fromView atIndex:0];
    }

    UIView *snapshot = SeafPhotoHero_BuildSnapshot(self.context);
    [containerView addSubview:snapshot];

    UIView *targetView = self.context.targetView;
    BOOL targetWasHidden = targetView.hidden;
    targetView.hidden = YES;

    BOOL hasTarget = NO;
    CGRect targetFrame = SeafPhotoHero_ResolveTargetFrame(self.context, containerView, &hasTarget);

    NSTimeInterval duration = [self transitionDuration:transitionContext];
    [UIView animateWithDuration:duration
                          delay:0
         usingSpringWithDamping:0.9
          initialSpringVelocity:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        snapshot.frame = targetFrame;
        snapshot.layer.cornerRadius = self.context.targetCornerRadius;
        for (UIView *sub in snapshot.subviews) {
            if ([sub isKindOfClass:[UIImageView class]]) {
                ((UIImageView *)sub).contentMode = self.context.targetContentMode;
            }
        }
        if (!hasTarget) {
            snapshot.alpha = 0;
        }
        fromView.alpha = 0;
    } completion:^(BOOL finished) {
        targetView.hidden = targetWasHidden;
        [snapshot removeFromSuperview];
        // Restore fromView alpha so reused VC instances aren't permanently
        // transparent if UIKit keeps them around.
        fromView.alpha = 1;
        BOOL cancelled = [transitionContext transitionWasCancelled];
        [transitionContext completeTransition:!cancelled];
    }];
}

@end

#pragma mark - Interactive Dismiss

@interface SeafPhotoInteractiveDismiss ()
@property (nonatomic, strong, readwrite) SeafPhotoHeroContext *context;
@property (nonatomic, strong, readwrite, nullable) UIView *snapshotView;
@property (nonatomic, weak, nullable) id<UIViewControllerContextTransitioning> transitionContext;
@property (nonatomic, weak, nullable) UIView *fromView;
@property (nonatomic, assign) BOOL targetWasHidden;
@property (nonatomic, assign, readwrite) BOOL hasStarted;
@property (nonatomic, assign) BOOL hasFinished;
@property (nonatomic, assign) CGFloat lastProgress;
@end

@implementation SeafPhotoInteractiveDismiss

- (instancetype)initWithContext:(SeafPhotoHeroContext *)context {
    if ((self = [super init])) {
        _context = context;
        _lastProgress = 0;
    }
    return self;
}

- (void)startInteractiveTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    self.transitionContext = transitionContext;

    UIView *containerView = [transitionContext containerView];
    UIViewController *fromVC = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIView *fromView = fromVC.view;
    self.fromView = fromView;

    if (fromView && fromView.superview != containerView) {
        [containerView insertSubview:fromView atIndex:0];
    }

    UIView *snapshot = SeafPhotoHero_BuildSnapshot(self.context);
    [containerView addSubview:snapshot];
    self.snapshotView = snapshot;

    UIView *targetView = self.context.targetView;
    self.targetWasHidden = targetView.hidden;
    targetView.hidden = YES;

    self.hasStarted = YES;

    if (self.onSnapshotReady) {
        void (^cb)(SeafPhotoInteractiveDismiss *) = self.onSnapshotReady;
        self.onSnapshotReady = nil;
        cb(self);
    }
}

- (CGFloat)completionSpeed {
    return 1.0;
}

- (UIViewAnimationCurve)completionCurve {
    return UIViewAnimationCurveEaseOut;
}

- (BOOL)wantsInteractiveStart {
    return YES;
}

- (void)updateWithTranslation:(CGPoint)translation progress:(CGFloat)progress {
    if (!self.snapshotView) return;

    CGFloat clampedProgress = MAX(0.0, MIN(1.0, progress));
    self.lastProgress = clampedProgress;

    CGFloat scale = MAX(0.4, 1.0 - clampedProgress * 0.4);

    CGRect start = self.context.startFrameInWindow;
    CGFloat newWidth = start.size.width * scale;
    CGFloat newHeight = start.size.height * scale;
    CGFloat centerX = CGRectGetMidX(start) + translation.x;
    CGFloat centerY = CGRectGetMidY(start) + translation.y;
    self.snapshotView.frame = CGRectMake(centerX - newWidth / 2.0,
                                          centerY - newHeight / 2.0,
                                          newWidth,
                                          newHeight);

    // Fade the gallery background tied to drag progress so the underlying
    // presenter view becomes visible smoothly.
    self.fromView.alpha = MAX(0.0, 1.0 - clampedProgress);
}

- (void)finishWithVelocity:(CGPoint)velocity {
    if (self.hasFinished) return;
    self.hasFinished = YES;

    UIView *snapshot = self.snapshotView;
    UIView *containerView = [self.transitionContext containerView];
    BOOL hasTarget = NO;
    CGRect targetFrame = SeafPhotoHero_ResolveTargetFrame(self.context, containerView, &hasTarget);

    NSTimeInterval duration = 0.32;
    CGFloat springVelocity = 0;
    if (snapshot && hasTarget) {
        CGFloat distance = MAX(40.0, fabs(targetFrame.origin.y - snapshot.frame.origin.y));
        springVelocity = MIN(6.0, MAX(0.0, fabs(velocity.y) / distance));
    }

    UIView *fromView = self.fromView;
    UIView *targetView = self.context.targetView;
    BOOL targetWasHidden = self.targetWasHidden;
    SeafPhotoHeroContext *ctx = self.context;
    id<UIViewControllerContextTransitioning> transitionContext = self.transitionContext;

    [UIView animateWithDuration:duration
                          delay:0
         usingSpringWithDamping:0.86
          initialSpringVelocity:springVelocity
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        snapshot.frame = targetFrame;
        snapshot.layer.cornerRadius = ctx.targetCornerRadius;
        for (UIView *sub in snapshot.subviews) {
            if ([sub isKindOfClass:[UIImageView class]]) {
                ((UIImageView *)sub).contentMode = ctx.targetContentMode;
            }
        }
        if (!hasTarget) {
            snapshot.alpha = 0;
        }
        fromView.alpha = 0;
    } completion:^(BOOL finished) {
        targetView.hidden = targetWasHidden;
        [snapshot removeFromSuperview];
        fromView.alpha = 1;
        [transitionContext finishInteractiveTransition];
        [transitionContext completeTransition:YES];
    }];
}

- (void)cancelWithVelocity:(CGPoint)velocity {
    if (self.hasFinished) return;
    self.hasFinished = YES;

    UIView *snapshot = self.snapshotView;
    UIView *fromView = self.fromView;
    UIView *targetView = self.context.targetView;
    BOOL targetWasHidden = self.targetWasHidden;
    SeafPhotoHeroContext *ctx = self.context;
    id<UIViewControllerContextTransitioning> transitionContext = self.transitionContext;

    NSTimeInterval duration = 0.28;
    [UIView animateWithDuration:duration
                          delay:0
         usingSpringWithDamping:0.85
          initialSpringVelocity:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        snapshot.frame = ctx.startFrameInWindow;
        snapshot.layer.cornerRadius = 0;
        snapshot.alpha = 1;
        fromView.alpha = 1;
    } completion:^(BOOL finished) {
        targetView.hidden = targetWasHidden;
        [snapshot removeFromSuperview];
        [transitionContext cancelInteractiveTransition];
        [transitionContext completeTransition:NO];
    }];
}

@end
