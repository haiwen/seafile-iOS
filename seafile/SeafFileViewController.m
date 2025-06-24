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

#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "ExtentedString.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "Debug.h"

#import "QBImagePickerController.h"
#import <WechatOpenSDK/WXApi.h>
#import "SeafWechatHelper.h"
#import "SeafMkLibAlertController.h"
#import "SeafActionsManager.h"
#import "SeafSearchResultViewController.h"
#import "UISearchBar+SeafExtend.h"
#import "UIImage+FileType.h"
#import "SeafUploadOperation.h"
#import "SeafFileOperationManager.h"
#import "SeafUploadFileModel.h"
#import "SeafNavLeftItem.h"
#import "SeafHeaderView.h"
#import "SeafEditNavRightItem.h"
#import "SeafLoadingView.h"
#import "SeafPhotoGalleryViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

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


@interface SeafFileViewController ()<QBImagePickerControllerDelegate, SeafUploadDelegate, SeafDirDelegate, SeafShareDelegate, MFMailComposeViewControllerDelegate, SWTableViewCellDelegate, UIScrollViewAccessibilityDelegate, UIGestureRecognizerDelegate, UIDocumentPickerDelegate>

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
@property (strong) NSArray *rightItems;

@property (retain) SWTableViewCell *selectedCell;// The cell currently selected.
@property (retain) NSIndexPath *selectedindex; // Index path of the currently selected cell.
@property (readonly) NSArray *editToolItems;// Tools available when editing.

@property int state;

@property (retain) NSDateFormatter *formatter;

@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) SeafSearchResultViewController *searchResultController;

@property (strong, retain) NSArray *photos;// Array of photo entries.
@property (strong, retain) NSArray *thumbs;// Array of thumbnail entries.
@property SeafUploadFile *ufile; // The file being uploaded.
@property (nonatomic, strong) NSArray *allItems;// All items in the current directory.

//@property (nonatomic, strong) NSMutableDictionary *expandedSections; // Dictionary to store expanded sections

@property (nonatomic, strong) NSString *originalTitle; // Property to store the original title

