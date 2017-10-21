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


static NSMutableDictionary *uploadFileAttrs = nil;


@interface SeafUploadFile ()
@property (readonly) NSString *mime;
@property (strong, readonly) NSURL *preViewURL;
@property (strong) NSURLSessionUploadTask *task;
@property (strong) NSProgress *progress;
@property long long mtime;

@property (strong) NSArray *missingblocks;
@property (strong) NSArray *allblocks;
@property (strong) NSString *commiturl;
@property (strong) NSString *rawblksurl;
@property (strong) NSString *uploadpath;
@property (nonatomic, strong) NSString *blockDir;
@property long blkidx;

@property dispatch_semaphore_t semaphore;
@property (strong, nonatomic)NSMutableDictionary *uploadAttr;
@property (nonatomic) TaskCompleteBlock taskCompleteBlock;
@property (nonatomic) TaskProgressBlock taskProgressBlock;

@end

@implementation SeafUploadFile
@synthesize assetURL = _assetURL;
@synthesize filesize = _filesize;
@synthesize lastFinishTimestamp = _lastFinishTimestamp;
@synthesize retryable = _retryable;

- (id)initWithPath:(NSString *)lpath
{
    self = [super init];
    if (self) {
        self.retryable = true;
        _lpath = lpath;
        _uProgress = 0;
        _uploading = NO;
        _autoSync = NO;
        self.overwrite = [[self.uploadAttr objectForKey:@"update"] boolValue];
        if ([self.uploadAttr objectForKey:@"mtime"] != nil) {
            self.mtime = [[self.uploadAttr objectForKey:@"mtime"] longLongValue];
        } else {
            self.mtime = [[NSDate date] timeIntervalSince1970];
        }
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

- (BOOL)editable
{
    return NO;
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

- (NSURL *)assetURL
{
    if (!_assetURL)
        _assetURL = [self.uploadAttr objectForKey:@"assetURL"];
    return _assetURL;
}

- (void)cancel
{
    Debug("Cancel uploadFile: %@", self.lpath);
    self.udir = nil;
    [self.task cancel];
    self.task = nil;
    [self clearLocalCache];
    [self clearUploadAttr:true];
}

- (void)cancelAnyLoading
{
}

- (void)clearLocalCache
{
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

- (BOOL)uploaded
{
    NSMutableDictionary *dict = self.uploadAttr;
    if (dict && [[dict objectForKey:@"result"] boolValue])
        return YES;
    return NO;
}

- (void)finishUpload:(BOOL)result oid:(NSString *)oid
{
    @synchronized(self) {
        if (!_uploading) return;
        _uploading = NO;
        self.task = nil;
        [self updateProgress:nil];
    }
    if (result && !_autoSync)
        [Utils linkFileAtPath:self.lpath to:[SeafStorage.sharedObject documentPath:oid]];

    self.rawblksurl = nil;
    self.commiturl = nil;
    self.missingblocks = nil;
    self.blkidx = 0;

    if (!self.removed && !self.autoSync) {
        NSMutableDictionary *dict = self.uploadAttr;
        if (!dict) {
            dict = [[NSMutableDictionary alloc] init];
            [Utils dict:dict setObject:self.name forKey:@"name"];
        }
        [Utils dict:dict setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]]forKey:@"utime"];
        [Utils dict:dict setObject:[NSNumber numberWithLongLong:self.mtime] forKey:@"mtime"];
        [Utils dict:dict setObject:[NSNumber numberWithBool:result] forKey:@"result"];
        [Utils dict:dict setObject:[NSNumber numberWithBool:self.autoSync] forKey:@"autoSync"];
        [self saveUploadAttr:true];
    }
    Debug("result=%d, name=%@, delegate=%@, oid=%@\n", result, self.name, _delegate, oid);
    [self uploadComplete:result oid:oid];
    if (result) {
        [self clearLocalCache];
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
        Debug("Upload failed: local file %@ not exist\n", self.lpath);
        [self finishUpload:NO oid:nil];
    }
    NSProgress *progress = nil;
    _task = [connection.sessionMgr uploadTaskWithStreamedRequest:request progress:&progress completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
        NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
        if (error && resp.statusCode == 200) {
            Debug("Error:%@, %@, %@", error, response, error.userInfo);
            error = nil;
        }
        if (error) {
            Debug("Upload failed :%@,code=%ld, res=%@\n", error, (long)resp.statusCode, responseObject);
            [self showDeserializedError:error];
            [self finishUpload:NO oid:nil];
        } else {
            NSString *oid = nil;
            if ([responseObject isKindOfClass:[NSArray class]]) {
                oid = [[responseObject objectAtIndex:0] objectForKey:@"id"];
            } else if ([responseObject isKindOfClass:[NSDictionary class]]) {
                oid = [responseObject objectForKey:@"id"];
            }
            if (!oid || oid.length < 1) oid = [[NSUUID UUID] UUIDString];
            Debug("Successfully upload file:%@ autosync:%d oid=%@, responseObject=%@", self.name, _autoSync, oid, responseObject);
            [self finishUpload:YES oid:oid];
        }
    }];

    [self updateProgress:progress];
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
        [formData appendPartWithFormData:[_uploadpath dataUsingEncoding:NSUTF8StringEncoding] name:@"parent_dir"];
        [formData appendPartWithFormData:[self.name dataUsingEncoding:NSUTF8StringEncoding] name:@"file_name"];
        [formData appendPartWithFormData:[[NSString stringWithFormat:@"%lld", [Utils fileSizeAtPath1:self.lpath]] dataUsingEncoding:NSUTF8StringEncoding] name:@"file_size"];
        [formData appendPartWithFormData:[@"n8ba38951c9ba66418311a25195e2e380" dataUsingEncoding:NSUTF8StringEncoding] name:@"csrfmiddlewaretoken"];
        [formData appendPartWithFormData:[Utils JSONEncode:self.allblocks] name:@"blockids"];
        Debug("url:%@ parent_dir:%@, %@", url, _uploadpath, [[NSString alloc] initWithData:[Utils JSONEncode:self.allblocks] encoding:NSUTF8StringEncoding]);
    } error:nil];
    NSURLSessionDataTask *task = [connection.sessionMgr dataTaskWithRequest:request completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
        if (error) {
            Debug("Failed to upload blocks: %@", error);
            [self finishUpload:NO oid:nil];
        } else {
            NSString *oid = nil;
            if ([responseObject isKindOfClass:[NSArray class]]) {
                oid = [[responseObject objectAtIndex:0] objectForKey:@"id"];
            } else if ([responseObject isKindOfClass:[NSDictionary class]]) {
                oid = [responseObject objectForKey:@"id"];
            }
            if (!oid || oid.length < 1) oid = [[NSUUID UUID] UUIDString];
            Debug("Successfully upload file:%@ autosync:%d oid=%@, responseObject=%@", self.name, _autoSync, oid, responseObject);
            [self finishUpload:YES oid:oid];
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

    NSProgress *progress = nil;
    _task = [connection.sessionMgr uploadTaskWithStreamedRequest:request progress:&progress completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
        Debug("Upload blocks %@", arr);
        NSHTTPURLResponse *resp __attribute__((unused)) = (NSHTTPURLResponse *)response;
        if (error) {
            Debug("Upload failed :%@,code=%ld, res=%@\n", error, (long)resp.statusCode, responseObject);
            [self showDeserializedError:error];
            [self finishUpload:NO oid:nil];
        } else {
            _blkidx += count;
            [self performSelector:@selector(uploadRawBlocks:) withObject:connection afterDelay:0.0];
        }
    }];
    [self updateProgress:progress];
    [_task resume];
}

