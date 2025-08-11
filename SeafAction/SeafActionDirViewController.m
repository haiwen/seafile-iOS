//
//  SeafActionDirViewController.m
//  seafilePro
//
//  Created by Wang Wei on 08/12/2016.
//  Copyright © 2016 Seafile. All rights reserved.
//

#import "SeafActionDirViewController.h"
#import "UIViewController+Extend.h"
#import "UIScrollView+SVPullToRefresh.h"
#import "Utils.h"
#import "Debug.h"
#import "ExtentedString.h"
#import "SeafUploadFile.h"
#import "SeafGlobal.h"
#import "SeafFile.h"
#import "SeafDataTaskManager.h"
#import "SeafFileOperationManager.h"
#import "SeafUploadFileModel.h"
#import "SeafCell.h"
#import "Constants.h"
#import "FileSizeFormatter.h"
#import "SeafNavLeftItem.h"
#import "SeafRepos.h"
#import "SeafBase+Display.h"

@interface SeafActionDirViewController()<SeafDentryDelegate, SeafUploadDelegate>
@property (strong, nonatomic) SeafDir *directory;
@property (strong, nonatomic) SeafUploadFile *ufile;
@property (strong, nonatomic) UIBarButtonItem *saveButton;
@property (strong, nonatomic) UIBarButtonItem *createButton;

@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *loadingView;

@property (strong, nonatomic) UIProgressView* progressView;
@property (strong) UIAlertController *alert;
@property (nonatomic, strong) NSArray *subDirs;

@end

@implementation SeafActionDirViewController

- (id)initWithSeafDir:(SeafDir *)directory file:(SeafUploadFile *)ufile
{
    if (self = [super init]) {
        _directory = directory;
        _directory.delegate = self;
        _ufile = ufile;
        [_directory loadContent:NO];
    }
    return self;
}

- (NSFileCoordinator *)fileCoordinator
{
    NSFileCoordinator *fileCoordinator = [[NSFileCoordinator alloc] init];
    [fileCoordinator setPurposeIdentifier:APP_ID];
    return fileCoordinator;
}

- (void)setDirectory:(SeafDir *)directory
{
    _directory = directory;
    _directory.delegate = self;
    [_directory loadContent:true];
    [self setupNavigationItems];
}

- (UIProgressView *)progressView
{
    if (!_progressView) {
        _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    }
    return _progressView;
}

