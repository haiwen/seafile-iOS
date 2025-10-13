//
//  SeafMemoryCacheManager.m
//  Seafile
//
//  Created by threezhao on 2024/9/17.
//

#import "SeafCacheManager.h"
#import "SeafRealmManager.h"
#import "SeafStorage.h"
#import "SeafFile.h"
#import <CommonCrypto/CommonDigest.h>

#define DEFAULT_TotalCostLimit 20*1024*1024
#define DEFAULT_CountLimit 100

@interface SeafCacheManager ()

@property (nonatomic, strong) NSCache *thumbMemoryCache;
@property (nonatomic, strong) NSCache *imageMemoryCache;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;
@property (nonatomic, copy) NSString *fileCachePath;
@property (nonatomic, copy) NSString *thumbDiskCachePath;
@property (nonatomic, copy) NSString *imageDiskCachePath; // URL 图片磁盘缓存目录

@end

@implementation SeafCacheManager

+ (SeafCacheManager *)sharedManager {
    static SeafCacheManager *object = nil;
    if (!object) {
        object = [[SeafCacheManager alloc] init];
    }
    return object;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cacheQueue = dispatch_queue_create("com.seafile.cacheQueue", DISPATCH_QUEUE_SERIAL);
        // 初始化 URL 图片缓存目录（沿用评论缓存目录名称以复用已有数据）
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *base = (paths.count > 0) ? paths.firstObject : NSTemporaryDirectory();
        _imageDiskCachePath = [base stringByAppendingPathComponent:@"SeafCommentImageCache"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_imageDiskCachePath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return self;
}

- (void)saveThumbToCache:(UIImage *)image key:(NSString *)key {
    if (!image || !key || key.length == 0) {
        return;
    }
    NSUInteger cost = [self costForImage:image];
    if (cost > 0) {
        [self.thumbMemoryCache setObject:image forKey:key cost:cost];
    }
}

- (UIImage *)getThumbFromCache:(NSString *)key {
    if (!key || key.length == 0) {
        return nil;
    }
    return [self.thumbMemoryCache objectForKey:key];
}

- (NSUInteger)costForImage:(UIImage *)image {
    CGImageRef imageRef = image.CGImage;
    if (!imageRef) {
        return 0;
    }
    NSUInteger bytesPerFrame = CGImageGetBytesPerRow(imageRef) * CGImageGetHeight(imageRef);
    NSUInteger frameCount = image.images.count > 1 ? [NSSet setWithArray:image.images].count : 1;
    NSUInteger cost = bytesPerFrame * frameCount;
    return cost;
}

- (NSCache *)thumbMemoryCache {
    if (!_thumbMemoryCache) {
        _thumbMemoryCache = [[NSCache alloc] init];
        _thumbMemoryCache.totalCostLimit = DEFAULT_TotalCostLimit;
        _thumbMemoryCache.countLimit = DEFAULT_CountLimit;
        _thumbMemoryCache.evictsObjectsWithDiscardedContent = YES;
    }
    return _thumbMemoryCache;
}

#pragma mark - URL Image Cache

static NSString *sha1String(NSString *s)
{
    if (!s) return @"";
    const char *cstr = [s UTF8String];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(cstr, (CC_LONG)strlen(cstr), digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [out appendFormat:@"%02x", digest[i]];
    }
    return out;
}

- (NSCache *)imageMemoryCache {
    if (!_imageMemoryCache) {
        _imageMemoryCache = [[NSCache alloc] init];
        _imageMemoryCache.totalCostLimit = 50 * 1024 * 1024; // 与评论页一致的约束
        _imageMemoryCache.countLimit = 200;
        _imageMemoryCache.evictsObjectsWithDiscardedContent = YES;
    }
    return _imageMemoryCache;
}

- (UIImage *)getImageForURL:(NSString *)url
{
    if (url.length == 0) return nil;
    UIImage *mem = [self.imageMemoryCache objectForKey:url];
    if (mem) return mem;
    NSString *file = [[self.imageDiskCachePath stringByAppendingPathComponent:sha1String(url)] stringByAppendingPathExtension:@"img"];
    NSData *data = [NSData dataWithContentsOfFile:file];
    if (!data) return nil;
    UIImage *img = [UIImage imageWithData:data];
    if (img) {
        // 估算内存消耗
        NSUInteger cost = 0;
        CGImageRef imageRef = img.CGImage;
        if (imageRef) {
            cost = CGImageGetBytesPerRow(imageRef) * CGImageGetHeight(imageRef);
        } else {
            cost = (NSUInteger)(img.size.width * img.size.height * MAX(1.0, img.scale) * MAX(1.0, img.scale) * 4);
        }
        [self.imageMemoryCache setObject:img forKey:url cost:cost];
    }
    return img;
}

- (void)storeImage:(UIImage *)image forURL:(NSString *)url
{
    if (!image || url.length == 0) return;
    NSUInteger cost = 0;
    CGImageRef imageRef = image.CGImage;
    if (imageRef) {
        cost = CGImageGetBytesPerRow(imageRef) * CGImageGetHeight(imageRef);
    } else {
        cost = (NSUInteger)(image.size.width * image.size.height * MAX(1.0, image.scale) * MAX(1.0, image.scale) * 4);
    }
    [self.imageMemoryCache setObject:image forKey:url cost:cost];
    NSString *file = [[self.imageDiskCachePath stringByAppendingPathComponent:sha1String(url)] stringByAppendingPathExtension:@"img"];
    dispatch_async(self.cacheQueue, ^{
        NSData *data = UIImageJPEGRepresentation(image, 0.9);
        if (!data) data = UIImagePNGRepresentation(image);
        if (!data) return;
        [data writeToFile:file atomically:YES];
    });
}

#pragma mark - File Cache Methods

- (NSString *)getCachedPath:(NSString *)fileId {
    if (!fileId) return nil;
    NSString *path = [self.fileCachePath stringByAppendingPathComponent:fileId];
    return [[NSFileManager defaultManager] fileExistsAtPath:path] ? path : nil;
}

- (void)saveFileToCache:(NSString *)path fileId:(NSString *)fileId {
    if (!path || !fileId) return;
    
    dispatch_async(self.cacheQueue, ^{
        NSString *cachePath = [self.fileCachePath stringByAppendingPathComponent:fileId];
        NSError *error = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
            [[NSFileManager defaultManager] removeItemAtPath:cachePath error:nil];
        }
        
        BOOL success = [[NSFileManager defaultManager] copyItemAtPath:path
                                                             toPath:cachePath
                                                              error:&error];
        if (!success) {
            Debug(@"Failed to cache file: %@", error);
        }
    });
}

