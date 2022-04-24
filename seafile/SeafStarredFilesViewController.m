//
//  SeafStarredFilesViewController.m
//  seafile
//
//  Created by Wang Wei on 11/4/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "UIScrollView+SVPullToRefresh.h"

#import "SeafAppDelegate.h"
#import "SeafStarredFilesViewController.h"
#import "SeafDetailViewController.h"
#import "SeafStarredFile.h"
#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "SeafCell.h"
#import "SeafActionSheet.h"

#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "Utils.h"
#import "Debug.h"
#import "SeafActionsManager.h"

@interface SeafStarredFilesViewController ()<SWTableViewCellDelegate>
@property NSMutableArray *starredFiles;
@property (readonly) SeafDetailViewController *detailViewController;
@property (retain) NSIndexPath *selectedindex;

@property (retain)id lock;
@end

@implementation SeafStarredFilesViewController
@synthesize connection = _connection;
@synthesize starredFiles = _starredFiles;
@synthesize selectedindex = _selectedindex;

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
            Debug("Succeeded to get starred files ...\n");
            [self handleData:JSON];
            [self.tableView.pullToRefreshView stopAnimating];
            [self.tableView reloadData];
        }
    }
                         failure:^(NSHTTPURLResponse *response, NSError *error) {
                             Warning("Failed to get starred files ...\n");
                             if (self.isVisible)
                                 [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to get starred files", @"Seafile")];
                             [self.tableView.pullToRefreshView stopAnimating];
                         }];
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = NSLocalizedString(@"Starred", @"Seafile");
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafCell" bundle:nil]
         forCellReuseIdentifier:@"SeafCell"];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)])
        [self.tableView setSeparatorInset:UIEdgeInsetsMake(0, 0, 0, 0)];
    self.tableView.estimatedRowHeight = 55.0;
    self.tableView.tableFooterView = [UIView new];
    self.navigationController.navigationBar.tintColor = BAR_COLOR;

    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barAppearance = [UINavigationBarAppearance new];
        barAppearance.backgroundColor = [UIColor whiteColor];
        
        self.navigationController.navigationBar.standardAppearance = barAppearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = barAppearance;
        
//        self.tableView.sectionHeaderTopPadding = 0;
    }
    
    __weak typeof(self) weakSelf = self;
    [self.tableView addPullToRefresh:[SVArrowPullToRefreshView class] withActionHandler:^{
        if (![weakSelf checkNetworkStatus]) {
            [weakSelf.tableView.pullToRefreshView stopAnimating];
        } else {
            [weakSelf refresh:nil];
        }
    }];
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
        SeafStarredFile *sfile = [[SeafStarredFile alloc] initWithConnection:_connection repo:[info objectForKey:@"repo"] path:[info objectForKey:@"path"] mtime:[[info objectForKey:@"mtime"] integerValue:0] size:[[info objectForKey:@"size"] integerValue:0] org:(int)[[info objectForKey:@"org"] integerValue:0] oid:[info objectForKey:@"oid"]];
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
    if (!cell) return;
    dispatch_async(dispatch_get_main_queue(), ^{
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
    });
}

- (void)updateCellContent:(SeafCell *)cell file:(SeafFile *)sfile
{
    cell.textLabel.text = sfile.name;
    cell.detailTextLabel.text = sfile.detailText;
    cell.imageView.image = sfile.icon;
    cell.moreButton.hidden = NO;
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
    cell.cellIndexPath = indexPath;
    cell.moreButtonBlock = ^(NSIndexPath *indexPath) {
        Debug(@"%@", indexPath);
        [self showActionSheetWithIndexPath:indexPath];
    };
    [cell reset];

    SeafStarredFile *sfile;
    @try {
        sfile = [_starredFiles objectAtIndex:indexPath.row];
    } @catch(NSException *exception) {
        return cell;
    }
    sfile.udelegate = self;

    [self updateCellContent:cell file:sfile];
    return cell;
}

- (void)selectFile:(SeafStarredFile *)sfile
{
    Debug("Select file %@", sfile.name);
    [self.detailViewController setPreViewItem:sfile master:self];

    if (!IsIpad()) {
        if (self.detailViewController.state == PREVIEW_QL_MODAL) { // Use fullscreen preview for doc, xls, etc.
            [self.detailViewController.qlViewController reloadData];
            [self presentViewController:self.detailViewController.qlViewController animated:NO completion:nil];
        } else {
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate showDetailView:self.detailViewController];
        }
    }
}

#pragma mark - Table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafStarredFile *sfile;
    @try {
        sfile = [_starredFiles objectAtIndex:indexPath.row];
        SeafRepo *repo = [_connection getRepo:sfile.repoId];
        if (repo && repo.passwordRequiredWithSyncRefresh) {
            Debug("Star file %@ repo %@ password required.", sfile.name, sfile.repoId);
            [self popupSetRepoPassword:repo handler:^{
                [self selectFile:sfile];
            }];
        } else {
            [self selectFile:sfile];
        }
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
    [self updateCellContent:cell file:entry];
}

#pragma mark - SeafDentryDelegate
- (void)download:(SeafBase *)entry progress:(float)progress
{
    SeafCell *cell = [self getEntryCell:entry];
    [self updateCellDownloadStatus:cell file:(SeafFile *)entry waiting:false];
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
- (void)updateProgress:(SeafFile *)file progress:(float)progress
{
    [self updateEntryCell:file];
}
- (void)updateComplete:(nonnull SeafFile * )file result:(BOOL)res
{
    if (!res) [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to upload file", @"Seafile")];
    [self refreshView];
    [self updateEntryCell:file];
}

- (void)updateProgress:(SeafFile *)file result:(BOOL)res progress:(float)progress
{
    if (!res) [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to upload file", @"Seafile")];
    [self refreshView];
}

#pragma mark - Sheet
- (void)showActionSheetWithIndexPath:(NSIndexPath *)indexPath
{
    _selectedindex = indexPath;
    SeafFile *file = (SeafFile *)[_starredFiles objectAtIndex:_selectedindex.row];

    SeafCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    NSString *title;
    if (file.mpath)
        title = S_UPLOAD;
    else
        title = S_REDOWNLOAD;

    NSArray *titles = @[title];

    [self showSheetWithTitles:titles andFromView:cell];
}

- (void)showSheetWithTitles:(NSArray*)titles andFromView:(id)view {
    SeafActionSheet *actionSheet = [SeafActionSheet actionSheetWithTitles:titles];
    actionSheet.targetVC = self;

    [actionSheet setButtonPressedBlock:^(SeafActionSheet *actionSheet, NSIndexPath *indexPath){
        [actionSheet dismissAnimated:YES];
        if (indexPath.section == 0) {
            [self cellMoreAction];
        }
    }];
    
    [actionSheet showFromView:view];
}

-(void)cellMoreAction{
    SeafFile *file = (SeafFile *)[_starredFiles objectAtIndex:_selectedindex.row];
    if (file.mpath) {
        [file update:self];
        [self refreshView];
    } else {
        [self redownloadFile:file];
    }
}

- (void)redownloadFile:(SeafFile *)file
{
    [file deleteCache];
    [self.detailViewController setPreViewItem:nil master:nil];
    [self tableView:self.tableView didSelectRowAtIndexPath:_selectedindex];
}

@end
