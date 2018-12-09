//
//  SeafSearchResultViewController.m
//  seafileApp
//
//  Created by three on 2018/12/4.
//  Copyright © 2018 Seafile. All rights reserved.
//

#import "SeafSearchResultViewController.h"
#import "SVProgressHUD.h"
#import "SeafRepos.h"
#import "Debug.h"
#import "SeafCell.h"
#import "SeafFileViewController.h"
#import "SeafDetailViewController.h"
#import "SeafAppDelegate.h"
#import "SeafPhoto.h"

#define SEARCH_STATE_INIT NSLocalizedString(@"Click \"Search\" to start", @"Seafile")
#define SEARCH_STATE_SEARCHING NSLocalizedString(@"Searching", @"Seafile")
#define SEARCH_STATE_NORESULTS NSLocalizedString(@"No Results", @"Seafile")

@interface SeafSearchResultViewController ()<UITableViewDelegate, UITableViewDataSource, SeafDentryDelegate, UISearchBarDelegate>

@property (nonatomic, strong) UITableView *tableView;

@property (nonatomic, strong) NSArray *searchResults;

@property (nonatomic, strong) UILabel *stateLabel;

@property (strong, readonly) SeafDetailViewController *detailViewController;

@end

@implementation SeafSearchResultViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.estimatedRowHeight = 55;
    self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 0.01)];
    self.tableView.tableFooterView = [UIView new];
    if (@available(iOS 11.0, *)) {
        self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    self.automaticallyAdjustsScrollViewInsets = NO;
    [self.view addSubview:self.tableView];
    
    self.stateLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 50)];
    self.stateLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.stateLabel];
    self.stateLabel.center = CGPointMake(self.view.center.x, self.view.center.y - 100);
    
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (IsIpad()) {
        self.tableView.frame = CGRectMake(0, 0, self.presentingViewController.view.frame.size.width, self.view.window.frame.size.height);
        self.stateLabel.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, 50);
        self.stateLabel.center = CGPointMake(self.tableView.center.x, self.tableView.center.y - 100);
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    searchController.searchBar.delegate = self;
    if (searchController.searchBar.text.length == 0) {
        [self resetTableview];
        [self updateStateLabel:SEARCH_STATE_INIT];
    }
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    Debug("search %@", searchBar.text);
    self.tableView.contentInset = UIEdgeInsetsMake(CGRectGetMaxY(searchBar.frame), 0, 0, 0);
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Searching ...", @"Seafile")];
    [self updateStateLabel:SEARCH_STATE_SEARCHING];
    NSString *repoId = [_directory isKindOfClass:[SeafRepos class]] ? nil : _directory.repoId;
    [_connection search:searchBar.text repo:repoId success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSMutableArray *results) {
        [SVProgressHUD dismiss];
        if (results.count == 0) {
            [self updateStateLabel:SEARCH_STATE_NORESULTS];
        } else {
            [self updateStateLabel:nil];
            self.searchResults = results;
            [self.tableView reloadData];
        }
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        if (response.statusCode == 404) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Search is not supported on the server", @"Seafile")];
        } else {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to search", @"Seafile")];
        }
        [self updateStateLabel:SEARCH_STATE_NORESULTS];
    }];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [self resetTableview];
}

- (void)resetTableview {
    self.searchResults = nil;
    [self updateStateLabel:SEARCH_STATE_INIT];
    [self.tableView reloadData];
}

- (void)updateStateLabel:(NSString *)state {
    if (state) {
        self.stateLabel.text = state;
        self.stateLabel.hidden = false;
    } else {
        self.stateLabel.hidden = true;
    }
}

#pragma mark - Table View
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.searchResults.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSObject *entry = [self.searchResults objectAtIndex:indexPath.row];
    if (!entry) return [UITableViewCell new];
    
    if ([entry isKindOfClass:[SeafDir class]]) {
        return [self getSeafDirCell:(SeafDir *)entry forTableView:tableView andIndexPath: indexPath];
    } else {
        return [self getSeafFileCell:(SeafFile *)entry forTableView:tableView andIndexPath:indexPath];
    }
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSObject *entry = [self.searchResults objectAtIndex:indexPath.row];
    
    if ([entry conformsToProtocol:@protocol(SeafPreView)]) {
        [(id<SeafPreView>)entry setDelegate:self];
        if ([entry isKindOfClass:[SeafFile class]] && ![(SeafFile *)entry hasCache]) {
            SeafCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            [self updateCellDownloadStatus:cell isDownloading:false waiting:true cached:false];
        }
        
        id<SeafPreView> item = (id<SeafPreView>)entry;

        if ([self isCurrentFileImage:item]) {
            [self.detailViewController setPreViewPhotos:[self getCurrentFileImagesInTableView:tableView] current:item master:self];
        } else {
            [self.detailViewController setPreViewItem:item master:self];
        }
        
        if (!IsIpad()) {
            if (self.detailViewController.state == PREVIEW_QL_MODAL) { // Use fullscreen preview for doc, xls, etc.
                [self.detailViewController.qlViewController reloadData];
                [self.presentingViewController presentViewController:self.detailViewController.qlViewController animated:true completion:nil];
            } else {
                SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
                [appdelegate showDetailView:self.detailViewController];
            }
        }
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
        [(SeafDir *)entry setDelegate:controller];
        [controller setDirectory:(SeafDir *)entry];
        
        [self.presentingViewController.navigationController pushViewController:controller animated:YES];
    }
}

