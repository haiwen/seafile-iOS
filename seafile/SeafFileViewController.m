//
//  SeafMasterViewController.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//
#import "MWPhotoBrowser.h"
#import "UIScrollView+SVPullToRefresh.h"

#import "SeafAppDelegate.h"
#import "SeafFileViewController.h"
#import "SeafDetailViewController.h"
#import "SeafDirViewController.h"
#import "SeafFile.h"
#import "SeafRepos.h"
#import "SeafCell.h"
#import "SeafPhoto.h"
#import "SeafPhotoThumb.h"

#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "ExtentedString.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "Debug.h"

#import "QBImagePickerController.h"

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
};


@interface SeafFileViewController ()<QBImagePickerControllerDelegate, UIPopoverControllerDelegate, SeafUploadDelegate, SeafDirDelegate, SeafShareDelegate, UISearchBarDelegate, UISearchDisplayDelegate, MFMailComposeViewControllerDelegate, SWTableViewCellDelegate, MWPhotoBrowserDelegate>
- (UITableViewCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView;
- (UITableViewCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView;
- (UITableViewCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView;

@property (strong, nonatomic) SeafDir *directory;
@property (strong) id<SeafItem> curEntry;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *loadingView;

@property (strong) UIBarButtonItem *selectAllItem;
@property (strong) UIBarButtonItem *selectNoneItem;
@property (strong) UIBarButtonItem *photoItem;
@property (strong) UIBarButtonItem *doneItem;
@property (strong) UIBarButtonItem *editItem;
@property (strong) NSArray *rightItems;

@property (retain) SWTableViewCell *selectedCell;
@property (retain) NSIndexPath *selectedindex;
@property (readonly) NSArray *editToolItems;

@property int state;

@property(nonatomic,strong) UIPopoverController *popoverController;
@property (retain) NSDateFormatter *formatter;

@property(nonatomic, strong, readwrite) UISearchBar *searchBar;
@property(nonatomic, strong) UISearchDisplayController *strongSearchDisplayController;

@property (strong) NSMutableArray *searchResults;

@property (strong, retain) NSArray *photos;
@property (strong, retain) NSArray *thumbs;
@property BOOL inPhotoBrowser;

@property SeafUploadFile *ufile;

@end

@implementation SeafFileViewController

@synthesize connection = _connection;
@synthesize directory = _directory;
@synthesize curEntry = _curEntry;
@synthesize selectAllItem = _selectAllItem, selectNoneItem = _selectNoneItem;
@synthesize selectedindex = _selectedindex;
@synthesize selectedCell = _selectedCell;

@synthesize editToolItems = _editToolItems;

@synthesize popoverController;


- (SeafDetailViewController *)detailViewController
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    return (SeafDetailViewController *)[appdelegate detailViewControllerAtIndex:TABBED_SEAFILE];
}

- (NSArray *)editToolItems
{
    if (!_editToolItems) {
        int i;
        UIBarButtonItem *flexibleFpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:nil];
        UIBarButtonItem *fixedSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:self action:nil];

        NSArray *itemsTitles = [NSArray arrayWithObjects:S_MKDIR, S_NEWFILE, NSLocalizedString(@"Copy", @"Seafile"), NSLocalizedString(@"Move", @"Seafile"), S_DELETE, NSLocalizedString(@"PasteTo", @"Seafile"), NSLocalizedString(@"MoveTo", @"Seafile"), STR_CANCEL, nil ];

        UIBarButtonItem *items[EDITOP_NUM];
        items[0] = flexibleFpaceItem;

        fixedSpaceItem.width = 38.0f;;
        for (i = 1; i < itemsTitles.count + 1; ++i) {
            items[i] = [[UIBarButtonItem alloc] initWithTitle:[itemsTitles objectAtIndex:i-1] style:UIBarButtonItemStylePlain target:self action:@selector(editOperation:)];
            items[i].tag = i;
        }

        _editToolItems = [NSArray arrayWithObjects:items[EDITOP_COPY], items[EDITOP_MOVE], items[EDITOP_SPACE], items[EDITOP_DELETE], nil ];
    }
    return _editToolItems;
}

- (void)setConnection:(SeafConnection *)conn
{
    [self.detailViewController setPreViewItem:nil master:nil];
    [conn loadRepos:self];
    [self setDirectory:(SeafDir *)conn.rootFolder];
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
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)])
        [self.tableView setSeparatorInset:UIEdgeInsetsMake(0, 0, 0, 0)];
    self.formatter = [[NSDateFormatter alloc] init];
    [self.formatter setDateFormat:@"yyyy-MM-dd HH.mm.ss"];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 50.0;
    self.state = STATE_INIT;

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    self.searchBar.searchTextPositionAdjustment = UIOffsetMake(0, 0);
    Debug("repoId:%@, %@, path:%@, loading ... cached:%d %@\n", _directory.repoId, _directory.name, _directory.path, _directory.hasCache, _directory.ooid);
    self.searchBar.delegate = self;
    [self.searchBar sizeToFit];
    self.strongSearchDisplayController = [[UISearchDisplayController alloc] initWithSearchBar:self.searchBar contentsController:self];
    self.searchDisplayController.searchResultsDataSource = self;
    self.searchDisplayController.searchResultsDelegate = self;
    self.searchDisplayController.delegate = self;
    self.tableView.tableHeaderView = self.searchBar;
    self.tableView.contentOffset = CGPointMake(0, CGRectGetHeight(self.searchBar.bounds));
    self.tableView.allowsMultipleSelection = NO;

    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    [self.navigationController setToolbarHidden:YES animated:NO];

    __weak typeof(self) weakSelf = self;
    [self.tableView addPullToRefreshWithActionHandler:^{
        if (weakSelf.searchDisplayController.active)
            return;
        if (![weakSelf checkNetworkStatus]) {
            [weakSelf performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:0.1];
            return;
        }

        weakSelf.state = STATE_LOADING;
        weakSelf.directory.delegate = weakSelf;
        [weakSelf.directory loadContent:YES];
    }];
    [self refreshView];
}

- (void)noneSelected:(BOOL)none
{
    if (none) {
        self.navigationItem.leftBarButtonItem = _selectAllItem;
        NSArray *items = self.toolbarItems;
        [[items objectAtIndex:0] setEnabled:NO];
        [[items objectAtIndex:1] setEnabled:NO];
        [[items objectAtIndex:3] setEnabled:NO];
    } else {
        self.navigationItem.leftBarButtonItem = _selectNoneItem;
        NSArray *items = self.toolbarItems;
        [[items objectAtIndex:0] setEnabled:YES];
        [[items objectAtIndex:1] setEnabled:YES];
        [[items objectAtIndex:3] setEnabled:YES];
    }
}

