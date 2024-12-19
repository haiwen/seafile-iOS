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
#define QUEUE_MAX_COUNT 50


@interface SeafAccountTaskQueue ()

@property (nonatomic, strong) dispatch_source_t cleanupTimerSource;  // GCD timer object
@property (nonatomic, assign) BOOL isCleanupTimerRunning;           // Timer status flag

@end

@implementation SeafAccountTaskQueue

- (instancetype)init {
    self = [super init];
    if (self) {
        self.downloadQueue = [[NSOperationQueue alloc] init];
        self.downloadQueue.name = @"com.seafile.fileDownloadQueue";
        self.downloadQueue.maxConcurrentOperationCount = DOWNLOAD_MAX_COUNT;
        
        self.thumbQueue = [[NSOperationQueue alloc] init];
        self.thumbQueue.name = @"com.seafile.thumbDownloadQueue";
        self.thumbQueue.maxConcurrentOperationCount = THUMB_MAX_COUNT;
        self.thumbQueue.qualityOfService = NSQualityOfServiceUserInteractive;
        
        self.uploadQueue = [[NSOperationQueue alloc] init];
        self.uploadQueue.name = @"com.seafile.fileUploadQueue";
        self.uploadQueue.maxConcurrentOperationCount = UPLOAD_MAX_COUNT;
        
        self.ongoingTasks = [NSMutableArray array];
        self.waitingTasks = [NSMutableArray array];
        self.cancelledTasks = [NSMutableArray array];
        self.completedSuccessfulTasks = [NSMutableArray array];
        self.completedFailedTasks = [NSMutableArray array];
        
        // Initialize arrays for download task statuses
        self.ongoingDownloadTasks = [NSMutableArray array];
        self.waitingDownloadTasks = [NSMutableArray array];
        self.cancelledDownloadTasks = [NSMutableArray array];
        self.completedSuccessfulDownloadTasks = [NSMutableArray array];
        self.completedFailedDownloadTasks = [NSMutableArray array];
        
        // Initialize arrays for paused task states
        self.pausedUploadTasks = [NSMutableArray array];
        self.pausedDownloadTasks = [NSMutableArray array];
        self.pausedThumbTasks = [NSMutableArray array];
        
        self.pendingUploadTasks = [NSMutableArray array];
        self.maxBatchSize = QUEUE_MAX_COUNT; // Maximum of 50 tasks per batch
        
        [self startCleanupTimer];
    }
    return self;
}


#pragma mark - Add Download Task

- (void)addFileDownloadTask:(SeafFile * _Nonnull)dfile {
    dfile.state = SEAF_DENTRY_INIT;
    // Check if the task already exists
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

    // Initial state is waiting to execute, add to waitingDownloadTasks
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
    [operation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:NULL];
    [operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:NULL];
    [operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:NULL];
    operation.observersAdded = YES; // Set to YES after adding observers
    operation.queuePriority = priority;
    // Initial state is waiting to execute, add to waitingTasks
    @synchronized (self.waitingTasks) {
        [self.waitingTasks addObject:ufile];
    }
    
    [self.uploadQueue addOperation:operation];
    return YES;
}

- (void)addUploadTasksInBatch:(NSArray<SeafUploadFile *> *)tasks {
    @synchronized (self.pendingUploadTasks) {
        [self.pendingUploadTasks addObjectsFromArray:tasks];
    }
    // If there are no ongoing or waiting tasks in uploadQueue, start the next batch
    if ([self getOngoingTasks].count == 0 && [self getWaitingTasks].count == 0) {
        [self startNextBatchOfUploadTasks];
    }
}

- (void)startNextBatchOfUploadTasks {
    @synchronized (self.pendingUploadTasks) {
        if (self.pendingUploadTasks.count == 0) {
            Debug(@"No more pending upload tasks.");
            return;
        }

        NSRange range = NSMakeRange(0, MIN(self.maxBatchSize, self.pendingUploadTasks.count));
        NSArray<SeafUploadFile *> *batch = [self.pendingUploadTasks subarrayWithRange:range];

        // Add this batch of tasks to the uploadQueue
        for (SeafUploadFile *ufile in batch) {
            [self addUploadTask:ufile];
        }

        // Remove the batch of tasks that have been added to the queue from pendingUploadTasks
        [self.pendingUploadTasks removeObjectsInRange:range];
    }
}

