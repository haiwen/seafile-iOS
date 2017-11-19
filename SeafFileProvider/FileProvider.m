//
//  FileProvider.m
//  SeafFileProvider
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
    return ret;
}

- (nullable NSFileProviderItemIdentifier)persistentIdentifierForItemAtURL:(NSURL *)url
{
    NSRange range = [url.path rangeOfString:self.rootPath.lastPathComponent];
    if (range.location == NSNotFound) {
        Warning("Unknown url: %@", url);
        return nil;
    }
    NSString *suffix = [url.path substringFromIndex:(range.location+range.length)];
    if (!suffix || suffix.length == 0) return @"/";
    return suffix;
}

- (nullable NSFileProviderItem)itemForIdentifier:(NSFileProviderItemIdentifier)identifier error:(NSError * _Nullable *)error
{
    return [[SeafProviderItem alloc] initWithItemIdentifier:[self translateIdentifier:identifier]];
}

- (void)providePlaceholderAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))completionHandler
{
    NSFileProviderItemIdentifier identifier = [self persistentIdentifierForItemAtURL:url];
    if (!identifier) {
        return completionHandler([Utils defaultError]);
    }
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:identifier];
    if (!item.isFile) {
        return completionHandler([Utils defaultError]);
    }

    NSURL *placeholderURL = [NSFileProviderManager placeholderURLForURL:url];
    Debug("placeholderURL:%@ url:%@", placeholderURL, url);
    NSError *error = nil;
    SeafProviderItem *providerItem = [[SeafProviderItem alloc] initWithSeafItem:item];
    [NSFileProviderManager writePlaceholderAtURL:placeholderURL withMetadata:providerItem error:&error];
    completionHandler(error);
}

- (void)startProvidingItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *))completionHandler
{
    Debug("providing at url: %@", url);
    NSFileProviderItemIdentifier identifier = [self persistentIdentifierForItemAtURL:url];
    if (!identifier) {
        return completionHandler([Utils defaultError]);
    }
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:identifier];
    if (!item.isFile) {
        return completionHandler([Utils defaultError]);
    }

    SeafFile *file = (SeafFile *)item.toSeafObj;
    [file setFileDownloadedBlock:^(SeafFile * _Nonnull file, NSError * _Nullable error) {
        if (error) {
            Warning("Failed to download file %@: %@", identifier, error);
            return completionHandler(error);
        }
        if ([Utils fileExistsAtPath:url.path]) {
            [Utils removeFile:url.path];
        }
        [Utils checkMakeDir:url.path.stringByDeletingLastPathComponent];
        BOOL ret = [Utils linkFileAtURL:file.exportURL to:url];
        NSError *err = ret ? nil : [Utils defaultError];
        completionHandler(err);
    }];
    [file loadContent:true];
}

- (void)itemChangedAtURL:(NSURL *)url
{
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
    [sfile uploadFromFile:url];
    [sfile waitUpload];
}

- (void)stopProvidingItemAtURL:(NSURL *)url {
    // Called after the last claim to the file has been released. At this point, it is safe for the file provider to remove the content file.
    // Care should be taken that the corresponding placeholder file stays behind after the content file has been deleted.

    [self.fileCoordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForDeleting error:nil byAccessor:^(NSURL *newURL) {
        Debug("Remove exported file %@", newURL);
        [[NSFileManager defaultManager] removeItemAtURL:newURL error:nil];
        NSError *error = nil;
        NSString *parentDir = newURL.path.stringByDeletingLastPathComponent;
        NSArray *folderContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:parentDir error:&error];
        if (!error && folderContents.count == 0) {
             [[NSFileManager defaultManager] removeItemAtPath:parentDir error:nil];
        }
    }];
}

# pragma mark - NSFileProviderEnumerator
- (nullable id<NSFileProviderEnumerator>)enumeratorForContainerItemIdentifier:(NSFileProviderItemIdentifier)containerItemIdentifier error:(NSError **)error
{
    Debug("enumerator for %@", containerItemIdentifier);
    return [[SeafEnumerator alloc] initWithItemIdentifier:[self translateIdentifier:[self translateIdentifier:containerItemIdentifier]]];
   }

# pragma mark - NSFileProviderActions
- (void)importDocumentAtURL:(NSURL *)fileURL
     toParentItemIdentifier:(NSFileProviderItemIdentifier)parentItemIdentifier
          completionHandler:(void (^)(NSFileProviderItem _Nullable importedDocumentItem, NSError * _Nullable error))completionHandler
{
    NSFileProviderItemIdentifier itemIdentifier = [parentItemIdentifier stringByAppendingPathComponent:fileURL.path.lastPathComponent];
    Debug("file path: %@, parentItemIdentifier:%@, itemIdentifier:%@", fileURL.path, parentItemIdentifier, itemIdentifier);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:itemIdentifier];
    SeafFile *sfile = (SeafFile *)[item toSeafObj];
    [sfile setFileUploadedBlock:^(SeafUploadFile *file, NSString *oid, NSError *error) {
        SeafProviderItem *providerItem = [[SeafProviderItem alloc] initWithSeafItem:item];
        completionHandler(providerItem, error);
    }];
    [sfile uploadFromFile:fileURL];
}

