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

@property (readonly, strong) NSData *content;
@property (strong) NSURL *preViewURL;
@property (readonly) NSURL *checkoutURL;

@property (readonly, strong) NSMutableData *tmpData;
@property (readonly, strong) NSString *tmpOid;


@end

@implementation SeafFile
@synthesize checkoutURL = _checkoutURL;
@synthesize preViewURL = _preViewURL;
@synthesize content = _content;
@synthesize filesize = _filesize;
@synthesize shareLink = _shareLink;
@synthesize tmpData = _tmpData;
@synthesize tmpOid = _tmpOid;


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
        _filesize = size;
        _shareLink = nil;
    }

    return self;
}

- (NSString *)mime
{
    return [FileMimeType mimeType:self.name];
}

- (void)updateWithEntry:(SeafBase *)entry
{
    SeafFile *file = (SeafFile *)entry;
    [super updateWithEntry:entry];
    _filesize = file.filesize;
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

- (void)setContent:(NSData *)content
{
    _content = content;
    [_content writeToFile:[self documentPath] atomically:YES];
}

- (NSData *)content
{
    if (_content)
        return _content;
    if (self.ooid) {
        _content = [NSData dataWithContentsOfFile:[self documentPath]];
    }

    return _content;
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
    [_tmpData appendData:data];
    int percent = 0;
    if (_filesize != 0)
        percent = _tmpData.length * 100/_filesize;
    if (percent >= 100)
        percent = 99;
    [self.delegate entry:self contentUpdated:YES completeness:percent];
}

- (void)connection:(NSURLConnection *)aConn didFailWithError:(NSError *)error
{
    Debug("error=%@",[error localizedDescription]);
    self.state = SEAF_DENTRY_INIT;
    [self.delegate entryContentLoadingFailed:error.code entry:self];
    _tmpData = nil;
    _tmpOid = nil;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)aConn
{
    @synchronized(self) {
        self.state = SEAF_DENTRY_UPTODATE;
        [self setOoid:_tmpOid];
        [self setContent:_tmpData];
        [self savetoCache];
        _tmpData = nil;
        _tmpOid = nil;
    }
    [self.delegate entry:self contentUpdated:YES completeness:100];
    if (![self.oid isEqualToString:_tmpOid]) {
        Debug("the parent is out of date and need to reload %@, %@\n", self.oid, _tmpOid);
        self.oid = _tmpOid;
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
    _tmpData = [[NSMutableData alloc] init];
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
    _tmpOid = nil;
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

         if (_tmpOid)
             return;
         _tmpOid = curId;

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
    if (_checkoutURL)
        return _checkoutURL;
    if (!self.ooid)
        return nil;

    @synchronized (self) {
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:self.ooid];
        if (![Utils checkMakeDir:tempPath])
            return nil;

        NSString *tempFileName = [tempPath stringByAppendingPathComponent:self.name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:tempFileName]
            || [[NSFileManager defaultManager] createFileAtPath:tempFileName
                                                       contents:self.content
                                                     attributes:nil]) {
                _checkoutURL = [NSURL fileURLWithPath:tempFileName];
            }
    }
    //[self.content writeToFile:[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"] stringByAppendingPathComponent:self.name] atomically:YES];

    return _checkoutURL;
}

- (NSString *)tryTransformEncoding:(NSData *)data
{
    int i = 0;
    NSString *res = nil;
    NSStringEncoding encodes[] = {
        NSUTF8StringEncoding,
        CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000),
        CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_2312_80),
        CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGBK_95),
        NSUnicodeStringEncoding,
        NSASCIIStringEncoding,
        0,
    };

    while (encodes[i]) {
        res = [[NSString alloc] initWithData:data encoding:encodes[i]];
        if (res) {
            Debug("use encoding %d\n", i);
            break;
        }
        ++i;
    }
    return res;
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

    @synchronized (self) {
        NSString *tempPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:self.ooid] stringByAppendingPathComponent:@"utf16" ];
        if (![Utils checkMakeDir:tempPath])
            return _preViewURL;

        NSString *tempFileName = [tempPath stringByAppendingPathComponent:self.name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:tempFileName]) {
            Debug("file %@ existes already\n", tempFileName);
            _preViewURL = [NSURL fileURLWithPath:tempFileName];
        } else {
            NSString *encodeContent = [self tryTransformEncoding:self.content];
            if (!encodeContent)
                return _preViewURL;

            if ([encodeContent writeToFile:tempFileName atomically:YES encoding:NSUTF16StringEncoding error:nil]) {
                _preViewURL = [NSURL fileURLWithPath:tempFileName];
                return _preViewURL;
            }
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
