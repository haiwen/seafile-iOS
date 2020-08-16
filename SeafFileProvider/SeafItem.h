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
- (SeafItem *)convertFromDict:(NSDictionary *)dict;
@end
