//
//  SeafSyncInfoViewController.m
//  SeafilePro
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
#import "SeafUploadOperation.h"

#define CANCEL_UPLOAD NSLocalizedString(@"Cancel upload", @"Seafile")
#define CANCEL_DOWNLOAD NSLocalizedString(@"Cancel download", @"Seafile")

static NSString *cellIdentifier = @"SeafSyncInfoCell";

@interface SeafSyncInfoViewController ()

@property (nonatomic, strong) NSArray *uploadingTasks;     // Tasks currently being uploaded
@property (nonatomic, strong) NSArray *waitingUploadTasks; // Tasks waiting to be uploaded
@property (nonatomic, strong) NSArray *downloadingTasks;   // Tasks currently being downloaded
@property (nonatomic, strong) NSArray *waitingDownloadTasks; // Tasks waiting to be downloaded
@property (nonatomic, strong) NSArray *finishedTasks;      // Array of completed tasks
@property (nonatomic, strong) SeafConnection *connection;

@end

@implementation SeafSyncInfoViewController

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

    if ([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;

    if (self.detailType == DOWNLOAD_DETAIL) {
        self.navigationItem.title = NSLocalizedString(@"Downloading", @"Seafile");
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:CANCEL_DOWNLOAD style:UIBarButtonItemStyleDone target:self action:@selector(cancelAllDownloadTasks)];
    } else {
        self.navigationItem.title = NSLocalizedString(@"Uploading", @"Seafile");
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:CANCEL_UPLOAD style:UIBarButtonItemStyleDone target:self action:@selector(cancelAllUploadTasks)];
    }

    self.connection = [SeafGlobal sharedObject].connection;

    [self initTaskArrays];

    // Add notification observers
    if (self.detailType == DOWNLOAD_DETAIL) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(taskStatusChanged:) name:@"SeafDownloadTaskStatusChanged" object:nil];
    }
    else {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(taskStatusChanged:) name:@"SeafUploadTaskStatusChanged" object:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Initialize Task Arrays

- (void)initTaskArrays {
    [self updateTaskArrays];
}

- (void)updateTaskArrays {
    SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection];

    if (self.detailType == DOWNLOAD_DETAIL) {
        // Separate tasks into currently downloading and waiting to download
        self.downloadingTasks = [accountQueue.getOngoingDownloadTasks copy];
        self.waitingDownloadTasks = [accountQueue.getWaitingDownloadTasks copy];

        NSMutableArray *finishedTasks = [NSMutableArray array];
        [finishedTasks addObjectsFromArray:accountQueue.getCompletedSuccessfulDownloadTasks];
        // Do not include failed tasks
//        [finishedTasks addObjectsFromArray:accountQueue.getCompletedFailedDownloadTasks];
        self.finishedTasks = [finishedTasks copy];
    } else {
        // Separate tasks into currently uploading and waiting to upload
        self.uploadingTasks = [accountQueue.getOngoingTasks copy];
        self.waitingUploadTasks = [accountQueue.getWaitingTasks copy];

        NSMutableArray *finishedTasks = [NSMutableArray array];
        [finishedTasks addObjectsFromArray:accountQueue.getCompletedSuccessfulTasks];
        // Do not include failed tasks
//        [finishedTasks addObjectsFromArray:accountQueue.getCompletedFailedTasks];
        self.finishedTasks = [finishedTasks copy];
    }
}

#pragma mark - Notification Callback

- (void)taskStatusChanged:(NSNotification *)notification {
    [self updateTaskArrays];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

#pragma mark - Cancel All Tasks
- (void)cancelAllDownloadTasks {
    [Utils alertWithTitle:NSLocalizedString(@"Are you sure to cancel all downloading tasks?", @"Seafile") message:nil yes:^{
        [SeafDataTaskManager.sharedObject cancelAllDownloadTasks:self.connection];
    } no:^{
    } from:self];
}

- (void)cancelAllUploadTasks {
    [Utils alertWithTitle:NSLocalizedString(@"Are you sure to cancel all uploading tasks?", @"Seafile") message:nil yes:^{
        [SeafDataTaskManager.sharedObject cancelAllUploadTasks:self.connection];
    } no:^{
    } from:self];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.detailType == DOWNLOAD_DETAIL) {
        if (section == 0) {
            return self.downloadingTasks.count + self.waitingDownloadTasks.count;
        } else if (section == 1) {
            return self.finishedTasks.count;
        }
    } else {
        if (section == 0) {
            return self.uploadingTasks.count + self.waitingUploadTasks.count;
        } else if (section == 1) {
            return self.finishedTasks.count;
        }
    }
    return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    // Always show the header with a height of 24
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
    } else if (section == 1) {
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

- (NSArray *)combinedActiveTasks {
    if (self.detailType == DOWNLOAD_DETAIL) {
        NSMutableArray *combinedTasks = [NSMutableArray array];
        // Add currently downloading tasks first
        [combinedTasks addObjectsFromArray:self.downloadingTasks];
        // Add tasks waiting to be downloaded
        [combinedTasks addObjectsFromArray:self.waitingDownloadTasks];
        return [combinedTasks copy];
    } else {
        NSMutableArray *combinedTasks = [NSMutableArray array];
        // Add currently uploading tasks first
        [combinedTasks addObjectsFromArray:self.uploadingTasks];
        // Add tasks waiting to be uploaded
        [combinedTasks addObjectsFromArray:self.waitingUploadTasks];
        return [combinedTasks copy];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SeafSyncInfoCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier forIndexPath:indexPath];
    NSArray *tasks = nil;
    if (indexPath.section == 0) {
        tasks = [self combinedActiveTasks];
    } else if (indexPath.section == 1) {
        tasks = self.finishedTasks;
    }

    if (tasks.count > indexPath.row) {
        if (self.detailType == DOWNLOAD_DETAIL) {
            SeafFile *task = tasks[indexPath.row];
            [cell showCellWithTask:task];
        } else {
            SeafUploadFile *task = tasks[indexPath.row];
            [cell showCellWithTask:task];
        }
    }
    return cell;
}

@end
