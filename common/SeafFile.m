//
//  SeafFile.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

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

@interface SeafFile ()

@property (strong, readonly) NSURL *preViewURL;
@property (readonly) NSURL *exportURL;
@property (strong) NSString *downloadingFileOid;
@property (strong) AFHTTPRequestOperation *operation;

@property (strong) SeafUploadFile *ufile;
@property (strong) NSArray *blks;
@property int index;

@end

@implementation SeafFile
@synthesize exportURL = _exportURL;
@synthesize preViewURL = _preViewURL;
@synthesize groups = _groups;

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
        self.operation = nil;
        [self loadCache];
    }
    return self;
}

- (NSArray *)groups
{
    if (!_groups) {
        _groups = [[NSMutableArray alloc] init];
        for (SeafRepo *r in connection.rootFolder.items) {
            if ([r.repoId isEqualToString:self.repoId] && [r.repoType isEqualToString:@"grepo"]) {
                NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
                [d setObject:r.owner forKey:@"name"];
                if (!r.gid)
                    continue;
                [d setObject:r.gid forKey:@"id"];
                [_groups addObject:d];
            }
        }
    }
    return _groups;
}

- (NSString *)detailText
{
    NSString *str = [FileSizeFormatter stringFromNumber:[NSNumber numberWithLongLong:self.filesize ] useBaseTen:NO];
    if (self.mpath) {
        if (self.ufile.uploading)
            return [str stringByAppendingFormat:@", %@", NSLocalizedString(@"uploading", @"Seafile")];
        else
            return [str stringByAppendingFormat:@", %@", NSLocalizedString(@"modified", @"Seafile")];
    }
    if (self.mtime) {
        NSString *timeStr = [SeafDateFormatter stringFromLongLong:self.mtime];
        str = [str stringByAppendingFormat:@", %@", timeStr];
    }
    if ([self hasCache])
        return [str stringByAppendingFormat:@", %@", NSLocalizedString(@"cached", @"Seafile")];

    return str;
}

- (NSString *)downloadTempPath:(NSString *)objId
{
    return [[SeafGlobal.sharedObject applicationTempDirectory] stringByAppendingPathComponent:objId];
}

- (void)updateWithEntry:(SeafBase *)entry
{
    SeafFile *file = (SeafFile *)entry;
    if ([self.oid isEqualToString:entry.oid])
        return;
    [super updateWithEntry:entry];
    _filesize = file.filesize;
    _mtime = file.mtime;
    self.ooid = nil;
    self.state = SEAF_DENTRY_INIT;
    [self loadCache];
    [self.delegate entry:self updated:YES progress:100];
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

- (void)finishDownload:(NSString *)ooid
{
    BOOL updated = ![ooid isEqualToString:self.ooid];
    [self setOoid:ooid];
    self.state = SEAF_DENTRY_UPTODATE;
    self.downloadingFileOid = nil;
    self.operation = nil;
    [SeafGlobal.sharedObject decDownloadnum];
    self.oid = self.ooid;
    [self savetoCache];
    [self.delegate entry:self updated:updated progress:100];
}

- (void)failedDownload:(NSError *)error
{
    self.state = SEAF_DENTRY_INIT;
    [self.delegate entry:self downloadingFailed:error.code];
    self.downloadingFileOid = nil;
    self.operation = nil;
    [SeafGlobal.sharedObject decDownloadnum];
}
/*
 curl -D a.txt -H 'Cookie:sessionid=7eb567868b5df5b22b2ba2440854589c' http://127.0.0.1:8000/api/file/640fd90d-ef4e-490d-be1c-b34c24040da7/8dd0a3be9289aea6795c1203351691fcc1373fbb/

 */
- (void)downloadByFile
{
    [SeafGlobal.sharedObject incDownloadnum];
    [connection sendRequest:[NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@", self.repoId, [self.path escapedUrl]] success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         NSString *url = JSON;
         NSString *curId = [[response allHeaderFields] objectForKey:@"oid"];
         if (!curId)
             curId = self.oid;
         if ([[NSFileManager defaultManager] fileExistsAtPath:[SeafGlobal.sharedObject documentPath:curId]]) {
             Debug("already uptodate oid=%@, %@\n", self.ooid, curId);
             [self finishDownload:curId];
             return;
         }
         @synchronized (self) {
             if (self.downloadingFileOid) {// Already downloading
                 Debug("Already downloading %@", self.downloadingFileOid);
                 [SeafGlobal.sharedObject decDownloadnum];
                 return;
             }
             self.downloadingFileOid = curId;
         }
         url = [url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
         NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
         AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:downloadRequest];
         self.operation = operation;
         operation.outputStream = [NSOutputStream outputStreamToFileAtPath:[self downloadTempPath:self.downloadingFileOid] append:NO];
         [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
             Debug("Successfully downloaded file:%@", self.name);
             [[NSFileManager defaultManager] moveItemAtPath:[self downloadTempPath:self.downloadingFileOid] toPath:[SeafGlobal.sharedObject documentPath:self.downloadingFileOid] error:nil];
             [self finishDownload:self.downloadingFileOid];
         } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
             Debug("download %@, error=%@", self.name,[error localizedDescription]);
             [self failedDownload:error];
         }];
         [operation setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead) {
             int percent = 99;
             if (totalBytesExpectedToRead > 0)
                 percent = (int)(totalBytesRead * 100 / totalBytesExpectedToRead);
             if (percent >= 100)
                 percent = 99;
             [self.delegate entry:self updated:false progress:percent];
         }];
         [self->connection handleOperation:operation];
     }
                    failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
         self.state = SEAF_DENTRY_INIT;
         [self.delegate entry:self downloadingFailed:response.statusCode];
     }];
}

