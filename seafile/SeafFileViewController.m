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
};

@interface SeafFileViewController ()<QBImagePickerControllerDelegate, UIPopoverControllerDelegate, SeafUploadDelegate, EGORefreshTableHeaderDelegate>
- (UITableViewCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView;
- (UITableViewCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView;
- (UITableViewCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView;

@property (strong, nonatomic) SeafDir *directory;
@property (strong) id curEntry;
@property (strong) InputAlertPrompt *passSetView;
@property (strong) InputAlertPrompt *inputView;
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

@property int state;

@property(nonatomic,strong) UIPopoverController *popoverController;
@property (retain) NSDateFormatter *formatter;

@end

@implementation SeafFileViewController

@synthesize connection = _connection;
@synthesize directory = _directory;
@synthesize curEntry = _curEntry;
@synthesize passSetView = _passSetView, inputView = _inputView;
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

        NSArray *itemsTitles = [NSArray arrayWithObjects:@"New Folder", @"New File", @"Copy", @"Move", @"Delete", @"Paste", @"MoveTo", @"Cancel", nil ];

        UIBarButtonItem *items[EDITOP_NUM];
        items[0] = flexibleFpaceItem;

        fixedSpaceItem.width = 38.0f;;
        for (i = 1; i < itemsTitles.count + 1; ++i) {
            items[i] = [[UIBarButtonItem alloc] initWithTitle:[itemsTitles objectAtIndex:i-1] style:UIBarButtonItemStyleBordered target:self action:@selector(editOperation:)];
            items[i].tag = i;
        }

        _editToolItems = [NSArray arrayWithObjects:items[EDITOP_CREATE], items[EDITOP_MKDIR], items[EDITOP_SPACE], items[EDITOP_DELETE], nil ];
    }
    return _editToolItems;
}

- (void)setConnection:(SeafConnection *)conn
{
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
    self.formatter = [[NSDateFormatter alloc] init];
    [self.formatter setDateFormat:@"yyyy-MM-dd HH.mm.ss"];
    self.tableView.rowHeight = 50;
    self.clearsSelectionOnViewWillAppear = YES;

    self.state = STATE_INIT;
    if (_refreshHeaderView == nil) {
        EGORefreshTableHeaderView *view = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.tableView.bounds.size.height, self.view.frame.size.width, self.tableView.bounds.size.height)];
        view.delegate = self;
        [self.tableView addSubview:view];
        _refreshHeaderView = view;
    }
    [_refreshHeaderView refreshLastUpdatedDate];
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
}

- (void)noneSelected:(BOOL)none
{
    if (none) {
        self.navigationItem.leftBarButtonItem = _selectAllItem;
        NSArray *items = self.toolbarItems;
        [[items objectAtIndex:0] setEnabled:YES];
        [[items objectAtIndex:1] setEnabled:YES];
        [[items objectAtIndex:3] setEnabled:NO];
    } else {
        self.navigationItem.leftBarButtonItem = _selectNoneItem;
        NSArray *items = self.toolbarItems;
        [[items objectAtIndex:0] setEnabled:NO];
        [[items objectAtIndex:1] setEnabled:NO];
        [[items objectAtIndex:3] setEnabled:YES];
    }
}

