//
//  SeafPhotoContentViewController.m
//  seafileApp
//
//  Created by henry on 2025/4/17.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import "SeafPhotoContentViewController.h"
#import "SeafPhotoGalleryViewController.h"
#import "SeafZoomableScrollView.h"
#import <ImageIO/ImageIO.h>
#import "FileSizeFormatter.h"
#import "Debug.h"
#import "ExtentedString.h"
#import "SeafConnection.h"
#import <SDWebImage/UIImageView+WebCache.h>
#import "SeafFile.h"
#import "SeafStorage.h"
#import "SeafPreview.h"
#import "SeafPhotoInfoView.h"
#import "SeafUploadFile.h"
#import "SeafErrorPlaceholderView.h"
#import "SeafLivePhotoPlayerView.h"
#import "SeafMotionPhotoExtractor.h"

@interface SeafPhotoContentViewController ()<UIScrollViewDelegate, SeafLivePhotoPlayerViewDelegate>
@property (nonatomic, strong, readwrite) UIScrollView  *scrollView;
@property (nonatomic, strong) UIImageView   *imageView;
@property (nonatomic, strong) SeafPhotoInfoView *infoView;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGesture;
@property (nonatomic, strong) UIImageView *errorIconImageView;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, assign, readwrite) BOOL isMotionPhoto;
@property (nonatomic, assign, readwrite) BOOL isZooming;
// Edge tracking removed: SeafZoomableScrollView now drives the
// single-gesture handoff into the outer paging view directly, so the
// content VC no longer has to surface edge events to the gallery.
@property (nonatomic, assign) BOOL wasInZoomedState; // Tracks zoom threshold crossing for immersive mode
@property (nonatomic, assign) BOOL wasImmersiveBeforeZoom; // Snapshot of chrome state captured right before a zoom-in begins
@property (nonatomic, strong) UIPanGestureRecognizer *dismissPanGesture; // Pull-down-to-dismiss gesture

/// Live Photo badge displayed in top-left corner (below navigation bar)
/// Contains icon + "LIVE" text, similar to iOS native style
@property (nonatomic, strong) UIView *livePhotoBadge;

/// YES while this VC is the gallery's currently visible page.
@property (nonatomic, assign) BOOL isCurrentVisiblePage;

/// YES if `didBecomeCurrentVisiblePage` was called before the live photo
/// player view was set up. The auto-preview will be triggered later, once
/// `setupLivePhotoPlayerViewWithData:` finishes initializing the player.
@property (nonatomic, assign) BOOL pendingAutoPreview;

/// Previous hidden state of `livePhotoBadge` captured when the underlying
/// scroll view is hidden during an interactive Hero dismiss, so it can be
/// restored verbatim if the gesture cancels.
@property (nonatomic, assign) BOOL savedLivePhotoBadgeHidden;

// Forward declaration so call sites above the implementation don't trigger
// -Wundeclared-selector. This is the SOLE entry point for re-centering the
// image — every caller must supply a `reason` tag (used in [ZoomBug] logs).
- (void)centerImageInScrollViewForReason:(NSString *)reason;

@end

@implementation SeafPhotoContentViewController

// Custom getter for repoId
- (NSString *)repoId {
    if (self.seafFile && [self.seafFile isKindOfClass:[SeafFile class]]) {
        return ((SeafFile *)self.seafFile).repoId;
    }
    return nil;
}

- (NSString *)filePath {
    if (self.seafFile && [self.seafFile isKindOfClass:[SeafFile class]]) {
        return ((SeafFile *)self.seafFile).path;
    }
    return nil;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Patch §3.11.4: pageIndex defaults to NSNotFound — never to 0.
        // A 0 default would cause the first real index-0 page to look like
        // an unset placeholder for any nil-safe lookup. Gallery sets the
        // real index before adding the VC into the paging view.
        _pageIndex = NSNotFound;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _pageIndex = NSNotFound;
    }
    return self;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _pageIndex = NSNotFound;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:249/255.0 green:249/255.0 blue:249/255.0 alpha:1.0]; // #F9F9F9
    [self setupScrollView];
    [self setupInfoView];
    [self setupLoadingIndicator];
    [self setupLivePhotoIcon];
    // [self loadImage]; // loadImage will be called by viewWillAppear or explicitly after file is set
    
    // Initialize with info view hidden
    self.infoVisible = NO;
    self.infoView.hidden = YES;
    
    // Initialize placeholder image flag
    self.isDisplayingPlaceholderOrErrorImage = NO;
}

- (void)setupScrollView {
    // Create a scroll view that fills the entire view
    self.scrollView = [[SeafZoomableScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.scrollView.delegate = self;
    self.scrollView.backgroundColor = [UIColor colorWithRed:249/255.0 green:249/255.0 blue:249/255.0 alpha:1.0]; // #F9F9F9
    // Initial zoom scales — will be updated by configureForImage: when image loads
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 1.0;
    // Hide scroll indicators (matches iOS system Photos behavior)
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.bouncesZoom = YES; // Rubber-band effect at min/max zoom
    // Disable automatic content inset adjustment — we manage contentInset ourselves
    // via centerImageInScrollView for precise Aspect Fit centering. Leaving this as
    // 'automatic' causes UIKit to add safeAreaInsets on top of our centering inset,
    // which leads to inconsistent image positioning on page transitions.
    if (@available(iOS 11.0, *)) {
        self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    [self.view addSubview:self.scrollView];

    // Create an image view — frame will be set precisely by configureForImage:
    self.imageView = [[UIImageView alloc] initWithFrame:self.scrollView.bounds];
    self.imageView.contentMode = UIViewContentModeScaleToFill; // Frame is precisely calculated, no need for AspectFit
    // No autoresizingMask — imageView frame is managed by configureForImage:
    [self.scrollView addSubview:self.imageView];
    
    // Add tap gesture for toggling UI visibility
    self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self.scrollView addGestureRecognizer:self.tapGesture];
    
    // Add double tap gesture for zooming
    self.doubleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    self.doubleTapGesture.numberOfTapsRequired = 2;
    [self.scrollView addGestureRecognizer:self.doubleTapGesture];
    
    // Ensure single tap gesture doesn't interfere with double tap
    [self.tapGesture requireGestureRecognizerToFail:self.doubleTapGesture];
    
    // Add pull-down-to-dismiss gesture (iOS Photos style).
    // Restrict to single-finger pans only — pinch-to-zoom is always a two-finger
    // gesture, and we want hardware-level separation from it. Without this,
    // the natural slight downward drift of two-finger pinch-out (especially
    // when zoom rubber-bands below `minimumZoomScale` and `isZoomedIn` returns
    // NO so the soft gate in `gestureRecognizerShouldBegin:` no longer
    // disqualifies the pan) was being mis-recognized as a dismiss-drag,
    // hiding the underlying scroll view (`setUnderlyingPhotoHidden:YES`)
    // mid-pinch and leaving the user staring at the Hero snapshot until
    // release.
    self.dismissPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissPan:)];
    self.dismissPanGesture.delegate = self;
    self.dismissPanGesture.minimumNumberOfTouches = 1;
    self.dismissPanGesture.maximumNumberOfTouches = 1;
    [self.scrollView addGestureRecognizer:self.dismissPanGesture];
}

- (void)setupInfoView {
    // Create the info view that will display metadata
    CGFloat infoHeight = roundf(self.view.bounds.size.height * 0.6); // 3/5 of screen height
    
    // Position initially off-screen at the bottom
    CGRect infoFrame = CGRectMake(0,
                                  self.view.bounds.size.height,
                                  self.view.bounds.size.width,
                                  infoHeight);
    
    // Create info view with a slightly translucent background
    self.infoView = [[SeafPhotoInfoView alloc] initWithFrame:infoFrame];
    
    // Add autoresizing mask to maintain width and position relative to bottom
    self.infoView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    
    // Add to view hierarchy as a top-level view (above scroll view)
    [self.view addSubview:self.infoView];
    
    // Set the delegate for the internal scroll view
    self.infoView.infoScrollView.delegate = self;
    
    // Initially hidden
    self.infoView.hidden = YES;
}

- (void)setupLivePhotoIcon {
    CGFloat badgeHeight = 20.0;
    CGFloat leftPadding = 3.0;
    CGFloat rightPadding = 8.0;
    CGFloat iconSize = 16.0;
    CGFloat spacing = 2.0;
    CGFloat estimatedTextWidth = 24.0;
    CGFloat badgeWidth = leftPadding + iconSize + spacing + estimatedTextWidth + rightPadding;
    
    self.livePhotoBadge = [[UIView alloc] initWithFrame:CGRectMake(0, 0, badgeWidth, badgeHeight)];
    self.livePhotoBadge.backgroundColor = [UIColor clearColor];
    self.livePhotoBadge.layer.masksToBounds = NO;
    
    // Background: #F2F2F9 75%, border: #C7C7C7 75%
    UIView *contentView = [[UIView alloc] initWithFrame:self.livePhotoBadge.bounds];
    contentView.backgroundColor = [[UIColor colorWithRed:242/255.0 green:242/255.0 blue:249/255.0 alpha:1.0] colorWithAlphaComponent:0.75];
    contentView.layer.cornerRadius = badgeHeight / 2.0;
    contentView.layer.masksToBounds = YES;
    contentView.layer.borderWidth = 0.5;
    contentView.layer.borderColor = [UIColor colorWithRed:199/255.0 green:199/255.0 blue:199/255.0 alpha:0.75].CGColor;
    contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    contentView.tag = 100;
    [self.livePhotoBadge addSubview:contentView];
    
    // Icon: #1C1C1C 60%
    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(leftPadding, (badgeHeight - iconSize) / 2.0, iconSize, iconSize)];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:iconSize weight:UIImageSymbolWeightRegular];
        UIImage *livePhotoSymbol = [UIImage systemImageNamed:@"livephoto" withConfiguration:config];
        iconView.image = livePhotoSymbol;
        iconView.tintColor = [UIColor colorWithRed:28/255.0 green:28/255.0 blue:28/255.0 alpha:0.6];
    }
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.tag = 101;
    [contentView addSubview:iconView];
    
    // Text: #1C1C1C 60%
    UILabel *liveLabel = [[UILabel alloc] init];
    liveLabel.text = NSLocalizedString(@"LIVE", @"Live Photo badge text");
    liveLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    liveLabel.textColor = [UIColor colorWithRed:28/255.0 green:28/255.0 blue:28/255.0 alpha:0.6];
    liveLabel.tag = 102;
    [liveLabel sizeToFit];
    liveLabel.frame = CGRectMake(leftPadding + iconSize + spacing, 
                                  (badgeHeight - liveLabel.frame.size.height) / 2.0, 
                                  liveLabel.frame.size.width, 
                                  liveLabel.frame.size.height);
    [contentView addSubview:liveLabel];
    
    CGFloat actualBadgeWidth = leftPadding + iconSize + spacing + liveLabel.frame.size.width + rightPadding;
    CGRect badgeFrame = self.livePhotoBadge.frame;
    badgeFrame.size.width = actualBadgeWidth;
    self.livePhotoBadge.frame = badgeFrame;
    contentView.frame = self.livePhotoBadge.bounds;
    
    self.livePhotoBadge.hidden = YES;
    self.livePhotoBadge.alpha = 1.0;
    [self.view addSubview:self.livePhotoBadge];
}

- (void)showLivePhotoIcon {
    if (!self.livePhotoBadge) return;
    
    self.livePhotoBadge.hidden = NO;
    self.livePhotoBadge.alpha = 1.0;
    [self.view bringSubviewToFront:self.livePhotoBadge];
}

- (void)hideLivePhotoIcon {
    if (!self.livePhotoBadge) return;
    
    self.livePhotoBadge.hidden = YES;
}

- (void)showLivePhotoIconAnimated:(BOOL)animated {
    if (!self.livePhotoBadge) return;
    
    if (animated) {
        self.livePhotoBadge.alpha = 0.0;
        self.livePhotoBadge.hidden = NO;
        [self.view bringSubviewToFront:self.livePhotoBadge];
        
        [UIView animateWithDuration:0.2 animations:^{
            self.livePhotoBadge.alpha = 1.0;
        }];
    } else {
        [self showLivePhotoIcon];
    }
}

- (void)hideLivePhotoIconAnimated:(BOOL)animated {
    if (!self.livePhotoBadge) return;
    
    if (animated) {
        [UIView animateWithDuration:0.2 animations:^{
            self.livePhotoBadge.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.livePhotoBadge.hidden = YES;
        }];
    } else {
        [self hideLivePhotoIcon];
    }
}

// Update the info view with data from the info model
- (void)updateInfoView {
    self.infoView.infoModel = self.infoModel;
    [self.infoView updateInfoView];
}

