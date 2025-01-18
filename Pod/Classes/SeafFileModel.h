//
//  SeafFileModel.h
//  Seafile
//
//  Created by henry on 2025/1/22.
//

#import "SeafBaseModel.h"
#import "SeafConnection.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SeafFileDelegate <NSObject>
- (void)download:(id)file complete:(BOOL)updated;
- (void)download:(id)file failed:(NSError *)error;
- (void)download:(id)file progress:(float)progress;
@end
//@class SeafBaseModel;
@interface SeafFileModel : SeafBaseModel

/// 文件修改时间
@property (nonatomic, assign) long long mtime;
/// 文件大小
@property (nonatomic, assign) unsigned long long filesize;
/// 文件在本地缓存的路径
@property (nonatomic, copy, nullable) NSString *localPath;
/// 对应的 SeafConnection
@property (nonatomic, strong, nullable) SeafConnection *conn;

/**
 自定义的初始化方法

 @param oid    对象ID
 @param repoId 仓库ID
 @param name   文件名称
 @param path   文件在仓库中的路径
 @param mtime  文件修改时间
 @param size   文件大小
 @param conn   对应的 SeafConnection
 */
- (instancetype)initWithOid:(NSString *)oid
                     repoId:(NSString *)repoId
                       name:(NSString *)name
                       path:(NSString *)path
                      mtime:(long long)mtime
                       size:(unsigned long long)size
                 connection:(nullable SeafConnection *)conn NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/** 生成一个唯一标识 key，用于区分同账号下同仓库同路径的文件 */
- (NSString *)uniqueKey;

/** 判断文件是否是图片类型 */
- (BOOL)isImageFile;

/** 判断文件是否是视频类型 */
- (BOOL)isVideoFile;

/** 判断文件是否可编辑 */
- (BOOL)isEditable;

/** 转为字典，可用于序列化、日志或其他场景 */
- (NSDictionary *)toDictionary;

@end

NS_ASSUME_NONNULL_END
