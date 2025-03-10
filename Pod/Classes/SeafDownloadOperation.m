//
//  SeafDownloadOperation.m
//  Seafile
//
//  Created by henry on 2024/11/16.
//

#import "SeafDownloadOperation.h"
#import "SeafFile.h"
#import "SeafConnection.h"
#import "Utils.h"
#import "Debug.h"
#import "SeafStorage.h"
#import "SeafBase.h"
#import "SeafDir.h"
#import "SeafRepos.h"
#import "NSData+Encryption.h"
#import "SeafRealmManager.h"
#import "SeafDataTaskManager.h"

@implementation SeafDownloadOperation

- (instancetype)initWithFile:(SeafFile *)file
{
    if (self = [super init]) {
        self.file = file;
        self.maxRetryCount = file.retryable ? DEFAULT_RETRYCOUNT : 0;
    }
    return self;
}

#pragma mark - NSOperation Overrides
- (void)start
{
    [super start];
    
    if (self.isCancelled || self.isFinished) {
        return;
    }

    [self beginDownload];
}

- (void)cancel {
    @synchronized (self) {
        [super cancel];

        self.file.state = SEAF_DENTRY_FAILURE;

        if (self.isExecuting && !self.operationCompleted) {
            NSError *cancelError = [NSError errorWithDomain:NSURLErrorDomain
                                                       code:NSURLErrorCancelled
                                                   userInfo:@{NSLocalizedDescriptionKey: @"The download task was cancelled."}];
            [self finishDownload:NO error:cancelError ooid:self.file.ooid];
            [self completeOperation];
        }
    }
}

#pragma mark - Download Logic

- (void)beginDownload
{
    if (!self.file.repoId || !self.file.path) {
        [self finishDownload:NO error:[Utils defaultError] ooid:self.file.ooid];
        return;
    }

    SeafConnection *connection = self.file.connection;
    self.file.state = SEAF_DENTRY_LOADING;

    if ([connection shouldLocalDecrypt:self.file.repoId] || self.file.filesize > LARGE_FILE_SIZE) {
        Debug("Download file %@ by blocks: %lld", self.file.name, self.file.filesize);
        [self downloadByBlocks:connection];
    } else {
        [self downloadByFile:connection];
    }
}

// SeafFile download logic.
- (void)downloadByFile:(SeafConnection *)connection
{
    NSString *url = [NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@", self.file.repoId, [self.file.path escapedUrl]];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *getDownloadUrlTask = [connection sendRequest:url
                                                               success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *downloadUrl = JSON;
        NSString *curId = [[response allHeaderFields] objectForKey:@"oid"];

        Debug("Downloading file from file server url: %@, state:%d %@, %@", JSON, strongSelf.file.state, strongSelf.downloadingFileOid, curId);

        if (!curId) curId = strongSelf.file.oid;
        NSString *cachePath = [[SeafRealmManager shared] getCachePathWithOid:curId mtime:0 uniKey:strongSelf.file.uniqueKey];
        if ([[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
            Debug("File %@ already exists, curId=%@, ooid=%@", strongSelf.file.name, curId, strongSelf.file.ooid);
            [strongSelf finishDownload:YES error:nil ooid:curId];
            return;
        }
        
        @synchronized (strongSelf) {
            if (strongSelf.file.state != SEAF_DENTRY_LOADING) {
                Info("Download file %@ already canceled", strongSelf.file.name);
                [self completeOperation];
                return;
            }
            if (strongSelf.downloadingFileOid) {
                Debug("Already downloading %@", strongSelf.downloadingFileOid);
                [self completeOperation];
                return;
            }
            strongSelf.downloadingFileOid = curId;
        }
        [strongSelf.file downloadProgress:0];
        [strongSelf downloadFileWithUrl:downloadUrl connection:connection];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.file.state = SEAF_DENTRY_INIT;
        [strongSelf finishDownload:NO error:error ooid:nil];
    }];
    
    [self addTaskToList:getDownloadUrlTask];
}

- (void)updateProgress:(float)progress
{
    float percent = 0;
    if (self.blkids) {
        percent = self.currentBlockIndex * 1.0f / self.blkids.count;
    } else {
        percent = progress;
    }
    
    [self.file downloadProgress:percent];
}

- (void)downloadFileWithUrl:(NSString *)url connection:(SeafConnection *)connection
{
    url = [url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:DEFAULT_TIMEOUT];

    NSString *target = [SeafStorage.sharedObject documentPath:self.downloadingFileOid];
    Debug("Download file %@ %@ from %@, target:%@", self.file.name, self.downloadingFileOid, url, target);

    __weak typeof(self) weakSelf = self;
    NSURLSessionDownloadTask *downloadTask = [connection.sessionMgr downloadTaskWithRequest:downloadRequest
                                                                                   progress:^(NSProgress * _Nonnull downloadProgress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf updateProgress:downloadProgress.fractionCompleted];
    } destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        return [NSURL fileURLWithPath:[target stringByAppendingPathExtension:@"tmp"]];
    } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            [strongSelf finishDownload:YES error:nil ooid:nil];
            return;
        }
        if (!strongSelf.downloadingFileOid) {
            Info("Download file %@ already canceled", strongSelf.file.name);
            [strongSelf completeOperation];
            return;
        }
        if (error) {
            Debug("Failed to download %@, error=%@, %ld", strongSelf.file.name, [error localizedDescription], (long)((NSHTTPURLResponse *)response).statusCode);
            [strongSelf finishDownload:NO error:error ooid:nil];
        } else {
            Debug("Successfully downloaded file:%@, %@", strongSelf.file.name, downloadRequest.URL);
            if (![filePath.path isEqualToString:target]) {
                [Utils removeFile:target];
                [[NSFileManager defaultManager] moveItemAtPath:filePath.path toPath:target error:nil];
            }
            [strongSelf finishDownload:YES error:nil ooid:strongSelf.downloadingFileOid];
        }
    }];
    [downloadTask resume];
    
    [self addTaskToList:downloadTask];
}

