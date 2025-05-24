//
//  SeafPhotoGalleryViewController.m
//  seafileApp
//
//  Created by henry on 2025/4/17.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import "SeafPhotoGalleryViewController.h"
#import "SeafNavigationBarStyler.h"
#import "SeafPhotoContentViewController.h"
#import "Constants.h"
#import "SeafFile.h"
#import "SVProgressHUD.h"
#import "UIViewController+Extend.h"
#import <Photos/Photos.h>
#import "Debug.h"
#import "SeafPhoto.h"
#import "SeafDataTaskManager.h"
#import "SeafConnection.h"
#import "SeafGlobal.h"
#import "SeafPhotoThumb.h"
#import <ImageIO/ImageIO.h>
#import "SeafPGThumbnailCell.h" // Added import
#import "SeafPGThumbnailCellViewModel.h" // Added import

// Define an enum for toolbar button types
typedef NS_ENUM(NSInteger, SeafPhotoToolbarButtonType) {
    SeafPhotoToolbarButtonTypeDownload,
    SeafPhotoToolbarButtonTypeDelete,
    SeafPhotoToolbarButtonTypeInfo,
    SeafPhotoToolbarButtonTypeStar,
    SeafPhotoToolbarButtonTypeShare
};

// Custom collection view layout to support different spacing between selected and unselected items
@interface SeafThumbnailFlowLayout : UICollectionViewFlowLayout
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, assign) CGFloat defaultSpacing;
@property (nonatomic, assign) CGFloat spacingAroundSelectedItem;
@property (nonatomic, assign) BOOL isDragging; // Add property to track dragging state
@end

@implementation SeafThumbnailFlowLayout

- (instancetype)init {
    if (self = [super init]) {
        _selectedIndex = 0;
        _defaultSpacing = 4.0; // Increased from 1.0
        _spacingAroundSelectedItem = 13.0;
        _isDragging = NO; // Initialize dragging state
    }
    return self;
}

// Override layout method to customize spacing between items
- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    // First, get the layout attributes from the superclass
    NSArray<UICollectionViewLayoutAttributes *> *attributes = [super layoutAttributesForElementsInRect:rect];
    
    // Create a copy to modify
    NSArray<UICollectionViewLayoutAttributes *> *copiedAttributes = [[NSArray alloc] initWithArray:attributes copyItems:YES];
    
    // Process each layout attribute
    for (int i = 1; i < copiedAttributes.count; i++) {
        UICollectionViewLayoutAttributes *currentAttr = copiedAttributes[i];
        UICollectionViewLayoutAttributes *prevAttr = copiedAttributes[i-1];
        
        // Determine which spacing to use
        CGFloat spacing = _defaultSpacing;
        
        // If the current or previous item is the selected item and not dragging, use larger spacing
        if (!_isDragging && (currentAttr.indexPath.item == _selectedIndex || prevAttr.indexPath.item == _selectedIndex)) {
            spacing = _spacingAroundSelectedItem;
        }
        
        // Calculate the new X position
        CGFloat originX = CGRectGetMaxX(prevAttr.frame) + spacing;
        
        // Update the layout attribute
        CGRect frame = currentAttr.frame;
        frame.origin.x = originX;
        currentAttr.frame = frame;
    }
    
    return copiedAttributes;
}

// Must implement this method to ensure layout is recalculated during scrolling
- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return YES;
}

@end

@interface SeafPhotoGalleryViewController ()
  <UIPageViewControllerDataSource,
   UIPageViewControllerDelegate,
   UICollectionViewDataSource,
   UICollectionViewDelegate,
   UICollectionViewDelegateFlowLayout,
   UIScrollViewDelegate,
   SeafDentryDelegate>

//@property (nonatomic, strong) UIPageViewController     *pageVC;
@property (nonatomic, strong) NSArray<NSDictionary *>  *infoModels;
@property (nonatomic, assign) NSUInteger                currentIndex;

// UI Components
@property (nonatomic, strong) UICollectionView         *thumbnailCollection;
@property (nonatomic, strong) UIView                   *toolbarView;
@property (nonatomic, assign) CGFloat                   thumbnailHeight; // Thumbnail height
@property (nonatomic, strong) UIView                   *leftThumbnailOverlay; // Added
@property (nonatomic, strong) UIView                   *rightThumbnailOverlay; // Added

/// Tracks whether it's in fullscreen or detail expanded state
@property (nonatomic, assign) BOOL                      infoVisible;

// Currently displayed content view controller
@property (nonatomic, strong) SeafPhotoContentViewController *currentContentVC;

// Add properties similar to SeafDetailViewController to support SeafFile loading and caching
@property (nonatomic, strong) id<SeafPreView>          preViewItem;     // Current file being viewed
@property (nonatomic, strong) NSArray<id<SeafPreView>> *preViewItems;   // Array of all file items
@property (nonatomic, weak) UIViewController<SeafDentryDelegate> *masterVc; // Master view controller

// Add property to track the range of loaded images
@property (nonatomic, assign) NSRange loadedImagesRange;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SeafPhotoContentViewController *> *contentVCCache;

// Add download progress dictionary to track progress for each image
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *downloadProgressDict;

// Add loading status dictionary to track loading state for each image (whether download is needed)
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *loadingStatusDict;

// Add active controller set to track currently loading or loaded controllers
@property (nonatomic, strong) NSMutableSet<NSNumber *> *activeControllers;

// Private method declarations
- (void)showDownloadError:(NSString *)fileName;

@end

@implementation SeafPhotoGalleryViewController

// Initialization method using SeafFile objects
- (instancetype)initWithPhotos:(NSArray<id<SeafPreView>> *)files
                   currentItem:(id<SeafPreView>)currentItem
                        master:(UIViewController<SeafDentryDelegate> *)masterVC {
    if (self = [super init]) {
        // Save all photo files
        _preViewItems = files;
        // Current photo being viewed
        _preViewItem = currentItem;
        // Save reference to master view controller
        _masterVc = masterVC;
        // Set the starting index
        _currentIndex = [files indexOfObject:currentItem];
        _infoVisible = NO;
        _contentVCCache = [NSMutableDictionary dictionary];
        // Initialize the active controller set
        _activeControllers = [NSMutableSet set];
        
        // Initialize active controllers with current index and its neighbors
        [_activeControllers addObject:@(_currentIndex)];
        if (_currentIndex > 0) {
            [_activeControllers addObject:@(_currentIndex - 1)];
        }
        if (_currentIndex + 1 < files.count) {
            [_activeControllers addObject:@(_currentIndex + 1)];
        }
        
        // Initialize loading range to the current index and its neighbors
        [self updateLoadedImagesRangeForIndex:_currentIndex];
        
        // Initialize data
        NSMutableArray *infos = [NSMutableArray arrayWithCapacity:files.count];
        
        // First prepare basic information, the files will actually be loaded in viewDidLoad
        for (id<SeafPreView> file in files) {
            // Prepare basic information for display
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            [info setObject:file.name forKey:@"Name"];
            [info setObject:[NSString stringWithFormat:@"%lld", file.filesize] forKey:@"Size"];
            [infos addObject:info];
        }
        
        // Save information for compatibility with the old implementation
        _infoModels = infos;
        
        // Initialize download progress and loading status dictionaries
        _downloadProgressDict = [NSMutableDictionary dictionary];
        _loadingStatusDict = [NSMutableDictionary dictionary];
    }
    return self;
}

// Update the range of images to load
- (void)updateLoadedImagesRangeForIndex:(NSUInteger)index {
    // Ensure the index is within valid range
    if (index >= self.preViewItems.count) return;
    
    // Calculate loading range: one image before and after current index (or maximum available range)
    NSInteger startIndex = MAX(0, (NSInteger)index - 1);
    NSInteger endIndex = MIN(self.preViewItems.count - 1, index + 1);
    NSUInteger length = endIndex - startIndex + 1;
    
    // Update loading range
    _loadedImagesRange = NSMakeRange(startIndex, length);
    
    Debug(@"Updated loaded range to %@ around index %ld", NSStringFromRange(_loadedImagesRange), (long)index);
}

// Check if an image at a specific index should be loaded
- (BOOL)shouldLoadImageAtIndex:(NSUInteger)index {
    return NSLocationInRange(index, self.loadedImagesRange);
}

// Load the image at the specified index (only when needed)
- (void)loadImageAtIndex:(NSUInteger)index {
    if (![self shouldLoadImageAtIndex:index]) {
        Debug(@"Skipping loading image at index %ld (not in load range)", (long)index);
        return;
    }
    
    // Check if the file at this index needs to be loaded
    if (self.preViewItems && index < self.preViewItems.count) {
        id<SeafPreView> file = self.preViewItems[index];
        
        // Make sure the file has this controller set as its delegate
        if ([file isKindOfClass:[SeafFile class]]) {
            SeafFile *seafFile = (SeafFile *)file;
            // Check if we need to set the delegate
            if (seafFile.delegate != self) {
                Debug(@"[Gallery] Setting self as delegate for file %@", seafFile.name);
                seafFile.delegate = self;
            }
        }
        
        // If file doesn't have cache and URL is not set, load it
        if (!file.hasCache && file.previewItemURL == nil) {
            Debug(@"[Gallery] Starting to load image at index %ld: %@", (long)index, file.name);
            [file load:self force:NO];
        } else {
            // File is available, update the content view controller with seafFile
            NSNumber *key = @(index);
            SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:key];
            
            if (vc) {
                vc.seafFile = file; // Directly assign the id<SeafPreView> object

                if ([file isKindOfClass:[SeafFile class]]) {
                    SeafFile *specificFile = (SeafFile *)file;
                    Debug(@"[Gallery] Updating VC with SeafFile: %@, ooid: %@", specificFile.name, specificFile.ooid ? specificFile.ooid : @"nil");
                    vc.connection = specificFile.connection;
                }
            }
        }
    }
}

