//
//  SeafUploadFile.m
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafStorage.h"
#import "SeafUploadFile.h"
#import "SeafRepos.h"
#import "SeafDataTaskManager.h"

#import "Utils.h"
#import "FileMimeType.h"
#import "UIImage+FileType.h"
#import "ExtentedString.h"
#import "NSData+Encryption.h"
#import "Debug.h"


@interface SeafUploadFile ()
@property (readonly) NSString *mime;
@property (strong, readonly) NSURL *preViewURL;
@property (strong) NSURLSessionUploadTask *task;
@property (strong) NSProgress *progress;

@property (strong) NSArray *missingblocks;
@property (strong) NSArray *allblocks;
@property (strong) NSString *commiturl;
@property (strong) NSString *rawblksurl;
@property (strong) NSString *uploadpath;
@property (nonatomic, strong) NSString *blockDir;
@property long blkidx;

@property dispatch_semaphore_t semaphore;
@property (nonatomic) TaskCompleteBlock taskCompleteBlock;
@property (nonatomic) TaskProgressBlock taskProgressBlock;
@property (nonatomic, strong) PHImageRequestOptions *requestOptions;

@end

@implementation SeafUploadFile
@synthesize assetURL = _assetURL;
@synthesize filesize = _filesize;
@synthesize lastFinishTimestamp = _lastFinishTimestamp;
@synthesize retryable = _retryable;
@synthesize retryCount = _retryCount;

- (id)initWithPath:(NSString *)lpath
{
    self = [super init];
    if (self) {
        self.retryable = true;
        _lpath = lpath;
        _uProgress = 0;
        _uploading = NO;
        _autoSync = NO;
        _starred = NO;
        _uploaded = NO;
        _overwrite = NO;
        _semaphore = dispatch_semaphore_create(0);
    }
    return self;
}

- (NSString *)name
{
    return [_lpath lastPathComponent];
}

- (long long)filesize
{
    if (!_filesize || _filesize == 0) {
        _filesize = [Utils fileSizeAtPath1:self.lpath] ;
    }
    return _filesize;
}

- (void)unload
{
}

- (NSString *)accountIdentifier
{
    return self.udir->connection.accountIdentifier;
}

- (BOOL)hasCache
{
    return YES;
}

- (BOOL)isImageFile
{
    return [Utils isImageFile:self.name];
}

- (void)load:(id<SeafDentryDelegate>)delegate force:(BOOL)force
{
    [self checkAsset];
}

- (long long)mtime
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.lpath]) {
        return [[NSDate date] timeIntervalSince1970];
    } else {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.lpath error:nil];
        return [[attributes fileModificationDate] timeIntervalSince1970];
    }
}

- (BOOL)editable
{
    return NO;
}

- (BOOL)uploadHeic {
    return self.udir->connection.uploadHeicEnabled;
}

- (NSString *)blockDir
{
    if (!_blockDir) {
        _blockDir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.tempDir];
        [Utils checkMakeDir:_blockDir];
    }
    return _blockDir;
}

- (NSString *)blockPath:(NSString*)blkId
{
    return [self.blockDir stringByAppendingPathComponent:blkId];
}

- (void)cancel
{
    Debug("Cancel uploadFile: %@", self.lpath);
    // Avoid recursively call cancel in SeafDataTaskManager
    if (!self.udir) return;
    SeafConnection *conn = self.udir->connection;
    @synchronized(self) {
        [self.task cancel];
        [self cleanup];
        [self.udir removeUploadItem:self];
        self.udir = nil;
        self.task = nil;
    }

    [SeafDataTaskManager.sharedObject removeUploadTask:self forAccount: conn];
}

- (void)cancelAnyLoading
{
}

- (void)cleanup
{
    Debug("Cleanup uploaded disk file: %@", self.lpath);
    [Utils removeFile:self.lpath];
    if (_blockDir) {
        [[NSFileManager defaultManager] removeItemAtPath:_blockDir error:nil];
    }
    if (!self.autoSync) {
        [Utils removeDirIfEmpty:[self.lpath stringByDeletingLastPathComponent]];
    }
}

- (BOOL)removed
{
    return !_udir;
}