- (void)downloadByBlocks:(SeafConnection *)connection
{
    NSString *url = [NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@&op=downloadblks", self.file.repoId, [self.file.path escapedUrl]];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *getBlockInfoTask = [connection sendRequest:url
                                                           success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.isCancelled) return;
        
        NSString *curId = JSON[@"file_id"];
        NSString *cachePath = [[SeafRealmManager shared] getCachePathWithOid:curId mtime:0 uniKey:strongSelf.file.uniqueKey];
        if (cachePath && cachePath.length > 0) {
            Debug("Already up-to-date oid=%@", strongSelf.file.ooid);
            [strongSelf finishDownload:YES error:nil ooid:curId];
            return;
        }

        @synchronized (strongSelf) {
            if (strongSelf.isCancelled) {
                return;
            }
            strongSelf.downloadingFileOid = curId;
            strongSelf.blkids = JSON[@"blklist"];
            strongSelf.currentBlockIndex = 0;
            
            if (strongSelf.blkids.count <= 0) {
                [@"" writeToFile:[SeafStorage.sharedObject documentPath:strongSelf.downloadingFileOid] 
                     atomically:YES 
                      encoding:NSUTF8StringEncoding 
                         error:nil];
                [strongSelf finishDownload:YES error:nil ooid:strongSelf.downloadingFileOid];
            } else {
                Debug("blks=%@", strongSelf.blkids);
                [strongSelf downloadBlocks];
            }
        }
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf finishDownload:NO error:error ooid:nil];
    }];
    
    [self addTaskToList:getBlockInfoTask];
}

- (void)downloadBlocks
{
    if (self.isCancelled) return;
    
    NSString *blk_id = [self.blkids objectAtIndex:self.currentBlockIndex];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[SeafStorage.sharedObject blockPath:blk_id]]) {
        return [self finishBlock:blk_id];
    }

    NSString *link = [NSString stringWithFormat:API_URL"/repos/%@/files/%@/blks/%@/download-link/",
                     self.file.repoId,
                     self.downloadingFileOid,
                     blk_id];
    
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.file.connection sendRequest:link 
        success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.isCancelled) return;
            NSString *url = JSON;
            [strongSelf downloadBlock:blk_id fromUrl:url];
        } 
        failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            Warning("error=%@", error);
            [strongSelf finishDownload:NO error:error ooid:nil];
        }];
    [self addTaskToList:task];
}

