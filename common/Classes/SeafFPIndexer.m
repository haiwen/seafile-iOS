//
//  SeafFPIndexer.m
//  seafile
//

#import "SeafFPIndexer.h"
#import <UIKit/UIKit.h>
#import <CoreSpotlight/CoreSpotlight.h>
#import <FileProvider/FileProvider.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>
#import <os/lock.h>
#import <stdatomic.h>
#import "SeafFPStore.h"
#import "SeafFPIdentifier.h"
#import "SeafConstants.h"
#import "SeafGlobal.h"
#import "SeafRepos.h"
#import "SeafDir.h"
#import "SeafFile.h"
#import "Utils.h"
#import "Debug.h"

static NSString * const kSeafFPIndexerEnabledKey = @"SeafFPIndexerEnabled";
static NSString * const kSeafFPActivityIndexEnabledKey = @"SeafFPActivityIndexEnabled";
static NSString * const kSeafFPSpotlightIndexPrefix = @"com.seafile.fpindexer/";
static NSString * const kSeafFPMetaSpotlightSeqKey = @"spotlight_seq_v8";
static NSString * const kSeafFPMetaSpotlightReposKey = @"spotlight_repos_v8";
static const NSInteger kSeafFPSpotlightBatchSize = 500;
/// An account's activity log is fetched in the background at most this often.
static const NSTimeInterval kSeafFPActivityFetchInterval = 15 * 60;
/// Gives the library list a moment to load after the app became active.
static const NSTimeInterval kSeafFPActivityFetchDelay = 3.0;
/// Directory refreshes asked for within this window are merged (an upload of
/// many files into one directory lists it once).
static const NSTimeInterval kSeafFPRefreshCoalesceInterval = 1.0;
/// Timestamps below this are not unix times (some search APIs send strings).
static const long long kSeafFPMinPlausibleMtime = 946684800;   // 2000-01-01

#pragma mark - CoreSpotlight helpers

@interface SeafFPSpotlightVendorItem : NSObject <NSFileProviderItem>
@property (nonatomic, copy) NSFileProviderItemIdentifier itemIdentifier;
@property (nonatomic, copy) NSFileProviderItemIdentifier parentItemIdentifier;
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, copy) UTType *contentType;
@property (nonatomic, assign) NSFileProviderItemCapabilities capabilities;
@property (nonatomic, strong) NSFileProviderItemVersion *itemVersion;
@property (nonatomic, copy, nullable) NSNumber *documentSize;
@property (nonatomic, copy, nullable) NSDate *contentModificationDate;
@property (nonatomic, copy, nullable) NSNumber *favoriteRank;
@property (nonatomic, copy, nullable) NSData *tagData;
@property (nonatomic, copy, nullable) NSDate *lastUsedDate;
@property (nonatomic, assign) BOOL isDirectory;
@end

@implementation SeafFPSpotlightVendorItem
@end

static NSString *SeafFPProviderIdentifier(void)
{
    static NSString *providerID;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        providerID = bundleID.length > 0 ? [bundleID stringByAppendingString:@".SeafFileProvider"] : @"com.seafile.seafilePro.SeafFileProvider";
    });
    return providerID;
}

static NSString *SeafFPCoreSpotlightIdentifier(NSString *itemIdentifier, NSString *domainId)
{
    Class fpItemIDClass = NSClassFromString(@"FPItemID");
    SEL sel = NSSelectorFromString(@"csIdentifierFromFPIdentifier:domainIdentifier:");
    if (fpItemIDClass && [fpItemIDClass respondsToSelector:sel]) {
        NSString *csId = ((NSString *(*)(id, SEL, NSString *, NSString *))objc_msgSend)(fpItemIDClass, sel, itemIdentifier, domainId);
        if ([csId isKindOfClass:[NSString class]] && csId.length > 0) return csId;
    }
    NSString *prefix = @"__fpdefault";
    if (domainId.length > 0 && ![domainId isEqualToString:@"NSFileProviderDomainDefaultIdentifier"]) {
        NSString *b64 = [[domainId dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
        prefix = [@"__fp" stringByAppendingPathComponent:b64];
    }
    return [prefix stringByAppendingPathComponent:itemIdentifier];
}

static UTType *SeafFPContentTypeForFilename(NSString *filename)
{
    static NSDictionary *extensionTypes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"Seafile" withExtension:@"bundle"];
        NSBundle *bundle = url ? [NSBundle bundleWithURL:url] : [NSBundle mainBundle];
        NSString *plistPath = [bundle pathForResource:@"ExtensionTypes" ofType:@"plist"];
        extensionTypes = plistPath ? [NSDictionary dictionaryWithContentsOfFile:plistPath] : @{};
    });
    NSString *extension = filename.pathExtension.lowercaseString;
    if (extension.length == 0) return UTTypeData;
    NSString *predefined = extensionTypes[extension];
    if (predefined) {
        UTType *type = [UTType typeWithIdentifier:predefined];
        if (type) return type;
    }
    UTType *type = [UTType typeWithFilenameExtension:extension];
    if (type && ![type.identifier hasPrefix:@"dyn."]) return type;
    return UTTypeData;
}

static NSFileProviderItemCapabilities SeafFPCapabilitiesForDirectory(BOOL isDirectory, BOOL editable)
{
    NSFileProviderItemCapabilities caps = NSFileProviderItemCapabilitiesAllowsReading;
    if (isDirectory) {
        caps |= NSFileProviderItemCapabilitiesAllowsContentEnumerating
              | NSFileProviderItemCapabilitiesAllowsAddingSubItems;
    } else {
        caps |= NSFileProviderItemCapabilitiesAllowsWriting;
    }
    if (editable) {
        caps |= NSFileProviderItemCapabilitiesAllowsRenaming
              | NSFileProviderItemCapabilitiesAllowsReparenting
              | NSFileProviderItemCapabilitiesAllowsDeleting;
    }
    return caps;
}

static NSFileProviderItemVersion *SeafFPVersionWithContent(NSString * _Nullable content, NSString *metadata)
{
    NSData *contentData = [SeafFPIdentifier versionComponentData:(content.length > 0 ? content : @"-")];
    NSData *metadataData = [SeafFPIdentifier versionComponentData:(metadata ?: @"")];
    return [[NSFileProviderItemVersion alloc] initWithContentVersion:contentData metadataVersion:metadataData];
}

