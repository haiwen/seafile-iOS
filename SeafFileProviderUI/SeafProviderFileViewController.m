//
//  SeafProviderFileViewController.m
//  seafilePro
//
//  Created by Wang Wei on 11/14/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import "SeafProviderFileViewController.h"
#import "UIViewController+Extend.h"
#import "SeafFile.h"
#import "SeafRepos.h"
#import "SeafGlobal.h"
#import "SeafStorage.h"
#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "Utils.h"
#import "Debug.h"

@interface SeafProviderFileViewController ()<SeafDentryDelegate, SeafUploadDelegate, UIScrollViewDelegate>
@property (strong, nonatomic) IBOutlet UIButton *chooseButton;
@property (strong, nonatomic) IBOutlet UIButton *backButton;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *loadingView;

@property (strong, nonatomic) UIProgressView* progressView;
@property (strong) UIAlertController *alert;
@property (strong) SeafFile *sfile;
@property (strong) SeafUploadFile *ufile;
@property (strong) NSArray *items;
@property BOOL clearall;
@end

@implementation SeafProviderFileViewController

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
    self.titleLabel.text = _directory.name;
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
    self.titleLabel.text = _directory.name;
    if (self.root.documentPickerMode == UIDocumentPickerModeImport
        || self.root.documentPickerMode == UIDocumentPickerModeOpen) {
        self.chooseButton.hidden = true;
        if (self.root.documentPickerMode == UIDocumentPickerModeOpen && !_directory.editable) {
            // Only open files with write permission
            self.items = _directory.subDirs;
        } else {
            self.items = _directory.items;
        }
    } else {
        self.items = _directory.subDirs;
        self.chooseButton.hidden = !_directory.editable;
    }

    self.tableView.sectionHeaderHeight = self.chooseButton.hidden ? 1 : HEADER_HEIGHT;

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
    _clearall = false;
    [self refreshView];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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

- (void)dismissLoadingView
{
    [self.loadingView stopAnimating];
}

- (IBAction)goBack:(id)sender
{
    [self popViewController];
}

