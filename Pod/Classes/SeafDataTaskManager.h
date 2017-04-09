//
//  SeafBackgroundTaskManager.h
//  Pods
//
//  Created by Wei W on 4/9/17.
//
//

#import <Foundation/Foundation.h>
#import <AssetsLibrary/AssetsLibrary.h>

#import "SeafPreView.h"
#import "SeafConnection.h"
#import "SeafUploadFile.h"

// Manager for background download/upload tasks, retry if failed.
@interface SeafDataTaskManager : NSObject

@property (readonly) ALAssetsLibrary *assetsLibrary;

+ (SeafDataTaskManager *)sharedObject;

- (void)startTimer;

- (unsigned long)backgroundUploadingNum;
- (unsigned long)backgroundDownloadingNum;

- (void)finishDownload:(id<SeafDownloadDelegate>)task result:(BOOL)result;
- (void)finishUpload:(SeafUploadFile *)file result:(BOOL)result;

- (void)addBackgroundUploadTask:(SeafUploadFile *)file;
- (void)addBackgroundDownloadTask:(id<SeafDownloadDelegate>)file;
- (void)removeBackgroundUploadTask:(SeafUploadFile *)file;
- (void)removeBackgroundDownloadTask:(id<SeafDownloadDelegate>)task;
- (void)cancelAutoSyncTasks:(SeafConnection *)conn;
- (void)cancelAutoSyncVideoTasks:(SeafConnection *)conn;

- (void)assetForURL:(NSURL *)assetURL resultBlock:(ALAssetsLibraryAssetForURLResultBlock)resultBlock failureBlock:(ALAssetsLibraryAccessFailureBlock)failureBlock;
@end
