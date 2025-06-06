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

- (void)alertWithTitle:(NSString*)title message:(NSString*)message handler:(void (^)(void))handler;
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

- (void)alertWithTitle:(NSString*)title handler:(void (^)(void))handler
{
    [self alertWithTitle:title message:nil handler:handler];
}


- (void)alertWithTitle:(NSString *)title message:(NSString*)message yes:(void (^)(void))yes no:(void (^)(void))no
{
    [Utils alertWithTitle:title message:message yes:yes no:no from:self];
}

- (void)popupInputView:(NSString *)title placeholder:(NSString *)tip inputs:(NSString *)inputs secure:(BOOL)secure handler:(void (^)(NSString *input))handler {
    [Utils popupInputView:title placeholder:tip inputs:inputs secure:secure handler:handler from:self];
}

- (void)popupInputView:(NSString *)title placeholder:(NSString *)tip secure:(BOOL)secure handler:(void (^)(NSString *input))handler {
    [Utils popupInputView:title placeholder:tip inputs:nil secure:secure handler:handler from:self];
}

- (void)popupTwoStepVerificationViewHandler:(void (^)(NSString *input,BOOL remember))handler {
    NSString *placeHolder = NSLocalizedString(@"Two step verification code", @"Seafile");;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:placeHolder message:nil preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:STR_CANCEL style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    }];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *input = [[alert.textFields objectAtIndex:0] text];
        if (handler)
            handler(input,false);
    }];
    
    UIAlertAction *rememberAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK and Remember Device", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *input = [[alert.textFields objectAtIndex:0] text];
        if (handler)
            handler(input,true);
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = placeHolder;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.secureTextEntry = true;
    }];
    
    [alert addAction:rememberAction];
    [alert addAction:cancelAction];
    [alert addAction:okAction];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:true completion:nil];
    });
}

- (UIBarButtonItem *)getBarItem:(NSString *)imageName action:(SEL)action size:(float)size;
{
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0,0,size,size);
    UIImage *img = [UIImage imageNamed:imageName];
    
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    [img drawInRect:CGRectMake(0, 0, size, size)];
    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    [btn setImage:resizedImage forState:UIControlStateNormal];
    btn.showsTouchWhenHighlighted = YES;
    btn.clipsToBounds = true;
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

// Action method for the password visibility toggle button in alerts
- (void)alertTextFieldToggleVisibility:(UIButton *)sender {
    // Try to find the UIAlertController.
    // If 'self' is presenting it, self.presentedViewController should be it.
    if ([self.presentedViewController isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alertController = (UIAlertController *)self.presentedViewController;
        if (alertController.textFields.count > 0) {
            UITextField *textField = alertController.textFields.firstObject;
            textField.secureTextEntry = !textField.secureTextEntry;
            sender.selected = !textField.secureTextEntry; // true if text is NOT secure (visible)
        }
    }
}

- (void)popupSetRepoPassword:(SeafRepo *)repo handler:(void (^)(void))handler
{
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"Password of library '%@'", @"Seafile"), repo.name];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = NSLocalizedString(@"Password", @"Password Placeholder");
        textField.secureTextEntry = YES;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;

        UIButton *visibilityButton = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImage *eyeSlashImage = [UIImage imageNamed:@"icon_eye_close"]; // Password hidden state
        UIImage *eyeImage = [UIImage imageNamed:@"icon_eye_open"];       // Password visible state
        [visibilityButton setImage:eyeSlashImage forState:UIControlStateNormal];
        [visibilityButton setImage:eyeImage forState:UIControlStateSelected];
        
        visibilityButton.frame = CGRectMake(0, 0, 30, 30); // Consistent with SeafMkLibAlertController
        visibilityButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        visibilityButton.tintColor = [UIColor grayColor]; // A common tint color for such icons
        
        // Add target to the UIViewController instance (self)
        [visibilityButton addTarget:self action:@selector(alertTextFieldToggleVisibility:) forControlEvents:UIControlEventTouchUpInside];

        textField.rightView = visibilityButton;
        textField.rightViewMode = UITextFieldViewModeAlways;
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel button title")
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK button title")
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
        UITextField *passwordField = alert.textFields.firstObject;
        NSString *input = passwordField.text;

        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Password must not be empty", @"Seafile")handler:^{
                // Retry by calling the method again
                [self popupSetRepoPassword:repo handler:handler];
            }];
            return;
        }
        // Using existing length validation from the original method
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
                if (handler) { // Ensure handler is not nil before calling
                    handler();
                }
            } else {
#ifdef SEAFILE_APP
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Wrong library password", @"Seafile")];
#endif
                // Add a slight delay before retrying to allow SVProgressHUD to be seen
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self popupSetRepoPassword:repo handler:handler];
                });
            }
        }];
    }];

    [alert addAction:cancelAction];
    [alert addAction:okAction];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

#define STR_15 NSLocalizedString(@"Your device cannot authenticate using Touch ID.", @"Seafile")
#define STR_16 NSLocalizedString(@"There was a problem verifying your identity.", @"Seafile")
#define STR_17 NSLocalizedString(@"Please authenticate to proceed", @"Seafile")
#define STR_18 NSLocalizedString(@"Failed to authenticate", @"Seafile")
#define STR_19 NSLocalizedString(@"Your device cannot authenticate using Face ID.", @"Seafile")

- (void)checkTouchId:(void (^)(bool success))handler
{
    NSError *error = nil;
    LAContext *context = [[LAContext alloc] init];
    if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
        Warning("TouchID unavailable: %@", error);
        if (@available(iOS 11.0, *)) {
            if (context.biometryType == LABiometryTypeFaceID) {
                [self alertWithTitle:STR_19];
            } else {
                [self alertWithTitle:STR_15];
            }
        } else {
            [self alertWithTitle:STR_15];
        }
        
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

- (void)checkPhotoLibraryAuth:(void (^)(void))handler {
    if ([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusRestricted || [PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusDenied) {
        return [self alertWithTitle:NSLocalizedString(@"This app does not have access to your photos and videos.", @"Seafile") message:NSLocalizedString(@"You can enable access in Privacy Settings", @"Seafile")];
    }
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status == PHAuthorizationStatusAuthorized) {
            if (handler) {
                handler();
            }
        } else {
            [self alertWithTitle:NSLocalizedString(@"This app does not have access to your photos and videos.", @"Seafile") message:NSLocalizedString(@"You can enable access in Privacy Settings", @"Seafile")];
        }
    }];
}

@end
