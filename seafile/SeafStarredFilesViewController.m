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
#import "SeafStarredRepo.h"
#import "SeafStarredDir.h"
#import <AFNetworking/AFNetworking.h>
#import <AFNetworking/UIImageView+AFNetworking.h>
#import <AFNetworking/AFImageDownloader.h>
#import <SDWebImage/SDWebImageManager.h>
#import "SKFileTypeImageLoader.h"
#import "SeafDataTaskManager.h"
#import "SeafUploadOperation.h"

@interface SeafStarredFilesViewController ()<SWTableViewCellDelegate>
@property (readonly) SeafDetailViewController *detailViewController;
@property (retain) NSIndexPath *selectedindex;

@property (retain)id lock;
@property (nonatomic, strong)NSMutableArray *cellDataArray;
@end

@implementation SeafStarredFilesViewController
@synthesize connection = _connection;
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
            [self endPullRefresh];
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
    if (!_cellDataArray){
        _cellDataArray = [[NSMutableArray alloc]init];
    }
    self.title = NSLocalizedString(@"Starred", @"Seafile");
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafCell" bundle:nil]
         forCellReuseIdentifier:@"SeafCell"];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)])
        [self.tableView setSeparatorInset:UIEdgeInsetsMake(0, 0, 0, 0)];
    self.tableView.estimatedRowHeight = 55.0;
    self.tableView.tableFooterView = [UIView new];
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafCell" bundle:nil] forCellReuseIdentifier:@"SeafCell"];
    
    self.navigationController.navigationBar.tintColor = BAR_COLOR;

    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barAppearance = [UINavigationBarAppearance new];
        barAppearance.backgroundColor = [UIColor whiteColor];
        
        self.navigationController.navigationBar.standardAppearance = barAppearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = barAppearance;
        
        self.tableView.sectionHeaderTopPadding = 0;
    }
    
    self.tableView.refreshControl = [[UIRefreshControl alloc] init];
    [self.tableView.refreshControl addTarget:self action:@selector(refreshControlChanged) forControlEvents:UIControlEventValueChanged];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self refresh:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)refreshView
{
    [self.tableView reloadData];
}

- (void)handleData:(id)JSON
{
    if (!_cellDataArray){
        _cellDataArray = [[NSMutableArray alloc]init];
    }
    NSMutableArray *jsonDataArray = [[NSMutableArray alloc]init];
    if (![JSON isKindOfClass:[NSDictionary class]]) {
        Debug(@"Expected a dictionary with a 'starred_item_list' key");
        return;
    }
    
    NSArray *starredItems = [JSON objectForKey:@"starred_item_list"];
    if (![starredItems isKindOfClass:[NSArray class]]) {
        Debug(@"Expected 'starred_item_list' to be an array");
        return;
    }
    
    //check if has edited file not uploaded before.
    SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:_connection];
    NSArray *allUpLoadTasks = [accountQueue getNeedUploadTasks];
    
    NSMutableArray *starFiles = [NSMutableArray array];
    for (NSDictionary *info in starredItems) {
        NSNumber *isDirNum = [info objectForKey:@"is_dir"];
        int isDir = [isDirNum intValue];
        if (isDir != 0){//is repo or dir
            NSString *path = [info objectForKey:@"path"];
            //is dir
            if ([path isKindOfClass:[NSString class]] && [path length] > 1) {
                SeafStarredDir *starredDir = [[SeafStarredDir alloc] initWithConnection:_connection Info:info];
                [jsonDataArray addObject:starredDir];
            } else {//is repo
                SeafStarredRepo *starredRepo = [[SeafStarredRepo alloc] initWithConnection:_connection Info:info];
                [jsonDataArray addObject:starredRepo];

            }
        } else {// is file
            SeafStarredFile *sfile = [[SeafStarredFile alloc] initWithConnection:_connection Info:info];
            sfile.udelegate = self;
            if (allUpLoadTasks.count > 0) {//if have uploadTask
                for (SeafUploadFile *file in allUpLoadTasks) {
                    //check and set uploadFile to SeafFile
//                    SeafUploadFile *file = uploadOperation.uploadFile;
                    if ((file.editedFileOid != nil) && [file.editedFilePath isEqualToString:sfile.path] && [file.editedFileRepoId isEqualToString:sfile.repoId]) {
                        sfile.ufile = file;
                        [sfile setMpath:file.lpath];
                        sfile.ufile.staredFileDelegate = sfile;
                    }
                }
            }
            [starFiles addObject:sfile];
        }
    }
    
    [jsonDataArray addObjectsFromArray:starFiles];
    
    for (NSObject *item in jsonDataArray) {
        if ([item isKindOfClass:[SeafStarredFile class]]) {
            SeafStarredFile *sfile = (SeafStarredFile *)item;
            [sfile loadCache];
        }
    }
    _cellDataArray = jsonDataArray;

    return;
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
    _cellDataArray = nil;
    [self.detailViewController setPreViewItem:nil master:nil];
    [self loadCache];
    [self.tableView reloadData];
}


