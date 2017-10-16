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
@property (nonatomic, copy) TaskCompleteBlock taskCompleteBlock;
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
        __weak typeof(self) weakSelf = self;
        self.taskCompleteBlock = ^(id<SeafTask> task, BOOL result) {
            if (![weakSelf.ongoingTasks containsObject:task]) return;
            Debug("finish task %@, %ld tasks remained.",task.name, (long)[weakSelf taskNumber]);
            @synchronized (weakSelf.ongoingTasks) { // task succeeded, remove it
                [weakSelf.ongoingTasks removeObject:task];
            }
            if (!result && task.retryable) { // Task fail, add to the tail of queue for retry
                task.lastFailureTimestamp = [[NSDate new] timeIntervalSince1970];
                @synchronized (weakSelf.tasks) {
                    [weakSelf.tasks addObject:task];
                    weakSelf.failedCount += 1;
                }
            }
            if (weakSelf.finishTaskBlock) {
                weakSelf.finishTaskBlock(task, result);
            }
            [weakSelf tick];
        };
    }
    return self;
}

- (void)addTask:(id<SeafTask>)task {
    @synchronized (self.tasks) {
        if (![self.tasks containsObject:task] && ![self.ongoingTasks containsObject:task]) {
            task.lastFailureTimestamp = 0;
            [self.tasks addObject:task];
            Debug("Added file task %@: %ld", task.name, (unsigned long)self.tasks.count);
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
}

- (void)runTasks {
    if (![[AFNetworkReachabilityManager sharedManager] isReachable] || self.tasks.count == 0) {
        return;
    }

    NSMutableArray *todo = [NSMutableArray new];
    @synchronized (self.tasks) {
        for (id<SeafTask> task in self.tasks) {
            if (!task.runable) continue;
            if (task.lastFailureTimestamp < ([[NSDate new] timeIntervalSince1970] - self.attemptInterval)) {
                // did not fail recently
                [todo addObject:task];
            }
            if (self.ongoingTasks.count + todo.count + self.failedCount >= self.concurrency) break;
        }
        for (id<SeafTask> task in todo) {
            [self.tasks removeObject:task];
            [self.ongoingTasks addObject:task];
        }
    }
    for (id<SeafTask> task in todo) {
        [task run:self.taskCompleteBlock];
    }
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

- (void)clear {
    [self.tasks removeAllObjects];
    [self.ongoingTasks removeAllObjects];
    self.failedCount = 0;
}

@end
