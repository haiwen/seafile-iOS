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

// Singleton method
+ (SeafCacheManager *)sharedManager;

// Thumbnail cache (maintain existing functionality)
- (void)saveThumbToCache:(UIImage *)image key:(NSString *)key;
- (UIImage *)getThumbFromCache:(NSString *)key;

// File cache
- (NSString *)getCachedPath:(NSString *)fileId;
- (void)saveFileToCache:(NSString *)path fileId:(NSString *)fileId;
- (BOOL)isCached:(NSString *)fileId;
//- (void)clearFileCache:(NSString *)fileId;

// Cache configuration
- (void)setMemoryCacheLimit:(NSUInteger)totalCostLimit countLimit:(NSUInteger)countLimit;
- (void)setDiskCacheLimit:(unsigned long long)maxSize;

// Cache management
- (unsigned long long)totalCacheSize;
- (void)clearAllCache;
- (void)trimCacheToSize:(unsigned long long)maxSize;

// New interfaces to replace cache logic in SeafFile
- (BOOL)fileHasCache:(SeafFile *)file;
- (BOOL)loadFileCache:(SeafFile *)file;
- (BOOL)saveFileCache:(SeafFile *)file;
- (void)clearFileCache:(SeafFile *)file;
- (void)deleteCacheForFile:(SeafFile *)file;
- (BOOL)realLoadCache:(SeafFile *)file;
- (void)saveOidToLocalDB:(NSString *)oid seafFile:(SeafFile *)sFile connection:(SeafConnection *)conn;
- (NSString *)cachePathForFile:(SeafFile *)file;
- (void)updateWithEntry:(SeafBase *)entry sFile:(SeafFile *)sFile;

- (NSString *)getCachePathForFile:(SeafFile *)file;

// URL 图片缓存（与评论/预览页复用）
- (UIImage *)getImageForURL:(NSString *)url;
- (void)storeImage:(UIImage *)image forURL:(NSString *)url;
@end