// Load all images in the current range
- (void)loadImagesInCurrentRange {
    if (_loadedImagesRange.length == 0) return;
    
    // First load the current image and its neighbors (one image before and after, total 3 images)
    NSUInteger currentIndex = self.currentIndex;
    [self loadImageAtIndex:currentIndex]; // Load the current image first
    
    // If there is an image to the left, preload the left image
    if (currentIndex > 0 && currentIndex - 1 >= _loadedImagesRange.location) {
        [self loadImageAtIndex:currentIndex - 1];
    }
    
    // If there is an image to the right, preload the right image
    if (currentIndex + 1 < self.preViewItems.count && currentIndex + 1 < NSMaxRange(_loadedImagesRange)) {
        [self loadImageAtIndex:currentIndex + 1];
    }
    
    // Then load the rest of the images in the range
    for (NSUInteger i = _loadedImagesRange.location; i < NSMaxRange(_loadedImagesRange); i++) {
        // Skip the current image and its neighbors
        if (i == currentIndex || i == currentIndex - 1 || i == currentIndex + 1) continue;
        
        [self loadImageAtIndex:i];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;

    // Determine title setting method based on whether SeafFile is initialized
    NSString *titleText;
    
    if (self.preViewItem) {
        titleText = self.preViewItem.name;
    } else {
        titleText = NSLocalizedString(@"View Photos", @"Seafile");
    }

    // Create custom title view using styling utility
    UILabel *titleLabel = [SeafNavigationBarStyler createCustomTitleViewWithText:titleText
                                                            maxWidthPercentage:0.7
                                                                 viewController:self];
    self.navigationItem.titleView = titleLabel;
    
    // Create back button using styling utility, set to gray
    UIColor *grayColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0]; // Medium gray
    self.navigationItem.leftBarButtonItem = [SeafNavigationBarStyler createBackButtonWithTarget:self
                                                                                       action:@selector(dismissGallery)
                                                                                        color:grayColor];
    
    // Set up page view controller and thumbnail strip
    [self setupPageViewController];
    [self setupThumbnailStrip];
    
    [self setupToolbar];
    [self addSwipeGestures];
    
    // Initialize download progress dictionary
    self.downloadProgressDict = [NSMutableDictionary dictionary];
    
    // Initialize loading status dictionary
    self.loadingStatusDict = [NSMutableDictionary dictionary];
    
    // Initialize active controllers
    [self updateActiveControllersForIndex:self.currentIndex];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // Position the thumbnail collection and toolbar at the bottom of the screen
    CGRect bounds = self.view.bounds;
    CGFloat stripHeight = 45; // Use the fixed strip height
    CGFloat toolbarHeight = 44;
    CGFloat safeAreaBottom = 0;
    
    if (@available(iOS 11.0, *)) {
        safeAreaBottom = self.view.safeAreaInsets.bottom;
    }
    
    // Adjust the location of the thumbnail collection
    CGRect thumbnailFrame = CGRectMake(0,
                                      bounds.size.height - stripHeight - toolbarHeight - safeAreaBottom, // Use stripHeight
                                      bounds.size.width,
                                      stripHeight); // Use stripHeight
    self.thumbnailCollection.frame = thumbnailFrame;
    
    // Make sure page view controller fills the available space
    self.pageVC.view.frame = bounds;
    
    // Toolbar always stays at the bottom, including safe area
    CGRect toolbarFrame = CGRectMake(0,
                                    bounds.size.height - toolbarHeight - safeAreaBottom,
                                    bounds.size.width,
                                    toolbarHeight + safeAreaBottom); // Include safe area in height
    self.toolbarView.frame = toolbarFrame;

    // Position overlays for thumbnailCollection
    // CGFloat overlayWidth = 25.0; // This will be used in the new helper method
    // CGRect tcFrame = self.thumbnailCollection.frame; // This will be used in the new helper method

    // // The following is replaced by the new helper method call
    // self.leftThumbnailOverlay.frame = CGRectMake(tcFrame.origin.x,
    //                                              tcFrame.origin.y,
    //                                              overlayWidth,
    //                                              tcFrame.size.height);
    // self.rightThumbnailOverlay.frame = CGRectMake(CGRectGetMaxX(tcFrame) - overlayWidth,
    //                                               tcFrame.origin.y,
    //                                               overlayWidth,
    //                                               tcFrame.size.height);
    // // Update gradient layer frames
    // if (self.leftThumbnailOverlay.layer.sublayers.count > 0) {
    //     CAGradientLayer *leftSubGradient = (CAGradientLayer *)self.leftThumbnailOverlay.layer.sublayers.firstObject;
    //     if ([leftSubGradient isKindOfClass:[CAGradientLayer class]]) {
    //         leftSubGradient.frame = self.leftThumbnailOverlay.bounds;
    //     }
    // }
    // if (self.rightThumbnailOverlay.layer.sublayers.count > 0) {
    //     CAGradientLayer *rightSubGradient = (CAGradientLayer *)self.rightThumbnailOverlay.layer.sublayers.firstObject;
    //     if ([rightSubGradient isKindOfClass:[CAGradientLayer class]]) {
    //         rightSubGradient.frame = self.rightThumbnailOverlay.bounds;
    //     }
    // }

    [self synchronizeOverlayFramesAndVisibilityWithThumbnailCollectionFrame:self.thumbnailCollection.frame isAnimatingReveal:NO];

    [self.view bringSubviewToFront:self.leftThumbnailOverlay];
    [self.view bringSubviewToFront:self.rightThumbnailOverlay];

    // [self updateThumbnailOverlaysVisibility]; // This is now called by the helper method
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    // Perform actions during the rotation animation
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // Force layout update
        [self.view setNeedsLayout];
        
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // This will be called after the rotation animation completes
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.currentIndex < self.thumbnailCollection.numberOfSections) { // Check if index is valid
        [self.thumbnailCollection scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:self.currentIndex inSection:0]
                                       atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                               animated:YES];
            }
        });
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Ensure the navigation bar is visible
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    
    // Use styling utility to set navigation bar style
    [SeafNavigationBarStyler applyStandardAppearanceToNavigationController:self.navigationController];
}

#pragma mark - Layout Subviews
- (void)setupPageViewController {
    // Create page view controller
    self.pageVC = [[UIPageViewController alloc] initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll
        navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal
                      options:nil];
    
    // Set data source and delegate
    self.pageVC.dataSource = self;
    self.pageVC.delegate = self;
    
    // Set page view controller's view
    self.pageVC.view.frame = self.view.bounds;
    [self.view addSubview:self.pageVC.view];
    
    // Set the first content view controller
    if (self.preViewItems.count > 0 && self.currentIndex < self.preViewItems.count) {
        // Ensure the current, left, and right images will be loaded
        [self updateLoadedImagesRangeForIndex:self.currentIndex];
        [self loadImagesInCurrentRange];
        
        // Get the content view controller for the current index
        SeafPhotoContentViewController *contentVC = [self viewControllerAtIndex:self.currentIndex];
        self.currentContentVC = contentVC;
        
        [self.pageVC setViewControllers:@[contentVC]
                          direction:UIPageViewControllerNavigationDirectionForward
                           animated:NO
                         completion:nil];
    }

    // Add as child view controller
    [self addChildViewController:self.pageVC];
    [self.pageVC didMoveToParentViewController:self];
}

- (void)setupThumbnailStrip {
    // Set thumbnail height
    self.thumbnailHeight = 42; // Thumbnail height is 42
    
    // Create custom flow layout
    SeafThumbnailFlowLayout *layout = [[SeafThumbnailFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.selectedIndex = self.currentIndex;
    layout.defaultSpacing = 4.0;        // Spacing between unselected items is 3
    layout.spacingAroundSelectedItem = 13.0; // Spacing between selected and unselected items is 12
    layout.minimumLineSpacing = 4.0; // Changed from 1.0
    layout.minimumInteritemSpacing = 4.0; // Changed from 1.0
    layout.sectionInset = UIEdgeInsetsMake(1.5, 10, 1.5, 10); // Collection view inset
    
    // Create collection view
    CGFloat stripHeight = 45; // Total height is fixed at 45
    CGRect frame = CGRectMake(0, self.view.bounds.size.height - stripHeight, self.view.bounds.size.width, stripHeight);
    self.thumbnailCollection = [[UICollectionView alloc] initWithFrame:frame collectionViewLayout:layout];
    self.thumbnailCollection.backgroundColor = [UIColor whiteColor]; // Set to pure white background
    self.thumbnailCollection.showsHorizontalScrollIndicator = NO;
    
    // Register cell
    [self.thumbnailCollection registerClass:[SeafPGThumbnailCell class] forCellWithReuseIdentifier:@"ThumbnailCell"]; // Changed to SeafPGThumbnailCell
    
    // Set data source and delegate
    self.thumbnailCollection.dataSource = self;
    self.thumbnailCollection.delegate = self;
    
    // Add to view
    [self.view addSubview:self.thumbnailCollection];

    // Add overlays for left and right edges
    self.leftThumbnailOverlay = [[UIView alloc] init];
    self.leftThumbnailOverlay.userInteractionEnabled = NO;
    self.leftThumbnailOverlay.backgroundColor = [UIColor clearColor]; // Ensure background is clear
    CAGradientLayer *leftGradient = [CAGradientLayer layer];
    leftGradient.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:1.0].CGColor, (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    leftGradient.startPoint = CGPointMake(0.0, 0.5);
    leftGradient.endPoint = CGPointMake(1.0, 0.5);
    [self.leftThumbnailOverlay.layer insertSublayer:leftGradient atIndex:0];
    [self.view addSubview:self.leftThumbnailOverlay];

    self.rightThumbnailOverlay = [[UIView alloc] init];
    self.rightThumbnailOverlay.userInteractionEnabled = NO;
    self.rightThumbnailOverlay.backgroundColor = [UIColor clearColor]; // Ensure background is clear
    CAGradientLayer *rightGradient = [CAGradientLayer layer];
    rightGradient.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor, (id)[UIColor colorWithWhite:1.0 alpha:1.0].CGColor];
    rightGradient.startPoint = CGPointMake(0.0, 0.5);
    rightGradient.endPoint = CGPointMake(1.0, 0.5);
    [self.rightThumbnailOverlay.layer insertSublayer:rightGradient atIndex:0];
    [self.view addSubview:self.rightThumbnailOverlay];
    
    // For performance, preload some thumbnails
    if (self.preViewItems.count > 0) {
        [self.thumbnailCollection reloadData];
        
        // Scroll to the currently selected item to ensure it's in the middle of the view - delay execution to ensure layout is complete
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scrollToCurrentItemAnimated:NO];
            [self updateThumbnailOverlaysVisibility]; // Update after scroll and layout
        });
    } else {
        [self updateThumbnailOverlaysVisibility]; // Hide if no items
    }
}

// Update the selected index and refresh layout
- (void)updateSelectedIndex:(NSUInteger)index {
    // Check if index is valid
    if (index >= self.preViewItems.count) {
        Debug(@"[Gallery] WARNING: Trying to update to invalid index: %ld", (long)index);
        return;
    }
    
    // Store old index for reference
    NSUInteger oldIndex = self.currentIndex;
    
    // Update current index
    self.currentIndex = index;
    
    // Update thumbnail collection view layout
    SeafThumbnailFlowLayout *layout = (SeafThumbnailFlowLayout *)self.thumbnailCollection.collectionViewLayout;
    layout.selectedIndex = index;
    layout.isDragging = NO; // Ensure not in dragging state
    
    // Refresh layout
    [layout invalidateLayout];
    
    // Create index path for scrolling
    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:index inSection:0];
    
    // Update selected item appearance and position with animation
    [UIView animateWithDuration:0.3 animations:^{
        // Refresh visible cell appearance
        [self.thumbnailCollection performBatchUpdates:^{
            // This empty block will trigger layout update
        } completion:nil];
        
        // Scroll thumbnail to center position in the same animation
        [self.thumbnailCollection scrollToItemAtIndexPath:indexPath
                                       atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                               animated:NO]; // Use NO to include in current animation block
    }];
    
    // Update active controllers, cancel unnecessary image loading
    [self updateActiveControllersForIndex:index];
    
    // Cancel downloads outside the range
    [self cancelDownloadsExceptForIndex:index withRange:2];
    
    Debug(@"[Gallery] Updated selected index from %ld to %ld", (long)oldIndex, (long)index);
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    NSUInteger idx = ip.item;
    SeafPhotoContentViewController *to = [self contentVCAtIndex:idx];
    UIPageViewControllerNavigationDirection dir = (idx > self.currentIndex
                                                   ? UIPageViewControllerNavigationDirectionForward
                                                   : UIPageViewControllerNavigationDirectionReverse);
    __weak typeof(self) wself = self;
    [self.pageVC setViewControllers:@[to]
                         direction:dir
                          animated:YES
                        completion:^(BOOL done){
        if (done) {
            __strong typeof(wself) strongSelf = wself;
            if (!strongSelf) return;

            [strongSelf updateSelectedIndex:idx];
            
            // Update loading range and trigger loading for the newly selected index
            [strongSelf updateLoadedImagesRangeForIndex:idx];
            [strongSelf loadImagesInCurrentRange]; // Ensure neighbor images start loading
            // Update active controllers, cancel unnecessary image loading
            [strongSelf updateActiveControllersForIndex:idx];

            // Cancel downloads outside the range (Add this for consistency)
            [strongSelf cancelDownloadsExceptForIndex:idx withRange:2];

            strongSelf.currentContentVC = to;

            NSString *titleText = nil;
            if (strongSelf.preViewItems && idx < strongSelf.preViewItems.count) {
                strongSelf.preViewItem = strongSelf.preViewItems[idx]; // Update the current preViewItem
                titleText = strongSelf.preViewItem.name;
            }
            
            if (titleText) {
                [SeafNavigationBarStyler updateTitleView:(UILabel *)strongSelf.navigationItem.titleView withText:titleText];
            }

            [strongSelf updateStarButtonIcon];
        }
    }];
}