@property (nonatomic, strong) UIView *customToolView;
@property (nonatomic, strong) UILabel *customTitleLabel; // Add new property to track title label

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
    
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;

    self.formatter = [[NSDateFormatter alloc] init];
    [self.formatter setDateFormat:@"yyyy-MM-dd HH.mm.ss"];

    self.tableView.estimatedRowHeight = 55;
    
    // Custom navigation bar left button
    if (!self.isEditing) {
        UIBarButtonItem *customBarButton = [[UIBarButtonItem alloc] initWithCustomView:[SeafNavLeftItem navLeftItemWithDirectory:self.directory target:self action:@selector(backButtonTapped)]];
        self.navigationItem.leftBarButtonItem = customBarButton;
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

    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barAppearance = [UINavigationBarAppearance new];
        barAppearance.backgroundColor = [UIColor whiteColor];
        
        self.navigationController.navigationBar.standardAppearance = barAppearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = barAppearance;
        
        self.tableView.sectionHeaderTopPadding = 0;
    }
    
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    [self.navigationController setToolbarHidden:YES animated:NO];

    // Configure view controller for status bar appearance during search
    if (@available(iOS 13.0, *)) {
        // This ensures status bar uses proper background during search
        self.modalPresentationCapturesStatusBarAppearance = YES;
    }

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    self.tableView.refreshControl = refreshControl;
    [self.tableView.refreshControl addTarget:self action:@selector(refreshControlChanged) forControlEvents:UIControlEventValueChanged];
    
    self.view.accessibilityElements = @[refreshControl, self.tableView];
    Debug(@"%@", self.view);
    
    self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
    self.tableView.layoutMargins = UIEdgeInsetsMake(0, 15, 0, 15);
    self.tableView.separatorInset = SEAF_SEPARATOR_INSET;
    
    [self refreshView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Set delegate here to ensure it's properly set each time the view appears
    if (self.navigationController) {
        self.navigationController.interactivePopGestureRecognizer.delegate = self;
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    }
        
    [self checkUploadfiles];
    [self refreshDownloadStatus];
    [self refreshEncryptedThumb];
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

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // Update customToolView frame for orientation change if it exists
        if (self.customToolView) {
            CGRect frame = self.customToolView.frame;
            frame.size.width = size.width;
            frame.origin.y = size.height - frame.size.height;
            self.customToolView.frame = frame;
            
            // Update child subviews to match the new width
            [self relayoutCustomToolViewSubviews];
        }
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
        // Update section header views to adapt to the new width
        NSInteger numberOfSections = [self.tableView numberOfSections];
        for (NSInteger i = 0; i < numberOfSections; i++) {
            UIView *sectionHeader = [self.tableView headerViewForSection:i];
            if (sectionHeader) {
                CGRect sectionFrame = sectionHeader.frame;
                sectionFrame.size.width = size.width;
                sectionHeader.frame = sectionFrame;
                [sectionHeader setNeedsLayout];
                [sectionHeader layoutIfNeeded];
            }
        }
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        
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

- (void)initNavigationItems:(SeafDir *)directory
{
    dispatch_async(dispatch_get_main_queue(), ^{
//        self.photoItem = [self getBarItem:@"plus2" action:@selector(addPhotos:) size:20];
        
        // Create a container view containing icon and label
        UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 180, 44)];
        
        // Add close icon
        UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [closeButton setImage:[UIImage imageNamed:@"close"] forState:UIControlStateNormal];
        closeButton.frame = CGRectMake(0, 10, 24, 24);
        [closeButton addTarget:self action:@selector(editDone:) forControlEvents:UIControlEventTouchUpInside];
        [containerView addSubview:closeButton];
        
        // Add selection count label
        UILabel *countLabel = [[UILabel alloc] initWithFrame:CGRectMake(35, 0, containerView.frame.size.width - 24 - 20, 44)];
        countLabel.font = [UIFont systemFontOfSize:17];
        countLabel.textColor = [UIColor blackColor];
        countLabel.text = NSLocalizedString(@"Select items", @"Seafile");
        [containerView addSubview:countLabel];
        
        UIBarButtonItem *customBarItem = [[UIBarButtonItem alloc] initWithCustomView:containerView];
        self.doneItem = customBarItem;
        self.editItem = [self getBarItemAutoSize:@"more" action:@selector(editSheet:)];
        if (directory.connection.isSearchEnabled) {
            self.searchItem = [self getBarItem:@"fileNav_search" action:@selector(searchAction:) size:18];
            // Add a fixed width space item to increase button spacing
            UIBarButtonItem *spaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
            spaceItem.width = 20; // Set spacing width
            
            self.rightItems = [NSArray arrayWithObjects:self.editItem, spaceItem, self.searchItem, nil];
        } else {
            self.rightItems = [NSArray arrayWithObjects:self.editItem,nil];
        }

        _selectNoneItem = [[SeafEditNavRightItem alloc] initWithTitle:@"Select All" imageName:@"ic_checkbox_unchecked" target:self action:@selector(selectAll:)];
        
        _selectAllItem = [[SeafEditNavRightItem alloc] initWithTitle:@"Select All" imageName:@"ic_checkbox_checked" target:self action:@selector(selectNone:)];
        self.navigationItem.rightBarButtonItems = self.rightItems;
    });
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
    
    // Check if the section is expanded
    NSNumber *expanded = [self.expandedSections objectForKey:@(section)];
    if (expanded && ![expanded boolValue]) {
        // Section is collapsed
        return 0;
    }
    
    // Section is expanded, return the normal count
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
    _curEntry = [self getDentrybyIndexPath:indexPath tableView:tableView];
    Debug("Select %@", [_curEntry valueForKey:@"name"]);
    if (!_curEntry) {
        return [tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
    }
    if ([_curEntry isKindOfClass:[SeafRepo class]] && [(SeafRepo *)_curEntry passwordRequiredWithSyncRefresh]) {
        return [self popupSetRepoPassword:(SeafRepo *)_curEntry];
    }

    if ([_curEntry conformsToProtocol:@protocol(SeafPreView)]) {
        [(id<SeafPreView>)_curEntry setDelegate:self];
        if ([_curEntry isKindOfClass:[SeafFile class]] && ![(SeafFile *)_curEntry hasCache]) {
            SeafCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            [self updateCellDownloadStatus:cell file:(SeafFile *)_curEntry waiting:true];
        }

        id<SeafPreView> item = (id<SeafPreView>)_curEntry;

        if ([self isCurrentFileImage:item]) {
            // 收集所有图片类型的文件
            NSMutableArray *imageFiles = [NSMutableArray array];
            for (id entry in self.allItems) {
                if ([entry conformsToProtocol:@protocol(SeafPreView)] && [(id<SeafPreView>)entry isImageFile]) {
                    [imageFiles addObject:entry];
                }
            }
            
            // 如果没有找到图片文件，使用旧版详情视图
            if (imageFiles.count == 0) {
                Warning("没有找到图片文件");
                [self.detailViewController setPreViewItem:item master:self];
                return;
            }
            
            // 创建并设置照片库视图控制器，使用推荐的初始化方法
            SeafPhotoGalleryViewController *gallery = [[SeafPhotoGalleryViewController alloc] initWithPhotos:imageFiles
                                                                                                currentItem:item
                                                                                                     master:self];
            
            // 将画廊视图控制器包装在导航控制器中，并模态显示
            UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:gallery];
            navController.modalPresentationStyle = UIModalPresentationFullScreen;
            
            // 模态显示导航控制器
            [self presentViewController:navController animated:YES completion:nil];
            return; // 处理图片文件后返回
        } else {
            [self.detailViewController setPreViewItem:item master:self];
        }
        
        if (self.detailViewController.state == PREVIEW_QL_MODAL) {
            [self.detailViewController.qlViewController reloadData];
            if (IsIpad()) {
                [[[SeafAppDelegate topViewController] parentViewController] presentViewController:self.detailViewController.qlViewController animated:true completion:nil];
            } else {
                [self presentViewController:self.detailViewController.qlViewController animated:true completion:nil];
            }
        } else if (!IsIpad()) {
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
    if (![_directory isKindOfClass:[SeafRepos class]]) {
        return 0.01;
    } else {
        return 45;
    }
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
    
    // Get whether the current section is expanded
    NSNumber *expanded = [self.expandedSections objectForKey:@(section)];
    BOOL isExpanded = expanded ? [expanded boolValue] : NO;
    
    // Create SeafHeaderView instance
    SeafHeaderView *header = [[SeafHeaderView alloc] initWithSection:section title:text expanded:isExpanded];
    
    // Set toggle and tap callbacks
    __weak typeof(self) weakSelf = self;
    header.toggleAction = ^(NSInteger section) {
        __strong typeof(weakSelf) self = weakSelf;
        [self toggleSectionAtIndex:section];
    };
    header.tapAction = ^(NSInteger section) {
        __strong typeof(weakSelf) self = weakSelf;
        [self toggleSectionAtIndex:section];
    };
    
    return header;
}

// Method to handle header tap
- (void)headerTapped:(UITapGestureRecognizer *)gesture
{
    NSInteger section = gesture.view.tag;
    [self toggleSectionAtIndex:section];
}

// Method to handle toggle button tap
- (void)toggleSection:(UIButton *)sender
{
    NSInteger section = sender.tag;
    [self toggleSectionAtIndex:section];
}

// Helper method to toggle section
- (void)toggleSectionAtIndex:(NSInteger)section
{
    // Toggle the expanded state
    NSNumber *expanded = [self.expandedSections objectForKey:@(section)];
    BOOL isExpanded = expanded ? [expanded boolValue] : NO;
    BOOL willExpand = !isExpanded;
    
    // Find the toggle button in the section header
    UIView *headerView = [self.tableView headerViewForSection:section];
    UIButton *toggleButton = [headerView.subviews filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [evaluatedObject isKindOfClass:[UIButton class]];
    }]].firstObject;
    
    toggleButton.layer.anchorPoint = CGPointMake(0.5, 0.5);
    
    [UIView animateWithDuration:0.25
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        CGFloat targetRotation = willExpand ? M_PI_2 : 0;
        toggleButton.transform = CGAffineTransformMakeRotation(targetRotation);
    } completion:^(BOOL finished) {
        if (finished) {
            [self.expandedSections setObject:@(willExpand) forKey:@(section)];
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:section]
                        withRowAnimation:UITableViewRowAnimationFade];
        }
    }];
}


#pragma mark - Pull to Refresh

- (void)refreshControlChanged {
    if (!self.tableView.isDragging) {
        [self pullToRefresh];
    }
}