static CSSearchableItem * _Nullable SeafFPSearchableItemFromVendorItem(SeafFPSpotlightVendorItem *vendorItem, NSString *domainId)
{
    if (!vendorItem || vendorItem.itemIdentifier.length == 0 || domainId.length == 0) return nil;
    NSString *providerID = SeafFPProviderIdentifier();
    Class fpItemClass = NSClassFromString(@"FPItem");
    SEL initSel = NSSelectorFromString(@"initWithVendorItem:provider:domain:spotlightDomainIdentifier:extensionCapabilities:useFPFS:");
    SEL toCSSel = NSSelectorFromString(@"toSearchableItem");
    if (fpItemClass && [fpItemClass instancesRespondToSelector:initSel] && [fpItemClass instancesRespondToSelector:toCSSel]) {
        id fpItem = ((id (*)(id, SEL, id, NSString *, NSString *, NSString *, NSUInteger, BOOL))objc_msgSend)(
            [fpItemClass alloc], initSel, vendorItem, providerID, domainId, domainId, (NSUInteger)-1, NO);
        if (fpItem) {
            CSSearchableItem *csItem = ((CSSearchableItem *(*)(id, SEL))objc_msgSend)(fpItem, toCSSel);
            if ([csItem isKindOfClass:[CSSearchableItem class]]) {
                if (!vendorItem.lastUsedDate && vendorItem.contentModificationDate) {
                    csItem.attributeSet.lastUsedDate = vendorItem.contentModificationDate;
                }
                return csItem;
            }
        }
    }
    NSString *csIdentifier = SeafFPCoreSpotlightIdentifier(vendorItem.itemIdentifier, domainId);
    CSSearchableItemAttributeSet *attr = [[CSSearchableItemAttributeSet alloc] initWithContentType:vendorItem.contentType ?: UTTypeData];
    attr.displayName = vendorItem.filename;
    attr.contentModificationDate = vendorItem.contentModificationDate;
    attr.lastUsedDate = vendorItem.lastUsedDate;
    SEL setFavoriteRankSel = NSSelectorFromString(@"setFavoriteRank:");
    if (vendorItem.favoriteRank && [attr respondsToSelector:setFavoriteRankSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(attr, setFavoriteRankSel, vendorItem.favoriteRank);
    }
    if (!vendorItem.isDirectory && vendorItem.documentSize) {
        attr.fileSize = @((double)MAX(vendorItem.documentSize.longLongValue, 0LL) / 1000.0);
    }
    SEL setFileItemIDSel = NSSelectorFromString(@"setFileItemID:");
    if ([attr respondsToSelector:setFileItemIDSel]) ((void (*)(id, SEL, id))objc_msgSend)(attr, setFileItemIDSel, csIdentifier);
    SEL setProviderIDSel = NSSelectorFromString(@"setFileProviderID:");
    if ([attr respondsToSelector:setProviderIDSel]) ((void (*)(id, SEL, id))objc_msgSend)(attr, setProviderIDSel, providerID);
    SEL setDomainIDSel = NSSelectorFromString(@"setFileProviderDomainIdentifier:");
    if ([attr respondsToSelector:setDomainIDSel]) ((void (*)(id, SEL, id))objc_msgSend)(attr, setDomainIDSel, domainId);
    SEL setFilenameSel = NSSelectorFromString(@"setFilename:");
    if ([attr respondsToSelector:setFilenameSel]) ((void (*)(id, SEL, id))objc_msgSend)(attr, setFilenameSel, vendorItem.filename);
    SEL setAttrSel = NSSelectorFromString(@"setAttribute:forKey:");
    if ([attr respondsToSelector:setAttrSel]) {
        ((void (*)(id, SEL, id, NSString *))objc_msgSend)(attr, setAttrSel, vendorItem.filename, @"FPFilename");
        ((void (*)(id, SEL, id, NSString *))objc_msgSend)(attr, setAttrSel, vendorItem.parentItemIdentifier, @"FPParentFileItemID");
        ((void (*)(id, SEL, id, NSString *))objc_msgSend)(attr, setAttrSel, @(vendorItem.capabilities), @"FPCapabilities");
        ((void (*)(id, SEL, id, NSString *))objc_msgSend)(attr, setAttrSel, @(vendorItem.isDirectory), @"FPIsContainer");
        ((void (*)(id, SEL, id, NSString *))objc_msgSend)(attr, setAttrSel, @NO, @"FPIsContainerPristine");
        ((void (*)(id, SEL, id, NSString *))objc_msgSend)(attr, setAttrSel, @YES, @"FPIsUbiquitous");
        ((void (*)(id, SEL, id, NSString *))objc_msgSend)(attr, setAttrSel, @NO, @"FPDownloaded");
        ((void (*)(id, SEL, id, NSString *))objc_msgSend)(attr, setAttrSel, @YES, @"FPMostRecentVersionDownloaded");
    }
    CSSearchableItem *csItem = [[CSSearchableItem alloc] initWithUniqueIdentifier:csIdentifier
                                                                  domainIdentifier:domainId
                                                                      attributeSet:attr];
    csItem.expirationDate = [NSDate distantFuture];
    return csItem;
}

static CSSearchableItem * _Nullable SeafFPSearchableItemForRepoInfo(NSDictionary *repoInfo,
                                                                    SeafFPDecoration * _Nullable decoration,
                                                                    NSString *domainId)
{
    NSString *repoId = repoInfo[@"repoId"];
    if (repoId.length == 0) return nil;
    NSString *name = repoInfo[@"name"] ?: repoId;
    long long mtime = [repoInfo[@"mtime"] longLongValue];
    NSString *perm = repoInfo[@"perm"] ?: @"";
    NSString *ooid = repoInfo[@"ooid"];
    SeafFPSpotlightVendorItem *vendorItem = [SeafFPSpotlightVendorItem new];
    vendorItem.itemIdentifier = [SeafFPIdentifier identifierForRepo:repoId];
    vendorItem.parentItemIdentifier = NSFileProviderRootContainerItemIdentifier;
    vendorItem.filename = name;
    vendorItem.contentType = UTTypeFolder;
    vendorItem.isDirectory = YES;
    vendorItem.capabilities = SeafFPCapabilitiesForDirectory(YES, NO);
    NSString *metadata = [NSString stringWithFormat:@"%lld|%@|%@", mtime, name, perm];
    vendorItem.itemVersion = SeafFPVersionWithContent(ooid, metadata);
    if (mtime > 0) {
        vendorItem.contentModificationDate = [NSDate dateWithTimeIntervalSince1970:mtime];
    }
    if (decoration) {
        vendorItem.favoriteRank = decoration.favoriteRank;
        vendorItem.tagData = decoration.tagData;
        vendorItem.lastUsedDate = decoration.lastUsedDate;
    }
    return SeafFPSearchableItemFromVendorItem(vendorItem, domainId);
}

static CSSearchableItem * _Nullable SeafFPSearchableItemForRecord(SeafFPRecord *record,
                                                                  BOOL editable,
                                                                  SeafFPDecoration * _Nullable decoration,
                                                                  NSString *domainId)
{
    if (!record || record.deleted) return nil;
    NSString *filename = record.name.length > 0 ? record.name : record.path.lastPathComponent;
    if (filename.length == 0) return nil;
    SeafFPSpotlightVendorItem *vendorItem = [SeafFPSpotlightVendorItem new];
    vendorItem.itemIdentifier = record.itemIdentifier;
    vendorItem.parentItemIdentifier = record.parentItemIdentifier;
    vendorItem.filename = filename;
    vendorItem.isDirectory = record.isDir;
    vendorItem.contentType = record.isDir ? UTTypeFolder : SeafFPContentTypeForFilename(filename);
    vendorItem.capabilities = SeafFPCapabilitiesForDirectory(record.isDir, editable);
    NSString *metadata = [NSString stringWithFormat:@"%lld|%lld|%@", record.mtime, record.size, filename];
    vendorItem.itemVersion = SeafFPVersionWithContent(record.oid, metadata);
    if (!record.isDir && record.size >= 0) {
        vendorItem.documentSize = @(record.size);
    }
    if (record.mtime > 0) {
        vendorItem.contentModificationDate = [NSDate dateWithTimeIntervalSince1970:record.mtime];
    }
    if (decoration) {
        vendorItem.favoriteRank = decoration.favoriteRank;
        vendorItem.tagData = decoration.tagData;
        vendorItem.lastUsedDate = decoration.lastUsedDate;
    }
    return SeafFPSearchableItemFromVendorItem(vendorItem, domainId);
}

@interface SeafDir (SeafFPIndexingPrivate)
- (NSString *)url;
- (void)handleResponse:(NSHTTPURLResponse *)response json:(id)JSON;
- (nullable NSArray<NSDictionary *> *)fp_listingSnapshotForResponse:(id)JSON;
@end

@interface SeafFPIndexer ()
{
    dispatch_queue_t _workQueue;
    // Work queue only.
    NSMutableDictionary<NSString *, SeafFPStore *> *_stores;
    NSMutableDictionary<NSString *, CSSearchableIndex *> *_spotlightIndices;
    NSMutableSet<NSString *> *_spotlightSyncingDomains;
    NSMutableSet<NSString *> *_spotlightNeedsResyncDomains;
    NSMutableDictionary<NSString *, NSMutableArray<dispatch_block_t> *> *_spotlightCompletionsByDomain;
    NSMutableArray<SeafConnection *> *_changedConnections;
    // Guarded by _lock (read from any thread, never waits on the work queue).
    os_unfair_lock _lock;
    NSMutableSet<NSString *> *_deactivatedDomains;
    NSMutableDictionary<NSString *, NSNumber *> *_domainGenerations;
    NSMutableSet<NSString *> *_pendingRefreshes;
    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSDictionary *> *> *_repoInfosByDomain;
    NSMutableDictionary<NSString *, NSSet<NSString *> *> *_indexedRepoIdsByDomain;
    NSMutableDictionary<NSString *, NSNumber *> *_pendingMoveCounts;
    NSMutableDictionary<NSString *, NSMutableArray<dispatch_block_t> *> *_deferredDirWork;
    // Main thread only: when each account's activity log was last indexed.
    NSMutableDictionary<NSString *, NSDate *> *_activityFetchedAt;
    atomic_bool _expired;        // background time ran out: skip queued work
    atomic_bool _inBackground;   // signals must leave before suspension
    BOOL _started;
}
@end

@implementation SeafFPIndexer

+ (instancetype)shared
{
    static SeafFPIndexer *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SeafFPIndexer alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _workQueue = dispatch_queue_create("com.seafile.fpindexer",
                                           dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
        _stores = [NSMutableDictionary dictionary];
        _spotlightIndices = [NSMutableDictionary dictionary];
        _spotlightSyncingDomains = [NSMutableSet set];
        _spotlightNeedsResyncDomains = [NSMutableSet set];
        _spotlightCompletionsByDomain = [NSMutableDictionary dictionary];
        _changedConnections = [NSMutableArray array];
        _lock = OS_UNFAIR_LOCK_INIT;
        _deactivatedDomains = [NSMutableSet set];
        _domainGenerations = [NSMutableDictionary dictionary];
        _pendingRefreshes = [NSMutableSet set];
        _repoInfosByDomain = [NSMutableDictionary dictionary];
        _indexedRepoIdsByDomain = [NSMutableDictionary dictionary];
        _pendingMoveCounts = [NSMutableDictionary dictionary];
        _deferredDirWork = [NSMutableDictionary dictionary];
        _activityFetchedAt = [NSMutableDictionary dictionary];
        atomic_init(&_expired, false);
        atomic_init(&_inBackground, false);
    }
    return self;
}

- (void)start
{
    if (![Utils isMainApp] || _started) return;
    _started = YES;
    SeafConnection.fileProviderIndexer = self;
    [SeafFileProviderDomainManager shared].domainObserver = self;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(appDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [nc addObserver:self selector:@selector(appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(fileProviderShouldSignal:) name:SeafFileProviderShouldSignalNotification object:nil];
    void (^readState)(void) = ^{
        atomic_store(&self->_inBackground, [UIApplication sharedApplication].applicationState == UIApplicationStateBackground);
    };
    if ([NSThread isMainThread]) readState(); else dispatch_async(dispatch_get_main_queue(), readState);
    Debug("Files app indexer started (enabled=%d)", self.enabled);
}

- (void)fileProviderShouldSignal:(NSNotification *)note
{
    SeafConnection *conn = [note.object isKindOfClass:[SeafConnection class]] ? note.object : nil;
    if (!conn) return;
    NSString *type = note.userInfo[SeafFileProviderSignalTypeKey];
    if ([type isEqualToString:SeafFileProviderSignalTypeRoot]) {
        if ([NSThread isMainThread]) {
            [self syncSpotlightIfNeededForConnection:conn];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self syncSpotlightIfNeededForConnection:conn];
            });
        }
    }
}

- (BOOL)isEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kSeafFPIndexerEnabledKey];
    return value == nil || [value boolValue];
}

- (void)appDidEnterBackground:(NSNotification *)note
{
    atomic_store(&_expired, false);
    atomic_store(&_inBackground, true);
}

- (void)appWillEnterForeground:(NSNotification *)note
{
    atomic_store(&_inBackground, false);
    atomic_store(&_expired, false);
}

- (BOOL)isActivityIndexEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kSeafFPActivityIndexEnabledKey];
    return value == nil || [value boolValue];
}

/// Launch and every return to the foreground: fetch the first activity page
/// of each Pro account whose log was not indexed for a while.
- (void)appDidBecomeActive:(NSNotification *)note
{
    atomic_store(&_inBackground, false);
    atomic_store(&_expired, false);
    for (SeafConnection *conn in [SeafGlobal.sharedObject.conns copy]) {
        [self syncSpotlightIfNeededForConnection:conn];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSeafFPActivityFetchDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
        for (SeafConnection *conn in [SeafGlobal.sharedObject.conns copy]) {
            [self syncSpotlightIfNeededForConnection:conn];
            [self fetchActivitiesIfDueForConnection:conn];
        }
    });
}

- (void)syncSpotlightIfNeededForConnection:(SeafConnection *)conn
{
    NSString *domainId = [self domainIdForConnection:conn repoId:nil];
    if (!domainId) return;
    uint64_t generation = [self generationForDomainId:domainId];
    if (conn.rootFolder && conn.rootFolder.items == nil && ![conn.rootFolder loadCache]) {
        __weak typeof(self) weakSelf = self;
        __weak SeafConnection *weakConn = conn;
        [conn.rootFolder loadContentSuccess:^(SeafDir *dir) {
            typeof(self) strongSelf = weakSelf;
            SeafConnection *strongConn = weakConn;
            if (!strongSelf || !strongConn || ![strongSelf isDomainActive:domainId generation:generation]) return;
            NSString *loadedDomainId = [strongSelf domainIdForConnection:strongConn repoId:nil];
            if (!loadedDomainId || ![loadedDomainId isEqualToString:domainId]) return;
            [strongSelf enqueueForDomainId:loadedDomainId work:^(SeafFPStore *store) {
                [strongSelf noteChangedConnection:strongConn];
            }];
        } failure:nil];
        return;
    }
    [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
        // enqueueForDomainId:work: runs syncSpotlightForDomainId:store:completion: after work(store).
        [self noteChangedConnection:conn];
    }];
}

- (BOOL)canIndexActivitiesOfConnection:(SeafConnection *)conn
{
    return self.activityIndexEnabled && conn.isActivityEnabled && conn.isNewActivitiesApiSupported
        && [self domainIdForConnection:conn repoId:nil] != nil;
}