- (void)refreshView
{
    [self.tableView reloadData];
    if (IsIpad() && self.detailViewController.preViewItem && [self.detailViewController.preViewItem isKindOfClass:[SeafFile class]]) {
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
    int count = _directory.allItems.count;
    for (row = 0; row < count; ++row) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        NSObject *entry  = [self getDentrybyIndexPath:indexPath];
        if (![entry isKindOfClass:[SeafUploadFile class]])
            [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
    }
    [self noneSelected:NO];
}

- (void)selectNone:(id)sender
{
    int count = _directory.allItems.count;
    for (int row = 0; row < count; ++row) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
    [self noneSelected:YES];
}

- (void)hideTabBar
{
    if (self.tabBarController.tabBar.hidden == YES) {
        return;
    }
    UIView *contentView;
    if ( [[self.tabBarController.view.subviews objectAtIndex:0] isKindOfClass:[UITabBar class]] )
        contentView = [self.tabBarController.view.subviews objectAtIndex:1];
    else
        contentView = [self.tabBarController.view.subviews objectAtIndex:0];
    contentView.frame = CGRectMake(contentView.bounds.origin.x,  contentView.bounds.origin.y,  contentView.bounds.size.width, contentView.bounds.size.height + self.tabBarController.tabBar.frame.size.height);
    self.tabBarController.tabBar.hidden = YES;
}

- (void)showTabBar
{
    if (self.tabBarController.tabBar.hidden == NO) {
        return;
    }
    UIView *contentView;
    if ([[self.tabBarController.view.subviews objectAtIndex:0] isKindOfClass:[UITabBar class]])
        contentView = [self.tabBarController.view.subviews objectAtIndex:1];
    else
        contentView = [self.tabBarController.view.subviews objectAtIndex:0];
    contentView.frame = CGRectMake(contentView.bounds.origin.x, contentView.bounds.origin.y,  contentView.bounds.size.width, contentView.bounds.size.height - self.tabBarController.tabBar.frame.size.height);
    self.tabBarController.tabBar.hidden = NO;
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (editing) {
        if (![appdelegate checkNetworkStatus]) return;
        [self setToolbarItems:self.editToolItems];
        if(!IsIpad())  [self hideTabBar];
        [self.navigationController.toolbar sizeToFit];
        [self noneSelected:YES];
        [self.photoItem setEnabled:NO];
        [self.navigationController setToolbarHidden:NO animated:YES];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
        [self.navigationController setToolbarHidden:YES animated:YES];
        if(!IsIpad())  [self showTabBar];
        [self.photoItem setEnabled:YES];
    }

    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
}

- (void)addPhotos:(id)sender
{
    if(self.popoverController)
        return;
    QBImagePickerController *imagePickerController = [[QBImagePickerController alloc] init];
    imagePickerController.delegate = self;
    imagePickerController.allowsMultipleSelection = YES;
    imagePickerController.maximumNumberOfSelection = 20;
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
    [self setEditing:NO animated:NO];
    self.navigationItem.rightBarButtonItem = nil;
    self.navigationItem.rightBarButtonItems = self.rightItems;
}

- (void)editStart:(id)sender
{
    [self setEditing:YES animated:NO];
    if (self.editing) {
        self.navigationItem.rightBarButtonItems = nil;
        self.navigationItem.rightBarButtonItem = self.doneItem;
        if (IsIpad() && self.popoverController) {
            [self.popoverController dismissPopoverAnimated:YES];
            self.popoverController = nil;
        }
    }
}

- (void)initNavigationItems:(SeafDir *)directory
{
    if ([directory isKindOfClass:[SeafRepos class]]) {
    } else {
        if (directory.editable) {
            self.photoItem = [self getBarItem:@"plus.png" action:@selector(addPhotos:)size:20];
            self.doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(editDone:)];
            self.editItem = [self getBarItemAutoSize:@"checkmask.png" action:@selector(editStart:)];
            UIBarButtonItem *space = [self getSpaceBarItem:16.0];
            self.rightItems = [NSArray arrayWithObjects: self.editItem, space, self.photoItem, nil];
            self.navigationItem.rightBarButtonItems = self.rightItems;

            _selectAllItem = [[UIBarButtonItem alloc] initWithTitle:@"Select All" style:UIBarButtonItemStylePlain target:self action:@selector(selectAll:)];
            _selectNoneItem = [[UIBarButtonItem alloc] initWithTitle:@"Select None" style:UIBarButtonItemStylePlain target:self action:@selector(selectNone:)];
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
    Debug("%@, loading ... %d\n", _directory.path, _directory.hasCache);
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
}

#pragma mark - Table View

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
        return _directory.allItems.count;
    }
    NSArray *repos =  [[((SeafRepos *)_directory)repoGroups] objectAtIndex:section];
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
    SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex];
    if ([file isKindOfClass:[SeafUploadFile class]])
        return;
    if (![file hasCache])
        return;
    NSString *cancelTitle = nil;
    if (!IsIpad())
        cancelTitle = @"Cancel";
    if (file.mpath)
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:cancelTitle destructiveButtonTitle:nil otherButtonTitles:@"Delete", @"Redownload", @"Upload", nil];
    else
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Delete", @"Redownload", nil];

    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:_selectedindex];
    [actionSheet showFromRect:cell.frame inView:self.tableView animated:YES];
}

