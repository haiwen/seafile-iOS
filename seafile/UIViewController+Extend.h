//
//  UIViewController+alertMessage.h
//  seafile
//
//  Created by Wang Wei on 10/4/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIViewController (Extend)

- (id)initWithAutoNibName;
- (id)initWithAutoPlatformNibName;
- (id)initWithAutoPlatformLangNibName:(NSString *)lang;

- (void)alertWithMessage:(NSString*)message;
- (void)alertWithMessage:(NSString*)message handler:(void (^)())handler;
- (void)alertWithMessage:(NSString*)message yes:(void (^)())yes no:(void (^)())no;

- (void)popupInputView:(NSString *)title placeholder:(NSString *)tip handler:(void (^)(NSString *input))handler;

- (UIBarButtonItem *)getBarItem:(NSString *)imageName action:(SEL)action size:(float)size;

- (UIBarButtonItem *)getBarItemAutoSize:(NSString *)imageName action:(SEL)action;
- (UIBarButtonItem *)getSpaceBarItem:(float)width;

- (BOOL)isVisible;

@end
