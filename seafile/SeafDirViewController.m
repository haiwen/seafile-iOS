//
//  SeafUploadDirVontrollerViewController.m
//  seafile
//
//  Created by Wang Wei on 10/20/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//
#import "UIScrollView+SVPullToRefresh.h"

#import "SeafDirViewController.h"
#import "SeafAppDelegate.h"
#import "SeafDir.h"
#import "SeafRepos.h"
#import "SeafCell.h"
#import "Debug.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "SeafDestCell.h"

@interface SeafDirViewController ()<SeafDentryDelegate>
@property (strong) UIBarButtonItem *chooseItem;
@property (strong, readonly) SeafDir *directory;
@property (readwrite) BOOL chooseRepo;
@property (nonatomic, strong) NSArray *subDirs;
@property (nonatomic, strong) NSArray *destDisplayItems; // dirs + files for destination style
@property (nonatomic, strong) UIView *returnHeaderView;
@property (strong) SeafDirChoose dirChoose;
@property (strong) SeafDirCancelChoose dirCancel;
// Private helpers
- (void)updateReturnHeader;
- (void)onTapReturnHeader;
- (NSString *)repoGroupTitleForSection:(NSInteger)section;
- (void)applyRoundedCornersIfNeeded;
@end

@implementation SeafDirViewController

// Custom initializer with directory, selection handlers, and a flag to choose repositories
- (id)initWithSeafDir:(SeafDir *)dir dirChosen:(SeafDirChoose)choose cancel:(SeafDirCancelChoose)cancel chooseRepo:(BOOL)chooseRepo
{
    if (self = [super init]) {
        _directory = dir;
        _directory.delegate = self;
        [_directory loadContent:NO];
        _dirChoose = choose;
        _dirCancel = cancel;
        _chooseRepo = chooseRepo;
        self.tableView.delegate = self;
    }
    return self;
}

// Overloaded initializer for initializing with a delegate instead of blocks
- (id)initWithSeafDir:(SeafDir *)dir delegate:(id<SeafDirDelegate>)delegate chooseRepo:(BOOL)chooseRepo
{
    return [self initWithSeafDir:dir dirChosen:^(UIViewController *c, SeafDir *dir) {
        [delegate chooseDir:c dir:dir];
    } cancel:^(UIViewController *c) {
        [delegate cancelChoose:c];
    } chooseRepo:chooseRepo];
    return self;
}

- (void)cancel:(id)sender
{
    self.dirCancel(self);
}

// Method to handle the confirmation of the directory selection
- (IBAction)chooseFolder:(id)sender
{
    self.dirChoose(self, _directory);// Call the choose block with the current directory
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Align cell sizing with file list page
    self.tableView.estimatedRowHeight = 55;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0;
    }
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafDirCell" bundle:nil]
         forCellReuseIdentifier:@"SeafDirCell"];
    if (self.useDestinationStyle) {
        [self.tableView registerClass:[SeafDestCell class] forCellReuseIdentifier:@"SeafDestCell"];
        // Apply rounded corners directly on the tableView
        self.tableView.backgroundColor = [UIColor whiteColor];
        self.tableView.opaque = NO;
        [self applyRoundedCornersIfNeeded];
    }

    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;
    [self.navigationItem setHidesBackButton:[self.directory isKindOfClass:[SeafRepos class]]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:STR_CANCEL style:UIBarButtonItemStylePlain target:self action:@selector(cancel:)];
    self.tableView.scrollEnabled = YES;
    
    // Setup the toolbar items
    UIBarButtonItem *flexibleFpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.chooseItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(chooseFolder:)];
    self.chooseItem.tintColor = BAR_COLOR;
    NSArray *items = [NSArray arrayWithObjects:flexibleFpaceItem, self.chooseItem, flexibleFpaceItem, nil];
    [self setToolbarItems:items];

    // Setup the refresh control for pull-to-refresh functionality
    self.tableView.refreshControl = [[UIRefreshControl alloc] init];
    [self.tableView.refreshControl addTarget:self action:@selector(refreshControlChanged) forControlEvents:UIControlEventValueChanged];

    // Setup return-to-parent header if needed
    [self updateReturnHeader];
    Debug("[DestPicker] viewDidLoad path=%@, repo=%@, vc=%p", _directory.path, _directory.repoId, self);
}