- (void)refreshView
{
    if ([self isViewLoaded]) {
        [self.tableView reloadData];
        if (_directory && !_directory.hasCache) {
            [self showLoadingView];
        } else {
            [self dismissLoadingView];
        }
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionFooterHeight = 0;
    self.tableView.estimatedSectionHeaderHeight = 0;
    
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barAppearance = [UINavigationBarAppearance new];
        barAppearance.backgroundColor = [UIColor whiteColor];
        
        self.navigationController.navigationBar.standardAppearance = barAppearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = barAppearance;
        
        self.tableView.sectionHeaderTopPadding = 0;
    }
    
    if (_directory.editable) {
        // Right bar addFolder icon
        UIImage *addIcon = [[UIImage imageNamed:@"share_addFile"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIButton *addBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [addBtn setImage:addIcon forState:UIControlStateNormal];
        addBtn.tintColor = [UIColor labelColor];
        addBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [addBtn.widthAnchor constraintEqualToConstant:24].active = YES;
        [addBtn.heightAnchor constraintEqualToConstant:24].active = YES;
        [addBtn addTarget:self action:@selector(createFolder) forControlEvents:UIControlEventTouchUpInside];
        self.createButton = [[UIBarButtonItem alloc] initWithCustomView:addBtn];

        // Save button centered in toolbar
        UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [saveBtn setTitle:NSLocalizedString(@"OK", @"Seafile") forState:UIControlStateNormal];
        saveBtn.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        [saveBtn setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
        saveBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [saveBtn.widthAnchor constraintEqualToConstant:80].active = YES;
        [saveBtn.heightAnchor constraintEqualToConstant:50].active = YES;
        [saveBtn addTarget:self action:@selector(save:) forControlEvents:UIControlEventTouchUpInside];
        self.saveButton = [[UIBarButtonItem alloc] initWithCustomView:saveBtn];

        UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        self.toolbarItems = @[flex,self.saveButton,flex];

        self.navigationItem.rightBarButtonItem = self.createButton;
        self.navigationItem.title = @"";

        // toolbar bg
        UIColor *bgCol = [UIColor colorWithRed:242/255.0 green:242/255.0 blue:242/255.0 alpha:1.0];
        if (@available(iOS 15.0,*)) {
            UIToolbarAppearance *toolAp = [UIToolbarAppearance new];
            [toolAp configureWithOpaqueBackground];
            toolAp.backgroundColor = bgCol;
            self.navigationController.toolbar.standardAppearance = toolAp;
            self.navigationController.toolbar.scrollEdgeAppearance = toolAp;
        } else {
            self.navigationController.toolbar.barTintColor = bgCol;
        }
    }
    
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;
    [self refreshView];

    __weak typeof(self) weakSelf = self;
    [self.tableView addPullToRefresh:[SVArrowPullToRefreshView class] withActionHandler:^{
        weakSelf.directory.delegate = weakSelf;
        [weakSelf.directory loadContent:YES];
    }];

    // Register SeafCell & background
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafCell" bundle:nil] forCellReuseIdentifier:@"SeafCell"];
    UIView *bgView = [[UIView alloc] initWithFrame:self.tableView.bounds];
    bgView.backgroundColor = kPrimaryBackgroundColor;
    self.tableView.backgroundView = bgView;
    self.view.backgroundColor = kPrimaryBackgroundColor;
    self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,10)];

    // Ensure custom navigation layout (arrow + title) is set for the initial directory
    [self setupNavigationItems];

    // Adjust bottom content inset for safe area (home indicator)
    [self updateTableInsets];
}

- (void)doneLoadingTableViewData
{
    [self.tableView.pullToRefreshView stopAnimating];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)uploadFile:(SeafUploadFile *)ufile overwrite:(BOOL)overwrite
{
     ufile.delegate = self;
     ufile.udir = _directory;
     ufile.model.overwrite = overwrite;
    Debug("file %@ %d %d", ufile.lpath, ufile.model.uploading, ufile.model.uploaded);
     [self showUploadProgress:ufile];
}

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
        [[SeafFileOperationManager sharedManager] mkdir:input inDir:self.directory completion:^(BOOL success, NSError * _Nullable error) {
            [self dismissLoadingView];
            if (!success) {
                [self alertWithTitle:NSLocalizedString(@"Failed to create folder", @"Seafile") handler:nil];
            } else {
                // Refresh the directory list so user can select the newly created folder
                [self.directory loadContent:YES];
            }
        }];
    }];
}

- (IBAction)save:(id)sender
{
    Debug("start to upload file: %@, existed:%d", _ufile.lpath, [_directory nameExist:_ufile.name]);
    if ([_directory nameExist:_ufile.name]) {
        NSString *title = NSLocalizedString(@"A file with the same name already exists, do you want to overwrite?", @"Seafile");
        [self alertWithTitle:title message:nil yes:^{
            [self uploadFile:self.ufile overwrite:true];
        } no:^{
            [self uploadFile:self.ufile overwrite:false];
        }];
    } else {
        [self uploadFile:_ufile overwrite:false];
    }
}

- (void)showLoadingView
{
    if (!self.loadingView) {
        self.loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        self.loadingView.color = [UIColor darkTextColor];
        self.loadingView.hidesWhenStopped = YES;
        [self.view addSubview:self.loadingView];
    }
    self.loadingView.center = self.view.center;
    self.loadingView.frame = CGRectMake((self.view.frame.size.width-self.loadingView.frame.size.width)/2, (self.view.frame.size.height-self.loadingView.frame.size.height)/2, self.loadingView.frame.size.width, self.loadingView.frame.size.height);
    [self.loadingView startAnimating];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (self.loadingView && [self.loadingView isAnimating]) {
        self.loadingView.frame = CGRectMake((self.view.frame.size.width-self.loadingView.frame.size.width)/2, (self.view.frame.size.height-self.loadingView.frame.size.height)/2, self.loadingView.frame.size.width, self.loadingView.frame.size.height);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Show or hide toolbar immediately without animation
    self.navigationController.toolbarHidden = _directory.editable ? NO : YES;
}

- (void)dismissLoadingView
{
    [self.loadingView stopAnimating];
}

- (void)showUploadProgress:(SeafUploadFile *)file
{
    Debug("Uploading file %@", file.lpath);
    NSString *title = [NSString stringWithFormat: @"Uploading %@", file.name];
    self.alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:STR_CANCEL style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        file.delegate = nil;
        [file cancel];
    }];
    self.ufile = file;
    [self.alert addAction:cancelAction];
    [self presentViewController:self.alert animated:true completion:^{
        self.progressView.progress = 0.f;
        CGRect r = self.alert.view.frame;
        self.progressView.frame = CGRectMake(20, r.size.height-45, r.size.width - 40, 20);
        [self.alert.view addSubview:self.progressView];
        [SeafDataTaskManager.sharedObject addUploadTask:self.ufile priority:NSOperationQueuePriorityVeryHigh];
    }];
}

