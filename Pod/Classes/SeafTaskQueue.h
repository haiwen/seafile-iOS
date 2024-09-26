//
//  SeafTaskQueue.h
//  Pods
//
//  Created by three on 2017/10/2.
//
//

#import <Foundation/Foundation.h>

/**
 * Default number of concurrent tasks that can run.
 */
#define DEFAULT_CONCURRENCY 3

/**
 * Default number of times a task should retry on failure.
 */
#define DEFAULT_RETRYCOUNT 3

/**
 * Default number of times a FileThumb should retry on failure.
 */
#define Default_FileThumb_RetryCount 3

/**
 * Default interval in seconds between retries of a task.
 */
#define DEFAULT_ATTEMPT_INTERVAL 60 // 1 min

/**
 * Default interval in seconds before a completed task is considered fully completed.
 */
#define DEFAULT_COMPLELE_INTERVAL 3*60 // 3 min

@protocol SeafTask;

/**
 * Completion block for a task.
 * @param task The task that has completed.
 * @param result The result of the task execution (YES if successful, NO otherwise).
 */
typedef void (^TaskCompleteBlock)(id<SeafTask> _Nonnull task, BOOL result);

/**
 * Progress block for a task.
 * @param task The task reporting progress.
 * @param progress The progress of the task (from 0.0 to 1.0).
 */
typedef void (^TaskProgressBlock)(id<SeafTask> _Nonnull task, float progress);

/**
 * Protocol defining the basic requirements and properties of a task.
 */
@protocol SeafTask<NSObject>

/// The timestamp when the task last finished.
@property NSTimeInterval lastFinishTimestamp;
/// The number of times the task has been retried.
@property NSInteger retryCount;
/// Indicates whether the task can be retried upon failure.
@property BOOL retryable;

/**
 * Returns the unique account identifier associated with the task.
 * @return A string that uniquely identifies the account.
 */
- (NSString * _Nonnull)accountIdentifier;

- (BOOL)runable; // task good to go

/**
 * Returns the name of the task.
 * @return A string representing the task's name.
 */
- (NSString * _Nonnull)name;

/**
 * Executes the task.
 * @param completeBlock The completion block to be called when the task execution is finished.
 */
- (void)run:(TaskCompleteBlock _Nullable)completeBlock;

/**
 * Cancels the execution of the task.
 */
- (void)cancel;

/**
 * Sets a progress block for the task, which is called as the task makes progress.
 * @param taskProgressBlock The block to be called with progress updates.
 */
- (void)setTaskProgressBlock:(TaskProgressBlock _Nullable)taskProgressBlock;

@optional
/**
 * Performs any necessary cleanup after the task has completed or failed.
 */
- (void)cleanup;

@end

/**
 * Manages a queue of tasks, handling their execution, retries, and cancellations.
 */
@interface SeafTaskQueue : NSObject

/// The maximum number of concurrent tasks allowed.
@property (nonatomic, assign) NSInteger concurrency;
/// The interval between attempts to run a task.
@property (nonatomic, assign) double attemptInterval;
/// The completion block called when any task in the queue completes.
@property (nonatomic, copy) TaskCompleteBlock _Nullable taskCompleteBlock;
/// The progress block called as any task in the queue makes progress.
@property (nonatomic, copy) TaskProgressBlock _Nullable taskProgressBlock;
/// A collection of tasks that have been completed.
@property (nonatomic, strong) NSMutableArray * _Nullable completedTasks;

/**
 * Returns the number of tasks currently managed by the queue.
 * @return The number of tasks.
 */
- (NSInteger)taskNumber;

- (NSInteger)onGoingTaskNumber;

/**
 * Returns all tasks currently in the queue.
 * @return An array of all tasks.
 */
- (NSArray * _Nonnull)allTasks;

/**
 * Adds a task to the queue if it does not already exist.
 * @param task The task to add.
 * @return YES if the task was added successfully, NO if the task already exists.
 */
- (BOOL)addTask:(id<SeafTask> _Nonnull)task; // Add task if not exist

- (void)removeTask:(id<SeafTask> _Nonnull)task;// Remove task, cancel if running
- (void)clearTasks; //clear all tasks
- (void)tick; //pick available tasks from tasks queue to activate untill it reaches queue concurrency.

@end
