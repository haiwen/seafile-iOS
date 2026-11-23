//
//  SeafUploadOperation.m
//  Seafile
//
//  Created by henry on 2024/11/11.
//

// SeafUploadOperation.m

#import "SeafUploadOperation.h"
#import "SeafUploadFile.h"
#import "SeafConnection.h"
#import "SeafDir.h"
#import "Utils.h"
#import "Debug.h"
#import "SeafRepos.h"
#import "SeafStorage.h"
#import "SeafUploadFileModel.h"
#import "SeafResumableUploadSession.h"
#import "SeafResumableUploadPolicy.h"
#import "SeafConnection+ResumableUpload.h"

// Time interval (in seconds) after which encrypted repo password should be refreshed on server
#define REPO_PASSWORD_REFRESH_INTERVAL 300

@interface SeafUploadOperation ()
/// The resumable session of the current attempt, if this file is segmented.
@property (nonatomic, strong) SeafResumableUploadSession *resumableSession;
/// Set when the server refused the upload for good: the operation does not retry it.
@property (nonatomic, assign) BOOL terminalFailure;
@end

@implementation SeafUploadOperation

- (instancetype)initWithUploadFile:(SeafUploadFile *)uploadFile
{
    if (self = [super init]) {
        _uploadFile = uploadFile;

        _retryCount = 0;
        self.maxRetryCount = uploadFile.retryable ? DEFAULT_RETRYCOUNT : 0;
    }
    return self;
}

#pragma mark - NSOperation Overrides

- (void)start
{
    [super start];
    if (self.isFinished) {
        return;
    }
    if (self.isCancelled) {
        // Cancelled between the check in -[SeafBaseOperation start] and the switch to
        // executing: -cancel saw a non-executing operation and left the finish to us.
        // Returning here would leave it executing forever, holding a queue slot and
        // blocking a later task with the same path from being added.
        [self completeOperation];
        return;
    }
    // Backups queued just before a pause, or re-added after a network outage,
    // must not start while the account's photo backup is paused.
    if (self.uploadFile.uploadFileAutoSync && self.uploadFile.udir.connection.photoBackupPaused) {
        Debug("Photo backup paused, cancel %@", self.uploadFile.name);
        [self cancel];
        return;
    }

    // Begin the upload process
    __block BOOL answered = NO;
    [self.uploadFile prepareForUploadWithCompletion:^(BOOL success, NSError *error) {
        // An asset that has to come from iCloud can answer twice: PhotoKit
        // reports the failed download to the progress handler and then calls
        // the result handler without data (SeafAssetManager). The first
        // answer carries the reason; the second would report the same
        // failure again.
        @synchronized (self) {
            if (answered) return;
            answered = YES;
        }
        if (self.isCancelled) {
            [self completeOperation];
            return;
        }
        if (!success) {
            [self failPreparation:error];
            return;
        }

        [self beginUpload];
    }];
}

/// The upload fails before anything was sent (the local file or the library
/// is gone). SeafUploadFile only reports the end of an upload it considers
/// started, so the file is marked first: a failure nobody hears about is
/// neither counted by the queue nor remembered by whoever queued the file,
/// which then queues it again on every timer tick.
- (void)failBeforeTransfer:(NSError *)error
{
    self.uploadFile.model.uploading = YES;
    [self finishUpload:NO oid:nil error:error ?: [Utils defaultError]];
}

/// The file could not be prepared (the asset could not be exported). Reported
/// like any failure before the transfer, but never retried from here: a retry
/// starts at -beginUpload and does not prepare again, so it would wait out
/// its delays, replace this error with a placeholder, and send whatever a
/// failed export left at the path (an empty or truncated file passes the
/// "file exists" check).
- (void)failPreparation:(NSError *)error
{
    self.uploadFile.model.uploading = YES;
    NSString *oid = nil;
    [self.uploadFile finishUpload:NO oid:oid error:error ?: [Utils defaultError]];
    [self completeOperation];
}