#pragma mark - Cache Management

- (unsigned long long)totalCacheSize {
    __block unsigned long long size = 0;
    dispatch_sync(self.cacheQueue, ^{
        NSArray *paths = @[self.fileCachePath, self.thumbDiskCachePath];
        for (NSString *path in paths) {
            NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
            for (NSString *file in files) {
                NSString *filePath = [path stringByAppendingPathComponent:file];
                NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
                size += [attrs fileSize];
            }
        }
    });
    return size;
}

- (NSString *)getCachePathForFile:(SeafFile *)file {
    if ([Utils isMainApp]) {
        return [[SeafRealmManager shared] getCachePathWithOid:file.oid
                                                      mtime:file.mtime
                                                     uniKey:file.uniqueKey];
    } else {
        return [SeafStorage.sharedObject documentPath:file.oid];
    }
}

// Check if there is a local cache
- (BOOL)fileHasCache:(SeafFile *)file
{
    // 1) If the local mpath exists and the file exists
    if (file.mpath && [[NSFileManager defaultManager] fileExistsAtPath:file.mpath]) {
        return YES;
    }
    
    // 2) If the Realm records the local cache of the corresponding oid & the file actually exists
    NSString *cachePath = [self getCachePathForFile:file];
    if (cachePath && cachePath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
        [file setOoid:file.oid];
        return YES;
    } else if (file.oid.length > 0
               && [[NSFileManager defaultManager] fileExistsAtPath:[SeafStorage.sharedObject documentPath:file.oid]]) {
        if (![file.oid isEqualToString:file.ooid]) {
            [file setOoid:file.oid];
        }
        return YES;
    }
    file.preViewURL = nil;
    file.exportURL = nil;
    // If none, there is no cache
    return NO;
}

// Load cache (original realLoadCache / loadCache logic combined)
- (BOOL)loadFileCache:(SeafFile *)file {
    // 1) Check the temporary mpath cached by connection
    NSString *cachedMpath = [file.connection objectForKey:file.cacheKey entityName:ENTITY_FILE];
    if (cachedMpath && [[NSFileManager defaultManager] fileExistsAtPath:cachedMpath]) {
        if (!file.mpath || ![file.mpath isEqualToString:cachedMpath]) {
            file.mpath = cachedMpath;
            file.preViewURL = nil;
            file.exportURL  = nil;
        }
        return YES;
    }
    
    // 2) Find the cache from Realm and confirm whether the local file exists
    NSString *cachePath = [self getCachePathForFile:file];
    if ((cachePath && cachePath.length > 0) || file.oid) {
        if (!file.oid || file.oid.length == 0) {
            // Try to update file.oid
            if ([Utils isMainApp]) {
                NSString *cacheOid = [[SeafRealmManager shared] getOidForUniKey:file.uniqueKey
                                                                    serverMtime:file.mtime];
                if (cacheOid && cacheOid.length > 0) {
                    file.oid = cacheOid;
                }
            }
        }
        NSString *docPath = [SeafStorage.sharedObject documentPath:file.oid];
        if (file.oid && [[NSFileManager defaultManager] fileExistsAtPath:docPath]) {
            if (![file.oid isEqualToString:file.ooid]) {
                [file setOoid:file.oid];
            }
            return YES;
        }
    }
    
    // If the cache cannot be found, reset file.ooid and return NO
    [file setOoid:nil];
    return NO;
}