- (void)showUploadProgress:(SeafUploadFile *)file
{
    Debug("Uploading file %@", file.lpath);
    NSString *title = [NSString stringWithFormat: @"Uploading %@", file.name];
    self.alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:STR_CANCEL style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
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

- (void)uploadFileOverwrite:(BOOL)overwrite
{
    NSString *uniqDir = [Utils encodePath:_directory->connection.address username:_directory->connection.username repo:_directory.repoId path:_directory.path];
    NSString *tmpdir = [self.root.documentStorageURL.path stringByAppendingString:uniqDir];
    if (![Utils checkMakeDir:tmpdir]) {
        Warning("Failed to create temp dir.");
        return [self alertWithTitle:NSLocalizedString(@"Failed to upload file", @"Seafile") handler:nil];
    }
    NSString *name = self.root.originalURL.lastPathComponent;
    NSURL *url = [NSURL fileURLWithPath:[tmpdir stringByAppendingPathComponent:name]];

    Debug("Upload file: %@(%d) to %@, overwrite=%d, mode=%lu", url, [Utils fileExistsAtPath:url.path], _directory.path, overwrite, (unsigned long)self.root.documentPickerMode);
    if (self.root.documentPickerMode == UIDocumentPickerModeMoveToService) {
        return [self uploadMovedFile:url];
    }

    [self.fileCoordinator coordinateWritingItemAtURL:url options:0 error:NULL byAccessor:^(NSURL *newURL) {
        BOOL ret = [Utils copyFile:self.root.originalURL to:newURL];
        Debug("from %@ %lld, url: %@ , ret:%d", self.root.originalURL.path, [Utils fileSizeAtPath1:self.root.originalURL.path], url, ret);
        if (!ret) {
            Warning("Failed to copy file:%@ to %@", self.root.originalURL, newURL);
            return [self alertWithTitle:NSLocalizedString(@"Failed to upload file", @"Seafile") handler:nil];
        }
        SeafUploadFile *ufile = [[SeafUploadFile alloc] initWithPath:newURL.path];
        ufile.delegate = self;
        ufile.udir = _directory;
        ufile.overwrite = overwrite;
        Debug("file %@ %d %d", ufile.lpath, ufile.isUploading, ufile.isUploaded);
        [self showUploadProgress:ufile];
    }];
}

- (void)uploadMovedFile:(NSURL *)url
{
    [self.root.originalURL startAccessingSecurityScopedResource];
    NSError* error = nil;
    NSFileCoordinator *fileCoordinator = [[NSFileCoordinator alloc] init];
    [fileCoordinator coordinateReadingItemAtURL:self.root.originalURL
                                        options:NSFileCoordinatorReadingForUploading
                                          error:&error
                                     byAccessor:^(NSURL *newURL) {
                                         BOOL ret __attribute__((unused)) = [Utils copyFile:newURL to:url];
                                         Debug("Copy file from %@ %lld, url: %@ , ret:%d", newURL.path, [Utils fileSizeAtPath1:newURL.path], url, ret);
                                     }];
    [self.root.originalURL stopAccessingSecurityScopedResource];
    [self.root dismissGrantingAccessToURL:url];
}

- (IBAction)chooseCurrentDir:(id)sender
{
    NSString *name = self.root.originalURL.lastPathComponent;
    if ([_directory nameExist:name]) {
        NSString *title = NSLocalizedString(@"A file with the same name already exists, do you want to overwrite?", @"Seafile");
        [self alertWithTitle:title message:nil yes:^{
            [self uploadFileOverwrite:true];
        } no:^{
            [self uploadFileOverwrite:false];
        }];
    } else
        [self uploadFileOverwrite:false];
}

- (void)popupSetRepoPassword:(SeafRepo *)repo
{
    [repo setDelegate:self];
    [self popupSetRepoPassword:repo handler:^{
        [self pushViewControllerDir:repo];
    }];
}

- (void)reloadTable:(BOOL)clearall
{
    _clearall = clearall;
    [self.tableView reloadData];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return _clearall ? 0 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.items.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (self.chooseButton.hidden) {
        UIView *lineView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, tableView.frame.size.width, 0.5f)];
        [lineView setBackgroundColor:[UIColor lightGrayColor]];
        return lineView;
    } else {
        UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, tableView.bounds.size.width - 10, 18)];
        label.text = NSLocalizedString(@"Save Destination", @"Seafile");
        label.textColor = [UIColor darkTextColor];
        label.backgroundColor = [UIColor clearColor];
        label.font = [UIFont systemFontOfSize:16];
        [headerView setBackgroundColor:HEADER_COLOR];
        [headerView addSubview:label];
        return headerView;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (self.chooseButton.hidden) {
        return 0.5;
    } else {
        return 30;
    }
}

