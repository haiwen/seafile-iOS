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

// Tunables for the thumbnail failure policy. The backoff is short on purpose:
// thumbnail-server keeps generating after it answered 503 (queue full) or timed
// out, so the next request a few seconds later usually finds the thumb ready.
// A cell only re-requests when it is configured again, so a long backoff showed
// as thumbs that never load on a page the user stopped on.
static const NSInteger kSeafThumbMaxServerFailures = 5;   // give up after this many counted failures
static const NSTimeInterval kSeafThumbRetryBackoff = 5.0; // min seconds between retries after any failure
static const NSUInteger kSeafThumbFailRecordCountLimit = 200;

@interface SeafThumbFailRecord : NSObject
@property (nonatomic, assign) NSInteger serverFailures;   // counted failures: 400, 500 and other 5xx, non-image body
@property (nonatomic, assign) NSTimeInterval lastFailure; // time of last failure of any kind (referenceDate)
@property (nonatomic, assign) BOOL permanent;             // 401/403/404/415...: definitively not thumbnailable
@end
@implementation SeafThumbFailRecord
@end

// Negative cache for failed thumbnail downloads (keyed by repo+path+oid+mtime+size).
// Prevents infinite re-enqueue when the server keeps failing and the UI refreshes.
static NSCache<NSString *, SeafThumbFailRecord *> *SeafThumbFailRecords(void) {
    static NSCache<NSString *, SeafThumbFailRecord *> *records;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        records = [[NSCache alloc] init];
        records.countLimit = kSeafThumbFailRecordCountLimit;
    });
    return records;
}

static NSString *SeafThumbFailKeyForFile(SeafFile *file) {
    NSString *oid = file.oid.length ? file.oid : @"noid";
    return [NSString stringWithFormat:@"%@|%@|%@|%lld|%d",
            file.repoId ?: @"",
            file.path ?: @"",
            oid,
            file.mtime,
            SEAF_THUMB_PIXEL_SIZE];
}

// On-disk names carry the pixel size, so changing SEAF_THUMB_PIXEL_SIZE retires
// every cached thumb instead of serving old files at the wrong size. Earlier
// builds named files `{oid}-{256*scale}` / `{name}-{mtime}`; those are left to
// the cache cleanup in SeafStorage.
static NSString *SeafThumbCacheFileName(NSString *stem)
{
    return [NSString stringWithFormat:@"%@-%dpx", stem, SEAF_THUMB_PIXEL_SIZE];
}

static NSString *SeafThumbOidPath(NSString *oid)
{
    return [SeafStorage.sharedObject.thumbsDir stringByAppendingPathComponent:SeafThumbCacheFileName(oid)];
}

static NSString *SeafThumbMtimePath(SeafFile *file)
{
    NSString *stem = [NSString stringWithFormat:@"%@-%lld", file.name, file.mtime];
    return [SeafStorage.sharedObject.thumbsDir stringByAppendingPathComponent:SeafThumbCacheFileName(stem)];
}

// Types only thumbnail-server can render need a gate, or every request on a
// server without it ends in 400 plus a backoff cycle. For video and sdoc the
// directory listing is the signal: Seahub lists their thumbnail source exactly
// when thumbnail-server is enabled, so "" (listed none) skips the request and nil
// (search results, old caches) keeps it. xmind is never listed at all, so it goes
// by the ping probe. Images, pdf, epub are never gated: Seahub renders those
// itself, and without thumbnail-server their source is listed only once the thumb
// exists, which says nothing about support.
static BOOL SeafServerCannotThumbFile(SeafFile *file)
{
    NSString *name = file.name;
    if ([Utils isXmindFile:name]) {
        return !file.connection.isThumbnailServerAvailable;
    }
    if ([Utils isServerThumbVideoFile:name] || [Utils isSdocFile:name]) {
        NSString *src = file.thumbnailURLStr;
        return src != nil && src.length == 0;
    }
    return NO;
}

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

- (void)markThumbDownloadPermanentlyFailedForFile:(SeafFile *)file
{
    if (!file) return;
    NSString *key = SeafThumbFailKeyForFile(file);
    NSCache<NSString *, SeafThumbFailRecord *> *records = SeafThumbFailRecords();
    SeafThumbFailRecord *record = [records objectForKey:key] ?: [SeafThumbFailRecord new];
    record.permanent = YES;
    [records setObject:record forKey:key];
}

- (void)markThumbDownloadTransientlyFailedForFile:(SeafFile *)file
{
    if (!file) return;
    NSString *key = SeafThumbFailKeyForFile(file);
    NSCache<NSString *, SeafThumbFailRecord *> *records = SeafThumbFailRecords();
    SeafThumbFailRecord *record = [records objectForKey:key] ?: [SeafThumbFailRecord new];
    record.serverFailures += 1;
    record.lastFailure = [NSDate timeIntervalSinceReferenceDate];
    [records setObject:record forKey:key];
}

