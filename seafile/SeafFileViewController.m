//
//  SeafFileViewController.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafFileViewController.h"
#import "SeafDetailViewController.h"
#import "SeafSdocWebViewController.h"
#import "SeafSdocService.h"
#import "SeafSdocProfileAssembler.h"
#import "SeafSdocProfileSheetViewController.h"
#import "SeafDirViewController.h"
#import "SeafFile.h"
#import "SeafRepos.h"
#import "SeafCell.h"
#import "SeafActionSheet.h"
#import "SeafPhoto.h"
#import "SeafPhotoThumb.h"
#import "SeafStorage.h"
#import "SeafDataTaskManager.h"
#import "SeafGlobal.h"
#import "SeafPhotoAsset.h"
#import "SeafVideoPlayerViewController.h"
#import "SeafSelectionActionCoordinator.h"
#import "SeafDestinationPickerViewController.h"

#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "ExtentedString.h"
#import "UIViewController+Extend.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>
#import "SVProgressHUD.h"
#import "Debug.h"
#import "SeafNavigationBarStyler.h"
#import "SeafTabBarController.h"

#import "SeafImagePickerHelper.h"
#import <WechatOpenSDK/WXApi.h>
#import "SeafWechatHelper.h"
#import "SeafMkLibAlertController.h"
#import "SeafActionsManager.h"
#import "SeafSearchResultViewController.h"
#import "UIImage+FileType.h"
#import "SeafUploadOperation.h"
#import "SeafFileOperationManager.h"
#import "SeafUploadFileModel.h"
#import "SeafHeaderView.h"
#import "SeafEditNavRightItem.h"
#import "SeafLoadingView.h"
#import "SeafPhotoGalleryViewController.h"
#import "SeafGridCell.h"
#import "SeafFileViewType.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import "Version.h"
#import "SeafVideoPlayerViewController.h"

#define kCustomTabToolWithTopPadding 15
#define kCustomTabToolButtonHeight 40
#define kCustomTabToolTotalHeight 130


enum {
    STATE_INIT = 0,
    STATE_LOADING,
    STATE_DELETE,
    STATE_MKDIR,
    STATE_CREATE,
    STATE_RENAME,
    STATE_PASSWORD,
    STATE_MOVE,
    STATE_COPY,
    STATE_SHARE_EMAIL,
    STATE_SHARE_LINK,
    STATE_SHARE_SHARE_WECHAT,
    STATE_MKLIB,
    STATE_EXPORT
};

// Where the library list stands in looking up a library a file link needs.
typedef NS_ENUM(NSInteger, SeafLinkRefreshState) {
    SeafLinkRefreshNone = 0,
    // A load sent before the link is still running. Its answer may predate a
    // library shared since, so it only lets the link look again.
    SeafLinkRefreshAwaitingEarlierLoad,
    // The load sent for the link is running.
    SeafLinkRefreshRequested,
    // The load sent for the link has answered.
    SeafLinkRefreshFinished,
};

static void *SeafPreviewSelectionContext = &SeafPreviewSelectionContext;

static BOOL SeafEntriesMatchForPreview(id entry, id previewItem)
{
    if (!entry || !previewItem) return NO;
    if (entry == previewItem) return YES;
    if (![entry isKindOfClass:SeafFile.class] || ![previewItem isKindOfClass:SeafFile.class]) return NO;

    SeafFile *file = entry;
    SeafFile *previewFile = previewItem;
    return file.connection == previewFile.connection &&
        [file.repoId isEqualToString:previewFile.repoId] &&
        [file.path isEqualToString:previewFile.path];
}

@interface SeafFileViewController ()<SeafImagePickerHelperDelegate, SeafUploadDelegate, SeafDirDelegate, SeafShareDelegate, MFMailComposeViewControllerDelegate, SWTableViewCellDelegate, UIScrollViewAccessibilityDelegate, UIGestureRecognizerDelegate, UIDocumentPickerDelegate, UITableViewDataSource, UITableViewDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UISearchControllerDelegate>

- (UITableViewCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView andIndexPath:(NSIndexPath *)indexPath;
- (UITableViewCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView andIndexPath:(NSIndexPath *)indexPath;
- (UITableViewCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView andIndexPath:(NSIndexPath *)indexPath;

@property (strong) id curEntry; // Currently selected directory entry.

@property (strong) UIBarButtonItem *selectAllItem;// Button to select all items in the directory.
@property (strong) UIBarButtonItem *selectNoneItem;
@property (strong) UIBarButtonItem *photoItem; // Button to trigger photo actions.
@property (strong) UIBarButtonItem *doneItem;
@property (strong) UIBarButtonItem *editItem;
@property (strong) UIBarButtonItem *searchItem;
@property (strong) UIBarButtonItem *viewModeItem;
@property (strong) NSArray *rightItems;

@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) UICollectionView *collectionView;
@property (nonatomic, assign) BOOL gridModeEnabled;
@property (nonatomic, assign) BOOL collectionNeedsReload;
@property (nonatomic, assign) CGFloat lastGridLayoutWidth;
@property (strong, nonatomic) UIRefreshControl *gridRefreshControl;
@property (nonatomic, weak) SeafDetailViewController *observedPreviewController;
@property (nonatomic) BOOL usesSplitPreviewSelection;

@property (retain) SWTableViewCell *selectedCell;// The cell currently selected.
@property (retain) NSIndexPath *selectedindex; // Index path of the currently selected cell.
@property (readonly) NSArray *editToolItems;// Tools available when editing.

@property int state;

@property (retain) NSDateFormatter *formatter;

@property (nonatomic, strong) UISearchController *searchController;
/// Remembers the search's container even if this page is popped before dismissal.
@property (nonatomic, weak) SeafTabBarController *searchTabBarController;
@property (nonatomic, strong) SeafSearchResultViewController *searchResultController;
/// Back arrow drawn inside the search bar; replaced by a rail item when a vertical bar is shown.
@property (nonatomic, strong) UIButton *searchBarBackButton;
/// iPad iOS 26: closes the search from the bar's leading edge (see -applySearchNavigationChrome).
@property (nonatomic, strong) UIBarButtonItem *searchCloseItem;
@property (nonatomic, assign) BOOL searchUsesVerticalBar;
/// Holds the search bar above the grid (see -gridSearchBarHost).
@property (nonatomic, strong) UIView *gridSearchBarHost;
/// Folder picked from the search results, pushed once the search controller has gone.
@property (nonatomic, strong) SeafDir *pendingSearchResultDirectory;
/// Pages below this one that gave up their presentation context for a vertical bar search.
@property (nonatomic, strong) NSHashTable<UIViewController *> *searchContextYieldedControllers;
/// Extends the navigation bar surface behind the top safe area (see viewDidLoad).
@property (nonatomic, strong) UIView *navigationBackgroundView;

@property (strong, retain) NSArray *photos;// Array of photo entries.
@property (strong, retain) NSArray *thumbs;// Array of thumbnail entries.
@property SeafUploadFile *ufile; // The file being uploaded.
@property (nonatomic, strong) NSArray *allItems;// All items in the current directory.

//@property (nonatomic, strong) NSMutableDictionary *expandedSections; // Dictionary to store expanded sections

@property (nonatomic, strong) UIView *customToolView;
@property (nonatomic, strong) SeafFile *pendingVideoFile; // Video file waiting to play after download
// Deep link (goTo:path:) bookkeeping on the library list.
// Library the list is being refreshed for because the cached list did not have it.
@property (nonatomic, copy) NSString *gotoRefreshRepoId;
@property (nonatomic, assign) SeafLinkRefreshState gotoRefreshState;
// Encrypted library whose password prompt is up on behalf of a link.
@property (nonatomic, copy) NSString *gotoPasswordRepoId;

@property (nonatomic, strong) SeafSelectionActionCoordinator *selectionCoordinator;

// Cache of entries selected at the moment user triggers copy/move (for both
// toolbar and bottom tool button flows). This avoids relying solely on
// tableView selection state when the destination picker returns.
@property (nonatomic, strong) NSArray<NSString *> *pendingEntriesForOperation;

@property (nonatomic, strong) SeafImagePickerHelper *imagePickerHelper;
@property (nonatomic, strong) UISelectionFeedbackGenerator *selectionFeedback;

@end

@implementation SeafFileViewController

@synthesize connection = _connection;
@synthesize directory = _directory;
@synthesize curEntry = _curEntry;
@synthesize selectAllItem = _selectAllItem, selectNoneItem = _selectNoneItem;
@synthesize selectedindex = _selectedindex;
@synthesize selectedCell = _selectedCell;
@synthesize editToolItems = _editToolItems;

// Override status bar style for this view controller
- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault; // Use default (dark content, light background)
}

// Ensure view controller controls status bar
- (BOOL)prefersStatusBarHidden {
    return NO;
}

#pragma mark - Lifecycle

- (void)awakeFromNib
{
    if (IsIpad()) {
        self.preferredContentSize = CGSizeMake(320.0, 600.0);
    }
    [super awakeFromNib];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [SeafNavigationBarStyler applyListPageBackgroundToViewController:self];

    BOOL glassSidebar = [self usesGlassSidebarChrome];
    if (!glassSidebar) {
        // On Duo the navigation bar's background stops short of the top edge.
        // Continue its surface behind the top safe area without moving content or
        // changing the gray backdrop beside the list. The safe-area anchor follows
        // navigation bar minimization and fold/unfold transitions.
        UIView *navigationBackground = [[UIView alloc] init];
        navigationBackground.backgroundColor = [SeafTheme primarySurface];
        navigationBackground.userInteractionEnabled = NO;
        navigationBackground.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:navigationBackground];
        self.navigationBackgroundView = navigationBackground;
        [NSLayoutConstraint activateConstraints:@[
            [navigationBackground.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [navigationBackground.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [navigationBackground.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [navigationBackground.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        ]];
    } else {
        [self applySidebarBarAppearance];
    }

    self.gridModeEnabled = SeafFileBrowseGridModeEnabled();

    UITableView *tv = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tv.dataSource = self;
    tv.delegate = self;
    tv.allowsSelectionDuringEditing = YES;
    tv.allowsMultipleSelectionDuringEditing = YES;
    tv.backgroundColor = kPrimaryBackgroundColor;
    // Bottom follows the host view so rows stay visible in the home-indicator
    // band. Horizontal edges stay in the safe area (Duo camera column). In the
    // glass sidebar the top follows it too: rows scroll under the navigation bar,
    // and automatic adjustment keeps them clear of it at rest.
    [SeafNavigationBarStyler pinView:tv inHostView:self.view
               extendPastTopSafeArea:glassSidebar
            extendPastBottomSafeArea:YES];
    self.tableView = tv;

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    // 8pt grid: 16pt page margins, 12pt gutters (Files-like density).
    layout.minimumInteritemSpacing = 12.0;
    layout.minimumLineSpacing = 16.0;
    layout.sectionInset = UIEdgeInsetsMake(16.0, 16.0, 16.0, 16.0);
    UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    cv.backgroundColor = kPrimaryBackgroundColor;
    cv.dataSource = self;
    cv.delegate = self;
    cv.alwaysBounceVertical = YES;
    // The collection view is already pinned inside the safe area. Automatic
    // adjustment would add that inset a second time after a fold/unfold and
    // the row would no longer fill the width. In the glass sidebar only the top
    // edge leaves the safe area (to scroll under the bar), so automatic
    // adjustment adds the top inset alone.
    cv.contentInsetAdjustmentBehavior = glassSidebar ? UIScrollViewContentInsetAdjustmentAutomatic
                                                     : UIScrollViewContentInsetAdjustmentNever;
    cv.hidden = YES;
    cv.accessibilityElementsHidden = YES;
    [cv registerClass:[SeafGridCell class] forCellWithReuseIdentifier:@"SeafGridCell"];
    [SeafNavigationBarStyler pinView:cv inHostView:self.view
               extendPastTopSafeArea:glassSidebar
            extendPastBottomSafeArea:NO];
    self.collectionView = cv;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChange:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];

    UILongPressGestureRecognizer *gridLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleGridLongPress:)];
    gridLongPress.minimumPressDuration = 0.5;
    [self.collectionView addGestureRecognizer:gridLongPress];

    self.selectionFeedback = [[UISelectionFeedbackGenerator alloc] init];
    [self.selectionFeedback prepare];
    
    // Initialize loading view
    self.loadingView = [SeafLoadingView loadingViewWithParentView:self.view];
    
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafCell" bundle:nil]
         forCellReuseIdentifier:@"SeafCell"];
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafDirCell" bundle:nil]
         forCellReuseIdentifier:@"SeafDirCell"];
    
    // Add long press gesture recognizer
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5; // Set duration to 0.5 seconds
    [self.tableView addGestureRecognizer:longPress];
    
    self.formatter = [[NSDateFormatter alloc] init];
    [self.formatter setDateFormat:@"yyyy-MM-dd HH.mm.ss"];

    self.tableView.estimatedRowHeight = 55;
    
    // Skip until setDirectory: when the directory is not ready.
    if (!self.isEditing && self.directory) {
        [self applyLibraryNavigationChrome];
    }
    
    self.state = STATE_INIT;
    
    // Initialize expandedSections dictionary with default values
    self.expandedSections = [NSMutableDictionary dictionary];
    
    // By default, expand "My Own Libraries" (section 0)
    [self.expandedSections setObject:@YES forKey:@(0)];

    UIView *bView = [[UIView alloc] initWithFrame:self.tableView.frame];
    bView.backgroundColor = kPrimaryBackgroundColor;
    self.tableView.backgroundView = bView;
    
    self.tableView.tableFooterView = [UIView new];
    self.tableView.allowsMultipleSelection = NO;

    [SeafNavigationBarStyler applyStandardAppearanceToNavigationController:self.navigationController];

    self.tableView.sectionHeaderTopPadding = 0;

    // The glass sidebar's items follow the bar's label tint like the system back and
    // sidebar buttons beside them.
    if (!glassSidebar) {
        self.navigationController.navigationBar.tintColor = BAR_COLOR;
    }
    [self.navigationController setToolbarHidden:YES animated:NO];
    
    // Selection action coordinator
    self.selectionCoordinator = [[SeafSelectionActionCoordinator alloc] initWithHostViewController:self];

    // Configure view controller for status bar appearance during search
    // This ensures status bar uses proper background during search
    self.modalPresentationCapturesStatusBarAppearance = YES;

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    self.tableView.refreshControl = refreshControl;
    [self.tableView.refreshControl addTarget:self action:@selector(refreshControlChanged) forControlEvents:UIControlEventValueChanged];

    self.gridRefreshControl = [[UIRefreshControl alloc] init];
    self.collectionView.refreshControl = self.gridRefreshControl;
    [self.gridRefreshControl addTarget:self action:@selector(refreshControlChanged) forControlEvents:UIControlEventValueChanged];
    
    self.view.accessibilityElements = @[refreshControl, self.gridRefreshControl, self.tableView, self.collectionView];
    Debug(@"%@", self.view);
    
    self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
    self.tableView.layoutMargins = UIEdgeInsetsMake(0, 15, 0, 15);
    self.tableView.separatorInset = SEAF_SEPARATOR_INSET;
    
    [self refreshView];
    [self applyViewMode];
}

#pragma mark - Grid / List View Mode

- (BOOL)isRepoRootDirectory {
    return [_directory isKindOfClass:[SeafRepos class]];
}

- (BOOL)isGridModeActive {
    return self.gridModeEnabled && ![self isRepoRootDirectory];
}

- (NSArray<NSIndexPath *> *)selectedEntryIndexPaths {
    // Normalize empty selection to nil so existing `if (!idxs)` guards work for both
    // UITableView (returns nil) and UICollectionView (returns @[]).
    NSArray<NSIndexPath *> *paths = nil;
    if ([self isGridModeActive]) {
        paths = [self.collectionView indexPathsForSelectedItems];
    } else {
        paths = [self.tableView indexPathsForSelectedRows];
    }
    return paths.count > 0 ? paths : nil;
}

/// Clear UICollectionView selection state (and visible checkbox visuals).
/// Unlike UITableView's setEditing:NO, CollectionView keeps indexPathsForSelectedItems
/// across edit sessions unless explicitly deselected.
- (void)clearCollectionViewSelection {
    if (!self.collectionView) return;
    NSArray<NSIndexPath *> *selected = [[self.collectionView indexPathsForSelectedItems] copy];
    for (NSIndexPath *indexPath in selected) {
        [self.collectionView deselectItemAtIndexPath:indexPath animated:NO];
    }
    for (UICollectionViewCell *visible in self.collectionView.visibleCells) {
        if ([visible isKindOfClass:[SeafGridCell class]]) {
            [(SeafGridCell *)visible updateCheckboxForSelected:NO];
        }
    }
}

- (UIScrollView *)currentContentScrollView {
    return [self isGridModeActive] ? (UIScrollView *)self.collectionView : (UIScrollView *)self.tableView;
}

- (void)gridItemSize:(CGSize *)outSize inset:(UIEdgeInsets *)outInset forCollectionWidth:(CGFloat)width {
    const CGFloat baseInset = 16.0;
    const CGFloat spacing = 12.0;
    const CGFloat maxItemWidth = 220.0;
    // Always the collection view's current width. A width remembered from the
    // folded layout stays near 220pt after unfold, and the row then stretches
    // the gutter instead of the cells.
    if (width <= 0) width = CGRectGetWidth(self.collectionView.bounds);
    if (width <= 0) width = CGRectGetWidth(self.view.bounds);
    CGFloat usable = MAX(0, width - baseInset * 2.0);
    NSInteger columns = MAX(2, (NSInteger)floor((usable + spacing) / (maxItemWidth + spacing)));
    CGFloat itemWidth = floor((usable - spacing * (CGFloat)(columns - 1)) / (CGFloat)columns);
    if (itemWidth < 1.0) itemWidth = 1.0;
    if (outSize) {
        *outSize = CGSizeMake(itemWidth, [SeafGridCell preferredItemHeightForWidth:itemWidth]);
    }
    if (outInset) {
        *outInset = UIEdgeInsetsMake(baseInset, baseInset, baseInset, baseInset);
    }
}

/// Invalidate the grid layout when the collection view's width changes.
/// Item size, insets, and spacing come from the flow-layout delegate methods
/// below, which read the width at layout time; nothing is cached on the layout.
- (void)updateCollectionViewLayout {
    if (!self.collectionView || ![self isGridModeActive]) return;
    // Read the width only. Do not layoutIfNeeded here: that pass can grow the
    // bounds while this method is still on the stack, and the in-between width
    // (the 3-column boundary, item size exactly 220pt) then sticks.
    CGFloat width = CGRectGetWidth(self.collectionView.bounds);
    if (width <= 0) return;
    if (fabs(width - self.lastGridLayoutWidth) < 0.5) return;
    self.lastGridLayoutWidth = width;
    [self.collectionView.collectionViewLayout invalidateLayout];
}

- (void)relayoutGridAfterBoundsChange {
    self.lastGridLayoutWidth = 0;
    [self updateCollectionViewLayout];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self isGridModeActive] || !self.collectionView) return;
        self.lastGridLayoutWidth = 0;
        [self updateCollectionViewLayout];
        [self.collectionView reloadData];
    });
}

- (void)applyViewMode {
    BOOL grid = [self isGridModeActive];
    self.tableView.hidden = grid;
    self.collectionView.hidden = !grid;
    self.tableView.accessibilityElementsHidden = grid;
    self.collectionView.accessibilityElementsHidden = !grid;
    if (grid) {
        [self updateCollectionViewLayout];
        if (self.collectionNeedsReload) {
            [self.collectionView reloadData];
            self.collectionNeedsReload = NO;
        }
    }
    [self updateViewModeBarButtonImage];
    [self updateGlassSidebarContentScrollView];
}

- (void)contentSizeCategoryDidChange:(NSNotification *)notification {
    if ([self isGridModeActive]) {
        [self updateCollectionViewLayout];
        [self.collectionView reloadData];
    }
}

/// Template glyph sizing; the system owns bar item placement.
static const CGFloat kNavBarIconGlyphSize = 20.0;
static const CGFloat kNavBarViewModeGlyphSize = 17.0;

- (UIImage *)navBarTemplateImageNamed:(NSString *)imageName {
    UIImage *img = [[UIImage imageNamed:imageName] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (!img) return nil;
    CGSize size = CGSizeMake(kNavBarIconGlyphSize, kNavBarIconGlyphSize);
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = self.traitCollection.displayScale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *resized = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [img drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
    return [resized imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

/// The glass sidebar sits beside the system back and sidebar buttons, so its items use
/// the matching SF Symbols at the bar's own size and the bar's tint (nil here).
- (nullable UIColor *)navBarIconTintColor {
    return [self usesGlassSidebarChrome] ? nil : [SeafTheme glassBarIconColor];
}

- (UIImage *)navBarIconImageNamed:(NSString *)imageName {
    if ([self usesGlassSidebarChrome]) {
        NSString *symbol = @{@"fileNav_search": @"magnifyingglass", @"more": @"ellipsis"}[imageName];
        UIImage *image = symbol ? [UIImage systemImageNamed:symbol] : nil;
        if (image) return image;
    }
    return [self navBarTemplateImageNamed:imageName];
}

- (UIBarButtonItem *)makeNavBarIconItemWithImageName:(NSString *)imageName action:(SEL)action {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:[self navBarIconImageNamed:imageName]
                                                          style:UIBarButtonItemStylePlain target:self action:action];
    item.tintColor = [self navBarIconTintColor];
    return item;
}

- (UIImage *)viewModeBarButtonSymbol {
    NSString *name = self.gridModeEnabled ? @"list.bullet" : @"square.grid.2x2";
    if ([self usesGlassSidebarChrome]) {
        return [UIImage systemImageNamed:name];
    }
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:kNavBarViewModeGlyphSize
                                                                                          weight:UIImageSymbolWeightRegular];
    return [UIImage systemImageNamed:name withConfiguration:config];
}

- (UIBarButtonItem *)makeViewModeBarButtonItem {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:[self viewModeBarButtonSymbol]
                                                          style:UIBarButtonItemStylePlain target:self action:@selector(toggleViewMode:)];
    item.tintColor = [self navBarIconTintColor];
    item.accessibilityIdentifier = @"directory_view_mode_button";
    return item;
}

- (void)updateViewModeBarButtonImage {
    self.viewModeItem.image = [self viewModeBarButtonSymbol];
    self.viewModeItem.title = self.gridModeEnabled
        ? NSLocalizedString(@"Switch to List View", @"Seafile")
        : NSLocalizedString(@"Switch to Grid View", @"Seafile");
    self.viewModeItem.accessibilityLabel = self.viewModeItem.title;
}

- (void)toggleViewMode:(id)sender {
    if ([self isRepoRootDirectory]) return;
    // Leave editing before flipping the visible scroll view; inset cleanup
    // also clears both scroll views in adjustContentInsetForCustomToolbar:.
    if (self.editing) {
        [self editDone:nil];
    }
    self.gridModeEnabled = !self.gridModeEnabled;
    SeafFileBrowseSetGridModeEnabled(self.gridModeEnabled);
    [self.selectionFeedback selectionChanged];
    [self.selectionFeedback prepare];
    [UIView transitionWithView:self.view
                      duration:0.2
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        [self applyViewMode];
        [self showCurrentListFromTopInGlassSidebar];
    } completion:^(BOOL finished) {
        if ([self isGridModeActive]) {
            [self.collectionView reloadData];
        } else {
            [self.tableView reloadData];
        }
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [SeafNavigationBarStyler updateTableViewBackgroundViewFrame:self.tableView];
    BOOL usesSplitPreviewSelection = [self isShowingSplitPreview];
    if (self.usesSplitPreviewSelection != usesSplitPreviewSelection) {
        self.usesSplitPreviewSelection = usesSplitPreviewSelection;
        [self updateVisiblePreviewSelection];
    }
    if ([self isGridModeActive]) {
        [self updateCollectionViewLayout];
    }
    // Both the panel and its scroll-view overlap follow the current content area.
    if (self.editing && self.customToolView) {
        self.customToolView.frame = [self customToolFrame];
        [self layoutCustomToolButtons];
        [self adjustContentInsetForCustomToolbar:YES];
    }
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self.view setNeedsLayout];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [SeafNavigationBarStyler applyListPageBackgroundToViewController:self];

    // Set delegate here to ensure it's properly set each time the view appears
    if (self.navigationController) {
        self.navigationController.interactivePopGestureRecognizer.delegate = self;
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    }
    // A search keeps its inline title (see -applySearchNavigationChrome).
    if ([self usesGlassSidebarChrome] && !_searchController.active) {
        [self applySidebarTitleStyle];
    }
    [self updateGlassSidebarContentScrollView];

    // Parent VCs on the nav stack keep a stale gridModeEnabled from viewDidLoad;
    // re-sync with the global preference when returning from a child directory.
    BOOL preferredGrid = SeafFileBrowseGridModeEnabled();
    if (self.gridModeEnabled != preferredGrid) {
        self.gridModeEnabled = preferredGrid;
        [self applyViewMode];
    }

    // UIViewController no longer provides UITableViewController's
    // clearsSelectionOnViewWillAppear; clear list selection on return.
    if (![self isGridModeActive]) {
        NSIndexPath *selected = [self.tableView indexPathForSelectedRow];
        if (selected) {
            [self.tableView deselectRowAtIndexPath:selected animated:animated];
        }
    }
    [self checkUploadfiles];
    [self refreshDownloadStatus];
    [self refreshEncryptedThumb];
}

- (void)viewIsAppearing:(BOOL)animated {
    [super viewIsAppearing:animated];
    [self observeSidebarPreview];
    [self updateVisiblePreviewSelection];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // A file link that arrived while something covered this page (Quick Look,
    // the text editor) was left pending: carry on with it now the page is back.
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if ([appdelegate pendingLinkRepo])
        [SeafAppDelegate checkOpenLink:self];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    [self setLoadingView:nil];
    _directory = nil;
    _curEntry = nil;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    if (!self.isVisible)
        [_directory unload];
}

- (void)dealloc {
    [_observedPreviewController removeObserver:self forKeyPath:NSStringFromSelector(@selector(preViewItem))
                                        context:SeafPreviewSelectionContext];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (self.customToolView) {
            self.customToolView.frame = [self customToolFrame];
            [self relayoutCustomToolViewSubviews];
        }
        [self relayoutGridAfterBoundsChange];
        // Update tableView headerView frame and refresh all its subviews layout
        if (self.tableView.tableHeaderView) {
            CGRect headerFrame = self.tableView.tableHeaderView.frame;
            headerFrame.size.width = size.width;
            self.tableView.tableHeaderView.frame = headerFrame;
            
            // Force headerView and its subviews to relayout
            [self.tableView.tableHeaderView setNeedsLayout];
            [self.tableView.tableHeaderView layoutIfNeeded];
            
            // Reassign to update headerView
            self.tableView.tableHeaderView = self.tableView.tableHeaderView;
        }
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self relayoutGridAfterBoundsChange];
    }];
}