- (void)tryLoadNextBatchIfNeeded {
    NSInteger ongoingCount = [self getOngoingTasks].count;
    NSInteger waitingCount = [self getWaitingTasks].count;
    
    // If the number of ongoing + waiting tasks is less than 5, load the next batch
    if ((ongoingCount + waitingCount) < 5) {
        if (!self.uploadQueue.isSuspended) {
            [self startNextBatchOfUploadTasks];
        }
    }
}

- (void)addThumbTask:(SeafThumb * _Nonnull)thumb {
    // Check if the task already exists
    for (SeafThumbOperation *op in self.thumbQueue.operations) {
        if ([op.file.oid isEqual:thumb.file.oid]) {
            return;
        }
    }
    
    SeafThumbOperation *operation = [[SeafThumbOperation alloc] initWithSeafFile:thumb.file];
    [self.thumbQueue addOperation:operation];
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
                // Task started executing, move it from waitingTasks to ongoingTasks
                [self moveTask:ufile fromArray:self.waitingTasks toArray:self.ongoingTasks];
            }
        } else if ([keyPath isEqualToString:@"isFinished"]) {
            BOOL isFinished = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
            if (isFinished) {
                // Task finished, remove it from ongoingTasks
                [self removeTask:ufile fromArray:self.ongoingTasks];
                
                // Add to success or failure array based on the upload result
                if (ufile.uploaded) {
                    [self addTask:ufile toArray:self.completedSuccessfulTasks];
                } else {
                    [self addTask:ufile toArray:self.completedFailedTasks];
                }

                // Remove observers
                [self safelyRemoveObserversFromOperation:operation];
                
            }
        } else if ([keyPath isEqualToString:@"isCancelled"]) {
            BOOL isCancelled = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
            if (isCancelled) {
                // Task was canceled, remove it from waitingTasks or ongoingTasks and add to cancelledTasks
                [self removeTask:ufile fromArray:self.waitingTasks];
                [self removeTask:ufile fromArray:self.ongoingTasks];
                [self addTask:ufile toArray:self.cancelledTasks];

                // Remove observers
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
                    // Task started executing, move it from waitingDownloadTasks to ongoingDownloadTasks
                    [self moveDownloadTask:dfile fromArray:self.waitingDownloadTasks toArray:self.ongoingDownloadTasks];
                }
            } else if ([keyPath isEqualToString:@"isFinished"]) {
                BOOL isFinished = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
                if (isFinished) {
                    // Task finished, remove it from ongoingDownloadTasks
                    [self removeDownloadTask:dfile fromArray:self.ongoingDownloadTasks];
                    
                    // Add to success or failure array based on the download result
                    if (dfile.downloaded) {
                        [self addDownloadTask:dfile toArray:self.completedSuccessfulDownloadTasks];
                    } else {
                        [self addDownloadTask:dfile toArray:self.completedFailedDownloadTasks];
                    }

                    // Remove observers
                    [self safelyRemoveObserversFromOperation:operation];
                }
            } else if ([keyPath isEqualToString:@"isCancelled"]) {
                BOOL isCancelled = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
                if (isCancelled) {
                    // Task was canceled, remove it from waitingDownloadTasks or ongoingDownloadTasks and add to cancelledDownloadTasks
                    [self removeDownloadTask:dfile fromArray:self.waitingDownloadTasks];
                    [self removeDownloadTask:dfile fromArray:self.ongoingDownloadTasks];
                    [self addDownloadTask:dfile toArray:self.cancelledDownloadTasks];
                
                    // Remove observers
                    [self safelyRemoveObserversFromOperation:operation];
                }
            }
            [self postDownloadTaskStatusChangedNotification];
        }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - Post Notifications