- (int)checkoutFile
{
    NSString *password = nil;
    SeafRepo *repo = [connection getRepo:self.repoId];
    if (repo.encrypted)
        password = [SeafGlobal.sharedObject getRepoPassword:self.repoId];
    NSString *tmpPath = [self downloadTempPath:self.downloadingFileOid];
    if (![[NSFileManager defaultManager] fileExistsAtPath:tmpPath])
        [[NSFileManager defaultManager] createFileAtPath:tmpPath contents: nil attributes: nil];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:tmpPath];
    [handle truncateFileAtOffset:0];
    for (NSString *blk_id in self.blks) {
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

- (void)finishBlock:(NSString *)url
{
    self.index ++;
    if (self.index >= self.blks.count) {
        if ([self checkoutFile] < 0) {
            Debug("Faile to checkout out file %@\n", self.downloadingFileOid);
            self.index = 0;
            for (NSString *blk_id in self.blks)
                [[NSFileManager defaultManager] removeItemAtPath:[SeafGlobal.sharedObject blockPath:blk_id] error:nil];
            self.blks = nil;
            [self failedDownload:nil];
            return;
        }
        [self finishDownload:self.downloadingFileOid];
        self.index = 0;
        self.blks = nil;
        return;
    }
    [self performSelector:@selector(downloadBlock:) withObject:url afterDelay:0.0];
}

- (void)downloadBlock:(NSString *)url
{
    NSString *blk_id = [self.blks objectAtIndex:self.index];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[SeafGlobal.sharedObject blockPath:blk_id]])
        return [self finishBlock:url];
    NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:[url stringByAppendingString:blk_id]]];
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:downloadRequest];
    self.operation = operation;
    operation.outputStream = [NSOutputStream outputStreamToFileAtPath:[self downloadTempPath:blk_id] append:NO];
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        Debug("Successfully downloaded block %@\n", blk_id);
        [[NSFileManager defaultManager] moveItemAtPath:[self downloadTempPath:blk_id] toPath:[SeafGlobal.sharedObject blockPath:blk_id] error:nil];
        [self finishBlock:url];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        Debug("error=%@",[error localizedDescription]);
        self.index = 0;
        self.blks = nil;
        [self failedDownload:error];
    }];
    [operation setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead) {
        int percent = 99;
        if (totalBytesExpectedToRead > 0)
            percent = (int)(totalBytesRead * 100 / totalBytesExpectedToRead);
        percent = (percent + self.index*100.0)/self.blks.count;
        if (percent >= 100)
            percent = 99;
        [self.delegate entry:self updated:YES progress:percent];
    }];
    [self->connection handleOperation:operation];
}

/*
 curl -D a.txt -H 'Cookie:sessionid=7eb567868b5df5b22b2ba2440854589c' http://127.0.0.1:8000/api/file/640fd90d-ef4e-490d-be1c-b34c24040da7/8dd0a3be9289aea6795c1203351691fcc1373fbb/

 */
