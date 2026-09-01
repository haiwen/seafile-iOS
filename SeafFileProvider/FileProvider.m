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
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "SeafFileProviderUtility.h"
#import "SeafThumb.h"
#import "SeafDataTaskManager.h"
#import "SeafFileOperationManager.h"

@interface FileProvider ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSLock *> *fileLocks;
@property (nonatomic, strong) NSCache *urlCache;
- (void)refreshAccountsIfNeeded;
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
        
        // Sync account list to get latest info
        // Lightweight sync: reload only if changed
        [self refreshAccountsIfNeeded];

        [self migrateLocalMetadataStoreIfNeeded];
        [self migrateStorageDirectoriesIfNeeded];
        [self materializePersistedFavoriteContainers];
        [SeafFileProviderUtility.shared requestWorkingSetFullResyncIfNeeded];
        if (SeafFileProviderUtility.shared.pendingWorkingSetFullResync) {
            // fileproviderd keeps its own favorite records across an app upgrade. A change
            // enumeration from the last pre-upgrade anchor reports "nothing changed" and
            // never replaces those stale records; expire-and-relist is what does.
            [self signalEnumerator:@[NSFileProviderWorkingSetContainerItemIdentifier]];
        }
    }
    return self;
}

/**
 * Recreates on-disk container directories for every persisted favorite. The Files app
 * takes a coordinated read on those URLs when rebuilding sidebar bookmarks after a
 * relaunch; if the directory is missing the read fails and the favorite disappears.
 * The legacy path is materialized alongside the slug path: a bookmark created while an
 * older build was installed still points there.
 */
- (void)materializePersistedFavoriteContainers {
    NSDictionary *store = [SeafItem localMetadataStore];
    for (id value in store.allValues) {
        if (![value isKindOfClass:[NSDictionary class]]) continue;
        if (![value objectForKey:@"favoriteRank"]) continue;

        NSString *identifier = [value objectForKey:@"itemIdentifier"];
        if (identifier.length == 0) continue;

        // Containers only, matching the guard in setFavoriteRank: for a file entry the URL
        // is the file's content path, and materializing would replace the downloaded copy
        // with an empty directory.
        if ([[SeafItem alloc] initWithItemIdentity:identifier].isFile) continue;

        NSURL *url = [self URLForItemWithPersistentIdentifier:identifier];
        if (url) {
            [self materializeContainerDirectoryAtURL:url];
        }
        NSURL *legacyURL = [self legacyStorageURLForContainerIdentifier:identifier];
        if (legacyURL) {
            [self materializeContainerDirectoryAtURL:legacyURL];
        }
    }
}

/**
 * Rekeys the metadata store to canonical identifiers.
 * Entries written before identifiers were normalized are keyed by whatever the system
 * supplied, so a canonical lookup would miss them and the favorite would read as removed.
 * Version 2 flips the canonical form to slash-less identifiers and rekeys the slug maps
 * and the reported working set. The legacy slash-prefixed forms are deliberately NOT
 * reported as deletions: fileproviderd normalizes identifiers on the deletion path too,
 * so deleting "/x" tears down the live "x" node along with its sidebar favorite.
 */
- (void)migrateLocalMetadataStoreIfNeeded {
    if ([[SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER_STORE_VERSION] integerValue] >= 2) {
        return;
    }

    @synchronized(self) {
        NSDictionary *stored = [SeafItem localMetadataStore];
        NSMutableDictionary *migrated = [NSMutableDictionary dictionaryWithCapacity:stored.count];
        if (stored.count > 0) {
            for (NSString *key in stored) {
                NSDictionary *dict = [stored objectForKey:key];
                if (![dict isKindOfClass:[NSDictionary class]]) continue;

                NSFileProviderItemIdentifier canonicalId = [SeafItem canonicalIdentifier:key];
                NSString *storedIdentifier = [dict objectForKey:@"itemIdentifier"];
                if (![canonicalId isEqualToString:key] || ![storedIdentifier isEqualToString:canonicalId]) {
                    NSMutableDictionary *rekeyed = [NSMutableDictionary dictionaryWithDictionary:dict];
                    [rekeyed setObject:canonicalId forKey:@"itemIdentifier"];
                    dict = rekeyed;
                }

                // Two raw keys can collapse onto one canonical key; the entry carrying a
                // favorite outranks one that only holds leftover import metadata.
                NSDictionary *collision = [migrated objectForKey:canonicalId];
                if (collision && [collision objectForKey:@"favoriteRank"] && ![dict objectForKey:@"favoriteRank"]) {
                    continue;
                }
                [migrated setObject:dict forKey:canonicalId];
            }
            [SeafStorage.sharedObject setObject:migrated forKey:SEAF_FILE_PROVIDER];
            Debug(@"Migrated %lu file provider metadata entries to %lu canonical keys",
                  (unsigned long)stored.count, (unsigned long)migrated.count);
        }

        [SeafFileProviderUtility.shared rekeyStorageMapsToCanonicalIdentifiers];

        NSMutableOrderedSet *reported = [NSMutableOrderedSet orderedSet];
        for (NSString *identifier in [SeafFileProviderUtility.shared reportedWorkingSetIdentifiers]) {
            [reported addObject:[SeafItem canonicalIdentifier:identifier]];
        }
        [SeafFileProviderUtility.shared setReportedWorkingSetIdentifiers:reported.array];

        [SeafStorage.sharedObject setObject:@(2) forKey:SEAF_FILE_PROVIDER_STORE_VERSION];
    }
}

