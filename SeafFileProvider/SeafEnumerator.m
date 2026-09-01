//
//  SeafFileProviderEnumerator.m
//  SeafFileProvider
//
//  Created by Wei W on 11/5/17.
//  Copyright © 2017 Seafile. All rights reserved.
//

#import "SeafEnumerator.h"
#import "SeafProviderItem.h"
#import "Debug.h"
#import "SeafGlobal.h"
#import "SeafRepos.h"
#import "NSError+SeafFileProvierError.h"
#import "SeafStorage.h"
#import "SeafFileProviderUtility.h"

/// The metadata store also holds entries written for plain uploads. Only favorites and
/// tagged items are working set members; reporting the rest would put unrelated files in
/// the Files app's Recents and Favorites.
static BOOL SeafIsWorkingSetEntry(NSDictionary *dict) {
    if (![dict isKindOfClass:[NSDictionary class]]) return NO;
    if ([dict objectForKey:@"favoriteRank"]) return YES;
    NSData *tagData = [dict objectForKey:@"tagData"];
    return [tagData isKindOfClass:[NSData class]] && tagData.length > 0;
}

static NSUInteger SeafFavoriteCountInStore(NSDictionary *store) {
    NSUInteger count = 0;
    for (id value in store.allValues) {
        if ([value isKindOfClass:[NSDictionary class]] && [value objectForKey:@"favoriteRank"]) {
            count += 1;
        }
    }
    return count;
}

@interface SeafEnumerator ()
@property (nonatomic, copy) NSFileProviderItemIdentifier itemIdentifier;
@property (nonatomic, strong) SeafItem* item;
@property (nonatomic, assign) NSInteger maxItemCount;
@end


@implementation SeafEnumerator

- (instancetype)initWithItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
{
    self = [super init];
    if (self) {
        // A stale bookmark may still enumerate with a slash-prefixed identifier; comparisons
        // against item parents and system constants must use the canonical form.
        self.itemIdentifier = [SeafItem canonicalIdentifier:itemIdentifier];
        self.item = [[SeafItem alloc] initWithItemIdentity:itemIdentifier];
        [self.item applyLocalMetadataFromStore:[SeafItem localMetadataStore]];
        self.maxItemCount = 20;
    }
    return self;
}

- (void)invalidate
{
    Debug("invalidate %@", self.itemIdentifier);
    _item = nil;
    _itemIdentifier = nil;
}

- (void)enumerateItemsForObserver:(id<NSFileProviderEnumerationObserver>)observer
                   startingAtPage:(NSFileProviderPage)page
{
    Debug("%@, root:%d accountroot:%d, reporoot:%d ", _item.itemIdentifier, _item.isRoot, _item.isAccountRoot, _item.isRepoRoot);

    if ([_itemIdentifier isEqualToString:NSFileProviderRootContainerItemIdentifier]) {
        NSArray *accounts = self.getRootProviderItems;
        if (accounts.count == 0) {
            [observer finishEnumeratingWithError:[NSError fileProvierErrorNoAccount]];
        } else {
            [observer didEnumerateItems:accounts];
            [observer finishEnumeratingUpToPage:nil];
        }
    } else if ([_itemIdentifier isEqualToString: NSFileProviderWorkingSetContainerItemIdentifier]) {
        Debug("WorkingSetItemIdentifier %@", _item.itemIdentifier);
        NSArray<SeafProviderItem *> *items = [self workingSetItems];
        NSMutableArray *ids = [NSMutableArray array];
        NSUInteger enumerableFavorites = 0;
        for (SeafProviderItem *it in items) {
            [ids addObject:it.itemIdentifier];
            if (it.favoriteRank) enumerableFavorites += 1;
        }
        [observer didEnumerateItems:items];
        [observer finishEnumeratingUpToPage:nil];
        NSUInteger favoritesInStore = SeafFavoriteCountInStore([SeafItem localMetadataStore]);
        if (items.count == 0 && favoritesInStore > 0) {
            // Empty rebuild while the store still holds favorites: keep the previous
            // baseline, the same way the change path refuses to diff in this state, so a
            // later real unfavorite can still be reported as a deletion.
            Warning("Working set rebuild returned 0 items for %lu stored favorites; keeping baseline",
                    (unsigned long)favoritesInStore);
        } else {
            [SeafFileProviderUtility.shared setReportedWorkingSetIdentifiers:ids];
        }
        // Membership is deterministic, so a stored favorite that did not make it into this
        // listing never will: waiting for it would answer SyncAnchorExpired forever.
        if (items.count > 0 || favoritesInStore == 0 || enumerableFavorites == 0) {
            [SeafFileProviderUtility.shared markWorkingSetResyncComplete];
        }
        return;
    } else {
        if (_item.isAccountRoot && _item.isTouchIdEnabled) {
            [observer finishEnumeratingWithError:[NSError fileProvierErrorNotAuthenticated]];
            return;
        }

        if (_item.isFile) {
            [observer didEnumerateItems:@[[[SeafProviderItem alloc] initWithSeafItem:_item]]];
            [observer finishEnumeratingUpToPage:nil];
            return;
        }

        SeafDir *dir = (SeafDir *)[_item toSeafObj];
        [dir loadContentSuccess: ^(SeafDir *d) {
            [self enumerateItemsForObserver:observer startingAtPage:page inSeafDir:d];
        } failure:^(SeafDir *d, NSError *error) {
            if (d.hasCache) {
                [self enumerateItemsForObserver:observer startingAtPage:page inSeafDir:d];
            } else {
                [observer finishEnumeratingWithError:[NSError fileProvierErrorServerUnreachable]];
            }
        }];
    }
}

