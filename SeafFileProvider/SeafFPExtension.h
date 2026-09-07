//
//  SeafFPExtension.h
//  SeafFileProvider
//
//  Principal class of the replicated File Provider extension. One instance
//  per NSFileProviderDomain, one domain per Seafile account. The system owns
//  the on-disk replica; this class only translates between Seafile's model
//  and NSFileProviderItem.
//

#import <Foundation/Foundation.h>
#import <FileProvider/FileProvider.h>

@class SeafConnection;
@class SeafRepo;
@class SeafDir;
@class SeafFile;
@class SeafFPStore;
@class SeafFPRecord;
@class SeafFPItem;

NS_ASSUME_NONNULL_BEGIN

@interface SeafFPExtension : NSObject <NSFileProviderReplicatedExtension, NSFileProviderThumbnailing>

@property (nonatomic, strong, readonly) NSFileProviderDomain *domain;
@property (nonatomic, strong, readonly) NSFileProviderManager *manager;
// Read from enumerator callbacks on several threads while invalidate / the
// re-login check may replace them: atomic on purpose.
@property (strong, readonly, nullable) SeafConnection *connection;
@property (strong, readonly, nullable) SeafFPStore *store;

#pragma mark Helpers shared with the enumerator

/// nil when the account exists, is not Touch ID protected and the store is
/// open; enough for reads of local state (items, decorations).
- (nullable NSError *)localAccessError;
/// localAccessError plus a signed-in session: needed for server requests.
- (nullable NSError *)accessError;

/// Builds the item for any identifier from local state (store / cached
/// library list). Never touches the network.
- (nullable SeafFPItem *)resolveItem:(NSFileProviderItemIdentifier)identifier error:(NSError * _Nullable * _Nullable)error;
- (SeafFPItem *)itemForRepo:(SeafRepo *)repo;
- (SeafFPItem *)itemForRecord:(SeafFPRecord *)record;

- (nullable SeafRepo *)repoWithId:(NSString *)repoId;
/// The library list of a fresh extension process is empty until the SDK
/// cache or the server answered; before that a library must not be reported
/// as missing. known: the list is available (possibly empty); fromNetwork:
/// it came from the server just now.
- (void)ensureRepoListLoaded:(void (^)(BOOL known, BOOL fromNetwork))completion;
/// YES when the library is not in a list that has not been loaded yet.
- (BOOL)repoListUnknownFor:(nullable NSString *)repoId;
- (BOOL)isRepoEditable:(NSString *)repoId;
- (nullable SeafDir *)seafDirForContainer:(NSFileProviderItemIdentifier)containerIdentifier
                                   record:(SeafFPRecord * _Nullable * _Nullable)outRecord;
- (nullable SeafFile *)seafFileForRecord:(SeafFPRecord *)record;

/// Lists a directory from the server; falls back to the cache when unreachable
/// (fromCache = YES). loaded = NO only when neither is available.
- (void)loadDirectory:(SeafDir *)dir completion:(void (^)(BOOL loaded, BOOL fromCache, NSError * _Nullable error))completion;

/// Error bookkeeping for -[NSFileProviderManager signalErrorResolved:].
- (void)noteError:(nullable NSError *)error;
- (void)noteSuccess;

/// Asks the system to enumerate working set changes (the only container a
/// replicated extension may signal).
- (void)signalWorkingSet;
/// Signals the working set again at `date` (at least one second from now)
/// so directories a pass left alone for being listed just now get checked;
/// one timer at a time.
- (void)scheduleWorkingSetRecheckAt:(NSDate *)date;

@end

NS_ASSUME_NONNULL_END