- (void)createDirectoryWithName:(NSString *)directoryName
         inParentItemIdentifier:(NSFileProviderItemIdentifier)parentItemIdentifier
              completionHandler:(void (^)(NSFileProviderItem _Nullable createdDirectoryItem, NSError * _Nullable error))completionHandler
{
    Debug("parentItemIdentifier: %@, directoryName:%@", parentItemIdentifier, directoryName);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:parentItemIdentifier];
    SeafDir *parentDir = (SeafDir *)[item toSeafObj];
    [parentDir mkdir:directoryName success:^(SeafDir *dir) {
        NSString *createdDirectoryPath = [dir.path stringByAppendingPathComponent:directoryName];
        SeafItem *createdItem = [[SeafItem alloc] initWithServer:dir->connection.address username:dir->connection.username repo:dir.repoId path:createdDirectoryPath filename:nil];
        SeafProviderItem *providerItem = [[SeafProviderItem alloc] initWithSeafItem:createdItem];
        completionHandler(providerItem, nil);
    } failure:^(SeafDir *dir, NSError *error) {
        completionHandler(nil, error ? error : [Utils defaultError]);
    }];
}

- (void)renameItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
                          toName:(NSString *)itemName
               completionHandler:(void (^)(NSFileProviderItem _Nullable renamedItem, NSError * _Nullable error))completionHandler;
{
    Debug("itemIdentifier: %@, toName:%@", itemIdentifier, itemName);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:itemIdentifier];
    SeafDir *dir = (SeafDir *)[item.parentItem toSeafObj];

    [dir renameEntry:item.name newName:itemName success:^(SeafDir *dir) {
        NSString *newpath = [dir.path stringByAppendingPathComponent:itemName];
        NSString *filename = item.isFile ? itemName : nil;
        SeafItem *newItem = [[SeafItem alloc] initWithServer:dir->connection.address username:dir->connection.username repo:dir.repoId path:newpath filename:filename];
        SeafProviderItem *renamedItem = [[SeafProviderItem alloc] initWithSeafItem:newItem];
        completionHandler(renamedItem, nil);
    } failure:^(SeafDir *dir, NSError *error) {
        completionHandler(nil, error ? error : [Utils defaultError]);
    }];
}
- (void)reparentItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
        toParentItemWithIdentifier:(NSFileProviderItemIdentifier)parentItemIdentifier
                           newName:(nullable NSString *)newName
                 completionHandler:(void (^)(NSFileProviderItem _Nullable reparentedItem, NSError * _Nullable error))completionHandler
{
    // move file
    Debug("itemIdentifier: %@, parentItemIdentifier:%@", itemIdentifier, parentItemIdentifier);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:itemIdentifier];
    SeafItem *dstItem = [[SeafItem alloc] initWithItemIdentity:parentItemIdentifier];
    SeafDir *srcDir = (SeafDir *)[item.parentItem toSeafObj];
    SeafDir *dstDir = (SeafDir *)dstItem.toSeafObj;

    [srcDir moveEntries:[NSArray arrayWithObject:item.name] dstDir:dstDir success:^(SeafDir *dir) {
        NSString *newpath = [dstDir.path stringByAppendingPathComponent:item.name];
        NSString *filename = item.isFile ? item.filename : nil;
        if (newName && ![newName isEqualToString:item.name]) {
            [dstDir renameEntry:item.name newName:newName success:^(SeafDir *dir) {
                NSString *renamedpath = [dstDir.path stringByAppendingPathComponent:newName];
                SeafItem *renamedItem = [[SeafItem alloc] initWithServer:dstDir->connection.address username:dstDir->connection.username repo:dstDir.repoId path:renamedpath filename:newName];
                completionHandler([[SeafProviderItem alloc] initWithSeafItem:renamedItem], nil);
            } failure:^(SeafDir *dir, NSError *error) {
                completionHandler(nil, error ? error : [Utils defaultError]);
            }];
        } else {
            SeafItem *newItem = [[SeafItem alloc] initWithServer:dstDir->connection.address username:dstDir->connection.username repo:dstDir.repoId path:newpath filename:filename];
            SeafProviderItem *reparentedItem = [[SeafProviderItem alloc] initWithSeafItem:newItem];
            completionHandler(reparentedItem, nil);
        }
    } failure:^(SeafDir *dir, NSError *error) {
        completionHandler(nil, error ? error : [Utils defaultError]);
    }];
}

- (void)deleteItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
               completionHandler:(void (^)(NSError * _Nullable error))completionHandler
{
    Debug("itemIdentifier: %@", itemIdentifier);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:itemIdentifier];
    SeafDir *dir = (SeafDir *)[item.parentItem toSeafObj];
    [dir delEntries:[NSArray arrayWithObject:item.name] success:^(SeafDir *dir) {
        completionHandler(nil);
    } failure:^(SeafDir *dir, NSError *error) {
        completionHandler(error ? error : [Utils defaultError]);
    }];
}

/*
 - (void)trashItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
 completionHandler:(void (^)(NSFileProviderItem _Nullable trashedItem, NSError * _Nullable error))completionHandler
 {

 }

 - (void)untrashItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
 toParentItemIdentifier:(nullable NSFileProviderItemIdentifier)parentItemIdentifier
 completionHandler:(void (^)(NSFileProviderItem _Nullable untrashedItem, NSError * _Nullable error))completionHandler
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
 */
@end