- (void)refreshControlChanged {
    if (!self.tableView.isDragging) {
        [self pullToRefresh];
    }
}

- (void)pullToRefresh {
    if (![self checkNetworkStatus]) {// Check network status and stop if not connected
        [self performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:0.1];
        return;
    }
    _subDirs = nil;
    _destDisplayItems = nil;
    
    self.tableView.accessibilityElementsHidden = YES;
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.tableView.refreshControl);
    self.directory.delegate = self;
    [self.directory loadContent:YES];// Reload the directory content with force
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (self.tableView.refreshControl.isRefreshing) {
        [self pullToRefresh];
    }
}

// Method to set the current operation state and adjust the title accordingly
- (void)setOperationState:(OperationState)operationState {
    _operationState = operationState;
    if (_operationState == OPERATION_STATE_COPY) {
        self.title = NSLocalizedString(@"Copy", @"Seafile");
    } else if (_operationState == OPERATION_STATE_MOVE) {
        self.title = NSLocalizedString(@"Move", @"Seafile");
    } else {
        self.title = _directory.name;
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.useDestinationStyle) {
        // In destination picker shell, the outer controller provides its own bottom bar.
        // Always hide the internal toolbar (OK button) to avoid duplication.
        [self.navigationController setToolbarHidden:YES];
    } else {
        [self.navigationController setToolbarHidden:_chooseRepo];
    }
    [self.chooseItem setEnabled:_directory.editable];// Enable the choose item if the directory is editable
    Debug("[DestPicker] viewWillAppear path=%@, stackCount=%lu, useDest=%d, showOnRoot=%d", _directory.path, (unsigned long)self.navigationController.viewControllers.count, self.useDestinationStyle, self.showReturnHeaderOnRoot);
    [self updateReturnHeader];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self applyRoundedCornersIfNeeded];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if ([_directory isKindOfClass:[SeafRepos class]]) {
        return ((SeafRepos *)_directory).repoGroups.count;
    }
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (!self.useDestinationStyle) return NSLocalizedString(@"Choose directory", @"Seafile");
    if ([_directory isKindOfClass:[SeafRepos class]]) return nil; // use custom header view
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (self.useDestinationStyle && [_directory isKindOfClass:[SeafRepos class]]) return 36.0;
    if (self.useDestinationStyle) return CGFLOAT_MIN;
    return UITableViewAutomaticDimension;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (!(self.useDestinationStyle && [_directory isKindOfClass:[SeafRepos class]])) return nil;
    // Build compact header with no top padding
    NSString *text = [self repoGroupTitleForSection:section] ?: @"";
    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    header.backgroundColor = [UIColor systemBackgroundColor];
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.textColor = [UIColor secondaryLabelColor];
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        // Vertically center, align to left with 16pt inset
        [label.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:26],
        [header.trailingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:16]
    ]];
    return header;
}


// Loading of subdirectories to improve performance.
- (NSArray *)subDirs
{
    if (!_subDirs) {
        NSMutableArray *arr = [NSMutableArray new];
        if ([_directory isKindOfClass:[SeafRepos class]]) {
            SeafRepos *repos = (SeafRepos *)_directory;
            // Iterate over repositories, adding those that are either editable or when _chooseRepo is false.
            for (int i = 0; i < repos.repoGroups.count; ++i) {
                for (SeafRepo *repo in [repos.repoGroups objectAtIndex:i]) {
                    if (!_chooseRepo || repo.editable) {
                        [arr addObject:repo];
                    }
                }
            }
        } else {
            // Iterate over directories, adding those that are either editable or when _chooseRepo is false.
            for (SeafDir *dir in _directory.subDirs) {
                if (!_chooseRepo || dir.editable) {
                    [arr addObject:dir];
                }
            }
        }
        _subDirs = [NSArray arrayWithArray:arr];
    }
    return _subDirs;
}