// Toggle the info view visibility
- (void)toggleInfoView:(BOOL)show animated:(BOOL)animated {
    // Skip if already in the requested state
    if (show == self.infoVisible) return;
    
    self.infoVisible = show;
    [self updateGestureRecognizersForInfoVisibility:show];
    
    // Toggle Live Photo badge with info panel
    if (show) {
        [self hideLivePhotoIconAnimated:animated];
    } else {
        if (self.isMotionPhoto) {
            [self showLivePhotoIconAnimated:animated];
        }
    }
    
    // Get parent navigation controller and top view controller for controlling navigation bar and bottom UI
    UIViewController *parentVC = self.parentViewController;
    while (parentVC && ![parentVC isKindOfClass:[UINavigationController class]]) {
        parentVC = parentVC.parentViewController;
    }
    
    if ([parentVC isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navController = (UINavigationController *)parentVC;
        UIViewController *galleryVC = navController.topViewController;
        
        // When showing info panel
        if (show) {
            // Check if gallery controller has special methods
            BOOL hasSpecialGalleryHandling = NO;
            if ([galleryVC respondsToSelector:@selector(disableScrolling)]) {
                @try {
                    [galleryVC performSelector:@selector(disableScrolling)];
                    hasSpecialGalleryHandling = YES;
                } @catch (NSException *exception) {
                    Debug(@"Exception when calling disableScrolling: %@", exception);
                }
            }
            
            // Special case handling for SeafPhotoGalleryViewController - hide navigation bar with animation
            if (hasSpecialGalleryHandling) {
                // First move thumbnails out of the way immediately
                @try {
                    SeafPhotoGalleryViewController *specificGalleryVC = (SeafPhotoGalleryViewController *)galleryVC;
                    UIView *thumbnailCollection = specificGalleryVC.thumbnailCollection;
                    UIView *toolbarView = specificGalleryVC.toolbarView;
                    
                    // Hide thumbnail view immediately
                    if (thumbnailCollection) {
                        thumbnailCollection.hidden = YES;
                        thumbnailCollection.alpha = 0.0;
                    }
                    
                    // Keep toolbar visible
                    if (toolbarView) {
                        toolbarView.hidden = NO;
                        toolbarView.alpha = 1.0;
                    }
                } @catch (NSException *exception) {
                    Debug(@"Exception when accessing gallery properties: %@", exception);
                }
                
                // Hide navigation bar with fade
                    [UIView animateWithDuration:0.15 animations:^{
                        navController.navigationBar.alpha = 0.0;
                    } completion:^(BOOL finished) {
                        [navController setNavigationBarHidden:YES animated:NO];
                }];
            } else {
                // Normal behavior - add fade transition for hiding navigation bar
                [UIView animateWithDuration:0.15 animations:^{
                    navController.navigationBar.alpha = 0.0;
                } completion:^(BOOL finished) {
                    [navController setNavigationBarHidden:YES animated:NO];
                }];
            }
            
            if ([galleryVC isKindOfClass:[SeafPhotoGalleryViewController class]]) {
                @try {
                    SeafPhotoGalleryViewController *specificGalleryVC = (SeafPhotoGalleryViewController *)galleryVC;
                    UIView *thumbnailCollection = specificGalleryVC.thumbnailCollection;
                    UIView *toolbarView = specificGalleryVC.toolbarView;
                    
                    // Hide thumbnails immediately without animation
                    if (thumbnailCollection) {
                        thumbnailCollection.hidden = YES;
                        thumbnailCollection.alpha = 0.0;
                    }
                    
                    // Keep toolbar visible
                    if (toolbarView) {
                        toolbarView.hidden = NO;
                        toolbarView.alpha = 1.0;
                    }
                } @catch (NSException *exception) {
                    Debug(@"Exception when accessing gallery properties: %@", exception);
                }
            }
        }
        // When hiding info panel, restore navigation bar and thumbnails later
        else {
            // Add fade transition for showing navigation bar
            [navController setNavigationBarHidden:NO animated:NO];
            navController.navigationBar.alpha = 0.0;
            [UIView animateWithDuration:0.15 animations:^{
                navController.navigationBar.alpha = 1.0;
            }];
            
            if ([galleryVC isKindOfClass:[SeafPhotoGalleryViewController class]]) {
                @try {
                    SeafPhotoGalleryViewController *specificGalleryVC = (SeafPhotoGalleryViewController *)galleryVC;
                    UIView *thumbnailCollection = specificGalleryVC.thumbnailCollection;
                    UIView *toolbarView = specificGalleryVC.toolbarView;
                    
                    // Keep toolbar visible
                    if (toolbarView) {
                        toolbarView.hidden = NO;
                        toolbarView.alpha = 1.0;
                    }
                    
                    // Keep thumbnails hidden until info panel animation completes
                    if (thumbnailCollection) {
                        thumbnailCollection.hidden = YES;
                        thumbnailCollection.alpha = 0.0;
                    }
                } @catch (NSException *exception) {
                    Debug(@"Exception when accessing gallery properties: %@", exception);
                }
            }
        }
    }
    
    // If we need to show the info view, make sure it's updated and visible
    if (show) {
        // Restore background color from view mode (black) to normal mode (#F9F9F9)
        UIColor *normalBgColor = [UIColor colorWithRed:249/255.0 green:249/255.0 blue:249/255.0 alpha:1.0]; // #F9F9F9
        self.view.backgroundColor = normalBgColor;
        self.scrollView.backgroundColor = normalBgColor;
        self.imageView.backgroundColor = [UIColor clearColor];
        if (self.livePhotoPlayerView) {
            self.livePhotoPlayerView.backgroundColor = normalBgColor;
        }
        
        [self updateInfoView];
        self.infoView.hidden = NO;
        
        // Also display EXIF data if we have an image
        if (self.seafFile) {
            if ([self.seafFile isKindOfClass:[SeafFile class]]) {
                // If we have a file path, get the data to display EXIF info
                if (((SeafFile *)self.seafFile).ooid) {
                    NSString *path = [SeafStorage.sharedObject documentPath:((SeafFile *)self.seafFile).ooid];
                    NSData *data = [NSData dataWithContentsOfFile:path];
                    if (data) {
                        [self displayExifData:data];
                    }
                }
            } else if ([self.seafFile isKindOfClass:[SeafUploadFile class]]) {
                // For upload files, get data from the associated asset
                [((SeafUploadFile *)self.seafFile) getDataForAssociatedAssetWithCompletion:^(NSData * _Nullable data, NSError * _Nullable error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (data) {
                            [self displayExifData:data];
                        }
                    });
                }];
            }
        }
    }
    
    // Get bounds for calculations - these won't change during animation
    CGRect bounds = self.view.bounds;
    CGFloat infoHeight = roundf(bounds.size.height * 0.6); // 3/5 of height for info view
    CGFloat scrollHeight = roundf(bounds.size.height * 0.4); // 2/5 of height for scroll view
    
    // For non-animated transitions
    if (!animated) {
        // Update info panel position immediately
        if (show) {
            // Slide info panel up to show 3/5 of screen
            self.infoView.frame = CGRectMake(0, scrollHeight, bounds.size.width, infoHeight);
        } else {
            // Slide info panel down off screen
            self.infoView.frame = CGRectMake(0, bounds.size.height, bounds.size.width, infoHeight);
        }
        
        // Update scroll view frame without animation
        [self updateScrollViewForInfoVisibility:show animated:NO];
        
        // Hide the info view if we're hiding it
        if (!show) {
            self.infoView.hidden = YES;
            [self showThumbnailCollectionAfterInfoHidden];
        }
        
        return;
    }
    
    // Save current state before animation
    CGPoint contentOffset = self.scrollView.contentOffset;
    CGFloat zoomScale = self.scrollView.zoomScale;
    
    // Calculate target frames
    CGRect infoTargetFrame = show ?
        CGRectMake(0, scrollHeight, bounds.size.width, infoHeight) :
        CGRectMake(0, bounds.size.height, bounds.size.width, infoHeight);
        
    // Calculate scroll view target frame
    CGRect targetScrollFrame;
    
    if (show) {
        // When showing info, calculate proper scroll view position
        CGFloat visibleAreaCenterY = scrollHeight / 2.0; // Center of top 2/5 area
        CGFloat yOffset = visibleAreaCenterY - (bounds.size.height / 2.0);
        targetScrollFrame = CGRectMake(0, yOffset, bounds.size.width, bounds.size.height);
    } else {
        // When hiding info, scroll view takes full screen
        targetScrollFrame = bounds;
    }
    
    // Animated version
    if (show) {
        // Position info view initially off-screen
        self.infoView.frame = CGRectMake(0, bounds.size.height, bounds.size.width, infoHeight);
        
        // Animate both the info panel and scroll view together
        [UIView animateWithDuration:0.2
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            // Slide info panel up
            self.infoView.frame = infoTargetFrame;
            
            // Move scroll view to target position
            self.scrollView.frame = targetScrollFrame;

            // If the error placeholder view is visible, move it along with the scroll view
            if (self.errorPlaceholderView && self.errorPlaceholderView.superview) {
                CGRect placeholderFrame = targetScrollFrame;
                placeholderFrame.origin.y += 30.0; // Adjust position to be a bit lower
                self.errorPlaceholderView.frame = placeholderFrame;
            }
            
            // Restore content offset and scale
            self.scrollView.contentOffset = contentOffset;
            self.scrollView.zoomScale = zoomScale;
            
            // Update image center with animation
            [self scrollViewDidZoom:self.scrollView];
        } completion:^(BOOL finished) {
            // Reconfigure imageView for the new scrollView bounds
            [self configureForImage:self.imageView.image];
        }];
    } else {
        // Animate both info panel sliding down and scroll view moving back to full screen
        [UIView animateWithDuration:0.2
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
            // Slide info panel down
            self.infoView.frame = infoTargetFrame;
            
            // Move scroll view to target position
            self.scrollView.frame = targetScrollFrame;

            // If the error placeholder view is visible, move it along with the scroll view
            if (self.errorPlaceholderView && self.errorPlaceholderView.superview) {
                CGRect placeholderFrame = targetScrollFrame;
                placeholderFrame.origin.y += 30.0; // Adjust position to be a bit lower
                self.errorPlaceholderView.frame = placeholderFrame;
            }
            
            // Restore content offset and scale
            self.scrollView.contentOffset = contentOffset;
            self.scrollView.zoomScale = zoomScale;
            
            // Update image center with animation
            [self scrollViewDidZoom:self.scrollView];
        } completion:^(BOOL finished) {
            // After animation completes, hide the info view
            self.infoView.hidden = YES;
            
            // Reconfigure imageView for the restored full-screen scrollView bounds
            [self configureForImage:self.imageView.image];
            
            // Show thumbnails after info panel is hidden
            [self showThumbnailCollectionAfterInfoHidden];
        }];
    }
}

// Helper method to update scroll view frame separately from info panel animation
- (void)updateScrollViewForInfoVisibility:(BOOL)infoVisible animated:(BOOL)animated {
    CGRect bounds = self.view.bounds;
    CGFloat scrollHeight = roundf(bounds.size.height * 0.4); // 2/5 of height for scroll view
    
    // Save current state
    CGPoint contentOffset = self.scrollView.contentOffset;
    CGFloat zoomScale = self.scrollView.zoomScale;
    
    // Calculate target frame
    CGRect targetFrame;
    
    if (infoVisible) {
        // Calculate the center point of the top 2/5 area - it should be at 1/5 of screen height from top
        CGFloat visibleAreaCenterY = scrollHeight / 2.0; // Center of top 2/5 area
        
        // Use negative y-offset to position the scroll view's center at the center of the visible area
        CGFloat yOffset = visibleAreaCenterY - (bounds.size.height / 2.0);
        targetFrame = CGRectMake(0, yOffset, bounds.size.width, bounds.size.height);
    } else {
        // When info is hidden, scroll view takes full screen
        targetFrame = bounds;
    }
    
    // Apply changes with or without animation
    if (animated) {
        [UIView animateWithDuration:0.2 animations:^{
            self.scrollView.frame = targetFrame;

            // If the error placeholder view is visible, move it along with the scroll view
            if (self.errorPlaceholderView && self.errorPlaceholderView.superview) {
                CGRect placeholderFrame = targetFrame;
                if (infoVisible) {
                    placeholderFrame.origin.y += 30.0; // Adjust position to be a bit lower
                }
                self.errorPlaceholderView.frame = placeholderFrame;
            }
            
            // Restore offset and scale
            self.scrollView.contentOffset = contentOffset;
            self.scrollView.zoomScale = zoomScale;
            
            // Update image center with animation
            [self scrollViewDidZoom:self.scrollView];
        } completion:^(BOOL finished) {
            // Reconfigure imageView for the new scrollView bounds
            [self configureForImage:self.imageView.image];
        }];
    } else {
        // Apply changes immediately
        self.scrollView.frame = targetFrame;

        // If the error placeholder view is visible, move it along with the scroll view
        if (self.errorPlaceholderView && self.errorPlaceholderView.superview) {
            CGRect placeholderFrame = targetFrame;
            if (infoVisible) {
                placeholderFrame.origin.y += 30.0; // Adjust position to be a bit lower
            }
            self.errorPlaceholderView.frame = placeholderFrame;
        }
        
        // Restore offset and scale
        self.scrollView.contentOffset = contentOffset;
        self.scrollView.zoomScale = zoomScale;
        
        // Reconfigure imageView for the new scrollView bounds
        [self configureForImage:self.imageView.image];
    }
    
    // Force immediate layout update
    [self.scrollView setNeedsLayout];
    [self.scrollView layoutIfNeeded];
}

// Helper method to update frames based on info visibility - separate from animation
- (void)updateViewFramesForInfoVisibility:(BOOL)infoVisible {
    CGRect bounds = self.view.bounds;
    CGFloat infoHeight = roundf(bounds.size.height * 0.6); // 3/5 of height for info view
    CGFloat scrollHeight = roundf(bounds.size.height * 0.4); // 2/5 of height for scroll view
    
    // Update info panel position
    if (infoVisible) {
        self.infoView.frame = CGRectMake(0, scrollHeight, bounds.size.width, infoHeight);
    } else {
        self.infoView.frame = CGRectMake(0, bounds.size.height, bounds.size.width, infoHeight);
    }
    
    // Update scroll view separately - use NO for animation to avoid unwanted animations during layout updates
    [self updateScrollViewForInfoVisibility:infoVisible animated:NO];
}