- (void)showEditUploadFileMenu:(UILongPressGestureRecognizer *)gestureRecognizer
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
    SeafUploadFile *file = (SeafUploadFile *)[self getDentrybyIndexPath:_selectedindex];
    if (![file isKindOfClass:[SeafUploadFile class]])
        return;

    NSString *cancelTitle = nil;
    if (!IsIpad())
        cancelTitle = @"Cancel";
    actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:cancelTitle destructiveButtonTitle:nil otherButtonTitles:@"Delete", nil];
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
        cell.imageView.image = file.image;
        [cell.progressView setProgress:file.uploadProgress *1.0/100];
        c = cell;
    } else {
        SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
        cell.textLabel.text = file.name;
        cell.imageView.image = file.image;
        cell.accLabel.text = nil;

        NSString *sizeStr = [FileSizeFormatter stringFromNumber:[NSNumber numberWithInt:file.filesize ] useBaseTen:NO];
        NSDictionary *dict = [file uploadAttr];
        cell.accessoryView = nil;
        if (dict) {
            int utime = [[dict objectForKey:@"utime"] intValue];
            BOOL result = [[dict objectForKey:@"result"] boolValue];
            if (result)
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@, Uploaded %@", sizeStr, [SeafDateFormatter stringFromInt:utime]];
            else {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@, waiting to upload", sizeStr];
            }
        } else {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@, waiting to upload", sizeStr];
        }
        c = cell;
    }
    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showEditUploadFileMenu:)];
    [c addGestureRecognizer:longPressGesture];
    return c;
}

- (SeafCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
    cell.textLabel.text = sfile.name;
    cell.detailTextLabel.text = sfile.detailText;
    cell.imageView.image = sfile.image;
    cell.accLabel.text = nil;
    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showEditFileMenu:)];
    [cell addGestureRecognizer:longPressGesture];
    sfile.delegate = self;
    return cell;
}

- (SeafCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafDirCell" forTableView:tableView];
    cell.textLabel.text = sdir.name;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = sdir.image;
    sdir.delegate = self;
    return cell;
}

- (SeafCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
    NSString *detail = [NSString stringWithFormat:@"%@, %@", [FileSizeFormatter stringFromNumber:[NSNumber numberWithUnsignedLongLong:srepo.size ] useBaseTen:NO], [SeafDateFormatter stringFromInt:srepo.mtime]];
    cell.detailTextLabel.text = detail;
    cell.imageView.image = srepo.image;
    cell.textLabel.text = srepo.name;
    cell.accLabel.text = nil;
    srepo.delegate = self;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSObject *entry  = [self getDentrybyIndexPath:indexPath];
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
    NSObject *entry  = [self getDentrybyIndexPath:indexPath];
    if (tableView.editing && [entry isKindOfClass:[SeafUploadFile class]])
        return nil;
    return indexPath;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSObject *entry  = [self getDentrybyIndexPath:indexPath];
    if ([entry isKindOfClass:[SeafUploadFile class]])
        return NO;
    return YES;
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
    _passSetView = [[InputAlertPrompt alloc] initWithTitle:@"Password of this library" delegate:self autoDismiss:NO];
    _passSetView.inputTextField.secureTextEntry = YES;
    _passSetView.inputTextField.placeholder = @"Password";
    _passSetView.inputTextField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _passSetView.inputTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _passSetView.inputTextField.returnKeyType = UIReturnKeyDone;
    _passSetView.inputTextField.keyboardType = UIKeyboardTypeASCIICapable;
    _passSetView.inputTextField.autocorrectionType = UITextAutocapitalizationTypeNone;
    _passSetView.inputDoneDelegate = self;
    [_passSetView show];
}