// Build display items for destination picker: directories and files mixed
- (NSArray *)destDisplayItems
{
    if (!self.useDestinationStyle)
        return self.subDirs;

    if (_destDisplayItems) return _destDisplayItems;

    NSMutableArray *arr = [NSMutableArray new];
    if ([_directory isKindOfClass:[SeafRepos class]]) {
        // At repositories root, keep the same logic as subDirs (list repos only)
        return (self.destDisplayItems = self.subDirs);
    } else {
        for (SeafBase *entry in _directory.allItems) {
            if ([entry isKindOfClass:[SeafDir class]]) {
                SeafDir *dir = (SeafDir *)entry;
                if (!self.chooseRepo || dir.editable) {
                    [arr addObject:dir];
                }
            } else if ([entry isKindOfClass:[SeafFile class]]) {
                // Files are shown but not selectable as destination
                [arr addObject:entry];
            }
        }
    }
    _destDisplayItems = [NSArray arrayWithArray:arr];
    return _destDisplayItems;
}

- (NSString *)repoGroupTitleForSection:(NSInteger)section
{
    NSArray *repoGroups = ((SeafRepos *)_directory).repoGroups;
    if (section >= (NSInteger)repoGroups.count) return @"";
    NSArray *repos = repoGroups[section];
    if (repos.count == 0) return @"";
    SeafRepo *repo = repos.firstObject;
    if ([repo.type isEqualToString:SHARE_REPO]) {
        return NSLocalizedString(@"Shared to me", @"Seafile");
    } else if ([repo.type isEqualToString:PUBLIC_REPO]) {
        return NSLocalizedString(@"Shared with all", @"Seafile");
    } else if ([repo.type isEqualToString:GROUP_REPO]) {
        if (repo.groupName.length == 0) return NSLocalizedString(@"Shared with groups", @"Seafile");
        if ([repo.groupName isEqualToString:ORG_REPO]) return NSLocalizedString(@"Organization", @"Seafile");
        return repo.groupName;
    } else if (section == 0) {
        return NSLocalizedString(@"My Own Libraries", @"Seafile");
    } else {
        return (repo.owner && ![repo.owner isKindOfClass:[NSNull class]]) ? ([repo.owner isEqualToString:ORG_REPO] ? NSLocalizedString(@"Organization", @"Seafile") : repo.owner) : @"";
    }
}

#pragma mark - Return Header (destination style only)
- (void)updateReturnHeader
{
    // Show only when in destination style and not at root controller
    BOOL shouldShow = self.useDestinationStyle && (self.showReturnHeaderOnRoot || (self.navigationController.viewControllers.firstObject != self));
    // Do NOT show header on repo list (SeafRepos), even when not root
    if (shouldShow && [_directory isKindOfClass:[SeafRepos class]]) {
        shouldShow = NO;
    }
    Debug("[DestPicker] updateReturnHeader shouldShow=%d, path=%@, stackCount=%lu", shouldShow, _directory.path, (unsigned long)self.navigationController.viewControllers.count);
    if (!shouldShow) {
        self.tableView.tableHeaderView = nil;
        self.returnHeaderView = nil;
        return;
    }
    if (self.returnHeaderView) {
        self.tableView.tableHeaderView = self.returnHeaderView;
        return;
    }
    CGFloat height = 48.0;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, height)];
    header.backgroundColor = [UIColor systemBackgroundColor];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"return"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [UIColor systemGrayColor];
    [header addSubview:icon];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = NSLocalizedString(@"Return to previous level", @"Seafile");
    label.textColor = [UIColor secondaryLabelColor];
    label.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    [header addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [icon.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:20],
        [icon.heightAnchor constraintEqualToConstant:20],

        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [label.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [header.trailingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:16],
        [header.heightAnchor constraintGreaterThanOrEqualToConstant:height]
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapReturnHeader)];
    [header addGestureRecognizer:tap];
    header.isAccessibilityElement = YES;
    header.accessibilityLabel = label.text;
    self.returnHeaderView = header;
    self.tableView.tableHeaderView = header;
}

