//
//  SeafMasterViewController.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafFileViewController.h"
#import "SeafDetailViewController.h"
#import "SeafUploadDirViewController.h"
#import "SeafDirViewController.h"
#import "SeafFile.h"
#import "SeafRepos.h"
#import "SeafCell.h"
#import "SeafUploadingFileCell.h"

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
#define S_PASSWORD NSLocalizedString(@"Password of this library", @"Seafile")
#define S_MKDIR NSLocalizedString(@"New Folder", @"Seafile")
#define S_NEWFILE NSLocalizedString(@"New File", @"Seafile")
#define S_RENAME NSLocalizedString(@"Rename", @"Seafile")
#define S_EDIT NSLocalizedString(@"Edit", @"Seafile")
#define S_DELETE NSLocalizedString(@"Delete", @"Seafile")
#define S_SHARE_EMAIL NSLocalizedString(@"Send share link via email", @"Seafile")
#define S_SHARE_LINK NSLocalizedString(@"Copy share link to clipboard", @"Seafile")
#define S_REDOWNLOAD NSLocalizedString(@"Redownload", @"Seafile")
#define S_UPLOAD NSLocalizedString(@"Upload", @"Seafile")


@interface SeafFileViewController ()<QBImagePickerControllerDelegate, UIPopoverControllerDelegate, SeafUploadDelegate, EGORefreshTableHeaderDelegate, SeafDirDelegate, SeafShareDelegate, UISearchBarDelegate, UISearchDisplayDelegate, UIAlertViewDelegate, UIActionSheetDelegate, MFMailComposeViewControllerDelegate>
- (UITableViewCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView;
- (UITableViewCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView;
- (UITableViewCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView;

@property (strong, nonatomic) SeafDir *directory;
@property (strong) id curEntry;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *loadingView;

@property (strong) UIBarButtonItem *selectAllItem;
@property (strong) UIBarButtonItem *selectNoneItem;
@property (strong) UIBarButtonItem *photoItem;
@property (strong) UIBarButtonItem *doneItem;
@property (strong) UIBarButtonItem *editItem;
@property (strong) NSArray *rightItems;

@property (readonly) EGORefreshTableHeaderView* refreshHeaderView;

@property (retain) NSIndexPath *selectedindex;
@property (readonly) NSArray *editToolItems;

@property (strong) UIActionSheet *actionSheet;

@property int state;

@property(nonatomic,strong) UIPopoverController *popoverController;
@property (retain) NSDateFormatter *formatter;

@property(nonatomic, strong, readwrite) UISearchBar *searchBar;
@property(nonatomic, strong) UISearchDisplayController *strongSearchDisplayController;

@property (strong) NSMutableArray *searchResults;

@end

@implementation SeafFileViewController

@synthesize connection = _connection;
@synthesize directory = _directory;
@synthesize curEntry = _curEntry;
@synthesize selectAllItem = _selectAllItem, selectNoneItem = _selectNoneItem;
@synthesize selectedindex = _selectedindex;
@synthesize editToolItems = _editToolItems;

@synthesize popoverController;


- (SeafDetailViewController *)detailViewController
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    return (SeafDetailViewController *)[appdelegate detailViewController:TABBED_SEAFILE];
}

- (NSArray *)editToolItems
{
    if (!_editToolItems) {
        int i;
        UIBarButtonItem *flexibleFpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:nil];
        UIBarButtonItem *fixedSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:self action:nil];

        NSArray *itemsTitles = [NSArray arrayWithObjects:S_MKDIR, S_NEWFILE, NSLocalizedString(@"Copy", @"Seafile"), NSLocalizedString(@"Move", @"Seafile"), S_DELETE, NSLocalizedString(@"PasteTo", @"Seafile"), NSLocalizedString(@"MoveTo", @"Seafile"), NSLocalizedString(@"Cancel", @"Seafile"), nil ];

        UIBarButtonItem *items[EDITOP_NUM];
        items[0] = flexibleFpaceItem;

        fixedSpaceItem.width = 38.0f;;
        for (i = 1; i < itemsTitles.count + 1; ++i) {
            items[i] = [[UIBarButtonItem alloc] initWithTitle:[itemsTitles objectAtIndex:i-1] style:UIBarButtonItemStyleBordered target:self action:@selector(editOperation:)];
            items[i].tag = i;
        }

        _editToolItems = [NSArray arrayWithObjects:items[EDITOP_COPY], items[EDITOP_MOVE], items[EDITOP_SPACE], items[EDITOP_DELETE], nil ];
    }
    return _editToolItems;
}

