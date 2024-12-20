//
//  SeafBackgroundTaskManager.m
//  Pods
//
//  Created by Wei W on 4/9/17.
//
//

#import "SeafDataTaskManager.h"
#import "SeafDir.h"
#import "Debug.h"
#import "SeafFile.h"
#import "SeafStorage.h"

#define KEY_UPLOAD @"allUploadingTasks"
#define KEY_DOWNLOAD @"allDownloadingTasks"
#define KEY_UPLOADED @"allUploadedTasks"

@interface SeafDataTaskManager()

@property (nonatomic, strong) NSTimer *taskTimer;
@property NSUserDefaults *storage;
@property (nonatomic, strong) NSMutableDictionary *accountQueueDict;

@end

@implementation SeafDataTaskManager

+ (SeafDataTaskManager *)sharedObject
{
    static SeafDataTaskManager *object = nil;
    if (!object) {
        object = [SeafDataTaskManager new];
    }
    return object;
}

- (id)init
{
    if (self = [super init]) {
        _accountQueueDict = [NSMutableDictionary new];
        _finishBlock = nil;
        [self startTimer];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    }
    return self;
}

/**
 * Starts a timer to periodically execute background tasks.
 */
- (void)startTimer
{
    Debug("Start timer.");
    self.taskTimer = [NSTimer scheduledTimerWithTimeInterval:1*60 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        [self tick:nil];
    }];
}

/**
 * A method called by the timer at regular intervals.
 * @param userInfo Additional user information that can be passed into the timer.
 */
- (void)tick:(id)userInfo {
    if (![[AFNetworkReachabilityManager sharedManager] isReachable]) {
        return;
    }
    Debug("tick...");
    for (SeafAccountTaskQueue *accountQueue in self.accountQueueDict.allValues) {
        [accountQueue tick];
    }
}

#pragma mark- upload
- (BOOL)addUploadTask:(SeafUploadFile *)file {
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:file.accountIdentifier];
    BOOL res = [accountQueue addUploadTask:file];
    if (res && file.retryable) {
        [self saveUploadFileToTaskStorage:file];
    }
    if (self.trySyncBlock) {
        self.trySyncBlock(file);
    }
    return res;
}

- (void)removeUploadTask:(SeafUploadFile * _Nonnull)ufile forAccount:(SeafConnection * _Nonnull)conn
{
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:conn.accountIdentifier];
    [accountQueue removeUploadTask:ufile];
}

- (void)cancelAutoSyncTasks:(SeafConnection *)conn
{
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:conn.accountIdentifier];
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    @synchronized (accountQueue.uploadQueue.allTasks) {
        for (SeafUploadFile *ufile in accountQueue.uploadQueue.allTasks) {
            if (ufile.uploadFileAutoSync && ufile.udir->connection == conn) {
                [arr addObject:ufile];
            }
        }
        for (SeafUploadFile *ufile in arr) {
            [accountQueue.uploadQueue removeTask:ufile];
        }
    }
    Debug("clear %ld photos", (long)arr.count);
    for (SeafUploadFile *ufile in arr) {
        [ufile cancel];
    }
}

- (void)cancelAutoSyncVideoTasks:(SeafConnection *)conn
{
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:conn.accountIdentifier];
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    @synchronized (accountQueue.uploadQueue.allTasks) {
        for (SeafUploadFile *ufile in accountQueue.uploadQueue.allTasks) {
            if (ufile.uploadFileAutoSync && ufile.udir->connection == conn && !ufile.isImageFile) {
                [arr addObject:ufile];
            }
        }
        for (SeafUploadFile *ufile in arr) {
            [accountQueue.uploadQueue removeTask:ufile];
        }
    }
    for (SeafUploadFile *ufile in arr) {
        Debug("Remove autosync video file: %@, %@", ufile.lpath, ufile.assetURL);
        [ufile cancel];
    }
}

- (void)cancelAllDownloadTasks:(SeafConnection * _Nonnull)conn
{
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:conn.accountIdentifier];
    [accountQueue.fileQueue clearTasks];
    [self removeAccountDownloadTaskFromStorage:conn.accountIdentifier];
}

