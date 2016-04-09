//
//  SeafFile.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//
#import <Foundation/Foundation.h>
#import "SeafFile.h"
#import "SeafData.h"
#import "SeafRepos.h"
#import "SeafGlobal.h"

#import "FileMimeType.h"
#import "ExtentedString.h"
#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "NSData+Encryption.h"
#import "Debug.h"
#import "Utils.h"

typedef void (^SeafThumbCompleteBlock)(BOOL ret);


@interface SeafFile()

@property (strong, readonly) NSURL *preViewURL;
@property (readonly) NSURL *exportURL;
@property (strong) NSString *downloadingFileOid;
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, strong) UIImage *thumb;
@property NSURLSessionDownloadTask *task;
@property NSURLSessionDownloadTask *thumbtask;
@property (strong) NSProgress *progress;
@property (strong) SeafUploadFile *ufile;
@property (strong) NSArray *blkids;
@property int index;

@property (readwrite, nonatomic, copy) SeafThumbCompleteBlock thumbCompleteBlock;

@end

@implementation SeafFile
@synthesize exportURL = _exportURL;
@synthesize preViewURL = _preViewURL;

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
        if (self.ufile.uploading)
            return [str stringByAppendingFormat:@", %@", NSLocalizedString(@"uploading", @"Seafile")];
        else
            return [str stringByAppendingFormat:@", %@", NSLocalizedString(@"modified", @"Seafile")];
    }

    return str;
}

- (NSString *)downloadTempPath:(NSString *)objId
{
    return [SeafGlobal.sharedObject.tempDir stringByAppendingPathComponent:objId];
}

- (NSString *)thumbPath: (NSString *)objId
{
    if (!self.oid) return nil;
    int size = THUMB_SIZE * (int)[[UIScreen mainScreen] scale];
    return [SeafGlobal.sharedObject.thumbsDir stringByAppendingFormat:@"%@-%d", objId, size];
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
    [self.delegate download:self complete:true];
}

- (void)setOoid:(NSString *)ooid
{
    super.ooid = ooid;
    _exportURL = nil;
    _preViewURL = nil;
}

- (BOOL)isDownloading
{
    return self.downloadingFileOid != nil;
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
}

- (void)finishDownload:(NSString *)ooid
{
    self.index = 0;
    self.blkids = nil;
    [self clearDownloadContext];
    [SeafGlobal.sharedObject finishDownload:self result:true];
    Debug("ooid=%@, self.ooid=%@, oid=%@", ooid, self.ooid, self.oid);
    BOOL updated = ![ooid isEqualToString:self.ooid];
    [self setOoid:ooid];
    self.state = SEAF_DENTRY_UPTODATE;
    self.oid = self.ooid;
    [self savetoCache];
    [self.delegate download:self complete:updated];
}

- (void)failedDownload:(NSError *)error
{
    self.index = 0;
    self.blkids = nil;
    [self clearDownloadContext];
    [SeafGlobal.sharedObject finishDownload:self result:false];
    self.state = SEAF_DENTRY_INIT;
    [self.delegate download:self failed:error];
}

- (void)finishDownloadThumb:(BOOL)success
{
    if (self.thumbCompleteBlock)
        self.thumbCompleteBlock(success);

    _thumbtask = nil;
    if (success) {
        _icon = nil;
        [self.delegate download:self complete:false];
    } else if (!_icon && self.image) {
        _icon = [Utils reSizeImage:self.image toSquare:THUMB_SIZE];
        [self.delegate download:self complete:false];
    }
}

/*
 curl -D a.txt -H 'Cookie:sessionid=7eb567868b5df5b22b2ba2440854589c' http://127.0.0.1:8000/api/file/640fd90d-ef4e-490d-be1c-b34c24040da7/8dd0a3be9289aea6795c1203351691fcc1373fbb/

 */
