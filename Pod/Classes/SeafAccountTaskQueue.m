//
//  SeafAccountTaskQueue.m
//  Seafile
//
//  Created by henry on 2024/11/11.
//

#import "SeafDataTaskManager.h"
#import "SeafUploadOperation.h"
#import "SeafDownloadOperation.h"
#import "SeafThumbOperation.h"
#import "SeafAccountTaskQueue.h"
#import "SeafBase.h"
#import "SeafDir.h"
#import "Debug.h"

#define THUMB_MAX_COUNT 20
#define UPLOAD_MAX_COUNT 5
#define DOWNLOAD_MAX_COUNT 5

@implementation SeafAccountTaskQueue

- (instancetype)init {
    self = [super init];
    if (self) {
        self.downloadQueue = [[NSOperationQueue alloc] init];
        self.downloadQueue.maxConcurrentOperationCount = DOWNLOAD_MAX_COUNT;
        
        self.thumbQueue = [[NSOperationQueue alloc] init];
        self.thumbQueue.maxConcurrentOperationCount = THUMB_MAX_COUNT;
        self.thumbQueue.qualityOfService = NSQualityOfServiceUserInteractive;
        
        self.uploadQueue = [[NSOperationQueue alloc] init];
        self.uploadQueue.maxConcurrentOperationCount = UPLOAD_MAX_COUNT;
        
        self.ongoingTasks = [NSMutableArray array];
        self.waitingTasks = [NSMutableArray array];
        self.cancelledTasks = [NSMutableArray array];
        self.completedSuccessfulTasks = [NSMutableArray array];
        self.completedFailedTasks = [NSMutableArray array];
        
        // 初始化下载任务状态数组
        self.ongoingDownloadTasks = [NSMutableArray array];
        self.waitingDownloadTasks = [NSMutableArray array];
        self.cancelledDownloadTasks = [NSMutableArray array];
        self.completedSuccessfulDownloadTasks = [NSMutableArray array];
        self.completedFailedDownloadTasks = [NSMutableArray array];
        
        // 管理已取消的缩略图任务
        self.cancelledThumbTasks = [NSMutableArray array];

    }
    return self;
}

#pragma mark - 添加下载任务

- (void)addFileDownloadTask:(SeafFile * _Nonnull)dfile {
    // 检查任务是否已存在
    for (SeafDownloadOperation *op in self.downloadQueue.operations) {
        if ([op.file isEqual:dfile]) {
            return;
        }
    }
    SeafDownloadOperation *operation = [[SeafDownloadOperation alloc] initWithFile:dfile];
    [operation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:NULL];
    [operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:NULL];
    [operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:NULL];
    operation.observersAdded = YES; // Set to YES after adding observers

    // 初始状态为等待执行，添加到 waitingDownloadTasks
    @synchronized (self.waitingDownloadTasks) {
        [self.waitingDownloadTasks addObject:dfile];
    }
    
    [self.downloadQueue addOperation:operation];
}

- (BOOL)addUploadTask:(SeafUploadFile * _Nonnull)ufile {
    return [self addUploadTask:ufile priority:NSOperationQueuePriorityNormal];
}

- (BOOL)addUploadTask:(SeafUploadFile * _Nonnull)ufile priority:(NSOperationQueuePriority)priority {
    // Check if the task already exists
    for (SeafUploadOperation *op in self.uploadQueue.operations) {
        if ([op.uploadFile.lpath isEqual:ufile.lpath]) {
            return NO;
        }
    }
    SeafUploadOperation *operation = [[SeafUploadOperation alloc] initWithUploadFile:ufile];
//    operation.accountTaskQueue = self; // Set the weak reference
    [operation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:NULL];
    [operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:NULL];
    [operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:NULL];
    operation.observersAdded = YES; // Set to YES after adding observers
    operation.queuePriority = priority;
    // 初始状态为等待执行，添加到 waitingTasks
    @synchronized (self.waitingTasks) {
        [self.waitingTasks addObject:ufile];
    }
    
    [self.uploadQueue addOperation:operation];
    return YES;
}

- (void)addThumbTask:(SeafThumb * _Nonnull)thumb {
    // 检查任务是否在已取消的任务列表中
    if ([self resumeCancelledThumbTask:thumb]) {
        return; // 如果成功恢复任务，则直接返回
    }
    
    // Check if the task already exists
    for (SeafThumbOperation *op in self.thumbQueue.operations) {
        if ([op.file.oid isEqual:thumb.file.oid]) {
            return;
        }
    }
    
    SeafThumbOperation *operation = [[SeafThumbOperation alloc] initWithSeafFile:thumb.file];
    [self.thumbQueue addOperation:operation];
}