- (void)checkPreviewFileExist
{
    if ([self.detailViewController.preViewItem isKindOfClass:[SeafFile class]]) {
        SeafFile *sfile = (SeafFile *)self.detailViewController.preViewItem;
        NSString *parent = [sfile.path stringByDeletingLastPathComponent];
        BOOL deleted = YES;
        if (![_directory isKindOfClass:[SeafRepos class]] && _directory.repoId == sfile.repoId && [parent isEqualToString:_directory.path]) {
            for (SeafBase *entry in _directory.allItems) {
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

    for (id entry in _directory.allItems) {
        if ([entry conformsToProtocol:@protocol(SeafPreView)]
            && [(id<SeafPreView>)entry isImageFile]) {
            id<SeafPreView> file = entry;
            [file setDelegate:self];
            [seafPhotos addObject:[[SeafPhoto alloc] initWithSeafPreviewIem:entry]];
            [seafThumbs addObject:[[SeafPhotoThumb alloc] initWithSeafPreviewIem:entry]];
        }
    }
    self.photos = [NSArray arrayWithArray:seafPhotos];
    self.thumbs = [NSArray arrayWithArray:seafThumbs];
}

- (void)refreshView
{
    if (!_directory)
        return;
    if ([_directory isKindOfClass:[SeafRepos class]]) {
        self.searchBar.placeholder = NSLocalizedString(@"Search", @"Seafile");
    } else {
        self.searchBar.placeholder = NSLocalizedString(@"Search files in this library", @"Seafile");
    }

    [self initSeafPhotos];
    for (SeafUploadFile *file in _directory.uploadFiles) {
        file.delegate = self;
    }
    [self.tableView reloadData];
    if (IsIpad() && self.detailViewController.preViewItem) {
        [self checkPreviewFileExist];
    }
    if (self.editing) {
        if (![self.tableView indexPathsForSelectedRows])
            [self noneSelected:YES];
        else
            [self noneSelected:NO];
    }
    if (_directory && !_directory.hasCache) {
        Debug("no cache, load %@ from server.", _directory.path);
        [self showLoadingView];
        self.state = STATE_LOADING;
    }
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

- (void)selectAll:(id)sender
{
    int row;
    long count = _directory.allItems.count;
    for (row = 0; row < count; ++row) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        NSObject *entry  = [self getDentrybyIndexPath:indexPath tableView:self.tableView];
        if (![entry isKindOfClass:[SeafUploadFile class]])
            [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
    }
    [self noneSelected:NO];
}

- (void)selectNone:(id)sender
{
    long count = _directory.allItems.count;
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
        //if(!IsIpad())  self.tabBarController.tabBar.hidden = NO;
        [self.photoItem setEnabled:YES];
    }

    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
}

- (void)addPhotos:(id)sender
{
    if(self.popoverController)
        return;
    if([ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusRestricted ||
       [ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusDenied) {
        return [self alertWithTitle:NSLocalizedString(@"This app does not have access to your photos and videos.", @"Seafile") message:NSLocalizedString(@"You can enable access in Privacy Settings", @"Seafile")];
    }

    QBImagePickerController *imagePickerController = [[QBImagePickerController alloc] init];
    imagePickerController.title = NSLocalizedString(@"Photos", @"Seafile");
    imagePickerController.delegate = self;
    imagePickerController.allowsMultipleSelection = YES;
    imagePickerController.filterType = QBImagePickerControllerFilterTypeNone;

    if (IsIpad()) {
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:imagePickerController];
        self.popoverController = [[UIPopoverController alloc] initWithContentViewController:navigationController];
        self.popoverController.delegate = self;
        [self.popoverController presentPopoverFromBarButtonItem:self.photoItem permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate showDetailView:imagePickerController];
    }
}

- (void)editDone:(id)sender
{
    [self setEditing:NO animated:YES];
    self.navigationItem.rightBarButtonItem = nil;
    self.navigationItem.rightBarButtonItems = self.rightItems;
}

- (void)editStart:(id)sender
{
    [self setEditing:YES animated:YES];
    if (self.editing) {
        self.navigationItem.rightBarButtonItems = nil;
        self.navigationItem.rightBarButtonItem = self.doneItem;
        if (IsIpad() && self.popoverController) {
            [self.popoverController dismissPopoverAnimated:YES];
            self.popoverController = nil;
        }
    }
}

- (void)editSheet:(id)sender
{
    NSMutableArray *titles = nil;
    if ([_directory isKindOfClass:[SeafRepos class]]) {
        titles = [NSMutableArray arrayWithObjects:S_SORT_NAME, S_SORT_MTIME, nil];
    } else if (_directory.editable) {
        titles = [NSMutableArray arrayWithObjects:S_EDIT, S_NEWFILE, S_MKDIR, S_SORT_NAME, S_SORT_MTIME, S_PHOTOS_ALBUM, nil];
        if (self.photos.count >= 3) [titles addObject:S_PHOTOS_BROWSER];
    } else {
        titles = [NSMutableArray arrayWithObjects:S_SORT_NAME, S_SORT_MTIME, S_PHOTOS_ALBUM, nil];
        if (self.photos.count >= 3) [titles addObject:S_PHOTOS_BROWSER];
    }
    [self showAlertWithAction:titles fromBarItem:self.editItem withTitle:nil];
}

- (void)initNavigationItems:(SeafDir *)directory
{
    if (![directory isKindOfClass:[SeafRepos class]] && directory.editable) {
        self.photoItem = [self getBarItem:@"plus".navItemImgName action:@selector(addPhotos:)size:20];
        self.doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(editDone:)];
        self.editItem = [self getBarItemAutoSize:@"ellipsis".navItemImgName action:@selector(editSheet:)];
        UIBarButtonItem *space = [self getSpaceBarItem:16.0];
        self.rightItems = [NSArray arrayWithObjects: self.editItem, space, self.photoItem, nil];

        _selectAllItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Select All", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(selectAll:)];
        _selectNoneItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Select None", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(selectNone:)];
    } else {
        self.editItem = [self getBarItemAutoSize:@"ellipsis".navItemImgName action:@selector(editSheet:)];
        self.rightItems = [NSArray arrayWithObjects: self.editItem, nil];
    }
    self.navigationItem.rightBarButtonItems = self.rightItems;
}

- (SeafDir *)directory
{
    return _directory;
}

- (void)hideSearchBar:(SeafConnection *)conn
{
    if (conn.isSearchEnabled) {
        self.tableView.tableHeaderView = self.searchBar;
    } else {
        self.tableView.tableHeaderView = nil;
    }
    self.searchDisplayController.active = NO;
}

- (void)setDirectory:(SeafDir *)directory
{
    [self hideSearchBar:directory->connection];
    [self initNavigationItems:directory];

    _directory = directory;
    _connection = directory->connection;
    self.title = directory.name;
    [_directory loadContent:false];
    Debug("repoId:%@, %@, path:%@, loading ... cached:%d %@, editable:%d\n", _directory.repoId, _directory.name, _directory.path, _directory.hasCache, _directory.ooid, _directory.editable);
    if (![_directory isKindOfClass:[SeafRepos class]])
        self.tableView.sectionHeaderHeight = 0;
    [_directory setDelegate:self];
    [self refreshView];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (self.loadingView.isAnimating) {
        CGRect viewBounds = self.view.bounds;
        self.loadingView.center = CGPointMake(CGRectGetMidX(viewBounds), CGRectGetMidY(viewBounds));
    }
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
        file.delegate = self;
        if (!file.uploaded && !file.uploading) {
            Debug("background upload %@", file.name);
            [[SeafGlobal sharedObject] addUploadTask:file];
        }
    }
}
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self checkUploadfiles];
    [_directory loadContent:true];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (IsIpad() && self.popoverController) {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController = nil;
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if ([_directory hasCache])
        [SeafAppDelegate checkOpenLink:self];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (tableView != self.tableView || ![_directory isKindOfClass:[SeafRepos class]]) {
        return 1;
    }
    return [[((SeafRepos *)_directory)repoGroups] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (tableView != self.tableView)
        return self.searchResults.count;

    if (![_directory isKindOfClass:[SeafRepos class]]) {
        return _directory.allItems.count;
    }
    NSArray *repos =  [[((SeafRepos *)_directory) repoGroups] objectAtIndex:section];
    return repos.count;
}

- (SeafCell *)getCell:(NSString *)CellIdentifier forTableView:(UITableView *)tableView
{
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    [cell reset];
    if (tableView == self.tableView) {
        cell.rightUtilityButtons = [self rightButtons];
        cell.delegate = self;
    }
    return cell;
}

- (SeafCell *)getCellForTableView:(UITableView *)tableView
{
    return [self getCell:@"SeafCell" forTableView:tableView];
}

- (void)showAlertWithAction:(NSArray *)arr fromRect:(CGRect)rect inView:(UIView *)view withTitle:(NSString *)title
{
    UIAlertController *alert = [self generateAlert:arr withTitle:title handler:^(UIAlertAction *action) {
        [self handleAction:action.title];
    }];
    alert.popoverPresentationController.sourceRect = rect;
    [self presentViewController:alert animated:true completion:nil];
}

- (void)showAlertWithAction:(NSArray *)arr fromBarItem:(UIBarButtonItem *)item withTitle:(NSString *)title
{
    UIAlertController *alert = [self generateAlert:arr withTitle:title handler:^(UIAlertAction *action) {
        [self handleAction:action.title];
    }];
    alert.popoverPresentationController.barButtonItem = item;
    [self presentViewController:alert animated:true completion:nil];
}

- (void)showActionSheetForCell:(UITableViewCell *)cell
{
    id entry = [self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
    if ([entry isKindOfClass:[SeafRepo class]]) {
        SeafRepo *repo = (SeafRepo *)entry;
        NSMutableArray *titles = [[NSMutableArray alloc] init];
        [titles addObject:S_DOWNLOAD];
        if (repo.encrypted) {
            [titles addObject:S_RESET_PASSWORD];
        }
        [self showAlertWithAction:titles fromRect:cell.frame inView:self.tableView withTitle:nil];
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        [self showAlertWithAction:[NSArray arrayWithObjects:S_DOWNLOAD, S_DELETE, S_RENAME, S_SHARE_EMAIL, S_SHARE_LINK, nil] fromRect:cell.frame inView:self.tableView withTitle:nil];
    } else if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)entry;
        NSArray *titles;
        if (file.mpath)
            titles = [NSArray arrayWithObjects:S_DELETE, S_UPLOAD, S_SHARE_EMAIL, S_SHARE_LINK, nil];
        else
            titles = [NSArray arrayWithObjects:S_DELETE, S_REDOWNLOAD, S_RENAME, S_SHARE_EMAIL, S_SHARE_LINK, nil];
        [self showAlertWithAction:[NSArray arrayWithObjects:S_DELETE, S_REDOWNLOAD, S_RENAME, S_SHARE_EMAIL, S_SHARE_LINK, nil] fromRect:cell.frame inView:self.tableView withTitle:nil];
    } else if ([entry isKindOfClass:[SeafUploadFile class]]) {
        [self showAlertWithAction:[NSArray arrayWithObjects:S_DELETE, nil] fromRect:cell.frame inView:self.tableView withTitle:nil];
    }
}

- (void)showEditMenu:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if (self.tableView.editing == YES)
        return;
    if (gestureRecognizer.state != UIGestureRecognizerStateBegan)
        return;

    CGPoint touchPoint = [gestureRecognizer locationInView:self.tableView];
    _selectedindex = [self.tableView indexPathForRowAtPoint:touchPoint];
    if (!_selectedindex)
        return;
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:_selectedindex];
    [self showActionSheetForCell:cell];
}

