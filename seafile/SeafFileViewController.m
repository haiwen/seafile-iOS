//
//  SeafFileViewController.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "MWPhotoBrowser.h"

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


@interface SeafFileViewController ()<QBImagePickerControllerDelegate, SeafUploadDelegate, SeafDirDelegate, SeafShareDelegate, MFMailComposeViewControllerDelegate, SWTableViewCellDelegate, MWPhotoBrowserDelegate, UIScrollViewAccessibilityDelegate>

- (UITableViewCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView andIndexPath:(NSIndexPath *)indexPath;
- (UITableViewCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView andIndexPath:(NSIndexPath *)indexPath;
- (UITableViewCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView andIndexPath:(NSIndexPath *)indexPath;

@property (strong) id curEntry; // Currently selected directory entry.
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *loadingView;

@property (strong) UIBarButtonItem *selectAllItem;// Button to select all items in the directory.
@property (strong) UIBarButtonItem *selectNoneItem;
@property (strong) UIBarButtonItem *photoItem; // Button to trigger photo actions.
@property (strong) UIBarButtonItem *doneItem;
@property (strong) UIBarButtonItem *editItem;
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
@property BOOL inPhotoBrowser;// Indicates whether the photo browser is active.

@property SeafUploadFile *ufile; // The file being uploaded.
@property (nonatomic, strong) NSArray *allItems;// All items in the current directory.

@end

@implementation SeafFileViewController

@synthesize connection = _connection;
@synthesize directory = _directory;
@synthesize curEntry = _curEntry;
@synthesize selectAllItem = _selectAllItem, selectNoneItem = _selectNoneItem;
@synthesize selectedindex = _selectedindex;
@synthesize selectedCell = _selectedCell;
@synthesize editToolItems = _editToolItems;


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
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafCell" bundle:nil]
         forCellReuseIdentifier:@"SeafCell"];
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafDirCell" bundle:nil]
         forCellReuseIdentifier:@"SeafDirCell"];
    
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;

    self.formatter = [[NSDateFormatter alloc] init];
    [self.formatter setDateFormat:@"yyyy-MM-dd HH.mm.ss"];

    self.tableView.estimatedRowHeight = 55;
    self.state = STATE_INIT;

    UIView *bView = [[UIView alloc] initWithFrame:self.tableView.frame];
    bView.backgroundColor = [UIColor whiteColor];
    self.tableView.backgroundView = bView;
    
    self.tableView.tableHeaderView = self.searchController.searchBar;
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

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    self.tableView.refreshControl = refreshControl;
    [self.tableView.refreshControl addTarget:self action:@selector(refreshControlChanged) forControlEvents:UIControlEventValueChanged];
    
    self.view.accessibilityElements = @[refreshControl, self.tableView];
    Debug(@"%@", self.view);
    [self refreshView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self checkUploadfiles];
    [self refreshDownloadStatus];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if ([_directory hasCache]) {
        [SeafAppDelegate checkOpenLink:self];
    }
    self.state = STATE_LOADING;
    self.directory.delegate = self;
    [_directory loadContent:true]; // get data from server
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
}


#pragma mark - UI & Navigation Items

- (SeafDetailViewController *)detailViewController
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    return (SeafDetailViewController *)[appdelegate detailViewControllerAtIndex:TABBED_SEAFILE];
}

