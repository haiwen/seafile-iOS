//
//  SeafFPIndexer.h
//  seafile
//
//  Main app only. Copies the metadata the app already has (directory
//  listings, renames and moves, starred items, search results, opened and
//  downloaded files) into the File Provider store, so Files finds those
//  items through the working set (iOS offers no search callback to file
//  providers). See docs/features/files-app-extension/files-app-search-implementation-plan.md.
//

#import <Foundation/Foundation.h>
#import "SeafConnection.h"
#import "SeafFileProviderDomainManager.h"

@class SeafFile;

NS_ASSUME_NONNULL_BEGIN

@interface SeafFPIndexer : NSObject <SeafFPIndexingSink, SeafFileProviderDomainObserver>

+ (instancetype)shared;

/// Registers with the SDK (SeafConnection.fileProviderIndexer) and the domain
/// manager. Call once at launch from the main app; does nothing elsewhere.
- (void)start;

/// NSUserDefaults "SeafFPIndexerEnabled", YES when unset. Turning it off only
/// stops new writes; rows already written stay and are maintained normally.
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;

/// The user opened a file in the app: Files lists it under Recents.
- (void)noteFileOpened:(SeafFile *)file;

/// NSUserDefaults "SeafFPActivityIndexEnabled", YES when unset (and only on
/// Seafile Pro servers with the new activities API).
@property (nonatomic, readonly, getter=isActivityIndexEnabled) BOOL activityIndexEnabled;

/// Reads the account's activity log back to where the last read ended, so
/// creations, edits, renames, moves and deletions made on other devices reach
/// the index without the user browsing there: they become directory checks
/// (listed by this class) and rename hints. Runs automatically when the app
/// becomes active (at most every 15 minutes); force: now, e.g. after the
/// activity list was refreshed. One read per account at a time.
- (void)syncActivitiesForConnection:(SeafConnection *)conn force:(BOOL)force;

@end

NS_ASSUME_NONNULL_END