- (UITableViewCell *)getSeafUploadFileCell:(SeafUploadFile *)file forTableView:(UITableView *)tableView
{
    file.delegate = self;
    SeafCell *cell = [self getCellForTableView:tableView];
    cell.textLabel.text = file.name;
    cell.imageView.image = file.icon;
    if (file.uploading) {
        cell.progressView.hidden = false;
        [cell.progressView setProgress:file.uProgress * 1.0/100];
    } else {
        NSString *sizeStr = [FileSizeFormatter stringFromLongLong:file.filesize];
        NSDictionary *dict = [file uploadAttr];
        if (dict) {
            int utime = [[dict objectForKey:@"utime"] intValue];
            BOOL result = [[dict objectForKey:@"result"] boolValue];
            if (result)
                cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@, Uploaded %@", @"Seafile"), sizeStr, [SeafDateFormatter stringFromLongLong:utime]];
            else {
                cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@, waiting to upload", @"Seafile"), sizeStr];
            }
        } else {
            cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@, waiting to upload", @"Seafile"), sizeStr];
        }
        [self updateCellDownloadStatus:cell isDownloading:false waiting:false cached:false];
    }
    return cell;
}

- (void)updateCellDownloadStatus:(SeafCell *)cell file:(SeafFile *)sfile waiting:(BOOL)waiting
{
    [self updateCellDownloadStatus:cell isDownloading:sfile.isDownloading waiting:waiting cached:sfile.hasCache];
}

