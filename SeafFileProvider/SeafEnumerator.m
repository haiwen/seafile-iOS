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

@interface SeafEnumerator ()
@property (nonatomic, strong) SeafItem *item;
@property (nonatomic, copy) NSFileProviderItemIdentifier containerItemIdentifier;
@property (nonatomic, assign) NSInteger currentAnchor;
@property (nonatomic, assign) NSInteger maxItemCount;
@end


@implementation SeafEnumerator

- (instancetype)initWithItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier containerItemIdentifier:(NSFileProviderItemIdentifier)containerItemIdentifier currentAnchor:(NSInteger)currentAnchor
{
    SeafEnumerator *enumerator = [self initWithSeafItem:[[SeafItem alloc] initWithItemIdentity:itemIdentifier]];
    enumerator.containerItemIdentifier = containerItemIdentifier;
    enumerator.currentAnchor = currentAnchor;
    return enumerator;
}

- (instancetype)initWithSeafItem:(SeafItem *)item
{
    if (self = [super init]) {
        _item = item;
        _maxItemCount = 20;
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
    
    if (@available(iOS 11.0, *)) {
        if ([_containerItemIdentifier isEqualToString:NSFileProviderRootContainerItemIdentifier]) {
            NSArray *accounts = self.getRootProviderItems;
            if (accounts.count == 0) {
                [observer finishEnumeratingWithError:[NSError fileProvierErrorNoAccount]];
            } else {
                [observer didEnumerateItems:accounts];
                [observer finishEnumeratingUpToPage:nil];
            }
        } else if ([_containerItemIdentifier isEqualToString: NSFileProviderWorkingSetContainerItemIdentifier]) {
            Debug("WorkingSetItemIdentifier %@", _item.itemIdentifier);
            NSMutableArray *items = [NSMutableArray array];
            NSMutableDictionary *filesStorage = [NSMutableDictionary dictionaryWithDictionary:[SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER]];
            for (NSDictionary *dict in filesStorage.allValues) {
                SeafItem *item = [[SeafItem alloc] convertFromDict:dict];
                SeafProviderItem *providerItem = [[SeafProviderItem alloc] initWithSeafItem:item];
                [items addObject:providerItem];
            }
            [observer didEnumerateItems:items];
            [observer finishEnumeratingUpToPage:nil];
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
    if (@available(iOS 11.0, *)) {
        if (NSFileProviderInitialPageSortedByDate == page) {
            [dir reSortItemsByMtime];
        } else {
            [dir reSortItemsByName];
        }
    }
    
    NSInteger numPage = [[NSString stringWithUTF8String:[page bytes]] integerValue];
    NSInteger start = numPage * self.maxItemCount;
    NSInteger stop = start + (self.maxItemCount - 1);

    NSMutableArray *items = [NSMutableArray new];
    NSArray *array = [self getAccessiableSubItems:dir];
    BOOL isLastPage = (stop >= array.count - 1);
    for (NSUInteger idx = start; idx <= stop && idx < array.count; ++idx) {
        SeafBase *obj = [array objectAtIndex:idx];
        [obj loadCache];
        [items addObject: [[SeafProviderItem alloc] initWithSeafItem:[SeafItem fromSeafBase:obj]]];
    }
    resultBlock(items, isLastPage);
}

- (void)enumerateChangesForObserver:(id<NSFileProviderChangeObserver>)observer fromSyncAnchor:(NSFileProviderSyncAnchor)syncAnchor {
    NSMutableArray *itemsUpdate = [NSMutableArray array];
    
    if (@available(iOS 11.0, *)) {
        if (_containerItemIdentifier == NSFileProviderWorkingSetContainerItemIdentifier) {
            NSDictionary *filesStorage = [SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER];
            for (NSDictionary *dict in filesStorage.allValues) {
                SeafItem *item = [[SeafItem alloc] convertFromDict:dict];
                [itemsUpdate addObject:[[SeafProviderItem alloc] initWithSeafItem:item]];
            }
        }
    }
    [observer didUpdateItems:itemsUpdate];
    NSData *currentAnchor = [[NSString stringWithFormat:@"%ld",(long)_currentAnchor] dataUsingEncoding:NSUTF8StringEncoding];
    [observer finishEnumeratingChangesUpToSyncAnchor:currentAnchor moreComing:false];
}

- (void)currentSyncAnchorWithCompletionHandler:(void(^)(_Nullable NSFileProviderSyncAnchor currentAnchor))completionHandler
{
    NSData *currentAnchor = [[NSString stringWithFormat:@"%ld",(long)_currentAnchor] dataUsingEncoding:NSUTF8StringEncoding];
    completionHandler(currentAnchor);
}

@end