- (void)relayoutCustomToolViewSubviews {
    if (!self.customToolView) {
        return;
    }
    [self layoutCustomToolButtons];
}

#pragma mark - UI & Navigation Items

- (SeafDetailViewController *)detailViewController
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (self.tabBarController && self.tabBarController.selectedIndex != NSNotFound) {
        return (SeafDetailViewController *)[appdelegate detailViewControllerAtIndex:self.tabBarController.selectedIndex];
    }
    return (SeafDetailViewController *)[appdelegate detailViewControllerAtIndex:TABBED_SEAFILE];
}

- (void)observeSidebarPreview {
    UISplitViewController *split = self.splitViewController;
    if (split.style != UISplitViewControllerStyleDoubleColumn) return;

    UIViewController *secondary = [split viewControllerForColumn:UISplitViewControllerColumnSecondary];
    UIViewController *root = [secondary isKindOfClass:UINavigationController.class]
        ? ((UINavigationController *)secondary).viewControllers.firstObject : secondary;
    SeafDetailViewController *detail = [root isKindOfClass:SeafDetailViewController.class] ? (SeafDetailViewController *)root : nil;
    if (self.observedPreviewController == detail) return;

    NSString *keyPath = NSStringFromSelector(@selector(preViewItem));
    [self.observedPreviewController removeObserver:self forKeyPath:keyPath context:SeafPreviewSelectionContext];
    self.observedPreviewController = detail;
    [detail addObserver:self forKeyPath:keyPath options:0 context:SeafPreviewSelectionContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if (context != SeafPreviewSelectionContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    if (NSThread.isMainThread) {
        [self updateVisiblePreviewSelection];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateVisiblePreviewSelection]; });
    }
}

- (BOOL)isShowingSplitPreview {
    UISplitViewController *split = self.splitViewController;
    return split.style == UISplitViewControllerStyleDoubleColumn && !split.isCollapsed;
}

- (id)sidebarPreviewItem {
    if (![self isShowingSplitPreview]) return nil;
    id item = self.observedPreviewController.preViewItem;
    // The video player opens separately, including when the detail is used to download it.
    return [item isKindOfClass:SeafFile.class] && [(SeafFile *)item isVideoFile] ? nil : item;
}

- (void)updateVisiblePreviewSelection {
    if (!self.viewIfLoaded.window || self.navigationController.topViewController != self) return;

    id previewItem = [self sidebarPreviewItem];
    for (SeafCell *cell in self.tableView.visibleCells) {
        if (![cell isKindOfClass:SeafCell.class]) continue;
        NSIndexPath *path = [self.tableView indexPathForCell:cell];
        cell.previewSelected = SeafEntriesMatchForPreview([self getDentrybyIndexPath:path tableView:self.tableView], previewItem);
    }
    for (SeafGridCell *cell in self.collectionView.visibleCells) {
        NSIndexPath *path = [self.collectionView indexPathForCell:cell];
        cell.previewSelected = SeafEntriesMatchForPreview([self getDentrybyIndexPath:path tableView:nil], previewItem);
    }
}

- (void)initNavigationItems:(SeafDir *)directory
{
    // Install buttons before the first navigation-bar layout. Deferring them
    // lets long titles appear centered before shifting to fit the buttons.
    self.doneItem = [SeafNavigationBarStyler createCloseButtonWithTarget:self action:@selector(editDone:)];
    self.doneItem.accessibilityIdentifier = @"directory_exit_selection_button";
    self.editItem = [self makeNavBarIconItemWithImageName:@"more" action:@selector(editSheet:)];
    if ([self usesGlassSidebarChrome]) {
        // A system menu (Liquid Glass, symbols) instead of the custom action sheet.
        self.editItem.target = nil;
        self.editItem.action = NULL;
        self.editItem.menu = [self directoryActionsMenu];
    }
    self.editItem.accessibilityIdentifier = @"directory_more_button";
    self.editItem.title = NSLocalizedString(@"More", @"Seafile");
    self.editItem.accessibilityLabel = self.editItem.title;

    // Determine whether to show search button based on server type and current level
    SeafConnection *conn = directory.connection;
    BOOL isRoot = [directory isKindOfClass:[SeafRepos class]];
    BOOL isPro = conn.isProServer;
    BOOL isAdvanced = conn.isAdvancedSearchEnabled;
    BOOL isCommunity = conn.isCommunityServer;

    BOOL shouldShowSearch = NO;
    if (isPro && isAdvanced) {
        // Pro + file-search: support search on root and inside repos
        shouldShowSearch = YES;
    } else if (isCommunity && !isRoot) {
        // Community edition: only support search inside a specific repo
        shouldShowSearch = YES;
    }

    self.searchItem = nil;
    self.viewModeItem = nil;
    // UIKit orders trailing items from the edge inward and adapts their axis.
    NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray arrayWithObject:self.editItem];
    if (!isRoot) {
        self.viewModeItem = [self makeViewModeBarButtonItem];
        [self updateViewModeBarButtonImage];
        [items addObject:self.viewModeItem];
    }
    if (shouldShowSearch) {
        self.searchItem = [self makeNavBarIconItemWithImageName:@"fileNav_search" action:@selector(searchAction:)];
        self.searchItem.accessibilityIdentifier = @"directory_search_button";
        self.searchItem.title = NSLocalizedString(@"Search", @"Seafile");
        self.searchItem.accessibilityLabel = self.searchItem.title;
        [items addObject:self.searchItem];
    }
    self.rightItems = items;

    _selectNoneItem = [[SeafEditNavRightItem alloc] initWithTitle:NSLocalizedString(@"Select All", @"Seafile") imageName:@"ic_checkbox_unchecked" target:self action:@selector(selectAll:)];

    _selectAllItem = [[SeafEditNavRightItem alloc] initWithTitle:NSLocalizedString(@"Select None", @"Seafile") imageName:@"ic_checkbox_checked" target:self action:@selector(selectNone:)];
    if ([self usesGlassSidebarChrome]) {
        // BAR_COLOR gray text reads as disabled next to the system-tinted buttons.
        _selectNoneItem.tintColor = nil;
        _selectAllItem.tintColor = nil;
    }
    self.navigationItem.rightBarButtonItems = self.rightItems;
}

/// Built each time it opens, so it follows the directory as loaded (e.g. whether it is
/// writable) without being rebuilt on every change.
- (UIMenu *)directoryActionsMenu {
    @weakify(self);
    UIDeferredMenuElement *items = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        @strongify(self);
        completion(self ? [self directoryActionMenuElements] : @[]);
    }];
    return [UIMenu menuWithChildren:@[items]];
}

- (NSArray<UIMenuElement *> *)directoryActionMenuElements {
    NSArray<NSString *> *titles = [SeafActionsManager directoryActionTitles:self.directory];
    NSDictionary<NSString *, NSString *> *symbols = @{
        S_UPLOAD: @"photo.on.rectangle",
        S_UPLOAD_FILE: @"arrow.up.doc",
        S_EDIT: @"checkmark.circle",
        S_NEWFILE: @"doc.badge.plus",
        S_MKDIR: @"folder.badge.plus",
        S_MKLIB: @"plus.rectangle.on.folder",
        // Not "textformat": it is localized into words (e.g. "格式" in Chinese).
        S_SORT_NAME: @"arrow.up.arrow.down",
        S_SORT_MTIME: @"clock",
    };
    // Related actions share a section, as in the system menus.
    NSArray<NSArray<NSString *> *> *groups = @[
        @[S_UPLOAD, S_UPLOAD_FILE],
        @[S_EDIT],
        @[S_NEWFILE, S_MKDIR, S_MKLIB],
        @[S_SORT_NAME, S_SORT_MTIME],
    ];
    NSMutableArray<UIMenuElement *> *sections = [NSMutableArray array];
    @weakify(self);
    for (NSArray<NSString *> *group in groups) {
        NSMutableArray<UIAction *> *actions = [NSMutableArray array];
        for (NSString *title in group) {
            if (![titles containsObject:title]) continue;
            NSString *symbol = symbols[title];
            UIImage *image = symbol ? [UIImage systemImageNamed:symbol] : nil;
            [actions addObject:[UIAction actionWithTitle:title image:image identifier:nil handler:^(__kindof UIAction *action) {
                @strongify(self);
                [self handleAction:title];
            }]];
        }
        if (actions.count == 0) continue;
        [sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil
                                          options:UIMenuOptionsDisplayInline children:actions]];
    }
    return sections;
}

- (void)editSheet:(id)sender {
    @weakify(self);
    [SeafActionsManager directoryAction:self.directory photos:self.photos inTargetVC:self fromItem:self.editItem actionBlock:^(NSString *typeTile) {
        @strongify(self);
        [self handleAction:typeTile];
    }];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self.loadingView updatePosition];
}


#pragma mark - UICollectionView Data Source & Delegate

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGSize itemSize = CGSizeZero;
    [self gridItemSize:&itemSize inset:NULL forCollectionWidth:CGRectGetWidth(collectionView.bounds)];
    return itemSize;
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout insetForSectionAtIndex:(NSInteger)section {
    UIEdgeInsets inset = UIEdgeInsetsZero;
    [self gridItemSize:NULL inset:&inset forCollectionWidth:CGRectGetWidth(collectionView.bounds)];
    return inset;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    return 12.0;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return 16.0;
}


- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if ([self isRepoRootDirectory]) return 0;
    return self.allItems.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SeafGridCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"SeafGridCell" forIndexPath:indexPath];
    cell.cellIndexPath = indexPath;
    cell.isUserEditing = self.editing;
    if (self.editing) {
        BOOL selected = [collectionView.indexPathsForSelectedItems containsObject:indexPath];
        [cell updateCheckboxForSelected:selected];
    }

    NSObject *entry = [self getDentrybyIndexPath:indexPath tableView:nil];
    cell.previewSelected = SeafEntriesMatchForPreview(entry, [self sidebarPreviewItem]);
    if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)entry;
        [file loadCache];
        file.delegate = self;
        file.udelegate = self;
        [cell configureWithFile:file];
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        [cell configureWithDir:(SeafDir *)entry];
    } else if ([entry isKindOfClass:[SeafUploadFile class]]) {
        SeafUploadFile *ufile = (SeafUploadFile *)entry;
        ufile.delegate = self;
        __weak typeof(cell) weakCell = cell;
        [cell configureWithUploadFile:ufile completion:nil];
        [ufile iconWithCompletion:^(UIImage *image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                SeafGridCell *strongCell = weakCell;
                // Match on the upload entry, not just the index path: an upload
                // finishing or the directory re-sorting can leave the same index
                // path showing a different file by the time this lands.
                if (strongCell && strongCell.cellUploadFile == ufile && image) {
                    // iconWithCompletion: yields a real preview only for photos/videos.
                    SeafThumbPreviewStyle style = [Utils thumbPreviewStyleForFileName:ufile.name
                                                                             hasThumb:(ufile.isImageFile || ufile.isVideoFile)];
                    [strongCell setThumbnailImage:image style:style];
                }
            });
        }];
    }
    return cell;
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSObject *entry = [self getDentrybyIndexPath:indexPath tableView:nil];
    if (self.editing && [entry isKindOfClass:[SeafUploadFile class]]) {
        return NO;
    }
    return YES;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.navigationController.topViewController != self) return;
    _selectedindex = indexPath;
    if (self.editing) {
        SeafGridCell *cell = (SeafGridCell *)[collectionView cellForItemAtIndexPath:indexPath];
        cell.isUserEditing = YES;
        [cell updateCheckboxForSelected:YES];
        [self noneSelected:NO];
        [self updateToolButtonsState];
        return;
    }
    [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.editing) return;
    SeafGridCell *cell = (SeafGridCell *)[collectionView cellForItemAtIndexPath:indexPath];
    [cell updateCheckboxForSelected:NO];
    if ([collectionView indexPathsForSelectedItems].count == 0) {
        [self noneSelected:YES];
    } else {
        [self noneSelected:NO];
    }
    [self updateToolButtonsState];
}

- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    if ([cell isKindOfClass:[SeafGridCell class]]) {
        [(SeafGridCell *)cell resetCellFile];
    }
}

- (UIView *)cellViewForIndexPath:(NSIndexPath *)indexPath {
    if ([self isGridModeActive]) {
        return [self.collectionView cellForItemAtIndexPath:indexPath];
    }
    return [self.tableView cellForRowAtIndexPath:indexPath];
}

#pragma mark - TableView Data Source & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (![_directory isKindOfClass:[SeafRepos class]]) {
        return 1;
    }
    return [[((SeafRepos *)_directory)repoGroups] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (![_directory isKindOfClass:[SeafRepos class]]) {
        return self.allItems.count;
    }
    
    if (![self isLibrarySectionExpanded:section]) return 0;

    NSArray *repos = [[((SeafRepos *)_directory) repoGroups] objectAtIndex:section];
    return repos.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSObject *entry = [self getDentrybyIndexPath:indexPath tableView:tableView];
    if (!entry) return [[UITableViewCell alloc] init];
    
    if ([entry isKindOfClass:[SeafRepo class]]) {
        return [self getSeafRepoCell:(SeafRepo *)entry forTableView:tableView andIndexPath:indexPath];
    } else if ([entry isKindOfClass:[SeafFile class]]) {
        return [self getSeafFileCell:(SeafFile *)entry forTableView:tableView andIndexPath:indexPath];
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        return [self getSeafDirCell:(SeafDir *)entry forTableView:tableView andIndexPath:indexPath];
    } else {
        return [self getSeafUploadFileCell:(SeafUploadFile *)entry forTableView:tableView andIndexPath:indexPath];
    }
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([cell isKindOfClass:SeafCell.class]) {
        SeafBase *entry = [self getDentrybyIndexPath:indexPath tableView:tableView];
        ((SeafCell *)cell).previewSelected = SeafEntriesMatchForPreview(entry, [self sidebarPreviewItem]);
    }
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSObject *entry  = [self getDentrybyIndexPath:indexPath tableView:tableView];
    if (tableView.editing && [entry isKindOfClass:[SeafUploadFile class]])
        return nil;
    return indexPath;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSObject *entry  = [self getDentrybyIndexPath:indexPath tableView:tableView];
    return ![entry isKindOfClass:[SeafUploadFile class]];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([cell isKindOfClass:[SeafCell class]]) {
        SeafCell *sCell = (SeafCell *)cell;
        [sCell resetCellFile];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.navigationController.topViewController != self)   return;
    _selectedindex = indexPath;
    if (tableView.editing == YES) {
        [self noneSelected:NO];
        [self updateToolButtonsState];
        return;
    }
    if ([self isShowingSplitPreview] && [tableView.indexPathForSelectedRow isEqual:indexPath]) {
        // The preview state is separate from the table's own multi-selection.
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
    }
    _curEntry = [self getDentrybyIndexPath:indexPath tableView:tableView];
    Debug("Select %@", [_curEntry valueForKey:@"name"]);
    if (!_curEntry) {
        return [tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
    }
    if ([_curEntry isKindOfClass:[SeafRepo class]] && [(SeafRepo *)_curEntry passwordRequiredWithSyncRefresh]) {
        return [self popupSetRepoPassword:(SeafRepo *)_curEntry];
    }

    if ([_curEntry isKindOfClass:[SeafFile class]]) {
        SeafFile *sfile = (SeafFile *)_curEntry;
        if ([sfile.mime isEqualToString:@"application/sdoc"]) {
            Debug(@"[SDOC] direct open from list: %@", sfile.name);
            SeafSdocWebViewController *vc = [[SeafSdocWebViewController alloc] initWithFile:sfile fileName:sfile.name];
            if (IsIpad()) {
                SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
                [appdelegate showDetailView:vc];
            } else {
                vc.hidesBottomBarWhenPushed = YES;
                [self.navigationController pushViewController:vc animated:YES];
            }
            return;
        }
    }

    if ([_curEntry conformsToProtocol:@protocol(SeafPreView)]) {
        [(id<SeafPreView>)_curEntry setDelegate:self];
        if ([_curEntry isKindOfClass:[SeafFile class]] && ![(SeafFile *)_curEntry hasCache]) {
            UIView *cellView = [self cellViewForIndexPath:indexPath];
            if ([cellView isKindOfClass:[SeafCell class]]) {
                [self updateCellDownloadStatus:(SeafCell *)cellView file:(SeafFile *)_curEntry waiting:true];
            } else if ([cellView isKindOfClass:[SeafGridCell class]]) {
                [(SeafGridCell *)cellView updateDownloadStatusForFile:(SeafFile *)_curEntry waiting:YES];
            }
        }

        id<SeafPreView> item = (id<SeafPreView>)_curEntry;

       if ([item isKindOfClass:[SeafFile class]] && [(SeafFile *)item isVideoFile]) {
           SeafFile *file = (SeafFile *)item;
           
           // If video file is cached, use SeafVideoPlayerViewController to play
           if ([file hasCache]) {
               SeafVideoPlayerViewController *playerVC = [[SeafVideoPlayerViewController alloc] initWithFile:file];
               [self presentViewController:playerVC animated:YES completion:nil];
               return;
           }
           
           // In encrypted libraries, skip the prompt and directly download, then auto-play
           if ([self.connection isEncrypted:self.directory.repoId]) {
               self.pendingVideoFile = file;
               // Video never reaches PREVIEW_QL_MODAL: updatePreviewState forces
               // PREVIEW_NONE for it, so the detail view is the only route here.
               [self.detailViewController setPreViewItem:item master:self];
               if (!IsIpad()) {
                   SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
                   [appdelegate showDetailView:self.detailViewController];
               }
               return;
           }
           
           // Show selection menu when not cached
           // Use custom SeafActionSheet style
           NSArray *titles = @[NSLocalizedString(@"Play", @"Seafile"), NSLocalizedString(@"Download", @"Seafile")];
           SeafActionSheet *sheet = [SeafActionSheet actionSheetWithoutCancelWithTitles:titles];
           sheet.targetVC = self;

           __weak typeof(self) weakSelf = self;
           [sheet setButtonPressedBlock:^(SeafActionSheet * _Nonnull actionSheet, NSIndexPath * _Nonnull idx) {
               __strong typeof(weakSelf) self = weakSelf;
               [actionSheet dismissAnimated:YES];
               if (idx.row == 0) { // Play
                   // Close any existing video player first
                   [SeafVideoPlayerViewController closeActiveVideoPlayer];
                   
                   SeafVideoPlayerViewController *playerVC = [[SeafVideoPlayerViewController alloc] initWithFile:file];
                   [self presentViewController:playerVC animated:YES completion:nil];
               } else if (idx.row == 1) { // Download
                   // Remember this file so we can auto-play it after the download finishes
                   self.pendingVideoFile = file;
                   // Continue with default preview flow, same as non-video files
                   [self.detailViewController setPreViewItem:item master:self];
                   if (!IsIpad()) {
                       SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
                       [appdelegate showDetailView:self.detailViewController];
                   }
               }
           }];

           // anchor from the tapped cell to keep style consistent
           UIView *cellView = [self cellViewForIndexPath:indexPath];
           [sheet showFromView:cellView ?: self.view];
           return;
       }

        if (([item isKindOfClass:[SeafFile class]] || [item isKindOfClass:[SeafUploadFile class]]) 
            && [(id<SeafPreView>)item isImageFile]) {
            // Collect all image type files (including upload files)
            NSMutableArray *imageFiles = [NSMutableArray array];
            for (id entry in self.allItems) {
                if (([entry isKindOfClass:[SeafFile class]] || [entry isKindOfClass:[SeafUploadFile class]]) 
                    && [(id<SeafPreView>)entry isImageFile]) {
                    [imageFiles addObject:entry];
                }
            }
            
            // If no image files found, use old detail view
            if (imageFiles.count == 0) {
                Warning("No image files found");
                [self.detailViewController setPreViewItem:item master:self];
                return;
            }
            
            // Create + wrap the gallery for the Hero dismiss transition.
            UINavigationController *navController = [SeafPhotoGalleryViewController heroNavigationControllerWithPhotos:imageFiles
                                                                                                           currentItem:item
                                                                                                                master:self
                                                                                                          heroProvider:self];

            [self presentViewController:navController animated:YES completion:nil];
            return; // Return after handling image file
        } else if (![self.detailViewController previewItem:item master:self presentFrom:self animated:YES]
                   && !IsIpad()) {
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate showDetailView:self.detailViewController];
        }
    } else if ([_curEntry isKindOfClass:[SeafDir class]]) {
        [(SeafDir *)_curEntry setDelegate:self];
        SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
        [controller setDirectory:(SeafDir *)_curEntry];
        [self.navigationController pushViewController:controller animated:YES];
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    [self tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView.editing == YES) {
        if (![tableView indexPathsForSelectedRows]) {
            [self noneSelected:YES];
        } else {
            [self noneSelected:NO];
        }
        [self updateToolButtonsState];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return [self isRepoRootDirectory] ? [SeafHeaderView headerHeight] : 0.01;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    // Only process headers for SeafRepos type directories
    if (![_directory isKindOfClass:[SeafRepos class]])
        return nil;
    
    // Calculate header text based on section
    NSString *text = nil;
    if (section == 0) {
        text = NSLocalizedString(@"My Own Libraries", @"Seafile");
    } else {
        NSArray *repoGroups = [((SeafRepos *)_directory) repoGroups];
        if (section >= repoGroups.count) return nil;
        
        NSArray *repos = repoGroups[section];
        if (repos.count == 0) {
            text = @"";
        } else {
            SeafRepo *repo = repos.firstObject;
            if (!repo) {
                text = @"";
            } else if ([repo.type isEqualToString:SHARE_REPO]) {
                text = NSLocalizedString(@"Shared to me", @"Seafile");
            } else if ([repo.type isEqualToString:PUBLIC_REPO]) {
                text = NSLocalizedString(@"Shared with all", @"Seafile");
            } else if ([repo.type isEqualToString:GROUP_REPO]) {//show group name, not id
                if (!repo.groupName || repo.groupName.length == 0) {
                    text = NSLocalizedString(@"Shared with groups", @"Seafile");
                } else {
                    if ([text isEqualToString:ORG_REPO]) {//Organization special
                        text = NSLocalizedString(@"Organization", @"Seafile");
                    } else {
                        text = repo.groupName;
                    }
                }
            } else {//old logic
                if ([repo.owner isKindOfClass:[NSNull class]]) {
                    text = @"";
                } else {
                    text = [repo.owner isEqualToString:ORG_REPO] ? NSLocalizedString(@"Organization", @"Seafile") : repo.owner;
                }
            }
        }
    }
    
    SeafHeaderView *header = [[SeafHeaderView alloc] initWithSection:section title:text
                                                           expanded:[self isLibrarySectionExpanded:section]];
    __weak typeof(self) weakSelf = self;
    header.toggleAction = ^(NSInteger section) {
        [weakSelf toggleSectionAtIndex:section];
    };
    return header;
}

- (BOOL)isLibrarySectionExpanded:(NSInteger)section {
    NSNumber *expanded = self.expandedSections[@(section)];
    return expanded ? expanded.boolValue : section == 0;
}

- (void)toggleSectionAtIndex:(NSInteger)section
{
    if (![self isRepoRootDirectory]) return;
    NSArray<NSArray *> *groups = ((SeafRepos *)self.directory).repoGroups;
    if (section < 0 || section >= groups.count) return;

    BOOL willExpand = ![self isLibrarySectionExpanded:section];
    BOOL countsMatch = self.tableView.numberOfSections == groups.count;
    for (NSInteger index = 0; countsMatch && index < groups.count; index++) {
        NSInteger expectedRows = [self isLibrarySectionExpanded:index] ? groups[index].count : 0;
        countsMatch = [self.tableView numberOfRowsInSection:index] == expectedRows;
    }
    if (!countsMatch) {
        // A library refresh can replace the groups before the queued table reload.
        self.expandedSections[@(section)] = @(willExpand);
        [self.tableView reloadData];
        return;
    }

    NSInteger rowCount = groups[section].count;
    NSMutableArray<NSIndexPath *> *rows = [NSMutableArray arrayWithCapacity:rowCount];
    for (NSInteger row = 0; row < rowCount; row++) {
        [rows addObject:[NSIndexPath indexPathForRow:row inSection:section]];
    }

    BOOL animated = !UIAccessibilityIsReduceMotionEnabled();
    SeafHeaderView *header = (SeafHeaderView *)[self.tableView headerViewForSection:section];
    [header setExpanded:willExpand animated:animated];
    UITableViewRowAnimation animation = animated ? UITableViewRowAnimationFade : UITableViewRowAnimationNone;
    [self.tableView performBatchUpdates:^{
        self.expandedSections[@(section)] = @(willExpand);
        if (willExpand) {
            [self.tableView insertRowsAtIndexPaths:rows withRowAnimation:animation];
        } else {
            [self.tableView deleteRowsAtIndexPaths:rows withRowAnimation:animation];
        }
    } completion:nil];
}


#pragma mark - Pull to Refresh

- (void)refreshControlChanged {
    UIScrollView *scrollView = [self currentContentScrollView];
    if (!scrollView.isDragging) {
        [self pullToRefresh];
    }
}

- (void)pullToRefresh {
    [self reloadTable];
    if (self.searchDisplayController.active)
        return;
    if (![self checkNetworkStatus]) {
        [self performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:0.1];
        return;
    }
    
    UIScrollView *scrollView = [self currentContentScrollView];
    scrollView.accessibilityElementsHidden = YES;
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, scrollView.refreshControl);
    self.state = STATE_LOADING;
    self.directory.delegate = self;
    [self.directory loadContent:YES];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (scrollView.refreshControl.isRefreshing) {
        [self pullToRefresh];
    }
}

- (void)doneLoadingTableViewData {
    @weakify(self);
    dispatch_async(dispatch_get_main_queue(), ^{
        @strongify(self);
        [self.tableView.refreshControl endRefreshing];
        [self.gridRefreshControl endRefreshing];
        BOOL grid = [self isGridModeActive];
        self.tableView.accessibilityElementsHidden = grid;
        self.collectionView.accessibilityElementsHidden = !grid;
    });
}


#pragma mark - Directory/Data Loading & Setting

- (NSArray *)allItems
{
    if (!_allItems) {
        _allItems = _directory.allItems;
    }
    return _allItems;
}

- (void)setConnection:(SeafConnection *)conn
{
    [self.detailViewController setPreViewItem:nil master:nil];
    [conn loadRepos:self];
    [self setDirectory:(SeafDir *)conn.rootFolder];
}

/// iPad on iOS 26+: the list uses the floating sidebar and its native navigation controls.
- (BOOL)usesGlassSidebarChrome
{
    return [SeafNavigationBarStyler usesSystemBarsOnIpad];
}

- (void)applySidebarBarAppearance
{
    [SeafNavigationBarStyler applyOpaqueAppearanceToNavigationItem:self.navigationItem
                                                  backgroundColor:[SeafTheme primaryBackgroundColor]];

    // UIKit draws the expanded title in the scroll view, underneath the bar.
    // Use the system background at the top so the title remains visible.
    UINavigationBarAppearance *edgeAppearance = [[UINavigationBarAppearance alloc] init];
    [edgeAppearance configureWithDefaultBackground];
    self.navigationItem.scrollEdgeAppearance = edgeAppearance;
    self.navigationItem.compactScrollEdgeAppearance = edgeAppearance;
}

/// The back button and the four trailing glass buttons leave the sidebar's title row
/// about 84pt or less, so folder names get a large title row of their own. The Starred
/// root, which folders are also pushed onto, opts out of large titles itself.
- (BOOL)usesLargeSidebarTitle
{
    return [self usesGlassSidebarChrome] && self.navigationController != nil;
}

- (void)updateGlassSidebarContentScrollView
{
    if (![self usesGlassSidebarChrome]) return;
    // The edge effect and the large title follow the list that is showing.
    [self setContentScrollView:[self currentContentScrollView] forEdge:NSDirectionalRectEdgeTop];
    if (@available(iOS 26.0, *)) {
        // Pinned library headers need an opaque boundary to keep scrolled rows from peeking above them.
        self.tableView.topEdgeEffect.style = [self isRepoRootDirectory]
            ? UIScrollEdgeEffectStyle.hardStyle : UIScrollEdgeEffectStyle.automaticStyle;
    }
}

/// UIKit leaves a collapsed large title collapsed when it is asked for again in place (the
/// mode switching back to Always, or another list becoming the content scroll view), so the
/// bar is resized here; it moves a list resting at its top along with it.
- (void)expandSidebarLargeTitle
{
    if (![self usesLargeSidebarTitle]) return;
    [self.navigationController.navigationBar sizeToFit];
}

/// The list and the grid each keep their own offset while hidden, but the bar's height
/// follows the one that is showing. Start the one that appears at its top under an expanded
/// title, so it is neither half under the title nor below a gap.
- (void)showCurrentListFromTopInGlassSidebar
{
    if (![self usesGlassSidebarChrome]) return;
    [self expandSidebarLargeTitle];
    [self.view layoutIfNeeded];
    UIScrollView *content = [self currentContentScrollView];
    content.contentOffset = CGPointMake(content.contentOffset.x, -content.adjustedContentInset.top);
}

/// A pushed folder gets its directory before it has a navigation controller, so this
/// runs again from viewWillAppear.
- (void)applySidebarTitleStyle
{
    if ([self usesLargeSidebarTitle]) {
        self.navigationController.navigationBar.prefersLargeTitles = YES;
        self.navigationItem.style = UINavigationItemStyleNavigator;
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    } else {
        // Keep every directory title leading-aligned, regardless of its length.
        self.navigationItem.style = UINavigationItemStyleBrowser;
    }
}

/// Keep the title independent so UIKit can adapt navigation controls to either display.
- (void)applyLibraryNavigationChrome
{
    self.navigationItem.titleView = nil;
    [self applySidebarTitleStyle];
    self.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
    SeafDir *directory = self.directory;
    self.title = directory.name.length ? directory.name : NSLocalizedString(@"Libraries", @"Seafile");
    self.navigationItem.leftBarButtonItem = [self glassBackItemIfNeeded];
    self.navigationItem.hidesBackButton = NO;
}

/// On iOS 26+ iPhones the system back button ignores the bar tint (and the iPhone
/// Duo side rail also ignores a custom back indicator), so it stays black while
/// the other bar buttons use glassBarIconColor. Subfolders show their own back
/// item with the same chevron and color instead; swipe-back still works through
/// gestureRecognizerShouldBegin:. The library root has nothing to go back to.
- (nullable UIBarButtonItem *)glassBackItemIfNeeded
{
    if (@available(iOS 26.0, *)) {
        if (IsIpad() || [self.directory isKindOfClass:[SeafRepos class]])
            return nil;
        UIBarButtonItem *back = [SeafNavigationBarStyler createBackButtonWithTarget:self
                                                                             action:@selector(backButtonTapped)
                                                                              color:[SeafTheme glassBarIconColor]];
        return back;
    }
    return nil;
}

- (void)setDirectory:(SeafDir *)directory
{
    [self resetLinkState];
    _directory = directory;
    _connection = directory.connection;
    self.searchResultController.connection = _connection;
    self.searchResultController.directory = _directory;
    
    // Update custom title
    
    [_directory loadContent:false];
    Debug("repoId:%@, %@, path:%@, loading ... cached:%d %@, editable:%d\n", _directory.repoId, _directory.name, _directory.path, _directory.hasCache, _directory.ooid, _directory.editable);
    
    // Initialize expanded states for repositories
    if ([_directory isKindOfClass:[SeafRepos class]]) {
        NSArray *repoGroups = [((SeafRepos *)_directory) repoGroups];
        for (NSInteger i = 0; i < repoGroups.count; i++) {
            // By default, expand section 0 (My Own Libraries), collapse others
            if (![self.expandedSections objectForKey:@(i)]) {
                [self.expandedSections setObject:i == 0 ? @YES : @NO forKey:@(i)];
            }
        }
    }
    
    // Add a 10pt height blank header view if directory is not SeafRepos
    if (![_directory isKindOfClass:[SeafRepos class]]) {
        self.tableView.sectionHeaderHeight = 0;
        self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 10.0)];
    } else {
        self.tableView.tableHeaderView = nil;
    }
    
    [_directory setDelegate:self];
    [self applyViewMode];
    [self refreshView];

    [self initNavigationItems:directory];
    [self applyLibraryNavigationChrome];

    self.state = STATE_LOADING;
    self.directory.delegate = self;
    [_directory loadContent:true];
}

