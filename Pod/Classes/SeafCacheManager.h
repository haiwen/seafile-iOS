//
//  SeafMemoryCacheManager.h
//  Seafile
//
//  Created by threezhao on 2024/9/17.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafCacheManager : NSObject

+ (SeafCacheManager *)sharedManager;

- (void)saveThumbToCache:(UIImage *)image key:(NSString *)key;

- (UIImage *)getThumbFromCache:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
