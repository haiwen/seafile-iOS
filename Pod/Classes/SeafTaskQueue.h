//
//  SeafTaskQueue.h
//  Pods
//
//  Created by three on 2017/10/2.
//
//

#import <Foundation/Foundation.h>

#define DEFAULT_CONCURRENCY 3
#define DEFAULT_ATTEMPT_INTERVAL 60 // 1 min

@protocol SeafTask;

typedef void (^TaskCompleteBlock)(id<SeafTask> _Nonnull task, BOOL result);

@protocol SeafTask<NSObject>

@property NSTimeInterval lastFailureTimestamp;
@property BOOL retryable;

- (BOOL)runable; // task good to go
- (NSString * _Nonnull)name;
- (void)run:(TaskCompleteBlock _Nullable)block;
- (void)cancel;

@end


@interface SeafTaskQueue : NSObject

@property (nonatomic, assign) NSInteger concurrency;
@property (nonatomic, assign) double attemptInterval;

- (NSInteger)taskNumber;
- (NSArray * _Nonnull)allTasks;
- (void)addTask:(id<SeafTask> _Nonnull)task; // Add task if not exist
- (void)removeTask:(id<SeafTask> _Nonnull)task;// Remove task, cancel if running
- (void)clear; //clear all tasks
- (void)tick; //pick available tasks from tasks queue to activate untill it reaches queue concurrency.

@end
