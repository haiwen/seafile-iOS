//
//  SeafBackgroundTaskManager.h
//  Pods
//
//  Created by Wei W on 4/9/17.
//
//

// SeafDataTaskManager.h

#import <Foundation/Foundation.h>
#import "SeafPreView.h"
#import "SeafConnection.h"
#import "SeafUploadFile.h"
#import "SeafFile.h"
#import "SeafThumb.h"
#import "SeafAccountTaskQueue.h"

typedef void(^SyncBlock)(id<SeafTask> _Nullable file);
typedef void(^DownLoadFinshBlock)(id<SeafTask>  _Nonnull task);

#define KEY_DOWNLOAD @"allDownloadingTasks"
#define KEY_UPLOAD @"allUploadingTasks"

/**
 * Manager for background download/upload tasks, utilizing NSOperationQueue.
 */
@interface SeafDataTaskManager : NSObject

//@property (nonatomic, copy) SyncBlock _Nullable trySyncBlock;
@property (nonatomic, copy) DownLoadFinshBlock _Nullable finishBlock;

+ (SeafDataTaskManager * _Nonnull)sharedObject;

- (void)addFileDownloadTask:(SeafFile * _Nonnull)dfile;
- (BOOL)addUploadTask:(SeafUploadFile * _Nonnull)ufile;
- (void)addThumbTask:(SeafThumb * _Nonnull)thumb;

- (void)removeUploadTask:(SeafUploadFile * _Nonnull)ufile forAccount:(SeafConnection * _Nonnull)conn;

- (void)startLastTimeUnfinshTaskWithConnection:(SeafConnection *_Nullable)conn;
- (void)removeAccountQueue:(SeafConnection *_Nullable)conn;

- (NSArray * _Nullable)getUploadTasksInDir:(SeafDir *_Nullable)dir connection:(SeafConnection * _Nonnull)connection;

- (void)cancelAllDownloadTasks:(SeafConnection * _Nonnull)conn;
- (void)cancelAllUploadTasks:(SeafConnection * _Nonnull)conn;

- (SeafAccountTaskQueue * _Nonnull)accountQueueForConnection:(SeafConnection * _Nonnull)connection;

- (void)removeThumbTaskFromAccountQueue:(SeafThumb * _Nonnull)thumb;

- (NSArray *_Nullable)getOngoingUploadTasks: (SeafConnection *_Nullable)connection;

- (NSMutableDictionary*_Nullable)convertTaskToDict:(id _Nullable )task;

@end