#pragma mark - pull to Refresh
- (void)refreshControlChanged {
    if (!self.tableView.isDragging) {
        [self pullToRefresh];
    }
}

- (void)pullToRefresh {
    if (![self checkNetworkStatus]) {
        [self.tableView.refreshControl endRefreshing];
    } else {
        self.tableView.accessibilityElementsHidden = YES;
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.tableView.refreshControl);
        [self refresh:nil];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (self.tableView.refreshControl.isRefreshing) {
        [self pullToRefresh];
    }
}

- (void)endPullRefresh {
    [self.tableView.refreshControl endRefreshing];
    self.tableView.accessibilityElementsHidden = NO;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _cellDataArray.count;
}

- (void)updateCellDownloadStatus:(SeafCell *)cell file:(SeafFile *)sfile waiting:(BOOL)waiting
{
    if (!cell) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sfile) {
            cell.cacheStatusView.hidden = true;
            [cell.cacheStatusWidthConstraint setConstant:0.0f];
            [cell layoutIfNeeded];
        } else {
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
    });
}

- (void)updateCellContent:(SeafCell *)cell file:(SeafFile *)sfile {
    NSString *detailText;
    UIColor *textColor;
    if (sfile.isDeleted){
        detailText = NSLocalizedString(@"Removed", @"Seafile");
        textColor = UIColor.redColor;
    } else {
        detailText = sfile.starredDetailText;
        textColor = Utils.cellDetailTextTextColor;
    }
    [self updateCellUI:cell cellName:sfile.name detailText:detailText detailTextColor:textColor image:sfile.icon morButtonIsHidden:NO];
    
    sfile.delegate = self;
    sfile.udelegate = self;

    [self updateCellDownloadStatus:cell file:sfile waiting:false];
}

- (void)updateCellContent:(SeafCell *)cell dir:(SeafStarredDir *)sDir
{
    NSString *detailText;
    UIColor *textColor;
    if (sDir.isDeleted){
        detailText = NSLocalizedString(@"Removed", @"Seafile");
        textColor = UIColor.redColor;
    } else {
        detailText = sDir.detailText;
        textColor = Utils.cellDetailTextTextColor;
    }
    
    [self updateCellUI:cell cellName:sDir.name detailText:detailText detailTextColor:textColor image:sDir.icon morButtonIsHidden:NO];
    sDir.delegate = self;

    //Not of type "sfile", set to nil
    [self updateCellDownloadStatus:cell file:nil waiting:false];
}

- (void)updateCellUI:(SeafCell *)cell
            cellName:(NSString *)name
          detailText:(NSString *)detailText
     detailTextColor:(UIColor *)color
               image:(UIImage *)img
   morButtonIsHidden:(BOOL)isHidden
{
    [cell.cacheStatusWidthConstraint setConstant:0.0f];

    cell.textLabel.text = name;
    cell.detailTextLabel.text = detailText;
    cell.detailTextLabel.textColor = color;
    cell.imageView.image = img;
    cell.moreButton.hidden = isHidden;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafCell";
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    cell.cellIndexPath = indexPath;
    cell.moreButtonBlock = ^(NSIndexPath *indexPath) {
        Debug(@"%@", indexPath);
        [self showActionSheetWithIndexPath:indexPath];
    };
    [cell reset];
    
    NSObject *entry = [_cellDataArray objectAtIndex:indexPath.row];
    if ([entry isKindOfClass:[SeafStarredFile class]]) {
        [self updateCellContent:cell file:(SeafStarredFile *)entry];
        return cell;
    } else {
        [self updateCellContent:cell dir:(SeafStarredDir *)entry];
        return cell;
    }
    return cell;
}

