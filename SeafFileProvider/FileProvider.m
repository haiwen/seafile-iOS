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
#import <MobileCoreServices/MobileCoreServices.h>
#import "SeafFileProviderUtility.h"
#import "SeafThumb.h"
#import "SeafDataTaskManager.h"
#import "SeafFileOperationManager.h"

@interface FileProvider ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSLock *> *fileLocks;
@property (nonatomic, strong) NSCache *urlCache;
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
        self.fileLocks = [NSMutableDictionary new];
        self.urlCache = [[NSCache alloc] init];
        self.urlCache.countLimit = 100;
        
        self.identifierCache = [[NSCache alloc] init];
        self.identifierCache.countLimit = 100;
        
        self.itemCache = [[NSCache alloc] init];
        self.itemCache.countLimit = 100;
        
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

- (nullable NSURL *)URLForItemWithPersistentIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
{
    // Check cache
    NSURL *cachedURL = [self.urlCache objectForKey:itemIdentifier];
    if (cachedURL) {
        return cachedURL;
    }
    
    Debug(@"[FileProvider] Getting file URL called: itemIdentifier=%@", itemIdentifier);
    NSURL *ret;
    if (![itemIdentifier isEqualToString:NSFileProviderRootContainerItemIdentifier] && ![itemIdentifier hasPrefix:@"/"]) {
        itemIdentifier = [NSString stringWithFormat:@"/%@", itemIdentifier];
    }
    NSArray *pathComponents = [itemIdentifier pathComponents];
    Debug(@"URLForItem pathComponents: %@", pathComponents);
    if (pathComponents.count == 1) {
        ret = self.rootURL;
    } else if (pathComponents.count == 2) {
        BOOL isFolder = [[pathComponents objectAtIndex:1] isEqualToString:(NSString *)kUTTypeFolder];
        ret = [self.rootURL URLByAppendingPathComponent:[pathComponents objectAtIndex:1] isDirectory:isFolder];
    } else {
        NSURL *url = [self.rootURL URLByAppendingPathComponent:[pathComponents objectAtIndex:1] isDirectory:true];
        ret = [url URLByAppendingPathComponent:[[pathComponents objectAtIndex:2] stringByRemovingPercentEncoding] isDirectory:false];
    }
    Debug(@"URLForItem url: %@", ret);
    
    // Cache result
    if (ret) {
        [self.urlCache setObject:ret forKey:itemIdentifier];
    }
    
    return ret;
}

- (nullable NSFileProviderItemIdentifier)persistentIdentifierForItemAtURL:(NSURL *)url {
    // Check cache
    NSString *cachedIdentifier = [self.identifierCache objectForKey:url];
    if (cachedIdentifier) {
        return cachedIdentifier;
    }
    
    Debug(@"[FileProvider] Getting file identifier called: url=%@", url);
    NSRange range = [url.path rangeOfString:self.rootPath.lastPathComponent];
    if (range.location == NSNotFound) {
        Warning("Unknown url: %@", url);
        return nil;
    }
    NSString *suffix = [url.path substringFromIndex:(range.location+range.length)];
    if (!suffix || suffix.length == 0) return NSFileProviderRootContainerItemIdentifier;
    NSArray *pathCompoents = suffix.pathComponents;
    if (pathCompoents.count >= 3) {
        NSString *path = url.path.precomposedStringWithCanonicalMapping;
        NSString *fileName = path.lastPathComponent;
        NSString *str = [NSString stringWithFormat:@"%@%@/%@", pathCompoents[0], pathCompoents[1], [fileName escapedUrl]];
        suffix = str;
    }
    
    // Cache result
    if (suffix) {
        [self.identifierCache setObject:suffix forKey:url];
    }
    
    return suffix;
}

