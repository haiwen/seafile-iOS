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
#import "NSError+SeafFileProvierError.h"
#import "SeafStorage.h"

@interface FileProvider ()
@end

@implementation FileProvider

- (NSFileCoordinator *)fileCoordinator {
    NSFileCoordinator *fileCoordinator = [[NSFileCoordinator alloc] init];
    if (@available(iOS 11.0, *)) {
        [fileCoordinator setPurposeIdentifier:APP_ID];
    }
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
        if ([containerItemIdentifier isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier]) {
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
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:[self translateIdentifier:identifier]];
    return [[SeafProviderItem alloc] initWithSeafItem:item itemIdentifier:identifier];
}

- (NSURL *)getPlaceholderURLForURL:(NSURL *)url
{
    if (@available(iOS 11.0, *)) {
        return [NSFileProviderManager placeholderURLForURL:url];
    } else {
        return [NSFileProviderExtension placeholderURLForURL:url];
    }
}

- (void)providePlaceholderAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))completionHandler
{
    NSFileProviderItemIdentifier identifier = [self persistentIdentifierForItemAtURL:url];
    if (!identifier) {
        return completionHandler([NSError fileProvierErrorNoSuchItem]);
    }
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:identifier];
    if (!item.isFile) {
        return completionHandler([NSError fileProvierErrorNoSuchItem]);
    }

    [Utils checkMakeDir:url.path.stringByDeletingLastPathComponent];
    NSURL *placeholderURL = [self getPlaceholderURLForURL:url];
    Debug("placeholderURL:%@ url:%@", placeholderURL, url);
    NSError *error = nil;
    SeafProviderItem *providerItem = [[SeafProviderItem alloc] initWithSeafItem:item];
    if (@available(iOS 11.0, *)) {
        [NSFileProviderManager writePlaceholderAtURL:placeholderURL withMetadata:providerItem error:&error];
    } else {
        NSDictionary *metadata = [[NSDictionary alloc] initWithObjectsAndKeys:
                                  providerItem.filename, @"filename", providerItem.typeIdentifier, @"typeIdentifier",
                                  providerItem.documentSize, @"documentSize", nil];
        [NSFileProviderExtension writePlaceholderAtURL:placeholderURL withMetadata:metadata error:&error];
    }
    if (error) Warning("Failed to write placeholder: %@", error);
    completionHandler(error);
}

