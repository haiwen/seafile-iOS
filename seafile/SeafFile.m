//
//  SeafFile.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafFile.h"
#import "SeafData.h"

#import "SeafAppDelegate.h"
#import "FileMimeType.h"
#import "ExtentedString.h"
#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "Debug.h"
#import "Utils.h"

@interface SeafFile ()

@property (strong, readonly) NSURL *preViewURL;
@property (readonly) NSURL *checkoutURL;
@property (strong) NSString *downloadingFileOid;
@property (strong) NSFileHandle *downloadFileHandle;
@property (strong) SeafUploadFile *ufile;
@property (weak) id <SeafFileUploadDelegate> udelegate;

@end

@implementation SeafFile
@synthesize checkoutURL = _checkoutURL;
@synthesize preViewURL = _preViewURL;
@synthesize shareLink = _shareLink;
@synthesize filesize;
@synthesize downloadFileHandle;
@synthesize downloadingFileOid;
@synthesize mpath;
@synthesize ufile;
@synthesize udelegate;


- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    name:(NSString *)aName
                    path:(NSString *)aPath
                   mtime:(int)mtime
                    size:(int)size;
{
    if (self = [super initWithConnection:aConnection oid:anId repoId:aRepoId name:aName path:aPath mime:[FileMimeType mimeType:aName]]) {
        _mtime = mtime;
        _shareLink = nil;
        filesize = size;
        downloadingFileOid = nil;
        downloadFileHandle = nil;
    }
    [self loadCache];
    return self;
}

- (NSString *)detailText
{
    if (self.mpath) {
        if (self.ufile.uploading)
            return [NSString stringWithFormat:@"%@, uploading", [FileSizeFormatter stringFromNumber:[NSNumber numberWithInt:self.filesize ] useBaseTen:NO]];
        else
            return [NSString stringWithFormat:@"%@, modified", [FileSizeFormatter stringFromNumber:[NSNumber numberWithInt:self.filesize ] useBaseTen:NO]];
    } else if (!self.mtime)
        return [FileSizeFormatter stringFromNumber:[NSNumber numberWithInt:self.filesize ] useBaseTen:NO];
    else
        return [NSString stringWithFormat:@"%@, %@", [FileSizeFormatter stringFromNumber:[NSNumber numberWithInt:self.filesize ] useBaseTen:NO], [SeafDateFormatter stringFromInt:self.mtime]];
}

- (NSString *)downloadTempPath
{
    return [[Utils applicationTempDirectory] stringByAppendingPathComponent:self.downloadingFileOid];;
}

- (void)updateWithEntry:(SeafBase *)entry
{
    SeafFile *file = (SeafFile *)entry;
    if ([self.oid isEqualToString:entry.oid])
        return;
    [super updateWithEntry:entry];
    filesize = file.filesize;
    _mtime = file.mtime;
    self.ooid = nil;
    self.state = SEAF_DENTRY_INIT;
    [self loadCache];
    [self.delegate entryChanged:self];
}

+ (NSString *)documentPath:(NSString*)fileId
{
    return [[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"objects"] stringByAppendingPathComponent:fileId];
}

- (NSString *)documentPath
{
    if (!self.ooid)
        return nil;
    return [SeafFile documentPath:self.ooid];
}

- (void)setOoid:(NSString *)ooid
{
    super.ooid = ooid;
    _checkoutURL = nil;
    _preViewURL = nil;
}

- (NSString *)downloadLinkUrl
{
    return [NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@", self.repoId, [self.path escapedUrl]];
}

#pragma - NSURLConnectionDelegate
- (void)connection:(NSURLConnection *)aConn didReceiveData:(NSData *)data
{
    [downloadFileHandle writeData:data];
    int percent = 0;
    if (filesize != 0)
        percent = downloadFileHandle.offsetInFile * 100/filesize;
    if (percent >= 100)
        percent = 99;
    [self.delegate entry:self contentUpdated:YES completeness:percent];
}

- (void)connection:(NSURLConnection *)aConn didFailWithError:(NSError *)error
{
    Debug("error=%@",[error localizedDescription]);
    self.state = SEAF_DENTRY_INIT;
    [self.delegate entryContentLoadingFailed:error.code entry:self];
    downloadingFileOid = nil;
    [SeafAppDelegate decDownloadnum];
    [downloadFileHandle closeFile];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)aConn
{
    @synchronized(self) {
        self.state = SEAF_DENTRY_UPTODATE;
        [self setOoid:downloadingFileOid];
        [self savetoCache];
        [downloadFileHandle closeFile];
        [[NSFileManager defaultManager] moveItemAtPath:[self downloadTempPath] toPath:[self documentPath] error:nil];
        downloadingFileOid = nil;
    }
    [SeafAppDelegate decDownloadnum];
    [self.delegate entry:self contentUpdated:YES completeness:100];
    if (![self.oid isEqualToString:self.ooid]) {
        Debug("the parent is out of date and need to reload %@, %@\n", self.oid, self.ooid);
        self.oid = self.ooid;
    }
}

- (void)connection:(NSURLConnection *)aConn didReceiveResponse:(NSURLResponse *)response
{
    NSError *error = nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:[self downloadTempPath]])
        [[NSFileManager defaultManager] createFileAtPath: [self downloadTempPath] contents: nil attributes: nil];
    self.downloadFileHandle = [NSFileHandle fileHandleForWritingToURL:[NSURL fileURLWithPath:[self downloadTempPath]] error:&error];
    [self.downloadFileHandle truncateFileAtOffset:0];
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace
{
    return YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
}

