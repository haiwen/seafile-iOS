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

@class SeafFile;
@protocol SeafPreView;

// Define a protocol for retry requests
@protocol SeafPhotoContentDelegate <NSObject>
- (void)photoContentViewControllerRequestsRetryForFile:(id<SeafPreView>)file atIndex:(NSUInteger)index;
@end

NS_ASSUME_NONNULL_BEGIN

@interface SeafPhotoContentViewController : UIViewController <UIScrollViewDelegate>
/// The photo URL to display
@property (nonatomic, strong) NSURL *photoURL;

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

/// Updates scroll view content size to match image size
- (void)updateScrollViewContentSize;

/// Updates scroll view zoom scales for given size
- (void)updateZoomScalesForSize:(CGSize)size;
@end

NS_ASSUME_NONNULL_END
