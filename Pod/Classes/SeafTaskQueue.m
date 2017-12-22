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

@end

@implementation SeafTaskQueue

- (instancetype)init {
    self = [super init];
    if (self) {
        self.concurrency = DEFAULT_CONCURRENCY;
        self.attemptInterval = DEFAULT_ATTEMPT_INTERVAL;
        self.failedCount = 0;
        self.tasks = [NSMutableArray array];
        self.ongoingTasks = [NSMutableArray array];
        self.completedTasks = [NSMutableArray array];
        __weak typeof(self) weakSelf = self;
        self.innerQueueTaskCompleteBlock = ^(id<SeafTask> task, BOOL result) {
            if (![weakSelf.ongoingTasks containsObject:task]) return;
            @synchronized (weakSelf.ongoingTasks) { // task succeeded, remove it
                [weakSelf.ongoingTasks removeObject:task];
            }
            Debug("finish task %@, %ld tasks remained.",task.name, (long)[weakSelf taskNumber]);
            task.lastFinishTimestamp = [[NSDate new] timeIntervalSince1970];
            if (!result) { // Task fail, add to the tail of queue for retry
                @synchronized (weakSelf.tasks) {
                    if (task.retryable) [weakSelf.tasks addObject:task];
                    weakSelf.failedCount += 1;
                }
            } else {
                if (![weakSelf.completedTasks containsObject:task]) {
                    @synchronized (weakSelf.completedTasks) { // task succeeded, add to completedTasks
                        [weakSelf.completedTasks addObject:task];
                    }
                }
            }
            if (weakSelf.taskCompleteBlock) {
                weakSelf.taskCompleteBlock(task, result);
            }
            [weakSelf tick];
        };
        self.innerQueueTaskProgressBlock = ^(id<SeafTask> task, float progress) {
            if (weakSelf.taskProgressBlock) {
                weakSelf.taskProgressBlock(task, progress);
            }
        };
    }
    return self;
}

- (void)addTask:(id<SeafTask>)task {
    @synchronized (self.tasks) {
        if (![self.tasks containsObject:task] && ![self.ongoingTasks containsObject:task]) {
            task.lastFinishTimestamp = 0;
            [self.tasks addObject:task];
            Debug("Added task %@: %ld", task.name, (unsigned long)self.tasks.count);
        }
    }
    [self tick];
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
    [self performSelectorInBackground:@selector(runTasks) withObject:nil];
    [self performSelectorInBackground:@selector(removOldCompletedTask) withObject:nil];
}

- (void)runTasks {
    if (![[AFNetworkReachabilityManager sharedManager] isReachable] || self.tasks.count == 0) {
        return;
    }

    while (self.ongoingTasks.count + self.failedCount < self.concurrency) {
        id<SeafTask> task = [self pickTask];
        if (!task) break;
        @synchronized (self.ongoingTasks) {
            [self.ongoingTasks addObject:task];
        }
        [task run:self.innerQueueTaskCompleteBlock];
    }
}

- (id<SeafTask>)pickTask {
    id<SeafTask> runableTask;
    @synchronized (self.tasks) {
        for (id<SeafTask> task in self.tasks) {
            if (task.runable && task.lastFinishTimestamp < ([[NSDate new] timeIntervalSince1970] - self.attemptInterval)) {
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
        for (id<SeafTask> task in self.completedTasks) {
            //remove task finished more than 3 min
            if ([[NSDate new] timeIntervalSinceNow] - task.lastFinishTimestamp > DEFAULT_COMPLELE_INTERVAL) {
                [tempArray addObject:task];
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

@end