- (nullable NSFileProviderItem)itemForIdentifier:(NSFileProviderItemIdentifier)identifier error:(NSError * _Nullable *)error
{
    // Check cache
    SeafProviderItem *cachedItem = [self.itemCache objectForKey:identifier];
    if (cachedItem) {
        return cachedItem;
    }
    
    Debug(@"[FileProvider] Getting file item called: identifier=%@", identifier);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:identifier];
    SeafProviderItem *providerItem = [[SeafProviderItem alloc] initWithSeafItem:item itemIdentifier:identifier];
    
    // Cache result
    if (providerItem) {
        [self.itemCache setObject:providerItem forKey:identifier];
    }
    
    return providerItem;
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
    Debug(@"[FileProvider] Providing placeholder called: url=%@", url);
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
    Debug(@"placeholderURL:%@ url:%@", placeholderURL, url);
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
    NSString *identifier = [self persistentIdentifierForItemAtURL:url];
    if (!identifier) {
        return completionHandler([NSError fileProvierErrorNoSuchItem]);
    }
    
    // Get or create file lock
    NSLock *lock = nil;
    @synchronized(self.fileLocks) {
        lock = self.fileLocks[identifier];
        if (!lock) {
            lock = [[NSLock alloc] init];
            self.fileLocks[identifier] = lock;
        }
    }
    
    // Try to acquire lock
    if (![lock tryLock]) {
        Debug(@"File is being processed, skipping duplicate operation: %@", identifier);
        return completionHandler(nil);
    }
    
    @try {
        // Original file processing logic
        SeafItem *item = [[SeafItem alloc] initWithItemIdentity:identifier];
        SeafFile *file = (SeafFile *)item.toSeafObj;
        
        if ([file isKindOfClass:[SeafFile class]]) {
            // Force reload to check if file needs update
            [file setFileDownloadedBlock:^(SeafFile * _Nonnull file, NSError * _Nullable error) {
                @try {
                    if (error) {
                        return completionHandler([NSError fileProvierErrorServerUnreachable]);
                    }
                    
                    if ([Utils fileExistsAtPath:url.path]) {
                        [Utils removeFile:url.path];
                    }
                    [Utils checkMakeDir:url.path.stringByDeletingLastPathComponent];
                    
                    BOOL ret = [Utils copyFile:file.exportURL to:url];
                    completionHandler(ret ? nil : [NSError fileProvierErrorNoSuchItem]);
                } @finally {
                    [self unlockAndRemoveFileLock:lock forIdentifier:identifier];
                }
            }];
            
            [file loadContent:true];
        } else {
            [self unlockAndRemoveFileLock:lock forIdentifier:identifier];
            completionHandler([NSError fileProvierErrorNoSuchItem]);
        }
    } @catch (NSException *exception) {
        [self unlockAndRemoveFileLock:lock forIdentifier:identifier];
        completionHandler([NSError fileProvierErrorNoSuchItem]);
    }
}

- (void)itemChangedAtURL:(NSURL *)url
{
    if ([url.path hasSuffix:@"/"] || [url.path isEqualToString:self.rootPath]) return;

    NSString *identifier = [self persistentIdentifierForItemAtURL:url];
    if ([identifier isEqualToString:NSFileProviderRootContainerItemIdentifier] || [identifier isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier]) {
        return;
    }
    
    [self clearCachesForIdentifier:identifier];
    
    Debug(@"File changed: %@ %@", url, identifier);
    SeafItem *item = [self readFromLocal:identifier];
    if (!item) {
        item = [[SeafItem alloc] initWithItemIdentity:identifier];
    }
    
    if (!item.isFile) {
        Debug(@"%@ is not a file.", identifier);
        return;
    }

    SeafFile *sfile = (SeafFile *)item.toSeafObj;
    NSURL *tempURL = [Utils generateFileTempPath:sfile.name];
    BOOL ret = [self copyItemAtURL:url toURL:tempURL];
    if (ret) {
        [sfile uploadFromFile:tempURL];
        [sfile waitUpload];
    }
}

- (BOOL)copyItemAtURL:(NSURL *)fromUrl toURL:(NSURL *)toURL {
    [[NSFileManager defaultManager] removeItemAtURL:toURL error:nil];
    NSError *error;
    BOOL ret = [[NSFileManager defaultManager] copyItemAtURL:fromUrl toURL:toURL error:&error];
    return error ? NO : ret;
}