- (void)pageViewController:(UIPageViewController *)pageViewController
       didFinishAnimating:(BOOL)finished
  previousViewControllers:(NSArray *)previousViewControllers
      transitionCompleted:(BOOL)completed {
    if (!finished || !completed) return;

    SeafPhotoContentViewController *vc = (SeafPhotoContentViewController *)pageViewController.viewControllers.firstObject;
    // Directly use view.tag to get the new index
    NSUInteger newIdx = vc.view.tag;
    if (newIdx != self.currentIndex) {
        NSUInteger oldIndex = self.currentIndex;
        self.currentIndex = newIdx;

        // Update loading range and trigger loading for the new index
        [self updateLoadedImagesRangeForIndex:newIdx];
        [self loadImagesInCurrentRange];
        // Update active controllers, cancel unnecessary image loading
        [self updateActiveControllersForIndex:newIdx];

        // Cancel downloads outside the range (This was already here, keep it)
        [self cancelDownloadsExceptForIndex:newIdx withRange:2];
        
        self.currentContentVC = vc;

        // Update thumbnail layout and title
        SeafThumbnailFlowLayout *layout = (SeafThumbnailFlowLayout *)self.thumbnailCollection.collectionViewLayout;
        layout.selectedIndex = newIdx;
        [self.thumbnailCollection reloadData];
        NSIndexPath *idxPath = [NSIndexPath indexPathForItem:newIdx inSection:0];
        [self.thumbnailCollection scrollToItemAtIndexPath:idxPath
                                     atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                             animated:YES];

        // Update navigation bar title
        NSString *titleText = nil;
        if (self.preViewItems && newIdx < self.preViewItems.count) {
            self.preViewItem = self.preViewItems[newIdx];
            titleText = self.preViewItem.name;
        } else {
            titleText = NSLocalizedString(@"View Photos", @"Seafile");
        }
        [SeafNavigationBarStyler updateTitleView:(UILabel *)self.navigationItem.titleView withText:titleText];
        
        // Update star icon in toolbar
        [self updateStarButtonIcon];
        [self updateThumbnailOverlaysVisibility]; // Update after page change
        
        Debug(@"Page changed from %ld to %ld, updated loaded range: %@",
              (long)oldIndex, (long)newIdx, NSStringFromRange(self.loadedImagesRange));
    }
}

#pragma mark - PageVC DataSource

- (SeafPhotoContentViewController *)viewControllerAtIndex:(NSUInteger)index {
    if (index >= self.preViewItems.count) {
        return nil;
    }

    // Check if this page is already cached
    NSNumber *key = @(index);
    SeafPhotoContentViewController *cachedController = [self.contentVCCache objectForKey:key];
    if (cachedController) {
        // Call prepareForReuse to clean up any existing state
        Debug(@"[Gallery] Preparing cached VC for reuse at index %ld", (long)index);
        [cachedController prepareForReuse];
        
        // If we already have a cached VC, check loading status
        NSNumber *needsLoading = [self.loadingStatusDict objectForKey:key];
        if (needsLoading && [needsLoading boolValue]) {
            // Check if we have saved progress
            NSNumber *savedProgress = [self.downloadProgressDict objectForKey:key];
            if (savedProgress) {
                // Update loading progress
                [cachedController updateLoadingProgress:[savedProgress floatValue]];
            }
        }
        
        // Update the seafFile even for cached controllers to ensure they have latest info
        if (self.preViewItems && index < self.preViewItems.count) {
            id<SeafPreView> item = self.preViewItems[index];
            cachedController.seafFile = item;
            if ([item isKindOfClass:[SeafFile class]]) {
                SeafFile *seafFile = (SeafFile *)item;
                cachedController.connection = seafFile.connection;
            }
        }
        
        Debug(@"Retrieved content VC for index %ld from cache", (long)index);
        return cachedController;
    }
    
    // Create new content controller
    SeafPhotoContentViewController *contentController = [[SeafPhotoContentViewController alloc] init];
    
    // Configure the content controller
    if (self.preViewItems && index < self.preViewItems.count) {
        id<SeafPreView> item = self.preViewItems[index];
        contentController.seafFile = item;
        if ([item isKindOfClass:[SeafFile class]]) {
            // Use the new seafFile property if it's a SeafFile
            SeafFile *seafFile = (SeafFile *)item;
            contentController.connection = seafFile.connection;
            
            // Check if image needs loading
            BOOL needsLoading = !item.hasCache && item.previewItemURL == nil;
            
            // Save loading status to dictionary
            [self.loadingStatusDict setObject:@(needsLoading) forKey:key];
            
            // If it needs downloading and hasn't started downloading, show loading indicator
            if (needsLoading) {
                [contentController showLoadingIndicator];
                
                // Check if we have saved progress
                NSNumber *savedProgress = [self.downloadProgressDict objectForKey:key];
                if (savedProgress) {
                    // Apply saved progress to newly created VC
                    [contentController updateLoadingProgress:[savedProgress floatValue]];
                }
            }
        }
    }
    
    // Set info model if available
    if (index < self.infoModels.count) {
        contentController.infoModel = self.infoModels[index];
    }
    
    // Set view tag to index for later identification
    contentController.view.tag = index;
    contentController.delegate = self; // Set the gallery as the delegate
    
    // Store in cache
    [self.contentVCCache setObject:contentController forKey:key];
    
    Debug(@"Created content VC for index %ld", (long)index);
    
    return contentController;
}

- (SeafPhotoContentViewController*)contentVCAtIndex:(NSUInteger)idx {
    return [self viewControllerAtIndex:idx];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pvc
      viewControllerBeforeViewController:(SeafPhotoContentViewController *)vc {
    // Directly use view.tag to get the real index
    NSUInteger i = vc.view.tag;
    if (i == 0) return nil;  // No more images before the first one

    NSUInteger prevIndex = i - 1;

    // When swiping left, proactively expand the loading range to include the previous image
    NSRange currentRange = self.loadedImagesRange;
    if (prevIndex < currentRange.location) {
        // Update the loading range to include the previous image
        NSUInteger newLocation = prevIndex;
        NSUInteger newLength = NSMaxRange(currentRange) - newLocation;
        _loadedImagesRange = NSMakeRange(newLocation, newLength);
        
        // Load this image immediately
        [self loadImageAtIndex:prevIndex];
        
        Debug(@"Expanded loading range to include previous image: %@", NSStringFromRange(_loadedImagesRange));
    }

    return [self contentVCAtIndex:prevIndex];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pvc
     viewControllerAfterViewController:(SeafPhotoContentViewController *)vc {
    // Directly use view.tag to get the real index
    NSUInteger i = vc.view.tag;
    if (i + 1 >= self.preViewItems.count) return nil;  // Already at the last image

    NSUInteger nextIndex = i + 1;

    // When swiping right, proactively expand the loading range to include the next image
    NSRange currentRange = self.loadedImagesRange;
    if (nextIndex >= NSMaxRange(currentRange)) {
        // Update the loading range to include the next image
        NSUInteger newLocation = currentRange.location;
        NSUInteger newLength = nextIndex - newLocation + 1;
        _loadedImagesRange = NSMakeRange(newLocation, newLength);
        
        // Load this image immediately
        [self loadImageAtIndex:nextIndex];
        
        Debug(@"Expanded loading range to include next image: %@", NSStringFromRange(_loadedImagesRange));
    }

    return [self contentVCAtIndex:nextIndex];
}

#pragma mark - PageVC Delegate

- (void)pageViewController:(UIPageViewController *)pageViewController
       willTransitionToViewControllers:(NSArray<UIViewController *> *)pendingViewControllers {
    // Ensure the pending view controller has the correct info state
    SeafPhotoContentViewController *pendingVC = pendingViewControllers.firstObject;
    if ([pendingVC isKindOfClass:[SeafPhotoContentViewController class]]) {
        // Ensure info view display state matches global state
        if (pendingVC.infoVisible != self.infoVisible) {
            // Update immediately without animation before transition
            [pendingVC toggleInfoView:self.infoVisible animated:NO];
            [pendingVC.view layoutIfNeeded];
        }
        
        // Ensure info button icon state matches global state
        [self updateInfoButtonIcon:self.infoVisible];
    }
}

#pragma mark - UICollectionViewDelegateFlowLayout

// Set the size for each item - the selected item's size is based on its actual aspect ratio, while unselected items have a width that is half of the height
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger index = indexPath.item;
    
    // Get standard height
    CGFloat height = self.thumbnailHeight; // Fixed height of 42
    
    // Get custom layout to check dragging status
    SeafThumbnailFlowLayout *layout = (SeafThumbnailFlowLayout *)collectionViewLayout;
    BOOL isDragging = layout.isDragging;
    
    // If it's the currently selected item
    if (index == self.currentIndex) {
        // If dragging, make the width half of the height, same as unselected items
        if (isDragging) {
            return CGSizeMake(height * 2.0 / 3.0, height);
        }
        
        // Return size where width and height are equal
        return CGSizeMake(height, height);
    }
    // Unselected items have a width that is 2/3 of the height
    else {
        return CGSizeMake(height * 2.0 / 3.0, height);
    }
}

// Set custom spacing
- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    return 4.0; // Default spacing between items is 3 points
}

// Since the standard UICollectionViewFlowLayout doesn't support setting different spacing between different items
- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return 4.0;  // Default line spacing is 3 points
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsMake(1.5, 10, 1.5, 10); // Top, left, bottom, right insets
}

#pragma mark - Thumbnail Collection
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return self.preViewItems.count;
}

- (UICollectionViewCell*)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    SeafPGThumbnailCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"ThumbnailCell" forIndexPath:ip];
    
    NSUInteger index = ip.item;
    if (index < self.preViewItems.count) {
        id<SeafPreView> previewItem = self.preViewItems[index];
        SeafPGThumbnailCellViewModel *viewModel = [[SeafPGThumbnailCellViewModel alloc] initWithPreviewItem:previewItem];
        [cell configureWithViewModel:viewModel];
    } else {
        // Handle index out of bounds if necessary, though configureWithViewModel should also handle nil/default state
        SeafPGThumbnailCellViewModel *errorViewModel = [[SeafPGThumbnailCellViewModel alloc] initWithPreviewItem:nil]; // nil item will result in error state
        [cell configureWithViewModel:errorViewModel];
    }
    return cell;
}

#pragma mark - Toolbar Action