- (void)refreshView
{
    if (!_directory)
        return;
    if ([_directory isKindOfClass:[SeafRepos class]]) {
        @weakify(self);
        dispatch_async(dispatch_get_main_queue(), ^{
            @strongify(self);
            self.searchController.searchBar.placeholder = NSLocalizedString(@"Search", @"Seafile");
            
            // Make sure all sections have an expanded state
            NSArray *repoGroups = [((SeafRepos *)_directory) repoGroups];
            for (NSInteger i = 0; i < repoGroups.count; i++) {
                if (![self.expandedSections objectForKey:@(i)]) {
                    // Default for new sections, expand section 0 (My Own Libraries), collapse others
                    [self.expandedSections setObject:i == 0 ? @YES : @NO forKey:@(i)];
                }
            }
        });
    } else {
        @weakify(self);
        dispatch_async(dispatch_get_main_queue(), ^{
            @strongify(self);
            self.searchController.searchBar.placeholder = NSLocalizedString(@"Search files in this library", @"Seafile");
        });
    }

    [self initSeafPhotos];
    for (SeafUploadFile *file in _directory.uploadFiles) {
        file.delegate = self;
    }
    [self reloadTable];
    if (IsIpad() && self.detailViewController.preViewItem) {
        [self checkPreviewFileExist];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.editing) {
            if (![self selectedEntryIndexPaths])
                [self noneSelected:YES];
            else
                [self noneSelected:NO];
        }
    });

    if ([_directory isKindOfClass:[SeafRepos class]]) {
        SeafRepos *root = (SeafRepos*)_directory;
        NSMutableArray *tempArray = [NSMutableArray array];
        @synchronized (_directory) {
            for (NSArray *array in root.repoGroups) {
                for (SeafRepos *repos in array) {
                    [tempArray addObject:repos];
                }
            }
        }
        if (tempArray.count == 0) {
            [self dismissLoadingView];
            self.state = STATE_INIT;
            return;
        }
    }
    if (_directory && !_directory.hasCache) {
        Debug("no cache, load %@ from server.", _directory.path);
        [self showLoadingView];
        self.state = STATE_LOADING;
    }
    [self initNavigationItems:_directory];
}

- (void)showLoadingView
{
    // Get the key window for proper centering in the entire screen
    UIWindow *keyWindow = [SeafAppDelegate activeWindow];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Only show loading view if still in loading state
        if (self.state == STATE_LOADING) {
            [self.loadingView showInView:keyWindow];
        }
    });
}

- (void)dismissLoadingView
{
    [self.loadingView dismiss];
}

- (void)loadDataFromServerAndRefresh {
    self.state = STATE_LOADING;
    self.directory.delegate = self;
    [_directory loadContent:true]; // get data from server
}

- (void)checkPreviewFileExist
{
    SeafDetailViewController *detail = self.detailViewController;
    if (![detail.preViewItem isKindOfClass:SeafFile.class] || [self isRepoRootDirectory] || !_directory.items) return;

    SeafFile *file = (SeafFile *)detail.preViewItem;
    if (_directory.connection != file.connection || ![_directory.repoId isEqualToString:file.repoId] ||
        ![_directory.path isEqualToString:file.path.stringByDeletingLastPathComponent]) return;

    for (SeafBase *entry in self.allItems) {
        if (SeafEntriesMatchForPreview(entry, file)) return;
    }
    [detail setPreViewItem:nil master:nil];
}

- (void)initSeafPhotos
{
    NSMutableArray *seafPhotos = [NSMutableArray array];
    NSMutableArray *seafThumbs = [NSMutableArray array];

    for (id entry in self.allItems) {
        if ([entry isKindOfClass:[SeafFile class]]
            && [(SeafFile *)entry isImageFile]) {
            id<SeafPreView> file = entry;
            [file setDelegate:self];
            [seafPhotos addObject:[[SeafPhoto alloc] initWithSeafPreviewIem:entry]];
            [seafThumbs addObject:[[SeafPhotoThumb alloc] initWithSeafFile:entry]];
        }
    }
    self.photos = [NSArray arrayWithArray:seafPhotos];
    self.thumbs = [NSArray arrayWithArray:seafThumbs];
}

- (void)checkUploadfiles
{
    [_connection checkSyncDst:_directory];
    NSArray *uploadFiles = _directory.uploadFiles;
#if DEBUG
    if (uploadFiles.count > 0)
        Debug("Upload %lu, state=%d", (unsigned long)uploadFiles.count, self.state);
#endif
    for (SeafUploadFile *file in uploadFiles) {
        Debug("background upload %@", file.name);
        file.delegate = self;
    }
}

- (void)reloadTable
{
    _allItems = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
        if ([self isGridModeActive]) {
            [self.collectionView reloadData];
        } else {
            self.collectionNeedsReload = YES;
        }
    });
}


#pragma mark - Edit / CRUD Operations

- (NSArray *)editToolItems
{
    if (!_editToolItems) {
        UIBarButtonItem *flexibleFpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:nil];

        UIBarButtonItem *exportItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(editOperation:)];
        exportItem.tintColor = BAR_COLOR;
        exportItem.tag = EDITOP_EXPORT;
        
        UIBarButtonItem *copyItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"toolbar_copy"] style:UIBarButtonItemStylePlain target:self action:@selector(editOperation:)];
        copyItem.tintColor = BAR_COLOR;
        copyItem.tag = EDITOP_COPY;
        
        UIBarButtonItem *moveItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"toolbar_move"] style:UIBarButtonItemStylePlain target:self action:@selector(editOperation:)];
        moveItem.tintColor = BAR_COLOR;
        moveItem.tag = EDITOP_MOVE;
        
        UIBarButtonItem *deleteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"toolbar_delete"] style:UIBarButtonItemStylePlain  target:self action:@selector(editOperation:)];
        deleteItem.tintColor = BAR_COLOR;
        deleteItem.tag = EDITOP_DELETE;
        
        _editToolItems = [NSArray arrayWithObjects:exportItem, flexibleFpaceItem, copyItem, flexibleFpaceItem, moveItem, flexibleFpaceItem, deleteItem, nil];
    }
    return _editToolItems;
}

- (void)selectAll:(id)sender
{
    int row;
    long count = self.allItems.count;
    for (row = 0; row < count; ++row) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        NSObject *entry  = [self getDentrybyIndexPath:indexPath tableView:self.tableView];
        if (![entry isKindOfClass:[SeafUploadFile class]]) {
            if ([self isGridModeActive]) {
                [self.collectionView selectItemAtIndexPath:indexPath animated:YES scrollPosition:UICollectionViewScrollPositionNone];
                SeafGridCell *cell = (SeafGridCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
                cell.isUserEditing = YES;
                [cell updateCheckboxForSelected:YES];
            } else {
                [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
            }
        }
    }
    [self noneSelected:NO];
    [self updateToolButtonsState];
}

- (void)selectNone:(id)sender
{
    long count = self.allItems.count;
    for (int row = 0; row < count; ++row) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        if ([self isGridModeActive]) {
            [self.collectionView deselectItemAtIndexPath:indexPath animated:YES];
            SeafGridCell *cell = (SeafGridCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
            [cell updateCheckboxForSelected:NO];
        } else {
            [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
        }
    }
    [self noneSelected:YES];
    [self updateToolButtonsState];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    [super setEditing:editing animated:animated];
    
    if (editing) {
        [self checkNetworkStatus];
        // Clear the title so the root page does not keep a centered
        // "Libraries" title next to the selection button. editDone: puts it
        // back through applyLibraryNavigationChrome.
        self.title = nil;
        
        [self.navigationController.toolbar sizeToFit];
        [self setupCustomTabTool];
        // Drop any leftover selection from a previous edit session or
        // non-edit selectItem: calls before multi-select begins.
        [self clearCollectionViewSelection];
        [self noneSelected:YES];
        [self.photoItem setEnabled:NO];
        [self.navigationController setToolbarHidden:YES animated:animated];
        [self adjustContentInsetForCustomToolbar:YES];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
        [self.photoItem setEnabled:YES];
        
        [self applyLibraryNavigationChrome];

        // Remove custom toolbar
        [self dismissCustomTabTool:^{
            [self adjustContentInsetForCustomToolbar:self.editing];
        }];
    }

    [self.tableView setEditing:editing animated:animated];
    if (!editing) {
        // Must clear before disabling multi-select; otherwise selected items
        // survive into the next edit session (select-all → Done → long-press).
        [self clearCollectionViewSelection];
    }
    self.collectionView.allowsMultipleSelection = editing;
    for (UICollectionViewCell *visible in self.collectionView.visibleCells) {
        if ([visible isKindOfClass:[SeafGridCell class]]) {
            SeafGridCell *gridCell = (SeafGridCell *)visible;
            gridCell.isUserEditing = editing;
            if (!editing) {
                [gridCell updateCheckboxForSelected:NO];
            }
        }
    }
}

// Method to remove custom toolbar when no longer needed
- (void)dismissCustomTabTool:(void (^)(void))completion {
    UIView *panel = self.customToolView;
    if (!panel) {
        if (completion) completion();
        return;
    }
    self.customToolView = nil;
    NSMutableArray *accessibleViews = [self.view.accessibilityElements mutableCopy];
    [accessibleViews removeObject:panel];
    self.view.accessibilityElements = accessibleViews;
    [UIView animateWithDuration:0.2 animations:^{
        CGRect frame = panel.frame;
        frame.origin.y = panel.superview.bounds.size.height;
        panel.frame = frame;
    } completion:^(BOOL finished) {
        [panel removeFromSuperview];

        // Execute completion callback
        if (completion) {
            completion();
        }
    }];
}

- (void)editStart:(id)sender
{
    [self setEditing:YES animated:YES];
    if (self.editing) {
        self.navigationItem.rightBarButtonItems = nil;
        [self noneSelected:YES];  // Let noneSelected: handle the button setup
    }
}

- (void)editDone:(id)sender
{
    [self setEditing:NO animated:YES];
    self.navigationItem.rightBarButtonItem = nil;
    self.navigationItem.rightBarButtonItems = self.rightItems;
    
    [self applyLibraryNavigationChrome];
}

- (void)editOperation:(id)sender
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];

    if (self != appdelegate.fileVC) {
        return [appdelegate.fileVC editOperation:sender];
    }
    switch ([sender tag]) {
        case EDITOP_MKDIR:
            [self popupMkdirView];
            break;

        case EDITOP_CREATE:
            [self popupCreateView];
            break;

        case EDITOP_COPY: { //for selected item
            NSArray *idxs = [self selectedEntryIndexPaths];
            NSMutableArray *names = [NSMutableArray new];
            for (NSIndexPath *indexPath in idxs) {
                if (indexPath.row >= self.allItems.count) continue;
                SeafBase *item = (SeafBase *)self.allItems[indexPath.row];
                [names addObject:item.name ?: @""];
            }
            self.pendingEntriesForOperation = [names copy];
            self.state = STATE_COPY;
            [self popupDirChooseView:nil];
            break;
        }
        case EDITOP_MOVE: { //for selected item
            NSArray *idxs = [self selectedEntryIndexPaths];
            NSMutableArray *names = [NSMutableArray new];
            for (NSIndexPath *indexPath in idxs) {
                if (indexPath.row >= self.allItems.count) continue;
                SeafBase *item = (SeafBase *)self.allItems[indexPath.row];
                [names addObject:item.name ?: @""];
            }
            self.pendingEntriesForOperation = [names copy];
            self.state = STATE_MOVE;
            [self popupDirChooseView:nil];
            break;
        }
        case EDITOP_DELETE: {//for selected item
            NSArray *idxs = [self selectedEntryIndexPaths];
            if (!idxs) return;
            NSMutableArray *entries = [[NSMutableArray alloc] init];
            for (NSIndexPath *indexPath in idxs) {
                if (indexPath.row >= self.allItems.count) continue; // Add safety check
                SeafBase *item = (SeafBase *)[self.allItems objectAtIndex:indexPath.row];
                [entries addObject:item.name];
            }
            self.state = STATE_DELETE;
            _directory.delegate = self;
//            [_directory delEntries:entries];
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting files ...", @"Seafile")];
            [[SeafFileOperationManager sharedManager]
                            deleteEntries:entries
                            inDir:self.directory
                            completion:^(BOOL success, NSError * _Nullable error)
                        {
                            if (success) {
                                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Delete success", @"Seafile")];
                                [self.directory loadContent:YES];
                            } else {
                                NSString *errMsg = error.localizedDescription ?: NSLocalizedString(@"Failed to delete files", @"Seafile");
                                [SVProgressHUD showErrorWithStatus:errMsg];
                            }
                        }];
            
            break;
        }
        case EDITOP_EXPORT: {//for selected item
            [self exportSelected];
        }
        default:
            break;
    }
}

- (void)noneSelected:(BOOL)none
{
    NSInteger selectedCount = none ? 0 : [self selectedEntryIndexPaths].count;
    NSInteger selectableCount = 0;
    for (id entry in self.allItems) {
        if (![entry isKindOfClass:[SeafUploadFile class]]) selectableCount++;
    }
    self.navigationItem.titleView = nil;
    self.navigationItem.title = selectedCount > 0
        ? [NSString stringWithFormat:NSLocalizedString(@"%ld selected", @"Seafile"), (long)selectedCount]
        : NSLocalizedString(@"Select items", @"Seafile");
    self.navigationItem.leftBarButtonItem = self.doneItem;
    self.navigationItem.rightBarButtonItems = @[(selectedCount > 0 && selectedCount == selectableCount) ? self.selectAllItem : self.selectNoneItem];
}

- (void)updateExportBarItem:(NSArray *)items {
    if (items.count > 9) {
        [self updateToolButton:ToolButtonShare enabled:NO];
        return;
    }
    for (SeafBase * entry in items) {
        if ([entry isKindOfClass:[SeafDir class]] || [entry isKindOfClass:[SeafUploadFile class]]) {
            [self updateToolButton:ToolButtonShare enabled:NO];
            return;
        }
    }
    // Deselecting the folder (or dropping back under the limit) makes the
    // remaining selection shareable again, so re-enable rather than only ever
    // disabling.
    [self updateToolButton:ToolButtonShare enabled:YES];
}

// Present actions for directory (Create new folder/file/library):
- (void)popupMkdirView
{
    // No need to assign self.state = STATE_MKDIR here, nor _directory.delegate = self
    [self popupInputView:S_MKDIR
             placeholder:NSLocalizedString(@"New folder name", @"Seafile")
                  secure:false
                 handler:^(NSString *input)
    {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Folder name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"Folder name invalid", @"Seafile")];
            return;
        }
        // Show HUD
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Creating folder ...", @"Seafile")];
        
        // Call the encapsulated Manager
        [[SeafFileOperationManager sharedManager]
            mkdir:input
            inDir:self.directory
            completion:^(BOOL success, NSError * _Nullable error)
        {
            if (success) {
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Create folder success", @"Seafile")];
                // Refresh directory
                [self.directory loadContent:YES];
            } else {
                NSString *errMsg = error.localizedDescription ?: NSLocalizedString(@"Failed to create folder", @"Seafile");
                [SVProgressHUD showErrorWithStatus:errMsg];
                // If you want to retry, you can pop up the input box again here
            }
        }];
    }];
}

