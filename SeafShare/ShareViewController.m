//
//  ShareViewController.m
//  SeafShare
//
//  Created by three on 2018/7/26.
//  Copyright © 2018年 Seafile. All rights reserved.
//

#import "ShareViewController.h"
#import "UIViewController+Extend.h"
#import "SeafGlobal.h"
#import "SeafStorage.h"
#import "Debug.h"
#import "Utils.h"
#import "SeafUploadFile.h"
#import "SeafCell.h"
#import "SeafDateFormatter.h"
#import "FileSizeFormatter.h"
#import "SeafShareAccountViewController.h"
#import "SeafShareDirViewController.h"
#import "SeafDataTaskManager.h"

@interface ShareViewController ()<UITableViewDataSource, UITableViewDelegate, SeafUploadDelegate>

@property (nonatomic, copy) NSArray *conns;
@property (nonatomic, strong) NSMutableArray *ufiles;
@property (nonatomic, strong) dispatch_group_t group;
@property (nonatomic, strong) SeafConnection *connection;
@property (nonatomic, strong) SeafDir *directory;
@property (nonatomic, strong) UIActivityIndicatorView *loadingView;
@property (nonatomic, strong) UIAlertController *alert;
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet UILabel *accountLabel;
@property (weak, nonatomic) IBOutlet UILabel *destinationLabel;
@property (weak, nonatomic) IBOutlet UIButton *accontButton;
@property (weak, nonatomic) IBOutlet UIButton *destinationButton;
@property (weak, nonatomic) IBOutlet UIButton *saveButton;

@end

@implementation ShareViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (IsIpad()) {
        [self setPreferredContentSize:CGSizeMake(480.0f, 540.0f)];
    }
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
    self.navigationItem.title = NSLocalizedString(@"Save to Seafile", @"Seafile");
    
    self.accountLabel.text = NSLocalizedString(@"Accounts", @"Seafile");
    self.destinationLabel.text = NSLocalizedString(@"Destination", @"Seafile");
    self.accontButton.enabled = false;
    self.destinationButton.enabled = false;
    [self.saveButton setTitle:NSLocalizedString(@"Save", @"Seafile") forState:UIControlStateNormal];
    
    [SeafGlobal.sharedObject loadAccounts];
    _conns = SeafGlobal.sharedObject.conns;
    if (_conns.count > 0) {
        self.connection = _conns.firstObject;
        NSString *hostAndName = [NSString stringWithFormat:@"%@-%@",_connection.host,_connection.username];
        [self.accontButton setTitle:hostAndName forState:UIControlStateNormal];
        [self updateSaveButton];
    } else {
        [self showAlert];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(selectDirNotification:) name:@"SelectedDirectoryNotif" object:nil];
    
    [self setupTableview];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.ufiles.count == 0) {
        [self handleInputs];
    }
    [self updateSaveButton];
}

- (void)selectDirNotification:(NSNotification *)notif {
    self.directory = notif.object;
    [self updateSaveButton];
}