- (void)toolbarButtonTapped:(UIButton*)btn {
    // Get the current file being operated on, prioritize using SeafFile
    id<SeafPreView> currentFile = self.preViewItem;

    // First, check if the current file is an instance of SeafUploadFile
    if (currentFile && [currentFile isKindOfClass:[SeafUploadFile class]] && (btn.tag != 2)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                       message:NSLocalizedString(@"Please wait for the image to upload and refresh the list before proceeding.", @"Seafile")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Seafile")
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return; // Do not proceed with other actions if it's an upload file
    }

    switch (btn.tag) {
        case SeafPhotoToolbarButtonTypeDownload: // Download
            if (currentFile && [currentFile isKindOfClass:[SeafFile class]]) {
                SeafFile *file = (SeafFile *)currentFile;
                // New logic: Save file to album
                [self saveCurrentPhotoToAlbum:file];
            } else {
                Debug(@"Download feature only supports SeafFile objects");
            }
            break;
            
        case SeafPhotoToolbarButtonTypeDelete: // Delete
            if (currentFile && [currentFile isKindOfClass:[SeafFile class]]) {
                [self deleteFile:(SeafFile *)currentFile];
            } else {
                Debug(@"Delete feature only supports SeafFile objects");
            }
            break;
            
        case SeafPhotoToolbarButtonTypeInfo: // Info
            // Toggle info view with info button
            if (!self.infoVisible) {
                [self handleSwipeUp:nil];
                // Icon update handled in handleSwipeUp method
            } else {
                [self handleSwipeDown:nil];
                // Icon update handled in handleSwipeDown method
            }
            break;
            
        case SeafPhotoToolbarButtonTypeStar: // Star
            if (currentFile && [currentFile isKindOfClass:[SeafFile class]]) {
                SeafFile *file = (SeafFile *)currentFile;
                if ([file isStarred]) {
                    [self unstarFile:file];
                } else {
                    [self starFile:file];
                }
            } else {
                Debug(@"Star feature only supports SeafFile objects");
            }
            break;
            
        case SeafPhotoToolbarButtonTypeShare: // Share
            if (currentFile && [currentFile isKindOfClass:[SeafFile class]]) {
                [self shareFile:(SeafFile *)currentFile];
            } else {
                Debug(@"Share feature only supports SeafFile objects");
            }
            break;
    }
}

// Save the current photo to the album
- (void)saveCurrentPhotoToAlbum:(SeafFile *)file {
    // Check photo library permission
    [self checkPhotoLibraryAuth:^{
        // Check if the file is already downloaded
        if (file.cachePath) {
            // Already downloaded, save to album directly
            UIImage *img = [UIImage imageWithContentsOfFile:file.cachePath];
            if (img) {
                UIImageWriteToSavedPhotosAlbum(img, self, @selector(image:didFinishSavingWithError:contextInfo:), (__bridge void *)(file));
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD showInfoWithStatus:NSLocalizedString(@"Saving to album", @"Seafile")];
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load image", @"Seafile")];
                });
            }
        } else {
            // Not downloaded, download first then save
            dispatch_async(dispatch_get_main_queue(), ^{
                [SVProgressHUD showInfoWithStatus:NSLocalizedString(@"Downloading file", @"Seafile")];
            });
            
            file.state = SEAF_DENTRY_INIT;
            __weak typeof(self) weakSelf = self;
            [file setFileDownloadedBlock:^(SeafFile *file, NSError *error) {
                __strong typeof(weakSelf) self = weakSelf;
                if (error) {
                    Warning("Failed to download file %@: %@", file.path, error);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to download file", @"Seafile")];
                    });
                } else {
                    [file setFileDownloadedBlock:nil];
                    // Save to album after downloading
                    UIImage *img = [UIImage imageWithContentsOfFile:file.cachePath];
                    if (img) {
                        UIImageWriteToSavedPhotosAlbum(img, self, @selector(image:didFinishSavingWithError:contextInfo:), (__bridge void *)(file));
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [SVProgressHUD showInfoWithStatus:NSLocalizedString(@"Saving to album", @"Seafile")];
                        });
                    } else {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load image", @"Seafile")];
                        });
                    }
                }
            }];
            [SeafDataTaskManager.sharedObject addFileDownloadTask:file];
        }
    }];
}

// Handle the callback for saving to the album
- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    SeafFile *file = (__bridge SeafFile *)contextInfo;
    if (error) {
        Warning("Failed to save file %@ to album: %@", file.name, error);
        dispatch_async(dispatch_get_main_queue(), ^{
            [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to save %@ to album", @"Seafile"), file.name]];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Succeeded to save %@ to album", @"Seafile"), file.name]];
        });
    }
}

// SeafFile operation related methods
- (void)exportFile:(SeafFile *)file {
    // Keep the existing logic for exporting to local
    if (file.exportURL) {
        // Share file using standard export controller
        UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[file.exportURL] applicationActivities:nil];
        
        // Set popover source on iPad
        if (IsIpad()) {
            activityVC.popoverPresentationController.sourceView = self.view;
            activityVC.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 0, 0);
        }
        
        [self presentViewController:activityVC animated:YES completion:nil];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"File is not downloaded yet", @"Seafile")];
        });
    }
}

- (void)deleteFile:(SeafFile *)file {
    // Confirmation dialog
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete %@ ?", @"Seafile"), file.name]
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"Seafile") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        // Execute delete operation
        if (self.masterVc && [self.masterVc respondsToSelector:@selector(deleteFile:)]) {
            [self dismissGallery]; // Close gallery view
            [self.masterVc performSelector:@selector(deleteFile:) withObject:file];
        }
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"Seafile") style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Capture both self and file weakly to avoid retain-cycles: file → block → self/file
- (void)starFile:(SeafFile *)file {
    __weak typeof(self) weakSelf = self;
    __weak typeof(file) weakFile = file;
    
    [file setStarred:YES withBlock:^(BOOL success) {
        __strong typeof(weakSelf) self = weakSelf;
        __strong typeof(weakFile) strongFile = weakFile;
        if (!self || !strongFile) return;   // Either one deallocated
        
        if (success) {
            [SVProgressHUD showSuccessWithStatus:
             [NSString stringWithFormat:NSLocalizedString(@"%@ has been starred", @"Seafile"),
              strongFile.name]];
            
            // Update star icon in toolbar
            [self updateStarButtonIcon];
        } else {
            [SVProgressHUD showErrorWithStatus:
             [NSString stringWithFormat:NSLocalizedString(@"Failed to star %@", @"Seafile"),
              strongFile.name]];
        }
    }];
}


- (void)unstarFile:(SeafFile *)file {
    // Capture both self and file weakly to avoid retain-cycles
    __weak typeof(self) weakSelf = self;
    __weak typeof(file) weakFile = file;
    
    [file setStarred:NO withBlock:^(BOOL success) {
        __strong typeof(weakSelf) self = weakSelf;
        __strong typeof(weakFile) strongFile = weakFile;
        if (!self || !strongFile) return;
        
        if (success) {
            [SVProgressHUD showSuccessWithStatus:
             [NSString stringWithFormat:NSLocalizedString(@"%@ has been unstarred", @"Seafile"),
              strongFile.name]];
            
            // Update star icon in toolbar
            [self updateStarButtonIcon];
        } else {
            [SVProgressHUD showErrorWithStatus:
             [NSString stringWithFormat:NSLocalizedString(@"Failed to unstar %@", @"Seafile"),
              strongFile.name]];
        }
    }];
}

// New method: Update star icon state
- (void)updateStarButtonIcon {
    if (!self.toolbarView) return;
    
    // Find the star button at index 3
    for (UIView *subview in self.toolbarView.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)subview;
            if (btn.tag == SeafPhotoToolbarButtonTypeStar) {
                // Check the starred status of the current file
                BOOL isStarred = NO;
                if (self.preViewItem && [self.preViewItem isKindOfClass:[SeafFile class]]) {
                    SeafFile *file = (SeafFile *)self.preViewItem;
                    isStarred = [file isStarred];
                }
                
                // Choose icon based on starred status
                NSString *iconName = isStarred ? @"detail_starred_selected" : @"detail_starred";
                UIImage *image = [UIImage imageNamed:iconName];
                
                if (image) {
                    // Resize icon
                    CGFloat iconSize = 20.0;
                    UIGraphicsBeginImageContextWithOptions(CGSizeMake(iconSize, iconSize), NO, 0.0);
                    [image drawInRect:CGRectMake(0, 0, iconSize, iconSize)];
                    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
                    UIGraphicsEndImageContext();
                    
                    // Set icon color
                    UIImage *finalImage;
                    if (isStarred) {
                        finalImage = resizedImage; // Keep original color for starred status
                    } else {
                        finalImage = [self imageWithTintColor:[UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0] image:resizedImage]; // Gray for non-starred status
                    }
                    
                    // Update button icon
                    [btn setImage:finalImage forState:UIControlStateNormal];
                }
                break;
            }
        }
    }
}

- (void)shareFile:(SeafFile *)file {
    // Ensure the file is downloaded
    if (!file.exportURL) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"File is not downloaded yet", @"Seafile")];
        });
        return;
    }
    
    // Use system share functionality
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[file.exportURL] applicationActivities:nil];
    
    // Set popover source on iPad
    if (IsIpad()) {
        activityVC.popoverPresentationController.sourceView = self.view;
        activityVC.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 0, 0);
    }
    
    [self presentViewController:activityVC animated:YES completion:nil];
}

#pragma mark - Actions

- (void)cancelAllPendingFileOperations {
    Debug(@"[Gallery] Cancelling all pending file operations (images and thumbnails).");

    // Cancel operations for VCs in cache
    for (NSNumber *key in [self.contentVCCache allKeys]) {
        SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:key];
        if (vc) {
            Debug(@"[Gallery] Requesting VC (index %@, file: %@) to cancel image loading.", key, vc.seafFile.name ? vc.seafFile.name : @"N/A");
            [vc cancelImageLoading]; // This will call [self.seafFile cancelDownload] and clear seafFile.delegate
        }
    }

    // Cancel operations for all files in preViewItems
    if (self.preViewItems) {
        for (id<SeafPreView> item in self.preViewItems) {
            if ([item isKindOfClass:[SeafFile class]]) {
                SeafFile *file = (SeafFile *)item;

                // Cancel main file download if ongoing.
                if (file.isDownloading) { // Assuming isDownloading property exists or method
                    Debug(@"[Gallery] Directly cancelling download for file from preViewItems: %@", file.name);
                    [file cancelDownload];
                }
               
                file.thumbCompleteBlock = nil;

                // If the gallery itself is a direct delegate for file loading (e.g., via [file load:self...])
                if (file.delegate == self) {
                    Debug(@"[Gallery] Clearing self as delegate for file: %@", file.name);
                    file.delegate = nil;
                }
            }
        }
    }
}

