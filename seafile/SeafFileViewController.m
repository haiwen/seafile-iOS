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
#import "SeafTableViewRepoCell.h"

#import "SeafFile.h"
#import "SeafRepos.h"

#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "ExtentedString.h"
#import "UIViewController+AlertMessage.h"
#import "SVProgressHUD.h"
#import "Debug.h"

enum {
    STATE_INIT = 0,
    STATE_LOADING,
    STATE_DELETE,
    STATE_MKDIR,
};

@interface SeafFileViewController ()
- (UITableViewCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView;
- (UITableViewCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView;
- (UITableViewCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView;

@property (strong) SeafBase *curEntry;
@property (strong) InputAlertPrompt *passSetView;
@property (strong) InputAlertPrompt *mkdirView;

@property (strong) UIBarButtonItem *selectAllItem;
@property (strong) UIBarButtonItem *selectNoneItem;
@property (strong) UIBarButtonItem *backItem;

@property (strong, readonly) UIView *overlayView;
@property int state;
@end

@implementation SeafFileViewController

@synthesize detailViewController = _detailViewController;
@synthesize directory = _directory;
@synthesize curEntry = _curEntry;
@synthesize passSetView = _passSetView, mkdirView = _mkdirView;
@synthesize backItem = _backItem, selectAllItem = _selectAllItem, selectNoneItem = _selectNoneItem;
@synthesize state;


@synthesize overlayView = _overlayView;

- (void)initTabBarItem
{
    self.title = @"Seafile";
    self.navigationController.tabBarItem.image = [[UIImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"tab-home" ofType:@"png"]];
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
    // Do any additional setup after loading the view, typically from a nib.
    self.tableView.scrollEnabled = YES;
    self.state = STATE_INIT;
    if (_refreshHeaderView == nil) {
        EGORefreshTableHeaderView *view = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.tableView.bounds.size.height, self.view.frame.size.width, self.tableView.bounds.size.height)];
        view.delegate = self;
        [self.tableView addSubview:view];
        _refreshHeaderView = view;
    }
    //  update the last update date
    [_refreshHeaderView refreshLastUpdatedDate];
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    _detailViewController = appdelegate.detailVC;
}

- (void)noneSelected:(BOOL)none
{
    if (none) {
        self.navigationItem.leftBarButtonItem = _selectAllItem;
        NSArray *items = self.toolbarItems;
        [[items objectAtIndex:0] setEnabled:YES];
        [[items objectAtIndex:2] setEnabled:NO];
        //[[items objectAtIndex:4] setEnabled:NO];
        //[[items objectAtIndex:6] setEnabled:NO];
    } else {
        self.navigationItem.leftBarButtonItem = _selectNoneItem;
        NSArray *items = self.toolbarItems;
        [[items objectAtIndex:0] setEnabled:NO];
        [[items objectAtIndex:2] setEnabled:YES];
        //[[items objectAtIndex:4] setEnabled:YES];
        //[[items objectAtIndex:6] setEnabled:YES];
    }
}

- (void)tableViewReloadData
{
    [self.tableView reloadData];
    if (IsIpad() && _detailViewController.preViewItem && [_detailViewController.preViewItem isKindOfClass:[SeafFile class]]) {
        SeafFile *sfile = (SeafFile *)_detailViewController.preViewItem;
        NSString *parent = [sfile.path stringByDeletingLastPathComponent];
        BOOL deleted = YES;
        if ([parent isEqualToString:_directory.path]) {
            for (SeafBase *entry in _directory.items) {
                if (entry == sfile) {
                    deleted = NO;
                    break;
                }
            }
            if (deleted)
                [_detailViewController setPreViewItem:nil];
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
    // Release any retained subviews of the main view.
    _refreshHeaderView = nil;
    _detailViewController = nil;
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
    int count = _directory.items.count;
    for (row = 0; row < count; ++row) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
    }
    [self noneSelected:NO];
}

- (void)selectNone:(id)sender
{
    int row;
    int count = _directory.items.count;
    for (row = 0; row < count; ++row) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
    [self noneSelected:YES];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (editing) {
        if (![appdelegate checkNetworkStatus])
            return;
        self.navigationItem.backBarButtonItem = nil;
        [self setToolbarItems:appdelegate.toolItems1];
        [self.navigationController.toolbar sizeToFit];
        [self noneSelected:YES];
        [self.navigationController setToolbarHidden:NO animated:YES];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.backBarButtonItem = _backItem;
        [self.navigationController setToolbarHidden:YES animated:YES];
    }

    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
}


- (void)goBack:(id)sender
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate.detailVC setPreViewItem:nil];
    appdelegate.window.rootViewController = appdelegate.startNav;
    [appdelegate.window makeKeyAndVisible];
}

