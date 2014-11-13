//
//  SeafUploadFile.m
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafGlobal.h"
#import "SeafUploadFile.h"
#import "SeafRepos.h"
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
        _filesize = [Utils fileSizeAtPath1:lpath] ;
        _uProgress = 0;
        _uploading = NO;
        _autoSync = NO;
        self.update = [[self.uploadAttr objectForKey:@"update"] boolValue];
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
- (void)unload
{

}
- (BOOL)hasCache
{
    return YES;
}
- (BOOL)isImageFile
{
    return NO;
}
- (void)load:(id<SeafDentryDelegate>)delegate force:(BOOL)force
{
    [self checkAsset];
}

- (BOOL)editable
{
    return NO;
}

- (NSURL *)assetURL
{
    if (!_assetURL)
        _assetURL = [self.uploadAttr objectForKey:@"assetURL"];
    return _assetURL;
}

- (void)doRemove
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
    [SeafGlobal.sharedObject finishUpload:self result:result];
    NSMutableDictionary *dict = self.uploadAttr;
    if (!dict) {
        dict = [[NSMutableDictionary alloc] init];
        [dict setObject:self.name forKey:@"name"];
    }
    [dict setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]]forKey:@"utime"];
    [dict setObject:[NSNumber numberWithBool:result] forKey:@"result"];
    [dict setObject:[NSNumber numberWithBool:self.autoSync] forKey:@"autoSync"];
    [self saveAttr:dict];
    Debug("result=%d, name=%@, _delegate=%@, oid=%@\n", result, self.name, _delegate, oid);
    if (result)
        [_delegate uploadSucess:self oid:oid];
    else
        [_delegate uploadProgress:self result:NO progress:0];
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

- (void)uploadByFile:(SeafConnection *)connection url:(NSString *)surl path:(NSString *)uploadpath update:(BOOL)update
{
    NSMutableURLRequest *request = [[SeafConnection requestSerializer] multipartFormRequestWithMethod:@"POST" URLString:surl parameters:nil constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        if (update) {
            [formData appendPartWithFormData:[@"1" dataUsingEncoding:NSUTF8StringEncoding] name:@"replace"];
        }
        [formData appendPartWithFormData:[uploadpath dataUsingEncoding:NSUTF8StringEncoding] name:@"parent_dir"];

        [formData appendPartWithFormData:[@"n8ba38951c9ba66418311a25195e2e380" dataUsingEncoding:NSUTF8StringEncoding] name:@"csrfmiddlewaretoken"];
        [formData appendPartWithFileURL:[NSURL fileURLWithPath:self.lpath] name:@"file" error:nil];
    } error:nil];
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    self.operation = operation;
    [operation setUploadProgressBlock:^(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite) {
        int percent = [self percentForShow:totalBytesWritten expected:totalBytesExpectedToWrite];
        [_delegate uploadProgress:self result:YES progress:percent];
    }];
    [operation setCompletionBlockWithSuccess:
     ^(AFHTTPRequestOperation *operation, id responseObject) {
         NSString *oid = nil;
         if ([responseObject isKindOfClass:[NSData class]]) {
             oid = [[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
             [[NSFileManager defaultManager] linkItemAtPath:self.lpath toPath:[SeafGlobal.sharedObject documentPath:oid] error:nil];
         }
         Debug("Upload success _uploading=%d, update=%d, oid=%@\n", _uploading, update, oid);
         [self finishUpload:YES oid:oid];
     }
                                     failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                                         Debug("Upload failed :%@,code=%ldd, res=%@, %@\n", error, (long)operation.response.statusCode, operation.responseData, operation.responseString);
                                         [self finishUpload:NO oid:nil];
                                     }];

    [connection handleOperation:operation];
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
        NSString *blockpath = [SeafGlobal.sharedObject blockPath:blockid];
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
        for (NSString *path in paths) {
            [formData appendPartWithFileURL:[NSURL fileURLWithPath:path] name:@"file" error:nil];
        }
    } error:nil];
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    [operation setUploadProgressBlock:^(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite) {
        int percent = [self percentForShow:totalBytesWritten expected:totalBytesExpectedToWrite];
        [_delegate uploadProgress:self result:YES progress:percent];
    }];
    [operation setCompletionBlockWithSuccess:
     ^(AFHTTPRequestOperation *operation, id responseObject) {
         NSString *oid = nil;
         if ([responseObject isKindOfClass:[NSData class]]) {
             oid = [[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
             [[NSFileManager defaultManager] linkItemAtPath:self.lpath toPath:[SeafGlobal.sharedObject documentPath:oid] error:nil];
         }
         Debug("Upload success _uploading=%d, oid=%@\n", _uploading, oid);
         [self finishUpload:YES oid:oid];
     }
                                     failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                                         Debug("Upload failed :%@,code=%ld, res=%@, %@\n", error, (long)operation.response.statusCode, operation.responseData, operation.responseString);
                                         [self finishUpload:NO oid:nil];
                                     }];
    [connection handleOperation:operation];
}

