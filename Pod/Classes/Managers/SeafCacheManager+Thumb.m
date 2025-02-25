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

// Check if it is an image type
- (BOOL)isImageFile:(SeafFile *)file
{
    return [Utils isImageFile:file.name];
}

// Check if it is a video type
- (BOOL)isVideoFile:(SeafFile *)file
{
    return [Utils isVideoFile:file.name];
}

/// Return icon: if it's an image/video, try to get the thumbnail, otherwise return the default icon
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
        } else if ([file.connection isDecrypted:file.repoId]) {
            Debug("file has decrypted");
            UIImage *img = [self thumbForFile:file];
            if (img) {
                return img;
            }
        } else {
            return nil;
        }
    }
    return nil;
}

/// Cancel thumbnail download or generation
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

- (UIImage *)loadDecryptedImageForFile:(SeafFile *)file {
    if (!file.oid) return nil;
    
    // Get the full path for cached file
    NSString *cachedPath = [SeafStorage.sharedObject documentPath:file.oid];
    
    NSString *mtimePath = [SeafStorage.sharedObject.thumbsDir
        stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@-%lld",
                                        file.name, file.mtime]];
    
    // Check if file exists in cache
    if ([Utils fileExistsAtPath:cachedPath]) {
        UIImage *image = [UIImage imageWithContentsOfFile:cachedPath];
        return image;
    } else if ([Utils fileExistsAtPath:mtimePath]) {
        UIImage *image = [UIImage imageWithContentsOfFile:mtimePath];
        return image;
    }
    
    return nil;
}

- (void)saveThumbFromEncrypetedFile:(SeafFile *)seafFile {
    if ([seafFile isKindOfClass:[SeafFile class]] && [seafFile isImageFile]) {
        SeafFile *sFile = (SeafFile *)seafFile;
        if ([sFile.connection isEncrypted:sFile.repoId] && [sFile.connection isDecrypted:sFile.repoId]) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                
                // Check if thumbnail already exists
                NSString *oidPath = sFile.oid ? [sFile thumbPath:sFile.oid] : nil;
                NSString *mtimePath = [SeafStorage.sharedObject.thumbsDir
                    stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@-%lld",
                    sFile.name, sFile.mtime]];
                    
                // Only proceed if thumbnails don't exist in both paths
                if ((!oidPath || ![Utils fileExistsAtPath:oidPath]) &&
                    ![Utils fileExistsAtPath:mtimePath]) {
                    
                    // First load the original image
                    UIImage *originalImage = [self loadDecryptedImageForFile:sFile];
                    if (!originalImage) {
                        Debug("Failed to load original image");
                        return;
                    }
                    
                    // Calculate thumbnail size while maintaining aspect ratio
                    CGFloat scale = [UIScreen mainScreen].scale;
                    CGFloat maxSize = THUMB_SIZE * scale;
                    CGSize originalSize = originalImage.size;
                    CGSize targetSize;
                    
                    if (originalSize.width > originalSize.height) {
                        CGFloat ratio = originalSize.height / originalSize.width;
                        targetSize = CGSizeMake(maxSize, maxSize * ratio);
                    } else {
                        CGFloat ratio = originalSize.width / originalSize.height;
                        targetSize = CGSizeMake(maxSize * ratio, maxSize);
                    }
                    
                    // Create thumbnail
                    UIGraphicsBeginImageContextWithOptions(targetSize, NO, scale);
                    [originalImage drawInRect:CGRectMake(0, 0, targetSize.width, targetSize.height)];
                    UIImage *thumbnailImage = UIGraphicsGetImageFromCurrentImageContext();
                    UIGraphicsEndImageContext();
                    
                    // Save to both paths
                    NSData *imageData = UIImageJPEGRepresentation(thumbnailImage, 0.7);
                    if (imageData) {
                        if (oidPath) {
                            [imageData writeToFile:oidPath atomically:YES];
                        }
                        [imageData writeToFile:mtimePath atomically:YES];
                        
                        if (thumbnailImage) {
                            [self saveThumbToCache:thumbnailImage key:oidPath ?: mtimePath];
                        }
                        Debug("Thumbnail saved successfully");
                        [sFile finishDownloadThumb:YES];
                    }
                }
            });
        }
    }
}

@end
