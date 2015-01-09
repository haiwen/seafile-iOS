//
//  UIViewController+alertMessage.h
//  seafile
//
//  Created by Wang Wei on 10/4/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIViewController (Extend)<UIAlertViewDelegate>
@property void (^handler_ok)();
@property void (^handler_cancel)();
@property void (^handler_input)(NSString *input);

- (id)initWithAutoNibName;
- (id)initWithAutoPlatformNibName;
- (id)initWithAutoPlatformLangNibName:(NSString *)lang;

- (void)alertWithTitle:(NSString*)title;
- (void)alertWithTitle:(NSString*)title message:(NSString*)message;
- (void)alertWithTitle:(NSString*)title handler:(void (^)())handler;
- (void)alertWithTitle:(NSString *)title message:(NSString*)message yes:(void (^)())yes no:(void (^)())no;

- (void)popupInputView:(NSString *)title placeholder:(NSString *)tip secure:(BOOL)secure handler:(void (^)(NSString *input))handler;

- (UIBarButtonItem *)getBarItem:(NSString *)imageName action:(SEL)action size:(float)size;

- (UIBarButtonItem *)getBarItemAutoSize:(NSString *)imageName action:(SEL)action;
- (UIBarButtonItem *)getSpaceBarItem:(float)width;

- (BOOL)isVisible;

@end