- (void)pullToRefresh {
    [self.tableView reloadData];
    if (self.searchDisplayController.active)
        return;
    if (![self checkNetworkStatus]) {
        [self performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:0.1];
        return;
    }
    
    self.tableView.accessibilityElementsHidden = YES;
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.tableView.refreshControl);
    self.state = STATE_LOADING;
    self.directory.delegate = self;
    [self.directory loadContent:YES];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (self.tableView.refreshControl.isRefreshing) {
        [self pullToRefresh];
    }
}

- (void)doneLoadingTableViewData {
    @weakify(self);
    dispatch_async(dispatch_get_main_queue(), ^{
        @strongify(self);
        [self.tableView.refreshControl endRefreshing];
        self.tableView.accessibilityElementsHidden = NO;
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

- (void)setDirectory:(SeafDir *)directory
{
    [self initNavigationItems:directory];

    _directory = directory;
    _connection = directory.connection;
    self.searchResultController.connection = _connection;
    self.searchResultController.directory = _directory;
    
    // Update custom title
    if (self.customTitleLabel) {
        self.customTitleLabel.text = directory.name;
    }
    
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
    [self refreshView];
    
    UIBarButtonItem *customBarButton = [[UIBarButtonItem alloc] initWithCustomView:[SeafNavLeftItem navLeftItemWithDirectory:directory target:self action:@selector(backButtonTapped)]];
    self.navigationItem.leftBarButtonItem = customBarButton;
    
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
            if (![self.tableView indexPathsForSelectedRows])
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
    UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
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
    if ([self.detailViewController.preViewItem isKindOfClass:[SeafFile class]]) {
        SeafFile *sfile = (SeafFile *)self.detailViewController.preViewItem;
        NSString *parent = [sfile.path stringByDeletingLastPathComponent];
        BOOL deleted = YES;
        if (![_directory isKindOfClass:[SeafRepos class]] && _directory.repoId == sfile.repoId && [parent isEqualToString:_directory.path]) {
            for (SeafBase *entry in self.allItems) {
                if (entry == sfile) {
                    deleted = NO;
                    break;
                }
            }
            if (deleted)
                [self.detailViewController setPreViewItem:nil master:nil];
        }
    }
}

- (void)initSeafPhotos
{
    NSMutableArray *seafPhotos = [NSMutableArray array];
    NSMutableArray *seafThumbs = [NSMutableArray array];

    for (id entry in self.allItems) {
        if ([entry conformsToProtocol:@protocol(SeafPreView)]
            && [(id<SeafPreView>)entry isImageFile]) {
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
        if (![entry isKindOfClass:[SeafUploadFile class]])
            [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
    }
    [self noneSelected:NO];
    [self updateToolButtonsState];
}

- (void)selectNone:(id)sender
{
    long count = self.allItems.count;
    for (int row = 0; row < count; ++row) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
    [self noneSelected:YES];
    [self updateToolButtonsState];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    [super setEditing:editing animated:animated];
    
    if (editing) {
        if (![self checkNetworkStatus]) return;
        // Save original title
        self.originalTitle = self.title;
        
        [self.navigationController.toolbar sizeToFit];
        [self setupCustomTabTool];
        [self noneSelected:YES];
        [self.photoItem setEnabled:NO];
        [self.navigationController setToolbarHidden:YES animated:animated];
        [self adjustContentInsetForCustomToolbar:YES];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
        [self.photoItem setEnabled:YES];
        
        // Restore original title
        self.customTitleLabel.text = self.directory.name;

        // Remove custom toolbar
        [self dismissCustomTabTool:^{
            [self adjustContentInsetForCustomToolbar:NO];
        }];
    }

    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
}

// Method to remove custom toolbar when no longer needed
- (void)dismissCustomTabTool:(void (^)(void))completion {
    if (!self.customToolView) {
        return;
    }
    
    [UIView animateWithDuration:0.2 animations:^{
        CGRect frame = self.customToolView.frame;
        frame.origin.y = self.view.bounds.size.height;
        self.customToolView.frame = frame;
    } completion:^(BOOL finished) {
        [self.customToolView removeFromSuperview];
        self.customToolView = nil;
        
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
    
    // Restore original title
    self.customTitleLabel.text = self.directory.name;
    
    UIBarButtonItem *customBarButton = [[UIBarButtonItem alloc] initWithCustomView:[SeafNavLeftItem navLeftItemWithDirectory:self.directory target:self action:@selector(backButtonTapped)]];
    self.navigationItem.leftBarButtonItem = customBarButton;
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

        case EDITOP_COPY://for selected item
            self.state = STATE_COPY;
            [self popupDirChooseView:nil];
            break;
        case EDITOP_MOVE://for selected item
            self.state = STATE_MOVE;
            [self popupDirChooseView:nil];
            break;
        case EDITOP_DELETE: {//for selected item
            NSArray *idxs = [self.tableView indexPathsForSelectedRows];
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
    if (none) {
        // Get done button container view
        UIView *containerView = (UIView *)self.doneItem.customView;
        UILabel *countLabel = [containerView.subviews.lastObject isKindOfClass:[UILabel class]] ?
                             (UILabel *)containerView.subviews.lastObject : nil;
        countLabel.text = NSLocalizedString(@"Select items", @"Seafile");
        
        self.navigationItem.rightBarButtonItem = _selectNoneItem;
        self.navigationItem.leftBarButtonItem = self.doneItem;
    
    } else {
        NSArray *selectedRows = [self.tableView indexPathsForSelectedRows];
        NSInteger selectedCount = selectedRows.count;
        
        // Update label text on done button
        UIView *containerView = (UIView *)self.doneItem.customView;
        UILabel *countLabel = [containerView.subviews.lastObject isKindOfClass:[UILabel class]] ?
                             (UILabel *)containerView.subviews.lastObject : nil;
        countLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%ld selected", @"Seafile"), (long)selectedCount];
        
        // Calculate total selectable rows
        NSInteger selectableCount = 0;
        for (id entry in self.allItems) {
            if (![entry isKindOfClass:[SeafUploadFile class]]) {
                selectableCount++;
            }
        }
        
        // Decide which button to show based on selection state
        if (selectedCount == selectableCount) {
            self.navigationItem.rightBarButtonItem = _selectAllItem;
        } else {
            self.navigationItem.rightBarButtonItem = _selectNoneItem;
        }
        
        self.navigationItem.leftBarButtonItem = self.doneItem;
        
        // Only update custom title in edit mode
        if (self.editing) {
            self.customTitleLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%ld items selected", @"Seafile"), (long)selectedCount];
        }
    }
}

- (void)updateExportBarItem:(NSArray *)items {
    if (items.count > 9) {
        [self updateToolButton:ToolButtonShare enabled:NO];
        return;
    }
    for (SeafBase * entry in items) {
        if ([entry isKindOfClass:[SeafDir class]] || [entry isKindOfClass:[SeafUploadFile class]]) {
            [self updateToolButton:ToolButtonShare enabled:NO];
            break;
        }
    }
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
        navController.modalPresentationStyle = UIModalPresentationOverCurrentContext;
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
    SeafDirViewController *controller = [[SeafDirViewController alloc] initWithSeafDir:self.connection.rootFolder delegate:self chooseRepo:false];
    if (self.state == STATE_COPY) {
        controller.operationState = OPERATION_STATE_COPY;
    } else if (self.state == STATE_MOVE) {
        controller.operationState = OPERATION_STATE_MOVE;
    }

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    if (IsIpad()) {
        [navController setModalPresentationStyle:UIModalPresentationFormSheet];
    } else {
        [navController setModalPresentationStyle:UIModalPresentationFullScreen];
    }
    navController.navigationBar.tintColor = BAR_COLOR;
    navController.navigationBar.backgroundColor = [UIColor whiteColor];
    [self presentViewController:navController animated:YES completion:nil];
    if (IsIpad()) {
        CGRect frame = navController.view.superview.frame;
        navController.view.superview.frame = CGRectMake(frame.origin.x+frame.size.width/2-320/2, frame.origin.y+frame.size.height/2-500/2, 320, 500);
    }
}


#pragma mark - Photos / Album

- (void)addPhotos:(id)sender {
    if ([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusRestricted || [PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusDenied) {
        return [self alertWithTitle:NSLocalizedString(@"This app does not have access to your photos and videos.", @"Seafile") message:NSLocalizedString(@"You can enable access in Privacy Settings", @"Seafile")];
    }

    QBImagePickerController *imagePickerController = [[QBImagePickerController alloc] init];
    imagePickerController.title = NSLocalizedString(@"Photos", @"Seafile");
    imagePickerController.delegate = self;
    imagePickerController.allowsMultipleSelection = YES;
    imagePickerController.mediaType = QBImagePickerMediaTypeAny;
    if (IsIpad()) {
        imagePickerController.modalPresentationStyle = UIModalPresentationPopover;
        // Use self.editItem if self.photoItem is nil (when called from "more" menu)
        UIBarButtonItem *sourceItem = sender && [sender isKindOfClass:[UIBarButtonItem class]] ? (UIBarButtonItem *)sender : (self.photoItem ? self.photoItem : self.editItem);
        imagePickerController.popoverPresentationController.barButtonItem = sourceItem;
        
        // Fallback to using view controller's view as source view if no bar button item is available
        if (!sourceItem) {
            imagePickerController.popoverPresentationController.sourceView = self.view;
            imagePickerController.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 0, 0);
        }
    } else {
        imagePickerController.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    [self presentViewController:imagePickerController animated:YES completion:nil];
}

- (void)qb_imagePickerControllerDidCancel:(QBImagePickerController *)imagePickerController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)qb_imagePickerController:(QBImagePickerController *)imagePickerController didFinishPickingAssets:(NSArray *)assets {
    if (assets.count == 0) return;
    NSSet *nameSet = [self getExistedNameSet];
    NSMutableArray *identifiers = [[NSMutableArray alloc] init];
    int duplicated = 0;
    BOOL uploadHeicEnabled = self.connection.isUploadHeicEnabled;
    for (PHAsset *asset in assets) {
        SeafPhotoAsset *photoAsset = [[SeafPhotoAsset alloc] initWithAsset:asset isCompress:!uploadHeicEnabled];
        if (photoAsset.localIdentifier) {
            if ([nameSet containsObject:photoAsset.name])
                duplicated++;
            [identifiers addObject:photoAsset.localIdentifier];
        } else
            Warning("Failed to get asset url %@", asset);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
    if (duplicated > 0) {
        NSString *title = duplicated == 1 ? STR_12 : STR_13;
        @weakify(self);
        [self alertWithTitle:title message:nil yes:^{
            @strongify(self);
            [self uploadPickedAssetsIdentifier:identifiers overwrite:true];
        } no:^{
            @strongify(self);
            [self uploadPickedAssetsIdentifier:identifiers overwrite:false];
        }];
    } else
        [self uploadPickedAssetsIdentifier:identifiers overwrite:false];
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
        [nameSet addObject:name];
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

- (void)uploadPickedAssetsIdentifier:(NSArray *)identifiers overwrite:(BOOL)overwrite {
    if (identifiers.count == 0) return;
    
    NSMutableArray *files = [[NSMutableArray alloc] init];
    NSString *uploadDir = [self.connection uniqueUploadDir];
    NSMutableSet *nameSet = overwrite ? [NSMutableSet new] : [self getExistedNameSet];
    BOOL uploadHeicEnabled = self.connection.isUploadHeicEnabled;

    if (overwrite) {
        NSMutableArray *newItems = [self.directory.items mutableCopy];
        NSMutableSet *uploadingFilenames = [NSMutableSet set];
        for (NSString *localIdentifier in identifiers) {
            PHFetchResult *result = [PHAsset fetchAssetsWithLocalIdentifiers:@[localIdentifier] options:nil];
            PHAsset *asset = [result firstObject];
            SeafPhotoAsset *photoAsset = [[SeafPhotoAsset alloc] initWithAsset:asset isCompress:!uploadHeicEnabled];
            if (photoAsset.name) {
                [uploadingFilenames addObject:photoAsset.name];
            }
        }
        NSIndexSet *indexes = [newItems indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            return [obj isKindOfClass:[SeafFile class]] && [uploadingFilenames containsObject:((SeafFile *)obj).name];
        }];
        [newItems removeObjectsAtIndexes:indexes];
        self.directory.items = newItems;
    }
    
    for (NSString *localIdentifier in identifiers) {
        PHFetchResult *result = [PHAsset fetchAssetsWithLocalIdentifiers:@[localIdentifier] options:nil];
        PHAsset *asset = [result firstObject];
        SeafPhotoAsset *photoAsset = [[SeafPhotoAsset alloc] initWithAsset:asset isCompress:!uploadHeicEnabled];
        
        NSString *filename = photoAsset.name;
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

- (BOOL)isCurrentFileImage:(id<SeafPreView>)item
{
    if (![item conformsToProtocol:@protocol(SeafPreView)])
        return NO;
    return item.isImageFile;
}

- (NSArray *)getCurrentFileImagesInTableView:(UITableView *)tableView {
    NSMutableArray *images = [NSMutableArray array];
    
    for (id entry in self.allItems) {
        if ([entry conformsToProtocol:@protocol(SeafPreView)] && [(id<SeafPreView>)entry isImageFile]) {
            [images addObject:entry];
        }
    }
    
    return [images copy];
}

#pragma mark - Share & Export

- (void)exportSelected {
    NSArray *idxs = [self.tableView indexPathsForSelectedRows];
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
    [SVProgressHUD show];
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
    }

}

#pragma mark - File Picker
- (void)selectFileToUpload {
    UIDocumentPickerViewController *documentPicker;
    if (@available(iOS 14.0, *)) {
        UTType *type = [UTType typeWithIdentifier:@"public.item"];
        documentPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[type] asCopy:YES];
    } else {
        documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[(NSString *)kUTTypeItem] inMode:UIDocumentPickerModeImport];
    }
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
        NSIndexSet *indexes = [newItems indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            return [obj isKindOfClass:[SeafFile class]] && [uploadingFilenames containsObject:((SeafFile *)obj).name];
        }];
        [newItems removeObjectsAtIndexes:indexes];
        self.directory.items = newItems;
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

    // Ensure the upload directory exists once before copying
    NSString *uploadDir = [self.connection uniqueUploadDir];
    if (![[NSFileManager defaultManager] fileExistsAtPath:uploadDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:uploadDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
    }

    NSSet *nameSet = [self getExistedNameSet];
    NSMutableArray *filesToUpload = [NSMutableArray new];
    int duplicated = 0;
    int copyFailedCount = 0;

    for (NSURL *url in urls) {
        NSString *fileName = [url lastPathComponent];
        // NSString *uploadDir = [self.connection uniqueUploadDir];
        NSString *destinationPath = [uploadDir stringByAppendingPathComponent:fileName];

        if ([[NSFileManager defaultManager] fileExistsAtPath:destinationPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:destinationPath error:NULL];
        }

        // It's necessary to gain access to the security-scoped resource.
        BOOL accessing = [url startAccessingSecurityScopedResource];
        if (!accessing) {
            Warning("Failed to start accessing security-scoped resource for URL: %@", url);
        }

        __block BOOL success = NO;
        __block NSError *coordinationError = nil;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];

        [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingWithoutChanges error:&coordinationError byAccessor:^(NSURL *newURL) {
            NSError *copyError;
            if ([[NSFileManager defaultManager] copyItemAtURL:newURL toURL:[NSURL fileURLWithPath:destinationPath] error:&copyError]) {
                success = YES;
            } else {
                Warning("Failed to copy file for upload: %@", copyError);
            }
        }];

        if (coordinationError) {
            Warning("File coordination error: %@", coordinationError);
        }

        if (!success) {
            copyFailedCount++;
        } else {
            [filesToUpload addObject:destinationPath];
            if ([nameSet containsObject:fileName]) {
                duplicated++;
            }
        }
        
        // Only stop accessing the resource if it was started
        if (accessing) {
            [url stopAccessingSecurityScopedResource];
        }
    }

    if (copyFailedCount > 0 && copyFailedCount == urls.count) {
        [self alertWithTitle:NSLocalizedString(@"Failed to access selected file(s)", @"Seafile")];
        return;
    }

    if (duplicated > 0) {
        NSString *title = duplicated == 1 ? STR_12 : STR_13;
        @weakify(self);
        [self alertWithTitle:title message:nil yes:^{
            @strongify(self);
            [self startFileUploadsFromPaths:filesToUpload overwrite:true];
        } no:^{
            @strongify(self);
            [self startFileUploadsFromPaths:filesToUpload overwrite:false];
        }];
    } else {
        [self startFileUploadsFromPaths:filesToUpload overwrite:false];
    }
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
            if (cell.cellIndexPath == indexPath) {
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
    cell.imageView.image = sfile.icon;
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
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        if (!cell) return;
        @try {
            [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
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

- (SeafCell *)getEntryCell:(id)entry indexPath:(NSIndexPath **)indexPath
{
    NSUInteger index = [self indexOfEntry:entry];
    if (index == NSNotFound || index >= self.allItems.count) // Add safety check
        return nil;
    @try {
        NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
        if (indexPath) *indexPath = path;
        return (SeafCell *)[[self currentTableView] cellForRowAtIndexPath:path];
    } @catch(NSException *exception) {
        Warning("Something wrong %@", exception);
        return nil;
    }
}

- (void)updateEntryCell:(SeafFile *)entry
{
    @try {
        SeafCell *cell = [self getEntryCell:entry indexPath:nil];
        [self updateCellContent:cell file:entry];
    } @catch(NSException *exception) {
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
    NSArray *selectedIndexPaths = [self.tableView indexPathsForSelectedRows];
    NSMutableArray *entries = [NSMutableArray new];
    for (NSIndexPath *indexPath in selectedIndexPaths) {
        if (indexPath.row >= self.allItems.count) continue;
        SeafBase *item = self.allItems[indexPath.row];
        [entries addObject:item.name];
    }
    
    // Exit edit mode first
    [self editDone:nil];
    
    // Then close the directory picker
    [c.navigationController dismissViewControllerAnimated:YES completion:nil];
    
    if (self.ufile) {
        return [self uploadFile:self.ufile toDir:dstDir];
    }

    _directory.delegate = self;

    if (self.state == STATE_COPY) {
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Copying files ...", @"Seafile")];
        [[SeafFileOperationManager sharedManager]
            copyEntries:entries
            fromDir:self.directory
            toDir:dstDir
            completion:^(BOOL success, NSError * _Nullable error){}];
    } else if (self.state == STATE_MOVE) {
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Moving files ...", @"Seafile")];
        [[SeafFileOperationManager sharedManager]
            moveEntries:entries
            fromDir:self.directory
            toDir:dstDir
            completion:^(BOOL success, NSError * _Nullable error){}];
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

- (void)download:(SeafBase *)entry progress:(float)progress
{
    if ([entry isKindOfClass:[SeafFile class]]) {
        [self.detailViewController download:entry progress:progress];
        SeafPhoto *photo = [self getSeafPhoto:(id<SeafPreView>)entry];
        [photo setProgress:progress];
        SeafCell *cell = [self getEntryCell:(SeafFile *)entry indexPath:nil];
        [self updateCellDownloadStatus:cell file:(SeafFile *)entry waiting:false];
    }
}

- (void)download:(SeafBase *)entry complete:(BOOL)updated
{
    if (self.state == STATE_COPY) {
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Successfully copied", @"Seafile")];
    } else if (self.state == STATE_MOVE) {
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Successfully moved", @"Seafile")];
    } else if (self.state != STATE_EXPORT) {
        [SVProgressHUD dismiss];
    }
    if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)entry;
        [self updateEntryCell:file];
        if (self.state == STATE_SHARE_SHARE_WECHAT) {
            [self shareToWechat:file];
        } else {
            [self.detailViewController download:file complete:updated];
            SeafPhoto *photo = [self getSeafPhoto:(id<SeafPreView>)entry];
            [photo complete:updated error:nil];
        }
    } else if (entry == _directory) {
        [self dismissLoadingView];
        [self doneLoadingTableViewData];
        if (self.state == STATE_DELETE && !IsIpad()) {
            [self.detailViewController goBack:nil];
        }

        [self dismissLoadingView];
        if (updated) {
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
        if (self.state != STATE_EXPORT) {
            [SVProgressHUD dismiss];
        }
        SeafFile *file = (SeafFile *)entry;
        [self updateEntryCell:file];
        [self.detailViewController download:entry failed:error];
        SeafPhoto *photo = [self getSeafPhoto:file];
        return [photo complete:false error:error];
    }

    NSCAssert([entry isKindOfClass:[SeafDir class]], @"entry must be SeafDir");
    Debug("state=%d %@,%@, %@\n", self.state, entry.path, entry.name, _directory.path);
    if (entry == _directory) {
        [self doneLoadingTableViewData];
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
    SeafCell *cell = [self getEntryCell:file indexPath:&indexPath];
    if (!cell) return;
    if (!completed && res) {
        cell.progressView.hidden = false;
        cell.detailTextLabel.text = nil;
        [cell.progressView setProgress:progress];
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
    [[self currentTableView] selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionMiddle];
}

- (void)refreshDownloadStatus {
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
        if (IsIpad()) {
            _searchController.hidesNavigationBarDuringPresentation = NO; // Keep navigation bar visible
        }
        
        // Set properties to ensure opaque status bar background
        _searchController.searchBar.searchBarStyle = UISearchBarStyleProminent; // Changed to prominent style
        _searchController.obscuresBackgroundDuringPresentation = NO;
        
        // Additional style settings for iOS appearance
        _searchController.searchBar.translucent = YES;  // Make it translucent for the gray appearance

        // Apply a 38px leading margin to the UISearchBar to indent its content (the searchTextField)
        // This makes space for our custom back button (30px width) and its 8px leading offset.
        if (@available(iOS 11.0, *)) {
            _searchController.searchBar.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 42, 0, 0);
        } else {
            // Fallback for older iOS versions if needed, though UISearchController is iOS 8+
            _searchController.searchBar.layoutMargins = UIEdgeInsetsMake(0, 42, 0, 0);
        }
        
        // Configure search bar appearance like system search - Light gray background
        UIColor *lightGrayColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0]; // Light gray
        _searchController.searchBar.barTintColor = lightGrayColor;
        _searchController.searchBar.backgroundColor = lightGrayColor;
        
        // Remove any background images to show the default system appearance
        [_searchController.searchBar setBackgroundImage:nil forBarPosition:UIBarPositionAny barMetrics:UIBarMetricsDefault];
        [_searchController.searchBar setBackgroundImage:nil];
        
        // Set the overall tint color for the search bar elements (custom buttons, cursor etc.)
        _searchController.searchBar.tintColor = BAR_COLOR;
        
        // Set placeholder text style and color
        if (@available(iOS 13.0, *)) {
            UITextField *searchField = _searchController.searchBar.searchTextField;
            searchField.placeholder = NSLocalizedString(@"Search files in this library", @"Seafile");
            searchField.backgroundColor = [UIColor whiteColor]; // Changed to white

            // Add system search icon (magnifying glass) to the left of the text field
            UIImageView *searchIconImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
            searchIconImageView.tintColor = [UIColor secondaryLabelColor]; // Standard system color for icons
            
            // Create a container view for the leftView to provide padding
            CGFloat iconSize = 22.0; // Made icon slightly larger
            CGFloat padding = 0.0;   // Reduced padding further
            UIView *leftViewContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, iconSize + padding * 2, searchField.bounds.size.height)];
            searchIconImageView.frame = CGRectMake(padding, (leftViewContainer.bounds.size.height - iconSize) / 2, iconSize, iconSize);
            searchIconImageView.contentMode = UIViewContentModeScaleAspectFit;
            [leftViewContainer addSubview:searchIconImageView];
            
            searchField.leftView = leftViewContainer;
            searchField.leftViewMode = UITextFieldViewModeAlways;
        } else {
            // For older iOS versions
            _searchController.searchBar.placeholder = NSLocalizedString(@"Search files in this library", @"Seafile");
        }
        
        // Configure custom appearance for search presentation
        if (@available(iOS 15.0, *)) {
            UINavigationBarAppearance *searchBarAppearance = [[UINavigationBarAppearance alloc] init];
            [searchBarAppearance configureWithOpaqueBackground];
            searchBarAppearance.backgroundColor = [UIColor whiteColor]; // Same as navigation bar
            
            // Apply to navigation bar instead of search bar
            self.navigationController.navigationBar.standardAppearance = searchBarAppearance;
            self.navigationController.navigationBar.scrollEdgeAppearance = searchBarAppearance;
            
            // For search bar, we can only set these properties
            if (@available(iOS 13.0, *)) {
                // System default styling will now largely apply to the text field
            }
            _searchController.searchBar.tintColor = BAR_COLOR;
        }
        
        // Hide the Cancel button
        _searchController.searchBar.showsCancelButton = NO;

        [_searchController.searchBar sizeToFit];

        // Get the actual height of the search bar for vertical centering
        CGFloat searchBarHeight = _searchController.searchBar.bounds.size.height;

        // Create and add custom back button on the far left
        UIButton *customBackButton = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImage *backImage = [[UIImage imageNamed:@"arrowLeft_black"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]; // Ensure it's a template image
        [customBackButton setImage:backImage forState:UIControlStateNormal];
        customBackButton.tintColor = BAR_COLOR; // Match SeafNavigationBarStyler default
        
        CGFloat buttonHeight = 44.0;
        CGFloat buttonY = 0;
        if (IsIpad()) {
            buttonY = (searchBarHeight - buttonHeight) / 2.0;
        }
        customBackButton.frame = CGRectMake(12, buttonY, 30, buttonHeight);
        customBackButton.imageEdgeInsets = UIEdgeInsetsMake(12, 0, 12, 10);

        customBackButton.imageView.contentMode = UIViewContentModeScaleAspectFit;

        [customBackButton addTarget:self action:@selector(customSearchDismissAction:) forControlEvents:UIControlEventTouchUpInside];
        [_searchController.searchBar addSubview:customBackButton];
        
        // Listen for notifications to handle search cancellation
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(searchCancelled:)
                                                     name:@"SeafSearchCancelled"
                                                   object:nil];
        
        self.definesPresentationContext = YES;
    }
    return _searchController;
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

    // Immediately hide search bar (tableView.tableHeaderView), similar to searchCancelled logic
    if (![self.directory isKindOfClass:[SeafRepos class]]) {
        self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 10.0)];
    } else {
        self.tableView.tableHeaderView = nil;
    }

    // Restore animation settings, similar to searchCancelled logic (synchronously)
    [UIView setAnimationsEnabled:YES];
    
    if (self.navigationController && self.navigationController.navigationBar) {
        self.navigationController.navigationBar.alpha = 1.0;
    }
    // Table content fade-in
    self.tableView.alpha = 1.0;
}

// Handle search cancellation notification
- (void)searchCancelled:(NSNotification *)notification {
    // Disable animations
    [UIView setAnimationsEnabled:NO];
    
    // Directly set search controller to inactive state
    if (self.searchController.active) {
        self.searchController.active = NO;
    }
    
    // Immediately hide search bar without animation
    if (![self.directory isKindOfClass:[SeafRepos class]]) {
        self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 10.0)];
    } else {
        self.tableView.tableHeaderView = nil;
    }
    // Restore animation settings
    [UIView setAnimationsEnabled:YES];
    
    // Add fade-in effect for table content
    self.tableView.alpha = 0.9;
    
    // Add fade-in animation for navigation bar and table content
    [UIView animateWithDuration:0.3 animations:^{
        // Navigation bar fade-in
        if (self.navigationController && self.navigationController.navigationBar) {
            self.navigationController.navigationBar.alpha = 1.0;
        }
        
        // Table content fade-in
        self.tableView.alpha = 1.0;
    }];
}

- (void)setupCustomTabTool {
    // Remove existing custom view if present
    if (self.customToolView) {
        [self.customToolView removeFromSuperview];
        self.customToolView = nil;
    }
    
    // Calculate custom view size and position
    CGFloat toolHeight = kCustomTabToolTotalHeight;
    
    CGFloat pureHomeIndicator = 0;
    if (@available(iOS 11.0, *)) {
        UIWindow *window = UIApplication.sharedApplication.keyWindow;
           pureHomeIndicator = window.safeAreaInsets.bottom;
    }

    // Apply bottom padding parameters
    CGRect frame = CGRectMake(0,
                             self.view.bounds.size.height - toolHeight - pureHomeIndicator,
                             self.view.bounds.size.width,
                             toolHeight + pureHomeIndicator);
    
    // Create custom view
    UIView *customToolView = [[UIView alloc] initWithFrame:frame];
    customToolView.backgroundColor = [UIColor whiteColor];
    
    // Add top border
    CALayer *topBorder = [CALayer layer];
    topBorder.frame = CGRectMake(0, 0, customToolView.frame.size.width, 0.5);
    topBorder.backgroundColor = [UIColor lightGrayColor].CGColor;
    [customToolView.layer addSublayer:topBorder];
    
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
    
    // Second row buttons - 2 buttons
    NSArray *secondRowTitles = @[
        NSLocalizedString(@"Move", @"Seafile"),
        NSLocalizedString(@"Delete", @"Seafile")
    ];
    
    NSArray *secondRowIcons = @[
        @"action_move",
        @"action_delete"
    ];
    
    // Set button sizes and spacing
    CGFloat screenWidth = customToolView.bounds.size.width;
    
    // Calculate second row position
    CGFloat buttonHeight = kCustomTabToolButtonHeight;
        
    // Set initial position below screen
    CGRect initialFrame = customToolView.frame;
    initialFrame.origin.y = self.view.bounds.size.height;
    customToolView.frame = initialFrame;
    
    // Add to key window to prevent scrolling with tableView
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        NSArray<UIWindowScene *> *scenes = UIApplication.sharedApplication.connectedScenes.allObjects;
        for (UIWindowScene *scene in scenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                keyWindow = scene.windows.firstObject;
                break;
            }
        }
    } else {
        keyWindow = UIApplication.sharedApplication.keyWindow;
    }
    
    [keyWindow addSubview:customToolView];
    
    // Store reference
    self.customToolView = customToolView;
    
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
        UIView *buttonView = [self createTabButtonWithTitle:secondRowTitles[i]
                                                   iconName:secondRowIcons[i]
                                                     width:80.0
                                                      tag:i + 5 + 1001];
        [customToolView addSubview:buttonView];
    }

    [self layoutCustomToolButtons];

    
    // Animate from bottom
    [UIView animateWithDuration:0.2 animations:^{
        self.customToolView.frame = frame;
    }];
}

- (void)layoutCustomToolButtons {
    if (!self.customToolView) return;
    
    CGFloat screenWidth = self.customToolView.bounds.size.width;
    // Fixed button width, button height, top padding and spacing between rows
    CGFloat fixedButtonWidth = 80.0;
    CGFloat buttonHeight = kCustomTabToolButtonHeight;
    CGFloat topPadding = kCustomTabToolWithTopPadding;
    CGFloat verticalSpacing = 25.0;
    
    // First row has 5 buttons, second row has 2 buttons
    NSInteger firstRowButtonCount = 5;
    NSInteger secondRowButtonCount = 2;
    
    // Calculate left and right spacing to ensure even distribution of buttons in the first row
    CGFloat firstRowSpacing = (screenWidth - (fixedButtonWidth * firstRowButtonCount)) / (firstRowButtonCount + 1);
    CGFloat firstRowTopPosition = topPadding;
    CGFloat secondRowTopPosition = topPadding + buttonHeight + verticalSpacing;
    
    // Iterate through customToolView's subviews and layout based on tag values
    for (UIView *subview in self.customToolView.subviews) {
        if (subview.tag >= 1001 && subview.tag < 1001 + firstRowButtonCount) {
            // First row buttons: tags 1001-1005
            NSInteger index = subview.tag - 1001;
            CGFloat xPosition = firstRowSpacing + index * (fixedButtonWidth + firstRowSpacing);
            subview.frame = CGRectMake(xPosition, firstRowTopPosition, fixedButtonWidth, buttonHeight);
        } else if (subview.tag >= 1001 + firstRowButtonCount && subview.tag < 1001 + firstRowButtonCount + secondRowButtonCount) {
            // Second row buttons: tags 1006-1007, arranged according to desiredIndexes (here using @[@0, @1], aligned with first two buttons of first row)
            NSArray *desiredIndexes = @[@0, @1];
            NSInteger index = subview.tag - (1001 + firstRowButtonCount); // 0 or 1
            CGFloat xPosition = firstRowSpacing + ([desiredIndexes[index] integerValue]) * (fixedButtonWidth + firstRowSpacing);
            subview.frame = CGRectMake(xPosition, secondRowTopPosition, fixedButtonWidth, buttonHeight);
        }
    }
}
// Create individual button view
- (UIView *)createTabButtonWithTitle:(NSString *)title iconName:(NSString *)iconName width:(CGFloat)width tag:(NSInteger)tag {
    UIView *buttonView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 40)];
    buttonView.tag = tag;
    
    // Create icon - centered at top
    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake((width - 24) / 2, 0, 24, 24)];
    iconView.tag = 100;
    
    UIImage *icon = [UIImage imageNamed:iconName];
    if (icon) {
        UIImage *grayIcon = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        iconView.image = grayIcon;
        iconView.tintColor = BOTTOM_TOOL_VIEW_DISABLE_COLOR;
    }
    
    [buttonView addSubview:iconView];
    
    // Create title label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 28, width, 14)];
    titleLabel.tag = 101;
    titleLabel.text = title;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont systemFontOfSize:12];
    titleLabel.textColor = BOTTOM_TOOL_VIEW_DISABLE_COLOR;
    
    [buttonView addSubview:titleLabel];
    
    // Add tap gesture
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
    
    UIImageView *iconView = [buttonView viewWithTag:100];
    UILabel *titleLabel = [buttonView viewWithTag:101];
    
    UIColor *color = enabled ? BAR_COLOR : BOTTOM_TOOL_VIEW_DISABLE_COLOR;
    
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
    ToolButtonDelete = 1007
};