- (void)cancel
{
    [super cancel];
    [self.resumableSession cancel];

    if (self.isExecuting && !self.operationCompleted) {
        // create cancel NSError
        NSError *cancelError = [NSError errorWithDomain:NSURLErrorDomain
                                                       code:NSURLErrorCancelled
                                                   userInfo:@{NSLocalizedDescriptionKey: @"The upload task was cancelled."}];

        [self finishUpload:NO oid:nil error:cancelError];
        [self completeOperation];
    }
}

#pragma mark - Upload Logic

- (void)beginUpload
{
    if (!self.uploadFile.udir.repoId || !self.uploadFile.udir.path) {
        [self failBeforeTransfer:nil];
        return;
    }

    SeafConnection *connection = self.uploadFile.udir.connection;
    NSString *repoId = self.uploadFile.udir.repoId;
    NSString *uploadPath = self.uploadFile.udir.path;

    [self upload:connection repo:repoId path:uploadPath];
}

// SeafUploadFile upload logic
- (void)upload:(SeafConnection *)connection repo:(NSString *)repoId path:(NSString *)uploadpath
{
    if (![Utils fileExistsAtPath:self.uploadFile.lpath]) {
        Warning("File %@ does not exist", self.uploadFile.lpath);
        [self failBeforeTransfer:nil];
        return;
    }

    SeafRepo *repo = [connection getRepo:repoId];
    if (!repo) {
        Warning("Repo %@ does not exist", repoId);
        [self failBeforeTransfer:nil];
        return;
    }

    self.uploadFile.model.uploading = YES;

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.uploadFile.lpath error:nil];
    self.uploadFile.model.filesize = attrs.fileSize;

    // For encrypted repos, ensure server-side password cache is valid before uploading
    // This fixes the issue where uploads to encrypted libraries fail when accessed via iOS Files app
    // after the server-side password cache has expired (typically ~1 hour)
    if (repo.encrypted) {
        NSString *password = [connection getRepoPassword:repoId];
        if (password) {
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            NSTimeInterval lastRefresh = [connection getRepoLastRefreshPasswordTime:repoId];
            if (now - lastRefresh > REPO_PASSWORD_REFRESH_INTERVAL) {
                Debug("Encrypted repo %@ password cache expired, refreshing before upload...", repoId);
                __weak typeof(self) weakSelf = self;
                [repo setRepoPassword:password block:^(SeafBase *entry, int ret) {
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) return;

                    if (ret == RET_SUCCESS) {
                        Debug("Password refreshed successfully, proceeding with upload");
                        [strongSelf doUpload:connection repo:repoId path:uploadpath];
                    } else {
                        Warning("Failed to refresh encrypted repo password, ret=%d", ret);
                        [strongSelf finishUpload:NO oid:nil error:[Utils defaultError]];
                    }
                }];
                return;
            }
        }
    }

    [self doUpload:connection repo:repoId path:uploadpath];
}

// Actual upload logic after password validation
- (void)doUpload:(SeafConnection *)connection repo:(NSString *)repoId path:(NSString *)uploadpath
{
    if (self.isCancelled) return;
    if ([self shouldUploadResumably:connection repo:repoId]) {
        [self resumableUpload:connection repo:repoId path:uploadpath];
        return;
    }
    [self singleRequestUpload:connection repo:repoId path:uploadpath];
}

/// The existing upload: the whole file in one multipart POST.
- (void)singleRequestUpload:(SeafConnection *)connection repo:(NSString *)repoId path:(NSString *)uploadpath
{
    Debug("Uploading file %@ as single request (size=%lld)", self.uploadFile.name, self.uploadFile.filesize);

    NSString *uploadURL = [NSString stringWithFormat:API_URL"/repos/%@/upload-link/?p=%@", repoId, uploadpath.escapedUrl];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *connectUploadLinkTask = [connection sendRequest:uploadURL success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        // Cancellation already reported the outcome; do not start the upload request.
        if (!strongSelf || strongSelf.isCancelled) return;
        NSString *url = [JSON stringByAppendingString:@"?ret-json=true"];
        [strongSelf uploadByFile:connection url:url path:uploadpath update:strongSelf.uploadFile.overwrite];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf finishUpload:NO oid:nil error:error];
    }];

    @synchronized (self.taskList) {
        [self.taskList addObject:connectUploadLinkTask];
    }
}

