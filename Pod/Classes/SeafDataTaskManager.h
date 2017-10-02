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
@class SeafDownloadAccountQueue;

typedef void(^SyncBlock)(SeafFile *file);
typedef void(^DownLoadFinshBlock)(SeafFile *file);
// Manager for background download/upload tasks, retry if failed.
@interface SeafDataTaskManager : NSObject

@property (readonly) ALAssetsLibrary *assetsLibrary;
@property (nonatomic, copy) SyncBlock trySyncBlock;
@property (nonatomic, copy) DownLoadFinshBlock finishBlock;

+ (SeafDataTaskManager *)sharedObject;

- (void)addBackgroundUploadTask:(SeafUploadFile *)file;
- (void)finishUpload:(SeafUploadFile *)file result:(BOOL)result;
- (void)removeBackgroundUploadTask:(SeafUploadFile *)file;

- (void)cancelAutoSyncTasks:(SeafConnection *)conn;
- (void)cancelAutoSyncVideoTasks:(SeafConnection *)conn;

- (void)assetForURL:(NSURL *)assetURL resultBlock:(ALAssetsLibraryAssetForURLResultBlock)resultBlock failureBlock:(ALAssetsLibraryAccessFailureBlock)failureBlock;

- (void)addDownloadTask:(id<SeafDownloadDelegate>)task;
- (void)finishDownloadTask:(id<SeafDownloadDelegate>)task result:(BOOL)result;
- (SeafDownloadAccountQueue*)accountQueueForConnection:(SeafConnection*)connection;
- (void)removeBackgroundDownloadTask:(id<SeafDownloadDelegate>)task;

@end

@interface SeafDownloadAccountQueue : NSObject

@property (nonatomic, strong) SeafTaskQueue *fileQueue;
@property (nonatomic, strong) SeafTaskQueue *thumbQueue;
@property (nonatomic, strong) SeafTaskQueue *avatarQueue;
@property (nonatomic, strong) SeafTaskQueue *uploadQueue;

- (void)addFileDownloadTask:(SeafFile * _Nullable)dfile;
- (void)addUploadTask:(SeafUploadFile * _Nullable)ufile;
- (void)addAvatarTask:(SeafAvatar * _Nullable)avatar;
- (void)addThumbTask:(SeafThumb * _Nullable)thumb;

@end
