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

/// Caps the title so trailing bar buttons stay inside the horizontal safe area.
/// `reservedTrailingWidth` is the trailing cluster plus the gap in front of it.
/// Returns YES when the frame changes.
- (BOOL)applyContainerWidth:(CGFloat)containerWidth
                  safeInsets:(UIEdgeInsets)safeInsets
       reservedTrailingWidth:(CGFloat)reservedTrailingWidth;

/// Caps the title at `maximumWidth` points. Short titles stay at their text width.
/// Returns YES when the frame changes.
- (BOOL)applyMaximumWidth:(CGFloat)maximumWidth;

@end

NS_ASSUME_NONNULL_END
