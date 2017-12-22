//
//  SeafBackgroundTaskManager.h
//  Pods
//
//  Created by Wei W on 4/9/17.
//
//

#import <Foundation/Foundation.h>
#import <AssetsLibrary/AssetsLibrary.h>

#import "SeafPreView.h"
#import "SeafConnection.h"
#import "SeafUploadFile.h"
#import "SeafFile.h"
#import "SeafThumb.h"
#import "SeafAvatar.h"
#import "SeafTaskQueue.h"
@class SeafAccountTaskQueue;

typedef void(^SyncBlock)(id<SeafTask> _Nullable file);
typedef void(^DownLoadFinshBlock)(id<SeafTask>  _Nonnull task);
// Manager for background download/upload tasks, retry if failed.
@interface SeafDataTaskManager : NSObject

@property (readonly) ALAssetsLibrary * _Nonnull assetsLibrary;
@property (nonatomic, copy) SyncBlock _Nullable trySyncBlock;
@property (nonatomic, copy) DownLoadFinshBlock _Nullable finishBlock;

+ (SeafDataTaskManager * _Nonnull)sharedObject;

- (void)addFileDownloadTask:(SeafFile * _Nonnull)dfile;
- (void)addUploadTask:(SeafUploadFile * _Nonnull)ufile;
- (void)addAvatarTask:(SeafAvatar * _Nonnull)avatar;
- (void)addThumbTask:(SeafThumb * _Nonnull)thumb;
- (void)removeUploadTask:(SeafUploadFile * _Nonnull)ufile forAccount:(SeafConnection * _Nonnull)conn;

- (void)startLastTimeUnfinshTaskWithConnection:(SeafConnection *_Nullable)conn;
- (void)removeAccountQueue:(SeafConnection *_Nullable)conn;

- (NSArray * _Nullable)getUploadTasksInDir:(SeafDir * _Nullable)dir;

- (void)cancelAutoSyncTasks:(SeafConnection * _Nonnull)conn;
- (void)cancelAutoSyncVideoTasks:(SeafConnection * _Nonnull)conn;
- (void)cancelAllDownloadTasks:(SeafConnection * _Nonnull)conn;
- (void)cancelAllUploadTasks:(SeafConnection * _Nonnull)conn;

- (void)assetForURL:(NSURL * _Nonnull)assetURL resultBlock:(ALAssetsLibraryAssetForURLResultBlock _Nonnull)resultBlock failureBlock:(ALAssetsLibraryAccessFailureBlock _Nonnull)failureBlock;

- (SeafAccountTaskQueue * _Nonnull)accountQueueForConnection:(SeafConnection * _Nonnull)connection;

@end

@interface SeafAccountTaskQueue : NSObject

@property (nonatomic, strong) SeafTaskQueue * _Nonnull fileQueue;
@property (nonatomic, strong) SeafTaskQueue * _Nonnull thumbQueue;
@property (nonatomic, strong) SeafTaskQueue * _Nonnull avatarQueue;
@property (nonatomic, strong) SeafTaskQueue * _Nonnull uploadQueue;

- (void)addFileDownloadTask:(SeafFile * _Nonnull)dfile;
- (void)addUploadTask:(SeafUploadFile * _Nonnull)ufile;
- (void)addAvatarTask:(SeafAvatar * _Nonnull)avatar;
- (void)addThumbTask:(SeafThumb * _Nonnull)thumb;

- (void)removeFileDownloadTask:(SeafFile * _Nonnull)dfile;
- (void)removeUploadTask:(SeafUploadFile * _Nonnull)ufile;
- (void)removeAvatarTask:(SeafAvatar * _Nonnull)avatar;
- (void)removeThumbTask:(SeafThumb * _Nonnull)thumb;
- (void)tick;
- (void)clearTasks;
@end