- (void)downloadByBlocks
{
    [SeafGlobal.sharedObject incDownloadnum];
    [connection sendRequest:[NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@&op=downloadblks", self.repoId, [self.path escapedUrl]] success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         NSString *curId = [[response allHeaderFields] objectForKey:@"oid"];
         if (!curId)
             curId = self.oid;
         if ([[NSFileManager defaultManager] fileExistsAtPath:[SeafGlobal.sharedObject documentPath:curId]]) {
             Debug("already uptodate oid=%@, %@\n", self.ooid, curId);
             [self finishDownload:curId];
             return;
         }
         @synchronized (self) {
             if (self.downloadingFileOid) {// Already downloading
                 [SeafGlobal.sharedObject decDownloadnum];
                 return;
             }
             self.downloadingFileOid = curId;
         }
         NSString *url = [[JSON objectForKey:@"url"] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
         self.blks = [JSON objectForKey:@"blklist"];
         if (self.blks.count <= 0) {
             [@"" writeToFile:[SeafGlobal.sharedObject documentPath:self.downloadingFileOid] atomically:YES encoding:NSUTF8StringEncoding error:nil];
             [self finishDownload:self.downloadingFileOid];
         } else {
             SeafRepo *repo = [connection getRepo:self.repoId];
             repo.encrypted = [[JSON objectForKey:@"encrypted"] booleanValue:repo.encrypted];
             repo.encVersion = (int)[[JSON objectForKey:@"enc_version"] integerValue:repo.encVersion];
             self.index = 0;
             Debug("blks=%@, encver=%d\n", self.blks, repo.encVersion);
             [self performSelector:@selector(downloadBlock:) withObject:url afterDelay:0.0];
         }
     }
                    failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
         self.state = SEAF_DENTRY_INIT;
         [self.delegate entry:self downloadingFailed:response.statusCode];
     }];
}

- (void)download
{
    SeafRepo *repo = [connection getRepo:self.repoId];
    if (repo.encrypted && [connection localDecrypt:self.repoId])
        [self downloadByBlocks];
    else
        [self downloadByFile];
}

- (void)realLoadContent
{
    if (!self.isDownloading) {
        [self loadCache];
        [self download];
    }
}

- (void)load:(id<SeafDentryDelegate>)delegate force:(BOOL)force
{
    self.delegate = delegate;
    [self loadContent:NO];
}

- (BOOL)hasCache
{
    if (self.ooid && [[NSFileManager defaultManager] fileExistsAtPath:[SeafGlobal.sharedObject documentPath:self.ooid]])
        return YES;
    self.ooid = nil;
    return NO;
}
- (BOOL)isImageFile
{
    return [Utils isImageFile:self.name];
}

- (UIImage *)icon;
{
    UIImage *img = [self isImageFile] ? self.image : nil;
    return img ? [Utils reSizeImage:img toSquare:32.0f] : [super icon];
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
    if (self.oid && [[NSFileManager defaultManager] fileExistsAtPath:[SeafGlobal.sharedObject documentPath:self.oid]]) {
        [self setOoid:self.oid];
    }
    DownloadedFile *dfile = [self loadCacheObj];
    if (!dfile)
        return (!self.ooid);
    if (!self.oid)
        self.oid = dfile.oid;
    NSString *did = self.oid;

    if (dfile && dfile.mpath && [[NSFileManager defaultManager] fileExistsAtPath:dfile.mpath]) {
        _mpath = dfile.mpath;
        _preViewURL = nil;
        _exportURL = nil;
    }
    if (self.mpath)
        [self autoupload];

    if (!self.ooid && [[NSFileManager defaultManager] fileExistsAtPath:[SeafGlobal.sharedObject documentPath:did]])
        [self setOoid:did];

    if (!self.mpath && !self.ooid)
        return NO;
    return YES;
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
        [context updatedObjects];
    }
    [[SeafGlobal sharedObject] saveContext];
    return YES;
}

#pragma mark - QLPreviewItem
- (NSURL *)exportURL
{
    NSError *error = nil;
    if (_exportURL && [[NSFileManager defaultManager] fileExistsAtPath:_exportURL.path])
        return _exportURL;

    if (self.mpath) {
        _exportURL = [NSURL fileURLWithPath:self.mpath];
        return _exportURL;
    }

    if (!self.ooid)
        return nil;
    @synchronized (self) {
        NSString *tempDir = [[SeafGlobal.sharedObject applicationTempDirectory] stringByAppendingPathComponent:self.ooid];
        if (![Utils checkMakeDir:tempDir])
            return nil;
        NSString *tempFileName = [tempDir stringByAppendingPathComponent:self.name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:tempFileName]
            || [[NSFileManager defaultManager] linkItemAtPath:[SeafGlobal.sharedObject documentPath:self.ooid] toPath:tempFileName error:&error]) {
            _exportURL = [NSURL fileURLWithPath:tempFileName];
        } else {
            Warning("Copy file to exportURL failed:%@\n", error);
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
    if (_preViewURL && [[NSFileManager defaultManager] fileExistsAtPath:_preViewURL.path])
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
        tmpdir = [[[SeafGlobal.sharedObject applicationTempDirectory] stringByAppendingPathComponent:self.ooid] stringByAppendingPathComponent:@"utf16" ];
    } else {
        src = self.mpath;
        tmpdir = [[SeafGlobal.sharedObject applicationTempDirectory] stringByAppendingPathComponent:[[self.mpath stringByDeletingLastPathComponent] lastPathComponent]];
    }

    if (![Utils checkMakeDir:tmpdir])
        return _preViewURL;

    NSString *dst = [tmpdir stringByAppendingPathComponent:self.name];
    @synchronized (self) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:dst]
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
    NSString *path = [SeafGlobal.sharedObject documentPath:self.ooid];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path])
        return [UIImage imageWithContentsOfFile:path];
    return nil;
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
    if (self.mpath)
        return [Utils stringContent:self.mpath];
    return [Utils stringContent:[SeafGlobal.sharedObject documentPath:self.ooid]];
}