- (void)downloadByFile
{
    [SeafGlobal.sharedObject incDownloadnum];
    [connection sendRequest:[NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@", self.repoId, [self.path escapedUrl]] success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         Debug("Download file from file server url: %@", JSON);
         NSString *url = JSON;
         NSString *curId = [[response allHeaderFields] objectForKey:@"oid"];
         if (!curId)
             curId = self.oid;
         if ([[NSFileManager defaultManager] fileExistsAtPath:[SeafGlobal.sharedObject documentPath:curId]]) {
             Debug("file %@ already uptodate oid=%@\n", self.name, self.ooid);
             [self finishDownload:curId];
             return;
         }
         @synchronized (self) {
             if (self.downloadingFileOid) {// Already downloading
                 Debug("Already downloading %@", self.downloadingFileOid);
                 [SeafGlobal.sharedObject finishDownload:self result:true];
                 return;
             }
             self.downloadingFileOid = curId;
         }
         [self.delegate download:self progress:0];
         url = [url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
         NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:DEFAULT_TIMEOUT];
         Debug("Download file %@  %@ from %@", self.name, self.downloadingFileOid, url);
         NSProgress *progress = nil;
         NSString *target = [SeafGlobal.sharedObject documentPath:self.downloadingFileOid];
         _task = [connection.sessionMgr downloadTaskWithRequest:downloadRequest progress:&progress destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
             return [NSURL fileURLWithPath:target];
         } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
             if (error) {
                 Debug("download %@, error=%@, %ld", self.name, [error localizedDescription], (long)((NSHTTPURLResponse *)response).statusCode);
                 [self failedDownload:error];
             } else {
                 Debug("Successfully downloaded file:%@, %@ oid=%@, ooid=%@, delegate=%@", self.name, downloadRequest.URL, self.downloadingFileOid, self.ooid, self.delegate);
                 if (![filePath.path isEqualToString:target]) {
                     Debug("target=%@, filePath=%@", target, filePath.path);
                     [[NSFileManager defaultManager] removeItemAtPath:target error:nil];
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
         [self.delegate download:self failed:error];
     }];
}

- (void)setThumbCompleteBlock:(nullable void (^)(BOOL ret))block
{
    _thumbCompleteBlock = block;
}

- (void)downloadThumb
{
    SeafRepo *repo = [connection getRepo:self.repoId];
    if (repo.encrypted) return;
    int size = THUMB_SIZE * (int)[[UIScreen mainScreen] scale];
    NSString *thumburl = [NSString stringWithFormat:API_URL"/repos/%@/thumbnail/?size=%d&p=%@", self.repoId, size, self.path.escapedUrl];
    NSURLRequest *downloadRequest = [connection buildRequest:thumburl method:@"GET" form:nil];
    NSString *target = [self thumbPath:self.oid];
    @synchronized (self) {
        if (_thumbtask) return;
        if (self.thumb) {
            [self finishDownloadThumb:true];
            return;
        }
        _thumbtask = [connection.sessionMgr downloadTaskWithRequest:downloadRequest progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
            return [NSURL fileURLWithPath:target];
        } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
            if (error) {
                Debug("Failed to download thumb %@, error=%@", self.name, error.localizedDescription);
            } else {
                if (![filePath.path isEqualToString:target]) {
                    [[NSFileManager defaultManager] removeItemAtPath:target error:nil];
                    [[NSFileManager defaultManager] moveItemAtPath:filePath.path toPath:target error:nil];
                }
            }
            [self finishDownloadThumb:!error];
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
    [self.delegate download:self progress:percent];
}

- (int)checkoutFile
{
    NSString *password = nil;
    SeafRepo *repo = [connection getRepo:self.repoId];
    if (repo.encrypted)
        password = [connection getRepoPassword:self.repoId];
    NSString *tmpPath = [self downloadTempPath:self.downloadingFileOid];
    if (![[NSFileManager defaultManager] fileExistsAtPath:tmpPath])
        [[NSFileManager defaultManager] createFileAtPath:tmpPath contents: nil attributes: nil];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:tmpPath];
    [handle truncateFileAtOffset:0];
    for (NSString *blk_id in self.blkids) {
        NSData *data = [[NSData alloc] initWithContentsOfFile:[SeafGlobal.sharedObject blockPath:blk_id]];
        if (password)
            data = [data decrypt:password encKey:repo.encKey version:repo.encVersion];
        if (!data)
            return -1;
        [handle writeData:data];
    }
    [handle closeFile];
    if (!self.downloadingFileOid)
        return -1;
    [[NSFileManager defaultManager] moveItemAtPath:tmpPath toPath:[SeafGlobal.sharedObject documentPath:self.downloadingFileOid] error:nil];
    return 0;
}

- (void)finishBlock:(NSString *)blkid
{
    self.index ++;
    if (self.index >= self.blkids.count) {
        if ([self checkoutFile] < 0) {
            Debug("Faile to checkout out file %@\n", self.downloadingFileOid);
            self.index = 0;
            for (NSString *blk_id in self.blkids)
                [[NSFileManager defaultManager] removeItemAtPath:[SeafGlobal.sharedObject blockPath:blk_id] error:nil];
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
    NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    Debug("URL: %@", downloadRequest.URL);
    NSProgress *progress = nil;
    NSString *target = [SeafGlobal.sharedObject blockPath:blk_id];
    NSURLSessionDownloadTask *task = [connection.sessionMgr downloadTaskWithRequest:downloadRequest progress:&progress destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        return [NSURL fileURLWithPath:target];
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        if (error) {
            Warning("error=%@", error);
            [self failedDownload:error];
        } else {
            Debug("Successfully downloaded file %@ block:%@", self.name, blk_id);
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
    NSString *blk_id = [self.blkids objectAtIndex:self.index];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[SeafGlobal.sharedObject blockPath:blk_id]])
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
    [SeafGlobal.sharedObject incDownloadnum];
    [connection sendRequest:[NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@&op=downloadblks", self.repoId, [self.path escapedUrl]] success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         NSString *curId = [JSON objectForKey:@"file_id"];
         if ([[NSFileManager defaultManager] fileExistsAtPath:[SeafGlobal.sharedObject documentPath:curId]]) {
             Debug("already uptodate oid=%@\n", self.ooid);
             [self finishDownload:curId];
             return;
         }
         @synchronized (self) {
             if (self.downloadingFileOid) {// Already downloading
                 [SeafGlobal.sharedObject finishDownload:self result:true];
                 return;
             }
             self.downloadingFileOid = curId;
         }
         [self.delegate download:self progress:0];
         self.blkids = [JSON objectForKey:@"blklist"];
         if (self.blkids.count <= 0) {
             [@"" writeToFile:[SeafGlobal.sharedObject documentPath:self.downloadingFileOid] atomically:YES encoding:NSUTF8StringEncoding error:nil];
             [self finishDownload:self.downloadingFileOid];
         } else {
             SeafRepo *repo = [connection getRepo:self.repoId];
             repo.encrypted = [[JSON objectForKey:@"encrypted"] booleanValue:repo.encrypted];
             repo.encVersion = (int)[[JSON objectForKey:@"enc_version"] integerValue:repo.encVersion];
             self.index = 0;
             Debug("blks=%@, encversion=%d\n", self.blkids, repo.encVersion);
             [self downloadBlocks];
         }
     }
                    failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         self.state = SEAF_DENTRY_INIT;
         [self.delegate download:self failed:error];
     }];
}

- (void)download
{
    if (self.localDecrypt)
        [self downloadByBlocks];
    else
        [self downloadByFile];
}

- (void)realLoadContent
{
    if (!self.isDownloading) {
        [self loadCache];
        [self download];
    } else {
        Debug("File %@ is already donwloading.", self.name);
    }
}

- (void)load:(id<SeafDentryDelegate>)delegate force:(BOOL)force
{
    if (delegate != nil) self.delegate = delegate;
    [self loadContent:NO];
}

- (BOOL)hasCache
{
    if (self.mpath && [[NSFileManager defaultManager] fileExistsAtPath:self.mpath])
        return true;
    if (self.ooid && [[NSFileManager defaultManager] fileExistsAtPath:[SeafGlobal.sharedObject documentPath:self.ooid]])
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
            else
                [self performSelectorInBackground:@selector(downloadThumb) withObject:nil];
        } else if (self.image) {
            [self performSelectorInBackground:@selector(genThumb) withObject:nil];
        }
    }
    return [super icon];
}

- (void)genThumb
{
    _icon = [Utils reSizeImage:self.image toSquare:THUMB_SIZE];
    [self.delegate download:self complete:false];
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

- (DownloadedFile *)loadCacheObj
{
    NSManagedObjectContext *context = [[SeafGlobal sharedObject] managedObjectContext];
    NSFetchRequest *fetchRequest=[[NSFetchRequest alloc] init];
    [fetchRequest setEntity:[NSEntityDescription entityForName:@"DownloadedFile" inManagedObjectContext:context]];
    NSSortDescriptor *sortDescriptor=[[NSSortDescriptor alloc] initWithKey:@"path" ascending:YES selector:nil];
    NSArray *descriptor=[NSArray arrayWithObject:sortDescriptor];
    [fetchRequest setSortDescriptors:descriptor];

    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"repoid==%@ AND path==%@", self.repoId, self.path]];
    NSFetchedResultsController *controller = [[NSFetchedResultsController alloc]
                                              initWithFetchRequest:fetchRequest
                                              managedObjectContext:context
                                              sectionNameKeyPath:nil
                                              cacheName:nil];
    NSError *error;
    if (![controller performFetch:&error]) {
        Debug(@"Fetch cache error %@",[error localizedDescription]);
        return nil;
    }
    NSArray *results = [controller fetchedObjects];
    if ([results count] == 0)
        return nil;
    DownloadedFile *dfile = [results objectAtIndex:0];
    return dfile;
}

