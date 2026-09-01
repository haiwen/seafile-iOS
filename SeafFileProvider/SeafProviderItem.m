//
//  SeafProviderItem.m
//  SeafFileProvider
//
//  Created by Wei W on 11/5/17.
//  Copyright © 2017 Seafile. All rights reserved.
//

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "SeafProviderItem.h"
#import "SeafGlobal.h"
#import "SeafItem.h"
#import "SeafDir.h"
#import "SeafRepos.h"
#import "Debug.h"
#import "FileMimeType.h"

@interface SeafProviderItem ()
@property (nonatomic, strong) SeafItem *item;
@property (nonatomic, copy) NSString *parentItemIdentifier;
@end


@implementation SeafProviderItem
@synthesize itemIdentifier = _itemIdentifier;

- (instancetype)initWithSeafItem:(SeafItem *)item itemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
{
    if (self = [super init]) {
        _item = item;
        _itemIdentifier = itemIdentifier;
    }
    return self;
}
- (instancetype)initWithSeafItem:(SeafItem *)item
{
    return [self initWithSeafItem:item itemIdentifier:item.itemIdentifier];
}

- (NSFileProviderItemIdentifier)parentItemIdentifier
{
    SeafItem *parentItem = self.item.parentItem;
    if (parentItem == nil) {
        return _itemIdentifier;
    }
    if (parentItem.isRoot) {
        return NSFileProviderRootContainerItemIdentifier;
    }
    return parentItem.itemIdentifier;
}

- (NSString *)filename
{
    NSString *name = _item.name;
    if (name.length > 0) {
        return name;
    }
    // filename is declared non-null. An empty value makes the system treat the item as
    // invalid, which is how a stale duplicate ends up stuck in the Files app.
    if (_item.filename.length > 0) {
        return _item.filename;
    }
    NSString *lastComponent = _item.path.lastPathComponent;
    if (lastComponent.length > 0 && ![lastComponent isEqualToString:@"/"]) {
        return lastComponent;
    }
    return _item.repoId.length > 0 ? _item.repoId : @"Seafile";
}

- (NSString *)typeIdentifier
{
    if (!_item.filename) {
        return UTTypeFolder.identifier;
    }
    static NSDictionary *extensionTypes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *plistPath = [SeafileBundle() pathForResource:@"ExtensionTypes" ofType:@"plist"];
        extensionTypes = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    });
    
    NSString *extension = _item.filename.pathExtension.lowercaseString;
    
    //If there is no extension, return generic data type
    if (extension.length == 0) {
        return UTTypeData.identifier;
    }
    
    // Lookup predefined type
    NSString *typeId = extensionTypes[extension];
    if (typeId) {
        return typeId;
    }
    
    //Try system UTI recognition
    UTType *uttype = [UTType typeWithFilenameExtension:extension];
    NSString *uti = uttype.identifier;
    
    if (uti && ![uti hasPrefix:@"dyn."]) {
        return uti;
    }
    
    //If all else fails, return generic data type
    return UTTypeData.identifier;
}

- (NSFileProviderItemCapabilities)capabilities
{
    NSFileProviderItemCapabilities cap = NSFileProviderItemCapabilitiesAllowsReading;

    // Every container must stay enumerable regardless of permissions, otherwise the Files
    // app cannot open it and a favorite pointing at it becomes a dead entry.
    BOOL isContainer = !_item.isFile;
    if (isContainer) {
        cap |= NSFileProviderItemCapabilitiesAllowsContentEnumerating;
    }

    if (_item.isRoot || _item.isAccountRoot) {
        return cap;
    }

    // The repo list is not loaded on a cold start, so a missing repo says nothing about
    // permissions. Keep the item readable and browsable and let the operation itself fail.
    SeafRepo *repo = [_item.conn getRepo:_item.repoId];
    BOOL editable = repo ? repo.editable : NO;

    if (_item.isRepoRoot) {
        if (editable) {
            cap |= NSFileProviderItemCapabilitiesAllowsAddingSubItems;
        }
        return cap;
    }

    if (editable) {
        cap |= NSFileProviderItemCapabilitiesAllowsReparenting
        | NSFileProviderItemCapabilitiesAllowsRenaming
        | NSFileProviderItemCapabilitiesAllowsDeleting;
        cap |= isContainer ? NSFileProviderItemCapabilitiesAllowsAddingSubItems
                           : NSFileProviderItemCapabilitiesAllowsWriting;
    }
    
    return cap;
}

