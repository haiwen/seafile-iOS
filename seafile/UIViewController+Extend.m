//
//  UIViewController+AlertMessage.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

@import LocalAuthentication;

#ifdef SEAFILE_APP
#import "SVProgressHUD.h"
#endif
#import "AFNetworking.h"
#import "UIViewController+Extend.h"
#import "Utils.h"
#import "Debug.h"


@implementation UIViewController (Extend)


- (id)initWithAutoNibName
{
    return [self initWithNibName:(NSStringFromClass ([self class])) bundle:nil];
}

- (id)initWithAutoPlatformNibName
{
    NSString* className = NSStringFromClass ([self class]);
    NSString* plaformSuffix;
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        plaformSuffix = @"iPhone";
    } else {
        plaformSuffix = @"iPad";
    }
    return [self initWithNibName:[NSString stringWithFormat:@"%@_%@", className, plaformSuffix] bundle:nil];
}

- (id)initWithAutoPlatformLangNibName:(NSString *)lang
{
    NSString* className = NSStringFromClass ([self class]);
    NSString* plaformSuffix;
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        plaformSuffix = @"iPhone";
    } else {
        plaformSuffix = @"iPad";
    }
    return [self initWithNibName:[NSString stringWithFormat:@"%@_%@_%@", className, plaformSuffix, lang] bundle:nil];
}

- (void)alertWithTitle:(NSString*)title message:(NSString*)message handler:(void (^)())handler;
{
    [Utils alertWithTitle:title message:message handler:handler from:self];
}

- (void)alertWithTitle:(NSString*)title message:(NSString*)message
{
    [self alertWithTitle:title message:message handler:nil];
}

- (void)alertWithTitle:(NSString*)title
{
    [self alertWithTitle:title message:nil];
}

- (void)alertWithTitle:(NSString*)title handler:(void (^)())handler
{
    [self alertWithTitle:title message:nil handler:handler];
}


- (void)alertWithTitle:(NSString *)title message:(NSString*)message yes:(void (^)())yes no:(void (^)())no
{
    [Utils alertWithTitle:title message:message yes:yes no:no from:self];
}

- (void)popupInputView:(NSString *)title placeholder:(NSString *)tip secure:(BOOL)secure handler:(void (^)(NSString *input))handler
{
    [Utils popupInputView:title placeholder:tip secure:secure handler:handler from:self];
}

- (UIBarButtonItem *)getBarItem:(NSString *)imageName action:(SEL)action size:(float)size;
{
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0,0,size,size);
    UIImage *img = [UIImage imageNamed:imageName];
    [btn setImage:img forState:UIControlStateNormal];
    btn.showsTouchWhenHighlighted = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:btn];
    return item;
}

- (UIBarButtonItem *)getBarItemAutoSize:(NSString *)imageName action:(SEL)action
{
    return [self getBarItem:imageName action:action size:22];
}

- (UIBarButtonItem *)getSpaceBarItem:(float)width
{
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:self action:nil];
    space.width = width;
    return space;
}

- (BOOL)isVisible
{
    return [self isViewLoaded] && self.view.window;
}

- (void)popupSetRepoPassword:(SeafRepo *)repo handler:(void (^)())handler
{
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"Password of library '%@'", @"Seafile"), repo.name];
    [self popupInputView:title placeholder:nil secure:true handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Password must not be empty", @"Seafile")handler:^{
                [self popupSetRepoPassword:repo handler:handler];
            }];
            return;
        }
        if (input.length < 3 || input.length  > 100) {
            [self alertWithTitle:NSLocalizedString(@"The length of password should be between 3 and 100", @"Seafile") handler:^{
                [self popupSetRepoPassword:repo handler:handler];
            }];
            return;
        }
#ifdef SEAFILE_APP
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Checking library password ...", @"Seafile")];
#endif
        [repo checkOrSetRepoPassword:input block:^(SeafBase *entry, int ret) {
            if (ret == RET_SUCCESS) {
#ifdef SEAFILE_APP
                [SVProgressHUD dismiss];
#endif
                handler();
            } else {
#ifdef SEAFILE_APP
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Wrong library password", @"Seafile")];
#endif
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self popupSetRepoPassword:repo handler:handler];
                });
            }
        }];
    }];
}

#define STR_15 NSLocalizedString(@"Your device cannot authenticate using Touch ID.", @"Seafile")
#define STR_16 NSLocalizedString(@"There was a problem verifying your identity.", @"Seafile")
#define STR_17 NSLocalizedString(@"Please authenticate to proceed", @"Seafile")
#define STR_18 NSLocalizedString(@"Failed to authenticate", @"Seafile")

- (void)checkTouchId:(void (^)(bool success))handler
{
    NSError *error = nil;
    LAContext *context = [[LAContext alloc] init];
    if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
        Warning("TouchID unavailable: %@", error);
        [self alertWithTitle:STR_15];
        return handler(false);
    }

    [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
            localizedReason:STR_17
                      reply:^(BOOL success, NSError *error) {
                          if (error && error.code == LAErrorUserCancel) {
                              Debug("Canceld by user.");
                              return;
                          }
                          if (success)
                              return handler(true);

                          if (error && error.code == LAErrorAuthenticationFailed) {
                              Warning("Failed to evaluate TouchID: %@", error);
                              [self alertWithTitle:STR_18];
                              return handler(false);
                          }

                          Warning("Failed to evaluate TouchID: %@", error);
                          [self alertWithTitle:STR_16];
                          return handler(false);
                      }];
}

- (UIAlertController *)generateAlert:(NSArray *)arr withTitle:(NSString *)title handler:(void (^ __nullable)(UIAlertAction *action))handler
{
    UIAlertController *alert = [Utils generateAlert:arr withTitle:title handler:handler cancelHandler:nil preferredStyle:UIAlertControllerStyleActionSheet];
    alert.popoverPresentationController.sourceView = self.view;
    if (IsIpad()) {
        [alert.view layoutIfNeeded];
    }
    return alert;
}

- (BOOL)checkNetworkStatus
{
    Debug("network status=%@\n", [[AFNetworkReachabilityManager sharedManager] localizedNetworkReachabilityStatusString]);
    if (![[AFNetworkReachabilityManager sharedManager] isReachable]) {
        [Utils alertWithTitle:NSLocalizedString(@"Network unavailable", @"Seafile") message:nil handler:nil from:self];
        return NO;
    }
    return YES;
}

@end
