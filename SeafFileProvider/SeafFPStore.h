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

/// Matches the numbered alternatives the server can assign to an occupied name.
FOUNDATION_EXPORT BOOL SeafFPIsConflictSiblingName(NSString *candidate, NSString *expected);

/// Working set membership reasons (bit flags).
typedef NS_OPTIONS(NSInteger, SeafFPWorkingSetReason) {
    SeafFPWorkingSetReasonMaterialized = 1 << 0,
    SeafFPWorkingSetReasonFavorite     = 1 << 1,
    SeafFPWorkingSetReasonTag          = 1 << 2,
    SeafFPWorkingSetReasonMigrated     = 1 << 3,
};

/// Why a row is a tombstone (0 while it is live).
typedef NS_ENUM(NSInteger, SeafFPTombReason) {
    SeafFPTombReasonNone = 0,
    SeafFPTombReasonAbsent = 1,     // a fresh listing no longer showed it: a later rename may bring it back
    SeafFPTombReasonLocal = 2,      // deleted or retired on this device
    SeafFPTombReasonReplaced = 3,   // another row took its path (or its identity was merged away)
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
@property (nonatomic, assign) long long createdSeq;           // seq the row was inserted with; 0 for rows from before schema 2
@property (nonatomic, assign) SeafFPTombReason tombReason;    // deleted rows only
@property (nonatomic, assign) long long tombTxn;              // deleted rows: store seq when the tombstoning transaction began

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

/// One page of the full working set scan, read in one transaction. The scan
/// orders rows by path depth, directories before files, then seq and uuid, so
/// a parent always comes before its children.
@interface SeafFPWorkingSetPage : NSObject
/// Live rows after the cursor, in scan order.
@property (nonatomic, copy) NSArray<SeafFPRecord *> *records;
/// Every ancestor row of `records` by uuid, live or not; a uuid without a row is missing.
@property (nonatomic, copy) NSDictionary<NSString *, SeafFPRecord *> *ancestors;
@property (nonatomic, copy) NSDictionary<NSString *, NSDictionary *> *repositories;
@property (nonatomic, copy) NSDictionary<NSString *, SeafFPDecoration *> *decorations;
/// The store seq when the page was read.
@property (nonatomic, assign) long long sequence;
@property (nonatomic, assign) BOOL moreComing;
@end

/// One consistent, bounded change batch from all public File Provider streams.
@interface SeafFPPublicationBatch : NSObject
@property (nonatomic, copy) NSArray<SeafFPRecord *> *records;
@property (nonatomic, copy) NSArray<NSString *> *decorationIdentifiers;
@property (nonatomic, copy) NSArray<NSDictionary *> *repositoryEvents;
@property (nonatomic, copy) NSDictionary<NSString *, NSDictionary *> *repositories;
@property (nonatomic, copy) NSDictionary<NSString *, SeafFPDecoration *> *decorations;
@property (nonatomic, assign) long long sequence;
@property (nonatomic, assign) BOOL moreComing;
@end

/// A directory the main app still has to list.
@interface SeafFPDirectoryCheck : NSObject
@property (nonatomic, copy) NSString *repoId;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) long long version;   // a listing whose request started at or after it confirms the check
@property (nonatomic, assign) NSInteger attempts;  // failed listings since the check was last asked for
@property (nonatomic, assign) NSInteger denials;   // of those, answered with 403
@end

/// Outcome of an index write.
typedef NS_ENUM(NSInteger, SeafFPWriteResult) {
    SeafFPWriteFailed = -1,     // nothing written: store busy, a statement failed, rolled back
    SeafFPWriteUnchanged = 0,   // committed, no row changed
    SeafFPWriteChanged = 1,     // committed with changes
};

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
/// NO when a statement failed (then nothing of the block is committed) or
/// COMMIT failed.
- (BOOL)performBatch:(void (NS_NOESCAPE ^)(void))block;

#pragma mark meta / sequence

- (long long)currentSeq;
- (long long)nextSeq;
- (nullable NSString *)metaValueForKey:(NSString *)key;
- (void)setMetaValue:(nullable NSString *)value forKey:(NSString *)key;

#pragma mark public File Provider publication

/// Reserve a distinct, persistent request boundary before fetching libraries.
/// Unlike currentSeq, two overlapping requests never share this value.
- (long long)beginRepositoryRequest;
/// Snapshots contain repoId/name/perm/editable/mtime/ooid/locked. Only a
/// complete, fresh list may confirm absence. Cached/unknown-time data cannot
/// replace a newer accepted state. No identity or decoration is deleted.
/// Network requests use beginRepositoryRequest, not a currentSeq read, so
/// unchanged and overlapping responses have a reliable ordering boundary.
- (BOOL)applyRepositorySnapshot:(NSArray<NSDictionary *> *)repositories
                      complete:(BOOL)complete
                     fromCache:(BOOL)fromCache
               requestStartSeq:(long long)requestStartSeq;