- (void)popupMklibView {
    self.state = STATE_MKLIB;
    _directory.delegate = self;
    
    SeafMkLibAlertController *alter = [[SeafMkLibAlertController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:alter];
    navController.navigationBarHidden = YES; // Hide nav bar as alert controller has its own title

    if (IsIpad()) {
        navController.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:navController animated:YES completion:nil];
    } else {
        navController.modalPresentationStyle = UIModalPresentationOverFullScreen;
        [self presentViewController:navController animated:NO completion:nil]; // iPhone uses custom animation
    }
    
    __weak typeof(self) weakSelf = self;
    alter.handlerBlock = ^(NSString *name, NSString *pwd) {
        SeafRepos *repos = (SeafRepos*)_directory;
        [repos createLibrary:name passwd:pwd block:^(bool success, id repoInfo) {
            if (success) {
                [SVProgressHUD dismiss];
                [weakSelf.directory loadContent:true];
            }
        }];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Creating library ...", @"Seafile")];
    };
}

- (void)popupCreateView
{
    [self popupInputView:S_NEWFILE
             placeholder:NSLocalizedString(@"New file name", @"Seafile")
                  secure:false
                 handler:^(NSString *input)
    {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"File name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"File name invalid", @"Seafile")];
            return;
        }
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Creating file ...", @"Seafile")];
        
        [[SeafFileOperationManager sharedManager]
            createFile:input
            inDir:self.directory
            completion:^(BOOL success, NSError * _Nullable error)
        {
            if (success) {
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Create file success", @"Seafile")];
                [self.directory loadContent:YES];
            } else {
                NSString *errMsg = error.localizedDescription ?: NSLocalizedString(@"Failed to create file", @"Seafile");
                [SVProgressHUD showErrorWithStatus:errMsg];
            }
        }];
    }];
}

- (void)popupRenameView:(NSString *)oldName
{
    [self popupInputView:S_RENAME
             placeholder:oldName
                  inputs:oldName
                  secure:false
                 handler:^(NSString *input)
    {
        if ([input isEqualToString:oldName]) {
            return; // No need to rename
        }
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"File name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"File name invalid", @"Seafile")];
            return;
        }
        
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Renaming file ...", @"Seafile")];
        
        if ([self.directory isKindOfClass:[SeafRepos class]]) {
            SeafRepo *repo = nil;
            if ([_curEntry isKindOfClass:[SeafRepo class]]) {
                repo = (SeafRepo *)_curEntry;
            } else {
                return;
            }
            [[SeafFileOperationManager sharedManager]
                renameEntry:oldName
                newName:input
                inRepo:repo
                completion:^(BOOL success, SeafBase *renamedFile, NSError * _Nullable error)
            {
                if (success) {
                    [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Rename file success", @"Seafile")];
                    [self.directory loadContent:YES];
                } else {
                    NSString *errMsg = error.localizedDescription ?: NSLocalizedString(@"Failed to rename file", @"Seafile");
                    [SVProgressHUD showErrorWithStatus:errMsg];
                }
            }];
        } else {
            [[SeafFileOperationManager sharedManager]
                renameEntry:oldName
                newName:input
                inDir:self.directory
                completion:^(BOOL success, SeafBase *renamedFile, NSError * _Nullable error)
            {
                if (success) {
                    [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Rename file success", @"Seafile")];
                    [self.directory loadContent:YES];
                } else {
                    NSString *errMsg = error.localizedDescription ?: NSLocalizedString(@"Failed to rename file", @"Seafile");
                    [SVProgressHUD showErrorWithStatus:errMsg];
                }
            }];
        }
    }];
}

- (void)popupDirChooseView:(SeafUploadFile *)file
{
    self.ufile = file;

    // Collect selected file names for title display in the destination picker
    NSMutableArray<NSString *> *selectedNames = [NSMutableArray new];
    NSArray *idxs = [self selectedEntryIndexPaths];
    for (NSIndexPath *indexPath in idxs) {
        if (indexPath.row >= self.allItems.count) continue;
        SeafBase *item = (SeafBase *)[self.allItems objectAtIndex:indexPath.row];
        [selectedNames addObject:item.name ?: @""];
    }

    OperationState opState = OPERATION_STATE_OTHER;
    if (self.state == STATE_COPY) opState = OPERATION_STATE_COPY;
    else if (self.state == STATE_MOVE) opState = OPERATION_STATE_MOVE;

    SeafDestinationPickerViewController *controller = [[SeafDestinationPickerViewController alloc]
        initWithConnection:self.connection
        sourceDirectory:self.directory
        delegate:self
        operationState:opState
        fileNames:selectedNames];

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    [navController setModalPresentationStyle:UIModalPresentationFullScreen];
    navController.navigationBar.tintColor = BAR_COLOR;
    navController.navigationBar.backgroundColor = [SeafTheme primarySurface];
    [self presentViewController:navController animated:YES completion:nil];
}


#pragma mark - Photos / Album

- (SeafImagePickerHelper *)imagePickerHelper {
    if (!_imagePickerHelper) {
        _imagePickerHelper = [[SeafImagePickerHelper alloc] init];
        _imagePickerHelper.delegate = self;
        _imagePickerHelper.allowsMultipleSelection = YES;
        _imagePickerHelper.mediaType = SeafImagePickerMediaTypeAny;
    }
    return _imagePickerHelper;
}

- (void)addPhotos:(id)sender {
    UIBarButtonItem *barItem = nil;
    if ([sender isKindOfClass:[UIBarButtonItem class]]) {
        barItem = (UIBarButtonItem *)sender;
    } else {
        barItem = self.photoItem ?: self.editItem;
    }
    [self.imagePickerHelper presentFromViewController:self
                                       barButtonItem:barItem
                                          sourceView:nil];
}

#pragma mark - SeafImagePickerHelperDelegate

- (void)imagePickerHelper:(SeafImagePickerHelper *)helper didFinishPickingAssets:(NSArray<PHAsset *> *)assets {
    if (assets.count == 0) return;
    NSSet *nameSet = [self getExistedNameSet];
    int duplicated = 0;
    // ============ Live Photo / Motion Photo upload setting ============
    BOOL uploadLivePhotoEnabled = self.connection.isUploadLivePhotoEnabled;
    BOOL useJpg = self.connection.isUseJpgForStaticPhoto;
    for (PHAsset *asset in assets) {
        SeafPhotoAsset *photoAsset = [[SeafPhotoAsset alloc] initWithAsset:asset isCompress:NO];
        if (photoAsset.localIdentifier) {
            // Get upload filename based on Live Photo and JPG format settings
            NSString *uploadName = [photoAsset uploadNameWithLivePhotoEnabled:uploadLivePhotoEnabled useJpgForStaticPhoto:useJpg];
            if ([nameSet containsObject:uploadName])
                duplicated++;
        } else {
            Warning("Failed to get asset url %@", asset);
        }
    }
    if (duplicated > 0) {
        NSString *title = duplicated == 1 ? STR_12 : STR_13;
        @weakify(self);
        [self alertWithTitle:title message:nil yes:^{
            @strongify(self);
            [self uploadPickedAssets:assets overwrite:YES];
        } no:^{
            @strongify(self);
            [self uploadPickedAssets:assets overwrite:NO];
        }];
    } else {
        [self uploadPickedAssets:assets overwrite:NO];
    }
}

- (void)imagePickerHelper:(SeafImagePickerHelper *)helper didFinishPickingFileURLs:(NSArray<NSURL *> *)fileURLs {
    if (fileURLs.count == 0) return;
    [self uploadFilesAtURLs:fileURLs];
}

- (void)imagePickerHelper:(SeafImagePickerHelper *)helper didFailWithMessage:(NSString *)message {
    if (message.length == 0) {
        message = NSLocalizedString(@"Failed to load selected photos", @"Seafile");
    }
    [self alertWithTitle:message];
}

- (NSMutableSet *)getExistedNameSet
{
    NSMutableSet *nameSet = [[NSMutableSet alloc] init];
    for (id obj in self.allItems) {
        NSString *name = nil;
        if ([obj conformsToProtocol:@protocol(SeafPreView)]) {
            name = ((id<SeafPreView>)obj).name;
        } else if ([obj isKindOfClass:[SeafBase class]]) {
            name = ((SeafBase *)obj).name;
        }
        if (name) {
            [nameSet addObject:name];
        }
    }
    return nameSet;
}

- (NSString *)getUniqueFilename:(NSString *)name ext:(NSString *)ext nameSet:(NSMutableSet *)nameSet
{
    for (int i = 1; i < 999; ++i) {
        NSString *filename = [NSString stringWithFormat:@"%@ (%d).%@", name, i, ext];
        if (![nameSet containsObject:filename])
            return filename;
    }
    NSString *date = [self.formatter stringFromDate:[NSDate date]];
    return [NSString stringWithFormat:@"%@-%@.%@", name, date, ext];
}

- (void)uploadPickedAssets:(NSArray<PHAsset *> *)assets overwrite:(BOOL)overwrite {
    if (assets.count == 0) return;
    
    NSMutableArray *files = [[NSMutableArray alloc] init];
    NSString *uploadDir = [self.connection uniqueUploadDir];
    NSMutableSet *nameSet = overwrite ? [NSMutableSet new] : [self getExistedNameSet];
    // ============ Live Photo / Motion Photo upload setting ============
    BOOL uploadLivePhotoEnabled = self.connection.isUploadLivePhotoEnabled;
    BOOL useJpg = self.connection.isUseJpgForStaticPhoto;

    // Build SeafPhotoAsset for each PHAsset once (avoid repeated creation).
    NSMutableArray<SeafPhotoAsset *> *photoAssets = [NSMutableArray arrayWithCapacity:assets.count];
    for (PHAsset *asset in assets) {
        [photoAssets addObject:[[SeafPhotoAsset alloc] initWithAsset:asset isCompress:NO]];
    }

    if (overwrite) {
        NSMutableArray *newItems = [self.directory.items mutableCopy];
        NSMutableSet *uploadingFilenames = [NSMutableSet set];
        for (SeafPhotoAsset *photoAsset in photoAssets) {
            // Get upload filename based on Live Photo and JPG format settings
            NSString *uploadName = [photoAsset uploadNameWithLivePhotoEnabled:uploadLivePhotoEnabled useJpgForStaticPhoto:useJpg];
            if (uploadName) {
                [uploadingFilenames addObject:uploadName];
            }
        }
        // Remove from items (server-synced SeafFile objects)
        NSIndexSet *indexes = [newItems indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            return [obj isKindOfClass:[SeafFile class]] && [uploadingFilenames containsObject:((SeafFile *)obj).name];
        }];
        [newItems removeObjectsAtIndexes:indexes];
        self.directory.items = newItems;
        
        // Also remove from uploadItems (local SeafUploadFile objects not yet refreshed)
        NSArray *existingUploadFiles = [self.directory.uploadFiles copy];
        for (SeafUploadFile *ufile in existingUploadFiles) {
            if ([uploadingFilenames containsObject:ufile.name]) {
                [ufile cancel];
                [self.directory removeUploadItem:ufile];
            }
        }
    }
    
    for (NSUInteger i = 0; i < assets.count; i++) {
        PHAsset *asset = assets[i];
        SeafPhotoAsset *photoAsset = photoAssets[i];
        
        // Get upload filename based on Live Photo and JPG format settings
        NSString *filename = [photoAsset uploadNameWithLivePhotoEnabled:uploadLivePhotoEnabled useJpgForStaticPhoto:useJpg];
        Debug("Upload picked file : %@", filename);
        if (!overwrite && [nameSet containsObject:filename]) {
            NSString *name = filename.stringByDeletingPathExtension;
            NSString *ext = filename.pathExtension;
            filename = [self getUniqueFilename:name ext:ext nameSet:nameSet];
        }
        [nameSet addObject:filename];
        NSString *path = [uploadDir stringByAppendingPathComponent:filename];
        SeafUploadFile *file = [[SeafUploadFile alloc] initWithPath:path];
        file.lastModified = asset.modificationDate ?: asset.creationDate;
        file.model.overwrite = overwrite;
        
        // Mark Live Photo for Motion Photo processing only when "Upload Live Photo" setting is enabled
        // When disabled, Live Photo uploads as static image only (no video part)
        if (photoAsset.isLivePhoto && uploadLivePhotoEnabled) {
            file.model.isLivePhoto = YES;
            Debug("Live Photo detected, will upload as Motion Photo: %@", filename);
        }
        
        [file setPHAsset:asset url:photoAsset.ALAssetURL];
        file.delegate = self;
        [files addObject:file];
        [self.directory addUploadFile:file];
    }
    
    [self reloadTable];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [SeafDataTaskManager.sharedObject addUploadTasksInBatch:files forConnection:self.connection];
    });
}

- (NSArray *)getCurrentFileImagesInTableView:(UITableView *)tableView {
    NSMutableArray *images = [NSMutableArray array];
    
    for (id entry in self.allItems) {
        if ([entry isKindOfClass:[SeafFile class]] && [(SeafFile *)entry isImageFile]) {
            [images addObject:entry];
        }
    }
    
    return [images copy];
}

#pragma mark - Share & Export

- (void)exportSelected {
    NSArray *idxs = [self selectedEntryIndexPaths];
    if (!idxs) return;
    NSMutableArray *entries = [[NSMutableArray alloc] init];
    for (NSIndexPath *indexPath in idxs) {
        id entry = [self getDentrybyIndexPath:indexPath tableView:self.tableView];
        [entries addObject:entry];
    }
    self.state = STATE_EXPORT;
    [self editDone:nil];
    @weakify(self);
    [self downloadEntries:entries completion:^(NSArray *array, NSString *errorStr) {
        @strongify(self);
        self.state = STATE_INIT;
        @weakify(self);
        dispatch_async(dispatch_get_main_queue(), ^{
            @strongify(self);
            if (errorStr) {
                [SVProgressHUD showErrorWithStatus:errorStr];
            } else {
                [SeafActionsManager exportByActivityView:array item:self.toolbarItems.firstObject targerVC:self];
            }
        });
    }];
}

- (void)downloadEntries:(NSArray *)entries completion:(DownloadCompleteBlock)block {
    NSMutableArray *urls = [NSMutableArray array];
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_group_t group = dispatch_group_create();
    dispatch_async(dispatch_get_main_queue(), ^{
        [SVProgressHUD show];
    });
    for (id entry in entries) {
        dispatch_group_enter(group);
        dispatch_barrier_async(queue, ^{
            SeafFile *file = (SeafFile *)entry;
            [file loadCache];
            NSURL *exportURL = file.exportURL;
            if (!exportURL) {
                [SeafDataTaskManager.sharedObject addFileDownloadTask:file];
                Debug("Download file %@", file.path);
                [file setFileDownloadedBlock:^(SeafFile * _Nonnull file, NSError * _Nullable error) {
                    if (error) {
                        Warning("Failed to download file %@: %@", file.path, error);
                        block(nil, [NSString stringWithFormat:NSLocalizedString(@"Failed to download file '%@'", @"Seafile"), file.previewItemTitle]);
                    } else {
                        [urls addObject:file.exportURL];
                        dispatch_group_leave(group);
                    }
                    [file setFileDownloadedBlock:nil];
                }];
            } else {
                [urls addObject:file.exportURL];
                dispatch_group_leave(group);
            }
        });
    }
    dispatch_group_notify(group, queue, ^{
        block(urls, nil);
        dispatch_async(dispatch_get_main_queue(), ^{
            [SVProgressHUD dismiss];
        });
    });
}

- (void)shareToWechat:(SeafFile*)file {
    self.state = STATE_INIT;
    [SeafWechatHelper shareToWechatWithFile:file];
}

- (void)popupSetRepoPassword:(SeafRepo *)repo
{
    self.state = STATE_PASSWORD;
    @weakify(self);
    [self popupSetRepoPassword:repo handler:^{
        @strongify(self);
        [SVProgressHUD dismiss];
        self.state = STATE_INIT;
        SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
        [self.navigationController pushViewController:controller animated:YES];
        [controller setDirectory:(SeafDir *)repo];
    }];
}

// Password prompt opened by a file link. The link stays pending while the
// prompt is up, so later refreshes of the list must not open a second one,
// and giving up on the prompt gives up on the link.
- (void)popupSetRepoPasswordForLink:(SeafRepo *)repo
{
    NSString *repoId = repo.repoId;
    self.gotoPasswordRepoId = repoId;
    self.state = STATE_PASSWORD;
    @weakify(self);
    [self popupSetRepoPassword:repo handler:^{
        @strongify(self);
        if (!self) return;
        [SVProgressHUD dismiss];
        self.state = STATE_INIT;
        self.gotoPasswordRepoId = nil;
        if (self.navigationController.topViewController != self) return;
        // Another link arrived while the prompt was up: it goes first, from the list.
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        NSString *pending = [appdelegate pendingLinkRepo];
        if (pending && ![pending isEqualToString:repoId]) {
            [SeafAppDelegate checkOpenLink:self];
            return;
        }
        // The pushed page resumes the link once its listing has loaded.
        SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
        [self.navigationController pushViewController:controller animated:YES];
        [controller setDirectory:(SeafDir *)repo];
    } cancelHandler:^{
        @strongify(self);
        if (!self) return;
        self.state = STATE_INIT;
        self.gotoPasswordRepoId = nil;
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate endGotoForRepo:repoId];
        // No-op unless a different link arrived while the prompt was up.
        [SeafAppDelegate checkOpenLink:self];
    }];
}

- (void)resetLinkState
{
    self.gotoRefreshRepoId = nil;
    self.gotoRefreshState = SeafLinkRefreshNone;
    self.gotoPasswordRepoId = nil;
}

- (void)deleteFile:(SeafFile *)file {
    NSArray *entries = [NSArray arrayWithObject:file.name];
     self.state = STATE_DELETE; // State management might need review if this method is called from gallery directly
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting file ...", @"Seafile")];
    
    [[SeafFileOperationManager sharedManager]
        deleteEntries:entries
        inDir:self.directory // Assuming self.directory is the correct context for the file being deleted.
                           // If file can be from any directory, 'inDir' might need to be more dynamic or passed in.
        completion:^(BOOL success, NSError * _Nullable error)
    {
        if (success) {
            [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Delete success", @"Seafile")];
            // It's important that masterVc reloads its content to reflect the deletion.
            [self.directory loadContent:YES];
        } else {
            NSString *errMsg = error.localizedDescription ?: NSLocalizedString(@"Failed to delete files", @"Seafile");
            [SVProgressHUD showErrorWithStatus:errMsg];
        }
        // Call the provided completion handler
    }];
}

- (void)deleteFile:(SeafFile *)file completion:(void (^)(BOOL success, NSError *error))completion
{
    NSArray *entries = [NSArray arrayWithObject:file.name];
    // self.state = STATE_DELETE; // State management might need review if this method is called from gallery directly
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting file ...", @"Seafile")];
    
    [[SeafFileOperationManager sharedManager]
        deleteEntries:entries
        inDir:self.directory // Assuming self.directory is the correct context for the file being deleted.
                           // If file can be from any directory, 'inDir' might need to be more dynamic or passed in.
        completion:^(BOOL success, NSError * _Nullable error) {
            if (success) {
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Delete success", @"Seafile")];
                // It's important that masterVc reloads its content to reflect the deletion.
                [self.directory loadContent:YES];
            } else {
                NSString *errMsg = error.localizedDescription ?: NSLocalizedString(@"Failed to delete files", @"Seafile");
                [SVProgressHUD showErrorWithStatus:errMsg];
            }
            // Call the provided completion handler
            if (completion) {
                completion(success, error);
            }
        }];
}

- (void)deleteDir:(SeafDir *)dir
{
    NSArray *entries = [NSArray arrayWithObject:dir.name];
    self.state = STATE_DELETE;
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting directory ...", @"Seafile")];
    
    [[SeafFileOperationManager sharedManager]
        deleteEntries:entries
        inDir:self.directory
        completion:^(BOOL success, NSError * _Nullable error) {
            if (success) {
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Delete success", @"Seafile")];
                [self.directory loadContent:YES];
            } else {
                NSString *errMsg = error.localizedDescription ?: NSLocalizedString(@"Failed to delete files", @"Seafile");
                [SVProgressHUD showErrorWithStatus:errMsg];
            }
        }];
}

- (void)redownloadFile:(SeafFile *)file
{
    [file cancel];
    [file deleteCache];
    [self.detailViewController setPreViewItem:nil master:nil];
    [self tableView:self.tableView didSelectRowAtIndexPath:_selectedindex];
}

- (void)downloadDir:(SeafDir *)dir
{
    Debug("download dir: %@ %@", dir.repoId, dir.path);
    [SVProgressHUD showSuccessWithStatus:[NSLocalizedString(@"Start to download folder: ", @"Seafile") stringByAppendingString:dir.name]];
    [_connection performSelectorInBackground:@selector(downloadDir:) withObject:dir];
}

- (void)renameEntry:(SeafBase *)obj
{
    _curEntry = obj;
    [self popupRenameView:obj.name];
}

- (void)deleteEntry:(id)entry
{
    self.state = STATE_DELETE;
    if ([entry isKindOfClass:[SeafUploadFile class]]) {
        if (self.detailViewController.preViewItem == entry)
            self.detailViewController.preViewItem = nil;
        SeafUploadFile *ufile = (SeafUploadFile *)entry;
        Debug("Remove SeafUploadFile %@", ufile.name);
        [ufile cancel];
        [self reloadTable];
    } else if ([entry isKindOfClass:[SeafFile class]])
        [self deleteFile:(SeafFile*)entry];
    else if ([entry isKindOfClass:[SeafDir class]])
        [self deleteDir: (SeafDir*)entry];
}

- (void)handleAction:(NSString *)title
{
    Debug("handle action title:%@, %@", title, _selectedCell);
    if (_selectedCell) {
        _selectedCell = nil;
    }

    if ([S_NEWFILE isEqualToString:title]) {
        [self popupCreateView];
    } else if ([S_MKDIR isEqualToString:title]) {
        [self popupMkdirView];
    } else if ([S_DOWNLOAD isEqualToString:title]) {
        SeafDir *dir = (SeafDir *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [self downloadDir:dir];
    } else if ([S_EDIT isEqualToString:title]) {
        [self editStart:nil];
    } else if ([S_DELETE isEqualToString:title]) {
        SeafBase *entry = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [self deleteEntry:entry];
    } else if ([S_REDOWNLOAD isEqualToString:title]) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [self redownloadFile:file];
    } else if ([S_RENAME isEqualToString:title]) {
        SeafBase *entry = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [self renameEntry:entry];//rename
    } else if ([S_RE_UPLOAD_FILE isEqualToString:title]) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [file update:self];
        [self reloadIndex:_selectedindex];
    } else if ([S_SHARE_EMAIL isEqualToString:title]) {
        self.state = STATE_SHARE_EMAIL;
        SeafBase *entry = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        if (!entry.shareLink) {
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Generate share link ...", @"Seafile")];
            [entry generateShareLink:self];
        } else {
            [self generateSharelink:entry WithResult:YES];
        }
    } else if ([S_SHARE_LINK isEqualToString:title]) {
        self.state = STATE_SHARE_LINK;
        SeafBase *entry = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        if (!entry.shareLink) {
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Generate share link ...", @"Seafile")];
            [entry generateShareLink:self];
        } else {
            [self generateSharelink:entry WithResult:YES];
        }
    } else if ([S_SORT_NAME isEqualToString:title]) {
        [_directory reSortItemsByName];
        [self reloadTable];
    } else if ([S_SORT_MTIME isEqualToString:title]) {
        [_directory reSortItemsByMtime];
        [self reloadTable];
    } else if ([S_RESET_PASSWORD isEqualToString:title]) {
        SeafRepo *repo = (SeafRepo *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [repo.connection saveRepo:repo.repoId password:nil];
        [self popupSetRepoPassword:repo];
    } else if ([S_CLEAR_REPO_PASSWORD isEqualToString:title]) {
        SeafRepo *repo = (SeafRepo *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [repo.connection saveRepo:repo.repoId password:nil];
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Clear library password successfully.", @"Seafile")];
    } else if ([S_STAR isEqualToString:title]) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [file setStarred:YES withBlock:nil];
    } else if ([S_UNSTAR isEqualToString:title]) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [file setStarred:NO withBlock:nil];
    } else if ([S_SHARE_TO_WECHAT isEqualToString:title]) {
        self.state = STATE_SHARE_SHARE_WECHAT;
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        if (!file.hasCache) {
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Downloading", @"Seafile")];
            [file load:self force:true];
        } else {
            [self shareToWechat:file];
        }
    } else if ([S_MKLIB isEqualToString:title]) {
        Debug("create lib");
        [self popupMklibView];
    } else if ([S_UPLOAD isEqualToString:title]) {
        [self addPhotos:nil];
    } else if ([S_UPLOAD_FILE isEqualToString:title]) {
        [self selectFileToUpload];
    } else if ([S_PROFILE isEqualToString:title]) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [self showFileProfileSheetForFile:file];
    }

}