- (void)dismissGallery {
    // 1. Cancel all pending network operations and clear callbacks
    [self cancelAllPendingFileOperations];

    // 2. Release resources held by Content View Controllers
    for (NSNumber *key in [self.contentVCCache allKeys]) {
        SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:key];
        if (vc) {
            // cancelImageLoading was called in cancelAllPendingFileOperations
            // releaseImageMemory should be called to free up image data
            [vc releaseImageMemory];
        }
    }
    // Clear the cache of VCs after they have been processed
    [self.contentVCCache removeAllObjects];
    
    // 3. Clear active controllers set
    [self.activeControllers removeAllObjects];
    
    // 4. Dismiss the view controller
    // Check if navigationController is not nil before dismissing
    if (self.navigationController) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else if (self.presentingViewController) {
        // Fallback if not in a navigation controller but presented modally
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

// Helper method to create a 1px image for the shadow
- (UIImage *)createSinglePixelImageWithColor:(UIColor *)color {
    CGRect rect = CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
    UIGraphicsBeginImageContext(rect.size);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGContextSetFillColorWithColor(context, [color CGColor]);
    CGContextFillRect(context, rect);
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}


// Clear views method
- (void)clearViews {
    // Release page view controller
    if (self.pageVC) {
        [self.pageVC.view removeFromSuperview];
        [self.pageVC removeFromParentViewController];
        self.pageVC = nil;
    }
    
    // Release thumbnail collection
    if (self.thumbnailCollection) {
        [self.thumbnailCollection removeFromSuperview];
        self.thumbnailCollection = nil;
    }
    
    // Cancel any download tasks
    if (self.preViewItems) {
        for (id<SeafPreView> item in self.preViewItems) {
            if ([item isKindOfClass:[SeafFile class]]) {
                SeafFile *file = (SeafFile *)item;
                // If the file is downloading, cancel the download
                if (file.isDownloading) {
                    // Remove task from DataTaskManager
                    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
                        if (conn.accountIdentifier) {
                            SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:conn];
                            [accountQueue removeFileDownloadTask:file];
                        }
                    }
                }
            }
        }
    }
}

// Update current content controller method
- (void)updateCurrentContentController {
    if (!self.pageVC || self.preViewItems.count == 0 || self.currentIndex >= self.preViewItems.count) return;

    // Update load range
    [self updateLoadedImagesRangeForIndex:self.currentIndex];
    
    // Load images in current range
    [self loadImagesInCurrentRange];
    
    // Get content view controller for current index
    SeafPhotoContentViewController *contentVC = [self viewControllerAtIndex:self.currentIndex];
    
    [self.pageVC setViewControllers:@[contentVC]
                         direction:UIPageViewControllerNavigationDirectionForward
                          animated:NO
                        completion:nil];
    
    self.currentContentVC = contentVC;
    
    // Update title
    if (self.preViewItem) {
        // Update title view using styling utility
        [SeafNavigationBarStyler updateTitleView:(UILabel *)self.navigationItem.titleView withText:self.preViewItem.name];
    }
    
    // Update star icon in toolbar
    [self updateStarButtonIcon];
    
    // If there's a thumbnail collection, scroll to current index - delay execution
    if (self.thumbnailCollection) {
        [self.thumbnailCollection reloadData]; // Reload first
        dispatch_async(dispatch_get_main_queue(), ^{
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:self.currentIndex inSection:0];
        [self.thumbnailCollection scrollToItemAtIndexPath:indexPath
                                        atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                                animated:YES];
        [self updateThumbnailOverlaysVisibility]; // Update after reload and scroll
        });
    }
}

// Update file preview URL handling
- (void)updateFilePreviewURL:(SeafBase *)file {
    if (!self.preViewItems || ![file isKindOfClass:[SeafFile class]]) return;
    SeafFile *seafFile = (SeafFile *)file;
    
    // Find the index of this file in preViewItems
    NSInteger index = [self.preViewItems indexOfObject:seafFile];
    if (index == NSNotFound) return;
        
    // If the view controller is cached or currently visible, update its seafFile property
    NSNumber *key = @(index);
    SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:key];
    if (vc) {
        vc.seafFile = seafFile; // Update the file object
        Debug(@"[Gallery] Updated cached VC at index %ld with new file data: %@", (long)index, seafFile.name);
    }
    
    // If it's the current content VC, update it directly
    if (index == self.currentIndex && self.currentContentVC) {
        self.currentContentVC.seafFile = seafFile; // Update the file object
        // Trigger image loading if needed, or let the delegate methods handle it
        Debug(@"[Gallery] Updated current VC at index %ld with new file data: %@", (long)index, seafFile.name);
    }
}

#pragma mark - SeafDentryDelegate (Download and caching related methods)

// Helper method to find the VC for a file and apply updates
- (void)_findAndUpdateContentViewControllerForFile:(SeafFile *)file updateBlock:(void (^)(SeafPhotoContentViewController *vc, NSUInteger index))updateBlock {
    // Find the index of this file in preViewItems
    NSUInteger fileIndex = [self.preViewItems indexOfObject:file];
    if (fileIndex == NSNotFound) {
        Debug(@"[Gallery] WARNING: File '%@' not found in preViewItems during update.", file.name);
        return;
    }

    NSNumber *key = @(fileIndex);
    SeafPhotoContentViewController *vc = nil; // Initialize vc to nil

    // Try to get from cache first
    SeafPhotoContentViewController *cachedController = [self.contentVCCache objectForKey:key];
    if (cachedController) {
        vc = cachedController;
        Debug(@"[Gallery] Applying update to cached VC for file '%@' at index %lu.", file.name, (unsigned long)fileIndex);
        // Ensure the cached VC has the latest file object, especially if 'file' instance from delegate might be newer
        vc.seafFile = file;
        vc.connection = file.connection;
    }

    // If not in cache, check if it's the current one being displayed
    if (!vc && fileIndex == self.currentIndex && self.currentContentVC) {
        // Ensure the currentContentVC actually corresponds to this file's index
        if (self.currentContentVC.view.tag == fileIndex) {
             vc = self.currentContentVC;
             Debug(@"[Gallery] Applying update to currentContentVC for file '%@' at index %lu.", file.name, (unsigned long)fileIndex);
             // Ensure currentContentVC also has the latest file object
             vc.seafFile = file;
             vc.connection = file.connection;
        } else {
            Debug(@"[Gallery] WARNING: currentContentVC tag (%ld) does not match expected index (%lu) for file '%@'. Cannot apply update via currentContentVC.", (long)self.currentContentVC.view.tag, (unsigned long)fileIndex, file.name);
        }
    }

    // If still not found, but should be an active/preloaded controller (current or immediate neighbor)
    // attempt to get/create it. This makes the update process more robust for nearby items.
    if (!vc) {
        BOOL isKeyController = (fileIndex == self.currentIndex);
        if (!isKeyController && self.currentIndex > 0 && fileIndex == self.currentIndex - 1) {
            isKeyController = YES; // Previous item
        }
        if (!isKeyController && (self.currentIndex + 1 < self.preViewItems.count) && fileIndex == self.currentIndex + 1) {
            isKeyController = YES; // Next item
        }

        if (isKeyController) {
            Debug(@"[Gallery] VC for key index %lu (current or neighbor) not found initially. Attempting to get/create.", (unsigned long)fileIndex);
            // viewControllerAtIndex: will create if not cached and assign the SeafFile from preViewItems.
            // It will also update an existing cached VC's seafFile property.
            SeafPhotoContentViewController *potentialVC = [self viewControllerAtIndex:fileIndex];
            if (potentialVC) {
                // The 'file' parameter to this method is the instance from the download delegate,
                // which has the most up-to-date state. Ensure potentialVC uses this instance.
                potentialVC.seafFile = file;
                potentialVC.connection = file.connection;
                vc = potentialVC; // Use this VC for the updateBlock
                Debug(@"[Gallery] Obtained/created VC for key index %lu. Will use for update block.", (unsigned long)fileIndex);
            } else {
                Debug(@"[Gallery] Failed to obtain/create VC for key index %lu even after trying.", (unsigned long)fileIndex);
            }
        }
    }

    // Execute the update block if a relevant view controller was found
    if (vc && updateBlock) {
        updateBlock(vc, fileIndex);
    } else if (updateBlock) { // vc is nil, but updateBlock was provided
         Debug(@"[Gallery] No active VC found for file '%@' at index %lu. Update block will not run.", file.name, (unsigned long)fileIndex);
         // vc is nil, updateBlock won't be called
    }
}

- (void)download:(SeafBase *)entry progress:(float)progress {
    // This is called to update download progress
    if (![entry isKindOfClass:[SeafFile class]]) return;
    SeafFile *file = (SeafFile *)entry;

    [self _findAndUpdateContentViewControllerForFile:file updateBlock:^(SeafPhotoContentViewController *vc, NSUInteger index) {
        NSNumber *key = @(index);
        // Save progress to dictionary (outside the VC update, keep state in gallery)
        [self.downloadProgressDict setObject:@(progress) forKey:key];

        // Update progress in the content view controller
        [vc updateLoadingProgress:progress];
        Debug(@"Updating download progress for %@ to %.2f%%", file.name, progress * 100);
    }];
}

- (void)download:(SeafBase *)entry complete:(BOOL)success {
    // This is called when a file is downloaded successfully OR fails (check success flag)
    if (![entry isKindOfClass:[SeafFile class]]) return;
    SeafFile *file = (SeafFile *)entry;

    Debug(@"[Gallery] Download complete callback for file %@, ooid: %@, success: %d", file.name, file.ooid, success);

    // Find index first, needed for state updates even if no VC is found
    NSUInteger fileIndex = [self.preViewItems indexOfObject:file];
    if (fileIndex == NSNotFound) {
        Debug(@"[Gallery] WARNING: Completed/failed file not found in preViewItems: %@", file.name);
        return;
    }
    NSNumber *key = @(fileIndex);

    // Mark the file as no longer loading and remove progress state (always do this)
    [self.loadingStatusDict setObject:@NO forKey:key];
    [self.downloadProgressDict removeObjectForKey:key];

    [self _findAndUpdateContentViewControllerForFile:file updateBlock:^(SeafPhotoContentViewController *vc, NSUInteger index) {
        if (success) {
            Debug(@"[Gallery] Updating content VC with completed file: %@", file.name);
            // Update the content view controller with the seafFile that has completed downloading
            vc.seafFile = file; // Ensure VC has the latest file object
            // Make sure the VC loads the image, which will hide its loading indicator when done
            [vc loadImage];
            Debug(@"[Gallery] File download complete for index %ld: %@", (long)index, file.name);
        } else {
            // Handle failure case within the callback for the specific VC
            Debug(@"[Gallery] Showing error image for failed file: %@", file.name);
            [vc showErrorImage]; // Show error if success is false
            Debug(@"[Gallery] File download failed for index %ld: %@", (long)index, file.name);
        }
    }];

    // If no VC was found by the helper, and the download succeeded, the file object in preViewItems is now updated.
    BOOL vcFoundOrHandled = ([self.contentVCCache objectForKey:key] != nil) || (fileIndex == self.currentIndex && self.currentContentVC && self.currentContentVC.view.tag == fileIndex);
    
    // If this is the current page, ensure the image is reloaded *even if* the helper didn't find the VC initially
    if (fileIndex == self.currentIndex) {
        if (success) {
            Debug(@"[Gallery] This is the current page (%lu), ensuring image is loaded for completed file %@", (unsigned long)fileIndex, file.name);
            if (self.currentContentVC) {
                // Double ensure the seafFile is up to date and trigger load
                self.currentContentVC.seafFile = file;
                [self.currentContentVC loadImage];
            } else {
                 Debug(@"[Gallery] WARNING: currentContentVC is nil on completion, attempting to recreate/set for index %lu", (unsigned long)fileIndex);
                 // Attempt to create/set the VC if it's missing for the current index
                 SeafPhotoContentViewController *newVC = [self contentVCAtIndex:fileIndex]; // This will create if needed and update file details
                 if (newVC) {
                     self.currentContentVC = newVC;
                     // Trigger the load again after setting
                     [newVC loadImage];
                     // Set it in the page controller if it wasn't already the active one
                     if (![self.pageVC.viewControllers containsObject:newVC]) {
                          [self.pageVC setViewControllers:@[newVC] direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
                     }
                 }
            }
        } else {
            // If download failed for the current item, show the alert (if helper didn't handle it)
             if (!vcFoundOrHandled) {
                 Debug(@"[Gallery] Download failed for current item (%lu), showing alert.", (unsigned long)fileIndex);
                 [self showDownloadError:file.name]; // Use helper for alert
             }
        }
    } else if (!success && !vcFoundOrHandled) {
         Debug(@"[Gallery] Download failed for non-visible item (%lu), no VC to update.", (unsigned long)fileIndex);
    }
}


- (void)download:(SeafBase *)entry failed:(NSError *)error {
    if (![entry isKindOfClass:[SeafFile class]]) return;
    SeafFile *file = (SeafFile *)entry;

    Debug(@"[Gallery] Received FAILED signal via download:failed: for file %@, error: %@", file.name, error);

    [self download:entry complete:NO];
}

- (void)cancelDownload {
    // Cancel the download of the current item
    id<SeafPreView> item = self.preViewItem;
    
    // Cancel download tasks for all accounts
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        if (conn.accountIdentifier) {
            SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:conn];
            [accountQueue removeFileDownloadTask:item];
        }
    }
}

