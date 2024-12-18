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
    self.navigationItem.title = _directory.name;
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
    self.tableView.rowHeight = 50;
    self.tableView.estimatedSectionFooterHeight = 0;
    self.tableView.estimatedSectionHeaderHeight = 0;
    
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barAppearance = [UINavigationBarAppearance new];
        barAppearance.backgroundColor = [UIColor whiteColor];
        
        self.navigationController.navigationBar.standardAppearance = barAppearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = barAppearance;
        
        self.tableView.sectionHeaderTopPadding = 0;
    }
    
    if (_directory.editable) {
        self.saveButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save:)];
        self.navigationItem.title = _directory.name;
        self.navigationItem.rightBarButtonItem = self.saveButton;
        
        self.createButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"New Folder", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(createFolder)];
        UIBarButtonItem *flexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        self.toolbarItems = @[flexItem, self.createButton, flexItem];
    }
    
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;
    [self refreshView];

    __weak typeof(self) weakSelf = self;
    [self.tableView addPullToRefresh:[SVArrowPullToRefreshView class] withActionHandler:^{
        weakSelf.directory.delegate = weakSelf;
        [weakSelf.directory loadContent:YES];
    }];
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
     ufile.overwrite = overwrite;
     Debug("file %@ %d %d", ufile.lpath, ufile.isUploading, ufile.isUploaded);
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
        [self.directory mkdir:input success:^(SeafDir *dir) {
            [self dismissLoadingView];
        } failure:^(SeafDir *dir, NSError *error) {
            [self dismissLoadingView];
            [self alertWithTitle:NSLocalizedString(@"Failed to create folder", @"Seafile") handler:nil];
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
    self.navigationController.toolbarHidden = _directory.editable ? false : true;
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
        [self.ufile run:nil];
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
    if (_directory.editable) {
        return 0.01;
    } else {
        return 30;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (_directory.editable) {
        UIView *lineView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, tableView.frame.size.width, 1.0f)];
        [lineView setBackgroundColor:[UIColor clearColor]];
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
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];

    if ([entry isKindOfClass:[SeafRepo class]]) {
        SeafRepo *repo = (SeafRepo *)entry;
        NSString *detail = [repo detailText];
        if (repo.isGroupRepo)
            detail = [NSString stringWithFormat:@"%@, %@", detail, repo.owner];
        cell.detailTextLabel.text = detail;
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        cell.detailTextLabel.text = nil;
    } else if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *sfile = (SeafFile *)entry;
        cell.detailTextLabel.text = sfile.detailText;
    }
    cell.imageView.frame = CGRectMake(8, 8, 28, 28);
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

@end
