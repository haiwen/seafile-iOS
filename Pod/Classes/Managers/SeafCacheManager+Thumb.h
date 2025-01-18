//
//  SeafCacheManager+Thumb.h
//  Seafile
//
//  Created by henry on 2025/1/24.
//

#import "SeafCacheManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface SeafCacheManager (Thumb)

/// 返回某个 SeafFile 的图标(若是图片/视频, 则先从缩略图缓存获取, 如无则发起生成/下载等逻辑)
- (UIImage *_Nullable)iconForFile:(SeafFile *)file;

/// 生成或下载缩略图（若已存在则直接读取），成功后回调
- (void)generateThumbForFile:(SeafFile *)file completion:(void (^)(BOOL success, UIImage *_Nullable thumb))completion;

/// 取消缩略图下载或生成
- (void)cancelThumbForFile:(SeafFile *)file;

// 根据 file 判断是否是图片/视频文件
- (BOOL)isImageFile:(SeafFile *)file;
- (BOOL)isVideoFile:(SeafFile *)file;

- (UIImage *)thumbForFile:(SeafFile *)file;

- (NSString *)thumbPath:(NSString *)objId sFile:(SeafFile *)sFile;

@end

NS_ASSUME_NONNULL_END