- (BOOL)realLoadCache
{
    DownloadedFile *dfile = [self loadCacheObj];
    if (!dfile) {
        if (self.oid && [[NSFileManager defaultManager] fileExistsAtPath:[SeafGlobal.sharedObject documentPath:self.oid]]) {
            if (![self.oid isEqualToString:self.ooid])
                [self setOoid:self.oid];
            return true;
        } else {
            [self setOoid:nil];
            return false;
        }
    }

    if (dfile.mpath && [[NSFileManager defaultManager] fileExistsAtPath:dfile.mpath]) {
        if (!_mpath || ![_mpath isEqualToString:dfile.mpath]) {
            _mpath = dfile.mpath;
            _preViewURL = nil;
            _exportURL = nil;
        }
        [self autoupload];
    }
    if (!self.oid && dfile) self.oid = dfile.oid;

    if (self.oid && [[NSFileManager defaultManager] fileExistsAtPath:[SeafGlobal.sharedObject documentPath:self.oid]]) {
        if (![self.oid isEqualToString:self.ooid])
            [self setOoid:self.oid];
        return true;
    } else if (self.mpath) {
        return true;
    } else {
        [self setOoid:nil];
        return false;
    }
}

- (BOOL)loadCache
{
    return [self realLoadCache];
}

- (BOOL)savetoCache
{
    NSManagedObjectContext *context = [[SeafGlobal sharedObject] managedObjectContext];
    DownloadedFile *dfile = [self loadCacheObj];
    if (!dfile) {
        dfile = (DownloadedFile *)[NSEntityDescription insertNewObjectForEntityForName:@"DownloadedFile" inManagedObjectContext:context];
        dfile.repoid = self.repoId;
        dfile.oid = self.ooid;
        dfile.path = self.path;
        dfile.mpath = self.mpath;
    } else {
        dfile.oid = self.ooid;
        dfile.mpath = self.mpath;
    }
    [[SeafGlobal sharedObject] saveContext];
    return YES;
}