- (BOOL)isCurrentFileImage:(id<SeafPreView>)item {
    if (![item conformsToProtocol:@protocol(SeafPreView)])
        return NO;
    return item.isImageFile;
}

- (NSArray *)getCurrentFileImagesInTableView:(UITableView *)tableView {
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    for (id entry in self.searchResults) {
        if ([entry conformsToProtocol:@protocol(SeafPreView)]
            && [(id<SeafPreView>)entry isImageFile])
            [arr addObject:entry];
    }
    return arr;
}

#pragma mark - SeafDentryDelegate
- (void)download:(SeafBase *)entry complete:(BOOL)updated {
    if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)entry;
        [self updateEntryCell:file];
        [self.detailViewController download:file complete:updated];
        SeafPhoto *photo = [[SeafPhoto alloc] initWithSeafPreviewIem:(id<SeafPreView>)entry];
        [photo complete:updated error:nil];
    }
}

- (void)download:(SeafBase *)entry failed:(NSError *)error {
    if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)entry;
        [self updateEntryCell:file];
        [self.detailViewController download:entry failed:error];
    }
}

- (void)download:(SeafBase *)entry progress:(float)progress {
    if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)entry;
        [self.detailViewController download:entry progress:progress];
        SeafPhoto *photo = [[SeafPhoto alloc] initWithSeafPreviewIem:(id<SeafPreView>)entry];
        [photo setProgress:progress];
        NSUInteger index = [self.searchResults indexOfObject:entry];
        NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
        SeafCell *cell = (SeafCell *)[self.tableView cellForRowAtIndexPath:path];
        [self updateCellDownloadStatus:cell isDownloading:file.isDownloading waiting:false cached:file.hasCache];
    }
}

#pragma mark - Tableview cell
- (SeafCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView andIndexPath:(NSIndexPath *)indexPath {
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafDirCell" forTableView:tableView];
    cell.textLabel.text = sdir.name;
    SeafRepo *repo = [_connection getRepo:sdir.repoId];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@", repo.name, sdir.path.stringByDeletingLastPathComponent];
    cell.moreButton.hidden = true;
    cell.imageView.image = sdir.icon;
    cell.cellIndexPath = indexPath;
    sdir.delegate = self;
    return cell;
}

- (SeafCell *)getCell:(NSString *)cellIdentifier forTableView:(UITableView *)tableView {
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:cellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    [cell reset];
    
    return cell;
}

- (SeafCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView andIndexPath:(NSIndexPath *)indexPath {
    [sfile loadCache];
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafDirCell" forTableView:tableView];
    cell.cellIndexPath = indexPath;
    sfile.delegate = self;
    SeafRepo *repo = [_connection getRepo:sfile.repoId];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@, %@", repo.name, sfile.path.stringByDeletingLastPathComponent, sfile.detailText];
    [self updateCellContent:cell file:sfile];
    return cell;
}

- (void)updateCellContent:(SeafCell *)cell file:(SeafFile *)sfile {
    cell.textLabel.text = sfile.name;
    cell.imageView.image = sfile.icon;
    cell.badgeLabel.text = nil;
    cell.moreButton.hidden = YES;
    [self updateCellDownloadStatus:cell isDownloading:sfile.isDownloading waiting:false cached:sfile.hasCache];
}

- (void)updateCellDownloadStatus:(SeafCell *)cell isDownloading:(BOOL )isDownloading waiting:(BOOL)waiting cached:(BOOL)cached {
    if (!cell) return;
    if (isDownloading && cell.downloadingIndicator.isAnimating)
        return;
    //Debug("%@ cached:%d %d %d", cell.textLabel.text, cached, waiting, isDownloading);
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

- (void)updateEntryCell:(SeafFile *)entry {
    NSUInteger index = [self.searchResults indexOfObject:entry];
    NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
    SeafCell *cell = [self.tableView cellForRowAtIndexPath:path];
    [self updateCellContent:cell file:entry];
}

- (SeafDetailViewController *)detailViewController {
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    return (SeafDetailViewController *)[appdelegate detailViewControllerAtIndex:TABBED_SEAFILE];
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