/**
 * Collapses legacy on-disk container directories onto their storage slugs and registers
 * every known directory name in the slug map, leaving an empty directory behind at each
 * legacy path. fileproviderd's records and the sidebar bookmarks written while an older
 * build was installed still carry those paths, and persisting a favorite checks that the
 * recorded path exists — deleting the legacy directory made that check fail silently, so a
 * favorite added right after an upgrade never survived a Files app relaunch. The legacy
 * path and the slug path resolve to the same canonical identifier, so the leftover
 * directory cannot surface as a second favorite the way the old two-node split did.
 */
- (void)migrateStorageDirectoriesIfNeeded {
    // One-shot migration: after the collapse only slug-named directories are ever created,
    // and a per-launch scan would re-delete content written through a still-live legacy
    // bookmark between launches.
    if ([[SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER_STORAGE_DIRS_VERSION] integerValue] >= 1) {
        return;
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray<NSString *> *entries = [manager contentsOfDirectoryAtPath:self.rootURL.path error:&error];
    if (!entries) {
        return;
    }

    for (NSString *entry in entries) {
        if ([entry isEqualToString:@".DS_Store"]) {
            continue;
        }

        BOOL isDirectory = NO;
        NSString *entryPath = [self.rootURL.path stringByAppendingPathComponent:entry];
        if (![manager fileExistsAtPath:entryPath isDirectory:&isDirectory] || !isDirectory) {
            continue;
        }

        NSFileProviderItemIdentifier identifier = nil;
        if ([SeafFileProviderUtility.shared isStorageSlug:entry]) {
            identifier = [SeafFileProviderUtility.shared identifierForStorageSlug:entry];
            if (!identifier) {
                // The slug map is the only way back from the one-way SHA1 name, and a missing
                // entry is indistinguishable from a lost map (restore that carries files but
                // not prefs, failed defaults write). Deleting here would wipe live container
                // directories and the Files app bookmarks pointing into them.
                Warning("Unmapped storage slug left in place: %@", entry);
            }
            continue;
        }

        if ([entry containsString:@"%"] || [entry hasPrefix:@"http"]) {
            identifier = [SeafItem canonicalIdentifier:entry];
            NSString *slug = [SeafFileProviderUtility.shared storageSlugForIdentifier:identifier];
            NSString *slugPath = [self.rootURL.path stringByAppendingPathComponent:slug];
            if ([entry isEqualToString:slug]) {
                continue;
            }
            if (![manager fileExistsAtPath:slugPath]) {
                [manager moveItemAtPath:entryPath toPath:slugPath error:nil];
            } else if ([manager contentsOfDirectoryAtPath:entryPath error:nil].count > 0) {
                // The slug directory is the live copy; the leftover content is stale.
                [manager removeItemAtPath:entryPath error:nil];
            } else {
                continue; // already reduced to the empty legacy marker
            }
            [manager createDirectoryAtPath:entryPath withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }

    [SeafStorage.sharedObject setObject:@(1) forKey:SEAF_FILE_PROVIDER_STORAGE_DIRS_VERSION];
}

/**
 * The pre-slug on-disk location of a container: older builds used the encoded identifier
 * itself as the directory name. Returns nil for the system containers.
 */
- (nullable NSURL *)legacyStorageURLForContainerIdentifier:(NSFileProviderItemIdentifier)identifier
{
    NSFileProviderItemIdentifier canonicalId = [SeafItem canonicalIdentifier:identifier];
    if ([canonicalId isEqualToString:NSFileProviderRootContainerItemIdentifier]
        || [canonicalId isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier]) {
        return nil;
    }
    NSString *container = canonicalId.pathComponents.firstObject;
    if (container.length == 0) {
        return nil;
    }
    return [self.rootURL URLByAppendingPathComponent:container isDirectory:YES];
}

/**
 * Re-reads the account list before answering a request.
 * The extension process outlives any single sign-in: one launched while no account existed
 * yet keeps an empty connection list, so every root enumeration answers NotAuthenticated
 * and every item fails to resolve its connection, until the system happens to recycle the
 * process. Signalling the root enumerator from the app only makes the system ask again -
 * it does not reload the list - so the reload has to happen on the request itself.
 * Anything cached against the old accounts is dropped along with it.
 */
- (void)refreshAccountsIfNeeded
{
    if (![SeafGlobal.sharedObject syncAccountsFromStorage]) {
        return;
    }
    [self clearAllCaches];
}

- (NSString *)rootPath
{
    return self.rootURL.path;
}

- (NSURL *)rootURL
{
    return [[NSFileProviderManager defaultManager] documentStorageURL];
}

- (nullable NSURL *)URLForItemWithPersistentIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
{
    itemIdentifier = [SeafItem canonicalIdentifier:itemIdentifier];

    // Check cache
    NSURL *cachedURL = [self.urlCache objectForKey:itemIdentifier];
    if (cachedURL) {
        return cachedURL;
    }
    
    Debug(@"[FileProvider] Getting file URL called: itemIdentifier=%@", itemIdentifier);
    NSURL *ret;
    if ([itemIdentifier isEqualToString:NSFileProviderRootContainerItemIdentifier]
        || [itemIdentifier isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier]) {
        ret = self.rootURL;
    } else {
        NSArray *pathComponents = [itemIdentifier pathComponents];
        if (pathComponents.count == 1) {
            // A single-component identifier always denotes a container (account root, library
            // root or folder); a file carries a second component holding its name.
            NSString *slug = [SeafFileProviderUtility.shared storageSlugForIdentifier:itemIdentifier];
            ret = [self.rootURL URLByAppendingPathComponent:slug isDirectory:YES];
        } else {
            NSString *containerIdentifier = [pathComponents objectAtIndex:0];
            NSString *slug = [SeafFileProviderUtility.shared storageSlugForIdentifier:containerIdentifier];
            NSURL *url = [self.rootURL URLByAppendingPathComponent:slug isDirectory:true];
            // A malformed legacy escape decodes to nil, and URLByAppendingPathComponent:nil
            // throws; fall back to the raw component instead.
            NSString *nameComponent = [pathComponents objectAtIndex:1];
            NSString *decodedName = [nameComponent stringByRemovingPercentEncoding] ?: nameComponent;
            ret = [url URLByAppendingPathComponent:decodedName isDirectory:false];
        }
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
    if (pathCompoents.count == 2) {
        NSString *slug = pathCompoents[1];
        NSString *identifier = [SeafFileProviderUtility.shared identifierForStorageSlug:slug];
        if (identifier) {
            suffix = identifier;
        } else if ([slug containsString:@"%"] || [slug hasPrefix:@"http"]) {
            // Pre-slug installs stored containers under the full encoded path component.
            suffix = [SeafItem canonicalIdentifier:slug];
        } else {
            Warning("Unknown storage slug, cannot resolve identifier: %@", slug);
            return nil;
        }
    } else if (pathCompoents.count >= 3) {
        NSString *slug = pathCompoents[1];
        NSString *containerIdentifier = [SeafFileProviderUtility.shared identifierForStorageSlug:slug];
        if (!containerIdentifier) {
            containerIdentifier = [SeafItem canonicalIdentifier:slug];
        }
        NSString *path = url.path.precomposedStringWithCanonicalMapping;
        NSString *fileName = path.lastPathComponent;
        suffix = [NSString stringWithFormat:@"%@/%@", containerIdentifier, [fileName escapedUrl]];
    }
    
    // Cache result
    if (suffix) {
        [self.identifierCache setObject:suffix forKey:url];
    }
    
    return suffix;
}

- (nullable NSFileProviderItem)itemForIdentifier:(NSFileProviderItemIdentifier)identifier error:(NSError * _Nullable *)error
{
    // Before the cache lookup below: a reload evicts the entries built against the old
    // account list, which is exactly what must not be served back here.
    [self refreshAccountsIfNeeded];

    NSFileProviderItemIdentifier canonicalId = [SeafItem canonicalIdentifier:identifier];

    // Check cache
    SeafProviderItem *cachedItem = [self.itemCache objectForKey:canonicalId];
    if (cachedItem) {
        return cachedItem;
    }
    
    Debug(@"[FileProvider] Getting file item called: identifier=%@", canonicalId);
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:canonicalId];

    BOOL isSystemContainer = [canonicalId isEqualToString:NSFileProviderRootContainerItemIdentifier]
                          || [canonicalId isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier];
    if (!isSystemContainer && item.isRoot) {
        // The identifier did not decode into an account. Reporting the root item instead
        // would leave the Files app holding a bogus entry that never resolves.
        Warning("Failed to resolve item identifier: %@", identifier);
        if (error) *error = [NSError fileProvierErrorNoSuchItem];
        return nil;
    }

    // Favorite rank and display name live in local storage, not on the server, so an item
    // rebuilt from its identifier alone would come back without them after a cold start.
    [item applyLocalMetadataFromStore:[SeafItem localMetadataStore]];

    SeafProviderItem *providerItem = [[SeafProviderItem alloc] initWithSeafItem:item itemIdentifier:canonicalId];
    
    // Cache result
    if (providerItem) {
        [self.itemCache setObject:providerItem forKey:canonicalId];
    }
    
    return providerItem;
}

- (NSURL *)getPlaceholderURLForURL:(NSURL *)url
{
    return [NSFileProviderManager placeholderURLForURL:url];
}

/**
 * Makes sure a container's URL exists on disk so a coordinated read on it can succeed.
 * Directory contents stay lazy — the enumerator is what fills them in.
 */
- (NSError *)materializeContainerDirectoryAtURL:(NSURL *)url
{
    if (!url) {
        return [NSError fileProvierErrorNoSuchItem];
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if ([manager fileExistsAtPath:url.path isDirectory:&isDirectory]) {
        if (isDirectory) {
            return nil;
        }
        // A stale regular file would make createDirectory fail forever.
        [Utils removeFile:url.path];
    }

    NSError *error = nil;
    if ([manager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:&error]) {
        return nil;
    }

    // createDirectoryAtURL returns NO when the directory already exists — normal after
    // the first bookmark read, and required for favorites to survive a Files app relaunch.
    if ([manager fileExistsAtPath:url.path isDirectory:&isDirectory] && isDirectory) {
        return nil;
    }

    Warning("Failed to materialize container directory %@: %@", url.path, error);
    return [NSError fileProvierErrorNoSuchItem];
}

- (void)providePlaceholderAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))completionHandler
{
    Debug(@"[FileProvider] Providing placeholder called: url=%@", url);
    NSFileProviderItemIdentifier identifier = [self persistentIdentifierForItemAtURL:url];
    if (!identifier) {
        return completionHandler([NSError fileProvierErrorNoSuchItem]);
    }
    SeafItem *item = [[SeafItem alloc] initWithItemIdentity:identifier];
    // The placeholder metadata must carry the persisted display name and rank; built from
    // the identifier alone, an unloaded library root falls back to its repo UUID.
    [item applyLocalMetadataFromStore:[SeafItem localMetadataStore]];
    if (!item.isFile) {
        NSError *materializeError = [self materializeContainerDirectoryAtURL:url];
        if (materializeError) {
            return completionHandler(materializeError);
        }
        NSURL *placeholderURL = [self getPlaceholderURLForURL:url];
        SeafProviderItem *providerItem = [[SeafProviderItem alloc] initWithSeafItem:item itemIdentifier:identifier];
        NSError *error = nil;
        [NSFileProviderManager writePlaceholderAtURL:placeholderURL withMetadata:providerItem error:&error];
        return completionHandler(error);
    }

    [Utils checkMakeDir:url.path.stringByDeletingLastPathComponent];
    NSURL *placeholderURL = [self getPlaceholderURLForURL:url];
    Debug(@"placeholderURL:%@ url:%@", placeholderURL, url);
    NSError *error = nil;
    SeafProviderItem *providerItem = [[SeafProviderItem alloc] initWithSeafItem:item];
    [NSFileProviderManager writePlaceholderAtURL:placeholderURL withMetadata:providerItem error:&error];
    if (error) Warning("Failed to write placeholder: %@", error);
    completionHandler(error);
}

- (void)startProvidingItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *))completionHandler
{
    NSString *identifier = [self persistentIdentifierForItemAtURL:url];
    if (!identifier) {
        return completionHandler([NSError fileProvierErrorNoSuchItem]);
    }

    // See providePlaceholderAtURL: a coordinated read on a container has to succeed or the
    // Favorites bookmark the Files app builds for it is discarded.
    SeafItem *probe = [[SeafItem alloc] initWithItemIdentity:identifier];
    if (!probe.isFile) {
        return completionHandler([self materializeContainerDirectoryAtURL:url]);
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
            // Quick path: if we already have a cached copy, provide it immediately to avoid iOS timeout
            if ([file hasCache] && file.exportURL) {
                // Ensure target directory exists
                if ([Utils fileExistsAtPath:url.path]) {
                    [Utils removeFile:url.path];
                }
                [Utils checkMakeDir:url.path.stringByDeletingLastPathComponent];

                BOOL copied = [Utils copyFile:file.exportURL to:url];

                // Fire background refresh to get latest version, but don't block the caller
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    // Remove any previous download callback to avoid duplicate completion handling
                    [file setFileDownloadedBlock:nil];
                    // Force refresh; newer version will be written later & enumerator signalled elsewhere
                    [file loadContent:true];
                });

                [self unlockAndRemoveFileLock:lock forIdentifier:identifier];
                return completionHandler(copied ? nil : [NSError fileProvierErrorServerUnreachable]);
            }
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
                    completionHandler(ret ? nil : [NSError fileProvierErrorServerUnreachable]);
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

    // Only a file's downloaded content is ours to throw away. Deleting a container would undo
    // the directory a coordinated read just created, taking the Files app's bookmark with it.
    // An unresolvable identifier gets the same benefit of the doubt: it is far more likely a
    // container whose slug mapping was lost than a stray file.
    BOOL isFile = identifier != nil && [[[SeafItem alloc] initWithItemIdentity:identifier] isFile];
    if (!isFile) {
        return;
    }

    [self.fileCoordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForDeleting error:nil byAccessor:^(NSURL *newURL) {
        [self removeProvidingItem:url];
    }];
}

