//
//  SeafCacheManager+Thumb.m
//  Seafile
//
//  Created by henry on 2025/1/24.
//

#import "SeafCacheManager+Thumb.h"
#import "SeafFile.h"
#import "Utils.h"
#import "SeafThumb.h"
#import "SeafDataTaskManager.h"
#import "Debug.h"
#import "SeafStorage.h"
#import "SeafRealmManager.h"

@implementation SeafCacheManager (Thumb)

// 是否图片类型
- (BOOL)isImageFile:(SeafFile *)file
{
    return [Utils isImageFile:file.name];
}

// 是否视频类型
- (BOOL)isVideoFile:(SeafFile *)file
{
    return [Utils isVideoFile:file.name];
}

/// 返回图标：若是图片/视频则尝试获取缩略图，否则返回默认 icon
- (UIImage *_Nullable)iconForFile:(SeafFile *)file
{
    if (!file.oid) {
        NSString *cacheOid = [[SeafRealmManager shared] getOidForUniKey:file.uniqueKey serverMtime:file.mtime];
        if (cacheOid && cacheOid.length > 0) {
            file.oid = cacheOid;
        }
    }
    if ((file.isImageFile || file.isVideoFile)) {
        if (![file.connection isEncrypted:file.repoId]) {
            if (!file.isDeleted) {
                UIImage *img = [self thumbForFile:file];
                if (img) {
                    return img;
                }
                else if (!file.thumbTaskForQueue) {
                    SeafThumb *thb = [[SeafThumb alloc] initWithSeafFile:file];
                    file.thumbTaskForQueue = thb;
                    [SeafDataTaskManager.sharedObject addThumbTask:thb];
                }
            } else {
                return nil;
            }
        } else {
            return nil;
        }
    }
    return nil;
}

/// 取消缩略图下载或生成
- (void)cancelThumbForFile:(SeafFile *)file
{
    if (file.thumbTaskForQueue) {
        [file.thumbTaskForQueue cancel];
        file.thumbTaskForQueue = nil;
    }
}

- (UIImage *)thumbForFile:(SeafFile *)file {
    NSString *thumbpath;
    if (file.oid) {
        thumbpath = [file thumbPath:file.oid];
    } else {
        thumbpath = [SeafStorage.sharedObject.thumbsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@-%lld", file.name, file.mtime]];
    }

    UIImage *thumb = [SeafCacheManager.sharedManager getThumbFromCache:thumbpath];
    if (thumb) {
        return thumb;
    }
    
    if (thumbpath && [Utils fileExistsAtPath:thumbpath]) {
        thumb = [UIImage imageWithContentsOfFile:thumbpath];
        if (thumb) {
            [SeafCacheManager.sharedManager saveThumbToCache:thumb key:thumbpath];
        }
    }
    return thumb;
}

- (NSString *)thumbPath:(NSString *)objId sFile:(SeafFile *)sFile {
    if (!sFile.oid) return nil;
    int size = THUMB_SIZE * (int)[[UIScreen mainScreen] scale];
    return [SeafStorage.sharedObject.thumbsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@-%d", objId, size]];
}


@end