- (SeafBase *)getDentrybyIndexPath:(NSIndexPath *)indexPath
{
    if (![_directory isKindOfClass:[SeafRepos class]]) {
        return [_directory.allItems objectAtIndex:[indexPath row]];
    }
    NSArray *repos = [[((SeafRepos *)_directory)repoGroups] objectAtIndex:[indexPath section]];
    return [repos objectAtIndex:[indexPath row]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.navigationController.topViewController != self)
        return;
    _selectedindex = indexPath;
    if (tableView.editing == YES) {
        [self noneSelected:NO];
        return;
    }
    _curEntry = [self getDentrybyIndexPath:indexPath];
    [_curEntry setDelegate:self];
    if ([_curEntry isKindOfClass:[SeafRepo class]] && [(SeafRepo *)_curEntry passwordRequired]) {
        [self popupSetRepoPassword];
        return;
    }

    if ([_curEntry isKindOfClass:[SeafFile class]] || [_curEntry isKindOfClass:[SeafUploadFile class]]) {
        if (!IsIpad()) {
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate showDetailView:self.detailViewController];
        }
        id<QLPreviewItem, PreViewDelegate> item = (id<QLPreviewItem, PreViewDelegate>)_curEntry;
        [self.detailViewController setPreViewItem:item master:self];
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
    if (![_directory isKindOfClass:[SeafRepos class]]) {
        return nil;
    }
    NSString *text = nil;
    if (section == 0) {
        text = @"My Own Libraries";
    } else {
        NSArray *repos =  [[((SeafRepos *)_directory)repoGroups] objectAtIndex:section];
        SeafRepo *repo = (SeafRepo *)[repos objectAtIndex:0];
        if (!repo)
            text =  @"";
        else
            text =  repo.owner;
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

#pragma mark - InputDoneDelegate
- (BOOL)inputDone:(InputAlertPrompt *)alertView input:(NSString *)input errmsg:(NSString **)errmsg;
{
    if (alertView == _passSetView) {
        if (!input) {
            *errmsg = @"Password must not be empty";
            return NO;
        }
        if (input.length < 3 || input.length  > 100) {
            *errmsg = @"The length of password should be between 3 and 100";
            return NO;
        }
        [_curEntry setDelegate:self];
        [_curEntry setRepoPassword:input];
        [_passSetView.inputTextField setEnabled:NO];
        return YES;
    } else if (alertView == _inputView) {
        [_directory setDelegate:self];

        if (self.state == STATE_MKDIR) {
            if (!input) {
                *errmsg = @"Folder name must not be empty";
                return NO;
            }
            if (![input isValidFileName]) {
                *errmsg = @"Folder name invalid";
                return NO;
            }
            [_directory mkdir:input];
            [_inputView.inputTextField setEnabled:NO];
            [SVProgressHUD showWithStatus:@"Creating folder ..."];
        } else {
            if (!input) {
                *errmsg = @"File name must not be empty";
                return NO;
            }
            if (![input isValidFileName]) {
                *errmsg = @"File name invalid";
                return NO;
            }
            [_directory createFile:input];
            [_inputView.inputTextField setEnabled:NO];
            [SVProgressHUD showWithStatus:@"Creating file ..."];
        }
        return YES;
    }
    return NO;
}

#pragma mark - UIAlertViewDelegate
- (void)didPresentAlertView:(UIAlertView *)alertView
{
    if ([alertView isKindOfClass:[InputAlertPrompt class]]) {
    }
}

- (void)alertView:(UIAlertView *)alertView willDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if ([alertView isKindOfClass:[InputAlertPrompt class]]) {
        if (_passSetView == alertView) {
            _passSetView = nil;
        } else if (_inputView == alertView) {
            _inputView = nil;
        }
    }
}

#pragma mark - SeafDentryDelegate
- (void)entryChanged:(SeafBase *)entry
{
    if ([entry isKindOfClass:[SeafFile class]] && entry == self.detailViewController.preViewItem)
        [self.detailViewController entryChanged:entry];
}
- (void)entry:(SeafBase *)entry contentUpdated:(BOOL)updated completeness:(int)percent
{
    if (entry == _directory) {
        [self dismissLoadingView];
        [SVProgressHUD dismiss];
        [self doneLoadingTableViewData];
        [self refreshView];
        if (_inputView) {
            [_inputView dismissWithClickedButtonIndex:0 animated:YES];
        }
    } else if ([entry isKindOfClass:[SeafFile class]]) {
        if (updated && entry == self.detailViewController.preViewItem)
            [self.detailViewController entry:entry contentUpdated:updated completeness:percent];
    }
    self.state = STATE_INIT;
}

- (void)entryContentLoadingFailed:(int)errCode entry:(SeafBase *)entry;
{
    if (errCode == HTTP_ERR_REPO_PASSWORD_REQUIRED) {
        NSAssert(0, @"Here should never be reached");
    }
    if ([entry isKindOfClass:[SeafFile class]]) {
        [self.detailViewController entryContentLoadingFailed:errCode entry:entry];
        return;
    }

    NSCAssert([entry isKindOfClass:[SeafDir class]], @"entry must be SeafDir");
    SeafDir *folder = (SeafDir *)entry;
    Debug("%@,%@, %@\n", folder.path, folder.repoId, _directory.path);
    if (entry == _directory) {
        [self doneLoadingTableViewData];
        switch (self.state) {
            case STATE_DELETE:
                [SVProgressHUD showErrorWithStatus:@"Failed to delete files"];
                break;
            case STATE_MKDIR:
                [SVProgressHUD showErrorWithStatus:@"Failed to create folder"];
                [_inputView.inputTextField setEnabled:YES];
                break;
            case STATE_CREATE:
                [SVProgressHUD showErrorWithStatus:@"Failed to create file"];
                [_inputView.inputTextField setEnabled:YES];
                break;
            case STATE_LOADING:
                if (!_directory.hasCache) {
                    [self dismissLoadingView];
                    [SVProgressHUD showErrorWithStatus:@"Failed to load files"];
                } else
                    [SVProgressHUD dismiss];
                break;
            default:
                break;
        }
        self.state = STATE_INIT;
    }
}

- (void)repoPasswordSet:(SeafBase *)entry WithResult:(BOOL)success;
{
    if (entry != _curEntry) {
        return;
    }
    NSAssert([entry isKindOfClass:[SeafRepo class]], @"entry must be a repo\n");
    if (success) {
        [self.passSetView dismissWithClickedButtonIndex:0 animated:YES];
        SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
        [self.navigationController pushViewController:controller animated:YES];
        [controller setDirectory:(SeafDir *)_curEntry];
    } else {
        [self alertWithMessage:@"Wrong library password"];
        [_passSetView.inputTextField setEnabled:YES];
    }
}

- (void)doneLoadingTableViewData
{
    [_refreshHeaderView egoRefreshScrollViewDataSourceDidFinishedLoading:self.tableView];
}

#pragma mark - mark UIScrollViewDelegate Methods
- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [_refreshHeaderView egoRefreshScrollViewDidScroll:scrollView];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    [_refreshHeaderView egoRefreshScrollViewDidEndDragging:scrollView];
}

