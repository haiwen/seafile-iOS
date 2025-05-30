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
#import <AFNetworking/AFHTTPSessionManager.h> // For AFHTTPSessionManager
#import <AFNetworking/AFNetworkReachabilityManager.h> // For AFNetworkReachabilityManager

@interface SeafThumbOperation ()

@property (nonatomic, assign) BOOL executing;
@property (nonatomic, assign) BOOL finished;

@property (strong, nonatomic) NSURLSessionDownloadTask *thumbTask;
@property (strong, nonatomic) NSProgress *progress;

@property (nonatomic, strong) NSMutableArray<NSURLSessionTask *> *taskList;
@property (nonatomic, assign) BOOL operationCompleted;

@property (nonatomic, assign) NSInteger retryCount; // Tracks the current number of retry attempts

@end

@implementation SeafThumbOperation

@synthesize executing = _executing;
@synthesize finished = _finished;

#define THUMB_MAX_RETRY_COUNT 0

- (instancetype)initWithSeafFile:(SeafFile *)file
{
    if (self = [super init]) {
        _file = file;
        _executing = NO;
        _finished = NO;
        _taskList = [NSMutableArray array];
        _retryCount = 0; // Initialize retry count to 0
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

    // Check network availability when the operation starts
    // Ensure file, connection, and sessionMgr are valid
    if (!self.file || !self.file.connection || !self.file.connection.sessionMgr || !self.file.connection.sessionMgr.reachabilityManager.isReachable) {
        Debug(@"[SeafThumbOperation] Network is not available or connection/session manager is invalid at start for: %@", self.file ? self.file.name : @"unknown file");
        [self finishDownloadThumbOperation:NO]; // Marks failure and completes operation
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
    SeafConnection *connection = self.file.connection;
    SeafRepo *repo = [connection getRepo:self.file.repoId];
    if (repo.encrypted) {
        [self finishDownloadThumbOperation:NO];
        return;
    }
    int size = THUMB_SIZE * (int)[[UIScreen mainScreen] scale];
    NSString *thumburl = [NSString stringWithFormat:API_URL"/repos/%@/thumbnail/?size=%d&p=%@", self.file.repoId, size, self.file.path.escapedUrl];
    NSURLRequest *downloadRequest = [connection buildRequest:thumburl method:@"GET" form:nil];
    NSMutableURLRequest *mutableDownloadRequest = [downloadRequest mutableCopy];
    mutableDownloadRequest.timeoutInterval = 10.0;
    downloadRequest = [mutableDownloadRequest copy];
    Debug("Request: %@, Timeout: %f", downloadRequest.URL, downloadRequest.timeoutInterval);
    
    NSString *target;
    if (self.file.oid) {
        target = [self thumbPath:self.file.oid];
    } else {
        target = [SeafStorage.sharedObject.thumbsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@-%lld", self.file.name, self.file.mtime]];
    }
    
    @synchronized (self) {
        if (self.file.thumb) {
            [self finishDownloadThumbOperation:YES];
            return;
        }
    }
    
    __weak typeof(self) weakSelf = self;
    self.thumbTask = [connection.sessionMgr downloadTaskWithRequest:downloadRequest progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        return [NSURL fileURLWithPath:target];
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf.isCancelled) {
            [strongSelf finishDownloadThumbOperation:NO];
            return;
        }
        if (error) {
            if (error.code == NSURLErrorCancelled) {
                Debug(@"Task was cancelled %@", self.file.name);
                [strongSelf finishDownloadThumbOperation:NO];
            } else {
                strongSelf.retryCount++; // Increment the retry count
                if (strongSelf.retryCount < THUMB_MAX_RETRY_COUNT) {
                    Debug(@"Retrying download for %@ (Retry %ld/%ld)", self.file.name, (long)strongSelf.retryCount, (long)THUMB_MAX_RETRY_COUNT);
                    // Retry after a 1-second delay to avoid retrying too quickly
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [strongSelf downloadThumb];
                    });
                } else {
                    Debug(@"Max retry count reached for %@. Failing download.", self.file.name);
                    [strongSelf finishDownloadThumbOperation:NO];
                }
            }
        }
        else {
            if (![filePath.path isEqualToString:target]) {
                [Utils removeFile:target];
                [[NSFileManager defaultManager] moveItemAtPath:filePath.path toPath:target error:nil];
            }
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
    [self.file finishDownloadThumb:success];
    [self completeOperation];
}

#pragma mark - Operation State Management
- (void)completeOperation
{
    if (_operationCompleted) {
        return; // If the operation is already completed, do not repeat
    }

    _operationCompleted = YES;  // Set the flag indicating operation is complete
    
    // Reset the retry count
    self.retryCount = 0;

    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    _executing = NO;
    _finished = YES;
    [self didChangeValueForKey:@"isFinished"];
    [self didChangeValueForKey:@"isExecuting"];
}

@end
