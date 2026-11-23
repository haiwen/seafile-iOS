//
//  SeafConnection+ResumableUpload.m
//  Seafile
//

#import "SeafConnection+ResumableUpload.h"
#import "SeafResumableUploadDefines.h"
#import "SeafResumableUploadStore.h"
#import "ExtentedString.h"
#import "Debug.h"

@implementation SeafConnection (ResumableUpload)

- (BOOL)isResumableUploadSupported
{
    if (!SeafResumableUploadEnabled) return NO;
    if (![self isServerVersionAtLeast:@"7.0.0"]) return NO;
    SeafResumableUploadStore *store = [SeafResumableUploadStore sharedStore];
    if (!store || self.accountIdentifier.length == 0) return NO;
    return ![store isSegmentingDisabledForAccount:self.accountIdentifier serverVersion:self.serverVersion];
}

- (NSURLSessionDataTask *)resumable_uploadedBytesInRepo:(NSString *)repoId
                                              parentDir:(NSString *)parentDir
                                               fileName:(NSString *)fileName
                                             lastModify:(NSString *)lastModify
                                             completion:(void (^)(NSInteger, NSString *, id, NSError *))completion
{
    NSMutableString *url = [NSMutableString stringWithFormat:API_URL_V21"/repos/%@/file-uploaded-bytes/?parent_dir=%@&file_name=%@",
                            repoId, parentDir.escapedUrl, fileName.escapedUrl];
    if (lastModify.length > 0) {
        // 13.0.29 reads last_modify, master reads file_mtime; older servers ignore both.
        [url appendFormat:@"&last_modify=%@&file_mtime=%@", lastModify.escapedUrl, lastModify.escapedUrl];
    }
    return [self sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        completion(response.statusCode, [response valueForHTTPHeaderField:@"Accept-Ranges"], JSON, nil);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        completion(response.statusCode, [response valueForHTTPHeaderField:@"Accept-Ranges"], JSON, error);
    }];
}

- (NSURLSessionDataTask *)resumable_uploadLinkInRepo:(NSString *)repoId
                                           parentDir:(NSString *)parentDir
                                          completion:(void (^)(NSString *, NSInteger, NSError *))completion
{
    NSString *url = [NSString stringWithFormat:API_URL"/repos/%@/upload-link/?p=%@", repoId, parentDir.escapedUrl];
    return [self sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        if ([JSON isKindOfClass:[NSString class]] && [(NSString *)JSON length] > 0) {
            completion(JSON, response.statusCode, nil);
        } else {
            completion(nil, response.statusCode, [NSError errorWithDomain:SeafResumableErrorDomain code:SeafResumableErrorRetryable
                                                                 userInfo:@{NSLocalizedDescriptionKey: @"Invalid upload link"}]);
        }
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        completion(nil, response.statusCode, error);
    }];
}

- (NSString *)resumable_fileURLForRepo:(NSString *)repoId path:(NSString *)path
{
    return [NSString stringWithFormat:API_URL_V21"/repos/%@/file/?p=%@", repoId, path.escapedUrl];
}

- (NSURLSessionDataTask *)resumable_fileInfoInRepo:(NSString *)repoId
                                              path:(NSString *)path
                                        completion:(void (^)(NSInteger, NSDictionary *, NSError *))completion
{
    return [self sendRequest:[self resumable_fileURLForRepo:repoId path:path]
                     success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        completion(response.statusCode, [JSON isKindOfClass:[NSDictionary class]] ? JSON : nil, nil);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        completion(response.statusCode, nil, error);
    }];
}

- (NSURLSessionDataTask *)resumable_listDirInRepo:(NSString *)repoId
                                             path:(NSString *)path
                                       completion:(void (^)(NSInteger, NSArray<NSDictionary *> *, NSError *))completion
{
    NSString *url = [NSString stringWithFormat:API_URL"/repos/%@/dir/?p=%@", repoId, path.escapedUrl];
    return [self sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        completion(response.statusCode, [JSON isKindOfClass:[NSArray class]] ? JSON : nil, nil);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        completion(response.statusCode, nil, error);
    }];
}

- (NSURLSessionDataTask *)resumable_renameFileInRepo:(NSString *)repoId
                                                path:(NSString *)path
                                             newName:(NSString *)newName
                                          completion:(void (^)(NSInteger, NSDictionary *, NSError *))completion
{
    NSString *form = [NSString stringWithFormat:@"operation=rename&newname=%@", newName.escapedPostForm];
    return [self sendPost:[self resumable_fileURLForRepo:repoId path:path] form:form
                  success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        completion(response.statusCode, [JSON isKindOfClass:[NSDictionary class]] ? JSON : nil, nil);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        completion(response.statusCode, nil, error);
    }];
}

- (void)resumable_deleteFileInRepo:(NSString *)repoId
                              path:(NSString *)path
                        completion:(void (^)(NSInteger, NSError *))completion
{
    [self sendDelete:[self resumable_fileURLForRepo:repoId path:path]
             success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        completion(response.statusCode, nil);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        completion(response.statusCode, error);
    }];
}

- (NSURLSessionDataTask *)resumable_downloadURLInRepo:(NSString *)repoId
                                                 path:(NSString *)path
                                           completion:(void (^)(NSString *, NSInteger, NSError *))completion
{
    NSString *url = [NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@&reuse=1", repoId, path.escapedUrl];
    return [self sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        completion([JSON isKindOfClass:[NSString class]] ? JSON : nil, response.statusCode, nil);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        completion(nil, response.statusCode, error);
    }];
}

- (NSURLSessionDownloadTask *)resumable_readRangeFromURL:(NSString *)url
                                                  offset:(long long)offset
                                                  length:(NSUInteger)length
                                              completion:(void (^)(NSData *, NSInteger, NSError *))completion
{
    NSURL *target = [NSURL URLWithString:url];
    if (!target || length == 0) {
        completion(nil, 0, [NSError errorWithDomain:SeafResumableErrorDomain code:SeafResumableErrorRetryable userInfo:nil]);
        return nil;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:target];
    request.timeoutInterval = 60;
    [request setValue:[NSString stringWithFormat:@"bytes=%lld-%lld", offset, offset + (long long)length - 1] forHTTPHeaderField:@"Range"];
    // The process's own tmp: the shared tempDir is emptied at main-app launch, when the sweeper reads too.
    NSString *dest = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSURLSessionDownloadTask *task = [self.sessionMgr downloadTaskWithRequest:request progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        return [NSURL fileURLWithPath:dest];
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSData *data = filePath ? [NSData dataWithContentsOfURL:filePath] : nil;
        if (filePath) [[NSFileManager defaultManager] removeItemAtURL:filePath error:nil];
        completion(error ? nil : data, status, error);
    }];
    [task resume];
    return task;
}

- (NSURLSessionUploadTask *)resumable_uploadSegment:(NSURLRequest *)request
                                           fromFile:(NSURL *)bodyFile
                                           progress:(void (^)(int64_t, int64_t))progress
                                         completion:(void (^)(NSHTTPURLResponse *, id, NSError *))completion
{
    NSURLSessionUploadTask *task = [self.sessionMgr uploadTaskWithRequest:request fromFile:bodyFile progress:^(NSProgress *p) {
        if (progress) progress(p.completedUnitCount, p.totalUnitCount);
    } completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
        completion([response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil, responseObject, error);
    }];
    [task resume];
    return task;
}

@end