- (SeafBase *)getItemAtIndex:(NSUInteger)index
{
    @try {
        return [self.items objectAtIndex:index];
    } @catch(NSException *exception) {
        return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafProviderCell";
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

- (void)showDownloadProgress:(SeafFile *)file force:(BOOL)force
{
    Debug("Download file %@, cached:%d", file.path, [file hasCache]);
    NSString *title = [NSString stringWithFormat: @"Downloading %@", file.name];
    self.alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:STR_CANCEL style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [file cancel];
    }];
    self.sfile = file;
    [self.alert addAction:cancelAction];
    [self presentViewController:self.alert animated:true completion:^{
        self.progressView.progress = 0.f;
        CGRect r = self.alert.view.frame;
        self.progressView.frame = CGRectMake(20, r.size.height-45, r.size.width - 40, 20);
        [self.alert.view addSubview:self.progressView];
        Debug("Start to download file: %@", file.path);
        [file load:self force:force];
    }];
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafBase *entry = [self getItemAtIndex:indexPath.row];
    if (!entry) {
        return [self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
    }

    if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)entry;
        [entry loadCache];
        NSURL *exportURL = [file exportURL];
        if (!exportURL) {
            return [self showDownloadProgress:file force:false];
        }

        if (self.root.documentPickerMode == UIDocumentPickerModeImport
            || self.root.documentPickerMode == UIDocumentPickerModeOpen) {
            NSString *encodeUniqDir = [Utils encodePath:file->connection.address username:file->connection.username repo:file.repoId path:file.path.stringByDeletingLastPathComponent];
            NSString *tmpdir = [self.root.documentStorageURL.path stringByAppendingPathComponent:encodeUniqDir];
            NSURL *url = [NSURL fileURLWithPath:[tmpdir stringByAppendingPathComponent:file.name]];
            Debug("dismissGrantingAccessToURL:%@", url);
            [self.root dismissGrantingAccessToURL:url];

        }
    } else if ([entry isKindOfClass:[SeafRepo class]] && [(SeafRepo *)entry passwordRequiredWithSyncRefresh]) {
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
    if (![self isViewLoaded] || entry != self.sfile)
        return;

    NSUInteger index = [_directory.items indexOfObject:entry];
    if (index == NSNotFound)
        return;
    dispatch_after(0, dispatch_get_main_queue(), ^{
        self.progressView.progress = progress;
    });
}
- (void)download:(SeafBase *)entry complete:(BOOL)updated
{
    if (![self isViewLoaded])
        return;
    if (_directory == entry)
        [self refreshView];
    if (entry != self.sfile)
        return;
    NSUInteger index = [_directory.items indexOfObject:entry];
    if (index == NSNotFound)
        return;
    dispatch_after(0, dispatch_get_main_queue(), ^{
        Debug("Successfully download %ld %@", (unsigned long)index, entry.path);
        [self.alert dismissViewControllerAnimated:NO completion:^{
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
        }];
    });
}

- (void)download:(SeafBase *)entry failed:(NSError *)error
{
    if (_directory == entry) {
        Warning("Failed to load directory content %@\n", entry.name);
        if ([_directory hasCache])
            return;
    }
    if (entry != self.sfile) return;

    dispatch_after(0, dispatch_get_main_queue(), ^{
        [self.alert dismissViewControllerAnimated:NO completion:^{
            NSUInteger index = [_directory.items indexOfObject:entry];
            if (index == NSNotFound) return;
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            [self reloadIndex:indexPath];
            Warning("Failed to download file %@\n", entry.name);
            NSString *msg = [NSString stringWithFormat:@"Failed to download file '%@'", entry.name];
            [self alertWithTitle:msg handler:nil];
        }];
    });
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
        [self.ufile cancel];
        dispatch_after(0, dispatch_get_main_queue(), ^{
            [self.alert dismissViewControllerAnimated:NO completion:^{
                [self.root dismissGrantingAccessToURL:[NSURL URLWithString:file.lpath]];
            }];
        });
    }
}

- (void)pushViewControllerDir:(SeafDir *)dir
{
    SeafProviderFileViewController *controller = [[UIStoryboard storyboardWithName:@"SeafProviderFileViewController" bundle:nil] instantiateViewControllerWithIdentifier:@"SeafProviderFileViewController"];
    controller.directory = dir;
    controller.root = self.root;
    controller.view.frame = CGRectMake(self.view.frame.size.width, self.view.frame.origin.y, self.view.frame.size.width, self.view.frame.size.height);
    @synchronized (self) {
        if (self.childViewControllers.count > 0)
            return;
        [self addChildViewController:controller];
    }
    [controller didMoveToParentViewController:self];
    [self.view addSubview:controller.view];
    [self.view bringSubviewToFront:controller.view];

    [UIView animateWithDuration:0.5f delay:0.f options:0 animations:^{
        controller.view.frame = self.view.frame;
    } completion:^(BOOL finished) {
        [self reloadTable:true];
    }];
}

- (void)popViewController
{
    if ([self.parentViewController isKindOfClass:[SeafProviderFileViewController class]])
        [(SeafProviderFileViewController *)self.parentViewController reloadTable:false];
    [UIView animateWithDuration:0.5
                     animations:^{
                         self.view.frame = CGRectMake(self.view.frame.size.width, self.view.frame.origin.y, self.view.frame.size.width, self.view.frame.size.height);
                     }
                     completion:^(BOOL finished){
                         [self willMoveToParentViewController:self.parentViewController];
                         [self removeFromParentViewController];
                         [self.view removeFromSuperview];
                     }];
}

@end
