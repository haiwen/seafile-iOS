//
//  SeafFileProviderUtility.m
//  SeafFileProvider
//
//  Created by three on 2022/8/8.
//  Copyright © 2022 Seafile. All rights reserved.
//

#import "SeafFileProviderUtility.h"
#import "SeafProviderItem.h"
#import "SeafStorage.h"
#import "SeafItem.h"
#import "Constants.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * const kIdentifierToSlugKey = @"identifierToSlug";
static NSString * const kSlugToIdentifierKey = @"slugToIdentifier";

@interface SeafFileProviderUtility()

@property (nonatomic, strong) NSMutableArray *updateItems;

@end

@implementation SeafFileProviderUtility

+ (instancetype)shared {
    static SeafFileProviderUtility *_shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[self alloc] init];
    });
    return _shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.updateItems = [NSMutableArray array];
    }
    return self;
}

- (NSInteger)currentAnchor {
    @synchronized (self) {
        return [[SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER_ANCHOR] integerValue];
    }
}

- (void)setCurrentAnchor:(NSInteger)currentAnchor {
    @synchronized (self) {
        NSInteger stored = [[SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER_ANCHOR] integerValue];
        // Never move backwards. The system remembers the last anchor it was given, so an
        // anchor that resets on process launch reads as "nothing changed since then".
        if (currentAnchor <= stored) {
            currentAnchor = stored + 1;
        }
        [SeafStorage.sharedObject setObject:@(currentAnchor) forKey:SEAF_FILE_PROVIDER_ANCHOR];
    }
}

- (void)saveUpdateItem:(SeafProviderItem *)item {
    if (!item) return;
    @synchronized (self) {
        if (![self.updateItems containsObject:item]) {
            [self.updateItems addObject:item];
        }
    }
}

- (NSArray *)allUpdateItems {
    @synchronized (self) {
        return [self.updateItems copy];
    }
}

- (NSArray *)updateItemsForContainer:(NSFileProviderItemIdentifier)container {
    @synchronized (self) {
        // No special case for the working set: its change enumeration re-reports the
        // members rebuilt from the metadata store, and handing it the whole list here
        // consumed (and removed) updates the owning container had not delivered yet.
        NSMutableArray *matched = [NSMutableArray array];
        for (SeafProviderItem *item in self.updateItems) {
            if ([item.parentItemIdentifier isEqualToString:container]) {
                [matched addObject:item];
            }
        }
        return matched;
    }
}

- (void)removeUpdateItems:(NSArray *)items {
    if (items.count == 0) return;
    @synchronized (self) {
        [self.updateItems removeObjectsInArray:items];
    }
}

- (NSArray<NSFileProviderItemIdentifier> *)reportedWorkingSetIdentifiers {
    @synchronized (self) {
        NSArray *stored = [SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER_WORKING_SET];
        return [stored isKindOfClass:[NSArray class]] ? stored : @[];
    }
}

- (void)setReportedWorkingSetIdentifiers:(NSArray<NSFileProviderItemIdentifier> *)identifiers {
    @synchronized (self) {
        [SeafStorage.sharedObject setObject:(identifiers ?: @[]) forKey:SEAF_FILE_PROVIDER_WORKING_SET];
    }
}

- (void)requestWorkingSetFullResyncIfNeeded {
    @synchronized (self) {
        NSInteger epoch = [[SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER_WORKING_SET_EPOCH] integerValue];
        if (epoch >= 1) {
            self.pendingWorkingSetFullResync = NO;
            return;
        }
        self.pendingWorkingSetFullResync = YES;
    }
}

- (void)markWorkingSetResyncComplete {
    @synchronized (self) {
        if (!self.pendingWorkingSetFullResync) {
            return;
        }
        self.pendingWorkingSetFullResync = NO;
        [SeafStorage.sharedObject setObject:@(1) forKey:SEAF_FILE_PROVIDER_WORKING_SET_EPOCH];
    }
}

