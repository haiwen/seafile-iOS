//
//  SeafAccountTaskQueue.h
//  Pods
//
//  Created by henry on 2024/11/11.
//
#import "SeafUploadFile.h"
#import "SeafFile.h"
#import "SeafThumb.h"
#import "SeafBaseOperation.h"

@interface SeafAccountTaskQueue : NSObject

@property (nonatomic, strong) NSOperationQueue * _Nonnull downloadQueue;
@property (nonatomic, strong) NSOperationQueue * _Nonnull thumbQueue;
@property (nonatomic, strong) NSOperationQueue * _Nonnull uploadQueue;

// Arrays for task status
@property (nonatomic, strong) NSMutableArray<SeafUploadFile *> * _Nullable ongoingTasks;
@property (nonatomic, strong) NSMutableArray<SeafUploadFile *> * _Nullable waitingTasks;
@property (nonatomic, strong) NSMutableArray<SeafUploadFile *> * _Nullable cancelledTasks;
@property (nonatomic, strong) NSMutableArray<SeafUploadFile *> * _Nullable completedSuccessfulTasks;
@property (nonatomic, strong) NSMutableArray<SeafUploadFile *> * _Nullable completedFailedTasks;

// 下载任务状态数组
@property (nonatomic, strong) NSMutableArray<SeafFile *> * _Nullable ongoingDownloadTasks;
@property (nonatomic, strong) NSMutableArray<SeafFile *> * _Nullable waitingDownloadTasks;
@property (nonatomic, strong) NSMutableArray<SeafFile *> * _Nullable cancelledDownloadTasks;
@property (nonatomic, strong) NSMutableArray<SeafFile *> * _Nullable completedSuccessfulDownloadTasks;
@property (nonatomic, strong) NSMutableArray<SeafFile *> * _Nullable completedFailedDownloadTasks;

// keep track of paused tasks
@property (nonatomic, strong) NSMutableArray<SeafUploadFile *> * _Nullable pausedUploadTasks;
@property (nonatomic, strong) NSMutableArray<SeafFile *> * _Nullable pausedDownloadTasks;
@property (nonatomic, strong) NSMutableArray<SeafThumb *> * _Nullable pausedThumbTasks;

// 取消的缩略图数组
@property (nonatomic, strong) NSMutableArray<SeafThumb *> * _Nullable cancelledThumbTasks;

@property (nonatomic, strong) SeafConnection * _Nonnull conn;

- (void)addFileDownloadTask:(SeafFile * _Nonnull)dfile;
- (BOOL)addUploadTask:(SeafUploadFile * _Nonnull)ufile;
- (void)addThumbTask:(SeafThumb * _Nonnull)thumb;

- (void)removeFileDownloadTask:(SeafFile * _Nonnull)dfile;
- (void)removeUploadTask:(SeafUploadFile * _Nonnull)ufile;
- (void)removeThumbTask:(SeafThumb * _Nonnull)thumb;

- (NSArray *_Nullable)getUploadTasksInDir:(SeafDir *_Nullable)dir;

- (NSArray<SeafUploadFile *> *_Nullable)getNeedUploadTasks;
- (NSArray<SeafUploadFile *> *_Nullable)getOngoingTasks;
- (NSArray<SeafUploadFile *> *_Nullable)getWaitingTasks;
- (NSArray<SeafUploadFile *> *_Nullable)getCancelledTasks;
- (NSArray<SeafUploadFile *> *_Nullable)getCompletedSuccessfulTasks;
- (NSArray<SeafUploadFile *> *_Nullable)getCompletedFailedTasks;

- (NSArray<SeafFile *> *_Nullable)getNeedDownloadTasks;
- (NSArray<SeafFile *> *_Nullable)getOngoingDownloadTasks;
- (NSArray<SeafFile *> *_Nullable)getWaitingDownloadTasks;
- (NSArray<SeafFile *> *_Nullable)getCancelledDownloadTasks;
- (NSArray<SeafFile *> *_Nullable)getCompletedSuccessfulDownloadTasks;
- (NSArray<SeafFile *> *_Nullable)getCompletedFailedDownloadTasks;

// 继续取消过的缩略图
- (BOOL)resumeCancelledThumbTask:(SeafThumb * _Nonnull)thumb;

- (void)cancelAllTasks;
- (void)cancelAllUploadTasks;
- (void)cancelAllDownloadTasks;
- (void)cancelAutoSyncTasks;
- (void)cancelAutoSyncVideoTasks;
- (void)cancelUploadTasksForLocalIdentifier:(NSArray<NSString *> *_Nullable)accountIdentifiers;

- (void)postUploadTaskStatusChangedNotification;
- (void)postDownloadTaskStatusChangedNotification;

- (void)pauseAllTasks;
- (void)resumeAllTasks;

// 定时器控制方法
- (void)startCleanupTimer;   // 启动清理任务的定时器
- (void)pauseCleanupTimer;   // 暂停清理任务的定时器

@end
