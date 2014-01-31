//
//  SeafUploadFile.m
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafUploadFile.h"
#import "SeafConnection.h"
#import "AFHTTPClient.h"
#import "AFHTTPRequestOperation.h"
#import "SeafRepos.h"

#import "FileMimeType.h"
#import "UIImage+FileType.h"
#import "ExtentedString.h"
#import "NSData+Encryption.h"
#import "Debug.h"

#import "SeafJSONRequestOperation.h"

static NSMutableDictionary *uploadFiles = nil;


@interface SeafUploadFile ()
@property (readonly) NSString *mime;
@property (strong, readonly) NSURL *preViewURL;
@property (strong) AFHTTPRequestOperation *operation;
@end

@implementation SeafUploadFile

@synthesize lpath = _lpath;
@synthesize filesize = _filesize;
@synthesize delegate = _delegate;
@synthesize uploading = _uploading;
@synthesize uProgress = _uProgress;
@synthesize preViewURL = _preViewURL;


- (id)initWithPath:(NSString *)lpath
{
    self = [super init];
    if (self) {
        _lpath = lpath;
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:lpath error:nil];
        _filesize = attrs.fileSize;
        _uProgress = 0;
        _uploading = NO;
    }
    return self;
}

- (NSString *)key
{
    return self.name;
}

- (NSString *)name
{
    return [_lpath lastPathComponent];
}

- (BOOL)editable
{
    return NO;
}

- (void)removeFile
{
    [self.operation cancel];
    [self saveAttr:nil];
    [[NSFileManager defaultManager] removeItemAtPath:self.lpath error:nil];
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
        if (!_uploading)
            return;
        _uploading = NO;
        self.operation = nil;
    }
    NSMutableDictionary *dict = self.uploadAttr;
    if (!dict) {
        dict = [[NSMutableDictionary alloc] init];
        [dict setObject:self.name forKey:@"name"];
    }
    [dict setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]]forKey:@"utime"];
    [dict setObject:[NSNumber numberWithBool:result] forKey:@"result"];
    [self saveAttr:dict];
    Debug("result=%d, name=%@, _delegate=%@\n", result, self.name, _delegate);
    if (result)
        [_delegate uploadSucess:self oid:oid];
    else
        [_delegate uploadProgress:self result:NO completeness:0];
    [SeafAppDelegate decUploadnum:result];
}

- (int)percentForShow:(long long)totalBytesWritten expected:(long long)totalBytesExpectedToWrite
{
    int percent = 99;
    if (totalBytesExpectedToWrite > 0)
        percent = (int)(totalBytesWritten * 100 / totalBytesExpectedToWrite);
    if (percent >= 100)
        percent = 99;
    return percent;
}

- (void)uploadByFile:(NSString *)surl path:(NSString *)uploadpath update:(BOOL)update
{
    NSURL *url = [NSURL URLWithString:surl];
    AFHTTPClient *httpClient = [[AFHTTPClient alloc] initWithBaseURL:url];
    NSMutableURLRequest *request = [httpClient multipartFormRequestWithMethod:@"POST" path:nil parameters:nil constructingBodyWithBlock: ^(id <AFMultipartFormData>formData) {
        if (update)
            [formData appendPartWithFormData:[uploadpath dataUsingEncoding:NSUTF8StringEncoding] name:@"target_file"];
        else
            [formData appendPartWithFormData:[uploadpath dataUsingEncoding:NSUTF8StringEncoding] name:@"parent_dir"];

        [formData appendPartWithFormData:[@"n8ba38951c9ba66418311a25195e2e380" dataUsingEncoding:NSUTF8StringEncoding] name:@"csrfmiddlewaretoken"];
        [formData appendPartWithFileURL:[NSURL fileURLWithPath:self.lpath] name:@"file" error:nil];
    }];
    request.URL = url;
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    self.operation = operation;
    [operation setUploadProgressBlock:^(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite) {
        int percent = [self percentForShow:totalBytesWritten expected:totalBytesExpectedToWrite];
        [_delegate uploadProgress:self result:YES completeness:percent];
    }];
    [operation setCompletionBlockWithSuccess:
     ^(AFHTTPRequestOperation *operation, id responseObject) {
         NSString *oid = nil;
         if ([responseObject isKindOfClass:[NSData class]]) {
             oid = [[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
             [[NSFileManager defaultManager] linkItemAtPath:self.lpath toPath:[Utils documentPath:oid] error:nil];
         }
         Debug("Upload success _uploading=%d, oid=%@\n", _uploading, oid);
         [self finishUpload:YES oid:oid];
     }
                                     failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                                         Debug("Upload failed :%@,code=%d, res=%@, %@\n", error, operation.response.statusCode, operation.responseData, operation.responseString);
                                         [self finishUpload:NO oid:nil];
                                     }];

    [operation setAuthenticationAgainstProtectionSpaceBlock:^BOOL(NSURLConnection *connection, NSURLProtectionSpace *protectionSpace) {
        return YES;
    }];
    [operation setAuthenticationChallengeBlock:^(NSURLConnection *connection, NSURLAuthenticationChallenge *challenge) {
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    }];
    [operation start];
}

- (BOOL)chunkFile:(NSString *)path blockids:(NSMutableArray *)blockids paths:(NSMutableArray *)paths password:(NSString *)password repo:(SeafRepo *)repo
{
    BOOL ret = YES;
    int CHUNK_LENGTH = 1024*1024;
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
        NSString *blockpath = [Utils blockPath:blockid];
        Debug("Chunk file blockid=%@, path=%@, len=%d\n", blockid, blockpath, data.length);
        [blockids addObject:blockid];
        [paths addObject:blockpath];
        [data writeToFile:blockpath atomically:YES];
    }
    [fileHandle closeFile];
    return ret;
}

