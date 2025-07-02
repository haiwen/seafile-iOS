//
//  SeafFile.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//
#import <Foundation/Foundation.h>
#import "SeafFile.h"
#import "SeafRepos.h"
#import "SeafThumb.h"
#import "SeafDataTaskManager.h"
#import "SeafStorage.h"
#import "FileMimeType.h"
#import "ExtentedString.h"
#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "NSData+Encryption.h"
#import "Debug.h"
#import "Utils.h"
#import "SeafCacheManager.h"
#import <FileProvider/NSFileProviderError.h>
#import "SeafFilePreviewHandler.h"
#import "SeafCacheManager+Thumb.h"
#import "SeafUploadFileModel.h"

@interface SeafFile()

@property (nonatomic, strong) UIImage *icon;

@property (readwrite, nonatomic, copy) SeafThumbCompleteBlock thumbCompleteBlock;
@property (readwrite, nonatomic, copy) SeafDownloadCompletionBlock fileDidDownloadBlock;
@property (readwrite, nonatomic) SeafUploadCompletionBlock uploadCompletionBlock;
@property (nonatomic) TaskProgressBlock taskProgressBlock;
@property (assign, nonatomic) BOOL isFileEditedAgain; // to set SeafUploadFile shouldShowUploadFailure property

@property (nonatomic, copy) void(^downloadCompletion)(BOOL success, NSError *error);
@property (nonatomic, copy) void(^uploadCompletion)(BOOL success, NSError *error);

@end

@implementation SeafFile
@synthesize exportURL = _exportURL;
@synthesize preViewURL = _preViewURL;
@synthesize lastFinishTimestamp = _lastFinishTimestamp;

#pragma mark - Initialization

- (nonnull id)initWithConnection:(nonnull SeafConnection *)aConnection
                     oid:(nullable NSString *)anId
                  repoId:(nonnull NSString *)aRepoId
                    name:(nonnull NSString *)aName
                    path:(nonnull NSString *)aPath
                   mtime:(long long)mtime
                    size:(unsigned long long)size {
    SeafFileModel *model = [[SeafFileModel alloc] initWithOid:anId
                                                      repoId:aRepoId
                                                       name:aName
                                                       path:aPath
                                                      mtime:mtime
                                                         size:size connection:aConnection];
    return [self initWithModel:model connection:aConnection];
}

- (instancetype)initWithModel:(SeafFileModel *)model connection:(SeafConnection *)connection {
    self = [super init];
    if (self) {
        _model = model;
        self.connection = connection;
        _previewHandler = [[SeafFilePreviewHandler alloc] initWithFile:model];
    }
    return self;
}

#pragma mark - Basic Info & Detail
// oid
- (NSString *)oid {
    return self.model.oid;
}
- (void)setOid:(NSString *)oid {
    self.model.oid = oid;
}

// repoId
- (NSString *)repoId {
    return self.model.repoId;
}
- (void)setRepoId:(NSString *)repoId {
    self.model.repoId = repoId;
}

// name
- (NSString *)name {
    return self.model.name;
}
- (void)setName:(NSString *)name {
    self.model.name = name;
}

// path
- (NSString *)path {
    return self.model.path;
}
- (void)setPath:(NSString *)path {
    self.model.path = path;
}

- (void)setMtime:(long long)mtime {
    self.model.mtime = mtime;
}

- (void)setFilesize:(long long)filesize {
    self.model.filesize = filesize;
}

- (NSString *)detailText
{
    NSString *str = [FileSizeFormatter stringFromLongLong:self.filesize];
    if (self.mtime) {
        NSString *timeStr = [SeafDateFormatter stringFromLongLong:self.mtime];
        str = [str stringByAppendingFormat:@" · %@", timeStr];
    }
    if (self.mpath) {
        if (self.ufile.model.uploading)
            return [str stringByAppendingFormat:@", %@", NSLocalizedString(@"uploading", @"Seafile")];
        else
            return [str stringByAppendingFormat:@", %@", NSLocalizedString(@"modified", @"Seafile")];
    }
    return str;
}

- (NSString *)starredDetailText
{
    NSString *str = self.repoName;
    if (self.mtime) {
        NSString *timeStr = [SeafDateFormatter stringFromLongLong:self.mtime];
        if (str && str > 0){
            str = [str stringByAppendingFormat:@" · %@", timeStr];
        } else {
            str = timeStr;
        }
    }
    if (self.mpath) {
        if (self.ufile.uploading)
            return [str stringByAppendingFormat:@", %@", NSLocalizedString(@"uploading", @"Seafile")];
        else
            return [str stringByAppendingFormat:@", %@", NSLocalizedString(@"modified", @"Seafile")];
    }
    return str;
}