- (void)setConnection:(SeafConnection *)conn
{
    self.searchDisplayController.active = NO;
    [self.detailViewController setPreViewItem:nil master:nil];
    [conn loadRepos:self];
    [self setDirectory:(SeafDir *)conn.rootFolder];
}

- (void)showLodingView
{
    if (!self.loadingView) {
        self.loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        self.loadingView.color = [UIColor darkTextColor];
        self.loadingView.hidesWhenStopped = YES;
        [self.tableView addSubview:self.loadingView];
    }
    self.loadingView.center = self.view.center;
    self.loadingView.frame = CGRectMake(self.loadingView.frame.origin.x, (self.view.frame.size.height-self.loadingView.frame.size.height)/2, self.loadingView.frame.size.width, self.loadingView.frame.size.height);
    [self.loadingView startAnimating];
}

- (void)dismissLoadingView
{
    [self.loadingView stopAnimating];
}

- (void)awakeFromNib
{
    if (IsIpad()) {
        self.clearsSelectionOnViewWillAppear = NO;
        self.contentSizeForViewInPopover = CGSizeMake(320.0, 600.0);
    }
    [super awakeFromNib];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)])
        [self.tableView setSeparatorInset:UIEdgeInsetsMake(0, 0, 0, 0)];
    self.formatter = [[NSDateFormatter alloc] init];
    [self.formatter setDateFormat:@"yyyy-MM-dd HH.mm.ss"];
    self.tableView.rowHeight = 50;
    self.clearsSelectionOnViewWillAppear = YES;

    self.state = STATE_INIT;
    _refreshHeaderView = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.tableView.bounds.size.height, self.view.frame.size.width, self.tableView.bounds.size.height)];
    _refreshHeaderView.delegate = self;
    [_refreshHeaderView refreshLastUpdatedDate];
    [self.tableView addSubview:_refreshHeaderView];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    self.searchBar.searchTextPositionAdjustment = UIOffsetMake(0, 0);
    self.searchBar.placeholder = NSLocalizedString(@"Search", @"Seafile");
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
- (void)refreshView
{
    for (SeafUploadFile *file in _directory.uploadItems) {
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
}

- (void)viewDidUnload
{
    [self setLoadingView:nil];
    [super viewDidUnload];
    _refreshHeaderView = nil;
    _directory = nil;
    _curEntry = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
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
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (editing) {
        if (![appdelegate checkNetworkStatus]) return;
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
    if (![QBImagePickerController isAccessible]) {
        Warning("Error: Source is not accessible.");
        [self alertWithMessage:NSLocalizedString(@"Photos are not accessible", @"Seafile")];
        return;
    }
    QBImagePickerController *imagePickerController = [SeafFileViewController defaultQBImagePickerController];
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
    if (self.actionSheet) {
        [self.actionSheet dismissWithClickedButtonIndex:-1 animated:NO];
        self.actionSheet = nil;
    } else {
        NSString *cancelTitle = IsIpad() ? nil : NSLocalizedString(@"Cancel", @"Seafile");
        self.actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:cancelTitle destructiveButtonTitle:nil otherButtonTitles:S_NEWFILE, S_MKDIR, S_EDIT, nil];
        [self.actionSheet showFromBarButtonItem:self.editItem animated:YES];
    }
}

- (void)initNavigationItems:(SeafDir *)directory
{
    if (![directory isKindOfClass:[SeafRepos class]]) {
        if (directory.editable) {
            self.photoItem = [self getBarItem:@"plus".navItemImgName action:@selector(addPhotos:)size:20];
            self.doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(editDone:)];
            self.editItem = [self getBarItemAutoSize:@"ellipsis".navItemImgName action:@selector(editSheet:)];
            UIBarButtonItem *space = [self getSpaceBarItem:16.0];
            self.rightItems = [NSArray arrayWithObjects: self.editItem, space, self.photoItem, nil];
            self.navigationItem.rightBarButtonItems = self.rightItems;

            _selectAllItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Select All", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(selectAll:)];
            _selectNoneItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Select None", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(selectNone:)];
        }
    }
}

- (SeafDir *)directory
{
    return _directory;
}

