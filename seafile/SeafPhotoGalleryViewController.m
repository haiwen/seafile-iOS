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
#import "SeafMotionPhotoExtractor.h"
#import "SeafLivePhotoSaver.h"
#import "SeafPGThumbnailCell.h" // Added import
#import "SeafPGThumbnailCellViewModel.h" // Added import
#import "SeafFileViewController.h"
#import "SeafPhotoHeroAnimator.h"
#import "SeafPhotoPagingView.h"
#import "SeafPhotoPageContainer.h"

// Define an enum for toolbar button types
typedef NS_ENUM(NSInteger, SeafPhotoToolbarButtonType) {
    SeafPhotoToolbarButtonTypeDownload,
    SeafPhotoToolbarButtonTypeDelete,
    SeafPhotoToolbarButtonTypeInfo,
    SeafPhotoToolbarButtonTypeStar,
    SeafPhotoToolbarButtonTypeShare
};

/// iOS-Photos-style horizontal thumbnail strip layout.
///
/// State is split into two ORTHOGONAL axes — matches the real iOS Photos
/// behavior where cells are uniformly small while sliding, and only the
/// settled cell expands to a square thumbnail:
///
///   1. `fractionalSelectedIndex` ∈ [0, count-1] — which cell is
///      "logically centered". Drives `centeringContentOffsetXForFraction:`
///      so the strip's contentOffset can be slid in real time during
///      pager drag (cell N vs cell N+1 interpolated by alpha = f - N).
///      DOES NOT affect cell widths.
///
///   2. `expandedIndex` (NSInteger, -1 = none) + `expansionProgress`
///      (CGFloat 0..1) — which single cell is "selected" and how much
///      it's grown. ONLY this cell can have width > wMin; the rest are
///      always wMin. Settling kicks off `expansionProgress: 0 → 1` in a
///      UIView animation block (cells animate via UICollectionView's
///      built-in invalidateLayout-in-animation pattern). Any new scroll
///      collapses it back to 0 first.
///
/// Width formula:
///   width(i) = lerp(wMin, thumbnailHeight,
///                   expandedIndex == i ? expansionProgress : 0)
///   The expanded cell becomes a square (height × height), matching iOS
///   Photos. Aspect-ratio-aware widths are intentionally NOT supported —
///   iOS Photos itself center-crops the selected thumbnail into a square,
///   and our `SeafPGThumbnailCell` does the same via
///   `UIViewContentModeScaleAspectFill + clipsToBounds`.
///
/// Spacing formula (between cells i and i+1):
///   spacing(i, i+1) = lerp(defaultSpacing, selectedSpacing,
///                          max(s(i), s(i+1)))
///   where s(k) = (expandedIndex == k ? expansionProgress : 0).
///
/// Legacy callers that wrote `selectedIndex` (NSInteger) still work via
/// the compat shim — it forwards to `expandedIndex`.
@interface SeafThumbnailFlowLayout : UICollectionViewFlowLayout

#pragma mark - State axis 1: which cell is logically centered (drives offset only)
@property (nonatomic, assign) CGFloat fractionalSelectedIndex;

#pragma mark - State axis 2: which cell is expanded and by how much (drives widths)
@property (nonatomic, assign) NSInteger expandedIndex;     // -1 == none
@property (nonatomic, assign) CGFloat expansionProgress;   // 0..1

#pragma mark - Geometry constants
@property (nonatomic, assign) CGFloat thumbnailHeight;     // 42 (also == expanded cell width)
@property (nonatomic, assign) CGFloat wMin;                // 28 (== height * 2/3)
@property (nonatomic, assign) CGFloat defaultSpacing;      // 4
@property (nonatomic, assign) CGFloat selectedSpacing;     // 13
@property (nonatomic, assign) UIEdgeInsets sectionInsets;  // (1.5, 10, 1.5, 10)

#pragma mark - Compat shims (legacy callsites)
@property (nonatomic, assign) NSInteger selectedIndex;     // forwards to expandedIndex
@property (nonatomic, assign) CGFloat defaultSpacingValue; // legacy alias
@property (nonatomic, assign) CGFloat spacingAroundSelectedItem; // legacy alias
@property (nonatomic, assign) BOOL isDragging;             // ignored; kept for compat

#pragma mark - Geometry queries (stateless; do NOT mutate cache)

/// Centering content offset.x that places cell N..N+1 (interpolated by
/// alpha=f-N) at `boundsWidth/2`. Self-contained — does not require
/// prepareLayout to have run. Uses current `expandedIndex` /
/// `expansionProgress` for cell widths.
- (CGFloat)centeringContentOffsetXForFraction:(CGFloat)f boundsWidth:(CGFloat)bw;

/// Inverse of `centeringContentOffsetXForFraction:`. Binary search;
/// O(N * iters) but iters is fixed at 50 so still cheap for typical
/// album sizes.
- (CGFloat)fractionForCenteringContentOffsetX:(CGFloat)x boundsWidth:(CGFloat)bw;

/// Width that cell `idx` will currently render at, taking expansion
/// state into account. Useful for centering-inset calculation.
- (CGFloat)currentWidthForIndex:(NSInteger)idx;

@end

@implementation SeafThumbnailFlowLayout {
    NSMutableArray<NSValue *> *_cellFrames;     // cached after prepareLayout
    CGSize _computedContentSize;
    // Cache key: cell frames are a function of these three plus
    // `expandedIndex` / `expansionProgress`. Fraction is NOT a key
    // because it doesn't affect cell sizing.
    CGFloat _cachedExpansionProgress;
    NSInteger _cachedExpandedIndex;
    CGFloat _cachedBoundsWidth;
    NSInteger _cachedCount;
}

- (instancetype)init {
    if (self = [super init]) {
        _fractionalSelectedIndex = 0;
        _expandedIndex = 0;        // first cell is the default "selected" target
        _expansionProgress = 1.0;  // initial state: selected cell is fully expanded
        _thumbnailHeight = 42;
        _wMin = _thumbnailHeight * 2.0 / 3.0;        // 28
        _defaultSpacing = 4.0;
        _selectedSpacing = 13.0;
        _sectionInsets = UIEdgeInsetsMake(1.5, 10, 1.5, 10);
        _cachedExpansionProgress = -1;
        _cachedExpandedIndex = NSIntegerMin;
        _cachedBoundsWidth = -1;
        _cachedCount = -1;
        self.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    }
    return self;
}

#pragma mark - Compat shims

- (void)setSelectedIndex:(NSInteger)v {
    self.expandedIndex = v;
    self.fractionalSelectedIndex = (CGFloat)v;
}
- (NSInteger)selectedIndex { return self.expandedIndex; }

- (void)setDefaultSpacingValue:(CGFloat)v { self.defaultSpacing = v; }
- (CGFloat)defaultSpacingValue { return self.defaultSpacing; }
- (void)setSpacingAroundSelectedItem:(CGFloat)v { self.selectedSpacing = v; }
- (CGFloat)spacingAroundSelectedItem { return self.selectedSpacing; }

- (void)setIsDragging:(BOOL)v { /* no-op: expansion model doesn't need this */ }
- (BOOL)isDragging { return NO; }

#pragma mark - Setters that invalidate

- (void)setFractionalSelectedIndex:(CGFloat)v {
    // Doesn't affect cell sizes — cache stays valid. Just record.
    if (_fractionalSelectedIndex == v) return;
    _fractionalSelectedIndex = v;
}

- (void)setExpandedIndex:(NSInteger)v {
    if (_expandedIndex == v) return;
    _expandedIndex = v;
    [self invalidateLayout];
}

- (void)setExpansionProgress:(CGFloat)v {
    if (v < 0) v = 0; else if (v > 1) v = 1;
    if (_expansionProgress == v) return;
    _expansionProgress = v;
    [self invalidateLayout];
}

#pragma mark - Geometry primitives

static inline CGFloat seaf_lerp(CGFloat a, CGFloat b, CGFloat t) { return a + (b - a) * t; }

/// "Selectedness" of cell `i`: nonzero only for the single expanded
/// cell, scaled by `expansionProgress`. Returns 0 during scroll
/// (progress=0), 1 for the fully-expanded selected cell at rest.
- (CGFloat)expansionStrengthForIndex:(NSInteger)i {
    if (self.expandedIndex < 0 || i != self.expandedIndex) return 0;
    return self.expansionProgress;
}

- (CGFloat)widthForIndex:(NSInteger)i {
    CGFloat s = [self expansionStrengthForIndex:i];
    if (s <= 0) return self.wMin;
    // Selected cell expands to a square (height × height) — matches
    // iOS Photos. AR-aware widths are intentionally not modeled; see
    // class docstring above.
    return seaf_lerp(self.wMin, self.thumbnailHeight, s);
}

- (CGFloat)spacingBetweenIndex:(NSInteger)i andIndex:(NSInteger)j {
    CGFloat sLeft  = [self expansionStrengthForIndex:i];
    CGFloat sRight = [self expansionStrengthForIndex:j];
    CGFloat s = MAX(sLeft, sRight);
    if (s <= 0) return self.defaultSpacing;
    return seaf_lerp(self.defaultSpacing, self.selectedSpacing, s);
}

- (CGFloat)currentWidthForIndex:(NSInteger)i {
    return [self widthForIndex:i];
}

#pragma mark - prepareLayout / cache

- (NSInteger)numberOfItems {
    UICollectionView *cv = self.collectionView;
    if (!cv) return 0;
    if ([cv numberOfSections] == 0) return 0;
    return [cv numberOfItemsInSection:0];
}

- (void)prepareLayout {
    [super prepareLayout];

    UICollectionView *cv = self.collectionView;
    if (!cv) {
        _cellFrames = nil;
        _computedContentSize = CGSizeZero;
        return;
    }

    NSInteger count = [self numberOfItems];
    CGFloat bw = cv.bounds.size.width;

    if (_cellFrames
        && _cachedCount == count
        && _cachedBoundsWidth == bw
        && _cachedExpandedIndex == self.expandedIndex
        && _cachedExpansionProgress == self.expansionProgress) {
        return; // cache hit — nothing changed
    }

    NSMutableArray<NSValue *> *frames = [NSMutableArray arrayWithCapacity:MAX(count, 1)];
    CGFloat h = self.thumbnailHeight;
    CGFloat y = self.sectionInsets.top;
    CGFloat x = self.sectionInsets.left;

    if (count == 0) {
        _cellFrames = frames;
        _computedContentSize = CGSizeMake(self.sectionInsets.left + self.sectionInsets.right,
                                           h + self.sectionInsets.top + self.sectionInsets.bottom);
    } else {
        for (NSInteger i = 0; i < count; i++) {
            if (i > 0) {
                x += [self spacingBetweenIndex:i - 1 andIndex:i];
            }
            CGFloat w = [self widthForIndex:i];
            [frames addObject:[NSValue valueWithCGRect:CGRectMake(x, y, w, h)]];
            x += w;
        }
        x += self.sectionInsets.right;
        _cellFrames = frames;
        _computedContentSize = CGSizeMake(x, h + self.sectionInsets.top + self.sectionInsets.bottom);
    }

    _cachedCount = count;
    _cachedBoundsWidth = bw;
    _cachedExpandedIndex = self.expandedIndex;
    _cachedExpansionProgress = self.expansionProgress;
}

- (CGSize)collectionViewContentSize {
    return _computedContentSize;
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSMutableArray<UICollectionViewLayoutAttributes *> *out = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)_cellFrames.count; i++) {
        CGRect frame = [_cellFrames[i] CGRectValue];
        if (CGRectIntersectsRect(frame, rect)) {
            UICollectionViewLayoutAttributes *attr =
                [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:
                    [NSIndexPath indexPathForItem:i inSection:0]];
            attr.frame = frame;
            [out addObject:attr];
        }
    }
    return out;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger i = indexPath.item;
    if (i < 0 || i >= (NSInteger)_cellFrames.count) return nil;
    UICollectionViewLayoutAttributes *attr =
        [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
    attr.frame = [_cellFrames[i] CGRectValue];
    return attr;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    // Pure scrolling (origin change) doesn't affect cell frames in our
    // model — they're authored in content coordinates. Only re-prepare
    // when the visible width actually changes (rotation / resize).
    return !CGSizeEqualToSize(newBounds.size, self.collectionView.bounds.size);
}

- (void)invalidateLayout {
    // Bust the cache so the next prepareLayout recomputes cell frames
    // after any explicit invalidate call (e.g. rotation, count change).
    _cellFrames = nil;
    _cachedExpandedIndex = NSIntegerMin;
    _cachedExpansionProgress = -1;
    [super invalidateLayout];
}

#pragma mark - Stateless geometry queries

