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
/// The directory it leaves gets a stamp (see directoryStampForRepo:) so a
/// listing of it that was requested earlier is not applied by the main app.
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

#pragma mark main app indexing (SeafFPIndexer)

// The main app feeds metadata it already has (directory listings, starred
// items, search results, uploads, opened files) into the store so Files can
// find those items through the working set. Every method below runs in one
// BEGIN IMMEDIATE transaction and gives up without writing anything when the
// write lock cannot be taken or when the extension changed the affected rows
// after the main app's request started: the extension's view always wins.
// They return YES when at least one row changed (the caller signals then).

/// Keys of the entry dictionaries. Listing entries carry a name, sparse
/// entries a full path. oid (non-empty string), size (>= 0) and mtime (> 0)
/// are optional; a missing value keeps the stored one.
extern NSString * const SeafFPEntryName;
extern NSString * const SeafFPEntryPath;
extern NSString * const SeafFPEntryIsDir;
extern NSString * const SeafFPEntryOid;
extern NSString * const SeafFPEntrySize;
extern NSString * const SeafFPEntryMtime;

/// Current seq read through a private read-only style handle: the file is
/// opened without SQLITE_OPEN_CREATE, no DDL / PRAGMA runs, 200 ms busy
/// timeout, closed right away. -1 when the store does not exist or cannot be
/// read. Never waits behind a write transaction of another store instance
/// (WAL readers do not block), so it may run on the main thread.
+ (long long)currentSeqForDomainIdentifier:(NSString *)domainIdentifier;

/// Applies a complete server listing of one directory. requestStartSeq is the
/// seq read before the request was sent; -1 means unknown, then only rows for
/// unknown paths are inserted (nothing is updated, revived or tombstoned).
/// Gives up when an ancestor was tombstoned after (or, with -1, at all before)
/// the request, when a direct child changed after it, or when a directory
/// stamp along the chain moved past it (an entry was renamed or moved away).
- (BOOL)applyListingOfRepo:(NSString *)repoId
             directoryPath:(NSString *)directoryPath
                   entries:(NSArray<NSDictionary *> *)entries
           requestStartSeq:(long long)requestStartSeq;

/// Writes entries that are not a complete listing (starred items, search
/// results, an upload): missing ancestors are created, siblings are never
/// tombstoned, a stored oid is never replaced by a missing one. Entries that
/// are tombstoned, or sit below a tombstoned directory, are skipped unless
/// allowRevive is YES.
- (BOOL)applySparseEntriesOfRepo:(NSString *)repoId
                         entries:(NSArray<NSDictionary *> *)entries
                     allowRevive:(BOOL)allowRevive;

/// Follows a move the main app made on the server: the records keep their
/// uuid (favorites, tags, downloaded contents survive) and directory subtrees
/// follow. Each moved record's final filename in the destination directory is
/// confirmed against destinationEntries (including server auto-renames on
/// conflicts); ambiguous or occupied targets are skipped. Gives up when the
/// source/destination directory chains or moved subtrees changed after
/// requestStartSeq.
- (BOOL)moveRecordsOfRepo:(NSString *)srcRepoId
            fromDirectory:(NSString *)srcDirectoryPath
                    names:(NSArray<NSString *> *)names
                   toRepo:(NSString *)dstRepoId
              toDirectory:(NSString *)dstDirectoryPath
       destinationEntries:(NSArray<NSDictionary *> *)destinationEntries
          requestStartSeq:(long long)requestStartSeq;

/// Follows a rename the main app made on the server, keeping the uuid.
/// Confirms the final filename on the server from listing (including server
/// auto-renames on conflicts) and validates that the directory and source
/// record (and its subtree) did not change after requestStartSeq.
- (BOOL)renameRecordOfRepo:(NSString *)repoId
                 directory:(NSString *)directoryPath
                  fromName:(NSString *)oldName
                    toName:(NSString *)newName
                   listing:(NSArray<NSDictionary *> *)entries
           requestStartSeq:(long long)requestStartSeq;

/// Activity log operations for applyActivitiesOfRepo:entries:.
extern NSString * const SeafFPEntryOp;        // NSString, one of the values below
extern NSString * const SeafFPEntryOldPath;   // NSString, full path before a move / rename
extern NSString * const SeafFPActivityOpCreate;   // create, edit, recover, publish
extern NSString * const SeafFPActivityOpDelete;
extern NSString * const SeafFPActivityOpMove;     // move and rename (same library)

/// Replays server activity log entries of one library, oldest first. Entries
/// carry op, path, isDir, mtime (the event time) and, for moves, oldPath.
/// The log may lag behind or overlap what the store already knows, so it is
/// applied cautiously:
/// - create: only unknown paths get a row (no update, never a revive);
/// - delete: only when the stored row (and, for a directory, every live row
///   below it) is not newer than the event;
/// - move: the row at oldPath keeps its uuid and moves to path, unless that
///   row is newer than the event (a later file at the old path) or path is
///   taken by another live row; without a row at oldPath it is a create.
- (BOOL)applyActivitiesOfRepo:(NSString *)repoId entries:(NSArray<NSDictionary *> *)entries;

/// Records that the main app opened a file and fills in content information
/// the record lacks. The oid / size are only written when the record has no
/// oid yet (a stored oid is never replaced: it may be newer). lastUsedDate nil:
/// only the fill-in. createIfMissing NO: unknown paths are left alone.
/// Repeated within 60 s without a fill-in: nothing is written. Never revives.
- (BOOL)noteLastUsedDate:(nullable NSDate *)lastUsedDate
                 forRepo:(NSString *)repoId
                    path:(NSString *)path
                     oid:(nullable NSString *)oid
                    size:(long long)size
                   mtime:(long long)mtime
         createIfMissing:(BOOL)createIfMissing;

/// Seq at which an entry was last renamed or moved away from the directory
/// (parentUUID nil: the library root); 0 when never. Exposed for tests.
- (long long)directoryStampForRepo:(NSString *)repoId parentUUID:(nullable NSString *)parentUUID;

@end

NS_ASSUME_NONNULL_END
