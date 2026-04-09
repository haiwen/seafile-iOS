//
//  SeafPhotoContentViewController.h
//  seafileApp
//
//  Created by henry on 2025/4/17.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafPhotoInfoView.h"
#import "SeafConnection.h"
#import "SeafErrorPlaceholderView.h"

@class SeafFile;
@class SeafLivePhotoPlayerView;
@class SeafPhotoContentViewController;
@protocol SeafPreView;

// Define a protocol for content view controller events
@protocol SeafPhotoContentDelegate <NSObject>
@required
- (void)photoContentViewControllerRequestsRetryForFile:(id<SeafPreView>)file atIndex:(NSUInteger)index;

@optional
/// Called when the user begins a pinch-to-zoom gesture
- (void)photoContentViewControllerDidBeginZooming:(SeafPhotoContentViewController *)viewController;
/// Called when the zoom gesture ends. isAtMinZoom=YES means the image has returned to its initial size.
- (void)photoContentViewControllerDidEndZooming:(SeafPhotoContentViewController *)viewController
                                     isAtMinZoom:(BOOL)isAtMinZoom;
/// Called when the zoom gesture ends. Same as above, but additionally carries
/// `restoreChrome` — NO means the user was already in immersive (chrome hidden)
/// before they started zooming in, so the gallery should keep chrome hidden
/// even after the image returns to its initial size; YES means restore chrome
/// to the visible state. When this method is implemented, it is preferred over
/// the legacy `…isAtMinZoom:` callback.
- (void)photoContentViewControllerDidEndZooming:(SeafPhotoContentViewController *)viewController
                                     isAtMinZoom:(BOOL)isAtMinZoom
                                   restoreChrome:(BOOL)restoreChrome;
/// Called when the zoom scale first exceeds minimum, entering zoomed-in viewing state.
/// Unlike DidBeginZooming (which fires at gesture start), this fires only when the scale
/// actually crosses the threshold — avoiding false triggers from bounce-zoom-out.
- (void)photoContentViewControllerDidEnterZoomedState:(SeafPhotoContentViewController *)viewController;
/// Called when the user taps to toggle immersive viewing mode (chrome
/// hidden + black background). The gallery should update its own paging
/// view background and any cached adjacent pages to match.
///
/// NOTE: Prefer the newer `photoContentViewControllerDidRequestToggleChrome:`
/// callback. The gallery owns the authoritative chrome-hidden state and is
/// responsible for nav bar / status bar / thumbnails / toolbar; this older
/// "didToggle" callback is kept only for legacy delegates that mutate the
/// nav bar themselves.
- (void)photoContentViewController:(SeafPhotoContentViewController *)viewController
                didToggleImmersive:(BOOL)immersive;

/// Called when the user taps the photo and the gallery should toggle its
/// chrome (top nav bar + bottom toolbar + thumbnail strip + status bar).
/// The gallery is the single source of truth for chrome visibility — when
/// this method is implemented it is preferred over the legacy
/// `…didToggleImmersive:` callback, and the content VC will NOT touch the
/// parent navigation bar itself.
- (void)photoContentViewControllerDidRequestToggleChrome:(SeafPhotoContentViewController *)viewController;

/// Asked by the content VC when it needs to know the gallery's current
/// chrome-hidden state (for example, the LIVE badge / live-photo icon should
/// only be visible when the chrome is visible). Defaults to NO when the
/// delegate doesn't implement this.
- (BOOL)photoContentViewControllerIsChromeHidden:(SeafPhotoContentViewController *)viewController;

/// Called when the user begins dragging down to dismiss. The gallery is
/// expected to capture the photo's start frame, ask its hero provider for
/// the source thumbnail's target frame, hide the on-screen image (so only
/// the snapshot remains visible) and kick off an interactive dismiss.
- (void)photoContentViewControllerDidBeginDismissDrag:(SeafPhotoContentViewController *)viewController;
/// Called during dismiss drag with the live translation, normalized progress
/// (0~1) and current pan velocity. The gallery forwards these to its
/// interactive dismiss controller so the snapshot follows the finger.
- (void)photoContentViewController:(SeafPhotoContentViewController *)viewController
                  dismissDragMoved:(CGPoint)translation
                          progress:(CGFloat)progress
                          velocity:(CGPoint)velocity;
/// Called when dismiss drag completes (should commit the dismiss). Velocity
/// is the pan's release velocity, used to seed the spring animation.
- (void)photoContentViewController:(SeafPhotoContentViewController *)viewController
        didCompleteDismissDragWithVelocity:(CGPoint)velocity;
/// Called when dismiss drag is cancelled (should restore the gallery state).
- (void)photoContentViewController:(SeafPhotoContentViewController *)viewController
          didCancelDismissDragWithVelocity:(CGPoint)velocity;
@end

NS_ASSUME_NONNULL_BEGIN

@interface SeafPhotoContentViewController : UIViewController <UIScrollViewDelegate, UIGestureRecognizerDelegate>
/// The internal zoom/pan scroll view — exposed for gesture dependency setup.
@property (nonatomic, strong, readonly) UIScrollView *scrollView;
/// The photo URL to display
@property (nonatomic, strong) NSURL *photoURL;

