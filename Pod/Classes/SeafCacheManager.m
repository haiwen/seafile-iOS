//
//  SeafMemoryCacheManager.m
//  Seafile
//
//  Created by threezhao on 2024/9/17.
//

#import "SeafCacheManager.h"

#define DEFAULT_TotalCostLimit 20*1024*1024
#define DEFAULT_CountLimit 100

@interface SeafCacheManager ()

@property (nonatomic, strong) NSCache *thumbMemoryCache;

@end

@implementation SeafCacheManager

+ (SeafCacheManager *)sharedManager {
    static SeafCacheManager *object = nil;
    if (!object) {
        object = [[SeafCacheManager alloc] init];
    }
    return object;
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

@end