- (void)setDirectory:(SeafDir *)directory
{
    if (!_directory)
        [self initNavigationItems:directory];

    _connection = directory->connection;
    _directory = directory;
    self.title = directory.name;
    [_directory setDelegate:self];
    [_directory loadContent:NO];
    Debug("%@, %@, loading ... %d\n", _directory.repoId, _directory.path, _directory.hasCache);
    if (![_directory isKindOfClass:[SeafRepos class]])
        self.tableView.sectionHeaderHeight = 0;
    [self refreshView];
}

- (void)viewWillAppear:(BOOL)animated
{
    if (!_directory.hasCache) {
        [self showLodingView];
        self.state = STATE_LOADING;
    }
    if (_directory.uploadItems.count > 0)
        Debug("Upload %lu, state=%d", (unsigned long)_directory.uploadItems.count, self.state);

    for (SeafUploadFile *file in _directory.uploadItems) {
        file.delegate = self;
        if (!file.uploaded && !file.uploading) {
            [SeafAppDelegate backgroundUpload:file];
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (IsIpad() && self.popoverController) {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController = nil;
    }
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

- (UITableViewCell *)getCell:(NSString *)CellIdentifier forTableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    return cell;
}

- (void)showEditFileMenu:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if (self.tableView.editing == YES)
        return;
    UIActionSheet *actionSheet;
    if (gestureRecognizer.state != UIGestureRecognizerStateBegan)
        return;
    CGPoint touchPoint = [gestureRecognizer locationInView:self.tableView];
    _selectedindex = [self.tableView indexPathForRowAtPoint:touchPoint];
    if (!_selectedindex)
        return;
    SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
    NSAssert([file isKindOfClass:[SeafFile class]], @"file must be SeafFile");

    NSString *cancelTitle = IsIpad() ? nil : NSLocalizedString(@"Cancel", @"Seafile");
    if (file.mpath)
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:cancelTitle destructiveButtonTitle:nil otherButtonTitles:S_DELETE, S_REDOWNLOAD, S_UPLOAD, S_SHARE_EMAIL, S_SHARE_LINK, nil];
    else
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:cancelTitle destructiveButtonTitle:nil otherButtonTitles:S_DELETE, S_REDOWNLOAD, S_RENAME, S_SHARE_EMAIL, S_SHARE_LINK, nil];

    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:_selectedindex];
    [actionSheet showFromRect:cell.frame inView:self.tableView animated:YES];
}

- (void)showEditDirMenu:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if (self.tableView.editing == YES)
        return;
    UIActionSheet *actionSheet;
    if (gestureRecognizer.state != UIGestureRecognizerStateBegan)
        return;
    CGPoint touchPoint = [gestureRecognizer locationInView:self.tableView];
    _selectedindex = [self.tableView indexPathForRowAtPoint:touchPoint];
    if (!_selectedindex)
        return;
    SeafDir *dir = (SeafDir *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
    NSAssert([dir isKindOfClass:[SeafDir class]], @"dir must be SeafDir");

    NSString *cancelTitle = IsIpad() ? nil : NSLocalizedString(@"Cancel", @"Seafile");
    actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:cancelTitle destructiveButtonTitle:nil otherButtonTitles:S_DELETE, S_RENAME, S_SHARE_EMAIL, S_SHARE_LINK, nil];

    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:_selectedindex];
    [actionSheet showFromRect:cell.frame inView:self.tableView animated:YES];
}

- (void)showEditUploadFileMenu:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if (self.tableView.editing || gestureRecognizer.state != UIGestureRecognizerStateBegan)
        return;
    CGPoint touchPoint = [gestureRecognizer locationInView:self.tableView];
    _selectedindex = [self.tableView indexPathForRowAtPoint:touchPoint];
    if (!_selectedindex)
        return;
    SeafUploadFile *file = (SeafUploadFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
    NSAssert([file isKindOfClass:[SeafUploadFile class]], @"file must be SeafFile");

    NSString *cancelTitle = IsIpad() ? nil : NSLocalizedString(@"Cancel", @"Seafile");
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:cancelTitle destructiveButtonTitle:nil otherButtonTitles:S_DELETE, nil];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:_selectedindex];
    [actionSheet showFromRect:cell.frame inView:self.tableView animated:YES];
}

