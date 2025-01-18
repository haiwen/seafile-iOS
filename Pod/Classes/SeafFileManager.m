//
//  SeafFileManager.m
//  Seafile
//
//  Created by henry on 2025/1/23.
//

#import "SeafFileManager.h"
#import "SeafDataTaskManager.h"
#import "SeafStorage.h"
#import "Utils.h"
#import "Debug.h"
#import "SeafRealmManager.h"

@interface SeafFileManager()

@property (nonatomic, strong) NSMutableDictionary *downloadTasks;
@property (nonatomic, strong) NSMutableDictionary *uploadTasks;

@end

@implementation SeafFileManager

#pragma mark - Initialization

- (instancetype)initWithConnection:(SeafConnection *)connection {
    self = [super init];
    if (self) {
        _connection = connection;
        _cacheManager = [SeafCacheManager sharedManager];
        _stateManager = [[SeafFileStateManager alloc] initWithConnection:connection];
        _downloadTasks = [NSMutableDictionary new];
        _uploadTasks = [NSMutableDictionary new];
    }
    return self;
}

#pragma mark - Download Methods

- (void)downloadFile:(SeafFileModel *)file 
           progress:(void(^)(float progress))progressBlock
         completion:(void(^)(BOOL success, NSError *error))completion {
    if (!file || !file.oid) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"SeafFileManager" 
                                            code:-1 
                                        userInfo:@{NSLocalizedDescriptionKey: @"Invalid file or file ID"}]);
        }
        return;
    }
    
    // Check if file is already downloading
    if ([file isKindOfClass:[SeafFile class]] && ((SeafFile *)file).isDownloading) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"SeafFileManager" 
                                            code:-1 
                                        userInfo:@{NSLocalizedDescriptionKey: @"File is already downloading"}]);
        }
        return;
    }
    
    // Add download task through SeafDataTaskManager
    [[SeafDataTaskManager sharedObject] addFileDownloadTask:(SeafFile *)file];
}

- (void)cancelDownload:(SeafFileModel *)file {
    if (!file || ![file isKindOfClass:[SeafFile class]]) {
        return;
    }
    
    SeafFile *seafFile = (SeafFile *)file;
    // Cancel specific download task through SeafDataTaskManager
    SeafAccountTaskQueue *queue = [[SeafDataTaskManager sharedObject] accountQueueForConnection:seafFile.connection];
    [queue removeFileDownloadTask:seafFile];
}

#pragma mark - Upload Methods

- (void)uploadFile:(SeafUploadFile *)file {
    if (!file || !file.lpath) {
        return;
    }
    
    NSString *key = file.lpath;
    if (self.uploadTasks[key]) {
        return;
    }
    
    self.uploadTasks[key] = file;
    [[SeafDataTaskManager sharedObject] addUploadTask:file];
}

- (void)cancelUpload:(SeafUploadFile *)file {
    NSString *key = file.lpath;
    [self.uploadTasks removeObjectForKey:key];
    [[SeafDataTaskManager sharedObject] removeUploadTask:file forAccount:self.connection];
}

#pragma mark - Cache Methods

- (BOOL)hasLocalCache:(SeafFileModel *)file {
    if (!file || !file.oid) {
        return NO;
    }
    
    // Get cache path from Realm
    NSString *cachePath = [[SeafRealmManager shared] getLocalCacheWithOid:file.oid
                                                                          mtime:file.mtime
                                                                         uniKey:file.uniqueKey];
    
    // If found in Realm and file exists, return YES
    if (cachePath && [[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
        return YES;
    }
    
    // If not found in Realm, check legacy storage
    NSString *legacyPath = [SeafStorage.sharedObject documentPath:file.oid];
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:legacyPath];
    
    // If found in legacy storage, migrate to Realm
    if (exists && file.uniqueKey) {
        SeafFileStatus *status = [SeafFileStatus new];
        status.uniquePath = file.uniqueKey;
        status.serverOID = file.oid;
        status.localFilePath = legacyPath;
        status.serverMTime = file.mtime;
        [[SeafRealmManager shared] updateFileStatus:status];
    }
    
    return exists;
}

- (void)clearCache:(SeafFileModel *)file {
    if (!file || !file.oid) {
        return;
    }
    
    // Get cache path from Realm
    NSString *cachePath = [[SeafRealmManager shared] getLocalCacheWithOid:file.oid
                                                                          mtime:file.mtime
                                                                         uniKey:file.uniqueKey];
    
    // Remove file from cache location if exists
    if (cachePath && [[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
        NSError *error;
        if (![[NSFileManager defaultManager] removeItemAtPath:cachePath error:&error]) {
            Debug(@"Failed to remove cached file at %@: %@", cachePath, error);
        }
    }
    
    // Check and remove from legacy location
    NSString *legacyPath = [SeafStorage.sharedObject documentPath:file.oid];
    if ([[NSFileManager defaultManager] fileExistsAtPath:legacyPath]) {
        NSError *error;
        if (![[NSFileManager defaultManager] removeItemAtPath:legacyPath error:&error]) {
            Debug(@"Failed to remove legacy file at %@: %@", legacyPath, error);
        }
    }
    
    // Clear blocks directory
    NSString *blocksDir = [SeafStorage.sharedObject.blocksDir stringByAppendingPathComponent:file.oid];
    if ([[NSFileManager defaultManager] fileExistsAtPath:blocksDir]) {
        NSError *error;
        if (![[NSFileManager defaultManager] removeItemAtPath:blocksDir error:&error]) {
            Debug(@"Failed to remove blocks directory at %@: %@", blocksDir, error);
        }
    }
    
    // Update file status in Realm
    if (file.uniqueKey) {
        SeafFileStatus *status = [SeafFileStatus new];
        status.uniquePath = file.uniqueKey;
        status.serverOID = file.oid;
        status.localFilePath = nil;  // Clear local path
        status.serverMTime = file.mtime;
        [[SeafRealmManager shared] updateFileStatus:status];
    }
    
    // Clear download status if it's a SeafFile
    if ([file isKindOfClass:[SeafFile class]]) {
        SeafFile *seafFile = (SeafFile *)file;
        seafFile.downloaded = NO;
        seafFile.isDownloading = NO;
//        seafFile.downloadProgress = 0;
    }
}

- (NSArray *)getDownloadingFiles:(SeafConnection *)connection {
    if (!connection) {
        return @[];
    }
    SeafAccountTaskQueue *queue = [[SeafDataTaskManager sharedObject] accountQueueForConnection:connection];
    return [queue getOngoingDownloadTasks];
}

- (NSArray *)getDownloadCompletedFiles:(SeafConnection *)connection {
    if (!connection) {
        return @[];
    }
    SeafAccountTaskQueue *queue = [[SeafDataTaskManager sharedObject] accountQueueForConnection:connection];
    return [queue getCompletedSuccessfulDownloadTasks];
}

@end
