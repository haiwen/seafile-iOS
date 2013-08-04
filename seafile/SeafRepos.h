//
//  SeafRepos.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafDir.h"

@interface SeafRepo : SeafDir
@property (readonly) NSString *repoType;
@property (readonly, copy) NSString *desc;
@property (readonly, copy) NSString *owner;
@property (readonly) BOOL passwordRequired;
@property (readonly) BOOL editable;
@property (readwrite) BOOL encrypted;
@property (readwrite) int encVersion;
@property (readonly) unsigned long long size;
@property (readonly) int mtime;
@property (readonly) NSString *gid;
@end


@interface SeafRepos : SeafDir
@property NSMutableArray *repoGroups;

- (id)initWithConnection:(SeafConnection *)aConnection;

- (SeafRepo *)getRepo:(NSString *)repo;

@end
