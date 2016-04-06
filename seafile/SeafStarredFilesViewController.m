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

@interface SeafStarredFilesViewController ()<EGORefreshTableHeaderDelegate, SWTableViewCellDelegate, UIScrollViewDelegate>
@property NSMutableArray *starredFiles;
@property (readonly) SeafDetailViewController *detailViewController;
@property (retain) NSIndexPath *selectedindex;

@property (readonly) EGORefreshTableHeaderView* refreshHeaderView;
@property (retain)id lock;
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
    return (SeafDetailViewController *)[appdelegate detailViewControllerAtIndex:TABBED_STARRED];
}

- (void)refresh:(id)sender
{
    [_connection getStarredFiles:^(NSHTTPURLResponse *response, id JSON) {
        @synchronized(self) {
            Debug("Success to get starred files ...\n");
            [self doneLoadingTableViewData];
            [self handleData:JSON];
            [self.tableView reloadData];
        }
    }
                         failure:^(NSHTTPURLResponse *response, NSError *error) {
                             Warning("Failed to get starred files ...\n");
                             if (self.isVisible)
                                 [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to get starred files", @"Seafile")];
                             [self doneLoadingTableViewData];
                         }];
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = NSLocalizedString(@"Starred", @"Seafile");
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafCell" bundle:nil]
         forCellReuseIdentifier:@"SeafCell"];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)])
        [self.tableView setSeparatorInset:UIEdgeInsetsMake(0, 0, 0, 0)];
    self.tableView.rowHeight = 50;
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
    [self refresh:nil];
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

- (void)updateCellDownloadStatus:(SeafCell *)cell file:(SeafFile *)sfile waiting:(BOOL)waiting
{
    if (sfile.hasCache || waiting || sfile.isDownloading) {
        cell.cacheStatusView.hidden = false;
        [cell.cacheStatusWidthConstraint setConstant:21.0f];
        if (sfile.isDownloading) {
            [cell.downloadingIndicator startAnimating];
        } else {
            NSString *downloadImageNmae = waiting ? @"download_waiting" : @"download_finished";
            cell.downloadStatusImageView.image = [UIImage imageNamed:downloadImageNmae];
        }
        cell.downloadStatusImageView.hidden = sfile.isDownloading;
        cell.downloadingIndicator.hidden = !sfile.isDownloading;
    } else {
        cell.cacheStatusView.hidden = true;
        [cell.cacheStatusWidthConstraint setConstant:0.0f];
    }
    [cell layoutIfNeeded];
}

- (void)updateCellContent:(SeafCell *)cell file:(SeafFile *)sfile
{
    cell.textLabel.text = sfile.name;
    cell.detailTextLabel.text = sfile.detailText;
    cell.imageView.image = sfile.icon;
    cell.badgeLabel.text = nil;
    [self updateCellDownloadStatus:cell file:sfile waiting:false];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafCell";
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:@"SeafCell" owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    cell.badgeLabel.text = nil;
    SeafStarredFile *sfile;
    @try {
        sfile = [_starredFiles objectAtIndex:indexPath.row];
    } @catch(NSException *exception) {
        return cell;
    }
    sfile.udelegate = self;
    if (tableView == self.tableView) {
        cell.rightUtilityButtons = [self rightButtonsForFile:sfile];
        cell.delegate = self;
    } else {
        cell.rightUtilityButtons = nil;
        cell.delegate = nil;
    }
    [self updateCellContent:cell file:sfile];
    return cell;
}

- (void)selectFile:(SeafStarredFile *)sfile
{
    Debug("Select file %@", sfile);
    if (!IsIpad()) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate showDetailView:self.detailViewController];
    }
    [self.detailViewController setPreViewItem:sfile master:self];
}

#pragma mark - Table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafStarredFile *sfile;
    @try {
        sfile = [_starredFiles objectAtIndex:indexPath.row];
        [self selectFile:sfile];
    } @catch(NSException *exception) {
        [self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
        return;
    }
}

- (SeafCell *)getEntryCell:(id)entry
{
    NSUInteger index = [_starredFiles indexOfObject:entry];
    if (index == NSNotFound)
        return nil;
    @try {
        NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
        return (SeafCell *)[self.tableView cellForRowAtIndexPath:path];
    } @catch(NSException *exception) {
        return nil;
    }
}

- (void)updateEntryCell:(SeafFile *)entry
{
    SeafCell *cell = [self getEntryCell:entry];
    if (cell) [self updateCellContent:cell file:entry];
}

#pragma mark - SeafDentryDelegate
- (void)download:(SeafBase *)entry progress:(float)progress
{
    SeafCell *cell = [self getEntryCell:entry];
    if (cell) [self updateCellDownloadStatus:cell file:(SeafFile *)entry waiting:false];
    [self.detailViewController download:entry progress:progress];
}
- (void)download:(SeafBase *)entry complete:(BOOL)updated
{
    [self updateEntryCell:(SeafFile *)entry];
    [self.detailViewController download:entry complete:updated];
}
- (void)download:(SeafBase *)entry failed:(NSError *)error
{
    [self updateEntryCell:(SeafFile *)entry];
    [self.detailViewController download:entry failed:error];
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

#pragma mark - SeafFileUpdateDelegate
- (void)updateProgress:(SeafFile *)file result:(BOOL)res completeness:(int)percent
{
    if (!res) [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to upload file", @"Seafile")];
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
        return [self performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:0.1];
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

#pragma mark - SWTableViewCellDelegate
- (void)redownloadFile:(SeafFile *)file
{
    [file deleteCache];
    [self.detailViewController setPreViewItem:nil master:nil];
    [self tableView:self.tableView didSelectRowAtIndexPath:_selectedindex];
}

- (void)hideCellButton:(SWTableViewCell *)cell
{
    [cell hideUtilityButtonsAnimated:true];
}
- (void)swipeableTableViewCell:(SWTableViewCell *)cell didTriggerRightUtilityButtonWithIndex:(NSInteger)index
{
    _selectedindex = [self.tableView indexPathForCell:cell];
    if (!_selectedindex)
        return;
    SeafFile *file = (SeafFile *)[_starredFiles objectAtIndex:_selectedindex.row];
    if (file.mpath) {
        [file update:self];
        [self refreshView];
    } else {
        [self redownloadFile:file];
    }
    [self performSelector:@selector(hideCellButton:) withObject:cell afterDelay:0.1f];
}
- (NSArray *)rightButtonsForFile:(SeafStarredFile *)file
{
    NSMutableArray *rightUtilityButtons = [NSMutableArray new];
    NSString *title;
    if (file.mpath)
        title = S_UPLOAD;
    else
        title = S_REDOWNLOAD;

    [rightUtilityButtons sw_addUtilityButtonWithColor:
     [UIColor colorWithRed:0.78f green:0.78f blue:0.8f alpha:1.0]
                                                title:title];
    return rightUtilityButtons;
}

@end