#pragma mark - Resumable upload (docs/versions/_unreleased/features/upload-resume-plan.md)

/// Plan §4.1: size, unencrypted library, server and account support, plain rw permission.
/// Whether the target exists (for overwriting tasks) is checked by the session.
- (BOOL)shouldUploadResumably:(SeafConnection *)connection repo:(NSString *)repoId
{
    SeafUploadFile *ufile = self.uploadFile;
    if (![SeafResumableUploadPolicy shouldSegmentFileOfSize:ufile.filesize]) return NO;
    if (ufile.model.taskId.length == 0) return NO;
    if ([connection getRepo:repoId].encrypted) return NO;          // phase 1 (plan D5)
    if (![ufile.udir.perm isEqualToString:@"rw"]) return NO;       // custom permissions may forbid renaming
    return connection.isResumableUploadSupported;
}

- (NSString *)resumableEntryName
{
    if (self.uploadFile.uploadFileAutoSync) return @"photo-backup";
    if (![Utils isMainApp]) {
        // Nothing runs a share-extension task again, so its attempts are finished by the sweeper (plan §9).
        NSDictionary *extension = [NSBundle mainBundle].infoDictionary[@"NSExtension"];
        if ([extension isKindOfClass:[NSDictionary class]]
            && [extension[@"NSExtensionPointIdentifier"] isEqual:@"com.apple.share-services"]) {
            return SeafResumableEntryShare;
        }
        return self.uploadFile.isEditedFile ? @"extension-edit" : @"extension";
    }
    return self.uploadFile.isEditedFile ? @"edit" : @"manual";
}

- (void)resumableUpload:(SeafConnection *)connection repo:(NSString *)repoId path:(NSString *)uploadpath
{
    SeafUploadFile *ufile = self.uploadFile;
    // Show what is already on the server before the first request (plan §6.2).
    long long confirmed = [SeafResumableUploadSession confirmedBytesForTaskId:ufile.model.taskId];
    if (confirmed > 0 && ufile.filesize > 0) {
        [ufile uploadProgress:(float)((double)confirmed / (double)ufile.filesize)];
    }

    SeafResumableUploadSession *session =
        [[SeafResumableUploadSession alloc] initWithConnection:connection
                                                        repoId:repoId
                                                     parentDir:uploadpath
                                                    targetName:ufile.name
                                                     localPath:ufile.lpath
                                                      fileSize:ufile.filesize
                                                    lastModify:[SeafResumableUploadPolicy lastModifyStringForDate:ufile.lastModified]
                                                     overwrite:ufile.overwrite
                                                        taskId:ufile.model.taskId
                                                         entry:[self resumableEntryName]];
    __weak typeof(self) weakSelf = self;
    session.progressHandler = ^(float progress) {
        [weakSelf.uploadFile uploadProgress:progress];
    };
    session.userCancelled = ^BOOL{
        return weakSelf.uploadFile.model.userCancelled;
    };
    self.resumableSession = session;
    [session startWithCompletion:^(SeafResumableOutcome outcome, NSString *oid, NSString *serverDate, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.resumableSession = nil;
        // A cancelled operation has already reported its outcome (-cancel).
        if (strongSelf.isCancelled || strongSelf.operationCompleted) return;
        switch (outcome) {
            case SeafResumableOutcomeSuccess:
                strongSelf.uploadFile.serverDateHeader = serverDate;
                [strongSelf finishUpload:YES oid:oid error:nil];
                break;
            case SeafResumableOutcomeFallback:
                [strongSelf singleRequestUpload:connection repo:repoId path:uploadpath];
                break;
            case SeafResumableOutcomeTerminal:
                strongSelf.terminalFailure = YES;
                [strongSelf finishUpload:NO oid:nil error:error];
                break;
            case SeafResumableOutcomeCancelled:
                // The user removed the task: no retry.
                strongSelf.terminalFailure = YES;
                [strongSelf finishUpload:NO oid:nil error:error];
                break;
            case SeafResumableOutcomeRetryable:
                [strongSelf finishUpload:NO oid:nil error:error];
                break;
        }
    }];
}