// Handle button tap events
- (void)handleToolButtonTap:(UITapGestureRecognizer *)gesture {
    UIView *buttonView = gesture.view;
    
    // Get required info and save selected items
    NSArray *selectedIndexPaths = [self.tableView indexPathsForSelectedRows];
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
            [self editDone:nil]; // Exit edit mode here
            for (SeafBase *item in selectedItems) {
                if ([item isKindOfClass:[SeafFile class]]) {
                    SeafFile *file = (SeafFile *)item;
                    Debug("download file: %@, %@", item.repoId, item.path);
                    [SeafDataTaskManager.sharedObject addFileDownloadTask:file];
                } else if ([item isKindOfClass:[SeafDir class]]) {
                    Debug("download dir: %@, %@", item.repoId, item.path);
                    [self performSelector:@selector(downloadDir:) withObject:(SeafDir *)item];
                }
            }
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
            self.state = STATE_COPY;
            [self popupDirChooseView:nil];
            break;
        }
        case ToolButtonMove: {
            self.state = STATE_MOVE;
            [self popupDirChooseView:nil];
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
    NSArray *selectedIndexPaths = [self.tableView indexPathsForSelectedRows];
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
    for (int i = 1;i < 8 ;i++) {
        [self updateToolButton:i + 1000 enabled:enable];
    }
}