- (void)updateCellDownloadStatus:(SeafCell *)cell isDownloading:(BOOL )isDownloading waiting:(BOOL)waiting cached:(BOOL)cached
{
    if (!cell) return;
    //Debug("... cached:%d %d %d", cached, waiting, isDownloading);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (cached || waiting || isDownloading) {
            cell.cacheStatusView.hidden = false;
            [cell.cacheStatusWidthConstraint setConstant:21.0f];

            if (isDownloading) {
                [cell.downloadingIndicator startAnimating];
            } else {
                NSString *downloadImageNmae = waiting ? @"download_waiting" : @"download_finished";
                cell.downloadStatusImageView.image = [UIImage imageNamed:downloadImageNmae];
            }
            cell.downloadStatusImageView.hidden = isDownloading;
            cell.downloadingIndicator.hidden = !isDownloading;
        } else {
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

- (SeafCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView
{
    [sfile loadCache];
    SeafCell *cell = [self getCellForTableView:tableView];
    [self updateCellContent:cell file:sfile];
    sfile.delegate = self;
    sfile.udelegate = self;
    if (tableView != self.tableView) {// For search results
        SeafRepo *repo = [_connection getRepo:sfile.repoId];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@, %@", repo.name, sfile.path.stringByDeletingLastPathComponent, sfile.detailText];
    }
    return cell;
}

- (SeafCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafDirCell" forTableView:tableView];
    cell.textLabel.text = sdir.name;
    cell.detailTextLabel.text = @"";
    cell.imageView.image = sdir.icon;
    sdir.delegate = self;
    return cell;
}

- (SeafCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView
{
    SeafCell *cell = [self getCellForTableView:tableView];
    cell.detailTextLabel.text = srepo.detailText;
    cell.imageView.image = srepo.icon;
    cell.textLabel.text = srepo.name;
    [cell.cacheStatusWidthConstraint setConstant:0.0f];
    srepo.delegate = self;
    if (tableView == self.tableView) {
        [cell setRightUtilityButtons:[self repoButtons:srepo] WithButtonWidth:100];
    } else {
        cell.rightUtilityButtons = nil;
    }

    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSObject *entry = [self getDentrybyIndexPath:indexPath tableView:tableView];
    if (!entry) return [[UITableViewCell alloc] init];

    if (tableView != self.tableView) {
        // For search results.
        return [self getSeafFileCell:(SeafFile *)entry forTableView:tableView];
    }
    if ([entry isKindOfClass:[SeafRepo class]]) {
        return [self getSeafRepoCell:(SeafRepo *)entry forTableView:tableView];
    } else if ([entry isKindOfClass:[SeafFile class]]) {
        return [self getSeafFileCell:(SeafFile *)entry forTableView:tableView];
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        return [self getSeafDirCell:(SeafDir *)entry forTableView:tableView];
    } else {
        return [self getSeafUploadFileCell:(SeafUploadFile *)entry forTableView:tableView];
    }
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView != self.tableView) return indexPath;
    NSObject *entry  = [self getDentrybyIndexPath:indexPath tableView:tableView];
    if (tableView.editing && [entry isKindOfClass:[SeafUploadFile class]])
        return nil;
    return indexPath;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView != self.tableView) return NO;
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

- (void)popupSetRepoPassword:(SeafRepo *)repo
{
    self.state = STATE_PASSWORD;
    [self popupSetRepoPassword:repo handler:^{
            [SVProgressHUD dismiss];
            self.state = STATE_INIT;
            SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
            [self.navigationController pushViewController:controller animated:YES];
            [controller setDirectory:(SeafDir *)repo];
    }];
}

- (void)popupMkdirView
{
    self.state = STATE_MKDIR;
    _directory.delegate = self;
    [self popupInputView:S_MKDIR placeholder:NSLocalizedString(@"New folder name", @"Seafile") secure:false handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Folder name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"Folder name invalid", @"Seafile")];
            return;
        }
        [_directory mkdir:input];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Creating folder ...", @"Seafile")];
    }];
}

- (void)popupCreateView
{
    self.state = STATE_CREATE;
    _directory.delegate = self;
    [self popupInputView:S_NEWFILE placeholder:NSLocalizedString(@"New file name", @"Seafile") secure:false handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"File name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"File name invalid", @"Seafile")];
            return;
        }
        [_directory createFile:input];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Creating file ...", @"Seafile")];
    }];
}

- (void)popupRenameView:(NSString *)newName
{
    self.state = STATE_RENAME;
    [self popupInputView:S_RENAME placeholder:newName secure:false handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"File name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"File name invalid", @"Seafile")];
            return;
        }
        [_directory renameFile:(SeafFile *)_curEntry newName:input];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Renaming file ...", @"Seafile")];
    }];
}

- (void)popupDirChooseView:(SeafUploadFile *)file
{
    self.ufile = file;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    UIViewController *controller = [[SeafDirViewController alloc] initWithSeafDir:self.connection.rootFolder delegate:self chooseRepo:false];

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    [navController setModalPresentationStyle:UIModalPresentationFormSheet];
    [appdelegate.window.rootViewController presentViewController:navController animated:YES completion:nil];
    if (IsIpad()) {
        CGRect frame = navController.view.superview.frame;
        navController.view.superview.frame = CGRectMake(frame.origin.x+frame.size.width/2-320/2, frame.origin.y+frame.size.height/2-500/2, 320, 500);
    }
}

- (SeafBase *)getDentrybyIndexPath:(NSIndexPath *)indexPath tableView:(UITableView *)tableView
{
    if (!indexPath) return nil;
    @try {
        if (tableView != self.tableView) {
            return [self.searchResults objectAtIndex:indexPath.row];
        } else if (![_directory isKindOfClass:[SeafRepos class]])
            return [_directory.allItems objectAtIndex:[indexPath row]];
        NSArray *repos = [[((SeafRepos *)_directory)repoGroups] objectAtIndex:[indexPath section]];
        return [repos objectAtIndex:[indexPath row]];
    } @catch(NSException *exception) {
        return nil;
    }
}

