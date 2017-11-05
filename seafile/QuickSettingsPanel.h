//
//  SettingsBlock.h
//  SettingsAnimation
//
//  Created by Max on 30/09/2017.
//  Copyright © 2017 34x. All rights reserved.
//

#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString* const QuickSettingsFontSizeIncrement;
FOUNDATION_EXPORT NSString* const QuickSettingsFontSizeDecrement;

@interface QuickSettingsPanel : UIView
@property(nonatomic, copy) void(^actionHandler)(NSString* actionKey, NSDictionary* userInfo);
- (void)setOpen:(BOOL)isOpen animate:(BOOL)animate;
@end
