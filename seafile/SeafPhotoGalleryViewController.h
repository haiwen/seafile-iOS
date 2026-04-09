//
//  SeafPhotoGalleryViewController.h
//  seafileApp
//
//  Created by henry on 2025/4/17.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafFile.h"
#import "SeafPGThumbnailCellViewModel.h"
#import "SeafPhotoContentViewController.h"
#import "SeafGalleryHeroProvider.h"
#import "SeafPhotoPagingView.h"

@interface SeafPhotoGalleryViewController : UIViewController <SeafDentryDelegate, SeafPhotoContentDelegate, UIViewControllerTransitioningDelegate>

// Initialization method using SeafFile object
- (instancetype)initWithPhotos:(NSArray<id<SeafPreView>> *)files
                   currentItem:(id<SeafPreView>)currentItem
                        master:(UIViewController<SeafDentryDelegate> *)masterVC;

/// Optional Hero source provider. When set, the modal dismiss transition
/// (both interactive pull-down and programmatic close) animates the photo
/// back to the source thumbnail returned by the provider. Set this BEFORE
/// presenting the gallery; the navigation controller wrapper is configured
/// for the custom transition by `+heroNavigationControllerWith…` below.
@property (nonatomic, weak, nullable) id<SeafGalleryHeroProvider> heroProvider;

/// Convenience factory: builds a UINavigationController wrapper around a new
/// gallery and configures both for the custom Hero dismiss transition.
/// Callers should subsequently `[presenter presentViewController:result animated:YES …]`.
+ (UINavigationController *)heroNavigationControllerWithPhotos:(NSArray<id<SeafPreView>> *)files
                                                   currentItem:(id<SeafPreView>)currentItem
                                                        master:(UIViewController<SeafDentryDelegate> *)masterVC
                                                  heroProvider:(nullable id<SeafGalleryHeroProvider>)heroProvider;

// Track the range of loaded images
@property (nonatomic, readonly) NSRange loadedImagesRange;

// Expose UI Components as readonly properties
@property (nonatomic, strong, readonly, nullable) UICollectionView *thumbnailCollection;
@property (nonatomic, strong, readonly, nullable) UIView *toolbarView;
@property (nonatomic, strong, readonly, nullable) UIView *leftThumbnailOverlay;
@property (nonatomic, strong, readonly, nullable) UIView *rightThumbnailOverlay;

// Expose internal state for specific use cases
@property (nonatomic, strong, readonly, nullable) NSArray<SeafPhotoContentViewController *> *photoViewControllers;
@property (nonatomic, readonly) NSUInteger currentIndex;

#pragma mark - Chrome (nav bar / toolbar / status bar) — single source of truth

/// Why the chrome state is being changed. The setter uses this to choose
/// between full structural hide (toggles `setNavigationBarHidden:`) and a
/// pure alpha fade — pinch-to-zoom must NOT trigger a layout reflow on the
/// nav bar mid-gesture, so the zoom paths use alpha-only.
typedef NS_ENUM(NSInteger, SeafChromeReason) {
    SeafChromeReasonTap,         // user single-tap toggle
    SeafChromeReasonZoomIn,      // pinch zoom crossed into zoomed-in state
    SeafChromeReasonZoomOut,     // pinch zoom returned to min — restore from zoom-driven hide
    SeafChromeReasonPageSettle,  // sync new page to existing chrome state
    SeafChromeReasonRestore,     // viewWillDisappear / explicit reset
};

/// YES when the gallery's chrome (top nav bar + bottom toolbar + thumbnail
/// strip + status bar) is currently hidden. This is the single authoritative
/// flag — read it instead of inferring from `navigationBar.alpha < 0.01` or
/// `navigationBarHidden`, which can disagree across the tap and zoom paths.
@property (nonatomic, assign, readonly) BOOL isChromeHidden;

/// Centralized chrome show/hide. Replaces ad-hoc `setNavigationBarHidden:` /
/// `navigationBar.alpha = 0` / `thumbnailCollection.hidden = YES` writes
/// scattered across the gallery and content VCs. Always call this method
/// rather than touching the nav bar directly.
- (void)setChromeHidden:(BOOL)hidden
               animated:(BOOL)animated
                 reason:(SeafChromeReason)reason;

@end

@interface SeafPhotoGalleryViewController () <SeafPhotoPagingViewDataSource,
                                             SeafPhotoPagingViewDelegate,
                                             UICollectionViewDataSource,
                                             UICollectionViewDelegate,
                                             UICollectionViewDelegateFlowLayout,
                                             UIScrollViewDelegate,
                                             SeafDentryDelegate,
                                             SeafPhotoContentDelegate,
                                             UIViewControllerTransitioningDelegate>

@property (nonatomic, strong) SeafPhotoPagingView      *pagingView;
@property (nonatomic, assign) BOOL isDragging;
@end