- (BOOL)isCurrentFileImage:(NSMutableArray **)imgs
{
    if (![_curEntry conformsToProtocol:@protocol(SeafPreView)])
        return NO;
    id<SeafPreView> pre = (id<SeafPreView>)_curEntry;
    if (!pre.isImageFile) return NO;

    NSMutableArray *arr = [[NSMutableArray alloc] init];
    for (id entry in _directory.allItems) {
        if ([entry conformsToProtocol:@protocol(SeafPreView)]
            && [(id<SeafPreView>)entry isImageFile])
            [arr addObject:entry];
    }
    *imgs = arr;
    return YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.navigationController.topViewController != self)   return;
    _selectedindex = indexPath;
    if (tableView.editing == YES) {
        return [self noneSelected:NO];
    }
    _curEntry = [self getDentrybyIndexPath:indexPath tableView:tableView];
    Debug("Select %@", _curEntry.name);
    if (!_curEntry) {
        return [self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
    }
    if ([_curEntry isKindOfClass:[SeafRepo class]] && [(SeafRepo *)_curEntry passwordRequired]) {
        return [self popupSetRepoPassword:(SeafRepo *)_curEntry];
    }
    [_curEntry setDelegate:self];
    if ([_curEntry conformsToProtocol:@protocol(SeafPreView)]) {
        if ([_curEntry isKindOfClass:[SeafFile class]] && ![(SeafFile *)_curEntry hasCache]) {
            SeafCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            [self updateCellDownloadStatus:cell file:(SeafFile *)_curEntry waiting:true];
        }
        if (!IsIpad()) {
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate showDetailView:self.detailViewController];
        }
        NSMutableArray *arr = nil;
        if ([self isCurrentFileImage:&arr]) {
            [self.detailViewController setPreViewPhotos:arr current:(id<SeafPreView>)_curEntry master:self];
        } else {
            id<SeafPreView> item = (id<SeafPreView>)_curEntry;
            [self.detailViewController setPreViewItem:item master:self];
        }
    } else if ([_curEntry isKindOfClass:[SeafDir class]]) {
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
        if (![tableView indexPathsForSelectedRows])
            [self noneSelected:YES];
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (self.searchResults || tableView != self.tableView || ![_directory isKindOfClass:[SeafRepos class]])
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
        } else {
            if ([repo.owner isEqualToString:ORG_REPO]) {
                text = NSLocalizedString(@"Organization", @"Seafile");
            } else {
                text = repo.owner;
            }
        }
    }
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, tableView.bounds.size.width - 10, 18)];
    label.font = [UIFont systemFontOfSize:14];
    label.text = text;
    label.textColor = [UIColor darkTextColor];
    label.backgroundColor = [UIColor clearColor];
    [headerView setBackgroundColor:HEADER_COLOR];
    [headerView addSubview:label];
    return headerView;
}

#pragma mark - SeafDentryDelegate
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
    if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)entry;
        [self updateEntryCell:file];
        [self.detailViewController download:file complete:updated];
        SeafPhoto *photo = [self getSeafPhoto:(id<SeafPreView>)entry];
        [photo complete:updated error:nil];
    } else if (entry == _directory) {
        [self dismissLoadingView];
        [SVProgressHUD dismiss];
        [self doneLoadingTableViewData];
        if (self.state == STATE_DELETE && !IsIpad()) {
            [self.detailViewController goBack:nil];
        }

        [self dismissLoadingView];
        if (updated) {
            [self refreshView];
            [SeafAppDelegate checkOpenLink:self];
        } else {
            //[self.tableView reloadData];
        }
        self.state = STATE_INIT;
    }
}

- (void)download:(SeafBase *)entry failed:(NSError *)error
{
    if ([entry isKindOfClass:[SeafFile class]]) {
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
                SeafFile *file = (SeafFile *)_curEntry;
                [self performSelector:@selector(popupRenameView:) withObject:file.name afterDelay:1.0];
                break;
            }
            case STATE_LOADING:
                if (!_directory.hasCache) {
                    [self dismissLoadingView];
                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load files", @"Seafile")];
                } else
                    [SVProgressHUD dismiss];
                break;
            default:
                break;
        }
        self.state = STATE_INIT;
        [self dismissLoadingView];
    }
}

- (void)doneLoadingTableViewData
{
    [self.tableView.pullToRefreshView stopAnimating];
}

#pragma mark - edit files
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
                [entries addObject:[_directory.allItems objectAtIndex:indexPath.row]];
            }
            self.state = STATE_DELETE;
            _directory.delegate = self;
            [_directory delEntries:entries];
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting files ...", @"Seafile")];
            break;
        }
        default:
            break;
    }
}

- (void)deleteFile:(SeafFile *)file
{
    NSArray *entries = [NSArray arrayWithObject:file];
    self.state = STATE_DELETE;
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting file ...", @"Seafile")];
    _directory.delegate = self;
    [_directory delEntries:entries];
}

- (void)deleteDir:(SeafDir *)dir
{
    NSArray *entries = [NSArray arrayWithObject:dir];
    self.state = STATE_DELETE;
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting directory ...", @"Seafile")];
    _directory.delegate = self;
    [_directory delEntries:entries];
}

- (void)redownloadFile:(SeafFile *)file
{
    [file cancelAnyLoading];
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

- (void)savePhotosToAlbum
{
    SeafFileDidDownloadBlock block = ^(SeafFile *file, BOOL result) {
        if (!result) {
            return Warning("Failed to donwload file %@", file.path);
        }
        [file setFileDownloadedBlock:nil];
        Debug("Save file %@ %@ to album", file.name, file.cachePath);
        UIImage *img = [UIImage imageWithContentsOfFile:file.cachePath];
        UIImageWriteToSavedPhotosAlbum(img, self, @selector(thisImage:hasBeenSavedInPhotoAlbumWithError:usingContextInfo:), (void *)CFBridgingRetain(file));
    };
    for (id entry in _directory.allItems) {
        if (![entry isKindOfClass:[SeafFile class]]) continue;
        SeafFile *file = (SeafFile *)entry;
        if (!file.isImageFile) continue;
        [file loadCache];
        NSString *path = file.cachePath;
        if (!path) {
            [file setFileDownloadedBlock:block];
            [SeafGlobal.sharedObject addDownloadTask:file];
        } else {
            block(file, true);
        }
    }
    [SVProgressHUD showSuccessWithStatus:S_PHOTOS_ALBUM];
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
    _mwPhotoBrowser.preLoadNum = 3;

    self.inPhotoBrowser = true;

    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:_mwPhotoBrowser];
    nc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:nc animated:YES completion:nil];
}

