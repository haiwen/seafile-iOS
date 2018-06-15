//
//  SeafFile.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//
#import <Foundation/Foundation.h>
#import "SeafFile.h"
#import "SeafRepos.h"
#import "SeafThumb.h"
#import "SeafDataTaskManager.h"
#import "SeafStorage.h"

#import "FileMimeType.h"
#import "ExtentedString.h"
#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "NSData+Encryption.h"
#import "Debug.h"
#import "Utils.h"

#define THUMB_SIZE 96

@interface SeafFile()

@property (strong, readonly) NSURL *preViewURL;
@property (readonly) NSURL *exportURL;
@property (strong) NSString *downloadingFileOid;
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, strong) UIImage *thumb;
@property NSURLSessionDownloadTask *task;
@property NSURLSessionDownloadTask *thumbtask;
@property (strong) SeafUploadFile *ufile;
@property (strong) NSArray *blkids;
@property int index;

@property (readwrite, nonatomic, copy) SeafThumbCompleteBlock thumbCompleteBlock;
@property (readwrite, nonatomic, copy) SeafDownloadCompletionBlock fileDidDownloadBlock;
@property (readwrite, nonatomic) SeafUploadCompletionBlock uploadCompletionBlock;
@property (nonatomic) TaskCompleteBlock taskCompleteBlock;
@property (nonatomic) TaskProgressBlock taskProgressBlock;
@end

@implementation SeafFile
@synthesize exportURL = _exportURL;
@synthesize preViewURL = _preViewURL;
@synthesize lastFinishTimestamp = _lastFinishTimestamp;
@synthesize retryable = _retryable;
@synthesize retryCount = _retryCount;

- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    name:(NSString *)aName
                    path:(NSString *)aPath
                   mtime:(long long)mtime
                    size:(unsigned long long)size;
{
    if (self = [super initWithConnection:aConnection oid:anId repoId:aRepoId name:aName path:aPath mime:[FileMimeType mimeType:aName]]) {
        _mtime = mtime;
        _filesize = size;
        self.downloadingFileOid = nil;
        self.task = nil;
        self.retryable = true;
    }
    return self;
}

- (NSString *)detailText
{
    NSString *str = [FileSizeFormatter stringFromLongLong:self.filesize];
    if (self.mtime) {
        NSString *timeStr = [SeafDateFormatter stringFromLongLong:self.mtime];
        str = [str stringByAppendingFormat:@", %@", timeStr];
    }
    if (self.mpath) {
        if (self.ufile.isUploading)
            return [str stringByAppendingFormat:@", %@", NSLocalizedString(@"uploading", @"Seafile")];
        else
            return [str stringByAppendingFormat:@", %@", NSLocalizedString(@"modified", @"Seafile")];
    }

    return str;
}

- (BOOL)runable
{
    return true;
}

- (NSString *)accountIdentifier
{
    return self->connection.accountIdentifier;
}

- (NSString *)downloadTempPath:(NSString *)objId
{
    return [SeafStorage.sharedObject.tempDir stringByAppendingPathComponent:objId];
}