static NSString *SeafSHA1Hex(NSString *input) {
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

- (NSDictionary *)normalizedStorageMaps {
    NSDictionary *stored = [SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER_STORAGE_MAP];
    if (![stored isKindOfClass:[NSDictionary class]]) {
        return @{ kIdentifierToSlugKey: @{}, kSlugToIdentifierKey: @{} };
    }

    // Either the nested identifier map or, on pre-slug-map installs, the flat
    // identifier -> slug dictionary. Both are rebuilt with canonical identifiers so a
    // change of the canonical form (e.g. dropping the leading slash) rekeys them on read.
    NSDictionary *identifierToSlug = [stored objectForKey:kIdentifierToSlugKey];
    if (![identifierToSlug isKindOfClass:[NSDictionary class]]
        || ![[stored objectForKey:kSlugToIdentifierKey] isKindOfClass:[NSDictionary class]]) {
        identifierToSlug = stored;
    }

    NSMutableDictionary *normalizedIdentifierToSlug = [NSMutableDictionary dictionary];
    NSMutableDictionary *normalizedSlugToIdentifier = [NSMutableDictionary dictionary];
    for (NSString *identifier in identifierToSlug) {
        NSString *slug = [identifierToSlug objectForKey:identifier];
        if (![slug isKindOfClass:[NSString class]] || slug.length == 0) {
            continue;
        }
        NSFileProviderItemIdentifier canonicalId = [SeafItem canonicalIdentifier:identifier];
        [normalizedIdentifierToSlug setObject:slug forKey:canonicalId];
        [normalizedSlugToIdentifier setObject:canonicalId forKey:slug];
    }
    return @{
        kIdentifierToSlugKey: normalizedIdentifierToSlug,
        kSlugToIdentifierKey: normalizedSlugToIdentifier,
    };
}

- (void)rekeyStorageMapsToCanonicalIdentifiers {
    @synchronized (self) {
        if (![[SeafStorage.sharedObject objectForKey:SEAF_FILE_PROVIDER_STORAGE_MAP] isKindOfClass:[NSDictionary class]]) {
            return;
        }
        NSDictionary *maps = [self normalizedStorageMaps];
        [self persistStorageMaps:[maps objectForKey:kIdentifierToSlugKey]
                slugToIdentifier:[maps objectForKey:kSlugToIdentifierKey]];
    }
}

- (void)persistStorageMaps:(NSDictionary *)identifierToSlug slugToIdentifier:(NSDictionary *)slugToIdentifier {
    [SeafStorage.sharedObject setObject:@{
        kIdentifierToSlugKey: identifierToSlug ?: @{},
        kSlugToIdentifierKey: slugToIdentifier ?: @{},
    } forKey:SEAF_FILE_PROVIDER_STORAGE_MAP];
}

- (NSString *)storageSlugForIdentifier:(NSFileProviderItemIdentifier)identifier {
    NSFileProviderItemIdentifier canonicalId = [SeafItem canonicalIdentifier:identifier];
    if ([canonicalId isEqualToString:NSFileProviderRootContainerItemIdentifier]
        || [canonicalId isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier]) {
        return canonicalId;
    }

    @synchronized (self) {
        NSDictionary *maps = [self normalizedStorageMaps];
        NSMutableDictionary *identifierToSlug = [NSMutableDictionary dictionaryWithDictionary:[maps objectForKey:kIdentifierToSlugKey]];
        NSMutableDictionary *slugToIdentifier = [NSMutableDictionary dictionaryWithDictionary:[maps objectForKey:kSlugToIdentifierKey]];

        NSString *existing = [identifierToSlug objectForKey:canonicalId];
        if (existing.length > 0) {
            return existing;
        }

        NSString *slug = SeafSHA1Hex(canonicalId);
        [identifierToSlug setObject:slug forKey:canonicalId];
        [slugToIdentifier setObject:canonicalId forKey:slug];
        [self persistStorageMaps:identifierToSlug slugToIdentifier:slugToIdentifier];
        return slug;
    }
}

- (nullable NSFileProviderItemIdentifier)identifierForStorageSlug:(NSString *)slug {
    if (slug.length == 0) {
        return nil;
    }

    @synchronized (self) {
        NSDictionary *maps = [self normalizedStorageMaps];
        NSString *identifier = [[maps objectForKey:kSlugToIdentifierKey] objectForKey:slug];
        if (identifier.length > 0) {
            return identifier;
        }
    }

    // Pre-slug installs stored containers under the full encoded path component.
    if ([slug containsString:@"%"] || [slug hasPrefix:@"http"]) {
        return [SeafItem canonicalIdentifier:slug];
    }
    return nil;
}

- (BOOL)isStorageSlug:(NSString *)name {
    if (name.length != CC_SHA1_DIGEST_LENGTH * 2) {
        return NO;
    }
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    return [[name lowercaseString] rangeOfCharacterFromSet:[hex invertedSet]].location == NSNotFound;
}

@end