- (void)finishUpload:(BOOL)result oid:(NSString *)oid error:(NSError *)error
{
    @synchronized(self) {
        if (!self.isUploading) return;
        _uploading = NO;
        self.task = nil;
        [self updateProgress:nil];
    }
    
    if (_starred) {
        NSString* rpath = [_udir.path stringByAppendingPathComponent:self.name];
        [_udir->connection setStarred:YES repo:_udir.repoId path:rpath];
    }

    self.rawblksurl = nil;
    self.commiturl = nil;
    self.missingblocks = nil;
    self.blkidx = 0;
    _uploaded = result;
    NSError *err = error;
    if (!err && !result) {
        err = [Utils defaultError];
    }
    Debug("result=%d, name=%@, delegate=%@, oid=%@, err=%@\n", result, self.name, _delegate, oid, err);
    [self uploadComplete:oid error:err];
    if (result) {
        if (!_autoSync) {
            [Utils linkFileAtPath:self.lpath to:[SeafStorage.sharedObject documentPath:oid] error:nil];
            // files.app menory limit 15MB, reSizeImage will use more than 15MB
            // resize thumb while reaching memory limit in share extension
            if ([[Utils currentBundleIdentifier] isEqualToString:@"com.seafile.seafilePro"]) {
                [self saveThumbToLocal:oid];
            }
            
        } else {
            // For auto sync photos, release local cache files immediately.
            [self cleanup];
        }
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

- (void)uploadRequest:(NSMutableURLRequest *)request withConnection:(SeafConnection *)connection
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.lpath]) {
        Debug("Upload failed: local file %@ not exist.", self.lpath);
        [self finishUpload:NO oid:nil error:nil];
        return;
    }
    __weak __typeof__ (self) wself = self;
    self.task = [connection.sessionMgr uploadTaskWithStreamedRequest:request progress:^(NSProgress * _Nonnull uploadProgress) {
        __strong __typeof (wself) sself = wself;
        [sself updateProgress:uploadProgress];
    } completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        __strong __typeof (wself) sself = wself;
        NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
        if (error && resp.statusCode == 200) {
            Debug("Error:%@, %@, %@", error, response, error.userInfo);
            error = nil;
        }
        if (error) {
            Debug("Upload failed :%@,code=%ld, res=%@", error, (long)resp.statusCode, responseObject);
            if (resp.statusCode == HTTP_ERR_REPO_UPLOAD_PASSWORD_EXPIRED || resp.statusCode == HTTP_ERR_REPO_DOWNLOAD_PASSWORD_EXPIRED) {
                // Refresh passwords when expired
                [connection refreshRepoPasswords];
            }
            [sself showDeserializedError:error];
            [sself finishUpload:NO oid:nil error:error];
        } else {
            NSString *oid = nil;
            if ([responseObject isKindOfClass:[NSArray class]]) {
                oid = [[responseObject objectAtIndex:0] objectForKey:@"id"];
            } else if ([responseObject isKindOfClass:[NSDictionary class]]) {
                oid = [responseObject objectForKey:@"id"];
            }
            if (!oid || oid.length < 1) oid = [[NSUUID UUID] UUIDString];
            Debug("Successfully upload file:%@ autosync:%d oid=%@, responseObject=%@", self.name, self.autoSync, oid, responseObject);
            [sself finishUpload:YES oid:oid error:nil];
        }
    }];

    [_task resume];
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
        [formData appendPartWithFileURL:[NSURL fileURLWithPath:self.lpath] name:@"file" error:&error];
        if (error != nil)
            Debug("error: %@", error);
    } error:nil];
    [self uploadRequest:request withConnection:connection];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (![keyPath isEqualToString:@"fractionCompleted"] || ![object isKindOfClass:[NSProgress class]]) return;
    NSProgress *progress = (NSProgress *)object;
    float fraction = 0;
    if (_rawblksurl) {
        fraction = 1.0f*(progress.fractionCompleted + _blkidx)/self.missingblocks.count;
    } else {
        fraction = progress.fractionCompleted;
    }
    _uProgress = fraction;
    [self uploadProgress:fraction];
}