#pragma mark - File Profile Sheet (Android-aligned read-only viewer)

- (void)showFileProfileSheetForFile:(SeafFile *)file
{
    if (!file || !file.connection || !file.repoId || !file.path) {
        return;
    }

#if DEBUG
    if ([[NSProcessInfo processInfo].arguments containsObject:@"-UI_TEST_FAIL_PROFILE_LOAD"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load file profile", @"Seafile")];
        });
        return;
    }
#endif

    [SVProgressHUD showWithStatus:NSLocalizedString(@"Loading...", @"Seafile")];

    SeafSdocService *service = [[SeafSdocService alloc] initWithConnection:file.connection];
    __weak typeof(self) wself = self;
    [service fetchFileProfileAggregateWithRepoId:file.repoId
                                            path:file.path
                                      completion:^(id agg, NSError *error) {
        __strong typeof(wself) sself = wself;
        if (!sself) return;

        NSArray *rows = agg ? [SeafSdocProfileAssembler buildRowsFromProfileAggregate:agg] : @[];

        dispatch_async(dispatch_get_main_queue(), ^{
            [SVProgressHUD dismiss];

            if (!agg) {
                // Real network/API error
                NSString *msg = error.localizedDescription
                                ?: NSLocalizedString(@"Failed to load file profile", @"Seafile");
                [SVProgressHUD showErrorWithStatus:msg];
                return;
            }
            if (rows.count == 0) {
                // API succeeded but no displayable data
                [SVProgressHUD showInfoWithStatus:NSLocalizedString(@"No file profile data", @"Seafile")];
                return;
            }

            SeafFileProfileAggregate *aggTyped = (SeafFileProfileAggregate *)agg;
            BOOL metaEnabled = [aggTyped.metadataConfig[@"enabled"] boolValue];
#if DEBUG
            if ([[NSProcessInfo processInfo].arguments containsObject:@"-UI_TEST_METADATA_DISABLED"]) {
                metaEnabled = NO;
            }
            if ([[NSProcessInfo processInfo].arguments containsObject:@"-UI_TEST_EMPTY_PROFILE"]) {
                [SVProgressHUD showInfoWithStatus:NSLocalizedString(@"No file profile data", @"Seafile")];
                return;
            }
#endif
            SeafSdocProfileSheetViewController *vc =
                [[SeafSdocProfileSheetViewController alloc] initWithRows:rows
                                                             connection:file.connection
                                                                 repoId:file.repoId
                                                              aggregate:aggTyped
                                                        metadataEnabled:metaEnabled];
            vc.modalPresentationStyle = UIModalPresentationPageSheet;
            UISheetPresentationController *sheet = vc.sheetPresentationController;
            sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                              UISheetPresentationControllerDetent.largeDetent];
            sheet.prefersGrabberVisible = YES;
            sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
            sheet.largestUndimmedDetentIdentifier = nil;
            [sself presentViewController:vc animated:YES completion:nil];
        });
    }];
}

#pragma mark - File Picker
- (void)selectFileToUpload {
    UIDocumentPickerViewController *documentPicker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = YES;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)startFileUploadsFromPaths:(NSArray *)paths overwrite:(BOOL)overwrite {
    if (paths.count == 0) return;
    
    NSMutableArray *files = [[NSMutableArray alloc] init];
    NSMutableSet *nameSet = overwrite ? [NSMutableSet new] : [self getExistedNameSet];

    if (overwrite) {
        NSMutableArray *newItems = [self.directory.items mutableCopy];
        NSMutableSet *uploadingFilenames = [NSMutableSet set];
        for (NSString *path in paths) {
            [uploadingFilenames addObject:[path lastPathComponent]];
        }
        // Remove from items (server-synced SeafFile objects)
        NSIndexSet *indexes = [newItems indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            return [obj isKindOfClass:[SeafFile class]] && [uploadingFilenames containsObject:((SeafFile *)obj).name];
        }];
        [newItems removeObjectsAtIndexes:indexes];
        self.directory.items = newItems;
        
        // Also remove from uploadItems (local SeafUploadFile objects not yet refreshed)
        NSArray *existingUploadFiles = [self.directory.uploadFiles copy];
        for (SeafUploadFile *ufile in existingUploadFiles) {
            if ([uploadingFilenames containsObject:ufile.name]) {
                [ufile cancel];
                [self.directory removeUploadItem:ufile];
            }
        }
    }
    
    for (NSString *path in paths) {
        NSString *filename = [path lastPathComponent];
        NSString *finalPath = path;
        
        if (!overwrite) {
            if ([nameSet containsObject:filename]) {
                NSString *name = filename.stringByDeletingPathExtension;
                NSString *ext = filename.pathExtension;
                NSString *newFilename = [self getUniqueFilename:name ext:ext nameSet:nameSet];
                NSString *newPath = [path.stringByDeletingLastPathComponent stringByAppendingPathComponent:newFilename];
                [[NSFileManager defaultManager] moveItemAtPath:path toPath:newPath error:nil];
                finalPath = newPath;
            }
        }
        [nameSet addObject:[finalPath lastPathComponent]];
        
        SeafUploadFile *file = [[SeafUploadFile alloc] initWithPath:finalPath];
        file.model.overwrite = overwrite;
        file.delegate = self;
        [files addObject:file];
        [self.directory addUploadFile:file];
    }
    
    [self reloadTable];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [SeafDataTaskManager.sharedObject addUploadTasksInBatch:files forConnection:self.connection];
    });
}

// Refactored to ensure uploadDir exists once, and only stopAccessing if started.
- (void)uploadFilesAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;

    // Show a HUD to indicate preprocessing work
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Preparing files …", @"Seafile")];

    @weakify(self);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Ensure the upload directory exists before copying
        NSString *uploadDir = [self.connection uniqueUploadDir];
        if (![[NSFileManager defaultManager] fileExistsAtPath:uploadDir]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:uploadDir
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:nil];
        }

        NSSet *nameSet = [self getExistedNameSet];
        NSMutableArray *filesToUpload = [NSMutableArray array];
        int duplicated = 0;
        int copyFailedCount = 0;

        for (NSURL *url in urls) {
            NSString *fileName = url.lastPathComponent;
            NSString *destinationPath = [uploadDir stringByAppendingPathComponent:fileName];

            // Remove any existing file to avoid copy failure
            if ([[NSFileManager defaultManager] fileExistsAtPath:destinationPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:destinationPath error:NULL];
            }

            BOOL accessing = [url startAccessingSecurityScopedResource];
            __block BOOL success = NO;

            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
            [coordinator coordinateReadingItemAtURL:url
                                            options:NSFileCoordinatorReadingWithoutChanges
                                              error:nil
                                         byAccessor:^(NSURL *newURL) {
                NSError *copyError = nil;
                success = [[NSFileManager defaultManager] copyItemAtURL:newURL
                                                                    toURL:[NSURL fileURLWithPath:destinationPath]
                                                                    error:&copyError];
                if (!success) {
                    Warning("Failed to copy file for upload: %@", copyError);
                }
            }];

            if (!success) {
                copyFailedCount++;
            } else {
                [filesToUpload addObject:destinationPath];
                if ([nameSet containsObject:fileName]) {
                    duplicated++;
                }
            }

            if (accessing) {
                [url stopAccessingSecurityScopedResource];
            }
        }

        // Switch back to main thread for UI updates
        dispatch_async(dispatch_get_main_queue(), ^{
            @strongify(self);
            [SVProgressHUD dismiss];

            if (copyFailedCount > 0 && copyFailedCount == urls.count) {
                [self alertWithTitle:NSLocalizedString(@"Failed to access selected file(s)", @"Seafile")];
                return;
            }

            if (duplicated > 0) {
                NSString *title = duplicated == 1 ? STR_12 : STR_13;
                @weakify(self);
                [self alertWithTitle:title message:nil yes:^{
                    @strongify(self);
                    [self startFileUploadsFromPaths:filesToUpload overwrite:YES];
                } no:^{
                    @strongify(self);
                    [self startFileUploadsFromPaths:filesToUpload overwrite:NO];
                }];
            } else {
                [self startFileUploadsFromPaths:filesToUpload overwrite:NO];
            }
        });
    });
}

#pragma mark - UIDocumentPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [controller dismissViewControllerAnimated:YES completion:^{
        [self uploadFilesAtURLs:urls];
    }];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    Debug("Document picker was cancelled");
    [controller dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - Various Helpers for Cell & File

- (SeafCell *)getCell:(NSString *)CellIdentifier forTableView:(UITableView *)tableView
{
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[SeafCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    [cell reset];
    return cell;
}

- (SeafCell *)getCellForTableView:(UITableView *)tableView
{
    return [self getCell:@"SeafCell" forTableView:tableView];
}

- (UITableViewCell *)getSeafUploadFileCell:(SeafUploadFile *)file forTableView:(UITableView *)tableView andIndexPath:(NSIndexPath *)indexPath
{
    file.delegate = self;
    SeafCell *cell = [self getCellForTableView:tableView];
    cell.textLabel.text = file.name;
    cell.cellIndexPath = indexPath;
    cell.imageView.image = [UIImage imageForMimeType:file.mime ext:file.name.pathExtension.lowercaseString];
    [file iconWithCompletion:^(UIImage *image) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([cell.cellIndexPath isEqual:indexPath]) {
                cell.imageView.image = image;
            }
        });
    }];
    if (file.model.uploading) {
        cell.progressView.hidden = false;
        [cell.progressView setProgress:file.uProgress];
    } else {
        NSString *sizeStr = [FileSizeFormatter stringFromLongLong:file.filesize];
        if (file.uploaded) {
            cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@, Uploaded %@", @"Seafile"), sizeStr, [SeafDateFormatter stringFromLongLong:(long long)file.lastFinishTimestamp]];
            [self updateCellDownloadStatus:cell isDownloading:false waiting:false cached:true];
        } else {
            cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@, waiting to upload", @"Seafile"), sizeStr];
            [self updateCellDownloadStatus:cell isDownloading:false waiting:false cached:false];
        }
    }
    
    [self setCellSaparatorAndCorner:cell andIndexPath:indexPath];

    return cell;
}

- (UITableViewCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView andIndexPath:(NSIndexPath *)indexPath
{
    [sfile loadCache];
    SeafCell *cell = [self getCellForTableView:tableView];
    
    cell.cellSeafFile = sfile;
    cell.cellIndexPath = indexPath;
    cell.moreButtonBlock = ^(NSIndexPath *indexPath) {
        Debug(@"%@", indexPath);
        [self showActionSheetWithIndexPath:indexPath];
    };
    [self updateCellContent:cell file:sfile];
    sfile.delegate = self;
    sfile.udelegate = self;
    
    [self setCellSaparatorAndCorner:cell andIndexPath:indexPath];

    return cell;
}

- (UITableViewCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView andIndexPath:(NSIndexPath *)indexPath
{
    SeafCell *cell = [self getCell:@"SeafDirCell" forTableView:tableView];
    cell.textLabel.text = sdir.name;
    cell.detailTextLabel.text = [sdir detailText];
    cell.imageView.image = sdir.icon;
    cell.cellIndexPath = indexPath;
    cell.moreButtonBlock = ^(NSIndexPath *indexPath) {
        Debug(@"%@", indexPath);
        [self showActionSheetWithIndexPath:indexPath];
    };
    sdir.delegate = self;
    
    [self setCellSaparatorAndCorner:cell andIndexPath:indexPath];

    return cell;
}

- (UITableViewCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView andIndexPath:(NSIndexPath *)indexPath
{
    SeafCell *cell = [self getCellForTableView:tableView];
    cell.detailTextLabel.text = srepo.detailText;
    cell.imageView.image = srepo.icon;
    cell.textLabel.text = srepo.name;
    [cell.cacheStatusWidthConstraint setConstant:0.0f];
    cell.cellIndexPath = indexPath;
    cell.moreButtonBlock = ^(NSIndexPath *indexPath) {
        Debug(@"%@", indexPath);
        [self showActionSheetWithIndexPath:indexPath];
    };
    srepo.delegate = self;
    
    [self setCellSaparatorAndCorner:cell andIndexPath:indexPath];

    return cell;
}

- (void)setCellSaparatorAndCorner:(UITableViewCell *)cell andIndexPath:(NSIndexPath *)indexPath {
    // Check if it's the last cell in section
    BOOL isLastCell = NO;
    if (![_directory isKindOfClass:[SeafRepos class]]) {
        isLastCell = (indexPath.row == self.allItems.count - 1);
    } else {
        NSArray *repoGroups = [((SeafRepos *)_directory) repoGroups];
        NSArray *repos = [repoGroups objectAtIndex:indexPath.section];
        isLastCell = (indexPath.row == repos.count - 1);
    }
    
    // Update cell separator
    if ([cell isKindOfClass:[SeafCell class]]) {
        [(SeafCell *)cell updateSeparatorInset:isLastCell];
    }
    
    [self setCellCornerWithCell:cell andIndexPath:indexPath];
}

- (void)setCellCornerWithCell:(UITableViewCell *)cell andIndexPath:(NSIndexPath *)indexPath {
    if ([cell isKindOfClass:[SeafCell class]]) {
        BOOL isFirstCell = (indexPath.row == 0);
        BOOL isLastCell = NO;
        
        if (![_directory isKindOfClass:[SeafRepos class]]) {
            isLastCell = (indexPath.row == self.allItems.count - 1);
        } else {
            NSArray *repoGroups = [((SeafRepos *)_directory) repoGroups];
            NSArray *repos = [repoGroups objectAtIndex:indexPath.section];
            isLastCell = (indexPath.row == repos.count - 1);
        }
        
        [(SeafCell *)cell updateCellStyle:isFirstCell isLastCell:isLastCell];
    }
}

- (void)showActionSheetWithIndexPath:(NSIndexPath *)indexPath {
    _selectedindex = indexPath;
    id entry = [self getDentrybyIndexPath:indexPath tableView:self.tableView];
    SeafCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    @weakify(self);
    [SeafActionsManager entryAction:entry inEncryptedRepo:[self.connection isEncrypted:self.directory.repoId] inTargetVC:self fromView:cell actionBlock:^(NSString *typeTile) {
        @strongify(self);
        [self handleAction:typeTile];
    }];
}

- (void)updateCellDownloadStatus:(SeafCell *)cell file:(SeafFile *)sfile waiting:(BOOL)waiting
{
    BOOL fileHasCache = [sfile isWebOpenFile] ? NO : sfile.hasCache; //To prevent downloading sfile files, force it to have no cache. Force set statusView hidden.
    [self updateCellDownloadStatus:cell isDownloading:sfile.isDownloading waiting:waiting cached:fileHasCache];
}

- (void)updateCellDownloadStatus:(SeafCell *)cell isDownloading:(BOOL )isDownloading waiting:(BOOL)waiting cached:(BOOL)cached
{
    if (!cell) return;
    if (isDownloading && cell.downloadingIndicator.isAnimating)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (cached || waiting || isDownloading) {
            cell.cacheStatusView.hidden = false;
            [cell.cacheStatusWidthConstraint setConstant:21.0f];

            if (isDownloading) {
                [cell.downloadingIndicator startAnimating];
            } else {
                [cell.downloadingIndicator stopAnimating];
                NSString *downloadImageNmae = waiting ? @"download_waiting" : @"download_finished";
                cell.downloadStatusImageView.image = [UIImage imageNamed:downloadImageNmae];
            }
            cell.downloadStatusImageView.hidden = isDownloading;
            cell.downloadingIndicator.hidden = !isDownloading;
        } else {
            [cell.downloadingIndicator stopAnimating];
            cell.cacheStatusView.hidden = true;
            [cell.cacheStatusWidthConstraint setConstant:0.0f];
        }
        [cell layoutIfNeeded];
    });
}

- (void)updateCellContent:(SeafCell *)cell file:(SeafFile *)sfile
{
    cell.textLabel.text = sfile.name;
    cell.detailTextLabel.text = sfile.detailText;
    // icon also enqueues the thumbnail download when it is missing. Document
    // thumbs (pdf/sdoc) are cropped from the top, see SeafThumbPreviewStyle.
    UIImage *icon = sfile.icon;
    [Utils setThumbImage:icon onImageView:cell.imageView
                   style:[Utils thumbPreviewStyleForFileName:sfile.name hasThumb:(sfile.thumb != nil)]];
    cell.badgeLabel.text = nil;
    [self updateCellDownloadStatus:cell file:sfile waiting:false];
}

- (SeafBase *)getDentrybyIndexPath:(NSIndexPath *)indexPath tableView:(UITableView *)tableView
{
    if (!indexPath) return nil;
    @try {
        if (![_directory isKindOfClass:[SeafRepos class]]) {
            // Handle regular files/directories when the directory is not a repository list
            if ([indexPath row] < self.allItems.count) {
                return [self.allItems objectAtIndex:[indexPath row]];
            } else {
                return nil;
            }
        } else {
            // Handle repository list when the directory is a repository list
            NSArray *repos = [[((SeafRepos *)_directory) repoGroups] objectAtIndex:[indexPath section]];
            if ([indexPath row] < repos.count) {
                return [repos objectAtIndex:[indexPath row]];
            } else {
                return nil;
            }
        }
    } @catch(NSException *exception) {
        return nil;
    }
}

- (void)reloadIndex:(NSIndexPath *)indexPath
{
    if (indexPath) {
        @try {
            if ([self isGridModeActive]) {
                [self.collectionView reloadItemsAtIndexPaths:@[indexPath]];
            } else {
                UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
                if (!cell) return;
                [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            }
        } @catch(NSException *exception) {
            Warning("Failed to reload cell %@: %@", indexPath, exception);
        }
    } else {
        [self reloadTable];
    }
}

- (NSUInteger)indexOfEntry:(id<SeafPreView>)entry {
    return [self.allItems indexOfObject:entry];
}

- (UITableView *)currentTableView{
    return self.tableView;
}

- (id)getEntryCell:(id)entry indexPath:(NSIndexPath **)indexPath
{
    NSUInteger index = [self indexOfEntry:entry];
    if (index == NSNotFound || index >= self.allItems.count)
        return nil;
    @try {
        NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
        if (indexPath) *indexPath = path;
        if ([self isGridModeActive]) {
            return [self.collectionView cellForItemAtIndexPath:path];
        }
        return (SeafCell *)[self.tableView cellForRowAtIndexPath:path];
    } @catch(NSException *exception) {
        Warning("Something wrong %@", exception);
        return nil;
    }
}

- (NSIndexPath *)indexPathForFileByIdentity:(SeafFile *)file
{
    if (!file) return nil;
    NSString *targetKey = file.uniqueKey;
    if (targetKey.length == 0) return nil;
    NSUInteger count = self.allItems.count;
    for (NSUInteger i = 0; i < count; i++) {
        id obj = self.allItems[i];
        if (![obj isKindOfClass:[SeafFile class]]) continue;
        SeafFile *candidate = (SeafFile *)obj;
        NSString *key = candidate.uniqueKey;
        if (key.length > 0 && [key isEqualToString:targetKey]) {
            return [NSIndexPath indexPathForRow:(NSInteger)i inSection:0];
        }
    }
    return nil;
}

- (void)updateEntryCell:(SeafFile *)entry
{
    @try {
        NSIndexPath *path = [self indexPathForFileByIdentity:entry];
        if (!path) {
            NSUInteger index = [self indexOfEntry:entry];
            if (index == NSNotFound || index >= self.allItems.count) return;
            path = [NSIndexPath indexPathForRow:index inSection:0];
        }

        BOOL updated = NO;
        if ([self isGridModeActive]) {
            UICollectionViewCell *cvCell = [self.collectionView cellForItemAtIndexPath:path];
            if ([cvCell isKindOfClass:[SeafGridCell class]]) {
                [(SeafGridCell *)cvCell configureWithFile:entry];
                updated = YES;
            }
        } else {
            UITableViewCell *tvCell = [self.tableView cellForRowAtIndexPath:path];
            if ([tvCell isKindOfClass:[SeafCell class]]) {
                [self updateCellContent:(SeafCell *)tvCell file:entry];
                updated = YES;
            }
        }

        if (!updated) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self reloadIndex:path];
            });
        }
    } @catch(NSException *exception) {
        Warning("updateEntryCell exception: %@", exception);
    }
}

/// Refresh only the thumbnail/icon on a visible cell — avoids `configureWithFile`'s
/// `resetCellFile` (which cancels in-flight thumb tasks) and skips file-download HUD paths.
- (void)updateEntryCellThumbnail:(SeafFile *)entry
{
    if (!entry) return;
    @try {
        NSIndexPath *path = nil;
        id cell = [self getEntryCell:entry indexPath:&path];
        // Prefer thumb cache (warmed after download). Avoid `icon` here: it can
        // re-enqueue downloads and falls back to a type icon unsuitable for media layout.
        UIImage *thumb = entry.thumb;
        if ([cell isKindOfClass:[SeafGridCell class]]) {
            SeafGridCell *gridCell = (SeafGridCell *)cell;
            // Match upload-thumb path: directory reload/reuse can leave the same
            // index path showing a different file by the time this lands.
            if (gridCell.cellSeafFile != entry) {
                return;
            }
            if (thumb) {
                [gridCell setThumbnailImage:thumb style:[Utils thumbPreviewStyleForFileName:entry.name hasThumb:YES]];
            } else {
                NSIndexPath *ip = path ?: [self indexPathForFileByIdentity:entry];
                if (ip) {
                    [self reloadIndex:ip];
                }
            }
            return;
        }
        if ([cell isKindOfClass:[SeafCell class]]) {
            SeafCell *listCell = (SeafCell *)cell;
            if (listCell.cellSeafFile != entry) {
                return;
            }
            if (thumb) {
                [Utils setThumbImage:thumb onImageView:listCell.imageView
                               style:[Utils thumbPreviewStyleForFileName:entry.name hasThumb:YES]];
            } else {
                NSIndexPath *ip = path ?: [self indexPathForFileByIdentity:entry];
                if (ip) {
                    [self reloadIndex:ip];
                }
            }
            return;
        }
        NSIndexPath *ip = path ?: [self indexPathForFileByIdentity:entry];
        if (ip) {
            [self reloadIndex:ip];
        }
    } @catch(NSException *exception) {
        Warning("updateEntryCellThumbnail exception: %@", exception);
    }
}

#pragma mark - Upload / Update Delegate

- (void)uploadFile:(SeafUploadFile *)ufile toDir:(SeafDir *)dir overwrite:(BOOL)overwrite
{
    [SVProgressHUD showInfoWithStatus:[NSString stringWithFormat:NSLocalizedString(@"%@, uploading", @"Seafile"), ufile.name]];
    ufile.model.overwrite = overwrite;
    [dir addUploadFile:ufile];
    [SeafDataTaskManager.sharedObject addUploadTask:ufile];
}

- (void)uploadFile:(SeafUploadFile *)ufile toDir:(SeafDir *)dir
{
    if ([dir nameExist:ufile.name]) {
        @weakify(self);
        [self alertWithTitle:STR_12 message:nil yes:^{
            @strongify(self);
            [self uploadFile:ufile toDir:dir overwrite:true];
        } no:^{
            @strongify(self);
            [self uploadFile:ufile toDir:dir overwrite:false];
        }];
    } else
        [self uploadFile:ufile toDir:dir overwrite:false];
}

- (void)uploadFile:(SeafUploadFile *)file
{
    file.delegate = self;
    [self popupDirChooseView:file];
}