- (void)cancelAllUploadTasks:(SeafConnection * _Nonnull)conn
{
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:conn.accountIdentifier];
    [accountQueue.uploadQueue clearTasks];
    [self removeAccountUploadTaskFromStorage:conn.accountIdentifier];//remove the current account all uploadFile info from storage
}

- (void)noException:(void (^)(void))block
{
    @try {
        block();
    }
    @catch (NSException *exception) {
        Warning("Failed to run block:%@", block);
    } @finally {
    }

}

#pragma mark- download file
- (void)addFileDownloadTask:(SeafFile * _Nonnull)dfile {
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:dfile.accountIdentifier];
    [accountQueue addFileDownloadTask:dfile];
    if (dfile.retryable) {
        [self saveFileToTaskStorage:dfile];
    }
    if (self.trySyncBlock) {
        self.trySyncBlock(dfile);
    }
}

- (void)addAvatarTask:(SeafAvatar * _Nonnull)avatar
{
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:avatar.accountIdentifier];
    [accountQueue addAvatarTask:avatar];
}
- (void)addThumbTask:(SeafThumb * _Nonnull)thumb
{
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:thumb.accountIdentifier];
    [accountQueue addThumbTask:thumb];
}

- (void)removeThumbTaskFromAccountQueue:(SeafThumb * _Nonnull)thumb
{
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:thumb.accountIdentifier];
    [accountQueue removeThumbTask:thumb];
}

/**
 * Retrieves an account task queue associated with a specific identifier.
 * @param identifier The identifier associated with the account.
 * @return An instance of SeafAccountTaskQueue associated with the given identifier.
 */
- (SeafAccountTaskQueue *)getAccountQueueWithIndentifier:(NSString *)identifier
{
    @synchronized(self.accountQueueDict) {
        SeafAccountTaskQueue *accountQueue = [self.accountQueueDict valueForKey:identifier];
        if (!accountQueue) {
            accountQueue = [[SeafAccountTaskQueue alloc] init];

            __weak typeof(self) weakSelf = self;
            accountQueue.uploadQueue.taskCompleteBlock = ^(id<SeafTask>  _Nonnull task, BOOL result) {
                if (weakSelf.finishBlock)  weakSelf.finishBlock(task);
                SeafUploadFile *ufile = (SeafUploadFile*)task;
                if (result) {
                    if (ufile.retryable) { // Do not remove now, will remove it next time
                        [weakSelf saveUploadFileToTaskStorage:ufile];
                    }
                } else if (!ufile.retryable) {
                    // Remove upload file local cache
                    [ufile cleanup];
                }
            };
            accountQueue.fileQueue.taskCompleteBlock = ^(id<SeafTask>  _Nonnull task, BOOL result) {
                if (weakSelf.finishBlock)  weakSelf.finishBlock(task);
                SeafFile *file = (SeafFile*)task;
                if (result) {
                    [weakSelf removeFileTaskInStorage:file];
                }
            };

            [self.accountQueueDict setObject:accountQueue forKey:identifier];
        }
        return accountQueue;
    }
}

- (SeafAccountTaskQueue *)accountQueueForConnection:(SeafConnection *)connection
{
    return [self getAccountQueueWithIndentifier:connection.accountIdentifier];
}

/**
 * Saves information about an upload file task to persistent storage.
 * @param ufile The upload file whose information is to be saved.
 */
- (void)saveUploadFileToTaskStorage:(SeafUploadFile *)ufile {
    NSString *key = [self uploadStorageKey:ufile.accountIdentifier];
    NSDictionary *dict = [self convertTaskToDict:ufile];
    @synchronized(self) {
        NSMutableDictionary *taskStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:key]];
        [taskStorage setObject:dict forKey:ufile.lpath];
        [SeafStorage.sharedObject setObject:taskStorage forKey:key];
    }
}

/**
 * Saves information about a file download task to persistent storage.
 * @param file The file whose information is to be saved.
 */
