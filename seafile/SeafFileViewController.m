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
#import "UIViewController+AlertMessage.h"
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

@interface SeafFileViewController ()<QBImagePickerControllerDelegate, UIPopoverControllerDelegate, SeafUploadDelegate>
- (UITableViewCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView;
- (UITableViewCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView;
- (UITableViewCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView;

@property (strong, nonatomic) SeafDir *directory;
@property (strong) SeafBase *curEntry;
@property (strong) InputAlertPrompt *passSetView;
@property (strong) InputAlertPrompt *inputView;

@property (strong) UIBarButtonItem *selectAllItem;
@property (strong) UIBarButtonItem *selectNoneItem;
@property (strong) UIBarButtonItem *backItem;
@property (strong) UIBarButtonItem *photoItem;

@property (strong, readonly) UIView *overlayView;

@property (retain) NSIndexPath *selectedindex;
@property (readonly) NSArray *editToolItems;

@property int state;

@property(nonatomic,strong) UIPopoverController *popoverController;
@property (retain) NSDateFormatter *formatter;
@property (retain) SeafUploadFile *ufile;

@end

@implementation SeafFileViewController

@synthesize connection = _connection;
@synthesize directory = _directory;
@synthesize curEntry = _curEntry;
@synthesize passSetView = _passSetView, inputView = _inputView;
@synthesize selectAllItem = _selectAllItem, selectNoneItem = _selectNoneItem;
@synthesize selectedindex = _selectedindex;
@synthesize editToolItems = _editToolItems;
@synthesize state;
@synthesize photoItem;

@synthesize popoverController;
@synthesize formatter;
@synthesize overlayView = _overlayView;
@synthesize ufile;


- (SeafDetailViewController *)detailViewController
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    return (SeafDetailViewController *)[appdelegate detailViewController:TABBED_SEAFILE];
}

- (NSArray *)editToolItems
{
    if (!_editToolItems) {
        int i;
        UIBarButtonItem *flexibleFpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:@selector(editOperation:)];
        UIBarButtonItem *fixedSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:self action:@selector(editOperation:)];

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
    [conn loadRepos:self];
    [self setDirectory:(SeafDir *)conn.rootFolder];
}

- (UIView *)overlayView
{
    if (_overlayView == nil) {
        self.tableView.autoresizesSubviews = YES;
        _overlayView = [[UIView alloc] initWithFrame:self.tableView.frame];
        _overlayView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.2];
        UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        activityIndicator.center = self.overlayView.center;
        [_overlayView addSubview:activityIndicator];
        _overlayView.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        [activityIndicator startAnimating];
    }
    return _overlayView;
}

