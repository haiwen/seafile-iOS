//
//  SeafDecodedData.h
//  SeafFileProvider
//
//  Created by Wei W on 11/5/17.
//  Copyright © 2017 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SeafConnection.h"
#import "SeafFile.h"

@interface SeafItem : NSObject

/**
 * Normalizes an identifier to its canonical, slash-less form.
 * The system's path normalization (sidebar bookmarks, Spotlight) strips a leading slash,
 * so a slash-prefixed identifier comes back in both forms and fileproviderd keeps two
 * distinct nodes for the same item. Identifiers written by older builds still carry the
 * slash and are accepted here.
 */
+ (NSFileProviderItemIdentifier)canonicalIdentifier:(NSFileProviderItemIdentifier)identifier;

@property (readonly) NSFileProviderItemIdentifier itemIdentifier;

@property (readonly) NSString *server;
@property (readonly) NSString *username;
@property (readonly) NSString *repoId;
@property (readonly) NSString *path; //folder path
@property (readonly) NSString *filename;
@property (nonatomic, strong) NSData *tagData;
@property (nonatomic, strong) NSDate *lastUsedDate;
@property (nonatomic, strong) NSNumber *favoriteRank;

@property (readonly) NSString *name;
@property (readonly) SeafConnection *conn;


- (instancetype)initWithItemIdentity:(NSFileProviderItemIdentifier)identity;
- (instancetype)initWithServer:server username:(NSString *)username repo:(NSString *)repoId path:(NSString *)path filename:(NSString *)filename;

- (SeafItem *)parentItem;
- (BOOL)isRoot;
- (BOOL)isAccountRoot;
- (BOOL)isRepoRoot;
- (BOOL)isFile;
- (BOOL)isTouchIdEnabled;

- (SeafBase *)toSeafObj;

+ (SeafItem *)fromAccount:(SeafConnection *)conn;
+ (SeafItem *)fromSeafBase:(SeafBase *)obj;

- (NSDictionary*)convertToDict;
+ (SeafItem *)itemFromDict:(NSDictionary *)dict;

/// The persisted File Provider metadata store, keyed by canonical item identifier.
+ (NSDictionary *)localMetadataStore;

/**
 * Applies the locally persisted favorite rank, last used date and display name.
 * The favorite rank exists only on the device, so an item built from the server alone must
 * be topped up from the store before being handed to the system. Otherwise the system reads
 * the missing rank as "no longer a favorite" and drops the entry.
 */
- (void)applyLocalMetadataFromStore:(NSDictionary *)store;

- (void)updateCacheWithSubItem:(SeafItem *)item;
@end