/// Walk index 0..N+1 to compute the centers of cells N and N+1 under
/// the CURRENT expansion state (cell widths come from `widthForIndex:`,
/// not affected by `f`). Returns N=⌊f⌋ and alpha=f-N so the caller can
/// lerp between the two centers. Doesn't touch `_cellFrames` cache.
- (void)_centerOfCellsAtFraction:(CGFloat)f
                           count:(NSInteger)count
                     outCenterN:(CGFloat *)outCenterN
                   outCenterN1:(CGFloat *)outCenterN1
                          outN:(NSInteger *)outN
                      outAlpha:(CGFloat *)outAlpha {
    CGFloat clamped = MAX(0, MIN((CGFloat)(count - 1), f));
    NSInteger N = (NSInteger)floor(clamped);
    CGFloat alpha = clamped - (CGFloat)N;

    CGFloat x = self.sectionInsets.left;
    CGFloat cN = 0, cN1 = 0;
    NSInteger upper = MIN(count - 1, N + 1);
    for (NSInteger i = 0; i <= upper; i++) {
        if (i > 0) {
            x += [self spacingBetweenIndex:i - 1 andIndex:i];
        }
        CGFloat w = [self widthForIndex:i];
        CGFloat center = x + w / 2.0;
        if (i == N)     cN  = center;
        if (i == N + 1) cN1 = center;
        x += w;
    }
    if (N + 1 >= count) cN1 = cN;
    if (outCenterN)  *outCenterN  = cN;
    if (outCenterN1) *outCenterN1 = cN1;
    if (outN)        *outN        = N;
    if (outAlpha)    *outAlpha    = alpha;
}

- (CGFloat)centeringContentOffsetXForFraction:(CGFloat)f boundsWidth:(CGFloat)bw {
    NSInteger count = [self numberOfItems];
    if (count == 0) return 0;
    CGFloat cN = 0, cN1 = 0, alpha = 0;
    NSInteger N = 0;
    [self _centerOfCellsAtFraction:f count:count
                        outCenterN:&cN outCenterN1:&cN1
                              outN:&N outAlpha:&alpha];
    CGFloat centerX = cN * (1.0 - alpha) + cN1 * alpha;
    return centerX - bw / 2.0;
}

- (CGFloat)fractionForCenteringContentOffsetX:(CGFloat)x boundsWidth:(CGFloat)bw {
    NSInteger count = [self numberOfItems];
    if (count <= 1) return 0;
    CGFloat lo = 0, hi = (CGFloat)(count - 1);
    // 50 iterations bound the error to (count-1)/2^50 ~ 0 for any
    // realistic count; we exit early once the bracket is < 1/256 of a
    // step which is well below sub-pixel resolution.
    for (int i = 0; i < 50; i++) {
        CGFloat mid = (lo + hi) * 0.5;
        CGFloat midX = [self centeringContentOffsetXForFraction:mid boundsWidth:bw];
        if (midX < x) lo = mid; else hi = mid;
        if (hi - lo < (1.0 / 256.0)) break;
    }
    return (lo + hi) * 0.5;
}

@end

@interface SeafPhotoGalleryViewController ()
  <SeafPhotoPagingViewDataSource,
   SeafPhotoPagingViewDelegate,
   UICollectionViewDataSource,
   UICollectionViewDelegate,
   UICollectionViewDelegateFlowLayout,
   UIScrollViewDelegate,
   SeafDentryDelegate>

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

#pragma mark - Thumbnail strip state (iOS-Photos-style)

/// True while the user is actively dragging the thumbnail strip — we
/// reverse-bind its contentOffset back to the pager during the gesture.
/// Mutually exclusive with `pagerDriving` via the state-machine table
/// in the plan.
@property (nonatomic, assign) BOOL thumbDriving;

/// True while we are programmatically writing the thumbnail strip's
/// contentOffset from `pagingView:didScrollToOffset:`. Suppresses the
/// strip's own `scrollViewDidScroll:` from firing the inverse binding
/// and creating an infinite loop.
@property (nonatomic, assign) BOOL pagerDriving;

/// iOS-Photos-style strip scrubbing: while `thumbDriving` is YES, the
/// big photo pager only swaps when the centered thumbnail crosses an
/// integer boundary, instead of co-scrolling fractionally. This tracks
/// the most recently-jumped-to integer index so we don't re-jump on
/// every scroll frame. Reset to NSNotFound on settle / drag-begin.
@property (nonatomic, assign) NSUInteger stripScrubDisplayedIndex;

/// One-shot guard set ONLY around the very first programmatic
/// `setCurrentIndex:animated:NO` in `settleInitialPageIfNeeded`.
///
/// Why this exists: when the gallery is opened on a non-zero index
/// (the normal case — user taps the 5th photo in a grid), the initial
/// pager-positioning write moves contentOffset from 0 → currentIndex *
/// pageWidth. UIKit synchronously dispatches `scrollViewDidScroll:`,
/// which routes through `pagingView:didScrollToOffset:` and would
/// `collapseStripAnimated:YES` the strip — only for the immediately
/// following `didSettleAtIndex:` to re-`expandStripForIndex:animated:YES`
/// it back. The visible result is a ~0.6s "shrink → spring back"
/// flicker on first appearance.
///
/// While this flag is YES the pager→strip live binding is short-circuited.
/// The strip was already created in its expanded resting state by
/// `setupThumbnailStrip` (`expansionProgress = 1`, `expandedIndex =
/// currentIndex`), so suppressing the binding leaves it visually
/// stable; the subsequent settle's `expandStripForIndex:` becomes a
/// visual no-op that only re-centers the contentOffset.
@property (nonatomic, assign) BOOL isPerformingInitialPagerSettle;

#pragma mark - Hero dismiss state

/// The active interactive transition during a pull-down dismiss. nil at all
/// other times. Built in `photoContentViewControllerDidBeginDismissDrag:`,
/// consumed by UIKit via `interactionControllerForDismissal:`, then released
/// once the transition finishes / is cancelled.
@property (nonatomic, strong, nullable) SeafPhotoInteractiveDismiss *activeInteractive;

/// Hero context shared between the interactive controller and the animator.
/// Captured at gesture start so target frame / corner radius / contentMode
/// are stable for the whole transition.
@property (nonatomic, strong, nullable) SeafPhotoHeroContext *activeHeroContext;

/// Cached starting alpha of UI chrome (navbar/toolbar/thumb strip/overlays)
/// so we can scale them with the drag progress and snap them back exactly
/// on cancel.
@property (nonatomic, assign) CGFloat chromeBaselineAlpha;

/// Backing storage for `isChromeHidden`. Single source of truth — never
/// write to it directly outside `setChromeHidden:animated:reason:`.
@property (nonatomic, assign, readwrite) BOOL isChromeHidden;

// Private method declarations
- (void)showDownloadError:(NSString *)fileName;
- (void)dismissGalleryAnimated:(BOOL)animated;
- (UIWindow *)heroReferenceWindow;

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
        _thumbDriving = NO;
        _pagerDriving = NO;
        _stripScrubDisplayedIndex = NSNotFound;
        
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
    self.view.backgroundColor = [UIColor colorWithRed:254/255.0 green:255/255.0 blue:255/255.0 alpha:1.0]; // #FEFFFF

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
    
    // Set up paging view and thumbnail strip
    [self setupPagingView];
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

    CGRect prevPagingFrame = self.pagingView.frame;

    // Position the thumbnail collection and toolbar at the bottom of the screen
    CGRect bounds = self.view.bounds;
    CGFloat stripHeight = 45; // Use the fixed strip height
    CGFloat toolbarHeight = 44;
    CGFloat safeAreaBottom = 0;
    
    if (@available(iOS 11.0, *)) {
        safeAreaBottom = self.view.safeAreaInsets.bottom;
    }

    Debug(@"[ZoomBug] gallery.viewDidLayoutSubviews bounds=%@ safeArea=%@ "
          @"isChromeHidden=%d prevPagingFrame=%@",
          NSStringFromCGRect(bounds),
          NSStringFromUIEdgeInsets(self.view.safeAreaInsets),
          self.isChromeHidden,
          NSStringFromCGRect(prevPagingFrame));
    
    // Adjust the location of the thumbnail collection
    CGRect thumbnailFrame = CGRectMake(0,
                                      bounds.size.height - stripHeight - toolbarHeight - safeAreaBottom, // Use stripHeight
                                      bounds.size.width,
                                      stripHeight); // Use stripHeight
    self.thumbnailCollection.frame = thumbnailFrame;
    
    // Position the paging view so it extends `interPageSpacing` past the
    // screen edges (shifted left by halfSpacing). With `pageWidth = stride
    // = screenW + spacing` and each page rendered at width `screenW`
    // centered within its stride, the inter-page gap naturally falls off
    // both screen edges. Result: no left/right margin around photos, only
    // a visible gap between adjacent photos during transitions.
    CGFloat interSpacing = self.pagingView.interPageSpacing;
    CGFloat halfSpacing  = interSpacing / 2.0;
    self.pagingView.frame = CGRectMake(-halfSpacing,
                                        0,
                                        bounds.size.width + interSpacing,
                                        bounds.size.height);

    // Patch H + K: idempotent reload (no-op when bounds.size and pageCount
    // are unchanged) followed by initial-page settle on the first frame
    // where bounds is non-zero. Done here (NOT in viewDidLoad) so the Hero
    // present animation captures a fully laid-out paging view.
    [self.pagingView reloadPagesIfNeeded];
    [self settleInitialPageIfNeeded];

    // Toolbar always stays at the bottom, including safe area
    CGRect toolbarFrame = CGRectMake(0,
                                    bounds.size.height - toolbarHeight - safeAreaBottom,
                                    bounds.size.width,
                                    toolbarHeight + safeAreaBottom); // Include safe area in height
    self.toolbarView.frame = toolbarFrame;

    [self synchronizeOverlayFramesAndVisibilityWithThumbnailCollectionFrame:self.thumbnailCollection.frame isAnimatingReveal:NO];

    [self.view bringSubviewToFront:self.leftThumbnailOverlay];
    [self.view bringSubviewToFront:self.rightThumbnailOverlay];

    // [self updateThumbnailOverlaysVisibility]; // This is now called by the helper method
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    // Patch I: rotation can land mid-handoff if the user starts a paging
    // gesture and then rotates. Snap back so the alongside-animation
    // re-layouts on a clean integer page offset.
    [self.pagingView cancelHandoffIfNeeded];

    NSUInteger snapshotIndex = self.currentIndex;

    // A rotation can race with an in-flight strip drag (e.g. handoff
    // active, decelerating). Force-clear binding flags + recenter so we
    // don't land in a stuck `thumbDriving` state with the new bounds.
    [self resetThumbnailDraggingState];

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // Force layout update — viewDidLayoutSubviews will resize the paging
        // view and reflow alive pages to the new bounds, then settle current.
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
        // Recompute the constant centering inset for the new bounds.
        [self applyConstantCenteringInset];
        // Recenter the strip first (under the new bounds) so the
        // alongside animation interpolates the strip's contentOffset
        // and the pager's snap together.
        [self centerThumbnailForIndex:snapshotIndex animated:NO];
        // Re-snap to the current page after the new bounds.size took effect,
        // so the contentOffset matches the new pageWidth.
        [self.pagingView setCurrentIndex:snapshotIndex animated:NO];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // No completion-time scroll: the alongside block already centered
        // the strip and snapped the pager. `applyPageSettleAtIndex:`
        // (fired by the pager's didSettleAtIndex: delegate) will perform
        // any final cleanup needed.
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Ensure the navigation bar is visible — and reset the chrome state
    // machine to "visible" up front so the first tap doesn't read a stale
    // hidden flag from a previous gallery presentation.
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    self.navigationController.navigationBar.alpha = 1.0;
    self.isChromeHidden = NO;

    // Wrapper nav controller is presented with `UIModalPresentationOverFullScreen`,
    // which by default does NOT route status bar appearance to the presented
    // VC. Opt in so our `prefersStatusBarHidden` / `preferredStatusBarStyle`
    // overrides actually drive the system status bar.
    self.navigationController.modalPresentationCapturesStatusBarAppearance = YES;
    [self setNeedsStatusBarAppearanceUpdate];

    // Use styling utility to set navigation bar style
    [SeafNavigationBarStyler applyStandardAppearanceToNavigationController:self.navigationController];
}

#pragma mark - Layout Subviews

/// Patch K: create-only setup. We must not attach pages here because
/// `self.view.bounds` is not final yet (the navigation controller hasn't
/// laid out its child yet). The first real page attachment happens from
/// `viewDidLayoutSubviews` → `reloadPagesIfNeeded` + `settleInitialPageIfNeeded`.
- (void)setupPagingView {
    // The paging view's frame is set up in viewDidLayoutSubviews (it must
    // extend `interPageSpacing` past the screen edges so the inter-page gap
    // falls off-screen instead of leaving a margin around each photo).
    // Initialize to view.bounds for the very first layout pass; the real
    // frame is applied below.
    self.pagingView = [[SeafPhotoPagingView alloc] initWithFrame:self.view.bounds];
    // Manage frame manually in viewDidLayoutSubviews — autoresizing would
    // override the negative-x offset on rotation.
    self.pagingView.autoresizingMask = UIViewAutoresizingNone;
    self.pagingView.pagingDataSource = self;
    self.pagingView.pagingDelegate = self;
    self.pagingView.interPageSpacing = 20.0;
    self.pagingView.backgroundColor = [UIColor colorWithRed:249/255.0 green:249/255.0 blue:249/255.0 alpha:1.0]; // #F9F9F9
    [self.view addSubview:self.pagingView];

    if (self.preViewItems.count > 0 && self.currentIndex < self.preViewItems.count) {
        // Make sure the alive range / image preloads are seeded so the first
        // attachment (in viewDidLayoutSubviews) can fetch the right images.
        [self updateLoadedImagesRangeForIndex:self.currentIndex];
        [self loadImagesInCurrentRange];
    }
}

