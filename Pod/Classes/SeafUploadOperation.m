//
//  SeafUploadOperation.m
//  Seafile
//
//  Created by henry on 2024/11/11.
//

// SeafUploadOperation.m

#import "SeafUploadOperation.h"
#import "SeafUploadFile.h"
#import "SeafConnection.h"
#import "SeafDir.h"
#import "Utils.h"
#import "Debug.h"
#import "SeafRepos.h"
#import "NSData+Encryption.h"
#import "SeafStorage.h"
#import "SeafUploadFileModel.h"

@implementation SeafUploadOperation

- (instancetype)initWithUploadFile:(SeafUploadFile *)uploadFile
{
    if (self = [super init]) {
        _uploadFile = uploadFile;
        
        self.retryDelay = UPLOAD_RETRY_DELAY;
        self.maxRetryCount = uploadFile.retryable ? DEFAULT_RETRYCOUNT : 0;
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

    // Begin the upload process
    [self.uploadFile prepareForUploadWithCompletion:^(BOOL success, NSError *error) {
        if (!success || self.isCancelled) {
            [self completeOperation];
            return;
        }

        [self beginUpload];
    }];
}

- (void)cancel
{
    [super cancel];
        
    if (self.isExecuting && !self.operationCompleted) {
        // create cancel NSError
        NSError *cancelError = [NSError errorWithDomain:NSURLErrorDomain
                                                       code:NSURLErrorCancelled
                                                   userInfo:@{NSLocalizedDescriptionKey: @"The upload task was cancelled."}];
        
        [self finishUpload:NO oid:nil error:cancelError];
        [self completeOperation];
    }
}

#pragma mark - Upload Logic

- (void)beginUpload
{
    if (!self.uploadFile.udir.repoId || !self.uploadFile.udir.path) {
        [self finishUpload:NO oid:nil error:[Utils defaultError]];
        return;
    }

    SeafConnection *connection = self.uploadFile.udir.connection;
    NSString *repoId = self.uploadFile.udir.repoId;
    NSString *uploadPath = self.uploadFile.udir.path;

    [self upload:connection repo:repoId path:uploadPath];
}

// SeafUploadFile upload logic
- (void)upload:(SeafConnection *)connection repo:(NSString *)repoId path:(NSString *)uploadpath
{
    if (![Utils fileExistsAtPath:self.uploadFile.lpath]) {
        Warning("File %@ does not exist", self.uploadFile.lpath);
        [self finishUpload:NO oid:nil error:[Utils defaultError]];
        return;
    }
    
    SeafRepo *repo = [connection getRepo:repoId];
    if (!repo) {
        Warning("Repo %@ does not exist", repoId);
        [self finishUpload:NO oid:nil error:[Utils defaultError]];
        return;
    }
    
    self.uploadFile.model.uploading = YES;
    
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.uploadFile.lpath error:nil];
    self.uploadFile.model.filesize = attrs.fileSize;
    
    if (self.uploadFile.filesize > LARGE_FILE_SIZE) {
        Debug("Upload large file %@ by block: %lld", self.uploadFile.name, self.uploadFile.filesize);
        [self uploadLargeFileByBlocks:repo path:uploadpath];
        return;
    }
    
    BOOL byblock = [connection shouldLocalDecrypt:repo.repoId];
    if (byblock) {
        Debug("Upload with local decryption %@ by block: %lld", self.uploadFile.name, self.uploadFile.filesize);
        [self uploadLargeFileByBlocks:repo path:uploadpath];
        return;
    }
    
    NSString *uploadURL = [NSString stringWithFormat:API_URL"/repos/%@/upload-link/?p=%@", repoId, uploadpath.escapedUrl];
    
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *connectUploadLinkTask = [connection sendRequest:uploadURL success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSString *url = [JSON stringByAppendingString:@"?ret-json=true"];
        [strongSelf uploadByFile:connection url:url path:uploadpath update:strongSelf.uploadFile.overwrite];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf finishUpload:NO oid:nil error:error];
    }];
    
    @synchronized (self.taskList) {
        [self.taskList addObject:connectUploadLinkTask];
    }
}

