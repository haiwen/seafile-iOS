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
@property (readonly, copy) NSArray *items;
@property (readonly) NSArray *uploadFiles;
@property (readonly) BOOL editable;
@property (readonly) NSString *perm;


// Api
- (void)mkdir:(NSString *)newDirName;
- (void)mkdir:(NSString *)newDirName success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure;
- (void)createFile:(NSString *)newFileName;

- (void)delEntries:(NSArray *)entries success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure;
- (void)delEntries:(NSArray *)entries;

- (void)copyEntries:(NSArray *)entries dstDir:(SeafDir *)dstDir success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure;
- (void)copyEntries:(NSArray *)entries dstDir:(SeafDir *)dstDir;

- (void)moveEntries:(NSArray *)entries dstDir:(SeafDir *)dstDir success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure;
- (void)moveEntries:(NSArray *)entries dstDir:(SeafDir *)dstDir;

- (void)renameEntry:(NSString *)oldName newName:(NSString *)newName success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure;
- (void)renameEntry:(NSString *)oldName newName:(NSString *)newName;



- (void)unload;
- (void)addUploadFile:(SeafUploadFile *)file;
- (void)removeUploadItem:(SeafUploadFile *)ufile;

- (void)loadedItems:(NSMutableArray *)items;

- (NSString *)configKeyForSort;
- (void)reSortItemsByName;
- (void)reSortItemsByMtime;
- (void)sortItems:(NSMutableArray *)items;
- (void)loadContentSuccess:(void (^)(SeafDir *dir)) success failure:(void (^)(SeafDir *dir, NSError *error))failure;

- (BOOL)nameExist:(NSString *)name;
- (NSArray *)subDirs;
@end