- (NSString *)accountIdentifier
{
    return self.connection.accountIdentifier;
}

- (NSString *)uniqueKey
{
    NSString *normalizedPath = self.path;
    
    // Check and remove the "/" prefix from _path
    if ([normalizedPath hasPrefix:@"/"]) {
        normalizedPath = [normalizedPath substringFromIndex:1];
    }
    self.uniqueKey = [NSString stringWithFormat:@"%@/%@/%@", self.connection.accountIdentifier, self.repoId, self.name];
    return [super uniqueKey];
}

#pragma mark - Path & OID Handling

- (NSString *)thumbPath:(NSString *)objId
{
    return [[SeafCacheManager sharedManager] thumbPath:objId sFile:self];
}

- (void)updateWithEntry:(SeafBase *)entry
{
    [[SeafCacheManager sharedManager] updateWithEntry:entry sFile:self];
}

- (void)setOoid:(NSString *)ooid
{
    super.ooid = ooid;
    _exportURL = nil;
    _preViewURL = nil;
}

#pragma mark - Downloading State & Methods
- (BOOL)isDownloading {
    return self.state == SEAF_DENTRY_LOADING;
}

- (void)finishDownload:(NSString *)ooid
{
    if ([Utils isMainApp]) {
        [[SeafCacheManager sharedManager] saveOidToLocalDB:ooid seafFile:self connection:self.connection];
    }
    Debug("%@ ooid=%@, self.ooid=%@, oid=%@", self.name, ooid, self.ooid, self.oid);
    BOOL updated = ![ooid isEqualToString:self.ooid];
    [self setOoid:ooid];
    self.state = SEAF_DENTRY_SUCCESS;
    self.oid = ooid;
    [[SeafCacheManager sharedManager] saveThumbFromEncrypetedFile:self];
    [self downloadComplete:updated];
}

- (void)failedDownload:(NSError *)error
{
    [self downloadFailed:error];
}

- (void)cancelThumb
{
    [_thumbtask cancel];
    _thumbtask = nil;
}

- (void)finishDownloadThumb:(BOOL)success{
    Debug("finishDownloadThumb: %@ success: %d", self.name, success);
    if (self.thumbCompleteBlock)
        self.thumbCompleteBlock(success);
    _thumbtask = nil;
    if (success || _icon || self.image) {
        @weakify(self);
        dispatch_async(dispatch_get_main_queue(), ^{
            @strongify(self);
            [self.delegate download:self complete:false];
        });
    }
}

- (void)setThumbCompleteBlock:(nullable SeafThumbCompleteBlock)block
{
    _thumbCompleteBlock = block;
}

- (void)downloadfile
{
    [[SeafDataTaskManager sharedObject] addFileDownloadTask:self priority:NSOperationQueuePriorityVeryHigh];
}

- (void)realLoadContent
{
    if (self.state == SEAF_DENTRY_LOADING) {
        [self loadCache];
        [self downloadfile];
    } else {
        Debug("File %@ is already downloading.", self.name);
    }
}

- (void)load:(id<SeafDentryDelegate>)delegate force:(BOOL)force
{
    if (delegate != nil) self.delegate = delegate;
    self.udelegate = delegate;
    [self loadContent:force];
}

#pragma mark - File Type Checks
- (BOOL)isImageFile
{
    return [Utils isImageFile:self.name];
}

- (BOOL)isVideoFile
{
    return [Utils isVideoFile:self.name];
}

- (BOOL)isWebOpenFile {
    return [self.mime isEqualToString:@"application/sdoc"] || [self.mime isEqualToString:@"application/x-exdraw"] || [self.mime isEqualToString:@"application/x-draw"];
}

#pragma mark - Icon & Thumbnail

- (UIImage *)icon
{
    if (_icon) return _icon;
    UIImage *thumb = [[SeafCacheManager sharedManager] iconForFile:self];
    if (thumb) {
        return thumb;
    }
    return [super icon];
}

- (UIImage *)thumb
{
    return [[SeafCacheManager sharedManager] thumbForFile:self];
}

#pragma mark - Cache Checking & Loading
- (BOOL)hasCache {
    return [[SeafCacheManager sharedManager] fileHasCache:self];
}

