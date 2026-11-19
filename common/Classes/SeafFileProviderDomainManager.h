//
//  SeafFileProviderDomainManager.h
//  seafile
//
//  Owns the NSFileProviderDomain lifecycle for the replicated File Provider
//  extension: one domain per account. Lives in the main app; the SDK never
//  depends on it.
//

#import <Foundation/Foundation.h>
#import <FileProvider/FileProvider.h>

@class SeafConnection;

NS_ASSUME_NONNULL_BEGIN

/// Told about the domain lifecycle. Registered by the main app's indexer
/// (SeafFPIndexer); this class is compiled into the extensions too and must
/// not reference app-only classes directly.
@protocol SeafFileProviderDomainObserver <NSObject>
/// The domain was added (or is still there after a failed removal).
- (void)fileProviderDomainDidActivate:(NSString *)domainIdentifier;
/// The domain is about to be removed (Touch ID turned on, account deleted):
/// stop writing its store now.
- (void)fileProviderDomainWillDeactivate:(NSString *)domainIdentifier;
/// The domain's store is about to be deleted. Call `removeStore` once nothing
/// can write it anymore (queued writes drained, open stores closed).
- (void)fileProviderDomainWillRemoveStore:(NSString *)domainIdentifier removeStore:(dispatch_block_t)removeStore;
@end

@interface SeafFileProviderDomainManager : NSObject

+ (instancetype)shared;

/// Main app only; nil in the extensions.
@property (nonatomic, weak, nullable) id<SeafFileProviderDomainObserver> domainObserver;

+ (NSString *)domainIdentifierForConnection:(SeafConnection *)conn;
+ (NSString *)displayNameForConnection:(SeafConnection *)conn;
/// Accounts protected by Touch ID / Face ID never get a domain.
+ (BOOL)connectionWantsDomain:(SeafConnection *)conn;
- (NSFileProviderDomain *)domainForConnection:(SeafConnection *)conn;

/// Adds the domain when the account wants one, removes it when it does not.
- (void)ensureDomainForConnection:(SeafConnection *)conn completion:(nullable void (^)(NSError * _Nullable error))completion;
/// Removes the domain and its local store.
- (void)removeDomainForConnection:(SeafConnection *)conn completion:(nullable void (^)(NSError * _Nullable error))completion;
/// Makes the registered domains match the account list: unwanted and foreign
/// domains are removed, missing ones added.
- (void)reconcileDomainsWithConnections:(NSArray<SeafConnection *> *)conns completion:(nullable void (^)(void))completion;

/// Forwards SeafFileProviderShouldSignalNotification (posted by the SDK
/// after uploads, file operations, library password changes and logout) to
/// the account's domain. Call once from the main app; extensions post the
/// notification but never observe it. The "account" variant (account info
/// fetched) only refreshes the domain's display name.
- (void)startObservingChangeNotifications;

/// Signals are coalesced per domain within five seconds (every signal makes
/// the extension re-list the library list). A replicated
/// extension only honours working set signals, so the "root" variant also
/// signals the working set; the extension re-checks the library list there.
- (void)signalWorkingSetForConnection:(SeafConnection *)conn;
- (void)signalRootForConnection:(SeafConnection *)conn;
- (void)signalWorkingSetForConnections:(NSArray<SeafConnection *> *)conns;
/// Sends every coalesced signal now (call before the app is suspended).
- (void)flushPendingSignals;
/// Same, calling `completion` (on an arbitrary queue) once the system has
/// answered every signal sent.
- (void)flushPendingSignalsWithCompletion:(nullable dispatch_block_t)completion;

/// Deletes the legacy "File Provider Storage" directory left by the old
/// NSFileProviderExtension. Runs once.
- (void)cleanupLegacyStorageIfNeeded;

@end

NS_ASSUME_NONNULL_END
