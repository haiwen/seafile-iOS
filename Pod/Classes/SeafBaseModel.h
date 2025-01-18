//
//  SeafBaseModel.h
//  Seafile
//
//  Created by henry on 2025/1/23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafBaseModel : NSObject

@property (nonatomic, copy, nullable) NSString *oid;        // 对象 ID
@property (nonatomic, copy, nullable) NSString *repoId;     // 仓库 ID
@property (nonatomic, copy, nullable) NSString *name;       // 条目名称
@property (nonatomic, copy, nullable) NSString *path;       // 在仓库中的路径
@property (nonatomic, copy, nullable) NSString *mime;       // MIME 类型
@property (nonatomic, copy, nullable) NSString *ooid;       // old oid
@property (nonatomic, copy, nullable) NSString *shareLink;  // 分享链接

/**
 初始化 model

 @param oid 对象 ID
 @param repoId 仓库 ID
 @param name 文件夹或文件名
 @param path 在仓库中的路径
 @param mime MIME 类型
 */
- (instancetype)initWithOid:(nullable NSString *)oid
                     repoId:(nullable NSString *)repoId
                       name:(nullable NSString *)name
                       path:(nullable NSString *)path
                       mime:(nullable NSString *)mime NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