#pragma mark - Single request

- (void)uploadByFile:(SeafConnection *)connection url:(NSString *)surl path:(NSString *)uploadpath update:(BOOL)update
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
    [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    NSString *lastModifiedString = self.uploadFile.lastModified ? [formatter stringFromDate:self.uploadFile.lastModified] : nil;

    NSMutableURLRequest *request = [[SeafConnection requestSerializer] multipartFormRequestWithMethod:@"POST" URLString:surl parameters:nil constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        if (update) {
            [formData appendPartWithFormData:[@"1" dataUsingEncoding:NSUTF8StringEncoding] name:@"replace"];
        }
        [formData appendPartWithFormData:[uploadpath dataUsingEncoding:NSUTF8StringEncoding] name:@"parent_dir"];
        if (lastModifiedString) {
            [formData appendPartWithFormData:[lastModifiedString dataUsingEncoding:NSUTF8StringEncoding] name:@"last_modify"];
        }
        [formData appendPartWithFormData:[@"n8ba38951c9ba66418311a25195e2e380" dataUsingEncoding:NSUTF8StringEncoding] name:@"csrfmiddlewaretoken"];
        NSError *error = nil;
        [formData appendPartWithFileURL:[NSURL fileURLWithPath:self.uploadFile.lpath] name:@"file" error:&error];
        if (error != nil)
            Debug("Error appending file part: %@", error);
    } error:nil];
    [self uploadRequest:request withConnection:connection];
}

- (void)uploadRequest:(NSMutableURLRequest *)request withConnection:(SeafConnection *)connection
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.uploadFile.lpath]) {
        [self finishUpload:NO oid:nil error:nil];
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *uploadByFileTask = [connection.sessionMgr dataTaskWithRequest:request uploadProgress:^(NSProgress * _Nonnull uploadProgress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
//        [strongSelf.uploadFile updateProgressWithoutKVO:uploadProgress];
        [strongSelf.uploadFile uploadProgress:uploadProgress.fractionCompleted];
    } downloadProgress:nil completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (error) {
            [strongSelf finishUpload:NO oid:nil error:error];
        } else {
            NSString *oid = nil;
            if ([responseObject isKindOfClass:[NSArray class]]) {
                oid = [[responseObject objectAtIndex:0] objectForKey:@"id"];
            } else if ([responseObject isKindOfClass:[NSDictionary class]]) {
                oid = [responseObject objectForKey:@"id"];
            }
            if (!oid || oid.length < 1) oid = [[NSUUID UUID] UUIDString];
            strongSelf.uploadFile.serverDateHeader = [response isKindOfClass:NSHTTPURLResponse.class]
                ? [(NSHTTPURLResponse *)response valueForHTTPHeaderField:@"Date"] : nil;
            [strongSelf finishUpload:YES oid:oid error:nil];
        }
    }];

    [uploadByFileTask resume];

    @synchronized (self.taskList) {
        [self.taskList addObject:uploadByFileTask];
    }
}

//after upload
- (void)finishUpload:(BOOL)result oid:(NSString *)oid error:(NSError *)error {
    if (result) {
        [self.uploadFile finishUpload:result oid:oid error:error];
        [self completeOperation];
    } else {
        if (self.isCancelled) {
            [self.uploadFile finishUpload:result oid:oid error:error];
            [self completeOperation];
            return;
        }
        if (!self.terminalFailure && self.retryCount < self.maxRetryCount) {
            self.retryCount += 1;
            Debug(@"Upload failed, retrying %ld/%ld in %.0f seconds", (long)self.retryCount, (long)self.maxRetryCount, UPLOAD_RETRY_DELAY);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(UPLOAD_RETRY_DELAY * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!self.isCancelled) {
                    [self beginUpload];
                } else {
                    [self completeOperation];
                }
            });
        } else {
            [self.uploadFile finishUpload:result oid:oid error:error];
            [self completeOperation];
        }
    }
}

- (void)completeOperation {
    self.resumableSession = nil;
    [super completeOperation];
}

@end