/**
 * The working set is what the system consults to rebuild Favorites and tags, including after
 * the Files app has been relaunched. It is built from the local metadata store rather than
 * from the server, because the favorite rank only ever exists on the device.
 */
- (NSArray<SeafProviderItem *> *)workingSetItems {
    NSMutableArray *items = [NSMutableArray array];
    NSMutableSet<NSString *> *seenIdentifiers = [NSMutableSet set];
    NSDictionary *store = [SeafItem localMetadataStore];
    for (NSString *key in store) {
        NSDictionary *dict = [store objectForKey:key];
        if (!SeafIsWorkingSetEntry(dict)) continue;

        if (![dict objectForKey:@"itemIdentifier"]) {
            NSMutableDictionary *repaired = [NSMutableDictionary dictionaryWithDictionary:dict];
            [repaired setObject:[SeafItem canonicalIdentifier:key] forKey:@"itemIdentifier"];
            dict = repaired;
        }

        SeafItem *item = [SeafItem itemFromDict:dict];
        if (!item) continue;
        NSString *canonicalId = item.itemIdentifier;
        // Dedup by canonical identifier only. Deduping by display name dropped a
        // legitimately distinct favorite whenever two repos held a same-named folder,
        // and which of the two survived followed the store's dictionary order — so the
        // winner flipped between enumerations and the diff reported a live favorite as
        // deleted. Same-item duplicates all collapse onto one canonical identifier now.
        if ([seenIdentifiers containsObject:canonicalId]) continue;
        if (item.isRoot || (!item.isRepoRoot && item.path.length == 0)) continue;
        // Honor the per-account Touch ID lock: browsing is gated at the account root, and
        // the working set must not hand out favorites that walk around that gate.
        if (item.isTouchIdEnabled) continue;

        [seenIdentifiers addObject:canonicalId];
        [items addObject:[[SeafProviderItem alloc] initWithSeafItem:item]];
    }
    return items;
}

- (void)enumerateItemsForObserver:(id<NSFileProviderEnumerationObserver>)observer startingAtPage:(NSFileProviderPage)page inSeafDir:(SeafDir *)dir {
    [self getItemsFromSeafDir:dir startingAtPage:page result:^(NSArray *items, BOOL isLastPage) {
        [observer didEnumerateItems:items];
        if (isLastPage) {
            [observer finishEnumeratingUpToPage:nil];
        } else {
            NSInteger numPage = [[NSString stringWithUTF8String:[page bytes]] integerValue] + 1;
            NSData *providerPage = [[NSString stringWithFormat:@"%ld", (long)numPage] dataUsingEncoding:NSUTF8StringEncoding];
            [observer finishEnumeratingUpToPage:providerPage];
        }
    }];
}

- (NSArray *)getRootProviderItems
{
    NSMutableArray *items = [NSMutableArray new];
    for (SeafConnection *conn in SeafGlobal.sharedObject.publicAccounts) {
        SeafItem *item = [SeafItem fromAccount:conn];
        [items addObject:[[SeafProviderItem alloc] initWithSeafItem:item]];
    }
    return items;
}

- (NSArray *)getAccessiableSubItems:(SeafDir *)dir
{
    if ([dir isKindOfClass:[SeafRepos class]]) { // for repo, only show those unencryped or password already saved
        NSMutableArray *repos = [NSMutableArray new];
        for (SeafRepo *repo in [(SeafRepos*)dir items]) {
            if (!repo.passwordRequired) {
                [repos addObject:repo];
            }
        }
        return repos;
    }
    return dir.items;
}

