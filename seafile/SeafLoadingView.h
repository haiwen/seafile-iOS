//
//  SeafLoadingView.h
//  seafilePro
//
//  Created by henry on 2025/3/31.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafLoadingView : UIView

+ (instancetype)loadingViewWithParentView:(UIView *)parentView;
- (void)showInView:(UIView *)view;
- (void)dismiss;
- (void)updatePosition;

@end

NS_ASSUME_NONNULL_END 