/// Distinguishes a failed transaction from an accepted or superseded snapshot.
- (SeafFPWriteResult)applyRepositorySnapshotResult:(NSArray<NSDictionary *> *)repositories
                                         complete:(BOOL)complete fromCache:(BOOL)fromCache
                                   requestStartSeq:(long long)requestStartSeq;
/// nil if the publication state cannot be read; an empty dictionary is valid.
- (nullable NSDictionary<NSString *, NSDictionary *> *)repositoryStates;
- (BOOL)hasAuthoritativeRepositoryList;
/// Advances at most limit child records and commits the resumable cursor.
- (BOOL)publishPendingRepositoryRecordsWithLimit:(NSUInteger)limit;
- (BOOL)hasPendingRepositoryPublications;
- (nullable SeafFPPublicationBatch *)publicationBatchAfterSequence:(long long)sequence limit:(NSUInteger)limit;
/// Up to `limit` rows of the full working set scan after the position of the
/// last row of the previous page (uuid nil: the first page). Each page stands
/// on its own: the system asks for the next one on a new enumerator, possibly
/// in a new process, so the position is all a page has to go on.
- (nullable SeafFPWorkingSetPage *)workingSetPageAfterDepth:(NSUInteger)depth
                                                      isDir:(BOOL)isDir
                                                        seq:(long long)seq
                                                       uuid:(nullable NSString *)uuid
                                                      limit:(NSUInteger)limit;

/// Persisted notification request, separate from item change sequence numbers.
- (BOOL)requestWorkingSetSignal;
- (long long)pendingWorkingSetSignalTicket;
- (BOOL)completeWorkingSetSignalTicket:(long long)ticket;
/// Opens an existing store only. Used by delayed notification callbacks so a
/// removed domain's store is never created by a retry.
+ (nullable instancetype)openExistingStoreForDomainIdentifier:(NSString *)identifier;

#pragma mark identity

- (nullable SeafFPRecord *)recordForUUID:(NSString *)uuid;
/// failed (optional): set when the row could not be read, as opposed to not being there.
- (nullable SeafFPRecord *)recordForUUID:(NSString *)uuid failed:(nullable BOOL *)failed;
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
/// Retires an indexed occupant after a fresh preflight found its name free.
- (long long)prepareFileCreationInRepo:(NSString *)repoId path:(NSString *)path requestStartSeq:(long long)start;
/// Records a successful creation at a name the server listing showed free.
- (nullable SeafFPRecord *)recordCreatedFileInRepo:(NSString *)repoId
                                            path:(NSString *)path
                                      parentUUID:(nullable NSString *)parentUUID
                                             oid:(NSString *)oid
                                           mtime:(long long)mtime
                                            size:(long long)size
                                 requestStartSeq:(long long)requestStartSeq
                                      serverTime:(long long)serverTime;

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
/// at most `limit` rows, 0 means no limit. nil when the read failed.
- (nullable NSArray<SeafFPRecord *> *)liveRecordsAfterUUID:(nullable NSString *)uuid limit:(NSInteger)limit;

/// Renames / moves a record; directory subtrees follow. uuid stays the same.
/// The directory it leaves gets a stamp (see directoryStampForRepo:) so a
/// listing of it that was requested earlier is not applied by the main app.
- (nullable SeafFPRecord *)moveRecordUUID:(NSString *)uuid
                                   toRepo:(NSString *)repoId
                                     path:(NSString *)path
                               parentUUID:(nullable NSString *)parentUUID;
/// Files confirmed the server move. Reconciles only an occupant discovered
/// after the operation began, and only at the confirmed destination.
- (nullable SeafFPRecord *)confirmMoveOfRecord:(SeafFPRecord *)source
                                       toRepo:(NSString *)repoId
                                         path:(NSString *)path
                                   parentUUID:(nullable NSString *)parentUUID
                              requestStartSeq:(long long)requestStartSeq;
- (nullable SeafFPRecord *)confirmMoveOfRecord:(SeafFPRecord *)source
                                       toRepo:(NSString *)repoId
                                         path:(NSString *)path
                                   parentUUID:(nullable NSString *)parentUUID
                              requestStartSeq:(long long)requestStartSeq
                                   serverTime:(long long)serverTime;