#pragma mark - SeafDirDelegate
- (void)chooseDir:(UIViewController *)c dir:(SeafDir *)dstDir
{
    NSArray *selectedIndexPaths = [self selectedEntryIndexPaths];
    NSMutableArray *entries = [NSMutableArray new];
    // Prefer the cached entries captured at the moment user tapped Copy/Move,
    // this is more reliable on iPad where table selection state might change.
    if (self.pendingEntriesForOperation.count > 0) {
        [entries addObjectsFromArray:self.pendingEntriesForOperation];
    } else {
        for (NSIndexPath *indexPath in selectedIndexPaths) {
            if (indexPath.row >= self.allItems.count) continue;
            SeafBase *item = self.allItems[indexPath.row];
            [entries addObject:item.name];
        }
    }
    
    // Exit edit mode first
    [self editDone:nil];
    
    // Then close the directory picker
    [c.navigationController dismissViewControllerAnimated:YES completion:nil];
    
    if (self.ufile) {
        return [self uploadFile:self.ufile toDir:dstDir];
    }

    _directory.delegate = self;

    // Clear cache after we have consumed it
    self.pendingEntriesForOperation = nil;

    if (self.state == STATE_COPY) {
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Copying files ...", @"Seafile")];
        Debug("[CopyFlow] calling copyEntries, srcRepo=%@ srcPath=%@ dstRepo=%@ dstPath=%@ entries=%@",
              self.directory.repoId, self.directory.path,
              dstDir.repoId, dstDir.path,
              entries);
        [[SeafFileOperationManager sharedManager]
            copyEntries:entries
            fromDir:self.directory
            toDir:dstDir
            completion:^(BOOL success, NSError * _Nullable error){
                if (success) {
                    Debug("[CopyFlow] copyEntries completion success, srcRepo=%@ srcPath=%@ dstRepo=%@ dstPath=%@ entries=%@",
                          self.directory.repoId, self.directory.path,
                          dstDir.repoId, dstDir.path,
                          entries);
                } else {
                    Warning("[CopyFlow] copyEntries completion failed, srcRepo=%@ srcPath=%@ dstRepo=%@ dstPath=%@ entries=%@ error=%@",
                            self.directory.repoId, self.directory.path,
                            dstDir.repoId, dstDir.path,
                            entries, error);
                }
            }];
    } else if (self.state == STATE_MOVE) {
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Moving files ...", @"Seafile")];
        Debug("[CopyFlow] calling moveEntries, srcRepo=%@ srcPath=%@ dstRepo=%@ dstPath=%@ entries=%@",
              self.directory.repoId, self.directory.path,
              dstDir.repoId, dstDir.path,
              entries);
        [[SeafFileOperationManager sharedManager]
            moveEntries:entries
            fromDir:self.directory
            toDir:dstDir
            completion:^(BOOL success, NSError * _Nullable error){
                if (success) {
                    Debug("[CopyFlow] moveEntries completion success, srcRepo=%@ srcPath=%@ dstRepo=%@ dstPath=%@ entries=%@",
                          self.directory.repoId, self.directory.path,
                          dstDir.repoId, dstDir.path,
                          entries);
                    [self.directory loadContent:YES];
                } else {
                    Warning("[CopyFlow] moveEntries completion failed, srcRepo=%@ srcPath=%@ dstRepo=%@ dstPath=%@ entries=%@ error=%@",
                            self.directory.repoId, self.directory.path,
                            dstDir.repoId, dstDir.path,
                            entries, error);
                    [SVProgressHUD showErrorWithStatus:error.localizedDescription];
                }
            }];
    }
}

- (void)cancelChoose:(UIViewController *)c
{
    self.state = STATE_INIT;
    [c.navigationController dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - SeafDentryDelegate (Download callbacks)

- (SeafPhoto *)getSeafPhoto:(id<SeafPreView>)photo {
    if (![photo isImageFile])
        return nil;
    for (SeafPhoto *sphoto in self.photos) {
        if (sphoto.file == photo) {
            return sphoto;
        }
    }
    return nil;
}

- (void)thumbnailDownload:(id)entry complete:(BOOL)success
{
    if (!success || ![entry isKindOfClass:[SeafFile class]]) return;
    [self updateEntryCellThumbnail:(SeafFile *)entry];
}

- (void)download:(SeafBase *)entry progress:(float)progress
{
    if ([entry isKindOfClass:[SeafFile class]]) {
        // While unified progress is active, avoid triggering the detail view HUD to keep the custom overlay authoritative
        if (!(self.selectionCoordinator.isAggregating) && !self.selectionCoordinator.unifiedAllMediaProgressActive) {
            [self.detailViewController download:entry progress:progress];
        }
        // Still update the cell’s visible progress
        SeafPhoto *photo = [self getSeafPhoto:(id<SeafPreView>)entry];
        [photo setProgress:progress];
        id cell = [self getEntryCell:(SeafFile *)entry indexPath:nil];
        if ([cell isKindOfClass:[SeafCell class]]) {
            [self updateCellDownloadStatus:(SeafCell *)cell file:(SeafFile *)entry waiting:false];
        } else if ([cell isKindOfClass:[SeafGridCell class]]) {
            [(SeafGridCell *)cell updateDownloadStatusForFile:(SeafFile *)entry waiting:NO];
        }
    }
    // Aggregate progress update
    [self updateAggregateProgressForEntry:entry progress:progress];
}

- (void)download:(SeafBase *)entry complete:(BOOL)updated
{
    if (self.state == STATE_COPY) {
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Successfully copied", @"Seafile")];
    } else if (self.state == STATE_MOVE) {
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Successfully moved", @"Seafile")];
    } else if (self.state != STATE_EXPORT && !(self.selectionCoordinator.isAggregating) && !self.selectionCoordinator.unifiedAllMediaProgressActive) {
        // Prevent the unified progress flow from dismissing the overall HUD
        [SVProgressHUD dismiss];
    }
    if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)entry;
        [self updateEntryCell:file];
        // If an early refresh missed hasCache, retry shortly to keep state current
        if (![file isWebOpenFile] && !file.hasCache) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self updateEntryCell:file];
            });
        }
        if (self.state == STATE_SHARE_SHARE_WECHAT) {
            [self shareToWechat:file];
        } else if (!(self.selectionCoordinator.isAggregating) && !self.selectionCoordinator.unifiedAllMediaProgressActive) {
            // During unified progress, skip detail view callbacks so the overlay control stays consistent
            [self.detailViewController download:file complete:updated];
            SeafPhoto *photo = [self getSeafPhoto:(id<SeafPreView>)entry];
            [photo complete:updated error:nil];
        }
        // Notify coordinator for aggregate bookkeeping
        [self.selectionCoordinator notifyFileDownloadCompleted:file error:nil];
    } else if (entry == _directory) {
        [self dismissLoadingView];
        [self doneLoadingTableViewData];
        if (self.state == STATE_DELETE && !IsIpad()) {
            [self.detailViewController goBack:nil];
        }

        [self dismissLoadingView];
        // A load a link is waiting on reports back even if nothing changed.
        BOOL linkRefresh = self.gotoRefreshRepoId != nil
            && (self.gotoRefreshState == SeafLinkRefreshRequested
                || self.gotoRefreshState == SeafLinkRefreshAwaitingEarlierLoad);
        if (linkRefresh && self.gotoRefreshState == SeafLinkRefreshRequested)
            self.gotoRefreshState = SeafLinkRefreshFinished;
        if (updated || linkRefresh) {
            [self refreshView];
            [SeafAppDelegate checkOpenLink:self];
        } else {
            if ([entry isKindOfClass:[SeafDir class]] && [self checkIsEditedFileUploading:(SeafDir *)entry]) {
                [self refreshView];
                [SeafAppDelegate checkOpenLink:self];
            }
        }
        self.state = STATE_INIT;
    }

    /* Auto-play the video once it has been downloaded */
    if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *videoFileTmp = (SeafFile *)entry;
        if (videoFileTmp == self.pendingVideoFile && [videoFileTmp isVideoFile] && videoFileTmp.hasCache) {
            // Reset pending flag first
            self.pendingVideoFile = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                void (^presentPlayer)(void) = ^{
                    [SeafVideoPlayerViewController closeActiveVideoPlayer];
                    SeafVideoPlayerViewController *playerVC = [[SeafVideoPlayerViewController alloc] initWithFile:videoFileTmp];
                    [self presentViewController:playerVC animated:YES completion:nil];
                };
                if (self.presentedViewController) {
                    [self dismissViewControllerAnimated:NO completion:presentPlayer];
                } else if (self.detailViewController.presentedViewController) {
                    [self.detailViewController dismissViewControllerAnimated:NO completion:presentPlayer];
                } else {
                    presentPlayer();
                }
            });
        }
    }
}

- (BOOL)checkIsEditedFileUploading:(SeafDir *)entry {
    SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:self->_connection];
    NSArray *allUpLoadTasks = [accountQueue getNeedUploadTasks];
    
    BOOL hasEditedFile = false;
    if (allUpLoadTasks.count > 0) {
        NSPredicate *nonNilPredicate = [NSPredicate predicateWithFormat:@"editedFileOid != nil"];
        NSArray *nonNilTasks = [allUpLoadTasks filteredArrayUsingPredicate:nonNilPredicate];

        for (SeafBase *tempItem in entry.allItems){
            SeafBase *__strong item = tempItem; // strong reference
            if ([item isKindOfClass:[SeafFile class]]) {
                for (SeafUploadFile *file in nonNilTasks) {
                    if ([file.editedFilePath isEqualToString:item.path] && [file.editedFileRepoId isEqualToString:item.repoId]) {
                        SeafFile *fileItem = (SeafFile *)item;
                        fileItem.ufile = file;
                        [fileItem setMpath:file.lpath];
                        fileItem.udelegate = self;
                        fileItem.ufile.delegate = fileItem;
                        item = fileItem;
                        hasEditedFile = true;
                    }
                }
            }
        }
    }
    return hasEditedFile;
}

- (void)download:(SeafBase *)entry failed:(NSError *)error
{
    if ([entry isKindOfClass:[SeafFile class]]) {
        if (self.state != STATE_EXPORT && !(self.selectionCoordinator.isAggregating) && !self.selectionCoordinator.unifiedAllMediaProgressActive) {
            [SVProgressHUD dismiss];
        }
        SeafFile *file = (SeafFile *)entry;
        [self updateEntryCell:file];
        if (!(self.selectionCoordinator.isAggregating) && !self.selectionCoordinator.unifiedAllMediaProgressActive) {
            [self.detailViewController download:entry failed:error];
            SeafPhoto *photo = [self getSeafPhoto:file];
            [photo complete:false error:error];
        }
        // Notify coordinator for aggregate bookkeeping (failure)
        [self.selectionCoordinator notifyFileDownloadCompleted:file error:error];
        return;
    }

    NSCAssert([entry isKindOfClass:[SeafDir class]], @"entry must be SeafDir");
    Debug("state=%d %@,%@, %@\n", self.state, entry.path, entry.name, _directory.path);
    if (entry == _directory) {
        [self doneLoadingTableViewData];
        if (self.gotoRefreshRepoId && self.gotoRefreshState == SeafLinkRefreshAwaitingEarlierLoad) {
            // The earlier load the link was waiting on failed; it was not the
            // link's. Let the link send its own once this failure is handled.
            [SeafAppDelegate checkOpenLink:self];
        } else if (self.gotoRefreshRepoId && self.gotoRefreshState == SeafLinkRefreshRequested) {
            // The refresh a link was waiting for failed: the library cannot be
            // looked up, so end the link instead of leaving it pending.
            NSString *repoId = self.gotoRefreshRepoId;
            [self resetLinkState];
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate endGotoForRepo:repoId];
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to find library", @"Seafile")];
            self.state = STATE_INIT;
            [self dismissLoadingView];
            return;
        }
        switch (self.state) {
            case STATE_DELETE:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to delete files", @"Seafile")];
                break;
            case STATE_MKDIR:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to create folder", @"Seafile")];
                [self performSelector:@selector(popupMkdirView) withObject:nil afterDelay:1.0];
                break;
            case STATE_CREATE:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to create file", @"Seafile")];
                [self performSelector:@selector(popupCreateView) withObject:nil afterDelay:1.0];
                break;
            case STATE_COPY:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to copy files", @"Seafile")];
                break;
            case STATE_MOVE:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to move files", @"Seafile")];
                break;
            case STATE_RENAME: {
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to rename file", @"Seafile")];
                NSString *oldName = [(SeafBase *)_curEntry name];
                [self performSelector:@selector(popupRenameView:) withObject:oldName afterDelay:1.0];
                break;
            }
            case STATE_LOADING:
                if (!_directory.hasCache) {
                    [self dismissLoadingView];
                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load files", @"Seafile")];
                } else
                    [SVProgressHUD dismiss];
                break;
            case STATE_MKLIB:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to create library", @"Seafile")];
                [self performSelector:@selector(popupMklibView) withObject:nil afterDelay:1.0];
                break;
            default:
                break;
        }
        self.state = STATE_INIT;
        [self dismissLoadingView];
    }

    if (entry == self.pendingVideoFile) {
        self.pendingVideoFile = nil; // Clear pending flag on failure
    }
}


#pragma mark - SeafFileUpdateDelegate

- (void)updateProgress:(SeafFile *)file progress:(float)progress
{
    [self updateEntryCell:file];
}

- (void)updateComplete:(nonnull SeafFile *)file result:(BOOL)res
{
    [self updateEntryCell:file];
}


#pragma mark - SeafUploadDelegate

- (void)updateFileCell:(SeafUploadFile *)file result:(BOOL)res progress:(float)progress completed:(BOOL)completed
{
    NSIndexPath *indexPath = nil;
    id cell = [self getEntryCell:file indexPath:&indexPath];
    if (!cell) return;
    if ([cell isKindOfClass:[SeafGridCell class]]) {
        SeafGridCell *gridCell = (SeafGridCell *)cell;
        if (!completed && res) {
            [gridCell updateUploadProgress:progress uploaded:NO filesize:file.filesize timestamp:file.lastFinishTimestamp];
        } else if (indexPath) {
            [self reloadIndex:indexPath];
        }
        return;
    }
    SeafCell *listCell = (SeafCell *)cell;
    if (!completed && res) {
        listCell.progressView.hidden = false;
        listCell.detailTextLabel.text = nil;
        [listCell.progressView setProgress:progress];
    } else if (indexPath) {
        [self reloadIndex:indexPath];
    }
}

- (void)uploadProgress:(SeafUploadFile *)file progress:(float)progress
{
    [self updateFileCell:file result:true progress:progress completed:false];
}

- (void)uploadComplete:(BOOL)success file:(SeafUploadFile *)file oid:(NSString *)oid
{
    [self updateFileCell:file result:success progress:1.0f completed:YES];
    if (success && self.isVisible) {
        [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:NSLocalizedString(@"File '%@' uploaded successfully", @"Seafile"), file.name]];
    }
}


#pragma mark - SeafShareDelegate

- (void)generateSharelink:(SeafBase *)entry WithResult:(BOOL)success
{
    SeafBase *base = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
    if (entry != base) {
        [SVProgressHUD dismiss];
        return;
    }

    if (!success) {
        if ([entry isKindOfClass:[SeafFile class]])
            [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to generate share link of file '%@'", @"Seafile"), entry.name]];
        else
            [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to generate share link of directory '%@'", @"Seafile"), entry.name]];
        return;
    }
    [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Generate share link success", @"Seafile")];

    if (self.state == STATE_SHARE_EMAIL) {
        [self sendMailInApp:entry];
    } else if (self.state == STATE_SHARE_LINK){
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        [pasteboard setString:entry.shareLink];
    }
}


#pragma mark - Mail Compose (MFMailComposeViewControllerDelegate)

- (void)sendMailInApp:(SeafBase *)entry
{
    Class mailClass = (NSClassFromString(@"MFMailComposeViewController"));
    if (!mailClass) {
        [self alertWithTitle:NSLocalizedString(@"This function is not supportted yet，you can copy it to the pasteboard and send mail by yourself", @"Seafile")];
        return;
    }
    if (![mailClass canSendMail]) {
        [self alertWithTitle:NSLocalizedString(@"The mail account has not been set yet", @"Seafile")];
        return;
    }

    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    MFMailComposeViewController *mailPicker = appdelegate.globalMailComposer;
    mailPicker.mailComposeDelegate = self;
    NSString *emailSubject, *emailBody;
    if ([entry isKindOfClass:[SeafFile class]]) {
        emailSubject = [NSString stringWithFormat:NSLocalizedString(@"File '%@' is shared with you using %@", @"Seafile"), entry.name, APP_NAME];
        emailBody = [NSString stringWithFormat:NSLocalizedString(@"Hi,<br/><br/>Here is a link to <b>'%@'</b> in my %@:<br/><br/> <a href=\"%@\">%@</a>\n\n", @"Seafile"), entry.name, APP_NAME, entry.shareLink, entry.shareLink];
    } else {
        emailSubject = [NSString stringWithFormat:NSLocalizedString(@"Directory '%@' is shared with you using %@", @"Seafile"), entry.name, APP_NAME];
        emailBody = [NSString stringWithFormat:NSLocalizedString(@"Hi,<br/><br/>Here is a link to directory <b>'%@'</b> in my %@:<br/><br/> <a href=\"%@\">%@</a>\n\n", @"Seafile"), entry.name, APP_NAME, entry.shareLink, entry.shareLink];
    }
    [mailPicker setSubject:emailSubject];
    [mailPicker setMessageBody:emailBody isHTML:YES];
    mailPicker.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:mailPicker animated:YES completion:nil];
}

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
    NSString *msg;
    switch (result) {
        case MFMailComposeResultCancelled:
            msg = @"cancalled";
            break;
        case MFMailComposeResultSaved:
            msg = @"saved";
            break;
        case MFMailComposeResultSent:
            msg = @"sent";
            break;
        case MFMailComposeResultFailed:
            msg = @"failed";
            break;
        default:
            msg = @"";
            break;
    }
    Debug("share file:send mail %@\n", msg);
    [self dismissViewControllerAnimated:YES completion:^{
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate cycleTheGlobalMailComposer];
    }];
}

// Called when user scrolls to another photo
- (void)photoSelectedChanged:(id<SeafPreView>)from to:(id<SeafPreView>)to;
{
    NSUInteger index = [self indexOfEntry:to];
    if (index == NSNotFound)
        return;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    if ([self isGridModeActive]) {
        // Scroll only — do not selectItem:. Grid multi-select reuses
        // indexPathsForSelectedItems; a lingering selection here would be
        // counted into the next long-press edit session.
        @try {
            [self.collectionView scrollToItemAtIndexPath:indexPath
                                        atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                                                animated:NO];
        } @catch (NSException *exception) {
            Warning("scroll to item failed: %@", exception);
        }
    } else {
        [[self currentTableView] scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    }
}

- (void)refreshDownloadStatus {
    if ([self isGridModeActive]) {
        for (UICollectionViewCell *cell in self.collectionView.visibleCells) {
            if (![cell isKindOfClass:[SeafGridCell class]]) continue;
            NSIndexPath *indexPath = [self.collectionView indexPathForCell:cell];
            id entry = [self getDentrybyIndexPath:indexPath tableView:nil];
            if ([entry isKindOfClass:[SeafFile class]]) {
                [(SeafGridCell *)cell updateDownloadStatusForFile:(SeafFile *)entry waiting:NO];
            }
        }
        return;
    }
    NSArray *visibleCells = [self.tableView visibleCells];
    for (UITableViewCell *cell in visibleCells) {
        if ([cell isKindOfClass:[SeafCell class]]) {
            NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
            id entry = [self getDentrybyIndexPath:indexPath tableView:self.tableView];
            if ([entry isKindOfClass:[SeafFile class]]) {
                [self updateCellDownloadStatus:(SeafCell *)cell file:(SeafFile *)entry waiting:false];
            }
        }
    }
}

- (void)refreshEncryptedThumb {
    if ([self.connection isEncrypted:self.directory.repoId] && [self.connection isDecrypted:self.directory.repoId]) {
        [self.tableView reloadData];
        if ([self isGridModeActive]) {
            [self.collectionView reloadData];
        } else {
            self.collectionNeedsReload = YES;
        }
    }
}

#pragma mark - Lazy init
// getter searchResultController
- (SeafSearchResultViewController *)searchResultController {
    if (!_searchResultController) {
        _searchResultController = [[SeafSearchResultViewController alloc] init];
        _searchResultController.masterVC = self;
    }
    return _searchResultController;
}

- (UISearchController *)searchController {
    if (!_searchController) {
        _searchController = [[UISearchController alloc] initWithSearchResultsController:self.searchResultController];
        _searchController.searchResultsUpdater = self.searchResultController;
        _searchController.delegate = self;
        if (IsIpad()) {
            _searchController.hidesNavigationBarDuringPresentation = NO; // Keep navigation bar visible
        }
        
        BOOL usesMinimalSearchBar = IsIpad() && ![self isRepoRootDirectory];
        _searchController.searchBar.searchBarStyle = usesMinimalSearchBar ? UISearchBarStyleMinimal : UISearchBarStyleProminent;
        _searchController.obscuresBackgroundDuringPresentation = NO;
        
        // Additional style settings for iOS appearance
        _searchController.searchBar.translucent = YES;  // Make it translucent for the gray appearance

        // Apply a 38px leading margin to the UISearchBar to indent its content (the searchTextField)
        // This makes space for our custom back button (30px width) and its 8px leading offset.
        _searchController.searchBar.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 42, 0, 0);
        
        // Configure search bar appearance like system search.
        // Light mode restores the pre-dark-theme look; dark mode keeps the system color.
        UIColor *searchBarBg;
        searchBarBg = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull tc) {
            return tc.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor secondarySystemBackgroundColor]
                : [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0];
        }];
        if (!usesMinimalSearchBar) {
            _searchController.searchBar.barTintColor = searchBarBg;
        }
        _searchController.searchBar.backgroundColor = searchBarBg;
        
        // Remove any background images to show the default system appearance
        [_searchController.searchBar setBackgroundImage:nil forBarPosition:UIBarPositionAny barMetrics:UIBarMetricsDefault];
        [_searchController.searchBar setBackgroundImage:nil];
        
        // Set the overall tint color for the search bar elements (custom buttons, cursor etc.)
        _searchController.searchBar.tintColor = BAR_COLOR;
        
        // Set placeholder text style and color
        UITextField *searchField = _searchController.searchBar.searchTextField;
        searchField.placeholder = NSLocalizedString(@"Search files in this library", @"Seafile");
        // The default rounded border adds a system fill overlay that tints our color
        // (white renders as gray). Drop it and restore the pill shape manually so the
        // background color takes effect.
        searchField.borderStyle = UITextBorderStyleNone;
        searchField.layer.cornerRadius = 10.0;
        searchField.clipsToBounds = YES;
        // Light mode restores the pre-dark-theme white field; dark mode keeps the system color.
        searchField.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull tc) {
            return tc.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor tertiarySystemGroupedBackgroundColor]
                : [UIColor whiteColor];
        }];

        // Add custom search icon to the left of the text field
        UIImage *searchIcon = [[UIImage imageNamed:@"fileNav_search"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIImageView *searchIconImageView = [[UIImageView alloc] initWithImage:searchIcon];
        searchIconImageView.tintColor = [SeafTheme secondaryText];
        searchIconImageView.contentMode = UIViewContentModeScaleAspectFit;

        // Scale the icon with Dynamic Type so its proportion to the text stays consistent
        // in large-text mode. Sizing the container to the icon lets UITextField center it
        // vertically regardless of the (possibly enlarged) field height.
        CGFloat iconSize = [[UIFontMetrics defaultMetrics] scaledValueForValue:16.0];
        UIView *leftViewContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, iconSize, iconSize)];
        searchIconImageView.frame = leftViewContainer.bounds;
        searchIconImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [leftViewContainer addSubview:searchIconImageView];

        searchField.leftView = leftViewContainer;
        searchField.leftViewMode = UITextFieldViewModeAlways;
        
        // Configure custom appearance for search presentation
        [SeafNavigationBarStyler applyStandardAppearanceToNavigationController:self.navigationController];
        
        // For search bar, we can only set these properties
        // System default styling will now largely apply to the text field
        _searchController.searchBar.tintColor = BAR_COLOR;
        
        // Hide the Cancel button
        _searchController.searchBar.showsCancelButton = NO;

        [_searchController.searchBar sizeToFit];

        // Create and add custom back button on the far left. Center it vertically with Auto
        // Layout so it stays aligned for every search bar height, including Dynamic Type
        // large-text mode (previously iPhone pinned it to the top; only iPad was centered).
        UIButton *customBackButton = [UIButton buttonWithType:UIButtonTypeCustom];
        customBackButton.accessibilityIdentifier = @"search_back_button";
        UIImage *backImage = [[UIImage imageNamed:@"arrowLeft_black"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]; // Ensure it's a template image
        [customBackButton setImage:backImage forState:UIControlStateNormal];
        customBackButton.tintColor = [SeafTheme galleryOperationText];
        customBackButton.imageEdgeInsets = UIEdgeInsetsMake(12, 0, 12, 10);
        customBackButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [customBackButton addTarget:self action:@selector(customSearchDismissAction:) forControlEvents:UIControlEventTouchUpInside];

        customBackButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_searchController.searchBar addSubview:customBackButton];
        self.searchBarBackButton = customBackButton;

        // Align to the search field's vertical center (not the bar's) — the field is not
        // centered within the bar, so centering on the bar makes the button sit too low.
        UIView *verticalCenterView = _searchController.searchBar;
        verticalCenterView = _searchController.searchBar.searchTextField;
        [NSLayoutConstraint activateConstraints:@[
            [customBackButton.leadingAnchor constraintEqualToAnchor:_searchController.searchBar.leadingAnchor constant:12],
            [customBackButton.centerYAnchor constraintEqualToAnchor:verticalCenterView.centerYAnchor],
            [customBackButton.widthAnchor constraintEqualToConstant:30],
            [customBackButton.heightAnchor constraintEqualToConstant:44],
        ]];
        
        // Listen for notifications to handle search cancellation
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(searchCancelled:)
                                                     name:@"SeafSearchCancelled"
                                                   object:nil];
        
        self.definesPresentationContext = YES;
    }
    return _searchController;
}

