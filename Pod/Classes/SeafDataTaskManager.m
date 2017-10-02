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

@interface SeafDataTaskManager()

@property NSUserDefaults *storage;
@property (nonatomic, strong) NSMutableDictionary *accountQueueDict;

@end

@implementation SeafDataTaskManager

- (NSMutableDictionary *)accountQueueDict {
    if (!_accountQueueDict) {
        _accountQueueDict = [NSMutableDictionary dictionary];
    }
    return _accountQueueDict;
}

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
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cacheCleared:) name:@"clearCache" object:nil];
    }
    return self;
}

#pragma mark- upload
- (void)addBackgroundUploadTask:(SeafUploadFile *)file
{
    [file resetFailedAttempt];
    SeafDownloadAccountQueue *accountQueue = [self getAccountQueueWithFileIndectifier:file.userIdentifier];
    [accountQueue addUploadTask:file];
}

- (void)finishUpload:(SeafUploadFile *)file result:(BOOL)result
{
    SeafDownloadAccountQueue *accountQueue = [self getAccountQueueWithFileIndectifier:file.userIdentifier];
    [accountQueue.uploadQueue finishUploadTask:file result:result];
}

- (void)removeBackgroundUploadTask:(SeafUploadFile *)file
{
    SeafDownloadAccountQueue *accountQueue = [self getAccountQueueWithFileIndectifier:file.userIdentifier];
    [accountQueue.uploadQueue clear];
}

- (void)cancelAutoSyncTasks:(SeafConnection *)conn
{
    SeafDownloadAccountQueue *accountQueue = [self getAccountQueueWithFileIndectifier:[NSString stringWithFormat:@"%@%@", conn.host, conn.username]];
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    @synchronized (accountQueue.uploadQueue.allTasks) {
        for (SeafUploadFile *ufile in accountQueue.uploadQueue.allTasks) {
            if (ufile.autoSync && ufile.udir->connection == conn) {
                [arr addObject:ufile];
            }
        }
    }
    Debug("clear %ld photos", (long)arr.count);
    for (SeafUploadFile *ufile in arr) {
        [conn removeUploadfile:ufile];
    }
}

- (void)cancelAutoSyncVideoTasks:(SeafConnection *)conn
{
    SeafDownloadAccountQueue *accountQueue = [self getAccountQueueWithFileIndectifier:[NSString stringWithFormat:@"%@%@", conn.host, conn.username]];
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    @synchronized (accountQueue.uploadQueue.allTasks) {
        for (SeafUploadFile *ufile in accountQueue.uploadQueue.allTasks) {
            if (ufile.autoSync && ufile.udir->connection == conn && !ufile.isImageFile) {
                [arr addObject:ufile];
            }
        }
    }
    for (SeafUploadFile *ufile in arr) {
        Debug("Remove autosync video file: %@, %@", ufile.lpath, ufile.assetURL);
        [conn removeUploadfile:ufile];
    }
}

- (void)noException:(void (^)())block
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
- (void)addDownloadTask:(id<SeafDownloadDelegate>)task {
    SeafDownloadAccountQueue *accountQueue = [self getAccountQueueWithFileIndectifier:[task taskUserIdentifier]];
    if ([task isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile*)task;
        [accountQueue addFileDownloadTask:file];
        if (self.trySyncBlock) {
            self.trySyncBlock(file);
        }
    } else if ([task isKindOfClass:[SeafThumb class]]) {
        SeafThumb *thumb = (SeafThumb*)task;
        [accountQueue addThumbTask:thumb];
    } else if ([task isKindOfClass:[SeafAvatar class]]) {
        SeafAvatar *avatar = (SeafAvatar*)task;
        [accountQueue addAvatarTask:avatar];
    }
}

- (SeafDownloadAccountQueue *)getAccountQueueWithFileIndectifier:(NSString *)identifier {
    @synchronized(self. accountQueueDict) {
        SeafDownloadAccountQueue *accountQueue = [self.accountQueueDict valueForKey:identifier];
        if (!accountQueue) {
            accountQueue = [[SeafDownloadAccountQueue alloc] init];
            [self.accountQueueDict setObject:accountQueue forKey:identifier];
        }
        return accountQueue;
    }
}

- (void)finishDownloadTask:(id<SeafDownloadDelegate>)task result:(BOOL)result {
    SeafDownloadAccountQueue *accountQueue = [self getAccountQueueWithFileIndectifier:[task taskUserIdentifier]];
    if ([task isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile*)task;
        [accountQueue.fileQueue finishTask:task result:result];
        if (self.finishBlock) {
            self.finishBlock(file);
        }
    } else if ([task isKindOfClass:[SeafThumb class]]) {
        [accountQueue.thumbQueue finishTask:task result:result];
    } else if ([task isKindOfClass:[SeafAvatar class]]) {
        [accountQueue.avatarQueue finishTask:task result:result];
    }
}

- (SeafDownloadAccountQueue *)accountQueueForConnection:(SeafConnection *)connection {
    NSString *identifier = [NSString stringWithFormat:@"%@%@",connection.host,connection.username];
    SeafDownloadAccountQueue *task = [self.accountQueueDict valueForKey:identifier];
    return task;
}

- (void)removeBackgroundDownloadTask:(id<SeafDownloadDelegate>)task {
    SeafDownloadAccountQueue *accountQueue = [self.accountQueueDict valueForKey:[task taskUserIdentifier]];
    if ([task isKindOfClass:[SeafThumb class]]) {
        [accountQueue.thumbQueue clear];
    } else if ([task isKindOfClass:[SeafAvatar class]]) {
        [accountQueue.avatarQueue clear];
    }
}

- (void)cacheCleared:(NSNotification*)notification{
    [self.accountQueueDict removeAllObjects];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

@implementation SeafDownloadAccountQueue

- (instancetype)init {
    self = [super init];
    if (self) {
        self.fileQueue = [[SeafTaskQueue alloc] init];
        self.thumbQueue = [[SeafTaskQueue alloc] init];
        self.avatarQueue = [[SeafTaskQueue alloc] init];
        self.uploadQueue = [[SeafTaskQueue alloc] init];
    }
    return self;
}

- (void)addFileDownloadTask:(SeafFile *)dfile {
    [self.fileQueue addTask:dfile];
}

- (void)addThumbTask:(SeafThumb *)thumb {
    [self.thumbQueue addTask:thumb];
}

- (void)addAvatarTask:(SeafAvatar *)avatar {
    [self.avatarQueue addTask:avatar];
}

- (void)addUploadTask:(SeafUploadFile *)ufile {
    [self.uploadQueue addTask:ufile];
}

@end