/// First-time positioning: called from viewDidLayoutSubviews. Idempotent.
- (void)settleInitialPageIfNeeded {
    if (self.preViewItems.count == 0) return;
    if (self.pagingView.pageWidth <= 0) return; // bounds still zero
    NSUInteger desired = self.currentIndex;
    if (desired >= self.preViewItems.count) {
        desired = self.preViewItems.count - 1;
    }

    // If the contentOffset already lines up with the desired page AND the
    // currentContentVC is set, this is a no-op.
    CGFloat expected = (CGFloat)desired * self.pagingView.pageWidth;
    BOOL alreadyPositioned = (fabs(self.pagingView.contentOffset.x - expected) < 0.5)
                          && (self.currentContentVC != nil)
                          && (self.currentContentVC.pageIndex == desired);
    if (alreadyPositioned) return;

    // Suppress the pager→strip live binding for the duration of this
    // single programmatic positioning call. See
    // `isPerformingInitialPagerSettle` docs for the full rationale —
    // without this guard the strip would visibly collapse-then-expand
    // on first appearance whenever currentIndex != 0.
    self.isPerformingInitialPagerSettle = YES;
    [self.pagingView setCurrentIndex:desired animated:NO];
    self.isPerformingInitialPagerSettle = NO;

    // The setCurrentIndex above triggered the alive-window attach; pick up
    // the now-attached current contentVC and announce it as visible the
    // first time.
    SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:@(desired)];
    if (vc && vc != self.currentContentVC) {
        SeafPhotoContentViewController *previous = self.currentContentVC;
        self.currentContentVC = vc;
        if (previous && previous != vc) {
            [previous didResignCurrentVisiblePage];
        }
        [vc didBecomeCurrentVisiblePage];
    }
}

- (void)setupThumbnailStrip {
    // Set thumbnail height
    self.thumbnailHeight = 42; // Thumbnail height is 42
    
    // Create custom flow layout (iOS-Photos-style fractional model)
    SeafThumbnailFlowLayout *layout = [[SeafThumbnailFlowLayout alloc] init];
    layout.thumbnailHeight = self.thumbnailHeight;
    layout.wMin = self.thumbnailHeight * 2.0 / 3.0;     // 28
    layout.defaultSpacing = 4.0;
    layout.selectedSpacing = 13.0;
    layout.sectionInsets = UIEdgeInsetsMake(1.5, 10, 1.5, 10);
    layout.fractionalSelectedIndex = (CGFloat)self.currentIndex;
    // Initial state: selected cell is fully expanded. Any subsequent
    // scroll (pager or strip) will collapse `expansionProgress` → 0
    // first; settle re-expands it to 1.
    layout.expandedIndex = (NSInteger)self.currentIndex;
    layout.expansionProgress = 1.0;

    // Create collection view
    CGFloat stripHeight = 45; // Total height is fixed at 45
    CGRect frame = CGRectMake(0, self.view.bounds.size.height - stripHeight, self.view.bounds.size.width, stripHeight);
    self.thumbnailCollection = [[UICollectionView alloc] initWithFrame:frame collectionViewLayout:layout];
    self.thumbnailCollection.backgroundColor = [UIColor colorWithRed:254/255.0 green:255/255.0 blue:255/255.0 alpha:1.0]; // #FEFFFF
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
    
    // Apply the constant centering inset (based on wMin) once now —
    // it stays valid until the strip's bounds change.
    [self applyConstantCenteringInset];

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
    
    // Re-expand the new index to its true wAR width. The expand helper
    // wraps cell-frame + centering + fractional snap in a single spring
    // animation so the previous cell shrinks back to wMin and the new
    // cell grows simultaneously. No `reloadData` / `reloadItems` —
    // selection has no per-cell visual (no border / highlight); the
    // size change is driven entirely by `expandedIndex` /
    // `expansionProgress` on the layout, and the thumbnail image is
    // refreshed via the viewModel's onUpdate callback. Reloading here
    // would trigger UICollectionView's default crossfade animation,
    // producing a visible fade-in flicker on the affected cells.
    [self expandStripForIndex:index animated:YES];

    // Update active controllers, cancel unnecessary image loading
    [self updateActiveControllersForIndex:index];
    
    // Cancel downloads outside the range
    [self cancelDownloadsExceptForIndex:index withRange:2];
    
    Debug(@"[Gallery] Updated selected index from %ld to %ld", (long)oldIndex, (long)index);
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    NSUInteger idx = ip.item;
    if (idx == self.currentIndex) return;
    [self goToIndex:idx animated:YES];
}

#pragma mark - Centralized programmatic page change

/// Single entry-point for every programmatic page change (thumbnail tap,
/// delete, file update completion, etc.). Routes through the paging view's
/// queueing logic so a background event cannot interrupt an in-flight
/// user gesture (Patch §3.11.6).
- (void)goToIndex:(NSUInteger)index animated:(BOOL)animated {
    if (self.preViewItems.count == 0) return;
    if (index >= self.preViewItems.count) {
        index = self.preViewItems.count - 1;
    }
    [self.pagingView setCurrentIndex:index animated:animated];
}

/// Internal helper: applies all post-settle bookkeeping for a new index.
/// Called from `pagingView:didSettleAtIndex:byUserGesture:` AND from the
/// initial `settleInitialPageIfNeeded` flow.
- (void)applyPageSettleAtIndex:(NSUInteger)newIdx byUserGesture:(BOOL)byUser {
    if (newIdx >= self.preViewItems.count) return;

    SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:@(newIdx)];
    if (!vc) {
        // Should not happen — paging view always attaches alive ± 1 around
        // the new current index before firing settle.
        Debug(@"[Gallery] applyPageSettleAtIndex:%lu — no cached VC, recreating",
              (unsigned long)newIdx);
        vc = [self viewControllerAtIndex:newIdx];
    }

    NSUInteger oldIndex = self.currentIndex;
    self.currentIndex = newIdx;

    [self updateLoadedImagesRangeForIndex:newIdx];
    [self loadImagesInCurrentRange];
    [self updateActiveControllersForIndex:newIdx];
    [self cancelDownloadsExceptForIndex:newIdx withRange:2];

    SeafPhotoContentViewController *previousVC = self.currentContentVC;
    self.currentContentVC = vc;
    if (previousVC && previousVC != vc) {
        [previousVC didResignCurrentVisiblePage];

        // Reset zoom on the page we just left so it's at default scale
        // when the user comes back to it.
        if (previousVC.isZoomedIn) {
            previousVC.isConfiguringLayout = YES;
            [previousVC.scrollView setZoomScale:previousVC.scrollView.minimumZoomScale animated:NO];
            previousVC.isConfiguringLayout = NO;
        }
    }
    [vc didBecomeCurrentVisiblePage];

    // Sync thumbnail strip — settle the fractional model to the integer
    // newIdx, then expand the new cell to its true aspect ratio. NO
    // `reloadData` / `reloadItems` here:
    //   • cells have no per-selection visual styling (no border /
    //     highlight) — selection is expressed purely by the layout's
    //     `expandedIndex` driving cell width;
    //   • thumbnail images are refreshed via the viewModel's onUpdate
    //     callback, not reload;
    //   • `reloadItemsAtIndexPaths:` would trigger UICollectionView's
    //     default cell crossfade, which is visible as a fade-in
    //     flicker on the strip every time the user swipes pages.
    // Strip ownership flags are released here because settle marks the
    // end of any active drag/follow interaction.
    self.thumbDriving = NO;
    self.pagerDriving = NO;
    self.stripScrubDisplayedIndex = NSNotFound;
    // expandStripForIndex: snaps fractionalSelectedIndex inside its
    // animation block — no need to assign it here.
    //
    // Initial-positioning path: when this settle is fired synchronously
    // from `settleInitialPageIfNeeded` (one-shot guard set), expand
    // without animation. The strip was already set up in its expanded
    // resting state (`expansionProgress = 1`, `expandedIndex = newIdx`),
    // so the only meaningful side-effect of expandStripForIndex: here
    // is `centerThumbnailForIndex:animated:NO` — and inside an animated
    // expand's UIView block that NO is overridden, causing the strip to
    // visibly slide from offset 0 to the centered position over the
    // spring's 0.45s. With animated:NO the centering write happens
    // immediately and silently, which is what we want for first paint.
    BOOL animateExpand = !self.isPerformingInitialPagerSettle;
    [self expandStripForIndex:newIdx animated:animateExpand];

    // Sync title + star
    NSString *titleText = nil;
    if (self.preViewItems && newIdx < self.preViewItems.count) {
        self.preViewItem = self.preViewItems[newIdx];
        titleText = self.preViewItem.name;
    } else {
        titleText = NSLocalizedString(@"View Photos", @"Seafile");
    }
    [SeafNavigationBarStyler updateTitleView:(UILabel *)self.navigationItem.titleView withText:titleText];
    [self updateStarButtonIcon];
    [self updateThumbnailOverlaysVisibility];

    // After landing on a freshly settled page (and resetting the prior
    // page's zoom above), the new active page is at zoomScale = 1, so
    // outer paging is once again the right gesture target. Re-enable —
    // the inner zoom view will toggle it back off via
    // `photoContentViewControllerDidBeginZooming:` if the user re-zooms.
    self.pagingView.scrollEnabled = YES;

    Debug(@"[Gallery] Page settled %lu→%lu (byUser=%d), loaded range: %@",
          (unsigned long)oldIndex, (unsigned long)newIdx, byUser,
          NSStringFromRange(self.loadedImagesRange));
}

#pragma mark - SeafPhotoPagingView DataSource & content VC factory

- (NSUInteger)numberOfPagesInPagingView:(SeafPhotoPagingView *)view {
    return self.preViewItems.count;
}

- (UIView *)pagingView:(SeafPhotoPagingView *)view pageContainerForIndex:(NSUInteger)index {
    SeafPhotoContentViewController *contentVC = [self viewControllerAtIndex:index];
    if (!contentVC) return nil;

    // Patch §3.11.4: assign explicit pageIndex (replaces view.tag).
    contentVC.pageIndex = index;

    // Look for an existing container for this VC (it may already be in the
    // hierarchy from a previous attach). Reuse if found.
    SeafPhotoPageContainer *container = nil;
    for (UIView *parent = contentVC.view.superview; parent != nil; parent = parent.superview) {
        if ([parent isKindOfClass:[SeafPhotoPageContainer class]]) {
            container = (SeafPhotoPageContainer *)parent;
            break;
        }
    }
    if (!container) {
        container = [[SeafPhotoPageContainer alloc] initWithFrame:CGRectZero];
    }
    container.pageIndex = index;
    container.contentVC = contentVC;

    // Patch §3.11.3: manual child VC lifecycle (replaces UIPageViewController
    // doing this automatically). Skip the addChildViewController dance if
    // we're already a child, otherwise UIKit asserts.
    if (contentVC.parentViewController != self) {
        if (contentVC.parentViewController) {
            [contentVC willMoveToParentViewController:nil];
            [contentVC.view removeFromSuperview];
            [contentVC removeFromParentViewController];
        }
        [self addChildViewController:contentVC];
    }
    if (contentVC.view.superview != container) {
        contentVC.view.frame = container.bounds;
        contentVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [container addSubview:contentVC.view];
    }
    if (contentVC.parentViewController == self) {
        [contentVC didMoveToParentViewController:self];
    }

    // Patch §3.11.4: pre-sync infoVisible + immersive background to match
    // the gallery state BEFORE the page becomes visible. Migrated from the
    // old UIPageViewController willTransitionToViewControllers: callback.
    if (contentVC.infoVisible != self.infoVisible) {
        [contentVC toggleInfoView:self.infoVisible animated:NO];
    }
    if (self.isChromeHidden) {
        contentVC.view.backgroundColor = [UIColor blackColor];
        contentVC.scrollView.backgroundColor = [UIColor blackColor];
    }

    return container;
}

- (void)pagingView:(SeafPhotoPagingView *)view recyclePageContainer:(UIView *)container atIndex:(NSUInteger)index {
    if (![container isKindOfClass:[SeafPhotoPageContainer class]]) {
        [container removeFromSuperview];
        return;
    }
    SeafPhotoPageContainer *box = (SeafPhotoPageContainer *)container;
    SeafPhotoContentViewController *contentVC = box.contentVC;
    if (contentVC) {
        // Patch §3.11.3: tear down child VC relationship cleanly.
        [contentVC willMoveToParentViewController:nil];
        [contentVC.view removeFromSuperview];
        [contentVC removeFromParentViewController];

        // Mirror the old UIPageViewController behavior: the contentVC stays
        // alive in `contentVCCache`, but we cancel non-current loads via
        // `updateActiveControllersForIndex:` (already handled on page settle).
    }
    box.contentVC = nil;
    box.pageIndex = NSNotFound;
    [container removeFromSuperview];
}

#pragma mark - SeafPhotoPagingView Delegate

- (void)pagingView:(SeafPhotoPagingView *)view willBeginNavigatingFromIndex:(NSUInteger)index {
    // User started a pager drag — collapse the strip's expanded cell
    // back to uniform wMin so all thumbnails are the same size while
    // sliding (matches iOS Photos). Settle re-expands the new cell.
    [self collapseStripAnimated:YES];
}

- (void)pagingView:(SeafPhotoPagingView *)view didSettleAtIndex:(NSUInteger)index byUserGesture:(BOOL)byUser {
    [self applyPageSettleAtIndex:index byUserGesture:byUser];
}