- (NSString *)thumbPath: (NSString *)objId
{
    if (!self.oid) return nil;
    int size = THUMB_SIZE * (int)[[UIScreen mainScreen] scale];
    return [SeafStorage.sharedObject.thumbsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@-%d", objId, size]];
}

- (void)updateWithEntry:(SeafBase *)entry
{
    SeafFile *file = (SeafFile *)entry;
    if ([self.oid isEqualToString:entry.oid])
        return;
    [super updateWithEntry:entry];
    _filesize = file.filesize;
    _mtime = file.mtime;
    self.state = SEAF_DENTRY_INIT;
    [self loadCache];
}

- (void)setOoid:(NSString *)ooid
{
    super.ooid = ooid;
    _exportURL = nil;
    _preViewURL = nil;
}

- (BOOL)isDownloading
{
    return self.downloadingFileOid != nil || self.state == SEAF_DENTRY_LOADING;
}

- (void)removeBlock:(NSString *)blkId
{
    [[NSFileManager defaultManager] removeItemAtPath:[SeafStorage.sharedObject blockPath:blkId] error:nil];
}
- (void)clearDownloadContext
{
    if (_progress) {
        [_progress removeObserver:self
                       forKeyPath:@"fractionCompleted"
                          context:NULL];
        _progress = nil;
    }
    self.downloadingFileOid = nil;
    self.task = nil;
    self.index = 0;
    for (int i = 0; i < self.blkids.count; ++i) {
        [self removeBlock:[self.blkids objectAtIndex:i]];
    }
    self.blkids = nil;
}

- (void)finishDownload:(NSString *)ooid
{
    [self clearDownloadContext];
    Debug("%@ ooid=%@, self.ooid=%@, oid=%@", self.name, ooid, self.ooid, self.oid);
    BOOL updated = ![ooid isEqualToString:self.ooid];
    [self setOoid:ooid];
    self.state = SEAF_DENTRY_SUCCESS;
    self.oid = ooid;
    [self downloadComplete:updated];
}

- (void)failedDownload:(NSError *)error
{
    [self clearDownloadContext];
    self.state = SEAF_DENTRY_FAILURE;
    [self downloadFailed:error];
}

- (void)cancelThumb
{
    [_thumbtask cancel];
    _thumbtask = nil;
}
- (void)finishDownloadThumb:(BOOL)success completeBlock:(SeafThumbCompleteBlock)completeBlock
{
    Debug("finishDownloadThumb: %@ success: %d", self.name, success);
    if (self.thumbCompleteBlock)
        self.thumbCompleteBlock(success);

    if (completeBlock) {
        completeBlock(success);
    }
    _thumbtask = nil;
    if (success || _icon || self.image) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate download:self complete:false];
        });
    }
}

/*
 curl -D a.txt -H 'Cookie:sessionid=7eb567868b5df5b22b2ba2440854589c' http://127.0.0.1:8000/api/file/640fd90d-ef4e-490d-be1c-b34c24040da7/8dd0a3be9289aea6795c1203351691fcc1373fbb/

 */
- (void)downloadByFile
{
    [connection sendRequest:[NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@", self.repoId, [self.path escapedUrl]] success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         NSString *url = JSON;
         NSString *curId = [[response allHeaderFields] objectForKey:@"oid"];
         Debug("Downloading file from file server url: %@, state:%d %@, %@", JSON, self.state, self.ooid, curId);
         if (!curId) curId = self.oid;
         if ([[NSFileManager defaultManager] fileExistsAtPath:[SeafStorage.sharedObject documentPath:curId]]) {
             Debug("file %@ already exist curId=%@, ooid=%@", self.name, curId, self.ooid);
             [self finishDownload:curId];
             return;
         }

         @synchronized (self) {
             if (self.state != SEAF_DENTRY_LOADING) {
                 return Info("Download file %@ already canceled", self.name);
             }
             if (self.downloadingFileOid) {// Already downloading
                 Debug("Already downloading %@", self.downloadingFileOid);
                 return;
             }
             self.downloadingFileOid = curId;
         }
         [self downloadProgress:0];
         url = [url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
         NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:DEFAULT_TIMEOUT];
         NSProgress *progress = nil;
         NSString *target = [SeafStorage.sharedObject documentPath:self.downloadingFileOid];
         Debug("Download file %@  %@ from %@, target:%@ %d", self.name, self.downloadingFileOid, url, target, [Utils fileExistsAtPath:target]);

         _task = [connection.sessionMgr downloadTaskWithRequest:downloadRequest progress:&progress destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
             return [NSURL fileURLWithPath:[target stringByAppendingPathExtension:@"tmp"]];
         } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
             if (!self.downloadingFileOid) {
                 return Info("Download file %@ already canceled", self.name);
             }
             if (error) {
                 Debug("Failed to download %@, error=%@, %ld", self.name, [error localizedDescription], (long)((NSHTTPURLResponse *)response).statusCode);
                 [self failedDownload:error];
             } else {
                 Debug("Successfully downloaded file:%@, %@ oid=%@, ooid=%@, delegate=%@, %@", self.name, downloadRequest.URL, self.downloadingFileOid, self.ooid, self.delegate, filePath);
                 if (![filePath.path isEqualToString:target]) {
                     [Utils removeFile:target];
                     [[NSFileManager defaultManager] moveItemAtPath:filePath.path toPath:target error:nil];
                 }
                 [self finishDownload:self.downloadingFileOid];
            }
         }];
         _progress = progress;
         [_progress addObserver:self
                    forKeyPath:@"fractionCompleted"
                       options:NSKeyValueObservingOptionNew
                       context:NULL];
         [_task resume];
     }
                    failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         self.state = SEAF_DENTRY_INIT;
         [self downloadFailed:error];
     }];
}