- (void)uploadLargeFileByBlocks:(SeafRepo *)repo path:(NSString *)uploadpath
{
    NSMutableArray *blockids = [[NSMutableArray alloc] init];
    NSMutableArray *paths = [[NSMutableArray alloc] init];
    _uploadpath = uploadpath;
    if (![self chunkFile:self.lpath repo:repo blockids:blockids paths:paths]) {
        Debug("Failed to chunk file");
        [self finishUpload:NO oid:nil];
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
        [self finishUpload:NO oid:nil];
    }];
}

- (void)upload:(SeafConnection *)connection repo:(NSString *)repoId path:(NSString *)uploadpath
{
    if (![Utils fileExistsAtPath:self.lpath]) {
        Warning("File %@ no existed", self.lpath);
        self.retryable = false;
        return [self uploadComplete:false oid:nil];
    }
    SeafRepo *repo = [connection getRepo:repoId];
    if (!repo) {
        Warning("Repo %@ does not exist", repoId);
        self.retryable = false;
        return [self uploadComplete:false oid:nil];
    }

    @synchronized (self) {
        if (_uploading || self.uploaded)
            return;
        _uploading = YES;
        _uProgress = 0;
    }
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.lpath error:nil];
    _filesize = attrs.fileSize;
    [self uploadProgress:0];

    if (_filesize > LARGE_FILE_SIZE && connection.isChunkSupported) {
        Debug("upload large file %@ by block: %lld", self.name, _filesize);
        return [self uploadLargeFileByBlocks:repo path:uploadpath];
    }
    BOOL byblock = [connection shouldLocalDecrypt:repo.repoId];
    NSString* upload_url = [NSString stringWithFormat:API_URL"/repos/%@/upload-", repoId];
    if (byblock)
        upload_url = [upload_url stringByAppendingString:@"blks-link/"];
    else
        upload_url = [upload_url stringByAppendingString:@"link/"];

    upload_url = [upload_url stringByAppendingFormat:@"?p=%@", uploadpath.escapedUrl];
    Debug("upload file size: %lld %@ %@", _filesize, self.lpath, upload_url);
    [connection sendRequest:upload_url success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         NSString *url = [JSON stringByAppendingString:@"?ret-json=true"];
         Debug("Upload file %@ %@, %@ overwrite=%d, byblock=%d, delegate%@\n", self.name, url, uploadpath, self.overwrite, byblock, _delegate);
         if (byblock) {
             NSMutableArray *blockids = [[NSMutableArray alloc] init];
             NSMutableArray *paths = [[NSMutableArray alloc] init];
             if ([self chunkFile:self.lpath repo:repo blockids:blockids paths:paths]) {
                 [self uploadByBlocks:connection url:url uploadpath:uploadpath blocks:blockids paths:paths update:self.overwrite];
             } else {
                 [self finishUpload:NO oid:nil];
             }
         } else {
             [self uploadByFile:connection url:url path:uploadpath update:self.overwrite];
         }
     }
                    failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         Warning("Failed to upload file %@: %@", self.lpath, error);
         [self finishUpload:NO oid:nil];
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

    if (!self.udir) {
        return completeBlock(self, false);
    }
    [self upload:self.udir->connection repo:self.udir.repoId path:self.udir.path];
}

