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

@interface SeafDirViewController ()<SeafDentryDelegate>
@property (strong) UIBarButtonItem *chooseItem;
@property (strong, readonly) SeafDir *directory;
@property (readwrite) BOOL chooseRepo;
@property (nonatomic, strong) NSArray *subDirs;
@property (strong) SeafDirChoose dirChoose;
@property (strong) SeafDirCancelChoose dirCancel;
@end

@implementation SeafDirViewController

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

- (IBAction)chooseFolder:(id)sender
{
    self.dirChoose(self, _directory);
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.estimatedRowHeight = 50.0;
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafDirCell" bundle:nil]
         forCellReuseIdentifier:@"SeafDirCell"];

    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;
    [self.navigationItem setHidesBackButton:[self.directory isKindOfClass:[SeafRepos class]]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:STR_CANCEL style:UIBarButtonItemStylePlain target:self action:@selector(cancel:)];
    self.tableView.scrollEnabled = YES;
    UIBarButtonItem *flexibleFpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.chooseItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(chooseFolder:)];
    self.chooseItem.tintColor = BAR_COLOR;
    NSArray *items = [NSArray arrayWithObjects:flexibleFpaceItem, self.chooseItem, flexibleFpaceItem, nil];
    [self setToolbarItems:items];

    __weak typeof(self) weakSelf = self;
    [self.tableView addPullToRefresh:[SVArrowPullToRefreshView class] withActionHandler:^{
        if (![weakSelf checkNetworkStatus]) {
            [weakSelf performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:0.1];
            return;
        }

        weakSelf.directory.delegate = weakSelf;
        [weakSelf.directory loadContent:YES];
    }];
}

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
    [self.navigationController setToolbarHidden:_chooseRepo];
    [self.chooseItem setEnabled:_directory.editable];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return NSLocalizedString(@"Choose directory", @"Seafile");
}

- (NSArray *)subDirs
{
    if (!_subDirs) {
        NSMutableArray *arr = [NSMutableArray new];
        if ([_directory isKindOfClass:[SeafRepos class]]) {
            SeafRepos *repos = (SeafRepos *)_directory;
            for (int i = 0; i < repos.repoGroups.count; ++i) {
                for (SeafRepo *repo in [repos.repoGroups objectAtIndex:i]) {
                    if (!_chooseRepo || repo.editable) {
                        [arr addObject:repo];
                    }
                }
            }
        } else {
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

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    _subDirs = nil;
    return self.subDirs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafDirCell";
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    [cell reset];

    @try {
        SeafDir *sdir = [self.subDirs objectAtIndex:indexPath.row];
        cell.textLabel.text = sdir.name;
        cell.imageView.image = sdir.icon;
        cell.moreButton.hidden = YES;
        cell.detailTextLabel.text = @"";
        if ([sdir isKindOfClass:[SeafRepo class]]) {
            SeafRepo *repo = (SeafRepo *)sdir;
            if (repo.isGroupRepo) {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@, %@", repo.detailText, repo.owner];
            } else {
                cell.detailTextLabel.text = repo.detailText;
            }
        }
    } @catch(NSException *exception) {
    }
    return cell;
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}


#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafDir *curDir;
    @try {
        curDir = [self.subDirs objectAtIndex:indexPath.row];
    } @catch(NSException *exception) {
        [self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
        return;
    }
    if (![curDir isKindOfClass:[SeafDir class]])
        return;

    if (_chooseRepo) {
        return self.dirChoose(self, curDir);
    }
    if ([curDir isKindOfClass:[SeafRepo class]] && [(SeafRepo *)curDir passwordRequiredWithSyncRefresh]) {
        return [self popupSetRepoPassword:(SeafRepo *)curDir];
    }
    SeafDirViewController *controller = [[SeafDirViewController alloc] initWithSeafDir:curDir dirChosen:_dirChoose cancel:_dirCancel chooseRepo:false];
    controller.operationState = self.operationState;
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)popupSetRepoPassword:(SeafRepo *)repo
{
    @weakify(self);
    [self popupSetRepoPassword:repo handler:^{
        @strongify(self);
        [SVProgressHUD dismiss];
        SeafDirViewController *controller = [[SeafDirViewController alloc] initWithSeafDir:repo dirChosen:_dirChoose cancel:_dirCancel chooseRepo:false];
        controller.operationState = self.operationState;
        [self.navigationController pushViewController:controller animated:YES];
    }];
}

#pragma mark - SeafDentryDelegate
- (void)download:(SeafBase *)entry progress:(float)progress
{

}
- (void)download:(SeafBase *)entry complete:(BOOL)updated
{
    [self doneLoadingTableViewData];
    if (updated && [self isViewLoaded]) {
        [self.tableView reloadData];
    }
}

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

- (void)doneLoadingTableViewData
{
    [self.tableView.pullToRefreshView stopAnimating];
}
@end