- (void)dismissOverlayView
{
    if (_overlayView && _overlayView.superview) {
        [_overlayView removeFromSuperview];
    }
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
    [formatter setDateFormat:@"yyyy-MM-dd HH.mm.ss"];
    self.tableView.scrollEnabled = YES;
    self.tableView.rowHeight = 50;
    self.state = STATE_INIT;
    if (_refreshHeaderView == nil) {
        EGORefreshTableHeaderView *view = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.tableView.bounds.size.height, self.view.frame.size.width, self.tableView.bounds.size.height)];
        view.delegate = self;
        [self.tableView addSubview:view];
        _refreshHeaderView = view;
    }
    [_refreshHeaderView refreshLastUpdatedDate];
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
        if ([parent isEqualToString:_directory.path]) {
            for (SeafBase *entry in _directory.allItems) {
                if (entry == sfile) {
                    deleted = NO;
                    break;
                }
            }
            if (deleted)
                [self.detailViewController setPreViewItem:nil];
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
        [self.navigationController setToolbarHidden:NO animated:YES];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
        [self.navigationController setToolbarHidden:YES animated:YES];
        if(!IsIpad())  [self showTabBar];
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

    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:imagePickerController];
    if (IsIpad()) {
        self.popoverController = [[UIPopoverController alloc] initWithContentViewController:navigationController];
        self.popoverController.delegate = self;
        [self.popoverController presentPopoverFromBarButtonItem:sender permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else {
        [self presentViewController:navigationController animated:YES completion:NULL];
    }
}

- (void)initNavigationItems:(SeafDir *)directory
{
    if ([directory isKindOfClass:[SeafRepos class]]) {
    } else {
        if (directory.editable) {
            self.photoItem  = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCamera target:self action:@selector(addPhotos:)];
            self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects: self.editButtonItem, self.photoItem, nil];
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
    [self refreshView];
    if (!_directory.hasCache) {
        [self.tableView addSubview:self.overlayView];
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


- (UITableViewCell *)getSeafUploadFileCell:(SeafUploadFile *)file forTableView:(UITableView *)tableView
{
    file.delegate = self;
    if (file.uploading) {
        SeafUploadingFileCell *cell = (SeafUploadingFileCell *)[self getCell:@"SeafUploadingFileCell" forTableView:tableView];
        cell.nameLabel.text = file.name;
        cell.imageView.image = file.image;
        [cell.progressView setProgress:file.uploadProgress *1.0/100];
        return cell;
    } else {
        SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
        cell.textLabel.text = file.name;
        cell.imageView.image = file.image;

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
        return cell;
    }
}

- (SeafCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
    cell.textLabel.text = sfile.name;
    cell.detailTextLabel.text = sfile.detailText;
    cell.imageView.image = sfile.image;
    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showEditFileMenu:)];
    [cell addGestureRecognizer:longPressGesture];
    return cell;
}

- (SeafCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafDirCell" forTableView:tableView];
    cell.textLabel.text = sdir.name;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = sdir.image;
    return cell;
}

- (SeafCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
    NSString *detail = [NSString stringWithFormat:@"%@, %@", [FileSizeFormatter stringFromNumber:[NSNumber numberWithInt:srepo.size ] useBaseTen:NO], [SeafDateFormatter stringFromInt:srepo.mtime]];
    cell.detailTextLabel.text = detail;
    cell.imageView.image = srepo.image;
    cell.textLabel.text = srepo.name;
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
    if ([_curEntry isKindOfClass:[SeafUploadFile class]]) {
        if (!IsIpad()) {
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate showDetailView:self.detailViewController];
        }
        [self.detailViewController setPreViewItem:(SeafUploadFile *)_curEntry];
        return;
    }

    [_curEntry setDelegate:self];
    if ([_curEntry isKindOfClass:[SeafRepo class]] && [(SeafRepo *)_curEntry passwordRequired]) {
        [self popupSetRepoPassword];
        return;
    }

    if ([_curEntry isKindOfClass:[SeafFile class]]) {
        [_curEntry loadContent:NO];
        if (!IsIpad()) {
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate showDetailView:self.detailViewController];
        }
        [self.detailViewController setPreViewItem:(SeafFile *)_curEntry];
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

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (![_directory isKindOfClass:[SeafRepos class]]) {
        return nil;
    }
    if (section == 0) {
        return @"My Own Libraries";
    }
    NSArray *repos =  [[((SeafRepos *)_directory)repoGroups] objectAtIndex:section];
    SeafRepo *repo = (SeafRepo *)[repos objectAtIndex:0];
    if (!repo)
        return @"";
    return repo.owner;
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
        [self tableView:self.tableView didSelectRowAtIndexPath:_selectedindex];
}
- (void)entry:(SeafBase *)entry contentUpdated:(BOOL)updated completeness:(int)percent
{
    if (entry == _directory) {
        [self dismissOverlayView];
        [SVProgressHUD dismiss];
        [self doneLoadingTableViewData];
        [self refreshView];
        if (_inputView) {
            [_inputView dismissWithClickedButtonIndex:0 animated:YES];
        }
    } else if ([entry isKindOfClass:[SeafFile class]]) {
        if (updated && entry == self.detailViewController.preViewItem)
            [self.detailViewController fileContentLoaded:(SeafFile *)entry result:YES completeness:percent];
    }
    self.state = STATE_INIT;
}

- (void)entryContentLoadingFailed:(int)errCode entry:(SeafBase *)entry;
{
    if (errCode == HTTP_ERR_REPO_PASSWORD_REQUIRED) {
        NSAssert(0, @"Here should never be reached");
    }
    if ([entry isKindOfClass:[SeafFile class]]) {
        [self.detailViewController fileContentLoaded:(SeafFile *)entry result:NO completeness:0];
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
                    [self dismissOverlayView];
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
    [self.detailViewController setPreViewItem:nil];
    [self tableView:self.tableView didSelectRowAtIndexPath:_selectedindex];
}

#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex];
    if (buttonIndex == 0) {
        [self deleteFile:file];
    } else if (buttonIndex == 1) {
        [self redownloadFile:file];
    } else if (buttonIndex == 2)  {
        [file update:self];
        [self refreshView];
    }
}