/// Main thread.
- (void)fetchActivitiesIfDueForConnection:(SeafConnection *)conn
{
    if (![self canIndexActivitiesOfConnection:conn]) return;
    // Events of libraries that are not loaded yet would all be dropped.
    if (conn.rootFolder.items.count == 0) return;
    NSString *domainId = [SeafFileProviderDomainManager domainIdentifierForConnection:conn];
    uint64_t generation = [self generationForDomainId:domainId];
    NSDate *last = _activityFetchedAt[domainId];
    if (last && -[last timeIntervalSinceNow] < kSeafFPActivityFetchInterval) return;
    _activityFetchedAt[domainId] = [NSDate date];   // also while in flight: no second request
    __weak SeafConnection *weakConn = conn;
    [conn sendRequest:API_URL_V21"/activities/?page=1" success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        if (![self isDomainActive:domainId generation:generation]) return;
        SeafConnection *strongConn = weakConn;
        NSArray *events = [JSON isKindOfClass:[NSDictionary class]] ? JSON[@"events"] : nil;
        if (strongConn && [events isKindOfClass:[NSArray class]]) {
            [self indexActivityEvents:events connection:strongConn];
        }
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        Debug("activity fetch for the Files index failed: %@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self isDomainActive:domainId generation:generation]) return;
            // Try again next time the app becomes active.
            [self->_activityFetchedAt removeObjectForKey:domainId];
        });
    }];
}

#pragma mark - Admission

- (BOOL)isDomainDeactivated:(NSString *)domainId
{
    os_unfair_lock_lock(&_lock);
    BOOL deactivated = [_deactivatedDomains containsObject:domainId];
    os_unfair_lock_unlock(&_lock);
    return deactivated;
}

- (uint64_t)generationForDomainId:(NSString *)domainId
{
    if (domainId.length == 0) return 0;
    os_unfair_lock_lock(&_lock);
    uint64_t gen = [_domainGenerations[domainId] unsignedLongLongValue];
    os_unfair_lock_unlock(&_lock);
    return gen;
}

- (BOOL)isDomainActive:(NSString *)domainId generation:(uint64_t)generation
{
    if (domainId.length == 0) return NO;
    os_unfair_lock_lock(&_lock);
    BOOL active = ![_deactivatedDomains containsObject:domainId]
        && [_domainGenerations[domainId] unsignedLongLongValue] == generation;
    os_unfair_lock_unlock(&_lock);
    return active;
}

- (NSDictionary<NSString *, NSDictionary *> *)snapshotVisibleReposOfConnection:(SeafConnection *)conn
                                                                   extraRepoId:(nullable NSString *)extraRepoId
{
    if (!conn) return @{};
    SeafRepos *repos = conn.rootFolder;
    if (repos && repos.items.count == 0) {
        [repos loadCache];
    }
    NSMutableDictionary<NSString *, NSDictionary *> *snapshot = [NSMutableDictionary dictionary];
    for (SeafBase *obj in [repos.items copy]) {
        if (![obj isKindOfClass:[SeafRepo class]]) continue;
        SeafRepo *repo = (SeafRepo *)obj;
        if (repo.passwordRequired || repo.repoId.length == 0 || snapshot[repo.repoId]) continue;
        snapshot[repo.repoId] = @{
            @"repoId": repo.repoId,
            @"name": repo.name ?: repo.repoId,
            @"mtime": @(repo.mtime),
            @"perm": repo.perm ?: @"",
            @"ooid": repo.ooid ?: @"",
            @"editable": @(repo.editable),
        };
    }
    if (extraRepoId.length > 0 && !snapshot[extraRepoId]) {
        SeafRepo *repo = [conn getRepo:extraRepoId];
        if (repo && !repo.passwordRequired && repo.repoId.length > 0) {
            snapshot[repo.repoId] = @{
                @"repoId": repo.repoId,
                @"name": repo.name ?: repo.repoId,
                @"mtime": @(repo.mtime),
                @"perm": repo.perm ?: @"",
                @"ooid": repo.ooid ?: @"",
                @"editable": @(repo.editable),
            };
        }
    }
    return snapshot;
}

/// Checked on the calling thread (main thread / network callbacks, where the
/// account list and library list are maintained) before work is queued.
- (nullable NSString *)domainIdForConnection:(SeafConnection *)conn repoId:(nullable NSString *)repoId
{
    if (![Utils isMainApp] || !_started || !conn || !self.enabled) return nil;
    if (![SeafGlobal.sharedObject.conns containsObject:conn]) return nil;          // account still there
    if (!conn.authorized) return nil;                                              // signed in
    if (![SeafFileProviderDomainManager connectionWantsDomain:conn]) return nil;   // no Touch ID
    NSString *domainId = [SeafFileProviderDomainManager domainIdentifierForConnection:conn];
    if (domainId.length == 0 || [self isDomainDeactivated:domainId]) return nil;
    if (repoId.length > 0) {
        // Same rule as the extension's visible libraries. Explicit nil check:
        // !nil.passwordRequired would read as "no password needed".
        SeafRepo *repo = [conn getRepo:repoId];
        if (!repo || repo.passwordRequired) return nil;
    }
    NSDictionary<NSString *, NSDictionary *> *repoInfos = [self snapshotVisibleReposOfConnection:conn extraRepoId:repoId];
    os_unfair_lock_lock(&_lock);
    if (repoInfos.count > 0 || conn.rootFolder.items != nil || _repoInfosByDomain[domainId] != nil) {
        _repoInfosByDomain[domainId] = repoInfos ?: @{};
    }
    os_unfair_lock_unlock(&_lock);
    return domainId;
}

#pragma mark - Work queue

/// Work queue only.
- (CSSearchableIndex *)spotlightIndexForDomainId:(NSString *)domainId
{
    CSSearchableIndex *index = _spotlightIndices[domainId];
    if (!index) {
        NSString *indexName = [kSeafFPSpotlightIndexPrefix stringByAppendingString:domainId];
        index = [[CSSearchableIndex alloc] initWithName:indexName
                                        protectionClass:NSFileProtectionCompleteUntilFirstUserAuthentication];
        _spotlightIndices[domainId] = index;
    }
    return index;
}

static NSUInteger SeafFPSpotlightPathDepth(NSString *path)
{
    NSUInteger depth = 0;
    NSUInteger length = path.length;
    for (NSUInteger i = 0; i < length; i++) {
        if ([path characterAtIndex:i] == '/') depth++;
    }
    return depth;
}

static NSArray<SeafFPRecord *> *SeafFPSortSpotlightRecordsParentFirst(NSArray<SeafFPRecord *> *records)
{
    if (records.count <= 1) return records;
    return [records sortedArrayUsingComparator:^NSComparisonResult(SeafFPRecord *a, SeafFPRecord *b) {
        NSUInteger depthA = SeafFPSpotlightPathDepth(a.path);
        NSUInteger depthB = SeafFPSpotlightPathDepth(b.path);
        if (depthA != depthB) return depthA < depthB ? NSOrderedAscending : NSOrderedDescending;
        if (a.isDir != b.isDir) return a.isDir ? NSOrderedAscending : NSOrderedDescending;
        NSComparisonResult byRepo = [a.repoId compare:b.repoId];
        if (byRepo != NSOrderedSame) return byRepo;
        NSComparisonResult byPath = [a.path compare:b.path];
        return byPath != NSOrderedSame ? byPath : [a.uuid compare:b.uuid];
    }];
}

/// Work queue only. Mirrors store rows into CoreSpotlight
/// so Files.app search (FPSpotlightCollector) finds items even in deep directories
/// that were never manually opened in Files.app.
- (void)verifySpotlightItemsForDomainId:(NSString *)domainId
                  expectedIdentifiers:(NSSet<NSString *> *)expectedIdentifiers
                           completion:(void (^)(NSSet<NSString *> *missingIdentifiers))completion
{
    if (expectedIdentifiers.count == 0) {
        completion([NSSet set]);
        return;
    }
    CSSearchQueryContext *ctx = [[CSSearchQueryContext alloc] init];
    ctx.fetchAttributes = @[];
    CSSearchQuery *query = [[CSSearchQuery alloc] initWithQueryString:@"kMDItemDisplayName == '*'" queryContext:ctx];
    query.protectionClasses = @[NSFileProtectionCompleteUntilFirstUserAuthentication];
    __block CSSearchQuery *retainedQuery = query;
    NSMutableSet<NSString *> *missing = [expectedIdentifiers mutableCopy];
    // CSSearchQuery serializes its foundItemsHandler calls. Compare identities,
    // not a total count: unrelated/stale rows must not hide a missing sibling.
    query.foundItemsHandler = ^(NSArray<CSSearchableItem *> * _Nonnull items) {
        for (CSSearchableItem *item in items) {
            [missing removeObject:item.uniqueIdentifier];
        }
    };
    query.completionHandler = ^(NSError * _Nullable error) {
        retainedQuery = nil;
        if (error) {
            // A failed query cannot prove that an item is missing. Normal
            // incremental indexing still proceeds, and a later sync retries.
            completion([NSSet set]);
            return;
        }
        if (missing.count > 0) {
            Info("Files app Spotlight index for %@ is missing %lu of %lu items; repairing missing identities",
                 domainId, (unsigned long)missing.count, (unsigned long)expectedIdentifiers.count);
        }
        completion([missing copy]);
    };
    [query start];
}

static NSSet<NSString *> *SeafFPParseRepoIdsMeta(NSString * _Nullable metaValue)
{
    if (metaValue.length == 0) return [NSSet set];
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    for (NSString *part in [metaValue componentsSeparatedByString:@"\n"]) {
        if (part.length == 0) continue;
        NSRange tab = [part rangeOfString:@"\t"];
        NSString *repoId = (tab.location == NSNotFound) ? part : [part substringToIndex:tab.location];
        if (repoId.length > 0) [set addObject:repoId];
    }
    return set;
}

static NSString *SeafFPFormatRepoIdsMeta(NSArray<NSString *> *repoIds)
{
    if (repoIds.count == 0) return @"";
    NSArray<NSString *> *sorted = [repoIds sortedArrayUsingSelector:@selector(compare:)];
    return [sorted componentsJoinedByString:@"\n"];
}

- (void)addSpotlightCompletion:(nullable dispatch_block_t)completion forDomainId:(NSString *)domainId
{
    if (!completion || domainId.length == 0) return;
    NSMutableArray<dispatch_block_t> *list = _spotlightCompletionsByDomain[domainId];
    if (!list) {
        list = [NSMutableArray array];
        _spotlightCompletionsByDomain[domainId] = list;
    }
    [list addObject:[completion copy]];
}

- (void)finishSpotlightCompletionsForDomainId:(NSString *)domainId
{
    if (domainId.length == 0) return;
    NSArray<dispatch_block_t> *completions = [_spotlightCompletionsByDomain[domainId] copy];
    [_spotlightCompletionsByDomain removeObjectForKey:domainId];
    for (dispatch_block_t block in completions) {
        block();
    }
}