- (void)thisImage:(UIImage *)image hasBeenSavedInPhotoAlbumWithError:(NSError *)error usingContextInfo:(void *)ctxInfo
{
    if (error) {
        SeafFile *file = (__bridge SeafFile *)ctxInfo;
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to save %@ to album", @"Seafile"), file.name]];
    }
}

- (void)renameFile:(SeafFile *)file
{
    _curEntry = file;
    [self popupRenameView:file.name];
}

- (void)reloadIndex:(NSIndexPath *)indexPath
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (indexPath) {
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            if (!cell) return;
            @try {
                [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
            } @catch(NSException *exception) {
                Warning("Failed to reload cell %@: %@", indexPath, exception);
            }
        } else
            [self.tableView reloadData];
    });
}

- (void)deleteEntry:(id)entry
{
    self.state = STATE_DELETE;
    if ([entry isKindOfClass:[SeafUploadFile class]]) {
        if (self.detailViewController.preViewItem == entry)
            self.detailViewController.preViewItem = nil;
        [self.directory removeUploadFile:(SeafUploadFile *)entry];
        [self.tableView reloadData];
    } else if ([entry isKindOfClass:[SeafFile class]])
        [self deleteFile:(SeafFile*)entry];
    else if ([entry isKindOfClass:[SeafDir class]])
        [self deleteDir: (SeafDir*)entry];
}

