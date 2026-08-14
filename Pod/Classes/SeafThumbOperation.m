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
#import "SeafCacheManager.h"
#import "Utils.h"
#import "Debug.h"
#import "SeafCacheManager+Thumb.h"
#import <AFNetworking/AFHTTPSessionManager.h> // For AFHTTPSessionManager
#import <AFNetworking/AFNetworkReachabilityManager.h> // For AFNetworkReachabilityManager

@interface SeafThumbOperation ()

@property (nonatomic, assign) BOOL executing;
@property (nonatomic, assign) BOOL finished;

@property (strong, nonatomic) NSURLSessionDownloadTask *thumbTask;
@property (strong, nonatomic) NSProgress *progress;

@property (nonatomic, strong) NSMutableArray<NSURLSessionTask *> *taskList;
@property (nonatomic, assign) BOOL operationCompleted;

// Set once, under @synchronized(self), by whichever thread first reports a thumb
// result. Decode/warm now finishes on a global queue while cancel comes from the
// main queue, so without this gate both can pass the completion check and report
// twice.
@property (nonatomic, assign) BOOL thumbResultReported;

/// Generation claimed for the shared on-disk thumb path. Only the current owner
/// may delete that path on cancel/error, so a cancelled op cannot wipe a newer
/// download that reused the same target.
@property (nonatomic, assign) NSInteger thumbPathGeneration;

@end

@implementation SeafThumbOperation

@synthesize executing = _executing;
@synthesize finished = _finished;

// path -> current generation. Protected by @synchronized(SeafThumbPathGenerations()).
static NSMutableDictionary<NSString *, NSNumber *> *SeafThumbPathGenerations(void)
{
    static NSMutableDictionary<NSString *, NSNumber *> *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = [NSMutableDictionary dictionary];
    });
    return map;
}

static NSInteger SeafThumbClaimPathGeneration(NSString *path)
{
    if (path.length == 0) return 0;
    NSMutableDictionary<NSString *, NSNumber *> *map = SeafThumbPathGenerations();
    @synchronized (map) {
        NSInteger next = map[path].integerValue + 1;
        map[path] = @(next);
        return next;
    }
}

static BOOL SeafThumbOwnsPathGeneration(NSString *path, NSInteger generation)
{
    if (path.length == 0 || generation <= 0) return NO;
    NSMutableDictionary<NSString *, NSNumber *> *map = SeafThumbPathGenerations();
    @synchronized (map) {
        return map[path].integerValue == generation;
    }
}

static void SeafThumbReleasePathGenerationIfOwned(NSString *path, NSInteger generation)
{
    if (path.length == 0 || generation <= 0) return;
    NSMutableDictionary<NSString *, NSNumber *> *map = SeafThumbPathGenerations();
    @synchronized (map) {
        if (map[path].integerValue == generation) {
            [map removeObjectForKey:path];
        }
    }
}

typedef NS_ENUM(NSInteger, SeafThumbFailureKind) {
    SeafThumbFailureNone,       ///< Not recorded: offline, cancelled, DNS and the like.
    SeafThumbFailurePermanent,  ///< 4xx other than 400/408/429: this version cannot be thumbnailed.
    SeafThumbFailureCounted,    ///< 400, 500 and other 5xx: short backoff, given up after a few.
    SeafThumbFailureBusy,       ///< 408/429/502/503/504, request timeout: short backoff, never counted.
};

