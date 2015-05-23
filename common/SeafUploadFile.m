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
@property (strong) NSURLSessionUploadTask *task;
@property (strong) NSProgress *progress;
@property long long mtime;
@end

@implementation SeafUploadFile


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
        if ([self.uploadAttr objectForKey:@"mtime"] != nil) {
            self.mtime = [[self.uploadAttr objectForKey:@"mtime"] longLongValue];
        } else {
            self.mtime = [[NSDate date] timeIntervalSince1970];
        }
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

- (NSURL *)assetURL
{
    if (!_assetURL)
        _assetURL = [self.uploadAttr objectForKey:@"assetURL"];
    return _assetURL;
}

- (void)doRemove
{
    [self.task cancel];
    self.task = nil;
    [self saveAttr:nil flush:true];
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
        if (!_uploading) return;
        _uploading = NO;
        self.task = nil;
        if (_progress) {
            [_progress removeObserver:self
                           forKeyPath:@"fractionCompleted"
                              context:NULL];
            _progress = nil;
        }
    }
    [SeafGlobal.sharedObject finishUpload:self result:result];
    NSMutableDictionary *dict = self.uploadAttr;
    if (!dict) {
        dict = [[NSMutableDictionary alloc] init];
        [dict setObject:self.name forKey:@"name"];
    }
    [dict setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]]forKey:@"utime"];
    [dict setObject:[NSNumber numberWithLongLong:self.mtime] forKey:@"mtime"];
    [dict setObject:[NSNumber numberWithBool:result] forKey:@"result"];
    [dict setObject:[NSNumber numberWithBool:self.autoSync] forKey:@"autoSync"];
    [self saveAttr:dict flush:true];
    Debug("result=%d, name=%@, delegate=%@, oid=%@\n", result, self.name, _delegate, oid);
    if (result)
        [_delegate uploadSucess:self oid:oid];
    else
        [_delegate uploadProgress:self result:NO progress:0];
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
            // TODO This a bug in seafile http server: Request failed: unacceptable content-type: (null)
            NSData *data = [error.userInfo objectForKey:@"com.alamofire.serialization.response.error.data"];
            responseObject = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            error = nil;
        }
        if (error) {
            Debug("Upload failed :%@,code=%ldd, res=%@\n", error, (long)resp.statusCode, responseObject);
            [self finishUpload:NO oid:nil];
        } else {
            Debug("Successfully upload file:%@", self.name);
            NSString *oid = responseObject;
            [[NSFileManager defaultManager] linkItemAtPath:self.lpath toPath:[SeafGlobal.sharedObject documentPath:oid] error:nil];
            [self finishUpload:YES oid:oid];
        }
    }];

    _progress =progress;
    [_progress addObserver:self
               forKeyPath:@"fractionCompleted"
                  options:NSKeyValueObservingOptionNew
                  context:NULL];
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
        [formData appendPartWithFileURL:[NSURL fileURLWithPath:self.lpath] name:@"file" error:nil];
    } error:nil];
    [self uploadRequest:request withConnection:connection];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (![keyPath isEqualToString:@"fractionCompleted"] || ![object isKindOfClass:[NSProgress class]]) return;
    NSProgress *progress = (NSProgress *)object;
    int percent = MIN(progress.fractionCompleted * 100, 99);
    [_delegate uploadProgress:self result:YES progress:percent];
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

    [self uploadRequest:request withConnection:connection];
}

- (void)upload:(SeafConnection *)connection repo:(NSString *)repoId path:(NSString *)uploadpath
{
    @synchronized (self) {
        if (_uploading || self.uploaded)
            return;
        _uploading = YES;
        _uProgress = 0;
    }
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

    upload_url = [upload_url stringByAppendingFormat:@"?p=%@", uploadpath.escapedUrl];
    [connection sendRequest:upload_url success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
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
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
         [self finishUpload:NO oid:nil];
     }];
}

- (BOOL)canUpload
{
    if (self.autoSync && _udir->connection.wifiOnly)
        return [[AFNetworkReachabilityManager sharedManager] isReachableViaWiFi];
    else
        return [[AFNetworkReachabilityManager sharedManager] isReachable];
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
    if (_asset) {
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
        NSString *encodePath = [SeafGlobal.sharedObject.tempDir stringByAppendingPathComponent:self.name];
        if ([Utils tryTransformEncoding:encodePath fromFile:self.lpath])
            _preViewURL = [NSURL fileURLWithPath:encodePath];
    }
    if (!_preViewURL)
        _preViewURL = [NSURL fileURLWithPath:self.lpath];
    return _preViewURL;
}

- (UIImage *)icon;
{
    if (_asset)
        return [UIImage imageWithCGImage:_asset.thumbnail];

    UIImage *img = [self isImageFile] ? self.image : nil;
    return img ? [Utils reSizeImage:img toSquare:32.0f] : [UIImage imageForMimeType:self.mime ext:self.name.pathExtension.lowercaseString];
}

- (UIImage *)image
{
    if (_asset)
        return [UIImage imageWithCGImage:_asset.defaultRepresentation.fullResolutionImage];
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

+ (BOOL)saveAttrs
{
    NSString *attrsFile = [[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploadfiles.plist"];
    return [[SeafUploadFile uploadFileAttrs] writeToFile:attrsFile atomically:true];
}

+ (void)clearCache
{
    [Utils clearAllFiles:SeafGlobal.sharedObject.uploadsDir];
    uploadFileAttrs = [[NSMutableDictionary alloc] init];
}

- (NSDictionary *)uploadAttr
{
    return [[SeafUploadFile uploadFileAttrs] objectForKey:self.lpath];
}

- (BOOL)saveAttr:(NSMutableDictionary *)attr flush:(BOOL)flush
{
    if (attr)
        [[SeafUploadFile uploadFileAttrs] setObject:attr forKey:self.lpath];
    else
        [[SeafUploadFile uploadFileAttrs] removeObjectForKey:self.lpath];
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
            if (!file || (!file.asset && file.filesize == 0)) {
                Debug("Auto sync photos %@:%@, remove it and will reupload from beginning", file.lpath, info);
                [uploadFileAttrs removeObjectForKey:lpath];
                changed = true;
                continue;
            }
            file.udir = dir;
            file.update = [[info objectForKey:@"update"] boolValue];
            file.autoSync = autoSync;
            [files addObject:file];
        }
    }
    if (changed) [SeafUploadFile saveAttrs];
    return files;
}

@end