- (void)getItemsFromSeafDir:(SeafDir *)dir startingAtPage:(NSFileProviderPage)page result:(void (^)(NSArray *items, BOOL isLastPage))resultBlock {
    if (NSFileProviderInitialPageSortedByDate == page) {
        [dir reSortItemsByMtime];
    } else {
        [dir reSortItemsByName];
    }

    
    NSInteger numPage = [[NSString stringWithUTF8String:[page bytes]] integerValue];
    NSInteger start = numPage * self.maxItemCount;
    NSInteger stop = start + (self.maxItemCount - 1);

    NSMutableArray *items = [NSMutableArray new];
    NSArray *array = [self getAccessiableSubItems:dir];
    BOOL isLastPage = array.count == 0 ? YES : (stop >= array.count - 1);
    // Browse listings carry the favorite rank too: the context menu only offers
    // "Unfavorite" when the enumerated item reports its rank. Duplicate sidebar entries
    // used to come from the slash/no-slash identifier split, not from repeating the rank,
    // so with canonical identifiers the same item resolves to a single node either way.
    NSDictionary *metadataStore = [SeafItem localMetadataStore];
    for (NSUInteger idx = start; idx <= stop && idx < array.count; ++idx) {
        SeafBase *obj = [array objectAtIndex:idx];
        [obj loadCache];
        SeafItem *item = [SeafItem fromSeafBase:obj];
        [item applyLocalMetadataFromStore:metadataStore];
        [items addObject: [[SeafProviderItem alloc] initWithSeafItem:item]];
    }
    resultBlock(items, isLastPage);
}

- (void)enumerateChangesForObserver:(id<NSFileProviderChangeObserver>)observer fromSyncAnchor:(NSFileProviderSyncAnchor)syncAnchor {
    NSMutableArray *itemsUpdate = [NSMutableArray array];
    NSArray<NSFileProviderItemIdentifier> *deletedIdentifiers = @[];


    if ([_itemIdentifier isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier]) {
        if (SeafFileProviderUtility.shared.pendingWorkingSetFullResync) {
            [observer finishEnumeratingWithError:[NSError fileProvierErrorSyncAnchorExpired]];
            return;
        }

        NSDictionary *store = [SeafItem localMetadataStore] ?: @{};
        NSArray<SeafProviderItem *> *members = [self workingSetItems];
        [itemsUpdate addObjectsFromArray:members];

        NSUInteger favoritesInStore = SeafFavoriteCountInStore(store);
        BOOL canDiffDeletions = !(members.count == 0 && favoritesInStore > 0);

        if (canDiffDeletions) {
            // An item that left the working set has to be reported explicitly, otherwise
            // unfavoriting never reaches the system. Diffing against the last reported set
            // survives a process restart, which an in-memory tombstone list would not.
            NSMutableArray *currentIdentifiers = [NSMutableArray arrayWithCapacity:members.count];
            for (SeafProviderItem *item in members) {
                [currentIdentifiers addObject:item.itemIdentifier];
            }
            // Deletions are diffed and reported in canonical form only. fileproviderd
            // normalizes identifiers on the deletion path, so reporting a stale slash-prefixed
            // form as deleted would tear down the live slash-less node with it.
            NSMutableArray *removed = [NSMutableArray array];
            for (NSString *identifier in [SeafFileProviderUtility.shared reportedWorkingSetIdentifiers]) {
                NSString *canonicalId = [SeafItem canonicalIdentifier:identifier];
                if (![currentIdentifiers containsObject:canonicalId] && ![removed containsObject:canonicalId]) {
                    [removed addObject:canonicalId];
                }
            }
            deletedIdentifiers = removed;
            [SeafFileProviderUtility.shared setReportedWorkingSetIdentifiers:currentIdentifiers];
        } else {
            Warning("Skipping working set deletion diff: store has %lu favorites but rebuild returned 0 items",
                    (unsigned long)favoritesInStore);
        }
    }

    // Only the updates belonging to this container, so that enumerating one container does
    // not swallow the updates another container still has to deliver.
    NSArray<SeafProviderItem *> *pending = [SeafFileProviderUtility.shared updateItemsForContainer:_itemIdentifier];
    for (SeafProviderItem *item in pending) {
        Debug(@"allUpdateItem itemIdentifier: %@ parentItemIdentifier: %@",  item.itemIdentifier ,item.parentItemIdentifier);
        [itemsUpdate addObject:item];
    }
    [SeafFileProviderUtility.shared removeUpdateItems:pending];

    if (deletedIdentifiers.count > 0) {
        [observer didDeleteItemsWithIdentifiers:deletedIdentifiers];
    }

    [observer didUpdateItems:itemsUpdate];
    NSData *currentAnchor = [[NSString stringWithFormat:@"%ld",(long)SeafFileProviderUtility.shared.currentAnchor
                             ] dataUsingEncoding:NSUTF8StringEncoding];
    [observer finishEnumeratingChangesUpToSyncAnchor:currentAnchor moreComing:false];
}

- (void)currentSyncAnchorWithCompletionHandler:(void(^)(_Nullable NSFileProviderSyncAnchor currentAnchor))completionHandler
{
    NSData *currentAnchor = [[NSString stringWithFormat:@"%ld",(long)SeafFileProviderUtility.shared.currentAnchor] dataUsingEncoding:NSUTF8StringEncoding];
    completionHandler(currentAnchor);
}

@end
