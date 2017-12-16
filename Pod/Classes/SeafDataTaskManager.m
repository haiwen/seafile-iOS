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

#define KEY_UPLOAD @"allUploadTask"
#define KEY_DOWNLOAD @"allDownloadTask"

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
        _assetsLibrary = [[ALAssetsLibrary alloc] init];
        _accountQueueDict = [NSMutableDictionary new];
        _finishBlock = nil;
        [self startTimer];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cacheCleared:) name:@"clearCache" object:nil];
    }
    return self;
}

- (void)startTimer
{
    Debug("Start timer.");
    self.taskTimer = [NSTimer scheduledTimerWithTimeInterval:5*60 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        [self tick:nil];
    }];
}

- (void)tick:(id)userInfo {
    if (![[AFNetworkReachabilityManager sharedManager] isReachable]) {
        return;
    }
    for (SeafAccountTaskQueue *accountQueue in self.accountQueueDict.allValues) {
        [accountQueue tick];
    }
}

#pragma mark- upload
- (void)addUploadTask:(SeafUploadFile *)file {
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:file.accountIdentifier];
    [accountQueue addUploadTask:file];
    if (file.retryable) {
        [self saveUploadFileToTaskStorage:file];
    }
    if (self.trySyncBlock) {
        self.trySyncBlock(file);
    }
}

- (void)cancelAutoSyncTasks:(SeafConnection *)conn
{
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:conn.accountIdentifier];
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    @synchronized (accountQueue.uploadQueue.allTasks) {
        for (SeafUploadFile *ufile in accountQueue.uploadQueue.allTasks) {
            if (ufile.autoSync && ufile.udir->connection == conn) {
                [arr addObject:ufile];
            }
        }
        for (SeafUploadFile *ufile in arr) {
            [accountQueue.uploadQueue removeTask:ufile];
        }
    }
    Debug("clear %ld photos", (long)arr.count);
    for (SeafUploadFile *ufile in arr) {
        [conn removeUploadfile:ufile];
    }
}

- (void)cancelAutoSyncVideoTasks:(SeafConnection *)conn
{
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:conn.accountIdentifier];
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    @synchronized (accountQueue.uploadQueue.allTasks) {
        for (SeafUploadFile *ufile in accountQueue.uploadQueue.allTasks) {
            if (ufile.autoSync && ufile.udir->connection == conn && !ufile.isImageFile) {
                [arr addObject:ufile];
            }
        }
        for (SeafUploadFile *ufile in arr) {
            [accountQueue.uploadQueue removeTask:ufile];
        }
    }
    for (SeafUploadFile *ufile in arr) {
        Debug("Remove autosync video file: %@, %@", ufile.lpath, ufile.assetURL);
        [conn removeUploadfile:ufile];
    }
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

- (void)assetForURL:(NSURL *)assetURL resultBlock:(ALAssetsLibraryAssetForURLResultBlock)resultBlock failureBlock:(ALAssetsLibraryAccessFailureBlock)failureBlock
{
    [self.assetsLibrary assetForURL:assetURL
                        resultBlock:^(ALAsset *asset) {
                            // Success #1
                            if (asset){
                                [self noException:^{
                                    resultBlock(asset);
                                }];
                                // No luck, try another way
                            } else {
                                // Search in the Photo Stream Album
                                [self.assetsLibrary enumerateGroupsWithTypes:ALAssetsGroupPhotoStream
                                                                  usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
                                                                      [group enumerateAssetsWithOptions:NSEnumerationReverse usingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
                                                                          if([result.defaultRepresentation.url isEqual:assetURL]) {
                                                                              [self noException:^{
                                                                                  resultBlock(asset);
                                                                              }];
                                                                              *stop = YES;
                                                                          }
                                                                      }];
                                                                  }
                                                                failureBlock:^(NSError *error) {
                                                                    [self noException:^{
                                                                        failureBlock(error);
                                                                    }];
                                                                }];
                            }
                        } failureBlock:^(NSError *error) {
                            [self noException:^{
                                failureBlock(error);
                            }];
                        }];
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
                    [weakSelf removeUploadFileTaskInStorage:ufile];
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

- (void)cacheCleared:(NSNotification*)notification {
    for (SeafAccountTaskQueue *accountQueue in self.accountQueueDict.allValues) {
        [accountQueue clearTasks];
    }
}

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

- (void)removeFileTaskInStorage:(SeafFile *)file {
    NSString *key = [self downloadStorageKey:file.accountIdentifier];
    
    @synchronized(self) {
        NSMutableDictionary *taskStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:key]];
        [taskStorage removeObjectForKey:file.uniqueKey];
        [SeafStorage.sharedObject setObject:taskStorage forKey:key];
    }
}

- (NSMutableDictionary *)uploadFileInfoInStorage:(SeafUploadFile *)ufile {
    if (ufile.udir) {
        NSString *key = [self uploadStorageKey:ufile.accountIdentifier];
        NSMutableDictionary *taskStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:key]];
        return [taskStorage objectForKey:ufile.lpath];
    } else {
        return nil;
    }
    
}