- (void)setThumbCompleteBlock:(nullable SeafThumbCompleteBlock)block
{
    _thumbCompleteBlock = block;
}

- (void)downloadThumb:(SeafThumbCompleteBlock _Nonnull)completeBlock
{
    SeafRepo *repo = [connection getRepo:self.repoId];
    if (repo.encrypted) return [self finishDownloadThumb:false completeBlock:completeBlock];
    int size = THUMB_SIZE * (int)[[UIScreen mainScreen] scale];
    NSString *thumburl = [NSString stringWithFormat:API_URL"/repos/%@/thumbnail/?size=%d&p=%@", self.repoId, size, self.path.escapedUrl];
    NSURLRequest *downloadRequest = [connection buildRequest:thumburl method:@"GET" form:nil];
    Debug("Request: %@", downloadRequest.URL);
    NSString *target = [self thumbPath:self.oid];

    @synchronized (self) {
        if (_thumbtask) return [self finishDownloadThumb:true completeBlock:completeBlock];
        if (self.thumb) return [self finishDownloadThumb:true completeBlock:completeBlock];

        _thumbtask = [connection.sessionMgr downloadTaskWithRequest:downloadRequest progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
            return [NSURL fileURLWithPath:[target stringByAppendingPathExtension:@"tmp"]];
        } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
            if (error) {
                Debug("Failed to download thumb %@, error=%@", self.name, error.localizedDescription);
            } else {
                if (![filePath.path isEqualToString:target]) {
                    [Utils removeFile:target];
                    [[NSFileManager defaultManager] moveItemAtPath:filePath.path toPath:target error:nil];
                }
            }
            [self finishDownloadThumb:!error completeBlock:completeBlock];
        }];
    }
    [_thumbtask resume];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (!self.downloadingFileOid || ![keyPath isEqualToString:@"fractionCompleted"] || ![object isKindOfClass:[NSProgress class]]) return;
    NSProgress *progress = (NSProgress *)object;
    float percent;
    if (self.blkids) {
        percent = (progress.fractionCompleted + self.index) *1.0f/self.blkids.count;
    } else {
        percent = progress.fractionCompleted;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self downloadProgress:percent];
    });
}

- (int)checkoutFile
{
    NSString *password = nil;
    SeafRepo *repo = [connection getRepo:self.repoId];
    if (repo.encrypted) {
        password = [connection getRepoPassword:self.repoId];
    }
    NSString *tmpPath = [self downloadTempPath:self.downloadingFileOid];
    if (![[NSFileManager defaultManager] fileExistsAtPath:tmpPath])
        [[NSFileManager defaultManager] createFileAtPath:tmpPath contents: nil attributes: nil];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:tmpPath];
    [handle truncateFileAtOffset:0];
    for (NSString *blk_id in self.blkids) {
        NSData *data = [[NSData alloc] initWithContentsOfFile:[SeafStorage.sharedObject blockPath:blk_id]];
        if (password)
            data = [data decrypt:password encKey:repo.encKey version:repo.encVersion];
        if (!data)
            return -1;
        [handle writeData:data];
    }
    [handle closeFile];
    if (!self.downloadingFileOid)
        return -1;
    [[NSFileManager defaultManager] moveItemAtPath:tmpPath toPath:[SeafStorage.sharedObject documentPath:self.downloadingFileOid] error:nil];
    return 0;
}

