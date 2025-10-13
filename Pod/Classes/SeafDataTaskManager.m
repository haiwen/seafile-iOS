//  SeafBackgroundTaskManager.m
//  Pods
//
//  Created by Wei W on 4/9/17.
//
//
// SeafDataTaskManager.m

#import "SeafDataTaskManager.h"
#import "SeafUploadOperation.h"
#import "SeafDownloadOperation.h"
#import "SeafThumbOperation.h"
#import "SeafDir.h"
#import "Debug.h"
#import "SeafStorage.h"
#import <AFNetworking/AFNetworking.h>
#import "SeafUploadFileModel.h"
#import "SeafFile.h"
#import "SeafThumb.h"
#import "Version.h"

@interface SeafDataTaskManager()

@property (nonatomic, strong) NSMutableDictionary<NSString *, SeafAccountTaskQueue *> *accountQueueDict;
@property (nonatomic, strong) AFNetworkReachabilityManager *reachabilityManager;

@end

@implementation SeafDataTaskManager

+ (SeafDataTaskManager *)sharedObject
{
    static SeafDataTaskManager *object = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        object = [SeafDataTaskManager new];
    });
    return object;
}

- (id)init
{
    if (self = [super init]) {
        _accountQueueDict = [NSMutableDictionary new];
        _finishBlock = nil;
        
        // initial network monitor
        [self setupNetworkMonitoring];
    }
    return self;
}

#pragma mark - Upload Tasks

- (BOOL)addUploadTask:(SeafUploadFile *)file {
    return [self addUploadTask:file priority:NSOperationQueuePriorityNormal];
}

- (BOOL)addUploadTask:(SeafUploadFile *)file priority:(NSOperationQueuePriority)priority {
    SeafAccountTaskQueue *accountQueue = [self accountQueueForConnection:file.udir.connection];
    BOOL res = [accountQueue addUploadTask:file priority:priority];
    if (res && file.retryable) {
        [self saveUploadFileToTaskStorage:file];
    }
    return res;
}

- (void)removeUploadTask:(SeafUploadFile *)ufile forAccount:(SeafConnection * _Nonnull)conn
{
    SeafAccountTaskQueue *accountQueue = [self accountQueueForConnection:conn];
    [accountQueue removeUploadTask:ufile];
}

