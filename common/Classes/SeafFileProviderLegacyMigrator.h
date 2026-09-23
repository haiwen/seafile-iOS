//
//  SeafFileProviderLegacyMigrator.h
//  seafile
//
//  One-time migration of favorites / tags recorded by the legacy
//  NSFileProviderExtension into the per-domain stores of the replicated
//  extension. Main app only.
//

#import <Foundation/Foundation.h>

@class SeafConnection;

NS_ASSUME_NONNULL_BEGIN

@interface SeafFileProviderLegacyMigrator : NSObject

/// Runs at most once per install (App Group flag). Returns YES when data
/// was migrated in this call. Must run before the domains are registered;
/// on development devices that already have domains the caller signals
/// the working set afterwards.
+ (BOOL)migrateIfNeededWithConnections:(NSArray<SeafConnection *> *)connections;

/// Parses a legacy identifier ("/<encodedDir>/<escapedFilename>", the
/// leading slash may be missing). Exposed for tests.
+ (BOOL)parseLegacyIdentifier:(NSString *)identifier
                       server:(NSString * _Nullable * _Nullable)server
                     username:(NSString * _Nullable * _Nullable)username
                       repoId:(NSString * _Nullable * _Nullable)repoId
                         path:(NSString * _Nullable * _Nullable)path
                     filename:(NSString * _Nullable * _Nullable)filename;

@end

NS_ASSUME_NONNULL_END
