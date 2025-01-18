//
//  SeafMemoryCacheManager.h
//  Seafile
//
//  Created by threezhao on 2024/9/17.
//

#import <Foundation/Foundation.h>
@class SeafFile;
@class SeafConnection;
@class SeafBase;
@interface SeafCacheManager : NSObject

// 单例方法
+ (SeafCacheManager *)sharedManager;

// 缩略图缓存 (保持现有功能)
- (void)saveThumbToCache:(UIImage *)image key:(NSString *)key;
- (UIImage *)getThumbFromCache:(NSString *)key;

// 文件缓存
- (NSString *)getCachedPath:(NSString *)fileId;
- (void)saveFileToCache:(NSString *)path fileId:(NSString *)fileId;
- (BOOL)isCached:(NSString *)fileId;
//- (void)clearFileCache:(NSString *)fileId;

// 缓存配置
- (void)setMemoryCacheLimit:(NSUInteger)totalCostLimit countLimit:(NSUInteger)countLimit;
- (void)setDiskCacheLimit:(unsigned long long)maxSize;

// 缓存管理
- (unsigned long long)totalCacheSize;
- (void)clearAllCache;
- (void)trimCacheToSize:(unsigned long long)maxSize;

// 新增的接口，用来替代 SeafFile 中的缓存逻辑
- (BOOL)fileHasCache:(SeafFile *)file;
- (BOOL)loadFileCache:(SeafFile *)file;
- (BOOL)saveFileCache:(SeafFile *)file;
- (void)clearFileCache:(SeafFile *)file;
- (void)deleteCacheForFile:(SeafFile *)file;
- (BOOL)realLoadCache:(SeafFile *)file;
- (void)saveOidToLocalDB:(NSString *)oid seafFile:(SeafFile *)sFile connection:(SeafConnection *)conn;
- (NSString *)cachePathForFile:(SeafFile *)file;
- (void)updateWithEntry:(SeafBase *)entry sFile:(SeafFile *)sFile;

@end