- (void)saveFileToTaskStorage:(SeafFile *)file {
    NSString *key = [self downloadStorageKey:file.accountIdentifier];
    NSDictionary *dict = [self convertTaskToDict:file];
    @synchronized(self) {
        NSMutableDictionary *taskStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:key]];
        [taskStorage setObject:dict forKey:file.uniqueKey];
        [SeafStorage.sharedObject setObject:taskStorage forKey:key];
    }
}

/**
 * Removes information about an upload file task from persistent storage.
 * @param ufile The upload file whose information is to be removed.
 */
- (void)removeUploadFileTaskInStorage:(SeafUploadFile *)ufile {
    NSString *key = [self uploadStorageKey:ufile.accountIdentifier];
    
    @synchronized(self) {
        NSMutableDictionary *taskStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:key]];
        [taskStorage removeObjectForKey:ufile.lpath];
        [SeafStorage.sharedObject setObject:taskStorage forKey:key];
    }
}

/**
 * Removes information about a file download task from persistent storage.
 * @param file The file whose information is to be removed.
 */
- (void)removeFileTaskInStorage:(SeafFile *)file {
    NSString *key = [self downloadStorageKey:file.accountIdentifier];
    
    @synchronized(self) {
        NSMutableDictionary *taskStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:key]];
        [taskStorage removeObjectForKey:file.uniqueKey];
        [SeafStorage.sharedObject setObject:taskStorage forKey:key];
    }
}

/**
 * Retrieves the storage key for file download tasks associated with a specific account.
 * @param accountIdentifier The identifier for the account.
 * @return A string representing the storage key for download tasks.
 */
- (NSString*)downloadStorageKey:(NSString*)accountIdentifier {
    return [NSString stringWithFormat:@"%@/%@",KEY_DOWNLOAD,accountIdentifier];
}

/**
 * Retrieves the storage key for file upload tasks associated with a specific account.
 * @param accountIdentifier The identifier for the account.
 * @return A string representing the storage key for upload tasks.
 */
- (NSString*)uploadStorageKey:(NSString*)accountIdentifier {
     return [NSString stringWithFormat:@"%@/%@",KEY_UPLOAD,accountIdentifier];
}

/**
 * Converts a task object into a dictionary representation for storage.
 * @param task The task to be converted.
 * @return A dictionary representation of the task.
 */
- (NSMutableDictionary*)convertTaskToDict:(id)task {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if ([task isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile*)task;
        [Utils dict:dict setObject:file.oid forKey:@"oid"];
        [Utils dict:dict setObject:file.repoId forKey:@"repoId"];
        [Utils dict:dict setObject:file.name forKey:@"name"];
        [Utils dict:dict setObject:file.path forKey:@"path"];
        [Utils dict:dict setObject:[NSNumber numberWithLongLong:file.mtime] forKey:@"mtime"];
        [Utils dict:dict setObject:[NSNumber numberWithLongLong:file.filesize] forKey:@"size"];
    } else if ([task isKindOfClass:[SeafUploadFile class]]) {
        SeafUploadFile *ufile = (SeafUploadFile*)task;
        [Utils dict:dict setObject:ufile.lpath forKey:@"lpath"];
        [Utils dict:dict setObject:[NSNumber numberWithBool:ufile.overwrite] forKey:@"overwrite"];
        [Utils dict:dict setObject:ufile.udir.oid forKey:@"oid"];
        [Utils dict:dict setObject:ufile.udir.repoId forKey:@"repoId"];
        [Utils dict:dict setObject:ufile.udir.name forKey:@"name"];
        [Utils dict:dict setObject:ufile.udir.path forKey:@"path"];
        [Utils dict:dict setObject:ufile.udir.perm forKey:@"perm"];
        [Utils dict:dict setObject:ufile.udir.mime forKey:@"mime"];
        if (ufile.isEditedFile) {
            [Utils dict:dict setObject:[NSNumber numberWithBool:ufile.isEditedFile] forKey:@"isEditedFile"];
            [Utils dict:dict setObject:ufile.editedFilePath forKey:@"editedFilePath"];
            [Utils dict:dict setObject:ufile.editedFileRepoId forKey:@"editedFileRepoId"];
            [Utils dict:dict setObject:ufile.editedFileOid forKey:@"editedFileOid"];
        }

        [Utils dict:dict setObject:[NSNumber numberWithBool:ufile.isUploaded] forKey:@"uploaded"];
    }
    return dict;
}