- (void)finishBlock:(NSString *)blkid
{
    if (!self.downloadingFileOid) {
        Debug("file download has beeen canceled.");
        [self removeBlock:blkid];
        return;
    }
    self.index ++;
    if (self.index >= self.blkids.count) {
        if ([self checkoutFile] < 0) {
            Debug("Faile to checkout out file %@\n", self.downloadingFileOid);
            self.index = 0;
            for (NSString *blk_id in self.blkids)
                [self removeBlock:blk_id];
            NSError *error = [NSError errorWithDomain:@"Faile to checkout out file" code:-1 userInfo:nil];
            [self failedDownload:error];
            return;
        }
        [self finishDownload:self.downloadingFileOid];
        return;
    }
    [self performSelector:@selector(downloadBlocks) withObject:nil afterDelay:0.0];
}

- (void)donwloadBlock:(NSString *)blk_id fromUrl:(NSString *)url
{
    if (!self.isDownloading) return;
    NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    Debug("URL: %@", downloadRequest.URL);
    NSProgress *progress = nil;
    NSString *target = [SeafStorage.sharedObject blockPath:blk_id];
    NSURLSessionDownloadTask *task = [connection.sessionMgr downloadTaskWithRequest:downloadRequest progress:&progress destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        return [NSURL fileURLWithPath:target];
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        if (error) {
            Warning("error=%@", error);
            [self failedDownload:error];
        } else {
            Debug("Successfully downloaded file %@ block:%@, filePath:%@", self.name, blk_id, filePath);
            if (![filePath.path isEqualToString:target]) {
                [[NSFileManager defaultManager] removeItemAtPath:target error:nil];
                [[NSFileManager defaultManager] moveItemAtPath:filePath.path toPath:target error:nil];
            }
            [self finishBlock:blk_id];
        }
    }];
    _progress = progress;
    [_progress addObserver:self
                forKeyPath:@"fractionCompleted"
                   options:NSKeyValueObservingOptionNew
                   context:NULL];
    [task resume];
}

- (void)downloadBlocks
{
    if (!self.isDownloading) return;
    NSString *blk_id = [self.blkids objectAtIndex:self.index];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[SeafStorage.sharedObject blockPath:blk_id]])
        return [self finishBlock:blk_id];

    NSString *link = [NSString stringWithFormat:API_URL"/repos/%@/files/%@/blks/%@/download-link/", self.repoId, self.downloadingFileOid, blk_id];
    Debug("link=%@", link);
    [connection sendRequest:link success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         NSString *url = JSON;
         [self donwloadBlock:blk_id fromUrl:url];
     } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         Warning("error=%@", error);
         [self failedDownload:error];
     }];
}


/*
 curl -D a.txt -H 'Cookie:sessionid=7eb567868b5df5b22b2ba2440854589c' http://127.0.0.1:8000/api/file/640fd90d-ef4e-490d-be1c-b34c24040da7/8dd0a3be9289aea6795c1203351691fcc1373fbb/

 */
- (void)downloadByBlocks
{
    [connection sendRequest:[NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@&op=downloadblks", self.repoId, [self.path escapedUrl]] success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         NSString *curId = [JSON objectForKey:@"file_id"];
         if ([[NSFileManager defaultManager] fileExistsAtPath:[SeafStorage.sharedObject documentPath:curId]]) {
             Debug("Already uptodate oid=%@\n", self.ooid);
             [self finishDownload:curId];
             return;
         }
         @synchronized (self) {
             if (self.state != SEAF_DENTRY_LOADING) {
                 return Info("Download file %@ already canceled", self.name);
             }
             self.downloadingFileOid = curId;
         }
         [self downloadProgress:0];
         self.blkids = [JSON objectForKey:@"blklist"];
         if (self.blkids.count <= 0) {
             [@"" writeToFile:[SeafStorage.sharedObject documentPath:self.downloadingFileOid] atomically:YES encoding:NSUTF8StringEncoding error:nil];
             [self finishDownload:self.downloadingFileOid];
         } else {
             self.index = 0;
             Debug("blks=%@", self.blkids);
             [self downloadBlocks];
         }
     }
                    failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         self.state = SEAF_DENTRY_FAILURE;
         [self downloadFailed:error];
     }];
}

