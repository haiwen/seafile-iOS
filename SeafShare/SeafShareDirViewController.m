//
//  SeafShareDirViewController.m
//  seafilePro
//
//  Created by three on 2018/8/2.
//  Copyright © 2018年 Seafile. All rights reserved.
//

#import "SeafShareDirViewController.h"
#import "UIViewController+Extend.h"
#import "UIScrollView+SVPullToRefresh.h"
#import "Utils.h"
#import "Debug.h"
#import "ExtentedString.h"
#import "SeafGlobal.h"

#import "SeafFileOperationManager.h"
#import "SeafFileViewController.h"
#import "SeafCell.h"
#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "Constants.h"
#import "SeafNavLeftItem.h"
#import "SeafRepos.h"
#import "SeafBase+Display.h"

@interface SeafShareDirViewController ()<SeafDentryDelegate, UITableViewDelegate, UITableViewDataSource>

@property (strong, nonatomic) SeafDir *directory;
@property (copy, nonatomic) NSArray *subDirs;
@property (copy, nonatomic) NSArray *destDisplayItems;
@property (strong, nonatomic) UIBarButtonItem *saveButton;
@property (strong, nonatomic) UIBarButtonItem *createButton;
@property (strong, nonatomic) UIActivityIndicatorView *loadingView;
@property (strong, nonatomic) UITableView *tableView;
/// Rounded clip pinned to the visible area of the file-list card so the card keeps
/// its rounded frame while scrolling (the per-cell corners only round the first/last row).
@property (strong, nonatomic) CALayer *cardCornerMaskLayer;

@end

@implementation SeafShareDirViewController

@dynamic currentDirectory;

- (SeafDir *)currentDirectory {
    return _directory;
}

- (id)initWithSeafDir:(SeafDir *)directory {
    if (self = [super init]) {
        _directory = directory;
        _directory.delegate = self;
        [_directory loadContent:NO];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [SeafTheme applyPreferenceToViewController:self];
    
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;
    
    // All lists use plain style so section headers stick to the top while scrolling.
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 55;
    self.tableView.estimatedSectionFooterHeight = 0;
    self.tableView.estimatedSectionHeaderHeight = 0;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barAppearance = [UINavigationBarAppearance new];
        barAppearance.backgroundColor = [SeafTheme primarySurface];

        self.navigationController.navigationBar.standardAppearance = barAppearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = barAppearance;

        UIToolbarAppearance *toolbarAppearance = [UIToolbarAppearance new];
        toolbarAppearance.backgroundColor = [SeafTheme primarySurface];
        self.navigationController.toolbar.standardAppearance = toolbarAppearance;
        self.navigationController.toolbar.scrollEdgeAppearance = toolbarAppearance;

        self.tableView.sectionHeaderTopPadding = 0;
    }
    
    self.navigationController.navigationBar.tintColor = BAR_COLOR;

    NSMutableArray *items = [NSMutableArray array];
    
    if (_directory.editable && !self.browseOnly) {
        // Create buttons
        UIImage *addFolderIcon = [[UIImage imageNamed:@"share_addFile"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIButton *addBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [addBtn setImage:addFolderIcon forState:UIControlStateNormal];
        addBtn.tintColor = [SeafTheme primaryText];
        // Use Auto Layout constraints to enforce size so it does not stretch
        addBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [addBtn.widthAnchor constraintEqualToConstant:24].active = YES;
        [addBtn.heightAnchor constraintEqualToConstant:24].active = YES;
        [addBtn addTarget:self action:@selector(createFolder) forControlEvents:UIControlEventTouchUpInside];
        self.createButton = [[UIBarButtonItem alloc] initWithCustomView:addBtn];
        self.navigationController.toolbarHidden = true;
        
        // Create custom text button "OK"
        UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [saveBtn setTitle:NSLocalizedString(@"OK", @"Seafile") forState:UIControlStateNormal];
        saveBtn.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        [saveBtn setTitleColor:[SeafTheme primaryText] forState:UIControlStateNormal];
        saveBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [saveBtn.widthAnchor constraintEqualToConstant:80].active = YES;
        [saveBtn.heightAnchor constraintEqualToConstant:50].active = YES;
        [saveBtn addTarget:self action:@selector(save:) forControlEvents:UIControlEventTouchUpInside];
        self.saveButton = [[UIBarButtonItem alloc] initWithCustomView:saveBtn];
        
        // Toolbar items: center the save button
        UIBarButtonItem *flexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        [self setToolbarItems:@[flexItem, self.saveButton, flexItem] animated:true];
        
        // Customize toolbar background color (adapts to light/dark via grouped surface token)
        if (@available(iOS 15.0, *)) {
            UIToolbarAppearance *toolAppear = [UIToolbarAppearance new];
            [toolAppear configureWithOpaqueBackground];
            toolAppear.backgroundColor = [SeafTheme groupedSurface];
            self.navigationController.toolbar.standardAppearance = toolAppear;
            self.navigationController.toolbar.scrollEdgeAppearance = toolAppear;
        } else {
            self.navigationController.toolbar.barTintColor = [SeafTheme groupedSurface];
        }
        
        // Navigation bar right contains New Folder
        [items addObject:self.createButton];
        self.navigationItem.title = _directory.name;
        

    }
    
    self.navigationItem.rightBarButtonItems = items;
    [self refreshView];
    
    __weak typeof(self) weakSelf = self;
    [self.tableView addPullToRefresh:[SVArrowPullToRefreshView class] withActionHandler:^{
        weakSelf.directory.delegate = weakSelf;
        [weakSelf reloadContent];
    }];
    
    // Register cells
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafCell" bundle:nil] forCellReuseIdentifier:@"SeafCell"];
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafDirCell" bundle:nil] forCellReuseIdentifier:@"SeafDirCell"];
    if (self.useDestinationStyle) {
        // Match SeafFileViewController list chrome (card cells, margins, separators).
        UIView *bgView = [[UIView alloc] initWithFrame:self.tableView.bounds];
        bgView.backgroundColor = kPrimaryBackgroundColor;
        self.tableView.backgroundView = bgView;
        self.tableView.backgroundColor = kPrimaryBackgroundColor;
        self.tableView.tableFooterView = [UIView new];
        self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
        self.tableView.layoutMargins = UIEdgeInsetsMake(0, 15, 0, 15);
        self.tableView.separatorInset = SEAF_SEPARATOR_INSET;
    } else {
        UIView *bgView = [[UIView alloc] initWithFrame:self.tableView.bounds];
        bgView.backgroundColor = kPrimaryBackgroundColor;
        self.tableView.backgroundView = bgView;
    }
    self.view.backgroundColor = kPrimaryBackgroundColor;
    
    // Add blank top space similar to SeafFileViewController (skip in dest style)
    if (!self.useDestinationStyle) {
        self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 10.0)];
    }
    
    // Adjust safe-area insets
    [self updateTableInsets];
    // The rounded card mask is installed lazily in updateCardCornerMask once the table
    // has a valid (non-zero) bounds, driven by viewDidLayoutSubviews.
}