- (BOOL)resumeCancelledThumbTask:(SeafThumb * _Nonnull)thumb {
    @synchronized (self.cancelledThumbTasks) {
        for (SeafThumb *cancelledThumb in self.cancelledThumbTasks) {
            if ([cancelledThumb.file.oid isEqual:thumb.file.oid]) {
                // 从取消列表中移除
                [self.cancelledThumbTasks removeObject:cancelledThumb];
                // 重新添加任务
                SeafThumbOperation *operation = [[SeafThumbOperation alloc] initWithSeafFile:thumb.file];
                [self.thumbQueue addOperation:operation];
                return YES;
            }
        }
    }
    return NO;
}

- (void)removeFileDownloadTask:(SeafFile * _Nonnull)dfile {
    for (SeafDownloadOperation *op in self.downloadQueue.operations) {
        if ([op.file isEqual:dfile]) {
            [op cancel];
            break;
        }
    }
    // 从 waitingDownloadTasks 或 ongoingDownloadTasks 中移除，加入 cancelledDownloadTasks
    [self removeDownloadTask:dfile fromArray:self.waitingDownloadTasks];
    [self removeDownloadTask:dfile fromArray:self.ongoingDownloadTasks];
    [self addDownloadTask:dfile toArray:self.cancelledDownloadTasks];
    
    [self postDownloadTaskStatusChangedNotification];
}

- (void)removeUploadTask:(SeafUploadFile * _Nonnull)ufile {
    for (SeafUploadOperation *op in self.uploadQueue.operations) {
        if ([op.uploadFile isEqual:ufile]) {
            [op cancel];
            break;
        }
    }
    // 从 waitingTasks 或 ongoingTasks 中移除，加入 cancelledTasks
    [self removeTask:ufile fromArray:self.waitingTasks];
    [self removeTask:ufile fromArray:self.ongoingTasks];
    [self addTask:ufile toArray:self.cancelledTasks];
    
    [self postUploadTaskStatusChangedNotification];
}

- (void)removeThumbTask:(SeafThumb * _Nonnull)thumb {
    for (SeafThumbOperation *op in self.thumbQueue.operations) {
        if ([op.file.oid isEqual:thumb.file.oid]) {
            [op cancel];
            // 将任务加入取消列表
            @synchronized (self.cancelledThumbTasks) {
                [self.cancelledThumbTasks addObject:thumb];
            }
            break;
        }
    }
}

- (void)cancelAutoSyncTasks:(SeafConnection *)conn {
    [self.uploadQueue setSuspended:YES];

    // 遍历 ongoingTasks
    @synchronized (self.ongoingTasks) {
        NSArray *ongoingTasksCopy = [self.ongoingTasks copy];
        for (SeafUploadFile *ufile in ongoingTasksCopy) {
            if (ufile.uploadFileAutoSync && ufile.udir->connection == conn) {
                // 找到对应的 SeafUploadOperation
                for (SeafUploadOperation *op in self.uploadQueue.operations) {
                    if (op.uploadFile == ufile) {
                        [op cancel];
                        break;
                    }
                }
                // 从 ongoingTasks 中移除，加入 cancelledTasks
                [self removeTask:ufile fromArray:self.ongoingTasks];
                [self addTask:ufile toArray:self.cancelledTasks];
            }
        }
    }

    // 遍历 waitingTasks
    @synchronized (self.waitingTasks) {
        NSArray *waitingTasksCopy = [self.waitingTasks copy];
        for (SeafUploadFile *ufile in waitingTasksCopy) {
            if (ufile.uploadFileAutoSync && ufile.udir->connection == conn) {
                // 找到对应的 SeafUploadOperation
                for (SeafUploadOperation *op in self.uploadQueue.operations) {
                    if (op.uploadFile == ufile) {
                        [op cancel];
                        break;
                    }
                }
                // 从 waitingTasks 中移除，加入 cancelledTasks
                [self removeTask:ufile fromArray:self.waitingTasks];
                [self addTask:ufile toArray:self.cancelledTasks];
            }
        }
    }

    // Resume the operation queue
    [self.uploadQueue setSuspended:NO];
    
    // 发送任务状态变更通知
    [self postUploadTaskStatusChangedNotification];
}