- (void)handleInputs {
    self.group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_queue_create("com.seafile.share.imagehandle", DISPATCH_QUEUE_CONCURRENT);
    
    NSString *tmpdir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.tempDir];
    if (![Utils checkMakeDir:tmpdir]) {
        Warning("Failed to create temp dir.");
        return [self alertWithTitle:NSLocalizedString(@"Failed to upload file", @"Seafile") handler:nil];
    }
    
    [self showLoadingView];
    for (NSExtensionItem *item in self.extensionContext.inputItems) {
        for (NSItemProvider *itemProvider in item.attachments) {
            dispatch_group_enter(self.group);
            dispatch_barrier_async(queue, ^{
                Debug("itemProvider: %@", itemProvider);
                if ([itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeItem]) {
                    [itemProvider loadItemForTypeIdentifier:(NSString *)kUTTypeItem options:nil completionHandler:^(id<NSSecureCoding, NSObject>  _Nullable item, NSError * _Null_unspecified error) {
                        if (!error) {
                            if ([item isKindOfClass:[UIImage class]]) {
                                UIImage *image = (UIImage *)item;
                                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                                [formatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH'-'mm'-'ss"];
                                
                                NSString *name = [NSString stringWithFormat:@"IMG_%@.JPG", [formatter stringFromDate:[NSDate date]] ];
                                NSURL *targetUrl = [NSURL fileURLWithPath:[tmpdir stringByAppendingPathComponent:name]];
                                NSData *data = [self UIImageToDataJPEG:image];
                                BOOL ret = [data writeToURL:targetUrl atomically:true];
                                [self handleFile:ret ? targetUrl : nil];
                            } else if ([item isKindOfClass:[NSData class]]) {
                                NSData *data = (NSData *)item;
                                NSString *name = item.description;
                                NSURL *targetUrl = [NSURL fileURLWithPath:[tmpdir stringByAppendingPathComponent:name]];
                                BOOL ret = [data writeToURL:targetUrl atomically:true];
                                [self handleFile:ret ? targetUrl : nil];
                            } else if ([item isKindOfClass:[NSURL class]]) {
                                NSURL *url = (NSURL *)item;
                                NSString *name = url.lastPathComponent;
                                NSURL *targetUrl = [NSURL fileURLWithPath:[tmpdir stringByAppendingPathComponent:name]];
                                BOOL ret = [Utils copyFile:url to:targetUrl];
                                [self handleFile:ret ? targetUrl : nil];
                            } else if ([item isKindOfClass:[NSString class]]) {
                                NSString *string = (NSString *)item;
                                if (string.length > 0) {
                                    NSString *name = [NSString stringWithFormat:@"%@.txt", item.description];
                                    NSURL *targetUrl = [NSURL fileURLWithPath:[tmpdir stringByAppendingPathComponent:name]];
                                    BOOL ret = [[string dataUsingEncoding:NSUTF8StringEncoding] writeToURL:targetUrl atomically:true];
                                    [self handleFile:ret ? targetUrl : nil];
                                } else {
                                    [self handleFile:nil];
                                }
                            } else {
                                [self handleFile:nil];
                            }
                        } else {
                            [self handleFile:nil];
                        }
                    }];
                }
            });
        }
    }
    
    dispatch_group_notify(self.group, dispatch_get_main_queue(), ^{
        self.accontButton.enabled = true;
        self.destinationButton.enabled = true;
        [self.loadingView stopAnimating];
        [self.tableView reloadData];
    });
}

- (NSData *)UIImageToDataJPEG:(UIImage *)image {
    @autoreleasepool {
        NSData *data = UIImageJPEGRepresentation(image, 0.9f);
        return data;
    }
}

- (void)handleFile:(NSURL *)url {
    Debug("Received file : %@", url);
    if (!url) {
        Warning("Failed to load file.");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self alertWithTitle:NSLocalizedString(@"Failed to load file", @"Seafile") handler:^{
                [self.extensionContext completeRequestReturningItems:self.extensionContext.inputItems completionHandler:nil];
            }];
        });
        return;
    }
    Debug("Upload file %@ %lld", url, [Utils fileSizeAtPath1:url.path]);
    SeafUploadFile *ufile = [[SeafUploadFile alloc] initWithPath:url.path];
    dispatch_barrier_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.ufiles addObject:ufile];
    });
    dispatch_group_leave(self.group);
}

- (void)setupTableview {
    self.tableView.rowHeight = 68;
    self.tableView.tableFooterView = [UIView new];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafCell" bundle:nil] forCellReuseIdentifier:@"SeafCell"];
}

- (void)showLoadingView {
    [self.view addSubview:self.loadingView];
    self.loadingView.center = self.view.center;
    self.loadingView.frame = CGRectMake((self.view.frame.size.width-self.loadingView.frame.size.width)/2, (self.view.frame.size.height-self.loadingView.frame.size.height)/2, self.loadingView.frame.size.width, self.loadingView.frame.size.height);
    [self.loadingView startAnimating];
}

- (void)showAlert {
    if (!_alert) {
        self.alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Failed to login", @"Seafile") message:nil preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:STR_CANCEL style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [self cancel:nil];
        }];
        [self.alert addAction:cancelAction];
    }
    [self presentViewController:self.alert animated:true completion:nil];
}

