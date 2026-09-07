//
//  SeafFPStore.h
//  SeafFileProvider
//
//  Per-domain sqlite store shared by the extension and the main app:
//  identity table (uuid <-> repo/path), decorations (favorite/tag/lastUsed),
//  container anchors/snapshots and the working set.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Working set membership reasons (bit flags).
typedef NS_OPTIONS(NSInteger, SeafFPWorkingSetReason) {
    SeafFPWorkingSetReasonMaterialized = 1 << 0,
    SeafFPWorkingSetReasonFavorite     = 1 << 1,
    SeafFPWorkingSetReasonTag          = 1 << 2,
    SeafFPWorkingSetReasonMigrated     = 1 << 3,
};

@interface SeafFPRecord : NSObject
@property (nonatomic, copy) NSString *uuid;
@property (nonatomic, copy) NSString *repoId;
@property (nonatomic, copy) NSString *path;      // normalized, includes the file name
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *parentUUID;  // nil: direct child of the library root
@property (nonatomic, copy, nullable) NSString *oid;         // file oid / directory dir_id
@property (nonatomic, assign) BOOL isDir;
@property (nonatomic, assign) BOOL deleted;
@property (nonatomic, assign) long long mtime;
@property (nonatomic, assign) long long size;
@property (nonatomic, assign) long long seq;

- (NSString *)itemIdentifier;        // i:<uuid>
- (NSString *)parentItemIdentifier;  // i:<parentUUID> or r:<repoId>
- (NSString *)directoryPath;         // parent directory path
@end

@interface SeafFPDecoration : NSObject
@property (nonatomic, copy) NSString *itemIdentifier;
@property (nonatomic, strong, nullable) NSNumber *favoriteRank;
@property (nonatomic, strong, nullable) NSData *tagData;
@property (nonatomic, strong, nullable) NSDate *lastUsedDate;
- (BOOL)isEmpty;
@end

@interface SeafFPStore : NSObject

+ (void)removeStoreForDomainIdentifier:(NSString *)domainIdentifier;

- (nullable instancetype)initWithDomainIdentifier:(NSString *)domainIdentifier error:(NSError * _Nullable * _Nullable)error;
- (void)close;
/// NO after close: every query then answers empty, which callers must not
/// mistake for an authoritative answer.
- (BOOL)isOpen;

@property (nonatomic, copy, readonly) NSString *domainIdentifier;

#pragma mark batching

/// Runs the block on the store queue inside one transaction. Store calls made
/// from inside the block run inline (the queue is re-entrant) and share the
/// transaction, so a directory listing costs one queue hop and one commit.
- (void)performBatch:(void (NS_NOESCAPE ^)(void))block;

#pragma mark meta / sequence

- (long long)currentSeq;
- (long long)nextSeq;
- (nullable NSString *)metaValueForKey:(NSString *)key;
- (void)setMetaValue:(nullable NSString *)value forKey:(NSString *)key;

#pragma mark identity

- (nullable SeafFPRecord *)recordForUUID:(NSString *)uuid;
- (nullable SeafFPRecord *)recordForRepo:(NSString *)repoId path:(NSString *)path includeDeleted:(BOOL)includeDeleted;

/// Finds or creates the record for (repoId, path). A tombstoned record is
/// revived. Pass oid nil / mtime 0 / size -1 to keep the stored values.
- (SeafFPRecord *)upsertRecordForRepo:(NSString *)repoId
                                 path:(NSString *)path
                                isDir:(BOOL)isDir
                           parentUUID:(nullable NSString *)parentUUID
                                  oid:(nullable NSString *)oid
                                mtime:(long long)mtime
                                 size:(long long)size;

/// Finds or creates the record for (repoId, path) together with all of its
/// ancestor directories. Used when a path is known but has never been
/// enumerated (legacy favorites migration). Returns nil for the library root.
- (nullable SeafFPRecord *)ensureRecordChainForRepo:(NSString *)repoId path:(NSString *)path isDir:(BOOL)isDir;

/// Live (deleted = 0) children of a directory; parentUUID nil means the library root.
- (NSArray<SeafFPRecord *> *)childRecordsOfRepo:(NSString *)repoId parentUUID:(nullable NSString *)parentUUID;

/// Tombstones the record and, for directories, its whole subtree.
- (void)markDeletedUUID:(NSString *)uuid;
/// Same for several records, in one transaction.
- (void)markDeletedUUIDs:(NSArray<NSString *> *)uuids;

/// The record itself plus, for directories, every record below it (live or tombstoned).
- (NSArray<SeafFPRecord *> *)subtreeRecordsOfUUID:(NSString *)uuid;

/// Records (live or tombstoned) whose seq is greater than the given value,
/// in seq order; `limit` 0 means no limit.
- (NSArray<SeafFPRecord *> *)recordsChangedSinceSeq:(long long)seq;
- (NSArray<SeafFPRecord *> *)recordsChangedSinceSeq:(long long)seq limit:(NSInteger)limit;

/// Live records in uuid order, starting after `uuid` (nil: from the first);
/// at most `limit` rows, 0 means no limit. Pages the working set enumeration.
- (NSArray<SeafFPRecord *> *)liveRecordsAfterUUID:(nullable NSString *)uuid limit:(NSInteger)limit;

/// Renames / moves a record; directory subtrees follow. uuid stays the same.
- (nullable SeafFPRecord *)moveRecordUUID:(NSString *)uuid
                                   toRepo:(NSString *)repoId
                                     path:(NSString *)path
                               parentUUID:(nullable NSString *)parentUUID;

#pragma mark container

- (nullable NSString *)anchorForContainer:(NSString *)containerIdentifier;
- (NSArray<NSString *> *)snapshotForContainer:(NSString *)containerIdentifier;
- (nullable NSDate *)enumeratedAtForContainer:(NSString *)containerIdentifier;
/// enumerated_at of every known container, keyed by identifier.
- (NSDictionary<NSString *, NSDate *> *)enumeratedAtByContainer;
- (void)setAnchor:(nullable NSString *)anchor
         snapshot:(nullable NSArray<NSString *> *)snapshot
     forContainer:(NSString *)containerIdentifier;

#pragma mark decoration

- (nullable SeafFPDecoration *)decorationForItem:(NSString *)itemIdentifier;
/// Stores the decoration; an empty decoration deletes the row.
- (void)setDecoration:(SeafFPDecoration *)decoration;
- (void)removeDecorationForItem:(NSString *)itemIdentifier;
- (NSArray<SeafFPDecoration *> *)allDecorations;

#pragma mark working set

- (NSArray<NSString *> *)workingSetItemIdentifiers;
- (SeafFPWorkingSetReason)workingSetReasonForItem:(NSString *)itemIdentifier;
- (void)addWorkingSetItem:(NSString *)itemIdentifier reason:(SeafFPWorkingSetReason)reason;
/// Clears the given reason bits; the row is removed when no bit is left.
- (void)removeWorkingSetItem:(NSString *)itemIdentifier reason:(SeafFPWorkingSetReason)reason;
- (void)removeWorkingSetItem:(NSString *)itemIdentifier;
/// Working set rows whose seq is greater than the given value (favorite / tag changes).
- (NSArray<NSString *> *)workingSetItemIdentifiersChangedSinceSeq:(long long)seq;
/// Sets the "materialized" reason on exactly the given items and clears it
/// everywhere else. Does not advance seq: the system already knows these items.
- (void)replaceMaterializedItemIdentifiers:(NSArray<NSString *> *)identifiers;

@end

NS_ASSUME_NONNULL_END
