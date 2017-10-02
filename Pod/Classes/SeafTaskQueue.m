//
//  SeafTaskQueue.m
//  Pods
//
//  Created by three on 2017/10/2.
//
//

#import "SeafTaskQueue.h"
#import "Debug.h"
#import "SeafThumb.h"
#import "SeafAvatar.h"
#import "SeafDir.h"

@interface SeafTaskQueue ()

@property (nonatomic, strong) NSTimer *taskTimer;
@property unsigned long failedNum;

@end

@implementation SeafTaskQueue

- (NSMutableArray *)tasks {
    if (!_tasks) {
        _tasks = [NSMutableArray array];
    }
    return _tasks;
}

- (NSMutableArray *)ongoingTasks {
    if (!_ongoingTasks) {
        _ongoingTasks = [NSMutableArray array];
    }
    return _ongoingTasks;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.concurrency = 3;
        self.failedNum = 0;
        [self startTimer];
    }
    return self;
}

- (void)addTask:(id)task {
    @synchronized (self.tasks) {
        if (![self.tasks containsObject:task] && ![self.ongoingTasks containsObject:task]) {
            [self.tasks addObject:task];
            Debug("Added file task %@: %ld", [task valueForKey:@"name"], (unsigned long)self.tasks.count);
        }
    }
    if ([task isKindOfClass:[SeafUploadFile class]]) {
        [self performSelectorInBackground:@selector(tryRunUploadTask) withObject:nil];
    } else {
        [self tryRunDownloadTask];
    }
}

- (void)tryRunDownloadTask {
    if (self.tasks.count == 0) return;
    while ([self isActiveDownloadingFileCountBelowMaximumLimit]) {
        id<SeafDownloadDelegate> task = nil;
        @synchronized (self.tasks) {
            if (self.tasks.count == 0) {
                return;
            }
            // TODO if file last failed download timestamp < now-1min, skip that task
            for (int i = 0; i < self.tasks.count; i++) {
                task = [self.tasks objectAtIndex:i];
                if ([task isKindOfClass:[SeafFile class]]) {
                    SeafFile *file = (SeafFile*)task;
                    if (file.state != SEAF_DENTRY_FAILURE && file.failTime < ([[NSDate new] timeIntervalSince1970] - 60)) {
                        [self.tasks removeObject:task];
                        break;
                    }
                } else {
                    task = self.tasks.firstObject;
                    [self.tasks removeObject:task];
                }
            }
        }
        if (!task) return;
        @synchronized (self.ongoingTasks) {
            [self.ongoingTasks addObject:task];
        }
        [task download];
    }
}

- (void)tryRunUploadTask {
    double delayInMs = 400.0;
    if (self.tasks.count == 0) return;
    while ([self isActiveDownloadingFileCountBelowMaximumLimit]) {
        SeafUploadFile *task = nil;
        @synchronized (self.tasks) {
            if (self.tasks.count == 0) {
                return;
            }
            for (int i = 0; i < self.tasks.count; i++) {
                task = [self.tasks objectAtIndex:i];
                if (task.canUpload && !task.uploaded) {
                    [self.tasks removeObject:task];
                    break;
                }
            }
        }
        if (!task) return;
        @synchronized (self.ongoingTasks) {
            [self.ongoingTasks addObject:task];
        }
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, self.ongoingTasks.count * delayInMs * NSEC_PER_MSEC);
        dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(void){
            [task doUpload];
        });
    }
}

- (NSInteger)downloadingNum {
    return self.tasks.count + self.ongoingTasks.count;
}

- (NSArray *)allTasks {
    NSMutableArray *arr = [NSMutableArray new];
    [arr addObjectsFromArray:self.tasks];
    [arr addObjectsFromArray:self.ongoingTasks];
    return arr;
}

- (void)finishTask:(id<SeafDownloadDelegate>)task result:(BOOL)result {
    if ([self.ongoingTasks containsObject:task]) {
        Debug("finish file task %@: %ld",task.name, (unsigned long)self.tasks.count);
        if (result) {
            @synchronized (self.ongoingTasks) { // task succeeded, remove it
                [self.ongoingTasks removeObject:task];
            }
        } else if (task.retryable) { // Task fail, add to the tail of queue for retry
            @synchronized (self.tasks) {
                [self.tasks addObject:task];
            }
        }
        [self tryRunDownloadTask];
    }
}

- (void)finishUploadTask:(SeafUploadFile *)task result:(BOOL)result {
    Debug("upload %ld, result=%d, file=%@, udir=%@", (long)self.ongoingTasks.count, result, task.lpath, task.udir.path);
    @synchronized (self.ongoingTasks) {
        [self.ongoingTasks removeObject:task];
    }
    if (result) {
        self.failedNum = 0;
    } else {
        self.failedNum ++;
        if (!task.removed) {
            [self.tasks addObject:task];
        } else
            Debug("Upload file %@ removed.", task.name);
        if (self.failedNum >= 3) {
            [self performSelector:@selector(tryRunUploadTask) withObject:nil afterDelay:10.0];
            self.failedNum = 2;
            return;
        }
    }
    [self performSelector:@selector(tick:) withObject:_taskTimer afterDelay:0.1];
}

- (void)tick:(NSTimer *)timer {
    if (![[AFNetworkReachabilityManager sharedManager] isReachable]) {
        return;
    }
    if (self.tasks.count > 0) {
        if ([self.tasks.firstObject isKindOfClass:[SeafUploadFile class]]) {
            [self tryRunUploadTask];
        } else {
            [self tryRunDownloadTask];
        }
    }
}

- (void)startTimer {
    Debug("Start timer.");
    [self tick:nil];
    self.taskTimer = [NSTimer scheduledTimerWithTimeInterval:5*60 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        [self tick:self.taskTimer];
    }];
}

- (BOOL)isActiveDownloadingFileCountBelowMaximumLimit {
    return self.ongoingTasks.count + self.failedNum <= self.concurrency;
}

- (void)clear {
    [self.tasks removeAllObjects];
    [self.ongoingTasks removeAllObjects];
}

@end