- (void)finishOrResyncSpotlightForDomainId:(NSString *)domainId
                            preferredStore:(nullable SeafFPStore *)preferredStore
                               allowResync:(BOOL)allowResync
{
    [_spotlightSyncingDomains removeObject:domainId];
    if (allowResync
        && [_spotlightNeedsResyncDomains containsObject:domainId]
        && ![self isDomainDeactivated:domainId]) {
        [_spotlightNeedsResyncDomains removeObject:domainId];
        SeafFPStore *resyncStore = (preferredStore && [preferredStore isOpen]) ? preferredStore : _stores[domainId];
        if (!resyncStore || ![resyncStore isOpen]) {
            resyncStore = [[SeafFPStore alloc] initWithDomainIdentifier:domainId error:nil];
            if (resyncStore) _stores[domainId] = resyncStore;
        }
        if ([resyncStore isOpen]) {
            [self syncSpotlightForDomainId:domainId store:resyncStore completion:nil];
            return;
        }
    }
    [_spotlightNeedsResyncDomains removeObject:domainId];
    [self finishSpotlightCompletionsForDomainId:domainId];
}

- (void)syncSpotlightForDomainId:(NSString *)domainId
                           store:(SeafFPStore *)store
                      completion:(nullable dispatch_block_t)completion
{
    [self addSpotlightCompletion:completion forDomainId:domainId];
    if (![CSSearchableIndex isIndexingAvailable] || !self.enabled || [self isDomainDeactivated:domainId] || ![store isOpen]) {
        if (![_spotlightSyncingDomains containsObject:domainId]) {
            [self finishSpotlightCompletionsForDomainId:domainId];
        }
        return;
    }
    os_unfair_lock_lock(&_lock);
    NSDictionary<NSString *, NSDictionary *> *repoInfos = _repoInfosByDomain[domainId];
    NSSet<NSString *> *memIndexedRepos = _indexedRepoIdsByDomain[domainId];
    os_unfair_lock_unlock(&_lock);
    NSString *storedSeqStr = [store metaValueForKey:kSeafFPMetaSpotlightSeqKey];
    NSString *storedReposStr = [store metaValueForKey:kSeafFPMetaSpotlightReposKey];
    NSSet<NSString *> *storedIndexedRepos = SeafFPParseRepoIdsMeta(storedReposStr);
    BOOL hasPreviouslyIndexedRepos = (storedIndexedRepos.count > 0 || memIndexedRepos.count > 0
                                      || (storedReposStr == nil && storedSeqStr.length > 0 && storedSeqStr.longLongValue > 0));
    if (repoInfos.count == 0 && !hasPreviouslyIndexedRepos) {
        if (![_spotlightSyncingDomains containsObject:domainId]) {
            [self finishSpotlightCompletionsForDomainId:domainId];
        }
        return;
    }
    if ([_spotlightSyncingDomains containsObject:domainId]) {
        [_spotlightNeedsResyncDomains addObject:domainId];
        return;
    }
    uint64_t generation = [self generationForDomainId:domainId];
    if ((atomic_load(&_expired) && atomic_load(&_inBackground)) || ![self isDomainActive:domainId generation:generation] || ![store isOpen]) {
        [self finishSpotlightCompletionsForDomainId:domainId];
        return;
    }

    [_spotlightSyncingDomains addObject:domainId];
    [_spotlightNeedsResyncDomains removeObject:domainId];

    long long currentSeq = [store currentSeq];
    long long spotlightSeq = storedSeqStr.length > 0 ? storedSeqStr.longLongValue : 0;
    if (spotlightSeq < 0 || spotlightSeq > currentSeq) {
        spotlightSeq = 0;
    }
    if (spotlightSeq == 0 || repoInfos.count == 0) {
        [self performSpotlightSyncForDomainId:domainId store:store repairIdentifiers:nil];
        return;
    }

    NSMutableSet<NSString *> *expectedIdentifiers = [NSMutableSet set];
    for (NSString *repoId in repoInfos) {
        [expectedIdentifiers addObject:SeafFPCoreSpotlightIdentifier([SeafFPIdentifier identifierForRepo:repoId], domainId)];
    }
    for (SeafFPRecord *rec in [store liveRecordsAfterUUID:nil limit:0]) {
        if (repoInfos[rec.repoId]) {
            [expectedIdentifiers addObject:SeafFPCoreSpotlightIdentifier(rec.itemIdentifier, domainId)];
        }
    }

    __weak typeof(self) weakSelf = self;
    [self verifySpotlightItemsForDomainId:domainId
                     expectedIdentifiers:expectedIdentifiers
                              completion:^(NSSet<NSString *> *missingIdentifiers) {
        typeof(self) innerSelf = weakSelf;
        if (!innerSelf) {
            return;
        }
        dispatch_async(innerSelf->_workQueue, ^{
            if (![innerSelf isDomainActive:domainId generation:generation]) {
                [innerSelf finishOrResyncSpotlightForDomainId:domainId preferredStore:nil allowResync:YES];
                return;
            }
            [innerSelf performSpotlightSyncForDomainId:domainId
                                                 store:store
                                     repairIdentifiers:missingIdentifiers];
        });
    }];
}

