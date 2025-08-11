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
#import "SeafShareFileViewController.h"
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
@property (strong, nonatomic) UIBarButtonItem *saveButton;
@property (strong, nonatomic) UIBarButtonItem *createButton;
@property (strong, nonatomic) UIActivityIndicatorView *loadingView;
@property (strong, nonatomic) UITableView *tableView;

@end

@implementation SeafShareDirViewController

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
    
    // Always display in Light mode
    if (@available(iOS 13.0, *)) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        self.navigationController.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        self.navigationController.navigationBar.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    }
    
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;
    
    CGFloat TOP_DISTANCE = IsIpad()? 0 : 40.0;
    CGRect tableViewFrame = self.view.frame;
    
    if (@available(iOS 13.0, *)) {
        tableViewFrame = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y, self.view.frame.size.width , self.view.frame.size.height - self.navigationController.navigationBar.frame.size.height - TOP_DISTANCE);
    }
    self.tableView = [[UITableView alloc] initWithFrame:tableViewFrame style:UITableViewStylePlain];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionFooterHeight = 0;
    self.tableView.estimatedSectionHeaderHeight = 0;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    if (IsIpad()) {
        self.tableView.contentInset = UIEdgeInsetsMake(0, 0, self.navigationController.navigationBar.frame.size.height*2, 0);
    }
    [self.view addSubview:self.tableView];
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barAppearance = [UINavigationBarAppearance new];
        barAppearance.backgroundColor = [UIColor systemBackgroundColor];
        
        self.navigationController.navigationBar.standardAppearance = barAppearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = barAppearance;
        
        UIToolbarAppearance *toolbarAppearance = [UIToolbarAppearance new];
        toolbarAppearance.backgroundColor = [UIColor systemBackgroundColor];
        self.navigationController.toolbar.standardAppearance = toolbarAppearance;
        self.navigationController.toolbar.scrollEdgeAppearance = toolbarAppearance;
        
        self.tableView.sectionHeaderTopPadding = 0;
    }
    
    self.navigationController.navigationBar.tintColor = BAR_COLOR;

    NSMutableArray *items = [NSMutableArray array];
    
    if (_directory.editable) {
        // Create buttons
        UIImage *addFolderIcon = [[UIImage imageNamed:@"share_addFile"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIButton *addBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [addBtn setImage:addFolderIcon forState:UIControlStateNormal];
        addBtn.tintColor = [UIColor labelColor];
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
        [saveBtn setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
        saveBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [saveBtn.widthAnchor constraintEqualToConstant:80].active = YES;
        [saveBtn.heightAnchor constraintEqualToConstant:50].active = YES;
        [saveBtn addTarget:self action:@selector(save:) forControlEvents:UIControlEventTouchUpInside];
        self.saveButton = [[UIBarButtonItem alloc] initWithCustomView:saveBtn];
        
        // Toolbar items: center the save button
        UIBarButtonItem *flexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        [self setToolbarItems:@[flexItem, self.saveButton, flexItem] animated:true];
        
        // Customize toolbar background color (light gray like primary background)
        if (@available(iOS 15.0, *)) {
            UIColor *bg = [UIColor colorWithRed:242/255.0 green:242/255.0 blue:242/255.0 alpha:1.0];
            UIToolbarAppearance *toolAppear = [UIToolbarAppearance new];
            [toolAppear configureWithOpaqueBackground];
            toolAppear.backgroundColor = bg;
            self.navigationController.toolbar.standardAppearance = toolAppear;
            self.navigationController.toolbar.scrollEdgeAppearance = toolAppear;
        } else {
            self.navigationController.toolbar.barTintColor = [UIColor colorWithRed:242/255.0 green:242/255.0 blue:242/255.0 alpha:1.0];
        }
        
        // Navigation bar right contains New Folder
        [items addObject:self.createButton];
        self.navigationItem.title = _directory.name;
        
        if (!IsIpad()) {
            self.tableView.frame = CGRectMake(self.tableView.frame.origin.x, self.tableView.frame.origin.y, self.tableView.frame.size.width, self.tableView.frame.size.height - self.navigationController.toolbar.frame.size.height);
        }
    }
    
    self.navigationItem.rightBarButtonItems = items;
    [self refreshView];
    
    __weak typeof(self) weakSelf = self;
    [self.tableView addPullToRefresh:[SVArrowPullToRefreshView class] withActionHandler:^{
        weakSelf.directory.delegate = weakSelf;
        [weakSelf reloadContent];
    }];
    
    // Register custom SeafCell for modern list UI
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafCell" bundle:nil] forCellReuseIdentifier:@"SeafCell"];
    
    // Set background color consistent with SeafFileViewController
    UIView *bgView = [[UIView alloc] initWithFrame:self.tableView.bounds];
    bgView.backgroundColor = kPrimaryBackgroundColor;
    self.tableView.backgroundView = bgView;
    self.view.backgroundColor = kPrimaryBackgroundColor;
    
    // Add blank top space similar to SeafFileViewController
    self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 10.0)];
    
    // Adjust safe-area insets
    [self updateTableInsets];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    self.tableView.frame = CGRectMake(0, 0, size.width, size.height);
}

- (void)reloadContent {
    [self.directory loadContent:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = _directory.editable ? false : true;
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
    SeafShareFileViewController *fileVC = [[SeafShareFileViewController alloc] initWithDir:_directory];
    [self.navigationController pushViewController:fileVC animated:true];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    _subDirs = _directory.subDirs;
    return self.subDirs.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 0.01;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return nil;
}

- (SeafBase *)getItemAtIndex:(NSUInteger)index {
    @try {
        return [self.subDirs objectAtIndex:index];
    } @catch(NSException *exception) {
        return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SeafBase *entry = [self getItemAtIndex:indexPath.row];
    if (!entry) return [[UITableViewCell alloc] init];

    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SeafCell" forIndexPath:indexPath];
    [cell reset];

    cell.textLabel.text = entry.name;
    cell.imageView.image = entry.icon;
    cell.moreButton.hidden = YES;

    // Detail text for repo shows size/date, for folder blank
    cell.detailTextLabel.text = [entry displayDetailText];

    // After configuring cell details, apply corner & separator styling like SeafFileViewController
    BOOL isFirstCell = (indexPath.row == 0);
    BOOL isLastCell = (indexPath.row == self.subDirs.count - 1);
    [cell updateCellStyle:isFirstCell isLastCell:isLastCell];
    [cell updateSeparatorInset:isLastCell];

    // Hide cache/progress etc in this list
    cell.cacheStatusView.hidden = YES;
    [cell.cacheStatusWidthConstraint setConstant:0.0f];

    return cell;
}

#pragma mark - Table view delegate


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafBase *entry = [self getItemAtIndex:indexPath.row];
    if (!entry)
        return [self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
    
    if ([entry isKindOfClass:[SeafRepo class]] && [(SeafRepo *)entry passwordRequired]) {
        [self popupSetRepoPassword:(SeafRepo *)entry];
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        [self pushViewControllerDir:(SeafDir *)entry];
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
        _loadingView.color = [UIColor darkTextColor];
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
        if (inset.bottom != bottomInset) {
            inset.bottom = bottomInset;
            self.tableView.contentInset = inset;
            self.tableView.scrollIndicatorInsets = inset;
        }
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
