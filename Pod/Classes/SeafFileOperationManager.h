//
//  SeafFileOperationManager.h
//  Seafile
//
//  Created by henry on 2025/1/20.
//

#import <Foundation/Foundation.h>
#import "SeafDir.h"

NS_ASSUME_NONNULL_BEGIN

/**
 回调 block
 @param success YES 表示操作成功，NO 表示失败
 @param error   发生错误时返回（可以为 nil）
 */
typedef void(^SeafOperationCompletion)(BOOL success, NSError *_Nullable error);

@interface SeafFileOperationManager : NSObject

+ (instancetype)sharedManager;

/**
 创建文件

 @param fileName 文件名
 @param directory 所在目录 (SeafDir)
 @param completion 操作完成后的回调
 */
- (void)createFile:(NSString *)fileName
             inDir:(SeafDir *)directory
        completion:(SeafOperationCompletion)completion;

/**
 创建文件夹

 @param folderName 文件夹名
 @param directory 所在目录 (SeafDir)
 @param completion 操作完成后的回调
 */
- (void)mkdir:(NSString *)folderName
        inDir:(SeafDir *)directory
    completion:(SeafOperationCompletion)completion;

/**
 删除目录下的一组文件/文件夹

 @param entries 要删除的文件/文件夹名数组
 @param directory 所在目录 (SeafDir)
 @param completion 操作完成后的回调
 */
- (void)deleteEntries:(NSArray<NSString *> *)entries
               inDir:(SeafDir *)directory
          completion:(SeafOperationCompletion)completion;

/**
 重命名

 @param oldName 旧名称
 @param newName 新名称
 @param directory 目录
 @param completion 操作完成后的回调
 */
- (void)renameEntry:(NSString *)oldName
            newName:(NSString *)newName
              inDir:(SeafDir *)directory
         completion:(SeafOperationCompletion)completion;

/**
 复制

 @param entries 要复制的文件/文件夹名数组
 @param srcDir 源目录
 @param dstDir 目标目录
 @param completion 操作完成后的回调
 */
- (void)copyEntries:(NSArray<NSString *> *)entries
             fromDir:(SeafDir *)srcDir
               toDir:(SeafDir *)dstDir
          completion:(SeafOperationCompletion)completion;

/**
 移动

 @param entries 要移动的文件/文件夹名数组
 @param srcDir 源目录
 @param dstDir 目标目录
 @param completion 操作完成后的回调
 */
- (void)moveEntries:(NSArray<NSString *> *)entries
             fromDir:(SeafDir *)srcDir
               toDir:(SeafDir *)dstDir
          completion:(SeafOperationCompletion)completion;

@end

NS_ASSUME_NONNULL_END
