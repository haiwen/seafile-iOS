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
@property (readonly) int encVersion;
@property (readonly) unsigned long long size;
@property (readonly) long long mtime;
@property (readonly) NSString *type;

- (NSString *)detailText;
- (BOOL)isGroupRepo;


// If local decryption is enabled, check library password locally, otherwise set library password on remote server
- (void)checkOrSetRepoPassword:(NSString *)password delegate:(id<SeafRepoPasswordDelegate>)del;
- (void)checkOrSetRepoPassword:(NSString *)password block:(repo_password_set_block_t)block;

@end


@interface SeafRepos : SeafDir
@property NSMutableArray *repoGroups;

- (id)initWithConnection:(SeafConnection *)aConnection;

- (SeafRepo *)getRepo:(NSString *)repo;
- (void)createLibrary:(NSString *)newLibName passwd:(NSString*)passwd block:(void(^)(bool success, id repoInfo))completeBlock;

@end
