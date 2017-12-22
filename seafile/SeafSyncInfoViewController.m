//
//  SeafUpDownloadViewController.m
//  seafilePro
//
//  Created by three on 2017/7/29.
//  Copyright © 2017年 Seafile. All rights reserved.
//

#import "SeafSyncInfoViewController.h"
#import "SeafSyncInfoCell.h"
#import "Debug.h"
#import "SeafDataTaskManager.h"
#import "SeafFile.h"
#import "SeafPhoto.h"
#import "SeafGlobal.h"

#define CANCEL_UPLOAD NSLocalizedString(@"Cancel upload", @"Seafile")
#define CANCEL_DOWNLOAD NSLocalizedString(@"Cancel download", @"Seafile")

static NSString *cellIdentifier = @"SeafSyncInfoCell";

@interface SeafSyncInfoViewController ()

@property (nonatomic, strong) NSArray *finishedTasks;
@property (nonatomic, strong) NSMutableArray *ongongingTasks;
@property (nonatomic, strong) SeafConnection *connection;

@end

@implementation SeafSyncInfoViewController

- (NSArray *)finishedTasks {
    if (!_finishedTasks) {
        _finishedTasks = [NSArray array];
    }
    return _finishedTasks;
}

- (NSMutableArray *)ongongingTasks {
    if (!_ongongingTasks) {
        _ongongingTasks = [NSMutableArray array];
    }
    return _ongongingTasks;
}

- (instancetype)initWithType:(DETAILTYPE)type {
    self = [super init];
    if (self) {
        self.detailType = type;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 50.0;
    self.tableView.tableFooterView = [UIView new];
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafSyncInfoCell" bundle:nil]
         forCellReuseIdentifier:cellIdentifier];

    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;

    if (self.detailType == DOWNLOAD_DETAIL) {
        self.navigationItem.title = NSLocalizedString(@"Downloading", @"Seafile");
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:CANCEL_DOWNLOAD style:UIBarButtonItemStyleDone target:self action:@selector(cancelAllDownloadTasks)];
    } else {
        self.navigationItem.title = NSLocalizedString(@"Uploading", @"Seafile");
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:CANCEL_UPLOAD style:UIBarButtonItemStyleDone target:self action:@selector(cancelAllUploadTasks)];
    }

    self.connection = [SeafGlobal sharedObject].connection;

    [self initTaskArray];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
    WS(weakSelf);
    SeafDataTaskManager.sharedObject.trySyncBlock = ^(id<SeafTask> _Nullable task) {
        if (![task.accountIdentifier isEqualToString:self.connection.accountIdentifier]) return;
        if ([weakSelf.ongongingTasks containsObject:task]) return;
        @synchronized (weakSelf.ongongingTasks) {
            [weakSelf.ongongingTasks addObject:task];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.tableView reloadData];
        });
    };

    SeafDataTaskManager.sharedObject.finishBlock = ^(id<SeafTask>  _Nonnull task) {
        if (![task.accountIdentifier isEqualToString:self.connection.accountIdentifier]) return;
        if ([weakSelf.ongongingTasks containsObject:task]) {
            @synchronized (weakSelf.ongongingTasks) {
                [weakSelf.ongongingTasks removeObject:task];
            }
        }
        weakSelf.finishedTasks = [weakSelf allCompeletedTask];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.tableView reloadData];
        });
    };
}

- (NSArray*)allCompeletedTask {
    SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection];
    NSArray *completedArray = nil;
    if (self.detailType == DOWNLOAD_DETAIL) {
        completedArray = [accountQueue.fileQueue.completedTasks mutableCopy];
    } else {
        completedArray = [accountQueue.uploadQueue.completedTasks mutableCopy];
    }
    return completedArray;
}

- (void)initTaskArray {
    self.finishedTasks = [self allCompeletedTask];
    SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection];
    NSArray *allTasks = nil;
    if (self.detailType == DOWNLOAD_DETAIL) {
        allTasks = accountQueue.fileQueue.allTasks;
    } else {
        allTasks = accountQueue.uploadQueue.allTasks;
    }
    for (id<SeafTask> task in allTasks) {
        if (![self.finishedTasks containsObject:task]) {
            @synchronized (self.ongongingTasks) {
                [self.ongongingTasks addObject:task];
            }
        }
    }
}

- (void)cancelAllDownloadTasks {
    WS(weakSelf);
    [Utils alertWithTitle:NSLocalizedString(@"Are you sure to cancel all downloading tasks?", @"Seafile") message:nil yes:^{
        [SeafDataTaskManager.sharedObject cancelAllDownloadTasks:self.connection];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.tableView reloadData];
        });
    } no:^{
    } from:self];
}

- (void)cancelAllUploadTasks {
    WS(weakSelf);
    [Utils alertWithTitle:NSLocalizedString(@"Are you sure to cancel all uploading tasks?", @"Seafile") message:nil yes:^{
        [SeafDataTaskManager.sharedObject cancelAllUploadTasks:self.connection];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.tableView reloadData];
        });
    } no:^{
    } from:self];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return self.ongongingTasks.count;
    } else {
        return self.finishedTasks.count;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 24;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *text = nil;
    if (section == 0) {
        if (self.detailType == DOWNLOAD_DETAIL) {
            text = NSLocalizedString(@"Downloading", @"Seafile");
        } else {
            text = NSLocalizedString(@"Uploading", @"Seafile");
        }
    } else {
        text = NSLocalizedString(@"Completed", @"Seafile");
    }
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, tableView.bounds.size.width - 10, 18)];
    label.font = [UIFont systemFontOfSize:12];
    label.text = text;
    label.textColor = [UIColor darkTextColor];
    label.backgroundColor = [UIColor clearColor];
    [headerView setBackgroundColor:[UIColor colorWithRed:246/255.0 green:246/255.0 blue:250/255.0 alpha:1.0]];
    [headerView addSubview:label];
    return headerView;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SeafSyncInfoCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier forIndexPath:indexPath];
    NSArray *tasks = nil;
    if (indexPath.section == 0) {
        tasks = self.ongongingTasks;
    } else {
        tasks = self.finishedTasks;
    }

    if (tasks.count > 0 && tasks.count > indexPath.row) {
        id<SeafTask> task = tasks[indexPath.row];
        [cell showCellWithTask:task];
    }
    return cell;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