/*
 curl -D a.txt -H 'Cookie:sessionid=7eb567868b5df5b22b2ba2440854589c' http://127.0.0.1:8000/api/file/640fd90d-ef4e-490d-be1c-b34c24040da7/8dd0a3be9289aea6795c1203351691fcc1373fbb/

 */
- (void)realLoadContent
{
    [SeafAppDelegate incDownloadnum];
    [connection sendRequest:self.downloadLinkUrl repo:self.repoId success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         NSString *url = JSON;
         NSString *curId = [[response allHeaderFields] objectForKey:@"oid"];
         if (!curId)
             curId = self.oid;
         if ([curId isEqualToString:self.ooid]) {
             Debug("already uptodate oid=%@, %@\n", self.ooid, curId);
             [self.delegate entry:self contentUpdated:NO completeness:100];
             [SeafAppDelegate decDownloadnum];
             return;
         } else if ([[NSFileManager defaultManager] fileExistsAtPath:[SeafFile documentPath:curId]]) {
             [self setOoid:curId];
             [self savetoCache];
             [self.delegate entry:self contentUpdated:YES completeness:100];
             [SeafAppDelegate decDownloadnum];
             return;
         }
         url = [url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
         NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
         if (downloadingFileOid) {
             [SeafAppDelegate decDownloadnum];
             return;
         }
         downloadingFileOid = curId;
         NSURLConnection *downloadConncetion = [[NSURLConnection alloc] initWithRequest:downloadRequest delegate:self startImmediately:YES];
         if (!downloadConncetion) {
             self.state = SEAF_DENTRY_UPTODATE;
             downloadingFileOid = nil;
             [SeafAppDelegate decDownloadnum];
             [self.delegate entryContentLoadingFailed:response.statusCode entry:self];
             return;
         }
     }
                    failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
         self.state = SEAF_DENTRY_UPTODATE;
         [self.delegate entryContentLoadingFailed:response.statusCode entry:self];
     }];
}

- (DownloadedFile *)loadCacheObj
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    NSManagedObjectContext *context = [appdelegate managedObjectContext];

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
    if (!self.oid)
        self.oid = dfile.oid;
    NSString *did = self.oid;
    //if (dfile)         did = dfile.oid;

    if (dfile && dfile.mpath && [[NSFileManager defaultManager] fileExistsAtPath:dfile.mpath]) {
        self.mpath = dfile.mpath;
        self.filesize = [Utils fileSizeAtPath1:self.mpath];
    }
    if (self.mpath)
        [self autoupload];

    if ([[NSFileManager defaultManager] fileExistsAtPath:[SeafFile documentPath:did]])
        [self setOoid:did];

    if (!self.mpath && !self.ooid)
        return NO;
    [self.delegate entry:self contentUpdated:YES completeness:100];
    return YES;
}

- (BOOL)loadCache
{
    return [self realLoadCache];
}

- (BOOL)savetoCache
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    NSManagedObjectContext *context = [appdelegate managedObjectContext];
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
    [appdelegate saveContext];
    return YES;
}

- (void)generateShareLink:(id<SeafFileDelegate>)dg
{
    NSString *url = [NSString stringWithFormat:API_URL"/repos/%@/file/shared-link/", self.repoId];
    NSString *form = [NSString stringWithFormat:@"p=%@", [self.path escapedPostForm]];
    [connection sendPut:url repo:self.repoId form:form
                success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         NSString *link = [[response allHeaderFields] objectForKey:@"Location"];
         Debug(" share link = %@\n", link);

         if ([link hasPrefix:@"\""])
             _shareLink = [link substringWithRange:NSMakeRange(1, link.length-2)];
         else
             _shareLink = link;
         [dg generateSharelink:self WithResult:YES];
     }
                failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
         [dg generateSharelink:self WithResult:NO];
     }];
}