- (void)uploadByBlocks:(NSString *)surl uploadpath:(NSString *)uploadpath blocks:(NSArray *)blockids paths:(NSArray *)paths update:(BOOL)update
{
    NSURL *url = [NSURL URLWithString:surl];
    AFHTTPClient *httpClient = [[AFHTTPClient alloc] initWithBaseURL:url];
    NSMutableURLRequest *request = [httpClient multipartFormRequestWithMethod:@"POST" path:nil parameters:nil constructingBodyWithBlock: ^(id <AFMultipartFormData>formData) {
        if (update)
            [formData appendPartWithFormData:[uploadpath dataUsingEncoding:NSUTF8StringEncoding] name:@"target_file"];
        else {
            [formData appendPartWithFormData:[uploadpath dataUsingEncoding:NSUTF8StringEncoding] name:@"parent_dir"];
            [formData appendPartWithFormData:[self.name dataUsingEncoding:NSUTF8StringEncoding] name:@"file_name"];
        }
        [formData appendPartWithFormData:[[NSString stringWithFormat:@"%lld", [Utils fileSizeAtPath1:self.lpath]] dataUsingEncoding:NSUTF8StringEncoding] name:@"file_size"];
        for (NSString *path in paths) {
            [formData appendPartWithFileURL:[NSURL fileURLWithPath:path] name:@"file" error:nil];
        }
    }];
    request.URL = url;
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    [operation setUploadProgressBlock:^(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite) {
        int percent = [self percentForShow:totalBytesWritten expected:totalBytesExpectedToWrite];
        [_delegate uploadProgress:self result:YES completeness:percent];
    }];
    [operation setCompletionBlockWithSuccess:
     ^(AFHTTPRequestOperation *operation, id responseObject) {
         NSString *oid = nil;
         if ([responseObject isKindOfClass:[NSData class]]) {
             oid = [[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
             [[NSFileManager defaultManager] linkItemAtPath:self.lpath toPath:[Utils documentPath:oid] error:nil];
         }
         Debug("Upload success _uploading=%d, oid=%@\n", _uploading, oid);
         [self finishUpload:YES oid:oid];
     }
                                     failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                                         Debug("Upload failed :%@,code=%d, res=%@, %@\n", error, operation.response.statusCode, operation.responseData, operation.responseString);
                                         [self finishUpload:NO oid:nil];
                                     }];

    [operation setAuthenticationAgainstProtectionSpaceBlock:^BOOL(NSURLConnection *connection, NSURLProtectionSpace *protectionSpace) {
        return YES;
    }];
    [operation setAuthenticationChallengeBlock:^(NSURLConnection *connection, NSURLAuthenticationChallenge *challenge) {
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    }];
    [operation start];
}

- (void)upload:(SeafConnection *)connection repo:(NSString *)repoId path:(NSString *)uploadpath update:(BOOL)update
{
    @synchronized (self) {
        if (_uploading || self.uploaded)
            return;
        _uploading = YES;
        _uProgress = 0;
    }
    [SeafAppDelegate incUploadnum];
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.lpath error:nil];
    _filesize = attrs.fileSize;
    [_delegate uploadProgress:self result:YES completeness:0];
    NSString *upload_url;
    SeafRepo *repo = [connection getRepo:repoId];
    BOOL byblock = (repo.encrypted && [connection localDecrypt:repoId]);
    if (!update)
        upload_url = [NSString stringWithFormat:API_URL"/repos/%@/upload-", repoId];
    else
        upload_url = [NSString stringWithFormat:API_URL"/repos/%@/update-", repoId];
    if (byblock)
        upload_url = [upload_url stringByAppendingString:@"blks-link/"];
    else
        upload_url = [upload_url stringByAppendingString:@"link/"];

    [connection sendRequest:upload_url repo:repoId success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         NSString *url = JSON;
         Debug("Upload file %@ %@, %@ update=%d, byblock=%d, delegate%@\n", self.name, url, uploadpath, update, byblock, _delegate);
         if (byblock) {
             NSMutableArray *blockids = [[NSMutableArray alloc] init];
             NSMutableArray *paths = [[NSMutableArray alloc] init];
             NSString *passwrod = [Utils getRepoPassword:repo.repoId];
             if ([self chunkFile:self.lpath blockids:blockids paths:paths password:passwrod repo:repo]) {
                 [self uploadByBlocks:url uploadpath:uploadpath blocks:blockids paths:paths update:update];
             } else {
                 [self finishUpload:NO oid:nil];
             }
         } else {
             [self uploadByFile:url path:uploadpath update:update];
         }
     }
                    failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
         [self finishUpload:NO oid:nil];
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

    if (![self.mime hasPrefix:@"text"]) {
        _preViewURL = [NSURL fileURLWithPath:self.lpath];
    } else if ([self.mime hasSuffix:@"markdown"]) {
        _preViewURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"view_markdown" ofType:@"html"]];
    } else if ([self.mime hasSuffix:@"seafile"]) {
        _preViewURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"view_seaf" ofType:@"html"]];
    } else {
        NSString *encodePath = [[Utils applicationTempDirectory] stringByAppendingPathComponent:self.name];
        if ([Utils tryTransformEncoding:encodePath fromFile:self.lpath])
            _preViewURL = [NSURL fileURLWithPath:encodePath];
    }
    if (!_preViewURL)
        _preViewURL = [NSURL fileURLWithPath:self.lpath];
    return _preViewURL;
}