#pragma mark - Download Tasks
- (void)addFileDownloadTask:(SeafFile * _Nonnull)dfile priority:(NSOperationQueuePriority)priority {
    if (!self.reachabilityManager.isReachable) {
        Debug(@"[SeafDataTaskManager] Network is not available. Failing download task for: %@", dfile.name);
        NSError *networkUnreachableError = [NSError errorWithDomain:NSURLErrorDomain
                                                               code:NSURLErrorNotConnectedToInternet
                                                           userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Network unavailable", @"Seafile")}];

        if ([dfile respondsToSelector:@selector(failedDownload:)]) {
            [dfile failedDownload:networkUnreachableError];
        } else if (dfile.delegate && [dfile.delegate respondsToSelector:@selector(download:failed:)]) {
            dfile.state = SEAF_DENTRY_FAILURE; 
            [dfile.delegate download:dfile failed:networkUnreachableError];
        } else {
            dfile.state = SEAF_DENTRY_FAILURE;
            Debug(@"[SeafDataTaskManager] Could not notify delegate about download failure for: %@ due to network unavailability.", dfile.name);
        }
        return;
    }

    SeafAccountTaskQueue *accountQueue = [self accountQueueForConnection:dfile.connection];
    [accountQueue addFileDownloadTask:dfile priority:priority];
    if (dfile.retryable) {
        [self saveFileToTaskStorage:dfile];
    }
}

- (void)addFileDownloadTask:(SeafFile * _Nonnull)dfile {
    [self addFileDownloadTask:dfile priority:NSOperationQueuePriorityNormal];
}

#pragma mark - Thumb Tasks

- (void)addThumbTask:(SeafThumb * _Nonnull)thumb {
    // Check network availability before adding the task
    if (!self.reachabilityManager.isReachable) {
        Debug(@"[SeafDataTaskManager] Network is not available. Failing thumb task for: %@", thumb.file.name);
        if (thumb.file) {
            // Notify SeafFile that its thumbnail download has failed.
            // This will update the file's state and inform its delegate.
            [thumb.file finishDownloadThumb:NO];
        } else {
            Debug(@"[SeafDataTaskManager] Thumb task has no associated file. Cannot mark as failed.");
        }
        return;
    }

    SeafAccountTaskQueue *accountQueue = [self accountQueueForConnection:thumb.file.connection];
    [accountQueue addThumbTask:thumb];
}

#pragma mark - Comment Image Tasks

- (NSOperation *)addCommentImageDownload:(NSString *)url
                               connection:(SeafConnection *)conn
                               completion:(void(^)(UIImage * _Nullable image, NSString * _Nonnull url))completion
{
    if (url.length == 0 || !conn) return nil;
    if (!self.reachabilityManager.isReachable) {
        Debug(@"[SeafDataTaskManager] Network unavailable for comment image %@", url);
        if (completion) completion(nil, url);
        return nil;
    }
    NSURL *u = [NSURL URLWithString:url];
    if (!u) { if (completion) completion(nil, url); return nil; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15.0];
    if (conn.authorized && conn.token.length > 0) {
        [req setValue:[NSString stringWithFormat:@"Token %@", conn.token] forHTTPHeaderField:@"Authorization"];
        [req setValue:SEAFILE_VERSION forHTTPHeaderField:@"X-Seafile-Client-Version"];
    }

    NSBlockOperation *op = [NSBlockOperation new];
    __weak NSBlockOperation *wop = op;
    [op addExecutionBlock:^{
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 15.0;
        cfg.timeoutIntervalForResource = 30.0;
        NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        __block UIImage *img = nil;
        NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (!error && data.length > 0) {
                img = [UIImage imageWithData:data];
            }
            dispatch_semaphore_signal(sema);
            [session finishTasksAndInvalidate];
        }];
        [task resume];
        // Wait until finished or cancelled
        while (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(200 * NSEC_PER_MSEC))) != 0) {
            NSBlockOperation *sop = wop;
            if (!sop || sop.isCancelled) { [task cancel]; break; }
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(img, url); });
        }
    }];

    // Enqueue into dedicated comment image queue
    SeafAccountTaskQueue *accountQueue = [self accountQueueForConnection:conn];
    [accountQueue.commentImageQueue addOperation:op];
    return op;
}

- (void)cancelAllCommentImageDownloads:(SeafConnection *)conn
{
    SeafAccountTaskQueue *q = [self accountQueueForConnection:conn];
    [q cancelAllCommentImageTasks];
    Debug(@"[SeafDataTaskManager] cancelAllCommentImageDownloads for %@, remaining ops=%lu", conn.accountIdentifier, (unsigned long)q.commentImageQueue.operationCount);
}

- (void)removeThumbTaskFromAccountQueue:(SeafThumb * _Nonnull)thumb {
    SeafAccountTaskQueue *accountQueue = [self accountQueueForConnection:thumb.file.connection];
    [accountQueue removeThumbTask:thumb];
}

#pragma mark - Account Queue Management

- (SeafAccountTaskQueue *)accountQueueForConnection:(SeafConnection *)connection
{
    @synchronized(self.accountQueueDict) {
        SeafAccountTaskQueue *accountQueue = [self.accountQueueDict objectForKey:connection.accountIdentifier];
        if (!accountQueue) {
            accountQueue = [[SeafAccountTaskQueue alloc] init];
            [self.accountQueueDict setObject:accountQueue forKey:connection.accountIdentifier];
        }
        accountQueue.conn = connection;
        return accountQueue;
    }
}

- (void)removeAccountQueue:(SeafConnection *_Nullable)conn {
    @synchronized(self.accountQueueDict) {
        SeafAccountTaskQueue *accountQueue = [self.accountQueueDict objectForKey:conn.accountIdentifier];
        if (accountQueue) {
            [accountQueue cancelAllTasks];
            [self.accountQueueDict removeObjectForKey:conn.accountIdentifier];
        }
        [self removeAccountDownloadTaskFromStorage:conn.accountIdentifier];
        [self removeAccountUploadTaskFromStorage:conn.accountIdentifier];
    }
}

#pragma mark - Task Persistence