- (BOOL)chunkFile:(NSString *)path repo:(SeafRepo *)repo blockids:(NSMutableArray *)blockids paths:(NSMutableArray *)paths
{
    NSString *password = [repo->connection getRepoPassword:repo.repoId];
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

- (void)uploadByBlocks:(SeafConnection *)connection url:(NSString *)surl uploadpath:(NSString *)uploadpath blocks:(NSArray *)blockids paths:(NSArray *)paths update:(BOOL)update
{
    NSMutableURLRequest *request = [[SeafConnection requestSerializer] multipartFormRequestWithMethod:@"POST" URLString:surl parameters:nil constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        if (update) {
            [formData appendPartWithFormData:[@"1" dataUsingEncoding:NSUTF8StringEncoding] name:@"replace"];
        }
        [formData appendPartWithFormData:[uploadpath dataUsingEncoding:NSUTF8StringEncoding] name:@"parent_dir"];
        [formData appendPartWithFormData:[self.name dataUsingEncoding:NSUTF8StringEncoding] name:@"file_name"];
        [formData appendPartWithFormData:[[NSString stringWithFormat:@"%lld", [Utils fileSizeAtPath1:self.lpath]] dataUsingEncoding:NSUTF8StringEncoding] name:@"file_size"];
        [formData appendPartWithFormData:[@"n8ba38951c9ba66418311a25195e2e380" dataUsingEncoding:NSUTF8StringEncoding] name:@"csrfmiddlewaretoken"];

        Debug("surl:%@ parent_dir:%@, blocks: %@", surl, uploadpath, blockids);
        for (NSString *path in paths) {
            [formData appendPartWithFileURL:[NSURL fileURLWithPath:path] name:@"file" error:nil];
        }
    } error:nil];

    [self uploadRequest:request withConnection:connection];
}

- (void)uploadBlocksCommit:(SeafConnection *)connection
{
    NSString *url = _commiturl;
    NSMutableURLRequest *request = [[SeafConnection requestSerializer] multipartFormRequestWithMethod:@"POST" URLString:url parameters:nil constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        [formData appendPartWithFormData:[@"n8ba38951c9ba66418311a25195e2e380" dataUsingEncoding:NSUTF8StringEncoding] name:@"csrfmiddlewaretoken"];
        if (self.overwrite) {
            [formData appendPartWithFormData:[@"1" dataUsingEncoding:NSUTF8StringEncoding] name:@"replace"];
        }
        [formData appendPartWithFormData:[self.uploadpath dataUsingEncoding:NSUTF8StringEncoding] name:@"parent_dir"];
        [formData appendPartWithFormData:[self.name dataUsingEncoding:NSUTF8StringEncoding] name:@"file_name"];
        [formData appendPartWithFormData:[[NSString stringWithFormat:@"%lld", [Utils fileSizeAtPath1:self.lpath]] dataUsingEncoding:NSUTF8StringEncoding] name:@"file_size"];
        [formData appendPartWithFormData:[@"n8ba38951c9ba66418311a25195e2e380" dataUsingEncoding:NSUTF8StringEncoding] name:@"csrfmiddlewaretoken"];
        [formData appendPartWithFormData:[Utils JSONEncode:self.allblocks] name:@"blockids"];
        Debug("url:%@ parent_dir:%@, %@", url, self.uploadpath, [[NSString alloc] initWithData:[Utils JSONEncode:self.allblocks] encoding:NSUTF8StringEncoding]);
    } error:nil];
    
    NSURLSessionDataTask *task = [connection.sessionMgr dataTaskWithRequest:request uploadProgress:^(NSProgress * _Nonnull uploadProgress) {
        
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
            Debug("Successfully upload file:%@ autosync:%d oid=%@, responseObject=%@", self.name, self.autoSync, oid, responseObject);
            [self finishUpload:YES oid:oid error:nil];
        }
    }];
    [task resume];
}

- (void)updateProgress:(NSProgress *)progress
{
    if (_progress) {
        [_progress removeObserver:self
                       forKeyPath:@"fractionCompleted"
                          context:NULL];
    }

    _progress = progress;
    if (progress) {
        [_progress addObserver:self
                    forKeyPath:@"fractionCompleted"
                       options:NSKeyValueObservingOptionNew
                       context:NULL];
    }
}