- (void)setAsset:(ALAsset *)asset url:(NSURL *)url
{
    _asset = asset;
    _assetURL = url;
}

- (void)checkAsset
{
    NSMutableDictionary *dict = [SeafUploadFile uploadFileAttrs];
    if (_asset) {
        @synchronized(dict) {
            BOOL ret = [Utils writeDataToPath:self.lpath andAsset:self.asset];
            if (!ret) {
                Warning("Failed to write asset to file.");
                [self finishUpload:false oid:nil];
                return;
            }
        }
        _filesize = [Utils fileSizeAtPath1:self.lpath];
        Debug("asset file %@ size: %lld, lpath: %@", _asset.defaultRepresentation.url, _filesize, self.lpath);
        _asset = nil;
    }
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
        NSString *encodePath = [SeafStorage.sharedObject.tempDir stringByAppendingPathComponent:self.name];
        if ([Utils tryTransformEncoding:encodePath fromFile:self.lpath])
            _preViewURL = [NSURL fileURLWithPath:encodePath];
    }
    if (!_preViewURL)
        _preViewURL = [NSURL fileURLWithPath:self.lpath];
    return _preViewURL;
}

- (UIImage *)icon
{
    if (_asset)
        return [UIImage imageWithCGImage:_asset.thumbnail];

    UIImage *img = [self isImageFile] ? self.image : nil;
    return img ? [Utils reSizeImage:img toSquare:32.0f] : [UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString];
}

- (UIImage *)thumb
{
    return [self icon];
}