/**
 * Drops a file's downloaded content. The enclosing directory is deliberately left behind even
 * when it becomes empty: it is the target of whatever bookmark the Files app holds for that
 * folder, and removing it breaks Favorites and state restoration.
 */
- (void)removeProvidingItem:(NSURL *)url
{
    Debug("Remove providingItem: %@", url);
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
}

# pragma mark - NSFileProviderEnumerator
- (nullable id<NSFileProviderEnumerator>)enumeratorForContainerItemIdentifier:(NSFileProviderItemIdentifier)containerItemIdentifier error:(NSError **)error
{
    Debug("enumerator for %@", containerItemIdentifier);
    [self refreshAccountsIfNeeded];
    // The working set is the only channel through which the system can rebuild the Favorites
    // and tag lists, so it has to be enumerable. Leaving it closed meant a favorite survived
    // only as long as the Files app process stayed alive.
    BOOL isSystemContainer = [containerItemIdentifier isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier]
                          || [containerItemIdentifier isEqualToString:NSFileProviderRootContainerItemIdentifier];
    if (!isSystemContainer) {
        SeafItem *item = [[SeafItem alloc] initWithItemIdentity:containerItemIdentifier];
        if (item.isAccountRoot && item.isTouchIdEnabled && error) {
            *error = [NSError fileProvierErrorNotAuthenticated];
        }
    }
    SeafEnumerator *enumerator = [[SeafEnumerator alloc] initWithItemIdentifier:containerItemIdentifier];

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
            [self removeProvidingItem:localURL];
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
            SeafItem *newItem = [SeafItem fromSeafBase:renamedFile];
            // The identifier is path-derived, so a rename changes it: carry the persisted
            // favorite/tag metadata over and drop stale descendant entries, or the old
            // identifier survives as a working-set zombie.
            BOOL movedMeta = [self moveLocalMetadataFromItem:item toItem:newItem];
            if (!item.isFile) {
                movedMeta = [self purgeLocalMetadataForItem:item includeDescendants:YES] || movedMeta;
            }
            if (movedMeta) {
                [self signalEnumerator:@[NSFileProviderWorkingSetContainerItemIdentifier]];
            }
            SeafProviderItem *renamedItem = [[SeafProviderItem alloc] initWithSeafItem:newItem];
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
                    [self moveLocalMetadataFromItem:item toItem:renamedItem];
                    if (!item.isFile) {
                        [self purgeLocalMetadataForItem:item includeDescendants:YES];
                    }
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
            [self moveLocalMetadataFromItem:item toItem:newItem];
            if (!item.isFile) {
                [self purgeLocalMetadataForItem:item includeDescendants:YES];
            }
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
            // Drop the item's (and its descendants') persisted favorite/tag metadata, or the
            // working set keeps re-reporting a favorite whose target no longer exists.
            [self purgeLocalMetadataForItem:item includeDescendants:YES];
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
    // The acknowledgement below must carry the current favorite rank: fileproviderd merges
    // the returned item into its record, and a nil rank there reads as "unfavorited".
    [item applyLocalMetadataFromStore:[SeafItem localMetadataStore]];
    [item setTagData:tagData];
    if (tagData && tagData.length > 0) {
        [self saveToLocal:item];
    } else {
        [self removeLocalAttribute:@"tagData" forItem:item];
    }
    [self clearCachesForIdentifier:item.itemIdentifier];
    SeafProviderItem *tagedItem = [[SeafProviderItem alloc] initWithSeafItem:item];
    // A plain container's change enumeration only delivers queued items; signaling the
    // parent without queueing answers it with an empty diff and consumes the anchor, so
    // an observer browsing the folder would never learn about the tag change.
    [SeafFileProviderUtility.shared saveUpdateItem:tagedItem];
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

    if (item.isRoot) {
        Warning("Cannot favorite unresolvable identifier: %@", itemIdentifier);
        return completionHandler(nil, [NSError fileProvierErrorNoSuchItem]);
    }
    // Mirror the working-set membership filter in SeafEnumerator: accepting a favorite the
    // working set can never list (an account root decodes with no repo and no path) would
    // persist an entry that silently vanishes on relaunch and holds the resync open.
    if (favoriteRank && !item.isRepoRoot && item.path.length == 0) {
        Warning("Cannot favorite non-persistable item: %@", itemIdentifier);
        return completionHandler(nil, [NSError fileProvierErrorNoSuchItem]);
    }
    // A Touch ID protected account's content is gated at its root; a favorite would hand
    // out a bookmark that walks around that gate, so refuse to create one.
    if (favoriteRank && item.isTouchIdEnabled) {
        Warning("Refusing favorite on Touch ID protected account: %@", itemIdentifier);
        return completionHandler(nil, [NSError fileProvierErrorNotAuthenticated]);
    }

    [item applyLocalMetadataFromStore:[SeafItem localMetadataStore]];
    [item setFavoriteRank:favoriteRank];
    if (favoriteRank) {
        [self removeConflictingFavoritesForItem:item];
        // Register the slug before the Files app takes a coordinated read on the URL.
        [SeafFileProviderUtility.shared storageSlugForIdentifier:item.itemIdentifier];
        // Persisting the favorite checks that the path the system has recorded for the item
        // exists — after an upgrade that record may still be the legacy encoded path from
        // the old build, and a failed check drops the favorite silently, without a
        // coordinated read that would let the extension materialize on demand. Create both
        // candidate directories up front.
        if (!item.isFile) {
            [self materializeContainerDirectoryAtURL:[self URLForItemWithPersistentIdentifier:item.itemIdentifier]];
        }
        NSURL *legacyURL = [self legacyStorageURLForContainerIdentifier:item.itemIdentifier];
        if (legacyURL) {
            [self materializeContainerDirectoryAtURL:legacyURL];
        }
        // convertToDict resolves and persists the display name, which is what allows the
        // favorite to be rebuilt before the library list has loaded.
        [self saveToLocal:item];
    } else {
        [self removeLocalAttribute:@"favoriteRank" forItem:item];
        // The identifier deliberately stays in the reported baseline: the next working-set
        // change enumeration diffs it against the rebuilt members and reports the deletion,
        // backing up the acknowledgement below in case that reply is lost. The enumerators
        // are the only writers of the baseline, so favoriting cannot race their rebuilds.
    }

    // The cached provider item still carries the old rank.
    [self clearCachesForIdentifier:item.itemIdentifier];

    SeafProviderItem *favoriteItem = [[SeafProviderItem alloc] initWithSeafItem:item];
    // Browse listings report the rank too (it drives the context menu's Unfavorite state),
    // and the parent container's change enumeration only delivers queued items — same
    // queue-before-signal contract as setTagData above.
    [SeafFileProviderUtility.shared saveUpdateItem:favoriteItem];
    [self signalEnumerator:@[favoriteItem.parentItemIdentifier, NSFileProviderWorkingSetContainerItemIdentifier]];

    // Returning the updated item is the authoritative acknowledgement: fileproviderd merges
    // the returned rank into its record of the item. The working set diff alone only reports
    // that the item left the set, which does not clear the rank that a browse enumeration
    // reported earlier, so the sidebar favorite would survive an unfavorite without this.
    // (The historical double-entry this used to cause came from the slash/no-slash identifier
    // split, not from returning the item.)
    completionHandler(favoriteItem, nil);
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
        if ([sfile isImageFile] || [sfile isPdfFile] || [sfile isVideoFile] || [sfile isSdocFile]) {
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
                        NSString *thumbFilePath = weakFile.oid ? [weakFile thumbPath:weakFile.oid] : nil;
                        if (!thumbFilePath) {
                            thumbFilePath = [SeafStorage.sharedObject.thumbsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@-%lld", weakFile.name, weakFile.mtime]];
                        }
                        NSData *imageData = [NSData dataWithContentsOfFile:thumbFilePath];
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
    SeafFileProviderUtility.shared.currentAnchor += 1;
    for (NSString *identifier in itemIdentifiers) {
        [NSFileProviderManager.defaultManager signalEnumeratorForContainerItemIdentifier:identifier completionHandler:^(NSError * _Nullable error) {
            if (error) {
                Debug("signalEnumerator itemIdentifier: %@ error: %@", identifier, error);
            }
        }];
    }
}

/// Drops stale favorites that are another encoding of the same server item, or that never
/// resolved to a server path. A favorite that merely shares the display name is a different
/// folder (two repos can each hold a "Camera Uploads") and must survive.
- (void)removeConflictingFavoritesForItem:(SeafItem *)item {
    NSFileProviderItemIdentifier identifier = item.itemIdentifier;
    @synchronized(self) {
        NSDictionary *store = [SeafItem localMetadataStore];
        if (store.count == 0) return;

        NSMutableDictionary *filesStorage = [NSMutableDictionary dictionaryWithDictionary:store];
        BOOL changed = NO;
        for (NSString *key in [store.allKeys copy]) {
            NSDictionary *dict = [store objectForKey:key];
            if (![dict isKindOfClass:[NSDictionary class]] || ![dict objectForKey:@"favoriteRank"]) {
                continue;
            }

            NSFileProviderItemIdentifier canonicalKey = [SeafItem canonicalIdentifier:key];
            if ([canonicalKey isEqualToString:identifier]) {
                continue;
            }

            SeafItem *other = [SeafItem itemFromDict:dict];
            // Identity is account-scoped: two accounts sharing a library see the same
            // repoId/path, and favoriting through one must not tear down the other's entry.
            BOOL sameServerItem = other.server.length > 0 && [other.server isEqualToString:item.server]
                && (other.username == item.username || [other.username isEqualToString:item.username])
                && other.repoId.length > 0 && [other.repoId isEqualToString:item.repoId]
                && other.path.length > 0 && [other.path isEqualToString:item.path]
                && (other.filename == item.filename || [other.filename isEqualToString:item.filename]);
            BOOL unresolved = other.isRoot || (!other.isRepoRoot && other.path.length == 0);
            if (!sameServerItem && !unresolved) {
                continue;
            }

            NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:dict];
            [updated removeObjectForKey:@"favoriteRank"];
            NSData *tagData = [updated objectForKey:@"tagData"];
            if (tagData.length > 0) {
                [filesStorage setObject:updated forKey:canonicalKey];
            } else {
                [filesStorage removeObjectForKey:canonicalKey];
                if (![canonicalKey isEqualToString:key]) {
                    [filesStorage removeObjectForKey:key];
                }
            }
            changed = YES;
        }

        if (changed) {
            [SeafStorage.sharedObject setObject:filesStorage forKey:SEAF_FILE_PROVIDER];
        }
    }
}

/// Whether a store key names the given container or anything beneath it. A descendant
/// folder extends the encoded path with a percent-encoded separator; a file directly
/// inside it appends a plain "/" plus its name component.
- (BOOL)storeKey:(NSString *)key coversIdentifier:(NSFileProviderItemIdentifier)identifier {
    NSString *canonicalKey = [SeafItem canonicalIdentifier:key];
    if ([canonicalKey isEqualToString:identifier]) return YES;
    return [canonicalKey hasPrefix:[identifier stringByAppendingString:@"%2F"]]
        || [canonicalKey hasPrefix:[identifier stringByAppendingString:@"/"]];
}

/// Drops the persisted metadata for a removed item (and, for a container, everything
/// beneath it). Without this a deleted favorite keeps re-materializing as a working-set
/// zombie: still in members, still in the baseline, never diffed as deleted.
- (BOOL)purgeLocalMetadataForItem:(SeafItem *)item includeDescendants:(BOOL)includeDescendants {
    NSFileProviderItemIdentifier identifier = item.itemIdentifier;
    if (identifier.length == 0) return NO;

    BOOL changed = NO;
    @synchronized(self) {
        NSDictionary *store = [SeafItem localMetadataStore];
        if (store.count == 0) return NO;

        NSMutableDictionary *filesStorage = [NSMutableDictionary dictionaryWithDictionary:store];
        for (NSString *key in store) {
            BOOL matches = includeDescendants
                ? [self storeKey:key coversIdentifier:identifier]
                : [[SeafItem canonicalIdentifier:key] isEqualToString:identifier];
            if (!matches) continue;
            [filesStorage removeObjectForKey:key];
            changed = YES;
        }
        if (changed) {
            [SeafStorage.sharedObject setObject:filesStorage forKey:SEAF_FILE_PROVIDER];
        }
    }
    if (changed) {
        [self clearCachesForIdentifier:identifier];
    }
    return changed;
}

/// Carries an item's persisted favorite/tag metadata across a rename or move, so the
/// favorite follows the item instead of surviving as a zombie under the old identifier.
/// The old identifier is left in the reported baseline; the next working-set diff then
/// reports its node as deleted.
- (BOOL)moveLocalMetadataFromItem:(SeafItem *)oldItem toItem:(SeafItem *)newItem {
    NSFileProviderItemIdentifier oldId = oldItem.itemIdentifier;
    NSFileProviderItemIdentifier newId = newItem.itemIdentifier;
    if (oldId.length == 0 || newId.length == 0 || [oldId isEqualToString:newId]) return NO;

    // Built outside the lock: resolving the name and tag data can hit the disk.
    NSDictionary *identityDict = [newItem convertToDict];

    @synchronized(self) {
        NSDictionary *store = [SeafItem localMetadataStore];
        NSDictionary *stored = [store objectForKey:oldId];
        if (![stored isKindOfClass:[NSDictionary class]]) return NO;

        NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:stored];
        [entry addEntriesFromDictionary:identityDict];

        NSMutableDictionary *filesStorage = [NSMutableDictionary dictionaryWithDictionary:store];
        [filesStorage removeObjectForKey:oldId];
        [filesStorage setObject:entry forKey:newId];
        [SeafStorage.sharedObject setObject:filesStorage forKey:SEAF_FILE_PROVIDER];
    }
    [self clearCachesForIdentifier:oldId];
    return YES;
}

