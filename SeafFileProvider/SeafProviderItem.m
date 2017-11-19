//
//  SeafProviderItem.m
//  SeafFileProvider
//
//  Created by Wei W on 11/5/17.
//  Copyright © 2017 Seafile. All rights reserved.
//
#import <MobileCoreServices/MobileCoreServices.h>
#import "SeafProviderItem.h"
#import "SeafItem.h"
#import "SeafDir.h"
#import "SeafRepos.h"
#import "Debug.h"

@interface SeafProviderItem ()
@property (strong) SeafItem *item;
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

- (instancetype)initWithItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
{
    return [self initWithSeafItem:[[SeafItem alloc] initWithItemIdentity:itemIdentifier] itemIdentifier:itemIdentifier];
}

- (NSFileProviderItemIdentifier)parentItemIdentifier
{
    return self.item.parentItem.itemIdentifier;
}

- (NSString *)filename
{
    return _item.name;
}

- (NSString *)typeIdentifier
{
    NSString *uti = nil;
    if (!_item.filename) {
        uti = (NSString *)kUTTypeFolder;
    } else {
        uti = (NSString *)CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,(__bridge CFStringRef)(_item.filename.pathExtension), NULL));
    }
    return uti;
}

- (NSFileProviderItemCapabilities)capabilities
{
    NSFileProviderItemCapabilities cap = NSFileProviderItemCapabilitiesAllowsReading;
    if (_item.isRoot || _item.isAccountRoot) {
        return cap;
    }
    SeafRepo *repo = [_item.conn getRepo:_item.repoId];
    if (!repo) return cap;

    if (_item.isRepoRoot) {
        if (repo.editable) {
            cap |= NSFileProviderItemCapabilitiesAllowsAddingSubItems;
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
    if (obj && [obj isKindOfClass:[SeafFile class]]) {
        return [NSDate dateWithTimeIntervalSince1970:[(SeafFile *)obj mtime]];
    }
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
    SeafBase *obj = [_item toSeafObj];
    if (obj && [obj hasCache] && [obj isKindOfClass:[SeafDir class]]) {
        long cnt = [[(SeafDir *)obj items] count];
        return [NSNumber numberWithLong:cnt];
    }
    // placeholder
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

@end