- (void)cancelAutoSyncVideoTasks:(SeafConnection *)conn {
    [self.uploadQueue setSuspended:YES];

    // 遍历 ongoingTasks
    @synchronized (self.ongoingTasks) {
        NSArray *ongoingTasksCopy = [self.ongoingTasks copy];
        for (SeafUploadFile *ufile in ongoingTasksCopy) {
            if (ufile.uploadFileAutoSync && ufile.udir->connection == conn && !ufile.isImageFile) {
                // 找到对应的 SeafUploadOperation
                for (SeafUploadOperation *op in self.uploadQueue.operations) {
                    if (op.uploadFile == ufile) {
                        [op cancel];
                        break;
                    }
                }
                // 从 ongoingTasks 中移除，加入 cancelledTasks
                [self removeTask:ufile fromArray:self.ongoingTasks];
                [self addTask:ufile toArray:self.cancelledTasks];
            }
        }
    }

    // 遍历 waitingTasks
    @synchronized (self.waitingTasks) {
        NSArray *waitingTasksCopy = [self.waitingTasks copy];
        for (SeafUploadFile *ufile in waitingTasksCopy) {
            if (ufile.uploadFileAutoSync && ufile.udir->connection == conn && !ufile.isImageFile) {
                // 找到对应的 SeafUploadOperation
                for (SeafUploadOperation *op in self.uploadQueue.operations) {
                    if (op.uploadFile == ufile) {
                        [op cancel];
                        break;
                    }
                }
                // 从 waitingTasks 中移除，加入 cancelledTasks
                [self removeTask:ufile fromArray:self.waitingTasks];
                [self addTask:ufile toArray:self.cancelledTasks];
            }
        }
    }
    
    [self.uploadQueue setSuspended:NO];

    // 发送任务状态变更通知
    [self postUploadTaskStatusChangedNotification];
}

- (NSArray *)getUploadTasksInDir:(SeafDir *)dir {
    NSMutableArray *filesInDir = [NSMutableArray array];
    for (SeafUploadOperation *op in self.uploadQueue.operations) {
        SeafUploadFile *ufile = op.uploadFile;
        if (!ufile.isEditedFile && [ufile.udir.repoId isEqualToString:dir.repoId] && [ufile.udir.path isEqualToString:dir.path]) {
            [filesInDir addObject:ufile];
        }
    }
    return filesInDir;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([object isKindOfClass:[SeafUploadOperation class]]) {
        SeafUploadOperation *operation = (SeafUploadOperation *)object;
        SeafUploadFile *ufile = operation.uploadFile;
        
        if ([keyPath isEqualToString:@"isExecuting"]) {
            BOOL isExecuting = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
            if (isExecuting) {
                // 任务开始执行，从 waitingTasks 移到 ongoingTasks
                [self moveTask:ufile fromArray:self.waitingTasks toArray:self.ongoingTasks];
            }
        } else if ([keyPath isEqualToString:@"isFinished"]) {
            BOOL isFinished = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
            if (isFinished) {
                // 任务已完成，从 ongoingTasks 移除
                [self removeTask:ufile fromArray:self.ongoingTasks];
                
                // 根据上传结果，放入成功或失败的数组
                if (ufile.uploaded) {
                    [self addTask:ufile toArray:self.completedSuccessfulTasks];
                } else {
                    [self addTask:ufile toArray:self.completedFailedTasks];
                }

                // 移除观察者
                [self safelyRemoveObserversFromOperation:operation];
                
            }
        } else if ([keyPath isEqualToString:@"isCancelled"]) {
            BOOL isCancelled = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
            if (isCancelled) {
                // 任务已取消，从 waitingTasks 或 ongoingTasks 中移除，加入 cancelledTasks
                [self removeTask:ufile fromArray:self.waitingTasks];
                [self removeTask:ufile fromArray:self.ongoingTasks];
                [self addTask:ufile toArray:self.cancelledTasks];

                // 移除观察者
                [self safelyRemoveObserversFromOperation:operation];
            }
        }
        [self postUploadTaskStatusChangedNotification];
    }
    else if ([object isKindOfClass:[SeafDownloadOperation class]]) {
            SeafDownloadOperation *operation = (SeafDownloadOperation *)object;
            SeafFile *dfile = operation.file;
            
            if ([keyPath isEqualToString:@"isExecuting"]) {
                BOOL isExecuting = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
                if (isExecuting) {
                    // 任务开始执行，从 waitingDownloadTasks 移到 ongoingDownloadTasks
                    [self moveDownloadTask:dfile fromArray:self.waitingDownloadTasks toArray:self.ongoingDownloadTasks];
                }
            } else if ([keyPath isEqualToString:@"isFinished"]) {
                BOOL isFinished = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
                if (isFinished) {
                    // 任务已完成，从 ongoingDownloadTasks 移除
                    [self removeDownloadTask:dfile fromArray:self.ongoingDownloadTasks];
                    
                    // 根据下载结果，放入成功或失败的数组
                    if (dfile.downloaded) { 
                        [self addDownloadTask:dfile toArray:self.completedSuccessfulDownloadTasks];
                    } else {
                        [self addDownloadTask:dfile toArray:self.completedFailedDownloadTasks];
                    }

                    // 移除观察者
                    [self safelyRemoveObserversFromOperation:operation];
                }
            } else if ([keyPath isEqualToString:@"isCancelled"]) {
                BOOL isCancelled = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
                if (isCancelled) {
                    // 任务已取消，从 waitingDownloadTasks 或 ongoingDownloadTasks 中移除，加入 cancelledDownloadTasks
                    [self removeDownloadTask:dfile fromArray:self.waitingDownloadTasks];
                    [self removeDownloadTask:dfile fromArray:self.ongoingDownloadTasks];
                    [self addDownloadTask:dfile toArray:self.cancelledDownloadTasks];
                
                    // 移除观察者
                    [self safelyRemoveObserversFromOperation:operation];
                }
            }
            [self postDownloadTaskStatusChangedNotification];
        } else {
            [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        }
}

#pragma mark - 发送通知

- (void)postUploadTaskStatusChangedNotification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SeafUploadTaskStatusChanged" object:self];
    });
}

