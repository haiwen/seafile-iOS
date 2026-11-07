#!/usr/bin/env python3
"""Exercise production public enumeration, item projection and signal recovery.

Only application models and the system transport are replaced. The Store,
item projection, pagination, change observer and notification algorithms run
from the production sources, without requiring UIKit on the test host.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
enum = (root / 'SeafFileProvider/SeafFPEnumerator.m').read_text()
extension = (root / 'SeafFileProvider/SeafFPExtension.m').read_text()
index = (root / 'common/Classes/SeafFPIndexer.m').read_text()
manager = (root / 'common/Classes/SeafFileProviderDomainManager.m').read_text()
item = (root / 'SeafFileProvider/SeafFPItem.m').read_text()

def between(src, first, last):
    return src[src.index(first):src.index(last, src.index(first))]

header = r'''
#import <Foundation/Foundation.h>
#import <FileProvider/FileProvider.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <errno.h>
#import <limits.h>
#import <sqlite3.h>
#import "SeafFPStore.h"
#import "SeafFPIdentifier.h"
#import "SeafFPItem.h"
#import "SeafFPErrors.h"
#define Info(...) do {} while(0)
#define Debug(...) do {} while(0)
#define Warning(...) do {} while(0)
static NSString *gTestDir;
static int passes, failures;
#define CHECK(c) do { if (!(c)) { failures++; NSLog(@"FAIL line %d: %s", __LINE__, #c); } else passes++; } while(0)
static BOOL isMovePending(NSError *error) {
    return [error.domain isEqual:NSCocoaErrorDomain] && error.code == NSXPCConnectionReplyInvalid
        && [error.userInfo[@"reason"] isEqual:@"movePending"];
}
@implementation SeafFPIdentifier (PublicTest)
+ (NSURL *)storeDirectoryURL { return [NSURL fileURLWithPath:gTestDir isDirectory:YES]; }
+ (NSURL *)storeURLForDomainIdentifier:(NSString *)identifier { return [[self storeDirectoryURL] URLByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"sqlite"]]; }
@end
@interface Utils : NSObject
+ (long long)convertTimeStringToUTC:(NSString *)text;
+ (NSString *)creatNewFileName:(NSString *)name;
@end
@implementation Utils
+ (NSString *)creatNewFileName:(NSString *)name { return [name stringByAppendingString:@" (1)"]; }
+ (long long)convertTimeStringToUTC:(NSString *)text { return (long long)[[[NSISO8601DateFormatter new] dateFromString:text] timeIntervalSince1970]; }
@end
@class SeafConnection;
@interface SeafBase : NSObject
@property NSString *repoId;
@property NSString *name;
@property NSString *path;
@property NSString *oid;
@property long long mtime;
@end
@implementation SeafBase @end
@interface SeafDir : SeafBase
@property NSString *ooid;
@property NSString *perm;
@property NSArray<SeafBase *> *items;
- (NSString *)actualNameForCaseInsensitiveMatch:(NSString *)name;
- (instancetype)initWithConnection:(SeafConnection *)c oid:(NSString *)oid repoId:(NSString *)repoId perm:(NSString *)perm name:(NSString *)name path:(NSString *)path mtime:(long long)mtime;
@end
@interface SeafFile : SeafBase
@property long long filesize;
@end
@implementation SeafFile @end
@implementation SeafDir
- (NSString *)actualNameForCaseInsensitiveMatch:(NSString *)name {
    for (SeafBase *entry in self.items) if ([entry.name caseInsensitiveCompare:name] == NSOrderedSame) return entry.name;
    return nil;
}
- (instancetype)initWithConnection:(SeafConnection *)c oid:(NSString *)oid repoId:(NSString *)repoId perm:(NSString *)perm name:(NSString *)name path:(NSString *)path mtime:(long long)mtime {
    if ((self = [super init])) { self.oid = oid; self.repoId = repoId; self.perm = perm; self.name = name; self.path = path; self.mtime = mtime; }
    return self;
}
@end
static void (^gBeforeMoveResponse)(void);
static NSError *gMoveError;
static NSUInteger gMoveRequests;
static NSInteger gMoveStatus;
static BOOL gDropMoveReply;
static void (^gServerRelocate)(SeafDir *, SeafDir *, NSString *, NSString *);
@interface SeafFileOperationManager : NSObject
+ (instancetype)sharedManager;
- (void)moveEntries:(NSArray *)entries fromDir:(SeafDir *)src toDir:(SeafDir *)dst
 responseCompletion:(void (^)(BOOL, NSError *, NSHTTPURLResponse *))completion;
- (void)renameEntry:(NSString *)oldName newName:(NSString *)name inDir:(SeafDir *)src
 responseCompletion:(void (^)(BOOL, SeafBase *, NSError *, NSHTTPURLResponse *))completion;
- (void)deleteEntries:(NSArray *)entries inDir:(SeafDir *)dir completion:(void (^)(BOOL, NSError *))completion;
@end
static NSMutableArray<NSString *> *gDeletedPaths;
@implementation SeafFileOperationManager
+ (instancetype)sharedManager { return [self new]; }
- (void)performFrom:(SeafDir *)source to:(SeafDir *)destination oldName:(NSString *)oldName newName:(NSString *)name
        completion:(void (^)(BOOL, NSError *, NSHTTPURLResponse *))completion {
    gMoveRequests++;
    if (gBeforeMoveResponse) gBeforeMoveResponse();
    if (gServerRelocate) gServerRelocate(source, destination, oldName, name);
    if (gDropMoveReply) return;
    NSHTTPURLResponse *response = gMoveStatus ? [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://seafile.test/"]
        statusCode:gMoveStatus HTTPVersion:@"HTTP/1.1" headerFields:nil] : nil;
    NSError *error = gMoveError;
    if (error && response) {
        error = [NSError errorWithDomain:error.domain code:error.code userInfo:@{@"com.alamofire.serialization.response.error.response": response}];
    }
    completion(error == nil, error, response);
}
- (void)moveEntries:(NSArray *)entries fromDir:(SeafDir *)src toDir:(SeafDir *)dst
 responseCompletion:(void (^)(BOOL, NSError *, NSHTTPURLResponse *))completion {
    [self performFrom:src to:dst oldName:entries.firstObject newName:entries.firstObject completion:completion];
}
- (void)renameEntry:(NSString *)oldName newName:(NSString *)name inDir:(SeafDir *)src
 responseCompletion:(void (^)(BOOL, SeafBase *, NSError *, NSHTTPURLResponse *))completion {
    [self performFrom:src to:src oldName:oldName newName:name completion:^(BOOL ok, NSError *error, NSHTTPURLResponse *response) {
        completion(ok, nil, error, response);
    }];
}
- (void)deleteEntries:(NSArray *)entries inDir:(SeafDir *)dir completion:(void (^)(BOOL, NSError *))completion {
    if (!gDeletedPaths) gDeletedPaths = [NSMutableArray array];
    [gDeletedPaths addObject:[NSString stringWithFormat:@"%@:%@", dir.repoId, [dir.path stringByAppendingPathComponent:entries.firstObject]]];
    completion(YES, nil);
}
@end
@interface SeafRepo : SeafDir
@property NSString *ooid;
@property BOOL editable;
@property BOOL passwordRequired;
@end
@implementation SeafRepo @end
@interface SeafRepos : NSObject
@property NSArray<SeafRepo *> *items;
@property NSMutableArray *callbacks;
- (NSArray *)fp_repositorySnapshot;
- (void)loadContentSuccess:(void (^)(SeafDir *))success failure:(void (^)(SeafDir *,NSError *))failure;
- (BOOL)loadCache;
- (BOOL)hasCache;
@end
@implementation SeafRepos
- (void)loadContentSuccess:(void (^)(SeafDir *))success failure:(void (^)(SeafDir *,NSError *))failure { if(!self.callbacks) self.callbacks=[NSMutableArray array]; if(success) [self.callbacks addObject:[success copy]]; }
- (BOOL)loadCache { return NO; }
- (BOOL)hasCache { return self.items.count>0; }
- (NSArray *)fp_repositorySnapshot {
    NSMutableArray *a = [NSMutableArray array];
    for (SeafRepo *r in self.items) [a addObject:@{@"repoId":r.repoId, @"name":r.name ?: r.repoId, @"perm":r.perm ?: @"rw", @"editable":@(r.editable), @"mtime":@(r.mtime), @"ooid":r.ooid ?: @"", @"locked":@(r.passwordRequired)}];
    return a;
}
@end
@interface SeafConnection : NSObject
@property SeafRepos *rootFolder;
- (SeafRepo *)getRepo:(NSString *)repoId;
@end
@implementation SeafConnection
- (SeafRepo *)getRepo:(NSString *)repoId {
    for (SeafRepo *repo in self.rootFolder.items) if ([repo.repoId isEqual:repoId]) return repo;
    return nil;
}
@end
@interface SeafGlobal : NSObject
@property NSArray *conns;
+ (instancetype)sharedObject;
@end
@implementation SeafGlobal
+ (instancetype)sharedObject { static SeafGlobal *g; static dispatch_once_t once; dispatch_once(&once, ^{ g = [self new]; }); return g; }
@end
''' + between(extension, '/// What the listings say about a journaled move.', 'static long long SeafFPServerTime(') + r'''
@interface TestExtension : NSObject
@property SeafFPStore *store;
@property SeafConnection *connection;
@property NSCache *seafObjects;
@property SeafDir *loadedDirectory;
@property BOOL failDirectoryLoad;
@property NSSet<NSString *> *failingDirectories;
@property NSDictionary<NSString *, NSString *> *directory404Bodies;
@property NSString *uploadedPath;
@property NSDictionary<NSString *, NSArray *> *liveListings;
- (SeafFPItem *)itemForRepositoryState:(NSDictionary *)state;
- (void)scheduleWorkingSetRecheckAt:(NSDate *)date;
- (void)noteSuccess;
- (void)noteError:(NSError *)error;
- (SeafRepo *)repoWithId:(NSString *)repoId;
- (BOOL)isRepoEditable:(NSString *)repoId;
- (NSError *)localAccessError;
- (NSError *)accessError;
- (SeafFPItem *)itemForRecord:(SeafFPRecord *)record;
- (SeafFPItem *)resolveItem:(NSFileProviderItemIdentifier)identifier error:(NSError **)error;
- (void)applyDecorationChangesFromItem:(NSFileProviderItem)item changedFields:(NSFileProviderItemFields)fields toItem:(SeafFPItem *)current;
- (NSURL *)stageUploadSource:(NSURL *)url name:(NSString *)name error:(NSError **)error;
- (void)uploadStagedFile:(NSURL *)stagedURL repoId:(NSString *)repoId path:(NSString *)path parentUUID:(NSString *)parentUUID
        creationStartSeq:(NSNumber *)creationStartSeq progress:(NSProgress *)progress
              completion:(void (^)(SeafFPRecord *, NSError *))completion;
- (NSProgress *)modifyItem:(NSFileProviderItem)item baseVersion:(NSFileProviderItemVersion *)version
             changedFields:(NSFileProviderItemFields)fields contents:(NSURL *)contents options:(NSFileProviderModifyItemOptions)options
                   request:(NSFileProviderRequest *)request
         completionHandler:(void (^)(NSFileProviderItem, NSFileProviderItemFields, BOOL, NSError *))completion;
- (NSError *)repositoryAccessError:(NSString *)repoId;
- (BOOL)repoListUnknownFor:(NSString *)repoId;
- (void)ensureRepoListLoaded:(void (^)(BOOL known, BOOL fromNetwork))completion;
- (SeafDir *)seafDirForContainer:(NSString *)identifier record:(SeafFPRecord **)record;
- (void)loadDirectory:(SeafDir *)dir completion:(void (^)(BOOL, BOOL, NSError *))completion;
- (void)loadDirectoryForMove:(SeafDir *)dir completion:(void (^)(BOOL, NSError *))completion;
- (void)resolveMovedRecord:(SeafFPRecord *)record recovery:(NSDictionary *)recovery inDir:(SeafDir *)dir
                completion:(void (^)(SeafFPMoveOutcome, NSString *, NSError *))completion;
- (void)recoverMoveOfRecord:(SeafFPRecord *)record details:(NSDictionary *)recovery
                 completion:(void (^)(SeafFPRecord *, SeafFPMoveSettlement, NSError *))completion;
- (void)relocateRecord:(SeafFPRecord *)record fromDir:(SeafDir *)source toDir:(SeafDir *)destination
            parentUUID:(NSString *)parentUUID name:(NSString *)name requestedName:(NSString *)requestedName
                rename:(BOOL)rename completion:(void (^)(SeafFPRecord *, NSError *))completion;
- (void)forgetSeafObjectsForRecord:(SeafFPRecord *)record;
- (void)signalContainer:(NSString *)container;
- (void)signalWorkingSet;
@end
@implementation TestExtension
- (NSError *)localAccessError { return nil; }
- (NSError *)accessError { return nil; }
- (SeafFPItem *)itemForRecord:(SeafFPRecord *)record { return [SeafFPItem itemForRecord:record repoEditable:[self isRepoEditable:record.repoId]]; }
- (SeafFPItem *)resolveItem:(NSFileProviderItemIdentifier)identifier error:(NSError **)error {
    SeafFPRecord *record = [self.store recordForUUID:[SeafFPIdentifier uuidFromIdentifier:identifier]];
    if (record && !record.deleted) return [self itemForRecord:record];
    if (error) *error = [SeafFPErrors noSuchItem];
    return nil;
}
- (void)applyDecorationChangesFromItem:(NSFileProviderItem)item changedFields:(NSFileProviderItemFields)fields toItem:(SeafFPItem *)current {}
- (NSURL *)stageUploadSource:(NSURL *)url name:(NSString *)name error:(NSError **)error { return url; }
- (void)uploadStagedFile:(NSURL *)stagedURL repoId:(NSString *)repoId path:(NSString *)path parentUUID:(NSString *)parentUUID
        creationStartSeq:(NSNumber *)creationStartSeq progress:(NSProgress *)progress
              completion:(void (^)(SeafFPRecord *, NSError *))completion {
    self.uploadedPath = path;
    completion([self.store recordForRepo:repoId path:path includeDeleted:NO], nil);
}
- (SeafFPItem *)itemForRepositoryState:(NSDictionary *)state {
    SeafFPItem *i = [SeafFPItem itemForRepositoryMetadata:state];
    [i applyDecoration:[self.store decorationForItem:i.itemIdentifier]]; return i;
}
- (void)scheduleWorkingSetRecheckAt:(NSDate *)date {}
- (void)noteSuccess {}
- (void)noteError:(NSError *)error {}
- (void)forgetSeafObjectsForRecord:(SeafFPRecord *)record {}
- (void)signalWorkingSet {}
- (void)signalContainer:(NSString *)container {}
- (void)loadDirectoryForMove:(SeafDir *)dir completion:(void (^)(BOOL, NSError *))completion {
    NSString *body = self.directory404Bodies[[NSString stringWithFormat:@"%@:%@", dir.repoId, dir.path]];
    if (body) {
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://seafile.test/"]
            statusCode:404 HTTPVersion:@"HTTP/1.1" headerFields:nil];
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadServerResponse userInfo:@{
            @"com.alamofire.serialization.response.error.response": response,
            @"com.alamofire.serialization.response.error.data": [body dataUsingEncoding:NSUTF8StringEncoding]
        }];
        completion(NO, [SeafFPErrors directoryListingErrorForSeafError:error]);
        return;
    }
    [self loadDirectory:dir completion:^(BOOL loaded, BOOL fromCache, NSError *error) {
        completion(loaded && !fromCache, error);
    }];
}
- (void)loadDirectory:(SeafDir *)dir completion:(void (^)(BOOL, BOOL, NSError *))completion {
    self.loadedDirectory = dir;
    NSString *key = [NSString stringWithFormat:@"%@:%@", dir.repoId, dir.path];
    if (self.liveListings) dir.items = self.liveListings[key];
    BOOL failed = self.failDirectoryLoad || [self.failingDirectories containsObject:key];
    completion(!failed, NO, failed ? [SeafFPErrors serverUnreachable] : nil);
}
@end
@interface CountingStore : SeafFPStore
@property NSUInteger reads;
@property NSUInteger rows;
@property NSUInteger maxRows;   // most rows one page read
@end
@implementation CountingStore
- (SeafFPWorkingSetPage *)workingSetPageAfterDepth:(NSUInteger)depth isDir:(BOOL)isDir seq:(long long)seq uuid:(NSString *)uuid limit:(NSUInteger)limit {
    SeafFPWorkingSetPage *p = [super workingSetPageAfterDepth:depth isDir:isDir seq:seq uuid:uuid limit:limit];
    self.reads++; self.rows += p.records.count; self.maxRows = MAX(self.maxRows, p.records.count); return p;
}
@end
@interface UnreadableParentStore : SeafFPStore
@property NSString *unreadable;
@end
@implementation UnreadableParentStore
- (SeafFPRecord *)recordForUUID:(NSString *)uuid failed:(BOOL *)failed {
    if ([uuid isEqual:self.unreadable]) { if (failed) *failed = YES; return nil; }
    return [super recordForUUID:uuid failed:failed];
}
@end
@interface TestObserver : NSObject <NSFileProviderEnumerationObserver, NSFileProviderChangeObserver>
@property NSData *nextPage;
@property NSData *anchor;
@property NSError *error;
@property BOOL moreComing;
@property NSUInteger itemCount;
@property NSMutableSet<NSString *> *identifiers;
@property NSMutableDictionary<NSString *,SeafFPItem *> *updates;
@property NSMutableArray<NSString *> *order;
@property NSMutableArray<NSString *> *listed;   // enumerated items, in order
@property NSMutableSet<NSString *> *deleted;
@end
@implementation TestObserver
- (instancetype)init { if ((self=[super init])) { _identifiers=[NSMutableSet set]; _updates=[NSMutableDictionary dictionary]; _order=[NSMutableArray array]; _listed=[NSMutableArray array]; _deleted=[NSMutableSet set]; } return self; }
- (void)didEnumerateItems:(NSArray<id<NSFileProviderItem>> *)items {
    self.itemCount += items.count; for (id<NSFileProviderItem> item in items) { [self.identifiers addObject:item.itemIdentifier]; [self.listed addObject:item.itemIdentifier]; }
}
- (void)finishEnumeratingUpToPage:(NSFileProviderPage)page { self.nextPage=page; }
- (void)finishEnumeratingWithError:(NSError *)error { self.error=error; self.nextPage=nil; }
- (void)didUpdateItems:(NSArray<id<NSFileProviderItem>> *)items { for (SeafFPItem *item in items) { self.updates[item.itemIdentifier]=item; [self.order addObject:item.itemIdentifier]; } }
- (void)didDeleteItemsWithIdentifiers:(NSArray<NSFileProviderItemIdentifier> *)ids { [self.deleted addObjectsFromArray:ids]; }
- (void)finishEnumeratingChangesUpToSyncAnchor:(NSFileProviderSyncAnchor)anchor moreComing:(BOOL)more { self.anchor=anchor; self.moreComing=more; }
@end
'''

# Compile the real item implementation against app-model doubles above.
item_code = '\n'.join(line for line in item.splitlines() if not line.startswith('#import'))
enum_helpers = between(enum, 'static const NSUInteger kSeafFPWorkingSetDirectoryChecksPerPass', '#pragma mark - Container load result')
change_set = between(enum, '#pragma mark - Container load result', '#pragma mark - Enumerator')
enum_class = r'''
@interface SeafFPEnumerator : NSObject
@property TestExtension *extension;
@property long long scanStartSeq;
@property BOOL scanFailed;
@property NSUInteger networkChecks;
- (void)enumerateWorkingSetPage:(NSFileProviderPage)page observer:(id<NSFileProviderEnumerationObserver>)observer;
- (void)enumerateWorkingSetChangesSinceSeq:(long long)known observer:(id<NSFileProviderChangeObserver>)observer;
- (void)loadDirectory:(NSString *)identifier completion:(SeafFPContainerCompletion)completion;
@end
@implementation SeafFPEnumerator
- (NSArray *)workingSetContainersToCheckRecheckAt:(NSDate **)date { return @[@"root"]; }
- (void)checkContainers:(NSArray *)containers index:(NSUInteger)index deadline:(NSDate *)deadline changes:(SeafFPChangeSet *)changes completion:(dispatch_block_t)completion { self.networkChecks += containers.count; completion(); }
''' + between(enum, '- (void)deliverDirectory:', '#pragma mark - Working set') + r'''
'''
enum_methods = between(enum, '- (void)loadRoot:', '- (void)loadDirectory:')
enum_methods += between(enum, '- (void)loadDirectory:', '- (void)deliverDirectory:')
enum_methods += between(enum, '- (void)enumerateWorkingSetPage:', '/// A listing that changed the local view')
enum_methods += between(enum, '- (void)enumerateWorkingSetChangesSinceSeq:', '#pragma mark - NSFileProviderEnumerator')
extension_methods = r'''
static NSDictionary *SeafFPIndexEntryForBase(SeafBase *obj) {
    return @{SeafFPEntryName: obj.name, SeafFPEntryOid: obj.oid ?: @"",
             SeafFPEntryIsDir: @([obj isKindOfClass:[SeafDir class]])};
}
''' + (between(extension, 'static long long SeafFPServerTime(', '@interface SeafFPExtension ()')
                     + between(extension, 'static BOOL SeafFPNamesEqual(', '// A replicated extension')
                     + between(extension, 'static BOOL SeafFPRenameSucceeded(', '- (void)forgetSeafObjectsForRecord:')
                     + '\n@implementation TestExtension (ModelResolution)\n'
                     + between(extension, '- (SeafRepo *)repoWithId:', '- (SeafFPItem *)itemForRepo:')
                     + between(extension, '- (SeafDir *)seafDirForContainer:', '- (SeafFile *)seafFileForRecord:')
                     + between(extension, '- (NSString *)freeNameFor:', '/// Copies the system-provided contents')
                     + between(extension, '- (void)applyModificationOfRecord:', '#pragma mark - NSFileProviderReplicatedExtension: enumeration')
                     + '\n@end\n')
activity_helpers = between(index, '#pragma mark - Activity log', '/// Main thread. Reads the activity log back')
activity_method = between(index, '/// Main thread. Reads the activity log back', '#pragma mark - SeafFileProviderDomainObserver')
activity_class = r'''
#import <objc/runtime.h>
#import <sqlite3.h>
#define API_URL_V21 @"/api/v2.1"
static const NSTimeInterval kSeafFPActivityFetchInterval = 15 * 60;
typedef NS_ENUM(NSInteger, UIApplicationState) { UIApplicationStateActive, UIApplicationStateInactive, UIApplicationStateBackground };
@interface UIApplication : NSObject
+ (instancetype)sharedApplication;
@property UIApplicationState applicationState;
@end
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *a; static dispatch_once_t once; dispatch_once(&once, ^{ a = [self new]; a.applicationState = UIApplicationStateBackground; }); return a; }
@end
@interface SeafFileProviderDomainManager : NSObject
+ (NSString *)domainIdentifierForConnection:(SeafConnection *)connection;
@end
@implementation SeafFileProviderDomainManager
+ (NSString *)domainIdentifierForConnection:(SeafConnection *)connection { return @"probe"; }
@end

// A fake server: the activity log (newest first, paged by offset) and
// directory listings ("repo|path" -> entries, or an NSNumber status).
static NSMutableArray<NSDictionary *> *gLog;
static NSMutableDictionary<NSString *, id> *gDirs;
static NSUInteger gActivityRequests, gDirRequests, gInFlight, gMaxInFlight;
static NSUInteger gShiftBeforeActivityPage, gFailActivityPage;
static BOOL gHoldActivity, gHoldDirs;
static NSMutableArray<dispatch_block_t> *gHeld;
static NSMapTable *gDirRequestsBy;   // connection -> count
static NSInteger gFailProgressReads;
static NSString * const gServerDate = @"Tue, 03 Nov 2026 02:00:00 GMT";
typedef void (^TestSuccess)(NSURLRequest *, NSHTTPURLResponse *, id);
typedef void (^TestFailure)(NSURLRequest *, NSHTTPURLResponse *, id, NSError *);
static NSHTTPURLResponse *TestResponse(NSInteger status) {
    return [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://seafile.test/"] statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{@"Date": gServerDate}];
}
@interface SeafConnection (ActivityTest)
- (id)sendRequest:(NSString *)url success:(TestSuccess)success failure:(TestFailure)failure;
@end
@implementation SeafConnection (ActivityTest)
- (id)sendRequest:(NSString *)url success:(TestSuccess)success failure:(TestFailure)failure {
    if ([url hasPrefix:@"/api/v2.1/activities/"]) {
        gActivityRequests++;
        NSURLComponents *components = [NSURLComponents componentsWithString:[@"https://seafile.test" stringByAppendingString:url]];
        NSUInteger page = 1, perPage = 25;
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name isEqual:@"page"]) page = item.value.integerValue;
            if ([item.name isEqual:@"per_page"]) perPage = item.value.integerValue;
        }
        if (gFailActivityPage == page) {
            gFailActivityPage = 0;
            dispatch_async(dispatch_get_main_queue(), ^{ failure(nil, TestResponse(503), nil, [SeafFPErrors serverUnreachable]); });
            return nil;
        }
        if (gShiftBeforeActivityPage == page) {
            gShiftBeforeActivityPage = 0;
            [gLog removeObjectsInRange:NSMakeRange(0, 10)];
        }
        NSUInteger start = (page - 1) * perPage;
        NSArray *slice = start < gLog.count ? [gLog subarrayWithRange:NSMakeRange(start, MIN(perPage, gLog.count - start))] : @[];
        dispatch_block_t reply = ^{ success(nil, TestResponse(200), @{@"events": slice}); };
        if (gHoldActivity) [gHeld addObject:[reply copy]]; else dispatch_async(dispatch_get_main_queue(), reply);
        return nil;
    }
    gDirRequests++; gInFlight++; gMaxInFlight = MAX(gMaxInFlight, gInFlight);
    if (!gDirRequestsBy) gDirRequestsBy = [NSMapTable weakToStrongObjectsMapTable];
    [gDirRequestsBy setObject:@([[gDirRequestsBy objectForKey:self] integerValue] + 1) forKey:self];
    id answer = gDirs[url];
    dispatch_block_t reply = ^{
        gInFlight--;
        if ([answer isKindOfClass:[NSArray class]]) { success(nil, TestResponse(200), answer); return; }
        NSInteger status = [answer isKindOfClass:[NSNumber class]] ? [answer integerValue] : 404;
        BOOL libraryMissing = status == 4040, bare = status == 4044;   // 4044: a 404 without seahub's error body (proxy, HTML page)
        if (libraryMissing || bare) status = 404;
        NSString *message = status == 404 ? (libraryMissing ? @"Library x not found." : @"Folder x not found.") : @"Permission denied.";
        failure(nil, TestResponse(status), bare ? nil : @{@"error_msg": message}, [NSError errorWithDomain:@"test" code:status userInfo:nil]);
    };
    if (gHoldDirs) [gHeld addObject:[reply copy]]; else dispatch_async(dispatch_get_main_queue(), reply);
    return nil;
}
@end
@interface SeafDir (CheckTest)
- (instancetype)initWithConnection:(SeafConnection *)c oid:(NSString *)oid repoId:(NSString *)repoId perm:(NSString *)perm name:(NSString *)name path:(NSString *)path mtime:(long long)mtime;
- (NSString *)url;
- (void)handleResponse:(NSHTTPURLResponse *)response json:(id)JSON;
- (NSArray *)fp_listingSnapshotForResponse:(id)JSON;
@end
@implementation SeafDir (CheckTest)
- (instancetype)initWithConnection:(SeafConnection *)c oid:(NSString *)oid repoId:(NSString *)repoId perm:(NSString *)perm name:(NSString *)name path:(NSString *)path mtime:(long long)mtime {
    if ((self = [self init])) {
        self.repoId = repoId; self.oid = oid; self.perm = perm; self.name = name; self.path = path; self.mtime = mtime;
        objc_setAssociatedObject(self, "url", [NSString stringWithFormat:@"%@|%@", repoId, path], OBJC_ASSOCIATION_COPY);
    }
    return self;
}
- (NSString *)url { return objc_getAssociatedObject(self, "url"); }
- (void)handleResponse:(NSHTTPURLResponse *)response json:(id)JSON {}
- (NSArray *)fp_listingSnapshotForResponse:(id)JSON { return [JSON isKindOfClass:[NSArray class]] ? JSON : nil; }
@end

@interface SeafFPStore (ProgressReadFailure)
- (int)stepLocked:(sqlite3_stmt *)stmt;
- (void)noteFailureLocked:(int)rc;
@end
@interface ProgressFailingStore : SeafFPStore @end
@implementation ProgressFailingStore
- (int)stepLocked:(sqlite3_stmt *)stmt {
    if (gFailProgressReads > 0) {
        char *expanded = sqlite3_expanded_sql(stmt);
        BOOL match = expanded && !strncmp(expanded, "SELECT value FROM meta", 22) && strstr(expanded, "fp_activity_progress_v1");
        sqlite3_free(expanded);
        if (match) { gFailProgressReads--; [self noteFailureLocked:SQLITE_IOERR]; return SQLITE_IOERR; }
    }
    return [super stepLocked:stmt];
}
@end
@interface SnapshotFailingStore : SeafFPStore
@property NSInteger rowsBeforeError;
@property BOOL failRepositoryRead;
@end
@implementation SnapshotFailingStore
- (int)stepLocked:(sqlite3_stmt *)stmt {
    if (self.failRepositoryRead && strstr(sqlite3_sql(stmt), "fp_repo_publication_v1:")) {
        [self noteFailureLocked:SQLITE_IOERR];
        return SQLITE_IOERR;
    }
    if (self.rowsBeforeError >= 0 && strstr(sqlite3_sql(stmt), "FROM identity WHERE deleted = 0 AND (length(path)")) {
        if (self.rowsBeforeError == 0) { [self noteFailureLocked:SQLITE_IOERR]; return SQLITE_IOERR; }
        self.rowsBeforeError--;
    }
    return [super stepLocked:stmt];
}
@end
@interface ProbeIndexer : NSObject {
    NSMutableDictionary *_activityFetchedAt;
    NSMutableDictionary<NSString *, NSDictionary *> *_activitySyncs;
    NSMutableSet<NSString *> *_checkQueries;
    NSMutableSet<NSString *> *_checksInFlight;
    NSUInteger _checksRunning;
    NSMutableDictionary<NSString *, NSDate *> *_checkWakeups;
    NSHashTable *_checkWaiting;
}
@property NSArray<NSString *> *knownRepos;
@property SeafFPStore *activityStore;
@property NSMutableSet<NSString *> *lockedRepos;
@property NSUInteger changes;
@end
@implementation ProbeIndexer
- (instancetype)init {
    if ((self=[super init])) {
        _activityFetchedAt=[NSMutableDictionary dictionary]; _activitySyncs=[NSMutableDictionary dictionary];
        _checkQueries=[NSMutableSet set]; _checksInFlight=[NSMutableSet set]; _checkWakeups=[NSMutableDictionary dictionary];
        _checkWaiting=[NSHashTable weakObjectsHashTable];
        _lockedRepos=[NSMutableSet set];
    }
    return self;
}
- (BOOL)idle { return _activitySyncs.count == 0 && _checksRunning == 0 && _checkQueries.count == 0; }
- (void)ageSync { NSDictionary *run=_activitySyncs[@"probe"]; if (run) _activitySyncs[@"probe"]=@{@"token":run[@"token"], @"at":[NSDate dateWithTimeIntervalSinceNow:-121]}; }
// nil: every library (no filter); otherwise the known ones that are not locked.
- (NSArray *)indexableRepoIdsOfConnection:(SeafConnection *)c {
    if (!self.knownRepos && self.lockedRepos.count == 0) return nil;
    NSMutableArray *a=[NSMutableArray arrayWithArray:self.knownRepos ?: @[]]; [a removeObjectsInArray:self.lockedRepos.allObjects]; return a;
}
- (BOOL)canIndexActivitiesOfConnection:(SeafConnection *)c { return YES; }
- (uint64_t)generationForDomainId:(NSString *)domainId { return 0; }
- (BOOL)isDomainActive:(NSString *)domainId generation:(uint64_t)generation { return YES; }
- (NSString *)domainIdForConnection:(SeafConnection *)c repoId:(NSString *)r { return [self.lockedRepos containsObject:r ?: @""] ? nil : @"probe"; }
- (void)enqueueForDomainId:(NSString *)domain work:(void (^)(SeafFPStore *))work { work(self.activityStore); }
- (void)enqueueForDomainId:(NSString *)domain work:(void (^)(SeafFPStore *))work skipped:(dispatch_block_t)skipped { work(self.activityStore); }
- (void)noteChangedConnection:(SeafConnection *)c { self.changes++; }
- (long long)fp_requestStartSeqForConnection:(SeafConnection *)c { return self.activityStore.currentSeq; }
'''

# Run the real notification code with a controllable system completion callback.
signal_class = r'''
static const NSTimeInterval kSeafFPSignalCoalesceInterval = 3600;
static NSMutableArray *gSignalCallbacks;
@interface TestSignalTransport : NSObject
+ (instancetype)managerForDomain:(NSFileProviderDomain *)domain;
- (void)signalEnumeratorForContainerItemIdentifier:(NSString *)identifier completionHandler:(void (^)(NSError *))completion;
@end
@implementation TestSignalTransport
+ (instancetype)managerForDomain:(NSFileProviderDomain *)domain { return [self new]; }
- (void)signalEnumeratorForContainerItemIdentifier:(NSString *)identifier completionHandler:(void (^)(NSError *))completion { [gSignalCallbacks addObject:[completion copy]]; }
@end
@interface ProbeDomainManager : NSObject
@property NSMutableDictionary *pendingSignals;
@property NSMutableDictionary *signalGenerations;
@property NSMutableDictionary *signalRetries;
@property dispatch_queue_t signalQueue;
@end
@implementation ProbeDomainManager
- (instancetype)init { if ((self=[super init])) { _pendingSignals=[NSMutableDictionary dictionary]; _signalGenerations=[NSMutableDictionary dictionary]; _signalRetries=[NSMutableDictionary dictionary]; _signalQueue=dispatch_queue_create("test-signals", DISPATCH_QUEUE_SERIAL); } return self; }
+ (BOOL)connectionWantsDomain:(SeafConnection *)c { return YES; }
- (NSFileProviderDomain *)domainForConnection:(SeafConnection *)c { return [[NSFileProviderDomain alloc] initWithIdentifier:@"signals" displayName:@"Test"]; }
#define NSFileProviderManager TestSignalTransport
'''
signal_methods = between(manager, '- (void)invalidatePendingSignalsForDomainIdentifier:', '- (void)flushPendingSignals\n')

fixtures = r'''
static NSDictionary *repoInfo(NSString *repo, NSString *name, BOOL editable) {
    return @{@"repoId":repo,@"name":name,@"perm":editable?@"rw":@"r",@"editable":@(editable),@"mtime":@10,@"ooid":@"root",@"locked":@NO};
}
static SeafFPEnumerator *enumerator(SeafFPStore *store, NSString *repo) {
    SeafRepo *r=[SeafRepo new]; r.repoId=repo; r.name=repo; r.editable=YES; r.perm=@"rw";
    SeafRepos *repos=[SeafRepos new]; repos.items=@[r];
    SeafConnection *c=[SeafConnection new]; c.rootFolder=repos;
    TestExtension *e=[TestExtension new]; e.store=store; e.connection=c;
    SeafFPEnumerator *result=[SeafFPEnumerator new]; result.extension=e; result.scanStartSeq=-1; return result;
}
static TestObserver *changes(SeafFPEnumerator *e, long long known) {
    TestObserver *o=[TestObserver new]; [e enumerateWorkingSetChangesSinceSeq:known observer:o]; return o;
}
static void sharedLibraryRoot(void) {
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"shared-library-root" error:nil];
    [s applyRepositorySnapshot:@[repoInfo(@"shared", @"Shared library", YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    SeafFPEnumerator *e = enumerator(s, @"old");
    [e loadDirectory:@"r:shared" completion:^(SeafFPContainerLoad *load, NSError *error) {
        CHECK(load && !error);
    }];
    SeafDir *dir = e.extension.loadedDirectory;
    CHECK([dir.repoId isEqual:@"shared"] && [dir.path isEqual:@"/"] && [dir.perm isEqual:@"rw"]);

    NSMutableDictionary *locked = [repoInfo(@"shared", @"Shared library", YES) mutableCopy];
    locked[@"locked"] = @YES;
    [s applyRepositorySnapshot:@[locked] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    e.extension.loadedDirectory = nil;
    [e loadDirectory:@"r:shared" completion:^(SeafFPContainerLoad *load, NSError *error) {
        CHECK(!load && error.code == NSFileProviderErrorNotAuthenticated);
    }];
    CHECK(!e.extension.loadedDirectory);
    [s applyRepositorySnapshot:@[] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    [e loadDirectory:@"r:shared" completion:^(SeafFPContainerLoad *load, NSError *error) {
        CHECK(!load && error.code == NSFileProviderErrorNoSuchItem);
    }];
    [s close];
}

static void failedWorkingSetSnapshot(void) {
    SnapshotFailingStore *s = [[SnapshotFailingStore alloc] initWithDomainIdentifier:@"failed-snapshot" error:nil];
    SeafFPRecord *a = [s upsertRecordForRepo:@"r" path:@"/a" isDir:NO parentUUID:nil oid:@"a" mtime:10 size:1];
    SeafFPRecord *b = [s upsertRecordForRepo:@"r" path:@"/b" isDir:NO parentUUID:nil oid:@"b" mtime:10 size:1];
    [s applyRepositorySnapshot:@[repoInfo(@"r", @"Library", YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    for (int i = 0; i < 2; i++) {
        SeafFPEnumerator *e = enumerator(s, @"r");
        TestObserver *o = [TestObserver new];
        s.rowsBeforeError = i;
        [e enumerateWorkingSetPage:[NSData data] observer:o];
        CHECK(o.error.code == NSFileProviderErrorCannotSynchronize && !o.nextPage && o.itemCount == 0);
        CHECK(e.scanFailed && e.scanStartSeq == -1);

        s.rowsBeforeError = -1;
        o = [TestObserver new];
        [e enumerateWorkingSetPage:[NSData data] observer:o];
        CHECK(!o.error && [o.identifiers containsObject:a.itemIdentifier] && [o.identifiers containsObject:b.itemIdentifier]);
        CHECK(!e.scanFailed && e.scanStartSeq == s.currentSeq);
    }
    [s close];
}

static void directMoveWithProvisionalDestination(void) {
    for (int targetFirst = 0; targetFirst < 2; targetFirst++) {
        NSString *domain = [NSString stringWithFormat:@"direct-move-%d", targetFirst];
        SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPStore *concurrent = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPRecord *source = [s upsertRecordForRepo:@"r" path:@"/source" isDir:YES parentUUID:nil oid:@"dir" mtime:10 size:-1];
        long long start = s.currentSeq;
        NSArray *listing = @[@{SeafFPEntryName: @"target", SeafFPEntryIsDir: @YES, SeafFPEntryOid: @"dir"}];
        SeafFPRecord *(^browseTarget)(void) = ^{
            return [concurrent upsertRecordForRepo:@"r" path:@"/target" isDir:YES parentUUID:nil oid:@"dir" mtime:10 size:-1];
        };
        SeafFPRecord *target = targetFirst ? browseTarget() : nil;
        NSString *name = [s confirmedNameForRecord:source expected:@"target" inRepo:@"r" directory:@"/" entries:listing requestStartSeq:start];
        CHECK([name isEqual:@"target"]);
        if (!target) target = browseTarget();
        SeafFPRecord *child = [concurrent upsertRecordForRepo:@"r" path:@"/target/child" isDir:NO parentUUID:target.uuid oid:@"child" mtime:10 size:1];
        for (SeafFPRecord *record in @[target, child]) {
            SeafFPDecoration *decoration = [SeafFPDecoration new];
            decoration.itemIdentifier = record.itemIdentifier;
            decoration.favoriteRank = @42;
            [concurrent setDecoration:decoration];
        }
        CHECK(![s confirmMoveOfRecord:source toRepo:@"r" path:@"/target" parentUUID:nil requestStartSeq:s.currentSeq]);
        CHECK([s confirmMoveOfRecord:source toRepo:@"r" path:[@"/" stringByAppendingString:name] parentUUID:nil requestStartSeq:start]);
        long long after = s.currentSeq;
        CHECK([s confirmMoveOfRecord:source toRepo:@"r" path:@"/target" parentUUID:nil requestStartSeq:start]
              && s.currentSeq == after);
        CHECK([s recordForUUID:target.uuid].deleted && [[s recordForUUID:child.uuid].parentUUID isEqual:source.uuid]);
        CHECK([[s decorationForItem:source.itemIdentifier].favoriteRank isEqual:@42]
              && [[s decorationForItem:child.itemIdentifier].favoriteRank isEqual:@42]);
        TestObserver *o = [TestObserver new];
        [enumerator(s, @"r") enumerateWorkingSetPage:[NSData data] observer:o];
        CHECK(!o.error && [o.identifiers containsObject:child.itemIdentifier]);
        [concurrent close];
        [s close];
    }
}

static void moveAfterFailedListing(void) {
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"failed-post-move-listing" error:nil];
    SeafFPStore *other = [[SeafFPStore alloc] initWithDomainIdentifier:@"failed-post-move-listing" error:nil];
    TestExtension *ext = enumerator(s, @"r").extension;
    ext.failDirectoryLoad = YES;
    SeafDir *dir = [SeafDir new]; dir.repoId = @"r"; dir.path = @"/";
    SeafFPRecord *source = [s upsertRecordForRepo:@"r" path:@"/source" isDir:YES parentUUID:nil oid:@"dir" mtime:10 size:-1];
    long long start = s.currentSeq;
    [ext resolveMovedRecord:source recovery:@{@"name": @"target", @"start": @(start)} inDir:dir completion:^(SeafFPMoveOutcome outcome, NSString *name, NSError *error) {
        CHECK(!name && error.code == NSFileProviderErrorServerUnreachable && ![s recordForUUID:source.uuid].deleted);
    }];

    SeafFPRecord *separate = [other upsertRecordForRepo:@"r" path:@"/elsewhere" isDir:YES parentUUID:nil oid:@"dir" mtime:10 size:-1];
    CHECK([other confirmMoveOfRecord:separate toRepo:@"r" path:@"/target" parentUUID:nil requestStartSeq:other.currentSeq]);
    SeafFPDecoration *dec = [SeafFPDecoration new]; dec.itemIdentifier = separate.itemIdentifier; dec.favoriteRank = @42;
    [other setDecoration:dec];
    [ext resolveMovedRecord:source recovery:@{@"name": @"target", @"start": @(start)} inDir:dir completion:^(SeafFPMoveOutcome outcome, NSString *name, NSError *error) {
        CHECK(!name && outcome == SeafFPMoveOutcomeUnknown && ![s recordForUUID:source.uuid].deleted);
    }];
    CHECK(![s confirmMoveOfRecord:source toRepo:@"r" path:@"/target" parentUUID:nil requestStartSeq:start]
          && ![s recordForUUID:separate.uuid].deleted && [[s decorationForItem:separate.itemIdentifier].favoriteRank isEqual:@42]
          && ![s decorationForItem:source.itemIdentifier].favoriteRank);

    SeafFPRecord *target = [other upsertRecordForRepo:@"r" path:@"/provisional" isDir:YES parentUUID:nil oid:@"dir" mtime:10 size:-1];
    SeafFPRecord *child = [other upsertRecordForRepo:@"r" path:@"/provisional/child" isDir:NO parentUUID:target.uuid oid:@"child" mtime:10 size:1];
    CHECK([s rememberMoveOfRecord:source toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"provisional" requestStartSeq:start serverTime:200]);
    [ext resolveMovedRecord:source recovery:[s moveRecoveryForUUID:source.uuid] inDir:dir completion:^(SeafFPMoveOutcome outcome, NSString *name, NSError *error) {
        CHECK(!name && outcome == SeafFPMoveOutcomeUnknown && ![s recordForUUID:source.uuid].deleted && [s moveRecoveryForUUID:source.uuid].count > 0);
    }];
    NSArray *listing = @[@{SeafFPEntryName: @"target", SeafFPEntryIsDir: @YES, SeafFPEntryOid: @"dir"},
                         @{SeafFPEntryName: @"provisional", SeafFPEntryIsDir: @YES, SeafFPEntryOid: @"dir"}];
    [other applyListingOfRepo:@"r" directoryPath:@"/" entries:listing requestStartSeq:other.currentSeq];
    CHECK([other recordForUUID:source.uuid].tombReason == SeafFPTombReasonAbsent);
    [other close]; [s close];
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"failed-post-move-listing" error:nil];
    ext = enumerator(s, @"r").extension;
    SeafRepo *repo = ext.connection.rootFolder.items.firstObject;
    repo.path = @"/";
    SeafDir *entry = [SeafDir new]; entry.name = @"provisional"; entry.oid = @"dir";
    repo.items = @[entry];
    [ext recoverMoveOfRecord:[s recordForUUID:source.uuid] details:[s moveRecoveryForUUID:source.uuid] completion:^(SeafFPRecord *moved, SeafFPMoveSettlement settlement, NSError *error) { BOOL applied = moved && !error && settlement == SeafFPMoveSettlementRecovered;
        CHECK(applied && [moved.uuid isEqual:source.uuid] && [moved.path isEqual:@"/provisional"] && !error);
    }];
    CHECK([s recordForUUID:target.uuid].deleted && [[s recordForUUID:child.uuid].parentUUID isEqual:source.uuid]
          && [s moveRecoveryForUUID:source.uuid].count == 0);
    [s close];
}

static void workingSetPermissionsBetweenPages(void) {
    for (int locked = 0; locked < 2; locked++) {
        NSString *domain = [NSString stringWithFormat:@"permissions-between-pages-%d", locked];
        SnapshotFailingStore *s = [[SnapshotFailingStore alloc] initWithDomainIdentifier:domain error:nil];
        s.rowsBeforeError = -1;
        SeafFPStore *other = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        [s performBatch:^{
            for (int i = 0; i < 220; i++) {
                [s upsertRecordForRepo:@"r" path:[NSString stringWithFormat:@"/item-%d", i] isDir:NO parentUUID:nil oid:@"file" mtime:10 size:1];
            }
        }];
        SeafFPEnumerator *e = enumerator(s, @"r");
        TestObserver *first = [TestObserver new];
        [e enumerateWorkingSetPage:[NSData data] observer:first];
        CHECK(!first.error && first.nextPage && first.itemCount == 201);
        NSMutableDictionary *repo = [repoInfo(@"r", @"Library", YES) mutableCopy];
        repo[@"locked"] = @YES;
        [other applyRepositorySnapshot:locked ? @[repo] : @[] complete:YES fromCache:NO requestStartSeq:other.currentSeq];
        s.failRepositoryRead = YES;
        TestObserver *failed = [TestObserver new];
        [e enumerateWorkingSetPage:first.nextPage observer:failed];
        CHECK(failed.error.code == NSFileProviderErrorCannotSynchronize && failed.itemCount == 0 && e.scanFailed);
        s.failRepositoryRead = NO;
        TestObserver *second = [TestObserver new];
        [e enumerateWorkingSetPage:first.nextPage observer:second];
        CHECK(!second.error && second.itemCount == 0 && !e.scanFailed);
        [other close]; [s close];
    }
}
static void publicPermissions(void) {
    SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:@"permissions" error:nil];
    SeafFPRecord *r=[s upsertRecordForRepo:@"p" path:@"/a.txt" isDir:NO parentUUID:nil oid:@"a" mtime:10 size:5];
    SeafFPDecoration *d=[SeafFPDecoration new]; d.itemIdentifier=r.itemIdentifier; d.favoriteRank=@42; [s setDecoration:d];
    [s applyRepositorySnapshot:@[repoInfo(@"p",@"Library",YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    while(s.hasPendingRepositoryPublications) [s publishPendingRepositoryRecordsWithLimit:500];
    long long before=s.currentSeq;
    [s applyRepositorySnapshot:@[repoInfo(@"p",@"Library",NO)] complete:YES fromCache:NO requestStartSeq:before];
    SeafFPEnumerator *e=enumerator(s,@"p"); TestObserver *o=changes(e,before);
    SeafFPItem *file=o.updates[r.itemIdentifier];
    CHECK(!o.error && file && !(file.capabilities & NSFileProviderItemCapabilitiesAllowsRenaming));
    CHECK([file.favoriteRank isEqual:@42] && [file.itemVersion.contentVersion isEqual:[@"a" dataUsingEncoding:NSUTF8StringEncoding]]);
    CHECK([file.itemIdentifier isEqual:r.itemIdentifier] && [o.order.firstObject isEqual:@"r:p"]);
    CHECK(e.networkChecks==0); // Stale connection model remains writable: projection must use the Store.
    before=s.currentSeq;
    [s applyRepositorySnapshot:@[repoInfo(@"p",@"New name",NO)] complete:YES fromCache:NO requestStartSeq:before];
    o=changes(e,before);
    CHECK(o.updates.count==1 && [o.updates[@"r:p"].filename isEqual:@"New name"]);
    CHECK(!s.hasPendingRepositoryPublications);
    before=s.currentSeq;
    [s applyRepositorySnapshot:@[repoInfo(@"p",@"New name",YES)] complete:YES fromCache:NO requestStartSeq:before];
    o=changes(e,before);
    CHECK((o.updates[r.itemIdentifier].capabilities & NSFileProviderItemCapabilitiesAllowsRenaming)!=0);
    [s close];
}
static void repositoryResponseOrdering(void) {
    SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:@"response-order" error:nil];
    [s applyRepositorySnapshot:@[repoInfo(@"response",@"Initial",YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    SeafFPEnumerator *e=enumerator(s,@"response");
    __block NSUInteger completions=0;
    void (^finished)(SeafFPContainerLoad *,NSError *)=^(SeafFPContainerLoad *load,NSError *error) { CHECK(!error); completions++; };
    [e loadRoot:NSFileProviderRootContainerItemIdentifier completion:finished];
    [s applyRepositorySnapshot:@[repoInfo(@"response",@"Newer accepted",YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    [e loadRoot:NSFileProviderRootContainerItemIdentifier completion:finished];
    SeafRepos *repos=e.extension.connection.rootFolder;
    repos.items.firstObject.name=@"Old response";
    void (^oldResponse)(SeafDir *)=repos.callbacks[0]; oldResponse((SeafDir *)repos);
    CHECK([s.repositoryStates[@"response"][@"name"] isEqual:@"Newer accepted"]);
    repos.items.firstObject.name=@"Newest response";
    void (^newResponse)(SeafDir *)=repos.callbacks[1]; newResponse((SeafDir *)repos);
    CHECK(completions==2 && [s.repositoryStates[@"response"][@"name"] isEqual:@"Newest response"]);
    [s close];
}
static void deepHierarchy(void) {
    SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:@"deep" error:nil];
    NSString *path=@""; SeafFPRecord *parent=nil;
    for(NSUInteger i=0;i<90;i++) { path=[path stringByAppendingString:@"/目录"]; parent=[s upsertRecordForRepo:@"deep" path:path isDir:YES parentUUID:parent.uuid oid:@"dir" mtime:10 size:-1]; }
    [s applyRepositorySnapshot:@[repoInfo(@"deep",@"Deep",YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    while(s.hasPendingRepositoryPublications) [s publishPendingRepositoryRecordsWithLimit:500];
    long long before=s.currentSeq;
    SeafFPRecord *file=[s upsertRecordForRepo:@"deep" path:[path stringByAppendingString:@"/file.txt"] isDir:NO parentUUID:parent.uuid oid:@"file" mtime:10 size:5];
    TestObserver *o=changes(enumerator(s,@"deep"),before);
    CHECK(!o.error && o.updates.count==92 && [o.order.firstObject isEqual:@"r:deep"] && [o.order.lastObject isEqual:file.itemIdentifier]);
    // A row whose parent is gone has no place in the hierarchy: both
    // enumerations leave it out and still deliver everything else.
    SeafFPRecord *broken=[s upsertRecordForRepo:@"deep" path:@"/broken.txt" isDir:NO parentUUID:@"missing-parent" oid:@"x" mtime:10 size:1];
    o=changes(enumerator(s,@"deep"),before);
    CHECK(!o.error && o.anchor && !o.updates[broken.itemIdentifier] && o.updates[file.itemIdentifier]);
    TestObserver *invalidFull=[TestObserver new];
    [enumerator(s,@"deep") enumerateWorkingSetPage:[NSData data] observer:invalidFull];
    CHECK(!invalidFull.error && !invalidFull.nextPage && invalidFull.itemCount==92);
    CHECK(![invalidFull.identifiers containsObject:broken.itemIdentifier] && [invalidFull.identifiers containsObject:file.itemIdentifier]);
    [s close];
    s=[[SeafFPStore alloc] initWithDomainIdentifier:@"cycle" error:nil];
    SeafFPRecord *a=[s upsertRecordForRepo:@"cycle" path:@"/a" isDir:YES parentUUID:nil oid:@"a" mtime:10 size:-1];
    SeafFPRecord *b=[s upsertRecordForRepo:@"cycle" path:@"/a/b" isDir:YES parentUUID:a.uuid oid:@"b" mtime:10 size:-1];
    [s upsertRecordForRepo:@"cycle" path:@"/a" isDir:YES parentUUID:b.uuid oid:@"a" mtime:10 size:-1];
    SeafFPRecord *c=[s upsertRecordForRepo:@"cycle" path:@"/c.txt" isDir:NO parentUUID:nil oid:@"c" mtime:10 size:1];
    o=changes(enumerator(s,@"cycle"),0);
    CHECK(!o.error && o.anchor && !o.updates[a.itemIdentifier] && !o.updates[b.itemIdentifier] && o.updates[c.itemIdentifier]);
    TestObserver *cycleFull=[TestObserver new];
    [enumerator(s,@"cycle") enumerateWorkingSetPage:[NSData data] observer:cycleFull];
    CHECK(!cycleFull.error && [cycleFull.identifiers containsObject:c.itemIdentifier]
          && ![cycleFull.identifiers containsObject:a.itemIdentifier] && ![cycleFull.identifiers containsObject:b.itemIdentifier]);
    [s close];
    // A parent that could not be read is not a missing one: the pass fails
    // without an anchor and is retried.
    UnreadableParentStore *u=[[UnreadableParentStore alloc] initWithDomainIdentifier:@"unreadable" error:nil];
    SeafFPRecord *ud=[u upsertRecordForRepo:@"unreadable" path:@"/d" isDir:YES parentUUID:nil oid:@"d" mtime:10 size:-1];
    [u upsertRecordForRepo:@"unreadable" path:@"/d/f.txt" isDir:NO parentUUID:ud.uuid oid:@"f" mtime:10 size:1];
    u.unreadable=ud.uuid;
    o=changes(enumerator(u,@"unreadable"),0);
    CHECK(o.error && !o.anchor);
    [u close];
}
static void rawStoreSQL(NSString *domain, NSString *sql) {
    sqlite3 *db=NULL;
    sqlite3_open([SeafFPIdentifier storeURLForDomainIdentifier:domain].path.fileSystemRepresentation, &db);
    CHECK(sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL)==SQLITE_OK);
    sqlite3_close(db);
}
/// Every page of a full working set scan, each on a new enumerator like fileproviderd.
static TestObserver *scanWorkingSet(SeafFPStore *s, NSString *repo, NSUInteger *pages) {
    TestObserver *o=[TestObserver new]; NSData *page=[NSData data]; *pages=0;
    do { [enumerator(s,repo) enumerateWorkingSetPage:page observer:o]; page=o.nextPage; (*pages)++; } while (page && !o.error && *pages<20);
    return o;
}
/// 4.0.9 data with live rows under a tombstoned directory (a move onto a
/// stale folder) and under a row that became a file (a folder replaced by a
/// file). They used to fail the full scan on every retry, so the working set
/// never finished and Files search, tags and favorites never filled in.
static void legacyOrphansAfterUpgrade(void) {
    SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:@"legacy-orphans" error:nil];
    [s applyRepositorySnapshot:@[repoInfo(@"w",@"Work",YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    while(s.hasPendingRepositoryPublications) [s publishPendingRepositoryRecordsWithLimit:500];
    SeafFPRecord *B=[s upsertRecordForRepo:@"w" path:@"/B" isDir:YES parentUUID:nil oid:@"B" mtime:10 size:-1];
    SeafFPRecord *stale=[s upsertRecordForRepo:@"w" path:@"/B/A" isDir:YES parentUUID:B.uuid oid:@"old" mtime:10 size:-1];
    SeafFPRecord *x=[s upsertRecordForRepo:@"w" path:@"/B/A/x.txt" isDir:NO parentUUID:stale.uuid oid:@"x" mtime:10 size:1];
    SeafFPRecord *sub=[s upsertRecordForRepo:@"w" path:@"/B/A/sub" isDir:YES parentUUID:stale.uuid oid:@"sub" mtime:10 size:-1];
    SeafFPRecord *z=[s upsertRecordForRepo:@"w" path:@"/B/A/sub/z.txt" isDir:NO parentUUID:sub.uuid oid:@"z" mtime:10 size:1];
    SeafFPRecord *D=[s upsertRecordForRepo:@"w" path:@"/D" isDir:YES parentUUID:nil oid:@"D" mtime:10 size:-1];
    SeafFPRecord *c=[s upsertRecordForRepo:@"w" path:@"/D/c.txt" isDir:NO parentUUID:D.uuid oid:@"c" mtime:10 size:1];
    SeafFPRecord *keep=[s upsertRecordForRepo:@"w" path:@"/B/keep" isDir:YES parentUUID:B.uuid oid:@"k" mtime:10 size:-1];
    [s performBatch:^{
        for (int i=0;i<250;i++) [s upsertRecordForRepo:@"w" path:[NSString stringWithFormat:@"/B/keep/%03d.jpg",i] isDir:NO parentUUID:keep.uuid oid:@"f" mtime:10 size:1];
    }];
    SeafFPRecord *top=[s upsertRecordForRepo:@"w" path:@"/top.txt" isDir:NO parentUUID:nil oid:@"t" mtime:10 size:1];
    [s close];
    // What 4.0.9 left: only the stale folder tombstoned, the replaced folder flipped in place.
    rawStoreSQL(@"legacy-orphans", [NSString stringWithFormat:@"UPDATE identity SET deleted=1, path='/B/A#moved-1' WHERE uuid='%@';"
                "UPDATE identity SET is_dir=0, oid='file' WHERE uuid='%@'", stale.uuid, D.uuid]);
    NSArray<SeafFPRecord *> *orphans=@[x, sub, z, c];

    // Rows like these that reach the enumerators anyway are left out, and the rest goes through.
    s=[[SeafFPStore alloc] initWithDomainIdentifier:@"legacy-orphans" error:nil];
    NSUInteger pages=0;
    TestObserver *o=scanWorkingSet(s,@"w",&pages);
    CHECK(!o.error && pages==2 && o.itemCount==o.identifiers.count);
    CHECK([o.identifiers containsObject:top.itemIdentifier] && [o.identifiers containsObject:D.itemIdentifier] && [o.identifiers containsObject:B.itemIdentifier]);
    NSUInteger kept=0; for (NSString *identifier in o.identifiers) if ([[s recordForUUID:[SeafFPIdentifier uuidFromIdentifier:identifier]].path hasPrefix:@"/B/keep/"]) kept++;
    CHECK(kept==250);
    for (SeafFPRecord *r in orphans) CHECK(![o.identifiers containsObject:r.itemIdentifier]);
    TestObserver *delta=changes(enumerator(s,@"w"),0);
    CHECK(!delta.error && delta.anchor && delta.updates[top.itemIdentifier]);
    for (SeafFPRecord *r in orphans) CHECK(!delta.updates[r.itemIdentifier]);
    long long anchor=s.currentSeq;
    [s close];

    // The upgrade retires them; the change enumeration reports each one gone.
    rawStoreSQL(@"legacy-orphans", @"UPDATE meta SET value='1' WHERE key='schema_version'");
    s=[[SeafFPStore alloc] initWithDomainIdentifier:@"legacy-orphans" error:nil];
    CHECK([[s metaValueForKey:@"schema_version"] isEqual:@"4"]);
    for (SeafFPRecord *r in orphans) CHECK([s recordForUUID:r.uuid].deleted);
    delta=changes(enumerator(s,@"w"),anchor);
    CHECK(!delta.error && delta.anchor);
    for (SeafFPRecord *r in orphans) CHECK([delta.deleted containsObject:r.itemIdentifier]);
    CHECK(!delta.updates[top.itemIdentifier] && ![delta.deleted containsObject:top.itemIdentifier]);
    o=scanWorkingSet(s,@"w",&pages);
    CHECK(!o.error && pages==2 && [o.identifiers containsObject:top.itemIdentifier]);
    for (SeafFPRecord *r in orphans) CHECK(![o.identifiers containsObject:r.itemIdentifier]);
    [s close];
}
/// The device log of the bug: fileproviderd took page 1, invalidated the
/// enumerator, asked a new one for page 2, got pageExpired and started over,
/// so nothing past the first 200 rows (the deep ones) ever reached Spotlight.
static void workingSetScanAcrossEnumerators(void) {
    SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:@"scan-across-enumerators" error:nil];
    NSMutableDictionary *lockedV=[repoInfo(@"v",@"Vault",YES) mutableCopy]; lockedV[@"locked"]=@YES;
    [s applyRepositorySnapshot:@[repoInfo(@"w",@"Work",YES), lockedV] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    while(s.hasPendingRepositoryPublications) [s publishPendingRepositoryRecordsWithLimit:500];
    SeafFPRecord *a=[s upsertRecordForRepo:@"w" path:@"/a" isDir:YES parentUUID:nil oid:@"a" mtime:10 size:-1];
    SeafFPRecord *b=[s upsertRecordForRepo:@"w" path:@"/a/b" isDir:YES parentUUID:a.uuid oid:@"b" mtime:10 size:-1];
    [s performBatch:^{
        for (int i=0;i<300;i++) [s upsertRecordForRepo:@"w" path:[NSString stringWithFormat:@"/a/b/%05d.jpg",i] isDir:NO parentUUID:b.uuid oid:@"f" mtime:10 size:1];
    }];
    SeafFPRecord *v1=[s upsertRecordForRepo:@"v" path:@"/v1" isDir:YES parentUUID:nil oid:@"v1" mtime:10 size:-1];
    SeafFPRecord *v2=[s upsertRecordForRepo:@"v" path:@"/v1/v2" isDir:YES parentUUID:v1.uuid oid:@"v2" mtime:10 size:-1];
    SeafFPRecord *v3=[s upsertRecordForRepo:@"v" path:@"/v1/v2/v3" isDir:YES parentUUID:v2.uuid oid:@"v3" mtime:10 size:-1];
    SeafFPRecord *vf=[s upsertRecordForRepo:@"v" path:@"/v1/v2/v3/f.txt" isDir:NO parentUUID:v3.uuid oid:@"vf" mtime:10 size:1];
    SeafFPRecord *deep=[s recordForRepo:@"w" path:@"/a/b/00299.jpg" includeDeleted:NO];

    TestObserver *o=[TestObserver new];
    SeafFPEnumerator *e=enumerator(s,@"w");
    [e enumerateWorkingSetPage:[NSData data] observer:o];
    long long start=e.scanStartSeq;
    NSUInteger firstPage=o.listed.count;
    CHECK(!o.error && o.nextPage && [o.identifiers containsObject:@"r:w"] && ![o.identifiers containsObject:@"r:v"]);
    CHECK(![o.identifiers containsObject:deep.itemIdentifier] && ![o.identifiers containsObject:v1.itemIdentifier]);
    // Between pages: /a/b changes, a new folder with a file appears under /a,
    // and the locked library is unlocked.
    [s upsertRecordForRepo:@"w" path:@"/a/b" isDir:YES parentUUID:a.uuid oid:@"b2" mtime:11 size:-1];
    SeafFPRecord *fresh=[s upsertRecordForRepo:@"w" path:@"/a/new" isDir:YES parentUUID:a.uuid oid:@"n" mtime:11 size:-1];
    SeafFPRecord *x=[s upsertRecordForRepo:@"w" path:@"/a/new/x.txt" isDir:NO parentUUID:fresh.uuid oid:@"x" mtime:11 size:1];
    [s applyRepositorySnapshot:@[repoInfo(@"w",@"Work",YES), repoInfo(@"v",@"Vault",YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    NSData *next=o.nextPage; NSUInteger pages=1;
    while (next && !o.error && pages<10) {
        SeafFPEnumerator *pageEnumerator=enumerator(s,@"w");
        [pageEnumerator enumerateWorkingSetPage:next observer:o];
        CHECK(o.error || pageEnumerator.scanStartSeq==start);
        next=o.nextPage; pages++;
    }
    CHECK(!o.error && pages==2);
    NSArray *later=[o.listed subarrayWithRange:NSMakeRange(firstPage, o.listed.count-firstPage)];
    NSUInteger (^at)(NSString *)=^NSUInteger(NSString *identifier) { return [later indexOfObject:identifier]; };
    // The deep file arrives, after its changed parent; the unchanged /a is not repeated.
    CHECK([o.identifiers containsObject:deep.itemIdentifier]);
    CHECK(at(b.itemIdentifier)!=NSNotFound && at(b.itemIdentifier)<at(deep.itemIdentifier));
    CHECK(at(a.itemIdentifier)==NSNotFound);
    CHECK(at(fresh.itemIdentifier)!=NSNotFound && at(fresh.itemIdentifier)<at(x.itemIdentifier));
    // The library that became visible comes with its whole chain, in order.
    CHECK(at(@"r:v")<at(v1.itemIdentifier) && at(v1.itemIdentifier)<at(v2.itemIdentifier)
          && at(v2.itemIdentifier)<at(v3.itemIdentifier) && at(v3.itemIdentifier)<at(vf.itemIdentifier) && at(vf.itemIdentifier)!=NSNotFound);
    // Every /a/b file exactly once.
    NSUInteger files=0; for (NSString *identifier in o.listed) { SeafFPRecord *r=[s recordForUUID:[SeafFPIdentifier uuidFromIdentifier:identifier]]; if ([r.path hasPrefix:@"/a/b/"]) files++; }
    CHECK(files==300);
    [s close];
}
static void boundedTokensAndResume(void) {
    CountingStore *s=[[CountingStore alloc] initWithDomainIdentifier:@"tokens" error:nil];
    NSString *path=@"";
    for(NSUInteger i=0;i<20;i++) path=[path stringByAppendingString:@"/资料目录资料目录资料目录资料目录"];
    SeafFPRecord *parent=nil; NSArray *parts=[path componentsSeparatedByString:@"/"]; NSString *prefix=@"";
    for(NSString *part in parts) if(part.length) { prefix=[prefix stringByAppendingPathComponent:part]; if(![prefix hasPrefix:@"/"]) prefix=[@"/" stringByAppendingString:prefix]; parent=[s upsertRecordForRepo:@"tokens" path:prefix isDir:YES parentUUID:parent.uuid oid:@"d" mtime:10 size:-1]; }
    for(NSUInteger n=0;n<520;n++) [s upsertRecordForRepo:@"tokens" path:[path stringByAppendingPathComponent:[NSString stringWithFormat:@"f%04lu.txt",(unsigned long)n]] isDir:NO parentUUID:parent.uuid oid:@"o" mtime:10 size:1];
    SeafFPEnumerator *e=enumerator(s,@"tokens"); TestObserver *o=[TestObserver new];
    [e enumerateWorkingSetPage:[NSData data] observer:o]; NSData *saved=o.nextPage; long long original=e.scanStartSeq;
    CHECK(saved.length>0 && saved.length<=98 && !o.error && o.itemCount==201 && s.reads==1);
    CHECK(!SeafFPWorkingSetCursorFromToken(@"u:old-format"));
    CHECK(!SeafFPWorkingSetCursorFromToken(@"w2|9223372036854775808|1|0|1|ffffffffffffffffffffffffffffffff"));
    CHECK(!SeafFPWorkingSetCursorFromToken(@"w2|1|18446744073709551616|0|1|ffffffffffffffffffffffffffffffff"));
    CHECK(!SeafFPWorkingSetCursorFromToken(@"w2|1|1|2|1|ffffffffffffffffffffffffffffffff"));
    // Not delivered yet, and moved in front of the scan position.
    SeafFPRecord *moved=[s recordForRepo:@"tokens" path:[path stringByAppendingPathComponent:@"f0519.txt"] includeDeleted:NO];
    CHECK(moved && ![o.identifiers containsObject:moved.itemIdentifier]);
    [s moveRecordUUID:moved.uuid toRepo:@"tokens" path:@"/moved.txt" parentUUID:nil];
    // fileproviderd invalidates the enumerator after each page and continues
    // on a new one: the token alone has to carry the scan on.
    NSUInteger pages=1;
    SeafFPEnumerator *resumed=nil;
    do { resumed=enumerator(s,@"tokens"); [resumed enumerateWorkingSetPage:saved observer:o]; saved=o.nextPage; pages++;
         CHECK(!saved || saved.length<=98); CHECK(o.error || resumed.scanStartSeq==original); } while(saved && !o.error && pages<10);
    CHECK(!o.error && pages==3 && s.reads==3);
    NSArray<SeafFPRecord *> *live=[s recordsChangedSinceSeq:0 limit:0];
    BOOL all=YES;
    for (SeafFPRecord *r in live) if (!r.deleted && ![r.uuid isEqual:moved.uuid] && ![o.identifiers containsObject:r.itemIdentifier]) all=NO;
    CHECK(all && o.identifiers.count==540 && o.itemCount==540);   // library + 539 unmoved rows, each once
    TestObserver *restart=[TestObserver new]; [resumed enumerateWorkingSetPage:[NSData data] observer:restart];
    CHECK(!restart.error && resumed.scanStartSeq>original);
    // The library's rows are republished after `original`, so the move can
    // land in any batch of the change enumeration: read all of them.
    TestObserver *delta=changes(resumed,original);
    NSMutableDictionary *updates=[delta.updates mutableCopy];
    for (int pass=0; !delta.error && delta.moreComing && pass<10; pass++) {
        NSString *anchor=[[NSString alloc] initWithData:delta.anchor encoding:NSUTF8StringEncoding];
        if (![anchor hasPrefix:@"5:"]) break;
        delta=changes(resumed,[[anchor substringFromIndex:2] longLongValue]);
        [updates addEntriesFromDictionary:delta.updates];
    }
    CHECK(!delta.error && updates[moved.itemIdentifier]!=nil);
    TestObserver *invalid=[TestObserver new]; [resumed enumerateWorkingSetPage:[@"u:old" dataUsingEncoding:NSUTF8StringEncoding] observer:invalid];
    CHECK(invalid.error.code==NSFileProviderErrorPageExpired);
    // A position from before the store was rebuilt (its scan start is ahead of the store).
    NSString *future=[NSString stringWithFormat:@"w2|%lld|1|0|1|ffffffffffffffffffffffffffffffff", s.currentSeq+1000];
    TestObserver *rebuilt=[TestObserver new]; [enumerator(s,@"tokens") enumerateWorkingSetPage:[future dataUsingEncoding:NSUTF8StringEncoding] observer:rebuilt];
    CHECK(rebuilt.error.code==NSFileProviderErrorPageExpired && rebuilt.itemCount==0);
    [s close];
}
'''
signal_tests = r'''
static void drainSignals(ProbeDomainManager *m) { dispatch_sync(m.signalQueue,^{}); dispatch_sync(m.signalQueue,^{}); }
static dispatch_semaphore_t sendSignal(ProbeDomainManager *m) {
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    [m sendPendingSignalForDomainIdentifier:@"signals" completion:^{ dispatch_semaphore_signal(done); }];
    drainSignals(m); return done;
}
static void deliverSignal(ProbeDomainManager *m, NSError *error) {
    __block void (^callback)(NSError *);
    dispatch_sync(m.signalQueue,^{ callback=gSignalCallbacks.firstObject; if(callback) [gSignalCallbacks removeObjectAtIndex:0]; });
    CHECK(callback!=nil); if(callback) callback(error); drainSignals(m);
}
static void signalRecovery(void) {
    SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:@"signals" error:nil];
    ProbeDomainManager *m=[ProbeDomainManager new];
    SeafConnection *c=[SeafConnection new]; SeafGlobal.sharedObject.conns=@[c]; gSignalCallbacks=[NSMutableArray array];
    [m signalContainer:NSFileProviderWorkingSetContainerItemIdentifier forConnection:c]; drainSignals(m);
    long long first=s.pendingWorkingSetSignalTicket; CHECK(first>0);
    dispatch_semaphore_t done=sendSignal(m);
    [m signalContainer:NSFileProviderWorkingSetContainerItemIdentifier forConnection:c]; drainSignals(m);
    long long later=s.pendingWorkingSetSignalTicket; CHECK(later>first);
    deliverSignal(m,nil); CHECK(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0);
    CHECK(s.pendingWorkingSetSignalTicket==later);
    done=sendSignal(m); deliverSignal(m,nil); CHECK(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0);
    CHECK(s.pendingWorkingSetSignalTicket==0);
    [m signalContainer:NSFileProviderWorkingSetContainerItemIdentifier forConnection:c]; drainSignals(m);
    done=sendSignal(m); deliverSignal(m,[NSError errorWithDomain:@"transport" code:1 userInfo:nil]);
    CHECK(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0);
    CHECK(s.pendingWorkingSetSignalTicket>0 && m.pendingSignals.count==1);
    done=sendSignal(m); deliverSignal(m,nil); CHECK(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0);
    CHECK(s.pendingWorkingSetSignalTicket==0);
    // Restart the sender while only the persisted outbox survives.
    [s requestWorkingSetSignal]; m=[ProbeDomainManager new]; [m retryPendingSignals:nil]; drainSignals(m);
    done=sendSignal(m); deliverSignal(m,nil); CHECK(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0);
    CHECK(s.pendingWorkingSetSignalTicket==0);
    [m signalContainer:NSFileProviderWorkingSetContainerItemIdentifier forConnection:c]; drainSignals(m);
    done=sendSignal(m);
    [m invalidatePendingSignalsForDomainIdentifier:@"signals"];
    [s close]; [SeafFPStore removeStoreForDomainIdentifier:@"signals"];
    deliverSignal(m,nil); CHECK(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0);
    CHECK(![[NSFileManager defaultManager] fileExistsAtPath:[SeafFPIdentifier storeURLForDomainIdentifier:@"signals"].path]);
}
'''

# Retained behavior tests are defined here, not stored as generated fixtures.

retained_tests = r'''
static void issue7(void) {
    CountingStore *s = [[CountingStore alloc] initWithDomainIdentifier:@"benchmark" error:nil];
    [s performBatch:^{
        for (NSUInteger n=0; n<50000; n++) {
            [s upsertRecordForRepo:@"bench" path:[NSString stringWithFormat:@"/file-%05lu.txt", (unsigned long)n] isDir:NO parentUUID:nil oid:@"oid" mtime:10 size:5];
        }
    }];
    SeafRepo *repo = [SeafRepo new]; repo.repoId = @"bench";
    SeafRepos *repos = [SeafRepos new]; repos.items = @[repo];
    SeafConnection *conn = [SeafConnection new]; conn.rootFolder = repos;
    TestExtension *ext = [TestExtension new]; ext.store = s; ext.connection = conn;
    for (NSUInteger concurrent = 0; concurrent < 2; concurrent++) {
        s.reads = 0; s.rows = 0; s.maxRows = 0;
        SeafFPEnumerator *e = nil;
        TestObserver *observer = [TestObserver new];
        NSData *page = [NSData data];
        NSUInteger pages = 0;
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        do { @autoreleasepool {
            // Like fileproviderd: every page on a new enumerator.
            e = [SeafFPEnumerator new]; e.extension = ext; e.scanStartSeq = -1;
            [e enumerateWorkingSetPage:page observer:observer];
            page = observer.nextPage;
            pages++;
            if (concurrent && pages == 1) {
                // Move an already-emitted row to the end of the live sort order.
                [s upsertRecordForRepo:@"bench" path:@"/file-00000.txt" isDir:NO parentUUID:nil oid:@"updated-oid" mtime:11 size:6];
            }
        } } while (page && pages < 1000);
        NSTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - start;
        NSLog(@"PAGINATION BENCH: concurrent=%lu pages=%lu page reads=%lu rows=%lu time=%.3fs emitted=%lu error=%@", (unsigned long)concurrent, (unsigned long)pages, (unsigned long)s.reads, (unsigned long)s.rows, elapsed, (unsigned long)observer.itemCount, observer.error);
        // The moved row is delivered again at its new place: harmless, and
        // the change pass from the scan start reports it anyway.
        CHECK(!observer.error && pages == 250 + concurrent && observer.itemCount == 50001 + concurrent);
        CHECK(observer.identifiers.count == 50001);
        CHECK(s.reads == pages && s.rows == 50000 + concurrent && s.maxRows == 200);
        if (concurrent) {
            CHECK(s.currentSeq > e.scanStartSeq);
            NSArray<SeafFPRecord *> *changes = [s recordsChangedSinceSeq:e.scanStartSeq limit:0];
            CHECK(changes.count == 1 && [changes.firstObject.path isEqual:@"/file-00000.txt"]);
        }
    }
    [s close];
}
static NSDictionary *activityEvent(NSString *repo, NSString *op, NSString *objType, NSString *path, long long time) {
    NSString *stamp = [[NSISO8601DateFormatter new] stringFromDate:[NSDate dateWithTimeIntervalSince1970:time]];
    return @{@"repo_id":repo, @"op_type":op, @"obj_type":objType, @"path":path, @"time":stamp, @"commit_id":[NSString stringWithFormat:@"c%lld-%@", time, path]};
}
static void spinUntilIdle(ProbeIndexer *indexer) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
    do { CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false); } while (!indexer.idle && [deadline timeIntervalSinceNow] > 0);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
}
static void activitySyncPaging(void) {
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"activity-paging" error:nil];
    ProbeIndexer *indexer = [ProbeIndexer new]; indexer.activityStore = s;
    [indexer.lockedRepos addObject:@"r"];   // checks stay pending: this test only looks at what was collected
    SeafConnection *connection = [SeafConnection new];
    long long t0 = 1800000000;
    [s recordActivityEntries:@[] progress:@{@"boundary": @(t0)}];
    gLog = [NSMutableArray array];
    // Ten seconds apart: the 10 minute overlap is then a few pages, not dozens.
    for (int i = 749; i >= 0; i--) [gLog addObject:activityEvent(@"r", @"create", @"file", [NSString stringWithFormat:@"/d%03d/f.txt", i], t0 + 10 * (1 + i))];
    for (int i = 0; i < 30; i++) [gLog addObject:activityEvent(@"r", @"create", @"file", [NSString stringWithFormat:@"/old%02d/f.txt", i], t0 - 5000 - i)];
    gActivityRequests = 0;
    [indexer syncActivitiesForConnection:connection force:YES];
    spinUntilIdle(indexer);
    NSDictionary *progress = [s activityProgress];
    CHECK(gActivityRequests == 39 && [progress[@"scanTop"] longLongValue] == t0 + 7500 && [progress[@"nextPage"] integerValue] == 21);
    CHECK([s activityRecheckDirectoryPathsOfRepo:@"r"].count == 500);

    // Meanwhile 8 already read activities left the top of the log (aggregated
    // into one at the head) and 3 new ones arrived: unread ones moved up a page.
    for (int k = 0; k < 8; k++) [gLog removeObjectAtIndex:5 + k * 40];
    [gLog insertObject:activityEvent(@"r", @"create", @"file", @"/new-a/f.txt", t0 + 9000) atIndex:0];
    [gLog insertObject:activityEvent(@"r", @"create", @"file", @"/new-b/f.txt", t0 + 9010) atIndex:0];
    [gLog insertObject:activityEvent(@"r", @"create", @"file", @"/new-c/f.txt", t0 + 9020) atIndex:0];
    gActivityRequests = 0;
    [indexer syncActivitiesForConnection:connection force:YES];
    spinUntilIdle(indexer);
    progress = [s activityProgress];
    NSSet *checks = [NSSet setWithArray:[s activityRecheckDirectoryPathsOfRepo:@"r"]];
    BOOL all = YES;
    for (int i = 0; i < 750; i++) if (![checks containsObject:[NSString stringWithFormat:@"/d%03d", i]]) all = NO;
    CHECK(all && progress[@"scanTop"] == nil && [progress[@"boundary"] longLongValue] == t0 + 7500 && gActivityRequests <= 24);
    CHECK(![checks containsObject:@"/new-a"]);   // newer than the scan: the next one reads it
    gActivityRequests = 0;
    [indexer syncActivitiesForConnection:connection force:YES];
    spinUntilIdle(indexer);
    checks = [NSSet setWithArray:[s activityRecheckDirectoryPathsOfRepo:@"r"]];
    CHECK([checks containsObject:@"/new-a"] && [checks containsObject:@"/new-c"] && gActivityRequests <= 7 && [[s activityProgress][@"boundary"] longLongValue] == t0 + 9020);
    [s close];

    // First sync: no boundary. It reads back a week, then starts from the newest.
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"activity-first" error:nil];
    indexer.activityStore = s;
    long long now = 1793671200;   // the server's Date
    gLog = [NSMutableArray array];
    for (int i = 0; i < 30; i++) [gLog addObject:activityEvent(@"r", @"create", @"file", [NSString stringWithFormat:@"/recent%02d/f.txt", i], now - 60 - i)];
    for (int i = 0; i < 100; i++) [gLog addObject:activityEvent(@"r", @"create", @"file", [NSString stringWithFormat:@"/ancient%02d/f.txt", i], now - 9 * 86400 - i)];
    gActivityRequests = 0;
    [indexer syncActivitiesForConnection:connection force:YES];
    spinUntilIdle(indexer);
    CHECK(gActivityRequests == 3 && [[s activityProgress][@"boundary"] longLongValue] == now - 60);
    [s close];
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"activity-empty" error:nil];
    indexer.activityStore = s;
    gLog = [NSMutableArray array];
    [indexer syncActivitiesForConnection:connection force:YES];
    spinUntilIdle(indexer);
    CHECK([[s activityProgress][@"boundary"] longLongValue] == 1793671200);   // the server's Date
    [s close];
}

static void activitySameSecondResume(void) {
    for (int mode = 0; mode < 3; mode++) {
        SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"same-second-%d", mode] error:nil];
        ProbeIndexer *indexer = [ProbeIndexer new]; indexer.activityStore = s;
        [indexer.lockedRepos addObject:@"r"];
        SeafConnection *connection = [SeafConnection new];
        long long time = 1793671200;
        if (mode != 0) [s recordActivityEntries:@[] progress:@{@"boundary": @(time - 1000)}];
        int count = mode == 0 ? 1100 : 750;
        gLog = [NSMutableArray array];
        for (int i = 0; i < count; i++) {
            [gLog addObject:activityEvent(@"r", @"create", @"file", [NSString stringWithFormat:@"/equal-%d/file", i], time)];
        }
        gActivityRequests = 0;
        [indexer syncActivitiesForConnection:connection force:YES]; spinUntilIdle(indexer);
        CHECK(gActivityRequests == 39 && [s.activityProgress[@"nextPage"] intValue] == 21);
        if (mode == 2) [gLog removeObjectsInRange:NSMakeRange(0, 10)];
        for (int run = 0; run < 3 && s.activityProgress[@"scanTop"]; run++) {
            [indexer syncActivitiesForConnection:connection force:YES]; spinUntilIdle(indexer);
        }
        CHECK([s activityRecheckDirectoryPathsOfRepo:@"r"].count == count && !s.activityProgress[@"scanTop"]);
        CHECK(gActivityRequests <= (NSUInteger)(2 * (count / 25 + 4)));
        [s close];
    }
}

static void activityOffsetShiftsAtResume(void) {
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"activity-shift-at-resume" error:nil];
    ProbeIndexer *indexer = [ProbeIndexer new]; indexer.activityStore = s;
    [indexer.lockedRepos addObject:@"r"];
    SeafConnection *connection = [SeafConnection new];
    long long t0 = 1800000000;
    [s recordActivityEntries:@[] progress:@{@"boundary": @(t0)}];
    gLog = [NSMutableArray array];
    for (int i = 0; i < 750; i++) {
        long long time = i < 450 ? t0 + 7500 - i * 10 : t0 + 2500;
        [gLog addObject:activityEvent(@"r", @"create", @"file", [NSString stringWithFormat:@"/shift-%d/f", i], time)];
    }
    [indexer syncActivitiesForConnection:connection force:YES]; spinUntilIdle(indexer);
    NSDictionary *checkpoint = [s activityProgress];
    CHECK([checkpoint[@"nextPage"] intValue] == 21);
    gFailActivityPage = 20;
    [indexer syncActivitiesForConnection:connection force:YES]; spinUntilIdle(indexer);
    CHECK([[s activityProgress] isEqual:checkpoint] && [s activityRecheckDirectoryPathsOfRepo:@"r"].count == 500);
    gShiftBeforeActivityPage = 21;
    [indexer syncActivitiesForConnection:connection force:NO]; spinUntilIdle(indexer);
    CHECK(!s.activityProgress[@"scanTop"] && [s activityRecheckDirectoryPathsOfRepo:@"r"].count == 750);
    [s close];
}

static void reviewFollowups(void) {
    SeafConnection *connection = [SeafConnection new];
    long long t0 = 1800000000;
    // #8 a locked library with many checks does not starve the others.
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"followup-starve" error:nil];
    ProbeIndexer *indexer = [ProbeIndexer new]; indexer.activityStore = s;
    indexer.knownRepos = @[@"locked", @"open"]; [indexer.lockedRepos addObject:@"locked"];
    for (int n = 0; n < 20; n++) [s requestDirectoryCheckOfRepo:@"locked" path:[NSString stringWithFormat:@"/d%d", n]];
    [s requestDirectoryCheckOfRepo:@"open" path:@"/needed"];
    gDirs = [@{@"open|/needed": @[]} mutableCopy]; gDirRequests = 0;
    [indexer runDirectoryChecksForConnection:connection]; spinUntilIdle(indexer);
    CHECK(gDirRequests == 1 && [s activityRecheckDirectoryPathsOfRepo:@"open"].count == 0 && [s activityRecheckDirectoryPathsOfRepo:@"locked"].count == 20);
    [s close];

    // Another account waiting for a free slot runs when one frees up.
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"followup-waiting" error:nil];
    indexer = [ProbeIndexer new]; indexer.activityStore = s;
    for (NSString *path in @[@"/a", @"/b", @"/c"]) [s requestDirectoryCheckOfRepo:@"r" path:path];
    gDirs = [@{@"r|/a": @[], @"r|/b": @[], @"r|/c": @[]} mutableCopy];
    gHeld = [NSMutableArray array]; gHoldDirs = YES; gDirRequestsBy = nil;
    SeafConnection *first = [SeafConnection new], *second = [SeafConnection new];
    [indexer runDirectoryChecksForConnection:first];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    [indexer runDirectoryChecksForConnection:second];   // both slots taken: waits
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    CHECK(gHeld.count == 2 && [gDirRequestsBy objectForKey:second] == nil);
    gHoldDirs = NO;
    for (dispatch_block_t reply in [gHeld copy]) reply();
    spinUntilIdle(indexer);
    CHECK([[gDirRequestsBy objectForKey:second] integerValue] == 1 && [s activityRecheckDirectoryPathsOfRepo:@"r"].count == 0);
    [s close];

    // 403 is counted apart from other failures.
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"followup-denied" error:nil];
    indexer = [ProbeIndexer new]; indexer.activityStore = s;
    [s requestDirectoryCheckOfRepo:@"r" path:@"/deny"];
    SeafFPDirectoryCheck *check = [s dueDirectoryChecksAt:[NSDate date] limit:1].firstObject;
    for (int n = 0; n < 7; n++) { [s deferDirectoryCheck:check until:[NSDate date] status:503]; check.attempts++; }
    gDirs = [@{@"r|/deny": @403} mutableCopy];
    [indexer runDirectoryChecksForConnection:connection]; spinUntilIdle(indexer);
    SeafFPDirectoryCheck *after = [s dueDirectoryChecksAt:[NSDate dateWithTimeIntervalSinceNow:86400] limit:1].firstObject;
    CHECK(after && after.denials == 1 && after.attempts == 8);
    [s close];

    // #2 progress that cannot be read stops the run instead of starting over.
    ProgressFailingStore *pf = [[ProgressFailingStore alloc] initWithDomainIdentifier:@"followup-progress" error:nil];
    indexer = [ProbeIndexer new]; indexer.activityStore = pf; [indexer.lockedRepos addObject:@"r"];
    [pf recordActivityEntries:@[] progress:@{@"boundary": @(t0)}];
    gLog = [NSMutableArray array];
    for (int n = 99; n >= 0; n--) [gLog addObject:activityEvent(@"r", @"create", @"file", [NSString stringWithFormat:@"/p%02d/f", n], t0 + 10 * (n + 1))];
    [gLog addObject:activityEvent(@"r", @"create", @"file", @"/older/f", t0 - 5000)];
    gActivityRequests = 0; gFailProgressReads = 1;
    [indexer syncActivitiesForConnection:connection force:YES]; spinUntilIdle(indexer);
    CHECK(gActivityRequests == 0 && [[pf activityProgress][@"boundary"] longLongValue] == t0);
    [indexer syncActivitiesForConnection:connection force:YES]; spinUntilIdle(indexer);
    CHECK([[pf activityProgress][@"boundary"] longLongValue] == t0 + 1000 && [[pf activityRecheckDirectoryPathsOfRepo:@"r"] containsObject:@"/p00"]);
    [pf close];

    // #11 a scan paused for its budget goes on when the app comes back, within the 15 minutes.
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"followup-resume" error:nil];
    indexer = [ProbeIndexer new]; indexer.activityStore = s; [indexer.lockedRepos addObject:@"r"];
    [s recordActivityEntries:@[] progress:@{@"boundary": @(t0)}];
    gLog = [NSMutableArray array];
    for (int n = 799; n >= 0; n--) [gLog addObject:activityEvent(@"r", @"create", @"file", [NSString stringWithFormat:@"/r%03d/f", n], t0 + 10 * (n + 1))];
    [gLog addObject:activityEvent(@"r", @"create", @"file", @"/older/f", t0 - 5000)];
    gActivityRequests = 0;
    [indexer syncActivitiesForConnection:connection force:YES]; spinUntilIdle(indexer);
    CHECK(gActivityRequests == 39 && [s activityProgress][@"scanTop"] != nil);
    [indexer syncActivitiesForConnection:connection force:NO]; spinUntilIdle(indexer);
    CHECK(gActivityRequests > 39 && [s activityProgress][@"scanTop"] == nil && [[s activityProgress][@"boundary"] longLongValue] == t0 + 8000);
    [s close];

    // #9 a run replaced as stale writes nothing when its reply finally comes.
    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"followup-stale" error:nil];
    indexer = [ProbeIndexer new]; indexer.activityStore = s; [indexer.lockedRepos addObject:@"r"];
    gHeld = [NSMutableArray array]; gHoldActivity = YES;
    gLog = [NSMutableArray arrayWithObject:activityEvent(@"r", @"create", @"file", @"/old/f", t0 + 100)];
    [indexer syncActivitiesForConnection:connection force:YES]; CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    [indexer ageSync];
    gLog = [NSMutableArray arrayWithObject:activityEvent(@"r", @"create", @"file", @"/new/f", t0 + 200)];
    [indexer syncActivitiesForConnection:connection force:YES]; CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    gHoldActivity = NO;
    CHECK(gHeld.count == 2);
    if (gHeld.count == 2) {
        gHeld[1](); spinUntilIdle(indexer);
        gHeld[0](); spinUntilIdle(indexer);
    }
    CHECK([[s activityProgress][@"boundary"] longLongValue] == t0 + 200 && ![[s activityRecheckDirectoryPathsOfRepo:@"r"] containsObject:@"/old"]);
    [s close];
}
static void directoryCheckScheduling(void) {
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"directory-checks" error:nil];
    ProbeIndexer *indexer = [ProbeIndexer new]; indexer.activityStore = s;
    SeafConnection *connection = [SeafConnection new];
    SeafFPRecord *a = [s upsertRecordForRepo:@"r" path:@"/a" isDir:YES parentUUID:nil oid:@"a" mtime:1 size:-1];
    SeafFPRecord *b = [s upsertRecordForRepo:@"r" path:@"/a/b" isDir:YES parentUUID:a.uuid oid:@"b" mtime:1 size:-1];
    SeafFPRecord *kept = [s upsertRecordForRepo:@"r" path:@"/a/kept.txt" isDir:NO parentUUID:a.uuid oid:@"k" mtime:1 size:1];
    SeafFPRecord *x = [s upsertRecordForRepo:@"r" path:@"/x" isDir:YES parentUUID:nil oid:@"x" mtime:1 size:-1];
    SeafFPRecord *gone = [s upsertRecordForRepo:@"r" path:@"/x/gone.txt" isDir:NO parentUUID:x.uuid oid:@"g" mtime:1 size:1];
    for (NSString *path in @[@"/a/b", @"/deny", @"/x", @"/y", @"/z"]) [s requestDirectoryCheckOfRepo:@"r" path:path];
    [s requestDirectoryCheckOfRepo:@"lost" path:@"/q"];
    [s requestDirectoryCheckOfRepo:@"proxied" path:@"/p/q"];   // a 404 without seahub's body
    [s applyActivitiesOfRepo:@"r" entries:@[@{SeafFPEntryOp:SeafFPActivityOpDelete, SeafFPEntryPath:@"/x/gone.txt", SeafFPEntryIsDir:@NO, SeafFPEntryMtime:@100}]];
    gDirs = [@{@"r|/a/b": @404, @"r|/a": @[@{SeafFPEntryName:@"kept.txt", SeafFPEntryIsDir:@NO, SeafFPEntryOid:@"k", SeafFPEntrySize:@1, SeafFPEntryMtime:@1}],
               @"r|/deny": @403, @"r|/x": @[], @"r|/y": @[], @"r|/z": @[], @"lost|/q": @4040, @"proxied|/p/q": @4044} mutableCopy];
    gDirRequests = 0; gMaxInFlight = 0;
    [indexer runDirectoryChecksForConnection:connection];
    spinUntilIdle(indexer);
    NSArray *left = [s activityRecheckDirectoryPathsOfRepo:@"r"];
    CHECK([left isEqual:@[@"/deny"]] && [s activityRecheckDirectoryPathsOfRepo:@"lost"].count == 0);
    // The bare 404 neither walks up to the parent nor drops the library: it backs off where it is.
    CHECK([[s activityRecheckDirectoryPathsOfRepo:@"proxied"] isEqual:@[@"/p/q"]]
          && [s dueDirectoryChecksAt:[NSDate date] limit:10 repoIds:@[@"proxied"]].count == 0
          && [s dueDirectoryChecksAt:[NSDate dateWithTimeIntervalSinceNow:3600] limit:10 repoIds:@[@"proxied"]].count == 1);
    CHECK([s recordForUUID:b.uuid].deleted && ![s recordForUUID:kept.uuid].deleted && [s recordForUUID:gone.uuid].deleted);
    CHECK(gMaxInFlight <= 2 && gMaxInFlight >= 1);
    NSArray<SeafFPDirectoryCheck *> *deferred = [s dueDirectoryChecksAt:[NSDate dateWithTimeIntervalSinceNow:3600] limit:10 repoIds:@[@"r"]];
    CHECK(deferred.count == 1 && deferred.firstObject.attempts == 1 && [s dueDirectoryChecksAt:[NSDate date] limit:10].count == 0);
    // The same check is never listed twice at once.
    NSUInteger before = gDirRequests;
    [s requestDirectoryCheckOfRepo:@"r" path:@"/y"];
    [indexer runDirectoryChecksForConnection:connection];
    [indexer runDirectoryChecksForConnection:connection];
    spinUntilIdle(indexer);
    CHECK(gDirRequests == before + 1 && ![[s activityRecheckDirectoryPathsOfRepo:@"r"] containsObject:@"/y"]);
    // A locked library keeps its checks until it can be listed.
    [indexer.lockedRepos addObject:@"r"];
    [s requestDirectoryCheckOfRepo:@"r" path:@"/z"];
    before = gDirRequests;
    [indexer runDirectoryChecksForConnection:connection];
    spinUntilIdle(indexer);
    CHECK(gDirRequests == before && [[s activityRecheckDirectoryPathsOfRepo:@"r"] containsObject:@"/z"]);
    [s close];
}

'''

edge_tests = r'''
static SeafFPRecord *row(SeafFPStore *s, NSString *repo, NSString *path, NSString *oid) {
    return [s upsertRecordForRepo:repo path:path isDir:NO parentUUID:nil oid:oid mtime:10 size:5];
}
static NSDictionary *listingEntry(NSString *name, NSString *oid) {
    return @{SeafFPEntryName:name, SeafFPEntryIsDir:@NO, SeafFPEntryOid:oid, SeafFPEntryMtime:@10, SeafFPEntrySize:@5};
}
static NSDictionary *op(NSString *kind, NSString *old, NSString *path, long long t) {
    NSMutableDictionary *result = [@{SeafFPEntryOp:kind, SeafFPEntryPath:path, SeafFPEntryIsDir:@NO, SeafFPEntryMtime:@(t)} mutableCopy];
    if (old) result[SeafFPEntryOldPath] = old;
    return result;
}
static void favorite(SeafFPStore *s, SeafFPRecord *r) {
    SeafFPDecoration *d=[SeafFPDecoration new]; d.itemIdentifier=r.itemIdentifier; d.favoriteRank=@42;
    [s setDecoration:d];
}
static void uploadListingWins(void) {
    SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:@"upload-race" error:nil];
    SeafFPStore *other=[[SeafFPStore alloc] initWithDomainIdentifier:@"upload-race" error:nil];
    SeafFPRecord *stale=row(s,@"r",@"/A",@"old"); favorite(s,stale);
    long long start=[s prepareFileCreationInRepo:@"r" path:@"/A" requestStartSeq:s.currentSeq];
    CHECK(start >= 0 && [s recordForUUID:stale.uuid].deleted);
    [other applyListingOfRepo:@"r" directoryPath:@"/" entries:@[listingEntry(@"A",@"uploaded")] requestStartSeq:other.currentSeq];
    SeafFPRecord *result=[s recordCreatedFileInRepo:@"r" path:@"/A" parentUUID:nil oid:@"uploaded" mtime:10 size:5 requestStartSeq:start serverTime:200];
    SeafFPRecord *live=[s recordForRepo:@"r" path:@"/A" includeDeleted:NO];
    CHECK(result && ![result.uuid isEqual:stale.uuid] && ![s decorationForItem:result.itemIdentifier].favoriteRank);
    [other close]; [s close];
}
static void editedRenameOrderAndReplacement(void) {
    for (int mode=0;mode<3;mode++) {
        NSString *domain=[NSString stringWithFormat:@"edit-order-%d",mode];
        SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPStore *other=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPRecord *original=row(s,@"r",@"/import",@"original"); favorite(s,original);
        CHECK([s confirmMoveOfRecord:original toRepo:@"r" path:@"/A" parentUUID:nil requestStartSeq:s.currentSeq serverTime:200]);
        NSMutableArray *events=[NSMutableArray arrayWithObject:op(SeafFPActivityOpMove,@"/A",@"/B",300)];
        if(mode==2) {
            // The same collected log explicitly shows B being deleted and recreated.
            [events addObject:op(SeafFPActivityOpDelete,nil,@"/B",310)];
            [events addObject:op(SeafFPActivityOpCreate,nil,@"/B",320)];
        }
        [s applyActivitiesOfRepo:@"r" entries:events];
        NSArray *listing=@[listingEntry(@"B",mode==2?@"unrelated":@"edited")];
        if(mode==1) [other applyListingOfRepo:@"r" directoryPath:@"/" entries:listing requestStartSeq:other.currentSeq];
        [s decideRenameHintsWithLimit:100];
        [other applyListingOfRepo:@"r" directoryPath:@"/" entries:listing requestStartSeq:other.currentSeq];
        SeafFPRecord *b=[s recordForRepo:@"r" path:@"/B" includeDeleted:NO];
        BOOL same=[b.uuid isEqual:original.uuid];
        NSNumber *fav=[s decorationForItem:b.itemIdentifier].favoriteRank;
        CHECK(b && same==(mode!=2) && [fav isEqual:@42]==(mode!=2));
        [other close]; [s close];
    }
}
static void retombstoneAfterRevival(void) {
    NSString *domain=@"intermediate-revival";
    SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    SeafFPStore *other=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    SeafFPRecord *a=row(s,@"r",@"/A",@"content"); favorite(s,a);
    NSArray *final=@[listingEntry(@"C",@"content")];
    [s applyListingOfRepo:@"r" directoryPath:@"/" entries:final requestStartSeq:s.currentSeq];
    NSMutableArray *hints=[NSMutableArray array];
    for (int i=0;i<99;i++) [hints addObject:op(SeafFPActivityOpMove,[NSString stringWithFormat:@"/gone-%d",i],@"/gone",i+1)];
    [hints addObjectsFromArray:@[op(SeafFPActivityOpMove,@"/A",@"/B",200),op(SeafFPActivityOpMove,@"/B",@"/C",300)]];
    [s applyActivitiesOfRepo:@"r" entries:hints];
    [s decideRenameHintsWithLimit:100];
    CHECK([[s recordForUUID:a.uuid].path isEqual:@"/B"]);
    // After the real A -> B -> C, the server creates a different file at B.
    // That fresh directory response interleaves the two decision batches.
    [other applyListingOfRepo:@"r" directoryPath:@"/" entries:@[listingEntry(@"B",@"replacement"),listingEntry(@"C",@"content")] requestStartSeq:other.currentSeq];
    [other close]; [s close];
    s=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    [s decideRenameHintsWithLimit:100];
    SeafFPRecord *c=[s recordForRepo:@"r" path:@"/C" includeDeleted:NO];
    SeafFPRecord *b=[s recordForRepo:@"r" path:@"/B" includeDeleted:NO];
    CHECK([c.uuid isEqual:a.uuid] && [[s decorationForItem:c.itemIdentifier].favoriteRank isEqual:@42]);
    CHECK(b && ![b.uuid isEqual:a.uuid] && ![s decorationForItem:b.itemIdentifier].favoriteRank);
    [s close];
}
static void shiftAfterResumeAlreadyValidated(void) {
    NSString *domain=@"shift-on-22";
    SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    ProbeIndexer *idx=[ProbeIndexer new]; idx.activityStore=s; [idx.lockedRepos addObject:@"r"];
    SeafConnection *c=[SeafConnection new];
    long long t0=1800000000;
    [s recordActivityEntries:@[] progress:@{@"boundary":@(t0)}];
    gLog=[NSMutableArray array];
    for(int i=0;i<750;i++) [gLog addObject:activityEvent(@"r",@"create",@"file",[NSString stringWithFormat:@"/later-%d/f",i],
        i<450?t0+7500-i*10:t0+2500)];
    [idx syncActivitiesForConnection:c force:YES]; spinUntilIdle(idx);
    CHECK([s.activityProgress[@"nextPage"] intValue]==21);
    [s close];
    s=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    idx=[ProbeIndexer new]; idx.activityStore=s; [idx.lockedRepos addObject:@"r"];
    gShiftBeforeActivityPage=22;
    [idx syncActivitiesForConnection:c force:YES]; spinUntilIdle(idx);
    [idx syncActivitiesForConnection:c force:YES]; spinUntilIdle(idx);
    NSArray *paths=[s activityRecheckDirectoryPathsOfRepo:@"r"];
    CHECK(paths.count==750 && [paths containsObject:@"/later-525"]);
    [s close];
}
static void pendingMoveWithSourceReuse(void) {
    NSString *domain=@"pending-source-reused";
    SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    SeafFPStore *other=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    SeafFPRecord *source=row(s,@"r",@"/A",@"moved"); favorite(s,source);
    long long start=s.currentSeq;
    CHECK([s rememberMoveOfRecord:source toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"B" requestStartSeq:start serverTime:200]);
    [other applyListingOfRepo:@"r" directoryPath:@"/" entries:@[listingEntry(@"A",@"reused"),listingEntry(@"B",@"moved")] requestStartSeq:other.currentSeq];
    [s close]; [other close];
    s=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    TestExtension *ext=enumerator(s,@"r").extension;
    SeafRepo *root=ext.connection.rootFolder.items.firstObject; root.path=@"/";
    SeafBase *a=[SeafBase new]; a.name=@"A"; a.oid=@"reused";
    SeafBase *b=[SeafBase new]; b.name=@"B"; b.oid=@"moved"; root.items=@[a,b];
    for(int attempt=0;attempt<2;attempt++) {
        NSDictionary *pending=[s moveRecoveryForUUID:source.uuid];
        [ext recoverMoveOfRecord:[s recordForUUID:source.uuid] details:pending completion:^(SeafFPRecord *moved, SeafFPMoveSettlement settlement, NSError *error) { BOOL applied = moved && !error && settlement == SeafFPMoveSettlementRecovered;
            CHECK(applied && [moved.uuid isEqual:source.uuid] && [moved.path isEqual:@"/B"] && !error);
        }];
        if (![s moveRecoveryForUUID:source.uuid].count) break;
    }
    SeafFPRecord *live=[s recordForRepo:@"r" path:@"/A" includeDeleted:NO];
    CHECK(![live.uuid isEqual:source.uuid] && ![s decorationForItem:live.itemIdentifier].favoriteRank);
    [s close];
}
static void newRepoVisibleWhileResumingAfterRestart(void) {
    NSString *domain=@"unlocked-during-restart";
    SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    [s performBatch:^{ for(int i=0;i<220;i++) row(s,@"r",[NSString stringWithFormat:@"/a-%d",i],@"x"); }];
    SeafFPRecord *file=row(s,@"hidden",@"/secret",@"s");
    NSDictionary *r=repoInfo(@"r",@"R",YES);
    NSMutableDictionary *hidden=[repoInfo(@"hidden",@"Hidden",YES) mutableCopy]; hidden[@"locked"]=@YES;
    [s applyRepositorySnapshot:@[r,hidden] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    SeafFPEnumerator *e=enumerator(s,@"r");
    TestObserver *first=[TestObserver new]; [e enumerateWorkingSetPage:[NSData data] observer:first];
    CHECK(first.nextPage && ![first.identifiers containsObject:@"r:hidden"]);
    [s applyRepositorySnapshot:@[r,repoInfo(@"hidden",@"Hidden",YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    // A library that became visible after the scan started is delivered
    // before its rows, never a row without its library.
    TestObserver *same=[TestObserver new]; [e enumerateWorkingSetPage:first.nextPage observer:same];
    CHECK(!same.error && [same.listed indexOfObject:@"r:hidden"] < [same.listed indexOfObject:file.itemIdentifier]
          && [same.identifiers containsObject:file.itemIdentifier]);
    // After a restart the page token alone carries the scan on.
    [s close]; s=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    TestObserver *second=[TestObserver new]; [enumerator(s,@"r") enumerateWorkingSetPage:first.nextPage observer:second];
    CHECK(!second.error && !second.nextPage && [second.listed indexOfObject:@"r:hidden"] < [second.listed indexOfObject:file.itemIdentifier]
          && [second.identifiers containsObject:file.itemIdentifier]);
    TestObserver *restart=[TestObserver new];
    [enumerator(s,@"r") enumerateWorkingSetPage:[NSData data] observer:restart];
    CHECK(!restart.error && [restart.identifiers containsObject:@"r:hidden"]);
    [s close];
}

static void independentTargetStillAwaitingConfirmation(void) {
    NSString *domain=@"independent-target-pending";
    SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    SeafFPStore *other=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
    SeafFPRecord *first=row(s,@"r",@"/first",@"same");
    long long firstStart=s.currentSeq;
    NSString *resolved=[s confirmedNameForRecord:first expected:@"dst" inRepo:@"r" directory:@"/"
        entries:@[listingEntry(@"dst",@"same")] requestStartSeq:firstStart];
    CHECK([resolved isEqual:@"dst"]);
    SeafFPRecord *second=row(other,@"r",@"/second",@"same");
    long long secondStart=[other beginMoveOfRecord:second toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"dst" requestedName:nil existingDestinationNames:@[]];
    CHECK(secondStart>=0 && [other noteMoveReceiptForUUID:second.uuid requestStartSeq:secondStart serverTime:300]);
    CHECK([s beginMoveOfRecord:first toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"DST" requestedName:nil existingDestinationNames:@[]]<0);
    // The second server operation is already confirmed, but its own
    // callback has not yet merged the UUID discovered by this browse.
    SeafFPRecord *temporary=row(other,@"r",@"/dst",@"same");
    favorite(other,temporary);
    SeafFPRecord *staleResult=[s confirmMoveOfRecord:first toRepo:@"r" path:@"/dst" parentUUID:nil
        requestStartSeq:firstStart serverTime:200];
    SeafFPRecord *rightResult=[other finishPendingMoveOfRecord:second toRepo:@"r" path:@"/dst" parentUUID:nil
        requestStartSeq:secondStart serverTime:300];
    CHECK(!staleResult && [rightResult.uuid isEqual:second.uuid] && ![s decorationForItem:first.itemIdentifier].favoriteRank);
    [other close]; [s close];
}


static SeafBase *serverFile(NSString *name, NSString *oid) {
    SeafBase *entry = [SeafBase new]; entry.name = name; entry.oid = oid;
    return entry;
}

static SeafFPItem *modifyTemplate(SeafFPRecord *source, NSString *repoId, NSString *name) {
    SeafFPRecord *record = [SeafFPRecord new];
    record.uuid = source.uuid; record.repoId = repoId; record.path = [@"/" stringByAppendingString:name]; record.name = name;
    return [SeafFPItem itemForRecord:record repoEditable:YES];
}

static void moveRequestDefinitivelyRejected(void) {
    NSDictionary<NSNumber *, NSNumber *> *expectedErrors = @{
        @(NSURLErrorNotConnectedToInternet): @(NSFileProviderErrorServerUnreachable),
        @(NSURLErrorCannotFindHost): @(NSFileProviderErrorServerUnreachable),
        @(NSURLErrorCannotConnectToHost): @(NSFileProviderErrorServerUnreachable),
        @400: @(NSFileProviderErrorCannotSynchronize), @401: @(NSFileProviderErrorNotAuthenticated),
        @403: @(NSFileProviderErrorNotAuthenticated), @409: @(NSFileProviderErrorFilenameCollision),
        @440: @(NSFileProviderErrorCannotSynchronize), @441: @(NSFileProviderErrorCannotSynchronize),
        @443: @(NSFileProviderErrorInsufficientQuota)
    };
    for (NSNumber *code in expectedErrors) {
        NSString *domain = [@"move-rejected-" stringByAppendingString:code.stringValue];
        SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPStore *other = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        TestExtension *ext = enumerator(s, @"r").extension;
        ext.connection.rootFolder.items.firstObject.path = @"/";
        SeafFPRecord *source = row(s, @"r", @"/A", @"x");
        BOOL reparent = [code isEqual:@443];
        NSString *destinationRepo = reparent ? @"dst" : @"r";
        NSString *destinationName = reparent ? @"A" : @"B";
        if (reparent) [s applyRepositorySnapshot:@[repoInfo(@"r", @"Source", YES), repoInfo(@"dst", @"Destination", YES)]
                                        complete:YES fromCache:NO requestStartSeq:s.currentSeq];
        SeafFPItem *requested = modifyTemplate(source, destinationRepo, destinationName);
        NSFileProviderItemFields fields = reparent ? NSFileProviderItemParentItemIdentifier : NSFileProviderItemFilename;
        ext.liveListings = @{@"r:/": @[serverFile(@"A", @"x")], @"dst:/": @[]};
        gMoveStatus = MAX(code.integerValue, 0);
        gMoveError = [NSError errorWithDomain:gMoveStatus ? @"TestHTTP" : NSURLErrorDomain code:code.integerValue userInfo:nil];
        gMoveRequests = 0;
        __block long long rejectedStart = -1;
        gBeforeMoveResponse = ^{
            rejectedStart = [[other moveRecoveryForUUID:source.uuid][@"start"] longLongValue];
            CHECK(rejectedStart > 0);
        };
        [ext modifyItem:requested baseVersion:nil changedFields:fields contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields fields, BOOL fetch, NSError *error) {
                CHECK(!item && [error.domain isEqual:NSFileProviderErrorDomain] && error.code == expectedErrors[code].integerValue);
            }];
        CHECK(gMoveRequests == 1 && [other moveRecoveryForUUID:source.uuid].count == 0);
        gMoveStatus = 0;
        gMoveError = nil;
        gBeforeMoveResponse = nil;
        gServerRelocate = ^(SeafDir *src, SeafDir *dst, NSString *oldName, NSString *newName) {
            CHECK([oldName isEqual:@"A"] && [newName isEqual:destinationName] && [dst.repoId isEqual:destinationRepo]);
            CHECK(![other discardUnconfirmedMoveForUUID:source.uuid requestStartSeq:rejectedStart]);
            CHECK([[other moveRecoveryForUUID:source.uuid][@"start"] longLongValue] > rejectedStart);
            ext.liveListings = @{[destinationRepo stringByAppendingString:@":/"]: @[serverFile(destinationName, @"x")]};
        };
        [ext modifyItem:requested baseVersion:nil changedFields:fields contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields fields, BOOL fetch, NSError *error) {
                CHECK(!error && [item.filename isEqual:destinationName] && [item.itemIdentifier isEqual:source.itemIdentifier]
                    && [item.parentItemIdentifier isEqual:[SeafFPIdentifier identifierForRepo:destinationRepo]]);
            }];
        CHECK(gMoveRequests == 2 && [other moveRecoveryForUUID:source.uuid].count == 0);
        gServerRelocate = nil;
        [other close]; [s close];
    }
}

static void lostMoveResponse(void) {
    for (int mode = 0; mode < 3; mode++) {
        NSString *domain = [NSString stringWithFormat:@"lost-move-response-%d", mode];
        SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPStore *other = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPRecord *source = row(s, @"r", @"/A", @"x"); favorite(s, source);
        [s applyRepositorySnapshot:@[repoInfo(@"r",@"Source",YES), repoInfo(@"dst",@"Destination",YES)]
                          complete:YES fromCache:NO requestStartSeq:s.currentSeq];
        TestExtension *ext = enumerator(s, @"r").extension;
        ext.connection.rootFolder.items.firstObject.path = @"/";
        SeafBase *entry = serverFile(@"A", @"x");
        ext.liveListings = @{@"r:/": @[entry], @"dst:/": @[]};
        SeafFPItem *requested = modifyTemplate(source, @"dst", @"A");
        gMoveRequests = 0;
        gDropMoveReply = mode == 1;
        gMoveStatus = mode == 2 ? 404 : 0;   // a post-mutation directory reload can return 404
        gMoveError = mode == 0 ? [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]
            : (mode == 2 ? [NSError errorWithDomain:@"TestHTTP" code:404 userInfo:nil] : nil);
        gBeforeMoveResponse = ^{
            NSDictionary *journal = [other moveRecoveryForUUID:source.uuid];
            CHECK([journal[@"confirmed"] isEqual:@NO] && [journal[@"repo"] isEqual:@"dst"]);
            [other applyListingOfRepo:@"dst" directoryPath:@"/" entries:@[listingEntry(@"A",@"x")] requestStartSeq:other.currentSeq];
            [other applyListingOfRepo:@"r" directoryPath:@"/" entries:@[] requestStartSeq:other.currentSeq];
        };
        __block NSUInteger replies = 0;
        [ext modifyItem:requested baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields fields, BOOL fetch, NSError *error) {
                replies++;
                NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
                CHECK(!item && isMovePending(error) && underlying.code == gMoveError.code);
            }];
        CHECK(replies == (mode == 1 ? 0 : 1) && gMoveRequests == 1);
        CHECK([s moveRecoveryForUUID:source.uuid].count && [s recordForUUID:source.uuid].deleted);
        gBeforeMoveResponse = nil; gMoveError = nil; gMoveStatus = 0; gDropMoveReply = NO;
        [other close]; [s close];
        s = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        ext = enumerator(s, @"r").extension;
        ext.connection.rootFolder.items.firstObject.path = @"/";
        ext.liveListings = @{@"r:/": @[entry], @"dst:/": @[]};
        [ext modifyItem:requested baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields fields, BOOL fetch, NSError *error) {
                CHECK(!item && error && gMoveRequests == 1 && [s moveRecoveryForUUID:source.uuid].count);
            }];
        // Seeing the same content on both ends still does not establish that it moved.
        ext.liveListings = @{@"r:/": @[entry], @"dst:/": @[entry]};
        [ext modifyItem:requested baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields fields, BOOL fetch, NSError *error) {
                CHECK(!item && error && [s moveRecoveryForUUID:source.uuid].count);
            }];
        ext.liveListings = @{@"r:/": @[], @"dst:/": @[entry]};
        [ext modifyItem:requested baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields fields, BOOL fetch, NSError *error) {
                CHECK(!error && [item.itemIdentifier isEqual:source.itemIdentifier] && [item.parentItemIdentifier isEqual:@"r:dst"]);
            }];
        CHECK(gMoveRequests == 1 && ![s moveRecoveryForUUID:source.uuid].count);
        CHECK([[s decorationForItem:source.itemIdentifier].favoriteRank isEqual:@42]);
        [s close];
    }
}


static void lostConflictRenameResponse(void) {
    for (NSUInteger scenario = 0; scenario < 4; scenario++) {
        NSString *domain = [NSString stringWithFormat:@"lost-conflict-rename-%lu", (unsigned long)scenario];
        SeafFPStore *store = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPRecord *source = row(store, @"r", @"/A", @"x");
        favorite(store, source);
        TestExtension *extension = enumerator(store, @"r").extension;
        extension.connection.rootFolder.items.firstObject.path = @"/";
        SeafBase *original = serverFile(@"A", @"x");
        SeafBase *oldConflict = serverFile(@"B (1)", @"x");
        SeafBase *occupied = serverFile(@"B", @"other");
        NSArray *preflight = @[original];
        if (scenario == 1 || scenario == 2) preflight = @[original, oldConflict];
        if (scenario == 3) preflight = @[original, occupied];
        extension.liveListings = @{@"r:/": preflight};
        SeafFPItem *requested = modifyTemplate(source, @"r", @"B");
        gMoveRequests = 0;
        gDropMoveReply = YES;
        gServerRelocate = ^(SeafDir *src, SeafDir *dst, NSString *oldName, NSString *newName) {
            CHECK([oldName isEqual:@"A"] && [newName isEqual:(scenario == 3 ? @"B (1)" : @"B")]);
        };
        [extension modifyItem:requested baseVersion:nil changedFields:NSFileProviderItemFilename contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields fields, BOOL fetch, NSError *error) {
                CHECK(NO);   // The transport dropped the whole callback.
            }];
        CHECK(gMoveRequests == 1);
        CHECK([store moveRecoveryForUUID:source.uuid].count > 0);
        gDropMoveReply = NO;
        gServerRelocate = nil;
        [store close];

        store = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        extension = enumerator(store, @"r").extension;
        extension.connection.rootFolder.items.firstObject.path = @"/";
        extension.liveListings = @{@"r:/": scenario == 2 ? @[occupied, oldConflict, serverFile(@"B (2)", @"x")] : @[occupied, oldConflict]};
        [extension modifyItem:requested baseVersion:nil changedFields:NSFileProviderItemFilename contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields fields, BOOL fetch, NSError *error) {
                if (scenario == 1) CHECK(!item && isMovePending(error));
                else CHECK(!error && [item.itemIdentifier isEqual:source.itemIdentifier]
                    && [item.filename isEqual:scenario == 2 ? @"B (2)" : @"B (1)"]);
            }];
        CHECK(gMoveRequests == 1 && ([store moveRecoveryForUUID:source.uuid].count > 0) == (scenario == 1));
        CHECK([[store decorationForItem:source.itemIdentifier].favoriteRank isEqual:@42]);
        if (scenario != 1) {
            NSString *reserved = scenario == 3 ? @"/b (1)" : @"/b";
            SeafFPRecord *competitor = row(store, @"r", @"/competitor", @"y");
            CHECK([store beginMoveOfRecord:competitor toRepo:@"r" directory:@"/" parentUUID:nil
                expectedName:reserved.lastPathComponent requestedName:nil existingDestinationNames:@[]] > 0);
        }
        [store close];
    }
}

static void acknowledgedMoveWithExistingDuplicate(void) {
    for (int scenario = 0; scenario < 3; scenario++) {
        BOOL rename = scenario != 0;
        BOOL concurrentConflict = scenario == 2;
        NSString *domain = [NSString stringWithFormat:@"acknowledged-move-with-duplicate-%d", scenario];
        NSString *destination = rename ? @"r" : @"dst";
        NSString *expected = rename ? @"B" : @"A";
        NSString *finalName = concurrentConflict ? @"B (2)" : expected;
        SeafFPStore *store = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPRecord *source = row(store, @"r", @"/A", @"x");
        favorite(store, source);
        [store applyRepositorySnapshot:@[repoInfo(@"r", @"Source", YES), repoInfo(@"dst", @"Destination", YES)]
                              complete:YES fromCache:NO requestStartSeq:store.currentSeq];
        TestExtension *extension = enumerator(store, @"r").extension;
        extension.connection.rootFolder.items.firstObject.path = @"/";
        SeafBase *original = serverFile(@"A", @"x");
        SeafBase *duplicate = serverFile([expected stringByAppendingString:@" (1)"], @"x");
        extension.liveListings = rename ? @{@"r:/": @[original, duplicate]} :
            @{@"r:/": @[original], @"dst:/": @[duplicate]};
        SeafFPItem *requested = modifyTemplate(source, destination, expected);
        NSFileProviderItemFields fields = rename ? NSFileProviderItemFilename : NSFileProviderItemParentItemIdentifier;
        gMoveRequests = 0;
        gMoveStatus = 200;
        gServerRelocate = ^(SeafDir *src, SeafDir *dst, NSString *oldName, NSString *newName) {
            CHECK([dst.repoId isEqual:destination] && [oldName isEqual:@"A"] && [newName isEqual:expected]);
            NSArray *targetEntries = @[serverFile(finalName, @"x"), duplicate];
            if (concurrentConflict) targetEntries = [targetEntries arrayByAddingObject:serverFile(expected, @"other")];
            extension.liveListings = rename ? @{@"r:/": targetEntries} : @{@"r:/": @[], @"dst:/": targetEntries};
        };
        [extension modifyItem:requested baseVersion:nil changedFields:fields contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem result, NSFileProviderItemFields remaining, BOOL fetch, NSError *error) {
                CHECK(!error && [result.itemIdentifier isEqual:source.itemIdentifier] && [result.filename isEqual:finalName]
                    && [result.parentItemIdentifier isEqual:[@"r:" stringByAppendingString:destination]]);
            }];
        CHECK(gMoveRequests == 1 && [store moveRecoveryForUUID:source.uuid].count == 0);
        CHECK([[store decorationForItem:source.itemIdentifier].favoriteRank isEqual:@42]);
        gMoveStatus = 0;
        gServerRelocate = nil;
        [store close];
    }
}

static void unacknowledgedMoveDoesNotReplay(void) {
    for (NSNumber *code in @[@(NSURLErrorTimedOut), @404, @500]) {
        NSString *domain = [@"unacknowledged-move-" stringByAppendingString:code.stringValue];
        SeafFPStore *store = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPRecord *source = row(store, @"r", @"/A", @"x");
        favorite(store, source);
        [store applyRepositorySnapshot:@[repoInfo(@"r", @"Source", YES), repoInfo(@"dst", @"Destination", YES)]
                              complete:YES fromCache:NO requestStartSeq:store.currentSeq];
        TestExtension *extension = enumerator(store, @"r").extension;
        extension.connection.rootFolder.items.firstObject.path = @"/";
        SeafBase *original = serverFile(@"A", @"x");
        SeafBase *duplicate = serverFile(@"A (1)", @"x");
        NSDictionary *unmoved = @{@"r:/": @[original], @"dst:/": @[duplicate]};
        extension.liveListings = unmoved;
        SeafFPItem *requested = modifyTemplate(source, @"dst", @"A");
        NSFileProviderItemFields fields = NSFileProviderItemParentItemIdentifier;
        gMoveRequests = 0;
        gMoveStatus = MAX(0, code.integerValue);
        gMoveError = [NSError errorWithDomain:gMoveStatus ? @"TestHTTP" : NSURLErrorDomain code:code.integerValue userInfo:nil];
        [extension modifyItem:requested baseVersion:nil changedFields:fields contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem result, NSFileProviderItemFields remaining, BOOL fetch, NSError *error) {
                CHECK(!result && error && gMoveRequests == 1);
            }];
        gMoveStatus = 0;
        gMoveError = nil;

        // Simulate a journal from a previous build (pre-dispatch entries
        // instead of names).
        NSMutableDictionary *journal = [[store moveRecoveryForUUID:source.uuid] mutableCopy];
        CHECK([journal[@"existingDestinationNames"] isEqual:@[@"a (1)"]]);
        CHECK([journal[@"startedAt"] longLongValue] > 0 && ![SeafFPStore moveJournalExpired:journal now:(long long)[NSDate date].timeIntervalSince1970]);
        [journal removeObjectForKey:@"existingDestinationNames"];
        journal[@"existingDestinationEntries"] = @{@"a (1)": listingEntry(@"A (1)", @"x")};
        NSData *encoded = [NSJSONSerialization dataWithJSONObject:journal options:0 error:nil];
        CHECK(encoded != nil);
        [store setMetaValue:[[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding]
                     forKey:[@"fp_confirmed_move:" stringByAppendingString:source.uuid]];
        [store close];

        store = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        extension = enumerator(store, @"r").extension;
        extension.connection.rootFolder.items.firstObject.path = @"/";
        extension.liveListings = unmoved;
        // Without conclusive evidence nothing is re-sent or dropped.
        void (^expectPending)(NSFileProviderItem, NSFileProviderItemFields, BOOL, NSError *) =
            ^(NSFileProviderItem result, NSFileProviderItemFields remaining, BOOL fetch, NSError *error) {
                CHECK(!result && isMovePending(error) && gMoveRequests == 1
                    && [[store moveRecoveryForUUID:source.uuid] isEqual:journal]);
            };
        [extension modifyItem:requested baseVersion:nil changedFields:fields contents:nil options:0 request:nil completionHandler:expectPending];
        [extension modifyItem:modifyTemplate(source, @"r", @"C") baseVersion:nil changedFields:NSFileProviderItemFilename
                     contents:nil options:0 request:nil completionHandler:expectPending];

        // If the original operation later becomes visible, recover it without a POST.
        extension.liveListings = @{@"r:/": @[], @"dst:/": @[duplicate, original]};
        for (NSString *directory in @[@"r:/", @"dst:/"]) {
            extension.failingDirectories = [NSSet setWithObject:directory];
            [extension modifyItem:requested baseVersion:nil changedFields:fields contents:nil options:0 request:nil
                completionHandler:^(NSFileProviderItem result, NSFileProviderItemFields remaining, BOOL fetch, NSError *error) {
                    CHECK(!result && isMovePending(error) && [error.userInfo[NSUnderlyingErrorKey] code] == NSFileProviderErrorServerUnreachable && gMoveRequests == 1
                        && [[store moveRecoveryForUUID:source.uuid] isEqual:journal]);
                }];
        }
        extension.failingDirectories = nil;
        [extension modifyItem:requested baseVersion:nil changedFields:fields contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem result, NSFileProviderItemFields remaining, BOOL fetch, NSError *error) {
                CHECK(!error && [result.itemIdentifier isEqual:source.itemIdentifier]
                    && [result.filename isEqual:@"A"] && [result.parentItemIdentifier isEqual:@"r:dst"]);
            }];
        CHECK(gMoveRequests == 1 && [store moveRecoveryForUUID:source.uuid].count == 0);
        CHECK([[store decorationForItem:source.itemIdentifier].favoriteRank isEqual:@42]);
        [store close];
    }
}

static SeafBase *regressionFile(NSString *name, NSString *oid) {
    SeafFile *entry = [SeafFile new]; entry.name = name; entry.oid = oid; entry.mtime = 10; entry.filesize = 5;
    return entry;
}

static void setJournalAge(SeafFPStore *store, NSString *uuid, long long age) {
    NSMutableDictionary *journal=[[store moveRecoveryForUUID:uuid] mutableCopy];
    journal[@"startedAt"]=@((long long)[NSDate date].timeIntervalSince1970-age);
    NSData *data=[NSJSONSerialization dataWithJSONObject:journal options:0 error:nil];
    [store setMetaValue:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] forKey:[@"fp_confirmed_move:" stringByAppendingString:uuid]];
}
static void resetMoveTransport(void) {
    gMoveRequests=0; gMoveStatus=0; gMoveError=nil; gDropMoveReply=NO; gBeforeMoveResponse=nil; gServerRelocate=nil;
}
@interface ConfirmationRaceExtension : TestExtension
@property(copy) dispatch_block_t afterSourceListing;
@end
@implementation ConfirmationRaceExtension
- (void)loadDirectoryForMove:(SeafDir *)dir completion:(void (^)(BOOL,NSError *))completion {
    [super loadDirectoryForMove:dir completion:^(BOOL loaded,NSError *error) {
        if (loaded && [dir.repoId isEqual:@"r"] && self.afterSourceListing) {
            dispatch_block_t action=self.afterSourceListing; self.afterSourceListing=nil; action();
        }
        completion(loaded,error);
    }];
}
@end
static TestExtension *configuredExtension(SeafFPStore *s) {
    TestExtension *ext=enumerator(s,@"r").extension;
    ext.connection.rootFolder.items.firstObject.path=@"/";
    return ext;
}
static void pendingMoveRecoveryRegressions(void) {
    // 1: create the journal through the actual modifyItem path with a lost response.
    // Neither age nor an edited source or ambiguous target proves deletion or non-execution.
    for (int mode=0;mode<3;mode++) {
        resetMoveTransport();
        SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"confirm-source-%d",mode] error:nil];
        SeafFPRecord *a=row(s,@"r",@"/A",@"x"); favorite(s,a);
        TestExtension *ext=configuredExtension(s); ext.liveListings=@{@"r:/":@[regressionFile(@"A",@"x")]};
        gMoveError=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
        [ext modifyItem:modifyTemplate(a,@"r",@"B") baseVersion:nil changedFields:NSFileProviderItemFilename contents:nil options:0 request:nil completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { CHECK(error!=nil); }];
        CHECK(gMoveRequests==1 && [[s moveRecoveryForUUID:a.uuid][@"confirmed"] isEqual:@NO]);
        gMoveError=nil;
        setJournalAge(s,a.uuid,mode==0?60:660);
        if (mode<2) ext.liveListings=@{@"r:/":@[regressionFile(@"A",@"edited")]};
        else ext.liveListings=@{@"r:/":@[regressionFile(@"B",@"x"),regressionFile(@"B (1)",@"x")]};
        __block NSInteger status=0;
        [ext modifyItem:modifyTemplate(a,@"r",@"B") baseVersion:nil changedFields:NSFileProviderItemFilename contents:nil options:0 request:nil completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { status=error.code; }];
        CHECK(status==NSXPCConnectionReplyInvalid && gMoveRequests==1);
        CHECK(![s recordForUUID:a.uuid].deleted && [s moveRecoveryForUUID:a.uuid].count>0);
        CHECK([[s decorationForItem:a.itemIdentifier].favoriteRank isEqual:@42]);
        [s close];
    }
    // 2: exact same recoverable state, only journal age differs.
    for (int old=0;old<2;old++) {
        resetMoveTransport();
        SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"confirm-expiry-%d",old] error:nil];
        SeafFPRecord *a=row(s,@"r",@"/A",@"x"); favorite(s,a);
        TestExtension *ext=configuredExtension(s); ext.liveListings=@{@"r:/":@[regressionFile(@"A",@"x")]};
        gMoveStatus=200;
        gServerRelocate=^(SeafDir *src,SeafDir *dst,NSString *oldName,NSString *newName) {
            ext.liveListings=@{@"r:/":@[regressionFile(@"B",@"x")]};
            ext.failingDirectories=[NSSet setWithObject:@"r:/"]; // receipt exists, reconciliation interrupted
        };
        [ext modifyItem:modifyTemplate(a,@"r",@"B") baseVersion:nil changedFields:NSFileProviderItemFilename contents:nil options:0 request:nil completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { CHECK(error!=nil); }];
        CHECK([[s moveRecoveryForUUID:a.uuid][@"confirmed"] isEqual:@YES]);
        CHECK([s applyDirectoryListingOfRepo:@"r" directoryPath:@"/" entries:@[listingEntry(@"B",@"x")] requestStartSeq:s.currentSeq]!=SeafFPWriteFailed);
        CHECK([s recordForUUID:a.uuid].tombReason==SeafFPTombReasonAbsent);
        setJournalAge(s,a.uuid,old?8*86400:60); ext.failingDirectories=nil; gServerRelocate=nil;
        __block BOOL restored=NO; __block NSInteger status=0;
        [ext modifyItem:modifyTemplate(a,@"r",@"B") baseVersion:nil changedFields:NSFileProviderItemFilename contents:nil options:0 request:nil completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { restored=[item.itemIdentifier isEqual:a.itemIdentifier]; status=error.code; }];
        CHECK(restored && status==0 && gMoveRequests==1);
        CHECK([s recordForRepo:@"r" path:@"/B" includeDeleted:NO]!=nil);
        [s close];
    }
    // 3: a source path reused after a move: acknowledged and lost-receipt controls.
    for (int ack=0;ack<4;ack++) {
        resetMoveTransport();
        SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"confirm-reuse-%d",ack] error:nil];
        SeafFPRecord *a=row(s,@"r",@"/A",@"x"); favorite(s,a);
        long long start=[s beginMoveOfRecord:a toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"B" requestedName:@"B" existingDestinationNames:@[]];
        CHECK(start>0); if(ack==1) CHECK([s noteMoveReceiptForUUID:a.uuid requestStartSeq:start serverTime:1]);
        CHECK(([s applyDirectoryListingOfRepo:@"r" directoryPath:@"/" entries:@[listingEntry(@"A",@"replacement"),listingEntry(@"B",@"x")] requestStartSeq:s.currentSeq]!=SeafFPWriteFailed));
        if(ack==2) CHECK([s noteMoveReceiptForUUID:a.uuid requestStartSeq:start serverTime:1]);
        if(ack==3) CHECK([s applyDirectoryListingOfRepo:@"r" directoryPath:@"/" entries:@[listingEntry(@"B",@"x")] requestStartSeq:s.currentSeq]!=SeafFPWriteFailed);
        TestExtension *ext=configuredExtension(s);
        ext.liveListings=@{@"r:/":ack==3?@[regressionFile(@"B",@"x")]:@[regressionFile(@"A",@"replacement"),regressionFile(@"B",@"x")]};
        __block BOOL restored=NO; __block NSInteger status=0;
        [ext modifyItem:modifyTemplate(a,@"r",@"B") baseVersion:nil changedFields:NSFileProviderItemFilename contents:nil options:0 request:nil completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { restored=[item.itemIdentifier isEqual:a.itemIdentifier]; status=error.code; }];
        CHECK(restored && status==0 && [s moveRecoveryForUUID:a.uuid].count==0);
        SeafFPRecord *moved=[s recordForUUID:a.uuid];
        SeafFPRecord *replacement=[s recordForRepo:@"r" path:@"/A" includeDeleted:NO];
        CHECK([moved.path isEqual:@"/B"] && [moved.oid isEqual:@"x"]);
        CHECK([[s decorationForItem:a.itemIdentifier].favoriteRank isEqual:@42]);
        if(ack==3) CHECK(!replacement);
        else CHECK(replacement && ![replacement.uuid isEqual:a.uuid] && [replacement.oid isEqual:@"replacement"]
                   && ![s decorationForItem:replacement.itemIdentifier].favoriteRank);
        [s close];
    }
    // 4: pending move deletion with/without an intervening absence listing.
    for (int absent=0;absent<2;absent++) {
        resetMoveTransport();
        SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"confirm-delete-%d",absent] error:nil];
        SeafFPRecord *a=row(s,@"r",@"/A",@"x");
        long long start=[s beginMoveOfRecord:a toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"B" requestedName:@"B" existingDestinationNames:@[]];
        CHECK(start>0 && [s noteMoveReceiptForUUID:a.uuid requestStartSeq:start serverTime:1]);
        if(absent) CHECK([s applyDirectoryListingOfRepo:@"r" directoryPath:@"/" entries:@[listingEntry(@"B",@"x")] requestStartSeq:s.currentSeq]!=SeafFPWriteFailed);
        TestExtension *ext=configuredExtension(s); ext.liveListings=@{@"r:/":@[regressionFile(@"B",@"x")]}; gDeletedPaths=[NSMutableArray array];
        __block BOOL success=NO;
        [ext deleteItemWithIdentifier:a.itemIdentifier baseVersion:nil options:0 request:nil completionHandler:^(NSError *error) { success=error==nil; }];
        CHECK(success && gDeletedPaths.count==1);
        CHECK([gDeletedPaths.firstObject isEqual:@"r:/B"]);
        [s close];
    }
    // 5: full modifyItem preflight, another Store handle commits after the listing is captured.
    for(int race=0;race<2;race++) {
        resetMoveTransport();
        NSString *domain=[NSString stringWithFormat:@"confirm-race-%d",race];
        SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPStore *other=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPRecord *a=row(s,@"r",@"/A",@"initial");
        [s applyRepositorySnapshot:@[repoInfo(@"r",@"R",YES),repoInfo(@"dst",@"DST",YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
        ConfirmationRaceExtension *ext=[ConfirmationRaceExtension new]; ext.store=s; ext.connection=configuredExtension(s).connection;
        ext.liveListings=@{@"r:/":@[regressionFile(@"A",@"listing-before-upload")],@"dst:/":@[]};
        if(race) ext.afterSourceListing=^{ row(other,@"r",@"/A",@"new-upload"); };
        gMoveStatus=200;
        gServerRelocate=^(SeafDir *src,SeafDir *dst,NSString *oldName,NSString *newName) {
            CHECK([[[s recordForUUID:a.uuid] oid] isEqual:@"listing-before-upload"]);
            CHECK([[s moveRecoveryForUUID:a.uuid][@"oid"] isEqual:@"listing-before-upload"]);
            ext.liveListings=@{@"r:/":@[],@"dst:/":@[regressionFile(@"A",race?@"new-upload":@"listing-before-upload")]};
        };
        __block BOOL success=NO; __block NSInteger status=0;
        [ext modifyItem:modifyTemplate(a,@"dst",@"A") baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { success=item!=nil&&error==nil; status=error.code; }];
        CHECK(gMoveRequests==(race?0:1) && success==!race && status==(race?NSFileProviderErrorCannotSynchronize:0));
        if(race) {
            CHECK([[s recordForUUID:a.uuid].oid isEqual:@"new-upload"] && ![s moveRecoveryForUUID:a.uuid].count);
            ext.liveListings=@{@"r:/":@[regressionFile(@"A",@"new-upload")],@"dst:/":@[]};
            gServerRelocate=^(SeafDir *src,SeafDir *dst,NSString *oldName,NSString *newName) {
                CHECK([[s moveRecoveryForUUID:a.uuid][@"oid"] isEqual:@"new-upload"]);
                ext.liveListings=@{@"r:/":@[],@"dst:/":@[regressionFile(@"A",@"new-upload")]};
            };
            [ext modifyItem:modifyTemplate(a,@"dst",@"A") baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { CHECK(item && !error); }];
            CHECK(gMoveRequests==1 && [[s recordForUUID:a.uuid].oid isEqual:@"new-upload"]);
        }
        [other close]; [s close];
    }
    // 6: valid full-page control versus explicitly malformed timestamps.
    for(int malformed=0;malformed<2;malformed++) {
        resetMoveTransport();
        SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"confirm-activity-%d",malformed] error:nil];
        ProbeIndexer *idx=[ProbeIndexer new]; idx.activityStore=s; [idx.lockedRepos addObject:@"r"];
        SeafConnection *conn=[SeafConnection new]; long long now=SeafFPResponseTime(TestResponse(200));
        [s recordActivityEntries:@[] progress:@{@"boundary":@(now-3600)}];
        gLog=[NSMutableArray array];
        for(int i=0;i<25;i++) {
            NSMutableDictionary *event=[activityEvent(@"r",@"create",@"file",[NSString stringWithFormat:@"/first%d/f",i],now-10) mutableCopy];
            if(malformed) event[@"time"]=@"unparseable";
            [gLog addObject:event];
        }
        [gLog addObject:activityEvent(@"r",@"create",@"file",@"/second-page/f",now-100)];
        gActivityRequests=0; [idx syncActivitiesForConnection:conn force:YES]; spinUntilIdle(idx);
        BOOL collected=[[s activityRecheckDirectoryPathsOfRepo:@"r"] containsObject:@"/second-page"];
        CHECK(collected==!malformed);
        if(malformed) {
            CHECK([s.activityProgress[@"boundary"] longLongValue]==now-3600 && !s.activityProgress[@"scanTop"]);
            for(int i=0;i<25;i++) {
                NSMutableDictionary *event=[gLog[i] mutableCopy];
                event[@"time"]=activityEvent(@"r",@"create",@"file",@"/ignored/f",now-10)[@"time"];
                gLog[i]=event;
            }
            [idx syncActivitiesForConnection:conn force:YES]; spinUntilIdle(idx);
            CHECK([[s activityRecheckDirectoryPathsOfRepo:@"r"] containsObject:@"/second-page"]);
        }
        [s close];
    }
    // 7: full cross-repository move (not a hypothetical rename response).
    // The server picks A(1) after A becomes occupied; an old A(1) was removed meanwhile.
    for(int existed=0;existed<7;existed++) {
        resetMoveTransport();
        SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"confirm-conflict-%d",existed] error:nil];
        SeafFPRecord *a=row(s,@"r",@"/A",@"x"); favorite(s,a);
        [s applyRepositorySnapshot:@[repoInfo(@"r",@"R",YES),repoInfo(@"dst",@"DST",YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
        SeafFPRecord *former = existed>=4 ? row(s,@"dst",@"/A (1)",@"old-different-file") : nil;
        if(existed==6) {
            SeafFPDecoration *decoration=[SeafFPDecoration new]; decoration.itemIdentifier=former.itemIdentifier;
            decoration.tagData=[@"former occupant's tag" dataUsingEncoding:NSUTF8StringEncoding];
            [s setDecoration:decoration];
        }
        TestExtension *ext=configuredExtension(s);
        ext.liveListings=@{@"r:/":@[regressionFile(@"A",@"x")],@"dst:/":existed?@[regressionFile(@"A (1)",(existed==2?@"x":(existed==3?@"":@"old-different-file")))]:@[]};
        gMoveStatus=200;
        gServerRelocate=^(SeafDir *src,SeafDir *dst,NSString *oldName,NSString *newName) {
            CHECK([dst.repoId isEqual:@"dst"] && [oldName isEqual:@"A"] && [newName isEqual:@"A"]);
            if(existed==5) row(s,@"dst",@"/A (1)",@"new-local-write");
            ext.liveListings=@{@"r:/":@[],@"dst:/":@[regressionFile(@"A",@"unrelated"),regressionFile(@"A (1)",@"x")]};
        };
        __block BOOL success=NO; __block NSInteger status=0;
        [ext modifyItem:modifyTemplate(a,@"dst",@"A") baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { success=item!=nil&&error==nil; status=error.code; }];
        BOOL ambiguous=existed==2 || existed==3 || existed==5;
        CHECK(gMoveRequests==1 && success==!ambiguous && status==(ambiguous?NSXPCConnectionReplyInvalid:0));
        if(ambiguous) CHECK([[s moveRecoveryForUUID:a.uuid][@"confirmed"] isEqual:@YES]);
        else {
            CHECK([[s recordForUUID:a.uuid].path isEqual:@"/A (1)"] && ![s moveRecoveryForUUID:a.uuid].count);
            CHECK([[s decorationForItem:a.itemIdentifier].favoriteRank isEqual:@42] && ![s decorationForItem:a.itemIdentifier].tagData);
            if(former) CHECK([s recordForUUID:former.uuid].deleted);
        }
        if(existed==5) CHECK([[s recordForUUID:former.uuid].oid isEqual:@"new-local-write"] && ![s recordForUUID:former.uuid].deleted);
        [s close];
    }
    resetMoveTransport();
}

static void modifyAfterRecoveringRename(void) {
    for (int mode = 0; mode < 4; mode++) {
        NSString *domain = [NSString stringWithFormat:@"new-name-after-recovery-%d", mode];
        SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPRecord *source = row(s, @"r", @"/A", @"x"); favorite(s, source);
        // Files asked for B but the free name chosen before dispatch was B (1).
        NSString *priorName = mode == 2 ? @"B" : @"B (1)";
        if (mode == 2) {
            CHECK([s rememberMoveOfRecord:source toRepo:@"r" directory:@"/" parentUUID:nil
                expectedName:priorName requestStartSeq:s.currentSeq serverTime:200]);
        } else {
            long long start = [s beginMoveOfRecord:source toRepo:@"r" directory:@"/" parentUUID:nil expectedName:priorName requestedName:@"B" existingDestinationNames:@[]];
            CHECK(start >= 0 && [s noteMoveReceiptForUUID:source.uuid requestStartSeq:start serverTime:200]);
        }
        [s close];
        s = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        TestExtension *ext = enumerator(s, @"r").extension;
        ext.connection.rootFolder.items.firstObject.path = @"/";
        BOOL reparent = mode == 3;
        NSString *destinationRepo = reparent ? @"dst" : @"r";
        if (reparent) [s applyRepositorySnapshot:@[repoInfo(@"r", @"Source", YES), repoInfo(@"dst", @"Destination", YES)]
                                        complete:YES fromCache:NO requestStartSeq:s.currentSeq];
        ext.liveListings = @{@"r:/": @[serverFile(priorName, @"x")], @"dst:/": @[]};
        NSString *nextName = mode == 1 ? @"B" : @"C";
        gMoveRequests = 0;
        gServerRelocate = ^(SeafDir *src, SeafDir *dst, NSString *oldName, NSString *newName) {
            if ([dst.repoId isEqual:@"r"]) {
                CHECK([oldName isEqual:priorName] && [newName isEqual:@"C"]);
                ext.liveListings = @{@"r:/": @[serverFile(@"C", @"x")], @"dst:/": @[]};
            } else {
                CHECK(reparent && [oldName isEqual:@"C"] && [newName isEqual:@"C"]);
                ext.liveListings = @{@"r:/": @[], @"dst:/": @[serverFile(@"C", @"x")]};
            }
        };
        // A new filename must be applied before the accompanying content.
        // A retry of B must keep B (1), even if B itself has since become free.
        NSFileProviderItemFields fields = NSFileProviderItemFilename | NSFileProviderItemContents;
        if (reparent) fields |= NSFileProviderItemParentItemIdentifier;
        [ext modifyItem:modifyTemplate(source, destinationRepo, nextName) baseVersion:nil changedFields:fields
                contents:[NSURL fileURLWithPath:@"/test-only"] options:0 request:nil
            completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields remaining, BOOL fetch, NSError *error) {
                CHECK(!error && [item.filename isEqual:(mode == 1 ? priorName : @"C")]
                    && [item.itemIdentifier isEqual:source.itemIdentifier]
                    && [item.parentItemIdentifier isEqual:[SeafFPIdentifier identifierForRepo:destinationRepo]]);
            }];
        CHECK(gMoveRequests == (mode == 1 ? 0 : (reparent ? 2 : 1)) && ![s moveRecoveryForUUID:source.uuid].count);
        CHECK([ext.uploadedPath isEqual:[@"/" stringByAppendingString:(mode == 1 ? priorName : @"C")]]);
        CHECK([[s decorationForItem:source.itemIdentifier].favoriteRank isEqual:@42]);
        gServerRelocate = nil;
        [s close];
    }
}


/// 2.4: the source listing shows the entry with other contents than the
/// store knows. The identity is the name; the fresh contents are adopted and
/// the move goes on (and the journal records what actually moved).
static void moveAdoptsFreshContents(void) {
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"move-adopts-fresh-oid" error:nil];
    SeafFPRecord *source = row(s, @"r", @"/A", @"stale");
    favorite(s, source);
    [s applyRepositorySnapshot:@[repoInfo(@"r", @"Source", YES), repoInfo(@"dst", @"Destination", YES)]
                      complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    TestExtension *ext = enumerator(s, @"r").extension;
    ext.connection.rootFolder.items.firstObject.path = @"/";
    SeafBase *fresh = serverFile(@"A", @"fresh");
    ext.liveListings = @{@"r:/": @[fresh], @"dst:/": @[]};
    gMoveRequests = 0; gMoveStatus = 200;
    gServerRelocate = ^(SeafDir *src, SeafDir *dst, NSString *oldName, NSString *newName) {
        CHECK([[s moveRecoveryForUUID:source.uuid][@"oid"] isEqual:@"fresh"]);   // the journal knows the moved contents
        ext.liveListings = @{@"r:/": @[], @"dst:/": @[fresh]};
    };
    [ext modifyItem:modifyTemplate(source, @"dst", @"A") baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
        completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields fields, BOOL fetch, NSError *error) {
            CHECK(!error && [item.itemIdentifier isEqual:source.itemIdentifier] && [item.parentItemIdentifier isEqual:@"r:dst"]);
        }];
    SeafFPRecord *moved = [s recordForUUID:source.uuid];
    CHECK(gMoveRequests == 1 && [moved.repoId isEqual:@"dst"] && [moved.path isEqual:@"/A"] && [moved.oid isEqual:@"fresh"] && !moved.deleted);
    CHECK([[s decorationForItem:source.itemIdentifier].favoriteRank isEqual:@42] && [s moveRecoveryForUUID:source.uuid].count == 0);
    // A different kind at the name (a folder now) is not the item: no request.
    SeafFPRecord *file = row(s, @"r", @"/B", @"b");
    SeafDir *folder = [SeafDir new]; folder.name = @"B"; folder.oid = @"dir";
    ext.liveListings = @{@"r:/": @[folder], @"dst:/": @[]};
    [ext modifyItem:modifyTemplate(file, @"dst", @"B") baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
        completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields fields, BOOL fetch, NSError *error) {
            CHECK(!item && error.code == NSFileProviderErrorCannotSynchronize);
        }];
    CHECK(gMoveRequests == 1 && [[s activityRecheckDirectoryPathsOfRepo:@"r"] containsObject:@"/"]);
    gMoveStatus = 0; gServerRelocate = nil;
    [s close];
}

/// 2.6 / #13: unreadable full pages preserve the checkpoint for retry, and the entries of a locked library the store never
/// indexed are not written.
static void activityPageEdgeCases(void) {
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"activity-unreadable-times" error:nil];
    ProbeIndexer *indexer = [ProbeIndexer new]; indexer.activityStore = s;
    [indexer.lockedRepos addObject:@"r"];   // checks stay pending: this test only looks at what was collected
    SeafConnection *connection = [SeafConnection new];
    long long t0 = 1800000000;
    [s recordActivityEntries:@[] progress:@{@"boundary": @(t0)}];
    gLog = [NSMutableArray array];
    for (int i = 0; i < 100; i++) {
        NSMutableDictionary *event = [activityEvent(@"r", @"create", @"file", [NSString stringWithFormat:@"/u%03d/f.txt", i], t0 + 100 - i) mutableCopy];
        event[@"time"] = @"not a date";
        [gLog addObject:event];
    }
    gActivityRequests = 0;
    [indexer syncActivitiesForConnection:connection force:YES];
    spinUntilIdle(indexer);
    CHECK(gActivityRequests == 1 && [s activityProgress][@"scanTop"] == nil && [[s activityProgress][@"boundary"] longLongValue] == t0);
    CHECK([s activityRecheckDirectoryPathsOfRepo:@"r"].count == 0);
    [s close];

    s = [[SeafFPStore alloc] initWithDomainIdentifier:@"activity-locked-library" error:nil];
    indexer = [ProbeIndexer new]; indexer.activityStore = s;
    [indexer.lockedRepos addObject:@"open"]; [indexer.lockedRepos addObject:@"sealed"]; [indexer.lockedRepos addObject:@"relocked"];
    SeafRepos *repos = [SeafRepos new];
    SeafRepo *open = [SeafRepo new]; open.repoId = @"open";
    SeafRepo *sealed = [SeafRepo new]; sealed.repoId = @"sealed"; sealed.passwordRequired = YES;
    SeafRepo *relocked = [SeafRepo new]; relocked.repoId = @"relocked"; relocked.passwordRequired = YES;
    repos.items = @[open, sealed, relocked];
    connection = [SeafConnection new]; connection.rootFolder = repos;
    [s upsertRecordForRepo:@"relocked" path:@"/known" isDir:YES parentUUID:nil oid:@"k" mtime:1 size:-1];   // indexed while it was unlocked
    [s recordActivityEntries:@[] progress:@{@"boundary": @(t0)}];
    gLog = [NSMutableArray arrayWithArray:@[activityEvent(@"open", @"create", @"file", @"/a/f.txt", t0 + 30),
                                           activityEvent(@"sealed", @"create", @"file", @"/secret/f.txt", t0 + 20),
                                           activityEvent(@"relocked", @"create", @"file", @"/known/f.txt", t0 + 10)]];
    gActivityRequests = 0;
    [indexer syncActivitiesForConnection:connection force:YES];
    spinUntilIdle(indexer);
    CHECK([[s activityRecheckDirectoryPathsOfRepo:@"open"] isEqual:@[@"/a"]]);
    CHECK([s activityRecheckDirectoryPathsOfRepo:@"sealed"].count == 0);
    CHECK([[s activityRecheckDirectoryPathsOfRepo:@"relocked"] isEqual:@[@"/known"]]);
    [s close];
}

'''
final_tests = r'''
@interface SeafFPStore (FinalFailureProbe)
- (BOOL)execLocked:(NSString *)sql;
@end
@interface FinalRootStore : SeafFPStore
@property BOOL failBegin;
@end
@implementation FinalRootStore
- (BOOL)execLocked:(NSString *)sql {
    return self.failBegin && [sql isEqual:@"BEGIN IMMEDIATE"] ? NO : [super execLocked:sql];
}
@end
@interface FinalAccessExtension : TestExtension
@property BOOL removeRepo;
@property BOOL cachedReply;
@end
@implementation FinalAccessExtension
- (void)loadDirectory:(SeafDir *)dir completion:(void (^)(BOOL, BOOL, NSError *))completion {
    SeafFile *file=(SeafFile *)regressionFile(@"secret.txt",@"secret");
    file.repoId=@"r"; file.path=@"/sensitive/secret.txt"; dir.items=@[file];
    NSMutableDictionary *info=[repoInfo(@"r",@"R",YES) mutableCopy]; info[@"locked"]=@YES;
    CHECK([self.store applyRepositorySnapshot:self.removeRepo?@[]:@[info] complete:YES fromCache:NO requestStartSeq:[self.store beginRepositoryRequest]]);
    self.connection.rootFolder.items.firstObject.passwordRequired=YES;
    completion(YES,self.cachedReply,nil);
}
@end
@interface SeafFPEnumerator (FinalRootTest)
- (void)deliverRoot:(SeafRepos *)repos fromCache:(BOOL)cached requestStartSeq:(long long)seq container:(NSString *)container completion:(SeafFPContainerCompletion)completion;
@end
static void finalRepositoryRegressions(void) {
    FinalRootStore *s=[[FinalRootStore alloc] initWithDomainIdentifier:@"final-root-failure" error:nil];
    row(s,@"r",@"/existing",@"x");
    [s setAnchor:@"old-root" snapshot:@[@"r:r"] forContainer:NSFileProviderRootContainerItemIdentifier];
    SeafFPEnumerator *e=enumerator(s,@"r"); long long request=[s beginRepositoryRequest]; s.failBegin=YES;
    __block BOOL answered=NO;
    [e deliverRoot:e.extension.connection.rootFolder fromCache:NO requestStartSeq:request container:NSFileProviderRootContainerItemIdentifier completion:^(SeafFPContainerLoad *load,NSError *error) {
        answered=YES; CHECK(!load && error.code==NSFileProviderErrorCannotSynchronize);
    }];
    CHECK(answered && [[s anchorForContainer:NSFileProviderRootContainerItemIdentifier] isEqual:@"old-root"]);
    CHECK(([[s snapshotForContainer:NSFileProviderRootContainerItemIdentifier] isEqual:@[@"r:r"]]));
    s.failBegin=NO; [s close];
    for(int removed=0;removed<2;removed++) for(int cached=0;cached<2;cached++) {
        SeafFPStore *store=[[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"final-access-%d-%d",removed,cached] error:nil];
        [store applyRepositorySnapshot:@[repoInfo(@"r",@"R",YES)] complete:YES fromCache:NO requestStartSeq:[store beginRepositoryRequest]];
        SeafFPRecord *parent=[store upsertRecordForRepo:@"r" path:@"/sensitive" isDir:YES parentUUID:nil oid:@"dir" mtime:1 size:-1];
        SeafFPRecord *file=[store upsertRecordForRepo:@"r" path:@"/sensitive/secret.txt" isDir:NO parentUUID:parent.uuid oid:@"secret" mtime:1 size:5];
        [store setAnchor:@"previous" snapshot:@[file.itemIdentifier] forContainer:parent.itemIdentifier];
        SeafFPEnumerator *enumeration=enumerator(store,@"r");
        FinalAccessExtension *ext=[FinalAccessExtension new]; ext.store=store; ext.connection=enumeration.extension.connection;
        ext.removeRepo=removed; ext.cachedReply=cached; enumeration.extension=ext; answered=NO;
        [enumeration loadDirectory:parent.itemIdentifier completion:^(SeafFPContainerLoad *load,NSError *error) {
            answered=YES; CHECK(!load && error.code==(removed?NSFileProviderErrorNoSuchItem:NSFileProviderErrorNotAuthenticated));
        }];
        CHECK(answered && [[store anchorForContainer:parent.itemIdentifier] isEqual:@"previous"]);
        [store close];
    }
    for(int newerFirst=0;newerFirst<2;newerFirst++) {
        NSString *domain=[NSString stringWithFormat:@"final-request-order-%d",newerFirst];
        SeafFPStore *store=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPStore *other=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        [store applyRepositorySnapshot:@[repoInfo(@"r",@"Latest",NO)] complete:YES fromCache:NO requestStartSeq:[store beginRepositoryRequest]];
        long long older=[store beginRepositoryRequest], newer=[other beginRepositoryRequest]; CHECK(older>0 && newer>older);
        if(!newerFirst) CHECK([store applyRepositorySnapshot:@[repoInfo(@"r",@"Stale",YES)] complete:YES fromCache:NO requestStartSeq:older]);
        CHECK([other applyRepositorySnapshotResult:@[repoInfo(@"r",@"Latest",NO)] complete:YES fromCache:NO requestStartSeq:newer]!=SeafFPWriteFailed);
        CHECK(![store applyRepositorySnapshot:@[repoInfo(@"r",@"Stale",YES)] complete:YES fromCache:NO requestStartSeq:older]);
        CHECK([store.repositoryStates[@"r"][@"name"] isEqual:@"Latest"] && ![store.repositoryStates[@"r"][@"editable"] boolValue]);
        [store setMetaValue:nil forKey:@"seq"];
        CHECK([other beginRepositoryRequest]>newer);
        [other close]; [store close];
    }
}
static void finalParentJournalRegressions(void) {
    for(int renamed=0;renamed<2;renamed++) {
        resetMoveTransport();
        NSString *domain=[NSString stringWithFormat:@"final-parent-journal-%d",renamed];
        SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPStore *other=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPRecord *parent=[s upsertRecordForRepo:@"r" path:@"/P" isDir:YES parentUUID:nil oid:@"parent" mtime:10 size:-1];
        SeafFPRecord *file=[s upsertRecordForRepo:@"r" path:@"/P/A" isDir:NO parentUUID:parent.uuid oid:@"content" mtime:10 size:5]; favorite(s,file);
        TestExtension *ext=configuredExtension(s); ext.liveListings=@{@"r:/P":@[regressionFile(@"A",@"content")]}; gMoveStatus=200;
        gServerRelocate=^(SeafDir *src,SeafDir *dst,NSString *oldName,NSString *newName) {
            ext.failDirectoryLoad=YES; ext.liveListings=@{@"r:/P":@[regressionFile(@"B",@"content")]};
        };
        SeafFPItem *wanted=[SeafFPItem itemForRecord:file repoEditable:YES]; wanted.filename=@"B";
        __block BOOL success=NO;
        void (^answer)(NSFileProviderItem,NSFileProviderItemFields,BOOL,NSError *)=^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) {success=item!=nil&&!error;};
        [ext modifyItem:wanted baseVersion:nil changedFields:NSFileProviderItemFilename contents:nil options:0 request:nil completionHandler:answer];
        CHECK(!success && [[s moveRecoveryForUUID:file.uuid][@"confirmed"] boolValue]);
        ext.failDirectoryLoad=NO;
        if(renamed) {
            [other upsertRecordForRepo:@"r" path:@"/P" isDir:YES parentUUID:nil oid:@"parent-after-rename" mtime:20 size:-1];
            CHECK(([other renameRecordOfRepo:@"r" directory:@"/" fromName:@"P" toName:@"Q" listing:@[@{SeafFPEntryName:@"Q",SeafFPEntryIsDir:@YES,SeafFPEntryOid:@"parent-after-rename"}] requestStartSeq:other.currentSeq]));
            NSDictionary *journal=[s moveRecoveryForUUID:file.uuid];
            CHECK([journal[@"dir"] isEqual:@"/Q"] && [journal[@"sourcePath"] isEqual:@"/Q/A"]);
            CHECK([s prepareFileCreationInRepo:@"r" path:@"/Q/B" requestStartSeq:s.currentSeq]<0);
            CHECK([s prepareFileCreationInRepo:@"r" path:@"/P/B" requestStartSeq:s.currentSeq]>=0);
            ext.liveListings=@{@"r:/Q":@[regressionFile(@"B",@"content")]};
        }
        [ext modifyItem:wanted baseVersion:nil changedFields:NSFileProviderItemFilename contents:nil options:0 request:nil completionHandler:answer];
        CHECK(success && gMoveRequests==1 && ![s moveRecoveryForUUID:file.uuid].count);
        CHECK([[s recordForUUID:file.uuid].path isEqual:renamed?@"/Q/B":@"/P/B"]);
        CHECK([[s decorationForItem:file.itemIdentifier].favoriteRank isEqual:@42]);
        [other close]; [s close];
    }
    resetMoveTransport();
}

static void detachedParentJournalRegression(void) {
    SeafFPStore *store = [[SeafFPStore alloc] initWithDomainIdentifier:@"detached-parent-journal" error:nil];
    SeafFPRecord *parent = [store upsertRecordForRepo:@"r" path:@"/P" isDir:YES parentUUID:nil oid:@"parent" mtime:10 size:-1];
    SeafFPRecord *child = [store upsertRecordForRepo:@"r" path:@"/P/A" isDir:NO parentUUID:parent.uuid oid:@"content" mtime:10 size:5];
    favorite(store, child);
    long long childStart = [store beginMoveOfRecord:child toRepo:@"r" directory:@"/P" parentUUID:parent.uuid
                                       expectedName:@"B" requestedName:@"B" existingDestinationNames:@[]];
    CHECK(childStart > 0 && [store noteMoveReceiptForUUID:child.uuid requestStartSeq:childStart serverTime:20]);

    parent = [store refreshContentOfRecord:parent oid:@"parent-after-child-rename" mtime:20 size:-1];
    long long parentStart = [store beginMoveOfRecord:parent toRepo:@"r" directory:@"/" parentUUID:nil
                                        expectedName:@"Q" requestedName:@"Q" existingDestinationNames:@[]];
    CHECK(parentStart > 0 && [store noteMoveReceiptForUUID:parent.uuid requestStartSeq:parentStart serverTime:30]);
    // A listing sees the old path reused before the parent receipt is settled.
    NSArray *listing = @[@{SeafFPEntryName:@"P", SeafFPEntryIsDir:@YES, SeafFPEntryOid:@"replacement"},
                         @{SeafFPEntryName:@"Q", SeafFPEntryIsDir:@YES, SeafFPEntryOid:parent.oid}];
    CHECK([store applyDirectoryListingOfRepo:@"r" directoryPath:@"/" entries:listing
                             requestStartSeq:store.currentSeq] == SeafFPWriteChanged);
    CHECK([[store recordForUUID:parent.uuid].path hasPrefix:@"/P#moved-"]);

    SeafFPRecord *replacement = [store recordForRepo:@"r" path:@"/P" includeDeleted:NO];
    SeafFPRecord *replacementChild = [store upsertRecordForRepo:@"r" path:@"/P/A" isDir:NO parentUUID:replacement.uuid
                                                           oid:@"unrelated" mtime:30 size:4];
    long long replacementStart = [store beginMoveOfRecord:replacementChild toRepo:@"r" directory:@"/P" parentUUID:replacement.uuid
                                             expectedName:@"C" requestedName:@"C" existingDestinationNames:@[]];
    CHECK(replacementStart > 0);
    NSDictionary *replacementJournal = [store moveRecoveryForUUID:replacementChild.uuid];

    TestExtension *ext = configuredExtension(store);
    SeafDir *serverParent = [SeafDir new];
    serverParent.name = @"Q";
    serverParent.oid = parent.oid;
    ext.liveListings = @{@"r:/": @[serverParent], @"r:/Q": @[regressionFile(@"B", @"content")]};
    [ext recoverMoveOfRecord:[store recordForUUID:parent.uuid] details:[store moveRecoveryForUUID:parent.uuid]
                  completion:^(SeafFPRecord *moved, SeafFPMoveSettlement settlement, NSError *error) { BOOL applied = moved && !error && settlement == SeafFPMoveSettlementRecovered;
        CHECK(applied && !error && [moved.uuid isEqual:parent.uuid] && [moved.path isEqual:@"/Q"]);
    }];

    NSDictionary *childJournal = [store moveRecoveryForUUID:child.uuid];
    CHECK([childJournal[@"sourcePath"] isEqual:@"/Q/A"] && [childJournal[@"dir"] isEqual:@"/Q"]);
    CHECK([[store moveRecoveryForUUID:replacementChild.uuid] isEqual:replacementJournal]);
    CHECK([store prepareFileCreationInRepo:@"r" path:@"/P/B" requestStartSeq:store.currentSeq] >= 0);
    CHECK([store prepareFileCreationInRepo:@"r" path:@"/Q/B" requestStartSeq:store.currentSeq] < 0);
    [ext recoverMoveOfRecord:[store recordForUUID:child.uuid] details:childJournal
                  completion:^(SeafFPRecord *moved, SeafFPMoveSettlement settlement, NSError *error) { BOOL applied = moved && !error && settlement == SeafFPMoveSettlementRecovered;
        CHECK(applied && !error && [moved.uuid isEqual:child.uuid] && [moved.path isEqual:@"/Q/B"]);
    }];
    CHECK(![store moveRecoveryForUUID:child.uuid].count);
    CHECK([[store decorationForItem:child.itemIdentifier].favoriteRank isEqual:@42]);
    [store close];
}

/// An hour after the request the move's outcome is no longer awaited: the
/// source is re-listed, the journal dropped, and the operation decided from
/// the item's current row.
static void unsettledMoveAbandonedAfterGrace(void) {
    const long long hour = 3600;
    NSArray *ambiguousFailures = @[@502, @503, @(NSURLErrorTimedOut), @(NSURLErrorNetworkConnectionLost), @404];
    // 1: never executed, source unchanged: pending within the hour, then the
    //    retry is sent again and keeps the identity.
    for (NSNumber *code in ambiguousFailures) {
        resetMoveTransport();
        SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:[@"settle-unexecuted-" stringByAppendingString:code.stringValue] error:nil];
        SeafFPRecord *a=row(s,@"r",@"/A",@"x"); favorite(s,a);
        [s applyRepositorySnapshot:@[repoInfo(@"r",@"R",YES),repoInfo(@"dst",@"DST",YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
        TestExtension *ext=configuredExtension(s);
        ext.liveListings=@{@"r:/":@[regressionFile(@"A",@"x")],@"dst:/":@[]};
        gMoveStatus=MAX(0,code.integerValue);
        gMoveError=[NSError errorWithDomain:gMoveStatus?@"TestHTTP":NSURLErrorDomain code:code.integerValue userInfo:nil];
        SeafFPItem *requested=modifyTemplate(a,@"dst",@"A");
        [ext modifyItem:requested baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { CHECK(!item && isMovePending(error)); }];
        CHECK(gMoveRequests==1 && [[s moveRecoveryForUUID:a.uuid][@"confirmed"] isEqual:@NO]);
        gMoveStatus=0; gMoveError=nil;
        setJournalAge(s,a.uuid,hour-60);
        __block NSError *answer=nil;
        [ext modifyItem:requested baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { CHECK(!item); answer=error; }];
        CHECK(isMovePending(answer)
              && answer.localizedRecoverySuggestion.length>0 && gMoveRequests==1 && [s moveRecoveryForUUID:a.uuid].count>0);
        setJournalAge(s,a.uuid,hour+60);
        ext = configuredExtension(s); // no in-memory error or timer from the previous instance
        ext.liveListings = @{@"r:/": @[regressionFile(@"A", @"x")], @"dst:/": @[]};
        gMoveStatus=200;
        gServerRelocate=^(SeafDir *src,SeafDir *dst,NSString *oldName,NSString *newName) {
            ext.liveListings=@{@"r:/":@[],@"dst:/":@[regressionFile(@"A",@"x")]};
        };
        __block BOOL moved=NO; answer=nil;
        [ext modifyItem:requested baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) {
                moved=[item.itemIdentifier isEqual:a.itemIdentifier] && [item.parentItemIdentifier isEqual:@"r:dst"]; answer=error;
            }];
        CHECK(moved && !answer && gMoveRequests==2 && ![s moveRecoveryForUUID:a.uuid].count);
        CHECK([[s recordForUUID:a.uuid].repoId isEqual:@"dst"] && [[s decorationForItem:a.itemIdentifier].favoriteRank isEqual:@42]);
        [s close];
    }
    // 2: after the hour every other way out works too, and the destination
    //    name is free again even when the item is never touched.
    for (int mode=0;mode<5;mode++) {
        resetMoveTransport();
        SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"settle-exit-%d",mode] error:nil];
        SeafFPRecord *a=row(s,@"r",@"/A",@"x"); favorite(s,a);
        [s applyRepositorySnapshot:@[repoInfo(@"r",@"R",YES),repoInfo(@"dst",@"DST",YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
        TestExtension *ext=configuredExtension(s);
        ext.liveListings=@{@"r:/":@[regressionFile(@"A",@"x")],@"dst:/":@[]};
        gMoveStatus=502; gMoveError=[NSError errorWithDomain:@"TestHTTP" code:502 userInfo:nil];
        [ext modifyItem:modifyTemplate(a,@"dst",@"A") baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { CHECK(error!=nil); }];
        resetMoveTransport();
        SeafFPRecord *competitor=row(s,@"dst",@"/competitor",@"y");
        CHECK([s beginMoveOfRecord:competitor toRepo:@"dst" directory:@"/" parentUUID:nil expectedName:@"A" requestedName:nil existingDestinationNames:@[]]<0);
        setJournalAge(s,a.uuid,hour+60);
        if (mode==0) {
            // The reservation of an unanswered move lapses with the grace.
            CHECK([s beginMoveOfRecord:competitor toRepo:@"dst" directory:@"/" parentUUID:nil expectedName:@"A" requestedName:nil existingDestinationNames:@[]]>0);
        } else if (mode==1) {
            // The delete that expires the move is rejected (the system
            // restores the item); a delete after that runs normally.
            gDeletedPaths=[NSMutableArray array];
            __block NSError *first=nil;
            [ext deleteItemWithIdentifier:a.itemIdentifier baseVersion:nil options:0 request:nil completionHandler:^(NSError *error) { first=error; }];
            CHECK(first.code==NSFileProviderErrorDeletionRejected && gDeletedPaths.count==0 && ![s recordForUUID:a.uuid].deleted
                  && ![s moveRecoveryForUUID:a.uuid].count && [[s decorationForItem:a.itemIdentifier].favoriteRank isEqual:@42]);
            __block BOOL deleted=NO;
            [ext deleteItemWithIdentifier:a.itemIdentifier baseVersion:nil options:0 request:nil completionHandler:^(NSError *error) { deleted=error==nil; }];
            CHECK(deleted && [gDeletedPaths isEqual:@[@"r:/A"]] && [s recordForUUID:a.uuid].deleted);
        } else if (mode==2) {
            // A rename instead: the old move is dropped, the rename is sent.
            gMoveStatus=200;
            gServerRelocate=^(SeafDir *src,SeafDir *dst,NSString *oldName,NSString *newName) {
                CHECK([oldName isEqual:@"A"] && [newName isEqual:@"C"] && [dst.repoId isEqual:@"r"]);
                ext.liveListings=@{@"r:/":@[regressionFile(@"C",@"x")],@"dst:/":@[]};
            };
            __block BOOL renamed=NO;
            [ext modifyItem:modifyTemplate(a,@"r",@"C") baseVersion:nil changedFields:NSFileProviderItemFilename contents:nil options:0 request:nil
                completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { renamed=!error && [item.filename isEqual:@"C"]; }];
            CHECK(renamed && gMoveRequests==1 && ![s moveRecoveryForUUID:a.uuid].count
                  && [[s recordForUUID:a.uuid].path isEqual:@"/C"] && [[s decorationForItem:a.itemIdentifier].favoriteRank isEqual:@42]);
        } else if (mode==3) {
            // Gone from both places: the fresh source listing says so, the
            // modification answers NoSuchItem and a later delete succeeds.
            ext.liveListings=@{@"r:/":@[],@"dst:/":@[]};
            __block NSError *answer=nil;
            [ext modifyItem:modifyTemplate(a,@"dst",@"A") baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
                completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { CHECK(!item); answer=error; }];
            CHECK(answer.code==NSFileProviderErrorNoSuchItem && [answer.domain isEqual:NSFileProviderErrorDomain] && gMoveRequests==0
                  && ![s moveRecoveryForUUID:a.uuid].count && [s recordForUUID:a.uuid].deleted);
            __block BOOL deleted=NO;
            gDeletedPaths=[NSMutableArray array];
            [ext deleteItemWithIdentifier:a.itemIdentifier baseVersion:nil options:0 request:nil completionHandler:^(NSError *error) { deleted=error==nil; }];
            CHECK(deleted && gDeletedPaths.count==0);
        } else {
            // The destination folder is gone (404): an empty listing, not a stall.
            ext.directory404Bodies=@{@"dst:/": @"{\"error_msg\":\"Folder / not found.\"}"};
            setJournalAge(s,a.uuid,600);
            __block NSError *answer=nil;
            [ext modifyItem:modifyTemplate(a,@"r",@"C") baseVersion:nil changedFields:NSFileProviderItemFilename contents:nil options:0 request:nil
                completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { answer=error; }];
            CHECK(isMovePending(answer) && gMoveRequests==0);
            setJournalAge(s,a.uuid,hour+60);
            gMoveStatus=200;
            gServerRelocate=^(SeafDir *src,SeafDir *dst,NSString *oldName,NSString *newName) {
                ext.liveListings=@{@"r:/":@[regressionFile(@"C",@"x")]};
            };
            answer=nil;
            [ext modifyItem:modifyTemplate(a,@"r",@"C") baseVersion:nil changedFields:NSFileProviderItemFilename contents:nil options:0 request:nil
                completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { answer=error; }];
            CHECK(!answer && gMoveRequests==1 && ![s moveRecoveryForUUID:a.uuid].count && [[s recordForUUID:a.uuid].path isEqual:@"/C"]);
        }
        [s close];
    }
    // 3: matching contents at both ends: ambiguous within the hour; after it
    //    the item at the source is unchanged, so the rename goes ahead there.
    for (int late=0;late<2;late++) {
        resetMoveTransport();
        SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"settle-both-%d",late] error:nil];
        SeafFPRecord *a=row(s,@"r",@"/A",@"x"); favorite(s,a);
        [s applyRepositorySnapshot:@[repoInfo(@"r",@"R",YES),repoInfo(@"dst",@"DST",YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
        TestExtension *ext=configuredExtension(s);
        ext.liveListings=@{@"r:/":@[regressionFile(@"A",@"x")],@"dst:/":@[]};
        gMoveError=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
        [ext modifyItem:modifyTemplate(a,@"dst",@"A") baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { CHECK(error!=nil); }];
        resetMoveTransport();
        ext.liveListings=@{@"r:/":@[regressionFile(@"A",@"x")],@"dst:/":@[regressionFile(@"A",@"x")]};
        setJournalAge(s,a.uuid,late?hour+60:600);
        gMoveStatus=200;
        gServerRelocate=^(SeafDir *src,SeafDir *dst,NSString *oldName,NSString *newName) {
            ext.liveListings=@{@"r:/":@[regressionFile(@"C",@"x")],@"dst:/":@[regressionFile(@"A",@"x")]};
        };
        __block NSError *answer=nil;
        [ext modifyItem:modifyTemplate(a,@"r",@"C") baseVersion:nil changedFields:NSFileProviderItemFilename contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { answer=error; }];
        if (late) CHECK(!answer && gMoveRequests==1 && ![s moveRecoveryForUUID:a.uuid].count && [[s recordForUUID:a.uuid].path isEqual:@"/C"]);
        else CHECK(isMovePending(answer) && gMoveRequests==0 && [s moveRecoveryForUUID:a.uuid].count);
        [s close];
    }
}

static void unsettledMovePreservesUnverifiedFiles(void) {
    for (NSUInteger scenario = 0; scenario < 4; scenario++) {
        resetMoveTransport();
        NSString *domain = [NSString stringWithFormat:@"unsafe-move-delete-%lu", (unsigned long)scenario];
        SeafFPStore *store = [[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPRecord *file = row(store, @"r", @"/A", @"original");
        favorite(store, file);
        [store applyRepositorySnapshot:@[repoInfo(@"r", @"Source", YES), repoInfo(@"dst", @"Destination", YES)]
                             complete:YES fromCache:NO requestStartSeq:store.currentSeq];
        TestExtension *ext = configuredExtension(store);
        SeafBase *original = regressionFile(@"A", @"original");
        ext.liveListings = @{@"r:/": @[original], @"dst:/": @[]};
        gMoveError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
        [ext modifyItem:modifyTemplate(file, @"dst", @"A") baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier
               contents:nil options:0 request:nil completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields fields, BOOL fetch, NSError *error) {
            CHECK(!item && isMovePending(error));
        }];
        CHECK(gMoveRequests == 1 && [store moveRecoveryForUUID:file.uuid].count > 0);
        resetMoveTransport();

        BOOL proxy404 = scenario == 3;
        if (scenario == 2) {
            long long start = [[store moveRecoveryForUUID:file.uuid][@"start"] longLongValue];
            CHECK([store noteMoveReceiptForUUID:file.uuid requestStartSeq:start serverTime:1]);
        }
        setJournalAge(store, file.uuid, proxy404 ? 60 : 3660);
        // An edited destination, an empty destination, a late receipt, and a proxy 404.
        ext.liveListings = @{@"r:/": proxy404 || scenario == 2 ? @[original] : @[regressionFile(@"A", @"replacement")],
                             @"dst:/": proxy404 ? @[original] : scenario == 0 ? @[regressionFile(@"A", @"edited")] : @[]};
        if (proxy404) ext.directory404Bodies = @{@"r:/": @"<html>Not found</html>"};
        gDeletedPaths = [NSMutableArray array];
        NSDictionary *journal = [store moveRecoveryForUUID:file.uuid];
        __block BOOL replied = NO;
        [ext deleteItemWithIdentifier:file.itemIdentifier baseVersion:nil options:0 request:nil completionHandler:^(NSError *error) {
            replied = YES;
            CHECK(proxy404 ? isMovePending(error) : error.code == NSFileProviderErrorDeletionRejected);
        }];
        // Nothing is deleted on the server. A proxy 404 proves nothing and
        // keeps the journal; otherwise the journal is gone and the row shows
        // what the source holds now.
        CHECK(replied && gDeletedPaths.count == 0);
        if (proxy404) CHECK([[store moveRecoveryForUUID:file.uuid] isEqual:journal]);
        else CHECK([store moveRecoveryForUUID:file.uuid].count == 0
                   && [[store recordForUUID:file.uuid].oid isEqual:scenario == 2 ? @"original" : @"replacement"]);
        CHECK(![store recordForUUID:file.uuid].deleted && [[store decorationForItem:file.itemIdentifier].favoriteRank isEqual:@42]);
        [store close];
    }
}

/// After the grace a pending move is replayed only on the item it was asked
/// for; otherwise the local rename or move is reverted and other changes apply.
static void expiredMoveDecidesByVersion(void) {
    for (int mode = 0; mode < 4; mode++) {
        resetMoveTransport();
        SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"expired-version-%d", mode] error:nil];
        SeafFPRecord *a = row(s, @"r", @"/A", @"x"); favorite(s, a);
        [s applyRepositorySnapshot:@[repoInfo(@"r", @"R", YES), repoInfo(@"dst", @"DST", YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
        TestExtension *ext = configuredExtension(s);
        ext.liveListings = @{@"r:/": @[regressionFile(@"A", @"x")], @"dst:/": @[]};
        gMoveError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
        [ext modifyItem:modifyTemplate(a, @"dst", @"A") baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
            completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields fields, BOOL fetch, NSError *error) { CHECK(isMovePending(error)); }];
        resetMoveTransport();
        setJournalAge(s, a.uuid, 3660);
        // Someone edited the file at the source; the move never ran.
        ext = configuredExtension(s);
        ext.liveListings = @{@"r:/": @[regressionFile(@"A", @"edited")], @"dst:/": @[]};
        gMoveStatus = 200;
        gServerRelocate = ^(SeafDir *src, SeafDir *dst, NSString *oldName, NSString *newName) {
            ext.liveListings = @{@"r:/": @[], @"dst:/": @[regressionFile(@"A", @"edited")]};
        };
        NSFileProviderItemVersion *base = nil;
        if (mode == 2) {
            SeafFPRecord *seen = [SeafFPRecord new]; seen.uuid = a.uuid; seen.repoId = @"r"; seen.path = @"/A"; seen.name = @"A"; seen.oid = @"edited";
            base = [SeafFPItem itemForRecord:seen repoEditable:YES].itemVersion;   // the system already knew the edit
        } else if (mode == 3) {
            SeafFPRecord *seen = [SeafFPRecord new]; seen.uuid = a.uuid; seen.repoId = @"r"; seen.path = @"/A"; seen.name = @"A"; seen.oid = @"older";
            base = [SeafFPItem itemForRecord:seen repoEditable:YES].itemVersion;
        }
        NSFileProviderItemFields fields = NSFileProviderItemParentItemIdentifier | (mode == 1 ? NSFileProviderItemContents : 0);
        NSURL *contents = mode == 1 ? [NSURL fileURLWithPath:@"/tmp/local-edit"] : nil;
        __block NSFileProviderItem answer = nil; __block NSError *failure = nil;
        [ext modifyItem:modifyTemplate(a, @"dst", @"A") baseVersion:base changedFields:fields contents:contents options:0 request:nil
            completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields f, BOOL fetch, NSError *error) { answer = item; failure = error; }];
        CHECK(!failure && [answer.itemIdentifier isEqual:a.itemIdentifier] && ![s moveRecoveryForUUID:a.uuid].count);
        CHECK([[s decorationForItem:a.itemIdentifier].favoriteRank isEqual:@42]);
        if (mode == 2) {
            // Based on the edited version: the move goes ahead.
            CHECK(gMoveRequests == 1 && [answer.parentItemIdentifier isEqual:@"r:dst"] && [[s recordForUUID:a.uuid].repoId isEqual:@"dst"]);
        } else {
            // Not the item the move was asked for: reverted, nothing sent;
            // a content edit still uploads where the item is.
            CHECK(gMoveRequests == 0 && [answer.parentItemIdentifier isEqual:@"r:r"]
                  && [[s recordForUUID:a.uuid].path isEqual:@"/A"] && [[s recordForUUID:a.uuid].repoId isEqual:@"r"]);
            CHECK(mode == 1 ? [ext.uploadedPath isEqual:@"/A"] : ext.uploadedPath == nil);
        }
        [s close];
    }
    // A source library that is gone: the item is gone, the journal dropped.
    resetMoveTransport();
    SeafFPStore *s = [[SeafFPStore alloc] initWithDomainIdentifier:@"expired-source-library-gone" error:nil];
    SeafFPRecord *a = row(s, @"r", @"/A", @"x");
    [s applyRepositorySnapshot:@[repoInfo(@"r", @"R", YES), repoInfo(@"dst", @"DST", YES)] complete:YES fromCache:NO requestStartSeq:s.currentSeq];
    TestExtension *ext = configuredExtension(s);
    ext.liveListings = @{@"r:/": @[regressionFile(@"A", @"x")], @"dst:/": @[]};
    gMoveError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
    [ext modifyItem:modifyTemplate(a, @"dst", @"A") baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
        completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields fields, BOOL fetch, NSError *error) {}];
    resetMoveTransport();
    setJournalAge(s, a.uuid, 3660);
    ext.directory404Bodies = @{@"r:/": @"{\"error_msg\":\"Library r not found.\"}"};
    __block NSError *gone = nil;
    [ext modifyItem:modifyTemplate(a, @"dst", @"A") baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil
        completionHandler:^(NSFileProviderItem item, NSFileProviderItemFields fields, BOOL fetch, NSError *error) { gone = error; }];
    CHECK(gone.code == NSFileProviderErrorNoSuchItem && gMoveRequests == 0 && ![s moveRecoveryForUUID:a.uuid].count);
    [s close];
}

static void finalMoveResolutionRegressions(void) {
    resetMoveTransport();
    SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:@"final-edited-target" error:nil];
    SeafFPRecord *file=row(s,@"r",@"/A",@"original"); favorite(s,file);
    [s applyRepositorySnapshot:@[repoInfo(@"r",@"R",YES),repoInfo(@"dst",@"Destination",YES)] complete:YES fromCache:NO requestStartSeq:[s beginRepositoryRequest]];
    TestExtension *ext=configuredExtension(s); ext.liveListings=@{@"r:/":@[regressionFile(@"A",@"original")],@"dst:/":@[]};
    gMoveStatus=200;
    gServerRelocate=^(SeafDir *src,SeafDir *dst,NSString *oldName,NSString *newName) {ext.liveListings=@{@"r:/":@[],@"dst:/":@[regressionFile(@"A",@"edited")]};};
    __block NSError *answer;
    [ext modifyItem:modifyTemplate(file,@"dst",@"A") baseVersion:nil changedFields:NSFileProviderItemParentItemIdentifier contents:nil options:0 request:nil completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) { CHECK(!item); answer=error; }];
    CHECK(isMovePending(answer));
    CHECK(answer.localizedRecoverySuggestion.length>0 && [s moveRecoveryForUUID:file.uuid].count>0 && gMoveRequests==1);
    CHECK([[s decorationForItem:file.itemIdentifier].favoriteRank isEqual:@42] && ![s recordForUUID:file.uuid].deleted);
    [s close]; resetMoveTransport();
    for(int malformed=0;malformed<3;malformed++) {
        s=[[SeafFPStore alloc] initWithDomainIdentifier:[NSString stringWithFormat:@"final-quarantine-%d",malformed] error:nil];
        file=row(s,@"r",@"/A",@"x");
        long long request=[s beginMoveOfRecord:file toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"B" requestedName:@"B" existingDestinationNames:@[]]; CHECK(request>0);
        NSMutableDictionary *bad=[[s moveRecoveryForUUID:file.uuid] mutableCopy]; bad[@"start"]=@"invalid";
        NSString *raw=malformed==0?@"[]":malformed==1?@"not json":[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:bad options:0 error:nil] encoding:NSUTF8StringEncoding];
        [s setMetaValue:raw forKey:[@"fp_confirmed_move:" stringByAppendingString:file.uuid]];
        CHECK([s applyDirectoryListingOfRepo:@"r" directoryPath:@"/" entries:@[listingEntry(@"A",@"y")] requestStartSeq:s.currentSeq]!=SeafFPWriteFailed);
        CHECK([[s recordForUUID:file.uuid].oid isEqual:@"y"] && [[s moveRecoveryForUUID:file.uuid][@"needsResolution"] boolValue]);
        CHECK([[s metaValueForKey:[@"fp_quarantined_move:" stringByAppendingString:file.uuid]] isEqual:raw]);
        CHECK([s prepareFileCreationInRepo:@"r" path:@"/B" requestStartSeq:s.currentSeq]>=0);
        CHECK([s beginMoveOfRecord:[s recordForUUID:file.uuid] toRepo:@"r" directory:@"/" parentUUID:nil expectedName:@"C" requestedName:@"C" existingDestinationNames:@[]]<0);
        ext=configuredExtension(s); answer=nil;
        [ext modifyItem:modifyTemplate(file,@"r",@"C") baseVersion:nil changedFields:NSFileProviderItemFilename contents:nil options:0 request:nil completionHandler:^(NSFileProviderItem item,NSFileProviderItemFields fields,BOOL fetch,NSError *error) {answer=error;}];
        CHECK([answer.userInfo[@"reason"] isEqual:@"moveNeedsResolution"] && gMoveRequests==0);
        [s close];
    }
}

static void finalJournalEndpointRegressions(void) {
    for(int mode=0;mode<4;mode++) {
        NSString *domain=[NSString stringWithFormat:@"final-journal-endpoint-%d",mode];
        SeafFPStore *s=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        SeafFPStore *other=[[SeafFPStore alloc] initWithDomainIdentifier:domain error:nil];
        [s applyRepositorySnapshot:@[repoInfo(@"r",@"R",YES),repoInfo(@"dst",@"Destination",YES)] complete:YES fromCache:NO requestStartSeq:[s beginRepositoryRequest]];
        BOOL sourceInside=mode%2, crossRepo=mode>=2;
        SeafFPRecord *parent=[s upsertRecordForRepo:@"r" path:@"/P" isDir:YES parentUUID:nil oid:@"p" mtime:1 size:-1];
        SeafFPRecord *file=[s upsertRecordForRepo:@"r" path:sourceInside?@"/P/A":@"/outside" isDir:NO parentUUID:sourceInside?parent.uuid:nil oid:@"x" mtime:1 size:5]; favorite(s,file);
        long long start=[s beginMoveOfRecord:file toRepo:@"r" directory:sourceInside?@"/":@"/P" parentUUID:sourceInside?nil:parent.uuid expectedName:@"Target" requestedName:@"Target" existingDestinationNames:@[]];
        CHECK(start>0 && [s noteMoveReceiptForUUID:file.uuid requestStartSeq:start serverTime:10]);
        CHECK([other moveRecordUUID:parent.uuid toRepo:crossRepo?@"dst":@"r" path:@"/Q" parentUUID:nil]!=nil);
        NSDictionary *journal=[s moveRecoveryForUUID:file.uuid];
        CHECK([journal[@"sourceRepo"] isEqual:(sourceInside&&crossRepo?@"dst":@"r")]);
        CHECK([journal[@"sourcePath"] isEqual:(sourceInside?@"/Q/A":@"/outside")]);
        CHECK([journal[@"repo"] isEqual:(!sourceInside&&crossRepo?@"dst":@"r")]);
        CHECK([journal[@"dir"] isEqual:(sourceInside?@"/":@"/Q")]);
        SeafFPRecord *proof=[SeafFPRecord new];proof.uuid=file.uuid;proof.repoId=journal[@"sourceRepo"];proof.path=journal[@"sourcePath"];
        proof.oid=journal[@"oid"];proof.isDir=NO;proof.seq=[journal[@"sourceSeq"] longLongValue];
        SeafFPRecord *finished=[s finishPendingMoveOfRecord:proof toRepo:journal[@"repo"] path:[journal[@"dir"] stringByAppendingPathComponent:@"Target"] parentUUID:sourceInside?nil:parent.uuid requestStartSeq:start serverTime:10];
        CHECK(finished && [finished.uuid isEqual:file.uuid] && ![s moveRecoveryForUUID:file.uuid].count);
        CHECK([[s decorationForItem:file.itemIdentifier].favoriteRank isEqual:@42]);
        [other close];[s close];
    }
}

'''
main = r'''
int main(void) { @autoreleasepool {
    gTestDir=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"seaf-fp-public-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    finalRepositoryRegressions(); finalParentJournalRegressions(); detachedParentJournalRegression();
    finalMoveResolutionRegressions(); finalJournalEndpointRegressions();
    publicPermissions(); repositoryResponseOrdering(); sharedLibraryRoot(); failedWorkingSetSnapshot(); directMoveWithProvisionalDestination();
    moveAfterFailedListing(); workingSetPermissionsBetweenPages(); activityOffsetShiftsAtResume();
    deepHierarchy(); legacyOrphansAfterUpgrade(); workingSetScanAcrossEnumerators(); boundedTokensAndResume(); issue7(); activitySyncPaging(); activitySameSecondResume(); directoryCheckScheduling(); reviewFollowups(); signalRecovery();
    uploadListingWins(); editedRenameOrderAndReplacement(); retombstoneAfterRevival(); shiftAfterResumeAlreadyValidated();
    pendingMoveWithSourceReuse(); independentTargetStillAwaitingConfirmation(); newRepoVisibleWhileResumingAfterRestart();
    moveRequestDefinitivelyRejected(); lostMoveResponse(); modifyAfterRecoveringRename();
    lostConflictRenameResponse(); acknowledgedMoveWithExistingDuplicate(); unacknowledgedMoveDoesNotReplay(); pendingMoveRecoveryRegressions();
    unsettledMoveAbandonedAfterGrace(); unsettledMovePreservesUnverifiedFiles(); expiredMoveDecidesByVersion();
    moveAdoptsFreshContents(); activityPageEdgeCases();
    [[NSFileManager defaultManager] removeItemAtPath:gTestDir error:nil];
    NSLog(@"RESULT: public indexing regressions %d passed, %d failed",passes,failures);
    return failures?1:0;
} }
'''
source = (header + item_code + "\n" + enum_helpers + change_set + enum_class + enum_methods + '\n@end\n'
          + extension_methods
          + activity_helpers + activity_class + activity_method + '\n@end\n'
          + signal_class + signal_methods + '\n#undef NSFileProviderManager\n@end\n'
          + fixtures + retained_tests + signal_tests + edge_tests + final_tests + main)
with tempfile.TemporaryDirectory(prefix='seaf-fp-public-regression-') as workspace:
    out = Path(workspace)
    (out / 'PublicTests.m').write_text(source)
    command = [
        'clang', '-fobjc-arc', '-DDEBUG=1', '-DSEAFILE_APP=1', '-Wno-objc-protocol-method-implementation',
        '-Wno-incompatible-pointer-types', '-I', str(root / 'SeafFileProvider/StoreTest'),
        '-I', str(root / 'SeafFileProvider'), '-I', str(root / 'Pod/Classes'),
        '-framework', 'Foundation', '-framework', 'FileProvider',
        '-framework', 'UniformTypeIdentifiers', '-lsqlite3',
        str(root / 'SeafFileProvider/SeafFPStore.m'),
        str(root / 'SeafFileProvider/SeafFPIdentifier.m'),
        str(root / 'SeafFileProvider/SeafFPErrors.m'),
        str(out / 'PublicTests.m'), '-o', str(out / 'public-tests'),
    ]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode:
        print(result.stdout)
        raise SystemExit(result.returncode)
    result = subprocess.run([str(out / 'public-tests')], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in result.stdout.splitlines():
        if any(marker in line for marker in ('FAIL', 'RESULT', 'BENCH')):
            print(line)
    if result.returncode:
        Path('/private/tmp/seaf-fp-public-tests-failed.m').write_text(source)
        Path('/private/tmp/seaf-fp-public-tests-failed.log').write_text(result.stdout)
    raise SystemExit(result.returncode)