#pragma mark - EGORefreshTableHeaderDelegate Methods
- (void)egoRefreshTableHeaderDidTriggerRefresh:(EGORefreshTableHeaderView*)view
{
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

- (void)popupInputView:(NSString *)title placeholder:(NSString *)tip
{
    _inputView = [[InputAlertPrompt alloc] initWithTitle:title delegate:self autoDismiss:NO];
    _inputView.inputTextField.placeholder = tip;
    _inputView.inputTextField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _inputView.inputTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _inputView.inputTextField.returnKeyType = UIReturnKeyDone;
    _inputView.inputTextField.autocorrectionType = UITextAutocapitalizationTypeNone;
    _inputView.inputDoneDelegate = self;
    [_inputView show];
}

- (void)editOperation:(id)sender
{
    NSArray *idxs;
    NSMutableArray *entries;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];

    if (self != appdelegate.fileVC) {
        return [appdelegate.fileVC editOperation:sender];
    }
    switch ([sender tag]) {
        case EDITOP_MKDIR:
            self.state = STATE_MKDIR;
            [self popupInputView:@"New folder" placeholder:@"New folder name"];
            break;

        case EDITOP_CREATE:
            self.state = STATE_CREATE;
            [self popupInputView:@"New file" placeholder:@"New file name"];
            break;

        case EDITOP_DELETE:
            idxs = [self.tableView indexPathsForSelectedRows];
            if (!idxs) {
                return;
            }
            self.state = STATE_DELETE;
            entries = [[NSMutableArray alloc] init];
            for (NSIndexPath *indexPath in idxs) {
                [entries addObject:[_directory.allItems objectAtIndex:indexPath.row]];
            }
            [_directory delEntries:entries];
            [SVProgressHUD showWithStatus:@"Deleting files ..."];
        default:
            break;
    }
}