/// Non-search placeholder used as tableHeaderView when the directory is not the repo root.
- (UIView *)directoryTableHeaderPlaceholder {
    return [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 10.0)];
}

- (void)setCollectionViewSearchBarInset:(CGFloat)top {
    if (!self.collectionView) return;
    UIEdgeInsets inset = self.collectionView.contentInset;
    if (fabs(inset.top - top) < 0.5) return;
    // A grid resting at its top keeps resting there, so the first row starts below the bar
    // instead of under it. In the glass sidebar the grid also has the system top inset
    // (it extends under the navigation bar); elsewhere that part is zero.
    CGFloat systemTop = self.collectionView.adjustedContentInset.top - inset.top;
    CGPoint offset = self.collectionView.contentOffset;
    BOOL atTop = offset.y <= -(systemTop + inset.top) + 0.5;
    inset.top = top;
    self.collectionView.contentInset = inset;
    self.collectionView.scrollIndicatorInsets = inset;
    if (atTop) {
        offset.y = -(systemTop + top);
        self.collectionView.contentOffset = offset;
    }
}

/// Holds the search bar above the grid, at the top of the safe area (self.view extends behind
/// the navigation bar, which stays visible on iPad). The bar keeps a zero origin inside it:
/// UISearchController lifts the bar into a container placed where the bar was but keeps the
/// bar's own frame origin, so a bar offset inside self.view would end up offset twice.
- (UIView *)gridSearchBarHost {
    if (!_gridSearchBarHost) {
        UIView *host = [[UIView alloc] init];
        host.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        host.hidden = YES;
        [self.view addSubview:host];
        _gridSearchBarHost = host;
    }
    return _gridSearchBarHost;
}

- (void)detachGridSearchBar {
    UISearchBar *bar = _searchController.searchBar;
    if (bar && bar.superview == _gridSearchBarHost) {
        [bar removeFromSuperview];
    }
    _gridSearchBarHost.hidden = YES;
}

/// Install the search bar on a visible host. Grid mode hides tableView, so the bar
/// goes into gridSearchBarHost instead of tableHeaderView.
- (void)presentSearchBar {
    UISearchBar *bar = self.searchController.searchBar;
    bar.hidden = NO;
    [bar sizeToFit];
    if (self.searchUsesVerticalBar) {
        // The navigation bar stays visible to host the rail's back item, so the search bar
        // takes the title row; a header-hosted bar would be moved underneath the nav bar.
        [self detachGridSearchBar];
        if (self.tableView.tableHeaderView == bar) {
            self.tableView.tableHeaderView = [self directoryTableHeaderPlaceholder];
        }
        [self setCollectionViewSearchBarInset:0];
        self.navigationItem.titleView = bar;
        return;
    }
    if ([self isGridModeActive]) {
        if (self.tableView.tableHeaderView == bar) {
            self.tableView.tableHeaderView = [self directoryTableHeaderPlaceholder];
        }
        CGFloat barHeight = CGRectGetHeight(bar.frame);
        UIView *host = self.gridSearchBarHost;
        host.frame = CGRectMake(0, self.view.safeAreaInsets.top, CGRectGetWidth(self.view.bounds), barHeight);
        host.hidden = NO;
        bar.frame = host.bounds;
        bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        if (bar.superview != host) {
            [host addSubview:bar];
        }
        [self.view bringSubviewToFront:host];
        [self setCollectionViewSearchBarInset:barHeight];
    } else {
        [self detachGridSearchBar];
        [self setCollectionViewSearchBarInset:0];
        self.tableView.tableHeaderView = bar;
        if ([self usesGlassSidebarChrome]) {
            // UIKit lifts the header from its current position when the search field gains focus.
            // Bring it below the opaque navigation bar first if the list is already scrolled.
            CGPoint offset = self.tableView.contentOffset;
            CGFloat top = -self.tableView.adjustedContentInset.top;
            if (offset.y > top) {
                offset.y = top;
                self.tableView.contentOffset = offset;
                [self.tableView layoutIfNeeded];
            }
        }
    }
}

/// Once active, UISearchController lifts the bar into its own container and adds the bar's
/// height to our top safe area. The list is pinned to that safe area, so the room reserved
/// for the bar (table header slot / grid top inset) would show as an empty band below it.
- (void)collapseSearchBarSlotIfLifted {
    if (self.searchUsesVerticalBar || !_searchController.active) return;
    UISearchBar *bar = _searchController.searchBar;
    if (!bar.window || [bar isDescendantOfView:self.tableView] || bar.superview == _gridSearchBarHost) return;
    UIScrollView *content = [self currentContentScrollView];
    CGFloat barBottom = CGRectGetMaxY([bar convertRect:bar.bounds toView:self.view]);
    // Where the list's content starts: its frame top, plus the system top inset when it
    // extends under the navigation bar (glass sidebar; zero when pinned to the safe area).
    CGFloat systemTop = content.adjustedContentInset.top - content.contentInset.top;
    CGFloat contentTop = CGRectGetMinY(content.frame) + systemTop;
    // Keep the slot when the bar still overlaps the list (safe area not adjusted).
    if (barBottom > contentTop + 0.5) return;
    if (self.tableView.tableHeaderView) {
        self.tableView.tableHeaderView = nil;
    }
    [self setCollectionViewSearchBarInset:0];
    // The surface would otherwise show as a strip between the bar and the list.
    self.navigationBackgroundView.hidden = YES;
}

- (void)updateTabBarForSearch:(BOOL)active {
    if (active) {
        if (![self.tabBarController isKindOfClass:SeafTabBarController.class]) return;
        self.searchTabBarController = (SeafTabBarController *)self.tabBarController;
        [self.searchTabBarController setTabBarHiddenForSearch:YES fromViewController:self];
    } else {
        [self.searchTabBarController setTabBarHiddenForSearch:NO fromViewController:self];
        self.searchTabBarController = nil;
    }
}

- (void)willPresentSearchController:(UISearchController *)searchController {
    [self updateTabBarForSearch:YES];
}

- (void)didPresentSearchController:(UISearchController *)searchController {
    [self updateTabBarForSearch:YES];
    [self collapseSearchBarSlotIfLifted];
}

- (void)didDismissSearchController:(UISearchController *)searchController {
    if (searchController != _searchController || searchController.active) return;
    // Also clean up when UIKit ends search directly (for example active = NO).
    [self dismissSearchBar];
    SeafDir *dir = self.pendingSearchResultDirectory;
    if (!dir) {
        [self updateTabBarForSearch:NO];
        return;
    }
    // After the dismissal (and the chrome restore around it) has finished, so the push is
    // not dropped as overlapping a transition. Release the search override in the same
    // turn, before UIKit captures the destination's hidesBottomBarWhenPushed policy.
    // iOS 18 can otherwise keep treating the pushed page as if its tabs were visible.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateTabBarForSearch:NO];
        [self pushSearchResultDirectory:dir];
        self.pendingSearchResultDirectory = nil;
    });
}

/// The search results live inside the search controller, which is presented and has no
/// navigation controller, so the folder is pushed from here. The search is closed first,
/// like on Android: on iPhone the navigation bar is hidden while it is up, and with a
/// vertical bar this page's items are swapped for the search back item.
- (void)openSearchResultDirectory:(SeafDir *)dir {
    if (!dir) return;
    if (!_searchController.active) {
        [self pushSearchResultDirectory:dir];
        return;
    }
    self.pendingSearchResultDirectory = dir;
    [self customSearchDismissAction:nil];
}

- (void)pushSearchResultDirectory:(SeafDir *)dir {
    SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
    [controller setDirectory:dir];
    [self.navigationController pushViewController:controller animated:YES];
}

/// Remove the search bar from whichever host it was attached to.
- (void)dismissSearchBar {
    self.navigationBackgroundView.hidden = NO;
    UISearchBar *bar = _searchController.searchBar;
    // UISearchController puts the bar back into the list while it dismisses; with its
    // slot collapsed it would flash on top of the first rows.
    bar.hidden = YES;
    if (bar && self.navigationItem.titleView == bar) {
        self.navigationItem.titleView = nil;
    }
    [self detachGridSearchBar];
    [self setCollectionViewSearchBarInset:0];
    if (![self.directory isKindOfClass:[SeafRepos class]]) {
        self.tableView.tableHeaderView = [self directoryTableHeaderPlaceholder];
    } else {
        self.tableView.tableHeaderView = nil;
    }
    // Ensure list/grid visibility matches the current mode after a grid search session.
    [self applyViewMode];
    [self releaseSearchPresentationContext];
    [self restoreNavigationChromeAfterSearch];
    if ([self usesGlassSidebarChrome]) {
        [self applySidebarBarAppearance];
        self.searchItem.hidden = NO;
        if (self.searchCloseItem && self.navigationItem.leftBarButtonItem == self.searchCloseItem) {
            self.navigationItem.leftBarButtonItem = nil;
            self.navigationItem.hidesBackButton = NO;
        }
    }
    // Bring back the large title set aside in -applySearchNavigationChrome; a list that was
    // scrolled keeps it collapsed until it is back at the top, as usual.
    if ([self usesLargeSidebarTitle]) {
        [self applySidebarTitleStyle];
        UIScrollView *content = [self currentContentScrollView];
        if (content.contentOffset.y <= -content.adjustedContentInset.top + 0.5) {
            [self expandSidebarLargeTitle];
        }
    }
}

- (void)customSearchDismissAction:(UIButton *)sender {
    // Disable animations, similar to searchBarCancelButtonClicked
    [UIView setAnimationsEnabled:NO];

    // Ensure search bar resigns first responder and search controller is deactivated
    if (self.searchController.searchBar && self.searchController.searchBar.isFirstResponder) {
        [self.searchController.searchBar resignFirstResponder];
    }
    if (self.searchController.active) {
        self.searchController.active = NO;
    }

    [self dismissSearchBar];

    // Restore animation settings, similar to searchCancelled logic (synchronously)
    [UIView setAnimationsEnabled:YES];
    
    if (self.navigationController && self.navigationController.navigationBar) {
        self.navigationController.navigationBar.alpha = 1.0;
    }
    self.tableView.alpha = 1.0;
    self.collectionView.alpha = 1.0;
}

// Handle search cancellation notification
- (void)searchCancelled:(NSNotification *)notification {
    // Every list page that has built its search controller observes this (posted when the
    // search bar is cancelled, e.g. with Escape on a hardware keyboard). In the glass sidebar
    // only the page whose search is up closes it; the others would otherwise reset their own
    // lists and resize the shared bar for their large titles.
    if ([self usesGlassSidebarChrome] && !_searchController.active && !_searchController.searchBar.window) {
        return;
    }
    // Disable animations
    [UIView setAnimationsEnabled:NO];
    
    // Directly set search controller to inactive state
    if (self.searchController.active) {
        self.searchController.active = NO;
    }
    
    [self dismissSearchBar];
    // Restore animation settings
    [UIView setAnimationsEnabled:YES];
    
    // Add fade-in effect for content
    self.tableView.alpha = 0.9;
    self.collectionView.alpha = 0.9;
    
    // Add fade-in animation for navigation bar and content
    [UIView animateWithDuration:0.3 animations:^{
        // Navigation bar fade-in
        if (self.navigationController && self.navigationController.navigationBar) {
            self.navigationController.navigationBar.alpha = 1.0;
        }
        
        self.tableView.alpha = 1.0;
        self.collectionView.alpha = 1.0;
    }];
}

- (void)setupCustomTabTool {
    // Remove existing custom view if present
    if (self.customToolView) {
        NSMutableArray *accessibleViews = [self.view.accessibilityElements mutableCopy];
        [accessibleViews removeObject:self.customToolView];
        self.view.accessibilityElements = accessibleViews;
        [self.customToolView removeFromSuperview];
        self.customToolView = nil;
    }
    
    // A sibling of the list: it stays fixed without covering the system side bar.
    CGRect frame = [self customToolFrame];
    
    // Create custom view
    UIView *customToolView = [[UIView alloc] initWithFrame:frame];
    customToolView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    customToolView.backgroundColor = [SeafTheme primarySurface];

    // Paint through the bottom safe-area gap without extending the panel's
    // hit region or covering the system side rail. A bottom tab bar remains
    // above this controller's view in the container hierarchy.
    UIView *bottomFill = [[UIView alloc] initWithFrame:CGRectZero];
    bottomFill.tag = 9000;
    bottomFill.userInteractionEnabled = NO;
    bottomFill.backgroundColor = [SeafTheme primarySurface];
    [customToolView addSubview:bottomFill];

    // Add top border as a UIView so the dynamic separator color adapts to theme changes
    UIView *topBorder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, customToolView.frame.size.width, 0.5)];
    topBorder.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    topBorder.backgroundColor = [SeafTheme separator];
    [customToolView addSubview:topBorder];
    
    // First row buttons - 5 buttons
    NSArray *firstRowTitles = @[
        NSLocalizedString(@"Download", @"Seafile"),
        NSLocalizedString(@"Rename", @"Seafile"),
        NSLocalizedString(@"Star", @"Seafile"),
        NSLocalizedString(@"Copy", @"Seafile"),
        NSLocalizedString(@"Share", @"Seafile")
    ];
    
    NSArray *firstRowIcons = @[
        @"action_download",
        @"action_rename",
        @"action_star",
        @"action_copy",
        @"action_share"
    ];
    
    // Second row buttons - 3 buttons
    NSArray *secondRowTitles = @[
        NSLocalizedString(@"Move", @"Seafile"),
        NSLocalizedString(@"Delete", @"Seafile"),
        NSLocalizedString(@"Properties", @"Seafile")
    ];
    
    NSArray *secondRowIcons = @[
        @"action_move",
        @"action_delete",
        @"detail_information"
    ];
    
    // Set initial position below screen
    CGRect initialFrame = customToolView.frame;
    initialFrame.origin.y = CGRectGetHeight(self.view.bounds);
    customToolView.frame = initialFrame;
    
    customToolView.accessibilityIdentifier = @"directory_selection_toolbar";
    customToolView.accessibilityContainerType = UIAccessibilityContainerTypeSemanticGroup;
    customToolView.shouldGroupAccessibilityChildren = YES;
    [self.view addSubview:customToolView];
    
    // Store reference
    self.customToolView = customToolView;
    // The page defines an explicit accessibility order for its scroll views.
    // Include this sibling panel so VoiceOver and UI automation can reach it.
    NSMutableArray *accessibleViews = [self.view.accessibilityElements mutableCopy];
    [accessibleViews addObject:customToolView];
    self.view.accessibilityElements = accessibleViews;
    
    // Create first row buttons
    for (int i = 0; i < firstRowTitles.count; i++) {
        UIView *buttonView = [self createTabButtonWithTitle:firstRowTitles[i]
                                                   iconName:firstRowIcons[i]
                                                     width:80.0  // Fixed width, consistent with common layout method
                                                      tag:i + 1001];
        [customToolView addSubview:buttonView];
    }

    // Create second row buttons
    for (int i = 0; i < secondRowTitles.count; i++) {
        NSInteger tag = i + 5 + 1001;
        UIView *buttonView = [self createTabButtonWithTitle:secondRowTitles[i]
                                                   iconName:secondRowIcons[i]
                                                     width:80.0
                                                      tag:tag];
        if (tag == 1008) { // ToolButtonProfile
            buttonView.isAccessibilityElement = YES;
            buttonView.accessibilityIdentifier = @"profile_properties_toolbar_button";
            buttonView.accessibilityLabel = secondRowTitles[i];
            buttonView.accessibilityTraits = UIAccessibilityTraitButton;
        }
        [customToolView addSubview:buttonView];
    }

    [self layoutCustomToolButtons];

    
    // Animate from bottom
    [UIView animateWithDuration:0.2 animations:^{
        self.customToolView.frame = frame;
    }];
}

- (CGRect)customToolFrame {
    CGRect safe = self.view.safeAreaLayoutGuide.layoutFrame;
    CGFloat height = MIN(kCustomTabToolTotalHeight, CGRectGetHeight(safe));
    // Keep the entire panel inside the page, whether tabs are beside or below it.
    return CGRectMake(CGRectGetMinX(safe), CGRectGetMaxY(safe) - height,
                      CGRectGetWidth(safe), height);
}

- (void)layoutCustomToolButtons {
    if (!self.customToolView) return;
    UIView *bottomFill = [self.customToolView viewWithTag:9000];
    bottomFill.frame = CGRectMake(0, CGRectGetHeight(self.customToolView.bounds),
                                  CGRectGetWidth(self.customToolView.bounds),
                                  MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMaxY(self.view.safeAreaLayoutGuide.layoutFrame)));
    
    // Keep buttons out of side insets (landscape notch, iPhone Duo's outer-display camera column).
    CGFloat leadingInset = 0;
    CGFloat screenWidth = CGRectGetWidth(self.customToolView.bounds);
    // Desired fixed width for button and minimal horizontal spacing
    CGFloat desiredButtonWidth = 80.0;
    CGFloat minSpacing = 10.0; // minimal spacing to the edges and between buttons

    // First row configuration
    NSInteger firstRowButtonCount = 5;
    // Calculate button width dynamically to guarantee minimal spacing
    CGFloat maxButtonsTotalWidth = screenWidth - minSpacing * (firstRowButtonCount + 1);
    CGFloat buttonWidth = desiredButtonWidth;
    if (firstRowButtonCount * desiredButtonWidth > maxButtonsTotalWidth) {
        // Need to shrink button width so that everything fits with min spacing
        buttonWidth = maxButtonsTotalWidth / firstRowButtonCount;
    }
    // Re-compute actual spacing with the (possibly) updated buttonWidth
    CGFloat firstRowSpacing = (screenWidth - buttonWidth * firstRowButtonCount) / (firstRowButtonCount + 1);
    firstRowSpacing = MAX(firstRowSpacing, minSpacing);

    // Layout parameters
    CGFloat buttonHeight = kCustomTabToolButtonHeight;
    CGFloat topPadding = kCustomTabToolWithTopPadding;
    CGFloat verticalSpacing = 25.0;
    CGFloat firstRowTop = topPadding;
    CGFloat secondRowTop = topPadding + buttonHeight + verticalSpacing;

    // Layout each sub button view
    for (UIView *subview in self.customToolView.subviews) {
        NSInteger tag = subview.tag;
        if (tag >= 1001 && tag < 1001 + firstRowButtonCount) {
            NSInteger index = tag - 1001;
            CGFloat x = leadingInset + firstRowSpacing + index * (buttonWidth + firstRowSpacing);
            subview.frame = CGRectMake(x, firstRowTop, buttonWidth, buttonHeight);
        } else if (tag >= 1001 + firstRowButtonCount && tag < 1001 + firstRowButtonCount + 3) {
            // Second row (3 buttons: Move, Delete, Profile) aligned to the first three columns of first row
            NSInteger index = tag - (1001 + firstRowButtonCount); // 0, 1, or 2
            CGFloat x = leadingInset + firstRowSpacing + index * (buttonWidth + firstRowSpacing);
            subview.frame = CGRectMake(x, secondRowTop, buttonWidth, buttonHeight);
        }
        // ---- Relayout internal icon & label to match new button width ----
        UIImageView *iconView = [subview viewWithTag:100];
        UILabel *titleLabel = [subview viewWithTag:101];
        if (iconView && titleLabel) {
            CGFloat iconSide = 24.0;
            iconView.frame = CGRectMake((buttonWidth - iconSide) / 2.0, 0, iconSide, iconSide);
            titleLabel.frame = CGRectMake(0, 28, buttonWidth, 14);
        }
    }
}

// Update createTabButtonWithTitle to enable dynamic font sizing by setting adjustsFontSizeToFitWidth
- (UIView *)createTabButtonWithTitle:(NSString *)title iconName:(NSString *)iconName width:(CGFloat)width tag:(NSInteger)tag {
    UIView *buttonView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 40)];
    buttonView.tag = tag;
    buttonView.isAccessibilityElement = YES;
    buttonView.accessibilityLabel = title;
    buttonView.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitNotEnabled;
    
    // Icon image view
    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake((width - 24) / 2, 0, 24, 24)];
    iconView.tag = 100;
    UIImage *icon = [UIImage imageNamed:iconName];
    if (icon) {
        UIImage *grayIcon = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        iconView.image = grayIcon;
        iconView.tintColor = BOTTOM_TOOL_VIEW_DISABLE_COLOR;
    }
    [buttonView addSubview:iconView];
    
    // Title label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 28, width, 14)];
    titleLabel.tag = 101;
    titleLabel.text = title;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont systemFontOfSize:12];
    titleLabel.textColor = BOTTOM_TOOL_VIEW_DISABLE_COLOR;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.7;
    [buttonView addSubview:titleLabel];
    
    // Gesture recognizer
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleToolButtonTap:)];
    [buttonView addGestureRecognizer:tapGesture];
    
    // Disabled by default
    buttonView.userInteractionEnabled = NO;
    
    return buttonView;
}

// Method to update button state
- (void)updateToolButton:(NSInteger)tag enabled:(BOOL)enabled {
    UIView *buttonView = [self.customToolView viewWithTag:tag];
    if (!buttonView) return;
    buttonView.accessibilityTraits = UIAccessibilityTraitButton | (enabled ? 0 : UIAccessibilityTraitNotEnabled);
    
    UIImageView *iconView = [buttonView viewWithTag:100];
    UILabel *titleLabel = [buttonView viewWithTag:101];
    
    UIColor *color = enabled ? [SeafTheme galleryOperationText] : BOTTOM_TOOL_VIEW_DISABLE_COLOR;
    
    iconView.tintColor = color;
    titleLabel.textColor = color;
    buttonView.userInteractionEnabled = enabled;
}

// Define button tag constants
typedef NS_ENUM(NSInteger, ToolButtonTag) {
    ToolButtonDownload = 1001,
    ToolButtonRename = 1002,
    ToolButtonStar = 1003,
    ToolButtonCopy = 1004,
    ToolButtonShare = 1005,
    ToolButtonMove = 1006,
    ToolButtonDelete = 1007,
    ToolButtonProfile = 1008
};

