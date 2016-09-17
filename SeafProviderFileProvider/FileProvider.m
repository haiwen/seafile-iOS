//
//  FileProvider.m
//  SeafProviderFileProvider
//
//  Created by Wang Wei on 11/15/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FileProvider.h"
#import "SeafGlobal.h"
#import "SeafFile.h"
#import "SeafDir.h"
#import "ExtentedString.h"
#import "Debug.h"

@interface FileProvider ()
@end

@implementation FileProvider

- (NSFileCoordinator *)fileCoordinator {
    NSFileCoordinator *fileCoordinator = [[NSFileCoordinator alloc] init];
    [fileCoordinator setPurposeIdentifier:[self providerIdentifier]];
    return fileCoordinator;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self.fileCoordinator coordinateWritingItemAtURL:[self documentStorageURL] options:0 error:nil byAccessor:^(NSURL *newURL) {
            // ensure the documentStorageURL actually exists
            NSError *error = nil;
            [[NSFileManager defaultManager] createDirectoryAtURL:newURL withIntermediateDirectories:YES attributes:nil error:&error];
        }];
        if (SeafGlobal.sharedObject.conns.count == 0)
            [SeafGlobal.sharedObject loadAccounts];
    }
    return self;
}

- (NSString *)providerIdentifier
{
    return APP_ID;
}

- (void)providePlaceholderAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))completionHandler {

    NSError* error = nil;
    BOOL isDirectory = false;
    Debug("url=%@, filesize: %d", url, [Utils fileExistsAtPath:url.path]);
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDirectory]
        || isDirectory) {
        error = [NSError errorWithDomain:NSPOSIXErrorDomain code:-1 userInfo:nil];
    }
    if (completionHandler) {
        completionHandler(error);
    }
}

- (void)startProvidingItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *))completionHandler {
    NSError* error = nil;
    BOOL isDirectory = false;
    Debug("url=%@, filesize: %d", url, [Utils fileExistsAtPath:url.path]);

    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDirectory]
        || isDirectory) {
        error = [NSError errorWithDomain:NSPOSIXErrorDomain code:-1 userInfo:nil];
    }
    if (completionHandler) {
        completionHandler(error);
    }
}

- (void)itemChangedAtURL:(NSURL *)url {

    // Called at some point after the file has changed; the provider may then trigger an upload
    NSDictionary *dict = [SeafGlobal.sharedObject getExportFile:url];
    Debug("Item changed at URL %@, dict:%@, filesize: %d", url, dict, [Utils fileExistsAtPath:url.path]);
    if (!dict) return;

    NSString *connUrl = [dict objectForKey:@"conn_url"];
    NSString *username = [dict objectForKey:@"conn_username"];
    NSString *path = [dict objectForKey:@"path"];
    NSString *repoId = [dict objectForKey:@"repoid"];
    if (!connUrl || !username || !path || !repoId)
        return;
    SeafConnection *conn = [SeafGlobal.sharedObject getConnection:connUrl username:username];
    if (!conn) return;
    
    NSString *oid = [dict objectForKey:@"id"];
    if (oid) {
        SeafFile *file = [[SeafFile alloc] initWithConnection:conn oid:oid repoId:repoId name:path.lastPathComponent path:path mtime:[[dict objectForKey:@"mtime"] integerValue:0] size:[[dict objectForKey:@"size"] integerValue:0]];
        [file itemChangedAtURL:url];
        [file waitUpload];
    } else {
        BOOL overwrite = [[dict objectForKey:@"overwrite"] booleanValue:false];
        SeafUploadFile *ufile = [conn getUploadfile:url.path create:true];
        ufile.overwrite = overwrite;
        SeafDir *dir = [[SeafDir alloc] initWithConnection:conn oid:nil repoId:repoId perm:@"rw" name:path.lastPathComponent path:path];
        [dir addUploadFile:ufile flush:true];
        Debug("Upload %@(%lld) to %@ %@ overwrite:%d ", ufile.lpath, [Utils fileSizeAtPath1:ufile.lpath], dir.repoId, dir.path, overwrite);
        [ufile doUpload];
        [ufile waitUpload];
    }
}

- (void)stopProvidingItemAtURL:(NSURL *)url {
    // Called after the last claim to the file has been released. At this point, it is safe for the file provider to remove the content file.
    // Care should be taken that the corresponding placeholder file stays behind after the content file has been deleted.
    
    [self.fileCoordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForDeleting error:nil byAccessor:^(NSURL *newURL) {
        [[NSFileManager defaultManager] removeItemAtURL:newURL error:nil];
        Debug("Remove exported file %@", url);
        [SeafGlobal.sharedObject removeExportFile:url];
    }];
    [self providePlaceholderAtURL:url completionHandler:^(NSError *error){
        Warning("url=%@, error=%@", url, error);
    }];
}

@end