- (nullable SeafFPRecord *)finishPendingMoveOfRecord:(SeafFPRecord *)source toRepo:(NSString *)repoId path:(NSString *)path
                                          parentUUID:(nullable NSString *)parentUUID requestStartSeq:(long long)start
                                          serverTime:(long long)serverTime;
/// Reserves the source UUID and expected target before sending a server mutation.
/// requestedName is the Files filename change, if any, before conflict resolution.
- (long long)beginMoveOfRecord:(SeafFPRecord *)record toRepo:(NSString *)repoId directory:(NSString *)directoryPath
                   parentUUID:(nullable NSString *)parentUUID expectedName:(NSString *)name
                requestedName:(nullable NSString *)requestedName
       existingDestinationNames:(NSArray<NSString *> *)existingDestinationNames;
/// Also retains the pre-dispatch occupants, keyed by canonical filename, so
/// a reused conflict name can be distinguished by its original content id.
- (long long)beginMoveOfRecord:(SeafFPRecord *)record toRepo:(NSString *)repoId directory:(NSString *)directoryPath
                   parentUUID:(nullable NSString *)parentUUID expectedName:(NSString *)name
                requestedName:(nullable NSString *)requestedName
       existingDestinationNames:(NSArray<NSString *> *)existingDestinationNames
     existingDestinationEntries:(nullable NSDictionary<NSString *, NSDictionary *> *)existingDestinationEntries;
- (BOOL)noteMoveReceiptForUUID:(NSString *)uuid requestStartSeq:(long long)start serverTime:(long long)serverTime;
- (BOOL)discardUnconfirmedMoveForUUID:(NSString *)uuid requestStartSeq:(long long)start;
/// Drops the item's move journal and the destination it reserved, whatever
/// its state, after explicit deletion or other definitive cancellation.
- (BOOL)discardMoveJournalForUUID:(NSString *)uuid;
/// YES when the journal's destination reservation has expired: 7 days for a
/// move the server acknowledged, one hour for one it never answered.
/// The recovery evidence itself must survive until the move is resolved.
+ (BOOL)moveJournalExpired:(NSDictionary *)recovery now:(long long)now;
/// YES after the one-hour settle window. Journals without a start time count as elapsed.
+ (BOOL)moveSettleGraceElapsed:(NSDictionary *)recovery now:(long long)now;
/// Stops waiting for a move past its settle grace: drops the journal and the
/// reservation it holds, acknowledged or not. The caller lists the source
/// directory into the store first. NO when the journal is no longer
/// `expected` (replaced, settled or receipted meanwhile) or on failure.
- (BOOL)expireMoveForUUID:(NSString *)uuid matchingRecovery:(NSDictionary *)expected;
/// Adopts the content id a fresh listing shows for the record at its current
/// path (same name and type); the identity is unchanged. nil when the record
/// moved, its sequence changed since the preflight began, or a write failed.
- (nullable SeafFPRecord *)refreshContentOfRecord:(SeafFPRecord *)record oid:(nullable NSString *)oid mtime:(long long)mtime size:(long long)size;
/// A pending move whose local identity still needs resolution.
/// Empty when absent, nil on read failure. needsResolution=YES indicates an
/// isolated damaged journal; preserve local edits and require manual handling.
- (nullable NSDictionary *)moveRecoveryForUUID:(NSString *)uuid;
- (BOOL)rememberMoveOfRecord:(SeafFPRecord *)record
                       toRepo:(NSString *)repoId
                    directory:(NSString *)directoryPath
                   parentUUID:(nullable NSString *)parentUUID
                 expectedName:(NSString *)name
              requestStartSeq:(long long)requestStartSeq
                   serverTime:(long long)serverTime;
- (nullable NSString *)confirmedNameForRecord:(SeafFPRecord *)record
                                     expected:(NSString *)expected
                                       inRepo:(NSString *)repoId
                                    directory:(NSString *)directoryPath
                                      entries:(NSArray<NSDictionary *> *)entries
                              requestStartSeq:(long long)requestStartSeq;

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
/// the request, or when a directory stamp along the chain moved past it (an
/// entry was renamed or moved away). Children written after the request are
/// left as they are; the others are updated, revived or tombstoned (reason
/// Absent). A fresh listing confirms the directory checks registered before
/// its request started, in the same transaction.
/// Unknown-time cached listings cannot recreate paths vacated by a move or
/// rename; a fresh server listing is required to reuse those paths.
- (BOOL)applyListingOfRepo:(NSString *)repoId
             directoryPath:(NSString *)directoryPath
                   entries:(NSArray<NSDictionary *> *)entries
           requestStartSeq:(long long)requestStartSeq;