- (void)updateSaveButton {
    if (_directory && _connection) {
        self.saveButton.enabled = true;
        [self.destinationButton setTitle:_directory.fullPath forState:UIControlStateNormal];
    } else {
        self.saveButton.enabled = false;
        [self.destinationButton setTitle:@"" forState:UIControlStateNormal];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _ufiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SeafCell *cell = [self getCell:@"SeafCell" forTableView:tableView];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    SeafUploadFile *file = _ufiles[indexPath.row];
    file.delegate = self;
    cell.textLabel.text = file.name;
    cell.imageView.image = file.icon;
    cell.moreButton.hidden = true;
    [self updateCell:cell file:file];
    return cell;
}

- (void)updateCell:(SeafCell *)cell file:(SeafUploadFile *)file {
    if (file.isUploading) {
        cell.progressView.hidden = false;
        [cell.progressView setProgress:file.uProgress];
    } else {
        NSString *sizeStr = [FileSizeFormatter stringFromLongLong:file.filesize];
        if (file.uploaded) {
            cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@, Uploaded %@", @"Seafile"), sizeStr, [SeafDateFormatter stringFromLongLong:(long long)file.lastFinishTimestamp]];
        } else {
            cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@, waiting to upload", @"Seafile"), sizeStr];
        }
        cell.cacheStatusView.hidden = true;
        [cell.cacheStatusWidthConstraint setConstant:0.0f];
        [cell layoutIfNeeded];
    }
}

- (SeafCell *)getCell:(NSString *)cellIdentifier forTableView:(UITableView *)tableView {
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:cellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    [cell reset];
    
    return cell;
}

- (void)cancel:(id)sender {
    self.ufiles = nil;
    [self.extensionContext completeRequestReturningItems:self.extensionContext.inputItems completionHandler:nil];
}

- (IBAction)save:(id)sender {
    for (SeafUploadFile *ufile in _ufiles) {
        ufile.overwrite = true;
        ufile.udir = _directory;
        ufile.delegate = self;
        [SeafDataTaskManager.sharedObject addUploadTask:ufile];
    }
    self.saveButton.enabled = false;
    NSMutableArray *temp = [_ufiles mutableCopy];
    SeafDataTaskManager.sharedObject.finishBlock = ^(id<SeafTask>  _Nullable file) {
        if ([temp containsObject:file]) {
            [temp removeObject:file];
        }
        if (temp.count == 0) {
            self.saveButton.enabled = true;
            [self cancel:nil];
        }
    };
}

#pragma mark - SeafUploadDelegate
- (void)uploadProgress:(SeafUploadFile *)file progress:(float)progress {
    [self updateFileCell:file result:true progress:progress completed:false];
}

- (void)uploadComplete:(BOOL)success file:(SeafUploadFile *)file oid:(NSString *)oid {
    [self updateFileCell:file result:success progress:1.0f completed:YES];
}

- (void)updateFileCell:(SeafUploadFile *)file result:(BOOL)res progress:(float)progress completed:(BOOL)completed {
    NSIndexPath *indexPath = nil;
    SeafCell *cell = [self getEntryCell:file indexPath:&indexPath];
    if (!cell) return;
    if (!completed && res) {
        cell.progressView.hidden = false;
        cell.detailTextLabel.text = nil;
        [cell.progressView setProgress:progress];
    } else if (indexPath) {
        [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (SeafCell *)getEntryCell:(id)entry indexPath:(NSIndexPath **)indexPath {
    NSUInteger index = [_ufiles indexOfObject:entry];
    if (index == NSNotFound)
        return nil;
    @try {
        NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
        if (indexPath) *indexPath = path;
        return (SeafCell *)[self.tableView cellForRowAtIndexPath:path];
    } @catch(NSException *exception) {
        Warning("Something wrong %@", exception);
        return nil;
    }
}

- (IBAction)selectAccount:(id)sender {
    SeafShareAccountViewController *accountVC = [[SeafShareAccountViewController alloc] init];
    [self.navigationController pushViewController:accountVC animated:true];
    accountVC.selectedBlock = ^(SeafConnection *conn) {
        if (![self.connection.accountIdentifier isEqualToString:conn.accountIdentifier]) {
            self.connection = conn;
            self.directory = nil;
        }
        [self updateSaveButton];
    };
}

- (IBAction)selectDestination:(id)sender {
    SeafShareDirViewController *dirVC = [[SeafShareDirViewController alloc] initWithSeafDir:(SeafDir *)_connection.rootFolder andRepoName:nil];
    [self.navigationController pushViewController:dirVC animated:true];
}

- (NSMutableArray *)ufiles {
    if (!_ufiles) {
        _ufiles = [NSMutableArray array];
    }
    return _ufiles;
}

- (UIActivityIndicatorView *)loadingView {
    if (!_loadingView) {
        _loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        _loadingView.color = [UIColor darkTextColor];
        _loadingView.hidesWhenStopped = YES;
    }
    return _loadingView;
}

@end