- (void)onTapReturnHeader
{
    UINavigationController *nav = self.navigationController;
    NSUInteger count = nav.viewControllers.count;
    Debug("[DestPicker] onTapReturnHeader tapped, stackCount=%lu, path=%@, self=%p", (unsigned long)count, _directory.path, self);
    if (count > 1) {
        [nav popViewControllerAnimated:YES];
    } else {
        // At repo root under Current library: navigate to repo list (SeafRepos) in the same stack.
        SeafDir *reposRoot = _directory.connection.rootFolder;
        if (reposRoot) {
            SeafDirViewController *controller = [[SeafDirViewController alloc] initWithSeafDir:reposRoot dirChosen:_dirChoose cancel:_dirCancel chooseRepo:false];
            controller.operationState = self.operationState;
            controller.useDestinationStyle = self.useDestinationStyle;
            controller.showReturnHeaderOnRoot = NO; // repo list root should not show header
            Debug("[DestPicker] onTapReturnHeader push repo list (no animation), vc=%p", controller);
            [nav pushViewController:controller animated:NO];
        } else {
            Debug("[DestPicker] onTapReturnHeader root but reposRoot nil");
        }
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if ([_directory isKindOfClass:[SeafRepos class]]) {
        NSArray *repoGroups = ((SeafRepos *)_directory).repoGroups;
        if (section >= (NSInteger)repoGroups.count) return 0;
        NSArray *repos = repoGroups[section];
        return repos.count;
    }
    if (self.useDestinationStyle)
        return self.destDisplayItems.count;
    return self.subDirs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = self.useDestinationStyle ? @"SeafDestCell" : @"SeafDirCell";
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        if (self.useDestinationStyle) {
            cell = [[SeafDestCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        } else {
            NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
            cell = [cells objectAtIndex:0];
        }
    }
    if (self.useDestinationStyle) {
        cell.backgroundColor = [UIColor clearColor];
        cell.contentView.backgroundColor = [UIColor clearColor];
        if ([cell respondsToSelector:@selector(cellBackgroundView)] && [(id)cell cellBackgroundView]) {
            UIView *bg = [(id)cell cellBackgroundView];
            bg.backgroundColor = [UIColor clearColor];
        }
    }
    [cell reset];

    @try {
        id entry = nil;
        if ([_directory isKindOfClass:[SeafRepos class]]) {
            NSArray *repos = [((SeafRepos *)_directory).repoGroups objectAtIndex:indexPath.section];
            entry = repos[indexPath.row];
        } else {
            entry = self.useDestinationStyle ? [self.destDisplayItems objectAtIndex:indexPath.row] : [self.subDirs objectAtIndex:indexPath.row];
        }
        cell.moreButton.hidden = YES;
        cell.detailTextLabel.text = @"";

        if ([entry isKindOfClass:[SeafRepo class]]) {
            SeafRepo *repo = (SeafRepo *)entry;
            cell.textLabel.text = repo.name;
            cell.imageView.image = repo.icon;
            if (repo.isGroupRepo) {
                if (repo.owner.length > 0) {
                    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@, %@", repo.detailText, repo.owner];
                }
            } else {
                cell.detailTextLabel.text = repo.detailText;
            }
        } else if ([entry isKindOfClass:[SeafDir class]]) {
            SeafDir *sdir = (SeafDir *)entry;
            cell.textLabel.text = sdir.name;
            cell.imageView.image = sdir.icon;
            if (self.useDestinationStyle) {
                cell.detailTextLabel.text = [sdir detailText];
            }
        } else if ([entry isKindOfClass:[SeafFile class]]) {
            SeafFile *file = (SeafFile *)entry;
            cell.textLabel.text = file.name;
            cell.imageView.image = file.icon;
            cell.detailTextLabel.text = file.detailText ?: @""; // e.g., size · date
            cell.selectionStyle = UITableViewCellSelectionStyleNone; // not selectable as destination
        }
    } @catch(NSException *exception) {
    }
    return cell;
}
// Ensure the internal wrapper view gets the same corner radius; otherwise UITableView may not clip content
- (void)applyRoundedCornersIfNeeded
{
    if (!self.useDestinationStyle) return;
    CGFloat radius = 16.0;
    self.tableView.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) self.tableView.layer.cornerCurve = kCACornerCurveContinuous;
    self.tableView.clipsToBounds = YES;
    for (UIView *sub in self.tableView.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls containsString:@"WrapperView"] || [cls containsString:@"TableView"] || [cls containsString:@"ScrollView"]) {
            sub.layer.cornerRadius = radius;
            sub.clipsToBounds = YES;
        }
    }
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}