- (UITableViewCell *)getSeafUploadFileCell:(SeafUploadFile *)file forTableView:(UITableView *)tableView
{
    file.delegate = self;
    UITableViewCell *c;
    if (file.uploading) {
        SeafUploadingFileCell *cell = (SeafUploadingFileCell *)[self getCell:@"SeafUploadingFileCell" forTableView:tableView];
        cell.nameLabel.text = file.name;
        cell.imageView.image = file.icon;
        [cell.progressView setProgress:file.uProgress * 1.0/100];
        c = cell;
    } else {
        SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
        cell.textLabel.text = file.name;
        cell.imageView.image = file.icon;
        cell.badgeLabel.text = nil;

        NSString *sizeStr = [FileSizeFormatter stringFromNumber:[NSNumber numberWithLongLong:file.filesize ] useBaseTen:NO];
        NSDictionary *dict = [file uploadAttr];
        cell.accessoryView = nil;
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
        c = cell;
    }
    if (tableView == self.tableView) {
        UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showEditUploadFileMenu:)];
        [c addGestureRecognizer:longPressGesture];
    }
    return c;
}

- (SeafCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
    cell.textLabel.text = sfile.name;
    cell.detailTextLabel.text = sfile.detailText;
    cell.imageView.image = sfile.icon;
    cell.badgeLabel.text = nil;
    if (tableView == self.tableView) {
        UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showEditFileMenu:)];
        [cell addGestureRecognizer:longPressGesture];
    }
    sfile.delegate = self;
    sfile.udelegate = self;
    return cell;
}

- (SeafCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafDirCell" forTableView:tableView];
    cell.textLabel.text = sdir.name;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = sdir.icon;
    sdir.delegate = self;
    if (tableView == self.tableView) {
        UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showEditDirMenu:)];
        [cell addGestureRecognizer:longPressGesture];
    }
    return cell;
}

- (SeafCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
    NSString *detail = [NSString stringWithFormat:@"%@, %@", [FileSizeFormatter stringFromNumber:[NSNumber numberWithUnsignedLongLong:srepo.size ] useBaseTen:NO], [SeafDateFormatter stringFromLongLong:srepo.mtime]];
    cell.detailTextLabel.text = detail;
    cell.imageView.image = srepo.icon;
    cell.textLabel.text = srepo.name;
    cell.badgeLabel.text = nil;
    srepo.delegate = self;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSObject *entry = [self getDentrybyIndexPath:indexPath tableView:tableView];
    if (tableView != self.tableView) {
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

- (void)popupSetRepoPassword
{
    self.state = STATE_PASSWORD;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:S_PASSWORD message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"Seafile") otherButtonTitles:NSLocalizedString(@"OK", @"Seafile"), nil];
    alert.alertViewStyle = UIAlertViewStyleSecureTextInput;
    [alert show];
}
- (void)popupInputView:(NSString *)title placeholder:(NSString *)tip
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"Seafile") otherButtonTitles:NSLocalizedString(@"OK", @"Seafile"), nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *textfield = [alert textFieldAtIndex:0];
    textfield.placeholder = tip;
    textfield.autocorrectionType = UITextAutocorrectionTypeNo;
    [alert show];
}
- (void)popupMkdirView
{
    self.state = STATE_MKDIR;
    [self popupInputView:S_MKDIR placeholder:NSLocalizedString(@"New folder name", @"Seafile")];
}
- (void)popupCreateView
{
    self.state = STATE_CREATE;
    [self popupInputView:S_NEWFILE placeholder:NSLocalizedString(@"New file name", @"Seafile")];
}
- (void)popupRenameView:(NSString *)newName
{
    self.state = STATE_RENAME;
    [self popupInputView:S_RENAME placeholder:newName];
}

- (void)popupDirChooseView:(id<SeafPreView>)file
{
    UIViewController *controller = nil;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (file)
        controller = [[SeafUploadDirViewController alloc] initWithSeafConnection:_connection uploadFile:file];
    else
        controller = [[SeafDirViewController alloc] initWithSeafDir:self.connection.rootFolder delegate:self chooseRepo:false];

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    [navController setModalPresentationStyle:UIModalPresentationFormSheet];
    [appdelegate.tabbarController presentViewController:navController animated:YES completion:nil];
    if (IsIpad()) {
        CGRect frame = navController.view.superview.frame;
        navController.view.superview.frame = CGRectMake(frame.origin.x+frame.size.width/2-320/2, frame.origin.y+frame.size.height/2-500/2, 320, 500);
    }
}