- (void)performSpotlightSyncForDomainId:(NSString *)domainId
                                  store:(SeafFPStore *)store
                      repairIdentifiers:(nullable NSSet<NSString *> *)repairIdentifiers
{
    void (^finishEarly)(void) = ^{
        [self finishOrResyncSpotlightForDomainId:domainId preferredStore:store allowResync:YES];
    };

    uint64_t generation = [self generationForDomainId:domainId];
    if ((atomic_load(&_expired) && atomic_load(&_inBackground)) || ![self isDomainActive:domainId generation:generation] || ![store isOpen]) {
        finishEarly();
        return;
    }

    os_unfair_lock_lock(&_lock);
    NSDictionary<NSString *, NSDictionary *> *repoInfos = _repoInfosByDomain[domainId];
    NSSet<NSString *> *memIndexedRepos = _indexedRepoIdsByDomain[domainId];
    os_unfair_lock_unlock(&_lock);

    long long currentSeq = [store currentSeq];
    NSString *storedSeqStr = [store metaValueForKey:kSeafFPMetaSpotlightSeqKey];
    NSString *storedReposStr = [store metaValueForKey:kSeafFPMetaSpotlightReposKey];
    long long spotlightSeq = storedSeqStr.length > 0 ? storedSeqStr.longLongValue : 0;
    if (spotlightSeq < 0 || spotlightSeq > currentSeq) {
        spotlightSeq = 0;
    }

    NSMutableSet<NSString *> *previousRepoIds = [NSMutableSet set];
    [previousRepoIds unionSet:SeafFPParseRepoIdsMeta(storedReposStr)];
    if (memIndexedRepos.count > 0) {
        [previousRepoIds unionSet:memIndexedRepos];
    }
    BOOL hasPreviouslyIndexedRepos = (previousRepoIds.count > 0
                                      || (storedReposStr == nil && storedSeqStr.length > 0 && storedSeqStr.longLongValue > 0));
    if (repoInfos.count == 0 && !hasPreviouslyIndexedRepos) {
        finishEarly();
        return;
    }

    NSMutableDictionary<NSString *, NSString *> *storedRepoMetaById = [NSMutableDictionary dictionary];
    for (NSString *line in [storedReposStr componentsSeparatedByString:@"\n"]) {
        if (line.length == 0) continue;
        NSRange tab = [line rangeOfString:@"\t"];
        if (tab.location != NSNotFound) {
            NSString *rId = [line substringToIndex:tab.location];
            if (rId.length > 0) storedRepoMetaById[rId] = line;
        }
    }
    NSMutableDictionary<NSString *, NSString *> *currentRepoMetaById = [NSMutableDictionary dictionaryWithCapacity:repoInfos.count];
    for (NSString *repoId in repoInfos.allKeys) {
        NSDictionary *info = repoInfos[repoId];
        NSString *name = [info[@"name"] isKindOfClass:[NSString class]] ? info[@"name"] : @"";
        name = [[name stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
        long long mtime = [info[@"mtime"] respondsToSelector:@selector(longLongValue)] ? [info[@"mtime"] longLongValue] : 0;
        NSString *perm = [info[@"perm"] isKindOfClass:[NSString class]] ? info[@"perm"] : @"";
        BOOL editable = [info[@"editable"] respondsToSelector:@selector(boolValue)] && [info[@"editable"] boolValue];
        NSString *ooid = [info[@"ooid"] isKindOfClass:[NSString class]] ? info[@"ooid"] : @"";
        currentRepoMetaById[repoId] = [NSString stringWithFormat:@"%@\t%@\t%lld\t%@\t%d\t%@", repoId, name, mtime, perm, editable ? 1 : 0, ooid];
    }

    NSMutableSet<NSString *> *removedRepoIds = [NSMutableSet set];
    for (NSString *prevRepoId in previousRepoIds) {
        if (!repoInfos[prevRepoId]) {
            [removedRepoIds addObject:prevRepoId];
        }
    }
    NSArray<SeafFPRecord *> *allStoreRecords = nil;
    if (storedReposStr == nil && hasPreviouslyIndexedRepos) {
        allStoreRecords = [store recordsChangedSinceSeq:0 limit:0];
        for (SeafFPRecord *rec in allStoreRecords) {
            if (rec.repoId.length > 0 && !repoInfos[rec.repoId]) {
                [removedRepoIds addObject:rec.repoId];
            }
        }
    }
    NSMutableSet<NSString *> *addedRepoIds = [NSMutableSet set];
    NSMutableSet<NSString *> *updatedRepoIds = [NSMutableSet set];
    if (storedReposStr != nil || memIndexedRepos != nil) {
        for (NSString *repoId in repoInfos.allKeys) {
            if (![previousRepoIds containsObject:repoId]) {
                [addedRepoIds addObject:repoId];
            } else {
                NSString *prevMeta = storedRepoMetaById[repoId];
                NSString *curMeta = currentRepoMetaById[repoId];
                if (!prevMeta || ![prevMeta isEqualToString:curMeta]) {
                    [updatedRepoIds addObject:repoId];
                }
            }
        }
    }

    BOOL reposChanged = (removedRepoIds.count > 0 || addedRepoIds.count > 0 || updatedRepoIds.count > 0 || (storedReposStr == nil && repoInfos.count > 0));
    if (repairIdentifiers.count == 0 && !reposChanged && spotlightSeq == currentSeq && storedSeqStr.length > 0) {
        finishEarly();
        return;
    }

    BOOL isInitialSync = (spotlightSeq == 0);
    CSSearchableIndex *index = [self spotlightIndexForDomainId:domainId];
    NSMutableDictionary<NSString *, SeafFPDecoration *> *decorations = [NSMutableDictionary dictionary];
    for (SeafFPDecoration *decoration in [store allDecorations]) {
        decorations[decoration.itemIdentifier] = decoration;
    }

    NSMutableSet<NSString *> *repoIdsToIndex = [NSMutableSet set];
    if (isInitialSync) {
        [repoIdsToIndex addObjectsFromArray:repoInfos.allKeys];
    } else {
        if (addedRepoIds.count > 0) [repoIdsToIndex unionSet:addedRepoIds];
        if (updatedRepoIds.count > 0) [repoIdsToIndex unionSet:updatedRepoIds];
    }
    NSMutableDictionary<NSString *, SeafFPRecord *> *recordsByUUID = [NSMutableDictionary dictionary];
    NSMutableOrderedSet<NSString *> *identifiersToDelete = [NSMutableOrderedSet orderedSet];

    void (^addLiveRecordAndAncestors)(SeafFPRecord *) = ^(SeafFPRecord *record) {
        if (!record || record.deleted || !repoInfos[record.repoId]) return;
        [repoIdsToIndex addObject:record.repoId];
        SeafFPRecord *cur = record;
        NSUInteger hops = 0;
        while (cur && !cur.deleted && cur.uuid.length > 0 && hops < 64) {
            BOOL alreadyPresent = (recordsByUUID[cur.uuid] != nil);
            recordsByUUID[cur.uuid] = cur;
            if (alreadyPresent || cur.parentUUID.length == 0) break;
            hops++;
            cur = [store recordForUUID:cur.parentUUID];
        }
    };

    // The journal acknowledgement is not a guarantee that every row remains
    // searchable. Repair missing identities even when the store seq has not
    // changed, without rebuilding all of the account's healthy entries.
    if (repairIdentifiers.count > 0) {
        for (NSString *repoId in repoInfos) {
            NSString *identifier = SeafFPCoreSpotlightIdentifier([SeafFPIdentifier identifierForRepo:repoId], domainId);
            if ([repairIdentifiers containsObject:identifier]) [repoIdsToIndex addObject:repoId];
        }
        for (SeafFPRecord *rec in [store liveRecordsAfterUUID:nil limit:0]) {
            if ([repairIdentifiers containsObject:SeafFPCoreSpotlightIdentifier(rec.itemIdentifier, domainId)]) {
                addLiveRecordAndAncestors(rec);
            }
        }
    }

    for (NSString *removedRepoId in [removedRepoIds.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *repoIdentifier = [SeafFPIdentifier identifierForRepo:removedRepoId];
        [identifiersToDelete addObject:SeafFPCoreSpotlightIdentifier(repoIdentifier, domainId)];
    }
    if (removedRepoIds.count > 0 || (!isInitialSync && addedRepoIds.count > 0)) {
        if (!allStoreRecords) {
            allStoreRecords = [store recordsChangedSinceSeq:0 limit:0];
        }
        for (SeafFPRecord *rec in allStoreRecords) {
            if (rec.seq > currentSeq) continue;
            if ([removedRepoIds containsObject:rec.repoId]) {
                [identifiersToDelete addObject:SeafFPCoreSpotlightIdentifier(rec.itemIdentifier, domainId)];
            } else if (!isInitialSync && !rec.deleted && [addedRepoIds containsObject:rec.repoId]) {
                addLiveRecordAndAncestors(rec);
            }
        }
    }

    NSArray<SeafFPRecord *> *changedRecords = [store recordsChangedSinceSeq:spotlightSeq limit:0];
    for (SeafFPRecord *record in changedRecords) {
        if (record.seq > currentSeq) continue;
        if (record.deleted || !repoInfos[record.repoId]) {
            [identifiersToDelete addObject:SeafFPCoreSpotlightIdentifier(record.itemIdentifier, domainId)];
            continue;
        }
        addLiveRecordAndAncestors(record);
    }

    for (NSString *identifier in [store workingSetItemIdentifiersChangedSinceSeq:spotlightSeq]) {
        SeafFPIdentifierKind kind = [SeafFPIdentifier kindOfIdentifier:identifier];
        if (kind == SeafFPIdentifierKindRepo) {
            NSString *repoId = [SeafFPIdentifier repoIdFromIdentifier:identifier];
            if (repoId.length > 0 && repoInfos[repoId]) {
                [repoIdsToIndex addObject:repoId];
            }
        } else if (kind == SeafFPIdentifierKindItem) {
            SeafFPRecord *record = [store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:identifier]];
            if (record && !record.deleted && repoInfos[record.repoId]) {
                addLiveRecordAndAncestors(record);
            }
        }
    }

    NSMutableArray<CSSearchableItem *> *itemsToIndex = [NSMutableArray array];
    NSArray<NSString *> *sortedRepoIds = [repoIdsToIndex.allObjects sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *repoId in sortedRepoIds) {
        NSDictionary *repoInfo = repoInfos[repoId];
        if (!repoInfo) continue;
        NSString *repoIdentifier = [SeafFPIdentifier identifierForRepo:repoId];
        CSSearchableItem *repoItem = SeafFPSearchableItemForRepoInfo(repoInfo, decorations[repoIdentifier], domainId);
        if (repoItem) [itemsToIndex addObject:repoItem];
    }

    NSArray<SeafFPRecord *> *sortedRecords = SeafFPSortSpotlightRecordsParentFirst(recordsByUUID.allValues);
    for (SeafFPRecord *record in sortedRecords) {
        NSDictionary *repoInfo = repoInfos[record.repoId];
        if (!repoInfo) continue;
        BOOL editable = [repoInfo[@"editable"] boolValue];
        CSSearchableItem *csItem = SeafFPSearchableItemForRecord(record, editable, decorations[record.itemIdentifier], domainId);
        if (csItem) [itemsToIndex addObject:csItem];
    }

    NSArray<NSString *> *currentRepoIdList = repoInfos.allKeys ?: @[];
    NSString *currentReposMeta = SeafFPFormatRepoIdsMeta(currentRepoMetaById.allValues);
    NSSet<NSString *> *currentRepoIdSet = [NSSet setWithArray:currentRepoIdList];

    Info("Files app Spotlight prepared %@ up to seq %lld (initial=%d, %lu items to index, %lu to delete)",
         domainId, currentSeq, isInitialSync, (unsigned long)itemsToIndex.count, (unsigned long)identifiersToDelete.count);

    __weak typeof(self) weakSelf = self;
    [self indexSpotlightItems:itemsToIndex
                       offset:0
                     hadError:NO
                      inIndex:index
                     domainId:domainId
                   generation:generation
                   completion:^(BOOL hadError) {
        void (^finishSync)(BOOL) = ^(BOOL syncHadError) {
            typeof(self) innerSelf = weakSelf;
            if (!innerSelf) {
                return;
            }
            dispatch_async(innerSelf->_workQueue, ^{
                BOOL sameGeneration = [innerSelf isDomainActive:domainId generation:generation];
                BOOL active = sameGeneration && [store isOpen];
                if (!syncHadError && active) {
                    [store setMetaValue:[NSString stringWithFormat:@"%lld", currentSeq] forKey:kSeafFPMetaSpotlightSeqKey];
                    [store setMetaValue:currentReposMeta forKey:kSeafFPMetaSpotlightReposKey];
                    os_unfair_lock_lock(&innerSelf->_lock);
                    if (![innerSelf->_deactivatedDomains containsObject:domainId]
                        && [innerSelf->_domainGenerations[domainId] unsignedLongLongValue] == generation) {
                        innerSelf->_indexedRepoIdsByDomain[domainId] = currentRepoIdSet;
                    }
                    os_unfair_lock_unlock(&innerSelf->_lock);
                }
                if (!active && [innerSelf isDomainDeactivated:domainId]) {
                    [innerSelf->_spotlightIndices removeObjectForKey:domainId];
                    [index deleteSearchableItemsWithDomainIdentifiers:@[domainId] completionHandler:^(NSError * _Nullable dropError) {
                        if (dropError) Warning("Files app Spotlight drop failed for %@: %@", domainId, dropError);
                    }];
                }
                [innerSelf finishOrResyncSpotlightForDomainId:domainId
                                               preferredStore:(active ? store : nil)
                                                  allowResync:(!syncHadError || !sameGeneration)];
            });
        };
        typeof(self) innerSelf = weakSelf;
        if (!innerSelf || !innerSelf.enabled || ![innerSelf isDomainActive:domainId generation:generation]) {
            if (innerSelf && [innerSelf isDomainDeactivated:domainId]) {
                [index deleteSearchableItemsWithDomainIdentifiers:@[domainId] completionHandler:^(NSError * _Nullable dropError) {
                    if (dropError) Warning("Files app Spotlight drop failed for %@: %@", domainId, dropError);
                    finishSync(YES);
                }];
            } else {
                finishSync(YES);
            }
            return;
        }
        if (identifiersToDelete.count > 0) {
            [index deleteSearchableItemsWithIdentifiers:identifiersToDelete.array completionHandler:^(NSError * _Nullable error) {
                if (error) Warning("Files app Spotlight delete failed for %@: %@", domainId, error);
                BOOL deleteFailed = (error != nil);
                typeof(self) cbSelf = weakSelf;
                if (!cbSelf || !cbSelf.enabled || ![cbSelf isDomainActive:domainId generation:generation]) {
                    if (cbSelf && [cbSelf isDomainDeactivated:domainId]) {
                        [index deleteSearchableItemsWithDomainIdentifiers:@[domainId] completionHandler:^(NSError * _Nullable dropError) {
                            if (dropError) Warning("Files app Spotlight drop failed for %@: %@", domainId, dropError);
                            finishSync(YES);
                        }];
                    } else {
                        finishSync(YES);
                    }
                    return;
                }
                finishSync(hadError || deleteFailed);
            }];
        } else {
            finishSync(hadError);
        }
    }];
}

- (void)indexSpotlightItems:(NSArray<CSSearchableItem *> *)itemsToIndex
                     offset:(NSUInteger)offset
                   hadError:(BOOL)hadError
                    inIndex:(CSSearchableIndex *)index
                   domainId:(NSString *)domainId
                 completion:(void (^)(BOOL hadError))completion
{
    [self indexSpotlightItems:itemsToIndex
                       offset:offset
                     hadError:hadError
                      inIndex:index
                     domainId:domainId
                   generation:[self generationForDomainId:domainId]
                   completion:completion];
}

- (void)indexSpotlightItems:(NSArray<CSSearchableItem *> *)itemsToIndex
                     offset:(NSUInteger)offset
                   hadError:(BOOL)hadError
                    inIndex:(CSSearchableIndex *)index
                   domainId:(NSString *)domainId
                 generation:(uint64_t)generation
                 completion:(void (^)(BOOL hadError))completion
{
    if (!self.enabled || ![self isDomainActive:domainId generation:generation]) {
        if ([self isDomainDeactivated:domainId]) {
            [index deleteSearchableItemsWithDomainIdentifiers:@[domainId] completionHandler:^(NSError * _Nullable dropError) {
                if (dropError) Warning("Files app Spotlight drop failed for %@: %@", domainId, dropError);
                completion(YES);
            }];
        } else {
            completion(YES);
        }
        return;
    }
    if (offset >= itemsToIndex.count) {
        completion(hadError);
        return;
    }
    NSUInteger batchLen = MIN((NSUInteger)kSeafFPSpotlightBatchSize, itemsToIndex.count - offset);
    NSArray<CSSearchableItem *> *batch = [itemsToIndex subarrayWithRange:NSMakeRange(offset, batchLen)];
    __weak typeof(self) weakSelf = self;
    [index indexSearchableItems:batch completionHandler:^(NSError * _Nullable error) {
        if (error) {
            Warning("Files app Spotlight index batch (%lu..+%lu) failed for %@: %@",
                    (unsigned long)offset, (unsigned long)batchLen, domainId, error);
        } else {
            Info("Files app Spotlight indexed batch (%lu..+%lu) for %@",
                 (unsigned long)offset, (unsigned long)batchLen, domainId);
        }
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.enabled || ![strongSelf isDomainActive:domainId generation:generation]) {
            if (strongSelf && [strongSelf isDomainDeactivated:domainId]) {
                [index deleteSearchableItemsWithDomainIdentifiers:@[domainId] completionHandler:^(NSError * _Nullable dropError) {
                    if (dropError) Warning("Files app Spotlight drop failed for %@: %@", domainId, dropError);
                    completion(YES);
                }];
            } else {
                completion(YES);
            }
            return;
        }
        [strongSelf indexSpotlightItems:itemsToIndex
                                 offset:offset + batchLen
                               hadError:hadError || (error != nil)
                                inIndex:index
                               domainId:domainId
                             generation:generation
                             completion:completion];
    }];
}

/// Work queue only. nil once the domain was deactivated or indexing turned off.
- (nullable SeafFPStore *)storeForDomainId:(NSString *)domainId
{
    if (!self.enabled || [self isDomainDeactivated:domainId]) return nil;
    SeafFPStore *store = _stores[domainId];
    if (!store) {
        NSError *error = nil;
        store = [[SeafFPStore alloc] initWithDomainIdentifier:domainId error:&error];
        if (!store) {
            Warning("Files app indexer cannot open the store of %@: %@", domainId, error);
            return nil;
        }
        _stores[domainId] = store;
    }
    return store;
}

/// Work queue only: the account gets a working set signal when the current task ends.
- (void)noteChangedConnection:(SeafConnection *)conn
{
    if (conn && ![_changedConnections containsObject:conn]) [_changedConnections addObject:conn];
}

/// Runs `work` with the store of `domainId` on the work queue, under a
/// background task: the store only holds its sqlite file (and the -shm
/// lock) inside a request, and the app must not be suspended in one
/// (0xDEAD10CC). Each task is one store transaction, so an expiring
/// background task waits for one short transaction at most.
- (void)enqueueForDomainId:(NSString *)domainId work:(void (^)(SeafFPStore *store))work
{
    uint64_t generation = [self generationForDomainId:domainId];
    if (![self isDomainActive:domainId generation:generation]) return;
    UIApplication *app = [UIApplication sharedApplication];
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    NSObject *token = [NSObject new];
    void (^endTask)(void) = ^{
        UIBackgroundTaskIdentifier ending;
        @synchronized (token) {
            ending = task;
            task = UIBackgroundTaskInvalid;
        }
        if (ending != UIBackgroundTaskInvalid) [app endBackgroundTask:ending];
    };
    @synchronized (token) {
        task = [app beginBackgroundTaskWithName:@"SeafFPIndexer" expirationHandler:^{
            atomic_store(&self->_expired, true);
            endTask();
        }];
    }
    dispatch_async(_workQueue, ^{
        dispatch_group_t finishGroup = dispatch_group_create();
        void (^signalChanged)(NSArray<SeafConnection *> *) = ^(NSArray<SeafConnection *> *changed) {
            if (changed.count == 0) return;
            SeafFileProviderDomainManager *domains = [SeafFileProviderDomainManager shared];
            for (SeafConnection *conn in changed) {
                [domains signalWorkingSetForConnection:conn];
            }
            if (atomic_load(&self->_inBackground)) {
                // The coalesced signal would fire after suspension (the flush in
                // sceneDidEnterBackground ran before this write): send it now and
                // keep the background task until the system answered.
                dispatch_group_enter(finishGroup);
                [domains flushPendingSignalsWithCompletion:^{
                    dispatch_group_leave(finishGroup);
                }];
            }
        };
        if ((!atomic_load(&self->_expired) || !atomic_load(&self->_inBackground))
            && [self isDomainActive:domainId generation:generation]) {
            SeafFPStore *store = [self storeForDomainId:domainId];
            if (store) {
                work(store);
                NSArray<SeafConnection *> *changed = [self->_changedConnections copy];
                [self->_changedConnections removeAllObjects];
                // The shared store is ready for the extension now. Do not hold
                // its working set signal behind a potentially long Spotlight
                // rebuild of the whole account: Files can index these rows
                // independently, including after the app is suspended.
                signalChanged(changed);
                dispatch_group_enter(finishGroup);
                [self syncSpotlightForDomainId:domainId store:store completion:^{
                    dispatch_group_leave(finishGroup);
                }];
            }
        }
        if (self->_changedConnections.count > 0) {
            NSArray<SeafConnection *> *changed = [self->_changedConnections copy];
            [self->_changedConnections removeAllObjects];
            signalChanged(changed);
        }
        dispatch_group_notify(finishGroup, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), endTask);
    });
}

