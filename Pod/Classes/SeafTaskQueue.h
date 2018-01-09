//
//  SeafTaskQueue.h
//  Pods
//
//  Created by three on 2017/10/2.
//
//

#import <Foundation/Foundation.h>

#define DEFAULT_CONCURRENCY 3
#define DEFAULT_RETRYCOUNT 3
#define DEFAULT_ATTEMPT_INTERVAL 60 // 1 min
#define DEFAULT_COMPLELE_INTERVAL 3*60 // 3 min

@protocol SeafTask;

typedef void (^TaskCompleteBlock)(id<SeafTask> _Nonnull task, BOOL result);
typedef void (^TaskProgressBlock)(id<SeafTask> _Nonnull task, float progress);

@protocol SeafTask<NSObject>

@property NSTimeInterval lastFinishTimestamp;
@property NSInteger retryCount;
@property BOOL retryable;

- (NSString * _Nonnull)accountIdentifier;
- (BOOL)runable; // task good to go
- (NSString * _Nonnull)name;
- (void)run:(TaskCompleteBlock _Nullable)completeBlock;
- (void)cancel;
- (void)setTaskProgressBlock:(TaskProgressBlock _Nullable)taskProgressBlock;

@optional
- (void)cleanup;

@end


@interface SeafTaskQueue : NSObject

@property (nonatomic, assign) NSInteger concurrency;
@property (nonatomic, assign) double attemptInterval;
@property (nonatomic, copy) TaskCompleteBlock _Nullable taskCompleteBlock;
@property (nonatomic, copy) TaskProgressBlock _Nullable taskProgressBlock;
@property (nonatomic, strong) NSMutableArray * _Nullable completedTasks;

- (NSInteger)taskNumber;
- (NSArray * _Nonnull)allTasks;
- (void)addTask:(id<SeafTask> _Nonnull)task; // Add task if not exist
- (void)removeTask:(id<SeafTask> _Nonnull)task;// Remove task, cancel if running
- (void)clearTasks; //clear all tasks
- (void)tick; //pick available tasks from tasks queue to activate untill it reaches queue concurrency.

@end