- (void)run:(TaskCompleteBlock _Nullable)completeBlock
{
    self.taskCompleteBlock = completeBlock;
    self.state = SEAF_DENTRY_LOADING;
    [self downloadfile];
}

- (void)downloadfile
{
    if (connection.isChunkSupported && ([connection shouldLocalDecrypt:self.repoId] || _filesize > LARGE_FILE_SIZE)) {
        Debug("Download file %@ by blocks: %lld", self.name, _filesize);
        [self downloadByBlocks];
    } else
        [self downloadByFile];
}

- (void)realLoadContent
{
    if (!self.downloadingFileOid) {
        [self loadCache];
        [self downloadfile];
    } else {
        Debug("File %@ is already donwloading.", self.name);
    }
}

- (void)load:(id<SeafDentryDelegate>)delegate force:(BOOL)force
{
    if (delegate != nil) self.delegate = delegate;
    [self loadContent:force];
}

- (BOOL)hasCache
{
    if (self.mpath && [[NSFileManager defaultManager] fileExistsAtPath:self.mpath])
        return true;
    //Debug(".... %@ %@ %d", self.name, self.ooid, self.ooid && [[NSFileManager defaultManager] fileExistsAtPath:[SeafStorage.sharedObject documentPath:self.ooid]]);
    if (self.ooid && [[NSFileManager defaultManager] fileExistsAtPath:[SeafStorage.sharedObject documentPath:self.ooid]])
        return YES;
    self.ooid = nil;
    _preViewURL = nil;
    _exportURL = nil;
    return NO;
}


- (BOOL)isImageFile
{
    return [Utils isImageFile:self.name];
}

- (UIImage *)icon
{
    if (_icon) return _icon;
    if (self.isImageFile && self.oid) {
        if (![connection isEncrypted:self.repoId]) {
            UIImage *img = [self thumb];
            if (img)
                return _thumb;
            else if (!_thumbtask) {
                SeafThumb *thb = [[SeafThumb alloc] initWithSeafFile:self];
                [SeafDataTaskManager.sharedObject addThumbTask:thb];
            }
        } else if (self.image) {
            [self performSelectorInBackground:@selector(genThumb) withObject:nil];
        }
    }
    return [super icon];
}

- (void)genThumb
{
    _icon = [Utils reSizeImage:self.image toSquare:THUMB_SIZE];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate download:self complete:false];
    });
}

- (UIImage *)thumb
{
    if (_thumb)
        return _thumb;

    NSString *thumbpath = [self thumbPath:self.oid];
    if (thumbpath && [Utils fileExistsAtPath:thumbpath]) {
        _thumb = [UIImage imageWithContentsOfFile:thumbpath];
    }
    return _thumb;
}

- (BOOL)realLoadCache
{
    NSString *cachedMpath = [self->connection objectForKey:self.cacheKey entityName:ENTITY_FILE];
    if (cachedMpath && [[NSFileManager defaultManager] fileExistsAtPath:cachedMpath]) {
        if (!_mpath || ![_mpath isEqualToString:cachedMpath]) {
            _mpath = cachedMpath;
            _preViewURL = nil;
            _exportURL = nil;
        }
        [self autoupload];
        return true;
    } else if (self.oid && [[NSFileManager defaultManager] fileExistsAtPath:[SeafStorage.sharedObject documentPath:self.oid]]) {
        if (![self.oid isEqualToString:self.ooid])
            [self setOoid:self.oid];
        return true;
    }
    [self setOoid:nil];
    return false;
}