// Show thumbnails after hiding info panel
- (void)showThumbnailCollectionAfterInfoHidden {
    UIViewController *parentVC = self.parentViewController;
    while (parentVC && ![parentVC isKindOfClass:[UINavigationController class]]) {
        parentVC = parentVC.parentViewController;
    }
    
    if ([parentVC isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navController = (UINavigationController *)parentVC;
        UIViewController *galleryVC = navController.topViewController;
        
        if ([galleryVC isKindOfClass:[SeafPhotoGalleryViewController class]]) {
            @try {
                SeafPhotoGalleryViewController *specificGalleryVC = (SeafPhotoGalleryViewController *)galleryVC;
                UIView *thumbnailCollection = specificGalleryVC.thumbnailCollection;
                if (thumbnailCollection) {
                    // Add fade-in animation effect instead of showing immediately
                    thumbnailCollection.hidden = NO;
                    thumbnailCollection.alpha = 0.0;
                    
                    [UIView animateWithDuration:0.15
                                          delay:0.0
                                        options:UIViewAnimationOptionCurveEaseIn
                                     animations:^{
                        thumbnailCollection.alpha = 1.0;
                    } completion:nil];
                }
            } @catch (NSException *exception) {
                Debug(@"Exception when accessing gallery properties: %@", exception);
            }
        }
    }
}

// Helper method to enable/disable gesture recognizers based on info visibility
- (void)updateGestureRecognizersForInfoVisibility:(BOOL)infoVisible {
    // When info is hidden, enable gestures for normal interaction
    self.tapGesture.enabled = !infoVisible;
    self.doubleTapGesture.enabled = !infoVisible;
}

// Handle tap to toggle UI visibility.
//
// Single-tap intent only. The gallery is the authoritative owner of chrome
// visibility (top nav bar, bottom toolbar, thumbnail strip, status bar) and
// it drives the per-page contentVC's appearance via
// `enterImmersiveAppearanceAnimated:` / `exitImmersiveAppearanceAnimated:`
// when its chrome state flips. We therefore do NOT touch navigationBar /
// status bar / gallery internals from here — that historically caused state
// drift between the tap path and the pinch-to-zoom path (alpha vs hidden).
- (void)handleTap:(UITapGestureRecognizer *)gesture {
    if ([self.delegate respondsToSelector:@selector(photoContentViewControllerDidRequestToggleChrome:)]) {
        [self.delegate photoContentViewControllerDidRequestToggleChrome:self];
        return;
    }

    // Legacy fallback — the delegate hasn't migrated to the unified chrome
    // contract. Keep the older toggle so a stale embedder still works, but
    // tag the path so it's easy to find when removing the legacy branch.
    if ([self.delegate respondsToSelector:@selector(photoContentViewController:didToggleImmersive:)]) {
        BOOL enteringImmersive = !self.fullscreenMode;
        [self.delegate photoContentViewController:self didToggleImmersive:enteringImmersive];
    }
}

- (void)loadImage {
    // At the beginning of loadImage, remove any existing error view
    if (self.errorPlaceholderView) {
        [self.errorPlaceholderView removeFromSuperview];
        self.errorPlaceholderView = nil;
    }
    self.isDisplayingPlaceholderOrErrorImage = NO; // Reset flag

    self.imageView.image = nil; // Clear previous image before loading new one
    // If seafFile is available, use it to load the image
    if (self.seafFile && [self.seafFile isKindOfClass:[SeafFile class]]) {
        Debug(@"[PhotoContent] loadImage called for %@, seafFile: %@, has ooid: %@", self.photoURL, self.seafFile.name, ((SeafFile *)self.seafFile).ooid ? @"YES" : @"NO");

        // Only show indicator if the file is NOT yet downloaded/cached (ooid is nil)
        if (![self.seafFile hasCache]) {
            [self showLoadingIndicator];
            Debug(@"[PhotoContent] File needs download, showing indicator: %@", self.seafFile.name);
            // If we have repoId and filePath, fetch file metadata from API (can happen concurrently)
            if (self.repoId && self.filePath) {
                [self fetchFileMetadata];
            }
            return;
        } else {
            // Add a loading indicator while we load the image (might be large)
            [self showLoadingIndicator];
            
            // File exists, proceed with loading
            NSString *expectedName = self.seafFile.name; // Capture for recycling check
            @weakify(self);
            [((SeafFile *)self.seafFile) getImageWithCompletion:^(UIImage *image) {
                @strongify(self);
                if (!self) return;
                Debug(@"[PhotoContent] getImageWithCompletion callback for %@, image: %@", self.seafFile.name, image ? @"SUCCESS" : @"FAILED");
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    @strongify(self);
                    if (!self) return;
                    // Allow image loading even when view isn't visible — adjacent
                    // pages pre-fetched by UIPageViewController need their images
                    // set before becoming visible during a page transition.
                    // Only skip if the seafFile has changed (VC was recycled).
                    if (!self.seafFile || ![self.seafFile.name isEqualToString:expectedName]) {
                        Debug(@"[PhotoContent] VC recycled, skipping image for %@", expectedName);
                        [self hideLoadingIndicator];
                        return;
                    }
                    
                    if (image) {
                        // This prevents the brief flash of white/blank screen
                        self.imageView.image = image;
                        self.isDisplayingPlaceholderOrErrorImage = NO; // Clear flag when setting real image
                        [self updateScrollViewContentSize];
                        Debug(@"[PhotoContent] Image set successfully for %@", self.seafFile.name);
                        
                        // Ensure error view is removed if it was somehow still there
                        if (self.errorPlaceholderView) {
                            [self.errorPlaceholderView removeFromSuperview];
                            self.errorPlaceholderView = nil;
                        }
                        self.isDisplayingPlaceholderOrErrorImage = NO; // Ensure flag is cleared on success

                        // If we have the file path, get the data to display EXIF info and check for Motion Photo
                        if (((SeafFile *)self.seafFile).ooid) {
                            NSString *path = [SeafStorage.sharedObject documentPath:((SeafFile *)self.seafFile).ooid];
                            NSData *data = [NSData dataWithContentsOfFile:path];
                            if (data) {
                                [self displayExifData:data];
                                
                                // Check if this is a Motion Photo and setup player
                                [self checkAndSetupMotionPhotoWithData:data];
                            } else {
                                Debug(@"[PhotoContent] WARNING: Could not read file data for EXIF from path: %@", path);
                            }
                        }
                        // Explicitly hide indicator AFTER image is set
                        [self hideLoadingIndicator];
                        Debug(@"[PhotoContent] Image loading complete, indicator hidden for %@", self.seafFile.name);
                    } else {
                        Debug(@"[PhotoContent] Image loading failed for %@", self.seafFile.name);
                        // self.imageView.image = [UIImage imageNamed:@"gallery_failed.png"];
                        // self.isDisplayingPlaceholderOrErrorImage = YES; // Set flag when setting error image
                        [self showErrorImage];
                        [self clearExifDataView];
                        // Explicitly hide indicator even on failure
                        [self hideLoadingIndicator];
                    }
                });
            }];
            
            // Fetch metadata if needed (can happen concurrently)
            if (self.repoId && self.filePath) {
                [self fetchFileMetadata];
            }
            return;
        }
    }
    else if ([self.seafFile isKindOfClass:[SeafUploadFile class]]) {
        @weakify(self);
        [((SeafUploadFile *)self.seafFile) getImageWithCompletion:^(UIImage *image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                @strongify(self);
                if (!self) return;
                // Check if this view controller is still active and valid
                if (!self.view.window) {
                    Debug(@"[PhotoContent] View is no longer visible, skipping image update for %@", self.seafFile.name);
                    [self hideLoadingIndicator];
                    return;
                }
                
                if (image) {
                    // This prevents the brief flash of white/blank screen
                    self.imageView.image = image;
                    self.isDisplayingPlaceholderOrErrorImage = NO; // Clear flag when setting real image
                    [self updateScrollViewContentSize];
                    Debug(@"[PhotoContent] Image set successfully for %@", self.seafFile.name);
                    
                    // Ensure error view is removed if it was somehow still there
                    if (self.errorPlaceholderView) {
                        [self.errorPlaceholderView removeFromSuperview];
                        self.errorPlaceholderView = nil;
                    }
                    self.isDisplayingPlaceholderOrErrorImage = NO; // Ensure flag is cleared on success

                    // If we have the file path, get the data to display EXIF info and check for Motion Photo
                    @weakify(self);
                    [((SeafUploadFile *)self.seafFile) getDataForAssociatedAssetWithCompletion:^(NSData * _Nullable data, NSError * _Nullable error) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            @strongify(self);
                            if (!self) return;
                            if (data) {
                                [self displayExifData:data];
                                // Check if this is a Motion Photo and setup player
                                [self checkAndSetupMotionPhotoWithData:data];
                            } else {
                                Debug(@"[PhotoContent] WARNING: Could not read file data for EXIF from uploadImage: %@", self.seafFile.name);
                            }
                            // Explicitly hide indicator AFTER image is set
                            [self hideLoadingIndicator];
                        });
                    }];
                   
                    Debug(@"[PhotoContent] Image loading complete, indicator hidden for %@", self.seafFile.name);
                } else {
                    Debug(@"[PhotoContent] Image loading failed for %@", self.seafFile.name);
                    [self showErrorImage];
                    [self clearExifDataView];
                    // Explicitly hide indicator even on failure
                    [self hideLoadingIndicator];
                }
            });

        }];
        return;
    }
    else {
        Debug(@"[PhotoContent] No SeafFile available to show image");
        [self showErrorImage];
        [self hideLoadingIndicator];
    }
}

// Add method to fetch file metadata from API
- (void)fetchFileMetadata {
    if (!self.repoId || !self.filePath) {
        Debug(@"Cannot fetch file metadata: repoId or filePath is missing");
        return;
    }
    
    // Use the connection property instead of getting it from app delegate
    if (!self.connection || !self.connection.authorized) {
        Debug(@"No valid connection available for API request");
        return;
    }
    
    // Build the API URL
    NSString *requestUrl = [NSString stringWithFormat:@"%@/repos/%@/file/detail/?p=%%2F%@", API_URL, self.repoId, [self.filePath escapedUrl]];
    Debug(@"Fetching file metadata from URL: %@", requestUrl);
    
    // Use SeafConnection's sendRequest method
    @weakify(self);
    [self.connection sendRequest:requestUrl
                    success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        // Handle success response
        if (!JSON) {
            Debug(@"No data received from file metadata API");
            return;
        }
        
        // Log the response for debugging
        Debug(@"File metadata response: %@", JSON);
        
        // Extract the needed information
        NSNumber *fileSize = JSON[@"size"];
        NSString *lastModified = JSON[@"last_modified"];
        NSString *lastModifierName = JSON[@"last_modifier_name"];
        NSString *lastModifierAvatar = JSON[@"last_modifier_avatar"]; // Avatar URL field
        
        // Create info model dictionary with the extracted data
        NSMutableDictionary *infoDict = [NSMutableDictionary dictionary];
        
        if (fileSize) {
            [infoDict setObject:[fileSize stringValue] forKey:@"Size"];
        }
        
        if (lastModified) {
            [infoDict setObject:lastModified forKey:@"Modified"];
        }
        
        if (lastModifierName) {
            [infoDict setObject:lastModifierName forKey:@"Owner"];
        }
        
        // If avatar URL exists, add it to the data model
        if (lastModifierAvatar) {
            [infoDict setObject:lastModifierAvatar forKey:@"OwnerAvatar"];
        }
        
        // Update the infoModel on the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            @strongify(self);
            if (!self) return;
            self.infoModel = infoDict;
            
            // Update the info view if it's visible
            if (self.infoVisible) {
                [self updateInfoView];
            }
        });
    }
    failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        Debug(@"Error fetching file metadata: %@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            @strongify(self);
            if (!self) return;
            if (!self.imageView.image && !self.isDisplayingPlaceholderOrErrorImage) {
                 // for metadata failure, we just log it. The user experience is primarily driven by image display.
            }
        });
    }];
}

// Update displayExifData to use the new InfoView
- (void)displayExifData:(NSData *)data {
    [self.infoView displayExifData:data];
}

// Update clearExifDataView to use the new InfoView
- (void)clearExifDataView {
    [self.infoView clearExifDataView];
}

#pragma mark - UIScrollViewDelegate
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

// Returns YES when the image is zoomed beyond its initial Aspect Fit size
- (BOOL)isZoomedIn {
    return self.scrollView.zoomScale > self.scrollView.minimumZoomScale + 0.01;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    Debug(@"[ZoomBug] viewWillTransitionToSize newSize=%@ currentBounds=%@ isZooming=%d zoom=%.4f",
          NSStringFromCGSize(size),
          NSStringFromCGRect(self.view.bounds),
          self.isZooming,
          self.scrollView.zoomScale);

    // Save current focal point (normalized 0~1 coordinates relative to image content)
    CGPoint contentOffset = self.scrollView.contentOffset;
    CGFloat zoomScale = self.scrollView.zoomScale;
    CGSize contentSize = self.scrollView.contentSize;
    
    CGFloat normalizedCenterX = 0.5, normalizedCenterY = 0.5;
    if (contentSize.width > 0 && contentSize.height > 0) {
        normalizedCenterX = (contentOffset.x + self.scrollView.bounds.size.width  / 2.0) / contentSize.width;
        normalizedCenterY = (contentOffset.y + self.scrollView.bounds.size.height / 2.0) / contentSize.height;
    }
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // Reconfigure imageView and zoom scales for the new bounds
        [self configureForImage:self.imageView.image];
        
        // Restore relative zoom scale
        CGFloat newZoomScale = MIN(zoomScale, self.scrollView.maximumZoomScale);
        newZoomScale = MAX(newZoomScale, self.scrollView.minimumZoomScale);
        self.scrollView.zoomScale = newZoomScale;
        
        // Restore focal point position
        CGFloat maxOffsetX = self.scrollView.contentSize.width  - self.scrollView.bounds.size.width;
        CGFloat maxOffsetY = self.scrollView.contentSize.height - self.scrollView.bounds.size.height;
        CGFloat newOffsetX = normalizedCenterX * self.scrollView.contentSize.width  - self.scrollView.bounds.size.width  / 2.0;
        CGFloat newOffsetY = normalizedCenterY * self.scrollView.contentSize.height - self.scrollView.bounds.size.height / 2.0;
        self.scrollView.contentOffset = CGPointMake(
            MAX(0, MIN(newOffsetX, maxOffsetX)),
            MAX(0, MIN(newOffsetY, maxOffsetY))
        );

        [self centerImageInScrollViewForReason:@"viewWillTransitionToSize"];
        
        // Refresh info view to adapt to new width
        if (self.infoVisible) {
            [self updateInfoView];
        }
    } completion:nil];
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    if (scrollView != self.scrollView) return;

    Debug(@"[ZoomBug] didZoom ENTER zoom=%.4f wasZoomedState=%d isConfiguringLayout=%d "
          @"contentSize=%@ contentInset=%@ contentOffset=%@ "
          @"scrollView.bounds=%@ imageView.frame=%@",
          scrollView.zoomScale,
          self.wasInZoomedState,
          self.isConfiguringLayout,
          NSStringFromCGSize(scrollView.contentSize),
          NSStringFromUIEdgeInsets(scrollView.contentInset),
          NSStringFromCGPoint(scrollView.contentOffset),
          NSStringFromCGRect(scrollView.bounds),
          NSStringFromCGRect(self.imageView.frame));

    // Use contentInset to center the image — matches iOS system Photos behavior
    [self centerImageInScrollViewForReason:@"scrollViewDidZoom"];

    Debug(@"[ZoomBug] didZoom AFTER_CENTER contentInset=%@ contentOffset=%@ "
          @"scrollView.bounds=%@",
          NSStringFromUIEdgeInsets(scrollView.contentInset),
          NSStringFromCGPoint(scrollView.contentOffset),
          NSStringFromCGRect(scrollView.bounds));

    // Skip immersive mode logic during programmatic layout resets
    // (e.g. configureForImage: / prepareForReuse setting zoomScale = 1.0)
    if (self.isConfiguringLayout) return;
    
    // Detect transition into zoomed-in state for immersive viewing mode.
    // This fires only once per zoom-in gesture when scale first exceeds minimum,
    // avoiding false triggers from bounce-zoom-out at minimum scale.
    BOOL currentlyZoomedIn = self.isZoomedIn;
    if (currentlyZoomedIn && !self.wasInZoomedState) {
        self.wasInZoomedState = YES;

        // Snapshot whether chrome was already hidden BEFORE this zoom-in
        // started. Read from the gallery (the chrome owner) so we capture
        // both "tap hid the bar" and "previous zoom faded the bar" cases
        // without re-checking navigationBar internals.
        if ([self.delegate respondsToSelector:@selector(photoContentViewControllerIsChromeHidden:)]) {
            self.wasImmersiveBeforeZoom = [self.delegate photoContentViewControllerIsChromeHidden:self];
        } else {
            UINavigationController *nav = self.navigationController;
            self.wasImmersiveBeforeZoom = (nav.navigationBarHidden || nav.navigationBar.alpha < 0.01);
        }

        Debug(@"[ZoomBug] FIRST_ENTER_ZOOMED_STATE zoom=%.4f wasImmersiveBeforeZoom=%d "
              @"-> snapshot only; chrome-hide deferred until scrollViewDidEndZooming:",
              scrollView.zoomScale, self.wasImmersiveBeforeZoom);

        // NOTE: We intentionally do NOT trigger the chrome-hide pipeline
        // here, even via dispatch_async. Hiding chrome (nav bar alpha
        // fade + status bar visibility flip) WHILE the pinch is in
        // flight has a subtle but unavoidable visual side-effect on iPad
        // landscape with portrait images:
        //
        //   • Before chrome hides, the nav bar (~70pt safeArea.top)
        //     occludes the top strip of the image. The user perceives
        //     the image's visual center as being shifted DOWNWARD by
        //     about 35pt (half of the occluded strip).
        //   • As the nav bar's alpha fades to 0, that 35pt of image
        //     content is suddenly revealed, and the perceived visual
        //     center jumps UP to the true screen center.
        //   • The `safeAreaInsets` change also fans out a
        //     `viewDidLayoutSubviews` to every cached photo VC, adding
        //     additional layout work on the same main-thread budget the
        //     pinch is competing for.
        //
        // Even though the actual `imageView.frame`, `contentOffset` and
        // `scrollView.frame` do not move (verified in the iPad logs),
        // the user perceives this as "突然居中的闪动" — a sudden
        // recentering flash overlaid on the focal-point-tracked pinch.
        //
        // Mirror what iOS Photos.app does instead: keep chrome visible
        // throughout the pinch and hide it only on release (in
        // `scrollViewDidEndZooming:`). The visual center shift then
        // happens AFTER the user has stopped touching the image, where
        // the human-perception cost is negligible.
        //
        // We still keep the snapshot above (`wasInZoomedState = YES` and
        // `wasImmersiveBeforeZoom`) because the symmetric "restore on
        // pinch-out to min zoom" branch in `scrollViewDidEndZooming:`
        // depends on those flags.
    }
}


- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view {
    if (scrollView != self.scrollView) return;
    self.isZooming = YES;

    UIEdgeInsets safeArea = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        safeArea = self.view.safeAreaInsets;
    }
    Debug(@"[ZoomBug] WILL_BEGIN_ZOOMING file=%@ "
          @"view.bounds=%@ safeArea=%@ "
          @"scrollView.frame=%@ scrollView.bounds=%@ "
          @"contentSize=%@ contentInset=%@ contentOffset=%@ "
          @"zoomScale=%.4f minZoom=%.4f maxZoom=%.4f "
          @"imageView.frame=%@ imageView.bounds=%@ "
          @"isChromeHidden(viaDelegate)=%d",
          self.seafFile ? self.seafFile.name : @"nil",
          NSStringFromCGRect(self.view.bounds),
          NSStringFromUIEdgeInsets(safeArea),
          NSStringFromCGRect(self.scrollView.frame),
          NSStringFromCGRect(self.scrollView.bounds),
          NSStringFromCGSize(self.scrollView.contentSize),
          NSStringFromUIEdgeInsets(self.scrollView.contentInset),
          NSStringFromCGPoint(self.scrollView.contentOffset),
          self.scrollView.zoomScale,
          self.scrollView.minimumZoomScale,
          self.scrollView.maximumZoomScale,
          NSStringFromCGRect(self.imageView.frame),
          NSStringFromCGRect(self.imageView.bounds),
          [self.delegate respondsToSelector:@selector(photoContentViewControllerIsChromeHidden:)]
            ? [self.delegate photoContentViewControllerIsChromeHidden:self] : -1);

    if ([self.delegate respondsToSelector:@selector(photoContentViewControllerDidBeginZooming:)]) {
        [self.delegate photoContentViewControllerDidBeginZooming:self];
    }
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale {
    if (scrollView != self.scrollView) return;
    self.isZooming = NO;
    
    // Skip immersive mode logic during programmatic layout resets
    if (self.isConfiguringLayout) return;
    
    BOOL isAtMinZoom = (scale <= scrollView.minimumZoomScale + 0.01);

    // When zoom returns to its minimum, the image is back to its Aspect Fit size
    // and contentSize <= boundsSize, so the only valid contentOffset is the one
    // that places the image visually centered (i.e. -contentInset.left/top).
    // UIScrollView does NOT always clamp contentOffset itself after a pinch-out,
    // especially if the user had scrolled the zoomed image off-center first.
    // Without this explicit reset, residual contentOffset from the zoomed state
    // would shift the now-fitted image toward a corner, which the user perceives
    // as "图片变小了一圈 / 比浏览时尺寸小". Keep this re-center idempotent —
    // re-applying when already centered is a no-op.
    if (isAtMinZoom) {
        [self centerImageInScrollViewForReason:@"scrollViewDidEndZooming-atMin"];
        UIEdgeInsets insets = scrollView.contentInset;
        CGPoint centeredOffset = CGPointMake(-insets.left, -insets.top);
        if (!CGPointEqualToPoint(scrollView.contentOffset, centeredOffset)) {
            DebugZoom(@"[ZoomDebug] scrollViewDidEndZooming: re-centering at min zoom, "
                  @"oldOffset=%@, newOffset=%@, contentInset=%@, contentSize=%@, bounds=%@",
                  NSStringFromCGPoint(scrollView.contentOffset),
                  NSStringFromCGPoint(centeredOffset),
                  NSStringFromUIEdgeInsets(insets),
                  NSStringFromCGSize(scrollView.contentSize),
                  NSStringFromCGRect(scrollView.bounds));
            scrollView.contentOffset = centeredOffset;
        }
    }

    // When zoomed back to initial size, decide whether to exit immersive based
    // on whether the user was already in immersive BEFORE the zoom-in began.
    // - If they tap-toggled into fullscreen first (wasImmersiveBeforeZoom == YES),
    //   keep chrome hidden so the apparent state matches their pre-zoom intent.
    // - Otherwise restore the normal (light, chrome-visible) appearance.
    BOOL restoreChrome = YES;
    if (isAtMinZoom && self.wasInZoomedState) {
        self.wasInZoomedState = NO;
        restoreChrome = !self.wasImmersiveBeforeZoom;
        // Reset the snapshot for the next zoom cycle.
        self.wasImmersiveBeforeZoom = NO;
    }
    
    // Prefer the richer callback that carries the chrome-restoration intent;
    // fall back to the legacy signature for any delegate that hasn't migrated.
    // The gallery's restore path drives this page's appearance via the
    // `setChromeHidden:` pipeline, so we don't need to re-call
    // `exitImmersiveAppearanceAnimated:` locally here.
    BOOL ownerHandledAppearance = NO;
    if ([self.delegate respondsToSelector:@selector(photoContentViewControllerDidEndZooming:isAtMinZoom:restoreChrome:)]) {
        [self.delegate photoContentViewControllerDidEndZooming:self
                                                    isAtMinZoom:isAtMinZoom
                                                  restoreChrome:restoreChrome];
        ownerHandledAppearance = [self.delegate respondsToSelector:@selector(photoContentViewControllerIsChromeHidden:)];
    } else if ([self.delegate respondsToSelector:@selector(photoContentViewControllerDidEndZooming:isAtMinZoom:)]) {
        [self.delegate photoContentViewControllerDidEndZooming:self isAtMinZoom:isAtMinZoom];
    }

    // Legacy fallback: when no chrome owner is wired in, honor the
    // restoreChrome decision locally so the per-page appearance still flips
    // back to the light look on pinch-out.
    if (!ownerHandledAppearance && isAtMinZoom && restoreChrome) {
        [self exitImmersiveAppearanceAnimated:YES];
    }

    // Enter immersive mode on RELEASE, not mid-pinch.
    //
    // Historically the chrome-hide animation was triggered from
    // `scrollViewDidZoom:` the moment zoomScale first crossed above the
    // minimum. That made chrome fade out while the pinch was still in
    // flight, which on iPad-landscape with a portrait image causes a
    // perceptible "sudden centering" flicker — the nav bar's alpha
    // fade reveals ~35pt of previously-occluded image content and the
    // user's eye reads that as the image jumping to a new center.
    //
    // Defer the chrome-hide until the user actually releases. By then
    // the image is no longer being focal-point-tracked, so the same
    // 35pt visual-center shift is no longer overlaid on a moving image
    // and is no longer perceived as a flicker. This also matches the
    // iOS Photos.app pinch-zoom behavior.
    //
    // Conditions to enter immersive on release:
    //   • not at min zoom (we ended a zoom-in gesture, not a snap-back)
    //   • we observed the first-enter transition during the gesture
    //     (i.e. `wasInZoomedState == YES`)
    //   • chrome was NOT already hidden when the pinch started
    //     (otherwise there is nothing to hide)
    if (!isAtMinZoom && self.wasInZoomedState && !self.wasImmersiveBeforeZoom) {
        Debug(@"[ZoomBug] DID_END_ZOOMING zoom=%.4f -> entering immersive on release "
              @"(deferred from scrollViewDidZoom: to avoid mid-pinch chrome flicker)",
              scale);
        BOOL ownerHandledImmersive = NO;
        if ([self.delegate respondsToSelector:@selector(photoContentViewControllerDidEnterZoomedState:)]) {
            [self.delegate photoContentViewControllerDidEnterZoomedState:self];
            ownerHandledImmersive = [self.delegate respondsToSelector:@selector(photoContentViewControllerIsChromeHidden:)];
        }
        if (!ownerHandledImmersive) {
            [self enterImmersiveAppearanceAnimated:YES];
        }
    }
}

// Handle double tap gesture — aligned with iOS system Photos behavior
- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    if (self.scrollView.zoomScale > self.scrollView.minimumZoomScale + 0.01) {
        // Already zoomed in → zoom back to minimum
        [self.scrollView setZoomScale:self.scrollView.minimumZoomScale animated:YES];
    } else {
        // Not zoomed → zoom in to a suitable level
        CGPoint location = [gesture locationInView:self.imageView];
        
        // Mirror iOS Photos: fill the screen on the dimension that has whitespace after aspect-fit.
        // - Wide / panoramic / slightly-tall images (fit leaves vertical whitespace) → fill height
        //   exactly, no floor — overshooting would push the image past the screen height, which
        //   is exactly what we are trying to avoid for "略高一点" images.
        // - Tall / portrait images (fit fills height, leaves horizontal whitespace) → fill width,
        //   floored at 2x because widthFill can collapse to 1.0 when the image already fills width.
        CGSize boundsSize = self.scrollView.bounds.size;
        CGSize fitSize    = self.imageView.frame.size;
        CGFloat targetScale;
        if (fitSize.height > 0 && fitSize.height < boundsSize.height - 0.5) {
            targetScale = boundsSize.height / fitSize.height;
        } else {
            targetScale = MAX(boundsSize.width / fitSize.width, 2.0);
        }
        targetScale = MIN(targetScale, self.scrollView.maximumZoomScale); // Don't exceed max
        
        // Calculate zoomToRect based on precise imageView coordinates
        CGFloat width  = self.scrollView.bounds.size.width  / targetScale;
        CGFloat height = self.scrollView.bounds.size.height / targetScale;
        CGRect zoomRect = CGRectMake(location.x - width / 2,
                                     location.y - height / 2,
                                     width, height);
        
        [self.scrollView zoomToRect:zoomRect animated:YES];
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != self.dismissPanGesture) return YES;

    // Only begin dismiss drag when:
    // 1. Not in the middle of a pinch-zoom gesture. `isZoomedIn` (zoom > min)
    //    is NOT a sufficient guard here: while the user is pinching the image
    //    smaller than its initial size, zoom enters the rubber-band region
    //    (zoom < min), so `isZoomedIn` returns NO and the dismiss-drag would
    //    otherwise be allowed to start mid-pinch. `isZooming` covers the
    //    entire pinch lifecycle (set in scrollViewWillBeginZooming:, cleared
    //    in scrollViewDidEndZooming:), including sub-min rubber-band frames.
    // 2. Not already zoomed past the natural fit size — those gestures belong
    //    to the scroll view's own pan for exploring the zoomed image.
    // 3. Info panel is not visible.
    // 4. Dragging direction is primarily downward.
    if (self.isZooming) return NO;
    if (self.isZoomedIn) return NO;
    if (self.infoVisible) return NO;

    CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.view];
    return (fabs(velocity.y) > fabs(velocity.x) * 1.5) && (velocity.y > 0);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // Allow dismiss pan to coexist with scrollView's internal pan gesture
    if (gestureRecognizer == self.dismissPanGesture) {
        return YES;
    }
    return NO;
}

