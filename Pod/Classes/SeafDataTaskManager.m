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

#define ALL_UPLOAD @"allUploadTask"
#define ALL_DOWNLOAD @"allDownloadTask"

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
- (void)addUploadTask:(SeafUploadFile *)file
{
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:file.accountIdentifier];
    [accountQueue addUploadTask:file];
    [self saveToTaskStorage:file withIndentifier:file.accountIdentifier];
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
- (void)addFileDownloadTask:(SeafFile * _Nonnull)dfile
{
    SeafAccountTaskQueue *accountQueue = [self getAccountQueueWithIndentifier:dfile.accountIdentifier];
    [accountQueue addFileDownloadTask:dfile];
    [self saveToTaskStorage:dfile withIndentifier:dfile.accountIdentifier];
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
                [weakSelf removeTaskInStorage:task withIndentifier:task.accountIdentifier];
            };
            accountQueue.fileQueue.taskCompleteBlock = ^(id<SeafTask>  _Nonnull task, BOOL result) {
                if (weakSelf.finishBlock)  weakSelf.finishBlock(task);
                [weakSelf removeTaskInStorage:task withIndentifier:task.accountIdentifier];
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

- (void)cacheCleared:(NSNotification*)notification
{
    for (SeafAccountTaskQueue *accountQueue in self.accountQueueDict.allValues) {
        [accountQueue clearTasks];
    }
}

- (void)saveToTaskStorage:(id)task withIndentifier:(NSString*)accountIdentifier {
    NSString *key = [NSString new];
    NSDictionary *dict = [self convertTaskToDict:task];
    if ([task isKindOfClass:[SeafFile class]]) {
        key = [NSString stringWithFormat:@"%@/%@",ALL_DOWNLOAD,accountIdentifier];
    } else if ([task isKindOfClass:[SeafUploadFile class]]) {
        key = [NSString stringWithFormat:@"%@/%@",ALL_UPLOAD,accountIdentifier];
    }
    
    NSMutableArray *downloadStorage = [NSMutableArray arrayWithArray:[SeafStorage.sharedObject objectForKey:key]];
    if (![downloadStorage containsObject:dict]) {
        [downloadStorage addObject:dict];
        [SeafStorage.sharedObject setObject:downloadStorage forKey:key];
    }
}

- (void)removeTaskInStorage:(id)task withIndentifier:(NSString*)accountIdentifier {
    NSString *key = [NSString new];
    NSDictionary *dict = [self convertTaskToDict:task];
    if ([task isKindOfClass:[SeafFile class]]) {
        key = [NSString stringWithFormat:@"%@/%@",ALL_DOWNLOAD,accountIdentifier];
    } else if ([task isKindOfClass:[SeafUploadFile class]]) {
        key = [NSString stringWithFormat:@"%@/%@",ALL_UPLOAD,accountIdentifier];
    }
    
    NSMutableArray *downloadStorage = [NSMutableArray arrayWithArray:[SeafStorage.sharedObject objectForKey:key]];
    if ([downloadStorage containsObject:dict]) {
        [downloadStorage removeObject:dict];
        [SeafStorage.sharedObject setObject:downloadStorage forKey:key];
    }
}

- (NSDictionary*)convertTaskToDict:(id)task {
    NSDictionary *dict = [NSDictionary dictionary];
    if ([task isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile*)task;
        dict = @{@"oid":file.oid,@"repoId":file.repoId,@"name":file.name,@"path":file.path,@"mtime":[NSNumber numberWithLong:file.mtime],@"size":[NSNumber numberWithLong:file.filesize]};
    } else if ([task isKindOfClass:[SeafUploadFile class]]) {
        SeafUploadFile *ufile = (SeafUploadFile*)task;
        dict = @{@"lpath":ufile.lpath,@"oid":ufile.udir.oid,@"repoId":ufile.udir.repoId,@"name":ufile.udir.name,@"path":ufile.udir.path,@"perm":ufile.udir.perm,@"mime":ufile.udir.mime};
    }
    return dict;
}

- (void)startLastTimeUnfinshTaskWithConnection:(SeafConnection *)conn {
    NSString *downloadKey = [NSString stringWithFormat:@"%@/%@",ALL_DOWNLOAD,conn.accountIdentifier];
    NSArray *downloadTasks = [SeafStorage.sharedObject objectForKey:downloadKey];
    if (downloadTasks.count > 0) {
        for (NSDictionary *dict in downloadTasks) {
            SeafFile *file = [[SeafFile alloc] initWithConnection:conn oid:[dict objectForKey:@"oid"] repoId:[dict objectForKey:@"repoId"] name:[dict objectForKey:@"name"] path:[dict objectForKey:@"path"] mtime:[[dict objectForKey:@"mtime"] longLongValue] size:[[dict objectForKey:@"size"] longLongValue]];
            [self addFileDownloadTask:file];
        }
    }
    
    NSString *uploadKey = [NSString stringWithFormat:@"%@/%@",ALL_UPLOAD,conn.accountIdentifier];
    NSArray *uploadTasks = [SeafStorage.sharedObject objectForKey:uploadKey];
    if (uploadTasks.count > 0) {
        for (NSDictionary *dict in uploadTasks) {
            SeafUploadFile *ufile = [[SeafUploadFile alloc] initWithPath:[dict objectForKey:@"lpath"]];
            SeafDir *udir = [[SeafDir alloc] initWithConnection:conn oid:[dict objectForKey:@"oid"] repoId:[dict objectForKey:@"repoId"] perm:[dict objectForKey:@"perm"] name:[dict objectForKey:@"name"] path:[dict objectForKey:@"path"] mime:[dict objectForKey:@"mime"]];
            ufile.udir = udir;
            [self addUploadTask:ufile];
        }
    }
}

- (void)removeDownloadTaskInStoragewithIndentifier:(NSString *)accountIdentifier {
    NSString *key = [NSString stringWithFormat:@"%@/%@",ALL_DOWNLOAD,accountIdentifier];
    [SeafStorage.sharedObject removeObjectForKey:key];
}

- (void)removeUploadTaskInStoragewithIndentifier:(NSString*)accountIdentifier {
    NSString *key = [NSString stringWithFormat:@"%@/%@",ALL_UPLOAD,accountIdentifier];
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
