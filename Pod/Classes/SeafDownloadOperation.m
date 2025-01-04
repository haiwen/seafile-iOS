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

@implementation SeafDownloadOperation

- (instancetype)initWithFile:(SeafFile *)file
{
    if (self = [super init]) {
        self.file = file;

        self.retryDelay = 5;
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

    SeafConnection *connection = self.file->connection;
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
//        NSString *curId = [Utils getNewOidFromMtime:strongSelf.file.mtime repoId:strongSelf.file.repoId path:strongSelf.file.path];
        NSString *curId = [[response allHeaderFields] objectForKey:@"oid"];

        Debug("Downloading file from file server url: %@, state:%d %@, %@", JSON, strongSelf.file.state, strongSelf.file.ooid, curId);

        if (!curId) curId = strongSelf.file.oid;
        NSString *cachePath = [[SeafRealmManager shared] getLocalCacheWithOid:curId mtime:0 uniKey:strongSelf.file.uniqueKey];
        if ([[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
            Debug("File %@ already exists, curId=%@, ooid=%@", strongSelf.file.name, curId, strongSelf.file.ooid);
            [strongSelf finishDownload:YES error:nil ooid:curId];
            return;
        }
        
        @synchronized (strongSelf.file) {
            if (strongSelf.file.state != SEAF_DENTRY_LOADING) {
                Info("Download file %@ already canceled", strongSelf.file.name);
                [self completeOperation];

                return;
            }
            if (strongSelf.file.downloadingFileOid) {
                Debug("Already downloading %@", strongSelf.file.downloadingFileOid);
                [self completeOperation];

                return;
            }
            strongSelf.file.downloadingFileOid = curId;
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

- (void)downloadFileWithUrl:(NSString *)url connection:(SeafConnection *)connection
{
    url = [url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:DEFAULT_TIMEOUT];

    NSString *target = [SeafStorage.sharedObject documentPath:self.file.downloadingFileOid];
    Debug("Download file %@ %@ from %@, target:%@", self.file.name, self.file.downloadingFileOid, url, target);

    __weak typeof(self) weakSelf = self;
    NSURLSessionDownloadTask *downloadTask = [connection.sessionMgr downloadTaskWithRequest:downloadRequest
                                                                                   progress:^(NSProgress * _Nonnull downloadProgress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        float fraction = downloadProgress.fractionCompleted;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.file downloadProgress:fraction];
        });
    } destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        return [NSURL fileURLWithPath:[target stringByAppendingPathExtension:@"tmp"]];
    } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            [strongSelf finishDownload:YES error:nil ooid:nil];
            return;
        }
        if (!strongSelf.file.downloadingFileOid) {
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
            [strongSelf finishDownload:YES error:nil ooid:strongSelf.file.downloadingFileOid];
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
        if (!strongSelf) return;
        NSString *curId = JSON[@"file_id"];
        
        NSString *cachePath = [[SeafRealmManager shared] getLocalCacheWithOid:curId mtime:0 uniKey:strongSelf.file.uniqueKey];
        if (cachePath && cachePath.length > 0) {
            Debug("Already up-to-date oid=%@", strongSelf.file.ooid);
            [strongSelf finishDownload:YES error:nil ooid:curId];
            return;
        }

        @synchronized (strongSelf.file) {
            if (strongSelf.file.state != SEAF_DENTRY_LOADING) {
                Info("Download file %@ already canceled", strongSelf.file.name);
                [self completeOperation];
                return;
            }
            strongSelf.file.downloadingFileOid = curId;
        }
        [strongSelf.file downloadProgress:0];
        strongSelf.file.blkids = JSON[@"blklist"];
        if (strongSelf.file.blkids.count <= 0) {
            [@"" writeToFile:[SeafStorage.sharedObject documentPath:strongSelf.file.downloadingFileOid] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [strongSelf finishDownload:YES error:nil ooid:strongSelf.file.downloadingFileOid];
        } else {
            strongSelf.file.index = 0;
            Debug("blks=%@", strongSelf.file.blkids);
            [strongSelf downloadBlocks];
        }
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.file.state = SEAF_DENTRY_FAILURE;
        [strongSelf finishDownload:NO error:error ooid:nil];
    }];
    [self addTaskToList:getBlockInfoTask];
}

- (void)downloadBlocks
{
    if (!self.file.isDownloading) return;
    NSString *blk_id = [self.file.blkids objectAtIndex:self.file.index];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[SeafStorage.sharedObject blockPath:blk_id]])
        return [self finishBlock:blk_id];

    NSString *link = [NSString stringWithFormat:API_URL"/repos/%@/files/%@/blks/%@/download-link/", self.file.repoId, self.file.downloadingFileOid, blk_id];
    Debug("link=%@", link);
    @weakify(self);
    NSURLSessionDataTask *task = [self.file->connection sendRequest:link success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        @strongify(self);
         NSString *url = JSON;
         [self downloadBlock:blk_id fromUrl:url];
     } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         @strongify(self);
         Warning("error=%@", error);
         [self finishDownload:NO error:error ooid:nil];
     }];
    [self addTaskToList:task];
}