#pragma mark - Entry helpers

/// Sparse entries grouped by library, dropping values that are not trustworthy.
static NSDictionary<NSString *, NSMutableArray<NSDictionary *> *> *SeafFPGroupSparseEntries(NSArray<NSDictionary *> *entries)
{
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *groups = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *repoId = entry[SeafFPIndexKeyRepoId];
        NSString *path = entry[SeafFPIndexKeyPath];
        if (![repoId isKindOfClass:[NSString class]] || repoId.length == 0) continue;
        if (![path isKindOfClass:[NSString class]] || path.length == 0 || [path isEqualToString:@"/"]) continue;
        NSMutableDictionary *clean = [NSMutableDictionary dictionaryWithCapacity:6];
        clean[SeafFPEntryPath] = path;
        clean[SeafFPEntryIsDir] = @([entry[SeafFPIndexKeyIsDir] boolValue]);
        NSString *oid = entry[SeafFPIndexKeyOid];
        if ([oid isKindOfClass:[NSString class]] && oid.length > 0) clean[SeafFPEntryOid] = oid;
        long long size = [entry[SeafFPIndexKeySize] isKindOfClass:[NSNumber class]] ? [entry[SeafFPIndexKeySize] longLongValue] : -1;
        if (size > 0) clean[SeafFPEntrySize] = @(size);     // 0 usually means "not sent"
        long long mtime = [entry[SeafFPIndexKeyMtime] isKindOfClass:[NSNumber class]] ? [entry[SeafFPIndexKeyMtime] longLongValue] : 0;
        if (mtime >= kSeafFPMinPlausibleMtime) clean[SeafFPEntryMtime] = @(mtime);
        NSMutableArray *group = groups[repoId];
        if (!group) groups[repoId] = group = [NSMutableArray array];
        [group addObject:clean];
    }
    return groups;
}

#pragma mark - SeafFPIndexingSink

- (long long)fp_requestStartSeqForConnection:(SeafConnection *)conn
{
    NSString *domainId = [self domainIdForConnection:conn repoId:nil];
    if (!domainId) return -1;
    // Own read-only handle: never queued behind this class's write
    // transactions, never creates a store that was removed.
    return [SeafFPStore currentSeqForDomainIdentifier:domainId];
}

- (NSString *)moveKeyForDomainId:(NSString *)domainId repoId:(NSString *)repoId directoryPath:(NSString *)directoryPath
{
    NSString *normDir = [SeafFPIdentifier normalizedPath:directoryPath];
    return [NSString stringWithFormat:@"%@|%@|%@", domainId ?: @"", repoId ?: @"", normDir ?: @"/"];
}

- (void)beginPendingMoveForKey:(NSString *)moveKey
{
    if (moveKey.length == 0) return;
    os_unfair_lock_lock(&_lock);
    NSUInteger count = [_pendingMoveCounts[moveKey] unsignedIntegerValue];
    _pendingMoveCounts[moveKey] = @(count + 1);
    os_unfair_lock_unlock(&_lock);
}

- (void)finishPendingMoveForKey:(NSString *)moveKey
{
    if (moveKey.length == 0) return;
    NSArray<dispatch_block_t> *deferred = nil;
    os_unfair_lock_lock(&_lock);
    NSUInteger count = [_pendingMoveCounts[moveKey] unsignedIntegerValue];
    if (count <= 1) {
        [_pendingMoveCounts removeObjectForKey:moveKey];
        deferred = [_deferredDirWork[moveKey] copy];
        [_deferredDirWork removeObjectForKey:moveKey];
    } else {
        _pendingMoveCounts[moveKey] = @(count - 1);
    }
    os_unfair_lock_unlock(&_lock);
    for (dispatch_block_t block in deferred) {
        block();
    }
}

- (void)fp_indexListing:(NSArray<NSDictionary *> *)entries
                 ofRepo:(NSString *)repoId
              directory:(NSString *)directoryPath
             connection:(SeafConnection *)conn
        requestStartSeq:(long long)requestStartSeq
{
    NSString *domainId = [self domainIdForConnection:conn repoId:repoId];
    if (!domainId || directoryPath.length == 0) return;
    uint64_t generation = [self generationForDomainId:domainId];
    NSArray *snapshot = [entries copy];
    __weak typeof(self) weakSelf = self;
    __weak SeafConnection *weakConn = conn;
    NSString *moveKey = [self moveKeyForDomainId:domainId repoId:repoId directoryPath:directoryPath];
    BOOL defer = NO;
    os_unfair_lock_lock(&_lock);
    if ([_pendingMoveCounts[moveKey] unsignedIntegerValue] > 0) {
        defer = YES;
    }
    dispatch_block_t enqueueListing = ^{
        typeof(self) strongSelf = weakSelf;
        SeafConnection *strongConn = weakConn;
        if (!strongSelf || !strongConn || ![strongSelf isDomainActive:domainId generation:generation]) return;
        [strongSelf enqueueForDomainId:domainId work:^(SeafFPStore *store) {
            if (![strongSelf isDomainActive:domainId generation:generation]) return;
            BOOL applied = [store applyListingOfRepo:repoId directoryPath:directoryPath entries:snapshot requestStartSeq:requestStartSeq];
            if (applied || requestStartSeq >= 0) {
                [strongSelf noteChangedConnection:strongConn];
            }
            if (!applied && requestStartSeq >= 0 && [store currentSeq] > requestStartSeq) {
                [strongSelf fp_refreshDirectoryOfRepo:repoId path:directoryPath connection:strongConn];
            }
        }];
    };
    if (defer) {
        NSMutableArray<dispatch_block_t> *queue = _deferredDirWork[moveKey];
        if (!queue) _deferredDirWork[moveKey] = queue = [NSMutableArray array];
        [queue addObject:[enqueueListing copy]];
    }
    os_unfair_lock_unlock(&_lock);
    if (!defer) {
        enqueueListing();
    }
}

- (void)fp_indexSparseEntries:(NSArray<NSDictionary *> *)entries
                   connection:(SeafConnection *)conn
                  allowRevive:(BOOL)allowRevive
{
    if (![self domainIdForConnection:conn repoId:nil]) return;
    [SeafFPGroupSparseEntries(entries) enumerateKeysAndObjectsUsingBlock:^(NSString *repoId, NSMutableArray<NSDictionary *> *group, BOOL *stop) {
        NSString *domainId = [self domainIdForConnection:conn repoId:repoId];
        if (!domainId) return;
        [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
            if ([store applySparseEntriesOfRepo:repoId entries:group allowRevive:allowRevive]) {
                [self noteChangedConnection:conn];
            }
        }];
    }];
}