- (void)postDownloadTaskStatusChangedNotification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SeafDownloadTaskStatusChanged" object:self];
    });
}

#pragma mark - 上传任务辅助方法

// 从一个数组中移除任务
- (void)removeTask:(SeafUploadFile *)task fromArray:(NSMutableArray<SeafUploadFile *> *)array {
    @synchronized (array) {
        [array removeObject:task];
    }
}

// 将任务从一个数组移动到另一个数组
- (void)moveTask:(SeafUploadFile *)task fromArray:(NSMutableArray<SeafUploadFile *> *)fromArray toArray:(NSMutableArray<SeafUploadFile *> *)toArray {
    [self removeTask:task fromArray:fromArray];
    [self addTask:task toArray:toArray];
}

// 将任务添加到数组
- (void)addTask:(SeafUploadFile *)task toArray:(NSMutableArray<SeafUploadFile *> *)array {
    @synchronized (array) {
        if (![array containsObject:task]) {
            [array addObject:task];
        }
    }
}

#pragma mark - 下载任务辅助方法

// 从一个数组中移除下载任务
- (void)removeDownloadTask:(SeafFile *)task fromArray:(NSMutableArray<SeafFile *> *)array {
    @synchronized (array) {
        [array removeObject:task];
    }
}

// 将下载任务从一个数组移动到另一个数组
- (void)moveDownloadTask:(SeafFile *)task fromArray:(NSMutableArray<SeafFile *> *)fromArray toArray:(NSMutableArray<SeafFile *> *)toArray {
    [self removeDownloadTask:task fromArray:fromArray];
    [self addDownloadTask:task toArray:toArray];
}

// 将下载任务添加到数组
- (void)addDownloadTask:(SeafFile *)task toArray:(NSMutableArray<SeafFile *> *)array {
    @synchronized (array) {
        if (![array containsObject:task]) {
            [array addObject:task];
        }
    }
}

#pragma mark - 获取上传任务状态数组
- (NSArray<SeafUploadFile *> *)getNeedUploadTasks {
    NSArray *ongoingTasks = [self getOngoingTasks];
    NSArray *waitingTasks = [self getWaitingTasks];
    
    // 如果为 nil，则替换为空数组
    ongoingTasks = ongoingTasks ?: @[];
    waitingTasks = waitingTasks ?: @[];
    
    NSArray *allNeedUpLoadTasks = [ongoingTasks arrayByAddingObjectsFromArray:waitingTasks];
    return allNeedUpLoadTasks;
}

- (NSArray<SeafUploadFile *> *)getOngoingTasks {
    @synchronized (self.ongoingTasks) {
        return [self.ongoingTasks copy];
    }
}

- (NSArray<SeafUploadFile *> *)getWaitingTasks {
    @synchronized (self.waitingTasks) {
        return [self.waitingTasks copy];
    }
}

- (NSArray<SeafUploadFile *> *)getCancelledTasks {
    @synchronized (self.cancelledTasks) {
        return [self.cancelledTasks copy];
    }
}

- (NSArray<SeafUploadFile *> *)getCompletedSuccessfulTasks {
    @synchronized (self.completedSuccessfulTasks) {
        return [self.completedSuccessfulTasks copy];
    }
}