- (BOOL)realLoadCache {
    return [[SeafCacheManager sharedManager] realLoadCache:self];
}

- (BOOL)loadCache {
    return [[SeafCacheManager sharedManager] loadFileCache:self];
}

- (BOOL)savetoCache {
    return [[SeafCacheManager sharedManager] saveFileCache:self];
}

- (void)clearCache {
    [[SeafCacheManager sharedManager] clearFileCache:self];
}

- (void)deleteCache {
    [[SeafCacheManager sharedManager] deleteCacheForFile:self];
}
#pragma mark - QLPreviewItem
- (NSURL *)previewItemURL
{
    _preViewURL = [self.previewHandler getPreviewItemURLWithSeafFile:self
                                                      oldPreviewURL:_preViewURL];
    return _preViewURL;
}

- (NSString *)previewItemTitle
{
    return [self.previewHandler getPreviewItemTitle];
}

- (NSString *)mime
{
    return [FileMimeType mimeType:self.name];
}

- (BOOL)editable
{
    return [[self.connection getRepo:self.repoId] editable] && [self.mime hasPrefix:@"text/"];
}

#pragma mark - Image Content

- (UIImage *)image
{
    if (!self.ooid)
        return nil;
    NSString *path = [SeafStorage.sharedObject documentPath:self.ooid];
    NSString *name = [@"cacheimage-preview-" stringByAppendingString:self.name];
    NSString *cachePath = [[[SeafStorage.sharedObject tempDir] stringByAppendingPathComponent:self.ooid] stringByAppendingPathComponent:name];
    return [Utils imageFromPath:path withMaxSize:IMAGE_MAX_SIZE cachePath:cachePath];
}

- (void)getImageWithCompletion:(void (^)(UIImage *image))completion {
    if (!self.ooid) {
        return completion(nil);
    }
    NSString *path = [SeafStorage.sharedObject documentPath:self.ooid];
    NSString *name = [@"cacheimage-preview-" stringByAppendingString:self.name];
    NSString *cachePath = [[[SeafStorage.sharedObject tempDir] stringByAppendingPathComponent:self.ooid] stringByAppendingPathComponent:name];
    [Utils imageFromPath:path withMaxSize:IMAGE_MAX_SIZE cachePath:cachePath completion:^(UIImage *image) {
        completion(image);
    }];
}

#pragma mark - File Size & Mtime

- (long long)filesize
{
    return (self.mpath) ? [Utils fileSizeAtPath1:self.mpath] : self.model.filesize;
}

- (long long)mtime
{
    if (self.mpath) {
        NSDictionary* fileAttribs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.mpath error:nil];
        NSDate *date = [fileAttribs objectForKey:NSFileModificationDate];
        return [date timeIntervalSince1970];
    }
    return self.model.mtime;
}

- (void)unload
{

}

#pragma mark - Text Content Editing

- (NSString *)strContent
{
    return [Utils stringContent:self.cachePath];
}

- (NSString *)cachePath
{
    return [[SeafCacheManager sharedManager] cachePathForFile:self];
}

- (void)autoupload
{
    if (self.ufile) {
        NSString *newModifiedPath = [self.mpath copy];
        [SeafDataTaskManager.sharedObject removeUploadTask:self.ufile forAccount:self.connection];
        [self.ufile cleanup];
        self.ufile = nil;
        [self setMpath:newModifiedPath];
        self.isFileEditedAgain = true;
    }
    [self update:self.udelegate];
}

- (void)setMpath:(NSString *)mpath
{
    // Debug("filesize=%lld mtime=%lld, mpath=%@", self.filesize, self.mtime, mpath);
    @synchronized (self) {
        _mpath = mpath;
        [self savetoCache];
        _preViewURL = nil;
        _exportURL = nil;
    }
}

- (BOOL)saveStrContent:(NSString *)content
{
    NSString *dir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.editDir];
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

- (BOOL)uploadFromFile:(NSURL *_Nonnull)url
{
    Debug("file %@ from:%@, repo:%@, account:%@ %@", self.name, url, self.repoId, self.connection.address, self.connection.username);
    NSString *dir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.editDir];
    if (![Utils checkMakeDir:dir])
        return NO;

    NSString *newpath = [dir stringByAppendingPathComponent:self.name];
    NSError *error = nil;
    BOOL ret = [Utils linkFileAtPath:url.path to:newpath error:&error];
    if (ret) {
        [self setMpath:newpath];
        Debug(@"linked newpath : %@ file size: %lld", newpath, [Utils fileSizeAtPath1:newpath]);
        [self autoupload];
    } else {
        Warning("Failed to copy file %@ to %@: %@", url, newpath, error);
    }
    return ret;
}