// Handle button tap events
- (void)handleToolButtonTap:(UITapGestureRecognizer *)gesture {
    UIView *buttonView = gesture.view;
    
    // Get required info and save selected items
    NSArray *selectedIndexPaths = [self selectedEntryIndexPaths];
    NSMutableArray *selectedItems = [NSMutableArray new];
    for (NSIndexPath *indexPath in selectedIndexPaths) {
        id item = [self getDentrybyIndexPath:indexPath tableView:self.tableView];
        if (item) {
            [selectedItems addObject:item];
        }
    }
    
    // Return if no items selected
    if (selectedItems.count == 0) return;
    
    // Execute action based on button type
    switch (buttonView.tag) {
        case ToolButtonShare: {
            NSMutableArray *titles = [NSMutableArray array];

            // Show "Share File" as disabled if a directory is selected
            BOOL containsDirectory = NO;
            for (id item in selectedItems) {
                if ([item isKindOfClass:[SeafDir class]]) {
                    containsDirectory = YES;
                    break;
                }
            }
            if (containsDirectory) {
                NSString *disabledTitle = [@"DISABLED:" stringByAppendingString:NSLocalizedString(@"Share file", @"Seafile")];
                [titles addObject:disabledTitle];
            } else {
                [titles addObject:NSLocalizedString(@"Share file", @"Seafile")];
            }
            
            // Only show "Copy share link to clipboard" for a single item, otherwise show it as disabled.
            if (selectedItems.count == 1) {
                [titles addObject:NSLocalizedString(@"Copy share link to clipboard", @"Seafile")];
            } else if (selectedItems.count > 1) {
                NSString *disabledTitle = [@"DISABLED:" stringByAppendingString:NSLocalizedString(@"Copy share link to clipboard", @"Seafile")];
                [titles addObject:disabledTitle];
            }

            SeafActionSheet *actionSheet = [SeafActionSheet actionSheetWithTitles:titles];
            actionSheet.targetVC = self;
            [actionSheet setButtonPressedBlock:^(SeafActionSheet *sheet, NSIndexPath *indexPath){
                [sheet dismissAnimated:YES];
                
                NSString *selectedTitle = titles[indexPath.row];
                
                if ([selectedTitle isEqualToString:NSLocalizedString(@"Share file", @"Seafile")]) {
                    // This is the original logic for sharing files
                    self.state = STATE_EXPORT;
                    [self editDone:nil]; // Exit edit mode here
                    @weakify(self);
                    [self downloadEntries:selectedItems completion:^(NSArray *array, NSString *errorStr) {
                        @strongify(self);
                        self.state = STATE_INIT;
                        @weakify(self);
                        dispatch_async(dispatch_get_main_queue(), ^{
                            @strongify(self);
                            if (errorStr) {
                                [SVProgressHUD showErrorWithStatus:errorStr];
                            } else {
                                [SeafActionsManager exportByActivityView:array item:buttonView targerVC:self];
                            }
                        });
                    }];
                } else if ([selectedTitle isEqualToString:NSLocalizedString(@"Copy share link to clipboard", @"Seafile")]) {
                    [self editDone:nil];
                    // This logic now applies to a single file OR a single directory
                    SeafBase *selectedItem = selectedItems.firstObject;
                    self.state = STATE_SHARE_LINK;
                    if (!selectedItem.shareLink) {
                        [SVProgressHUD showWithStatus:NSLocalizedString(@"Generate share link ...", @"Seafile")];
                        [selectedItem generateShareLink:self];
                    } else {
                        [self generateSharelink:selectedItem WithResult:YES];
                    }
                }
            }];

            [actionSheet showFromView:buttonView];
            break;
        }
        case ToolButtonDownload: {
            // 新逻辑：展开选中项 -> 分类 -> 执行三态分支
            [self editDone:nil]; // Exit editing first to maintain expected interaction
            [self expandAndHandleDownloadForSelectedItems:selectedItems sourceView:buttonView];
            break;
        }
        case ToolButtonRename: {
            if (selectedItems.count == 1) {
                SeafBase *entry = selectedItems.firstObject;
                [self editDone:nil]; // Exit edit mode here
                [self renameEntry:entry];
            }
            break;
        }
        case ToolButtonStar: {
            [self editDone:nil]; // Exit edit mode here
            for (id item in selectedItems) {
                if ([item isKindOfClass:[SeafFile class]]) {
                    SeafFile *file = (SeafFile *)item;
                    [SVProgressHUD showWithStatus:NSLocalizedString(@"Setting star...", @"Seafile")];
                    [file setStarred:YES withBlock:^(BOOL success) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (success) {
                                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Successfully starred", @"Seafile")];
                            } else {
                                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to star", @"Seafile")];
                            }
                        });
                    }];
                } else if ([item isKindOfClass:[SeafDir class]]) {
                    SeafDir *dir = (SeafDir *)item;
                    [SVProgressHUD showWithStatus:NSLocalizedString(@"Setting star...", @"Seafile")];
                    [dir setStarred:YES withBlock:^(BOOL success) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (success) {
                                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Successfully starred", @"Seafile")];
                            } else {
                                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to star", @"Seafile")];
                            }
                        });
                    }];
                }
            }
            break;
        }
        case ToolButtonCopy: {
            NSMutableArray *names = [NSMutableArray new];
            for (SeafBase *item in selectedItems) {
                [names addObject:item.name ?: @""];
            }
            self.pendingEntriesForOperation = [names copy];
            self.state = STATE_COPY;
            [self popupDirChooseView:nil];
            break;
        }
        case ToolButtonMove: {
            NSMutableArray *names = [NSMutableArray new];
            for (SeafBase *item in selectedItems) {
                [names addObject:item.name ?: @""];
            }
            self.pendingEntriesForOperation = [names copy];
            self.state = STATE_MOVE;
            [self popupDirChooseView:nil];
            break;
        }
        case ToolButtonProfile: {
            if (selectedItems.count == 1) {
                id item = selectedItems.firstObject;
                if ([item isKindOfClass:[SeafFile class]]) {
                    [self editDone:nil];
                    [self showFileProfileSheetForFile:(SeafFile *)item];
                }
            }
            break;
        }
        case ToolButtonDelete: {
            NSMutableArray *entries = [[NSMutableArray alloc] init];
            for (SeafBase *item in selectedItems) {
                [entries addObject:item.name];
            }
            [self alertWithTitle:nil message:NSLocalizedString(@"Are you sure you want to delete these items?", @"Seafile") yes:^{
                 self.state = STATE_DELETE;
                 _directory.delegate = self;
                 [self editDone:nil]; // Exit edit mode after confirmation
                 [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting files ...", @"Seafile")];
                 [[SeafFileOperationManager sharedManager]
                  deleteEntries:entries
                  inDir:self.directory
                  completion:^(BOOL success, NSError * _Nullable error) {
                     if (success) {
                         [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Delete success", @"Seafile")];
                         [self.directory loadContent:YES];
                     } else {
                         NSString *errMsg = error.localizedDescription ?: NSLocalizedString(@"Failed to delete files", @"Seafile");
                         [SVProgressHUD showErrorWithStatus:errMsg];
                     }
                 }];
            } no:^{
                
            }];
            break;
        }
    }
}

// Method to update tool buttons state
- (void)updateToolButtonsState {
    NSArray *selectedIndexPaths = [self selectedEntryIndexPaths];
    // Get selected items
    NSMutableArray *selectedItems = [NSMutableArray new];
    for (NSIndexPath *indexPath in selectedIndexPaths) {
        id item = [self getDentrybyIndexPath:indexPath tableView:self.tableView];
        if (item) {
            [selectedItems addObject:item];
        }
    }
    if (selectedItems.count == 0) {
        [self setAllToolButtonEnable:NO];
    } else if (selectedItems.count == 1) {
        _selectedindex = selectedIndexPaths.firstObject;
        [self setAllToolButtonEnable:YES];
        // Profile button: only enabled for SeafFile (not dir, not upload, not repo)
        id singleItem = selectedItems.firstObject;
        BOOL isFile = [singleItem isKindOfClass:[SeafFile class]];
        [self updateToolButton:ToolButtonProfile enabled:isFile];
    } else {
        //redownload
        [self updateToolButton:ToolButtonDownload enabled:YES];
        
        // rename
        [self updateToolButton:ToolButtonRename enabled:NO];
        
        //star
        [self updateToolButton:ToolButtonStar enabled:YES];
        
        //copy
        [self updateToolButton:ToolButtonCopy enabled:YES];
                
        //move
        [self updateToolButton:ToolButtonMove enabled:YES];
        
        //delete
        [self updateToolButton:ToolButtonDelete enabled:YES];
        
        //profile: disabled for multi-select
        [self updateToolButton:ToolButtonProfile enabled:NO];
        
        //share
        [self updateExportBarItem:selectedItems];
    }
    
    if ([self.directory isKindOfClass:[SeafRepos class]]) {
        [self updateSeafBaseToolButton];
    }
}

- (void)updateSeafBaseToolButton {
    //copy
    [self updateToolButton:ToolButtonCopy enabled:NO];

    //move
    [self updateToolButton:ToolButtonMove enabled:NO];
    
    //delete
    [self updateToolButton:ToolButtonDelete enabled:NO];
}

- (void)setAllToolButtonEnable:(BOOL)enable{
    for (NSInteger tag = ToolButtonDownload; tag <= ToolButtonProfile; tag++) {
        [self updateToolButton:tag enabled:enable];
    }
}

// Adjust content insets to avoid custom toolbar overlap.
// Apply to both scroll views so an async edit-exit after a view-mode toggle
// cannot leave bottom inset on the scroll view that is no longer current.
// The list table extends through the bottom safe area and keeps automatic
// adjustment, so that system inset is already in adjustedContentInset.
// Subtract it; otherwise the toolbar padding stacks on the home indicator.
// The grid is inside the safe area with adjustment disabled, so this
// subtraction is zero and its inset stays the toolbar height.
- (void)adjustContentInsetForCustomToolbar:(BOOL)showing {
    NSArray<UIScrollView *> *scrollViews = @[self.tableView, self.collectionView];
    for (UIScrollView *scrollView in scrollViews) {
        if (!scrollView) continue;
        CGFloat systemBottom = scrollView.adjustedContentInset.bottom - scrollView.contentInset.bottom;
        CGFloat overlap = 0;
        if (showing && self.customToolView.superview) {
            CGRect panel = [scrollView convertRect:self.customToolView.bounds fromView:self.customToolView];
            CGRect intersection = CGRectIntersection(scrollView.bounds, panel);
            if (!CGRectIsNull(intersection)) {
                // Reserve everything below the panel's top, including the system
                // bottom area; automatic adjustment is subtracted exactly once.
                overlap = CGRectGetMaxY(scrollView.bounds) - CGRectGetMinY(intersection);
            }
        }
        CGFloat bottom = MAX(0, overlap - systemBottom);
        UIEdgeInsets contentInset = scrollView.contentInset;
        if (fabs(contentInset.bottom - bottom) < 0.5) continue;
        contentInset.bottom = bottom;
        scrollView.contentInset = contentInset;
        scrollView.scrollIndicatorInsets = contentInset;
    }
}

// Add new method to handle long press
- (void)handleLongPress:(UILongPressGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        CGPoint p = [gestureRecognizer locationInView:self.tableView];
        NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:p];
        [self beginEditingAtIndexPath:indexPath];
    }
}

- (void)handleGridLongPress:(UILongPressGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        CGPoint p = [gestureRecognizer locationInView:self.collectionView];
        NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:p];
        [self beginEditingAtIndexPath:indexPath];
    }
}

- (void)beginEditingAtIndexPath:(NSIndexPath *)indexPath {
    if (!indexPath) return;
    if (!self.editing) {
        [self editStart:nil];
        NSObject *entry = [self getDentrybyIndexPath:indexPath tableView:nil];
        if (![entry isKindOfClass:[SeafUploadFile class]]) {
            if ([self isGridModeActive]) {
                [self.collectionView selectItemAtIndexPath:indexPath animated:YES scrollPosition:UICollectionViewScrollPositionNone];
                SeafGridCell *cell = (SeafGridCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
                cell.isUserEditing = YES;
                [cell updateCheckboxForSelected:YES];
            } else {
                [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
            }
            _selectedindex = indexPath;
            [self noneSelected:NO];
            [self updateToolButtonsState];
        }
    }
}

- (void)backButtonTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.navigationController.interactivePopGestureRecognizer) {
        // If in editing mode, prevent pop gesture
        if (self.editing) {
            return NO;
        }
        return self.navigationController.viewControllers.count > 1;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.navigationController.interactivePopGestureRecognizer) {
        return YES;
    }
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;  // Return NO to avoid gesture conflict
}

#pragma mark - Search Action

/// Whether the system shows its vertical bar (the iPhone Duo side rail) for this view.
- (BOOL)hasVerticalBar {
    if (@available(iOS 27.1, *)) {
        return self.traitCollection.verticalBarEdge != UIVerticalBarEdgeUnspecified;
    }
    return NO;
}

/// With a vertical bar, the search back control belongs in the rail rather than in the
/// search bar, so keep the navigation bar and swap its items for a single back item.
- (void)applySearchNavigationChrome {
    self.searchUsesVerticalBar = [self hasVerticalBar];
    UISearchBar *bar = self.searchController.searchBar;
    if (!self.searchUsesVerticalBar) {
        self.searchController.hidesNavigationBarDuringPresentation = !IsIpad();
        if ([self usesGlassSidebarChrome]) {
            UIColor *backgroundColor = [self isRepoRootDirectory] ? [SeafTheme primaryBackgroundColor] : bar.backgroundColor;
            [SeafNavigationBarStyler applyOpaqueAppearanceToNavigationItem:self.navigationItem
                                                          backgroundColor:backgroundColor];

            // The bar's search button has become the field below it, as system search
            // buttons do; it comes back in -dismissSearchBar.
            self.searchItem.hidden = YES;
            // The system Close button at the bar's leading edge (where navigation controls
            // go) rather than the custom chevron inside the field. The search bar shows no
            // Cancel control of its own here on iPad, even with showsCancelButton set.
            self.searchBarBackButton.hidden = YES;
            bar.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 12, 0, 12);
            if (!self.searchCloseItem) {
                self.searchCloseItem = [SeafNavigationBarStyler createCloseButtonWithTarget:self
                                                                                     action:@selector(customSearchDismissAction:)];
                self.searchCloseItem.accessibilityIdentifier = @"search_close_button";
            }
            self.navigationItem.hidesBackButton = YES;
            self.navigationItem.leftBarButtonItem = self.searchCloseItem;
        } else {
            self.searchBarBackButton.hidden = NO;
            bar.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 42, 0, 0);
        }
        if ([self usesLargeSidebarTitle]) {
            // As in the system apps, the large title steps aside while searching. Once the
            // results show, UIKit empties the large title row but keeps its height, which
            // would leave a blank band above the search bar. Settled before the bar is
            // placed, so it is lifted from its final position.
            self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
            [self.navigationController.view layoutIfNeeded];
        }
        return;
    }
    self.searchController.hidesNavigationBarDuringPresentation = NO;
    self.searchBarBackButton.hidden = YES;
    bar.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 12, 0, 0);
    UIBarButtonItem *back = [SeafNavigationBarStyler createBackButtonWithTarget:self
                                                                         action:@selector(customSearchDismissAction:)
                                                                          color:[SeafTheme glassBarIconColor]];
    back.accessibilityIdentifier = @"search_back_button";
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItems = @[back];
    self.navigationItem.rightBarButtonItems = nil;
}

/// With a vertical bar the search bar sits in the navigation bar, so UIKit looks for the
/// presenting controller from the navigation controller and takes the first child that defines
/// a presentation context. Every list page defines one (see -searchController), so below the root
/// the hidden root page was picked and the search field refused focus. The pages underneath give
/// theirs up while this page's search is up; only the ones changed here are restored later.
- (void)claimSearchPresentationContext {
    [self releaseSearchPresentationContext];
    NSHashTable<UIViewController *> *yielded = [NSHashTable weakObjectsHashTable];
    for (UIViewController *vc in self.navigationController.viewControllers) {
        if (vc == self || !vc.definesPresentationContext) continue;
        vc.definesPresentationContext = NO;
        [yielded addObject:vc];
    }
    self.definesPresentationContext = YES;
    self.searchContextYieldedControllers = yielded;
}

- (void)releaseSearchPresentationContext {
    for (UIViewController *vc in self.searchContextYieldedControllers) {
        vc.definesPresentationContext = YES;
    }
    self.searchContextYieldedControllers = nil;
}

- (void)restoreNavigationChromeAfterSearch {
    if (!self.searchUsesVerticalBar) return;
    self.searchUsesVerticalBar = NO;
    self.navigationItem.leftBarButtonItems = nil;
    self.navigationItem.rightBarButtonItems = self.rightItems;
    [self applyLibraryNavigationChrome];
}

- (void)searchAction:(id)sender {
    [self applySearchNavigationChrome];
    if (self.searchUsesVerticalBar) {
        [self claimSearchPresentationContext];
    }
    [self presentSearchBar];
    
    // Ensure status bar style is set correctly before activating search
    // Force status bar to update appearance
    [self setNeedsStatusBarAppearanceUpdate];
    
    // Activate search bar. A bar just moved into the title view joins the window on the
    // next layout pass, so focus it after the current run loop turn.
    if (self.searchUsesVerticalBar) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.searchController.searchBar becomeFirstResponder];
        });
    } else {
        [self.searchController.searchBar becomeFirstResponder];
    }
}

#pragma mark - Helper Methods

// Helper method to create a solid color image for backgrounds
- (UIImage *)imageWithColor:(UIColor *)color {
    CGRect rect = CGRectMake(0, 0, 1, 1);
    UIGraphicsBeginImageContext(rect.size);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGContextSetFillColorWithColor(context, [color CGColor]);
    CGContextFillRect(context, rect);
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Popped while a vertical bar search is up: hand the presentation context back.
    if (self.isMovingFromParentViewController) {
        [self releaseSearchPresentationContext];
        [self updateTabBarForSearch:NO];
    }
    // On iPad, the master list (SeafFileViewController) can be hidden when the user focuses on the detail view.
    // If we are in editing mode (custom bottom toolbar is visible), make sure we exit editing mode so the toolbar
    // is dismissed together with the view.
    if (IsIpad() && self.editing) {
        // This will internally call `dismissCustomTabTool:` and restore insets.
        [self editDone:nil];
    }
}

#pragma mark - Expand, Classify and Handle Download/Export

// Removed: collectFilesRecursivelyFromItems (moved into SeafSelectionActionCoordinator)

// Forwarded handlers to coordinator
- (void)expandAndHandleDownloadForSelectedItems:(NSArray<SeafBase *> *)selectedItems
                                     sourceView:(UIView *)sourceView
{
    [self.selectionCoordinator handleSelectedItems:selectedItems sourceView:sourceView];
}

- (void)updateAggregateProgressForEntry:(SeafBase *)entry progress:(float)progress
{
    [self.selectionCoordinator updateAggregateProgressForEntry:entry progress:progress];
}

#pragma mark - SeafGalleryHeroProvider

- (UIView *)gallerySourceViewForItem:(id<SeafPreView>)item {
    id cell = [self getEntryCell:item indexPath:NULL];
    if ([cell isKindOfClass:[SeafGridCell class]]) {
        return [(SeafGridCell *)cell thumbnailView];
    }
    if ([cell isKindOfClass:[SeafCell class]]) {
        return ((SeafCell *)cell).imageView;
    }
    return nil;
}

- (CGRect)gallerySourceFrameInWindowForItem:(id<SeafPreView>)item {
    UIView *source = [self gallerySourceViewForItem:item];
    if (!source) return CGRectZero;
    return [source convertRect:source.bounds toView:nil];
}

- (void)galleryWillDismissToItem:(id<SeafPreView>)item {
    NSUInteger index = [self indexOfEntry:item];
    if (index == NSNotFound || index >= self.allItems.count) return;
    NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
    @try {
        if ([self isGridModeActive]) {
            if (![[self.collectionView indexPathsForVisibleItems] containsObject:path]) {
                [self.collectionView scrollToItemAtIndexPath:path
                                              atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                                                      animated:NO];
            }
            [self.collectionView layoutIfNeeded];
        } else {
            if (![[self.tableView indexPathsForVisibleRows] containsObject:path]) {
                [self.tableView scrollToRowAtIndexPath:path
                                      atScrollPosition:UITableViewScrollPositionNone
                                              animated:NO];
            }
            [self.tableView layoutIfNeeded];
        }
    } @catch (NSException *exception) {
        Warning("scroll to item failed: %@", exception);
    }
}

- (void)galleryDidDismissToItem:(id<SeafPreView>)item {
    // The gallery uses `UIModalPresentationOverFullScreen` so our own
    // `viewWillAppear:` does not fire on dismiss; refresh the visible
    // cells' download indicators here so files downloaded inside the
    // gallery (or whose download state changed) reflect immediately.
    [self refreshDownloadStatus];
}

// Navigates to a repository and path for deep links (SeafAppDelegate checkOpenLink:).
// Called on the root file view controller and again on every pushed child once its
// directory has loaded. Returns YES to keep descending and NO when navigation is
// finished or the target does not exist.
- (BOOL)goTo:(NSString *)targetRepo path:(NSString *)path
{
    if (!self.isVisible)
        return YES;
    BOOL isRepoList = [self.directory isKindOfClass:[SeafRepos class]];
    // A folder page waits for its listing. The library list is searched even
    // when empty: an account whose first library was just shared has no
    // listing to wait for, only a lookup to make.
    if (!isRepoList && ![_directory hasCache])
        return YES;
    Debug("repo: %@, path: %@, current: %@", targetRepo, path, _directory.path);
    if (isRepoList) {
        NSArray *repoGroups = ((SeafRepos *)_directory).repoGroups;
        for (NSUInteger i = 0; i < repoGroups.count; ++i) {
            NSArray *repos = repoGroups[i];
            for (NSUInteger j = 0; j < repos.count; ++j) {
                SeafRepo *r = repos[j];
                if ([r.repoId isEqualToString:targetRepo]) {
                    self.gotoRefreshRepoId = nil;
                    self.gotoRefreshState = SeafLinkRefreshNone;
                    if ([self.gotoPasswordRepoId isEqualToString:targetRepo]) {
                        // The prompt for this link is up, or between two retries
                        // (validation alert, password check / wrong-password HUD):
                        // the link stays pending and belongs to it.
                        if ([self.presentedViewController isKindOfClass:[UIAlertController class]] || [SVProgressHUD isVisible])
                            return YES;
                        // It never came up or went away without an answer.
                        self.gotoPasswordRepoId = nil;
                        if (self.state == STATE_PASSWORD)
                            self.state = STATE_INIT;
                    }
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:j inSection:i];
                    [self selectRowForLinkAtIndexPath:indexPath];
                    if (self.navigationController.topViewController == self && !self.tableView.editing
                        && [r passwordRequiredWithSyncRefresh]) {
                        // Something else is on screen: the prompt could not be
                        // shown, so leave the link for the next check.
                        if (self.presentedViewController)
                            return YES;
                        _selectedindex = indexPath;
                        _curEntry = r;
                        [self popupSetRepoPasswordForLink:r];
                        return YES;
                    }
                    [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
                    return YES;
                }
            }
        }
        // The list may simply be older than the link (a library shared a
        // moment ago): ask the server once before giving up. Only a load sent
        // after the link counts as that answer.
        if (![self.gotoRefreshRepoId isEqualToString:targetRepo]) {
            self.gotoRefreshRepoId = targetRepo;
            self.gotoRefreshState = SeafLinkRefreshNone;
        }
        switch (self.gotoRefreshState) {
            case SeafLinkRefreshNone:
            case SeafLinkRefreshAwaitingEarlierLoad:
                if (_directory.state == SEAF_DENTRY_LOADING) {
                    // A new load is skipped while one runs. Look again when
                    // this one answers, then send the link's own if needed.
                    Debug("Repo %@ not in the list, waiting for the load in flight.", targetRepo);
                    self.gotoRefreshState = SeafLinkRefreshAwaitingEarlierLoad;
                    return YES;
                }
                Debug("Repo %@ not in the list, refreshing.", targetRepo);
                self.gotoRefreshState = SeafLinkRefreshRequested;
                [self loadDataFromServerAndRefresh];
                return YES;
            case SeafLinkRefreshRequested:
                return YES;
            case SeafLinkRefreshFinished:
                break;
        }
        Debug("Repo %@ not found.", targetRepo);
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to find library", @"Seafile")];
        return NO;
    }

    // Only the page on top resolves a link: a page already popped, or covered
    // by a newer one, can still report a load it started earlier.
    if (self.navigationController.topViewController != self)
        return YES;
    // A link kept pending on the library list (refresh, password prompt) must
    // not be resolved by a page of another library the user opened meanwhile.
    if (![_directory.repoId isEqualToString:targetRepo]) {
        Debug("Link to repo %@ does not belong to %@, dropping it.", targetRepo, _directory.repoId);
        return NO;
    }
    if ([@"/" isEqualToString:path])
        return NO;
    for (NSUInteger i = 0; i < self.allItems.count; ++i) {
        SeafBase *b = self.allItems[i];
        NSString *p = b.path;
        if ([b isKindOfClass:[SeafDir class]]) {
            p = [p stringByAppendingString:@"/"];
        }
        BOOL found = [p isEqualToString:path];
        if (found || [path hasPrefix:p]) {
            Debug("found=%d, path:%@, p:%@", found, path, p);
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
            [self selectRowForLinkAtIndexPath:indexPath];
            [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
            return !found;
        }
    }
    Debug("file %@/%@ not found", targetRepo, path);
    [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to find %@", @"Seafile"), path]];
    return NO;
}

// Highlights the row a file link passes through. The rows come from the model,
// which the table may not show: a collapsed library group has no rows, and a
// refresh reloads the table asynchronously. UIKit throws when asked to scroll
// to a row it does not have, so open the group first and skip what is missing.
- (void)selectRowForLinkAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self isRepoRootDirectory] && ![self isLibrarySectionExpanded:indexPath.section]) {
        // Show the user where the link went.
        self.expandedSections[@(indexPath.section)] = @YES;
        [self.tableView reloadData];
    }
    if (indexPath.section >= self.tableView.numberOfSections
        || indexPath.row >= [self.tableView numberOfRowsInSection:indexPath.section]) {
        Debug("Link row %@ not in the table yet, not selecting it.", indexPath);
        return;
    }
    [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionMiddle];
}


@end
