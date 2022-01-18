//
//  APLRUCache.h
//  APLRUCache
//
//  Created by Jason Kaer on 15/7/11.
//  Copyright (c) 2015年 Jason Kaer. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface APLRUCache : NSObject

/**
 *  Capacity of cache.(Total Count of objects to be cached.)
 */
@property (nonatomic, readonly, assign) NSUInteger capacity;

/**
 *  The current count of objects in cache.
 */
@property (nonatomic, readonly, assign) NSUInteger length;


- (instancetype)initWithCapacity:(NSUInteger)capacity  NS_DESIGNATED_INITIALIZER ;

- (id)cachedObjectForKey:(NSString *)key;

- (void)cacheObject:(id)object forKey:(NSString *)key;

- (void)removeObjectForKey:(NSString *)key;
@end