- (void)stopProvidingItemAtURL:(NSURL *)url
{
    Debug(@"[FileProvider] Stopping providing file called: url=%@", url);
    NSString *identifier = [self persistentIdentifierForItemAtURL:url];
    if (identifier) {
        [self clearCachesForIdentifier:identifier];
    }
    
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
    SeafEnumerator *enumerator = nil;
    if (![containerItemIdentifier isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier]) {
        if ([containerItemIdentifier isEqualToString:NSFileProviderRootContainerItemIdentifier]) {
            enumerator = [[SeafEnumerator alloc] initWithItemIdentifier:containerItemIdentifier];
        } else {
            SeafItem *item = [[SeafItem alloc] initWithItemIdentity:containerItemIdentifier];
            if (item.isAccountRoot && item.isTouchIdEnabled) {
                *error = [NSError fileProvierErrorNotAuthenticated];
                enumerator = [[SeafEnumerator alloc] initWithItemIdentifier:containerItemIdentifier];
            } else {
                 enumerator = [[SeafEnumerator alloc] initWithItemIdentifier:containerItemIdentifier];
            }
        }
    }
    return enumerator;
}

# pragma mark - NSFileProviderActions
- (void)importDocumentAtURL:(NSURL *)fileURL
     toParentItemIdentifier:(NSFileProviderItemIdentifier)parentItemIdentifier
          completionHandler:(void (^)(NSFileProviderItem _Nullable importedDocumentItem, NSError * _Nullable error))completionHandler
{
    Debug(@"[FileProvider] Importing file called: fileURL=%@, parentItemIdentifier=%@", fileURL, parentItemIdentifier);
    Debug("file path: %@, parentItemIdentifier:%@", fileURL.path, parentItemIdentifier);
    NSString *fileName = fileURL.path.lastPathComponent;

    SeafItem *parentItem = [[SeafItem alloc] initWithItemIdentity:parentItemIdentifier];
    if ([[parentItem toSeafObj] isKindOfClass:[SeafDir class]]) {
        SeafDir *dir = (SeafDir *)[parentItem toSeafObj];
        bool exit = false;
        while (exit != true) {
            if ([dir nameExist:fileName]) {
                fileName = [Utils creatNewFileName:fileName];
            } else {
                exit = true;
            }
        }
    }
    
    NSFileProviderItemIdentifier itemIdentifier = [parentItemIdentifier stringByAppendingPathComponent:[fileName.precomposedStringWithCanonicalMapping escapedUrl]];
    Debug("file itemIdentifier: %@", itemIdentifier);

    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:itemIdentifier];
    [self saveToLocal:item];
    __weak SeafFile *sfile = (SeafFile *)[item toSeafObj];
    NSURL *localURL = [self URLForItemWithPersistentIdentifier:itemIdentifier];

    [sfile setFileUploadedBlock:^(SeafUploadFile *file, NSString *oid, NSError *error) {
        if (error) {
            completionHandler(nil, [NSError fileProvierErrorServerUnreachable]);
        } else {
            SeafProviderItem *providerItem = [[SeafProviderItem alloc] initWithSeafItem:[SeafItem fromSeafBase:sfile]];
            
            [parentItem updateCacheWithSubItem:item];
            [SeafFileProviderUtility.shared saveUpdateItem:providerItem];
            [self signalEnumerator:@[parentItemIdentifier, NSFileProviderWorkingSetContainerItemIdentifier]];
            [self removeProvidingItemAndParentIfEmpty:localURL];
        }
    }];
    
    [fileURL startAccessingSecurityScopedResource];
    [Utils checkMakeDir:localURL.path.stringByDeletingLastPathComponent];
    if ([Utils fileExistsAtPath:localURL.path]) {
        [Utils removeFile:localURL.path];
    }
    NSError *err = nil;
    BOOL ret = [[NSFileManager defaultManager] copyItemAtURL:fileURL toURL:localURL error:&err];
    [fileURL stopAccessingSecurityScopedResource];

    Debug(@"local file size: %lld", [Utils fileSizeAtPath1:localURL.path]);
    if (!ret) return completionHandler(nil, [NSError fileProvierErrorNoSuchItem]);
    [localURL startAccessingSecurityScopedResource];
    ret = [sfile uploadFromFile:localURL];
    [localURL stopAccessingSecurityScopedResource];
    if (!ret) return completionHandler(nil, [NSError fileProvierErrorNoSuchItem]);
    
    SeafProviderItem *providerItem = [[SeafProviderItem alloc] initWithSeafItem:[SeafItem fromSeafBase:sfile]];
    completionHandler(providerItem, nil);
}