- (void)initNavigationItems:(SeafDir *)directory
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![directory isKindOfClass:[SeafRepos class]] && directory.editable) {
            self.photoItem = [self getBarItem:@"plus2" action:@selector(addPhotos:) size:20];
            self.doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(editDone:)];
            self.editItem = [self getBarItemAutoSize:@"ellipsis2" action:@selector(editSheet:)];
            UIBarButtonItem *space = [self getSpaceBarItem:16.0];
            self.rightItems = [NSArray arrayWithObjects:self.editItem, space, self.photoItem, nil];

            _selectAllItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Select All", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(selectAll:)];
            _selectNoneItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Select None", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(selectNone:)];
        } else {
            self.editItem = [self getBarItemAutoSize:@"ellipsis2" action:@selector(editSheet:)];
            self.rightItems = [NSArray arrayWithObjects:self.editItem, nil];
        }
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
    if (self.loadingView.isAnimating) {
        CGRect viewBounds = self.view.bounds;
        self.loadingView.center = CGPointMake(CGRectGetMidX(viewBounds), CGRectGetMidY(viewBounds));
    }
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
    NSArray *repos =  [[((SeafRepos *)_directory) repoGroups] objectAtIndex:section];
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
        [self updateExportBarItem];
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
            [self.detailViewController setPreViewPhotos:[self getCurrentFileImagesInTableView:tableView] current:item master:self];
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
            [self updateExportBarItem];
        }
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (![_directory isKindOfClass:[SeafRepos class]]) {
        return 0.01;
    } else {
        return 24;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (![_directory isKindOfClass:[SeafRepos class]])
        return nil;

    NSString *text = nil;
    if (section == 0) {
        text = NSLocalizedString(@"My Own Libraries", @"Seafile");
    } else {
        NSArray *repos =  [[((SeafRepos *)_directory)repoGroups] objectAtIndex:section];
        SeafRepo *repo = (SeafRepo *)[repos objectAtIndex:0];
        if (!repo) {
            text = @"";
        } else if ([repo.type isEqualToString:SHARE_REPO]) {
            text = NSLocalizedString(@"Shared to me", @"Seafile");
        } else if ([repo.type isEqualToString:GROUP_REPO]) {
            if (!repo.groupName || repo.groupName.length == 0) {
                text = NSLocalizedString(@"Shared with groups", @"Seafile");
            } else {
                text = repo.groupName;
            }
        } else {
            if ([repo.owner isKindOfClass:[NSNull class]]) {
                text = @"";
            } else {
                if ([repo.owner isEqualToString:ORG_REPO]) {
                    text = NSLocalizedString(@"Organization", @"Seafile");
                } else {
                    text = repo.owner;
                }
            }
        }
    }
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, tableView.bounds.size.width - 10, 18)];
    label.font = [UIFont systemFontOfSize:12];
    label.text = text;
    label.textColor = [UIColor darkTextColor];
    label.backgroundColor = [UIColor clearColor];
    [headerView setBackgroundColor:[UIColor colorWithRed:246/255.0 green:246/255.0 blue:250/255.0 alpha:1.0]];
    [headerView addSubview:label];
    return headerView;
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

- (void)hideSearchBar:(SeafConnection *)conn
{
    if (conn.isSearchEnabled) {
        self.tableView.tableHeaderView = self.searchController.searchBar;
    } else {
        self.tableView.tableHeaderView = nil;
    }
}

- (void)setDirectory:(SeafDir *)directory
{
    [self hideSearchBar:directory.connection];
    [self initNavigationItems:directory];

    _directory = directory;
    _connection = directory.connection;
    self.searchResultController.connection = _connection;
    self.searchResultController.directory = _directory;
    self.title = directory.name;
    [_directory loadContent:false];
    Debug("repoId:%@, %@, path:%@, loading ... cached:%d %@, editable:%d\n", _directory.repoId, _directory.name, _directory.path, _directory.hasCache, _directory.ooid, _directory.editable);
    if (![_directory isKindOfClass:[SeafRepos class]])
        self.tableView.sectionHeaderHeight = 0;
    [_directory setDelegate:self];
    [self refreshView];
    
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
    if (!self.loadingView) {
        self.loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        self.loadingView.color = [UIColor darkTextColor];
        self.loadingView.hidesWhenStopped = YES;
        [self.view addSubview:self.loadingView];
    }
    self.loadingView.center = self.view.center;
    [self.loadingView startAnimating];
}

- (void)dismissLoadingView
{
    [self.loadingView stopAnimating];
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
    [self updateExportBarItem];
}

- (void)selectNone:(id)sender
{
    long count = self.allItems.count;
    for (int row = 0; row < count; ++row) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
    [self noneSelected:YES];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    if (editing) {
        if (![self checkNetworkStatus]) return;
        [self.navigationController.toolbar sizeToFit];
        [self setToolbarItems:self.editToolItems];
        [self noneSelected:YES];
        [self.photoItem setEnabled:NO];
        [self.navigationController setToolbarHidden:NO animated:YES];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
        [self.navigationController setToolbarHidden:YES animated:YES];
        [self.photoItem setEnabled:YES];
    }

    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
}