- (void)markThumbDownloadBusyForFile:(SeafFile *)file
{
    if (!file) return;
    NSString *key = SeafThumbFailKeyForFile(file);
    NSCache<NSString *, SeafThumbFailRecord *> *records = SeafThumbFailRecords();
    SeafThumbFailRecord *record = [records objectForKey:key] ?: [SeafThumbFailRecord new];
    // Backoff only. Not counted: a busy server is not evidence that this file
    // cannot be thumbnailed, and counting it exhausted the cap during bursts.
    record.lastFailure = [NSDate timeIntervalSinceReferenceDate];
    [records setObject:record forKey:key];
}

- (void)clearThumbDownloadFailedForFile:(SeafFile *)file
{
    if (!file) return;
    NSString *key = SeafThumbFailKeyForFile(file);
    [SeafThumbFailRecords() removeObjectForKey:key];
}

- (BOOL)shouldSkipThumbDownloadForFile:(SeafFile *)file
{
    if (!file) return NO;
    NSString *key = SeafThumbFailKeyForFile(file);
    SeafThumbFailRecord *record = [SeafThumbFailRecords() objectForKey:key];
    if (!record) return NO;
    if (record.permanent) return YES;                                    // never retry this version
    if (record.serverFailures >= kSeafThumbMaxServerFailures) return YES; // gave up after repeated counted failures
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - record.lastFailure;
    return elapsed < kSeafThumbRetryBackoff;                             // within backoff window: skip for now
}

/// Return icon: if it's an image/video/PDF, try to get the thumbnail, otherwise return the default icon
- (UIImage *_Nullable)iconForFile:(SeafFile *)file
{
    if (!file.oid) {
        NSString *cacheOid = [[SeafRealmManager shared] getOidForUniKey:file.uniqueKey serverMtime:file.mtime];
        if (cacheOid && cacheOid.length > 0) {
            file.oid = cacheOid;
        }
    }
    if ([Utils isServerThumbFile:file.name]) {
        if (![file.connection isEncrypted:file.repoId]) {
            if (!file.isDeleted) {
                UIImage *img = [self thumbForFile:file];
                if (img) {
                    return img;
                }
                else if ([self shouldSkipThumbDownloadForFile:file]) {
                    return nil;
                }
                else if (SeafServerCannotThumbFile(file)) {
                    return nil;
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
    NSString *thumbpath = [self thumbCachePathForFile:file];

    UIImage *thumb = [SeafCacheManager.sharedManager getThumbFromCache:thumbpath];
    if (thumb) {
        return thumb;
    }
    
    if (thumbpath && [Utils fileExistsAtPath:thumbpath]) {
        // Memory cache miss: load for display without storing an undecoded JPEG.
        // Warm the cache off the main thread so the next access is hitch-free.
        thumb = [UIImage imageWithContentsOfFile:thumbpath];
        if (thumb) {
            [[SeafCacheManager sharedManager] warmThumbCacheInBackgroundAtPath:thumbpath];
        } else {
            Debug(@"Thumbnail at path %@ is corrupted or invalid, deleting it.", thumbpath);
            NSError *error = nil;
            if (![[NSFileManager defaultManager] removeItemAtPath:thumbpath error:&error]) {
                Debug(@"Failed to delete corrupted thumbnail at path %@: %@", thumbpath, error);
            }
        }
    }
    return thumb;
}

- (NSString *)thumbPath:(NSString *)objId sFile:(SeafFile *)sFile {
    if (!sFile.oid || !objId) return nil;
    return SeafThumbOidPath(objId);
}

- (NSString *)thumbCachePathForFile:(SeafFile *)file {
    return file.oid.length ? SeafThumbOidPath(file.oid) : SeafThumbMtimePath(file);
}

- (UIImage *)loadDecryptedImageForFile:(SeafFile *)file {
    if (!file.oid) return nil;
    
    // Get the full path for cached file
    NSString *cachedPath = [SeafStorage.sharedObject documentPath:file.oid];
    
    NSString *mtimePath = SeafThumbMtimePath(file);
    
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
                NSString *mtimePath = SeafThumbMtimePath(sFile);
                    
                // Only proceed if thumbnails don't exist in both paths
                if ((!oidPath || ![Utils fileExistsAtPath:oidPath]) &&
                    ![Utils fileExistsAtPath:mtimePath]) {
                    
                    // First load the original image
                    UIImage *originalImage = [self loadDecryptedImageForFile:sFile];
                    if (!originalImage) {
                        Debug("Failed to load original image");
                        return;
                    }
                    
                    // Calculate thumbnail size while maintaining aspect ratio.
                    // targetSize is in pixels: the context below is created at
                    // scale 1.0, so the long side comes out at SEAF_THUMB_PIXEL_SIZE,
                    // the same as a server thumb.
                    CGFloat maxSize = SEAF_THUMB_PIXEL_SIZE;
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
                    UIGraphicsBeginImageContextWithOptions(targetSize, NO, 1.0);
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
                            UIImage *decoded = [Utils decodedImageWithImage:thumbnailImage] ?: thumbnailImage;
                            [self saveThumbToCache:decoded key:oidPath ?: mtimePath];
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