- (void)createDirectoryWithName:(NSString *)directoryName
         inParentItemIdentifier:(NSFileProviderItemIdentifier)parentItemIdentifier
              completionHandler:(void (^)(NSFileProviderItem _Nullable createdDirectoryItem, NSError * _Nullable error))completionHandler
{
    Debug("create dir parentItemIdentifier: %@, directoryName:%@", parentItemIdentifier, directoryName);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:parentItemIdentifier];
    SeafDir *parentDir = (SeafDir *)[item toSeafObj];
    
    [[SeafFileOperationManager sharedManager] mkdir:directoryName inDir:parentDir completion:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            NSString *createdDirectoryPath = [parentDir.path stringByAppendingPathComponent:directoryName];
            SeafItem *createdItem = [[SeafItem alloc] initWithServer:parentDir.connection.address 
                                                          username:parentDir.connection.username 
                                                             repo:parentDir.repoId 
                                                             path:createdDirectoryPath 
                                                         filename:nil];
            SeafProviderItem *providerItem = [[SeafProviderItem alloc] initWithSeafItem:createdItem];
            [self signalEnumerator:@[parentItemIdentifier, NSFileProviderWorkingSetContainerItemIdentifier]];
            completionHandler(providerItem, nil);
        } else {
            completionHandler(nil, [NSError fileProvierErrorServerUnreachable]);
        }
    }];
}

- (void)renameItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
                          toName:(NSString *)itemName
               completionHandler:(void (^)(NSFileProviderItem _Nullable renamedItem, NSError * _Nullable error))completionHandler
{
    Debug("itemIdentifier: %@, toName:%@", itemIdentifier, itemName);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:itemIdentifier];
    SeafDir *dir = (SeafDir *)[item.parentItem toSeafObj];

    [[SeafFileOperationManager sharedManager] renameEntry:item.name
                                                newName:itemName
                                                  inDir:dir
                                             completion:^(BOOL success, SeafBase *renamedFile, NSError *error) {
        if (success && renamedFile) {
            SeafProviderItem *renamedItem = [[SeafProviderItem alloc] initWithSeafItem:[SeafItem fromSeafBase:renamedFile]];
            completionHandler(renamedItem, nil);
        } else {
            completionHandler(nil, error ?: [Utils defaultError]);
        }
    }];
}
- (void)reparentItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
        toParentItemWithIdentifier:(NSFileProviderItemIdentifier)parentItemIdentifier
                           newName:(nullable NSString *)newName
                 completionHandler:(void (^)(NSFileProviderItem _Nullable reparentedItem, NSError * _Nullable error))completionHandler
{
    // move file
    Debug("move file itemIdentifier: %@, parentItemIdentifier:%@", itemIdentifier, parentItemIdentifier);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:itemIdentifier];
    SeafItem *dstItem = [[SeafItem alloc] initWithItemIdentity:parentItemIdentifier];
    SeafDir *srcDir = (SeafDir *)[item.parentItem toSeafObj];
    SeafDir *dstDir = (SeafDir *)dstItem.toSeafObj;

    [[SeafFileOperationManager sharedManager] moveEntries:@[item.name]
                                                fromDir:srcDir
                                                  toDir:dstDir
                                             completion:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            Warning("Failed to reparent %@: %@", itemIdentifier, error);
            completionHandler(nil, [NSError fileProvierErrorServerUnreachable]);
            return;
        }
        
        NSString *newpath = [dstDir.path stringByAppendingPathComponent:item.name];
        NSString *filename = item.isFile ? item.filename : nil;
        
        if (newName && ![newName isEqualToString:item.name]) {
            [[SeafFileOperationManager sharedManager] renameEntry:item.name
                                                        newName:newName
                                                          inDir:dstDir
                                                     completion:^(BOOL success, SeafBase *renamedFile, NSError *error) {
                if (success) {
                    NSString *renamedpath = [dstDir.path stringByAppendingPathComponent:newName];
                    SeafItem *renamedItem = [[SeafItem alloc] initWithServer:dstDir.connection.address 
                                                                  username:dstDir.connection.username 
                                                                     repo:dstDir.repoId 
                                                                     path:renamedpath 
                                                                 filename:newName];
                    Debug("reparent %@ successfully", itemIdentifier);
                    [self signalEnumerator:@[parentItemIdentifier, NSFileProviderWorkingSetContainerItemIdentifier]];
                    completionHandler([[SeafProviderItem alloc] initWithSeafItem:renamedItem], nil);
                } else {
                    Warning("Failed to reparent %@: %@", itemIdentifier, error);
                    completionHandler(nil, [NSError fileProvierErrorServerUnreachable]);
                }
            }];
        } else {
            SeafItem *newItem = [[SeafItem alloc] initWithServer:dstDir.connection.address 
                                                      username:dstDir.connection.username 
                                                         repo:dstDir.repoId 
                                                         path:newpath 
                                                     filename:filename];
            SeafProviderItem *reparentedItem = [[SeafProviderItem alloc] initWithSeafItem:newItem];
            [self signalEnumerator:@[parentItemIdentifier, NSFileProviderWorkingSetContainerItemIdentifier]];
            completionHandler(reparentedItem, nil);
        }
    }];
}