- (SeafBase *)getDentrybyIndexPath:(NSIndexPath *)indexPath tableView:(UITableView *)tableView
{
    if (!indexPath) return nil;
    if (tableView != self.tableView) {
        return [self.searchResults objectAtIndex:indexPath.row];
    } else if (![_directory isKindOfClass:[SeafRepos class]])
        return [_directory.allItems objectAtIndex:[indexPath row]];
    NSArray *repos = [[((SeafRepos *)_directory)repoGroups] objectAtIndex:[indexPath section]];
    return [repos objectAtIndex:[indexPath row]];
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
        [self noneSelected:NO];
        return;
    }
    _curEntry = [self getDentrybyIndexPath:indexPath tableView:tableView];
    [_curEntry setDelegate:self];
    if ([_curEntry isKindOfClass:[SeafRepo class]] && [(SeafRepo *)_curEntry passwordRequired]) {
        [self popupSetRepoPassword];
        return;
    }

    if ([_curEntry conformsToProtocol:@protocol(SeafPreView)]) {
        if (!IsIpad()) {
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate showDetailView:self.detailViewController];
        }
        NSMutableArray *arr = nil;
        if ([self isCurrentFileImage:&arr]) {
            [self.detailViewController setPreViewItems:arr current:_curEntry master:self];
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
        text = repo ? repo.owner: @"";
    }
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, tableView.bounds.size.width - 10, 18)];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor clearColor];
    [headerView setBackgroundColor:HEADER_COLOR];
    [headerView addSubview:label];
    return headerView;
}

#pragma mark - UIAlertViewDelegate
- (void)checkPassword:(NSString *)password
{
    [_curEntry setDelegate:self];
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Checking library password ...", @"Seafile")];
    if ([self.connection localDecrypt:[_curEntry repoId]])
        [_curEntry checkRepoPassword:password];
    else
        [_curEntry setRepoPassword:password];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) {
        self.state = STATE_INIT;
        return;
    } else {
        NSString *title = alertView.title;
        NSString *input = [alertView textFieldAtIndex:0].text;
        [_directory setDelegate:self];
        if ([title isEqualToString:S_PASSWORD]) {
            if (!input || input.length == 0) {
                [self alertWithMessage:NSLocalizedString(@"Password must not be empty", @"Seafile")];
                return;
            }
            if (input.length < 3 || input.length  > 100) {
                [self alertWithMessage:NSLocalizedString(@"The length of password should be between 3 and 100", @"Seafile")];
                return;
            }
            [self performSelector:@selector(checkPassword:) withObject:input afterDelay:0.0];
        } else if (self.state == STATE_MKDIR) {
            if (!input || input.length == 0) {
                [self alertWithMessage:NSLocalizedString(@"Folder name must not be empty", @"Seafile")];
                return;
            }
            if (![input isValidFileName]) {
                [self alertWithMessage:NSLocalizedString(@"Folder name invalid", @"Seafile")];
                return;
            }
            [_directory mkdir:input];
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Creating folder ...", @"Seafile")];
        } else if (self.state == STATE_RENAME) {
            if (!input || input.length == 0) {
                [self alertWithMessage:NSLocalizedString(@"File name must not be empty", @"Seafile")];
                return;
            }
            if (![input isValidFileName]) {
                [self alertWithMessage:NSLocalizedString(@"File name invalid", @"Seafile")];
                return;
            }
            [_directory renameFile:_curEntry newName:input];
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Renaming file ...", @"Seafile")];
        } else if (self.state == STATE_CREATE) {
            if (!input || input.length == 0) {
                [self alertWithMessage:NSLocalizedString(@"File name must not be empty", @"Seafile")];
                return;
            }
            if (![input isValidFileName]) {
                [self alertWithMessage:NSLocalizedString(@"File name invalid", @"Seafile")];
                return;
            }
            [_directory createFile:input];
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Creating file ...", @"Seafile")];
        }
    }
}

#pragma mark - SeafDentryDelegate
- (void)entry:(SeafBase *)entry updated:(BOOL)updated progress:(int)percent
{
    if (entry == _directory) {
        [self dismissLoadingView];
        [SVProgressHUD dismiss];
        [self doneLoadingTableViewData];
        [self refreshView];
    } else if ([entry isKindOfClass:[SeafFile class]]) {
        if (updated && entry == self.detailViewController.preViewItem)
            [self.detailViewController entry:entry updated:updated progress:percent];
    }
    self.state = STATE_INIT;
}

