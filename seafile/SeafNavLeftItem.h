//
//  SeafNavLeftItem.h
//  seafileApp
//
//  Created by henry on 2025/3/24.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>

@class SeafDir;

@interface SeafNavLeftItem : UIView

+ (instancetype)navLeftItemWithDirectory:(SeafDir *)directory target:(id)target action:(SEL)action;

@end
