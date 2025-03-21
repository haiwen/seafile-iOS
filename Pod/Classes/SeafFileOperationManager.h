//
//  SeafFileOperationManager.h
//  Seafile
//
//  Created by henry on 2025/1/20.
//

#import <Foundation/Foundation.h>
#import "SeafRepos.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Callback block
 @param success YES indicates the operation was successful, NO indicates failure
 @param error   Returns an error if one occurred (can be nil)
 */
typedef void(^SeafOperationCompletion)(BOOL success, NSError *_Nullable error);

@interface SeafFileOperationManager : NSObject

+ (instancetype)sharedManager;

/**
 Create a file

 @param fileName The name of the file
 @param directory The directory where the file is located (SeafDir)
 @param completion Callback after the operation is completed
 */
- (void)createFile:(NSString *)fileName
             inDir:(SeafDir *)directory
        completion:(SeafOperationCompletion)completion;

/**
 Create a folder

 @param folderName The name of the folder
 @param directory The directory where the folder is located (SeafDir)
 @param completion Callback after the operation is completed
 */
- (void)mkdir:(NSString *)folderName
        inDir:(SeafDir *)directory
    completion:(SeafOperationCompletion)completion;

/**
 Delete a group of files/folders in a directory

 @param entries An array of names of files/folders to be deleted
 @param directory The directory where the files/folders are located (SeafDir)
 @param completion Callback after the operation is completed
 */
- (void)deleteEntries:(NSArray<NSString *> *)entries
               inDir:(SeafDir *)directory
          completion:(SeafOperationCompletion)completion;

/**
 Rename

 @param oldName The old name
 @param newName The new name
 @param directory The directory
 @param completion Callback after the operation is completed
 */
- (void)renameEntry:(NSString *)oldName
            newName:(NSString *)newName
              inDir:(SeafDir *)directory
         completion:(void(^)(BOOL success, SeafBase *renamedFile, NSError *error))completion;

/**
 Copy

 @param entries An array of names of files/folders to be copied
 @param srcDir The source directory
 @param dstDir The destination directory
 @param completion Callback after the operation is completed
 */
- (void)copyEntries:(NSArray<NSString *> *)entries
             fromDir:(SeafDir *)srcDir
               toDir:(SeafDir *)dstDir
          completion:(SeafOperationCompletion)completion;

/**
 Move

 @param entries An array of names of files/folders to be moved
 @param srcDir The source directory
 @param dstDir The destination directory
 @param completion Callback after the operation is completed
 */
- (void)moveEntries:(NSArray<NSString *> *)entries
             fromDir:(SeafDir *)srcDir
               toDir:(SeafDir *)dstDir
          completion:(SeafOperationCompletion)completion;

- (void)renameEntry:(NSString *)oldName
            newName:(NSString *)newName
             inRepo:(SeafRepo *)repo
         completion:(void(^)(BOOL success, SeafBase *renamedFile, NSError *error))completion;

@end

NS_ASSUME_NONNULL_END
