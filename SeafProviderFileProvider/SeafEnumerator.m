//
//  SeafFileProviderEnumerator.m
//  SeafProviderFileProvider
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
        [observer didEnumerateItems:self.getRootProviderItems];
        [observer finishEnumeratingUpToPage:nil];
        return;
    }

    SeafDir *dir = (SeafDir *)[_item toSeafObj];
    [dir loadContentSuccess: ^(SeafDir *d) {
        if (@available(iOS 11.0, *)) {
            if (NSFileProviderInitialPageSortedByDate == page) {
                [d reSortItemsByMtime];
            } else {
                [d reSortItemsByName];
            }
        }
        [observer didEnumerateItems:[self getSeafDirProviderItems:d]];
        [observer finishEnumeratingUpToPage:nil];
    } failure:^(SeafDir *d, NSError *error) {
        [observer finishEnumeratingWithError:error];
    }];
}

- (NSArray *)getRootProviderItems
{
    NSMutableArray *items = [NSMutableArray new];
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        SeafItem *item = [SeafItem fromAccount:conn];
        [items addObject:[[SeafProviderItem alloc] initWithSeafItem:item]];
    }
    return items;
}

- (NSArray *)getSeafDirProviderItems:(SeafDir *)dir
{
    NSMutableArray *items = [NSMutableArray new];
    for (SeafBase *obj in dir.items) {
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