/**
 * Starts any unfinished tasks from the last session associated with a specific connection.
 * @param conn The connection whose tasks are to be started.
 */
- (void)startLastTimeUnfinshTaskWithConnection:(SeafConnection *)conn {
    NSString *downloadKey = [self downloadStorageKey:conn.accountIdentifier];
    NSDictionary *downloadTasks = [SeafStorage.sharedObject objectForKey:downloadKey];
    if (downloadTasks.allValues.count > 0) {
        for (NSDictionary *dict in downloadTasks.allValues) {
            NSNumber *mtimeNumber = [dict objectForKey:@"mtime"];

            NSString *oid = [Utils getNewOidFromMtime:[mtimeNumber longLongValue] repoId:[dict objectForKey:@"repoId"] path:[dict objectForKey:@"path"]];
                        
            SeafFile *file = [[SeafFile alloc] initWithConnection:conn oid:oid repoId:[dict objectForKey:@"repoId"] name:[dict objectForKey:@"name"] path:[dict objectForKey:@"path"] mtime:[[dict objectForKey:@"mtime"] longLongValue] size:[[dict objectForKey:@"size"] longLongValue]];
            [self addFileDownloadTask:file];
        }
    }
    
    NSString *uploadKey = [self uploadStorageKey:conn.accountIdentifier];
    NSMutableDictionary *uploadTasks = [NSMutableDictionary dictionaryWithDictionary: [SeafStorage.sharedObject objectForKey:uploadKey]];
    NSMutableArray *toDelete = [NSMutableArray new];
    for (NSString *key in uploadTasks) {
        NSDictionary *dict = [uploadTasks objectForKey:key];
        NSString *lpath = [dict objectForKey:@"lpath"];
        if (![Utils fileExistsAtPath:lpath]) {
            [toDelete addObject:key];
            continue;
        }
        SeafUploadFile *ufile = [[SeafUploadFile alloc] initWithPath:lpath];
        if ([[dict objectForKey:@"uploaded"] boolValue]) {
            [ufile cleanup];
            [toDelete addObject:key];
            continue;
        }
        ufile.overwrite = [[dict objectForKey:@"overwrite"] boolValue];
        SeafDir *udir = [[SeafDir alloc] initWithConnection:conn oid:[dict objectForKey:@"oid"] repoId:[dict objectForKey:@"repoId"] perm:[dict objectForKey:@"perm"] name:[dict objectForKey:@"name"] path:[dict objectForKey:@"path"] mime:[dict objectForKey:@"mime"]];
        ufile.udir = udir;
        
        NSNumber *isEditedFileNumber = [dict objectForKey:@"isEditedFile"];
        BOOL isEditedUploadFile = NO;
        if (isEditedFileNumber != nil && [isEditedFileNumber isKindOfClass:[NSNumber class]]) {
            isEditedUploadFile = [isEditedFileNumber boolValue];
        }
        
        if (isEditedUploadFile) {
            ufile.isEditedFile = YES;
            ufile.editedFilePath = [dict objectForKey:@"editedFilePath"];
            ufile.editedFileRepoId = [dict objectForKey:@"editedFileRepoId"];
            ufile.editedFileOid = [dict objectForKey:@"editedFileOid"];
        }
        [self addUploadTask:ufile];
    }
    if (toDelete.count > 0) {
        for (NSString *key in toDelete) {
            [uploadTasks removeObjectForKey:key];
        }
        [SeafStorage.sharedObject setObject:uploadTasks forKey:uploadKey];
    }
}

/**
 * Removes all tasks associated with a specific account queue.
 * @param conn The connection whose task queue is to be removed.
 */
