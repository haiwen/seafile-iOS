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
#import "Utils.h"
#import "Debug.h"

@interface FileProvider ()
@end

@implementation FileProvider

- (NSFileCoordinator *)fileCoordinator {
    NSFileCoordinator *fileCoordinator = [[NSFileCoordinator alloc] init];
    [fileCoordinator setPurposeIdentifier:APP_ID];
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
    NSString *filename = url.path.lastPathComponent;
    NSString *encodedDir = url.path.stringByDeletingLastPathComponent.lastPathComponent;
    NSArray *arr = [Utils decodeDir:encodedDir];
    if (arr.count != 5) {
        return Warning("Invalid dir: %@", encodedDir);
    }
    NSString *server = [arr objectAtIndex:0];
    NSString *username = [arr objectAtIndex:1];
    NSString *repoId = [arr objectAtIndex:2];
    NSString *path = [arr objectAtIndex:3];
    int overwrite = [[arr objectAtIndex:4] intValue];

    Debug("Item changed at URL %@, %@ %@ %@ %@ %d, filesize: %d", url, server, username, repoId, path, overwrite, [Utils fileExistsAtPath:url.path]);

    if (!server || !username || !path || !repoId) return;
    SeafConnection *conn = [SeafGlobal.sharedObject getConnection:server username:username];
    if (!conn) return;

    SeafUploadFile *ufile = [conn getUploadfile:url.path create:true];
    ufile.overwrite = overwrite;
    SeafDir *dir = [[SeafDir alloc] initWithConnection:conn oid:nil repoId:repoId perm:@"rw" name:path.lastPathComponent path:path];
    [dir addUploadFile:ufile flush:true];
    Debug("Upload %@(%lld) to %@ %@ overwrite:%d ", ufile.lpath, [Utils fileSizeAtPath1:ufile.lpath], dir.repoId, dir.path, overwrite);
    [ufile run:nil];
    [ufile waitUpload];
}

- (void)stopProvidingItemAtURL:(NSURL *)url {
    // Called after the last claim to the file has been released. At this point, it is safe for the file provider to remove the content file.
    // Care should be taken that the corresponding placeholder file stays behind after the content file has been deleted.

    [self.fileCoordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForDeleting error:nil byAccessor:^(NSURL *newURL) {
        Debug("Remove exported file %@", newURL);
        [[NSFileManager defaultManager] removeItemAtURL:newURL error:nil];
        [[NSFileManager defaultManager] removeItemAtURL:[newURL URLByDeletingLastPathComponent] error:nil];
    }];
}

@end
