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

/**
 * @class SeafDir
 * @discussion Represents a directory in the Seafile server, allowing navigation and management of its contents.
 */
@interface SeafDir : SeafBase

/**
 * Initializes a new instance of the directory with the specified details.
 * @param aConnection The Seafile connection associated with this directory.
 * @param anId The object identifier for this directory.
 * @param aRepoId The repository identifier this directory belongs to.
 * @param aPerm The permission string (e.g., "rw" for read-write).
 * @param aName The name of the directory.
 * @param aPath The full path of the directory.
 * @param mtime The modification timestamp of the directory.
 * @return An initialized directory object, or nil if an object could not be created for some reason.
 */
- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    perm:(NSString *)aPerm
                    name:(NSString *)aName
                    path:(NSString *)aPath
                   mtime:(long long)mtime;

- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    perm:(NSString *)aPerm
                    name:(NSString *)aName
                    path:(NSString *)aPath
                    mime:(NSString *)aMime
                   mtime:(long long)mtime;

@property (readonly, copy) NSArray *allItems;//All items displayed in the current directory
@property (nonatomic, copy) NSArray *items;//All items from server,after modified by - (void)updateItems:(NSMutableArray *)items
@property (readonly) NSArray *uploadFiles;// equal to uploadItems
@property (readonly) BOOL editable;
@property (nonatomic, copy) NSString *perm;
@property (nonatomic, assign) long long mtime;///< Modification time of the directory.
//@property (assign, nonatomic) BOOL encrypted;///< Indicates whether the repository is encrypted.

/**
 * Unloads the directory's content from memory, resetting its state.
 */
- (void)unload;

/**
 * Adds an upload file to the current directory's upload queue if it's not already present.
 * @param file The `SeafUploadFile` object representing the file to be uploaded.
 */
- (void)addUploadFile:(SeafUploadFile *)file;

/**
 * Removes an upload file from the current directory's upload items.
 * @param ufile The `SeafUploadFile` object to be removed from the upload items.
 */
- (void)removeUploadItem:(SeafUploadFile *)ufile;

/**
 * Updates the directory items with newly loaded items.
 * @param items An array of newly loaded items.
 */
- (void)loadedItems:(NSMutableArray *)items;

/**
 * Returns the configuration key for sorting directory contents.
 * @return A string representing the configuration key.
 */
- (NSString *)configKeyForSort;

/**
 * Re-sorts the directory items by name.
 */
- (void)reSortItemsByName;

/**
 * Re-sorts the directory items by modification time.
 */
- (void)reSortItemsByMtime;

/**
 * Sorts the items in the directory.
 * @param items An array of items to sort.
 */
- (void)sortItems:(NSMutableArray *)items;

/**
 * Initiates loading of the directory content from the server.
 * @param success A block called on successful loading of the directory.
 * @param failure A block called on failure to load the directory.
 */
- (void)loadContentSuccess:(void (^)(SeafDir *dir)) success failure:(void (^)(SeafDir *dir, NSError *error))failure;

/**
 * Checks if a given name already exists in the directory's items.
 * @param name The name of the item to check for existence.
 * @return A boolean indicating whether the name exists in the directory's items.
 */
- (BOOL)nameExist:(NSString *)name;

/**
 * Retrieves the array of subdirectories within this directory.
 * @return An array containing the subdirectories.
 */
- (NSArray *)subDirs;

- (void)handleResponse:(NSHTTPURLResponse *)response json:(id)JSON;

/**
 * Returns a string representation of the directory's modification time for display.
 * @return A formatted string with the modification time, or an empty string if mtime is not available.
 */
- (NSString *)detailText;

@end