- (void)deleteItemWithIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
               completionHandler:(void (^)(NSError * _Nullable error))completionHandler
{
    Debug("itemIdentifier: %@", itemIdentifier);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:itemIdentifier];
    SeafDir *dir = (SeafDir *)[item.parentItem toSeafObj];
    
    [[SeafFileOperationManager sharedManager] deleteEntries:@[item.name] 
                                                    inDir:dir 
                                               completion:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            [self signalEnumerator:@[item.parentItem.itemIdentifier, NSFileProviderWorkingSetContainerItemIdentifier]];
            completionHandler(nil);
        } else {
            completionHandler([NSError fileProvierErrorServerUnreachable]);
        }
    }];
}

- (void)setTagData:(NSData *)tagData forItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier completionHandler:(void (^)(NSFileProviderItem _Nullable, NSError * _Nullable))completionHandler
{
    Debug("itemIdentifier: %@, tagData:%@", itemIdentifier, tagData);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:itemIdentifier];
    [item setTagData:tagData];
    if (tagData && tagData.length > 0) {
        [self saveToLocal:item];
    } else {
        [self removeFromLocal:item];
    }
    SeafProviderItem *tagedItem = [[SeafProviderItem alloc] initWithSeafItem:item];
    [self signalEnumerator:@[tagedItem.parentItemIdentifier,NSFileProviderWorkingSetContainerItemIdentifier]];
    completionHandler(tagedItem, nil);
}

-(void)setLastUsedDate:(NSDate *)lastUsedDate forItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier completionHandler:(void (^)(NSFileProviderItem _Nullable, NSError * _Nullable))completionHandler {
    Debug("itemIdentifier: %@, lastUsedDate:%@", itemIdentifier, lastUsedDate);
    completionHandler(nil, [NSError fileProvierErrorFeatureUnsupported]);
}

- (void)setFavoriteRank:(nullable NSNumber *)favoriteRank
      forItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
      completionHandler:(void (^)(NSFileProviderItem _Nullable favoriteItem, NSError * _Nullable error))completionHandler
{
    Debug("itemIdentifier: %@, favoriteRank:%@", itemIdentifier, favoriteRank);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:itemIdentifier];
    [item setFavoriteRank:favoriteRank];
    if (favoriteRank) {
        [self saveToLocal:item];
    } else {
        [self removeFromLocal:item];
    }
    SeafProviderItem *lastItem = [[SeafProviderItem alloc] initWithSeafItem:item];
    completionHandler(lastItem, nil);
}