#pragma mark - Memory Management

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    
    // Perform memory cleanup on memory warning
    [self aggressiveMemoryCleanup];
}

// Aggressive memory cleanup: only keep the currently viewed image
- (void)aggressiveMemoryCleanup {
    // Save the current index's VC
    NSNumber *currentKey = @(self.currentIndex);
    SeafPhotoContentViewController *currentVC = [self.contentVCCache objectForKey:currentKey];
    
    // Re-add the current VC
    if (currentVC) {
        [self.contentVCCache setObject:currentVC forKey:currentKey];
    }
    
    // Update load range to only include the current image
    _loadedImagesRange = NSMakeRange(self.currentIndex, 1);
    
    Debug(@"Memory warning: Cleared non-current image cache, current load range: %@", NSStringFromRange(_loadedImagesRange));
}

- (void)dealloc {
    // Release all views and memory
    [self clearViews];
    
    // Clear data cache
    self.infoModels = nil;
    self.preViewItems = nil;
    self.preViewItem = nil;
    self.contentVCCache = nil;
    
    Debug(@"SeafPhotoGalleryViewController deallocated");
}

// Ensure the current item is scrolled to the center position
- (void)scrollToCurrentItemAnimated:(BOOL)animated {
    if (self.currentIndex < [self.thumbnailCollection numberOfItemsInSection:0]) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:self.currentIndex inSection:0];
        
        // Try to get the layout attributes for the current selected item to determine its width
        UICollectionViewLayoutAttributes *attributes = [self.thumbnailCollection layoutAttributesForItemAtIndexPath:indexPath];
        CGFloat cellWidth = attributes ? attributes.frame.size.width : (self.thumbnailHeight / 2.0); // Fallback width
        
        // Calculate the insets needed to ensure centering
        CGFloat collectionViewWidth = self.thumbnailCollection.bounds.size.width;
        CGFloat inset = MAX(0, (collectionViewWidth / 2.0) - (cellWidth / 2.0));
        
        // Update insets
        self.thumbnailCollection.contentInset = UIEdgeInsetsMake(self.thumbnailCollection.contentInset.top, inset, self.thumbnailCollection.contentInset.bottom, inset);
        
        // Scroll to center
        [self.thumbnailCollection scrollToItemAtIndexPath:indexPath
                                       atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                                animated:animated];
    }
}

- (void)setupToolbar {
    // Bottom toolbar (5 buttons) - including bottom safe area
    CGFloat toolbarH = 44;
    CGFloat safeAreaBottom = 0;
    
    if (@available(iOS 11.0, *)) {
        safeAreaBottom = self.view.safeAreaInsets.bottom;
    }
    
    CGRect tbFrame = CGRectMake(0,
                                self.view.bounds.size.height - toolbarH - safeAreaBottom,
                                self.view.bounds.size.width,
                                toolbarH + safeAreaBottom); // Include bottom safe area
    
    self.toolbarView = [[UIView alloc] initWithFrame:tbFrame];
    self.toolbarView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin;
    self.toolbarView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.toolbarView];

    // Update icon names to those in the design
    NSArray<NSString*> *icons = @[@"detail_download", @"detail_delete", @"detail_information", @"detail_starred", @"detail_share"];
    NSUInteger count = icons.count;
    
    // Adjust spacing and size according to design
    CGFloat totalWidth = self.toolbarView.bounds.size.width;
    
    // Buttons should have equal spacing, each occupying the same space
    CGFloat itemWidth = totalWidth / count;
    
    CGFloat iconSize = 20.0; // Set icon size to 20pt (Changed from 24.0)
    
    // Create buttons and distribute evenly - note buttons only in the top area of the toolbar, not extending into the safe area
    for (int i = 0; i < count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        
        // Center the button within its area - only in the top part of the toolbar
        CGFloat x = i * itemWidth;
        btn.frame = CGRectMake(x, 0, itemWidth, toolbarH); // Button height is toolbar height, not including safe area
        
        NSString *iconName = icons[i];        // Set icon
        
        // Check current state and update corresponding icon
        if (i == 2 && self.infoVisible) {
            iconName = @"detail_information_selected";// Info icon - use selected icon if info panel is already shown
        } else if (i == 3 && self.preViewItem && [self.preViewItem isKindOfClass:[SeafFile class]]) {
            // Star icon - use selected icon if current file is already starred
            SeafFile *file = (SeafFile *)self.preViewItem;
            if ([file isStarred]) {
                iconName = @"detail_starred_selected";
            }
        }
        
        UIImage *image = [UIImage imageNamed:iconName];
        
        // If icon is found, adjust its size and color
        if (image) {
            // Resize icon
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(iconSize, iconSize), NO, 0.0);
            [image drawInRect:CGRectMake(0, 0, iconSize, iconSize)];
            UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            
            // Set icon color to gray, but keep original color for selected icon
            UIImage *finalImage;
            if ([iconName isEqualToString:@"detail_starred_selected"] || [iconName isEqualToString:@"detail_information_selected"]) {
                finalImage = resizedImage; // Keep original color for selected status
            } else {
                finalImage = [self imageWithTintColor:[UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0] image:resizedImage]; // Gray for non-selected status
            }
            
            [btn setImage:finalImage forState:UIControlStateNormal];
            // Push the icon down slightly within the button's frame
            btn.imageEdgeInsets = UIEdgeInsetsMake(5.0, 0, -5.0, 0);
        }
        
        // Assign tag using the enum
        switch (i) {
            case 0:
                btn.tag = SeafPhotoToolbarButtonTypeDownload;
                break;
            case 1:
                btn.tag = SeafPhotoToolbarButtonTypeDelete;
                break;
            case 2:
                btn.tag = SeafPhotoToolbarButtonTypeInfo;
                break;
            case 3:
                btn.tag = SeafPhotoToolbarButtonTypeStar;
                break;
            case 4:
                btn.tag = SeafPhotoToolbarButtonTypeShare;
                break;
        }
        [btn addTarget:self action:@selector(toolbarButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.toolbarView addSubview:btn];
    }
}

#pragma mark - Utility Methods
// Set color for icon
- (UIImage *)imageWithTintColor:(UIColor *)tintColor image:(UIImage *)image {
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    CGRect rect = CGRectMake(0, 0, image.size.width, image.size.height);
    
    [image drawInRect:rect];
    [tintColor set];
    UIRectFillUsingBlendMode(rect, kCGBlendModeSourceAtop);
    
    UIImage *tintedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return tintedImage;
}

#pragma mark - Gestures
- (void)addSwipeGestures {
    // Add up swipe gesture
    UISwipeGestureRecognizer *swipeUpGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeUp:)];
    swipeUpGesture.direction = UISwipeGestureRecognizerDirectionUp;
    [self.view addGestureRecognizer:swipeUpGesture];
    
    // Add down swipe gesture
    UISwipeGestureRecognizer *swipeDownGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeDown:)];
    swipeDownGesture.direction = UISwipeGestureRecognizerDirectionDown;
    [self.view addGestureRecognizer:swipeDownGesture];
}

#pragma mark - Swipe Gesture Handlers

// Handle up swipe gesture - show info view
- (void)handleSwipeUp:(UISwipeGestureRecognizer *)sender {
    if (self.infoVisible) return;
    self.infoVisible = YES;
    
    // Update current content view controller's info view display state
    [self.currentContentVC toggleInfoView:YES animated:YES];
    
    // Update info button icon to selected state
    [self updateInfoButtonIcon:YES];
    
    // Adjust thumbnail strip position
    [UIView animateWithDuration:0.3 animations:^{
        CGRect bounds = self.view.bounds;
        CGFloat halfHeight = bounds.size.height / 2;
        CGFloat safeAreaBottom = 0;
        CGFloat stripHeight = 45; // Use fixed strip height
        
        if (@available(iOS 11.0, *)) {
            safeAreaBottom = self.view.safeAreaInsets.bottom;
        }
        
        // Calculate target frame for thumbnail collection
        CGRect targetThumbnailFrame = CGRectMake(0,
                                               halfHeight - stripHeight, // Use stripHeight for positioning
                                               bounds.size.width,
                                               stripHeight); // Use stripHeight for size
        self.thumbnailCollection.frame = targetThumbnailFrame;
        
        // Synchronize overlays with the new thumbnail collection frame
        [self synchronizeOverlayFramesAndVisibilityWithThumbnailCollectionFrame:targetThumbnailFrame isAnimatingReveal:NO]; // Modified
        
        // Toolbar stays at the bottom
        CGFloat toolbarHeight = 44;
        self.toolbarView.frame = CGRectMake(0,
                                          bounds.size.height - toolbarHeight - safeAreaBottom,
                                          bounds.size.width,
                                          toolbarHeight + safeAreaBottom); // Include safe area
    } completion:^(BOOL finished) {
        if (finished) {
            // Ensure the collection view is scrolled to the current item so contentOffset is correct
            [self scrollToCurrentItemAnimated:NO];
            // Re-synchronize overlays now that the thumbnail collection is in its final place and scrolled
            [self synchronizeOverlayFramesAndVisibilityWithThumbnailCollectionFrame:self.thumbnailCollection.frame isAnimatingReveal:NO]; // Modified
        }
    }];
}