- (void)uploadLargeFileByBlocks:(SeafRepo *)repo path:(NSString *)uploadpath
{
    NSMutableArray *blockids = [[NSMutableArray alloc] init];
    NSMutableArray *paths = [[NSMutableArray alloc] init];
    self.uploadpath = uploadpath;
    if (![self chunkFile:self.uploadFile.lpath repo:repo blockids:blockids paths:paths]) {
        Debug("Failed to chunk file");
        [self finishUpload:NO oid:nil error:[Utils defaultError]];
        return;
    }
    self.allBlocks = blockids;
    NSString* upload_url = [NSString stringWithFormat:API_URL"/repos/%@/upload-blks-link/?p=%@", repo.repoId, uploadpath.escapedUrl];
    NSString *form = [NSString stringWithFormat: @"blklist=%@", [blockids componentsJoinedByString:@","]];
    NSURLSessionDataTask *sendBlockInfoTask = [repo.connection sendPost:upload_url form:form success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        Debug("upload largefile by blocks, JSON: %@", JSON);
        self.rawBlksUrl = [JSON objectForKey:@"rawblksurl"];
        self.commitUrl = [JSON objectForKey:@"commiturl"];
        self.missingBlocks = [JSON objectForKey:@"blklist"];
        self.blkidx = 0;
        [self uploadRawBlocks:repo.connection];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        Debug("Failed to upload: %@", error);
        [self finishUpload:NO oid:nil error:error];
    }];
    
    @synchronized (self.taskList) {
        [self.taskList addObject:sendBlockInfoTask];
    }
}

- (void)uploadRawBlocks:(SeafConnection *)connection
{
    long count = MIN(3, (self.missingBlocks.count - self.blkidx));
    Debug("upload idx %ld, total: %ld, %ld", self.blkidx, (long)self.missingBlocks.count, count);
    if (count == 0) {
        [self uploadBlocksCommit:connection];
        return;
    }
    
    NSArray *arr = [self.missingBlocks subarrayWithRange:NSMakeRange(self.blkidx, count)];
    NSMutableURLRequest *request = [[SeafConnection requestSerializer] multipartFormRequestWithMethod:@"POST" URLString:self.rawBlksUrl parameters:nil constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        [formData appendPartWithFormData:[@"n8ba38951c9ba66418311a25195e2e380" dataUsingEncoding:NSUTF8StringEncoding] name:@"csrfmiddlewaretoken"];
        for (NSString *blockid in arr) {
            NSString *blockpath = [self blockPath:blockid];
            [formData appendPartWithFileURL:[NSURL fileURLWithPath:blockpath] name:@"file" error:nil];
        }
    } error:nil];
    
    __weak __typeof__ (self) wself = self;
    NSURLSessionUploadTask *blockDataUploadTask = [connection.sessionMgr uploadTaskWithStreamedRequest:request progress:^(NSProgress * _Nonnull uploadProgress) {
        __strong __typeof (wself) sself = wself;
//        [sself.uploadFile updateProgressWithoutKVO:uploadProgress];
        [sself.uploadFile uploadProgress:1.0f * self.blkidx / self.allBlocks.count];
        
    } completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        __strong __typeof (wself) sself = wself;
        Debug("Upload blocks %@", arr);
        NSHTTPURLResponse *resp __attribute__((unused)) = (NSHTTPURLResponse *)response;
        if (error) {
            Debug("Upload failed :%@,code=%ld, res=%@\n", error, (long)resp.statusCode, responseObject);
            [sself showDeserializedError:error];
            [sself finishUpload:NO oid:nil error:error];
        } else {
            sself.blkidx += count;
            [sself performSelector:@selector(uploadRawBlocks:) withObject:connection afterDelay:0.0];
        }
    }];
    
    [blockDataUploadTask resume];
    
    @synchronized (self.taskList) {
        [self.taskList addObject:blockDataUploadTask];
    }
}

-(void)showDeserializedError:(NSError *)error
{
    if (!error)
        return;
    id data = [error.userInfo objectForKey:@"com.alamofire.serialization.response.error.data"];

    if (data && [data isKindOfClass:[NSData class]]) {
        NSString *str __attribute__((unused)) = [[NSString alloc] initWithData:(NSData *)data encoding:NSUTF8StringEncoding];
        Debug("DeserializedError: %@", str);
    }
}