// Handle pull-down-to-dismiss gesture — iOS Photos style.
// We no longer manipulate the scroll view's transform here. Instead, the
// gallery owns a Hero snapshot that follows the finger via a custom
// interactive transition; we just relay translation/progress/velocity.
- (void)handleDismissPan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.view];
    CGPoint velocity = [gesture velocityInView:self.view];
    CGFloat progress = translation.y / MAX(1.0, self.view.bounds.size.height);
    progress = MAX(0, MIN(1, progress));

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            self.scrollView.scrollEnabled = NO;

            if ([self.delegate respondsToSelector:@selector(photoContentViewControllerDidBeginDismissDrag:)]) {
                [self.delegate photoContentViewControllerDidBeginDismissDrag:self];
            }
            break;
        }

        case UIGestureRecognizerStateChanged: {
            if ([self.delegate respondsToSelector:@selector(photoContentViewController:dismissDragMoved:progress:velocity:)]) {
                [self.delegate photoContentViewController:self
                                         dismissDragMoved:translation
                                                 progress:progress
                                                 velocity:velocity];
            }
            break;
        }

        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            BOOL shouldDismiss = (progress > 0.25) || (velocity.y > 800);
            if (gesture.state != UIGestureRecognizerStateEnded) {
                shouldDismiss = NO;
            }

            if (shouldDismiss) {
                if ([self.delegate respondsToSelector:@selector(photoContentViewController:didCompleteDismissDragWithVelocity:)]) {
                    [self.delegate photoContentViewController:self didCompleteDismissDragWithVelocity:velocity];
                }
            } else {
                self.scrollView.scrollEnabled = YES;
                if ([self.delegate respondsToSelector:@selector(photoContentViewController:didCancelDismissDragWithVelocity:)]) {
                    [self.delegate photoContentViewController:self didCancelDismissDragWithVelocity:velocity];
                }
            }
            break;
        }
        default:
            break;
    }
}

#pragma mark - Hero Transition Support

- (UIImage *)currentDisplayedImage {
    return self.imageView.image;
}

- (CGRect)displayedImageFrameInView:(UIView *)view {
    UIView *referenceView = self.imageView.image ? self.imageView : (UIView *)self.scrollView;
    if (!referenceView) return CGRectZero;
    UIView *coordinateSpace = view ?: self.view.window;
    if (!coordinateSpace) {
        // Fall back to the gallery's own view if window isn't reachable yet.
        coordinateSpace = self.view;
    }
    return [referenceView.superview convertRect:referenceView.frame toView:coordinateSpace];
}

- (void)setUnderlyingPhotoHidden:(BOOL)hidden {
    if (hidden) {
        // Remember the badge's previous hidden state so we can restore it
        // exactly on cancel — the badge has its own visibility lifecycle
        // driven by hasMotionPhotoContent.
        if (!self.scrollView.hidden) {
            self.savedLivePhotoBadgeHidden = self.livePhotoBadge ? self.livePhotoBadge.hidden : YES;
        }
        self.scrollView.hidden = YES;
        self.livePhotoBadge.hidden = YES;
    } else {
        self.scrollView.hidden = NO;
        if (self.livePhotoBadge) {
            self.livePhotoBadge.hidden = self.savedLivePhotoBadgeHidden;
        }
    }
}

- (void)setInfoVisible:(BOOL)infoVisible {
    if (_infoVisible != infoVisible) {
        _infoVisible = infoVisible;
        [self updateGestureRecognizersForInfoVisibility:infoVisible];
    }
}

#pragma mark - Loading Indicator Methods

- (void)showLoadingIndicator {
    Debug(@"[PhotoContent] showLoadingIndicator called for %@", self.seafFile ? self.seafFile.name : self.photoURL);
    
    // Ensure this runs on the main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showLoadingIndicator];
        });
        return;
    }
    
    // Ensure indicator exists and is created if needed
    if (!self.activityIndicator || !self.progressLabel) {
        Debug(@"[PhotoContent] Creating loading indicators that were not initialized for %@", self.seafFile ? self.seafFile.name : @"unknown");
        [self setupLoadingIndicator];
    }
    
    // Only start animating if not already animating
    if (!self.activityIndicator.isAnimating) {
        [self.activityIndicator startAnimating];
        self.progressLabel.text = @"0%";
        self.progressLabel.hidden = NO;
        [self.view bringSubviewToFront:self.activityIndicator];
        [self.view bringSubviewToFront:self.progressLabel];
        Debug(@"[PhotoContent] Loading indicator now visible for %@", self.seafFile ? self.seafFile.name : self.photoURL);
    }
}

- (void)hideLoadingIndicator {
    Debug(@"[PhotoContent] hideLoadingIndicator called for %@", self.seafFile ? self.seafFile.name : self.photoURL);
    
    // Ensure this runs on the main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideLoadingIndicator];
        });
        return;
    }
    
    // Remove all indicators to ensure none are left behind
    [self cleanupAllLoadingIndicators];
    
    Debug(@"[PhotoContent] Loading indicators hidden and cleaned up for %@", self.seafFile ? self.seafFile.name : self.photoURL);
}

// More thorough cleanup of all loading indicators
- (void)cleanupAllLoadingIndicators {
    // Stop the main activity indicator if it exists
    if (self.activityIndicator && [self.activityIndicator isAnimating]) {
        [self.activityIndicator stopAnimating];
    }
    
    // Hide the main progress label if it exists
    if (self.progressLabel) {
        self.progressLabel.hidden = YES;
    }
    
    // Find and remove any other activity indicators or percentage labels that might exist
    for (UIView *subview in self.view.subviews) {
        // Check for any UIActivityIndicatorView
        if ([subview isKindOfClass:[UIActivityIndicatorView class]]) {
            UIActivityIndicatorView *indicator = (UIActivityIndicatorView *)subview;
            [indicator stopAnimating];
            
            // If it's not our main indicator, remove it
            if (indicator != self.activityIndicator) {
                Debug(@"[PhotoContent] Removing extra indicator: %@", indicator);
                [indicator removeFromSuperview];
            }
        }
        // Check for any UILabel with percentage text
        else if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            NSString *text = label.text;
            
            // If it's a percentage label and not our main one, remove it
            if (text && ([text hasSuffix:@"%"] || label.tag == 1002) && label != self.progressLabel) {
                Debug(@"[PhotoContent] Removing extra progress label: %@", label);
                [label removeFromSuperview];
            }
        }
    }
}

- (void)updateLoadingProgress:(float)progress {
    // Ensure this runs on the main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateLoadingProgress:progress];
        });
        return;
    }
    
    // Ensure we have loading indicators
    if (!self.activityIndicator || !self.progressLabel) {
        Debug(@"[PhotoContent] Creating loading indicators before updating progress for %@", self.seafFile ? self.seafFile.name : @"unknown");
        [self setupLoadingIndicator];
    }
    
    // Only update if we have valid indicators
    if (self.activityIndicator && self.progressLabel) {
        // Start animating if not already
        if (!self.activityIndicator.isAnimating) {
            [self.activityIndicator startAnimating];
            [self.view bringSubviewToFront:self.activityIndicator];
        }
        
        // Update text and ensure visible
        self.progressLabel.text = [NSString stringWithFormat:@"%.0f%%", progress * 100];
        self.progressLabel.hidden = NO;
        [self.view bringSubviewToFront:self.progressLabel];
        
        Debug(@"[PhotoContent] Updated progress to %.0f%% for %@", progress * 100, self.seafFile ? self.seafFile.name : self.photoURL);
    }
}

// Sets an error image to display when loading fails
- (void)showErrorImage {
    Debug(@"[PhotoContent] Showing error image for %@", self.seafFile ? self.seafFile.name : self.photoURL);

    // Ensure this runs on the main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showErrorImage];
        });
        return;
    }

    // IMPORTANT: Don't show error if we already have a valid image displayed
    // This prevents thumbnail download failure from overwriting a successfully loaded full image
    if (self.imageView.image != nil && !self.isDisplayingPlaceholderOrErrorImage) {
        Debug(@"[PhotoContent] Skipping error image - already have valid image displayed for %@", self.seafFile.name);
        return;
    }
    
    // Also check if we have a live photo player view with content
    if (self.livePhotoPlayerView && self.livePhotoPlayerView.hasMotionPhotoContent) {
        Debug(@"[PhotoContent] Skipping error image - live photo player has content for %@", self.seafFile.name);
        return;
    }

    // Clear the main image view content
    self.imageView.image = nil;
    self.isDisplayingPlaceholderOrErrorImage = YES;

    // Remove existing error view if any to prevent duplicates
    if (self.errorPlaceholderView) {
        [self.errorPlaceholderView removeFromSuperview];
        self.errorPlaceholderView = nil;
    }

    // Create the new SeafErrorPlaceholderView
    self.errorPlaceholderView = [[SeafErrorPlaceholderView alloc] initWithFrame:self.view.bounds];
    // The autoresizingMask is set within SeafErrorPlaceholderView's initWithFrame

    // Disable the main tap gesture when error view is visible
    self.tapGesture.enabled = NO;

    // Set the retry action block
    __weak typeof(self) weakSelf = self;
    self.errorPlaceholderView.retryActionBlock = ^{
        // Call the existing retry tap handler
        // We pass nil because the gesture recognizer isn't strictly needed by handleRetryTap's core logic anymore
        [weakSelf handleRetryTap:nil]; 
    };

    // [self.view addSubview:self.errorPlaceholderView];
    // [self.view bringSubviewToFront:self.errorPlaceholderView];
    [self.view insertSubview:self.errorPlaceholderView belowSubview:self.infoView];

    // Update scroll view content size (imageView.image is nil, so contentSize should be minimal)
    [self updateScrollViewContentSize];

    // Clear any EXIF data
    [self clearExifDataView];

    // Make sure the loading indicator is hidden
    [self hideLoadingIndicator];

    Debug(@"[PhotoContent] Error placeholder view set and loading indicator hidden for %@", self.seafFile ? self.seafFile.name : self.photoURL);
}

// Method to handle the retry tap
- (void)handleRetryTap:(UITapGestureRecognizer *)gesture {
    Debug(@"[PhotoContent] Retry tapped for %@", self.seafFile ? self.seafFile.name : self.photoURL);
    // Remove the error view before retrying
    if (self.errorPlaceholderView) {
        [self.errorPlaceholderView removeFromSuperview];
        self.errorPlaceholderView = nil;
    }
    self.isDisplayingPlaceholderOrErrorImage = NO; // Reset flag

    // Re-enable the main tap gesture before attempting retry
    self.tapGesture.enabled = YES;

    // Notify delegate to retry loading
    if (self.delegate && [self.delegate respondsToSelector:@selector(photoContentViewControllerRequestsRetryForFile:atIndex:)]) {
        // Use the explicit pageIndex set by the gallery (replaces legacy view.tag).
        NSUInteger currentIndex = self.pageIndex;
        if (self.seafFile) { // Ensure seafFile is not nil
            [self.delegate photoContentViewControllerRequestsRetryForFile:self.seafFile atIndex:currentIndex];
            [self showLoadingIndicator]; // Show loading indicator immediately in the content view
        } else {
            Debug(@"[PhotoContent] Cannot retry: seafFile is nil.");
            // Optionally, show error again if seafFile is nil, as retry isn't possible
            [self showErrorImage]; 
        }
    } else {
        Debug(@"[PhotoContent] Delegate not set or does not respond to retry selector. Cannot retry.");
        // Fallback or error handling if delegate is not correctly set up
        // For example, re-show the error image as retry is not possible through delegate
        [self showErrorImage];
    }
}