- (void)entry:(SeafBase *)entry downloadingFailed:(NSUInteger)errCode;
{
    if (errCode == HTTP_ERR_REPO_PASSWORD_REQUIRED) {
        NSAssert(0, @"Here should never be reached");
    }
    if ([entry isKindOfClass:[SeafFile class]]) {
        [self.detailViewController entry:entry downloadingFailed:errCode];
        return;
    }

    NSCAssert([entry isKindOfClass:[SeafDir class]], @"entry must be SeafDir");
    SeafDir *folder = (SeafDir *)entry;
    Debug("%@,%@, %@\n", folder.path, folder.repoId, _directory.path);
    if (entry == _directory) {
        [self doneLoadingTableViewData];
        switch (self.state) {
            case STATE_DELETE:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to delete files", @"Seafile")];
                break;
            case STATE_MKDIR:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to create folder", @"Seafile") duration:2.0];
                [self performSelector:@selector(popupMkdirView) withObject:nil afterDelay:1.0];
                break;
            case STATE_CREATE:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to create file", @"Seafile") duration:2.0];
                [self performSelector:@selector(popupCreateView) withObject:nil afterDelay:1.0];
                break;
            case STATE_COPY:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to copy files", @"Seafile") duration:2.0];
                break;
            case STATE_MOVE:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to move files", @"Seafile") duration:2.0];
                break;
            case STATE_RENAME: {
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to rename file", @"Seafile") duration:2.0];
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

- (void)entry:(SeafBase *)entry repoPasswordSet:(BOOL)success;
{
    if (entry != _curEntry)  return;

    NSAssert([entry isKindOfClass:[SeafRepo class]], @"entry must be a repo\n");
    [SVProgressHUD dismiss];
    if (success) {
        self.state = STATE_INIT;
        SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
        [self.navigationController pushViewController:controller animated:YES];
        [controller setDirectory:(SeafDir *)_curEntry];
    } else {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Wrong library password", @"Seafile") duration:2.0];
        [self performSelector:@selector(popupSetRepoPassword) withObject:nil afterDelay:1.0];
    }
}

- (void)doneLoadingTableViewData
{
    [_refreshHeaderView egoRefreshScrollViewDataSourceDidFinishedLoading:self.tableView];
}

#pragma mark - mark UIScrollViewDelegate Methods
- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (!self.searchDisplayController.active)
        [_refreshHeaderView egoRefreshScrollViewDidScroll:scrollView];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (!self.searchDisplayController.active)
        [_refreshHeaderView egoRefreshScrollViewDidEndDragging:scrollView];
}

#pragma mark - EGORefreshTableHeaderDelegate Methods
- (void)egoRefreshTableHeaderDidTriggerRefresh:(EGORefreshTableHeaderView*)view
{
    if (self.searchDisplayController.active)
        return;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (![appdelegate checkNetworkStatus]) {
        [self performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:0.1];
        return;
    }

    _directory.delegate = self;
    [_directory loadContent:YES];
}

- (BOOL)egoRefreshTableHeaderDataSourceIsLoading:(EGORefreshTableHeaderView*)view
{
    return [_directory state] == SEAF_DENTRY_LOADING;
}

- (NSDate*)egoRefreshTableHeaderDataSourceLastUpdated:(EGORefreshTableHeaderView*)view
{
    return [NSDate date];
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
    self.state = EDITOP_DELETE;
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting file ...", @"Seafile")];
    [_directory delEntries:entries];
}

- (void)deleteDir:(SeafDir *)dir
{
    NSArray *entries = [NSArray arrayWithObject:dir];
    self.state = EDITOP_DELETE;
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting directory ...", @"Seafile")];
    [_directory delEntries:entries];
}

- (void)redownloadFile:(SeafFile *)file
{
    [file deleteCache];
    [self.detailViewController setPreViewItem:nil master:nil];
    [self tableView:self.tableView didSelectRowAtIndexPath:_selectedindex];
}

- (void)renameFile:(SeafFile *)file
{
    _curEntry = file;
    [self popupRenameView:file.name];
}

#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    self.actionSheet = nil;
    if (buttonIndex < 0 || buttonIndex >= actionSheet.numberOfButtons)
        return;
    NSString *title = [actionSheet buttonTitleAtIndex:buttonIndex];
    if ([S_NEWFILE isEqualToString:title]) {
        [self popupCreateView];
    } else if ([S_MKDIR isEqualToString:title]) {
        [self popupMkdirView];
    } else if ([S_EDIT isEqualToString:title]) {
        [self editStart:nil];
    } else if ([S_DELETE isEqualToString:title]) {
        SeafBase *entry = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        if ([entry isKindOfClass:[SeafUploadFile class]]) {
            if (self.detailViewController.preViewItem == entry)
                self.detailViewController.preViewItem = nil;
            [self.directory removeUploadFile:(SeafUploadFile *)entry];
            [self.tableView reloadData];
        } else if ([entry isKindOfClass:[SeafFile class]])
            [self deleteFile:(SeafFile*)entry];
        else if ([entry isKindOfClass:[SeafDir class]])
            [self deleteDir: (SeafDir*)entry];{
        }
    } else if ([S_REDOWNLOAD isEqualToString:title]) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [self redownloadFile:file];
    } else if ([S_RENAME isEqualToString:title]) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [self renameFile:file];
    } else if ([S_UPLOAD isEqualToString:title]) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [file update:self];
        [self refreshView];
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
    }
}

