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

@interface SeafEnumerator ()
@property (strong) SeafItem *item;
@end


@implementation SeafEnumerator

- (instancetype)initWithItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
{
    return [self initWithSeafItem:[[SeafItem alloc] initWithItemIdentity:itemIdentifier]];
}

- (instancetype)initWithSeafItem:(SeafItem *)item
{
    if (self = [super init]) {
        _item = item;
    }
    return self;
}

- (void)invalidate
{
    Debug("invalidate %@", self.item.itemIdentifier);
}

- (void)enumerateItemsForObserver:(id<NSFileProviderEnumerationObserver>)observer
                   startingAtPage:(NSFileProviderPage)page
{
    Debug("%@, root:%d accountroot:%d, reporoot:%d ", _item.itemIdentifier, _item.isRoot, _item.isAccountRoot, _item.isRepoRoot);
    if (_item.isRoot) {// account list
        NSArray *accounts = self.getRootProviderItems;
        [observer didEnumerateItems:accounts];
        [observer finishEnumeratingUpToPage:nil];
        return;
    }
    
    if (_item.isFile) {
        [observer didEnumerateItems:@[[[SeafProviderItem alloc] initWithSeafItem:_item]]];
        [observer finishEnumeratingUpToPage:nil];
        return;
    }

    SeafDir *dir = (SeafDir *)[_item toSeafObj];
    [dir loadContentSuccess: ^(SeafDir *d) {
        [observer didEnumerateItems:[self getSeafDirProviderItems:d startingAtPage:page]];
        [observer finishEnumeratingUpToPage:nil];
    } failure:^(SeafDir *d, NSError *error) {
        if (d.hasCache) {
            [observer didEnumerateItems:[self getSeafDirProviderItems:dir startingAtPage:page]];
            [observer finishEnumeratingUpToPage:nil];
        } else {
            [observer finishEnumeratingWithError:error];
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

- (NSArray *)getSeafDirProviderItems:(SeafDir *)dir startingAtPage:(NSFileProviderPage)page
{
    if (@available(iOS 11.0, *)) {
        if (NSFileProviderInitialPageSortedByDate == page) {
            [dir reSortItemsByMtime];
        } else {
            [dir reSortItemsByName];
        }
    }

    NSMutableArray *items = [NSMutableArray new];
    for (SeafBase *obj in [self getAccessiableSubItems: dir]) {
        [obj loadCache];
        [items addObject: [[SeafProviderItem alloc] initWithSeafItem:[SeafItem fromSeafBase:obj]]];
    }
    return items;
}

#if 0
- (void)enumerateChangesForObserver:(id<NSFileProviderChangeObserver>)observer
                     fromSyncAnchor:(NSFileProviderSyncAnchor)syncAnchor NS_SWIFT_NAME(enumerateChanges(for:from:))
{

}
- (void)currentSyncAnchorWithCompletionHandler:(void(^)(_Nullable NSFileProviderSyncAnchor currentAnchor))completionHandler
{

}
#endif

@end