- (BOOL)loadCache
{
    return [self realLoadCache];
}

- (BOOL)savetoCache
{
    if (!self.mpath) {
        return NO;
    }
    return [self->connection setValue:self.mpath forKey:self.cacheKey entityName:ENTITY_FILE];
}

- (void)clearCache
{
    [self->connection removeKey:self.cacheKey entityName:ENTITY_FILE];
}

#pragma mark - QLPreviewItem
- (NSURL *)exportURL
{
    if (_exportURL && [[NSFileManager defaultManager] fileExistsAtPath:_exportURL.path])
        return _exportURL;

    if (self.mpath) {
        _exportURL = [NSURL fileURLWithPath:self.mpath];
        return _exportURL;
    }
    if (![self hasCache])
        return nil;
    @synchronized (self) {
        NSString *tempDir = [SeafStorage.sharedObject.tempDir stringByAppendingPathComponent:self.ooid];
        if (![Utils checkMakeDir:tempDir])
            return nil;
        NSString *tempFileName = [tempDir stringByAppendingPathComponent:self.name];
        Debug("File exists at %@, %d", tempFileName, [Utils fileExistsAtPath:tempFileName]);
        if ([Utils fileExistsAtPath:tempFileName]
            || [Utils linkFileAtPath:[SeafStorage.sharedObject documentPath:self.ooid] to:tempFileName error:nil]) {
            _exportURL = [NSURL fileURLWithPath:tempFileName];
        } else {
            Warning("Copy file to exportURL failed.\n");
            self.ooid = nil;
            _exportURL = nil;
        }
    }
    return _exportURL;
}

- (NSURL *)markdownPreviewItemURL
{
    _preViewURL = [NSURL fileURLWithPath:[SeafileBundle() pathForResource:@"htmls/view_markdown" ofType:@"html"]];
    return _preViewURL;
}

- (NSURL *)seafPreviewItemURL
{
    _preViewURL = [NSURL fileURLWithPath:[SeafileBundle() pathForResource:@"htmls/view_seaf" ofType:@"html"]];
    return _preViewURL;
}

- (NSURL *)previewItemURL
{
    if (_preViewURL && [Utils fileExistsAtPath:_preViewURL.path])
        return _preViewURL;

    _preViewURL = self.exportURL;
    if (!_preViewURL)
        return nil;

    if (![self.mime hasPrefix:@"text"]) {
        return _preViewURL;
    } else if ([self.mime hasSuffix:@"markdown"]) {
        return [self markdownPreviewItemURL];
    } else if ([self.mime hasSuffix:@"seafile"]) {
        return [self seafPreviewItemURL];
    }

    NSString *src = nil;
    NSString *tmpdir = nil;
    if (!self.mpath) {
        src = [SeafStorage.sharedObject documentPath:self.ooid];
    } else {
        src = self.mpath;
    }
    tmpdir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.tempDir];
    if (![Utils checkMakeDir:tmpdir])
        return _preViewURL;

    NSString *dst = [tmpdir stringByAppendingPathComponent:self.name];
    @synchronized (self) {
        if ([Utils fileExistsAtPath:dst]
            || [Utils tryTransformEncoding:dst fromFile:src]) {
            _preViewURL = [NSURL fileURLWithPath:dst];
        }
    }

    return _preViewURL;
}

- (NSString *)previewItemTitle
{
    return self.name;
}

- (NSString *)mime
{
    return [FileMimeType mimeType:self.name];
}

- (BOOL)editable
{
    return [[connection getRepo:self.repoId] editable] && [self.mime hasPrefix:@"text/"];
}

- (UIImage *)image
{
    if (!self.ooid)
        return nil;
    NSString *path = [SeafStorage.sharedObject documentPath:self.ooid];
    NSString *cachePath = [[SeafStorage.sharedObject tempDir] stringByAppendingPathComponent:self.ooid];
    return [Utils imageFromPath:path withMaxSize:IMAGE_MAX_SIZE cachePath:cachePath andFileName:self.name];
}

