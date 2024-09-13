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

@property (nonatomic, strong) NSMutableArray *tasks;
@property (nonatomic, strong) NSMutableArray *ongoingTasks;
@property (nonatomic, copy) TaskCompleteBlock innerQueueTaskCompleteBlock;
@property (nonatomic, copy) TaskProgressBlock innerQueueTaskProgressBlock;
@property unsigned long failedCount;
@property (nonatomic, strong) dispatch_semaphore_t semaphore;

@end

@implementation SeafTaskQueue

- (instancetype)init {
    self = [super init];
    if (self) {
        self.concurrency = DEFAULT_CONCURRENCY;
        self.attemptInterval = DEFAULT_ATTEMPT_INTERVAL;
        self.failedCount = 0;
        self.semaphore = dispatch_semaphore_create(1);
        __weak typeof(self) weakSelf = self;
        self.innerQueueTaskCompleteBlock = ^(id<SeafTask> task, BOOL result) {
            __strong __typeof(self) strongSelf = weakSelf;
            @synchronized (strongSelf.ongoingTasks) { // task succeeded, remove it
                if (![strongSelf.ongoingTasks containsObject:task]) {
                    return;
                }
                [strongSelf.ongoingTasks removeObject:task];
            }
            Debug("finish task %@, %ld tasks remained.",task.name, (long)[weakSelf taskNumber]);
            task.lastFinishTimestamp = [[NSDate new] timeIntervalSince1970];
            if (!result) { // Task fail, add to the tail of queue for retry
                @synchronized (strongSelf.tasks) {
                    strongSelf.failedCount += 1;
                    if (task.retryable) {
                        task.retryCount += 1;
                        [strongSelf.tasks addObject:task];
                    }
                }
            } else {
                strongSelf.failedCount = 0;
                @synchronized (strongSelf.completedTasks) { // task succeeded, add to completedTasks
                    if (![strongSelf.completedTasks containsObject:task]) {
                        [strongSelf.completedTasks addObject:task];
                    }
                }
            }
            if (strongSelf.taskCompleteBlock) {
                strongSelf.taskCompleteBlock(task, result);
            }
            [strongSelf tick];
        };
        self.innerQueueTaskProgressBlock = ^(id<SeafTask> task, float progress) {
            __strong __typeof(self) strongSelf = weakSelf;
            if (strongSelf.taskProgressBlock) {
                strongSelf.taskProgressBlock(task, progress);
            }
        };
    }
    return self;
}

- (BOOL)addTask:(id<SeafTask>)task {
    BOOL res = YES;
    @synchronized (self.tasks) {
        if (task != nil && ![self.tasks containsObject:task] && ![self.ongoingTasks containsObject:task]) {
            task.lastFinishTimestamp = 0;
            task.retryCount = 0;
            [self.tasks addObject:task];
            Debug("Added task %@: %ld", task.name, (unsigned long)self.tasks.count);
        } else {
            res = NO;
        }
    }
    [self tick];
    return res;
}

- (NSInteger)taskNumber {
    return self.tasks.count + self.ongoingTasks.count;
}

- (NSArray *)allTasks {
    NSMutableArray *arr = [NSMutableArray new];
    [arr addObjectsFromArray:self.tasks];
    [arr addObjectsFromArray:self.ongoingTasks];
    return arr;
}

- (void)tick {
    if (self.failedCount > 0) self.failedCount -= 1;
    [self performSelectorInBackground:@selector(runTasks) withObject:nil];
    [self performSelectorInBackground:@selector(removOldCompletedTask) withObject:nil];
}

- (void)runTasks {
    if (![[AFNetworkReachabilityManager sharedManager] isReachable] || self.tasks.count == 0) {
        return;
    }
    
    dispatch_semaphore_wait(self.semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)));
    while (self.ongoingTasks.count < self.concurrency && self.failedCount < self.concurrency) {
        id<SeafTask> task = [self pickTask];
        if (!task) break;
        @synchronized (self.ongoingTasks) {
            [self.ongoingTasks addObject:task];
        }
        [task run:self.innerQueueTaskCompleteBlock];
    }
    dispatch_semaphore_signal(self.semaphore);
}

- (id<SeafTask>)pickTask {
    id<SeafTask> runableTask;
    @synchronized (self.tasks) {
        for (id<SeafTask> task in self.tasks) {
            if (task.runable && task.lastFinishTimestamp < ([[NSDate new] timeIntervalSince1970] - self.attemptInterval) && task.retryCount < DEFAULT_RETRYCOUNT) {
                runableTask = task;
                break;
            }
        }
        if (runableTask) {
            [self.tasks removeObject:runableTask];
        }
    }
    return runableTask;
}

- (void)removeTask:(id<SeafTask>)task {
    task.retryable = false;
    @synchronized (self.tasks) {
        if ([self.tasks containsObject:task]) {
//            Debug(@"Delete task ,remain undeleted %lu", (unsigned long)self.tasks.count);
            return [self.tasks removeObject:task];
        }
        @synchronized (self.ongoingTasks) {
            if ([self.ongoingTasks containsObject:task]) {
                [self.ongoingTasks removeObject:task];
                [task cancel];
            }
        }
    }
}

- (void)removOldCompletedTask {
    NSMutableArray *tempArray = [NSMutableArray array];
    @synchronized (self.completedTasks) {
        NSArray *copyArray = [NSArray arrayWithArray:self.completedTasks];
        for (id<SeafTask> task in copyArray) {
            //remove task finished more than 3 min
            if ([[NSDate date] timeIntervalSince1970] - task.lastFinishTimestamp > DEFAULT_COMPLELE_INTERVAL) {
                [tempArray addObject:task];
                if ([task respondsToSelector:@selector(cleanup)]) {
                    [task cleanup];
                }
            }
        }
        [self.completedTasks removeObjectsInArray:tempArray];
    }
}

- (void)clearTasks {
    @synchronized (self.tasks) {
        for (id<SeafTask> task in self.tasks) {
            task.retryable = false;
        }
        [self.tasks removeAllObjects];
    }
    NSArray *arr = [NSArray arrayWithArray:self.ongoingTasks];
    for (id<SeafTask> task in arr) {
        task.retryable = false;
        [task cancel];
    }
    [self.ongoingTasks removeAllObjects];

    [self.completedTasks removeAllObjects];
    self.failedCount = 0;
}

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

- (NSMutableArray *)completedTasks {
    if (!_completedTasks) {
        _completedTasks = [NSMutableArray array];
    }
    return _completedTasks;
}

@end
