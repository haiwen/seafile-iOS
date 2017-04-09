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

@interface SeafDataTaskManager()
@property (retain) NSMutableArray *uTasks;
@property (retain) NSMutableArray *dTasks;
@property (retain) NSMutableArray *uploadingTasks;
@property (retain) NSMutableArray *downloadingTasks;

@property unsigned long failedNum;
@property NSUserDefaults *storage;

@property NSTimer *taskTimer;

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

-(id)init
{
    if (self = [super init]) {
        _assetsLibrary = [[ALAssetsLibrary alloc] init];
        _uTasks = [NSMutableArray new];
        _dTasks = [NSMutableArray new];
        _uploadingTasks = [NSMutableArray new];
        _downloadingTasks = [NSMutableArray new];
        [self startTimer];
    }
    return self;
}

- (unsigned long)backgroundUploadingNum
{
    return self.uploadingTasks.count + self.uTasks.count;
}

- (unsigned long)backgroundDownloadingNum
{
    return self.downloadingTasks.count + self.dTasks.count;
}

- (void)finishDownload:(id<SeafDownloadDelegate>)task result:(BOOL)result
{
    Debug("file %@ download %ld, result=%d, failcnt=%ld", task.name, self.backgroundDownloadingNum, result, self.failedNum);

    @synchronized (self.downloadingTasks) {
        [self.downloadingTasks removeObject:task];
    }

    if (result) {
        self.failedNum = 0;
    } else {
        self.failedNum ++;
        if ([task retryable])
            [self.dTasks addObject:task];
        if (self.failedNum >= 3) {
            [self performSelector:@selector(tryDownload) withObject:nil afterDelay:10.0];
            self.failedNum = 2;
            return;
        }
    }
    [self performSelector:@selector(tick:) withObject:_taskTimer afterDelay:0.1];
}

- (void)finishUpload:(SeafUploadFile *)file result:(BOOL)result
{
    Debug("upload %ld, result=%d, file=%@, udir=%@", (long)self.uploadingTasks.count, result, file.lpath, file.udir.path);
    @synchronized (self.uploadingTasks) {
        [self.uploadingTasks removeObject:file];
    }

    if (result) {
        self.failedNum = 0;
    } else {
        self.failedNum ++;
        if (!file.removed) {
            [self.uTasks addObject:file];
        } else
            Debug("Upload file %@ removed.", file.name);
        if (self.failedNum >= 3) {
            [self performSelector:@selector(tryUpload) withObject:nil afterDelay:10.0];
            self.failedNum = 2;
            return;
        }
    }
    [self performSelector:@selector(tick:) withObject:_taskTimer afterDelay:0.1];
}

- (void)tryUpload
{
    Debug("tryUpload uploading:%ld left:%ld", (long)self.uploadingTasks.count, (long)self.uTasks.count);
    if (self.uTasks.count == 0) return;
    NSMutableArray *todo = [[NSMutableArray alloc] init];
    @synchronized (self.uTasks) {
        NSMutableArray *arr = [self.uTasks mutableCopy];
        for (SeafUploadFile *file in arr) {
            if (self.uploadingTasks.count + todo.count + self.failedNum >= 3) break;
            Debug("ufile %@ canUpload:%d, uploaded:%d", file.lpath, file.canUpload, file.uploaded);
            if (!file.canUpload) continue;
            [self.uTasks removeObject:file];
            if (!file.uploaded) {
                [todo addObject:file];
            }
        }
    }
    double delayInMs = 400.0;
    int uploadingCount = self.uploadingTasks.count;
    for (int i = 0; i < todo.count; i++) {
        SeafUploadFile *file = [todo objectAtIndex:i];
        if (!file.udir) continue;

        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (i+uploadingCount) * delayInMs * NSEC_PER_MSEC);
        dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(void){
            [file doUpload];
        });

        @synchronized (self.uploadingTasks) {
            [self.uploadingTasks addObject:file];
        }
    }
}

- (void)tryDownload
{
    if (self.dTasks.count == 0) return;
    NSMutableArray *todo = [[NSMutableArray alloc] init];
    @synchronized (self.dTasks) {
        NSMutableArray *arr = [self.dTasks mutableCopy];
        for (id<SeafDownloadDelegate> file in arr) {
            if (self.downloadingTasks.count + todo.count + self.failedNum >= 2) break;
            [self.dTasks removeObject:file];
            [todo addObject:file];
        }
    }
    for (id<SeafDownloadDelegate> task in todo) {
        Debug("try download %@", task.name);
        @synchronized (self.downloadingTasks) {
            [self.downloadingTasks addObject:task];
        }
        [task download];
    }
}


- (void)removeBackgroundUploadTask:(SeafUploadFile *)file
{
    @synchronized (self.uTasks) {
        [self.uTasks removeObject:file];
    }

    @synchronized (self.uploadingTasks) {
        [self.uploadingTasks removeObject:file];
    }
}

- (void)removeBackgroundDownloadTask:(id<SeafDownloadDelegate>)task
{
    @synchronized (self.dTasks) {
        [self.dTasks removeObject:task];
    }

    @synchronized (self.downloadingTasks) {
        [self.downloadingTasks removeObject:task];
    }
}

- (void)cancelAutoSyncTasks:(SeafConnection *)conn
{
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    @synchronized (self.uTasks) {
        for (SeafUploadFile *ufile in self.uTasks) {
            if (ufile.autoSync && ufile.udir->connection == conn) {
                [arr addObject:ufile];
            }
        }
    }
    @synchronized (self.uploadingTasks) {
        for (SeafUploadFile *ufile in self.uploadingTasks) {
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
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    @synchronized (self.uTasks) {
        for (SeafUploadFile *ufile in self.uTasks) {
            if (ufile.autoSync && ufile.udir->connection == conn && !ufile.isImageFile) {
                [arr addObject:ufile];
            }
        }
    }
    @synchronized (self.uploadingTasks) {
        for (SeafUploadFile *ufile in self.uploadingTasks) {
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

- (void)addBackgroundUploadTask:(SeafUploadFile *)file
{
    [file resetFailedAttempt];
    @synchronized (self.uTasks) {
        if (![self.uTasks containsObject:file] && ![self.uploadingTasks containsObject:file])
            [self.uTasks addObject:file];
        else
            Warning("upload task file %@ already exist", file.lpath);
    }
    [self performSelectorInBackground:@selector(tryUpload) withObject:file];
}

- (void)addBackgroundDownloadTask:(id<SeafDownloadDelegate>)file
{
    @synchronized (self.dTasks) {
        if (![self.dTasks containsObject:file] && ![self.downloadingTasks containsObject:file]) {
            [self.dTasks insertObject:file atIndex:0];
            Debug("Added download task %@: %ld", file.name, (unsigned long)self.dTasks.count);
        }
    }
    [self tryDownload];
}

- (void)tick:(NSTimer *)timer
{
    if (![[AFNetworkReachabilityManager sharedManager] isReachable]) {
        return;
    }
    if (self.uTasks.count > 0)
        [self tryUpload];
    if (self.dTasks.count > 0)
        [self tryDownload];
}

- (void)startTimer
{
    Debug("Start timer.");
    [self tick:nil];
    _taskTimer = [NSTimer scheduledTimerWithTimeInterval:5*60
                                                      target:self
                                                    selector:@selector(tick:)
                                                    userInfo:nil
                                                     repeats:YES];
    [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        [self tick:_taskTimer];
    }];
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


@end
