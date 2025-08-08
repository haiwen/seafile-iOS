//
//  SeafProviderItem.m
//  SeafFileProvider
//
//  Created by Wei W on 11/5/17.
//  Copyright © 2017 Seafile. All rights reserved.
//
#import <MobileCoreServices/MobileCoreServices.h>
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
    return _item.name;
}

- (NSString *)typeIdentifier
{
    if (!_item.filename) {
        return (NSString *)kUTTypeFolder;
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
        return (NSString *)kUTTypeData;
    }
    
    // Lookup predefined type
    NSString *typeId = extensionTypes[extension];
    if (typeId) {
        return typeId;
    }
    
    //Try system UTI recognition
    NSString *uti = (NSString *)CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag(
        kUTTagClassFilenameExtension,
        (__bridge CFStringRef)extension,
        NULL
    ));
    
    if (uti && ![uti hasPrefix:@"dyn."]) {
        return uti;
    }
    
    //If all else fails, return generic data type
    return (NSString *)kUTTypeData;
}

- (NSFileProviderItemCapabilities)capabilities
{
    Debug(@"[SeafProviderItem] Get file capabilities called: itemIdentifier=%@", self.itemIdentifier);
    NSFileProviderItemCapabilities cap = NSFileProviderItemCapabilitiesAllowsReading;
    if (_item.isRoot || _item.isAccountRoot) {
        return cap;
    }
    
    SeafRepo *repo = [_item.conn getRepo:_item.repoId];
    if (!repo) {
        return cap;
    }

    if (_item.isRepoRoot) {
        if (repo.editable) {
            cap |= NSFileProviderItemCapabilitiesAllowsAddingSubItems | NSFileProviderItemCapabilitiesAllowsContentEnumerating;
        }
        return cap;
    }

    if (repo.editable) {
        cap |= NSFileProviderItemCapabilitiesAllowsWriting
        | NSFileProviderItemCapabilitiesAllowsReparenting
        | NSFileProviderItemCapabilitiesAllowsRenaming
        | NSFileProviderItemCapabilitiesAllowsDeleting;
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
    // placeholder for folder
    return [NSNumber numberWithInt:1];
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