- (void)deleteFile:(SeafFile *)file
{
    NSArray *entries = [NSArray arrayWithObject:file];
    self.state = EDITOP_DELETE;
    [SVProgressHUD showWithStatus:@"Deleting file ..."];
    [_directory delEntries:entries];
}

- (void)redownloadFile:(SeafFile *)file
{
    [file deleteCache];
    [self.detailViewController setPreViewItem:nil master:nil];
    [self tableView:self.tableView didSelectRowAtIndexPath:_selectedindex];
}

#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex];
    if (buttonIndex == 0) {
        if ([file isKindOfClass:[SeafUploadFile class]]) {
            if (self.detailViewController.preViewItem == file)
                self.detailViewController.preViewItem = nil;
            [self.directory removeUploadFile:(SeafUploadFile *)file];
            [self.tableView reloadData];
        } else
            [self deleteFile:file];
    } else if (buttonIndex == 1) {
        [self redownloadFile:file];
    } else if (buttonIndex == 2)  {
        [file update:self];
        [self refreshView];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    for (SeafUploadFile *file in _directory.uploadItems)
        if (!file.uploaded && !file.uploading)
         [file upload:_connection repo:_directory.repoId path:_directory.path update:NO];
}

- (void)backgroundUpload:(SeafUploadFile *)ufile
{
    [ufile upload:ufile.udir->connection repo:ufile.udir.repoId path:ufile.udir.path update:NO];
}

- (void)chooseUploadDir:(SeafDir *)dir file:(SeafUploadFile *)ufile
{
    [dir addUploadFiles:[NSArray arrayWithObject:ufile]];
    [NSThread detachNewThreadSelector:@selector(backgroundUpload:) toTarget:self withObject:ufile];
}

- (void)uploadFile:(SeafUploadFile *)file
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    file.delegate = self;
    SeafUploadDirViewController *controller = [[SeafUploadDirViewController alloc] initWithSeafConnection:_connection uploadFile:file];

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    [navController setModalPresentationStyle:UIModalPresentationFormSheet];
    [appdelegate.tabbarController presentViewController:navController animated:YES completion:nil];
    if (IsIpad()) {
        CGRect frame = navController.view.superview.frame;
        navController.view.superview.frame = CGRectMake(frame.origin.x+frame.size.width/2-320/2, frame.origin.y+frame.size.height/2-500/2, 320, 500);
    }
}

