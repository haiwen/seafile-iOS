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
#import "Debug.h"
#import "Utils.h"

@interface SeafFile ()

@property (strong, readonly) NSURL *preViewURL;
@property (readonly) NSURL *checkoutURL;
@property (strong) NSString *downloadingFileOid;
@property (strong) NSFileHandle *downloadFileHandle;

@end

@implementation SeafFile
@synthesize checkoutURL = _checkoutURL;
@synthesize preViewURL = _preViewURL;
@synthesize shareLink = _shareLink;
@synthesize filesize;
@synthesize downloadFileHandle;
@synthesize downloadingFileOid;


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

    return self;
}

- (NSString *)mime
{
    return [FileMimeType mimeType:self.name];
}

- (NSString *)downloadTempPath
{
    return [[Utils applicationTempDirectory] stringByAppendingPathComponent:self.downloadingFileOid];;
}

- (void)updateWithEntry:(SeafBase *)entry
{
    SeafFile *file = (SeafFile *)entry;
    [super updateWithEntry:entry];
    filesize = file.filesize;
    _mtime = file.mtime;
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
    [self.delegate entry:self contentUpdated:YES completeness:100];
    if (![self.oid isEqualToString:self.ooid]) {
        Debug("the parent is out of date and need to reload %@, %@\n", self.oid, self.ooid);
        self.oid = self.ooid;
    }
}

- (void)connection:(NSURLConnection *)aConn didReceiveResponse:(NSURLResponse *)response
{
#if 0
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
    if ([response respondsToSelector:@selector(allHeaderFields)]) {
        NSDictionary *dictionary = [httpResponse allHeaderFields];
        Debug("headers=%@", dictionary);
    }
#endif
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
    [connection sendRequest:self.downloadLinkUrl repo:self.repoId success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         NSString *url = JSON;
         NSString *curId = [[response allHeaderFields] objectForKey:@"oid"];
         if (!curId)
             curId = self.oid;
         if ([curId isEqualToString:self.ooid]) {
             Debug("already uptodate oid=%@, %@\n", self.ooid, curId);
             [self.delegate entry:self contentUpdated:NO completeness:0];
             return;
         } else if ([[NSFileManager defaultManager] fileExistsAtPath:[SeafFile documentPath:curId]]) {
             [self setOoid:curId];
             [self savetoCache];
             [self.delegate entry:self contentUpdated:YES completeness:100];
             return;
         }

         NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:[url escapedPostForm]]];

         if (downloadingFileOid)
             return;
         downloadingFileOid = curId;

         NSURLConnection *downloadConncetion = [[NSURLConnection alloc] initWithRequest:downloadRequest delegate:self startImmediately:YES];
         if (!downloadConncetion) {
             self.state = SEAF_DENTRY_UPTODATE;
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

    NSString *preformat = [NSString stringWithFormat:@"repoid=='%@' AND path=='%@'", self.repoId, self.path];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:preformat]];
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
    if (!dfile)
        return NO;

    if (![[NSFileManager defaultManager] fileExistsAtPath:[SeafFile documentPath:dfile.oid]]) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        NSManagedObjectContext *context = [appdelegate managedObjectContext];
        [context deleteObject:dfile];
        return NO;
    }
    [self setOoid:dfile.oid];
    [self.delegate entry:self contentUpdated:YES completeness:100];
    return YES;
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
    } else {
        dfile.oid = self.ooid;
        [context updatedObjects];
    }
    [appdelegate saveContext];
    return YES;
}

- (void)generateShareLink:(id<SeafFileDelegate>)dg
{
    NSString *url = [NSString stringWithFormat:API_URL"/repos/%@/file/shared-link/", self.repoId];
    NSString *form = [NSString stringWithFormat:@"p=%@", [self.path escapedUrl]];
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
    if (!self.ooid)
        return nil;
    @synchronized (self) {
        NSString *tempPath = [[Utils applicationTempDirectory] stringByAppendingPathComponent:self.ooid];
        if (![Utils checkMakeDir:tempPath])
            return nil;

        NSString *tempFileName = [tempPath stringByAppendingPathComponent:self.name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:tempFileName]
            || [[NSFileManager defaultManager] copyItemAtPath:[self documentPath] toPath:tempFileName error:&error]) {
            _checkoutURL = [NSURL fileURLWithPath:tempFileName];
        } else {
            Warning("Copy file to checkoutURL failed:%@\n", error);
        }
    }
    return _checkoutURL;
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
    }

    NSString *encodePath = [[[Utils applicationTempDirectory] stringByAppendingPathComponent:self.ooid] stringByAppendingPathComponent:@"utf16" ];
    if (![Utils checkMakeDir:encodePath])
        return _preViewURL;

    NSString *encodeFileName = [encodePath stringByAppendingPathComponent:self.name];
    @synchronized (self) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:encodeFileName]
            || [Utils tryTransformEncoding:encodeFileName fromFile:[self documentPath]]) {
            _preViewURL = [NSURL fileURLWithPath:encodeFileName];
        }
    }
    return _preViewURL;
}

- (NSString *)previewItemTitle
{
    return self.name;
}

- (BOOL)isStarred
{
    return [connection isStarred:self.repoId path:self.path];
}

- (void)setStarred:(BOOL)starred
{
    [connection setStarred:starred repo:self.repoId path:self.path];
}


@end