/// pager → strip live binding. Fires for every paging scroll frame
/// (user drag, programmatic animated change, even mid-handoff zoom-pan)
/// so the thumbnail strip mirrors the pager's contentOffset in real
/// time — matches the iOS Photos bottom-strip experience.
///
/// Suppressed when `thumbDriving` is set: the thumbnail strip is the
/// authority and the pager is the follower in that direction; without
/// this guard the two views would feedback-loop on every scroll frame.
- (void)pagingView:(SeafPhotoPagingView *)view didScrollToOffset:(CGPoint)offset {
    if (self.thumbDriving) return;
    if (!self.thumbnailCollection) return;
    if (self.preViewItems.count == 0) return;
    // Initial-positioning guard: skip the pager→strip live binding
    // during the one-shot programmatic offset write performed by
    // `settleInitialPageIfNeeded`. Otherwise the strip — which was
    // created already-expanded at currentIndex — would collapse here
    // and then re-expand from `applyPageSettleAtIndex:`, producing the
    // visible flicker. See `isPerformingInitialPagerSettle` docs.
    if (self.isPerformingInitialPagerSettle) return;

    CGFloat pw = view.pageWidth;
    if (pw <= 0) return;

    CGFloat f = offset.x / pw;
    NSInteger maxIdx = (NSInteger)self.preViewItems.count - 1;
    if (maxIdx < 0) return;
    f = MAX(0, MIN((CGFloat)maxIdx, f));

    SeafThumbnailFlowLayout *layout = (SeafThumbnailFlowLayout *)self.thumbnailCollection.collectionViewLayout;

    // Defensive: programmatic pager scrolls (tap thumbnail → goToIndex)
    // don't trigger willBeginNavigatingFromIndex:, so collapse here too.
    // Idempotent — no-op once expansionProgress is already 0.
    if (layout.expansionProgress != 0.0) {
        [self collapseStripAnimated:YES];
    }

    layout.fractionalSelectedIndex = f;

    CGFloat bw = self.thumbnailCollection.bounds.size.width;
    if (bw <= 0) return;
    CGFloat targetX = [layout centeringContentOffsetXForFraction:f boundsWidth:bw];

    // Suppress the strip's own scrollViewDidScroll: from triggering the
    // inverse binding while we apply the pager-driven offset.
    self.pagerDriving = YES;
    [self.thumbnailCollection setContentOffset:CGPointMake(targetX, 0) animated:NO];
    self.pagerDriving = NO;

    [self updateThumbnailOverlaysVisibility];
}

#pragma mark - Content VC factory

- (SeafPhotoContentViewController *)viewControllerAtIndex:(NSUInteger)index {
    if (index >= self.preViewItems.count) {
        return nil;
    }

    // Check if this page is already cached
    NSNumber *key = @(index);
    SeafPhotoContentViewController *cachedController = [self.contentVCCache objectForKey:key];
    if (cachedController) {
        // Call prepareForReuse to clean up any existing state
        DebugZoom(@"[EdgeDebug] viewControllerAtIndex:%ld — calling prepareForReuse on cached VC, current bg=%@",
              (long)index, cachedController.view.backgroundColor);
        [cachedController prepareForReuse];
        DebugZoom(@"[EdgeDebug] viewControllerAtIndex:%ld — after prepareForReuse, bg=%@",
              (long)index, cachedController.view.backgroundColor);
        
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
    
    // Patch §3.11.4: prefer explicit pageIndex over view.tag.
    contentController.pageIndex = index;
    contentController.delegate = self; // Set the gallery as the delegate
    
    // Store in cache
    [self.contentVCCache setObject:contentController forKey:key];
    
    // If currently in immersive mode (zoomed viewing), set black bg on new VC
    // so it's ready before UIPageViewController displays it.
    if (self.isChromeHidden) {
        contentController.view.backgroundColor = [UIColor blackColor];
        contentController.scrollView.backgroundColor = [UIColor blackColor];
    }
    
    Debug(@"Created content VC for index %ld, immersive=%d", (long)index, self.isChromeHidden);
    
    return contentController;
}

- (SeafPhotoContentViewController*)contentVCAtIndex:(NSUInteger)idx {
    return [self viewControllerAtIndex:idx];
}

#pragma mark - UICollectionViewDelegateFlowLayout
//
// NOTE: cell sizing and inter-item spacing are now fully owned by
// `SeafThumbnailFlowLayout` (fractional iOS-Photos-style model). The old
// `sizeForItemAtIndexPath:` / `minimumInteritemSpacingForSectionAtIndex:` /
// `insetForSectionAtIndex:` delegate hooks have been removed — they would
// override the layout's interpolated frames mid-swipe and reintroduce the
// binary "selected vs unselected" snap.

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
        // Cell expansion is square (height × height) regardless of the
        // underlying photo's aspect ratio — matches iOS Photos. The cell
        // itself center-crops via UIViewContentModeScaleAspectFill, so
        // no AR plumbing is needed here.
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
        // Get file path - prefer exportURL (contains full file with embedded video for Motion Photos)
        NSURL *exportURL = file.exportURL;
        NSString *path = exportURL ? exportURL.path : file.cachePath;
        BOOL exists = path ? [[NSFileManager defaultManager] fileExistsAtPath:path] : NO;
        
        if (exists) {
            // File already downloaded, save to album directly
            [self saveFileToAlbumAtPath:path file:file];
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
                    // Get file path after download - prefer exportURL
                    NSURL *downloadedExportURL = file.exportURL;
                    NSString *downloadedPath = downloadedExportURL ? downloadedExportURL.path : file.cachePath;
                    [self saveFileToAlbumAtPath:downloadedPath file:file];
                }
            }];
            [SeafDataTaskManager.sharedObject addFileDownloadTask:file];
        }
    }];
}

// Save file to album - handles both regular images and Motion Photos (Live Photos)
- (void)saveFileToAlbumAtPath:(NSString *)path file:(SeafFile *)file {
    // Check if this is a Motion Photo (Live Photo) - HEIC format with embedded video
    if ([SeafLivePhotoSaver canSaveAsLivePhotoAtPath:path]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [SVProgressHUD showInfoWithStatus:NSLocalizedString(@"Saving Live Photo to album", @"Seafile")];
        });
        [self saveLivePhotoToAlbum:file atPath:path];
        return;
    }
    
    // Regular image save
    UIImage *img = [UIImage imageWithContentsOfFile:path];
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

#pragma mark - Live Photo Save (Motion Photo to iOS Live Photo)

/**
 * Save a Motion Photo (HEIC with embedded video) as iOS Live Photo to the photo library.
 * Uses SeafLivePhotoSaver for the actual save operation.
 */
- (void)saveLivePhotoToAlbum:(SeafFile *)file atPath:(NSString *)path {
    NSString *fileName = file.name;
    
    [SeafLivePhotoSaver saveLivePhotoFromPath:path completion:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Succeeded to save %@ to album", @"Seafile"), fileName]];
            } else {
                [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to save %@ to album", @"Seafile"), fileName]];
            }
        });
    }];
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

            NSUInteger deletedItemIndex = [self.preViewItems indexOfObject:file]; // Get index before potential async operation
            if (deletedItemIndex == NSNotFound) {
                Debug(@"[Gallery] Error: File to delete '%@' not found in preViewItems before calling masterVc. Aborting deletion.", file.name);
                // Show an error to the user or simply return.
                [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Error preparing to delete '%@'", @"Seafile"), file.name]];
                return;
            }

            // Use the new deleteFile:completion: method
            if ([self.masterVc isKindOfClass:[SeafFileViewController class]]) {
                SeafFileViewController *fileVC = (SeafFileViewController *)self.masterVc;
                [fileVC deleteFile:file completion:^(BOOL success, NSError *error) {
                    if (success) {
                        // Proceed with UI update for the gallery only if masterVc confirms success
                        [self handleSuccessfulDeletionOfFile:file atOriginalIndex:deletedItemIndex];
                    } else {
                        // Handle deletion failure reported by masterVc
                        Debug(@"[Gallery] MasterVc reported failure to delete file: %@, error: %@", file.name, error);
                        NSString *errMsg = error.localizedDescription ?: [NSString stringWithFormat:NSLocalizedString(@"Failed to delete '%@'", @"Seafile"), file.name];
                        [SVProgressHUD showErrorWithStatus:errMsg];
                    }
                }];
            } else {
                // Fallback or error handling if masterVc is not the expected type
                Debug(@"[Gallery] Error: masterVc is not of type SeafFileViewController. Cannot call deleteFile:completion:. Perform selector as fallback if available, or show error.");
                // This part of the fallback might be removed if strict typing is enforced and SeafFileViewController is always expected.
                if ([self.masterVc respondsToSelector:@selector(deleteFile:)]) {
                     // Perform selector without completion, UI will update optimistically as before this series of changes.
                    [self.masterVc performSelector:@selector(deleteFile:) withObject:file];
                    // Optimistic UI update (consider if this is desired for this fallback path)
                    [self handleSuccessfulDeletionOfFile:file atOriginalIndex:deletedItemIndex];
                } else {
                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Cannot delete file: Action not supported.", @"Seafile")];
                }
            }
        }
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"Seafile") style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// New private method to handle UI updates after successful deletion
- (void)handleSuccessfulDeletionOfFile:(id<SeafPreView>)deletedFile atOriginalIndex:(NSUInteger)deletedItemIndex {
    // 1. Update data sources
    NSMutableArray<id<SeafPreView>> *mutablePreViewItems = [self.preViewItems mutableCopy];
    // Since we passed deletedItemIndex, we use that.
    if (deletedItemIndex < mutablePreViewItems.count) {
        [mutablePreViewItems removeObjectAtIndex:deletedItemIndex];
    } else {
        Debug(@"[Gallery] Error: deletedItemIndex %lu is out of bounds for preViewItems (count %lu) during UI update.", (unsigned long)deletedItemIndex, (unsigned long)mutablePreViewItems.count);
        // This case should be rare if logic is correct up to this point.
        return;
    }
    self.preViewItems = [mutablePreViewItems copy];

    // Also update infoModels if it corresponds by index and is in use
    if (self.infoModels.count > deletedItemIndex) {
        NSMutableArray *mutableInfoModels = [self.infoModels mutableCopy];
        [mutableInfoModels removeObjectAtIndex:deletedItemIndex];
        self.infoModels = [mutableInfoModels copy];
    }
    
    // Clean up caches related to the deleted item's original index. If the
    // deleted VC is currently attached to the paging view, detach it first
    // so child-VC lifecycle stays clean.
    NSNumber *deletedItemOriginalKey = @(deletedItemIndex);
    SeafPhotoContentViewController *deletedVC = [self.contentVCCache objectForKey:deletedItemOriginalKey];
    if (deletedVC && deletedVC.parentViewController == self) {
        [deletedVC willMoveToParentViewController:nil];
        [deletedVC.view.superview removeFromSuperview]; // remove the page container
        [deletedVC.view removeFromSuperview];
        [deletedVC removeFromParentViewController];
    }
    [self.contentVCCache removeObjectForKey:deletedItemOriginalKey];
    [self.downloadProgressDict removeObjectForKey:deletedItemOriginalKey];
    [self.loadingStatusDict removeObjectForKey:deletedItemOriginalKey];

    // Re-key any cached VCs whose original index sat above the deletion point.
    NSArray<NSNumber *> *cachedKeysCopy = [self.contentVCCache.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *k in cachedKeysCopy) {
        NSUInteger oldIdx = k.unsignedIntegerValue;
        if (oldIdx > deletedItemIndex) {
            SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:k];
            [self.contentVCCache removeObjectForKey:k];
            NSUInteger newIdx = oldIdx - 1;
            vc.pageIndex = newIdx;
            [self.contentVCCache setObject:vc forKey:@(newIdx)];
        }
    }

    // 2. Determine the new current index for selection
    NSUInteger newCurrentIndex;
    if (self.preViewItems.count == 0) {
        // If all items are deleted, then dismiss the gallery.
        [self dismissGallery];
        return;
    } else if (deletedItemIndex >= self.preViewItems.count) {
        // If the last item was deleted (or index is now out of bounds due to deletion), select the new last item.
        newCurrentIndex = self.preViewItems.count - 1;
    } else {
        // Otherwise, the item at the deletedItemIndex is now the new item to select.
        newCurrentIndex = deletedItemIndex;
    }
    
    // 3. Update internal state for the new current item
    self.currentIndex = newCurrentIndex;
    // Ensure preViewItems has items before trying to access an element
    if (newCurrentIndex < self.preViewItems.count) {
        self.preViewItem = self.preViewItems[newCurrentIndex];
    } else {
        Debug(@"[Gallery] Critical Error: newCurrentIndex %lu is out of bounds for preViewItems after deletion. Dismissing.", (unsigned long)newCurrentIndex);
        [self dismissGallery];
        return;
    }


    // 4. Update Thumbnail Collection
    NSIndexPath *indexPathOfDeletedItem = [NSIndexPath indexPathForItem:deletedItemIndex inSection:0];
    __weak typeof(self) weakSelf = self; // Use weakSelf for blocks to avoid retain cycles

    [self.thumbnailCollection performBatchUpdates:^{
        if (deletedItemIndex < [weakSelf.thumbnailCollection numberOfItemsInSection:0]) {
             [weakSelf.thumbnailCollection deleteItemsAtIndexPaths:@[indexPathOfDeletedItem]];
        } else {
            Debug(@"[Gallery] Thumbnail deletion skipped: indexPath for deleted item (%@) seems invalid for current collection state.", indexPathOfDeletedItem);
            // Calling [self.thumbnailCollection reloadData] might be a safer fallback in the completion,
        }
    } completion:^(BOOL finished) {
        __strong typeof(weakSelf) strongSelf = weakSelf; // Re-strongify self for use inside the block
        if (!strongSelf || !finished) {
            // If animation didn't finish or self is deallocated, abort further UI updates.
            if (!finished) Debug(@"[Gallery] Thumbnail deletion animation did not complete.");
            return;
        }

        // 5. Re-flow the paging view around the new current index. After the
        // delete, the page count shrunk and the existing alive containers'
        // contentSize must be recomputed. `reloadPages` (non-idempotent
        // variant) forces it; we then explicitly apply the settle for the
        // new index because setCurrentIndex no-ops when the paging view
        // already considered itself on that index.
        NSUInteger settledIndex = strongSelf.currentIndex;
        // currentIndex above was already mutated; reset paging view's
        // internal state to NSNotFound-equivalent so setCurrentIndex
        // unconditionally drives a fresh settle.
        strongSelf.currentIndex = NSNotFound;
        [strongSelf.pagingView reloadPages];
        [strongSelf.pagingView setCurrentIndex:settledIndex animated:NO];
        [strongSelf applyPageSettleAtIndex:settledIndex byUserGesture:NO];
    }];
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
                    // Use template rendering mode
                    image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    
                    // Calculate the target size while maintaining aspect ratio
                    CGFloat iconSize = 20.0;
                    CGSize originalSize = image.size;
                    CGFloat aspectRatio = originalSize.width / originalSize.height;
                    CGFloat targetWidth, targetHeight;
                    
                    if (aspectRatio >= 1.0) {
                        targetWidth = iconSize;
                        targetHeight = iconSize / aspectRatio;
                    } else {
                        targetHeight = iconSize;
                        targetWidth = iconSize * aspectRatio;
                    }
                    
                    // Resize icon while maintaining aspect ratio
                    UIGraphicsBeginImageContextWithOptions(CGSizeMake(targetWidth, targetHeight), NO, 0.0);
                    [image drawInRect:CGRectMake(0, 0, targetWidth, targetHeight)];
                    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
                    UIGraphicsEndImageContext();
                    
                    resizedImage = [resizedImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    
                    // Update button icon
                    [btn setImage:resizedImage forState:UIControlStateNormal];
                    btn.imageView.contentMode = UIViewContentModeScaleAspectFit;
                    
                    // Set tintColor: gray (#666666) for all states (selected states differ by icon style, not color)
                    btn.tintColor = [UIColor colorWithRed:102.0/255.0 green:102.0/255.0 blue:102.0/255.0 alpha:1.0]; // Gray #666666
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
    [self dismissGalleryAnimated:YES];
}