- (void)uploadRawBlocks:(SeafConnection *)connection
{
    long count = MIN(3, (self.missingblocks.count - _blkidx));
    Debug("upload idx %ld, total: %ld, %ld", _blkidx, (long)self.missingblocks.count, count);
    if (count == 0) {
        [self uploadBlocksCommit:connection];
        return;
    }

    NSArray *arr = [self.missingblocks subarrayWithRange:NSMakeRange(_blkidx, count)];
    NSMutableURLRequest *request = [[SeafConnection requestSerializer] multipartFormRequestWithMethod:@"POST" URLString:_rawblksurl parameters:nil constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        [formData appendPartWithFormData:[@"n8ba38951c9ba66418311a25195e2e380" dataUsingEncoding:NSUTF8StringEncoding] name:@"csrfmiddlewaretoken"];
        for (NSString *blockid in arr) {
            NSString *blockpath = [self blockPath:blockid];
            [formData appendPartWithFileURL:[NSURL fileURLWithPath:blockpath] name:@"file" error:nil];
        }
    } error:nil];

    __weak __typeof__ (self) wself = self;
    self.task = [connection.sessionMgr uploadTaskWithStreamedRequest:request progress:^(NSProgress * _Nonnull uploadProgress) {
        __strong __typeof (wself) sself = wself;
        [sself updateProgress:uploadProgress];
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
    
    [_task resume];
}

- (void)uploadLargeFileByBlocks:(SeafRepo *)repo path:(NSString *)uploadpath
{
    NSMutableArray *blockids = [[NSMutableArray alloc] init];
    NSMutableArray *paths = [[NSMutableArray alloc] init];
    _uploadpath = uploadpath;
    if (![self chunkFile:self.lpath repo:repo blockids:blockids paths:paths]) {
        Debug("Failed to chunk file");
        [self finishUpload:NO oid:nil error:[Utils defaultError]];
        return;
    }
    self.allblocks = blockids;
    NSString* upload_url = [NSString stringWithFormat:API_URL"/repos/%@/upload-blks-link/?p=%@", repo.repoId, uploadpath.escapedUrl];
    NSString *form = [NSString stringWithFormat: @"blklist=%@", [blockids componentsJoinedByString:@","]];
    [repo->connection sendPost:upload_url form:form success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        Debug("upload largefile by blocks, JSON: %@", JSON);
        self.rawblksurl = [JSON objectForKey:@"rawblksurl"];
        self.commiturl = [JSON objectForKey:@"commiturl"];
        self.missingblocks = [JSON objectForKey:@"blklist"];
        self.blkidx = 0;
        [self uploadRawBlocks:repo->connection];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        Debug("Failed to upload: %@", error);
        [self finishUpload:NO oid:nil error:error];
    }];
}

- (void)upload:(SeafConnection *)connection repo:(NSString *)repoId path:(NSString *)uploadpath
{
    if (![Utils fileExistsAtPath:self.lpath]) {
        Warning("File %@ no existed", self.lpath);
        self.retryable = false;
        return [self uploadComplete:nil error:[Utils defaultError]];
    }
    SeafRepo *repo = [connection getRepo:repoId];
    if (!repo) {
        Warning("Repo %@ does not exist", repoId);
        self.retryable = false;
        return [self uploadComplete:nil error:[Utils defaultError]];
    }

    @synchronized (self) {
        if (self.isUploading || self.isUploaded)
            return;
        _uploading = YES;
        _uProgress = 0;
    }
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.lpath error:nil];
    _filesize = attrs.fileSize;
    [self uploadProgress:0];

    if (_filesize > LARGE_FILE_SIZE) {
        Debug("upload large file %@ by block: %lld", self.name, _filesize);
        return [self uploadLargeFileByBlocks:repo path:uploadpath];
    }
    BOOL byblock = [connection shouldLocalDecrypt:repo.repoId];
    if (byblock) {
        Debug("upload Local decrypt %@ by block: %lld", self.name, _filesize);
        return [self uploadLargeFileByBlocks:repo path:uploadpath];
    }
    NSString* upload_url = [NSString stringWithFormat:API_URL"/repos/%@/upload-link/", repoId];
    upload_url = [upload_url stringByAppendingFormat:@"?p=%@", uploadpath.escapedUrl];
    Debug("upload file size: %lld %@ %@", _filesize, self.lpath, upload_url);
    [connection sendRequest:upload_url success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         NSString *url = [JSON stringByAppendingString:@"?ret-json=true"];
         Debug("Upload file %@ %@, %@ overwrite=%d, byblock=%d, delegate%@\n", self.name, url, uploadpath, self.overwrite, byblock, self.delegate);
         [self uploadByFile:connection url:url path:uploadpath update:self.overwrite];
     }
                    failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         Warning("Failed to upload file %@: %@", self.lpath, error);
         [self finishUpload:NO oid:nil error:error];
     }];
}