- (void)clearCache
{
    NSManagedObjectContext *context = [[SeafGlobal sharedObject] managedObjectContext];
    DownloadedFile *dfile = [self loadCacheObj];
    if (dfile) {
        [context deleteObject:dfile];
        [[SeafGlobal sharedObject] saveContext];
    }
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
        NSString *tempDir = [SeafGlobal.sharedObject.tempDir stringByAppendingPathComponent:self.ooid];
        if (![Utils checkMakeDir:tempDir])
            return nil;
        NSString *tempFileName = [tempDir stringByAppendingPathComponent:self.name];
        Debug("File exists at %@, %d", tempFileName, [Utils fileExistsAtPath:tempFileName]);
        if ([Utils fileExistsAtPath:tempFileName]
            || [Utils linkFileAtPath:[SeafGlobal.sharedObject documentPath:self.ooid] to:tempFileName]) {
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
    _preViewURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"view_markdown" ofType:@"html"]];
    return _preViewURL;
}

- (NSURL *)seafPreviewItemURL
{
    _preViewURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"view_seaf" ofType:@"html"]];
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
        src = [SeafGlobal.sharedObject documentPath:self.ooid];
    } else {
        src = self.mpath;
    }
    tmpdir = [SeafGlobal.sharedObject uniqueDirUnder:SeafGlobal.sharedObject.tempDir];
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
    NSString *path = [SeafGlobal.sharedObject documentPath:self.ooid];
    NSString *name = [@"cacheimage-" stringByAppendingString:self.ooid];
    NSString *cachePath = [[SeafGlobal.sharedObject tempDir] stringByAppendingPathComponent:name];
    return [SeafGlobal.sharedObject imageFromPath:path withMaxSize:IMAGE_MAX_SIZE cachePath:cachePath];
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
        return [SeafGlobal.sharedObject documentPath:self.ooid];
    return nil;
}