#pragma mark - SeafFileUploadDelegate
- (BOOL)goTo:(NSString *)repo path:(NSString *)path
{
    if ([self.directory isKindOfClass:[SeafRepos class]]) {
        for (int i = 0; i < ((SeafRepos *)_directory).repoGroups.count; ++i) {
            NSArray *repos = [((SeafRepos *)_directory).repoGroups objectAtIndex:i];
            for (int j = 0; j < repos.count; ++j) {
                SeafRepo *r = [repos objectAtIndex:j];
                if ([r.repoId isEqualToString:repo]) {
                    NSIndexPath *idx = [NSIndexPath indexPathForRow:j inSection:i];
                    [self tableView:self.tableView didSelectRowAtIndexPath:idx];
                }
            }
        }
    } else {
        if ([@"/" isEqualToString:path])
            return NO;
        for (int i = 0; i < _directory.allItems.count; ++i) {
            SeafBase *b = [_directory.allItems objectAtIndex:i];
            NSString *p = b.path;
            if ([b isKindOfClass:[SeafDir class]]) {
                p = [p stringByAppendingString:@"/"];
            }
            if ([b.path isEqualToString:path] || [path hasPrefix:p]) {
                NSIndexPath *idx = [NSIndexPath indexPathForRow:i inSection:0];
                [self tableView:self.tableView didSelectRowAtIndexPath:idx];
            }
        }
    }
    if (self.navigationController.topViewController != self)
        return YES;
    return NO;
}

- (void)viewDidAppear:(BOOL)animated
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate checkGoto:self];
    for (SeafUploadFile *file in _directory.uploadItems)
        if (!file.uploaded && !file.uploading)
         [file upload:_connection repo:_directory.repoId path:_directory.path update:NO];
}

- (void)chooseUploadDir:(SeafDir *)dir
{
    [dir addUploadFiles:[NSArray arrayWithObject:self.ufile]];
    [self.ufile upload:dir->connection repo:dir.repoId path:dir.path update:NO];
}

- (void)uploadFile:(SeafUploadFile *)file
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    file.delegate = self;
    self.ufile = file;

    SeafUploadDirViewController *controller = [[SeafUploadDirViewController alloc] initWithSeafDir:_connection.rootFolder];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    [navController setModalPresentationStyle:UIModalPresentationFormSheet];
    [appdelegate.tabbarController presentViewController:navController animated:YES completion:nil];
}

#pragma mark - QBImagePickerControllerDelegate
- (void)imagePickerController:(QBImagePickerController *)imagePickerController didFinishPickingMediaWithInfo:(id)info
{
    if (IsIpad()) {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController = nil;
    } else {
        [self dismissViewControllerAnimated:YES completion:NULL];
    }
    if (imagePickerController.allowsMultipleSelection) {
        NSArray *mediaInfoArray = (NSArray *)info;
        Debug("Selected %d photos:%@\n", mediaInfoArray.count, mediaInfoArray);
    } else {
        NSDictionary *mediaInfo = (NSDictionary *)info;
        Debug("Selected: %@", mediaInfo);
    }

    NSMutableArray *files = [[NSMutableArray alloc] init];
    if (imagePickerController.allowsMultipleSelection) {
        int i = 0;
        NSString *date = [formatter stringFromDate:[NSDate date]];
        for (NSDictionary *dict in info) {
            i++;
            UIImage *image = [dict objectForKey:@"UIImagePickerControllerOriginalImage"];
            NSString *filename = [NSString stringWithFormat:@"Photo %@-%d.jpg", date, i];
            NSString *path = [[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"] stringByAppendingPathComponent:filename];
            [UIImageJPEGRepresentation(image, 1.0) writeToFile:path atomically:YES];
            SeafUploadFile *file =  [[SeafUploadFile alloc] initWithPath:path];
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
        [self dismissViewControllerAnimated:YES completion:NULL];
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

#pragma mark - SeafUploadDelegate
- (void)uploadProgress:(SeafUploadFile *)file result:(BOOL)res completeness:(int)percent
{
    int index = [_directory.allItems indexOfObject:file];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (res && file.uploading && [cell isKindOfClass:[SeafUploadingFileCell class]]) {
        [((SeafUploadingFileCell *)cell).progressView setProgress:percent*1.0f/100];
        return;
    }
    [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationAutomatic ];
}

@end