//set and push detailViewController by selected file.
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

//init and push FileViewController
- (void)selectDirOrRepo:(SeafDir *)repo
{
    [SVProgressHUD dismiss];
    SeafFileViewController *controller;
    if (IsIpad()){
        controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
    } else {
        controller = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"FILEMASTERVC"];
    }
    [self.navigationController pushViewController:controller animated:YES];
    [controller setDirectory:repo];
    [repo setDelegate:controller];
}

#pragma mark - Table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSObject *entry = [_cellDataArray objectAtIndex:indexPath.row];
    if (![entry isKindOfClass:[SeafStarredFile class]]) {
        SeafDir *starredRepo = (SeafDir *)entry;
        if (starredRepo.isDeleted) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"The folder has been deleted", @"Seafile")];
            return;
        }
    
        //check if is encrypted
        if ([(SeafRepo *)entry passwordRequiredWithSyncRefresh]){
            SeafRepo *repo = [[SeafRepo alloc] initWithConnection:starredRepo->connection andRepoId:starredRepo.repoId andRepoName:starredRepo.repoName];
            @weakify(self);
            [self popupSetRepoPassword:(SeafRepo *)repo handler:^{
                @strongify(self);
                [self selectDirOrRepo:starredRepo];//push fileViewController
            }];
        } else {
            [self selectDirOrRepo:starredRepo];
        }
    } else if ([entry isKindOfClass:[SeafStarredFile class]]) {
        SeafStarredFile *tempSFile = (SeafStarredFile *)entry;
        if (tempSFile.isDeleted) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"The file has been deleted", @"Seafile")];
            return;
        }
        SeafStarredFile *sfile;
        @try {
            sfile = [_cellDataArray objectAtIndex:indexPath.row];
            
            if ([(SeafRepo *)entry passwordRequiredWithSyncRefresh]){
                Debug("Star file %@ repo %@ password required.", sfile.name, sfile.repoId);
                SeafRepo *repo = [[SeafRepo alloc] initWithConnection:sfile->connection andRepoId:sfile.repoId andRepoName:sfile.repoName];
                @weakify(self);
                [self popupSetRepoPassword:(SeafRepo *)repo handler:^{
                    @strongify(self);
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
}

//creat subDirs SeafDirArray
- (NSArray *)createSubdirsFromTargetDir:(SeafBase *)aDir{
    NSArray *components = [aDir.path componentsSeparatedByString:@"/"];
    NSMutableArray *filteredComponents = [components mutableCopy];
    if (filteredComponents.count > 1) {//remove last ""
        [filteredComponents removeLastObject];
    } else if (filteredComponents.count == 0) {//is error
        return nil;
    }
    
    NSMutableArray *dirArray = [[NSMutableArray alloc]init];
    
    NSMutableString *creatDirPath = [[NSMutableString alloc]initWithString:@"/"];
    for (NSString *subPath in filteredComponents) {
        NSString *repoName = subPath;
        if ([subPath length] == 0){
            repoName = aDir.repoName;
        } else {
            [creatDirPath appendString:subPath];
        }
        NSString *pathStr = [NSString stringWithString:creatDirPath];
        SeafDir *newDir = [[SeafDir alloc]initWithConnection:aDir->connection oid:nil repoId:aDir.repoId perm:nil name:repoName path:pathStr];
       
        [dirArray addObject:newDir];
        if ([subPath length] > 0){
            [creatDirPath appendString:@"/"];
        }
    }
    
    for (SeafDir *d in dirArray){
        Debug(@"dPath ===== %@", d.path);
    }
    return dirArray;
}

- (SeafCell *)getEntryCell:(id)entry
{
    NSUInteger index = [_cellDataArray indexOfObject:entry];

    if (index == NSNotFound)
        return nil;
    @try {
        NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
        return (SeafCell *)[self.tableView cellForRowAtIndexPath:path];
    } @catch(NSException *exception) {
        return nil;
    }
}

- (void)updateEntryCell:(SeafBase *)entry
{
    SeafCell *cell = [self getEntryCell:entry];
    if ([entry isKindOfClass:[SeafStarredFile class]]) {
        [self updateCellContent:cell file:(SeafStarredFile *)entry];
    } else {
        [self updateCellContent:cell dir:(SeafStarredDir *)entry];
    }
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
    [self updateEntryCell:(SeafBase *)entry];
    [self.detailViewController download:entry complete:updated];
}
- (void)download:(SeafBase *)entry failed:(NSError *)error
{
    [self updateEntryCell:(SeafFile *)entry];
    [self.detailViewController download:entry failed:error];
}

#pragma mark - SeafFileUpdateDelegate
- (void)updateProgress:(SeafFile *)file progress:(float)progress
{
    [self updateEntryCell:file];
}
- (void)updateComplete:(nonnull SeafFile * )file result:(BOOL)res
{
    if (!res) {
        if (!file.ufile || file.ufile.shouldShowUploadFailure) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to upload file", @"Seafile")];
        }
    }
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

    SeafCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    NSString *title = NSLocalizedString(@"Navigate to Folder", @"Seafile");
    
    NSString *unStar = S_UNSTAR;

    NSArray *titles = @[title,unStar];

    [self showSheetWithTitles:titles andFromIndex:indexPath andView:cell];
}

- (void)showSheetWithTitles:(NSArray*)titles andFromIndex:(NSIndexPath *)cellIndexPath andView:(id)view{
    SeafActionSheet *actionSheet = [SeafActionSheet actionSheetWithoutCancelWithTitles:titles];
    actionSheet.targetVC = self;

    [actionSheet setButtonPressedBlock:^(SeafActionSheet *actionSheet, NSIndexPath *indexPath){
        [actionSheet dismissAnimated:YES];
        if (indexPath.section == 0) {
            [self locateToTargetPathFromIndex:cellIndexPath.row];
        } else if (indexPath.section == 1){
            [self setUnstar:cellIndexPath.row];
        }
    }];
    
    [actionSheet showFromView:view];
}

-(void)cellMoreAction{
    SeafFile *file = (SeafFile *)[_cellDataArray objectAtIndex:_selectedindex.row];
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

- (void)deleteRow:(NSInteger)row {
    if (row < _cellDataArray.count) {
        [_cellDataArray removeObjectAtIndex:row];
        
        //refresh tableView
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        [self.tableView beginUpdates];
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self.tableView endUpdates];
    }
}

//set unStar
- (void)setUnstar:(NSInteger)cellIndex {
    SeafBase *entry = [_cellDataArray objectAtIndex:cellIndex];
    [entry setStarred:NO];
    [self deleteRow:cellIndex];
}

- (void)locateToTargetPathFromIndex:(NSInteger)cellIndex {
    SeafBase *entry = [_cellDataArray objectAtIndex:cellIndex];
    NSArray *dirDataArray;
    if (entry.isDeleted) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"The file has been deleted", @"Seafile")];
        return;
    }
    if ([(SeafRepo *)entry passwordRequiredWithSyncRefresh]){
        SeafRepo *repo = [[SeafRepo alloc] initWithConnection:entry->connection andRepoId:entry.repoId andRepoName:entry.repoName];
        @weakify(self);
        return [self popupSetRepoPassword:repo handler:^{
            @strongify(self);
            [self locateToTargetPathFromIndex:cellIndex];//push fileViewController
        }];
    }
    dirDataArray = [self createSubdirsFromTargetDir:(SeafBase *)entry];
    
    // get the firest tab 的 UINavigationController
    UINavigationController *navController;
    if (IsIpad()){
        UISplitViewController *fileController = self.tabBarController.viewControllers[0];
        navController = [fileController.viewControllers firstObject];
    } else {
        navController = self.tabBarController.viewControllers[0];
    }
        
    // make sure navController is UINavigationController
    if ([navController isKindOfClass:[UINavigationController class]]) {
        [navController popToRootViewControllerAnimated:NO];
    }
    
    NSMutableArray *createdNavgationControllers = [[NSMutableArray alloc]init];
    UIViewController *rootViewController = [navController.viewControllers firstObject];
    [createdNavgationControllers addObject:rootViewController];
    
    for (SeafDir *seafDir in dirDataArray) {
        SeafFileViewController *controller;
        if (IsIpad()){
            controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
        } else {
            controller = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"FILEMASTERVC"];
        }
        [controller setDirectory:seafDir];
        [seafDir setDelegate:controller];
        [createdNavgationControllers addObject:controller];
    }
    
    [navController setViewControllers:createdNavgationControllers animated:NO];
    
    self.tabBarController.selectedIndex = 0;
}

@end