- (void)reloadContent {
    [self.directory loadContent:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.browseOnly) {
        self.navigationController.toolbarHidden = YES;
    } else {
        self.navigationController.toolbarHidden = _directory.editable ? NO : YES;
    }
    // Clear stale selection left from a prior push so labels don't render
    // with SeafCell's white highlightedColor (invisible on light backgrounds).
    if (self.useDestinationStyle) {
        for (NSIndexPath *path in [self.tableView indexPathsForSelectedRows] ?: @[]) {
            [self.tableView deselectRowAtIndexPath:path animated:NO];
        }
    }
}

- (BOOL)isRootReposMode {
    return self.useDestinationStyle && [_directory isKindOfClass:[SeafRepos class]];
}

/// A sub-directory file list (single section, no group headers). The card here is the
/// union of the per-cell white backgrounds inset by SEAF_CARD_HORIZONTAL_PADDING.
- (BOOL)isFileListCardMode {
    return self.useDestinationStyle && ![_directory isKindOfClass:[SeafRepos class]];
}

#pragma mark - Card corner mask (rounded frame while scrolling)

// The per-cell logic only rounds the first/last row, so once those rows scroll off the
// card looks square-edged. Clip the table content to a rounded rect that stays pinned to
// the visible viewport (updated on scroll/layout) so the rounded frame is always shown.
// Not applied in root repos mode, whose group headers live outside the cards.
- (void)updateCardCornerMask {
    if (![self isFileListCardMode]) return;
    UITableView *tv = self.tableView;
    CGFloat top = 0.0;
    if (@available(iOS 11.0, *)) top = tv.adjustedContentInset.top;
    CGFloat x = SEAF_CARD_HORIZONTAL_PADDING;
    CGFloat w = tv.bounds.size.width - 2 * SEAF_CARD_HORIZONTAL_PADDING;
    CGFloat y = tv.contentOffset.y + top;
    CGFloat h = tv.bounds.size.height - top;
    if (w <= 0 || h <= 0) return; // Not laid out yet; avoid a zero-frame mask hiding the table.

    // Install the mask lazily so it is only ever assigned with a valid frame.
    if (!self.cardCornerMaskLayer) {
        CALayer *mask = [CALayer layer];
        mask.backgroundColor = [UIColor blackColor].CGColor;
        mask.cornerRadius = SEAF_CELL_CORNER;
        if (@available(iOS 13.0, *)) mask.cornerCurve = kCACornerCurveContinuous;
        self.cardCornerMaskLayer = mask;
        self.tableView.layer.mask = mask;
        self.tableView.showsHorizontalScrollIndicator = NO;
    }

    // Follow contentOffset every frame; suppress the implicit position animation.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.cardCornerMaskLayer.frame = CGRectMake(x, y, w, h);
    [CATransaction commit];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateCardCornerMask];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self updateCardCornerMask];
    }
}