- (void)downloadBlock:(NSString *)blk_id fromUrl:(NSString *)url
{
    if (!self.file.isDownloading) return;
    NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    Debug("URL: %@", downloadRequest.URL);

    NSString *target = [SeafStorage.sharedObject blockPath:blk_id];
    __weak __typeof__ (self) wself = self;
    NSURLSessionDownloadTask *task = [self.file->connection.sessionMgr downloadTaskWithRequest:downloadRequest progress:^(NSProgress * _Nonnull downloadProgress) {
        __strong __typeof (wself) sself = wself;
        float fraction = downloadProgress.fractionCompleted;
        dispatch_async(dispatch_get_main_queue(), ^{
            [sself.file downloadProgress:fraction];
        });
    } destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        return [NSURL fileURLWithPath:target];
    } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        __strong __typeof (wself) sself = wself;
        if (error) {
            Warning("error=%@", error);
            [sself finishDownload:false error:error ooid:nil];
        } else {
            Debug("Successfully downloaded file %@ block:%@, filePath:%@", sself.name, blk_id, filePath);
            if (![filePath.path isEqualToString:target]) {
                [[NSFileManager defaultManager] removeItemAtPath:target error:nil];
                [[NSFileManager defaultManager] moveItemAtPath:filePath.path toPath:target error:nil];
            }
            [sself finishBlock:blk_id];
        }
    }];
    
    [task resume];
    [self addTaskToList:task];
}

- (void)finishBlock:(NSString *)blkid
{
    if (!self.file.downloadingFileOid) {
        Debug("file download has beeen canceled.");
        [self.file removeBlock:blkid];
        return;
    }
    self.file.index ++;
    if (self.file.index >= self.file.blkids.count) {
        if ([self checkoutFile] < 0) {
            Debug("Faile to checkout out file %@\n", self.file.downloadingFileOid);
            self.file.index = 0;
            for (NSString *blk_id in self.file.blkids)
                [self.file removeBlock:blk_id];
            NSError *error = [NSError errorWithDomain:@"Faile to checkout out file" code:-1 userInfo:nil];
            [self finishDownload:NO error:error ooid:nil];
            return;
        }
        [self finishDownload:YES error:nil ooid:self.file.downloadingFileOid];
        return;
    }
    [self performSelector:@selector(downloadBlocks) withObject:nil afterDelay:0.0];
}

- (int)checkoutFile
{
    NSString *password = nil;
    SeafRepo *repo = [self.file->connection getRepo:self.file.repoId];
    if (repo.encrypted) {
        password = [self.file->connection getRepoPassword:self.file.repoId];
    }
    NSString *tmpPath = [self.file downloadTempPath:self.file.downloadingFileOid];
    if (![[NSFileManager defaultManager] fileExistsAtPath:tmpPath])
        [[NSFileManager defaultManager] createFileAtPath:tmpPath contents: nil attributes: nil];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:tmpPath];
    [handle truncateFileAtOffset:0];
    for (NSString *blk_id in self.file.blkids) {
        NSData *data = [[NSData alloc] initWithContentsOfFile:[SeafStorage.sharedObject blockPath:blk_id]];
        if (password)
            data = [data decrypt:password encKey:repo.encKey version:repo.encVersion];
        if (!data)
            return -1;
        [handle writeData:data];
    }
    [handle closeFile];
    if (!self.file.downloadingFileOid)
        return -1;
        
    [[NSFileManager defaultManager] moveItemAtPath:tmpPath toPath:[SeafStorage.sharedObject documentPath:self.file.downloadingFileOid] error:nil];
    return 0;
}

- (void)finishDownload:(BOOL)success error:(NSError *)error ooid:(NSString *)ooid {
    @synchronized (self.file) {
        self.file.isDownloading = NO;
        self.file.downloaded = success;
        self.file.lastFinishTimestamp = [[NSDate new] timeIntervalSince1970];
        if (success && ooid != nil) {
            [self.file finishDownload:ooid];
            [self completeOperation];
        }
        else {
            if (self.isCancelled) {
                [self.file failedDownload:error];
                [self completeOperation];
                return;
            }

//            if ([self isRetryableError:error] && self.retryCount < self.maxRetryCount) {
            //if !success need to try,self.retryCount < self.maxRetryCount is a necessary condition for retry.
            if (self.retryCount < self.maxRetryCount && !success) {
                self.retryCount += 1;
                Debug(@"download failed，after %.0f second will retry %ld/%ld", self.retryDelay, (long)self.retryCount, (long)self.maxRetryCount);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.retryDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (!self.isCancelled) {
                        [self beginDownload];
                    } else {
                        [self completeOperation];
                    }
                });
            } else {
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