- (NSArray<SeafUploadFile *> *)getCompletedFailedTasks {
    @synchronized (self.completedFailedTasks) {
        return [self.completedFailedTasks copy];
    }
}

#pragma mark - 获取下载任务状态数组
- (NSArray<SeafFile *> *_Nullable)getNeedDownloadTasks {
    NSArray *ongoingTasks = [self getOngoingDownloadTasks];
    NSArray *waitingTasks = [self getWaitingDownloadTasks];
    
    // 如果为 nil，则替换为空数组
    ongoingTasks = ongoingTasks ?: @[];
    waitingTasks = waitingTasks ?: @[];
    
    NSArray *allNeedDownloadTasks = [ongoingTasks arrayByAddingObjectsFromArray:waitingTasks];
    return allNeedDownloadTasks;
}

- (NSArray<SeafFile *> *)getOngoingDownloadTasks {
    @synchronized (self.ongoingDownloadTasks) {
        return [self.ongoingDownloadTasks copy];
    }
}

- (NSArray<SeafFile *> *)getWaitingDownloadTasks {
    @synchronized (self.waitingDownloadTasks) {
        return [self.waitingDownloadTasks copy];
    }
}

- (NSArray<SeafFile *> *)getCancelledDownloadTasks {
    @synchronized (self.cancelledDownloadTasks) {
        return [self.cancelledDownloadTasks copy];
    }
}

- (NSArray<SeafFile *> *)getCompletedSuccessfulDownloadTasks {
    @synchronized (self.completedSuccessfulDownloadTasks) {
        return [self.completedSuccessfulDownloadTasks copy];
    }
}

- (NSArray<SeafFile *> *)getCompletedFailedDownloadTasks {
    @synchronized (self.completedFailedDownloadTasks) {
        return [self.completedFailedDownloadTasks copy];
    }
}

#pragma mark - 取消任务
//取消所有任务
- (void)cancelAllTasks {
    [self cancelAllUploadTasks];
    [self cancelAllDownloadTasks];
    [self.thumbQueue cancelAllOperations];
    
    // 发送相应的通知
//    [self postUploadTaskStatusChangedNotification];
//    [self postDownloadTaskStatusChangedNotification];
}

//取消所有上传任务
- (void)cancelAllUploadTasks {
    [self.uploadQueue setSuspended:YES];

    // 取消上传队列中的所有操作
    for (SeafUploadOperation *op in self.uploadQueue.operations) {
        [op cancel];
        [self safelyRemoveObserversFromOperation:op];
    }
    // 清空正在进行和等待中的上传任务数组，并将它们加入已取消的任务数组
    @synchronized (self.ongoingTasks) {
        [self.cancelledTasks addObjectsFromArray:self.ongoingTasks];
        [self.ongoingTasks removeAllObjects];
    }
    @synchronized (self.waitingTasks) {
        [self.cancelledTasks addObjectsFromArray:self.waitingTasks];
        [self.waitingTasks removeAllObjects];
    }
    
    [self.uploadQueue setSuspended:NO];

    [self postUploadTaskStatusChangedNotification];
}

//取消所有下载任务的方法
- (void)cancelAllDownloadTasks {
    [self.downloadQueue setSuspended:YES];

    // 取消下载队列中的所有操作
    for (SeafDownloadOperation *op in self.downloadQueue.operations) {
        [op cancel];
        [self safelyRemoveObserversFromOperation:op];
    }
    // 清空正在进行和等待中的下载任务数组，并将它们加入已取消的任务数组
    @synchronized (self.ongoingDownloadTasks) {
        [self.cancelledDownloadTasks addObjectsFromArray:self.ongoingDownloadTasks];
        [self.ongoingDownloadTasks removeAllObjects];
    }
    @synchronized (self.waitingDownloadTasks) {
        [self.cancelledDownloadTasks addObjectsFromArray:self.waitingDownloadTasks];
        [self.waitingDownloadTasks removeAllObjects];
    }
    
    [self.downloadQueue setSuspended:NO];

    [self postDownloadTaskStatusChangedNotification];
}

#pragma mark - 移除观察者

- (void)safelyRemoveObserversFromOperation:(SeafBaseOperation *)operation {
    if (operation.observersAdded && !operation.observersRemoved) {
        @try {
            [operation removeObserver:self forKeyPath:@"isExecuting"];
            [operation removeObserver:self forKeyPath:@"isFinished"];
            [operation removeObserver:self forKeyPath:@"isCancelled"];
            operation.observersRemoved = YES;
        } @catch (NSException *exception) {
            NSLog(@"Exception when removing observer: %@", exception);
        }
    }
}

@end
