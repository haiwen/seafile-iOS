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

@interface SeafSearchResultViewController ()<UITableViewDelegate, UITableViewDataSource, SeafDentryDelegate, UISearchBarDelegate, SeafFileUpdateDelegate>

@property (nonatomic, strong) UITableView *tableView;

@property (nonatomic, strong) NSArray *searchResults;

@property (nonatomic, strong) UILabel *stateLabel;

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
    self.tableView.tableFooterView = [UIView new];

    // Make style same as SeafFileViewController
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafCell" bundle:nil]
         forCellReuseIdentifier:@"SeafCell"];
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafDirCell" bundle:nil]
         forCellReuseIdentifier:@"SeafDirCell"];

    UIView *bView = [[UIView alloc] initWithFrame:self.tableView.frame];
    bView.backgroundColor = kPrimaryBackgroundColor;
    self.tableView.backgroundView = bView;
    self.tableView.separatorInset = SEAF_SEPARATOR_INSET;

    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0;
    }

    if (!IsIpad()) {
        self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    
    [self.view addSubview:self.tableView];
    
    self.stateLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 50)];
    self.stateLabel.textAlignment = NSTextAlignmentCenter;
    [self.tableView addSubview:self.stateLabel];
    self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stateLabel.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor].active = YES;
    [self.stateLabel.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor constant:-100].active = YES;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    
    CGFloat heightToSubtract = 0;
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    if ([rootVC isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabBarController = (UITabBarController *)rootVC;
        if (!tabBarController.tabBar.isHidden) {
            heightToSubtract = tabBarController.tabBar.frame.size.height;
        }
    }

    if (heightToSubtract == 0) {
        if (@available(iOS 11.0, *)) {
            UIWindow *window = [UIApplication sharedApplication].keyWindow;
            heightToSubtract = window.safeAreaInsets.bottom;
        }
    }

    if (IsIpad()) {
        self.tableView.frame = CGRectMake(0, 0, self.presentingViewController.view.frame.size.width, self.view.window.frame.size.height - heightToSubtract);
    } else {
        CGRect frame = self.view.bounds;
        frame.size.height -= heightToSubtract;
        self.tableView.frame = frame;
    }
}

// Update search results when user types in the search bar.
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    searchController.searchBar.delegate = self;
    if (searchController.searchBar.text.length == 0) {
        [self resetTableview];
        [self updateStateLabel:SEARCH_STATE_INIT];
    }
}

// Initiates search when the search button is clicked.
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
            self.searchResults = @[];
            [self.tableView reloadData];
        } else {
            [self updateStateLabel:nil];
            self.searchResults = results;
            self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 5.0)];
            [self.tableView reloadData];
        }
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        if (response.statusCode == 404) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Search is not supported on the server", @"Seafile")];
        } else {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to search", @"Seafile")];
        }
        [self updateStateLabel:SEARCH_STATE_NORESULTS];
        self.searchResults = @[];
        [self.tableView reloadData];
    }];
}

// Resets the search when the cancel button on the search bar is clicked.
- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    // Immediately send notification to make search bar disappear
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SeafSearchCancelled" object:nil];
    
    // Disable related animations
    [UIView setAnimationsEnabled:NO];
    
    // Force end search state
    [searchBar resignFirstResponder];
    
    // Restore animation settings
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView setAnimationsEnabled:YES];
    });
    
    // Reset search results view
    [self resetTableview];
}

// Resets the table view to its initial state.
- (void)resetTableview {
    self.searchResults = nil;
    self.tableView.tableHeaderView = nil;
    [self updateStateLabel:SEARCH_STATE_INIT];
    [self.tableView reloadData];
}

// Updates the label to reflect the current state of search.
- (void)updateStateLabel:(NSString *)state {
    if (state) {
        self.stateLabel.text = state;
        self.stateLabel.hidden = false;
    } else {
        self.stateLabel.hidden = true;
    }
}

#pragma mark - Cell Style Helpers

- (void)setCellSaparatorAndCorner:(UITableViewCell *)cell andIndexPath:(NSIndexPath *)indexPath {
    // Check if it's the last cell in section
    BOOL isLastCell = (indexPath.row == self.searchResults.count - 1);

    // Update cell separator
    if ([cell isKindOfClass:[SeafCell class]]) {
        [(SeafCell *)cell updateSeparatorInset:isLastCell];
    }

    [self setCellCornerWithCell:cell andIndexPath:indexPath];
}