- (void)fp_indexStarredItems:(NSArray<NSDictionary *> *)items connection:(SeafConnection *)conn
{
    if (![self domainIdForConnection:conn repoId:nil]) return;
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:items.count];
    for (NSDictionary *info in items) {
        if (![info isKindOfClass:[NSDictionary class]]) continue;
        if ([info[@"deleted"] respondsToSelector:@selector(boolValue)] && [info[@"deleted"] boolValue]) continue;   // gone on the server
        NSString *repoId = info[@"repo_id"];
        NSString *path = info[@"path"];
        if (![repoId isKindOfClass:[NSString class]] || ![path isKindOfClass:[NSString class]]) continue;
        if (path.length == 0 || [path isEqualToString:@"/"]) continue;   // a starred library, not an item
        BOOL isDir = [info[@"is_dir"] respondsToSelector:@selector(boolValue)] && [info[@"is_dir"] boolValue];
        long long mtime = 0;
        id rawMtime = info[@"mtime"];
        if ([rawMtime isKindOfClass:[NSString class]]) {
            mtime = [Utils convertTimeStringToUTC:rawMtime];
        } else if ([rawMtime isKindOfClass:[NSNumber class]]) {
            mtime = [rawMtime longLongValue];
        }
        // No oid and no size in starred items: the stored values are kept.
        [entries addObject:@{SeafFPIndexKeyRepoId: repoId, SeafFPIndexKeyPath: path,
                             SeafFPIndexKeyIsDir: @(isDir), SeafFPIndexKeyMtime: @(mtime)}];
    }
    [self fp_indexSparseEntries:entries connection:conn allowRevive:NO];
}

- (void)fp_indexRenameOf:(NSString *)oldName
                      to:(NSString *)newName
                  ofRepo:(NSString *)repoId
               directory:(NSString *)directoryPath
                 listing:(NSArray<NSDictionary *> *)entries
              connection:(SeafConnection *)conn
         requestStartSeq:(long long)requestStartSeq
{
    NSString *domainId = [self domainIdForConnection:conn repoId:repoId];
    if (!domainId || directoryPath.length == 0) return;
    NSArray *snapshot = [entries copy];
    [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
        BOOL changed = [store renameRecordOfRepo:repoId
                                       directory:directoryPath
                                        fromName:oldName
                                          toName:newName
                                         listing:snapshot
                                 requestStartSeq:requestStartSeq];
        if (!changed && snapshot) {
            // The store did not know the entry: the listing brings in the new name.
            changed = [store applyListingOfRepo:repoId directoryPath:directoryPath entries:snapshot requestStartSeq:requestStartSeq];
        }
        if (!changed && (!snapshot || requestStartSeq < 0 || [store currentSeq] > requestStartSeq)) {
            [self fp_refreshDirectoryOfRepo:repoId path:directoryPath connection:conn];
        }
        if (changed) [self noteChangedConnection:conn];
    }];
}

- (void)fp_indexMoveOf:(NSArray<NSString *> *)names
              fromRepo:(NSString *)srcRepoId
         fromDirectory:(NSString *)srcDirectoryPath
                toRepo:(NSString *)dstRepoId
           toDirectory:(NSString *)dstDirectoryPath
         sourceListing:(NSArray<NSDictionary *> *)entries
            connection:(SeafConnection *)conn
       requestStartSeq:(long long)requestStartSeq
{
    NSString *srcDomainId = [self domainIdForConnection:conn repoId:srcRepoId];
    BOOL dstVisible = [self domainIdForConnection:conn repoId:dstRepoId] != nil;
    if (!srcDomainId) {
        // Source not indexable (locked library, say): the destination may still be.
        if (dstVisible) [self fp_refreshDirectoryOfRepo:dstRepoId path:dstDirectoryPath connection:conn];
        return;
    }
    uint64_t generation = [self generationForDomainId:srcDomainId];
    NSArray *namesCopy = [names copy];
    NSArray *snapshot = [entries copy];
    if (!dstVisible) {
        [self enqueueForDomainId:srcDomainId work:^(SeafFPStore *store) {
            if (![self isDomainActive:srcDomainId generation:generation]) return;
            BOOL changed = snapshot ? [store applyListingOfRepo:srcRepoId
                                                  directoryPath:srcDirectoryPath
                                                        entries:snapshot
                                                requestStartSeq:requestStartSeq] : NO;
            if (!changed && (!snapshot || requestStartSeq < 0 || [store currentSeq] > requestStartSeq)) {
                [self fp_refreshDirectoryOfRepo:srcRepoId path:srcDirectoryPath connection:conn];
            }
            if (changed) [self noteChangedConnection:conn];
        }];
        return;
    }

    // Fetch the destination directory listing first so moveRecordsOfRepo: can
    // confirm the actual server-assigned filenames (including conflict renames
    // such as "report (1).txt") before migrating any UUID. Concurrent source
    // and destination directory listings are deferred until the destination
    // check finishes so they cannot race against UUID migration.
    NSString *moveKey = [self moveKeyForDomainId:srcDomainId repoId:srcRepoId directoryPath:srcDirectoryPath];
    NSString *dstMoveKey = [self moveKeyForDomainId:srcDomainId repoId:dstRepoId directoryPath:dstDirectoryPath];
    BOOL hasDistinctDstKey = ![dstMoveKey isEqualToString:moveKey];
    [self beginPendingMoveForKey:moveKey];
    if (hasDistinctDstKey) [self beginPendingMoveForKey:dstMoveKey];
    NSString *dstName = [dstDirectoryPath isEqualToString:@"/"] ? @"" : dstDirectoryPath.lastPathComponent;
    SeafDir *dstDir = [[SeafDir alloc] initWithConnection:conn oid:nil repoId:dstRepoId perm:nil name:dstName path:dstDirectoryPath mtime:0];
    __weak typeof(self) weakSelf = self;
    __weak SeafConnection *weakConn = conn;
    [conn sendRequest:dstDir.url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        typeof(self) strongSelf = weakSelf;
        SeafConnection *strongConn = weakConn;
        if (!strongSelf || ![strongSelf isDomainActive:srcDomainId generation:generation]) {
            return;
        }
        if (!strongConn) {
            [strongSelf finishPendingMoveForKey:moveKey];
            if (hasDistinctDstKey) [strongSelf finishPendingMoveForKey:dstMoveKey];
            return;
        }
        [dstDir handleResponse:response json:JSON];
        NSArray<NSDictionary *> *dstSnapshot = [dstDir fp_listingSnapshotForResponse:JSON];
        [strongSelf enqueueForDomainId:srcDomainId work:^(SeafFPStore *store) {
            if (![strongSelf isDomainActive:srcDomainId generation:generation]) return;
            BOOL moved = NO;
            if (dstSnapshot) {
                moved = [store moveRecordsOfRepo:srcRepoId
                                   fromDirectory:srcDirectoryPath
                                           names:namesCopy
                                          toRepo:dstRepoId
                                     toDirectory:dstDirectoryPath
                              destinationEntries:dstSnapshot
                                 requestStartSeq:requestStartSeq];
            }
            if (moved) {
                if (snapshot) {
                    [store applyListingOfRepo:srcRepoId directoryPath:srcDirectoryPath entries:snapshot requestStartSeq:-1];
                }
                [strongSelf noteChangedConnection:strongConn];
                NSString *normSrcDir = [SeafFPIdentifier normalizedPath:srcDirectoryPath];
                for (NSString *name in namesCopy) {
                    if (name.length == 0 || [name containsString:@"/"]) continue;
                    NSString *srcPath = [SeafFPIdentifier normalizedPath:[normSrcDir stringByAppendingFormat:@"/%@", name]];
                    if ([store recordForRepo:srcRepoId path:srcPath includeDeleted:NO]) {
                        [strongSelf fp_refreshDirectoryOfRepo:srcRepoId path:srcDirectoryPath connection:strongConn];
                        break;
                    }
                }
                return;
            }
            BOOL srcApplied = snapshot ? [store applyListingOfRepo:srcRepoId
                                                     directoryPath:srcDirectoryPath
                                                           entries:snapshot
                                                   requestStartSeq:requestStartSeq] : NO;
            BOOL dstApplied = dstSnapshot ? [store applyListingOfRepo:dstRepoId
                                                        directoryPath:dstDirectoryPath
                                                              entries:dstSnapshot
                                                      requestStartSeq:requestStartSeq] : NO;
            if (srcApplied || dstApplied) {
                [strongSelf noteChangedConnection:strongConn];
            }
            BOOL seqAdvanced = (requestStartSeq < 0 || [store currentSeq] > requestStartSeq);
            if (!srcApplied && (!snapshot || seqAdvanced)) {
                [strongSelf fp_refreshDirectoryOfRepo:srcRepoId path:srcDirectoryPath connection:strongConn];
            }
            if (!dstApplied && (!dstSnapshot || seqAdvanced)) {
                [strongSelf fp_refreshDirectoryOfRepo:dstRepoId path:dstDirectoryPath connection:strongConn];
            }
        }];
        [strongSelf finishPendingMoveForKey:moveKey];
        if (hasDistinctDstKey) [strongSelf finishPendingMoveForKey:dstMoveKey];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        SeafConnection *strongConn = weakConn;
        if (!strongSelf || ![strongSelf isDomainActive:srcDomainId generation:generation]) {
            return;
        }
        if (!strongConn) {
            [strongSelf finishPendingMoveForKey:moveKey];
            if (hasDistinctDstKey) [strongSelf finishPendingMoveForKey:dstMoveKey];
            return;
        }
        [strongSelf enqueueForDomainId:srcDomainId work:^(SeafFPStore *store) {
            if (![strongSelf isDomainActive:srcDomainId generation:generation]) return;
            BOOL srcApplied = snapshot ? [store applyListingOfRepo:srcRepoId
                                                     directoryPath:srcDirectoryPath
                                                           entries:snapshot
                                                   requestStartSeq:requestStartSeq] : NO;
            if (srcApplied) [strongSelf noteChangedConnection:strongConn];
            if (!srcApplied && (!snapshot || requestStartSeq < 0 || [store currentSeq] > requestStartSeq)) {
                [strongSelf fp_refreshDirectoryOfRepo:srcRepoId path:srcDirectoryPath connection:strongConn];
            }
        }];
        [strongSelf finishPendingMoveForKey:moveKey];
        if (hasDistinctDstKey) [strongSelf finishPendingMoveForKey:dstMoveKey];
        [strongSelf fp_refreshDirectoryOfRepo:dstRepoId path:dstDirectoryPath connection:strongConn];
    }];
}

