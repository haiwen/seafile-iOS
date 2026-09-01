//
//  SeafFileProviderUtility.h
//  SeafFileProvider
//
//  Created by three on 2022/8/8.
//  Copyright © 2022 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <FileProvider/FileProvider.h>
@class SeafProviderItem;

NS_ASSUME_NONNULL_BEGIN

@interface SeafFileProviderUtility : NSObject

/// Backed by persistent storage and monotonically increasing, so the anchor keeps growing
/// across extension launches.
@property (nonatomic, assign) NSInteger currentAnchor;

+(instancetype)shared;

- (void)saveUpdateItem:(SeafProviderItem *)item;

- (NSArray *)allUpdateItems;

/// Pending updates belong to the container that holds the item. Handing the whole list to
/// whichever enumerator asks first makes one container consume another's updates.
- (NSArray *)updateItemsForContainer:(NSFileProviderItemIdentifier)container;

- (void)removeUpdateItems:(NSArray *)items;

/// The working set members last reported to the system. Diffing against this is what lets
/// the provider report deletions after the extension process has been restarted.
- (NSArray<NSFileProviderItemIdentifier> *)reportedWorkingSetIdentifiers;
- (void)setReportedWorkingSetIdentifiers:(nullable NSArray<NSFileProviderItemIdentifier> *)identifiers;

/// YES until a full working-set listing has replaced fileproviderd's pre-upgrade favorites.
@property (nonatomic, assign) BOOL pendingWorkingSetFullResync;
- (void)requestWorkingSetFullResyncIfNeeded;
- (void)markWorkingSetResyncComplete;

/// Short, filesystem-safe directory name for a container identifier's on-disk storage.
- (NSString *)storageSlugForIdentifier:(NSFileProviderItemIdentifier)identifier;

/// Rewrites both slug maps so every identifier is stored in its canonical form. The slugs
/// themselves are left untouched, keeping existing on-disk directories valid.
- (void)rekeyStorageMapsToCanonicalIdentifiers;

/// Reverse lookup for a storage slug, with a fallback for legacy long encoded paths.
- (nullable NSFileProviderItemIdentifier)identifierForStorageSlug:(NSString *)slug;

/// Returns YES when the name matches a persisted storage slug (40-char SHA1 hex).
- (BOOL)isStorageSlug:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