- (void)startProvidingItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *))completionHandler
{
    Debug("providing at url: %@", url);
    NSFileProviderItemIdentifier identifier = [self persistentIdentifierForItemAtURL:url];
    if (!identifier) {
        return completionHandler([NSError fileProvierErrorNoSuchItem]);
    }
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:identifier];
    if (!item.isFile) {
        return completionHandler([NSError fileProvierErrorNoSuchItem]);
    }

    SeafFile *file = (SeafFile *)item.toSeafObj;
    [file setFileDownloadedBlock:^(SeafFile * _Nonnull file, NSError * _Nullable error) {
        if (error) {
            Warning("Failed to download file %@: %@", identifier, error);
            return completionHandler([NSError fileProvierErrorServerUnreachable]);
        }
        if ([Utils fileExistsAtPath:url.path]) {
            [Utils removeFile:url.path];
        }
        [Utils checkMakeDir:url.path.stringByDeletingLastPathComponent];
        NSError *err = nil;
        BOOL ret = [Utils linkFileAtURL:file.exportURL to:url error:&err];
        if (!ret && !err) err = [NSError fileProvierErrorNoSuchItem];
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

- (void)stopProvidingItemAtURL:(NSURL *)url
{
    // Called after the last claim to the file has been released. At this point, it is safe for the file provider to remove the content file.
    // Care should be taken that the corresponding placeholder file stays behind after the content file has been deleted.

    [self.fileCoordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForDeleting error:nil byAccessor:^(NSURL *newURL) {
        [self removeProvidingItemAndParentIfEmpty:url];
    }];
}

- (void)removeProvidingItemAndParentIfEmpty:(NSURL *)url
{
    Debug("Remove providingItem: %@", url);
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];

    NSError *error = nil;
    NSString *parentDir = url.path.stringByDeletingLastPathComponent;
    NSArray *folderContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:parentDir error:&error];
    if (!error && folderContents.count == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:parentDir error:nil];
    }
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
    NSURL *localURL = [self URLForItemWithPersistentIdentifier:itemIdentifier];

    [sfile setFileUploadedBlock:^(SeafUploadFile *file, NSString *oid, NSError *error) {
        if (error) {
            completionHandler(nil, [NSError fileProvierErrorServerUnreachable]);
        } else {
            [self removeProvidingItemAndParentIfEmpty:localURL];
        }
    }];
    
    [fileURL startAccessingSecurityScopedResource];
    [Utils checkMakeDir:localURL.path.stringByDeletingLastPathComponent];
    NSError *err = nil;
    BOOL ret = [[NSFileManager defaultManager] moveItemAtURL:fileURL toURL:localURL error:&err];
    [fileURL stopAccessingSecurityScopedResource];

    if (!ret) return completionHandler(nil, [NSError fileProvierErrorNoSuchItem]);
    ret = [sfile uploadFromFile:localURL];
    if (!ret) return completionHandler(nil, [NSError fileProvierErrorNoSuchItem]);

    SeafProviderItem *providerItem = [[SeafProviderItem alloc] initWithSeafItem:item];
    completionHandler(providerItem, nil);
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
        [self signalEnumerator:@[parentItemIdentifier, NSFileProviderWorkingSetContainerItemIdentifier]];
        completionHandler(providerItem, nil);
    } failure:^(SeafDir *dir, NSError *error) {
        completionHandler(nil, [NSError fileProvierErrorServerUnreachable]);
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
        [self signalEnumerator:@[renamedItem.parentItemIdentifier, NSFileProviderWorkingSetContainerItemIdentifier]];
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
                Debug("reparent %@ successfully", itemIdentifier);
                [self signalEnumerator:@[parentItemIdentifier, NSFileProviderWorkingSetContainerItemIdentifier]];
                completionHandler([[SeafProviderItem alloc] initWithSeafItem:renamedItem], nil);
            } failure:^(SeafDir *dir, NSError *error) {
                Warning("Failed to reparent %@: %@", itemIdentifier, error);
                completionHandler(nil, [NSError fileProvierErrorServerUnreachable]);
            }];
        } else {
            SeafItem *newItem = [[SeafItem alloc] initWithServer:dstDir->connection.address username:dstDir->connection.username repo:dstDir.repoId path:newpath filename:filename];
            SeafProviderItem *reparentedItem = [[SeafProviderItem alloc] initWithSeafItem:newItem];
            [self signalEnumerator:@[parentItemIdentifier, NSFileProviderWorkingSetContainerItemIdentifier]];
            completionHandler(reparentedItem, nil);
        }
    } failure:^(SeafDir *dir, NSError *error) {
        Warning("Failed to reparent %@: %@", itemIdentifier, error);
        completionHandler(nil, [NSError fileProvierErrorServerUnreachable]);
    }];
}

- (void)deleteItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
               completionHandler:(void (^)(NSError * _Nullable error))completionHandler
{
    Debug("itemIdentifier: %@", itemIdentifier);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:itemIdentifier];
    SeafDir *dir = (SeafDir *)[item.parentItem toSeafObj];
    [dir delEntries:[NSArray arrayWithObject:item.name] success:^(SeafDir *dir) {
        [self signalEnumerator:@[item.parentItem.itemIdentifier, NSFileProviderWorkingSetContainerItemIdentifier]];
        completionHandler(nil);
    } failure:^(SeafDir *dir, NSError *error) {
        completionHandler([NSError fileProvierErrorServerUnreachable]);
    }];
}

- (void)setTagData:(NSData *)tagData forItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier completionHandler:(void (^)(NSFileProviderItem _Nullable, NSError * _Nullable))completionHandler
{
    Debug("itemIdentifier: %@, tagData:%@", itemIdentifier, tagData);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:itemIdentifier];
    [item setTagData:tagData];
    [self saveToLocal:item];
    SeafProviderItem *tagedItem = [[SeafProviderItem alloc] initWithSeafItem:item];
    [self signalEnumerator:@[tagedItem.parentItemIdentifier,NSFileProviderWorkingSetContainerItemIdentifier]];
    completionHandler(tagedItem, nil);
}

- (void)signalEnumerator:(NSArray<NSFileProviderItemIdentifier> *)itemIdentifiers {
    if (@available(iOS 11.0, *)) {
        for (NSString *identifier in itemIdentifiers) {
            [NSFileProviderManager.defaultManager signalEnumeratorForContainerItemIdentifier:identifier completionHandler:^(NSError * _Nullable error) {
                Debug("error itemIdentifier: %@", identifier);
            }];
        }
    }
}

- (void)saveToLocal:(SeafItem *)item {
    NSDictionary *dict = [item convertToDict];
    @synchronized(self) {
        NSMutableDictionary *filesStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDE]];
        [filesStorage setObject:dict forKey:item.itemIdentifier];
        [SeafStorage.sharedObject setObject:filesStorage forKey:SEAF_FILE_PROVIDE];
    }
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