- (void)saveUploadFileToTaskStorage:(SeafUploadFile *)ufile {
    NSString *key = [self uploadStorageKey:ufile.accountIdentifier];
    NSDictionary *dict = [self convertTaskToDict:ufile];
    @synchronized(self) {
        NSMutableDictionary *taskStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:key]];
        [taskStorage setObject:dict forKey:ufile.lpath];
        [SeafStorage.sharedObject setObject:taskStorage forKey:key];
    }
}

- (void)saveFileToTaskStorage:(SeafFile *)file {
    NSString *key = [self downloadStorageKey:file.accountIdentifier];
    NSDictionary *dict = [self convertTaskToDict:file];
    @synchronized(self) {
        NSMutableDictionary *taskStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:key]];
        [taskStorage setObject:dict forKey:file.uniqueKey];
        [SeafStorage.sharedObject setObject:taskStorage forKey:key];
    }
}

- (void)removeUploadFileTaskInStorage:(SeafUploadFile *)ufile {
    NSString *key = [self uploadStorageKey:ufile.accountIdentifier];
    @synchronized(self) {
        NSMutableDictionary *taskStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:key]];
        [taskStorage removeObjectForKey:ufile.lpath];
        [SeafStorage.sharedObject setObject:taskStorage forKey:key];
    }
}


- (NSString *)downloadStorageKey:(NSString *)accountIdentifier {
    return [NSString stringWithFormat:@"%@/%@", KEY_DOWNLOAD, accountIdentifier];
}

- (NSString *)uploadStorageKey:(NSString *)accountIdentifier {
    return [NSString stringWithFormat:@"%@/%@", KEY_UPLOAD, accountIdentifier];
}

- (NSMutableDictionary *)convertTaskToDict:(id)task {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if ([task isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)task;
        [Utils dict:dict setObject:file.oid forKey:@"oid"];
        [Utils dict:dict setObject:file.repoId forKey:@"repoId"];
        [Utils dict:dict setObject:file.name forKey:@"name"];
        [Utils dict:dict setObject:file.path forKey:@"path"];
        [Utils dict:dict setObject:[NSNumber numberWithLongLong:file.mtime] forKey:@"mtime"];
        [Utils dict:dict setObject:[NSNumber numberWithLongLong:file.filesize] forKey:@"size"];
    } else if ([task isKindOfClass:[SeafUploadFile class]]) {
        SeafUploadFile *ufile = (SeafUploadFile *)task;
        [Utils dict:dict setObject:ufile.lpath forKey:@"lpath"];
        [Utils dict:dict setObject:[NSNumber numberWithBool:ufile.overwrite] forKey:@"overwrite"];
        [Utils dict:dict setObject:ufile.udir.oid forKey:@"oid"];
        [Utils dict:dict setObject:ufile.udir.repoId forKey:@"repoId"];
        [Utils dict:dict setObject:ufile.udir.name forKey:@"name"];
        [Utils dict:dict setObject:ufile.udir.path forKey:@"path"];
        [Utils dict:dict setObject:ufile.udir.perm forKey:@"perm"];
        [Utils dict:dict setObject:ufile.udir.mime forKey:@"mime"];
        if (ufile.lastModified) {
            [Utils dict:dict setObject:ufile.lastModified forKey:@"lastModified"];
        }
        if (ufile.isEditedFile) {
            [Utils dict:dict setObject:[NSNumber numberWithBool:ufile.isEditedFile] forKey:@"isEditedFile"];
            [Utils dict:dict setObject:ufile.editedFilePath forKey:@"editedFilePath"];
            [Utils dict:dict setObject:ufile.editedFileRepoId forKey:@"editedFileRepoId"];
            [Utils dict:dict setObject:ufile.editedFileOid forKey:@"editedFileOid"];
        }
        [Utils dict:dict setObject:[NSNumber numberWithBool:ufile.model.uploaded] forKey:@"uploaded"];
    }
    return dict;
}

#pragma mark - Starting Unfinished Tasks

- (void)startLastTimeUnfinshTaskWithConnection:(SeafConnection *)conn {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),^{
        [self p_startLastTimeUnfinshTaskWithConnection:conn];
    });
}

