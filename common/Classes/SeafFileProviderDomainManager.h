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

@interface SeafFileProviderDomainManager : NSObject

+ (instancetype)shared;

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

/// Signals are coalesced per domain within two seconds. A replicated
/// extension only honours working set signals, so the "root" variant also
/// signals the working set; the extension re-checks the library list there.
- (void)signalWorkingSetForConnection:(SeafConnection *)conn;
- (void)signalRootForConnection:(SeafConnection *)conn;
- (void)signalWorkingSetForConnections:(NSArray<SeafConnection *> *)conns;
/// Sends every coalesced signal now (call before the app is suspended).
- (void)flushPendingSignals;

/// Deletes the legacy "File Provider Storage" directory left by the old
/// NSFileProviderExtension. Runs once.
- (void)cleanupLegacyStorageIfNeeded;

@end

NS_ASSUME_NONNULL_END