- (long long)filesize
{
    return (self.mpath) ? [Utils fileSizeAtPath1:self.mpath] : _filesize;
}

- (long long)mtime
{
    if (self.mpath) {
        NSDictionary* fileAttribs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.mpath error:nil];
        NSDate *date = [fileAttribs objectForKey:NSFileModificationDate];
        return [date timeIntervalSince1970];
    }
    return _mtime;
}

- (void)unload
{

}

- (NSString *)strContent
{
    return [Utils stringContent:self.cachePath];
}

- (NSString *)cachePath
{
    if (self.mpath)
        return self.mpath;
    if (self.ooid)
        return [SeafStorage.sharedObject documentPath:self.ooid];
    return nil;
}

- (void)autoupload
{
    if (self.ufile && self.ufile.isUploading)  return;
    [self update:self.udelegate];
}

- (void)setMpath:(NSString *)mpath
{
    //Debug("filesize=%lld mtime=%lld, mpath=%@", self.filesize, self.mtime, mpath);
    @synchronized (self) {
        _mpath = mpath;
        [self savetoCache];
        _preViewURL = nil;
        _exportURL = nil;
    }
}

- (BOOL)saveStrContent:(NSString *)content
{
    NSString *dir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.editDir];
    if (![Utils checkMakeDir:dir])
        return NO;

    NSString *newpath = [dir stringByAppendingPathComponent:self.name];
    NSError *error = nil;
    BOOL ret = [content writeToFile:newpath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (ret) {
        [self setMpath:newpath];
        [self autoupload];
    }
    return ret;
}

- (BOOL)uploadFromFile:(NSURL *_Nonnull)url
{
    Debug("file %@ from:%@, repo:%@, account:%@ %@", self.name, url, self.repoId, connection.address, connection.username);
    NSString *dir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.editDir];
    if (![Utils checkMakeDir:dir])
        return NO;

    NSString *newpath = [dir stringByAppendingPathComponent:self.name];
    NSError *error = nil;
    BOOL ret = [Utils linkFileAtPath:url.path to:newpath error:&error];
    if (ret) {
        [self setMpath:newpath];
        [self autoupload];
    } else {
        Warning("Failed to copy file %@ to %@: %@", url, newpath, error);
    }
    return ret;
}

- (NSDictionary *)toDict
{
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:connection.address, @"conn_url",  connection.username, @"conn_username",
                          self.oid, @"id", self.repoId, @"repoid", self.path, @"path", [NSNumber numberWithLongLong:self.mtime ], @"mtime", [NSNumber numberWithLongLong:self.filesize], @"size", nil];
    Debug("dict=%@", dict);
    return dict;
}

- (BOOL)testupload
{
    NSString *dir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.editDir];
    if (![Utils checkMakeDir:dir])
        return NO;
    NSString *newpath = [dir stringByAppendingPathComponent:self.name];
    NSError *error = nil;

    BOOL ret = [[NSFileManager defaultManager] copyItemAtPath:[SeafStorage.sharedObject documentPath:self.ooid] toPath:newpath error:&error];
    Debug("ret=%d newpath=%@, %@\n", ret, newpath, error);
    if (ret) {
        [self setMpath:newpath];
        [self autoupload];
    }
    return ret;
}

- (BOOL)isStarred
{
    return [connection isStarred:self.repoId path:self.path];
}

- (void)setStarred:(BOOL)starred
{
    [connection setStarred:starred repo:self.repoId path:self.path];
}