- (void)refreshView {
    if ([self isViewLoaded]) {
        [self.tableView reloadData];
        if (_directory && !_directory.hasCache) {
            [self showLoadingView];
        } else {
            [self dismissLoadingView];
        }
    }
    [self setupNavigationItems];
}

#pragma mark- action
- (void)createFolder {
    [self popupInputView:NSLocalizedString(@"New Folder", @"Seafile") placeholder:NSLocalizedString(@"New folder name", @"Seafile") secure:false handler:^(NSString *input) {
        if (input == nil) {
            // User tapped cancel; simply return without any prompt
            return;
        }
        if (input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Folder name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"Folder name invalid", @"Seafile")];
            return;
        }
        [self showLoadingView];
        [[SeafFileOperationManager sharedManager] mkdir:input inDir:self.directory completion:^(BOOL success, NSError * _Nullable error) {
            [self dismissLoadingView];
            if (!success) {
                [self alertWithTitle:NSLocalizedString(@"Failed to create folder", @"Seafile") handler:nil];
            } else {
                // Reload directory so the newly-created folder appears in the list
                [self reloadContent];
            }
        }];
    }];
}

- (void)save:(id)sender {
    // Upload is now handled by SeafShareDestinationViewController via popup dialog.
    // This code path is only reached when browseOnly=NO (legacy toolbar-based flow),
    // which is no longer used by the current Share Extension architecture.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.useDestinationStyle && [_directory isKindOfClass:[SeafRepos class]]) {
        return ((SeafRepos *)_directory).repoGroups.count;
    }
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.useDestinationStyle && [_directory isKindOfClass:[SeafRepos class]]) {
        NSArray *repoGroups = ((SeafRepos *)_directory).repoGroups;
        if (section >= (NSInteger)repoGroups.count) return 0;
        return [repoGroups[section] count];
    }
    _subDirs = _directory.subDirs;
    if (self.useDestinationStyle) {
        return [self buildDestDisplayItems].count;
    }
    return self.subDirs.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if ([self isRootReposMode]) {
        // Section 0 (personal libraries) only shows its title header when it has content
        if (section == 0 && [self tableView:tableView numberOfRowsInSection:0] == 0) {
            return CGFLOAT_MIN;
        }
        // Match the main app's file list section header height (SeafHeaderView).
        return 45.0;
    }
    // Sub-directory: no section header. The "Return to previous level" bar is a
    // fixed header managed by SeafShareDestinationViewController.
    if (self.useDestinationStyle) return CGFLOAT_MIN;
    return 0.01;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if ([self isRootReposMode]) {
        if (section == 0 && [self tableView:tableView numberOfRowsInSection:0] == 0) {
            return nil;
        }
        return [self buildGroupHeaderForSection:section];
    }
    return nil;
}

/// Group title header for root repos mode (labels outside cards).
/// Opaque background so scrolled content doesn't bleed through while the header is pinned.
- (UIView *)buildGroupHeaderForSection:(NSInteger)section {
    NSString *text = [self repoGroupTitleForSection:section] ?: @"";
    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    header.backgroundColor = kPrimaryBackgroundColor;
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    // Match the main app's file list header style (SeafHeaderView): secondaryText color,
    // 15pt regular, vertically centered so section 0 doesn't have a large top gap.
    label.textColor = [SeafTheme secondaryText];
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:24],
        [header.trailingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:17]
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if ([self isRootReposMode]) return CGFLOAT_MIN;
    return CGFLOAT_MIN;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return nil;
}