// Adjust content insets to avoid custom toolbar overlap
- (void)adjustContentInsetForCustomToolbar:(BOOL)showing {
    if (showing) {
        CGFloat toolbarHeight = self.customToolView.frame.size.height;
        UIEdgeInsets contentInset = self.tableView.contentInset;
        contentInset.bottom = toolbarHeight;
        self.tableView.contentInset = contentInset;
        self.tableView.scrollIndicatorInsets = contentInset;
    } else {
        UIEdgeInsets contentInset = self.tableView.contentInset;
        contentInset.bottom = 0;
        self.tableView.contentInset = contentInset;
        self.tableView.scrollIndicatorInsets = contentInset;
    }
}

// Add new method to handle long press
- (void)handleLongPress:(UILongPressGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        CGPoint p = [gestureRecognizer locationInView:self.tableView];
        NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:p];
        if (indexPath) {
            // Only trigger edit mode if we're not already editing
            if (!self.editing) {
                [self editStart:nil];
                
                // Get the entry at this index path to check if it's an uploadFile
                NSObject *entry = [self getDentrybyIndexPath:indexPath tableView:self.tableView];
                
                // Only select if it's not an upload file
                if (![entry isKindOfClass:[SeafUploadFile class]]) {
                    // Select the cell that was long pressed
                    [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
                    _selectedindex = indexPath;
                    // Update selection status
                    [self noneSelected:NO];
                    [self updateToolButtonsState];
                }
            }
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

- (void)searchAction:(id)sender {
    // Set search bar as table header view
    self.tableView.tableHeaderView = self.searchController.searchBar;
    
    // Ensure status bar style is set correctly before activating search
    if (@available(iOS 13.0, *)) {
        // Force status bar to update appearance
        [self setNeedsStatusBarAppearanceUpdate];
    }
    
    // Activate search bar
    [self.searchController.searchBar becomeFirstResponder];
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

@end