- (void)setCellCornerWithCell:(UITableViewCell *)cell andIndexPath:(NSIndexPath *)indexPath {
    if ([cell isKindOfClass:[SeafCell class]]) {
        BOOL isFirstCell = (indexPath.row == 0);
        BOOL isLastCell = (indexPath.row == self.searchResults.count - 1);

        [(SeafCell *)cell updateCellStyle:isFirstCell isLastCell:isLastCell];
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
    
    SeafCell *cell;
    if ([entry isKindOfClass:[SeafDir class]]) {
        cell = [self getSeafDirCell:(SeafDir *)entry forTableView:tableView andIndexPath: indexPath];
    } else {
        cell = [self getSeafFileCell:(SeafFile *)entry forTableView:tableView andIndexPath:indexPath];
    }
    [self setCellSaparatorAndCorner:cell andIndexPath:indexPath];
    return cell;
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
            [self.masterVC.detailViewController setPreViewPhotos:[self getCurrentFileImagesInTableView:tableView] current:item master:self];
        } else {
            [self.masterVC.detailViewController setPreViewItem:item master:self];
        }
        
        if (self.masterVC.detailViewController.state == PREVIEW_QL_MODAL) {
            [self.masterVC.detailViewController.qlViewController reloadData];
            if (IsIpad()) {
                [[[SeafAppDelegate topViewController] parentViewController] presentViewController:self.masterVC.detailViewController.qlViewController animated:true completion:nil];
            } else {
                [self presentViewController:self.masterVC.detailViewController.qlViewController animated:true completion:nil];
            }
        } else if (!IsIpad()) {
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate showDetailView:self.masterVC.detailViewController];
        }
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        [(SeafDir *)entry setDelegate:self];
        SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
        [controller setDirectory:(SeafDir *)entry];
        [self.navigationController pushViewController:controller animated:YES];
    }
}

// Determine if the current file is an image.
- (BOOL)isCurrentFileImage:(id<SeafPreView>)item {
    if (![item conformsToProtocol:@protocol(SeafPreView)])
        return NO;
    return item.isImageFile;
}

// Retrieve all image files in the current search results.
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
    [self.masterVC.detailViewController download:entry complete:updated];
    [SVProgressHUD dismiss];
    [self updateEntryCell:entry];
}

// Handles errors during file download.
- (void)download:(SeafBase *)entry failed:(NSError *)error {
    [self.masterVC.detailViewController download:entry failed:error];
    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to download file", @"Seafile")];
    [self updateEntryCell:entry];
}

// Updates the progress of a file being downloaded.
- (void)download:(SeafBase *)entry progress:(float)progress {
    [self.masterVC.detailViewController download:entry progress:progress];
    SeafCell *cell = [self getEntryCell:entry];
    [self updateCellDownloadStatus:cell isDownloading:true waiting:false cached:((SeafFile *)entry).hasCache];
}

#pragma mark - Tableview cell
// Retrieves a cell configured for a directory entry.
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

// Generic method to retrieve a reusable cell from the table view.
- (SeafCell *)getCell:(NSString *)cellIdentifier forTableView:(UITableView *)tableView {
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:cellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    [cell reset];
    
    return cell;
}

// Retrieves a cell configured for a file entry.
- (SeafCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView andIndexPath:(NSIndexPath *)indexPath {
    [sfile loadCache];
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
    cell.cellIndexPath = indexPath;
    sfile.delegate = self;
    SeafRepo *repo = [_connection getRepo:sfile.repoId];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@", repo.name, sfile.path.stringByDeletingLastPathComponent];
    [self updateCellContent:cell file:sfile];
    return cell;
}

// Updates the content of a cell based on the properties of a file.
- (void)updateCellContent:(SeafCell *)cell file:(SeafFile *)sfile {
    cell.textLabel.text = sfile.name;
    cell.imageView.image = sfile.icon;
    cell.badgeLabel.text = nil;
    cell.moreButton.hidden = YES;
    [self updateCellDownloadStatus:cell isDownloading:sfile.isDownloading waiting:false cached:sfile.hasCache];
}

// Updates the download status indicator of a cell.
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

// Updates the display of a file entry cell after its data has changed.
- (void)updateEntryCell:(SeafFile *)entry {
    NSUInteger index = [self.searchResults indexOfObject:entry];
    NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
    SeafCell *cell = [self.tableView cellForRowAtIndexPath:path];
    [self updateCellContent:cell file:entry];
}

// Retrieves the cell for a given entry from the table view.
- (SeafCell *)getEntryCell:(id)entry {
    NSUInteger index = [self.searchResults indexOfObject:entry];
    if (index == NSNotFound) return nil;
    
    NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
    return [self.tableView cellForRowAtIndexPath:path];
}

// Retrieves the detail view controller from the app delegate.
- (SeafDetailViewController *)detailViewController {
    return self.masterVC.detailViewController;
}

#pragma mark - SeafFileUpdateDelegate

- (void)updateProgress:(SeafFile *)file progress:(float)progress {
    NSUInteger index = [self.searchResults indexOfObject:file];
    if (index == NSNotFound) return;
    
    NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
    SeafCell *cell = (SeafCell *)[self.tableView cellForRowAtIndexPath:path];
    
    if (cell) {
        // Show uploading indicator
        [self updateCellDownloadStatus:cell isDownloading:true waiting:false cached:false];
    }
}

- (void)updateComplete:(SeafFile *)file result:(BOOL)res {
    [self updateEntryCell:file];
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
