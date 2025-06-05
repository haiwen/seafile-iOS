//
//  SeafErrorPlaceholderView.h
//  seafileApp
//
//  Created by Henry on 2025/06/05.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafErrorPlaceholderView : UIView

/// A block to be executed when the user taps the view to retry an action.
@property (nonatomic, copy, nullable) void (^retryActionBlock)(void);

/// You can add a method to configure the text if it needs to be dynamic,
/// for now, it will use the fixed "Load failed, tap to retry".
// - (void)setMessage:(NSString *)message;

@end

NS_ASSUME_NONNULL_END 