#pragma mark - Rotation lock

// Lock rotation while the user is interactively dismissing — a mid-flight
// rotation invalidates all the cached frames the Hero animator depends on.
- (BOOL)shouldAutorotate {
    return self.activeInteractive == nil;
}

- (void)dismissGalleryAnimated:(BOOL)animated {
    // 1. Cancel all pending network operations and clear callbacks
    [self cancelAllPendingFileOperations];

    // 2. Release resources held by Content View Controllers
    for (NSNumber *key in [self.contentVCCache allKeys]) {
        SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:key];
        if (vc) {
            [vc releaseImageMemory];
        }
    }
    [self.contentVCCache removeAllObjects];

    // 3. Clear active controllers set
    [self.activeControllers removeAllObjects];

    // 4. Dismiss the view controller
    if (self.navigationController) {
        [self.navigationController dismissViewControllerAnimated:animated completion:nil];
    } else if (self.presentingViewController) {
        [self dismissViewControllerAnimated:animated completion:nil];
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
    // Tear down each child content VC (mirrors paging view's recycle path).
    for (NSNumber *key in [self.contentVCCache allKeys]) {
        SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:key];
        if (vc.parentViewController == self) {
            [vc willMoveToParentViewController:nil];
            [vc.view removeFromSuperview];
            [vc removeFromParentViewController];
        }
    }

    // Release the paging view
    if (self.pagingView) {
        [self.pagingView removeFromSuperview];
        self.pagingView = nil;
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
    if (!self.pagingView || self.preViewItems.count == 0 || self.currentIndex >= self.preViewItems.count) return;

    [self updateLoadedImagesRangeForIndex:self.currentIndex];
    [self loadImagesInCurrentRange];

    // Centralized programmatic page change. The paging view's settle
    // callback will dispatch `applyPageSettleAtIndex:` so title/thumbnail/
    // star icon stay in sync.
    [self goToIndex:self.currentIndex animated:NO];
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
        if (self.currentContentVC.pageIndex == fileIndex) {
             vc = self.currentContentVC;
             Debug(@"[Gallery] Applying update to currentContentVC for file '%@' at index %lu.", file.name, (unsigned long)fileIndex);
             // Ensure currentContentVC also has the latest file object
             vc.seafFile = file;
             vc.connection = file.connection;
        } else {
            Debug(@"[Gallery] WARNING: currentContentVC pageIndex (%lu) does not match expected index (%lu) for file '%@'. Cannot apply update via currentContentVC.", (unsigned long)self.currentContentVC.pageIndex, (unsigned long)fileIndex, file.name);
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
    BOOL vcFoundOrHandled = ([self.contentVCCache objectForKey:key] != nil) || (fileIndex == self.currentIndex && self.currentContentVC && self.currentContentVC.pageIndex == fileIndex);

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
                // Re-route through the centralized programmatic page change so
                // the paging view re-attaches the container if needed.
                [self goToIndex:fileIndex animated:NO];
                SeafPhotoContentViewController *newVC = [self.contentVCCache objectForKey:key];
                if (newVC) {
                    self.currentContentVC = newVC;
                    [newVC loadImage];
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

// Aggressive memory cleanup: only keep the currently viewed image. Previously
// this method was effectively a no-op because re-inserting the existing entry
// did not evict siblings. We now explicitly purge non-current entries and ask
// the paging view to recycle off-screen pages.
- (void)aggressiveMemoryCleanup {
    NSUInteger currentIdx = self.currentIndex;
    NSMutableArray<NSNumber *> *keysToRemove = [NSMutableArray array];
    for (NSNumber *key in [self.contentVCCache.allKeys copy]) {
        if (key.unsignedIntegerValue == currentIdx) continue;
        SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:key];
        if (!vc) continue;
        // Detach from paging view container and tear down child relationship.
        if (vc.parentViewController == self) {
            [vc willMoveToParentViewController:nil];
            [vc.view removeFromSuperview];
            [vc removeFromParentViewController];
        }
        [keysToRemove addObject:key];
    }
    for (NSNumber *key in keysToRemove) {
        [self.contentVCCache removeObjectForKey:key];
    }

    // Ask the paging view to recycle adjacent containers it may still hold.
    [self.pagingView recycleNonAdjacentPages];

    _loadedImagesRange = NSMakeRange(currentIdx, 1);

    Debug(@"Memory warning: cleared %lu non-current cache entries, load range: %@",
          (unsigned long)keysToRemove.count,
          NSStringFromRange(_loadedImagesRange));
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
    [self centerThumbnailForIndex:self.currentIndex animated:animated];
}

/// Writes the strip's constant centering inset based on `wMin` (= the
/// SMALLEST cell width). Since every cell's actual width is in the
/// range [wMin, thumbnailHeight] and `thumbnailHeight < boundsWidth`,
/// this inset always allows the first / last cell — at any expansion
/// state — to reach the visual center via `setContentOffset:`. Keeping
/// the inset CONSTANT removes one variable from the expand/collapse
/// animation block, so UIScrollView never inserts a non-animated
/// contentOffset adjustment when `adjustedContentInset` changes.
///
/// Called from `setupThumbnailStrip` and `viewWillTransitionToSize:`'s
/// alongside block — i.e., only when bounds change.
- (void)applyConstantCenteringInset {
    if (!self.thumbnailCollection) return;
    SeafThumbnailFlowLayout *layout =
        (SeafThumbnailFlowLayout *)self.thumbnailCollection.collectionViewLayout;
    CGFloat bw = self.thumbnailCollection.bounds.size.width;
    if (bw <= 0) return;
    CGFloat sideInset = MAX(0, (bw - layout.wMin) / 2.0);
    UIEdgeInsets ins = self.thumbnailCollection.contentInset;
    if (fabs(ins.left - sideInset) > 0.5 || fabs(ins.right - sideInset) > 0.5) {
        ins.left = sideInset;
        ins.right = sideInset;
        self.thumbnailCollection.contentInset = ins;
    }
}

/// Centers the strip on `index` using the layout's analytical centering
/// offset. Only writes `contentOffset` — the centering inset is set
/// once via `applyConstantCenteringInset` and never animated.
- (void)centerThumbnailForIndex:(NSUInteger)index animated:(BOOL)animated {
    if (!self.thumbnailCollection) return;
    NSInteger count = [self.thumbnailCollection numberOfItemsInSection:0];
    if (count == 0 || (NSInteger)index >= count) return;

    SeafThumbnailFlowLayout *layout = (SeafThumbnailFlowLayout *)self.thumbnailCollection.collectionViewLayout;
    CGFloat bw = self.thumbnailCollection.bounds.size.width;
    if (bw <= 0) return;

    CGFloat targetX = [layout centeringContentOffsetXForFraction:(CGFloat)index
                                                      boundsWidth:bw];
    [self.thumbnailCollection setContentOffset:CGPointMake(targetX, 0)
                                       animated:animated];
}

#pragma mark - Collapse / expand transitions (iOS-Photos-style)

/// Snaps the strip into "scrolling" mode: all cells become uniform wMin
/// width. If `animated` is YES, the cell-frame transition is wrapped in
/// a brief UIView animation so the previously-expanded cell visibly
/// shrinks back to wMin instead of popping. ContentOffset is NOT
/// repositioned — the caller (pager binding or user drag) immediately
/// drives the offset to the new desired position so the visual stays
/// continuous.
///
/// Idempotent: a no-op if `expansionProgress` is already 0.
- (void)collapseStripAnimated:(BOOL)animated {
    SeafThumbnailFlowLayout *layout = (SeafThumbnailFlowLayout *)self.thumbnailCollection.collectionViewLayout;
    if (!layout) return;
    if (layout.expansionProgress == 0.0) return;

    void (^animations)(void) = ^{
        // The setter calls invalidateLayout for us — no need to duplicate.
        layout.expansionProgress = 0.0;
        [self.thumbnailCollection layoutIfNeeded];
    };
    if (animated) {
        [UIView animateWithDuration:0.18
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut
                                  | UIViewAnimationOptionAllowUserInteraction
                                  | UIViewAnimationOptionBeginFromCurrentState
                         animations:animations
                         completion:nil];
    } else {
        animations();
    }
}

/// Expands `index` to its true wAR(index) width. Driven by settle paths
/// (pager settled at a new index, strip drag released on the same
/// index). The animation wraps the cell-frame change, the centering
/// recenter, AND the `fractionalSelectedIndex` snap so all three
/// interpolate together — preventing the "small jump" when fractional
/// jumps from N+0.4 to N at settle time.
- (void)expandStripForIndex:(NSUInteger)index animated:(BOOL)animated {
    SeafThumbnailFlowLayout *layout = (SeafThumbnailFlowLayout *)self.thumbnailCollection.collectionViewLayout;
    if (!layout) return;
    NSInteger count = [self.thumbnailCollection numberOfItemsInSection:0];
    if (count == 0 || (NSInteger)index >= count) return;

    void (^animations)(void) = ^{
        // Setters call invalidateLayout internally; no explicit invalidate.
        layout.expandedIndex = (NSInteger)index;
        layout.expansionProgress = 1.0;
        // Snap fractional → integer INSIDE the animation block so the
        // centering offset target shifts smoothly (UIView interpolates
        // contentOffset.x from current to the new target).
        layout.fractionalSelectedIndex = (CGFloat)index;
        [self centerThumbnailForIndex:index animated:NO];
        [self.thumbnailCollection layoutIfNeeded];
    };
    if (animated) {
        // iOS-Photos uses a soft spring for the settle expand. Damping
        // 0.85 lands without overshoot; 0.45s feels brisk but unhurried.
        [UIView animateWithDuration:0.45
                              delay:0
             usingSpringWithDamping:0.85
              initialSpringVelocity:0
                            options:UIViewAnimationOptionAllowUserInteraction
                                  | UIViewAnimationOptionBeginFromCurrentState
                         animations:animations
                         completion:nil];
    } else {
        animations();
    }
}

/// Convenience: center on the controller's `currentIndex`.
- (void)centerThumbnailForCurrentIndexAnimated:(BOOL)animated {
    [self centerThumbnailForIndex:self.currentIndex animated:animated];
}

/// Resets transient drag/follow flags. Called from rotation, disappear,
/// and any forced-recovery path so a stuck flag can't leave the strip
/// stranded mid-binding.
- (void)resetThumbnailDraggingState {
    self.thumbDriving = NO;
    self.pagerDriving = NO;
    self.stripScrubDisplayedIndex = NSNotFound;
    SeafThumbnailFlowLayout *layout = (SeafThumbnailFlowLayout *)self.thumbnailCollection.collectionViewLayout;
    if (layout) {
        layout.fractionalSelectedIndex = (CGFloat)self.currentIndex;
        // Restore the settled visual: current cell square-expanded, no
        // animation (we're recovering from an interrupted state, not
        // performing a new transition).
        layout.expandedIndex = (NSInteger)self.currentIndex;
        layout.expansionProgress = 1.0;
        [layout invalidateLayout];
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
    self.toolbarView.backgroundColor = [UIColor colorWithRed:254/255.0 green:255/255.0 blue:255/255.0 alpha:1.0]; // #FEFFFF
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
        BOOL isInfoSelected = NO; // Track if this is the selected info icon
        
        // Check current state and update corresponding icon
        if (i == 2 && self.infoVisible) {
            iconName = @"detail_information_selected";// Info icon - use selected icon if info panel is already shown
            isInfoSelected = YES;
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
            // Calculate the target size while maintaining aspect ratio
            CGSize originalSize = image.size;
            CGFloat aspectRatio = originalSize.width / originalSize.height;
            CGFloat targetWidth, targetHeight;
            
            if (aspectRatio >= 1.0) {
                targetWidth = iconSize;
                targetHeight = iconSize / aspectRatio;
            } else {
                targetHeight = iconSize;
                targetWidth = iconSize * aspectRatio;
            }
            
            // Resize icon while maintaining aspect ratio
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(targetWidth, targetHeight), NO, 0.0);
            [image drawInRect:CGRectMake(0, 0, targetWidth, targetHeight)];
            UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            
            // For selected info icon, use original rendering to preserve the dual-color design
            // For other icons, use template rendering mode
            if (isInfoSelected) {
                resizedImage = [resizedImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            } else {
                resizedImage = [resizedImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            }
            [btn setImage:resizedImage forState:UIControlStateNormal];
            btn.imageView.contentMode = UIViewContentModeScaleAspectFit;
            
            // Set tintColor: gray (#666666) for non-selected info icons
            if (!isInfoSelected) {
                btn.tintColor = [UIColor colorWithRed:102.0/255.0 green:102.0/255.0 blue:102.0/255.0 alpha:1.0]; // Gray #666666
            }
            
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
    // Don't trigger info panel when image is zoomed in (swipe should pan the image)
    if (self.currentContentVC.isZoomedIn) return;
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
    // Don't trigger info panel dismiss when image is zoomed in
    if (self.currentContentVC.isZoomedIn) return;
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
                    // Calculate the target size while maintaining aspect ratio
                    CGFloat iconSize = 20.0;
                    CGSize originalSize = image.size;
                    CGFloat aspectRatio = originalSize.width / originalSize.height;
                    CGFloat targetWidth, targetHeight;
                    
                    if (aspectRatio >= 1.0) {
                        targetWidth = iconSize;
                        targetHeight = iconSize / aspectRatio;
                    } else {
                        targetHeight = iconSize;
                        targetWidth = iconSize * aspectRatio;
                    }
                    
                    // Resize icon while maintaining aspect ratio
                    UIGraphicsBeginImageContextWithOptions(CGSizeMake(targetWidth, targetHeight), NO, 0.0);
                    [image drawInRect:CGRectMake(0, 0, targetWidth, targetHeight)];
                    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
                    UIGraphicsEndImageContext();
                    
                    // For selected info icon, use original rendering to preserve the dual-color design
                    // For other icons, use template rendering mode
                    if (selected) {
                        resizedImage = [resizedImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
                    } else {
                        resizedImage = [resizedImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    }
                    
                    // Update button icon
                    [btn setImage:resizedImage forState:UIControlStateNormal];
                    btn.imageView.contentMode = UIViewContentModeScaleAspectFit;
                    
                    // Set tintColor: gray (#666666) for non-selected state
                    if (!selected) {
                        btn.tintColor = [UIColor colorWithRed:102.0/255.0 green:102.0/255.0 blue:102.0/255.0 alpha:1.0];
                    }
                }
                break;
            }
        }
    }
}

#pragma mark - UIScrollViewDelegate (for Thumbnail Collection)
//
// The strip is bound bidirectionally to the pager (see also
// `pagingView:didScrollToOffset:`). The state machine:
//
//   * `thumbDriving == YES`  → user is dragging the strip; the pager
//                              follows. `pagingView:didScrollToOffset:`
//                              is suppressed for the duration.
//   * `pagerDriving == YES`  → set briefly while
//                              `pagingView:didScrollToOffset:` writes
//                              the strip's contentOffset, suppresses
//                              this object's `scrollViewDidScroll:` from
//                              firing the inverse binding.
//
// Both flags are cleared at settle (`applyPageSettleAtIndex:`) and by
// `resetThumbnailDraggingState` on rotation/disappear.

// Called when the user begins dragging
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView != self.thumbnailCollection) return;
    self.thumbDriving = YES;
    // Seed the scrub tracker with the page currently displayed so the
    // first integer crossing actually triggers a jump.
    self.stripScrubDisplayedIndex = self.currentIndex;
    // Collapse the expanded cell so all thumbnails are uniform wMin
    // while the user drags — matches iOS Photos. Settle re-expands.
    [self collapseStripAnimated:YES];
}

// Called when the user lifts their finger after dragging
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (scrollView != self.thumbnailCollection) return;
    if (!decelerate) {
        [self settleThumbDriveAtNearestIndex];
    }
}