- (void)saveToLocal:(SeafItem *)item {
    NSFileProviderItemIdentifier identifier = item.itemIdentifier;
    if (identifier.length == 0) return;

    // Built outside the lock: resolving the name and tag data can hit the disk.
    NSDictionary *itemDict = [item convertToDict];

    @synchronized(self) {
        NSMutableDictionary *filesStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER]];
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:itemDict];

        // The favorite rank and the tags arrive through separate callbacks, so keep whatever
        // the incoming item does not carry instead of dropping the other attribute.
        NSDictionary *stored = [filesStorage objectForKey:identifier];
        for (NSString *key in @[@"favoriteRank", @"tagData", @"lastUsedDate", @"name"]) {
            if (![dict objectForKey:key] && [stored objectForKey:key]) {
                [dict setObject:[stored objectForKey:key] forKey:key];
            }
        }

        [filesStorage setObject:dict forKey:identifier];
        // Drop duplicate metadata rows that collapse onto the same canonical identifier.
        for (NSString *key in [filesStorage.allKeys copy]) {
            if ([key isEqualToString:identifier]) {
                continue;
            }
            if ([[SeafItem canonicalIdentifier:key] isEqualToString:identifier]) {
                [filesStorage removeObjectForKey:key];
            }
        }
        [SeafStorage.sharedObject setObject:filesStorage forKey:SEAF_FILE_PROVIDER];
    }
}

