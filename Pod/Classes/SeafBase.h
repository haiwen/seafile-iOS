//
//  SeafBase.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafConnection.h"
#import "Debug.h"

// 下载回调相关状态
typedef enum {
    SEAF_DENTRY_INIT = 0,
    SEAF_DENTRY_LOADING,
    SEAF_DENTRY_SUCCESS,
    SEAF_DENTRY_FAILURE,
    SEAF_DENTRY_UPTODATE,
} SeafDentryState;

@interface NSObject (NSObjectValue)
- (long long)integerValue:(int)defaultValue;
- (BOOL)booleanValue:(BOOL)defaultValue;
- (NSString *)stringValue;

@end

@class SeafBase;
@class SeafConnection;
@protocol SeafDentryDelegate <NSObject>
- (void)download:(id)entry complete:(BOOL)updated;
- (void)download:(id)entry failed:(NSError *)error;
- (void)download:(id)entry progress:(float)progress;
@end

@protocol SeafShareDelegate <NSObject>
- (void)generateSharelink:(SeafBase *)entry WithResult:(BOOL)success;
@end

@interface SeafBase : NSObject

@property (nonatomic, weak, nullable) id<SeafDentryDelegate> delegate;    // 代理对象
@property (nonatomic, assign) SeafDentryState state;                      // 下载或加载状态

/**
 * 指向 SeafConnection，用于进行网络请求和仓库管理等。
 * 注意：在 init 时注入，强引用或弱引用请根据实际情况来定。
 */
@property (nonatomic, weak, nullable) SeafConnection *connection;

/**
 * 唯一标识，用于区分不同 SeafBase 实例（结合账号、repoId、path等信息）。
 * 如果在子类中需要生成特殊的 uniqueKey，也可以覆盖此属性的 getter。
 */
@property (nonatomic, copy, nullable) NSString *uniqueKey;

/**
 * 是否加密仓库。
 * 在需要判断该仓库是否加密或需要输入密码时使用（由子类或上层调用）。
 */
@property (nonatomic, assign) BOOL encrypted;

/**
 * 是否有缓存文件存在（可根据自己的业务逻辑决定实现）。
 */
@property (nonatomic, assign, readonly) BOOL hasCache;

/**
 加载（或更新）该条目的数据/内容。子类中应根据 force 判断是否强制拉取。
 @param force 是否强制刷新（忽略本地缓存，直接从服务器获取）
 */
- (void)loadContent:(BOOL)force;

/**
 清理缓存
 */
- (void)clearCache;

/**
 设置星标（收藏）
 */
- (void)setStarred:(BOOL)starred;

/**
 判断是否需要密码（加密仓库）
 */
- (BOOL)passwordRequiredWithSyncRefresh;

/**
 设置仓库密码
 */
- (void)setRepoPassword:(NSString *)password block:(void(^)(SeafBase *entry, int ret))block;

/**
 获取/生成分享链接
 */
- (void)generateShareLink:(id<SeafShareDelegate>)dg;
- (void)generateShareLink:(id<SeafShareDelegate>)dg
                 password:(nullable NSString *)password
              expire_days:(nullable NSString *)expire_days;

- (instancetype)initWithConnection:(SeafConnection *)aConnection
                               oid:(nullable NSString *)anId
                            repoId:(nullable NSString *)aRepoId
                              name:(nullable NSString *)aName
                              path:(nullable NSString *)aPath
                              mime:(nullable NSString *)aMime;

- (BOOL)loadCache; // load local cache
- (NSString *)cacheKey; //the key used for cache
- (NSString *)key; // The key used to sort
- (void)updateWithEntry:(SeafBase *)entry;
- (UIImage *)icon; // icon for this entry
@property (readonly, copy) NSString *mime; //mime type
@property (readonly, copy) NSString *shareLink; // shared link
@property (readonly, copy) NSString * _Nullable repoId; // library id
@property (readonly, copy) NSString * _Nullable path; // path in the library
@property (copy) NSString *_Nullable oid;  // current object id
@property (copy) NSString *_Nullable ooid; // cached object id
typedef void (^repo_password_set_block_t)(SeafBase *entry, int ret);
@property (nonatomic, copy) NSString *repoName;//repo name
@property (nonatomic, assign) BOOL isDeleted;//2.9.27 mark is deleted
@property (copy) NSString *name; //obj name
@property (nonatomic, copy) NSString *fullPath; // full path

@end