- (void)p_startLastTimeUnfinshTaskWithConnection:(SeafConnection *)conn {
    NSString *downloadKey = [self downloadStorageKey:conn.accountIdentifier];
    NSDictionary *downloadTasks = [SeafStorage.sharedObject objectForKey:downloadKey];
    if (downloadTasks.allValues.count > 0) {
        for (NSDictionary *dict in downloadTasks.allValues) {
            SeafFile *file = [[SeafFile alloc] initWithConnection:conn oid:[dict objectForKey:@"oid"] repoId:[dict objectForKey:@"repoId"] name:[dict objectForKey:@"name"] path:[dict objectForKey:@"path"] mtime:[[dict objectForKey:@"mtime"] longLongValue] size:[[dict objectForKey:@"size"] longLongValue]];
            [self addFileDownloadTask:file];
        }
    }
    
    NSString *uploadKey = [self uploadStorageKey:conn.accountIdentifier];
    NSMutableDictionary *uploadTasks = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:uploadKey]];
    NSMutableArray *toDelete = [NSMutableArray new];
    NSTimeInterval t1 = [NSDate date].timeIntervalSince1970;
    for (NSString *key in uploadTasks) {
        NSDictionary *dict = [uploadTasks objectForKey:key];
        NSString *lpath = [dict objectForKey:@"lpath"];
        if (![Utils fileExistsAtPath:lpath]) {
            [toDelete addObject:key];
            continue;
        }
        SeafUploadFile *ufile = [[SeafUploadFile alloc] initWithPath:lpath];
        id modDate = [dict objectForKey:@"lastModified"];
        if (modDate && [modDate isKindOfClass:[NSDate class]]) {
            ufile.lastModified = (NSDate *)modDate;
        }
        if ([[dict objectForKey:@"uploaded"] boolValue]) {
            [ufile cleanup];
            [toDelete addObject:key];
            continue;
        }
        ufile.model.overwrite = [[dict objectForKey:@"overwrite"] boolValue];
        SeafDir *udir = [[SeafDir alloc] initWithConnection:conn oid:[dict objectForKey:@"oid"] repoId:[dict objectForKey:@"repoId"] perm:[dict objectForKey:@"perm"] name:[dict objectForKey:@"name"] path:[dict objectForKey:@"path"] mime:[dict objectForKey:@"mime"] mtime:[[dict objectForKey:@"mtime"] integerValue:0]];
        ufile.udir = udir;
        
        NSNumber *isEditedFileNumber = [dict objectForKey:@"isEditedFile"];
        BOOL isEditedUploadFile = NO;
        if (isEditedFileNumber != nil && [isEditedFileNumber isKindOfClass:[NSNumber class]]) {
            isEditedUploadFile = [isEditedFileNumber boolValue];
        }
        
        if (isEditedUploadFile) {
            ufile.model.isEditedFile = YES;
            ufile.model.editedFilePath = [dict objectForKey:@"editedFilePath"];
            ufile.model.editedFileRepoId = [dict objectForKey:@"editedFileRepoId"];
            ufile.model.editedFileOid = [dict objectForKey:@"editedFileOid"];
        }
        [self addUploadTask:ufile];
    }
    NSTimeInterval t2 = [NSDate date].timeIntervalSince1970;
    Debug("restart uplaod task time cost: %f", (t2 - t1));
    if (toDelete.count > 0) {
        for (NSString *key in toDelete) {
            [uploadTasks removeObjectForKey:key];
        }
        [SeafStorage.sharedObject setObject:uploadTasks forKey:uploadKey];
    }
}

#pragma mark - Canceling Tasks
- (void)cancelAllDownloadTasks:(SeafConnection * _Nonnull)conn {
    SeafAccountTaskQueue *accountQueue = [self accountQueueForConnection:conn];
    [accountQueue cancelAllDownloadTasks];
    [self removeAccountDownloadTaskFromStorage:conn.accountIdentifier];
}

// Cancel the task and clear the cache
- (void)cancelAllUploadTasks:(SeafConnection * _Nonnull)conn {
    SeafAccountTaskQueue *accountQueue = [self accountQueueForConnection:conn];
    [accountQueue cancelAllUploadTasks];
    [self removeAccountUploadTaskFromStorage:conn.accountIdentifier];
}

#pragma mark - Helper Methods

- (void)removeAccountDownloadTaskFromStorage:(NSString *)accountIdentifier {
    NSString *key = [self downloadStorageKey:accountIdentifier];
    [SeafStorage.sharedObject removeObjectForKey:key];
}

- (void)removeAccountUploadTaskFromStorage:(NSString *)accountIdentifier {
    NSString *key = [self uploadStorageKey:accountIdentifier];
    [SeafStorage.sharedObject removeObjectForKey:key];
}

