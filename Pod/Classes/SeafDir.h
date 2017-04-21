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
                    perm:(NSString *)aPerm
                    name:(NSString *)aName
                    path:(NSString *)aPath;

- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    perm:(NSString *)aPerm
                    name:(NSString *)aName
                    path:(NSString *)aPath
                    mime:(NSString *)aMime;

@property (readonly, copy) NSArray *allItems;
@property (readwrite, copy) NSArray *items;
@property (readonly) NSArray *uploadFiles;
@property (readonly) BOOL editable;
@property (readonly) NSString *perm;


// Api
- (void)mkdir:(NSString *)newDirName;
- (void)mkdir:(NSString *)newDirName success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir))failure;
- (void)createFile:(NSString *)newFileName;
- (void)delEntries:(NSArray *)entries;
- (void)copyEntries:(NSArray *)entries dstDir:(SeafDir *)dst_dir;
- (void)moveEntries:(NSArray *)entries dstDir:(SeafDir *)dst_dir;
- (void)renameFile:(SeafFile *)sfile newName:(NSString *)newName;




- (void)unload;
- (void)addUploadFile:(SeafUploadFile *)file flush:(BOOL)flush;
- (void)removeUploadItem:(SeafUploadFile *)ufile;

- (void)loadedItems:(NSMutableArray *)items;

- (NSString *)configKeyForSort;
- (void)reSortItemsByName;
- (void)reSortItemsByMtime;
- (void)sortItems:(NSMutableArray *)items;
- (void)downloadContentSuccess:(void (^)(SeafDir *dir)) success failure:(void (^)(SeafDir *dir, NSError *error))failure;

- (BOOL)nameExist:(NSString *)name;
- (NSArray *)subDirs;
@end