- (void)downloadBlock:(NSString *)blkId fromUrl:(NSString *)url
{
    url = [url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url] 
                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData 
                                               timeoutInterval:DEFAULT_TIMEOUT];
    
    NSString *target = [SeafStorage.sharedObject blockPath:blkId];
    Debug("Download block %@ from %@", blkId, url);
    
    __weak typeof(self) weakSelf = self;
    NSURLSessionDownloadTask *downloadTask = [self.file.connection.sessionMgr
                                              downloadTaskWithRequest:downloadRequest
                                              progress:^(NSProgress * _Nonnull downloadProgress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.isCancelled) return;
        //            float blockProgress = downloadProgress.fractionCompleted;
        float overallProgress = strongSelf.currentBlockIndex * 1.0f / strongSelf.blkids.count;
        strongSelf.progress = overallProgress;
        [strongSelf updateProgress:overallProgress];
    }
                                              destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        return [NSURL fileURLWithPath:[target stringByAppendingPathExtension:@"tmp"]];
    }
                                              completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error) {
            Debug("Failed to download block %@: %@", blkId, error);
            [strongSelf finishDownload:NO error:error ooid:nil];
        } else {
            if (![filePath.path isEqualToString:target]) {
                [Utils removeFile:target];
                [[NSFileManager defaultManager] moveItemAtPath:filePath.path toPath:target error:nil];
            }
            
            [strongSelf finishBlock:blkId];
        }
    }];
    
    [downloadTask resume];
    [self addTaskToList:downloadTask];
}

- (void)finishBlock:(NSString *)blkId
{
    if (self.isCancelled) {
        [self removeBlock:blkId];
        return;
    }
    
    self.currentBlockIndex++;
    if (self.currentBlockIndex >= self.blkids.count) {
        if ([self checkoutFile] < 0) {
            Debug("Failed to checkout file %@", self.downloadingFileOid);
            self.currentBlockIndex = 0;
            for (NSString *blk_id in self.blkids) {
                [self removeBlock:blk_id];
            }
            NSError *error = [NSError errorWithDomain:@"SeafDownloadOperation" 
                                               code:-1 
                                           userInfo:@{NSLocalizedDescriptionKey: @"Failed to checkout file"}];
            [self finishDownload:NO error:error ooid:nil];
            return;
        }
        [self finishDownload:YES error:nil ooid:self.downloadingFileOid];
        return;
    }
    
    [self performSelector:@selector(downloadBlocks) withObject:nil afterDelay:0.0];
}

- (void)removeBlock:(NSString *)blkId
{
    [[NSFileManager defaultManager] removeItemAtPath:[SeafStorage.sharedObject blockPath:blkId] error:nil];
}

- (int)checkoutFile
{
    // Implement file block merging logic
    NSString *path = [SeafStorage.sharedObject documentPath:self.downloadingFileOid];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) {
        return 0;
    }
    
    NSFileHandle *outfile = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!outfile) {
        [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        outfile = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!outfile) return -1;
    }
    
    for (NSString *blkId in self.blkids) {
        NSString *blkPath = [SeafStorage.sharedObject blockPath:blkId];
        NSData *data = [NSData dataWithContentsOfFile:blkPath];
        if (!data) return -1;
        [outfile writeData:data];
    }
    
    [outfile closeFile];
    return 0;
}

- (void)clearDownloadContext
{
    self.downloadingFileOid = nil;
    self.currentBlockIndex = 0;
    for (int i = 0; i < self.blkids.count; ++i) {
        [self removeBlock:[self.blkids objectAtIndex:i]];
    }
    self.blkids = nil;
}

- (void)finishDownload:(BOOL)success error:(NSError *)error ooid:(NSString *)ooid {
    @synchronized (self.file) {
        self.file.isDownloading = NO;
        
        if (success && ooid != nil) {
            [self clearDownloadContext];
            self.file.downloaded = success;
            self.file.lastFinishTimestamp = [[NSDate new] timeIntervalSince1970];
            Debug("%@ ooid=%@, self.file.ooid=%@, oid=%@", self.file.name, ooid, self.file.ooid, self.file.oid);
            [self.file finishDownload:ooid];
            [self completeOperation];
        }
        else {
            if (self.isCancelled) {
                [self clearDownloadContext];
                [self.file failedDownload:error];
                [self completeOperation];
                return;
            }

            if (self.file.retryCount < self.maxRetryCount && !success) {
                self.file.retryCount += 1;
                Debug(@"Download failed, will retry %ld/%ld, task placed at the end of queue", (long)self.file.retryCount, (long)self.maxRetryCount);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DEFAULT_RETRY_INTERVAL * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    
                    // Clear the current download context
                    [self clearDownloadContext];
                    
                    // Complete the current operation
                    [self completeOperation];
                    
                    // Add the task back to queue - using SeafDataTaskManager, a more appropriate task management approach
                    [[SeafDataTaskManager sharedObject] addFileDownloadTask:self.file];
                });
            } else {
                [self clearDownloadContext];
                [self.file failedDownload:error];
                [self completeOperation];
            }
        }
    }
}

#pragma mark - Operation State Management
- (void)addTaskToList:(NSURLSessionTask *)task {
    @synchronized (self.taskList) {
        [self.taskList addObject:task];
    }
}

@end