-(NSDate *)contentModificationDate
{
    SeafBase *obj = [_item toSeafObj];
    long long mtimeValue = 0;
    if (obj && [obj isKindOfClass:[SeafFile class]]) {
        mtimeValue = [(SeafFile *)obj mtime];
    } else if (obj && [obj isKindOfClass:[SeafDir class]]) {
        mtimeValue = [(SeafDir *)obj mtime];
        // Special handling for account root (repositories container):
        // If its own mtime is 0, try to derive from contained repos.
        if (mtimeValue == 0 && [obj isKindOfClass:[SeafRepos class]]) {
            SeafRepos *reposContainer = (SeafRepos *)obj;
            long long latestRepoMtime = 0;
            for (SeafBase *sub in reposContainer.items) {
                if ([sub isKindOfClass:[SeafRepo class]]) {
                    long long repoMtime = ((SeafRepo *)sub).mtime;
                    if (repoMtime > latestRepoMtime) latestRepoMtime = repoMtime;
                }
            }
            if (latestRepoMtime > 0) {
                mtimeValue = latestRepoMtime;
            }
        }
    }
    if (mtimeValue > 0) return [NSDate dateWithTimeIntervalSince1970:mtimeValue];
    return nil;
}
-(NSNumber *)documentSize
{
    SeafBase *obj = [_item toSeafObj];
    if (obj && [obj isKindOfClass:[SeafFile class]]) {
        return [NSNumber numberWithLongLong:[(SeafFile *)obj filesize]];
    }
    return nil;
}
-(NSData *)versionIdentifier
{
    SeafBase *obj = [_item toSeafObj];
    return [obj.ooid dataUsingEncoding:NSUTF8StringEncoding];
}

-(NSNumber *)childItemCount
{
    if (_item.isRoot) {
        return [NSNumber numberWithUnsignedInteger:SeafGlobal.sharedObject.publicAccounts.count];
    }
    SeafBase *obj = [_item toSeafObj];
    if ([obj isKindOfClass:[SeafFile class]]) {
        return [NSNumber numberWithInt:0];
    }

    if (obj && [obj hasCache]) {
        if ([obj isKindOfClass:[SeafRepos class]]) {
            int cnt = 0;
            for (SeafRepo *repo in [(SeafRepos*)obj items]) {
                if (!repo.passwordRequired) ++cnt;
            }
            return  [NSNumber numberWithInt:cnt];
        } else if ([obj isKindOfClass:[SeafDir class]]) {
            return [NSNumber numberWithUnsignedInteger:[[(SeafDir *)obj items] count]];
        }
    }
    return nil;
}

- (BOOL)isDownloaded
{
    if (_item.isRoot) {
        return true;
    }

    SeafBase *obj = [_item toSeafObj];
    return [obj hasCache];
}

- (BOOL)isDownloading
{
    SeafBase *obj = [_item toSeafObj];
    if (obj && [obj isKindOfClass:[SeafFile class]]) {
        return [(SeafFile *)obj isDownloading];
    }
    return false;
}

- (BOOL)isUploaded
{
    SeafBase *obj = [_item toSeafObj];
    if (obj && [obj isKindOfClass:[SeafFile class]]) {
        return [(SeafFile *)obj isUploaded];
    }
    return false;
}

- (BOOL)isUploading
{
    SeafBase *obj = [_item toSeafObj];
    if (obj && [obj isKindOfClass:[SeafFile class]]) {
        return [(SeafFile *)obj isUploading];
    }
    return false;
}

- (NSData *)tagData {
    return _item.tagData;
}

- (NSDate *)lastUsedDate {
    return _item.lastUsedDate;
}

- (NSNumber *)favoriteRank {
    return _item.favoriteRank;
}

@end
