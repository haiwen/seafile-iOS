//
//  SeafFileProviderUtility.h
//  SeafFileProvider
//
//  Created by three on 2022/8/8.
//  Copyright © 2022 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
@class SeafProviderItem;

NS_ASSUME_NONNULL_BEGIN

@interface SeafFileProviderUtility : NSObject

@property (nonatomic, assign) NSInteger currentAnchor;

+(instancetype)shared;

- (void)saveUpdateItem:(SeafProviderItem *)item;

- (NSArray *)allUpdateItems;

- (void)removeAllUpdateItems;

@end

NS_ASSUME_NONNULL_END