- (NSString *)blockPath:(NSString*)blkId
{
    return [self.blockDir stringByAppendingPathComponent:blkId];
}

- (NSString *)blockDir
{
    if (!_blockDir) {
        _blockDir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.tempDir];
        [Utils checkMakeDir:_blockDir];
    }
    return _blockDir;
}

- (void)uploadBlocksCommit:(SeafConnection *)connection
{
    NSString *url = self.commitUrl;
    NSMutableURLRequest *request = [[SeafConnection requestSerializer] multipartFormRequestWithMethod:@"POST" URLString:url parameters:nil constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        [formData appendPartWithFormData:[@"n8ba38951c9ba66418311a25195e2e380" dataUsingEncoding:NSUTF8StringEncoding] name:@"csrfmiddlewaretoken"];
        if (self.uploadFile.overwrite) {
            [formData appendPartWithFormData:[@"1" dataUsingEncoding:NSUTF8StringEncoding] name:@"replace"];
        }
        [formData appendPartWithFormData:[self.uploadpath dataUsingEncoding:NSUTF8StringEncoding] name:@"parent_dir"];
        [formData appendPartWithFormData:[self.uploadFileName dataUsingEncoding:NSUTF8StringEncoding] name:@"file_name"];
        [formData appendPartWithFormData:[[NSString stringWithFormat:@"%lld", [Utils fileSizeAtPath1:self.uploadFile.lpath]] dataUsingEncoding:NSUTF8StringEncoding] name:@"file_size"];
        [formData appendPartWithFormData:[@"n8ba38951c9ba66418311a25195e2e380" dataUsingEncoding:NSUTF8StringEncoding] name:@"csrfmiddlewaretoken"];
        [formData appendPartWithFormData:[Utils JSONEncode:self.allBlocks] name:@"blockids"];
        Debug("url:%@ parent_dir:%@, %@", url, self.uploadpath, [[NSString alloc] initWithData:[Utils JSONEncode:self.allBlocks] encoding:NSUTF8StringEncoding]);
    } error:nil];
    
    NSURLSessionDataTask *blockCompleteTask = [connection.sessionMgr dataTaskWithRequest:request uploadProgress:^(NSProgress * _Nonnull uploadProgress) {
        
    } downloadProgress:^(NSProgress * _Nonnull downloadProgress) {
        
    } completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        if (error) {
            Debug("Failed to upload blocks: %@", error);
            [self finishUpload:NO oid:nil error:error];
        } else {
            NSString *oid = nil;
            if ([responseObject isKindOfClass:[NSArray class]]) {
                oid = [[responseObject objectAtIndex:0] objectForKey:@"id"];
            } else if ([responseObject isKindOfClass:[NSDictionary class]]) {
                oid = [responseObject objectForKey:@"id"];
            }
            if (!oid || oid.length < 1) oid = [[NSUUID UUID] UUIDString];
            Debug("Successfully upload file:%@ autosync:%d oid=%@, responseObject=%@", self.uploadFileName, self.uploadFile.uploadFileAutoSync, oid, responseObject);
            [self finishUpload:YES oid:oid error:nil];
        }
    }];
    [blockCompleteTask resume];
    
    @synchronized (self.taskList) {
        [self.taskList addObject:blockCompleteTask];
    }
}

- (NSString *)uploadFileName {
    return [self.uploadFile.lpath lastPathComponent];
}

- (BOOL)chunkFile:(NSString *)path repo:(SeafRepo *)repo blockids:(NSMutableArray *)blockids paths:(NSMutableArray *)paths
{
    NSString *password = [repo.connection getRepoPassword:repo.repoId];
    if (repo.encrypted && !password)
        return false;
    BOOL ret = YES;
    int CHUNK_LENGTH = 2*1024*1024;
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fileHandle)
        return NO;
    while (YES) {
        @autoreleasepool {
            NSData *data = [fileHandle readDataOfLength:CHUNK_LENGTH];
            if (!data || data.length == 0) break;
            if (password)
                data = [data encrypt:password encKey:repo.encKey version:repo.encVersion];
            if (!data) {
                ret = NO;
                break;
            }
            NSString *blockid = [data SHA1];
            NSString *blockpath = [self blockPath:blockid];
            Debug("Chunk file blockid=%@, path=%@, len=%lu\n", blockid, blockpath, (unsigned long)data.length);
            [blockids addObject:blockid];
            [paths addObject:blockpath];
            [data writeToFile:blockpath atomically:YES];
        }
    }
    [fileHandle closeFile];
    return ret;
}