- (NSProgress *)fetchThumbnailsForItemIdentifiers:(NSArray<NSFileProviderItemIdentifier> *)itemIdentifiers requestedSize:(CGSize)size perThumbnailCompletionHandler:(void (^)(NSFileProviderItemIdentifier _Nonnull, NSData * _Nullable, NSError * _Nullable))perThumbnailCompletionHandler completionHandler:(void (^)(NSError * _Nullable))completionHandler {
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:itemIdentifiers.count];
    __block NSInteger counterProgress = 0;
    
    for (NSString *itemIdentifier in itemIdentifiers) {
        Debug("fetch thumb itemIdentifier: %@", itemIdentifier);
        SeafItem *item = [[SeafItem alloc] initWithItemIdentity:itemIdentifier];
        if (!item.isFile) {
            counterProgress += 1;
            if (counterProgress == progress.totalUnitCount) {
                completionHandler(nil);
            }
            continue;
        }
        
        SeafFile *sfile = (SeafFile *)[item toSeafObj];
        if ([sfile isImageFile]) {
            if (sfile.thumb) {
                counterProgress += 1;
                NSData *imageData = UIImagePNGRepresentation(sfile.thumb);
                perThumbnailCompletionHandler(itemIdentifier, imageData, nil);
                if (counterProgress == progress.totalUnitCount) {
                    completionHandler(nil);
                }
            } else {
                __weak typeof(sfile) weakFile = sfile;
                [weakFile setThumbCompleteBlock:^(BOOL ret) {
                    counterProgress += 1;
                    if (ret) {
                        NSData *imageData = [NSData dataWithContentsOfFile:[weakFile thumbPath:weakFile.oid]];
                        perThumbnailCompletionHandler(itemIdentifier, imageData, nil);
                    } else {
                        Warning("Failed fetch thumb itemIdentifier: %@", itemIdentifier);
                        perThumbnailCompletionHandler(itemIdentifier, nil, [NSError fileProvierErrorServerUnreachable]);
                    }
                    if (counterProgress == progress.totalUnitCount) {
                        completionHandler(nil);
                    }
                }];
                SeafThumb *thb = [[SeafThumb alloc] initWithSeafFile:weakFile];
                [SeafDataTaskManager.sharedObject addThumbTask:thb];

            }
        } else {
            counterProgress += 1;
            if (counterProgress == progress.totalUnitCount) {
                completionHandler(nil);
            }
        }
    }
    return progress;
}

- (void)signalEnumerator:(NSArray<NSFileProviderItemIdentifier> *)itemIdentifiers {
    if (@available(iOS 11.0, *)) {
        SeafFileProviderUtility.shared.currentAnchor += 1;
        for (NSString *identifier in itemIdentifiers) {
            [NSFileProviderManager.defaultManager signalEnumeratorForContainerItemIdentifier:identifier completionHandler:^(NSError * _Nullable error) {
                if (error) {
                    Debug("signalEnumerator itemIdentifier: %@ error: %@", identifier, error);
                }
            }];
        }
    }
}

- (void)saveToLocal:(SeafItem *)item {
    NSDictionary *dict = [item convertToDict];
    @synchronized(self) {
        NSMutableDictionary *filesStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER]];
        [filesStorage setObject:dict forKey:item.itemIdentifier];
        [SeafStorage.sharedObject setObject:filesStorage forKey:SEAF_FILE_PROVIDER];
    }
}

- (void)removeFromLocal:(SeafItem *)item {
    @synchronized(self) {
        NSMutableDictionary *filesStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER]];
        [filesStorage removeObjectForKey:item.itemIdentifier];
        [SeafStorage.sharedObject setObject:filesStorage forKey:SEAF_FILE_PROVIDER];
    }
}

- (SeafItem *)readFromLocal:(NSString *)itemIdentifier {
    SeafItem *item;
    @synchronized (self) {
        NSMutableDictionary *filesStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER]];
        NSDictionary *dict = [filesStorage valueForKey:itemIdentifier];
        if (dict) {
            [item convertFromDict:dict];
        }
    }
    return item;
}

// Add a method to clear all caches
- (void)clearAllCaches {
    [self.urlCache removeAllObjects];
    [self.identifierCache removeAllObjects];
    [self.itemCache removeAllObjects];
}

- (void)clearCachesForIdentifier:(NSString *)identifier {
    [self.urlCache removeObjectForKey:identifier];
    [self.itemCache removeObjectForKey:identifier];
    // Iterate and clear related URL cache
    NSString *urlString = [self.identifierCache.name copy];
    if (urlString) {
        NSURL *url = [NSURL URLWithString:urlString];
        [self.identifierCache removeObjectForKey:url];
    }
}

- (void)unlockAndRemoveFileLock:(NSLock *)lock forIdentifier:(NSString *)identifier {
    if (lock) {
        [lock unlock];
        @synchronized(self.fileLocks) {
            [self.fileLocks removeObjectForKey:identifier];
        }
    }
}

- (void)dealloc {
    @synchronized(self.fileLocks) {
        [self.fileLocks removeAllObjects];
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