- (BOOL)runable
{
    if (!_udir) return false;
    [self checkAsset];
    if (![Utils fileExistsAtPath:self.lpath]) return false;
    if (self.autoSync && _udir->connection.wifiOnly)
        return [[AFNetworkReachabilityManager sharedManager] isReachableViaWiFi];
    else
        return [[AFNetworkReachabilityManager sharedManager] isReachable];
}

- (void)run:(TaskCompleteBlock _Nullable)completeBlock
{
    [self checkAsset];
    self.taskCompleteBlock = completeBlock;
    if (!completeBlock) {
        self.taskCompleteBlock = ^(id<SeafTask> task, BOOL result) {};
    }

    if (!self.udir.repoId || !self.udir.path) {
        return completeBlock(self, false);
    }
    [self upload:self.udir->connection repo:self.udir.repoId path:self.udir.path];
}

- (void)setPHAsset:(PHAsset *)asset url:(NSURL *)url {
    _asset = asset;
    _assetURL = url;
    _assetIdentifier = asset.localIdentifier;
    _starred = asset.isFavorite;
}

- (void)checkAsset {
    if (_asset) {
        @synchronized(self) {
            if (![Utils checkMakeDir:[self.lpath stringByDeletingLastPathComponent]]) {
                [self finishUpload:false oid:nil error:nil];
            }
            if (_asset.mediaType == PHAssetMediaTypeVideo) {
                [self getVideoForAsset];
            } else if (_asset.mediaType == PHAssetMediaTypeImage) {
                [self getImageDataForAsset];
            }
        }
        Debug("asset file %@ size: %lld, lpath: %@", _asset.localIdentifier, _filesize, self.lpath);
    }
}

- (void)getImageDataForAsset {
    __weak typeof(self) weakSelf = self;
    self.requestOptions.progressHandler = ^(double progress, NSError * _Nullable error, BOOL * _Nonnull stop, NSDictionary * _Nullable info) {
        if (error) {
            Debug("Failed to get image data: %@", error);
            [weakSelf finishUpload:false oid:nil error:nil];
        }
    };
    
    [[PHImageManager defaultManager] requestImageDataForAsset:_asset options:self.requestOptions resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
        if (imageData) {
            if (@available(iOS 10.0, *)) {
                if (![self uploadHeic] && [dataUTI isEqualToString:@"public.heic"]) {// HEIC available after iOS11
                    self->_lpath = [self.lpath stringByReplacingOccurrencesOfString:@"HEIC" withString:@"JPG"];
                }
                CIImage* ciImage = [CIImage imageWithData:imageData];
                if (![Utils writeCIImage:ciImage toPath:self.lpath]) {
                    [self finishUpload:false oid:nil error:nil];
                }
            } else {
                if (![Utils writeDataWithMeta:imageData toPath:self.lpath]) {
                    [self finishUpload:false oid:nil error:nil];
                }
            }
            self->_filesize = [Utils fileSizeAtPath1:self.lpath];
        } else {
            [self finishUpload:false oid:nil error:nil];
        }
        self->_asset = nil;
    }];
}

- (UIImage *)getThumbImageFromAsset {
    __block UIImage *img = nil;
    if (_asset) {
        CGSize size = CGSizeMake(THUMB_SIZE * (int)[UIScreen mainScreen].scale, THUMB_SIZE * (int)[UIScreen mainScreen].scale);
        [[PHImageManager defaultManager] requestImageForAsset:_asset targetSize:size contentMode:PHImageContentModeDefault options:self.requestOptions resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            img = result;
        }];
    }
    return img;
}

- (void)getVideoForAsset {
    PHVideoRequestOptions *options = [PHVideoRequestOptions new];
    options.networkAccessAllowed = YES;
    options.version = PHVideoRequestOptionsVersionOriginal;
    options.progressHandler = ^(double progress, NSError * _Nullable error, BOOL * _Nonnull stop, NSDictionary * _Nullable info) {
        if (error) {
            Debug("Failed to get video: %@", error);
            [self finishUpload:false oid:nil error:nil];
        }
    };
    
    [[PHImageManager defaultManager] requestAVAssetForVideo:_asset options:options resultHandler:^(AVAsset * _Nullable asset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
        if ([asset isKindOfClass:[AVURLAsset class]]) {
            [Utils checkMakeDir:[self.lpath stringByDeletingLastPathComponent]];
            BOOL result =  [Utils copyFile:[(AVURLAsset *)asset URL] to:[NSURL fileURLWithPath:self.lpath]];
            if (!result) {
                [self finishUpload:false oid:nil error:nil];
            }
        } else {
            [self finishUpload:false oid:nil error:nil];
        }
        self->_filesize = [Utils fileSizeAtPath1:self.lpath];
        self->_asset = nil;
    }];
}