- (BOOL)saveEditedPreviewFile:(NSURL *)url {
    NSString *editDir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.editDir];
    if (![Utils checkMakeDir:editDir])
        return NO;

    NSString *newpath = [editDir stringByAppendingPathComponent:self.name];
    NSURL *pathURL = [NSURL fileURLWithPath:newpath isDirectory:NO];
    
    [url startAccessingSecurityScopedResource];
    BOOL ret = [Utils copyFile:url to:pathURL];
    [url stopAccessingSecurityScopedResource];
    if (ret) {
        [self setMpath:newpath];
    }
    return ret;
}

#pragma mark - Dictionary & Star

- (NSDictionary *)toDict
{
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:self.connection.address, @"conn_url",  self.connection.username, @"conn_username",
                          self.oid, @"id", self.repoId, @"repoid", self.path, @"path", [NSNumber numberWithLongLong:self.mtime ], @"mtime", [NSNumber numberWithLongLong:self.filesize], @"size", nil];
    Debug("dict=%@", dict);
    return dict;
}

- (BOOL)isStarred
{
    return [self.connection isStarred:self.repoId path:self.path];
}

#pragma mark - Upload (Update) Logic

- (void)update:(id<SeafFileUpdateDelegate>)dg
{
    if (!self.mpath)   return;
    self.udelegate = dg;
    if (!self.ufile) {
        self.ufile = [[SeafUploadFile alloc] initWithPath:self.mpath];
        self.ufile.delegate = self;
        self.ufile.model.overwrite = YES;
        self.ufile.completionBlock = self.uploadCompletionBlock;
        self.ufile.model.isEditedFile = YES;
        self.ufile.model.editedFileRepoId = self.repoId;
        self.ufile.model.editedFilePath = self.path;
        self.ufile.model.editedFileOid = self.oid;
        if (self.isFileEditedAgain) {// is edited before upload completed
            self.ufile.model.shouldShowUploadFailure = false;
            self.isFileEditedAgain = false;// reset flag
        }
        NSString *path = [self.path stringByDeletingLastPathComponent];
        SeafDir *udir = [[SeafDir alloc] initWithConnection:self.connection oid:nil repoId:self.repoId perm:@"rw" name:path.lastPathComponent path:path mtime:0];
        self.ufile.udir = udir;
        [udir addUploadFile:self.ufile];
    }
    Debug("Update file %@, to %@", self.ufile.lpath, self.ufile.udir.path);
    [SeafDataTaskManager.sharedObject addUploadTask:self.ufile priority:NSOperationQueuePriorityHigh];
}

#pragma mark - Cache Cleanup
- (void)cancelNotDisplayThumb {
    if (self.thumbTaskForQueue){
        [SeafDataTaskManager.sharedObject removeThumbTaskFromAccountQueue:self.thumbTaskForQueue];
        self.thumbTaskForQueue = nil;
    }
}

#pragma mark - SeafUploadDelegate

- (void)uploadProgress:(SeafFile *)file progress:(float)progress
{
    [self.udelegate updateProgress:self progress:progress];
}

- (void)uploadComplete:(BOOL)success file:(SeafUploadFile *)file oid:(NSString *)oid
{
    Debug("%@ file %@ upload success oid: %@, %@", self, self.name, oid, self.udelegate);

    if (self.uploadCompletionBlock != nil) {
        NSError *error = nil;
        if (!success) {
            error = [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorServerUnreachable userInfo:nil];
        }
        self.uploadCompletionBlock(file, oid, error);
    }
    
    id<SeafFileUpdateDelegate> dg = self.udelegate;
    if (!success) {
        return [dg updateComplete:self result:false];
    }
    [self.ufile cleanup];
    self.ufile = nil;
    self.udelegate = nil;
    self.state = SEAF_DENTRY_INIT;
    self.ooid = oid;
    self.oid = oid;
    self.filesize = file.filesize;
    self.mtime = file.mtime;
    [self setMpath:nil];
    [dg updateComplete:self result:true];
}

- (BOOL)isUploaded
{
    return !self.ufile || self.ufile.uploaded;
}

- (BOOL)isUploading
{
    return self.ufile.uploading;
}

#pragma mark - Download Callback Helpers

- (void)setFileDownloadedBlock:(nullable SeafDownloadCompletionBlock)block
{
    self.fileDidDownloadBlock = block;
}

