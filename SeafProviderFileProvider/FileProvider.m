//
//  FileProvider.m
//  SeafProviderFileProvider
//
//  Created by Wang Wei on 11/15/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import "FileProvider.h"
#import "SeafProviderItem.h"
#import "SeafEnumerator.h"
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
        Debug(".....");
        [self.fileCoordinator coordinateWritingItemAtURL:self.rootURL options:0 error:nil byAccessor:^(NSURL *newURL) {
            // ensure the documentStorageURL actually exists
            NSError *error = nil;
            [[NSFileManager defaultManager] createDirectoryAtURL:newURL withIntermediateDirectories:YES attributes:nil error:&error];
        }];
        if (SeafGlobal.sharedObject.conns.count == 0) {
            [SeafGlobal.sharedObject loadAccounts];
        }
    }
    return self;
}

- (NSString *)rootPath
{
    return self.rootURL.path;
}

- (NSURL *)rootURL
{
    if (@available(iOS 11.0, *)) {
        return [[NSFileProviderManager defaultManager] documentStorageURL];
    } else {
        return self.documentStorageURL;
    }
}

- (NSFileProviderItemIdentifier)translateIdentifier:(NSFileProviderItemIdentifier)containerItemIdentifier
{
    if (@available(iOS 11.0, *)) {
        if ([containerItemIdentifier isEqualToString:NSFileProviderRootContainerItemIdentifier]) {
            return @"/";
        }
    }
    return containerItemIdentifier;
}

- (nullable NSURL *)URLForItemWithPersistentIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
{
    NSFileProviderItemIdentifier identifier = [self translateIdentifier:itemIdentifier];
    NSURL *ret;
    NSArray *pathComponents = [identifier pathComponents];
    if (pathComponents.count == 1) {
        ret = self.rootURL;
    } else if (pathComponents.count == 2) {
        ret = [self.rootURL URLByAppendingPathComponent:[pathComponents objectAtIndex:1] isDirectory:true];
    } else {
        NSURL *url = [self.rootURL URLByAppendingPathComponent:[pathComponents objectAtIndex:1] isDirectory:true];
        ret = [url URLByAppendingPathComponent:[pathComponents objectAtIndex:2] isDirectory:false];
    }
    //Debug("....identifier=%@, url=%@", identifier, ret.path);
    return ret;
}

- (nullable NSFileProviderItemIdentifier)persistentIdentifierForItemAtURL:(NSURL *)url
{
    //Debug("....url=%@, prefix=%@, hasprefix:%d", url, self.rootPath, [url.path hasPrefix:self.rootPath]);
    if ([url.path hasPrefix:self.rootPath]) {
        NSString *suffix = [url.path substringFromIndex:self.rootPath.length];
        if (!suffix || suffix.length == 0) return @"/";
        return suffix;
    } else {
        Warning("Unknown url: %@", url);
        return nil;
    }
}

- (nullable NSFileProviderItem)itemForIdentifier:(NSFileProviderItemIdentifier)identifier error:(NSError * _Nullable *)error
{
    Debug("....identifier=%@", identifier);
    return [[SeafProviderItem alloc] initWithItemIdentifier:[self translateIdentifier:identifier]];
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

    if ([url.path hasSuffix:@"/"] || [url.path isEqualToString:self.rootPath]) return;

    // Called at some point after the file has changed; the provider may then trigger an upload
    NSFileProviderItemIdentifier identifier = [self persistentIdentifierForItemAtURL:url];
    Debug("File changed: %@ %@", url, identifier);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:identifier];
    if (!item.isFile) {
        Debug("%@ is not a file.", identifier);
        return;
    }

    SeafFile *sfile = (SeafFile *)item.toSeafObj;
    [sfile itemChangedAtURL:url];
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

# pragma mark - NSFileProviderEnumerator
- (nullable id<NSFileProviderEnumerator>)enumeratorForContainerItemIdentifier:(NSFileProviderItemIdentifier)containerItemIdentifier error:(NSError **)error
{
    Debug("...containerItemIdentifier:%@", containerItemIdentifier);
    return [[SeafEnumerator alloc] initWithItemIdentifier:[self translateIdentifier:[self translateIdentifier:containerItemIdentifier]]];
   }

# pragma mark - NSFileProviderActions
- (void)importDocumentAtURL:(NSURL *)fileURL
     toParentItemIdentifier:(NSFileProviderItemIdentifier)parentItemIdentifier
          completionHandler:(void (^)(NSFileProviderItem _Nullable importedDocumentItem, NSError * _Nullable error))completionHandler
{
}

- (void)createDirectoryWithName:(NSString *)directoryName
         inParentItemIdentifier:(NSFileProviderItemIdentifier)parentItemIdentifier
              completionHandler:(void (^)(NSFileProviderItem _Nullable createdDirectoryItem, NSError * _Nullable error))completionHandler
{

}

- (void)renameItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
                          toName:(NSString *)itemName
               completionHandler:(void (^)(NSFileProviderItem _Nullable renamedItem, NSError * _Nullable error))completionHandler;
{

}
- (void)reparentItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
        toParentItemWithIdentifier:(NSFileProviderItemIdentifier)parentItemIdentifier
                           newName:(nullable NSString *)newName
                 completionHandler:(void (^)(NSFileProviderItem _Nullable reparentedItem, NSError * _Nullable error))completionHandler
{
}

- (void)trashItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
              completionHandler:(void (^)(NSFileProviderItem _Nullable trashedItem, NSError * _Nullable error))completionHandler
{

}
- (void)untrashItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
           toParentItemIdentifier:(nullable NSFileProviderItemIdentifier)parentItemIdentifier
                completionHandler:(void (^)(NSFileProviderItem _Nullable untrashedItem, NSError * _Nullable error))completionHandler
{

}
- (void)deleteItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
               completionHandler:(void (^)(NSError * _Nullable error))completionHandler
{

}
- (void)setLastUsedDate:(nullable NSDate *)lastUsedDate
      forItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
      completionHandler:(void (^)(NSFileProviderItem _Nullable recentlyUsedItem, NSError * _Nullable error))completionHandler
{

}

- (void)setTagData:(nullable NSData *)tagData
 forItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
 completionHandler:(void(^)(NSFileProviderItem _Nullable taggedItem, NSError * _Nullable error))completionHandler
{

}
- (void)setFavoriteRank:(nullable NSNumber *)favoriteRank
      forItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
      completionHandler:(void (^)(NSFileProviderItem _Nullable favoriteItem, NSError * _Nullable error))completionHandler
{

}

# pragma mark - NSFileProviderThumbnailing
- (NSProgress *)fetchThumbnailsForItemIdentifiers:(NSArray<NSFileProviderItemIdentifier> *)itemIdentifiers
                                    requestedSize:(CGSize)size
                    perThumbnailCompletionHandler:(void (^)(NSFileProviderItemIdentifier identifier, NSData * _Nullable imageData, NSError * _Nullable error))perThumbnailCompletionHandler
                                completionHandler:(void (^)(NSError * _Nullable error))completionHandler
{
    return nil;
}

# pragma mark - NSFileProviderService
- (nullable NSArray <id <NSFileProviderServiceSource>> *)supportedServiceSourcesForItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier error:(NSError **)error
{
    return nil;
}
@end
