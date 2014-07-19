//
//  SeafDir.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafBase.h"
@class SeafUploadFile;
@class SeafFile;

@interface SeafDir : SeafBase

- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    name:(NSString *)aName
                    path:(NSString *)aPath;

@property (readonly, copy) NSMutableArray *allItems;
@property (readonly, copy) NSMutableArray *items;
@property (readonly, nonatomic) NSMutableArray *uploadItems;

@property (readonly) BOOL editable;

- (void)loadedItems:(NSMutableArray *)items;
- (void)mkdir:(NSString *)newDirName;
- (void)createFile:(NSString *)newFileName;
- (void)delEntries:(NSArray *)entries;
- (void)copyEntries:(NSArray *)entries dstDir:(SeafDir *)dst_dir;
- (void)moveEntries:(NSArray *)entries dstDir:(SeafDir *)dst_dir;

- (void)addUploadFile:(SeafUploadFile *)file;
- (void)removeUploadFile:(SeafUploadFile *)ufile;

- (void)renameFile:(SeafFile *)sfile newName:(NSString *)newName;

@end