- (NSString *)repoGroupTitleForSection:(NSInteger)section {
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

- (NSArray *)buildDestDisplayItems {
    if (_destDisplayItems) return _destDisplayItems;
    NSMutableArray *arr = [NSMutableArray new];
    for (SeafBase *entry in _directory.allItems) {
        if ([entry isKindOfClass:[SeafDir class]]) {
            [arr addObject:entry];
        } else if ([entry isKindOfClass:[SeafFile class]]) {
            [arr addObject:entry]; // Files shown but not selectable
        }
    }
    _destDisplayItems = [arr copy];
    return _destDisplayItems;
}

- (SeafBase *)getItemAtIndexPath:(NSIndexPath *)indexPath {
    @try {
        if (self.useDestinationStyle && [_directory isKindOfClass:[SeafRepos class]]) {
            NSArray *repos = [((SeafRepos *)_directory).repoGroups objectAtIndex:indexPath.section];
            return repos[indexPath.row];
        }
        if (self.useDestinationStyle) {
            return [[self buildDestDisplayItems] objectAtIndex:indexPath.row];
        }
        return [self.subDirs objectAtIndex:indexPath.row];
    } @catch(NSException *exception) {
        return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SeafBase *entry = [self getItemAtIndexPath:indexPath];
    if (!entry) return [[UITableViewCell alloc] init];

    if (self.useDestinationStyle) {
        SeafCell *cell = nil;
        if ([entry isKindOfClass:[SeafRepo class]]) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"SeafCell" forIndexPath:indexPath];
            [cell reset];
            SeafRepo *repo = (SeafRepo *)entry;
            cell.textLabel.text = repo.name;
            cell.imageView.image = repo.icon;
            cell.detailTextLabel.text = repo.detailText;
        } else if ([entry isKindOfClass:[SeafDir class]]) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"SeafDirCell" forIndexPath:indexPath];
            [cell reset];
            SeafDir *sdir = (SeafDir *)entry;
            cell.textLabel.text = sdir.name;
            cell.imageView.image = sdir.icon;
            cell.detailTextLabel.text = [sdir detailText];
        } else if ([entry isKindOfClass:[SeafFile class]]) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"SeafCell" forIndexPath:indexPath];
            [cell reset];
            SeafFile *file = (SeafFile *)entry;
            cell.textLabel.text = file.name;
            cell.imageView.image = file.icon;
            cell.detailTextLabel.text = file.detailText ?: @"";
        } else {
            return [[UITableViewCell alloc] init];
        }
        cell.moreButton.hidden = YES;
        cell.cacheStatusView.hidden = YES;
        [cell.cacheStatusWidthConstraint setConstant:0.0f];
        cell.imageView.alpha = 1.0;
        cell.textLabel.alpha = 1.0;
        cell.detailTextLabel.alpha = 1.0;

        [self setCellSeparatorAndCorner:cell andIndexPath:indexPath];

        // Files: shown but dimmed and not selectable in destination picker
        if ([entry isKindOfClass:[SeafFile class]]) {
            cell.imageView.alpha = 0.4;
            cell.textLabel.alpha = 0.4;
            cell.detailTextLabel.alpha = 0.4;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        return cell;
    }

    // Original SeafCell path
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SeafCell" forIndexPath:indexPath];
    [cell reset];

    cell.textLabel.text = entry.name;
    cell.imageView.image = entry.icon;
    cell.moreButton.hidden = YES;

    // Detail text for repo shows size/date, for folder blank
    cell.detailTextLabel.text = [entry displayDetailText];

    [self setCellSeparatorAndCorner:cell andIndexPath:indexPath];

    // Hide cache/progress etc in this list
    cell.cacheStatusView.hidden = YES;
    [cell.cacheStatusWidthConstraint setConstant:0.0f];

    return cell;
}

#pragma mark - Cell styling (mirrors SeafFileViewController)

- (void)setCellSeparatorAndCorner:(SeafCell *)cell andIndexPath:(NSIndexPath *)indexPath {
    BOOL isFirstCell = (indexPath.row == 0);
    BOOL isLastCell = NO;
    if ([_directory isKindOfClass:[SeafRepos class]]) {
        NSArray *repoGroups = ((SeafRepos *)_directory).repoGroups;
        NSArray *repos = [repoGroups objectAtIndex:indexPath.section];
        isLastCell = (indexPath.row == repos.count - 1);
    } else if (self.useDestinationStyle) {
        isLastCell = (indexPath.row == [self buildDestDisplayItems].count - 1);
    } else {
        isLastCell = (indexPath.row == self.subDirs.count - 1);
    }
    [cell updateSeparatorInset:isLastCell];
    [cell updateCellStyle:isFirstCell isLastCell:isLastCell];
}

