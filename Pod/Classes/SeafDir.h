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
 * @return An initialized directory object, or nil if an object could not be created for some reason.
 */
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
@property (nonatomic, copy) NSString *perm;
//@property (assign, nonatomic) BOOL encrypted;///< Indicates whether the repository is encrypted.


// Api
- (void)mkdir:(NSString *)newDirName;

/**
 * Creates a new directory within this directory.
 * @param newDirName The name of the new directory to create.
 * @param success A block called on successful creation of the directory.
 * @param failure A block called on failure to create the directory.
 */
- (void)mkdir:(NSString *)newDirName success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure;

/**
 * Creates a new file within this directory.
 * @param newFileName The name of the new file to be created.
 */
- (void)createFile:(NSString *)newFileName;

/**
 * Deletes the specified entries from this directory.
 * @param entries An array of entries to delete.
 * @param success A block called on successful deletion of the entries.
 * @param failure A block called on failure to delete the entries.
 */
- (void)delEntries:(NSArray *)entries success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure;

- (void)delEntries:(NSArray *)entries;

/**
 * Copies specified entries from the current directory to another directory.
 * @param entries An array of `SeafBase` objects representing the entries to be copied.
 * @param dstDir The destination `SeafDir` directory where the entries should be copied.
 * @param success A block that gets called upon successful completion of the copy operation. It passes the `SeafDir` instance where the entries were copied.
 * @param failure A block that gets called if the copy operation fails. It passes the `SeafDir` instance and an `NSError` with details about the failure.
 */
- (void)copyEntries:(NSArray *)entries dstDir:(SeafDir *)dstDir success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure;
- (void)copyEntries:(NSArray *)entries dstDir:(SeafDir *)dstDir;

/**
 * Moves entries to another directory.
 * @param entries An array of entries to move.
 * @param dstDir The destination directory.
 * @param success A block called on successful movement of the entries.
 * @param failure A block called on failure to move the entries.
 */
- (void)moveEntries:(NSArray *)entries dstDir:(SeafDir *)dstDir success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure;
- (void)moveEntries:(NSArray *)entries dstDir:(SeafDir *)dstDir;

/**
 * Renames an entry within the directory.
 * @param oldName The current name of the entry.
 * @param newName The new name for the entry.
 * @param success A block called on successful renaming of the entry.
 * @param failure A block called on failure to rename the entry.
 */
- (void)renameEntry:(NSString *)oldName newName:(NSString *)newName success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure;
- (void)renameEntry:(NSString *)oldName newName:(NSString *)newName;


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
@end