- (void)fp_refreshDirectoryOfRepo:(NSString *)repoId path:(NSString *)path connection:(SeafConnection *)conn
{
    NSString *domainId = [self domainIdForConnection:conn repoId:repoId];
    if (!domainId || path.length == 0) return;
    uint64_t generation = [self generationForDomainId:domainId];
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", domainId, repoId, path];
    os_unfair_lock_lock(&_lock);
    BOOL pending = [_pendingRefreshes containsObject:key];
    if (!pending) [_pendingRefreshes addObject:key];
    os_unfair_lock_unlock(&_lock);
    if (pending) return;
    __weak SeafConnection *weakConn = conn;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSeafFPRefreshCoalesceInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        os_unfair_lock_lock(&self->_lock);
        [self->_pendingRefreshes removeObject:key];
        os_unfair_lock_unlock(&self->_lock);
        if (![self isDomainActive:domainId generation:generation]) return;
        SeafConnection *connection = weakConn;
        if (!connection || ![self domainIdForConnection:connection repoId:repoId]) return;
        // A private directory object without delegate: its listing reaches
        // the index through -[SeafDir loadContentSuccess:failure:] like any other.
        NSString *name = [path isEqualToString:@"/"] ? @"" : path.lastPathComponent;
        SeafDir *dir = [[SeafDir alloc] initWithConnection:connection oid:nil repoId:repoId perm:nil name:name path:path mtime:0];
        [dir loadContentSuccess:nil failure:nil];
    });
}

- (void)fp_noteDownloadedFileOfRepo:(NSString *)repoId
                               path:(NSString *)path
                                oid:(NSString *)oid
                               size:(long long)size
                         connection:(SeafConnection *)conn
{
    NSString *domainId = [self domainIdForConnection:conn repoId:repoId];
    if (!domainId || oid.length == 0) return;
    [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
        // Fill-in only, never a new row: a stored oid may be newer.
        if ([store noteLastUsedDate:nil forRepo:repoId path:path oid:oid size:size mtime:0 createIfMissing:NO]) {
            [self noteChangedConnection:conn];
        }
    }];
}

#pragma mark - Opened files

- (void)noteFileOpened:(SeafFile *)file
{
    if (![file isKindOfClass:[SeafFile class]]) return;
    SeafConnection *conn = file.connection;
    NSString *repoId = file.repoId;
    NSString *path = file.path;
    if (!conn || repoId.length == 0 || path.length == 0) return;
    NSString *domainId = [self domainIdForConnection:conn repoId:repoId];
    if (!domainId) return;
    NSDate *now = [NSDate date];
    NSString *oid = file.oid;
    long long size = (long long)file.filesize;
    long long mtime = file.mtime;
    [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
        if ([store noteLastUsedDate:now forRepo:repoId path:path oid:oid size:size mtime:mtime createIfMissing:YES]) {
            [self noteChangedConnection:conn];
        }
    }];
}

#pragma mark - Activity log

static NSString *SeafFPString(id value)
{
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? value : nil;
}

static long long SeafFPEventTime(id value)
{
    NSString *text = SeafFPString(value);
    return text ? [Utils convertTimeStringToUTC:text] : 0;
}

/// One activity event as store entries, oldest first. Field names checked
/// against seahub api2/endpoints/activities.py and seafevents
/// events/handlers.py: path is the path after the operation, old_path the
/// one before a move / rename (same library: moves across libraries are
/// logged as delete + create), details (14.0+) the items of a batch.
static NSArray<NSDictionary *> *SeafFPActivityEntries(NSDictionary *event)
{
    NSString *op = SeafFPString(event[@"op_type"]);
    NSString *objType = SeafFPString(event[@"obj_type"]);
    NSString *path = SeafFPString(event[@"path"]);
    NSString *name = SeafFPString(event[@"name"]) ?: path.lastPathComponent;
    if (!op || !objType || [objType isEqualToString:@"repo"] || [op isEqualToString:@"clean-up-trash"]) return @[];
    if (![op isEqualToString:@"publish"] && ([objType containsString:@"draft"] || [name hasSuffix:@"(draft).md"])) return @[];
    BOOL isDir = [objType isEqualToString:@"dir"];
    long long eventTime = SeafFPEventTime(event[@"time"]);

    NSString *storeOp = nil;
    if ([@[@"create", @"edit", @"update", @"recover", @"restore", @"publish"] containsObject:op]) {
        storeOp = SeafFPActivityOpCreate;
    } else if ([op isEqualToString:@"delete"]) {
        storeOp = SeafFPActivityOpDelete;
    } else if ([op isEqualToString:@"rename"] || [op isEqualToString:@"move"]) {
        storeOp = SeafFPActivityOpMove;
    } else if ([op isEqualToString:@"batch_create"] || [op isEqualToString:@"batch_delete"]) {
        NSString *itemOp = [op isEqualToString:@"batch_create"] ? SeafFPActivityOpCreate : SeafFPActivityOpDelete;
        NSArray *details = [event[@"details"] isKindOfClass:[NSArray class]] ? event[@"details"] : nil;
        NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
        for (NSDictionary *detail in details) {
            if (![detail isKindOfClass:[NSDictionary class]]) continue;
            NSString *itemPath = SeafFPString(detail[@"path"]);
            if (!itemPath || [itemPath isEqualToString:@"/"]) continue;
            // Details carry no time of their own (the client backfills the event's).
            long long itemTime = SeafFPEventTime(detail[@"time"]) ?: eventTime;
            [entries addObject:@{SeafFPEntryOp: itemOp, SeafFPEntryPath: itemPath,
                                 SeafFPEntryIsDir: @(isDir), SeafFPEntryMtime: @(itemTime)}];
        }
        if (entries.count == 0 && path && ![path isEqualToString:@"/"]) {
            [entries addObject:@{SeafFPEntryOp: itemOp, SeafFPEntryPath: path,
                                 SeafFPEntryIsDir: @(isDir), SeafFPEntryMtime: @(eventTime)}];
        }
        return entries;
    }
    if (!storeOp || !path || [path isEqualToString:@"/"]) return @[];
    NSMutableDictionary *entry = [@{SeafFPEntryOp: storeOp, SeafFPEntryPath: path,
                                    SeafFPEntryIsDir: @(isDir), SeafFPEntryMtime: @(eventTime)} mutableCopy];
    if ([storeOp isEqualToString:SeafFPActivityOpMove]) {
        NSString *oldPath = SeafFPString(event[@"old_path"]);
        if (!oldPath && [op isEqualToString:@"rename"]) {
            NSString *oldName = SeafFPString(isDir ? event[@"old_dir_name"] : event[@"old_name"]) ?: SeafFPString(event[@"old_name"]);
            if (oldName && ![oldName containsString:@"/"]) {
                oldPath = [path.stringByDeletingLastPathComponent stringByAppendingPathComponent:oldName];
            }
        }
        if (oldPath) entry[SeafFPEntryOldPath] = oldPath;   // without it: a create of the new path
    }
    return @[entry];
}

- (void)indexActivityEvents:(NSArray *)events connection:(SeafConnection *)conn
{
    if (![events isKindOfClass:[NSArray class]] || events.count == 0 || !conn) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self indexActivityEvents:events connection:conn]; });
        return;
    }
    if (![self canIndexActivitiesOfConnection:conn]) return;
    _activityFetchedAt[[SeafFileProviderDomainManager domainIdentifierForConnection:conn]] = [NSDate date];

    // The API lists the newest event first; the store replays oldest first.
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *byRepo = [NSMutableDictionary dictionary];
    for (NSDictionary *event in events.reverseObjectEnumerator) {
        if (![event isKindOfClass:[NSDictionary class]]) continue;
        NSString *repoId = SeafFPString(event[@"repo_id"]);
        if (!repoId) continue;
        NSArray<NSDictionary *> *entries = SeafFPActivityEntries(event);
        if (entries.count == 0) continue;
        NSMutableArray *group = byRepo[repoId];
        if (!group) byRepo[repoId] = group = [NSMutableArray array];
        [group addObjectsFromArray:entries];
    }
    [byRepo enumerateKeysAndObjectsUsingBlock:^(NSString *repoId, NSMutableArray<NSDictionary *> *entries, BOOL *stop) {
        NSString *domainId = [self domainIdForConnection:conn repoId:repoId];
        if (!domainId) return;   // library not loaded, locked or gone
        [self enqueueForDomainId:domainId work:^(SeafFPStore *store) {
            if ([store applyActivitiesOfRepo:repoId entries:entries]) {
                [self noteChangedConnection:conn];
            }
        }];
    }];
}

#pragma mark - SeafFileProviderDomainObserver

- (void)fileProviderDomainDidActivate:(NSString *)domainIdentifier
{
    if (domainIdentifier.length == 0) return;
    os_unfair_lock_lock(&_lock);
    if ([_deactivatedDomains containsObject:domainIdentifier]) {
        [_deactivatedDomains removeObject:domainIdentifier];
        uint64_t nextGen = [_domainGenerations[domainIdentifier] unsignedLongLongValue] + 1;
        _domainGenerations[domainIdentifier] = @(nextGen);
    }
    os_unfair_lock_unlock(&_lock);
}

- (void)fileProviderDomainWillDeactivate:(NSString *)domainIdentifier
{
    if (domainIdentifier.length == 0) return;
    [self deactivateDomain:domainIdentifier then:nil];
}

- (void)fileProviderDomainWillRemoveStore:(NSString *)domainIdentifier removeStore:(dispatch_block_t)removeStore
{
    if (domainIdentifier.length == 0) {
        if (removeStore) removeStore();
        return;
    }
    [self deactivateDomain:domainIdentifier then:removeStore];
}

/// Blocks new and queued writes right away (lock, no waiting on the work
/// queue), then closes the domain's store on the work queue -- after every
/// task queued before -- and runs `then` there.
- (void)deactivateDomain:(NSString *)domainIdentifier then:(nullable dispatch_block_t)then
{
    os_unfair_lock_lock(&_lock);
    [_deactivatedDomains addObject:domainIdentifier];
    [_repoInfosByDomain removeObjectForKey:domainIdentifier];
    [_indexedRepoIdsByDomain removeObjectForKey:domainIdentifier];
    uint64_t nextGen = [_domainGenerations[domainIdentifier] unsignedLongLongValue] + 1;
    _domainGenerations[domainIdentifier] = @(nextGen);
    NSString *movePrefix = [domainIdentifier stringByAppendingString:@"|"];
    for (NSString *key in [_pendingMoveCounts.allKeys copy]) {
        if ([key hasPrefix:movePrefix]) {
            [_pendingMoveCounts removeObjectForKey:key];
            [_deferredDirWork removeObjectForKey:key];
        }
    }
    os_unfair_lock_unlock(&_lock);
    dispatch_async(_workQueue, ^{
        [self->_spotlightNeedsResyncDomains removeObject:domainIdentifier];
        SeafFPStore *store = self->_stores[domainIdentifier];
        if ([store isOpen]) {
            [store setMetaValue:nil forKey:kSeafFPMetaSpotlightSeqKey];
            [store setMetaValue:nil forKey:kSeafFPMetaSpotlightReposKey];
        }
        [store close];
        [self->_stores removeObjectForKey:domainIdentifier];
        CSSearchableIndex *index = [self spotlightIndexForDomainId:domainIdentifier];
        [self->_spotlightIndices removeObjectForKey:domainIdentifier];
        [index deleteSearchableItemsWithDomainIdentifiers:@[domainIdentifier] completionHandler:^(NSError * _Nullable error) {
            if (error) Warning("Files app Spotlight drop failed for %@: %@", domainIdentifier, error);
        }];
        if (then) then();
    });
}

@end
