//
//  SeafBackgroundTaskManager.h
//  Pods
//
//  Created by Wei W on 4/9/17.
//
//

#import <Foundation/Foundation.h>

#import "SeafPreView.h"
#import "SeafConnection.h"
#import "SeafUploadFile.h"
#import "SeafFile.h"
#import "SeafThumb.h"
#import "SeafAvatar.h"
#import "SeafTaskQueue.h"

/**
 * @class SeafDataTaskManager
 * @discussion The SeafDataTaskManager class is designed to handle background tasks related to file synchronization, such as uploading and downloading files.
 */
@class SeafAccountTaskQueue;

typedef void(^SyncBlock)(id<SeafTask> _Nullable file);
typedef void(^DownLoadFinshBlock)(id<SeafTask>  _Nonnull task);
// Manager for background download/upload tasks, retry if failed.
@interface SeafDataTaskManager : NSObject

@property (nonatomic, copy) SyncBlock _Nullable trySyncBlock;
@property (nonatomic, copy) DownLoadFinshBlock _Nullable finishBlock;


+ (SeafDataTaskManager * _Nonnull)sharedObject;

/**
 * Adds a file download task to the task manager.
 * @param dfile The file to be downloaded.
 */
- (void)addFileDownloadTask:(SeafFile * _Nonnull)dfile;

/**
 * Adds an upload task to the task manager.
 * @param ufile The file to be uploaded.
 * @return A Boolean value indicating whether the file was successfully added to the upload queue.
 */
- (BOOL)addUploadTask:(SeafUploadFile * _Nonnull)ufile;

/**
 * Adds an avatar download task to the task manager.
 * @param avatar The avatar to be downloaded.
 */
- (void)addAvatarTask:(SeafAvatar * _Nonnull)avatar;

/**
 * Adds a thumbnail download task to the task manager.
 * @param thumb The thumbnail to be downloaded.
 */
- (void)addThumbTask:(SeafThumb * _Nonnull)thumb;

/**
 * Removes a specific upload task associated with a given account.
 * @param ufile The upload file task to be removed.
 * @param conn The connection related to the account from which the upload task will be removed.
 */
- (void)removeUploadTask:(SeafUploadFile * _Nonnull)ufile forAccount:(SeafConnection * _Nonnull)conn;

/**
 * Starts any unfinished tasks from the last session associated with a specific connection.
 * @param conn The connection whose tasks are to be started.
 */
- (void)startLastTimeUnfinshTaskWithConnection:(SeafConnection *_Nullable)conn;

/**
 * Removes all tasks associated with a specific account queue.
 * @param conn The connection whose task queue is to be removed.
 */
- (void)removeAccountQueue:(SeafConnection *_Nullable)conn;

/**
 * Retrieves all upload tasks that are within a specific directory.
 * @param dir The directory within which the upload tasks are to be retrieved.
 * @return An array containing all the upload tasks within the specified directory.
 */
- (NSArray * _Nullable)getUploadTasksInDir:(SeafDir * _Nullable)dir;

/**
 * Cancels all auto-sync upload tasks for a specific connection.
 * @param conn The connection whose auto-sync tasks are to be cancelled.
 */
- (void)cancelAutoSyncTasks:(SeafConnection * _Nonnull)conn;

/**
 * Cancels all auto-sync video upload tasks for a specific connection.
 * @param conn The connection whose auto-sync video tasks are to be cancelled.
 */
- (void)cancelAutoSyncVideoTasks:(SeafConnection * _Nonnull)conn;

/**
 * Cancels all download tasks for a specific connection.
 * @param conn The connection whose download tasks are to be cancelled.
 */
- (void)cancelAllDownloadTasks:(SeafConnection * _Nonnull)conn;

/**
 * Cancels all upload tasks for a specific connection.
 * @param conn The connection whose upload tasks are to be cancelled.
 */
- (void)cancelAllUploadTasks:(SeafConnection * _Nonnull)conn;

/**
 * Retrieves an account task queue associated with a specific connection.
 * @param connection The connection associated with the account.
 * @return An instance of SeafAccountTaskQueue associated with the given connection.
 */
- (SeafAccountTaskQueue * _Nonnull)accountQueueForConnection:(SeafConnection * _Nonnull)connection;

@end

@interface SeafAccountTaskQueue : NSObject

@property (nonatomic, strong) SeafTaskQueue * _Nonnull fileQueue;
@property (nonatomic, strong) SeafTaskQueue * _Nonnull thumbQueue;
@property (nonatomic, strong) SeafTaskQueue * _Nonnull avatarQueue;
@property (nonatomic, strong) SeafTaskQueue * _Nonnull uploadQueue;

/**
 * Starts any unfinished tasks from the last session associated with a specific connection.
 * @param conn The connection whose tasks are to be started.
 */
- (void)addFileDownloadTask:(SeafFile * _Nonnull)dfile;

/**
 * Adds an upload task to the queue.
 * @param ufile The upload task to be added.
 * @return A Boolean value indicating whether the task was successfully added.
 */
- (BOOL)addUploadTask:(SeafUploadFile * _Nonnull)ufile;

/**
 * Adds an avatar download task to the task manager.
 * @param avatar The avatar to be downloaded.
 */
- (void)addAvatarTask:(SeafAvatar * _Nonnull)avatar;

/**
 * Adds a thumbnail download task to the task manager.
 * @param thumb The thumbnail to be downloaded.
 */
- (void)addThumbTask:(SeafThumb * _Nonnull)thumb;

/**
 * Removes a specific file download task from the queue.
 * @param dfile The file download task to be removed.
 */
- (void)removeFileDownloadTask:(SeafFile * _Nonnull)dfile;

/**
 * Removes a specific upload task from the queue.
 * @param ufile The upload task to be removed.
 */
- (void)removeUploadTask:(SeafUploadFile * _Nonnull)ufile;

/**
 * Removes a specific avatar download task from the queue.
 * @param avatar The avatar download task to be removed.
 */
- (void)removeAvatarTask:(SeafAvatar * _Nonnull)avatar;

/**
 * Removes a specific thumbnail download task from the queue.
 * @param thumb The thumbnail download task to be removed.
 */
- (void)removeThumbTask:(SeafThumb * _Nonnull)thumb;

/**
 * Executes the tick method on all queues to process tasks.
 */
- (void)tick;

/**
 * Clears all tasks from all queues.
 */
- (void)clearTasks;
@end
