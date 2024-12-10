//
//  SeafThumbOperation.m
//  Seafile
//
//  Created by henry on 2024/11/11.
//
// SeafThumbOperation.m

#import "SeafThumbOperation.h"
#import "SeafFile.h"
#import "SeafConnection.h"
#import "SeafStorage.h"
#import "SeafBase.h"
#import "SeafRepos.h"
#import "Utils.h"
#import "Debug.h"

@interface SeafThumbOperation ()

@property (nonatomic, assign) BOOL executing;
@property (nonatomic, assign) BOOL finished;

@property (strong, nonatomic) NSURLSessionDownloadTask *thumbTask;
@property (strong, nonatomic) NSProgress *progress;

@property (nonatomic, strong) NSMutableArray<NSURLSessionTask *> *taskList;
@property (nonatomic, assign) BOOL operationCompleted;

@property (nonatomic, assign) NSInteger retryCount; // 记录当前失败重试次数

@end

@implementation SeafThumbOperation

@synthesize executing = _executing;
@synthesize finished = _finished;

#define MAX_RETRY_COUNT 3

- (instancetype)initWithSeafFile:(SeafFile *)file
{
    if (self = [super init]) {
        _file = file;
        _executing = NO;
        _finished = NO;
        _taskList = [NSMutableArray array];
        _retryCount = 0; // 初始化重试次数为 0

    }
    return self;
}

#pragma mark - NSOperation Overrides

- (BOOL)isAsynchronous
{
    return YES;
}

- (BOOL)isExecuting
{
    return _executing;
}

- (BOOL)isFinished
{
    return _finished;
}

- (void)start
{
    [self.taskList removeAllObjects];
    
    if (self.isCancelled) {
        [self completeOperation];
        return;
    }

    [self willChangeValueForKey:@"isExecuting"];
    _executing = YES;
    [self didChangeValueForKey:@"isExecuting"];

    [self downloadThumb];
}

- (void)cancel
{
    [super cancel];
    [self cancelAllRequests];
    if (self.isExecuting && !_operationCompleted) {
        [self completeOperation];
    }
}

- (void)cancelAllRequests
{
    for (NSURLSessionTask *task in self.taskList) {
        [task cancel];
    }
    [self.taskList removeAllObjects];
}

#pragma mark - Thumb Download Logic

- (void)downloadThumb
{
    SeafConnection *connection = self.file->connection;
    SeafRepo *repo = [connection getRepo:self.file.repoId];
    if (repo.encrypted) {
        [self finishDownloadThumbOperation:NO];
        return;
    }
    int size = THUMB_SIZE * (int)[[UIScreen mainScreen] scale];
    NSString *thumburl = [NSString stringWithFormat:API_URL"/repos/%@/thumbnail/?size=%d&p=%@", self.file.repoId, size, self.file.path.escapedUrl];
    NSURLRequest *downloadRequest = [connection buildRequest:thumburl method:@"GET" form:nil];
    Debug("Request: %@", downloadRequest.URL);
    NSString *target = [self thumbPath:self.file.oid];
    
    @synchronized (self) {
        if (self.file.thumb) {
            [self finishDownloadThumbOperation:YES];
            return;
        }
    }
    
    __weak typeof(self) weakSelf = self;
    self.thumbTask = [connection.sessionMgr downloadTaskWithRequest:downloadRequest progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        return [NSURL fileURLWithPath:[target stringByAppendingPathExtension:@"tmp"]];
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf.isCancelled) {
            [strongSelf finishDownloadThumbOperation:NO];
            return;
        }
        if (error) {
            if (error.code == NSURLErrorCancelled) {
                Debug(@"Task was cancelled %@", self.file.name);
//                [self.file finishDownloadThumb:NO];
                [strongSelf finishDownloadThumbOperation:NO];
            } else {
                strongSelf.retryCount++; // 增加重试次数
                if (strongSelf.retryCount < MAX_RETRY_COUNT) {
                    Debug(@"Retrying download for %@ (Retry %ld/%ld)", self.file.name, (long)strongSelf.retryCount, (long)MAX_RETRY_COUNT);
                    // 延迟1s后重试，避免过快重试
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [strongSelf downloadThumb];
                    });
                } else {
                    Debug(@"Max retry count reached for %@. Failing download.", self.file.name);
//                    [self.file finishDownloadThumb:NO];
                    [strongSelf finishDownloadThumbOperation:NO];
                }
            }
        }
        else {
                if (![filePath.path isEqualToString:target]) {
                    [Utils removeFile:target];
                    [[NSFileManager defaultManager] moveItemAtPath:filePath.path toPath:target error:nil];
                }
//                [self.file finishDownloadThumb:YES];
                [strongSelf finishDownloadThumbOperation:YES];
        } 
    }];
    
    [self.thumbTask resume];
    [self.taskList addObject:self.thumbTask];
}

- (NSString *)thumbPath:(NSString *)objId
{
    if (!objId) return nil;
    int size = THUMB_SIZE * (int)[[UIScreen mainScreen] scale];
    return [SeafStorage.sharedObject.thumbsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@-%d", objId, size]];
}

- (void)finishDownloadThumbOperation:(BOOL)success
{
//    if (success) {
//        // 通知文件对象缩略图已下载完成
//        if (self.file.delegate && [(NSObject *)self.file.delegate respondsToSelector:@selector(download:complete:)]) {
//            dispatch_async(dispatch_get_main_queue(), ^{
//                [self.file.delegate download:self.file complete:NO];
//            });
//        }
//    }
    [self.file finishDownloadThumb:success];
    [self completeOperation];
}

#pragma mark - Operation State Management

- (void)completeOperation
{
    if (_operationCompleted) {
        return; // 如果已经完成操作，则不再重复执行
    }

    _operationCompleted = YES;  // 设置标志，表示操作已完成
    
    // 重置重试次数
    self.retryCount = 0;

    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    _executing = NO;
    _finished = YES;
    [self didChangeValueForKey:@"isFinished"];
    [self didChangeValueForKey:@"isExecuting"];
}

@end