- (UIImage *)image
{
    if (_asset)
        return [UIImage imageWithCGImage:_asset.defaultRepresentation.fullResolutionImage];

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

+ (NSMutableDictionary *)uploadFileAttrs
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *attrsFile = [[SeafStorage.sharedObject rootPath] stringByAppendingPathComponent:@"uploadfiles.plist"];
        uploadFileAttrs = [[NSMutableDictionary alloc] initWithContentsOfFile:attrsFile];
        if (!uploadFileAttrs)
            uploadFileAttrs = [[NSMutableDictionary alloc] init];
    });
    return uploadFileAttrs;
}

+ (BOOL)saveAttrs
{
    NSString *attrsFile = [[SeafStorage.sharedObject rootPath] stringByAppendingPathComponent:@"uploadfiles.plist"];
    return [[SeafUploadFile uploadFileAttrs] writeToFile:attrsFile atomically:true];
}

+ (void)clearCache
{
    [Utils clearAllFiles:SeafStorage.sharedObject.uploadsDir];
    NSString *attrsFile = [[SeafStorage.sharedObject rootPath] stringByAppendingPathComponent:@"uploadfiles.plist"];

    [Utils removeFile:attrsFile];
    uploadFileAttrs = [[NSMutableDictionary alloc] init];
    [SeafUploadFile saveAttrs];
}

- (NSMutableDictionary *)uploadAttr
{
    if (!_uploadAttr) {
        if (self.lpath) {
            _uploadAttr = [[SeafUploadFile uploadFileAttrs] objectForKey:self.lpath];
        }

        if (!_uploadAttr) {
            _uploadAttr = [NSMutableDictionary new];
        }
    }
    return _uploadAttr;
}

- (BOOL)saveUploadAttr:(BOOL)flush
{
    [Utils dict:[SeafUploadFile uploadFileAttrs] setObject:self.uploadAttr forKey:self.lpath];
    return !flush || [SeafUploadFile saveAttrs];
}

- (BOOL)clearUploadAttr:(BOOL)flush
{
    [Utils dict:[SeafUploadFile uploadFileAttrs] setObject:nil forKey:self.lpath];
    return !flush || [SeafUploadFile saveAttrs];
}

+ (NSMutableArray *)uploadFilesForDir:(SeafDir *)dir
{
    bool changed = false;
    NSDictionary *allFiles = [[SeafUploadFile uploadFileAttrs] copy];
    NSMutableArray *files = [[NSMutableArray alloc] init];
    for (NSString *lpath in allFiles.allKeys) {
        NSDictionary *info = [allFiles objectForKey:lpath];
        if (![Utils fileExistsAtPath:lpath]) {
            [uploadFileAttrs removeObjectForKey:lpath];
            Debug("Upload file %@ not exist", lpath);
            changed = true;
            continue;
        }
        if ([dir.repoId isEqualToString:[info objectForKey:@"urepo"]] && [dir.path isEqualToString:[info objectForKey:@"upath"]]) {
            bool autoSync = [[info objectForKey:@"autoSync"] boolValue];
            SeafUploadFile *file = [dir->connection getUploadfile:lpath create:!autoSync];
            if (!file || file.asset) {
                Debug("Auto sync photos %@:%@, remove it and will reupload from beginning", file.lpath, info);
                if (file) {
                    [file clearLocalCache];
                    [file clearUploadAttr:false];
                } else {
                    [uploadFileAttrs removeObjectForKey:lpath];
                    changed = true;
                }
                continue;
            }
            file.udir = dir;
            file.overwrite = [[info objectForKey:@"update"] boolValue];
            file.autoSync = autoSync;
            [files addObject:file];
        }
    }
    if (changed) [SeafUploadFile saveAttrs];
    return files;
}

- (BOOL)waitUpload {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    return self.uploaded;
}

- (void)uploadProgress:(float)progress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate uploadProgress:self progress:progress];
        if (_taskProgressBlock) {
            _taskProgressBlock(self, progress);
        }
    });
}

- (void)uploadComplete:(BOOL)result oid:(NSString *)oid
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate uploadComplete:result file:self oid:oid];
        if (self.completionBlock) {
            self.completionBlock(result, self, oid);
        }
        if (self.taskCompleteBlock) {
            self.taskCompleteBlock(self, result);
        }
    });

    dispatch_semaphore_signal(_semaphore);
}

@end