- (void)initNavigationItems:(SeafDir *)directory
{
    if ([directory isKindOfClass:[SeafRepos class]]) {
        _backItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRewind target:self action:@selector(goBack:)];
        self.navigationItem.leftBarButtonItem = _backItem;
    } else {
        if (directory.editable) {
            self.navigationItem.rightBarButtonItem = self.editButtonItem;
            _selectAllItem = [[UIBarButtonItem alloc] initWithTitle:@"Select All" style:UIBarButtonItemStylePlain target:self action:@selector(selectAll:)];
            _selectNoneItem = [[UIBarButtonItem alloc] initWithTitle:@"Select None" style:UIBarButtonItemStylePlain target:self action:@selector(selectNone:)];
            _backItem = [[UIBarButtonItem alloc] initWithTitle:directory.name style:UIBarButtonItemStyleBordered target:self action:nil];
        }
        self.navigationItem.backBarButtonItem = _backItem;
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

    _directory = directory;
    self.title = directory.name;
    [_directory setDelegate:self];
    [_directory loadContent:NO];
    Debug("%@, loading ... %d\n", _directory.name, _directory.hasCache);
    [self tableViewReloadData];
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
        return _directory.items.count;
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

- (UITableViewCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView
{
    NSString *CellIdentifier = @"SeafTableViewFileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
        cell.textLabel.font = [UIFont systemFontOfSize:18];
        cell.textLabel.textColor = [UIColor darkTextColor];
    }

    cell.textLabel.text = sfile.name;
    cell.detailTextLabel.text = [FileSizeFormatter stringFromNumber:[NSNumber numberWithInt:sfile.filesize ] useBaseTen:NO];
    cell.imageView.image = sfile.image;
    return cell;
}

- (UITableViewCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView
{
    NSString *CellIdentifier = @"SeafTableViewDirCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
        cell.textLabel.font = [UIFont systemFontOfSize:18];
        cell.textLabel.textColor = [UIColor darkTextColor];
    }

    cell.textLabel.text = sdir.name;
    cell.imageView.image = sdir.image;
    return cell;
}

- (UITableViewCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView
{
    NSString *CellIdentifier = @"SeafTableViewRepoCell";
    SeafTableViewRepoCell *cell = (SeafTableViewRepoCell *)[self getCell:CellIdentifier forTableView:tableView];

    cell.imageView.image = srepo.image;
    if (srepo.mtime != 0)
        [cell.mtimeLabel setText:[SeafDateFormatter stringFromInt:srepo.mtime]];

    [cell.sizeLabel setText:[FileSizeFormatter stringFromNumber:[NSNumber numberWithInt:srepo.size ] useBaseTen:NO]];
    [cell.nameLabel setText:srepo.name];
    [cell.descLabel setText:srepo.desc];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafBase *entry  = [self getDentrybyIndexPath:indexPath];
    if ([entry isKindOfClass:[SeafRepo class]]) {
        return [self getSeafRepoCell:(SeafRepo *)entry forTableView:tableView];
    } else if ([entry isKindOfClass:[SeafFile class]]) {
        return [self getSeafFileCell:(SeafFile *)entry forTableView:tableView];
    } else {
        return [self getSeafDirCell:(SeafDir *)entry forTableView:tableView];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    // The table view should not be re-orderable.
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
        return [_directory.items objectAtIndex:[indexPath row]];
    }
    NSArray *repos =  [[((SeafRepos *)_directory)repoGroups] objectAtIndex:[indexPath section]];
    return [repos objectAtIndex:[indexPath row]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView.editing == YES) {
        [self noneSelected:NO];
        return;
    }
    _curEntry = [self getDentrybyIndexPath:indexPath];
    Debug(@"selected %d %@, %@\n", [indexPath row], _curEntry.mime, _curEntry.name);

    [_curEntry setDelegate:self];
    if ([_curEntry isKindOfClass:[SeafRepo class]] && [(SeafRepo *)_curEntry passwordRequired]) {
        [self popupSetRepoPassword];
        return;
    }

    if ([_curEntry isKindOfClass:[SeafFile class]]) {
        [_curEntry loadContent:NO];
        if (!IsIpad())
            [self.navigationController pushViewController:_detailViewController animated:YES];
        [_detailViewController setPreViewItem:(SeafFile *)_curEntry];
    } else if ([_curEntry isKindOfClass:[SeafDir class]]) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
        [appdelegate.masterNavController pushViewController:controller animated:YES];
        [controller setDirectory:(SeafDir *)_curEntry];
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

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // TODO? it seems useless
    Debug("%@\n", [segue identifier]);
}


#pragma mark - InputDoneDelegate
- (BOOL)inputDone:(InputAlertPrompt *)alertView input:(NSString *)input errmsg:(NSString **)errmsg;
{
    if (alertView == _passSetView) {
        if (!input) {
            *errmsg = @"Password must not be empty";
            return NO;
        }
        if (input.length < 3 || input.length  > 15) {
            *errmsg = @"The length of password should be between 3 and 15";
            return NO;
        }
        [_curEntry setDelegate:self];
        [_curEntry setRepoPassword:input];
        [_passSetView.inputTextField setEnabled:NO];
        return YES;
    } else if (alertView == _mkdirView) {
        if (!input) {
            *errmsg = @"Folder name must not be empty";
            return NO;
        }
        if (![input isValidFolderName]) {
            *errmsg = @"Folder name invalid";
            return NO;
        }
        [_directory setDelegate:self];
        [_directory mkdir:input];
        [_mkdirView.inputTextField setEnabled:NO];
        [SVProgressHUD showWithStatus:@"Creating folder ..."];
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
        } else if (_mkdirView == alertView) {
            _mkdirView = nil;
        }
    }
}

#pragma mark - SeafDentryDelegate
- (void)entry:(SeafBase *)entry contentUpdated:(BOOL)updated completeness:(int)percent
{
    if (entry == _directory) {
        [self dismissOverlayView];
        [SVProgressHUD dismiss];
        [self doneLoadingTableViewData];
        [self tableViewReloadData];
        if (_mkdirView) {
            [_mkdirView dismissWithClickedButtonIndex:0 animated:YES];
        }
    } else if ([entry isKindOfClass:[SeafFile class]]) {
        [_detailViewController fileContentLoaded:(SeafFile *)entry result:updated completeness:percent];
    }
    self.state = STATE_INIT;
}

- (void)entryContentLoadingFailed:(int)errCode entry:(SeafBase *)entry;
{
    if (errCode == HTTP_ERR_REPO_PASSWORD_REQUIRED) {
        NSAssert(0, @"Here should never be reached");
    }
    if ([entry isKindOfClass:[SeafFile class]]) {
        [_detailViewController fileContentLoaded:(SeafFile *)entry result:NO completeness:0];
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
                [_mkdirView.inputTextField setEnabled:YES];
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
    }
    self.state = STATE_INIT;
}

- (void)repoPasswordSet:(SeafBase *)entry WithResult:(BOOL)success;
{
    Debug("%@,%d\n", entry.repoId, success);
    if (entry != _curEntry) {
        return;
    }
    NSAssert([entry isKindOfClass:[SeafRepo class]], @"entry must be a repo\n");
    if (success) {
        [self.passSetView dismissWithClickedButtonIndex:0 animated:YES];
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
        [appdelegate.masterNavController pushViewController:controller animated:YES];
        [controller setDirectory:(SeafDir *)_curEntry];
    } else {
        [self alertWithMessage:@"Wrong library password"];
        [_passSetView.inputTextField setEnabled:YES];
    }
}

- (void)doneLoadingTableViewData
{
    //  model should call this when its done loading
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
        [self doneLoadingTableViewData];
        return;
    }
    _directory.delegate = self;
    [_directory loadContent:YES];
    //[self performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:3.0];
}