- (void)uploadByFile:(SeafConnection *)connection url:(NSString *)surl path:(NSString *)uploadpath update:(BOOL)update
{
    NSMutableURLRequest *request = [[SeafConnection requestSerializer] multipartFormRequestWithMethod:@"POST" URLString:surl parameters:nil constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        if (update) {
            [formData appendPartWithFormData:[@"1" dataUsingEncoding:NSUTF8StringEncoding] name:@"replace"];
        }
        [formData appendPartWithFormData:[uploadpath dataUsingEncoding:NSUTF8StringEncoding] name:@"parent_dir"];
        [formData appendPartWithFormData:[@"n8ba38951c9ba66418311a25195e2e380" dataUsingEncoding:NSUTF8StringEncoding] name:@"csrfmiddlewaretoken"];
        NSError *error = nil;
        [formData appendPartWithFileURL:[NSURL fileURLWithPath:self.uploadFile.lpath] name:@"file" error:&error];
        if (error != nil)
            Debug("Error appending file part: %@", error);
    } error:nil];
    [self uploadRequest:request withConnection:connection];
}

- (void)uploadRequest:(NSMutableURLRequest *)request withConnection:(SeafConnection *)connection
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.uploadFile.lpath]) {
        [self finishUpload:NO oid:nil error:nil];
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    NSURLSessionUploadTask *uploadByFileTask = [connection.sessionMgr uploadTaskWithStreamedRequest:request progress:^(NSProgress * _Nonnull uploadProgress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
//        [strongSelf.uploadFile updateProgressWithoutKVO:uploadProgress];
        [strongSelf.uploadFile uploadProgress:uploadProgress.fractionCompleted];
    } completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (error) {
            [strongSelf finishUpload:NO oid:nil error:error];
        } else {
            NSString *oid = nil;
            if ([responseObject isKindOfClass:[NSArray class]]) {
                oid = [[responseObject objectAtIndex:0] objectForKey:@"id"];
            } else if ([responseObject isKindOfClass:[NSDictionary class]]) {
                oid = [responseObject objectForKey:@"id"];
            }
            if (!oid || oid.length < 1) oid = [[NSUUID UUID] UUIDString];
            [strongSelf finishUpload:YES oid:oid error:nil];
        }
    }];
    
    [uploadByFileTask resume];
    
    @synchronized (self.taskList) {
        [self.taskList addObject:uploadByFileTask];
    }
}

//after upload
- (void)finishUpload:(BOOL)result oid:(NSString *)oid error:(NSError *)error {
    if (result) {
        [self.uploadFile finishUpload:result oid:oid error:error];
        [self completeOperation];
    } else {
        if (self.isCancelled) {
            [self.uploadFile finishUpload:result oid:oid error:error];
            [self completeOperation];
            return;
        }
//        if ([self isRetryableError:error] && self.retryCount < self.maxRetryCount) {//deal error
        if (self.retryCount < self.maxRetryCount) {
            self.retryCount += 1;
            Debug(@"Upload failed, retrying %ld/%ld in %.0f seconds", (long)self.retryCount, (long)self.maxRetryCount, self.retryDelay);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.retryDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!self.isCancelled) {
                    [self beginUpload];
                } else {
                    [self completeOperation];
                }
            });
        } else {
            [self.uploadFile finishUpload:result oid:oid error:error];
            [self completeOperation];
        }
    }
}

- (void)completeOperation {
    [self dataCleanup];
    [super completeOperation];
}

- (void)dataCleanup {
    self.rawBlksUrl = nil;
    self.commitUrl = nil;
    self.missingBlocks = nil;
    self.blkidx = 0;
    if (_blockDir) {
        [[NSFileManager defaultManager] removeItemAtPath:_blockDir error:nil];
        _blockDir = nil;
    }
    
}

@end
