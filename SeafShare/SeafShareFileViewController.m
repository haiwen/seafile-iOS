//
//  ShareViewController.m
//  SeafShare
//
//  Created by three on 2018/7/26.
//  Copyright © 2018年 Seafile. All rights reserved.
//

#import "SeafShareFileViewController.h"
#import "UIViewController+Extend.h"
#import "SeafGlobal.h"
#import "SeafStorage.h"
#import "Debug.h"
#import "Utils.h"
#import "SeafUploadFile.h"
#import "SeafCell.h"
#import "SeafDateFormatter.h"
#import "FileSizeFormatter.h"
#import "SeafShareDirViewController.h"
#import "SeafDataTaskManager.h"
#import "SeafInputItemsProvider.h"

@interface SeafShareFileViewController ()<UITableViewDataSource, UITableViewDelegate, SeafUploadDelegate>

@property (nonatomic, strong) NSArray *ufiles;
@property (nonatomic, strong) SeafConnection *connection;
@property (nonatomic, strong) SeafDir *directory;
@property (nonatomic, strong) UIActivityIndicatorView *loadingView;
@property (weak, nonatomic) IBOutlet UITableView *tableView;

@property (weak, nonatomic) IBOutlet UILabel *destinationLabel;
@property (weak, nonatomic) IBOutlet UIButton *destinationButton;
@property (weak, nonatomic) IBOutlet UIButton *saveButton;

@end

@implementation SeafShareFileViewController

- (instancetype)initWithConnection:(SeafConnection *)connection {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MainInterface" bundle:nil];
    self = [storyboard instantiateViewControllerWithIdentifier:@"SeafShareFileViewController"];
    if (self) {
        _connection = connection;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (IsIpad()) {
        [self setPreferredContentSize:CGSizeMake(480.0f, 540.0f)];
    }
    
    self.navigationItem.title = NSLocalizedString(@"Save to Seafile", @"Seafile");
    self.destinationLabel.text = NSLocalizedString(@"Destination", @"Seafile");
    self.destinationButton.enabled = false;
    [self.saveButton setTitle:NSLocalizedString(@"Save", @"Seafile") forState:UIControlStateNormal];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(selectDirNotification:) name:@"SelectedDirectoryNotif" object:nil];
    [self loadInputs];
    [self setupTableview];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateSaveButton];
}

- (void)loadInputs {
    [self showLoadingView];
    __weak typeof(self) weakSelf = self;
    [SeafInputItemsProvider loadInputs:weakSelf.extensionContext complete:^(BOOL result, NSArray *array) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.loadingView stopAnimating];
            if (result) {
                weakSelf.ufiles = array;
                [weakSelf.tableView reloadData];
                
                weakSelf.destinationButton.enabled = true;
            } else {
                [weakSelf alertWithTitle:NSLocalizedString(@"Failed to load file", @"Seafile") handler:^{
                    [weakSelf.extensionContext completeRequestReturningItems:self.extensionContext.inputItems completionHandler:nil];
                }];
            }
        });
    }];
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

- (void)updateSaveButton {
    if (_directory && _connection) {
        self.saveButton.enabled = true;
        SeafRepo *repo = [_connection getRepo:_directory.repoId];
        NSString *showPath = [NSString stringWithFormat:@"/%@%@", repo.name, _directory.path];
        if ([_directory.path isEqualToString:@"/"]) {
            showPath = [NSString stringWithFormat:@"/%@", repo.name];
        }
        [self.destinationButton setTitle:showPath forState:UIControlStateNormal];
    } else {
        self.saveButton.enabled = false;
        [self.destinationButton setTitle:@"" forState:UIControlStateNormal];
    }
}

#pragma mark - tableview
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

#pragma mark- action
- (IBAction)selectDestination:(id)sender {
    SeafShareDirViewController *dirVC = [[SeafShareDirViewController alloc] initWithSeafDir:(SeafDir *)_connection.rootFolder];
    [self.navigationController pushViewController:dirVC animated:true];
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
            [self done];
        }
    };
}

- (void)done {
    [self.extensionContext completeRequestReturningItems:self.extensionContext.inputItems completionHandler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)cancel:(id)sender {
    [self done];
    self.ufiles = nil;
}

#pragma mark- notification
- (void)selectDirNotification:(NSNotification *)notif {
    self.directory = notif.object;
    [self updateSaveButton];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self save:nil];
    });
}

- (UIActivityIndicatorView *)loadingView {
    if (!_loadingView) {
        _loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        _loadingView.color = [UIColor darkTextColor];
        _loadingView.hidesWhenStopped = YES;
    }
    return _loadingView;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