- (NSString*)downloadStorageKey:(NSString*)accountIdentifier {
    return [NSString stringWithFormat:@"%@/%@",KEY_DOWNLOAD,accountIdentifier];
}

- (NSString*)uploadStorageKey:(NSString*)accountIdentifier {
     return [NSString stringWithFormat:@"%@/%@",KEY_UPLOAD,accountIdentifier];
}

- (NSMutableDictionary*)convertTaskToDict:(id)task {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if ([task isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile*)task;
        [Utils dict:dict setObject:file.uniqueKey forKey:@"uniqueKey"];
        [Utils dict:dict setObject:file.oid forKey:@"oid"];
        [Utils dict:dict setObject:file.repoId forKey:@"repoId"];
        [Utils dict:dict setObject:file.name forKey:@"name"];
        [Utils dict:dict setObject:file.path forKey:@"path"];
        [Utils dict:dict setObject:[NSNumber numberWithLongLong:file.mtime] forKey:@"mtime"];
        [Utils dict:dict setObject:[NSNumber numberWithLongLong:file.filesize] forKey:@"size"];
    } else if ([task isKindOfClass:[SeafUploadFile class]]) {
        SeafUploadFile *ufile = (SeafUploadFile*)task;
        [Utils dict:dict setObject:ufile.lpath forKey:@"lpath"];
        [Utils dict:dict setObject:[NSNumber numberWithBool:ufile.overwrite] forKey:@"update"];
        [Utils dict:dict setObject:ufile.udir.oid forKey:@"oid"];
        [Utils dict:dict setObject:ufile.udir.repoId forKey:@"repoId"];
        [Utils dict:dict setObject:ufile.udir.name forKey:@"name"];
        [Utils dict:dict setObject:ufile.udir.path forKey:@"path"];
        [Utils dict:dict setObject:ufile.udir.perm forKey:@"perm"];
        [Utils dict:dict setObject:ufile.udir.mime forKey:@"mime"];
    }
    return dict;
}

- (void)startLastTimeUnfinshTaskWithConnection:(SeafConnection *)conn {
    NSString *downloadKey = [self downloadStorageKey:conn.accountIdentifier];
    NSDictionary *downloadTasks = [SeafStorage.sharedObject objectForKey:downloadKey];
    if (downloadTasks.allValues.count > 0) {
        for (NSDictionary *dict in downloadTasks.allValues) {
            SeafFile *file = [[SeafFile alloc] initWithConnection:conn oid:[dict objectForKey:@"oid"] repoId:[dict objectForKey:@"repoId"] name:[dict objectForKey:@"name"] path:[dict objectForKey:@"path"] mtime:[[dict objectForKey:@"mtime"] longLongValue] size:[[dict objectForKey:@"size"] longLongValue]];
            [self addFileDownloadTask:file];
        }
    }
    
    NSString *uploadKey = [self uploadStorageKey:conn.accountIdentifier];
    NSDictionary *uploadTasks = [SeafStorage.sharedObject objectForKey:uploadKey];
    if (uploadTasks.allValues.count > 0) {
        for (NSDictionary *dict in uploadTasks.allValues) {
            SeafUploadFile *ufile = [conn getUploadfile:[dict objectForKey:@"lpath"] create:true];
            SeafDir *udir = [[SeafDir alloc] initWithConnection:conn oid:[dict objectForKey:@"oid"] repoId:[dict objectForKey:@"repoId"] perm:[dict objectForKey:@"perm"] name:[dict objectForKey:@"name"] path:[dict objectForKey:@"path"] mime:[dict objectForKey:@"mime"]];
            ufile.udir = udir;
            [self addUploadTask:ufile];
        }
    }
}

- (NSArray *)getUploadTasksForDir:(SeafDir *)dir {
    NSMutableArray *filesInDir = [[NSMutableArray alloc] init];
    @synchronized(self) {
        NSDictionary *accountUploadStorage = [SeafStorage.sharedObject objectForKey:[self uploadStorageKey:dir->connection.accountIdentifier]];
        NSArray *uploadFiles = accountUploadStorage.allValues;
        for (NSDictionary *info in uploadFiles) {
            if ([dir.repoId isEqualToString:[info objectForKey:@"repoId"]] && [dir.path isEqualToString:[info objectForKey:@"path"]]) {
                SeafUploadFile *file = [dir->connection getUploadfile:[info objectForKey:@"lpath"] create:YES];
                file.udir = dir;
                [filesInDir addObject:file];
            }
        }
    }
    return filesInDir;
}

- (void)removeAccountDownloadTaskFromStorage:(NSString *)accountIdentifier {
    NSString *key = [self downloadStorageKey:accountIdentifier];
    [SeafStorage.sharedObject removeObjectForKey:key];
}

- (void)removeAccountUploadTaskFromStorage:(NSString *)accountIdentifier {
    NSString *key = [self uploadStorageKey:accountIdentifier];
    [SeafStorage.sharedObject removeObjectForKey:key];
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

- (void)addUploadTask:(SeafUploadFile * _Nonnull)ufile {
    [self.uploadQueue addTask:ufile];
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
    [self.fileQueue clear];
    [self.thumbQueue clear];
    [self.avatarQueue clear];
    [self.uploadQueue clear];
}

@end