- (void)backgroundUpload:(SeafUploadFile *)ufile
{
    [SeafAppDelegate backgroundUpload:ufile];
}

- (void)chooseUploadDir:(SeafDir *)dir file:(SeafUploadFile *)ufile replace:(BOOL)replace
{
    SeafUploadFile *uploadFile = (SeafUploadFile *)ufile;
    uploadFile.update = replace;
    [dir addUploadFile:uploadFile];
    [NSThread detachNewThreadSelector:@selector(backgroundUpload:) toTarget:self withObject:ufile];
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
    NSArray *idxs = [self.tableView indexPathsForSelectedRows];
    if (!idxs) return;
    NSMutableArray *entries = [[NSMutableArray alloc] init];
    for (NSIndexPath *indexPath in idxs) {
        [entries addObject:[_directory.allItems objectAtIndex:indexPath.row]];
    }
    Debug("_directory.delegate=%@", _directory.delegate);
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
- (BOOL)filenameExist:(NSString *)filename
{
    NSArray *arr = _directory.allItems;
    NSUInteger idx = [arr indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        NSString *name = nil;
        if ([obj conformsToProtocol:@protocol(SeafPreView)]) {
            name = ((id<SeafPreView>)obj).name;
        } else if ([obj isKindOfClass:[SeafBase class]]) {
            name = ((SeafBase *)obj).name;
        }
        if (name && [name isEqualToString:filename]) {
            *stop = true;
            return true;
        }
        return false;
    }];
    return (idx != NSNotFound);
}