- (UIImage *)image
{
    return [UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString];
}

- (NSURL *)checkoutURL
{
    return [NSURL fileURLWithPath:self.lpath];
}

- (NSString *)mime
{
    return [FileMimeType mimeType:self.name];
}

- (NSString *)content
{
    return [Utils stringContent:self.lpath];
}

- (BOOL)saveContent:(NSString *)content
{
    _preViewURL = nil;
    return [content writeToFile:self.lpath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

+ (NSMutableDictionary *)uploadFiles
{
    if (uploadFiles == nil) {
        NSString *attrsFile = [[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploadfiles.plist"];
        uploadFiles = [[NSMutableDictionary alloc] initWithContentsOfFile:attrsFile];
        if (!uploadFiles)
            uploadFiles = [[NSMutableDictionary alloc] init];
    }
    return uploadFiles;
}

- (NSDictionary *)uploadAttr
{
    return [[SeafUploadFile uploadFiles] objectForKey:self.lpath];
}

- (void)saveAttr:(NSMutableDictionary *)attr
{
    NSString *attrsFile = [[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploadfiles.plist"];
    if (attr)
        [[SeafUploadFile uploadFiles] setObject:attr forKey:self.lpath];
    else
        [[SeafUploadFile uploadFiles] removeObjectForKey:self.lpath];
    [[SeafUploadFile uploadFiles] writeToFile:attrsFile atomically:YES];
}

+ (NSMutableArray *)uploadFilesForDir:(SeafDir *)dir
{
    NSMutableDictionary *allFiles = [SeafUploadFile uploadFiles];
    NSMutableArray *files = [[NSMutableArray alloc] init];
    for (NSString *lpath in allFiles.allKeys) {
        NSDictionary *info = [allFiles objectForKey:lpath];
        if ([dir.repoId isEqualToString:[info objectForKey:@"urepo"]] && [dir.path isEqualToString:[info objectForKey:@"upath"]]) {
            SeafUploadFile *file  = [dir->connection getUploadfile:lpath];
            file.udir = dir;
            [files addObject:file];
        }
    }
    return files;
}

@end