/// Drops a single attribute, discarding the whole entry once no favorite or tag is left.
- (void)removeLocalAttribute:(NSString *)key forItem:(SeafItem *)item {
    NSFileProviderItemIdentifier identifier = item.itemIdentifier;
    if (identifier.length == 0) return;

    @synchronized(self) {
        NSMutableDictionary *filesStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER]];
        NSDictionary *stored = [filesStorage objectForKey:identifier];
        if (!stored) return;

        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:stored];
        [dict removeObjectForKey:key];

        NSData *tagData = [dict objectForKey:@"tagData"];
        if (![dict objectForKey:@"favoriteRank"] && tagData.length == 0) {
            [filesStorage removeObjectForKey:identifier];
        } else {
            [filesStorage setObject:dict forKey:identifier];
        }
        [SeafStorage.sharedObject setObject:filesStorage forKey:SEAF_FILE_PROVIDER];
    }
}

- (SeafItem *)readFromLocal:(NSString *)itemIdentifier {
    NSFileProviderItemIdentifier canonicalId = [SeafItem canonicalIdentifier:itemIdentifier];
    NSDictionary *dict = [[SeafItem localMetadataStore] objectForKey:canonicalId];
    return dict ? [SeafItem itemFromDict:dict] : nil;
}

// Add a method to clear all caches
- (void)clearAllCaches {
    [self.urlCache removeAllObjects];
    [self.identifierCache removeAllObjects];
    [self.itemCache removeAllObjects];
}

- (void)clearCachesForIdentifier:(NSString *)identifier {
    NSFileProviderItemIdentifier canonicalId = [SeafItem canonicalIdentifier:identifier];
    // identifierCache is keyed by URL, so resolve the URL before evicting it from urlCache.
    NSURL *cachedURL = [self.urlCache objectForKey:canonicalId];
    if (cachedURL) {
        [self.identifierCache removeObjectForKey:cachedURL];
    }
    [self.urlCache removeObjectForKey:canonicalId];
    [self.itemCache removeObjectForKey:canonicalId];
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