#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    id entry;
    @try {
        if ([_directory isKindOfClass:[SeafRepos class]]) {
            NSArray *repos = [((SeafRepos *)_directory).repoGroups objectAtIndex:indexPath.section];
            entry = repos[indexPath.row];
        } else {
            entry = self.useDestinationStyle ? [self.destDisplayItems objectAtIndex:indexPath.row] : [self.subDirs objectAtIndex:indexPath.row];
        }
    } @catch(NSException *exception) {
        [self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
        return;
    }

    // Tapping files is ignored in destination style
    if (self.useDestinationStyle && [entry isKindOfClass:[SeafFile class]]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }

    if (![entry isKindOfClass:[SeafDir class]])
        return;

    // Choose directory or handle repository with password.
    SeafDir *curDir = (SeafDir *)entry;
    if (_chooseRepo) {
        return self.dirChoose(self, curDir);
    }
    if ([curDir isKindOfClass:[SeafRepo class]] && [(SeafRepo *)curDir passwordRequiredWithSyncRefresh]) {
        return [self popupSetRepoPassword:(SeafRepo *)curDir];
    }
    SeafDirViewController *controller = [[SeafDirViewController alloc] initWithSeafDir:curDir dirChosen:_dirChoose cancel:_dirCancel chooseRepo:false];
    controller.operationState = self.operationState;
    controller.useDestinationStyle = self.useDestinationStyle;
    controller.showReturnHeaderOnRoot = self.showReturnHeaderOnRoot;
    Debug("[DestPicker] push to child dir=%@, path=%@ from=%p", curDir.name, curDir.path, self);
    [self.navigationController pushViewController:controller animated:YES];
}

// Display a popup to set the repository password if required.
- (void)popupSetRepoPassword:(SeafRepo *)repo
{
    @weakify(self);
    [self popupSetRepoPassword:repo handler:^{
        @strongify(self);
        [SVProgressHUD dismiss];
        SeafDirViewController *controller = [[SeafDirViewController alloc] initWithSeafDir:repo dirChosen:_dirChoose cancel:_dirCancel chooseRepo:false];
        controller.operationState = self.operationState;
        controller.useDestinationStyle = self.useDestinationStyle;
        controller.showReturnHeaderOnRoot = self.showReturnHeaderOnRoot;
        [self.navigationController pushViewController:controller animated:YES];
    }];
}

#pragma mark - SeafDentryDelegate
- (void)download:(SeafBase *)entry progress:(float)progress
{

}

// Handle the completion of a download operation.
- (void)download:(SeafBase *)entry complete:(BOOL)updated
{
    [self doneLoadingTableViewData];
    if (updated && [self isViewLoaded]) {
        _subDirs = nil;
        _destDisplayItems = nil;
        [self.tableView reloadData];
    }
}

// Handle failures in the download operation.
- (void)download:(SeafBase *)entry failed:(NSError *)error
{
    [self doneLoadingTableViewData];
    if ([_directory hasCache])
        return;

    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load content of the directory", @"Seafile")];
    [self.tableView reloadData];
    Warning("Failed to load directory content %@\n", _directory.name);
}

- (void)viewDidUnload
{
    [super viewDidUnload];
}

// Clean up and reset after data is loaded.
- (void)doneLoadingTableViewData
{
    self.tableView.accessibilityElementsHidden = NO;
    [self.tableView.refreshControl endRefreshing];
}
@end