#pragma mark - QLPreviewItem
- (NSURL *)checkoutURL
{
    NSError *error = nil;
    if (_checkoutURL)
        return _checkoutURL;

    if (self.mpath) {
        _checkoutURL = [NSURL fileURLWithPath:self.mpath];
        return _checkoutURL;
    }

    if (!self.ooid)
        return nil;
    @synchronized (self) {
        NSString *tempDir = [[Utils applicationTempDirectory] stringByAppendingPathComponent:self.ooid];
        if (![Utils checkMakeDir:tempDir])
            return nil;
        NSString *tempFileName = [tempDir stringByAppendingPathComponent:self.name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:tempFileName]
            || [[NSFileManager defaultManager] linkItemAtPath:[self documentPath] toPath:tempFileName error:&error]) {
            _checkoutURL = [NSURL fileURLWithPath:tempFileName];
        } else {
            Warning("Copy file to checkoutURL failed:%@\n", error);
        }
    }
    return _checkoutURL;
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
    if (_preViewURL)
        return _preViewURL;

    _preViewURL = self.checkoutURL;
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
        src = [self documentPath];
        tmpdir = [[[Utils applicationTempDirectory] stringByAppendingPathComponent:self.ooid] stringByAppendingPathComponent:@"utf16" ];
    } else {
        src = self.mpath;
        tmpdir = [[Utils applicationTempDirectory] stringByAppendingPathComponent:[[self.mpath stringByDeletingLastPathComponent] lastPathComponent]];
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
    return [connection repoEditable:self.repoId];
}

- (NSString *)content
{
    if (self.mpath) {
        return [Utils stringContent:self.mpath];
    }
    return [Utils stringContent:[self documentPath]];
}

- (void)autoupload
{
    if (ufile && ufile.uploading)
        return;
    if ([self.delegate conformsToProtocol:@protocol(SeafFileUploadDelegate)])
        [self update:(id<SeafFileUploadDelegate>)self.delegate];
    else
        [self update:self.udelegate];
}

- (BOOL)saveContent:(NSString *)content
{
    @synchronized (self) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd-HH.mm.ss"];
        NSString *dir = [[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"edit"] stringByAppendingPathComponent:[formatter stringFromDate:[NSDate date]]];
        if (![Utils checkMakeDir:dir])
            return NO;

        NSString *newpath = [dir stringByAppendingPathComponent:self.name];
        BOOL ret = [content writeToFile:newpath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if (ret) {
            self.mpath = newpath;
            [self savetoCache];
            _preViewURL = nil;
            _checkoutURL = nil;
            self.filesize = [Utils fileSizeAtPath1:self.mpath];
            self.mtime = [[NSDate date] timeIntervalSince1970];
            [self autoupload];
        }
        return ret;
    }
}

- (BOOL)isStarred
{
    return [connection isStarred:self.repoId path:self.path];
}

- (void)setStarred:(BOOL)starred
{
    [connection setStarred:starred repo:self.repoId path:self.path];
}

- (void)update:(id<SeafFileUploadDelegate>)dg
{
    if (!self.mpath)
        return;
    self.udelegate = dg;
    if (!self.ufile) {
        self.ufile = [[SeafUploadFile alloc] initWithPath:self.mpath];
        self.ufile.delegate = self;
    }
    [self.ufile upload:connection repo:self.repoId path:self.path update:YES];
}

- (void)deleteCache
{
    _checkoutURL = nil;
    _preViewURL = nil;
    _shareLink = nil;
    [[NSFileManager defaultManager] removeItemAtPath:[self documentPath] error:nil];
    NSString *tempDir = [[Utils applicationTempDirectory] stringByAppendingPathComponent:self.ooid];
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    self.ooid = nil;
    self.state = SEAF_DENTRY_INIT;
}

#pragma mark - SeafUploadDelegate
- (void)uploadProgress:(SeafUploadFile *)file result:(BOOL)res completeness:(int)percent
{
    id<SeafFileUploadDelegate> dg = self.udelegate;
    if (res && percent == 100) {
        self.ufile = nil;
        self.udelegate = nil;
        self.state = SEAF_DENTRY_INIT;
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd-HH.mm.ss"];
        self.ooid = [self.ooid stringByAppendingString:[formatter stringFromDate:[NSDate date]]];
        self.oid = self.ooid;
        [[NSFileManager defaultManager] moveItemAtPath:self.mpath toPath:[self documentPath] error:nil];
        self.mpath = nil;
        [self savetoCache];
    }
    [dg uploadProgress:self result:res completeness:percent];
}

@end