// Called when scrolling comes to a complete stop after deceleration
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView != self.thumbnailCollection) return;
    [self settleThumbDriveAtNearestIndex];
}

// Hook for overlay refresh on flick — UICollectionView doesn't always
// fire scrollViewDidScroll: at the very last decelerating frame.
- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView {
    if (scrollView != self.thumbnailCollection) return;
    [self updateThumbnailOverlaysVisibility];
}

// Programmatic `scrollToItemAtIndexPath:animated:YES` ends here without
// going through dragging/deceleration; refresh overlays so left/right
// fades disappear at the strip edges.
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    if (scrollView != self.thumbnailCollection) return;
    [self updateThumbnailOverlaysVisibility];
}

/// Settle path after the user releases the strip: derive the integer
/// index from the current contentOffset's fractional position, drive the
/// pager to that integer (which will fire didSettleAtIndex: → invokes
/// `applyPageSettleAtIndex:` for the final cleanup including
/// `thumbDriving = NO`).
- (void)settleThumbDriveAtNearestIndex {
    if (!self.thumbDriving) return; // already settled (e.g. via reset)
    if (self.preViewItems.count == 0) {
        self.thumbDriving = NO;
        self.stripScrubDisplayedIndex = NSNotFound;
        return;
    }

    SeafThumbnailFlowLayout *layout = (SeafThumbnailFlowLayout *)self.thumbnailCollection.collectionViewLayout;
    CGFloat bw = self.thumbnailCollection.bounds.size.width;
    CGFloat f = [layout fractionForCenteringContentOffsetX:self.thumbnailCollection.contentOffset.x
                                                boundsWidth:bw];
    NSInteger maxIdx = (NSInteger)self.preViewItems.count - 1;
    NSInteger nearest = (NSInteger)round(f);
    if (nearest < 0) nearest = 0;
    if (nearest > maxIdx) nearest = maxIdx;

    Debug(@"[Gallery] thumbDrive settle: f=%.3f → nearest=%ld", f, (long)nearest);

    // Drag is over — clear the scrub tracker so a fresh drag re-seeds it.
    self.stripScrubDisplayedIndex = NSNotFound;

    if ((NSUInteger)nearest == self.currentIndex) {
        // No net page change vs the gallery's last-settled index. The
        // pager may still be parked at nearest (== currentIndex) from
        // mid-drag jumps that ultimately rebounded back. Just re-expand
        // the (still-current) cell to its true wAR and recenter.
        self.thumbDriving = NO;
        [self expandStripForIndex:self.currentIndex animated:YES];
        [self updateThumbnailOverlaysVisibility];
        return;
    }

    // Page change. Two paths to applyPageSettleAtIndex:
    //   1. Pager is still at the OLD index (no mid-drag jumps fired —
    //      e.g. the user only crossed half a thumbnail before releasing).
    //      `setCurrentIndex:animated:NO` will move it and emit
    //      `didSettleAtIndex:`, which routes through the gallery's
    //      `pagingView:didSettleAtIndex:` → `applyPageSettleAtIndex:`.
    //   2. Pager already at `nearest` from in-drag scrub jumps. In that
    //      case `setCurrentIndex` short-circuits (currentIndex == index)
    //      and never emits the delegate, so we fire the settle path
    //      ourselves to give the gallery a chance to clean up
    //      (release VCs, refresh chrome, expand strip cell, etc.).
    //
    // We DON'T animate the pager — the photo on screen already matches
    // the centered thumbnail, so an animated jump would visually rewind
    // and re-cross.
    if (self.pagingView.currentIndex == (NSUInteger)nearest) {
        [self applyPageSettleAtIndex:(NSUInteger)nearest byUserGesture:YES];
    } else {
        [self.pagingView setCurrentIndex:(NSUInteger)nearest animated:NO];
    }
}