- (void)update:(id<SeafFileUpdateDelegate>)dg
{
    if (!self.mpath)   return;
    self.udelegate = dg;
    if (!self.ufile) {
        self.ufile = [[SeafUploadFile alloc] initWithPath:self.mpath];
        self.ufile.delegate = self;
        self.ufile.overwrite = YES;
        self.ufile.completionBlock = self.uploadCompletionBlock;
        NSString *path = [self.path stringByDeletingLastPathComponent];
        SeafDir *udir = [[SeafDir alloc] initWithConnection:connection oid:nil repoId:self.repoId perm:@"rw" name:path.lastPathComponent path:path];
        self.ufile.udir = udir;
        [udir addUploadFile:self.ufile];
    }
    Debug("Update file %@, to %@", self.ufile.lpath, self.ufile.udir.path);
    [SeafDataTaskManager.sharedObject addUploadTask:self.ufile];
}

- (void)deleteCache
{
    _exportURL = nil;
    _preViewURL = nil;
    _shareLink = nil;
    if (self.ooid) {
        [[NSFileManager defaultManager] removeItemAtPath:[SeafStorage.sharedObject documentPath:self.ooid] error:nil];
        NSString *tempDir = [SeafStorage.sharedObject.tempDir stringByAppendingPathComponent:self.ooid];
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    }
    [Utils clearAllFiles:SeafStorage.sharedObject.blocksDir];
    self.ooid = nil;
    self.state = SEAF_DENTRY_INIT;
}

- (void)cancel
{
    [self cancelAnyLoading];
}

- (void)cancelAnyLoading
{
    Debug("Cancel download %@, %@, state:%d", self.path, self.downloadingFileOid, self.state);
    if (self.state == SEAF_DENTRY_LOADING) {
        self.state = SEAF_DENTRY_INIT;
        [self.task cancel];
        [self clearDownloadContext];
        [self downloadFailed:nil];
    }
}

#pragma mark - SeafUploadDelegate
- (void)uploadProgress:(SeafFile *)file progress:(float)progress
{
    [self.udelegate updateProgress:self progress:progress];
}

- (void)uploadComplete:(BOOL)success file:(SeafUploadFile *)file oid:(NSString *)oid
{
    Debug("%@ file %@ upload success oid: %@, %@", self, self.name, oid, self.udelegate);
    id<SeafFileUpdateDelegate> dg = self.udelegate;
    if (!success) {
        return [dg updateComplete:self result:false];
    }
    [self.ufile cleanup];
    self.ufile = nil;
    self.udelegate = nil;
    self.state = SEAF_DENTRY_INIT;
    self.ooid = oid;
    self.oid = oid;
    _filesize = file.filesize;
    _mtime = file.mtime;
    [self setMpath:nil];
    [dg updateComplete:self result:true];
}

- (BOOL)waitUpload
{
    if (self.ufile)
        return [self.ufile waitUpload];
    return true;
}
- (BOOL)isUploaded
{
    return !self.ufile || self.ufile.isUploaded;
}

- (BOOL)isUploading
{
    return self.ufile.isUploading;
}

- (void)setFileDownloadedBlock:(nullable SeafDownloadCompletionBlock)block
{
    self.fileDidDownloadBlock = block;
}
- (void)setFileUploadedBlock:(nullable SeafUploadCompletionBlock)block
{
    self.uploadCompletionBlock = block;
}

- (void)downloadComplete:(BOOL)updated
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate download:self complete:updated];
        self.state = SEAF_DENTRY_SUCCESS;
        if (self.fileDidDownloadBlock) {
            self.fileDidDownloadBlock(self, nil);
        }
        if (self.taskCompleteBlock) {
            self.taskCompleteBlock(self, true);
        }
    });
}

- (void)downloadFailed:(NSError *)error
{
    NSError *err = error ? error : [Utils defaultError];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate download:self failed:err];
        if (self.fileDidDownloadBlock) {
            self.fileDidDownloadBlock(self, err);
        }
        if (self.taskCompleteBlock) {
            self.taskCompleteBlock(self, false);
        }
    });
}

- (void)downloadProgress:(float)progress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate download:self progress:progress];
        if (self.taskProgressBlock) {
            self.taskProgressBlock(self, progress);
        }
    });
}

@end