// Save file.mpath to connection cache
- (BOOL)saveFileCache:(SeafFile *)file {
    if (!file.mpath) {
        return NO;
    }
    return [file.connection setValue:file.mpath forKey:file.cacheKey entityName:ENTITY_FILE];
}

// Remove connection cache record
- (void)clearFileCache:(SeafFile *)file {
    [file.connection removeKey:file.cacheKey entityName:ENTITY_FILE];
}

// Delete local cache file
- (void)deleteCacheForFile:(SeafFile *)file {
    // Similar to the deleteCache method in file
    file.exportURL = nil;
    file.preViewURL = nil;
    file.shareLink = nil;
    
    if (file.ooid) {
        NSString *docPath = [SeafStorage.sharedObject documentPath:file.ooid];
        [[NSFileManager defaultManager] removeItemAtPath:docPath error:nil];
        
        NSString *tempDir = [SeafStorage.sharedObject.tempDir stringByAppendingPathComponent:file.ooid];
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    }
    [Utils clearAllFiles:SeafStorage.sharedObject.blocksDir]; // If needed
    file.ooid = nil;
    file.state = SEAF_DENTRY_INIT;
}

- (BOOL)realLoadCache:(SeafFile *)file {
    NSString *cachedMpath = [file.connection objectForKey:file.cacheKey entityName:ENTITY_FILE];
    if (cachedMpath && [[NSFileManager defaultManager] fileExistsAtPath:cachedMpath]) {
        if (!file.mpath || ![file.mpath isEqualToString:cachedMpath]) {
            file.mpath = cachedMpath;
            file.preViewURL = nil;
            file.exportURL = nil;
        }
        return true;
    }
    
    NSString *cachePath = [self getCachePathForFile:file];
    if ((cachePath && cachePath.length > 0) || file.oid) {
        if (!file.oid || file.oid.length == 0) {
            NSString *cacheOid = [[SeafRealmManager shared] getOidForUniKey:file.uniqueKey serverMtime:file.mtime];
            if (cacheOid && cacheOid.length > 0) {
                file.oid = cacheOid;
            }
        }
        
        if (file.oid && [[NSFileManager defaultManager] fileExistsAtPath:[SeafStorage.sharedObject documentPath:file.oid]]) {
            if (![file.oid isEqualToString:file.ooid])
                [file setOoid:file.oid];
            return true;
        }
    }
    [file setOoid:nil];
    return false;
}

- (void)saveOidToLocalDB:(NSString *)oid seafFile:(SeafFile *)sFile connection:(SeafConnection *)conn {
    NSString *filePath = [SeafStorage.sharedObject documentPath:oid];
    NSString *uniKey = sFile.uniqueKey;
    
    SeafFileStatus *fileStatus = [[SeafFileStatus alloc] init];
    fileStatus.uniquePath = uniKey;
    fileStatus.serverOID = oid;
    fileStatus.localFilePath = filePath;
    fileStatus.localMTime = [[NSDate date] timeIntervalSince1970];
    fileStatus.accountIdentifier = conn.accountIdentifier;
    
    fileStatus.fileName = sFile.name;

    [[SeafRealmManager shared] updateFileStatus:fileStatus];
}

- (NSString *)cachePathForFile:(SeafFile *)file {
    if (file.mpath)
        return file.mpath;
    if (file.ooid)
        return [SeafStorage.sharedObject documentPath:file.ooid];
    return nil;
}

- (void)updateWithEntry:(SeafBase *)entry sFile:(SeafFile *)sFile
{
    SeafFile *file = (SeafFile *)entry;
    if ([sFile.oid isEqualToString:entry.oid]) {
        if (file.ufile) {
            sFile.ufile = file.ufile;
            sFile.ufile.delegate = sFile;
            sFile.mpath = file.mpath;
            sFile.udelegate = file.udelegate;
        }
        return;
    }
    if (sFile.oid != entry.oid) {
        sFile.oid = entry.oid;
    }
    sFile.filesize = file.filesize;
    sFile.mtime = file.mtime;
    sFile.ufile = file.ufile;
    sFile.ufile.delegate = sFile;
    sFile.mpath = file.mpath;
    sFile.udelegate = file.udelegate;
    sFile.state = SEAF_DENTRY_INIT;
    [sFile loadCache];
}

@end
