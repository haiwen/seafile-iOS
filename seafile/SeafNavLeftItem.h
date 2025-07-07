//
//  SeafNavLeftItem.h
//  seafileApp
//
//  Created by henry on 2025/3/24.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>

@class SeafDir;

NS_ASSUME_NONNULL_BEGIN

@interface SeafNavLeftItem : UIView

+ (instancetype)navLeftItemWithDirectory:(nullable SeafDir *)directory title:(nullable NSString *)title target:(id)target action:(SEL)action;

@end

NS_ASSUME_NONNULL_END
