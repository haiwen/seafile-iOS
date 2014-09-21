//
//  SeafStarredFilesViewController.m
//  seafile
//
//  Created by Wang Wei on 11/4/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafStarredFilesViewController.h"
#import "SeafDetailViewController.h"
#import "SeafStarredFile.h"
#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "SeafCell.h"

#import "UIViewController+Extend.h"
#import "EGORefreshTableHeaderView.h"
#import "SVProgressHUD.h"
#import "SeafData.h"
#import "Utils.h"
#import "Debug.h"

@interface SeafStarredFilesViewController ()<EGORefreshTableHeaderDelegate, UIScrollViewDelegate>
@property NSMutableArray *starredFiles;
@property (readonly) SeafDetailViewController *detailViewController;
@property (retain) NSIndexPath *selectedindex;

@property (readonly) EGORefreshTableHeaderView* refreshHeaderView;

@end

@implementation SeafStarredFilesViewController
@synthesize connection = _connection;
@synthesize starredFiles = _starredFiles;
@synthesize selectedindex = _selectedindex;
@synthesize refreshHeaderView = _refreshHeaderView;

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (SeafDetailViewController *)detailViewController
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    return (SeafDetailViewController *)[appdelegate detailViewController:TABBED_STARRED];
}

- (void)refresh:(id)sender
{
    [_connection getStarredFiles:^(NSHTTPURLResponse *response, id JSON, NSData *data) {
        @synchronized(self) {
            Debug("Success to get starred files ...\n");
            [self doneLoadingTableViewData];
            [self handleData:JSON];
            [self.tableView reloadData];
        }
    }
                         failure:^(NSHTTPURLResponse *response, NSError *error, id JSON) {
                             Warning("Failed to get starred files ...\n");
                             if (self.isVisible)
                                 [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to get starred files", @"Seafile")];
                             [self doneLoadingTableViewData];
                         }];
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)])
        [self.tableView setSeparatorInset:UIEdgeInsetsMake(0, 0, 0, 0)];
    self.tableView.rowHeight = 50;
    self.clearsSelectionOnViewWillAppear = NO;
    if (_refreshHeaderView == nil) {
        EGORefreshTableHeaderView *view = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.tableView.bounds.size.height, self.view.frame.size.width, self.tableView.bounds.size.height)];
        view.delegate = self;
        [self.tableView addSubview:view];
        _refreshHeaderView = view;
    }
    [_refreshHeaderView refreshLastUpdatedDate];
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)refreshView
{
    [self.tableView reloadData];
}

- (BOOL)handleData:(id)JSON
{
    int i;
    NSMutableArray *stars = [NSMutableArray array];
    for (NSDictionary *info in JSON) {
        SeafStarredFile *sfile = [[SeafStarredFile alloc] initWithConnection:_connection repo:[info objectForKey:@"repo"] path:[info objectForKey:@"path"] mtime:[[info objectForKey:@"mtime"] integerValue:0] size:[[info objectForKey:@"size"] integerValue:0] org:(int)[[info objectForKey:@"org"] integerValue:0]];
        sfile.starDelegate = self;
        [stars addObject:sfile];
    }
    if (_starredFiles) {
        NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
        for (i = 0; i < [_starredFiles count]; ++i) {
            SeafBase *obj = (SeafBase*)[_starredFiles objectAtIndex:i];
            [dict setObject:obj forKey:[obj key]];
        }
        for (i = 0; i < [stars count]; ++i) {
            SeafStarredFile *obj = (SeafStarredFile*)[stars objectAtIndex:i];
            SeafStarredFile *oldObj = [dict objectForKey:[obj key]];
            if (oldObj) {
                [oldObj updateWithEntry:obj];
                [stars replaceObjectAtIndex:i withObject:oldObj];
            }
        }
    }
    _starredFiles = stars;
    return YES;
}

- (BOOL)loadCache
{
    id JSON = [_connection getCachedStarredFiles];
    if (!JSON)
        return NO;

    [self handleData:JSON];
    return YES;
}

- (void)setConnection:(SeafConnection *)conn
{
    _connection = conn;
    _starredFiles = nil;
    [self.detailViewController setPreViewItem:nil master:nil];
    [self loadCache];
    [self.tableView reloadData];
    //[self performSelector:@selector(refresh:) withObject:nil afterDelay:1.0f];
}

- (void)showEditFileMenu:(UILongPressGestureRecognizer *)gestureRecognizer
{
    UIActionSheet *actionSheet;
    if (gestureRecognizer.state != UIGestureRecognizerStateBegan)
        return;

    CGPoint touchPoint = [gestureRecognizer locationInView:self.tableView];
    _selectedindex = [self.tableView indexPathForRowAtPoint:touchPoint];
    if (!_selectedindex)
        return;

    SeafFile *file = (SeafFile *)[_starredFiles objectAtIndex:_selectedindex.row];
    if (![file hasCache])
        return;

    NSString *cancelTitle = nil;
    if (!IsIpad())
        cancelTitle = NSLocalizedString(@"Cancel", @"Seafile");
    if (file.mpath)
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:cancelTitle destructiveButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Redownload", @"Seafile"), NSLocalizedString(@"Upload", @"Seafile"), nil];
    else
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:cancelTitle destructiveButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Redownload", @"Seafile"), nil];

    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:_selectedindex];
    [actionSheet showFromRect:cell.frame inView:self.tableView animated:YES];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _starredFiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:@"SeafCell" owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    ((SeafCell *)cell).badgeLabel.text = nil;
    SeafStarredFile *sfile = [_starredFiles objectAtIndex:indexPath.row];
    sfile.udelegate = self;
    cell.textLabel.text = sfile.name;
    cell.detailTextLabel.text = sfile.detailText;
    cell.imageView.image = sfile.icon;
    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showEditFileMenu:)];
    [cell addGestureRecognizer:longPressGesture];
    return cell;
}


#pragma mark - Table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafStarredFile *sfile = [_starredFiles objectAtIndex:indexPath.row];
    if (!IsIpad()) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate showDetailView:self.detailViewController];
    }
    [self.detailViewController setPreViewItem:sfile master:self];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

#pragma mark - SeafStarFileDelegate
- (void)fileStateChanged:(BOOL)starred file:(SeafStarredFile *)sfile
{
    if (starred) {
        if ([_starredFiles indexOfObject:sfile] == NSNotFound)
            [_starredFiles addObject:sfile];
    } else {
        [_starredFiles removeObject:sfile];
    }

    [self.tableView reloadData];
}

#pragma mark - UIActionSheetDelegate
- (void)redownloadFile:(SeafFile *)file
{
    [file deleteCache];
    [self.detailViewController setPreViewItem:nil master:nil];
    [self tableView:self.tableView didSelectRowAtIndexPath:_selectedindex];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    SeafFile *file = (SeafFile *)[_starredFiles objectAtIndex:_selectedindex.row];
    if (buttonIndex == 0) {
        [self redownloadFile:file];
    } else if (buttonIndex == 1)  {
        [file update:self];
        [self refreshView];
    }
}

#pragma mark - SeafFileUpdateDelegate
- (void)updateProgress:(SeafFile *)file result:(BOOL)res completeness:(int)percent
{
    if (!res) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to upload file", @"Seafile")];
    }
    [self refreshView];
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

    [self refresh:nil];
}

- (BOOL)egoRefreshTableHeaderDataSourceIsLoading:(EGORefreshTableHeaderView*)view
{
    return NO;
}

- (NSDate*)egoRefreshTableHeaderDataSourceLastUpdated:(EGORefreshTableHeaderView*)view
{
    return [NSDate date];
}

@end