- (void)handleAction:(NSString *)title
{
    Debug("handle action title:%@, %@", title, _selectedCell);
    if (_selectedCell) {
        [self hideCellButton:_selectedCell];
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
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [self renameFile:file];
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
        NSString *key = [SeafGlobal.sharedObject objectForKey:@"SORT_KEY"];
        if ([@"NAME" caseInsensitiveCompare:key] != NSOrderedSame) {
            [SeafGlobal.sharedObject setObject:@"NAME" forKey:@"SORT_KEY"];
        }
        [_directory reSortItems];
        [self.tableView reloadData];
    } else if ([S_SORT_MTIME isEqualToString:title]) {
        NSString *key = [SeafGlobal.sharedObject objectForKey:@"SORT_KEY"];
        if ([@"MTIME" caseInsensitiveCompare:key] != NSOrderedSame) {
            [SeafGlobal.sharedObject setObject:@"MTIME" forKey:@"SORT_KEY"];
        }
        [_directory reSortItems];
        [self.tableView reloadData];
    } else if ([S_RESET_PASSWORD isEqualToString:title]) {
        SeafRepo *repo = (SeafRepo *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [repo->connection setRepo:repo.repoId password:nil];
        [self popupSetRepoPassword:repo];
    } else if ([S_CLEAR_REPO_PASSWORD isEqualToString:title]) {
        SeafRepo *repo = (SeafRepo *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [repo->connection setRepo:repo.repoId password:nil];
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Clear library password successfully.", @"Seafile")];
    }
}

- (void)backgroundUpload:(SeafUploadFile *)ufile
{
    [[SeafGlobal sharedObject] addUploadTask:ufile];
}

- (void)uploadFile:(SeafUploadFile *)ufile toDir:(SeafDir *)dir overwrite:(BOOL)overwrite
{
    ufile.overwrite = overwrite;
    [dir addUploadFile:ufile flush:true];
    [NSThread detachNewThreadSelector:@selector(backgroundUpload:) toTarget:self withObject:ufile];
}

- (void)uploadFile:(SeafUploadFile *)ufile toDor:(SeafDir *)dir
{
    if ([dir nameExist:ufile.name]) {
        [self alertWithTitle:STR_12 message:nil yes:^{
            [self uploadFile:ufile toDir:dir overwrite:true];
        } no:^{
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
- (void)chooseDir:(UIViewController *)c dir:(SeafDir *)dir
{
    [c.navigationController dismissViewControllerAnimated:YES completion:nil];
    if (self.ufile) {
        return [self uploadFile:self.ufile toDor:dir];
    }
    NSArray *idxs = [self.tableView indexPathsForSelectedRows];
    if (!idxs) return;
    NSMutableArray *entries = [[NSMutableArray alloc] init];
    for (NSIndexPath *indexPath in idxs) {
        [entries addObject:[_directory.allItems objectAtIndex:indexPath.row]];
    }
    _directory.delegate = self;
    if (self.state == STATE_COPY) {
        [_directory copyEntries:entries dstDir:dir];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Copying files ...", @"Seafile")];
    } else {
        [_directory moveEntries:entries dstDir:dir];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Moving files ...", @"Seafile")];
    }
}
- (void)cancelChoose:(UIViewController *)c
{
    [c.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - QBImagePickerControllerDelegate
- (NSMutableSet *)getExistedNameSet
{
    NSMutableSet *nameSet = [[NSMutableSet alloc] init];
    for (id obj in _directory.allItems) {
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

- (void)uploadPickedAssets:(NSArray *)assets overwrite:(BOOL)overwrite
{
    NSMutableSet *nameSet = overwrite ? [NSMutableSet new] : [self getExistedNameSet];
    NSMutableArray *files = [[NSMutableArray alloc] init];
    NSString *uploadDir = [SeafGlobal.sharedObject uniqueUploadDir];
    for (ALAsset *asset in assets) {
        NSString *filename = asset.defaultRepresentation.filename;
        Debug("Upload picked file : %@", filename);
        if (!overwrite && [nameSet containsObject:filename]) {
            NSString *name = filename.stringByDeletingPathExtension;
            NSString *ext = filename.pathExtension;
            filename = [self getUniqueFilename:name ext:ext nameSet:nameSet];
        }
        [nameSet addObject:filename];
        NSString *path = [uploadDir stringByAppendingPathComponent:filename];
        SeafUploadFile *file =  [self.connection getUploadfile:path];
        file.overwrite = overwrite;
        [file setAsset:asset url:asset.defaultRepresentation.url];
        file.delegate = self;
        [files addObject:file];
        [self.directory addUploadFile:file flush:false];
    }
    [SeafUploadFile saveAttrs];
    [self.tableView reloadData];
    for (SeafUploadFile *file in files) {
        [[SeafGlobal sharedObject] addUploadTask:file];
    }
}

- (void)uploadPickedAssetsUrl:(NSArray *)urls overwrite:(BOOL)overwrite
{
    if (urls.count == 0) return;
    NSMutableArray *assets = [[NSMutableArray alloc] init];
    NSURL *last = [urls objectAtIndex:urls.count-1];
    for (NSURL *url in urls) {
        [SeafGlobal.sharedObject assetForURL:url
                                  resultBlock:^(ALAsset *asset) {
                                      if (assets) [assets addObject:asset];
                                      if (url == last) [self uploadPickedAssets:assets overwrite:overwrite];
                                  } failureBlock:^(NSError *error) {
                                      if (url == last) [self uploadPickedAssets:assets overwrite:overwrite];
                                  }];
    }
}

- (void)dismissImagePickerController:(QBImagePickerController *)imagePickerController
{
    if (IsIpad()) {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController = nil;
    } else {
        [imagePickerController.navigationController dismissViewControllerAnimated:YES completion:NULL];
    }
}

- (void)qb_imagePickerControllerDidCancel:(QBImagePickerController *)imagePickerController
{
    [self dismissImagePickerController:imagePickerController];
}

- (void)qb_imagePickerController:(QBImagePickerController *)imagePickerController didSelectAssets:(NSArray *)assets
{
    if (assets.count == 0) return;
    NSSet *nameSet = [self getExistedNameSet];
    NSMutableArray *urls = [[NSMutableArray alloc] init];
    int duplicated = 0;
    for (ALAsset *asset in assets) {
        NSURL *url = asset.defaultRepresentation.url;
        if (url) {
            NSString *filename = asset.defaultRepresentation.filename;
            if ([nameSet containsObject:filename])
                duplicated++;
            [urls addObject:url];
        } else
            Warning("Failed to get asset url %@", asset);
    }
    [self dismissImagePickerController:imagePickerController];
    if (duplicated > 0) {
        NSString *title = duplicated == 1 ? STR_12 : STR_13;
        [self alertWithTitle:title message:nil yes:^{
            [self uploadPickedAssetsUrl:urls overwrite:true];
        } no:^{
            [self uploadPickedAssetsUrl:urls overwrite:false];
        }];
    } else
        [self uploadPickedAssetsUrl:urls overwrite:false];
}

#pragma mark - UIPopoverControllerDelegate
- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
    self.popoverController = nil;
}

#pragma mark - SeafFileUpdateDelegate
- (void)updateProgress:(SeafFile *)file progress:(int)percent
{
    [self updateEntryCell:file];
}
- (void)updateComplete:(nonnull SeafFile * )file result:(BOOL)res
{
    [self updateEntryCell:file];
}

#pragma mark - SeafUploadDelegate
- (void)updateFileCell:(SeafUploadFile *)file result:(BOOL)res progress:(int)percent completed:(BOOL)completed
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSIndexPath *indexPath = nil;
        SeafCell *cell = [self getEntryCell:file indexPath:&indexPath];
        if (!cell) return;
        if (!completed && res) {
            [cell.progressView setProgress:percent*1.0f/100];
        } else if (indexPath) {
            [self reloadIndex:indexPath];
        }
    });
}

- (void)uploadProgress:(SeafUploadFile *)file progress:(int)percent
{
    [self updateFileCell:file result:true progress:percent completed:false];
}

- (void)uploadComplete:(BOOL)success file:(SeafUploadFile *)file oid:(NSString *)oid
{
    if (!success) {
        return [self updateFileCell:file result:false progress:0 completed:true];
    }
    [self updateFileCell:file result:YES progress:100 completed:YES];
    if (self.isVisible) {
        [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:NSLocalizedString(@"File '%@' uploaded success", @"Seafile"), file.name]];
    }
}

#pragma mark - UISearchDisplayDelegate
#define SEARCH_STATE_INIT NSLocalizedString(@"Click \"Search\" to start", @"Seafile")
#define SEARCH_STATE_SEARCHING NSLocalizedString(@"Searching", @"Seafile")
#define SEARCH_STATE_NORESULTS NSLocalizedString(@"No Results", @"Seafile")

- (void)setSearchState:(UISearchDisplayController *)controller state:(NSString *)state
{
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.001*NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        for (UIView* v in controller.searchResultsTableView.subviews) {
            if ([v isKindOfClass: [UILabel class]] &&
                ([[(UILabel*)v text] isEqualToString:SEARCH_STATE_NORESULTS]
                 || [[(UILabel*)v text] isEqualToString:SEARCH_STATE_INIT]
                 || [[(UILabel*)v text] isEqualToString:SEARCH_STATE_SEARCHING])) {
                [(UILabel*)v setText:state];
                break;
            }
        }
    });
}

- (void)searchDisplayControllerWillBeginSearch:(UISearchDisplayController *)controller
{
    self.searchResults = [[NSMutableArray alloc] init];
    [self.searchDisplayController.searchResultsTableView reloadData];
    self.tableView.sectionHeaderHeight = 0;
    [self setSearchState:self.searchDisplayController state:SEARCH_STATE_INIT];
}

- (void)searchDisplayControllerDidEndSearch:(UISearchDisplayController *)controller
{
    self.searchResults = nil;
    if ([_directory isKindOfClass:[SeafRepos class]]) {
        self.tableView.sectionHeaderHeight = HEADER_HEIGHT;
        [self.tableView reloadData];
    }
}

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchString:(NSString *)searchString
{
    self.searchResults = [[NSMutableArray alloc] init];
    [self setSearchState:controller state:SEARCH_STATE_INIT];
    return YES;
}

- (void)searchDisplayController:(UISearchDisplayController *)controller didLoadSearchResultsTableView:(UITableView *)tableView
{
    tableView.sectionHeaderHeight = 0;
    [self setSearchState:controller state:SEARCH_STATE_INIT];
}

#pragma mark - UISearchBarDelegate
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    Debug("search %@", searchBar.text);
    [self setSearchState:self.searchDisplayController state:SEARCH_STATE_SEARCHING];
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Searching ...", @"Seafile")];
    NSString *repoId = [_directory isKindOfClass:[SeafRepos class]] ? nil : _directory.repoId;
    [_connection search:searchBar.text repo:repoId success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSMutableArray *results) {
        [SVProgressHUD dismiss];
        if (results.count == 0)
            [self setSearchState:self.searchDisplayController state:SEARCH_STATE_NORESULTS];
        else {
            self.searchResults = results;
            [self.searchDisplayController.searchResultsTableView reloadData];
        }
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        if (response.statusCode == 404) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Search is not supported on the server", @"Seafile")];
        } else
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to search", @"Seafile")];
    }];
}