/// The page index this VC represents in the gallery. Defaults to NSNotFound
/// for fresh allocations; the gallery sets it before adding the VC into the
/// paging view. Replaces the previous `view.tag`-based identity convention.
@property (nonatomic, assign) NSUInteger pageIndex;

/// Delegate to handle retry requests
@property (nonatomic, weak, nullable) id<SeafPhotoContentDelegate> delegate;

/// The connection to use for API requests
@property (nonatomic, strong) SeafConnection *connection;

/// The info dictionary for this photo
@property (nonatomic, strong) NSDictionary *infoModel;

/// Whether the info view is visible
@property (nonatomic, assign) BOOL infoVisible;

/// Loading indicator view
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;

/// Progress label view
@property (nonatomic, strong) UILabel *progressLabel;

/// Tracks if the info view has been dragged beyond top edge
@property (nonatomic, assign) BOOL draggedBeyondTopEdge;

/// New SeafFile-based image loading
@property (nonatomic, strong) id<SeafPreView> seafFile;

/// Metadata
@property (nonatomic, strong) NSString *repoId;
@property (nonatomic, strong) NSString *filePath;

/// View options and status
@property (nonatomic, assign) BOOL fullscreenMode;
@property (nonatomic, readonly) BOOL isZooming;

/// Flag to suppress zoom delegate callbacks during programmatic layout resets
@property (nonatomic, assign) BOOL isConfiguringLayout;

/// Whether the image is currently zoomed in (zoomScale > minimumZoomScale)
@property (nonatomic, readonly) BOOL isZoomedIn;

/// Whether the view is displaying a placeholder or error image
@property (nonatomic, assign) BOOL isDisplayingPlaceholderOrErrorImage;

/// Error placeholder view components
@property (nonatomic, strong, nullable) SeafErrorPlaceholderView *errorPlaceholderView;

/// Live Photo / Motion Photo player view
@property (nonatomic, strong, nullable) SeafLivePhotoPlayerView *livePhotoPlayerView;

/// Whether the current content is a Motion Photo
@property (nonatomic, assign, readonly) BOOL isMotionPhoto;

/// Method to toggle the info view
- (void)toggleInfoView:(BOOL)show animated:(BOOL)animated;

/// Shows the loading indicator and resets progress.
- (void)showLoadingIndicator;

/// Hides the loading indicator.
- (void)hideLoadingIndicator;

/// Updates the progress label.
- (void)updateLoadingProgress:(float)progress;

/// Sets an error image to display when loading fails
- (void)showErrorImage;

/// Prepare the view controller for reuse, clearing state and cached data
- (void)prepareForReuse;

/// Info section related methods
- (void)updateInfoView;

- (void)loadImage;

/// Cancels any ongoing image loading or download requests.
- (void)cancelImageLoading;

/// Releases memory used by loaded images when the controller is not in the view.
- (void)releaseImageMemory;

/// Configures the imageView frame and zoom scales based on the given image's size
/// and the current scrollView bounds. This is the core layout method.
- (void)configureForImage:(nullable UIImage *)image;

#pragma mark - Gallery Visibility Notifications

/// Called by the gallery container when this view controller becomes the
/// currently visible page. If the page hosts a Motion/Live Photo, a brief
/// silent auto-preview is started — mirroring iOS Photos' behavior.
/// If the underlying live photo data has not arrived yet, the request is
/// queued and replayed once `setupLivePhotoPlayerViewWithData:` finishes.
- (void)didBecomeCurrentVisiblePage;

/// Called by the gallery container when this view controller is no longer the
/// currently visible page. Stops any silent auto-preview in progress.
- (void)didResignCurrentVisiblePage;

#pragma mark - Hero Transition Support

/// The image currently displayed inside the scroll view. May be nil if loading
/// has not produced any image yet (in which case the hero animator falls back
/// to a frame-only flight without a picture).
- (nullable UIImage *)currentDisplayedImage;

/// Frame of the on-screen image inside the supplied view's coordinate space.
/// Pass nil to get window coordinates.
/// When no image has been displayed yet, returns the scroll view's frame
/// (a reasonable approximation of where the photo would have been).
- (CGRect)displayedImageFrameInView:(nullable UIView *)view;

/// While interactive dismiss is running we hide the underlying scroll view
/// so the hero snapshot is the only visible representation of the photo.
- (void)setUnderlyingPhotoHidden:(BOOL)hidden;

#pragma mark - Immersive Appearance (driven by gallery)

/// Switch this page's own appearance (background colors, scroll indicators,
/// LIVE badge) into the "immersive" look. Called by the gallery whenever its
/// chrome is hidden — both pinch-to-zoom and tap-to-toggle paths funnel
/// through here so the page-local state stays in sync with the gallery.
- (void)enterImmersiveAppearanceAnimated:(BOOL)animated;

/// Counterpart to `enterImmersiveAppearanceAnimated:` — restore the normal
/// (light backgrounds, hidden scroll indicators, LIVE badge if applicable)
/// appearance. Called by the gallery whenever its chrome becomes visible.
- (void)exitImmersiveAppearanceAnimated:(BOOL)animated;
@end

NS_ASSUME_NONNULL_END