- (void)postUploadTaskStatusChangedNotification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SeafUploadTaskStatusChanged" object:self];
    });
    [self tryLoadNextBatchIfNeeded];
}

- (void)postDownloadTaskStatusChangedNotification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SeafDownloadTaskStatusChanged" object:self];
    });
}

#pragma mark - Upload Task Helper Methods

// Remove a task from an array
- (void)removeTask:(SeafUploadFile *)task fromArray:(NSMutableArray<SeafUploadFile *> *)array {
    @synchronized (array) {
        [array removeObject:task];
    }
}

// Move a task from one array to another
- (void)moveTask:(SeafUploadFile *)task fromArray:(NSMutableArray<SeafUploadFile *> *)fromArray toArray:(NSMutableArray<SeafUploadFile *> *)toArray {
    [self removeTask:task fromArray:fromArray];
    [self addTask:task toArray:toArray];
}

// Add a task to an array
- (void)addTask:(SeafUploadFile *)task toArray:(NSMutableArray<SeafUploadFile *> *)array {
    @synchronized (array) {
        if (![array containsObject:task]) {
            [array addObject:task];
        }
    }
}

#pragma mark - Download Task Helper Methods

// Remove a download task from an array
- (void)removeDownloadTask:(SeafFile *)task fromArray:(NSMutableArray<SeafFile *> *)array {
    @synchronized (array) {
        [array removeObject:task];
    }
}

// Move a download task from one array to another
- (void)moveDownloadTask:(SeafFile *)task fromArray:(NSMutableArray<SeafFile *> *)fromArray toArray:(NSMutableArray<SeafFile *> *)toArray {
    [self removeDownloadTask:task fromArray:fromArray];
    [self addDownloadTask:task toArray:toArray];
}

// Add a download task to an array
- (void)addDownloadTask:(SeafFile *)task toArray:(NSMutableArray<SeafFile *> *)array {
    @synchronized (array) {
        if (![array containsObject:task]) {
            [array addObject:task];
        }
    }
}

