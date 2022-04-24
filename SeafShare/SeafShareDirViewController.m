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
    
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;
    
    CGFloat TOP_DISTANCE = IsIpad()? 0 : 40.0;
    CGRect tableViewFrame = self.view.frame;
    
    if (@available(iOS 13.0, *)) {
        tableViewFrame = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y, self.view.frame.size.width , self.view.frame.size.height - self.navigationController.navigationBar.frame.size.height - TOP_DISTANCE);
    }
    self.tableView = [[UITableView alloc] initWithFrame:tableViewFrame style:UITableViewStylePlain];
    self.tableView.rowHeight = 50;
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
        
//        self.tableView.sectionHeaderTopPadding = 0;
    }
    
    NSMutableArray *items = [NSMutableArray array];
    
    if (@available(iOS 13.0, *)) {
        UIBarButtonItem *refreshItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadContent)];
        [items addObject:refreshItem];
    }
    
    if (_directory.editable) {
        self.createButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"New Folder", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(createFolder)];
        UIBarButtonItem *flexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        [self setToolbarItems:@[flexItem, self.createButton, flexItem] animated:true];
        self.navigationController.toolbarHidden = true;
        
        self.saveButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save:)];
        [items addObject:self.saveButton];
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
}

#pragma mark- action
- (void)createFolder {
    [self popupInputView:NSLocalizedString(@"New Folder", @"Seafile") placeholder:NSLocalizedString(@"New folder name", @"Seafile") secure:false handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Folder name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"Folder name invalid", @"Seafile")];
            return;
        }
        [self showLoadingView];
        [self.directory mkdir:input success:^(SeafDir *dir) {
            [self dismissLoadingView];
        } failure:^(SeafDir *dir, NSError *error) {
            [self dismissLoadingView];
            [self alertWithTitle:NSLocalizedString(@"Failed to create folder", @"Seafile") handler:nil];
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
    if (_directory.editable) {
        return 0.01;
    } else {
        return 30;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (_directory.editable) {
        UIView *lineView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, tableView.frame.size.width, 1.0f)];
        if (@available(iOS 13.0, *)) {
            [lineView setBackgroundColor:[UIColor systemBackgroundColor]];
        } else {
            [lineView setBackgroundColor:[UIColor clearColor]];
        }
        return lineView;
    } else {
        UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, tableView.bounds.size.width - 10, 18)];
        label.text = NSLocalizedString(@"Save Destination", @"Seafile");
        label.backgroundColor = [UIColor clearColor];
        if (@available(iOS 13.0, *)) {
            [headerView setBackgroundColor:[UIColor secondarySystemBackgroundColor]];
            label.textColor = [UIColor labelColor];
        } else {
            [headerView setBackgroundColor:HEADER_COLOR];
            label.textColor = [UIColor darkTextColor];
        }
        label.font = [UIFont systemFontOfSize:15];
        [headerView addSubview:label];
        return headerView;
    }
}

- (SeafBase *)getItemAtIndex:(NSUInteger)index {
    @try {
        return [self.subDirs objectAtIndex:index];
    } @catch(NSException *exception) {
        return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *CellIdentifier = @"SeafActionDirCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }
    SeafBase *entry = [self getItemAtIndex:indexPath.row];
    if (!entry)        return cell;
    cell.textLabel.text = entry.name;
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.imageView.image = [Utils reSizeImage:entry.icon toSquare:32];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    if (@available(iOS 13.0, *)) {
        cell.textLabel.textColor = [UIColor labelColor];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        cell.textLabel.textColor = [UIColor blackColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    }
    
    if ([entry isKindOfClass:[SeafRepo class]]) {
        SeafRepo *repo = (SeafRepo *)entry;
        NSString *detail = [repo detailText];
        if (repo.isGroupRepo)
            detail = [NSString stringWithFormat:@"%@, %@", detail, repo.owner];
        cell.detailTextLabel.text = detail;
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        cell.detailTextLabel.text = nil;
    }
    cell.imageView.frame = CGRectMake(8, 8, 28, 28);
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
    [self.view addSubview:self.loadingView];
    self.loadingView.center = self.view.center;
    self.loadingView.frame = CGRectMake((self.view.frame.size.width-self.loadingView.frame.size.width)/2, (self.view.frame.size.height-self.loadingView.frame.size.height)/2, self.loadingView.frame.size.width, self.loadingView.frame.size.height);
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

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