#pragma mark - Table view delegate


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafBase *entry = [self getItemAtIndexPath:indexPath];
    if (!entry)
        return [self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];

    // Files not selectable in destination style
    if (self.useDestinationStyle && [entry isKindOfClass:[SeafFile class]]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }

    if ([entry isKindOfClass:[SeafRepo class]] && [(SeafRepo *)entry passwordRequired]) {
        [self popupSetRepoPassword:(SeafRepo *)entry];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        [self pushViewControllerDir:(SeafDir *)entry];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
}

- (void)reloadIndex:(NSIndexPath *)indexPath {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (indexPath) {
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            if (!cell) return;
            @try {
                [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
            } @catch(NSException *exception) {
                Warning("Failed to reload cell %@: %@", indexPath, exception);
            }
        } else
            [self.tableView reloadData];
    });
}

- (void)pushViewControllerDir:(SeafDir *)dir {
    SeafShareDirViewController *controller = [[SeafShareDirViewController alloc] initWithSeafDir:dir];
    controller.browseOnly = self.browseOnly;
    controller.useDestinationStyle = self.useDestinationStyle;
    [self.navigationController pushViewController:controller animated:true];
}

- (void)popupSetRepoPassword:(SeafRepo *)repo {
    [repo setDelegate:self];
    [self popupSetRepoPassword:repo handler:^{
        [self pushViewControllerDir:repo];
    }];
}

- (void)showLoadingView {
    if (!self.loadingView.superview) {
        [self.view addSubview:self.loadingView];
        self.loadingView.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [self.loadingView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [self.loadingView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
        ]];
    }
    [self.loadingView startAnimating];
}

- (void)dismissLoadingView {
    [self.loadingView stopAnimating];
}

#pragma mark - SeafDentryDelegate
- (void)download:(SeafBase *)entry progress:(float)progress {
    
}

- (void)download:(SeafBase *)entry complete:(BOOL)updated {
    if (![self isViewLoaded])
        return;
    
    _destDisplayItems = nil; // Clear cached display items
    [self doneLoadingTableViewData];
    if (_directory == entry)
        [self refreshView];
}

- (void)download:(SeafBase *)entry failed:(NSError *)error {
    if (_directory != entry)
        return;
    
    [self doneLoadingTableViewData];
    Warning("Failed to load directory content %@\n", entry.name);
    if ([_directory hasCache]) {
        return;
    } else {
        [self alertWithTitle:NSLocalizedString(@"Failed to load content of the directory", @"Seafile")];
    }
}

- (void)doneLoadingTableViewData {
    [self.tableView.pullToRefreshView stopAnimating];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark -lazy
- (void)setDirectory:(SeafDir *)directory {
    _directory = directory;
    _directory.delegate = self;
    [_directory loadContent:true];
    self.navigationItem.title = _directory.name;
}

- (UIActivityIndicatorView *)loadingView {
    if (!_loadingView) {
        _loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        _loadingView.color = [SeafTheme primaryText];
        _loadingView.hidesWhenStopped = YES;
    }
    return _loadingView;
}

#pragma mark - Safe Area Handling

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self updateTableInsets];
}

- (void)updateTableInsets {
    if (@available(iOS 11.0, *)) {
        CGFloat bottomInset = self.view.safeAreaInsets.bottom;
        UIEdgeInsets inset = self.tableView.contentInset;
        inset.bottom = bottomInset;
        self.tableView.contentInset = inset;
        // In card mode the table is clipped to a rounded rect inset by
        // SEAF_CARD_HORIZONTAL_PADDING, so pull the scroll indicator in to keep it visible.
        UIEdgeInsets indicatorInset = inset;
        if ([self isFileListCardMode]) {
            indicatorInset.right = SEAF_CARD_HORIZONTAL_PADDING;
        }
        self.tableView.scrollIndicatorInsets = indicatorInset;
    }
}

#pragma mark - Navigation helpers implementation

- (void)setupNavigationItems {
    if ([_directory isKindOfClass:[SeafRepos class]]) {
        NSString *title = NSLocalizedString(@"Save to Seafile", @"Seafile");
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:[SeafNavLeftItem navLeftItemWithDirectory:nil title:title target:self action:@selector(backAction)]];
    } else {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:[SeafNavLeftItem navLeftItemWithDirectory:_directory title:nil target:self action:@selector(backAction)]];
    }
    self.navigationItem.title = @"";
}

- (void)backAction {
    [self.navigationController popViewControllerAnimated:YES];
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