- (void)setFileUploadedBlock:(nullable SeafUploadCompletionBlock)block
{
    self.uploadCompletionBlock = block;
}

- (void)downloadComplete:(BOOL)updated
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate download:self complete:updated];
        self.state = SEAF_DENTRY_SUCCESS;
        if (self.fileDidDownloadBlock) {
            self.fileDidDownloadBlock(self, nil);
        }
        [self removeFileTaskInStorage:self];

    });
}

- (void)removeFileTaskInStorage:(SeafFile *)file {
    NSString *key = [self downloadStorageKey:file.accountIdentifier];
    @synchronized(self) {
        NSMutableDictionary *taskStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:key]];
        [taskStorage removeObjectForKey:file.uniqueKey];
        [SeafStorage.sharedObject setObject:taskStorage forKey:key];
    }
}

- (NSString*)downloadStorageKey:(NSString*)accountIdentifier {
   return [NSString stringWithFormat:@"%@/%@",KEY_DOWNLOAD,accountIdentifier];
}

- (void)downloadFailed:(NSError *)error
{
    NSError *err = error ? error : [Utils defaultError];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate download:self failed:err];
        
        self.state = SEAF_DENTRY_FAILURE;
        
        if (self.fileDidDownloadBlock) {
            self.fileDidDownloadBlock(self, err);
        }
    });
}

- (void)downloadProgress:(float)progress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate download:self progress:progress];
        if (self.taskProgressBlock) {
            self.taskProgressBlock(self, progress);
        }
    });
}

- (void)cancelDownload
{
    // Cancel the download task for the current file
    if (self.connection && self.connection.accountIdentifier) {
        Debug(@"Canceling download for file %@", self.name);
        
        // Get the account queue through DataTaskManager and remove the download task
        SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection];
        [accountQueue removeFileDownloadTask:self];
        
        // Reset file status
        if (self.state == SEAF_DENTRY_LOADING) {
            self.state = SEAF_DENTRY_INIT;
            
            // Notify delegate that download has been canceled
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *error = [NSError errorWithDomain:@"SeafFile" code:-999 userInfo:@{NSLocalizedDescriptionKey: @"Download canceled"}];
                [self.delegate download:self failed:error];
                
                if (self.fileDidDownloadBlock) {
                    self.fileDidDownloadBlock(self, error);
                }
            });
        }
        
        // Remove file task from storage
        [self removeFileTaskInStorage:self];
    }
}

- (void)cancel
{
    [self cancelDownload];
}

#pragma mark - SeafFileDelegate

- (void)download:(id)file complete:(BOOL)updated {
    [self.delegate download:self complete:updated];
}

- (void)download:(id)file failed:(NSError *)error {
    [self.delegate download:self failed:error];
}

- (void)download:(id)file progress:(float)progress {
    [self.delegate download:self progress:progress];
}

- (void)uploadWithPath:(NSString *)path completion:(void(^)(BOOL success, NSError *error))completion {
    if (self.isUploading) {
        if (completion) completion(NO, [NSError errorWithDomain:@"SeafFile" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Already uploading"}]);
        return;
    }
    
    self.uploadCompletion = completion;
    SeafUploadFile *uploadFile = [[SeafUploadFile alloc] initWithPath:path];
    uploadFile.delegate = self;
    [[SeafDataTaskManager sharedObject] addUploadTask:uploadFile];
}

- (NSURL *)previewURL {
    return [self.previewHandler getPreviewURL];
}

- (NSURL *)exportURL {
    _exportURL = [self.previewHandler getExportItemURLWithSeafFile:self oldExportURL:_exportURL];
    return _exportURL;
}

- (BOOL)retryable {
    return self.model.retryable;
}

- (void)setRetryable:(BOOL)retryable {
    self.model.retryable = retryable;
}

- (NSInteger)retryCount {
    return self.model.retryCount;
}

- (void)setRetryCount:(NSInteger)retryCount {
    self.model.retryCount = retryCount;
}

- (NSString *)getWebViewURLString
{
    if (![self isWebOpenFile]) return nil;
    
    NSString *encodedPath = [self.path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    NSString *urlString = [NSString stringWithFormat:@"%@/lib/%@/file%@",
                          self.connection.address, 
                          self.repoId, 
                          encodedPath];
    return urlString;
}

- (BOOL)waitUpload
{
    if (self.ufile)
        return [self.ufile waitUpload];
    return true;
}

@end