- (void)photoSelectedChanged:(id<SeafPreView>)from to:(id<SeafPreView>)to;
{
    NSUInteger index = [_directory.allItems indexOfObject:to];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];

    [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionMiddle];
}

- (SeafCell *)getEntryCell:(id)entry indexPath:(NSIndexPath **)indexPath
{
    NSUInteger index = [_directory.allItems indexOfObject:entry];
    if (index == NSNotFound)
        return nil;
    @try {
        NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
        if (indexPath) *indexPath = path;
        return (SeafCell *)[self.tableView cellForRowAtIndexPath:path];
    } @catch(NSException *exception) {
        return nil;
    }
}

- (void)updateEntryCell:(SeafFile *)entry
{
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            SeafCell *cell = [self getEntryCell:entry indexPath:nil];
            [self updateCellContent:cell file:entry];
        } @catch(NSException *exception) {
        }
    });
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

#pragma mark - sena mail inside app
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
    MFMailComposeViewController *mailPicker = appdelegate.globalMailComposer;    mailPicker.mailComposeDelegate = self;
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
    [self presentViewController:mailPicker animated:YES completion:nil];
}

#pragma mark - MFMailComposeViewControllerDelegate
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

- (void)hideCellButton:(SWTableViewCell *)cell
{
    [cell hideUtilityButtonsAnimated:true];
}

#pragma mark - SWTableViewCellDelegate
- (void)swipeableTableViewCell:(SWTableViewCell *)cell didTriggerRightUtilityButtonWithIndex:(NSInteger)index
{
    _selectedindex = [self.tableView indexPathForCell:cell];
    if (!_selectedindex)
        return;
    SeafBase *base = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
    if ([base isKindOfClass:[SeafRepo class]]) {
        SeafRepo *repo = (SeafRepo *)base;
       if (index == 0) {
           [self downloadRepo:repo];
        } else {
            [repo->connection setRepo:repo.repoId password:nil];
            [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Clear library password successfully.", @"Seafile")];
        }
        [self performSelector:@selector(hideCellButton:) withObject:cell afterDelay:0.1f];
    } else {
        if (index == 0) {// More
            _selectedCell = cell;
            [self showActionSheetForCell:cell];
            [self.tableView selectRowAtIndexPath:_selectedindex animated:true scrollPosition:UITableViewScrollPositionNone];
        } else { // Delete
            [self deleteEntry:base];
        }
    }
}

- (NSArray *)rightButtons
{
    NSMutableArray *rightUtilityButtons = [NSMutableArray new];
    [rightUtilityButtons sw_addUtilityButtonWithColor:
     [UIColor colorWithRed:0.78f green:0.78f blue:0.8f alpha:1.0]
                                                title:S_MORE];
    [rightUtilityButtons sw_addUtilityButtonWithColor:
     [UIColor colorWithRed:1.0f green:0.231f blue:0.188 alpha:1.0f]
                                                title:S_DELETE];

    return rightUtilityButtons;
}

- (NSArray *)repoButtons:(SeafRepo *)repo
{
    NSMutableArray *rightUtilityButtons = [NSMutableArray new];
    [rightUtilityButtons sw_addUtilityButtonWithColor:
     [UIColor colorWithRed:0.78f green:0.78f blue:0.8f alpha:1.0]
                                                title:S_DOWNLOAD];
    if (repo.encrypted) {
        [rightUtilityButtons sw_addUtilityButtonWithColor:
         [UIColor colorWithRed:1.0f green:0.231f blue:0.188 alpha:1.0f]
                                                    title:S_CLEAR_REPO_PASSWORD];
    }
    return rightUtilityButtons;
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
    } else {
        Warning("index %lu out of bound %lu, %@", (unsigned long)index, (unsigned long)self.photos.count, self.photos);
        return nil;
    }
}
- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser thumbPhotoAtIndex:(NSUInteger)index
{
    if (index < self.thumbs.count)
        return [self.thumbs objectAtIndex:index];
    return nil;
}

- (void)photoBrowserDidFinishModalPresentation:(MWPhotoBrowser *)photoBrowser
{
    [photoBrowser dismissViewControllerAnimated:YES completion:nil];
    self.inPhotoBrowser = false;
}

- (BOOL)goTo:(NSString *)repo path:(NSString *)path
{
    if (![_directory hasCache] || !self.isVisible)
        return TRUE;
    Debug("repo: %@, path: %@, current: %@", repo, path, _directory.path);
    if ([self.directory isKindOfClass:[SeafRepos class]]) {
        for (int i = 0; i < ((SeafRepos *)_directory).repoGroups.count; ++i) {
            NSArray *repos = [((SeafRepos *)_directory).repoGroups objectAtIndex:i];
            for (int j = 0; j < repos.count; ++j) {
                SeafRepo *r = [repos objectAtIndex:j];
                if ([r.repoId isEqualToString:repo]) {
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:j inSection:i];
                    [self.tableView selectRowAtIndexPath:indexPath animated:true scrollPosition:UITableViewScrollPositionMiddle];
                    [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
                    return TRUE;
                }
            }
        }
        Debug("Repo %@ not found.", repo);
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to find library", @"Seafile")];
    } else {
        if ([@"/" isEqualToString:path])
            return FALSE;
        for (int i = 0; i < _directory.allItems.count; ++i) {
            SeafBase *b = [_directory.allItems objectAtIndex:i];
            NSString *p = b.path;
            if ([b isKindOfClass:[SeafDir class]]) {
                p = [p stringByAppendingString:@"/"];
            }
            BOOL found = [p isEqualToString:path];
            if (found || [path hasPrefix:p]) {
                Debug("found=%d, path:%@, p:%@", found, path, p);
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
                [self.tableView selectRowAtIndexPath:indexPath animated:true scrollPosition:UITableViewScrollPositionMiddle];
                [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
                return !found;
            }
        }
        Debug("file %@/%@ not found", repo, path);
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to find %@", @"Seafile"), path]];
    }
    return FALSE;
}

@end