// Ensure indicator remains centered during layout changes
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.activityIndicator.center = self.view.center;
    self.progressLabel.center = CGPointMake(self.view.center.x, self.view.center.y + self.activityIndicator.bounds.size.height / 2 + 25);
    
    // Position Live Photo badge below navigation bar
    if (self.livePhotoBadge) {
        CGFloat leftMargin = 8.0;
        CGFloat topMargin = 12.0;
        CGFloat topOffset = topMargin;
        CGFloat leftOffset = leftMargin;
        if (@available(iOS 11.0, *)) {
            topOffset += self.view.safeAreaInsets.top;
            leftOffset += self.view.safeAreaInsets.left;
        }
        
        CGRect badgeFrame = self.livePhotoBadge.frame;
        badgeFrame.origin.x = leftOffset;
        badgeFrame.origin.y = topOffset;
        self.livePhotoBadge.frame = badgeFrame;
    }

    // If the error placeholder view is visible, re-layout its contents
    // This part is now handled by SeafErrorPlaceholderView's layoutSubviews
    /*
    if (self.errorPlaceholderView && self.errorPlaceholderView.superview) {
        self.errorPlaceholderView.frame = self.view.bounds; // Ensure it fills the view

        // Recalculate sizes and positions for error icon and label
        CGFloat iconSize = self.errorIconImageView.frame.size.width; // This property is gone
        if (iconSize == 0 && self.errorIconImageView.image) { // This property is gone
             iconSize = 130.0; // default size
             self.errorIconImageView.frame = CGRectMake(0,0,iconSize,iconSize); // This property is gone
        }
        [self.errorLabel sizeToFit]; // This property is gone

        CGFloat spacingBetweenIconAndLabel = 8.0;
        CGFloat totalContentHeight = self.errorIconImageView.frame.size.height + spacingBetweenIconAndLabel + self.errorLabel.frame.size.height; // These properties are gone
        
        CGFloat startY = (self.errorPlaceholderView.bounds.size.height - totalContentHeight) / 2.0 - 25.0;

        self.errorIconImageView.frame = CGRectMake(
            (self.errorPlaceholderView.bounds.size.width - self.errorIconImageView.frame.size.width) / 2.0,
            startY,
            self.errorIconImageView.frame.size.width,
            self.errorIconImageView.frame.size.height
        ); // These properties are gone

        // Ensure the label width doesn't exceed the placeholder view width with some padding
        CGFloat maxLabelWidth = self.errorPlaceholderView.bounds.size.width - 40; // 20px padding on each side
        CGRect currentLabelFrame = self.errorLabel.frame; // This property is gone
        currentLabelFrame.size.width = MIN(currentLabelFrame.size.width, maxLabelWidth);
        
        self.errorLabel.frame = CGRectMake(
            (self.errorPlaceholderView.bounds.size.width - currentLabelFrame.size.width) / 2.0,
            startY + self.errorIconImageView.frame.size.height + spacingBetweenIconAndLabel,
            currentLabelFrame.size.width,
            currentLabelFrame.size.height
        ); // These properties are gone
    }
    */

    // Update frames based on current state
    DebugZoom(@"[ZoomDebug] viewDidLayoutSubviews: file=%@, view.bounds=%@, scrollView.frame=%@, scrollView.bounds=%@, imageView.frame=%@, zoomScale=%.3f",
          self.seafFile ? self.seafFile.name : @"nil",
          NSStringFromCGRect(self.view.bounds),
          NSStringFromCGRect(self.scrollView.frame),
          NSStringFromCGRect(self.scrollView.bounds),
          NSStringFromCGRect(self.imageView.frame),
          self.scrollView.zoomScale);

    // CRITICAL — only run the heavy reconfigure chain (which calls
    // configureForImage: and force-resets zoomScale) when the scrollView's
    // frame actually needs to change. UIKit fires viewDidLayoutSubviews for
    // many incidental reasons (e.g. when entering immersive mode the gallery
    // animates alphas / pageVC.view.backgroundColor, which can mark the
    // hierarchy needsLayout). If we unconditionally reconfigure here while
    // the user is mid-pinch, configureForImage: will interrupt the gesture
    // — and historically it could even pollute imageView.bounds. Now that
    // configureForImage: is safe against mid-zoom calls (it pre-resets
    // zoomScale before touching imageView.frame), the worst case is just
    // wasted work plus a snap-out of the user's gesture, which is still
    // user-visible. Guard with a frame-equality check so the reconfigure
    // only fires on actual layout changes (orientation, info-panel toggle,
    // first appearance, etc.).
    CGRect targetScrollFrame = [self targetScrollViewFrameForInfoVisibility:self.infoVisible];
    BOOL frameChanged = !CGRectEqualToRect(self.scrollView.frame, targetScrollFrame);
    UIEdgeInsets safeArea = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        safeArea = self.view.safeAreaInsets;
    }
    Debug(@"[ZoomBug] viewDidLayoutSubviews isZooming=%d frameChanged=%d "
          @"view.bounds=%@ safeArea=%@ scrollView.frame=%@ target=%@ "
          @"zoom=%.4f contentInset=%@ contentOffset=%@",
          self.isZooming, frameChanged,
          NSStringFromCGRect(self.view.bounds),
          NSStringFromUIEdgeInsets(safeArea),
          NSStringFromCGRect(self.scrollView.frame),
          NSStringFromCGRect(targetScrollFrame),
          self.scrollView.zoomScale,
          NSStringFromUIEdgeInsets(self.scrollView.contentInset),
          NSStringFromCGPoint(self.scrollView.contentOffset));

    if (frameChanged) {
        DebugZoom(@"[ZoomDebug] viewDidLayoutSubviews: scrollView frame change detected, "
              @"current=%@, target=%@, running full reconfigure",
              NSStringFromCGRect(self.scrollView.frame),
              NSStringFromCGRect(targetScrollFrame));
        [self updateViewFramesForInfoVisibility:self.infoVisible];
    } else if (!self.isZooming) {
        // Frames already correct — just keep contentInset centered. This is
        // cheap and idempotent OUTSIDE of an active pinch. During a pinch
        // (`isZooming == YES`) `scrollViewDidZoom:` is already calling
        // `centerImageInScrollViewForReason:@"scrollViewDidZoom"` on every
        // zoom event, so the layout-time call here is purely redundant. It
        // is also actively harmful: while the user is mid-pinch the gallery
        // chrome may be animating (status bar / nav bar fade-out triggers a
        // `safeAreaInsets` change, which UIKit fans out as a
        // `viewDidLayoutSubviews` to every photo VC in the page strip).
        // Doing an extra `setContentInset:` write on the active VC's scroll
        // view in the middle of a pinch causes UIScrollView to re-run its
        // internal clamp / dispatch chain. Combined with the chrome
        // animation already monopolizing the main thread, that produces the
        // "image suddenly jumps a few points" frame-skip the user reported
        // around the moment immersive mode kicks in.
        [self centerImageInScrollViewForReason:@"viewDidLayoutSubviews"];
    }
}

// Compute the scrollView frame that updateScrollViewForInfoVisibility:
// would target for the given infoVisible state, without applying it.
// Kept in sync with the calculation in updateScrollViewForInfoVisibility:.
- (CGRect)targetScrollViewFrameForInfoVisibility:(BOOL)infoVisible {
    CGRect bounds = self.view.bounds;
    if (infoVisible) {
        CGFloat scrollHeight = roundf(bounds.size.height * 0.4);
        CGFloat visibleAreaCenterY = scrollHeight / 2.0;
        CGFloat yOffset = visibleAreaCenterY - (bounds.size.height / 2.0);
        return CGRectMake(0, yOffset, bounds.size.width, bounds.size.height);
    }
    return bounds;
}

// New method to setup the loading indicator and progress label
- (void)setupLoadingIndicator {
    // First, remove any existing indicators to prevent duplicates
    [self removeExistingLoadingIndicators];
    
    // Activity Indicator
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.activityIndicator.hidesWhenStopped = YES;
    self.activityIndicator.center = self.view.center; // Center in the main view initially
    self.activityIndicator.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    self.activityIndicator.tag = 1001; // Tag for identification
    [self.view addSubview:self.activityIndicator]; // Add to main view, not scroll view

    // Progress Label
    self.progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 100, 40)];
    self.progressLabel.center = CGPointMake(self.view.center.x, self.view.center.y + self.activityIndicator.bounds.size.height / 2 + 25); // Position below indicator
    self.progressLabel.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    self.progressLabel.textColor = [UIColor grayColor]; // Changed text color to gray
    self.progressLabel.backgroundColor = [UIColor clearColor]; // Removed background color
    self.progressLabel.textAlignment = NSTextAlignmentCenter;
    self.progressLabel.font = [UIFont systemFontOfSize:14];
    self.progressLabel.layer.cornerRadius = 8.0;
    self.progressLabel.layer.masksToBounds = YES;
    self.progressLabel.hidden = YES; // Initially hidden
    self.progressLabel.tag = 1002; // Tag for identification
    [self.view addSubview:self.progressLabel];
    
    Debug(@"[PhotoContent] Setup new loading indicators for %@", self.seafFile ? self.seafFile.name : @"unknown");
}

// Helper method to remove any existing loading indicators
- (void)removeExistingLoadingIndicators {
    // Remove all activity indicators and progress labels from the view
    for (UIView *subview in self.view.subviews) {
        if ([subview isKindOfClass:[UIActivityIndicatorView class]] ||
            ([subview isKindOfClass:[UILabel class]] &&
             (subview.tag == 1002 || [[(UILabel *)subview text] hasSuffix:@"%"]))) {
            
            Debug(@"[PhotoContent] Removing existing indicator/label: %@", subview);
            [subview removeFromSuperview];
        }
    }
    
    // Clear references
    self.activityIndicator = nil;
    self.progressLabel = nil;
}

// Detect scroll position for info scroll view
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    // Check if it's the info scroll view
    if (scrollView == self.infoView.infoScrollView) {
        // If at the top and being pulled down, track the dragging progress
        if (scrollView.contentOffset.y < 0) {
            // The more negative the content offset, the more it's being pulled down
            CGFloat pullDistance = -scrollView.contentOffset.y;
            
            // Check if we're actively dragging (not just bouncing back)
            if (scrollView.isDragging) {
                // Get the drag direction using the translation of the pan gesture
                CGPoint translation = [scrollView.panGestureRecognizer translationInView:self.view];
                
                // If pulled down more than a threshold and gesture is moving downward
                if (pullDistance > 40 && translation.y > 0) {
                    if (!self.draggedBeyondTopEdge) {
                        self.draggedBeyondTopEdge = YES;
                        [self notifyGalleryViewControllerToHideInfoPanel];
                    }
                }
            }
        }
    }
    // SeafZoomableScrollView handles edge handoff into the outer paging
    // view; no edge tracking required here anymore.
}

// Detect when user finishes dragging the info scroll view down
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    // Check if this is the info scroll view
    if (scrollView == self.infoView.infoScrollView) {
        // If at the top and being pulled down, hide the info panel
        if (scrollView.contentOffset.y <= 0 && [scrollView.panGestureRecognizer translationInView:self.view].y > 10) {
            // Find the gallery view controller and notify it to hide the info panel
            [self notifyGalleryViewControllerToHideInfoPanel];
        }
    }
    // Edge-driven paging handoff is now handled inside SeafZoomableScrollView
    // by observing its own pan gesture; no per-drag edge bookkeeping here.
}

// Track start of drag operation
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView == self.infoView.infoScrollView) {
        // Reset the tracking flag at the start of each drag operation
        self.draggedBeyondTopEdge = NO;
    }
}

// Helper method to notify the gallery view controller to hide the info panel
- (void)notifyGalleryViewControllerToHideInfoPanel {
    UIViewController *parentVC = self.parentViewController;
    while (parentVC && ![parentVC isKindOfClass:[SeafPhotoGalleryViewController class]]) {
        parentVC = parentVC.parentViewController;
    }
    
    if (parentVC) {
        @try {
            // Try to call the handleSwipeDown method on the gallery view controller
            SEL handleSwipeDownSelector = NSSelectorFromString(@"handleSwipeDown:");
            if ([parentVC respondsToSelector:handleSwipeDownSelector]) {
                [parentVC performSelector:handleSwipeDownSelector withObject:nil];
            }
        } @catch (NSException *exception) {
            Debug(@"Exception when trying to call handleSwipeDown: %@", exception);
        }
    }
}

// Add setter for connection property
- (void)setConnection:(SeafConnection *)connection {
    _connection = connection;
}

// Add setter method for seafFile
- (void)setSeafFile:(id<SeafPreView>)seafFile {    // If the same file, ignore
    if (_seafFile == seafFile) {
        return;
    }
    // Update the stored file
    _seafFile = seafFile;
    
    if ([self.seafFile isKindOfClass:[SeafFile class]]) {
        // Store previous loading state to determine if we need to update UI
        BOOL wasLoading = _seafFile && [_seafFile hasCache];
        BOOL willBeLoading = seafFile && ![seafFile hasCache];
        
        SeafFile *f = seafFile;
        Debug(@"[PhotoContent] Setting seafFile: %@, ooid: %@",
              seafFile.name,
              f.ooid ? f.ooid : @"nil (needs download)");
        
        // Update loading indicator based on new file state
        if (wasLoading && !willBeLoading) {
            // File was loading but now has loaded - hide indicator
            Debug(@"[PhotoContent] File now loaded, hiding indicator");
            [self hideLoadingIndicator];
        }
        else if (!wasLoading && willBeLoading) {
            Debug(@"[PhotoContent] New file needs download/processing, showing indicator");
            [self showLoadingIndicator];
        }
    }
    
    // If view is loaded, reload image with the new file
    if (self.isViewLoaded) {
        [self loadImage];
    }
}

// Add cleanup when the view is about to disappear
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    if (self.activityIndicator) {
        Debug(@"[PhotoContent] Cleaning up indicators in viewWillDisappear for %@", self.seafFile ? self.seafFile.name : self.photoURL);
        [self cleanupAllLoadingIndicators];
    }
}

// Method to prepare the view controller for reuse (called from gallery when recycling)
- (void)prepareForReuse {
    Debug(@"[PhotoContent] Preparing for reuse %@", self.seafFile ? self.seafFile.name : @"unknown");
    DebugZoom(@"[ZoomDebug] prepareForReuse BEFORE: file=%@, scrollView.bounds=%@, imageView.frame=%@, zoomScale=%.3f, contentInset=%@, contentSize=%@, hasImage=%d",
          self.seafFile ? self.seafFile.name : @"nil",
          NSStringFromCGRect(self.scrollView.bounds),
          NSStringFromCGRect(self.imageView.frame),
          self.scrollView.zoomScale,
          NSStringFromUIEdgeInsets(self.scrollView.contentInset),
          NSStringFromCGSize(self.scrollView.contentSize),
          self.imageView.image != nil);
    
    // Remove error view if it exists
    if (self.errorPlaceholderView) {
        [self.errorPlaceholderView removeFromSuperview];
        self.errorPlaceholderView = nil;
    }
    
    // Clean up Live Photo player view
    [self removeLivePhotoPlayerView];
    self.isMotionPhoto = NO;
    self.pendingAutoPreview = NO;
    self.isCurrentVisiblePage = NO;
    
    // Hide Live Photo icon
    [self hideLivePhotoIcon];

    // Cancel any ongoing image loading or download requests
    // Only if the image isn't already loaded
    if (!self.imageView.image || !self.seafFile || ![self.seafFile hasCache]) {
        [self cancelImageLoading];
    }
    
    // Clean up any existing UI elements
    [self cleanupAllLoadingIndicators];
    
    // Reset zoom scale and contentInset (suppress delegate callbacks)
    if (self.scrollView) {
        self.isConfiguringLayout = YES;
        self.scrollView.zoomScale = 1.0;
        self.scrollView.contentInset = UIEdgeInsetsZero;
        self.scrollView.contentOffset = CGPointZero;
        self.isConfiguringLayout = NO;
    }
    self.wasInZoomedState = NO;
    self.wasImmersiveBeforeZoom = NO;
    
    // Reset info view if needed
    if (self.infoVisible) {
        self.infoVisible = NO;
        self.infoView.hidden = YES;
    }
    
    // Reset placeholder/error image flag
    self.isDisplayingPlaceholderOrErrorImage = NO;
    
    DebugZoom(@"[ZoomDebug] prepareForReuse AFTER: file=%@, scrollView.bounds=%@, imageView.frame=%@, zoomScale=%.3f, contentInset=%@, contentSize=%@",
          self.seafFile ? self.seafFile.name : @"nil",
          NSStringFromCGRect(self.scrollView.bounds),
          NSStringFromCGRect(self.imageView.frame),
          self.scrollView.zoomScale,
          NSStringFromUIEdgeInsets(self.scrollView.contentInset),
          NSStringFromCGSize(self.scrollView.contentSize));
    Debug(@"[PhotoContent] View controller reset and ready for reuse");
}

// Cancel any ongoing image loading or download requests
- (void)cancelImageLoading {
    Debug(@"[PhotoContent] Canceling image loading for %@", self.seafFile ? self.seafFile.name : @"unknown");
    
    // Don't cancel if the image is already loaded and displayed
    if (self.imageView.image != nil && self.seafFile && [self.seafFile hasCache]) {
        Debug(@"[PhotoContent] Not canceling - image already displayed: %@", self.seafFile.name);
        // Still clean up any loading indicators
        [self cleanupAllLoadingIndicators];
        return;
    }
    // Cancel the SeafFile download task
    if (self.seafFile && [self.seafFile isKindOfClass:[SeafFile class]]) {
        // Cancel file download
        [(SeafFile *)self.seafFile cancelDownload];
        
        // Clean up any ongoing requests or operations
        [self.seafFile setDelegate:nil];
    }
    
    // Clean up loading indicators
    [self cleanupAllLoadingIndicators];
    
    Debug(@"[PhotoContent] Image loading canceled for %@", self.seafFile ? self.seafFile.name : @"unknown");
}