- (void)popupSetRepoPassword:(SeafRepo *)repo
{
    [repo setDelegate:self];
    [self popupSetRepoPassword:repo handler:^{
        [self pushViewControllerDir:repo];
    }];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    _subDirs = _directory.subDirs;
    return self.subDirs.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 0.01;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    return nil;
}

- (SeafBase *)getItemAtIndex:(NSUInteger)index
{
    @try {
        return [self.subDirs objectAtIndex:index];
    } @catch(NSException *exception) {
        return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafBase *entry = [self getItemAtIndex:indexPath.row];
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SeafCell" forIndexPath:indexPath];
    [cell reset];
    cell.textLabel.text = entry.name;
    cell.imageView.image = entry.icon;
    cell.moreButton.hidden = YES;
    cell.detailTextLabel.text = [entry displayDetailText];
    BOOL first = indexPath.row==0;
    BOOL last = indexPath.row== self.directory.subDirs.count-1;
    [cell updateCellStyle:first isLastCell:last];
    [cell updateSeparatorInset:last];
    cell.cacheStatusView.hidden = YES;
    [cell.cacheStatusWidthConstraint setConstant:0.0f];
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
    SeafBase *entry = [self getItemAtIndex:indexPath.row];
    if (!entry)
        return [self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];

    if ([entry isKindOfClass:[SeafFile class]]) {
    } else if ([entry isKindOfClass:[SeafRepo class]] && [(SeafRepo *)entry passwordRequired]) {
        [self popupSetRepoPassword:(SeafRepo *)entry];
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        [self pushViewControllerDir:(SeafDir *)entry];
    }
}

- (void)reloadIndex:(NSIndexPath *)indexPath
{
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

#pragma mark - SeafDentryDelegate
- (void)download:(SeafBase *)entry progress:(float)progress
{
}

- (void)download:(SeafBase *)entry complete:(BOOL)updated
{
    if (![self isViewLoaded])
        return;

    [self doneLoadingTableViewData];
    if (_directory == entry)
        [self refreshView];
}

- (void)download:(SeafBase *)entry failed:(NSError *)error
{
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

#pragma mark - SeafUploadDelegate
- (void)uploadProgress:(SeafUploadFile *)file progress:(float)progress
{
    if (self.ufile != file) return;
    self.progressView.progress = progress;
}

- (void)uploadComplete:(BOOL)success file:(SeafUploadFile *)file oid:(NSString *)oid
{
    if (self.ufile != file) return;
    Debug("upload file %@ %d", file.lpath, success);
    if (!success) {
        Warning("Failed to upload file %@", file.name);
        [self alertWithTitle:NSLocalizedString(@"Failed to upload file", @"Seafile") handler:nil];
    } else {
        dispatch_after(0, dispatch_get_main_queue(), ^{
            [self.alert dismissViewControllerAnimated:NO completion:^{
                [self.extensionContext completeRequestReturningItems:self.extensionContext.inputItems completionHandler:nil];
            }];
        });
    }
}

- (void)pushViewControllerDir:(SeafDir *)dir
{
    SeafActionDirViewController *controller = [[SeafActionDirViewController alloc] initWithSeafDir:dir file:self.ufile];
    [self.navigationController pushViewController:controller animated:true];
}

#pragma mark - Navigation helper

- (void)setupNavigationItems {
    if ([self.directory isKindOfClass:[SeafRepos class]]) {
        NSString *title = NSLocalizedString(@"Save to Seafile", @"Seafile");
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:[SeafNavLeftItem navLeftItemWithDirectory:nil title:title target:self action:@selector(backAction)]];
    } else {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:[SeafNavLeftItem navLeftItemWithDirectory:self.directory title:nil target:self action:@selector(backAction)]];
    }
    self.navigationItem.title = @"";
}

- (void)backAction {
    [self.navigationController popViewControllerAnimated:YES];
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

@end