/// How SeafCacheManager+Thumb should remember this failure. Busy means the
/// server is still working: thumbnail-server answers 503 when its generation
/// queue is full and keeps generating regardless, and a request timeout means it
/// was still waiting on that queue, so the next try a few seconds later usually
/// succeeds. 400 stays counted: thumbnail-server sends it both for its own 60s
/// generation timeout and for unsupported types, and the latter must stop.
static SeafThumbFailureKind SeafThumbClassifyFailure(NSHTTPURLResponse *httpResp, NSError *error)
{
    if (httpResp == nil) {
        BOOL timedOut = [error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorTimedOut;
        return timedOut ? SeafThumbFailureBusy : SeafThumbFailureNone;
    }
    NSInteger status = httpResp.statusCode;
    switch (status) {
        case 408: case 429: case 502: case 503: case 504:
            return SeafThumbFailureBusy;
        case 400:
            return SeafThumbFailureCounted;
        default:
            if (status >= 500) return SeafThumbFailureCounted;
            if (status >= 400) return SeafThumbFailurePermanent;
            return SeafThumbFailureNone;
    }
}

- (instancetype)initWithSeafFile:(SeafFile *)file
{
    if (self = [super init]) {
        _file = file;
        _executing = NO;
        _finished = NO;
        _taskList = [NSMutableArray array];
        _operationCompleted = NO;
        _thumbResultReported = NO;
        _thumbPathGeneration = 0;
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
    @synchronized (self) {
        return _executing;
    }
}

- (BOOL)isFinished
{
    @synchronized (self) {
        return _finished;
    }
}

- (void)start
{
    [self clearTaskList];
    
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
    @synchronized (self) {
        _executing = YES;
    }
    [self didChangeValueForKey:@"isExecuting"];

    [self downloadThumb];
}

- (void)cancel
{
    [super cancel];
    [self cancelAllRequests];
    // An operation that never started is finished by `start`, which checks
    // isCancelled; only tear down one that is already running.
    BOOL running = NO;
    @synchronized (self) {
        running = _executing && !_operationCompleted;
    }
    if (running) {
        [self completeOperation];
    }
}

- (void)cancelAllRequests
{
    for (NSURLSessionTask *task in [self currentTasks]) {
        [task cancel];
    }
    [self clearTaskList];
}

- (NSArray<NSURLSessionTask *> *)currentTasks
{
    @synchronized (self.taskList) {
        return [self.taskList copy];
    }
}

- (void)addTaskToList:(NSURLSessionTask *)task
{
    if (!task) return;
    @synchronized (self.taskList) {
        [self.taskList addObject:task];
    }
}

- (void)clearTaskList
{
    @synchronized (self.taskList) {
        [self.taskList removeAllObjects];
    }
}

#pragma mark - Thumb Download Logic

- (void)downloadThumb
{
    SeafConnection *connection = self.file.connection;
    SeafRepo *repo = [connection getRepo:self.file.repoId];
    BOOL needsLongerTimeout = [Utils isServerThumbDocumentFile:self.file.name] || [Utils isServerThumbVideoFile:self.file.name];
    if (repo.encrypted) {
        [self finishDownloadThumbOperation:NO];
        return;
    }
    // The request size is fixed inside buildThumbnailRequestPathForFile:. The
    // screen-scale suffix on the on-disk path below is only a cache key.
    NSString *thumburl = [connection buildThumbnailRequestPathForFile:self.file];
    NSURLRequest *downloadRequest = [connection buildRequest:thumburl method:@"GET" form:nil];
    NSMutableURLRequest *mutableDownloadRequest = [downloadRequest mutableCopy];
    // PDF/sdoc/video thumbnail generation on the server can take longer than image thumbs.
    mutableDownloadRequest.timeoutInterval = needsLongerTimeout ? 60.0 : 10.0;
    downloadRequest = [mutableDownloadRequest copy];
    Debug("Request: %@, Timeout: %f", downloadRequest.URL, downloadRequest.timeoutInterval);
    
    NSString *target = [[SeafCacheManager sharedManager] thumbCachePathForFile:self.file];
    
    BOOL hasDiskThumb = [Utils fileExistsAtPath:target];
    if (hasDiskThumb) {
        __weak typeof(self) weakSelf = self;
        [[SeafCacheManager sharedManager] warmThumbCacheAtPath:target completion:^(UIImage *warmed) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (strongSelf.isCancelled) {
                [strongSelf finishDownloadThumbOperation:NO];
                return;
            }
            [strongSelf finishDownloadThumbOperation:(warmed != nil)];
        }];
        return;
    }
    if (self.file.thumb) {
        [self finishDownloadThumbOperation:YES];
        return;
    }

    // Claim ownership of the shared target path before starting the download so a
    // later cancelled completion cannot delete a newer op's successful write.
    self.thumbPathGeneration = SeafThumbClaimPathGeneration(target);

    __weak typeof(self) weakSelf = self;
    self.thumbTask = [connection.sessionMgr downloadTaskWithRequest:downloadRequest progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        return [NSURL fileURLWithPath:target];
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            // Op deallocated; only remove a distinct temp file, never the shared target
            // (a newer op may already own it).
            if (filePath.path.length && ![filePath.path isEqualToString:target]) {
                [Utils removeFile:filePath.path];
            }
            return;
        }
        NSHTTPURLResponse *httpResp = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        NSInteger generation = strongSelf.thumbPathGeneration;
        BOOL ownsTarget = SeafThumbOwnsPathGeneration(target, generation);

        // AF download may still write an HTML/JSON error body into the destination on 4xx/5xx.
        // Only the current path owner may delete `target`; always clean a distinct temp path.
        void (^cleanupBadThumbFile)(void) = ^{
            if (ownsTarget && target.length) {
                [Utils removeFile:target];
            }
            if (filePath.path.length && ![filePath.path isEqualToString:target]) {
                [Utils removeFile:filePath.path];
            }
        };

        if (strongSelf.isCancelled) {
            cleanupBadThumbFile();
            SeafThumbReleasePathGenerationIfOwned(target, generation);
            [strongSelf finishDownloadThumbOperation:NO];
            return;
        }
        if (error) {
            cleanupBadThumbFile();
            if (error.code == NSURLErrorCancelled) {
                Debug(@"Task was cancelled %@", self.file.name);
                SeafThumbReleasePathGenerationIfOwned(target, generation);
                [strongSelf finishDownloadThumbOperation:NO];
            } else {
                // Retries are handled at enqueue time by SeafCacheManager+Thumb
                // (backoff / cap / permanent-fail negative cache), not inside this op.
                // See SeafThumbClassifyFailure for the policy behind each kind.
                switch (SeafThumbClassifyFailure(httpResp, error)) {
                    case SeafThumbFailurePermanent:
                        [[SeafCacheManager sharedManager] markThumbDownloadPermanentlyFailedForFile:strongSelf.file];
                        break;
                    case SeafThumbFailureCounted:
                        [[SeafCacheManager sharedManager] markThumbDownloadTransientlyFailedForFile:strongSelf.file];
                        break;
                    case SeafThumbFailureBusy:
                        [[SeafCacheManager sharedManager] markThumbDownloadBusyForFile:strongSelf.file];
                        break;
                    case SeafThumbFailureNone:
                        break;
                }
                Debug(@"Thumbnail download failed for %@: %@", self.file.name, error);
                SeafThumbReleasePathGenerationIfOwned(target, generation);
                [strongSelf finishDownloadThumbOperation:NO];
            }
        }
        else {
            if (!ownsTarget) {
                // A newer download owns this path; drop our temp artifact if any.
                if (filePath.path.length && ![filePath.path isEqualToString:target]) {
                    [Utils removeFile:filePath.path];
                }
                [strongSelf finishDownloadThumbOperation:NO];
                return;
            }
            if (![filePath.path isEqualToString:target]) {
                [Utils removeFile:target];
                [[NSFileManager defaultManager] moveItemAtPath:filePath.path toPath:target error:nil];
            }
            if (![UIImage imageWithContentsOfFile:target]) {
                // 2xx but the body isn't a decodable image (HTML error page, empty body,
                // etc.). Record as transient so SeafCacheManager+Thumb can backoff-retry
                // on the next enqueue instead of hammering the server on every refresh.
                [[SeafCacheManager sharedManager] markThumbDownloadTransientlyFailedForFile:strongSelf.file];
                cleanupBadThumbFile();
                SeafThumbReleasePathGenerationIfOwned(target, generation);
                [strongSelf finishDownloadThumbOperation:NO];
                return;
            }

            // Decode + warm memory cache off the main thread so UI refresh
            // (thumbnailDownload:) can set a ready-to-composite bitmap.
            [[SeafCacheManager sharedManager] warmThumbCacheAtPath:target completion:^(UIImage *warmed) {
                if (strongSelf.isCancelled) {
                    // Successful bytes already belong to a usable thumb; do not delete
                    // the shared path just because this op was cancelled after write.
                    SeafThumbReleasePathGenerationIfOwned(target, generation);
                    [strongSelf finishDownloadThumbOperation:NO];
                    return;
                }
                SeafThumbReleasePathGenerationIfOwned(target, generation);
                [strongSelf finishDownloadThumbOperation:(warmed != nil)];
            }];
        }
    }];
    
    [self.thumbTask resume];
    [self addTaskToList:self.thumbTask];
}

- (void)finishDownloadThumbOperation:(BOOL)success
{
    @synchronized (self) {
        if (_thumbResultReported || _operationCompleted) {
            return;
        }
        _thumbResultReported = YES;
    }
    [self.file finishDownloadThumb:success forTask:self.thumb];
    [self completeOperation];
}

#pragma mark - Operation State Management
- (void)completeOperation
{
    @synchronized (self) {
        if (_operationCompleted) {
            return; // If the operation is already completed, do not repeat
        }

        _operationCompleted = YES;  // Set the flag indicating operation is complete
    }

    // The gate above guarantees a single winner, so the KVO pair is sent exactly
    // once. Send it outside the lock: observers read isExecuting/isFinished, which
    // take the same lock, and they may do so from another thread.
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    @synchronized (self) {
        _executing = NO;
        _finished = YES;
    }
    [self didChangeValueForKey:@"isFinished"];
    [self didChangeValueForKey:@"isExecuting"];
}

@end
