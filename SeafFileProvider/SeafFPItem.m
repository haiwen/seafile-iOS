//
//  SeafFPItem.m
//  SeafFileProvider
//

#import "SeafFPItem.h"
#import "SeafFPIdentifier.h"
#import "SeafFPStore.h"
#import "SeafRepos.h"
#import "SeafConnection.h"

static const BOOL kSeafFPWriteOperationsEnabled = YES;

@interface SeafFPItem ()
@property (nonatomic, assign) BOOL isDirectory;
@end

@implementation SeafFPItem

+ (BOOL)writeOperationsEnabled
{
    return kSeafFPWriteOperationsEnabled;
}

+ (NSFileProviderItemVersion *)versionWithContent:(NSString *)content metadata:(NSString *)metadata
{
    // Versions must not be empty; "-" stands for "content id not known yet".
    // The metadata component carries the file name and may exceed the
    // 128-byte limit of a component; versionComponentData: digests it then.
    NSData *contentData = [SeafFPIdentifier versionComponentData:(content.length > 0 ? content : @"-")];
    NSData *metadataData = [SeafFPIdentifier versionComponentData:(metadata ?: @"")];
    return [[NSFileProviderItemVersion alloc] initWithContentVersion:contentData metadataVersion:metadataData];
}

+ (NSBundle *)resourceBundle
{
    static NSBundle *bundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"Seafile" withExtension:@"bundle"];
        if (!url) {
            url = [[NSBundle bundleForClass:[SeafConnection class]] URLForResource:@"Seafile" withExtension:@"bundle"];
        }
        bundle = url ? [NSBundle bundleWithURL:url] : [NSBundle mainBundle];
    });
    return bundle;
}

+ (UTType *)contentTypeForFilename:(NSString *)filename
{
    static NSDictionary *extensionTypes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *plistPath = [[self resourceBundle] pathForResource:@"ExtensionTypes" ofType:@"plist"];
        extensionTypes = plistPath ? [NSDictionary dictionaryWithContentsOfFile:plistPath] : @{};
    });
    NSString *extension = filename.pathExtension.lowercaseString;
    if (extension.length == 0) {
        return UTTypeData;
    }
    NSString *predefined = extensionTypes[extension];
    if (predefined) {
        UTType *type = [UTType typeWithIdentifier:predefined];
        if (type) return type;
    }
    UTType *type = [UTType typeWithFilenameExtension:extension];
    if (type && ![type.identifier hasPrefix:@"dyn."]) {
        return type;
    }
    return UTTypeData;
}

// An item without AllowsWriting (files) or AllowsAddingSubItems (directories)
// is written to disk by fileproviderd with the "locked" flag. On iOS 26
// setting that flag fails (VFSFileError.cannotSetMetadata, EPERM): the item
// is never created, the domain goes into throttled retry and Files shows the
// location with "!" / "Sync paused"; a read-only library appears empty.
// Read-only items therefore keep these two bits and the extension rejects
// the write in createItem / modifyItem instead (design §7.6 / §7.7).
+ (NSFileProviderItemCapabilities)baseCapabilitiesForDirectory:(BOOL)isDirectory
{
    NSFileProviderItemCapabilities caps = NSFileProviderItemCapabilitiesAllowsReading;
    if (isDirectory) {
        caps |= NSFileProviderItemCapabilitiesAllowsContentEnumerating
              | NSFileProviderItemCapabilitiesAllowsAddingSubItems;
    } else {
        caps |= NSFileProviderItemCapabilitiesAllowsWriting;
    }
    return caps;
}

+ (NSFileProviderItemCapabilities)capabilitiesForDirectory:(BOOL)isDirectory editable:(BOOL)editable
{
    NSFileProviderItemCapabilities caps = [self baseCapabilitiesForDirectory:isDirectory];
    if (editable && kSeafFPWriteOperationsEnabled) {
        caps |= NSFileProviderItemCapabilitiesAllowsRenaming
              | NSFileProviderItemCapabilitiesAllowsReparenting
              | NSFileProviderItemCapabilitiesAllowsDeleting;
    }
    return caps;
}