// Release the memory of the loaded image
- (void)releaseImageMemory {
    Debug(@"[PhotoContent] Releasing image memory for %@", self.seafFile ? self.seafFile.name : @"unknown");
    
    // Clear the error placeholder view if it exists
    if (self.errorPlaceholderView) {
        [self.errorPlaceholderView removeFromSuperview];
        self.errorPlaceholderView = nil;
    }

    // Clear the image data to free memory
    if (self.imageView) {
        self.imageView.image = nil;
        // Reset placeholder flag since we're clearing the image
        self.isDisplayingPlaceholderOrErrorImage = NO;
    }
        
    Debug(@"[PhotoContent] Image memory released for %@", self.seafFile ? self.seafFile.name : @"unknown");
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    // Patch §3.11.1: parent is now the gallery directly (the paging view is a
    // plain UIView, not a UIViewController). Only cancel loads if we're more
    // than 1 page away from the current page; the gallery already recycles
    // non-adjacent containers, so a viewDidDisappear here typically means we
    // were just kicked out of the alive window.
    UIViewController *parentVC = self.parentViewController;
    if ([parentVC isKindOfClass:[SeafPhotoGalleryViewController class]]) {
        SeafPhotoGalleryViewController *gallery = (SeafPhotoGalleryViewController *)parentVC;
        @try {
            NSUInteger currentPhotoIndex = gallery.currentIndex;
            NSUInteger thisIndex = self.pageIndex;
            if (thisIndex == NSNotFound) {
                Debug(@"[PhotoContent] viewDidDisappear with no pageIndex; canceling loads for %@", self.seafFile.name);
                [self cancelImageLoading];
                return;
            }
            NSInteger delta = labs((NSInteger)thisIndex - (NSInteger)currentPhotoIndex);
            if (delta > 1) {
                Debug(@"[PhotoContent] View far from current page (delta=%ld), canceling loads: %@",
                      (long)delta, self.seafFile.name);
                [self cancelImageLoading];
            } else {
                Debug(@"[PhotoContent] View still near current page (delta=%ld), keeping loads: %@",
                      (long)delta, self.seafFile.name);
            }
        } @catch (NSException *exception) {
            Debug(@"[PhotoContent] Exception when accessing gallery properties: %@", exception);
            [self cancelImageLoading];
        }
    } else {
        // Not currently in the gallery (e.g. being torn down) — cancel any downloads.
        Debug(@"[PhotoContent] View disappeared (no gallery parent): %@", self.seafFile.name);
        [self cancelImageLoading];
    }
}

// Add a new method for preloading images
- (void)preloadImage {
    // Only preload if we have a valid seafFile with an ooid
    if ([self.seafFile isKindOfClass:[SeafFile class]] && self.seafFile && [self.seafFile hasCache]) {
        if (!self.imageView.image) {
            Debug(@"[PhotoContent] Preloading image for %@", self.seafFile.name);
            
            // Load in background without affecting UI
            @weakify(self);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                @strongify(self);
                if (!self) return;
                [(SeafFile *)self.seafFile getImageWithCompletion:^(UIImage *image) {
                    if (image) {
                        // Store in memory but don't display yet
                        dispatch_async(dispatch_get_main_queue(), ^{
                            @strongify(self);
                            if (!self) return;
                            if (!self.imageView.image) {
                                self.imageView.image = image;
                                Debug(@"[PhotoContent] Image preloaded for %@", self.seafFile.name);
                            }
                        });
                    }
                }];
            });
        }
    }
}

// Add to viewWillAppear to ensure images are loaded when coming into view
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Decide background based on the chrome owner's authoritative state when
    // available — the legacy nav-bar inspection only catches the tap-toggle
    // path and the alpha-fade path; the gallery's `isChromeHidden` flag is
    // the single source of truth across both.
    BOOL chromeHidden = NO;
    if ([self.delegate respondsToSelector:@selector(photoContentViewControllerIsChromeHidden:)]) {
        chromeHidden = [self.delegate photoContentViewControllerIsChromeHidden:self];
    } else {
        UIViewController *parentVC = self.parentViewController;
        while (parentVC && ![parentVC isKindOfClass:[UINavigationController class]]) {
            parentVC = parentVC.parentViewController;
        }
        if ([parentVC isKindOfClass:[UINavigationController class]]) {
            UINavigationController *navController = (UINavigationController *)parentVC;
            chromeHidden = navController.navigationBarHidden ||
                           navController.navigationBar.alpha < 0.01;
        }
    }
    BOOL shouldBeBlackBackground = (chromeHidden && !self.infoVisible);

    // Set background color immediately based on inferred state
    if (shouldBeBlackBackground) {
        // Ensure the view is in the fullscreen state with black background
        self.view.backgroundColor = [UIColor blackColor];
        self.scrollView.backgroundColor = [UIColor blackColor];
        self.imageView.backgroundColor = [UIColor clearColor]; // Ensure image view is clear over black
        if (self.livePhotoPlayerView) {
            self.livePhotoPlayerView.backgroundColor = [UIColor blackColor];
        }
    } else {
        // Restore background to light mode - must explicitly set because VC may be reused
        // after being in view mode (black background), and viewDidLoad won't be called again
        self.view.backgroundColor = [UIColor colorWithRed:249/255.0 green:249/255.0 blue:249/255.0 alpha:1.0]; // #F9F9F9
        self.scrollView.backgroundColor = [UIColor colorWithRed:249/255.0 green:249/255.0 blue:249/255.0 alpha:1.0]; // #F9F9F9
        self.imageView.backgroundColor = [UIColor clearColor];
        if (self.livePhotoPlayerView) {
            self.livePhotoPlayerView.backgroundColor = [UIColor colorWithRed:249/255.0 green:249/255.0 blue:249/255.0 alpha:1.0]; // #F9F9F9
        }
    }
    // When a new view is about to appear during a transition, make sure layout is correct
    [self updateViewFramesForInfoVisibility:self.infoVisible];

    // Update info view if it's supposed to be visible
    if (self.infoVisible) {
        self.infoView.hidden = NO;
        [self updateInfoView];
    }

    // Make sure the image is loaded
    BOOL needsImageLoad = NO;
    
    if (!self.imageView.image) {
        // No image at all
        needsImageLoad = YES;
    } else if (self.isDisplayingPlaceholderOrErrorImage && self.seafFile && [self.seafFile hasCache]) {
        // If currently displaying a placeholder or error image, and seafFile has cache, need to reload
        needsImageLoad = YES;
    }
    
    DebugZoom(@"[ZoomDebug] viewWillAppear: file=%@, needsImageLoad=%d, hasImage=%d, isPlaceholder=%d, scrollView.bounds=%@, imageView.frame=%@, zoomScale=%.3f",
          self.seafFile ? self.seafFile.name : @"nil",
          needsImageLoad,
          self.imageView.image != nil,
          self.isDisplayingPlaceholderOrErrorImage,
          NSStringFromCGRect(self.scrollView.bounds),
          NSStringFromCGRect(self.imageView.frame),
          self.scrollView.zoomScale);
    
    if (needsImageLoad && self.seafFile) {
        Debug(@"[PhotoContent] Image needs loading in viewWillAppear (placeholder: %@), loading now: %@", 
              self.isDisplayingPlaceholderOrErrorImage ? @"YES" : @"NO", 
              self.seafFile.name);
        // If currently displaying an error, remove it before attempting to load again
        if (self.isDisplayingPlaceholderOrErrorImage && self.errorPlaceholderView) {
            [self.errorPlaceholderView removeFromSuperview];
            self.errorPlaceholderView = nil;
            // self.isDisplayingPlaceholderOrErrorImage = NO; // loadImage will reset this
        }
        [self loadImage];
    } else if (self.imageView.image) {
        // Image already loaded — ensure layout is correct by reconfiguring
        DebugZoom(@"[ZoomDebug] viewWillAppear: image already loaded, calling configureForImage to ensure correct layout");
        [self configureForImage:self.imageView.image];
    }
    
    // Ensure Live Photo badge visibility is correct based on chrome state.
    //
    // We must ask the gallery (the chrome owner) instead of inferring from
    // `navigationController.navigationBarHidden` alone, because the pinch-to
    // -zoom path only fades the nav bar's alpha to 0 without flipping
    // `navigationBarHidden`. Relying on the hidden flag here would make the
    // LIVE badge re-appear on top of a fully transparent nav bar.
    if (self.isMotionPhoto) {
        BOOL chromeHidden = NO;
        if ([self.delegate respondsToSelector:@selector(photoContentViewControllerIsChromeHidden:)]) {
            chromeHidden = [self.delegate photoContentViewControllerIsChromeHidden:self];
        } else {
            // Legacy fallback: best-effort using both navigationBarHidden
            // and alpha so we cover both code paths until the delegate is
            // upgraded.
            UIViewController *navParentVC = self.parentViewController;
            while (navParentVC && ![navParentVC isKindOfClass:[UINavigationController class]]) {
                navParentVC = navParentVC.parentViewController;
            }
            if ([navParentVC isKindOfClass:[UINavigationController class]]) {
                UINavigationController *navController = (UINavigationController *)navParentVC;
                chromeHidden = navController.navigationBarHidden ||
                               navController.navigationBar.alpha < 0.01;
            }
        }

        if (!chromeHidden && !self.infoVisible) {
            [self showLivePhotoIcon];
        } else {
            [self hideLivePhotoIcon];
        }
    } else {
        [self hideLivePhotoIcon];
    }
}

// Helper method to create the EXIF Camera Model row
- (CGFloat)createExifModelRow:(NSString *)cameraModel
                       inView:(UIView *)parentView
                    yPosition:(CGFloat)yPosition
               availableWidth:(CGFloat)availableWidth
                    modelFont:(UIFont *)modelFont
                    textColor:(UIColor *)textColor
                  cardPadding:(CGFloat)cardPadding
{
    if (!cameraModel || cameraModel.length == 0) return 0;

    UILabel *modelLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardPadding, yPosition, availableWidth - 2 * cardPadding, 0)];
    modelLabel.font = modelFont;
    modelLabel.textColor = textColor;
    modelLabel.text = cameraModel;
    [modelLabel sizeToFit]; // Adjust height
    CGRect modelFrame = modelLabel.frame;
    modelFrame.size.width = availableWidth - 2 * cardPadding; // Ensure it takes full width
    modelLabel.frame = modelFrame;
    [parentView addSubview:modelLabel];

    // Return height including bottom padding
    return modelLabel.frame.size.height + cardPadding;
}

// Helper method to create the EXIF Time and Dimensions rows
- (CGFloat)createExifTimeAndDimensionsRows:(NSString *)formattedTime
                                dimensions:(NSString *)dimensionsString
                                    inView:(UIView *)parentView
                                 yPosition:(CGFloat)yPosition
                            availableWidth:(CGFloat)availableWidth
                                mediumFont:(UIFont *)mediumFont
                                 textColor:(UIColor *)textColor
                               cardPadding:(CGFloat)cardPadding
{
    CGFloat currentY = yPosition;
    CGFloat rowHeight = 0;

    // Time Label
    if (formattedTime && ![formattedTime isEqualToString:@"-"]) {
        UILabel *timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardPadding, currentY, availableWidth - 2 * cardPadding, 0)];
        timeLabel.font = mediumFont;
        timeLabel.textColor = textColor;
        timeLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Capture Time • %@", @"Seafile"), formattedTime];
        [timeLabel sizeToFit];
        CGRect timeFrame = timeLabel.frame;
        timeFrame.size.width = availableWidth - 2 * cardPadding;
        timeLabel.frame = timeFrame;
        [parentView addSubview:timeLabel];
        currentY += timeLabel.frame.size.height + cardPadding - 2; // Adjust spacing
        rowHeight += timeLabel.frame.size.height + cardPadding - 2;
    }

    // Dimensions Label
    if (dimensionsString && ![dimensionsString isEqualToString:@"-"]) {
        UILabel *dimLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardPadding, currentY, availableWidth - 2 * cardPadding, 0)];
        dimLabel.font = mediumFont;
        dimLabel.textColor = textColor;
        dimLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Dimensions • %@", @"Seafile"), dimensionsString];

        [dimLabel sizeToFit];
        CGRect dimFrame = dimLabel.frame;
        dimFrame.size.width = availableWidth - 2 * cardPadding;
        dimLabel.frame = dimFrame;
        [parentView addSubview:dimLabel];
        rowHeight += dimLabel.frame.size.height;
    }

    return rowHeight;
}

#pragma mark - Immersive Viewing Mode (Zoom-triggered)

/// Transitions ContentVC's own appearance to immersive mode (black backgrounds, hide Live badge).
/// Called when zoom scale first crosses into zoomed-in territory.
- (void)enterImmersiveAppearanceAnimated:(BOOL)animated {
    UIColor *blackColor = [UIColor blackColor];
    void (^changes)(void) = ^{
        self.view.backgroundColor = blackColor;
        self.scrollView.backgroundColor = blackColor;
        if (self.livePhotoPlayerView) {
            self.livePhotoPlayerView.backgroundColor = blackColor;
        }
    };
    
    // Idempotent guard: when chrome was already immersive before this zoom
    // (i.e. user tap-toggled into fullscreen first), the appearance is already
    // black — apply state without playing another fade to avoid a visible flash.
    BOOL skipAnimation = self.wasImmersiveBeforeZoom;
    if (animated && !skipAnimation) {
        [UIView animateWithDuration:0.15 animations:changes];
    } else {
        changes();
    }
    [self hideLivePhotoIconAnimated:(animated && !skipAnimation)];
}

/// Transitions ContentVC's own appearance back to normal mode (light backgrounds, show Live badge).
/// Called when zoom returns to minimum scale.
- (void)exitImmersiveAppearanceAnimated:(BOOL)animated {
    UIColor *normalBgColor = [UIColor colorWithRed:249/255.0 green:249/255.0 blue:249/255.0 alpha:1.0]; // #F9F9F9
    void (^changes)(void) = ^{
        self.view.backgroundColor = normalBgColor;
        self.scrollView.backgroundColor = normalBgColor;
        if (self.livePhotoPlayerView) {
            self.livePhotoPlayerView.backgroundColor = normalBgColor;
        }
    };
    
    if (animated) {
        [UIView animateWithDuration:0.15 animations:changes];
    } else {
        changes();
    }
    if (self.isMotionPhoto) {
        [self showLivePhotoIconAnimated:animated];
    }
}