// Handle down swipe gesture - hide info view
- (void)handleSwipeDown:(UISwipeGestureRecognizer *)sender {
    if (!self.infoVisible) return;
    self.infoVisible = NO;
    
    // Update current content view controller's info view display state
    [self.currentContentVC toggleInfoView:NO animated:YES];
    
    // Update info button icon to non-selected state
    [self updateInfoButtonIcon:NO];

    // Prepare overlays for reveal animation: start transparent, ensure not hidden
    self.leftThumbnailOverlay.alpha = 0.0;
    self.rightThumbnailOverlay.alpha = 0.0;
    // Hidden state will be set to NO by synchronize... with isAnimatingReveal:YES
    
    // Restore thumbnail strip position
    [UIView animateWithDuration:0.3 animations:^{
        CGRect bounds = self.view.bounds;
        CGFloat stripHeight = 45; // Use fixed strip height
        CGFloat toolbarHeight = 44;
        CGFloat safeAreaBottom = 0;
        
        if (@available(iOS 11.0, *)) {
            safeAreaBottom = self.view.safeAreaInsets.bottom;
        }
        
        // Calculate target frame for thumbnail collection
        CGRect targetThumbnailFrame = CGRectMake(0,
                                               bounds.size.height - stripHeight - toolbarHeight - safeAreaBottom, // Use stripHeight
                                               bounds.size.width,
                                               stripHeight); // Use stripHeight
        self.thumbnailCollection.frame = targetThumbnailFrame;

        // Synchronize overlays: positions them and ensures they are NOT hidden during this reveal animation
        [self synchronizeOverlayFramesAndVisibilityWithThumbnailCollectionFrame:targetThumbnailFrame isAnimatingReveal:YES]; // Modified
        
        // Fade in overlays
        self.leftThumbnailOverlay.alpha = 1.0;
        self.rightThumbnailOverlay.alpha = 1.0;
        
        // Toolbar stays at the bottom
        self.toolbarView.frame = CGRectMake(0,
                                          bounds.size.height - toolbarHeight - safeAreaBottom,
                                          bounds.size.width,
                                          toolbarHeight + safeAreaBottom); // Include safe area
    } completion:^(BOOL finished) {
        if (finished) {
            // Ensure the collection view is scrolled to the current item so contentOffset is correct
            [self scrollToCurrentItemAnimated:NO];
            // Re-synchronize overlays: final frame update and visibility check based on scroll state
            [self synchronizeOverlayFramesAndVisibilityWithThumbnailCollectionFrame:self.thumbnailCollection.frame isAnimatingReveal:NO]; // Modified
        }
    }];
}

// Update info button icon state
- (void)updateInfoButtonIcon:(BOOL)selected {
    if (!self.toolbarView) return;
    
    // Find the info button at index 2
    for (UIView *subview in self.toolbarView.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)subview;
            if (btn.tag == SeafPhotoToolbarButtonTypeInfo) {
                // Choose icon based on selected state
                NSString *iconName = selected ? @"detail_information_selected" : @"detail_information";
                UIImage *image = [UIImage imageNamed:iconName];
                
                if (image) {
                    // Resize icon
                    CGFloat iconSize = 20.0;
                    UIGraphicsBeginImageContextWithOptions(CGSizeMake(iconSize, iconSize), NO, 0.0);
                    [image drawInRect:CGRectMake(0, 0, iconSize, iconSize)];
                    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
                    UIGraphicsEndImageContext();
                    
                    // Set icon color
                    UIImage *finalImage;
                    if (selected) {
                        finalImage = resizedImage; // Keep original color for selected status
                    } else {
                        finalImage = [self imageWithTintColor:[UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0] image:resizedImage]; // Gray for non-selected status
                    }
                    
                    // Update button icon
                    [btn setImage:finalImage forState:UIControlStateNormal];
                }
                break;
            }
        }
    }
}

#pragma mark - UIScrollViewDelegate (for Thumbnail Collection)

// Called when the user begins dragging
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    // Check if this delegate call is for the thumbnailCollection
    if (scrollView == self.thumbnailCollection) {
        // Set dragging state to true in the layout
        SeafThumbnailFlowLayout *layout = (SeafThumbnailFlowLayout *)self.thumbnailCollection.collectionViewLayout;
        layout.isDragging = YES;
        
        // Force layout update
        [layout invalidateLayout];
        
        // Animate the selected cell's size change
        [UIView animateWithDuration:0.2 animations:^{
            // Update the layout with animation
            [self.thumbnailCollection performBatchUpdates:nil completion:nil];
        }];
    }
}

// Called when the user lifts their finger after dragging
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    // Check if this delegate call is for the thumbnailCollection
    if (scrollView == self.thumbnailCollection) {
        if (!decelerate) {
            // If scrolling stops immediately, find and select the nearest item
            [self selectItemNearestToCenter];
            
            // Reset dragging state and restore normal layout
            [self endThumbnailDragging];
        }
    }
}

// Called when scrolling comes to a complete stop after deceleration
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    // Check if this delegate call is for the thumbnailCollection
    if (scrollView == self.thumbnailCollection) {
        // Find and select the nearest item
        [self selectItemNearestToCenter];
        
        // Reset dragging state and restore normal layout
        [self endThumbnailDragging];
    }
}

// Helper method to reset dragging state and restore layout
- (void)endThumbnailDragging {
    // Reset dragging state in the layout
    SeafThumbnailFlowLayout *layout = (SeafThumbnailFlowLayout *)self.thumbnailCollection.collectionViewLayout;
    layout.isDragging = NO;
    
    [layout invalidateLayout];    // Force layout update

    
    // Create index path for scrolling
    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:self.currentIndex inSection:0];
    
    // Animate back to normal layout with proper spacing around selected item
    [UIView animateWithDuration:0.3 animations:^{
        // Update the layout with animation
        [self.thumbnailCollection performBatchUpdates:nil completion:nil];
        
        // Include the selected thumbnail scrolling to center position in the same animation
        [self.thumbnailCollection scrollToItemAtIndexPath:indexPath
                                      atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                              animated:NO]; // Use NO to include in current animation block
    }];
}

// Helper method to find the item nearest to the center and select it
- (void)selectItemNearestToCenter {
    CGFloat contentOffsetX = self.thumbnailCollection.contentOffset.x;
    CGFloat contentSizeWidth = self.thumbnailCollection.contentSize.width;
    CGFloat boundsWidth = self.thumbnailCollection.bounds.size.width;
    CGFloat leftInset = self.thumbnailCollection.contentInset.left;
    CGFloat rightInset = self.thumbnailCollection.contentInset.right;
    NSUInteger itemCount = self.preViewItems.count; // Use the actual count

    // Check if item count is zero to avoid crashes
    if (itemCount == 0) {
        Debug(@"[Gallery] selectItemNearestToCenter called with zero items.");
        return;
    }

    NSIndexPath *forcedIndexPath = nil;

    // Check if scrolled to the absolute beginning (consider floating point inaccuracies)
    if (contentOffsetX <= -leftInset + 0.5) { // Added tolerance
        forcedIndexPath = [NSIndexPath indexPathForItem:0 inSection:0];
        Debug(@"[Gallery] Scrolled to beginning, forcing selection of index 0.");
    }
    // Check if scrolled to the absolute end (consider floating point inaccuracies)
    else if (contentOffsetX >= contentSizeWidth - boundsWidth + rightInset - 0.5) { // Added tolerance
        forcedIndexPath = [NSIndexPath indexPathForItem:itemCount - 1 inSection:0];
        Debug(@"[Gallery] Scrolled to end, forcing selection of index %lu.", (unsigned long)(itemCount - 1));
    }

    NSIndexPath *closestIndexPath = nil;
    if (forcedIndexPath) {
        closestIndexPath = forcedIndexPath;
    } else {
        // Original logic: Calculate the horizontal center of the visible area
        CGFloat centerX = contentOffsetX + (boundsWidth / 2.0);
        CGFloat minDistance = CGFLOAT_MAX;

        CGRect extendedBounds = CGRectInset(self.thumbnailCollection.bounds, -boundsWidth * 0.5, 0); // Extend horizontally by half the bounds width
        NSArray<UICollectionViewLayoutAttributes *> *visibleAttributes = [self.thumbnailCollection.collectionViewLayout layoutAttributesForElementsInRect:extendedBounds];

        if (visibleAttributes.count == 0) {
            // Handle case where no attributes are returned (e.g., during rapid scrolling or empty collection)
            Debug(@"[Gallery] No visible attributes found in extended bounds, cannot determine closest item.");
            return;
        }

        for (UICollectionViewLayoutAttributes *attributes in visibleAttributes) {
            // Ensure the index path is valid before accessing it
            if (attributes.indexPath.item < itemCount) {
                CGFloat distance = fabs(attributes.center.x - centerX);
                if (distance < minDistance) {
                    minDistance = distance;
                    closestIndexPath = attributes.indexPath;
                }
            }
        }
        Debug(@"[Gallery] Found closest item via distance calculation: Index %ld", (long)closestIndexPath.item);
    }

    // If no closest item could be determined (should be rare with the checks above), do nothing
    if (!closestIndexPath) {
         Debug(@"[Gallery] Could not determine a closest index path. Aborting selection.");
         return;
    }

    // If a closest item is found and it's not the current one, select it
    if (closestIndexPath && closestIndexPath.item != self.currentIndex) {
        NSUInteger newIndex = closestIndexPath.item;
        
        // Prepare the content view controller for transition
        SeafPhotoContentViewController *toVC = [self contentVCAtIndex:newIndex];
        if (toVC) {
            UIPageViewControllerNavigationDirection direction = (newIndex > self.currentIndex) ? UIPageViewControllerNavigationDirectionForward : UIPageViewControllerNavigationDirectionReverse;
            
            __weak typeof(self) weakSelf = self;
            
            // Update current index and layout configuration immediately
            self.currentIndex = newIndex;
            SeafThumbnailFlowLayout *layout = (SeafThumbnailFlowLayout *)self.thumbnailCollection.collectionViewLayout;
            layout.selectedIndex = newIndex;
            layout.isDragging = NO;
            
            // Perform all animations in a single coordinated animation block
            [UIView animateWithDuration:0.3 animations:^{
                // Layout changes for thumbnail size and spacing
                [layout invalidateLayout];
                [self.thumbnailCollection performBatchUpdates:nil completion:nil];
                
                // Center the thumbnail at the same time
                [self.thumbnailCollection scrollToItemAtIndexPath:closestIndexPath
                                              atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                                      animated:NO]; // Use NO to include in current animation block
            } completion:^(BOOL finished) {
                // After visual changes are complete, perform page transition
                [weakSelf.pageVC setViewControllers:@[toVC]
                                         direction:direction
                                          animated:NO
                                        completion:^(BOOL pageTransitionFinished) {
                    if (pageTransitionFinished) {
                        // Update everything after the page transition
                        weakSelf.currentContentVC = toVC;
                        
                        // Update title based on the new item
                        NSString *titleText;
                        if (weakSelf.preViewItems && newIndex < weakSelf.preViewItems.count) {
                            weakSelf.preViewItem = weakSelf.preViewItems[newIndex];
                            titleText = weakSelf.preViewItem.name;
                        }
                        
                        // Use styling utility to update title view
                        if (titleText) {
                            [SeafNavigationBarStyler updateTitleView:(UILabel *)weakSelf.navigationItem.titleView withText:titleText];
                        }
                        
                        // Update the star button icon based on the new item
                        [weakSelf updateStarButtonIcon];
                        
                        // Update loading range for the new index
                        [weakSelf updateLoadedImagesRangeForIndex:newIndex];
                        [weakSelf loadImagesInCurrentRange];
                        // Update active controllers, cancel unnecessary image loading
                        [weakSelf updateActiveControllersForIndex:newIndex];
                        
                        // Cancel downloads outside the range
                        [weakSelf cancelDownloadsExceptForIndex:newIndex withRange:2];
                    }
                }];
            }];
        } else {
            // Fallback: Directly update the index if VC creation fails (should not happen ideally)
            [self updateSelectedIndex:newIndex];
        }
    } else if (closestIndexPath && closestIndexPath.item == self.currentIndex) {
        // If the closest item is already selected, just ensure it's centered and sized correctly
        SeafThumbnailFlowLayout *layout = (SeafThumbnailFlowLayout *)self.thumbnailCollection.collectionViewLayout;
        layout.isDragging = NO;
        
        // Perform all visual adjustments in a single animation block
        [UIView animateWithDuration:0.3 animations:^{
            // Update layout for correct sizing and spacing
            [layout invalidateLayout];
            [self.thumbnailCollection performBatchUpdates:nil completion:nil];
            
            // Center the item at the same time
            [self.thumbnailCollection scrollToItemAtIndexPath:closestIndexPath
                                          atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                                  animated:NO]; // Use NO to include in current animation block
        }];
    }
}