- (BOOL)egoRefreshTableHeaderDataSourceIsLoading:(EGORefreshTableHeaderView*)view
{
    return [_directory state] == SEAF_DENTRY_LOADING;
}

- (NSDate*)egoRefreshTableHeaderDataSourceLastUpdated:(EGORefreshTableHeaderView*)view
{
    return [NSDate date]; // should return date data source was last changed
}

#pragma mark - edit files

- (void)popupMkdirView
{
    _mkdirView = [[InputAlertPrompt alloc] initWithTitle:@"New folder" delegate:self autoDismiss:NO];
    _mkdirView.inputTextField.placeholder = @"New folder name";
    _mkdirView.inputTextField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _mkdirView.inputTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _mkdirView.inputTextField.returnKeyType = UIReturnKeyDone;
    _mkdirView.inputTextField.keyboardType = UIKeyboardTypeASCIICapable;
    _mkdirView.inputTextField.autocorrectionType = UITextAutocapitalizationTypeNone;
    _mkdirView.inputDoneDelegate = self;
    [_mkdirView show];
}

- (void)editOperation:(id)sender
{
    NSArray *idxs;
    NSMutableArray *entries;
    Debug("%d, %@\n", [sender tag], self.title);
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];

    if (self != appdelegate.masterVC) {
        return [appdelegate.masterVC editOperation:sender];
    }
    switch ([sender tag]) {
        case EDITOP_MKDIR:
            self.state = STATE_MKDIR;
            [self popupMkdirView];
            break;

        case EDITOP_DELETE:
            idxs = [self.tableView indexPathsForSelectedRows];
            if (!idxs) {
                return;
            }
            self.state = STATE_DELETE;
            entries = [[NSMutableArray alloc] init];
            for (NSIndexPath *indexPath in idxs) {
                [entries addObject:[_directory.items objectAtIndex:indexPath.row]];
            }
            [_directory delEntries:entries];
            [SVProgressHUD showWithStatus:@"Deleting files ..."];
        default:
            break;
    }
}

@end