#pragma mark - Image Layout

// Configure imageView frame and zoom scales based on the image's actual size
// and the current scrollView bounds. This is the core layout method that replaces
// the old updateScrollViewContentSize and updateZoomScalesForSize: methods.
- (void)configureForImage:(UIImage *)image {
    if (!image) {
        DebugZoom(@"[ZoomDebug] configureForImage: SKIPPED (image is nil), file=%@", self.seafFile ? self.seafFile.name : @"nil");
        return;
    }
    
    CGSize imageSize  = image.size;  // Logical point size (e.g. 4032×3024)
    CGSize boundsSize = self.scrollView.bounds.size;
    
    DebugZoom(@"[ZoomDebug] configureForImage: file=%@, imageSize=%@, scrollView.bounds=%@, scrollView.frame=%@",
          self.seafFile ? self.seafFile.name : @"nil",
          NSStringFromCGSize(imageSize),
          NSStringFromCGSize(boundsSize),
          NSStringFromCGRect(self.scrollView.frame));
    
    if (imageSize.width == 0 || imageSize.height == 0 || boundsSize.width == 0 || boundsSize.height == 0) {
        DebugZoom(@"[ZoomDebug] configureForImage: SKIPPED (zero dimensions)");
        return;
    }
    
    // ① Calculate Aspect Fit scale
    CGFloat widthRatio  = boundsSize.width  / imageSize.width;
    CGFloat heightRatio = boundsSize.height / imageSize.height;
    CGFloat fitScale    = MIN(widthRatio, heightRatio);

    // ② Compute the precise Aspect Fit dimensions
    CGFloat fitWidth  = imageSize.width  * fitScale;
    CGFloat fitHeight = imageSize.height * fitScale;

    // ③ CRITICAL — reset zoomScale to 1.0 BEFORE assigning imageView.frame.
    //
    // UIScrollView treats imageView.bounds (not imageView.frame) as the unit-scale
    // (zoomScale==1.0) size, and renders imageView.frame == imageView.bounds * zoomScale.
    // Assigning imageView.frame directly while zoomScale != 1.0 causes UIScrollView
    // to back-compute imageView.bounds = frame / zoomScale, which permanently
    // shrinks the image's intrinsic size by a factor of the current zoom.
    //
    // This used to happen when viewDidLayoutSubviews fired mid-pinch (e.g. while
    // entering immersive mode at zoomScale=3.247), polluting imageView.bounds and
    // making the image appear ~1/3 of its proper Aspect Fit size after the user
    // pinched back to 1.0. By forcing zoomScale=1.0 first, the subsequent
    // imageView.frame assignment lands at the correct unit-scale size.
    //
    // We also need minimumZoomScale<=1.0 BEFORE this reset, otherwise UIScrollView
    // clamps the new zoomScale into the existing min/max range. Skip the assignment
    // entirely when already at 1.0 to avoid spurious delegate work.
    self.isConfiguringLayout = YES;
    self.scrollView.minimumZoomScale = 1.0;
    if (fabs(self.scrollView.zoomScale - 1.0) > 0.001) {
        self.scrollView.zoomScale = 1.0;
    }
    self.isConfiguringLayout = NO;

    // ④ Now that zoomScale==1.0, frame assignment is unambiguous.
    self.imageView.frame = CGRectMake(0, 0, fitWidth, fitHeight);

    // ⑤ Set scrollView's contentSize to match
    self.scrollView.contentSize = CGSizeMake(fitWidth, fitHeight);

    // ⑥ Maximum zoom scale.
    // Dynamic max zoom — high-res images can zoom to pixel level, low-res at least 3x.
    // For wide / panoramic images, also ensure max is large enough to let double-tap
    // fill the screen height (clamped by the same 10x memory cap).
    CGFloat maxByResolution = 1.0 / fitScale;  // Scale needed to show original pixels
    CGFloat heightFillScale = (fitHeight > 0 && fitHeight < boundsSize.height)
        ? (boundsSize.height / fitHeight)
        : 0.0;
    CGFloat maxScale = MAX(MAX(maxByResolution, 3.0), heightFillScale);
    maxScale = MIN(maxScale, 10.0); // Cap at 10x to limit memory
    self.scrollView.maximumZoomScale = maxScale;
    
    // ⑦ Center the image using contentInset
    [self centerImageInScrollViewForReason:@"configureForImage"];

    DebugZoom(@"[ZoomDebug] configureForImage DONE: fitScale=%.4f, imageView.frame=%@, contentSize=%@, contentInset=%@, zoomRange=[%.2f, %.2f]",
          fitScale,
          NSStringFromCGRect(self.imageView.frame),
          NSStringFromCGSize(self.scrollView.contentSize),
          NSStringFromUIEdgeInsets(self.scrollView.contentInset),
          self.scrollView.minimumZoomScale,
          self.scrollView.maximumZoomScale);
}

// Center the imageView within the scrollView using contentInset.
// This replaces the old approach of manually setting imageView.center in scrollViewDidZoom:.
// Using contentInset is how iOS system Photos does it — it doesn't interfere with
// contentOffset semantics and works naturally with bounce/deceleration.
//
// `reason` is REQUIRED: every call site must pass a short tag identifying who
// is asking us to re-center. The tag shows up verbatim in the [ZoomBug]
// centerImage logs, so when the layout pipeline fans this out an unexpected
// number of times during a chrome animation / dismiss-drag interaction we
// can identify the source from logs alone, instead of bisecting state. See
// the analysis transcript "Photo gallery zoom flicker debugging" for context.
// There is no zero-argument convenience overload — please don't add one.
- (void)centerImageInScrollViewForReason:(NSString *)reason {
    CGSize boundsSize  = self.scrollView.bounds.size;
    CGSize contentSize = self.scrollView.contentSize;

    CGFloat verticalPadding   = MAX(0, (boundsSize.height - contentSize.height) / 2.0);
    CGFloat horizontalPadding = MAX(0, (boundsSize.width  - contentSize.width)  / 2.0);

    UIEdgeInsets oldInset  = self.scrollView.contentInset;
    CGPoint      oldOffset = self.scrollView.contentOffset;
    CGFloat      zoomScale = self.scrollView.zoomScale;

    self.scrollView.contentInset = UIEdgeInsetsMake(
        verticalPadding, horizontalPadding,
        verticalPadding, horizontalPadding
    );

    UIEdgeInsets newInset  = self.scrollView.contentInset;
    CGPoint      newOffset = self.scrollView.contentOffset; // UIScrollView may clamp here

    Debug(@"[ZoomBug] centerImage reason=%@ zoom=%.4f bounds=%@ contentSize=%@ "
          @"inset:%@ -> %@ offset:%@ -> %@%@",
          reason,
          zoomScale,
          NSStringFromCGSize(boundsSize),
          NSStringFromCGSize(contentSize),
          NSStringFromUIEdgeInsets(oldInset),
          NSStringFromUIEdgeInsets(newInset),
          NSStringFromCGPoint(oldOffset),
          NSStringFromCGPoint(newOffset),
          CGPointEqualToPoint(oldOffset, newOffset) ? @"" : @" [OFFSET CHANGED BY INSET WRITE]");
}

// Legacy compatibility — kept for callsites that still reference these methods
- (void)updateScrollViewContentSize {
    [self configureForImage:self.imageView.image];
}

- (void)updateZoomScalesForSize:(CGSize)size {
    [self configureForImage:self.imageView.image];
}

#pragma mark - Motion Photo / Live Photo Support

// Set to 1 to enable Motion Photo / Live Photo feature, set to 0 to disable
#define ENABLE_MOTION_PHOTO_FEATURE 1

- (void)checkAndSetupMotionPhotoWithData:(NSData *)data {
#if !ENABLE_MOTION_PHOTO_FEATURE
    // Motion Photo / Live Photo playback feature is temporarily disabled, code preserved for future restoration
    self.isMotionPhoto = NO;
    [self hideLivePhotoIcon];
    return;
#endif
    
    if (!data || data.length == 0) {
        self.isMotionPhoto = NO;
        [self hideLivePhotoIcon];
        return;
    }
    
    // First, run detailed analysis for debugging purposes
    NSString *fileName = self.seafFile ? self.seafFile.name : @"Unknown";
    NSString *fileExt = [fileName.pathExtension lowercaseString];
    
    // Only analyze HEIC/HEIF files that might be Motion Photos
    if ([fileExt isEqualToString:@"heic"] || [fileExt isEqualToString:@"heif"]) {
        Debug(@"[PhotoContent] Running Motion Photo analysis for: %@", fileName);
        [SeafMotionPhotoExtractor analyzeAndLogMotionPhotoIssues:data fileName:fileName];
    }
    
    // Check if this is a Motion Photo
    BOOL isMotionPhoto = [SeafMotionPhotoExtractor isMotionPhoto:data];
    self.isMotionPhoto = isMotionPhoto;
    
    if (!isMotionPhoto) {
        // Remove any existing live photo player view
        [self removeLivePhotoPlayerView];
        [self hideLivePhotoIcon];
        Debug(@"[PhotoContent] Not a Motion Photo: %@", self.seafFile.name);
        return;
    }
    
    Debug(@"[PhotoContent] Motion Photo detected: %@", self.seafFile.name);
    
    // Show Live Photo icon
    [self showLivePhotoIcon];
    
    // Setup Live Photo Player View
    [self setupLivePhotoPlayerViewWithData:data];
}

- (void)setupLivePhotoPlayerViewWithData:(NSData *)data {
    // Remove any existing player view first (but don't hide the badge)
    if (self.livePhotoPlayerView) {
        [self.livePhotoPlayerView cleanup];
        [self.livePhotoPlayerView removeFromSuperview];
        self.livePhotoPlayerView = nil;
    }
    
    // Create and configure the live photo player view
    // Use imageView.bounds since livePhotoPlayerView will be a subview of imageView
    self.livePhotoPlayerView = [[SeafLivePhotoPlayerView alloc] initWithFrame:self.imageView.bounds];
    self.livePhotoPlayerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.livePhotoPlayerView.delegate = self;
    self.livePhotoPlayerView.imageContentMode = UIViewContentModeScaleToFill; // Frame is precisely Aspect Fit sized
    self.livePhotoPlayerView.showLiveBadge = NO;  // Disable built-in badge, we use our own Live Photo badge
    self.livePhotoPlayerView.longPressToPlayEnabled = YES;
    
    // Load the Motion Photo data
    [self.livePhotoPlayerView loadMotionPhotoFromData:data];
    
    // Add as subview of imageView (the zoom target returned by viewForZoomingInScrollView:)
    // so it naturally participates in the scroll view's zoom transform.
    // Previously it was added to scrollView directly and imageView was hidden,
    // causing zoom to only affect the hidden imageView while livePhotoPlayerView stayed static.
    self.imageView.userInteractionEnabled = YES;  // Enable touch for long-press gesture on livePhotoPlayerView
    [self.imageView addSubview:self.livePhotoPlayerView];
    
    // Keep imageView visible - livePhotoPlayerView overlays it
    self.imageView.hidden = NO;
    
    // Ensure badge is visible and on top
    [self showLivePhotoIcon];
    
    Debug(@"[PhotoContent] Live Photo Player View setup complete for: %@", self.seafFile.name);
    
    // If this page is the gallery's current visible page and a silent
    // auto-preview was queued before the player was ready, trigger it now.
    if (self.isCurrentVisiblePage && self.pendingAutoPreview) {
        self.pendingAutoPreview = NO;
        SeafLivePhotoPlayerView *player = self.livePhotoPlayerView;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (player == self.livePhotoPlayerView && self.isCurrentVisiblePage) {
                [player playMuted];
            }
        });
    }
}

- (void)removeLivePhotoPlayerView {
    if (self.livePhotoPlayerView) {
        [self.livePhotoPlayerView cleanup];
        [self.livePhotoPlayerView removeFromSuperview];
        self.livePhotoPlayerView = nil;
        
        // Restore imageView state
        self.imageView.hidden = NO;
        self.imageView.userInteractionEnabled = NO;  // Restore default UIImageView behavior
    }
    
    // Hide the Live Photo badge since we're removing the Motion Photo player
    // This indicates we're switching away from a Motion Photo
    [self hideLivePhotoIcon];
    self.isMotionPhoto = NO;
    self.pendingAutoPreview = NO;
}

#pragma mark - SeafLivePhotoPlayerViewDelegate

- (void)livePhotoPlayerViewDidStartPlaying:(SeafLivePhotoPlayerView *)playerView {
    Debug(@"[PhotoContent] Live Photo started playing: %@", self.seafFile.name);
    // Badge remains visible during playback - no action needed
}

- (void)livePhotoPlayerViewDidFinishPlaying:(SeafLivePhotoPlayerView *)playerView {
    Debug(@"[PhotoContent] Live Photo finished playing: %@", self.seafFile.name);
    // Badge remains visible - no action needed
}

- (void)livePhotoPlayerView:(SeafLivePhotoPlayerView *)playerView didFailWithError:(NSError *)error {
    Debug(@"[PhotoContent] Live Photo playback failed: %@, error: %@", self.seafFile.name, error);
    // Badge remains visible - no action needed
}

#pragma mark - Gallery Visibility Notifications

- (void)didBecomeCurrentVisiblePage {
    self.isCurrentVisiblePage = YES;
    
    // If the live photo player is already in place, kick off a silent
    // auto-preview right away (mirrors iOS Photos behavior on swipe).
    // Otherwise queue the request so it runs as soon as
    // setupLivePhotoPlayerViewWithData: finishes initializing the player.
    if (self.livePhotoPlayerView && self.livePhotoPlayerView.hasMotionPhotoContent) {
        self.pendingAutoPreview = NO;
        [self.livePhotoPlayerView playMuted];
    } else {
        self.pendingAutoPreview = YES;
    }
}

- (void)didResignCurrentVisiblePage {
    self.isCurrentVisiblePage = NO;
    self.pendingAutoPreview = NO;
    
    if (self.livePhotoPlayerView && self.livePhotoPlayerView.isPlaying) {
        [self.livePhotoPlayerView stop];
    }
}

@end
