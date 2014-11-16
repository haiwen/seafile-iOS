//
//  FileProvider.m
//  SeafProviderFileProvider
//
//  Created by Wang Wei on 11/15/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import "FileProvider.h"
#import <UIKit/UIKit.h>
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
    }
    return self;
}

- (NSString *)providerIdentifier
{
    return @"com.seafile.seafilePro";
}

- (void)providePlaceholderAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))completionHandler {

    // Should call + writePlaceholderAtURL:withMetadata:error: with the placeholder URL, then call the completion handler with the error if applicable.
    NSString* fileName = [url lastPathComponent];
    
    NSURL *placeholderURL = [NSFileProviderExtension placeholderURLForURL:[self.documentStorageURL URLByAppendingPathComponent:fileName]];
    
    NSUInteger fileSize = 0;
    // TODO: get file size for file at <url> from model
    
    [self.fileCoordinator coordinateWritingItemAtURL:placeholderURL options:0 error:NULL byAccessor:^(NSURL *newURL) {
        NSDictionary* metadata = @{ NSURLFileSizeKey : @(fileSize)};
        [NSFileProviderExtension writePlaceholderAtURL:placeholderURL withMetadata:metadata error:NULL];
    }];
    if (completionHandler) {
        completionHandler(nil);
    }
}

- (void)startProvidingItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *))completionHandler {
    NSError* error = nil;
    BOOL isDirectory = false;
    Debug("url=%@", url);
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDirectory]
        || isDirectory) {
        error = [NSError errorWithDomain:NSPOSIXErrorDomain code:-1 userInfo:nil];
    }
    completionHandler(error);
}

- (void)itemChangedAtURL:(NSURL *)url {

    // Called at some point after the file has changed; the provider may then trigger an upload
    
    // TODO: mark file at <url> as needing an update in the model; kick off update process
    NSLog(@"Item changed at URL %@", url);
}

- (void)stopProvidingItemAtURL:(NSURL *)url {
    // Called after the last claim to the file has been released. At this point, it is safe for the file provider to remove the content file.
    // Care should be taken that the corresponding placeholder file stays behind after the content file has been deleted.
    
    [self.fileCoordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForDeleting error:NULL byAccessor:^(NSURL *newURL) {
        [[NSFileManager defaultManager] removeItemAtURL:newURL error:NULL];
    }];
    [self providePlaceholderAtURL:url completionHandler:NULL];
}

@end