- (void)autoupload
{
    if (self.ufile && self.ufile.uploading)  return;
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
    NSString *dir = [SeafGlobal.sharedObject uniqueDirUnder:SeafGlobal.sharedObject.editDir];
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

- (BOOL)itemChangedAtURL:(NSURL *)url
{
    Debug("file %@ changed:%@, repo:%@, account:%@ %@", self.name, url, self.repoId, connection.address, connection.username);
    NSString *dir = [SeafGlobal.sharedObject uniqueDirUnder:SeafGlobal.sharedObject.editDir];
    if (![Utils checkMakeDir:dir])
        return NO;

    NSString *newpath = [dir stringByAppendingPathComponent:self.name];
    NSError *error = nil;
    BOOL ret = [Utils linkFileAtPath:url.path to:newpath];
    if (ret) {
        [self setMpath:newpath];
        [self autoupload];
    } else
        Warning("Failed to copy file %@ to %@: %@", url, newpath, error);
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
    NSString *dir = [SeafGlobal.sharedObject uniqueDirUnder:SeafGlobal.sharedObject.editDir];
    if (![Utils checkMakeDir:dir])
        return NO;
    NSString *newpath = [dir stringByAppendingPathComponent:self.name];
    NSError *error = nil;

    BOOL ret = [[NSFileManager defaultManager] copyItemAtPath:[SeafGlobal.sharedObject documentPath:self.ooid] toPath:newpath error:&error];
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
        self.ufile = [connection getUploadfile:self.mpath];
        self.ufile.delegate = self;
        self.ufile.overwrite = YES;
        NSString *path = [self.path stringByDeletingLastPathComponent];
        self.ufile.udir = [[SeafDir alloc] initWithConnection:connection oid:nil repoId:self.repoId name:path.lastPathComponent path:path];
    }
    [SeafGlobal.sharedObject addUploadTask:self.ufile];
}

- (void)deleteCache
{
    _exportURL = nil;
    _preViewURL = nil;
    _shareLink = nil;
    [[NSFileManager defaultManager] removeItemAtPath:[SeafGlobal.sharedObject documentPath:self.ooid] error:nil];
    NSString *tempDir = [SeafGlobal.sharedObject.tempDir stringByAppendingPathComponent:self.ooid];
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    self.ooid = nil;
    self.state = SEAF_DENTRY_INIT;
}

- (void)cancelAnyLoading
{
    if (self.downloadingFileOid) {
        self.state = SEAF_DENTRY_INIT;
        self.downloadingFileOid = nil;
        [self.task cancel];
        _task = nil;
        self.index = 0;
        self.blkids = nil;
        [SeafGlobal.sharedObject finishDownload:self result:true];
    }
}

#pragma mark - SeafUploadDelegate
- (void)uploadProgress:(SeafFile *)file result:(BOOL)res progress:(int)percent
{
    id<SeafFileUpdateDelegate> dg = self.udelegate;
    [dg updateProgress:self result:res completeness:percent];
}

- (void)uploadSucess:(SeafUploadFile *)file oid:(NSString *)oid
{
    Debug("%@ file %@ upload success oid: %@, %@", self, self.name, oid, self.udelegate);
    id<SeafFileUpdateDelegate> dg = self.udelegate;
    self.ufile = nil;
    self.udelegate = nil;
    self.state = SEAF_DENTRY_INIT;
    self.ooid = oid;
    self.oid = self.ooid;
    _filesize = self.filesize;
    _mtime = self.mtime;
    [self setMpath:nil];
    [dg updateProgress:self result:YES completeness:100];
}

@end