- (NSArray * _Nullable)getUploadTasksInDir:(SeafDir *)dir connection:(SeafConnection * _Nonnull)connection {
    SeafAccountTaskQueue *accountQueue = [self accountQueueForConnection:connection];
    return [accountQueue getUploadTasksInDir:dir];
}

// Get the queue status from the connection
- (NSArray *)getOngoingUploadTasksFromConnection: (SeafConnection *)connection {
    SeafAccountTaskQueue *accountQueue = [self accountQueueForConnection:connection];
    NSMutableArray *ongoingTasks = [NSMutableArray array];
    for (SeafUploadOperation *operation in accountQueue.uploadQueue.operations) {
        if (operation.isExecuting && !operation.isFinished) {
            [ongoingTasks addObject:operation.uploadFile];
        }
    }
    return ongoingTasks;
}

// get the on going download tasks
- (NSArray *)getOngoingDownloadTasks: (SeafConnection *)connection {
    SeafAccountTaskQueue *accountQueue = [self accountQueueForConnection:connection];
    NSMutableArray *ongoingTasks = [NSMutableArray array];
    for (SeafDownloadOperation *operation in accountQueue.downloadQueue.operations) {
        if (operation.isExecuting && !operation.isFinished) {
            [ongoingTasks addObject:operation.file];
        }
    }
    return ongoingTasks;
}

// Get completed upload tasks
- (NSArray *)getCompletedUploadTasks: (SeafConnection *)connection {
    SeafAccountTaskQueue *accountQueue = [self accountQueueForConnection:connection];
    NSMutableArray *completedTasks = [NSMutableArray array];
    for (SeafUploadOperation *operation in accountQueue.uploadQueue.operations) {
        if (operation.isFinished && !operation.isCancelled) {
            [completedTasks addObject:operation.uploadFile];
        }
    }
    return completedTasks;
}

// Get completed download tasks
- (NSArray *)getCompletedDownloadTasks: (SeafConnection *)connection {
    SeafAccountTaskQueue *accountQueue = [self accountQueueForConnection:connection];
    NSMutableArray *completedTasks = [NSMutableArray array];
    for (SeafDownloadOperation *operation in accountQueue.downloadQueue.operations) {
        if (operation.isFinished && !operation.isCancelled) {
            [completedTasks addObject:operation.file];
        }
    }
    return completedTasks;
}

#pragma mark - Network status monitoring

- (void)setupNetworkMonitoring {
    self.reachabilityManager = [AFNetworkReachabilityManager sharedManager];
    
    __weak typeof(self) weakSelf = self;
    [self.reachabilityManager setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        switch (status) {
            case AFNetworkReachabilityStatusNotReachable:
                Debug(@"Network is unavailable.");
                [strongSelf handleNetworkUnavailable];
                break;
            case AFNetworkReachabilityStatusReachableViaWiFi:
            case AFNetworkReachabilityStatusReachableViaWWAN:
                Debug(@"Network is available.");
                [strongSelf handleNetworkAvailable];
                break;
            case AFNetworkReachabilityStatusUnknown:
            default:
                Debug(@"Unknown network status.");
                break;
        }
    }];

    // start network monitor
    [self.reachabilityManager startMonitoring];
}

#pragma mark - Network status handling

- (void)handleNetworkUnavailable {
    @synchronized (self.accountQueueDict) {
        for (SeafAccountTaskQueue *queue in self.accountQueueDict.allValues) {
            [queue pauseAllTasks];
        }
    }
}

- (void)handleNetworkAvailable {
    @synchronized (self.accountQueueDict) {
        for (SeafAccountTaskQueue *queue in self.accountQueueDict.allValues) {
            [queue resumeAllTasks];
        }
    }
}

- (void)addUploadTasksInBatch:(NSArray<SeafUploadFile *> *)tasks forConnection:(SeafConnection *)conn {
    if (tasks.count == 0) {
        return;
    }
    
    SeafAccountTaskQueue *accountQueue = [self accountQueueForConnection:conn];
    [accountQueue addUploadTasksInBatch:tasks];

    // Store tasks that can be retried
    for (SeafUploadFile *file in tasks) {
        if (file.retryable) {
            [self saveUploadFileToTaskStorage:file];
        }
    }
}

@end