#pragma mark - Combined scrollViewDidScroll: (strip & pager paths)

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.thumbnailCollection) return;

    // Always keep the edge overlays in sync with scroll position.
    [self updateThumbnailOverlaysVisibility];

    // If the pager is driving us, this scroll event is the result of
    // our own programmatic write — don't bounce it back.
    if (self.pagerDriving) return;

    // If the user isn't actively dragging the strip, this is either an
    // inertial settle (deceleration) or a programmatic scroll. Update
    // the layout fraction so cell sizes stay in sync, but don't push
    // the pager — wait for settle.
    SeafThumbnailFlowLayout *layout = (SeafThumbnailFlowLayout *)self.thumbnailCollection.collectionViewLayout;
    if (!self.thumbDriving) {
        if (scrollView.isDragging || scrollView.isDecelerating) {
            CGFloat bw = self.thumbnailCollection.bounds.size.width;
            CGFloat f = [layout fractionForCenteringContentOffsetX:scrollView.contentOffset.x
                                                        boundsWidth:bw];
            NSInteger maxIdx = (NSInteger)self.preViewItems.count - 1;
            if (maxIdx >= 0) {
                f = MAX(0, MIN((CGFloat)maxIdx, f));
                layout.fractionalSelectedIndex = f;
            }
        }
        return;
    }

    // ── Strip → pager: discrete scrubber binding (iOS-Photos behavior) ──
    //
    // The strip itself slides smoothly under the user's finger (UIKit
    // owns that), and `fractionalSelectedIndex` keeps driving the
    // selected-cell expansion animation continuously. The big photo,
    // however, must NOT co-scroll fractionally — iOS Photos shows one
    // complete photo at a time, swapping discretely when the centered
    // thumbnail crosses the boundary between two adjacent images.
    //
    // We therefore compute the nearest integer page from the strip's
    // fractional position and jump the pager only when that integer
    // changes. The jump uses `jumpToIndexForStripScrub:` which writes
    // contentOffset directly and updates the alive window, but does NOT
    // fire the settle delegate — settle is reserved for drag-end.
    if (self.preViewItems.count == 0) return;
    CGFloat bw = self.thumbnailCollection.bounds.size.width;
    if (bw <= 0) return;
    CGFloat f = [layout fractionForCenteringContentOffsetX:scrollView.contentOffset.x
                                                boundsWidth:bw];
    NSInteger maxIdx = (NSInteger)self.preViewItems.count - 1;
    f = MAX(0, MIN((CGFloat)maxIdx, f));
    layout.fractionalSelectedIndex = f;

    NSInteger nearest = (NSInteger)round(f);
    if (nearest < 0) nearest = 0;
    if (nearest > maxIdx) nearest = maxIdx;

    if ((NSUInteger)nearest != self.stripScrubDisplayedIndex) {
        self.stripScrubDisplayedIndex = (NSUInteger)nearest;
        [self.pagingView jumpToIndexForStripScrub:(NSUInteger)nearest];
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

// Update active controllers and release image memory of every cached VC
// outside the new active window.
//
// Historically this method only diffed against `self.activeControllers`
// (the previous active window). That was wrong: during a fast strip
// drag the pager's alive-window machinery briefly attaches dozens of
// in-between VCs, each `viewWillAppear:` triggering a full ~16 MB
// `getImageWithCompletion:` decode (IMAGE_MAX_SIZE = 2048). Those
// in-between VCs are NEVER members of `activeControllers` (settle
// doesn't fire mid-drag), so they were skipped here and left holding
// their decoded UIImage — leaking ~16 MB each. Long sessions could
// accumulate hundreds of MB of bitmap data.
//
// Fix: iterate the FULL `contentVCCache` and release any VC's image
// that isn't in the new active window. The new active window equals
// the pager's alive window, so we never touch a currently-visible VC.
- (void)updateActiveControllersForIndex:(NSUInteger)index {
    // Build the new active window: current ± 1.
    NSMutableSet<NSNumber *> *newActiveControllers = [NSMutableSet set];
    if (self.preViewItems.count > 0 && index < self.preViewItems.count) {
        [newActiveControllers addObject:@(index)];
    }
    if (index > 0) {
        [newActiveControllers addObject:@(index - 1)];
    }
    if (index + 1 < self.preViewItems.count) {
        [newActiveControllers addObject:@(index + 1)];
    }

    // Walk EVERY cached VC, not just `self.activeControllers`, so we
    // catch any VC the strip-drag flow briefly attached and decoded
    // an image into.
    NSArray<NSNumber *> *allKeys = [self.contentVCCache.allKeys copy];
    NSUInteger releasedCount = 0;
    for (NSNumber *key in allKeys) {
        if ([newActiveControllers containsObject:key]) continue;

        SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:key];
        if (vc) {
            // Cancel any in-flight download (no-op if image already
            // landed; the decode itself isn't cancellable).
            [vc cancelImageLoading];
            // Drop the decoded UIImage — this is the actual memory win.
            [vc releaseImageMemory];
            releasedCount++;
        }

        [self.loadingStatusDict removeObjectForKey:key];
        [self.downloadProgressDict removeObjectForKey:key];
    }

    self.activeControllers = newActiveControllers;

    if (releasedCount > 0) {
        Debug(@"[Gallery] Released image memory for %lu inactive VC(s); active=%@",
              (unsigned long)releasedCount, self.activeControllers);
    }
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

    // Defensive: if we're going off-screen mid-binding (e.g. user swipes
    // up to dismiss while the strip is decelerating), drop transient
    // flags so the next presentation starts from a clean state.
    [self resetThumbnailDraggingState];

    BOOL isBeingDismissed = [self isBeingDismissed] || [self isMovingFromParentViewController];
    if (isBeingDismissed) {
        // Stop any silent live-photo auto-preview before the gallery goes away.
        if (self.currentContentVC) {
            [self.currentContentVC didResignCurrentVisiblePage];
        }

        // Restore the parent navigation bar so a presenter / pushed-back VC
        // doesn't inherit an alpha=0 / structurally-hidden chrome from us.
        // Skip animation here — dismiss/pop already runs its own transition.
        [self setChromeHidden:NO animated:NO reason:SeafChromeReasonRestore];
        self.navigationController.navigationBar.alpha = 1.0;
        [self.navigationController setNavigationBarHidden:NO animated:NO];
    }
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

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    // The gallery is presented with `UIModalPresentationOverFullScreen` so
    // the source list's `viewWillAppear:` does NOT fire on dismiss — and
    // that's where it normally refreshes per-row download status. Notify
    // the hero provider here instead so it can refresh after every dismiss
    // path (close button, programmatic dismiss, Hero interactive dismiss).
    BOOL dismissed = [self isBeingDismissed]
                  || [self.navigationController isBeingDismissed]
                  || self.presentingViewController == nil;
    if (dismissed
        && [self.heroProvider respondsToSelector:@selector(galleryDidDismissToItem:)]) {
        [self.heroProvider galleryDidDismissToItem:self.preViewItem];
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
    
    // Sub-pixel-aware epsilon: any drift smaller than one device pixel
    // can't actually be perceived, so treat it as "at the edge" and hide
    // the gradient overlay. Without this, programmatic settle scrolls
    // sometimes leave the overlay stuck visible at the very first / last
    // index due to rounding in `setContentOffset:`.
    CGFloat scale = MAX([UIScreen mainScreen].scale, 1.0);
    CGFloat Epsilon = 1.0 / scale;

    // Compensate for centering contentInset when comparing against the
    // beginning of the scroll range: at the leftmost integer position
    // contentOffset.x equals -leftInset, not 0.
    CGFloat leftInset = self.thumbnailCollection.contentInset.left;
    CGFloat rightInset = self.thumbnailCollection.contentInset.right;
    BOOL canScrollLeft  = contentOffsetX > -leftInset + Epsilon;
    BOOL canScrollRight = contentOffsetX + boundsWidth < contentWidth + rightInset - Epsilon;
    
    // If the total content width is less than or equal to the bounds, no scrolling is possible.
    if (contentWidth <= boundsWidth + Epsilon) { // Add Epsilon here too
        self.leftThumbnailOverlay.hidden = YES;
        self.rightThumbnailOverlay.hidden = YES;
    } else {
        self.leftThumbnailOverlay.hidden = !canScrollLeft;
        self.rightThumbnailOverlay.hidden = !canScrollRight;
    }
}

// (Note: `scrollViewDidScroll:` is implemented above in the
//        UIScrollViewDelegate (Thumbnail Collection) section — it now
//        also handles the strip→pager live binding when thumbDriving.)

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

#pragma mark - Chrome (single source of truth)

/// Light gray background used by the gallery and per-page contentVCs in the
/// non-immersive (chrome-visible) state. Kept here as a single constant so
/// the value matches everywhere the page background is reset.
static UIColor *SeafGalleryChromeVisibleBackground(void) {
    return [UIColor colorWithRed:249.0/255.0 green:249.0/255.0 blue:249.0/255.0 alpha:1.0]; // #F9F9F9
}

- (void)setChromeHidden:(BOOL)hidden
               animated:(BOOL)animated
                 reason:(SeafChromeReason)reason {
    BOOL stateChanged = (self.isChromeHidden != hidden);

    Debug(@"[ZoomBug] setChromeHidden hidden=%d animated=%d reason=%ld stateChanged=%d "
          @"prefersStatusBarHidden(before)=%d view.bounds=%@ safeArea=%@",
          hidden, animated, (long)reason, stateChanged,
          [self prefersStatusBarHidden],
          NSStringFromCGRect(self.view.bounds),
          NSStringFromUIEdgeInsets(self.view.safeAreaInsets));

    // PageSettle / Restore are reapply-style callers — they ask the state
    // machine to enforce the desired chrome appearance even when the boolean
    // didn't change (e.g. swiping to a new page that needs to inherit the
    // current immersive look without animating).
    BOOL forceReapply = (reason == SeafChromeReasonPageSettle ||
                         reason == SeafChromeReasonRestore);
    if (!stateChanged && !forceReapply) {
        return;
    }

    self.isChromeHidden = hidden;

    if (hidden) {
        [self applyChromeHiddenAnimated:animated reason:reason];
    } else {
        [self applyChromeVisibleAnimated:animated reason:reason];
    }

    // The status bar style/visibility piggy-backs on the chrome state via
    // the prefersStatusBarHidden / preferredStatusBarStyle overrides, so all
    // we need to do is request a refresh.
    [self setNeedsStatusBarAppearanceUpdate];

    Debug(@"[ZoomBug] setChromeHidden DONE reason=%ld safeArea(after)=%@",
          (long)reason,
          NSStringFromUIEdgeInsets(self.view.safeAreaInsets));
}

/// Apply chrome-hidden visuals. After the alpha fade completes we also
/// structurally hide the bar via `setNavigationBarHidden:YES` so it stops
/// swallowing taps and doesn't get re-rendered by an incidental layout
/// pass (notably on iPad, where the wider nav bar in modal-over-fullscreen
/// presentation could otherwise re-appear after the safe-area / status
/// bar refresh that fires right after `setNeedsStatusBarAppearanceUpdate`).
///
/// Historically `SeafChromeReasonZoomIn` was excluded from the structural
/// hide because the chrome-hide used to fire from `scrollViewDidZoom:`
/// while the pinch was still in flight — `setNavigationBarHidden:` would
/// re-lay out the scroll view bounds mid-gesture and make the image jump.
/// That is no longer the case: the pinch / double-tap chrome-hide now
/// fires from `scrollViewDidEndZooming:` (after the user releases), so
/// the structural hide is safe and necessary on every reason.
- (void)applyChromeHiddenAnimated:(BOOL)animated reason:(SeafChromeReason)reason {
    UINavigationController *nav = self.navigationController;
    NSTimeInterval duration = animated ? 0.15 : 0.0;

    // Sync cached adjacent VCs to the immersive (black) appearance up front
    // so a paging swipe mid-transition doesn't flash a light background.
    [self updateCachedVCsForImmersiveMode:YES];

    // Sync the currently visible page's own appearance. The contentVC owns
    // its background colors, scroll indicators and LIVE badge visibility —
    // delegating here keeps that knowledge inside the contentVC.
    if ([self.currentContentVC respondsToSelector:@selector(enterImmersiveAppearanceAnimated:)]) {
        [self.currentContentVC enterImmersiveAppearanceAnimated:animated];
    }

    void (^changes)(void) = ^{
        nav.navigationBar.alpha = 0.0;
        self.thumbnailCollection.alpha = 0.0;
        self.toolbarView.alpha = 0.0;
        self.leftThumbnailOverlay.alpha = 0.0;
        self.rightThumbnailOverlay.alpha = 0.0;
        self.pagingView.backgroundColor = [UIColor blackColor];
    };
    void (^completion)(BOOL) = ^(BOOL finished) {
        // Mark thumbs / toolbar / overlays as structurally hidden so they
        // don't intercept touches while invisible.
        self.thumbnailCollection.hidden = YES;
        self.toolbarView.hidden = YES;
        self.leftThumbnailOverlay.hidden = YES;
        self.rightThumbnailOverlay.hidden = YES;
        [nav setNavigationBarHidden:YES animated:NO];
    };

    if (animated) {
        [UIView animateWithDuration:duration animations:changes completion:completion];
    } else {
        changes();
        completion(YES);
    }
}

/// Apply chrome-visible visuals. The chrome consists of the parent nav bar,
/// the bottom toolbar, the thumbnail strip and the two side overlays —
/// they all fade back in together (with a slight delay on the bottom row to
/// match the original tap-restore stagger).
- (void)applyChromeVisibleAnimated:(BOOL)animated reason:(SeafChromeReason)reason {
    UINavigationController *nav = self.navigationController;
    NSTimeInterval duration = animated ? 0.15 : 0.0;

    [self updateCachedVCsForImmersiveMode:NO];

    if ([self.currentContentVC respondsToSelector:@selector(exitImmersiveAppearanceAnimated:)]) {
        [self.currentContentVC exitImmersiveAppearanceAnimated:animated];
    }

    // The nav bar may have been structurally hidden by a tap-driven
    // immersive entry. Make it visible first, then fade alpha back in.
    BOOL navBarVisuallyHidden = nav.navigationBarHidden || nav.navigationBar.alpha < 0.01;
    if (navBarVisuallyHidden) {
        [nav setNavigationBarHidden:NO animated:NO];
        nav.navigationBar.alpha = 0.0;
    }

    // Bring thumbs / toolbar / overlays back into the layout tree before
    // animating their alpha — otherwise hidden=YES short-circuits the fade.
    self.thumbnailCollection.hidden = NO;
    self.thumbnailCollection.alpha = 0.0;
    self.toolbarView.hidden = NO;
    self.toolbarView.alpha = 0.0;
    self.leftThumbnailOverlay.alpha = 0.0;
    self.rightThumbnailOverlay.alpha = 0.0;

    void (^topAnimations)(void) = ^{
        nav.navigationBar.alpha = 1.0;
        self.pagingView.backgroundColor = SeafGalleryChromeVisibleBackground();
    };
    void (^bottomAnimations)(void) = ^{
        self.thumbnailCollection.alpha = 1.0;
        self.toolbarView.alpha = 1.0;
        self.leftThumbnailOverlay.alpha = 1.0;
        self.rightThumbnailOverlay.alpha = 1.0;
    };
    void (^bottomCompletion)(BOOL) = ^(BOOL finished) {
        // Side overlays' .hidden state is otherwise scroll-position driven;
        // call back into the existing helper to restore the right value.
        [self updateThumbnailOverlaysVisibility];
    };

    if (animated) {
        [UIView animateWithDuration:duration animations:topAnimations];
        [UIView animateWithDuration:duration
                              delay:0.05
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:bottomAnimations
                         completion:bottomCompletion];
    } else {
        topAnimations();
        bottomAnimations();
        bottomCompletion(YES);
    }
}

#pragma mark - Status bar (driven by isChromeHidden)

- (BOOL)prefersStatusBarHidden {
    return self.isChromeHidden;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    if (self.isChromeHidden) {
        return UIStatusBarStyleLightContent;
    }
    if (@available(iOS 13.0, *)) {
        return UIStatusBarStyleDarkContent;
    }
    return UIStatusBarStyleDefault;
}

- (UIStatusBarAnimation)preferredStatusBarUpdateAnimation {
    return UIStatusBarAnimationFade;
}

// Self-managed: do not let any pushed/contained child VC override our
// status bar choices. The contentVC depends on isChromeHidden anyway.
- (UIViewController *)childViewControllerForStatusBarStyle {
    return nil;
}

- (UIViewController *)childViewControllerForStatusBarHidden {
    return nil;
}

#pragma mark - SeafPhotoContentDelegate

#pragma mark - SeafPhotoContentDelegate (Zoom)

// Stale-VC guard for zoom delegate callbacks.
//
// Background: the gallery keeps a small cache of nearby contentVCs (current
// page ± 1). UIScrollView delegate callbacks on a CACHED-but-not-current VC
// could in theory race with a page swap and ask us to flip global chrome
// state on behalf of a photo the user is no longer looking at. The
// scrollView for an off-screen VC can briefly emit zoom callbacks during
// `prepareForReuse` resets, programmatic `setZoomScale:` flips, or
// safeAreaInsets fan-out from an animation, none of which represent user
// intent. Honoring those would flip the nav bar / status bar / paging-scroll
// state under the user's current photo — exactly the kind of "hard to
// reproduce" cross-page contamination we want to make impossible.
//
// Logs a one-line warning rather than NSAssert: assertions disappear in
// Release, but a stale callback in production should still no-op
// gracefully (and be visible in console for triage).
- (BOOL)isZoomCallbackFromCurrentVC:(SeafPhotoContentViewController *)viewController
                            selector:(SEL)cmd {
    if (viewController == self.currentContentVC) return YES;
    Debug(@"[ZoomBug] %@ ignored — caller is not currentContentVC "
          @"(callerIndex=%lu currentIndex=%lu currentVC=%p caller=%p)",
          NSStringFromSelector(cmd),
          (unsigned long)viewController.pageIndex,
          (unsigned long)self.currentIndex,
          self.currentContentVC,
          viewController);
    NSAssert(NO, @"Zoom delegate %@ fired from non-current VC (idx=%lu, current=%lu)",
             NSStringFromSelector(cmd),
             (unsigned long)viewController.pageIndex,
             (unsigned long)self.currentIndex);
    return NO;
}

- (void)photoContentViewControllerDidBeginZooming:(SeafPhotoContentViewController *)viewController {
    if (![self isZoomCallbackFromCurrentVC:viewController selector:_cmd]) return;
    // Disable page scrolling when user starts pinch-to-zoom — handoff state
    // machine (commit 3) re-enables it situationally for edge transitions.
    self.pagingView.scrollEnabled = NO;
}

- (void)photoContentViewControllerDidEnterZoomedState:(SeafPhotoContentViewController *)viewController {
    if (![self isZoomCallbackFromCurrentVC:viewController selector:_cmd]) return;
    DebugZoom(@"[EdgeDebug] DidEnterZoomedState — updating %lu cached VCs to immersive",
          (unsigned long)[self.contentVCCache allKeys].count);
    // This callback now fires from `scrollViewDidEndZooming:` (after the
    // user releases the pinch / the double-tap zoom animation finishes),
    // not from `scrollViewDidZoom:`. So `setChromeHidden:` is free to
    // perform the full hide — alpha fade + structural `setNavigationBarHidden:` —
    // without re-laying out the scroll view bounds mid-gesture.
    [self setChromeHidden:YES animated:YES reason:SeafChromeReasonZoomIn];
}

- (void)photoContentViewControllerDidEndZooming:(SeafPhotoContentViewController *)viewController
                                     isAtMinZoom:(BOOL)isAtMinZoom {
    // Legacy callback — defaults to "restore chrome", preserving original behavior
    // for any caller that hasn't migrated to the richer delegate signature.
    // (Stale-VC check is performed by the richer overload below, so callers
    //  routed through here are still guarded.)
    [self photoContentViewControllerDidEndZooming:viewController
                                       isAtMinZoom:isAtMinZoom
                                     restoreChrome:YES];
}

- (void)photoContentViewControllerDidEndZooming:(SeafPhotoContentViewController *)viewController
                                     isAtMinZoom:(BOOL)isAtMinZoom
                                   restoreChrome:(BOOL)restoreChrome {
    if (![self isZoomCallbackFromCurrentVC:viewController selector:_cmd]) return;
    if (!isAtMinZoom) {
        // Still zoomed in — keep page scrolling disabled and chrome untouched.
        return;
    }

    // Image is back to initial size → always re-enable page scrolling so the
    // user can swipe between photos, regardless of immersive intent.
    self.pagingView.scrollEnabled = YES;

    if (!restoreChrome) {
        // User was already in immersive (chrome hidden) BEFORE the zoom-in;
        // honor that intent. The cached adjacent VCs may have drifted to a
        // non-immersive bg if they were touched between zoom-start and now,
        // so re-assert the immersive sync without animating chrome.
        [self updateCachedVCsForImmersiveMode:YES];
        return;
    }

    [self setChromeHidden:NO animated:YES reason:SeafChromeReasonZoomOut];
}

- (void)photoContentViewController:(SeafPhotoContentViewController *)viewController
                didToggleImmersive:(BOOL)immersive {
    // Legacy callback — kept as a no-op now that the gallery owns the
    // chrome state machine and `photoContentViewControllerDidRequestToggleChrome:`
    // is the canonical tap path. Older callers that emit this without going
    // through the request flow are not present in-tree, but the protocol
    // method is left declared for source compatibility.
}

- (void)photoContentViewControllerDidRequestToggleChrome:(SeafPhotoContentViewController *)viewController {
    // Single source of truth for the tap toggle. The contentVC no longer
    // touches the parent navigation bar / status bar / gallery chrome
    // directly — it just notifies us of intent.
    [self setChromeHidden:!self.isChromeHidden animated:YES reason:SeafChromeReasonTap];
}

- (BOOL)photoContentViewControllerIsChromeHidden:(SeafPhotoContentViewController *)viewController {
    return self.isChromeHidden;
}

// Edge-driven paging delegate methods removed: SeafZoomableScrollView now
// performs the page handoff directly from the inner pan via the
// `beginExternalHandoffFromIndex:` / `endExternalHandoffWithTargetIndex:animated:`
// API on SeafPhotoPagingView.

/// Update all cached content VCs (except current) to match immersive mode appearance.
/// Called when entering/exiting zoomed-in immersive mode so that adjacent pages
/// already have the correct background color before the paging view shows them.
- (void)updateCachedVCsForImmersiveMode:(BOOL)immersive {
    UIColor *bgColor = immersive
        ? [UIColor blackColor]
        : [UIColor colorWithRed:249/255.0 green:249/255.0 blue:249/255.0 alpha:1.0]; // #F9F9F9
    for (NSNumber *key in [self.contentVCCache allKeys]) {
        SeafPhotoContentViewController *vc = [self.contentVCCache objectForKey:key];
        if (vc != self.currentContentVC) {
            DebugZoom(@"[EdgeDebug] updateCachedVCs: index=%@, immersive=%d, oldBg=%@, hasImage=%d",
                  key, immersive, vc.view.backgroundColor,
                  vc.scrollView.subviews.firstObject != nil);
            vc.view.backgroundColor = bgColor;
            vc.scrollView.backgroundColor = bgColor;
        }
    }
}


#pragma mark - SeafPhotoContentDelegate (Dismiss Drag)

- (void)photoContentViewControllerDidBeginDismissDrag:(SeafPhotoContentViewController *)viewController {
    // Build the Hero context from the content VC's currently displayed image
    // and the source thumbnail (if the heroProvider can supply one).
    SeafPhotoHeroContext *ctx = [[SeafPhotoHeroContext alloc] init];
    ctx.image = [viewController currentDisplayedImage];

    UIWindow *window = [self heroReferenceWindow];
    ctx.startFrameInWindow = [viewController displayedImageFrameInView:window];

    // Ask the presenter to make the source cell visible, then resolve the
    // target frame. If anything is missing the animator falls back to a
    // generic shrink-to-bottom.
    if (self.heroProvider && self.preViewItem) {
        [self.heroProvider galleryWillDismissToItem:self.preViewItem];
        UIView *sourceView = [self.heroProvider gallerySourceViewForItem:self.preViewItem];
        if (sourceView) {
            ctx.targetView = sourceView;
            ctx.targetFrameInWindow = [self.heroProvider gallerySourceFrameInWindowForItem:self.preViewItem];
            ctx.targetCornerRadius = sourceView.layer.cornerRadius;
            ctx.targetContentMode = sourceView.contentMode;
        }
    }

    self.activeHeroContext = ctx;
    self.activeInteractive = [[SeafPhotoInteractiveDismiss alloc] initWithContext:ctx];

    // Hide the on-screen photo so only the snapshot is visible during the
    // hero flight. Restored on cancel / on completion (via the underlying
    // view being torn down with the gallery).
    [viewController setUnderlyingPhotoHidden:YES];

    // Capture chrome baseline alpha so cancel can restore exactly what was
    // there before the drag started.
    self.chromeBaselineAlpha = self.thumbnailCollection.alpha;

    // Stop any silent live-photo auto-preview while the gallery is going away.
    [viewController didResignCurrentVisiblePage];

    // Lock horizontal paging for the duration of the dismiss drag — once the
    // user has committed to pulling the photo back to its source thumbnail,
    // any residual horizontal motion must NOT slide the previous/next photo
    // into view (mirrors iOS Photos). Restored on cancel; on completion the
    // gallery is torn down so no restore is needed.
    self.pagingView.scrollEnabled = NO;

    // Kick off the dismiss; UIKit will pull the interactive controller out
    // of -interactionControllerForDismissal: and hand it the context.
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)photoContentViewController:(SeafPhotoContentViewController *)viewController
                  dismissDragMoved:(CGPoint)translation
                          progress:(CGFloat)progress
                          velocity:(CGPoint)velocity {
    // Forward to the interactive controller so the snapshot follows the finger.
    [self.activeInteractive updateWithTranslation:translation progress:progress];

    // Fade UI chrome tied to drag progress — first 30% of the drag fades it
    // completely out so the underlying presenter view is visible.
    CGFloat chromeAlpha = MAX(0.0, 1.0 - progress / 0.3);
    self.thumbnailCollection.alpha = chromeAlpha;
    self.toolbarView.alpha = chromeAlpha;
    self.navigationController.navigationBar.alpha = chromeAlpha;
    self.leftThumbnailOverlay.alpha = chromeAlpha;
    self.rightThumbnailOverlay.alpha = chromeAlpha;
}

- (void)photoContentViewController:(SeafPhotoContentViewController *)viewController
        didCompleteDismissDragWithVelocity:(CGPoint)velocity {
    SeafPhotoInteractiveDismiss *interactive = self.activeInteractive;
    SeafPhotoContentViewController *content = viewController;
    self.activeInteractive = nil;
    self.activeHeroContext = nil;

    if (interactive) {
        [interactive finishWithVelocity:velocity];
    } else {
        // Fallback — should not normally happen.
        [content setUnderlyingPhotoHidden:NO];
        [self dismissGalleryAnimated:YES];
    }
}

- (void)photoContentViewController:(SeafPhotoContentViewController *)viewController
        didCancelDismissDragWithVelocity:(CGPoint)velocity {
    SeafPhotoInteractiveDismiss *interactive = self.activeInteractive;
    self.activeInteractive = nil;
    self.activeHeroContext = nil;

    [interactive cancelWithVelocity:velocity];

    // Restore the underlying photo so the user can keep browsing.
    [viewController setUnderlyingPhotoHidden:NO];

    // Re-enable horizontal paging that we locked when the dismiss drag began,
    // so the user can swipe between photos again after a cancelled dismiss.
    self.pagingView.scrollEnabled = YES;

    // Restore chrome alpha with a short tween so it doesn't pop.
    CGFloat baseline = self.chromeBaselineAlpha > 0 ? self.chromeBaselineAlpha : 1.0;
    [UIView animateWithDuration:0.2 animations:^{
        self.thumbnailCollection.alpha = baseline;
        self.toolbarView.alpha = baseline;
        self.navigationController.navigationBar.alpha = 1;
        self.leftThumbnailOverlay.alpha = baseline;
        self.rightThumbnailOverlay.alpha = baseline;
    }];

    // Resume any live-photo silent auto-preview that was paused on Began.
    [viewController didBecomeCurrentVisiblePage];
}

#pragma mark - UIViewControllerTransitioningDelegate (Hero dismiss)

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    // The transitioning delegate is set on the wrapper navigation controller,
    // so `dismissed` will be that nav controller when the gallery is the root
    // VC. Either way, we provide the same animator.
    if (!self.activeHeroContext) {
        // No active drag → build a one-shot context for the non-interactive
        // dismiss path (close button, programmatic close).
        SeafPhotoContentViewController *current = self.currentContentVC;
        if (!current) return nil;

        SeafPhotoHeroContext *ctx = [[SeafPhotoHeroContext alloc] init];
        ctx.image = [current currentDisplayedImage];
        UIWindow *window = [self heroReferenceWindow];
        ctx.startFrameInWindow = [current displayedImageFrameInView:window];
        if (self.heroProvider && self.preViewItem) {
            [self.heroProvider galleryWillDismissToItem:self.preViewItem];
            UIView *sourceView = [self.heroProvider gallerySourceViewForItem:self.preViewItem];
            if (sourceView) {
                ctx.targetView = sourceView;
                ctx.targetFrameInWindow = [self.heroProvider gallerySourceFrameInWindowForItem:self.preViewItem];
                ctx.targetCornerRadius = sourceView.layer.cornerRadius;
                ctx.targetContentMode = sourceView.contentMode;
            }
        }
        return [[SeafPhotoHeroAnimator alloc] initWithContext:ctx];
    }
    return [[SeafPhotoHeroAnimator alloc] initWithContext:self.activeHeroContext];
}