- (void)editStart:(id)sender
{
    [self setEditing:YES animated:YES];
    if (self.editing) {
        self.navigationItem.rightBarButtonItems = nil;
        self.navigationItem.rightBarButtonItem = self.doneItem;
    }
}

- (void)editDone:(id)sender
{
    [self setEditing:NO animated:YES];
    self.navigationItem.rightBarButtonItem = nil;
    self.navigationItem.rightBarButtonItems = self.rightItems;
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

        case EDITOP_COPY:
            self.state = STATE_COPY;
            [self popupDirChooseView:nil];
            break;
        case EDITOP_MOVE:
            self.state = STATE_MOVE;
            [self popupDirChooseView:nil];
            break;
        case EDITOP_DELETE: {
            NSArray *idxs = [self.tableView indexPathsForSelectedRows];
            if (!idxs) return;
            NSMutableArray *entries = [[NSMutableArray alloc] init];
            for (NSIndexPath *indexPath in idxs) {
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
        case EDITOP_EXPORT: {
            [self exportSelected];
        }
        default:
            break;
    }
}

- (void)noneSelected:(BOOL)none
{
    if (none) {
        self.navigationItem.leftBarButtonItem = _selectAllItem;
    } else {
        self.navigationItem.leftBarButtonItem = _selectNoneItem;
    }
    [self setToolBarItemsEnabled:!none];
}

- (void)setToolBarItemsEnabled:(BOOL)enabled {
    for (UIBarButtonItem *item in self.toolbarItems) {
        [item setEnabled:enabled];
    }
}

- (void)updateExportBarItem {
    NSArray *idxs = [self.tableView indexPathsForSelectedRows];
    UIBarButtonItem *item = self.toolbarItems.firstObject;
    if (idxs.count > 9) {
        [item setEnabled:NO];
        return;
    }
    for (NSIndexPath *indexPath in idxs) {
        id entry = [self getDentrybyIndexPath:indexPath tableView:self.tableView];
        if ([entry isKindOfClass:[SeafDir class]] || [entry isKindOfClass:[SeafUploadFile class]]) {
            [item setEnabled:NO];
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
    [navController setModalPresentationStyle:UIModalPresentationOverCurrentContext];
    [self presentViewController:navController animated:false completion:nil];
    
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
        
        [[SeafFileOperationManager sharedManager]
            renameEntry:oldName
            newName:input
            inDir:self.directory
            completion:^(BOOL success,SeafBase *renamedFile , NSError * _Nullable error)
        {
            if (success) {
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Rename file success", @"Seafile")];
                [self.directory loadContent:YES];
            } else {
                NSString *errMsg = error.localizedDescription ?: NSLocalizedString(@"Failed to rename file", @"Seafile");
                [SVProgressHUD showErrorWithStatus:errMsg];
                // You can choose to pop up the rename interface again
            }
        }];
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
        imagePickerController.popoverPresentationController.barButtonItem = self.photoItem;
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

- (NSArray *)getCurrentFileImagesInTableView:(UITableView *)tableView
{
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    for (id entry in self.allItems) {
        if ([entry conformsToProtocol:@protocol(SeafPreView)]
            && [(id<SeafPreView>)entry isImageFile])
            [arr addObject:entry];
    }
    return arr;
}

- (void)browserAllPhotos
{
    MWPhotoBrowser *_mwPhotoBrowser = [[MWPhotoBrowser alloc] initWithDelegate:self];
    _mwPhotoBrowser.displayActionButton = false;
    _mwPhotoBrowser.displayNavArrows = true;
    _mwPhotoBrowser.displaySelectionButtons = false;
    _mwPhotoBrowser.alwaysShowControls = false;
    _mwPhotoBrowser.zoomPhotosToFill = YES;
    _mwPhotoBrowser.enableGrid = true;
    _mwPhotoBrowser.startOnGrid = true;
    _mwPhotoBrowser.enableSwipeToDismiss = false;
    _mwPhotoBrowser.preLoadNumLeft = 0;
    _mwPhotoBrowser.preLoadNumRight = 1;

    self.inPhotoBrowser = true;

    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:_mwPhotoBrowser];
    nc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    nc.modalPresentationStyle = UIModalPresentationFullScreen;
    [nc.navigationBar setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    [self presentViewController:nc animated:YES completion:nil];
}

- (void)savePhotosToAlbum
{
    [self checkPhotoLibraryAuth:^{
        __weak typeof(self) weakSelf = self;
        [self alertWithTitle:nil message:NSLocalizedString(@"Are you sure to save all photos to album?", @"Seafile") yes:^{
            __strong typeof(weakSelf) self = weakSelf;
            __weak typeof(self) weakSelf2 = self;
            SeafDownloadCompletionBlock block = ^(SeafFile *file, NSError *error) {
                __strong typeof(weakSelf2) self = weakSelf2;
                if (error) {
                    Warning("Failed to donwload file %@: %@", file.path, error);
                } else {
                    [file setFileDownloadedBlock:nil];
                    [self performSelectorInBackground:@selector(saveImageToAlbum:) withObject:file];
                }
            };
            for (id entry in self.allItems) {
                if (![entry isKindOfClass:[SeafFile class]]) continue;
                SeafFile *file = (SeafFile *)entry;
                if (!file.isImageFile) continue;
                [file loadCache];
                NSString *path = file.cachePath;
                if (!path) {
                    file.state = SEAF_DENTRY_INIT;
                    [file setFileDownloadedBlock:block];
                    [SeafDataTaskManager.sharedObject addFileDownloadTask:file];
                } else {
                    block(file, nil);
                }
            }
            [SVProgressHUD showInfoWithStatus:S_SAVING_PHOTOS_ALBUM];
        } no:nil];
    }];
}

- (void)saveImageToAlbum:(SeafFile *)file
{
    self.state = STATE_INIT;
    UIImage *img = [UIImage imageWithContentsOfFile:file.cachePath];
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC);
    dispatch_semaphore_wait(SeafGlobal.sharedObject.saveAlbumSem, timeout);
    Info("Write image file %@ %@ to album", file.name, file.cachePath);
    UIImageWriteToSavedPhotosAlbum(img, self, @selector(thisImage:hasBeenSavedInPhotoAlbumWithError:usingContextInfo:), (void *)CFBridgingRetain(file));
    dispatch_async(dispatch_get_main_queue(), ^{
        [SVProgressHUD showInfoWithStatus:NSLocalizedString(@"Save to album", @"Seafile")];
    });
}

- (void)thisImage:(UIImage *)image hasBeenSavedInPhotoAlbumWithError:(NSError *)error usingContextInfo:(void *)ctxInfo
{
    SeafFile *file = (__bridge SeafFile *)ctxInfo;
    Info("Finish write image file %@ %@ to album", file.name, file.cachePath);
    dispatch_semaphore_signal(SeafGlobal.sharedObject.saveAlbumSem);
    if (error) {
        Warning("Failed to save file %@ to album: %@", file.name, error);
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to save %@ to album", @"Seafile"), file.name]];
    }
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
                        Warning("Failed to donwload file %@: %@", file.path, error);
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

- (void)deleteFile:(SeafFile *)file
{
    NSArray *entries = [NSArray arrayWithObject:file.name];
    self.state = STATE_DELETE;
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting file ...", @"Seafile")];
    
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

- (void)downloadRepo:(SeafRepo *)repo
{
    Debug("download repo: %@ %@", repo.repoId, repo.path);
    [SVProgressHUD showSuccessWithStatus:[NSLocalizedString(@"Start to download library: ", @"Seafile") stringByAppendingString:repo.name]];
    [_connection performSelectorInBackground:@selector(downloadDir:) withObject:repo];
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
    } else if ([S_PHOTOS_ALBUM isEqualToString:title]) {
        [self savePhotosToAlbum];
    } else if ([S_PHOTOS_BROWSER isEqualToString:title]) {
        [self browserAllPhotos];
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
        [self renameEntry:entry];
    } else if ([S_UPLOAD isEqualToString:title]) {
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
        [file setStarred:YES];
    } else if ([S_UNSTAR isEqualToString:title]) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [file setStarred:NO];
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
        Debug(@"create lib");
        [self popupMklibView];
    }
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
    return cell;
}

- (UITableViewCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView andIndexPath:(NSIndexPath *)indexPath
{
    SeafCell *cell = [self getCell:@"SeafDirCell" forTableView:tableView];
    cell.textLabel.text = sdir.name;
    cell.detailTextLabel.text = @"";
    cell.moreButton.hidden = false;
    cell.imageView.image = sdir.icon;
    cell.cellIndexPath = indexPath;
    cell.moreButtonBlock = ^(NSIndexPath *indexPath) {
        Debug(@"%@", indexPath);
        [self showActionSheetWithIndexPath:indexPath];
    };
    sdir.delegate = self;
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

    return cell;
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
    [self updateCellDownloadStatus:cell isDownloading:sfile.isDownloading waiting:waiting cached:sfile.hasCache];
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
    cell.moreButton.hidden = NO;
    [self updateCellDownloadStatus:cell file:sfile waiting:false];
}

- (SeafBase *)getDentrybyIndexPath:(NSIndexPath *)indexPath tableView:(UITableView *)tableView
{
    if (!indexPath) return nil;
    @try {
        if (![_directory isKindOfClass:[SeafRepos class]])
            return [self.allItems objectAtIndex:[indexPath row]];
        NSArray *repos = [[((SeafRepos *)_directory) repoGroups] objectAtIndex:[indexPath section]];
        return [repos objectAtIndex:[indexPath row]];
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
    if (index == NSNotFound)
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
    [c.navigationController dismissViewControllerAnimated:YES completion:nil];
    NSArray *idxs = [self.tableView indexPathsForSelectedRows];
    if (!idxs) return;
    
    NSMutableArray *entries = [NSMutableArray new];
    for (NSIndexPath *indexPath in idxs) {
        SeafBase *item = self.allItems[indexPath.row];
        [entries addObject:item.name];
    }
    if (self.state == STATE_COPY) {
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Copying files ...", @"Seafile")];
        [[SeafFileOperationManager sharedManager]
            copyEntries:entries
            fromDir:self.directory
            toDir:dstDir
            completion:^(BOOL success, NSError * _Nullable error)
        {
            if (success) {
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Successfully copied", @"Seafile")];
                [self.directory loadContent:YES];
            } else {
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to copy files", @"Seafile")];
            }
        }];
    } else if (self.state == STATE_MOVE) {
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Moving files ...", @"Seafile")];
        [[SeafFileOperationManager sharedManager]
            moveEntries:entries
            fromDir:self.directory
            toDir:dstDir
            completion:^(BOOL success, NSError * _Nullable error)
        {
            if (success) {
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Successfully moved", @"Seafile")];
                [self.directory loadContent:YES];
            } else {
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to move files", @"Seafile")];
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
    if (!self.inPhotoBrowser || ![photo isImageFile])
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


#pragma mark - MWPhotoBrowserDelegate

- (NSUInteger)numberOfPhotosInPhotoBrowser:(MWPhotoBrowser *)photoBrowser {
    if (!self.photos) return 0;
    return self.photos.count;
}

- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index {
    if (index < self.photos.count) {
        return [self.photos objectAtIndex:index];
    }
    return nil;
}

- (NSString *)photoBrowser:(MWPhotoBrowser *)photoBrowser titleForPhotoAtIndex:(NSUInteger)index
{
    if (index < self.photos.count) {
        SeafPhoto *photo = [self.photos objectAtIndex:index];
        return photo.file.name;
    }
    return nil;
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

#pragma mark - Lazy init
// getter searchResultController
- (SeafSearchResultViewController *)searchResultController {
    if (!_searchResultController) {
        _searchResultController = [[SeafSearchResultViewController alloc] init];
    }
    return _searchResultController;
}

- (UISearchController *)searchController {
    if (!_searchController) {
        _searchController = [[UISearchController alloc] initWithSearchResultsController:self.searchResultController];
        _searchController.searchResultsUpdater = self.searchResultController;
        _searchController.searchBar.searchBarStyle = UISearchBarStyleMinimal;
        _searchController.searchBar.barTintColor = [UIColor clearColor];
        _searchController.searchBar.backgroundColor = [UIColor clearColor];
        [_searchController.searchBar sizeToFit];
        
        self.definesPresentationContext = YES;
    }
    return _searchController;
}
@end