+ (instancetype)rootItemWithName:(NSString *)name
{
    SeafFPItem *item = [SeafFPItem new];
    item.itemIdentifier = NSFileProviderRootContainerItemIdentifier;
    item.parentItemIdentifier = NSFileProviderRootContainerItemIdentifier;
    item.filename = name.length > 0 ? name : @"Seafile";
    item.contentType = UTTypeFolder;
    item.isDirectory = YES;
    item.capabilities = NSFileProviderItemCapabilitiesAllowsReading | NSFileProviderItemCapabilitiesAllowsContentEnumerating;
    item.itemVersion = [self versionWithContent:@"root" metadata:@"root"];
    return item;
}

+ (instancetype)trashItem
{
    SeafFPItem *item = [SeafFPItem new];
    item.itemIdentifier = NSFileProviderTrashContainerItemIdentifier;
    item.parentItemIdentifier = NSFileProviderRootContainerItemIdentifier;
    item.filename = @"Trash";
    item.contentType = UTTypeFolder;
    item.isDirectory = YES;
    item.capabilities = NSFileProviderItemCapabilitiesAllowsReading | NSFileProviderItemCapabilitiesAllowsContentEnumerating;
    item.itemVersion = [self versionWithContent:@"trash" metadata:@"trash"];
    return item;
}

+ (instancetype)itemForRepo:(SeafRepo *)repo
{
    SeafFPItem *item = [SeafFPItem new];
    item.itemIdentifier = [SeafFPIdentifier identifierForRepo:repo.repoId];
    item.parentItemIdentifier = NSFileProviderRootContainerItemIdentifier;
    item.filename = repo.name ?: repo.repoId;
    item.contentType = UTTypeFolder;
    item.isDirectory = YES;
    // Libraries themselves cannot be renamed, moved or deleted from Files.
    // AllowsAddingSubItems is kept for read-only libraries too, see
    // baseCapabilitiesForDirectory:; createItem rejects the write.
    item.capabilities = [self baseCapabilitiesForDirectory:YES];
    NSString *metadata = [NSString stringWithFormat:@"%lld|%@|%@", repo.mtime, repo.name ?: @"", repo.perm ?: @""];
    item.itemVersion = [self versionWithContent:repo.ooid metadata:metadata];
    if (repo.mtime > 0) {
        item.contentModificationDate = [NSDate dateWithTimeIntervalSince1970:repo.mtime];
    }
    return item;
}

+ (instancetype)itemForRecord:(SeafFPRecord *)record repoEditable:(BOOL)editable
{
    SeafFPItem *item = [SeafFPItem new];
    item.itemIdentifier = record.itemIdentifier;
    item.parentItemIdentifier = record.parentItemIdentifier;
    item.filename = record.name.length > 0 ? record.name : record.path.lastPathComponent;
    item.isDirectory = record.isDir;
    item.contentType = record.isDir ? UTTypeFolder : [self contentTypeForFilename:item.filename];
    item.capabilities = [self capabilitiesForDirectory:record.isDir editable:editable];
    NSString *metadata = [NSString stringWithFormat:@"%lld|%lld|%@", record.mtime, record.size, item.filename];
    item.itemVersion = [self versionWithContent:record.oid metadata:metadata];
    if (!record.isDir) {
        item.documentSize = @(record.size);
    }
    if (record.mtime > 0) {
        item.contentModificationDate = [NSDate dateWithTimeIntervalSince1970:record.mtime];
    }
    return item;
}

- (void)applyDecoration:(SeafFPDecoration *)decoration
{
    self.favoriteRank = decoration.favoriteRank;
    self.tagData = decoration.tagData;
    self.lastUsedDate = decoration.lastUsedDate;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<SeafFPItem %@ parent=%@ name=%@ dir=%d fav=%@>",
            self.itemIdentifier, self.parentItemIdentifier, self.filename, self.isDirectory, self.favoriteRank];
}

@end