- (id<UIViewControllerInteractiveTransitioning>)interactionControllerForDismissal:(id<UIViewControllerAnimatedTransitioning>)animator {
    return self.activeInteractive;
}

- (UIWindow *)heroReferenceWindow {
    UIWindow *window = self.view.window;
    if (window) return window;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) return w;
                }
            }
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

#pragma mark - Hero navigation factory

+ (UINavigationController *)heroNavigationControllerWithPhotos:(NSArray<id<SeafPreView>> *)files
                                                   currentItem:(id<SeafPreView>)currentItem
                                                        master:(UIViewController<SeafDentryDelegate> *)masterVC
                                                  heroProvider:(id<SeafGalleryHeroProvider>)heroProvider {
    SeafPhotoGalleryViewController *gallery = [[SeafPhotoGalleryViewController alloc] initWithPhotos:files
                                                                                          currentItem:currentItem
                                                                                               master:masterVC];
    gallery.heroProvider = heroProvider;

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:gallery];
    // Custom presentation keeps the presenting view alive in the hierarchy
    // so the Hero animator can fade the gallery to reveal the source list.
    nav.modalPresentationStyle = UIModalPresentationOverFullScreen;
    nav.transitioningDelegate = gallery;
    return nav;
}

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
        if (contentVC) {
            [contentVC loadImage]; // Ask the content view controller to attempt loading again.
        } else {
            // If no contentVC, it's harder to trigger its specific load.
        }
    }
}

@end