// Private method declarations
- (void)showDownloadError:(NSString *)fileName {
    // Show an error message using SVProgressHUD
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Failed to download file '%@'", @"Seafile"), fileName];
        [SVProgressHUD showErrorWithStatus:errorMessage];
    });
}

// Update active controllers and cancel unnecessary image requests
- (void)updateActiveControllersForIndex:(NSUInteger)index {
    // Create new set of active controllers (current index and its neighbors)
    NSMutableSet<NSNumber *> *newActiveControllers = [NSMutableSet set];
    
    // Add current index
    if (self.preViewItems.count > 0 && index < self.preViewItems.count) { // Add check for valid index
        [newActiveControllers addObject:@(index)];
    }
    
    // Add one index to the left (if exists and valid)
    if (index > 0) {
        [newActiveControllers addObject:@(index - 1)];
    }
    
    // Add one index to the right (if exists and valid)
    if (index + 1 < self.preViewItems.count) {
        [newActiveControllers addObject:@(index + 1)];
    }
    
    // Find controllers that are no longer active
    NSMutableSet<NSNumber *> *controllersToInactivate = [NSMutableSet setWithSet:self.activeControllers];
    [controllersToInactivate minusSet:newActiveControllers];
    
    // Cancel requests and release resources for inactive controllers
    for (NSNumber *key in controllersToInactivate) {
        NSUInteger controllerIndex = [key unsignedIntegerValue];
        SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:key];
        
        if (vc) {
            // Cancel any ongoing loading or download
            Debug(@"[Gallery] Canceling image loading for controller %ld, name: %@", (long)controllerIndex, vc.seafFile.name);
            [vc cancelImageLoading];
            
            // Optionally release loaded image memory (optional)
            [vc releaseImageMemory];
        }
        
        // Remove from loading status dictionary
        [self.loadingStatusDict removeObjectForKey:key];
        
        // Remove from download progress dictionary
        [self.downloadProgressDict removeObjectForKey:key];
    }
    
    // Update active controllers set
    self.activeControllers = newActiveControllers;
    
    Debug(@"[Gallery] Updated active controllers: %@", self.activeControllers);
}

/**
 * Cancel file downloads outside the specified index range
 * @param currentIndex The currently active index
 * @param range The range to keep around the current index (number of items to the left and right)
 */
- (void)cancelDownloadsExceptForIndex:(NSInteger)currentIndex withRange:(NSInteger)range {
    if (!self.preViewItems || self.preViewItems.count == 0) {
        return;
    }
    
    Debug(@"[Gallery] Canceling downloads outside index %ld range, keeping range: %ld", (long)currentIndex, (long)range);
    
    // Calculate the range to keep
    NSInteger startIndex = MAX(0, currentIndex - range);
    NSInteger endIndex = MIN(self.preViewItems.count - 1, currentIndex + range);
    
    // Iterate through all preview items
    for (NSInteger i = 0; i < self.preViewItems.count; i++) {
        // Skip items within the range to keep
        if (i >= startIndex && i <= endIndex) {
            continue;
        }
        
        // Get the cached view controller
        NSNumber *key = @(i);
        SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:key];
        
        // Cancel download if the view controller exists
        if (vc) {
            Debug(@"[Gallery] Canceling download for index %ld", (long)i);
            [vc cancelImageLoading];
            continue;
        }
        
        // If the item is a SeafFile, cancel the download directly
        id<SeafPreView> item = self.preViewItems[i];
        if ([item isKindOfClass:[SeafFile class]]) {
            SeafFile *file = (SeafFile *)item;
            [file cancelDownload];
            Debug(@"[Gallery] Directly canceled file download: %@", file.name);
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    BOOL isBeingDismissed = [self isBeingDismissed] || [self isMovingFromParentViewController];
    if (!isBeingDismissed) {
        // Original logic for non-dismissal disappearance:
        for (NSNumber *key in [self.contentVCCache allKeys]) { // Iterate a copy
            NSUInteger controllerIndex = [key unsignedIntegerValue];
            // Only cancel requests for images that are not the current one, and not its immediate neighbors
            BOOL isCurrentOrNeighbor = (controllerIndex == self.currentIndex ||
                                       (self.currentIndex > 0 && controllerIndex == self.currentIndex - 1) ||
                                       (controllerIndex == self.currentIndex + 1));

            if (!isCurrentOrNeighbor) {
                SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:key];
                if (vc) {
                    Debug(@"[Gallery] viewWillDisappear: Canceling image loading for non-visible/non-neighbor VC at index %lu", (unsigned long)controllerIndex);
                    [vc cancelImageLoading];
                }
            }
        }
    }
}

// Add new method for updating overlay visibility
- (void)updateThumbnailOverlaysVisibility {
    if (!self.thumbnailCollection || self.thumbnailCollection.hidden || self.preViewItems.count == 0) { // Added self.thumbnailCollection.hidden
        self.leftThumbnailOverlay.hidden = YES;
        self.rightThumbnailOverlay.hidden = YES;
        return;
    }

    CGFloat contentOffsetX = self.thumbnailCollection.contentOffset.x;
    CGFloat contentWidth = self.thumbnailCollection.contentSize.width;
    CGFloat boundsWidth = self.thumbnailCollection.bounds.size.width;
    // Effective scrollable width, considering content insets.
    // The thumbnailCollection has horizontal insets (left:10, right:10 from sectionInset)
    // These insets are part of the scrollable content area, not the contentSize directly for this calculation.
    // Simpler check: if contentSize.width is greater than bounds.width.
    
    CGFloat Epsilon = 1.0; // Increased epsilon for more robust edge detection

    BOOL canScrollLeft = contentOffsetX > Epsilon;
    BOOL canScrollRight = contentOffsetX + boundsWidth < contentWidth - Epsilon;
    
    // If the total content width is less than or equal to the bounds, no scrolling is possible.
    if (contentWidth <= boundsWidth + Epsilon) { // Add Epsilon here too
        self.leftThumbnailOverlay.hidden = YES;
        self.rightThumbnailOverlay.hidden = YES;
    } else {
        self.leftThumbnailOverlay.hidden = !canScrollLeft;
        self.rightThumbnailOverlay.hidden = !canScrollRight;
    }
}

// Add UIScrollViewDelegate method
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.thumbnailCollection) {
        [self updateThumbnailOverlaysVisibility];
    }
}

// New helper method to synchronize overlay frames and visibility
- (void)synchronizeOverlayFramesAndVisibilityWithThumbnailCollectionFrame:(CGRect)targetThumbnailCollectionFrame isAnimatingReveal:(BOOL)isAnimatingReveal {
    CGFloat overlayWidth = 25.0; // Width is defined here

    // Set frames for the overlay views
    self.leftThumbnailOverlay.frame = CGRectMake(targetThumbnailCollectionFrame.origin.x,
                                                 targetThumbnailCollectionFrame.origin.y,
                                                 overlayWidth,
                                                 targetThumbnailCollectionFrame.size.height);
    self.rightThumbnailOverlay.frame = CGRectMake(CGRectGetMaxX(targetThumbnailCollectionFrame) - overlayWidth,
                                                  targetThumbnailCollectionFrame.origin.y,
                                                  overlayWidth,
                                                  targetThumbnailCollectionFrame.size.height);

    // Update gradient layer frames to match new overlay bounds
    if (self.leftThumbnailOverlay.layer.sublayers.count > 0) {
        CAGradientLayer *leftSubGradient = (CAGradientLayer *)self.leftThumbnailOverlay.layer.sublayers.firstObject;
        if ([leftSubGradient isKindOfClass:[CAGradientLayer class]]) {
            leftSubGradient.frame = self.leftThumbnailOverlay.bounds;
        }
    }
    if (self.rightThumbnailOverlay.layer.sublayers.count > 0) {
        CAGradientLayer *rightSubGradient = (CAGradientLayer *)self.rightThumbnailOverlay.layer.sublayers.firstObject;
        if ([rightSubGradient isKindOfClass:[CAGradientLayer class]]) {
            rightSubGradient.frame = self.rightThumbnailOverlay.bounds;
        }
    }

    if (isAnimatingReveal) {
        // During reveal animation, ensure overlays are not hidden so they can animate into view.
        // Alpha is handled by the animation block.
        self.leftThumbnailOverlay.hidden = NO;
        self.rightThumbnailOverlay.hidden = NO;
    } else {
        // For all other cases (layout, scroll, or animation completion), update visibility based on scroll state.
        [self updateThumbnailOverlaysVisibility];
    }
}

#pragma mark - SeafPhotoContentDelegate

- (void)photoContentViewControllerRequestsRetryForFile:(id<SeafPreView>)file atIndex:(NSUInteger)index {
    Debug(@"[Gallery] Received retry request for file: %@ at index: %lu", file.name, (unsigned long)index);
    
    if (!file || index >= self.preViewItems.count || self.preViewItems[index] != file) {
        Debug(@"[Gallery] Invalid retry request: File mismatch or index out of bounds.");
        // Optionally, inform the specific content VC that retry cannot proceed.
        SeafPhotoContentViewController *contentVC = [self.contentVCCache objectForKey:@(index)];
        if (contentVC) {
            [contentVC hideLoadingIndicator]; // Hide its indicator
            [contentVC showErrorImage];     // Show error again
        }
        return;
    }

    // Ensure the content VC shows its loading indicator if it was hidden by the retry tap
    // (though the contentVC itself calls showLoadingIndicator before calling delegate)
    SeafPhotoContentViewController *contentVC = [self.contentVCCache objectForKey:@(index)];
    if (contentVC && !contentVC.activityIndicator.isAnimating) {
         [contentVC showLoadingIndicator];
    }

    // Logic to re-attempt loading the file.
    // This typically means calling [file load:...] again.
    // We might want to use `force:YES` for a retry if the file system or cache state might be stale.
    if ([file isKindOfClass:[SeafFile class]]) {
        SeafFile *seafFile = (SeafFile *)file;
        
        // Reset any previous error state for the file if necessary, e.g. if it had a specific error property.
        // seafFile.lastError = nil; // Example if SeafFile tracks errors

        Debug(@"[Gallery] Retrying load for file: %@", seafFile.name);
        // Setting the delegate again is important if it was cleared on a previous failure/cancel
        if (seafFile.delegate != self) {
             seafFile.delegate = self;
        }
        [seafFile load:self force:YES]; // Using force:YES for retry
    }
    // If it's an UploadFile, its getImageWithCompletion is usually self-contained for retries or reflects its current state.
    // However, if there was a more fundamental load issue, this is where you might handle it.
    else if ([file isKindOfClass:[SeafUploadFile class]]) {
        Debug(@"[Gallery] Retrying for SeafUploadFile: %@. This typically involves its internal retry or re-fetching logic via getImageWithCompletion.", file.name);
        // For SeafUploadFile, the loadImage in contentVC typically handles it.
        // If a more forceful retry is needed, specific logic for SeafUploadFile would go here.
        // For now, we assume that if the contentVC calls loadImage again after delegate call, it will work.
        // Or, we can directly ask the content VC to try loading again.
        if (contentVC) {
            [contentVC loadImage]; // Ask the content view controller to attempt loading again.
        } else {
            // If no contentVC, it's harder to trigger its specific load.
            // This case should be rare if the retry came from an active VC.
        }
    }
}

@end