#pragma mark - Retrieve Upload Task Status Arrays
- (NSArray<SeafUploadFile *> *)getNeedUploadTasks {
    NSArray *ongoingTasks = [self getOngoingTasks];
    NSArray *waitingTasks = [self getWaitingTasks];
    
    // Replace nil with an empty array
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

#pragma mark - Retrieve Download Task Status Arrays
- (NSArray<SeafFile *> *_Nullable)getNeedDownloadTasks {
    NSArray *ongoingTasks = [self getOngoingDownloadTasks];
    NSArray *waitingTasks = [self getWaitingDownloadTasks];
    
    // Replace nil with an empty array
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

#pragma mark - Cancel Tasks

// Cancel all tasks
- (void)cancelAllTasks {
    [self cancelAllUploadTasks];
    [self cancelAllDownloadTasks];
    [self.thumbQueue cancelAllOperations];
}

// Cancel all upload tasks
- (void)cancelAllUploadTasks {
    [self.uploadQueue setSuspended:YES];

    // Cancel all operations in the upload queue
    for (SeafUploadOperation *op in self.uploadQueue.operations) {
        [self safelyRemoveObserversFromOperation:op];
        [op cancel];
    }
    // Clear ongoing and waiting upload task arrays, and move them to cancelledTasks
    @synchronized (self.ongoingTasks) {
        [self.cancelledTasks addObjectsFromArray:self.ongoingTasks];
        [self.ongoingTasks removeAllObjects];
    }
    @synchronized (self.waitingTasks) {
        [self.cancelledTasks addObjectsFromArray:self.waitingTasks];
        [self.waitingTasks removeAllObjects];
    }
    
    [self.pendingUploadTasks removeAllObjects];
    
    [self.uploadQueue setSuspended:NO];

    [self postUploadTaskStatusChangedNotification];
}

// Cancel all download tasks
- (void)cancelAllDownloadTasks {
    [self.downloadQueue setSuspended:YES];

    // Cancel all operations in the download queue
    for (SeafDownloadOperation *op in self.downloadQueue.operations) {
        [self safelyRemoveObserversFromOperation:op];
        [op cancel];
    }
    // Clear ongoing and waiting download task arrays, and move them to cancelledDownloadTasks
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

// Photo backup : Cancel tasks based on the local photo identifier array
- (void)cancelUploadTasksForLocalIdentifier:(NSArray<NSString *> *)localAssetIdentifiers {
    // Pause the upload queue to ensure no tasks execute during the operation
    [self.uploadQueue setSuspended:YES];

    // Convert the localAssetIdentifiers array to a set for fast lookup
    NSSet *identifierSet = [NSSet setWithArray:localAssetIdentifiers];

    // Prepare an array to collect tasks to be canceled
    NSMutableArray<SeafUploadFile *> *tasksToCancel = [NSMutableArray array];
    
    // Iterate through all operations in the upload queue
    for (SeafUploadOperation *op in self.uploadQueue.operations) {
        SeafUploadFile *ufile = op.uploadFile;
        // Check if the task's assetIdentifier exists in the specified set
        if ([identifierSet containsObject:ufile.assetIdentifier]) {
            // Remove observers and cancel the task
            [self safelyRemoveObserversFromOperation:op];
            [op cancel];
            
            [tasksToCancel addObject:ufile];
        }
    }

    // Remove matching tasks from ongoingTasks and move to cancelledTasks
    @synchronized (self.ongoingTasks) {
        for (SeafUploadFile *ufile in tasksToCancel) {
            if ([self.ongoingTasks containsObject:ufile]) {
                [self.ongoingTasks removeObject:ufile];
                [self.cancelledTasks addObject:ufile];
            }
        }
    }

    // Remove matching tasks from waitingTasks and move to cancelledTasks
    @synchronized (self.waitingTasks) {
        for (SeafUploadFile *ufile in tasksToCancel) {
            if ([self.waitingTasks containsObject:ufile]) {
                [self.waitingTasks removeObject:ufile];
                [self.cancelledTasks addObject:ufile];
            }
        }
    }
    
    // Remove tasks not yet loaded from pendingUploadTasks
    @synchronized (self.pendingUploadTasks) {
        for (NSInteger i = self.pendingUploadTasks.count - 1; i >= 0; i--) {
            SeafUploadFile *ufile = self.pendingUploadTasks[i];
            if ([identifierSet containsObject:ufile.assetIdentifier]) {
                [self.pendingUploadTasks removeObjectAtIndex:i]; // Remove the corresponding element
            }
        }
    }
    // Resume the upload queue
    [self.uploadQueue setSuspended:NO];

    // Notify that upload task status has been updated
    [self postUploadTaskStatusChangedNotification];
}

- (void)removeFileDownloadTask:(SeafFile * _Nonnull)dfile {
    for (SeafDownloadOperation *op in self.downloadQueue.operations) {
        if ([op.file isEqual:dfile]) {
            [op cancel];
            break;
        }
    }
}

- (void)removeUploadTask:(SeafUploadFile * _Nonnull)ufile {
    for (SeafUploadOperation *op in self.uploadQueue.operations) {
        if ([op.uploadFile isEqual:ufile]) {
            [op cancel];
            break;
        }
    }
}

- (void)removeThumbTask:(SeafThumb * _Nonnull)thumb {
    for (SeafThumbOperation *op in self.thumbQueue.operations) {
        if ([op.file.oid isEqual:thumb.file.oid]) {
            [op cancel];
            break;
        }
    }
}

- (void)cancelAutoSyncTasks {
    [self.uploadQueue setSuspended:YES];
    
    [self cancelAutoSyncTasksWithoutSuspend];
    
    [self.uploadQueue setSuspended:NO];
}

- (void)cancelAutoSyncTasksWithoutSuspend {
    NSMutableArray<SeafUploadFile *> *tasksToCancel = [NSMutableArray array];
    
    // Collect tasks that need to be canceled
    NSArray *taskArrays = @[self.ongoingTasks, self.waitingTasks];
    for (NSMutableArray<SeafUploadFile *> *taskArray in taskArrays) {
        @synchronized (taskArray) {
            for (SeafUploadFile *ufile in taskArray) {
                if (ufile.uploadFileAutoSync && ufile.udir->connection == self.conn) {
                    [tasksToCancel addObject:ufile];
                }
            }
        }
    }
    
    // Create a mapping table using ufile.lpath as the key
    NSMutableDictionary<NSString *, SeafUploadOperation *> *operationMap = [NSMutableDictionary dictionary];
    for (SeafUploadOperation *op in self.uploadQueue.operations) {
        if (op.uploadFile && op.uploadFile.lpath) {
            operationMap[op.uploadFile.lpath] = op;
        }
    }
    
    // Cancel tasks and update task arrays
    for (SeafUploadFile *ufile in tasksToCancel) {
        SeafUploadOperation *op = operationMap[ufile.lpath];
        if (op) {
            [self safelyRemoveObserversFromOperation:op];
            [op cancel];
        }
        [self removeTask:ufile fromArray:self.ongoingTasks];
        [self removeTask:ufile fromArray:self.waitingTasks];
    }
    
    @synchronized(self.pendingUploadTasks) {
        for (NSInteger i = self.pendingUploadTasks.count - 1; i >= 0; i--) {
            SeafUploadFile *ufile = self.pendingUploadTasks[i];
            if (ufile.uploadFileAutoSync && ufile.udir->connection == self.conn) {
                [self.pendingUploadTasks removeObjectAtIndex:i]; // Remove elements that meet the condition
            }
        }
    }
    
    [self postUploadTaskStatusChangedNotification];
}

- (void)cancelAutoSyncVideoTasks {
    [self.uploadQueue setSuspended:YES];

    // Iterate through ongoingTasks
    @synchronized (self.ongoingTasks) {
        NSArray *ongoingTasksCopy = [self.ongoingTasks copy];
        for (SeafUploadFile *ufile in ongoingTasksCopy) {
            if (ufile.uploadFileAutoSync && ufile.udir->connection == self.conn && !ufile.isImageFile) {
                // Find the corresponding SeafUploadOperation
                for (SeafUploadOperation *op in self.uploadQueue.operations) {
                    if (op.uploadFile == ufile) {
                        [self safelyRemoveObserversFromOperation:op];
                        [op cancel];
                        break;
                    }
                }
                // Remove from ongoingTasks and add to cancelledTasks
                [self removeTask:ufile fromArray:self.ongoingTasks];
            }
        }
    }

    // Iterate through waitingTasks
    @synchronized (self.waitingTasks) {
        NSArray *waitingTasksCopy = [self.waitingTasks copy];
        for (SeafUploadFile *ufile in waitingTasksCopy) {
            if (ufile.uploadFileAutoSync && ufile.udir->connection == self.conn && !ufile.isImageFile) {
                // Find the corresponding SeafUploadOperation
                for (SeafUploadOperation *op in self.uploadQueue.operations) {
                    if (op.uploadFile == ufile) {
                        [self safelyRemoveObserversFromOperation:op];
                        [op cancel];
                        break;
                    }
                }
                // Remove from waitingTasks and add to cancelledTasks
                [self removeTask:ufile fromArray:self.waitingTasks];
            }
        }
    }
    
    @synchronized(self.pendingUploadTasks) {
        for (NSInteger i = self.pendingUploadTasks.count - 1; i >= 0; i--) {
            SeafUploadFile *ufile = self.pendingUploadTasks[i];
            if (ufile.uploadFileAutoSync && ufile.udir->connection == self.conn) {
                [self.pendingUploadTasks removeObjectAtIndex:i]; // Remove elements that meet the condition
            }
        }
    }
    
    [self.uploadQueue setSuspended:NO];

    // Send task status update notification
    [self postUploadTaskStatusChangedNotification];
}

#pragma mark - Pause Tasks
/// Pauses all queues and cancels any ongoing tasks, storing them for resumption.
- (void)pauseAllTasks {
    // Pause the queues
    [self.uploadQueue setSuspended:YES];
    [self.downloadQueue setSuspended:YES];
    [self.thumbQueue setSuspended:YES];
    
    [self cancelAutoSyncTasksWithoutSuspend];
    
    [self pauseAllUploadingTasks];
    [self pauseAllDownloadingTasks];
    [self pauseAllThumbOngoingTasks];
    
    [self pauseCleanupTimer];
}

/// Resumes all queues and restarts any tasks that were canceled during the pause.
- (void)resumeAllTasks {
    [self resumePausedUploadTasks];
    [self resumePausedDownloadTasks];
    [self resumePausedThumbTasks];
    
    [self.uploadQueue setSuspended:NO];
    [self.downloadQueue setSuspended:NO];
    [self.thumbQueue setSuspended:NO];
    
    NSNotification *note = [NSNotification notificationWithName:@"photosDidChange" object:nil userInfo:@{@"force" : @(YES)}];
    [self.conn photosDidChange:note];
    
    [self startCleanupTimer];
}

#pragma mark - Pause Helpers
/// Pauses all upload tasks.
- (void)pauseAllUploadingTasks {
    [self.uploadQueue setSuspended:YES];
    
    for (SeafUploadOperation *op in self.uploadQueue.operations) {
        if (op.isExecuting) {
            [self safelyRemoveObserversFromOperation:op];
            [op cancel];
            SeafUploadFile *ufile = op.uploadFile;
            @synchronized (self.pausedUploadTasks) {
                [self.pausedUploadTasks addObject:ufile];
            }
        }
    }
    
    // Clear ongoing and waiting tasks
    @synchronized (self.ongoingTasks) {
        [self.ongoingTasks removeAllObjects];
    }
    
    [self postUploadTaskStatusChangedNotification];
}

/// Pauses all download tasks.
- (void)pauseAllDownloadingTasks {
    [self.downloadQueue setSuspended:YES];
    
    for (SeafDownloadOperation *op in self.downloadQueue.operations) {
        if (op.isExecuting) {
            [self safelyRemoveObserversFromOperation:op];
            [op cancel];
            SeafFile *dfile = op.file;
            @synchronized (self.pausedDownloadTasks) {
                [self.pausedDownloadTasks addObject:dfile];
            }
        }
    }
    
    // Clear ongoing and waiting download tasks
    @synchronized (self.ongoingDownloadTasks) {
        [self.ongoingDownloadTasks removeAllObjects];
    }
    
    [self postDownloadTaskStatusChangedNotification];
}

/// Pauses all thumb tasks.
- (void)pauseAllThumbOngoingTasks {
    [self.thumbQueue setSuspended:YES];
    
    for (SeafThumbOperation *op in self.thumbQueue.operations) {
        if (op.isExecuting) {
            [op cancel];
            SeafThumb *thumb = [[SeafThumb alloc] initWithSeafFile:op.file];
            @synchronized (self.pausedThumbTasks) {
                [self.pausedThumbTasks addObject:thumb];
            }
        }
    }
}

#pragma mark - Resume Helpers

/// Resumes all paused upload tasks.
- (void)resumePausedUploadTasks {
    @synchronized (self.pausedUploadTasks) {
        for (SeafUploadFile *ufile in self.pausedUploadTasks) {
            [self addUploadTask:ufile];
        }
        [self.pausedUploadTasks removeAllObjects];
    }
}

/// Resumes all paused download tasks.
- (void)resumePausedDownloadTasks {
    @synchronized (self.pausedDownloadTasks) {
        for (SeafFile *dfile in self.pausedDownloadTasks) {
            [self addFileDownloadTask:dfile];
        }
        [self.pausedDownloadTasks removeAllObjects];
    }
}

/// Resumes all paused thumb tasks.
- (void)resumePausedThumbTasks {
    @synchronized (self.pausedThumbTasks) {
        for (SeafThumb *thumb in self.pausedThumbTasks) {
            [self addThumbTask:thumb];
        }
        [self.pausedThumbTasks removeAllObjects];
    }
}

#pragma mark - remove KVO Observer

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

#pragma mark - Remove Completed Tasks After 3 Minutes
// Call removeOldCompletedTasks on a background thread
- (void)runRemoveTasksInBackground {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [self removeOldCompletedTasks];
        [self checkBackupNeedToUpload];
    });
}

- (void)checkBackupNeedToUpload {
    if (self.conn.photoBackup.photosArray.count > 0 && self.ongoingTasks.count == 0 && self.waitingTasks.count == 0) {
        NSNotification *note = [NSNotification notificationWithName:@"photosDidChange" object:nil userInfo:@{@"force" : @(YES)}];
        [self.conn photosDidChange:note];
    }
}

- (void)removeOldCompletedTasks {
    NSMutableArray *tempSuccessfulDownloadTasks = [NSMutableArray array];
    NSMutableArray *tempSuccessfulTasks = [NSMutableArray array];

    NSTimeInterval currentTimestamp = [[NSDate date] timeIntervalSince1970];

    @synchronized (self.completedSuccessfulDownloadTasks) {
        NSArray *copyArray = [NSArray arrayWithArray:self.completedSuccessfulDownloadTasks];
        for (id<SeafTask> task in copyArray) {
            if (currentTimestamp - task.lastFinishTimestamp > DEFAULT_COMPLELE_INTERVAL) {
                [tempSuccessfulDownloadTasks addObject:task];
                if ([task respondsToSelector:@selector(cleanup)]) {
                    [task cleanup];
                }
            }
        }
        
        if (tempSuccessfulDownloadTasks.count > 0) {
            [self.completedSuccessfulDownloadTasks removeObjectsInArray:tempSuccessfulDownloadTasks];
            [self postDownloadTaskStatusChangedNotification];
        }
    }

    @synchronized (self.completedSuccessfulTasks) {
        NSArray *copyArray = [NSArray arrayWithArray:self.completedSuccessfulTasks];
        for (id<SeafTask> task in copyArray) {
            if (currentTimestamp - task.lastFinishTimestamp > DEFAULT_COMPLELE_INTERVAL) {
                [tempSuccessfulTasks addObject:task];
                if ([task respondsToSelector:@selector(cleanup)]) {
                    [task cleanup];
                }
            }
        }
        if (tempSuccessfulTasks.count > 0) {
            [self.completedSuccessfulTasks removeObjectsInArray:tempSuccessfulTasks];
            [self postUploadTaskStatusChangedNotification];
        }
    }
}

#pragma mark - GCD Timer Control

// Start the cleanup timer (GCD-based)
- (void)startCleanupTimer {
    if (self.isCleanupTimerRunning) {
        Debug(@"GCD Cleanup timer is already running.");
        return;
    }

    // Create a GCD timer
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    self.cleanupTimerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    
    // Set the timer interval: triggers every 30 seconds
    dispatch_source_set_timer(self.cleanupTimerSource,
                              dispatch_time(DISPATCH_TIME_NOW, 0),
                              30 * NSEC_PER_SEC,  // Trigger every 30 seconds
                              1 * NSEC_PER_SEC);  // Allowable error margin of 1 second

    // Event handler for the timer
    dispatch_source_set_event_handler(self.cleanupTimerSource, ^{
        [self runRemoveTasksInBackground];
    });

    // Start the timer
    dispatch_resume(self.cleanupTimerSource);
    self.isCleanupTimerRunning = YES;
    Debug(@"GCD Cleanup timer started.");
}

// Pause the cleanup timer (GCD-based)
- (void)pauseCleanupTimer {
    if (!self.isCleanupTimerRunning || !self.cleanupTimerSource) {
        Debug(@"GCD Cleanup timer is not running.");
        return;
    }
    
    dispatch_source_cancel(self.cleanupTimerSource);
    self.cleanupTimerSource = nil;
    self.isCleanupTimerRunning = NO;
    Debug(@"GCD Cleanup timer paused.");
}

@end
