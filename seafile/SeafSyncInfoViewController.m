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
@property (nonatomic, strong) NSMutableArray *ongongingArray;
@property (nonatomic, strong) SeafConnection *connection;

@end

@implementation SeafSyncInfoViewController

- (NSMutableArray *)finishArray {
    if (!_finishArray) {
        _finishArray = [NSMutableArray array];
    }
    return _finishArray;
}

- (NSMutableArray *)ongongingArray {
    if (!_ongongingArray) {
        _ongongingArray = [NSMutableArray array];
    }
    return _ongongingArray;
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
        self.navigationItem.title = NSLocalizedString(@"Uploading", @"Seafile");;
    }

    self.connection = [SeafGlobal sharedObject].connection;

    [self addToFileArray];

    WS(weakSelf);
    SeafDataTaskManager.sharedObject.trySyncBlock = ^(id  _Nullable file) {
        if (![weakSelf.ongongingArray containsObject:file]) {
            if (self.detailType == DOWNLOAD_DETAIL) {
                SeafFile *dfile = (SeafFile*)file;
                if (dfile->connection == self.connection) {
                    @synchronized (weakSelf.ongongingArray) {
                        [weakSelf.ongongingArray addObject:dfile];
                    }
                }
            } else {
                SeafUploadFile *ufile = (SeafUploadFile*)file;
                if (ufile.accountIdentifier == self.connection.accountIdentifier) {
                    @synchronized (weakSelf.ongongingArray) {
                        [weakSelf.ongongingArray addObject:ufile];
                    }
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.tableView reloadData];
        });
    };

    SeafDataTaskManager.sharedObject.finishBlock = ^(id<SeafTask>  _Nonnull task) {
        if (self.detailType == DOWNLOAD_DETAIL) {
            SeafFile *file = (SeafFile*)task;
            if (file->connection == self.connection) {
                @synchronized (weakSelf.ongongingArray) {
                     [weakSelf.ongongingArray removeObject:file];
                }
                @synchronized (weakSelf.finishArray) {
                    [weakSelf.finishArray addObject:file];
                }
            }
        } else {
            SeafUploadFile *ufile = (SeafUploadFile*)task;
            if (ufile.accountIdentifier == self.connection.accountIdentifier) {
                @synchronized (weakSelf.ongongingArray) {
                    [weakSelf.ongongingArray removeObject:ufile];
                }
                @synchronized (weakSelf.finishArray) {
                    [weakSelf.finishArray addObject:ufile];
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.tableView reloadData];
        });
    };
}

- (void)addToFileArray {
    SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection];
    if (self.detailType == DOWNLOAD_DETAIL) {
        for (SeafFile *file in accountQueue.fileQueue.allTasks) {
            if (file.state == SEAF_DENTRY_SUCCESS) {
                @synchronized (self.finishArray) {
                    [self.finishArray addObject:file];
                }
            } else {
                @synchronized (self.ongongingArray) {
                    [self.ongongingArray addObject:file];
                }
            }
        }
    } else {
        for (SeafUploadFile *file in accountQueue.uploadQueue.allTasks) {
            if (file.uploading || !file.uploaded) {
                @synchronized (self.ongongingArray) {
                    [self.ongongingArray addObject:file];
                }
            } else {
                @synchronized (self.finishArray) {
                    [self.finishArray addObject:file];
                }
            }
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
        return self.ongongingArray.count;
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
    if (indexPath.section == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.ongongingArray.count > 0 && self.ongongingArray.count > indexPath.row) {
                [cell showCellWithFile:self.ongongingArray[indexPath.row]];
            }
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.finishArray.count > 0 && self.finishArray.count > indexPath.row) {
                [cell showCellWithFile:self.finishArray[indexPath.row]];
            }
        });
    }
    return cell;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