- (void)autoupload
{
    if (self.ufile && self.ufile.uploading)  return;
    [self update:self.udelegate];
}

- (void)setMpath:(NSString *)mpath
{
    @synchronized (self) {
        _mpath = mpath;
        [self savetoCache];
        _preViewURL = nil;
        _exportURL = nil;
    }
    Debug("filesize=%lld mtime=%lld", self.filesize, self.mtime);
}

- (BOOL)saveStrContent:(NSString *)content
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd-HH.mm.ss"];
    NSString *dir = [[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"edit"] stringByAppendingPathComponent:[formatter stringFromDate:[NSDate date]]];
    if (![Utils checkMakeDir:dir])
        return NO;

    NSString *newpath = [dir stringByAppendingPathComponent:self.name];
    NSError *error = nil;

    BOOL ret = [content writeToFile:newpath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (ret) {
        self.mpath = newpath;
        [self autoupload];
    }
    return ret;
}

- (BOOL)itemChangedAtURL:(NSURL *)url
{
    Debug("file %@ changed:%@, repo:%@, account:%@ %@", self.name, url, self.repoId, connection.address, connection.username);
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd-HH.mm.ss"];
    NSString *dir = [[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"edit"] stringByAppendingPathComponent:[formatter stringFromDate:[NSDate date]]];
    if (![Utils checkMakeDir:dir])
        return NO;
    NSString *newpath = [dir stringByAppendingPathComponent:self.name];
    NSError *error = nil;

    BOOL ret = [[NSFileManager defaultManager] linkItemAtPath:url.path toPath:newpath error:&error];
    if (ret) {
        self.mpath = newpath;
        [self autoupload];
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
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd-HH.mm.ss"];
    NSString *dir = [[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"edit"] stringByAppendingPathComponent:[formatter stringFromDate:[NSDate date]]];
    if (![Utils checkMakeDir:dir])
        return NO;
    NSString *newpath = [dir stringByAppendingPathComponent:self.name];
    NSError *error = nil;

    BOOL ret = [[NSFileManager defaultManager] copyItemAtPath:[SeafGlobal.sharedObject documentPath:self.ooid] toPath:newpath error:&error];
    Debug("ret=%d newpath=%@, %@\n", ret, newpath, error);
    if (ret) {
        self.mpath = newpath;
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
        self.ufile.update = YES;
        NSString *path = [self.path stringByDeletingLastPathComponent];
        self.ufile.udir = [[SeafDir alloc] initWithConnection:connection oid:nil repoId:self.repoId name:path.lastPathComponent path:path];
    }
    [SeafGlobal.sharedObject backgroundUpload:self.ufile];
}

- (void)deleteCache
{
    _exportURL = nil;
    _preViewURL = nil;
    _shareLink = nil;
    [[NSFileManager defaultManager] removeItemAtPath:[SeafGlobal.sharedObject documentPath:self.ooid] error:nil];
    NSString *tempDir = [[SeafGlobal.sharedObject applicationTempDirectory] stringByAppendingPathComponent:self.ooid];
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    self.ooid = nil;
    self.state = SEAF_DENTRY_INIT;
}

- (void)cancelDownload
{
    if (self.downloadingFileOid) {
        self.state = SEAF_DENTRY_INIT;
        self.downloadingFileOid = nil;
        [self.operation cancel];
        self.operation = nil;
        self.index = 0;
        self.blks = nil;
        [SeafGlobal.sharedObject decDownloadnum];
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
    id<SeafFileUpdateDelegate> dg = self.udelegate;
    self.ufile = nil;
    self.udelegate = nil;
    self.state = SEAF_DENTRY_INIT;
    self.ooid = oid;
    self.oid = self.ooid;
    self.mpath = nil;
    [dg updateProgress:self result:YES completeness:100];
}

@end
