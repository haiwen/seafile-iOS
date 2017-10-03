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

static NSString *cellIdentifier = @"SeafSyncInfoCell";

@interface SeafSyncInfoViewController ()<SeafDentryDelegate>

@property (nonatomic, strong) NSMutableArray *finishArray;
@property (nonatomic, strong) NSMutableArray *downloadingArray;
@property (nonatomic, strong) SeafConnection *connection;

@end

@implementation SeafSyncInfoViewController

- (NSMutableArray *)finishArray {
    if (!_finishArray) {
        _finishArray = [NSMutableArray array];
    }
    return _finishArray;
}

- (NSMutableArray *)downloadingArray {
    if (!_downloadingArray) {
        _downloadingArray = [NSMutableArray array];
    }
    return _downloadingArray;
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
    } else {
        self.navigationItem.title = @"正在上传";
    }

    self.connection = [SeafGlobal sharedObject].connection;

    [self addToFileArray];

    WS(weakSelf);
    SeafDataTaskManager.sharedObject.trySyncBlock = ^(SeafFile *file) {
        if (![weakSelf.downloadingArray containsObject:file]) {
            if (file->connection == self.connection) {
                [weakSelf.downloadingArray addObject:file];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.tableView reloadData];
        });
    };

    SeafDataTaskManager.sharedObject.finishBlock = ^(SeafFile *file) {
        if (file->connection == self.connection) {
            [weakSelf.downloadingArray removeObject:file];
            [weakSelf.finishArray addObject:file];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.tableView reloadData];
        });
    };
}

- (void)addToFileArray {
    SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection];
    for (SeafFile *file in accountQueue.fileQueue.allTasks) {
        if (file.state == SEAF_DENTRY_SUCCESS) {
            [self.finishArray addObject:file];
        } else {
            [self.downloadingArray addObject:file];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return self.downloadingArray.count;
    } else {
        return self.finishArray.count;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 24;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *text = nil;
    if (section == 0) {
        text = NSLocalizedString(@"Downloading", @"Seafile");
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

    if (self.detailType == DOWNLOAD_DETAIL) {
        if (indexPath.section == 0) {
            if (self.downloadingArray.count > 0) {
                if (indexPath.row < self.downloadingArray.count-1) {
                    SeafFile *sfile = self.downloadingArray[indexPath.row];
                    [cell showCellWithSFile:sfile];
                }
            }
        } else {
            SeafFile *sfile = self.finishArray[indexPath.row];
             [cell showCellWithSFile:sfile];
        }
    }
    return cell;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