#pragma mark - QBImagePickerControllerDelegate
- (void)imagePickerController:(QBImagePickerController *)imagePickerController didFinishPickingMediaWithInfo:(id)info
{
    if (IsIpad()) {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController = nil;
    } else {
        [imagePickerController.navigationController dismissViewControllerAnimated:YES completion:NULL];
    }

    NSMutableArray *files = [[NSMutableArray alloc] init];
    if (imagePickerController.allowsMultipleSelection) {
        int i = 0;
        NSString *date = [self.formatter stringFromDate:[NSDate date]];
        for (NSDictionary *dict in info) {
            i++;
            UIImage *image = [dict objectForKey:@"UIImagePickerControllerOriginalImage"];
            NSString *filename = [NSString stringWithFormat:@"Photo %@-%d.jpg", date, i];
            NSString *path = [[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"] stringByAppendingPathComponent:filename];
            [UIImageJPEGRepresentation(image, 1.0) writeToFile:path atomically:YES];
            SeafUploadFile *file =  [self.connection getUploadfile:path];
            file.delegate = self;
            [files addObject:file];
        }
    }
    [self.directory addUploadFiles:files];
    [self.tableView reloadData];
    for (SeafUploadFile *file in files) {
        [file upload:_connection repo:self.directory.repoId path:self.directory.path update:NO];
    }
}

- (void)imagePickerControllerDidCancel:(QBImagePickerController *)imagePickerController
{
    if (IsIpad()) {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController = nil;
    } else {
        [imagePickerController.navigationController dismissViewControllerAnimated:YES completion:NULL];
    }
}

- (NSString *)descriptionForSelectingAllAssets:(QBImagePickerController *)imagePickerController
{
    return @"Select all photos";
}

- (NSString *)descriptionForDeselectingAllAssets:(QBImagePickerController *)imagePickerController
{
    return @"Deselect all photos";
}

- (NSString *)imagePickerController:(QBImagePickerController *)imagePickerController descriptionForNumberOfPhotos:(NSUInteger)numberOfPhotos
{
    return [NSString stringWithFormat:@"%d photos", numberOfPhotos];
}

- (NSString *)imagePickerController:(QBImagePickerController *)imagePickerController descriptionForNumberOfVideos:(NSUInteger)numberOfVideos
{
    return [NSString stringWithFormat:@"%d videos", numberOfVideos];
}

- (NSString *)imagePickerController:(QBImagePickerController *)imagePickerController descriptionForNumberOfPhotos:(NSUInteger)numberOfPhotos numberOfVideos:(NSUInteger)numberOfVideos
{
    return [NSString stringWithFormat:@"%d photos、%d videos", numberOfPhotos, numberOfVideos];
}

#pragma mark - UIPopoverControllerDelegate
- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
    self.popoverController = nil;
}

#pragma mark - SeafFileUploadDelegate
- (void)updateProgress:(SeafFile *)file result:(BOOL)res completeness:(int)percent
{
    int index = [_directory.allItems indexOfObject:file];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (res && file && [cell isKindOfClass:[SeafUploadingFileCell class]]) {
        [((SeafUploadingFileCell *)cell).progressView setProgress:percent*1.0f/100];
        return;
    }
    [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationAutomatic ];
}

#pragma mark - SeafUploadDelegate
- (void)uploadProgress:(SeafUploadFile *)file result:(BOOL)res completeness:(int)percent
{
    int index = [_directory.allItems indexOfObject:file];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (res && percent < 100 && [cell isKindOfClass:[SeafUploadingFileCell class]])
        [((SeafUploadingFileCell *)cell).progressView setProgress:percent];
    else
        [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (id<QLPreviewItem, PreViewDelegate>)nextItem:(id<QLPreviewItem, PreViewDelegate>)cur next:(BOOL)next
{
    id<QLPreviewItem, PreViewDelegate> n = nil;
    int count = _directory.allItems.count;
    int idx = [_directory.allItems indexOfObject:cur];
    if (idx == NSNotFound)
        return nil;
    int nidx = -1;

    if (next) {
        for (int i = idx+1; i < count; ++i)
            if ([Utils isImageFile:[[_directory.allItems objectAtIndex:i] name]]) {
                nidx = i;
                break;
            }
    } else {
        for (int i = idx-1; i >=  0; --i)
            if ([Utils isImageFile:[[_directory.allItems objectAtIndex:i] name]]) {
                nidx = i;
                break;
            }
    }
    if (nidx >= 0) {
        n = [_directory.allItems objectAtIndex:nidx];
        if ([n isKindOfClass:[SeafFile class]])
            ((SeafFile *)n).delegate = self;
        NSIndexPath *ip = [NSIndexPath indexPathForRow:nidx inSection:0];
        [self.tableView selectRowAtIndexPath:ip animated:YES scrollPosition:UITableViewScrollPositionBottom];
    }
    return n;
}

@end
