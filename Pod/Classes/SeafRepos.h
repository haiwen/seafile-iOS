//
//  SeafRepos.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafDir.h"

#define SHARE_REPO @"srepo"
#define GROUP_REPO @"grepo"

#define ORG_REPO @"Organization"

@interface SeafRepo : SeafDir<SeafSortable>
@property (readonly) NSString *repoType;
@property (readonly, copy) NSString *desc;
@property (readonly, copy) NSString *owner;
@property (readonly, copy) NSString *magic;
@property (readonly, copy) NSString *encKey;
@property (readonly) BOOL passwordRequired;
@property (readwrite) BOOL encrypted;
@property (readwrite) int encVersion;
@property (readonly) unsigned long long size;
@property (readonly) long long mtime;
@property (readonly) NSString *type;

- (BOOL)canLocalDecrypt;
- (NSString *)detailText;
- (BOOL)isGroupRepo;


@end


@interface SeafRepos : SeafDir
@property NSMutableArray *repoGroups;

- (id)initWithConnection:(SeafConnection *)aConnection;

- (SeafRepo *)getRepo:(NSString *)repo;

@end