- (void)upload:(SeafConnection *)connection repo:(NSString *)repoId path:(NSString *)uploadpath
{
    @synchronized (self) {
        if (_uploading || self.uploaded)
            return;
        _uploading = YES;
        _uProgress = 0;
    }
    [SeafGlobal.sharedObject incUploadnum];
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.lpath error:nil];
    _filesize = attrs.fileSize;
    [_delegate uploadProgress:self result:YES progress:0];
    SeafRepo *repo = [connection getRepo:repoId];
    BOOL byblock = [connection localDecrypt:repoId];
    NSString* upload_url = [NSString stringWithFormat:API_URL"/repos/%@/upload-", repoId];
    if (byblock)
        upload_url = [upload_url stringByAppendingString:@"blks-link/"];
    else
        upload_url = [upload_url stringByAppendingString:@"link/"];

    [connection sendRequest:upload_url success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         NSString *url = JSON;
         Debug("Upload file %@ %@, %@ update=%d, byblock=%d, delegate%@\n", self.name, url, uploadpath, self.update, byblock, _delegate);
         if (byblock) {
             NSMutableArray *blockids = [[NSMutableArray alloc] init];
             NSMutableArray *paths = [[NSMutableArray alloc] init];
             NSString *passwrod = [SeafGlobal.sharedObject getRepoPassword:repo.repoId];
             if ([self chunkFile:self.lpath blockids:blockids paths:paths password:passwrod repo:repo]) {
                 [self uploadByBlocks:connection url:url uploadpath:uploadpath blocks:blockids paths:paths update:self.update];
             } else {
                 [self finishUpload:NO oid:nil];
             }
         } else {
             [self uploadByFile:connection url:url path:uploadpath update:self.update];
         }
     }
                    failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
         [self finishUpload:NO oid:nil];
     }];
}
- (void)doUpload
{
    [self checkAsset];
    return [self upload:self.udir->connection repo:self.udir.repoId path:self.udir.path];
}

- (void)setAsset:(ALAsset *)asset
{
    _asset = asset;
    _assetURL = asset.defaultRepresentation.url;
}

- (void)checkAsset
{
    if (self.asset) {
        [Utils writeDataToPath:self.lpath andAsset:self.asset];
        _filesize = [Utils fileSizeAtPath1:self.lpath];
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
        _preViewURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"view_markdown" ofType:@"html"]];
    } else if ([self.mime hasSuffix:@"seafile"]) {
        _preViewURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"view_seaf" ofType:@"html"]];
    } else {
        NSString *encodePath = [[SeafGlobal.sharedObject applicationTempDirectory] stringByAppendingPathComponent:self.name];
        if ([Utils tryTransformEncoding:encodePath fromFile:self.lpath])
            _preViewURL = [NSURL fileURLWithPath:encodePath];
    }
    if (!_preViewURL)
        _preViewURL = [NSURL fileURLWithPath:self.lpath];
    return _preViewURL;
}

- (UIImage *)icon
{
    return [UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString];
}

- (UIImage *)image
{
    return [UIImage imageWithContentsOfFile:self.lpath];
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
    [self checkAsset];
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
    if (uploadFileAttrs == nil) {
        NSString *attrsFile = [[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploadfiles.plist"];
        uploadFileAttrs = [[NSMutableDictionary alloc] initWithContentsOfFile:attrsFile];
        if (!uploadFileAttrs)
            uploadFileAttrs = [[NSMutableDictionary alloc] init];
    }
    return uploadFileAttrs;
}

+ (void)clearCache
{
    [Utils clearAllFiles:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"]];
    uploadFileAttrs = [[NSMutableDictionary alloc] init];
}

- (NSDictionary *)uploadAttr
{
    return [[SeafUploadFile uploadFileAttrs] objectForKey:self.lpath];
}

- (void)saveAttr:(NSMutableDictionary *)attr
{
    NSString *attrsFile = [[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploadfiles.plist"];
    if (attr)
        [[SeafUploadFile uploadFileAttrs] setObject:attr forKey:self.lpath];
    else
        [[SeafUploadFile uploadFileAttrs] removeObjectForKey:self.lpath];
    [[SeafUploadFile uploadFileAttrs] writeToFile:attrsFile atomically:YES];
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
            SeafUploadFile *file  = [dir->connection getUploadfile:lpath create:!autoSync];
            if (!file) {
                Debug("Auto sync photos %@:%@, remove and will reupload from beginning", file.lpath, info);
                continue;
            }
            file.udir = dir;
            file.update = [[info objectForKey:@"update"] boolValue];
            file.autoSync = autoSync;
            [files addObject:file];
        }
    }
    return files;
}

@end