#pragma mark - QLPreviewItem
- (NSString *)previewItemTitle
{
    return self.name;
}

- (NSURL *)previewItemURL
{
    if (_preViewURL)
        return _preViewURL;

    [self checkAsset];
    if (![self.mime hasPrefix:@"text"]) {
        _preViewURL = [NSURL fileURLWithPath:self.lpath];
    } else if ([self.mime hasSuffix:@"markdown"]) {
        _preViewURL = [NSURL fileURLWithPath:[SeafileBundle() pathForResource:@"htmls/view_markdown" ofType:@"html"]];
    } else if ([self.mime hasSuffix:@"seafile"]) {
        _preViewURL = [NSURL fileURLWithPath:[SeafileBundle() pathForResource:@"htmls/view_seaf" ofType:@"html"]];
    } else {
        NSString *utf16Path = [SeafStorage.sharedObject.tempDir stringByAppendingPathComponent:self.name];
        if ([Utils tryTransformEncoding:utf16Path fromFile:self.lpath])
            _preViewURL = [NSURL fileURLWithPath:utf16Path];
    }
    if (!_preViewURL)
        _preViewURL = [NSURL fileURLWithPath:self.lpath];
    return _preViewURL;
}

- (UIImage *)icon {
    UIImage *thumb = [self getThumbImageFromAsset];
    if (thumb) {
        return thumb;
    } else {
        thumb = [self isImageFile] ? self.image : nil;
        return thumb ? [Utils reSizeImage:thumb toSquare:THUMB_SIZE * (int)[UIScreen mainScreen].scale] : [UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString];
    }
}

- (UIImage *)thumb
{
    return [self icon];
}

- (void)saveThumbToLocal:(NSString *)oid {
    if (![self isImageFile]) return;
    int size = THUMB_SIZE * (int)[[UIScreen mainScreen] scale];
    NSString *thumbPath = [SeafStorage.sharedObject.thumbsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@-%d", oid, size]];
    if (![Utils fileExistsAtPath:thumbPath]) {
        NSData *data = UIImageJPEGRepresentation([self thumb], 1.0);
        [data writeToFile:thumbPath atomically:true];
    }
}

- (UIImage *)image {
    NSString *name = [@"cacheimage-ufile-" stringByAppendingString:self.name];
    NSString *cachePath = [[SeafStorage.sharedObject tempDir] stringByAppendingPathComponent:name];
    return [Utils imageFromPath:self.lpath withMaxSize:IMAGE_MAX_SIZE cachePath:cachePath];
}

- (NSURL *)exportURL
{
    [self checkAsset];
    return [NSURL fileURLWithPath:self.lpath];
}

- (NSString *)mime
{
    return [FileMimeType mimeType:self.name];
}

- (NSString *)strContent
{
    return [Utils stringContent:self.lpath];
}

- (BOOL)isDownloading
{
    return NO;
}

- (BOOL)saveStrContent:(NSString *)content
{
    _preViewURL = nil;
    return [content writeToFile:self.lpath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

+ (void)clearCache
{
    [Utils clearAllFiles:SeafStorage.sharedObject.uploadsDir];
}

- (BOOL)waitUpload {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    return self.isUploaded;
}

- (void)uploadProgress:(float)progress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate uploadProgress:self progress:progress];
        if (self.taskProgressBlock) {
            self.taskProgressBlock(self, progress);
        }
    });
}

- (void)uploadComplete:(NSString *)oid error:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionBlock) {
            self.completionBlock(self, oid, error);
        }
        if (self.taskCompleteBlock) {
            self.taskCompleteBlock(self, !error);
        }
        [self.delegate uploadComplete:!error file:self oid:oid];
    });

    dispatch_semaphore_signal(_semaphore);
}

- (UIImage *)previewImage {
    if (!_previewImage) {
        return [UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString];
    } else {
        return _previewImage;
    }
}

- (PHImageRequestOptions *)requestOptions {
    if (!_requestOptions) {
        _requestOptions = [PHImageRequestOptions new];
        _requestOptions.networkAccessAllowed = YES; // iCloud
        _requestOptions.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
        _requestOptions.synchronous = YES;
    }
    return _requestOptions;
}

@end