- (void)uploadPickedAssets:(NSArray *)assets
{
    NSMutableArray *files = [[NSMutableArray alloc] init];
    NSMutableArray *paths = [[NSMutableArray alloc] init];
    NSString *path;
    NSString *date = [self.formatter stringFromDate:[NSDate date]];
    for (ALAsset *asset in assets) {
        NSString *filename = asset.defaultRepresentation.filename;
        if ([self filenameExist:filename]) {
            NSString *name = filename.stringByDeletingPathExtension;
            NSString *ext = filename.pathExtension;
            filename = [NSString stringWithFormat:@"%@-%@.%@", name, date, ext];
        }
        path = [[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"] stringByAppendingPathComponent:filename];
        [paths addObject:path];
        SeafUploadFile *file =  [self.connection getUploadfile:path];
        file.asset = asset;
        file.delegate = self;
        [files addObject:file];
        [self.directory addUploadFile:file];
    }
    [self.tableView reloadData];
    for (SeafUploadFile *file in files) {
        [SeafAppDelegate backgroundUpload:file];
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

- (void)imagePickerControllerDidCancel:(QBImagePickerController *)imagePickerController
{
    [self dismissImagePickerController:imagePickerController];
}

- (void)imagePickerController:(QBImagePickerController *)imagePickerController didSelectAsset:(ALAsset *)asset
{
    [self dismissImagePickerController:imagePickerController];
    [self performSelectorInBackground:@selector(uploadPickedAssets:) withObject:[NSArray arrayWithObject:asset]];

}

- (void)imagePickerController:(QBImagePickerController *)imagePickerController didSelectAssets:(NSArray *)assets
{
    [self dismissImagePickerController:imagePickerController];
    [self performSelectorInBackground:@selector(uploadPickedAssets:) withObject:assets];
}

#pragma mark - UIPopoverControllerDelegate
- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
    self.popoverController = nil;
}

#pragma mark - SeafFileUpdateDelegate
- (void)updateProgress:(SeafFile *)file result:(BOOL)res completeness:(int)percent
{
    long index = [_directory.allItems indexOfObject:file];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (res && file && [cell isKindOfClass:[SeafUploadingFileCell class]]) {
        [((SeafUploadingFileCell *)cell).progressView setProgress:percent*1.0f/100];
        return;
    }
    [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationAutomatic ];
}

#pragma mark - SeafUploadDelegate
- (void)uploadProgress:(SeafUploadFile *)file result:(BOOL)res progress:(int)percent
{
    long index = [_directory.allItems indexOfObject:file];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (res && percent < 100 && [cell isKindOfClass:[SeafUploadingFileCell class]])
        [((SeafUploadingFileCell *)cell).progressView setProgress:percent*1.0f/100];
    else {
        [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)uploadSucess:(SeafUploadFile *)file oid:(NSString *)oid
{
    [self uploadProgress:file result:YES progress:100];
    if (!self.isVisible) {
        [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:NSLocalizedString(@"File '%@' uploaded success", @"Seafile"), file.name] duration:1.0];
    }

}

#pragma mark - Search Delegate
#define SEARCH_STATE_INIT NSLocalizedString(@"Click \"Search\" to start", @"Seafile")
#define SEARCH_STATE_SEARCHING NSLocalizedString(@"Searching", @"Seafile")
#define SEARCH_STATE_NORESULTS NSLocalizedString(@"No Results", @"Seafile")

- (void)setSearchState:(UISearchDisplayController *)controller state:(NSString *)state
{
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.001);
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
        self.tableView.sectionHeaderHeight = 22;
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

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    Debug("search %@", searchBar.text);
    [self setSearchState:self.searchDisplayController state:SEARCH_STATE_SEARCHING];
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Searching ...", @"Seafile")];
    [_connection search:searchBar.text success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSMutableArray *results) {
        [SVProgressHUD dismiss];
        if (results.count == 0)
            [self setSearchState:self.searchDisplayController state:SEARCH_STATE_NORESULTS];
        else {
            self.searchResults = results;
            [self.searchDisplayController.searchResultsTableView reloadData];
        }
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        if (response.statusCode == 404) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Search is not supported on the server", @"Seafile")];
        } else
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to search", @"Seafile")];
    }];
}

+(QBImagePickerController *)defaultQBImagePickerController{
    static dispatch_once_t pred = 0;
    static QBImagePickerController *c = nil;
    dispatch_once(&pred, ^{
        c = [[QBImagePickerController alloc] init];
    });
    return c;
}

- (void)photoSelectedChanged:(id<SeafPreView>)from to:(id<SeafPreView>)to;
{
    int index = [_directory.allItems indexOfObject:to];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];

    [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionMiddle];
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
        [self alertWithMessage:NSLocalizedString(@"This function is not supportted yet，you can copy it to the pasteboard and send mail by yourself", @"Seafile")];
        return;
    }
    if (![mailClass canSendMail]) {
        [self alertWithMessage:NSLocalizedString(@"The mail account has not been set yet", @"Seafile")];
        return;
    }

    MFMailComposeViewController *mailPicker = [[MFMailComposeViewController alloc] init];
    mailPicker.mailComposeDelegate = self;
    NSString *emailSubject, *emailBody;
    if ([entry isKindOfClass:[SeafFile class]]) {
        emailSubject = [NSString stringWithFormat:NSLocalizedString(@"File '%@' is shared with you using seafile", @"Seafile"), entry.name];
        emailBody = [NSString stringWithFormat:NSLocalizedString(@"Hi,<br/><br/>Here is a link to <b>'%@'</b> in my Seafile:<br/><br/> <a href=\"%@\">%@</a>\n\n", @"Seafile"), entry.name, entry.shareLink, entry.shareLink];
    } else {
        emailSubject = [NSString stringWithFormat:NSLocalizedString(@"Directory '%@' is shared with you using seafile", @"Seafile"), entry.name];
        emailBody = [NSString stringWithFormat:NSLocalizedString(@"Hi,<br/><br/>Here is a link to directory <b>'%@'</b> in my Seafile:<br/><br/> <a href=\"%@\">%@</a>\n\n", @"Seafile"), entry.name, entry.shareLink, entry.shareLink];
    }
    [mailPicker setSubject:emailSubject];
    [mailPicker setMessageBody:emailBody isHTML:YES];
    [self presentViewController:mailPicker animated:YES completion:nil];
}

#pragma mark - MFMailComposeViewControllerDelegate
- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
    [self dismissViewControllerAnimated:YES completion:nil];
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
}
@end