- (void)removeAccountQueue:(SeafConnection *_Nullable)conn {
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:conn.accountIdentifier];
    [accountQueue clearTasks];
    [self removeAccountDownloadTaskFromStorage:conn.accountIdentifier];
    [self removeAccountUploadTaskFromStorage:conn.accountIdentifier];
}

/**
 * Retrieves all upload tasks that are within a specific directory.
 * @param dir The directory within which the upload tasks are to be retrieved.
 * @return An array containing all the upload tasks within the specified directory.
 */
- (NSArray *)getUploadTasksInDir:(SeafDir *)dir {
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:dir->connection.accountIdentifier];
    NSMutableArray *filesInDir = [NSMutableArray new];
    for (SeafUploadFile *ufile in accountQueue.uploadQueue.allTasks) {
        //Check if the uploaded file belongs to the current folder.
        if (!ufile.isEditedFile && [ufile.udir.repoId isEqualToString: dir.repoId] && [ufile.udir.path isEqualToString: dir.path]) {
            [filesInDir addObject:ufile];
        }
    }

    return filesInDir;
}

/**
 * Removes all download tasks associated with a specific account from storage.
 * @param accountIdentifier The identifier of the account whose download tasks are to be removed.
 */
- (void)removeAccountDownloadTaskFromStorage:(NSString *)accountIdentifier {
    NSString *key = [self downloadStorageKey:accountIdentifier];
    [SeafStorage.sharedObject removeObjectForKey:key];
}

/**
 * Removes all upload tasks associated with a specific account from storage.
 * @param accountIdentifier The identifier of the account whose upload tasks are to be removed.
 */
- (void)removeAccountUploadTaskFromStorage:(NSString *)accountIdentifier {
    NSString *key = [self uploadStorageKey:accountIdentifier];
    [SeafStorage.sharedObject removeObjectForKey:key];
}

- (void)applicationWillEnterForeground:(NSNotification *)notif {
    [self.taskTimer invalidate];
    self.taskTimer = nil;
    self.taskTimer = [NSTimer scheduledTimerWithTimeInterval:1*60 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

#pragma mark- SeafAccountTaskQueue

@implementation SeafAccountTaskQueue

- (instancetype)init {
    self = [super init];
    if (self) {
        self.fileQueue = [[SeafTaskQueue alloc] init];
        self.thumbQueue = [[SeafTaskQueue alloc] init];
        self.avatarQueue = [[SeafTaskQueue alloc] init];
        self.uploadQueue = [[SeafTaskQueue alloc] init];
        self.uploadQueue.attemptInterval = 180;
    }
    return self;
}

- (void)addFileDownloadTask:(SeafFile * _Nonnull)dfile {
    [self.fileQueue addTask:dfile];
}

- (void)addThumbTask:(SeafThumb * _Nonnull)thumb {
    [self.thumbQueue addTask:thumb];
}

- (void)addAvatarTask:(SeafAvatar * _Nonnull)avatar {
    [self.avatarQueue addTask:avatar];
}

- (BOOL)addUploadTask:(SeafUploadFile * _Nonnull)ufile {
    return [self.uploadQueue addTask:ufile];
}

- (void)removeFileDownloadTask:(SeafFile * _Nonnull)dfile {
    [self.fileQueue removeTask:dfile];
}
- (void)removeUploadTask:(SeafUploadFile * _Nonnull)ufile {
    [self.uploadQueue removeTask:ufile];
}
- (void)removeAvatarTask:(SeafAvatar * _Nonnull)avatar {
    [self.avatarQueue removeTask:avatar];
}
- (void)removeThumbTask:(SeafThumb * _Nonnull)thumb {
    [self.thumbQueue removeTask:thumb];
}

- (void)tick {
    [self.fileQueue tick];
    [self.thumbQueue tick];
    [self.avatarQueue tick];
    [self.uploadQueue tick];
}

- (void)clearTasks {
    [self.fileQueue clearTasks];
    [self.thumbQueue clearTasks];
    [self.avatarQueue clearTasks];
    [self.uploadQueue clearTasks];
}

@end