/// The same, telling a failed (or rejected) listing from one that changed nothing.
- (SeafFPWriteResult)applyDirectoryListingOfRepo:(NSString *)repoId
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

/// Activity log entries for recordActivityEntries:progress:.
extern NSString * const SeafFPEntryOp;        // NSString, one of the values below
extern NSString * const SeafFPEntryOldPath;   // NSString, full path before a move / rename
extern NSString * const SeafFPEntryRepoId;    // NSString, the entry's library
extern NSString * const SeafFPEntryActivityHash;   // NSString, identifies the activity the entry came from
extern NSString * const SeafFPActivityOpCreate;   // create, recover, restore, publish
extern NSString * const SeafFPActivityOpEdit;
extern NSString * const SeafFPActivityOpDelete;
extern NSString * const SeafFPActivityOpMove;     // move and rename (same library)

/// Records one page of the activity log in one transaction. The log is only
/// a hint of where something changed: no identity is created, moved or
/// deleted here. Entries of an activity (same hash) seen before are skipped;
/// the others ask for a fresh listing of the affected directories (a delete
/// only when the path has a live row) and same-library moves become rename
/// hints, decided later. `progress` (the collector's position, a JSON object)
/// is stored in the same transaction; its `boundary` prunes seen activities.
/// Changed when at least one entry was recorded.
- (SeafFPWriteResult)recordActivityEntries:(NSArray<NSDictionary *> *)entries progress:(nullable NSDictionary *)progress;
/// The progress last stored by recordActivityEntries:progress:; empty when
/// none, nil when it cannot be read.
- (nullable NSDictionary *)activityProgress;
/// Entries of one library without activity hashes (each entry is its own
/// activity). YES when something was recorded.
- (BOOL)applyActivitiesOfRepo:(NSString *)repoId entries:(NSArray<NSDictionary *> *)entries;

/// Directories with a pending check (a fresh listing is needed).
- (NSArray<NSString *> *)activityRecheckDirectoryPathsOfRepo:(NSString *)repoId;

/// Asks for a fresh listing of a directory (a new version: a listing already
/// in flight does not confirm it).
- (BOOL)requestDirectoryCheckOfRepo:(NSString *)repoId path:(NSString *)path;
/// Checks whose retry time has come, least tried first; nil when unreadable.
/// repoIds: only these libraries (nil: all).
- (nullable NSArray<SeafFPDirectoryCheck *> *)dueDirectoryChecksAt:(NSDate *)date limit:(NSUInteger)limit;
- (nullable NSArray<SeafFPDirectoryCheck *> *)dueDirectoryChecksAt:(NSDate *)date limit:(NSUInteger)limit repoIds:(nullable NSArray<NSString *> *)repoIds;
/// When the next deferred check becomes due; nil when none is waiting.
- (nullable NSDate *)nextDirectoryCheckDate;
- (nullable NSDate *)nextDirectoryCheckDateOfRepos:(nullable NSArray<NSString *> *)repoIds;
/// The calls below leave a check alone that was asked for again since `check`
/// was read (its version moved): the newer request still needs its listing.
/// A failed listing: try again at `date`.
- (BOOL)deferDirectoryCheck:(SeafFPDirectoryCheck *)check until:(NSDate *)date status:(NSInteger)status;
/// The directory is gone on the server: its parent's listing answers the check.
- (BOOL)moveDirectoryCheckToParent:(SeafFPDirectoryCheck *)check;
- (BOOL)dropDirectoryCheck:(SeafFPDirectoryCheck *)check;
/// The library is gone: its checks and rename hints with it.
- (BOOL)dropDirectoryChecksOfRepo:(NSString *)repoId;

/// Decides collected rename hints, oldest first per library; call it when no
/// activity scan is in progress (an unfinished scan may still bring older
/// hints). The record at the old path -- live, or tombstoned because a
/// listing no longer showed it -- keeps its identity at the new path together
/// with its subtree; a row a listing already created at the new path for the
/// same item gives up its identity (its favorite and tags move over). The
/// hint is dropped when the old row is a later entry, the target is taken by
/// an older row, or the target directory is gone. For a day afterwards a
/// listing that shows a carried row back at the old path with the same
/// content id restores it there.
- (SeafFPWriteResult)decideRenameHintsWithLimit:(NSUInteger)limit;
/// Collected hints not decided yet.
- (NSUInteger)pendingRenameHintCount;

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
