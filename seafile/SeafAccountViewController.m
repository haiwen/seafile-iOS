//
//  SeafAccountViewController.m
//  seafile
//
//  Created by Wang Wei on 1/12/13.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafAccountViewController.h"
#import "SeafShibbolethViewController.h"
#import "SeafStorage.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "SeafRepos.h"
#import "SecurityUtilities.h"
#import "UIViewController+Extend.h"
#import "Debug.h"
#import <openssl/x509.h>
#import "SeafPrivacyPolicyViewController.h"


#define HTTP @"http://"
#define HTTPS @"https://"

@interface SeafAccountViewController ()<SeafLoginDelegate, UITextFieldDelegate>
@property (strong, nonatomic) IBOutlet UITextField *serverTextField;
@property (strong, nonatomic) IBOutlet UITextField *usernameTextField;
@property (strong, nonatomic) IBOutlet UITextField *passwordTextField;
@property (strong, nonatomic) IBOutlet UIButton *loginButton;
@property (weak, nonatomic)   IBOutlet NSLayoutConstraint *loginBtnTopConstraint;
@property (weak, nonatomic)   IBOutlet UILabel *prefixLabel;
@property (strong, nonatomic) IBOutlet UISwitch *httpsSwitch;
@property (strong, nonatomic) IBOutlet UILabel *httpsLabel;
@property (weak, nonatomic) IBOutlet UIButton *privacyPolicyButton;
@property StartViewController *startController;
@property SeafConnection *connection;
@property int type;
@end

@implementation SeafAccountViewController
@synthesize loginButton;
@synthesize serverTextField;
@synthesize usernameTextField;
@synthesize passwordTextField;
@synthesize startController;
@synthesize connection;
@synthesize type;


- (id)initWithController:(StartViewController *)controller connection: (SeafConnection *)conn type:(int)atype
{
    if (self = [super initWithAutoPlatformNibName]) {
        self.startController = controller;
        self.connection = conn;
        self.type = atype;
    }
    return self;
}

- (IBAction)cancel:(id)sender
{
    connection.loginDelegate = nil;
    [SVProgressHUD dismiss];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSString *)replaceString:(NSString *)str prefix:(NSString *)prefix withString:(NSString *)target
{
    if ([str hasPrefix:prefix]) {
        return [str stringByReplacingOccurrencesOfString:prefix withString:target options:0 range:NSMakeRange(0, prefix.length)];
    } else {
        return str;
    }
}

- (IBAction)httpsSwitchFlip:(id)sender
{
    BOOL https = _httpsSwitch.on;
    BOOL cur = [self.prefixLabel.text hasPrefix:HTTPS];
    if (cur == https) return;
    if (https) {
        self.prefixLabel.text = @"https://";
    } else {
        self.prefixLabel.text = @"http://";
    }
}

- (IBAction)shibboleth:(id)sender
{
    NSString *url = [NSString stringWithFormat:@"%@%@",self.prefixLabel.text,serverTextField.text];
    if (!serverTextField.text || serverTextField.text.length < 1) {
        [self alertWithTitle:NSLocalizedString(@"Server must not be empty", @"Seafile")];
        return;
    }
    if (![url hasPrefix:HTTP] && ![url hasPrefix:HTTPS]) {
        [self alertWithTitle:NSLocalizedString(@"Invalid Server", @"Seafile")];
        return;
    }
    if ([url hasSuffix:@"/"])
        url = [url substringToIndex:url.length-1];
    if (!self.connection)
        connection = [[SeafConnection alloc] initWithUrl:url cacheProvider:SeafGlobal.sharedObject.cacheProvider];
    if (![url isEqualToString:connection.address]) {
        connection.address = url;
    }
    connection.loginDelegate = self;
    connection.delegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    SeafShibbolethViewController *c = [[SeafShibbolethViewController alloc] init:connection];
    [self.navigationController pushViewController:c animated:true];
}

- (IBAction)login:(id)sender
{
    if (self.type == ACCOUNT_SHIBBOLETH) {
        return [self shibboleth:sender];
    }
    [usernameTextField resignFirstResponder];
    [serverTextField resignFirstResponder];
    [passwordTextField resignFirstResponder];
    NSString *username = usernameTextField.text;
    NSString *password = passwordTextField.text;

    if (!serverTextField.text || serverTextField.text.length < 1) {
        [self alertWithTitle:NSLocalizedString(@"Server must not be empty", @"Seafile")];
        return;
    }

    NSString *url = [NSString stringWithFormat:@"%@%@",self.prefixLabel.text,serverTextField.text];
    if (![url hasPrefix:HTTP] && ![url hasPrefix:HTTPS]) {
        [self alertWithTitle:NSLocalizedString(@"Invalid Server", @"Seafile")];
        return;
    }
    if (!username || username.length < 1) {
        [self alertWithTitle:NSLocalizedString(@"Username must not be empty", @"Seafile")];
        return;
    }
    if (!password || password.length < 1) {
        [self alertWithTitle:NSLocalizedString(@"Password required", @"Seafile")];
        return;
    }
    if ([url hasSuffix:@"/"])
        url = [url substringToIndex:url.length-1];
    if (!self.connection)
        connection = [[SeafConnection alloc] initWithUrl:url cacheProvider:SeafGlobal.sharedObject.cacheProvider];
    if (![url isEqualToString:connection.address]) {
        connection = nil;
        connection = [[SeafConnection alloc] initWithUrl:url cacheProvider:SeafGlobal.sharedObject.cacheProvider];
    }
    connection.loginDelegate = self;
    connection.delegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [connection loginWithUsername:username password:password];
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Connecting to server", @"Seafile")];
}

- (CGSize)getSizeForText:(NSString *)text maxWidth:(CGFloat)width font:(UIFont*)font  {
    CGSize constraintSize;
    constraintSize.height = MAXFLOAT;
    constraintSize.width = width;
    NSDictionary *attributesDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                          font, NSFontAttributeName,
                                          nil];

    CGRect frame = [text boundingRectWithSize:constraintSize
                                      options:NSStringDrawingUsesLineFragmentOrigin
                                   attributes:attributesDictionary
                                      context:nil];

    CGSize stringSize = frame.size;
    return stringSize;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    for (UIView *v in self.view.subviews) {
        v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin
        | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    }
    UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
    self.navigationItem.leftBarButtonItem = cancelItem;

    loginButton.layer.borderColor = [[UIColor whiteColor] CGColor];
    loginButton.layer.borderWidth = 0.0f;
    loginButton.layer.cornerRadius = 4.0f;
    [loginButton setTitle:NSLocalizedString(@"Login", @"Seafile") forState:UIControlStateNormal];
    [loginButton setTitle:NSLocalizedString(@"Login", @"Seafile") forState:UIControlStateHighlighted];
    [self.privacyPolicyButton setTitle:NSLocalizedString(@"Privacy Policy", @"Seafile") forState:UIControlStateNormal];

    _httpsLabel.text = @"https";
    serverTextField.clearButtonMode = UITextFieldViewModeNever;
    serverTextField.placeholder = NSLocalizedString(@"Server, like https://seafile.cc", @"Seafile");
    if (self.type != ACCOUNT_SHIBBOLETH) {
        self.title = [APP_NAME stringByAppendingFormat:@" %@", NSLocalizedString(@"Account", @"Seafile")];
        usernameTextField.placeholder = NSLocalizedString(@"Email or Username", @"Seafile");
        passwordTextField.placeholder = NSLocalizedString(@"Password", @"Seafile");
    } else {
        self.title = NSLocalizedString(@"Single Sign On", @"Seafile");
        self.loginBtnTopConstraint.constant = 44;
        [usernameTextField removeFromSuperview];
        [passwordTextField removeFromSuperview];
    }
    BOOL https = true;
    _httpsSwitch.on = true;
    switch (self.type) {
        case ACCOUNT_SEACLOUD:
            serverTextField.enabled = false;
            _httpsSwitch.enabled = false;
            serverTextField.text = SERVER_SEACLOUD;
            break;
        case ACCOUNT_OTHER:{
#if DEBUG
            serverTextField.text = @"dev.seafile.com/seahub";
            usernameTextField.text = @"demo@seafile.com";
            passwordTextField.text = @"";
#else

#endif
        }
            break;
        case ACCOUNT_SHIBBOLETH:
            _httpsSwitch.enabled = false;
#if DEBUG
//            serverTextField.text = @"dev2.seafile.com/seahub/";
#else

#endif
            break;
        default:
            break;
    }
    if (self.connection) {
        https = [connection.address hasPrefix:HTTPS];
        _httpsSwitch.on = https;
        [self httpsSwitchFlip:_httpsSwitch];
        serverTextField.text = [connection.address componentsSeparatedByString:@"//"].lastObject;
        usernameTextField.text = connection.username;
        passwordTextField.text = nil;
        serverTextField.enabled = false;
        usernameTextField.enabled = false;
        _httpsSwitch.enabled = false;
    }
    [self.serverTextField setDelegate:self];
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barAppearance = [UINavigationBarAppearance new];
        barAppearance.backgroundColor = [UIColor whiteColor];
        
        self.navigationController.navigationBar.standardAppearance = barAppearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = barAppearance;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)viewDidUnload
{
    [self setServerTextField:nil];
    [self setUsernameTextField:nil];
    [self setPasswordTextField:nil];
    [self setLoginButton:nil];
    [super viewDidUnload];
}

#pragma mark - SeafLoginDelegate
- (NSData *)getClientCertPersistentRef:(NSURLCredential *__autoreleasing *)credential
{
    __block NSURLCredential *b_cred = NULL;
    __block NSData *b_key;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    BOOL ret = [self getClientCert:^(NSData *key, NSURLCredential *cred) {
        b_cred = cred;
        b_key = key;
        dispatch_semaphore_signal(semaphore);

    }];
    if (!ret) return nil;

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    Debug("Choosed credential: %@", b_cred);
    *credential = b_cred;
    return b_key;
}

- (BOOL)getClientCert:(void (^)(NSData *key, NSURLCredential *cred))completeHandler
{
    NSDictionary *dict = [SeafStorage.sharedObject getAllSecIdentities];
    if (dict.count == 0) {
        Warning("No client certificates.");
        dispatch_async(dispatch_get_main_queue(), ^{
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"No available certificates", @"Seafile")];
        });
        return false;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [SeafStorage.sharedObject chooseCertFrom:dict handler:^(CFDataRef persistentRef, SecIdentityRef identity) {
            if (!identity || ! persistentRef) completeHandler(nil, nil);
            completeHandler((__bridge NSData *)persistentRef, [SecurityUtilities getCredentialFromSecIdentity:identity]);
        } from:self];
    });
    return true;
}

- (void)authorizeInvalidCert:(NSURLProtectionSpace *)protectionSpace yes:(void (^)(void))yes no:(void (^)(void))no
{
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"%@ can't verify the identity of the website \"%@\"", @"Seafile"), APP_NAME, protectionSpace.host];
    NSString *message = NSLocalizedString(@"The certificate from this website is invalid. Would you like to connect to the server anyway?", @"Seafile");
    [self alertWithTitle:title message:message yes:yes no:no];
}

- (BOOL)authorizeInvalidCert:(NSURLProtectionSpace *)protectionSpace
{
    __block BOOL ret = false;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_block_t block = ^{
        [self authorizeInvalidCert:protectionSpace yes:^{
            ret = true;
            dispatch_semaphore_signal(semaphore);
        } no:^{
            ret = false;
            dispatch_semaphore_signal(semaphore);
        }];
    };
    block();
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return ret;
}

- (void)loginSuccess:(SeafConnection *)conn
{
    if (conn != connection)
        return;

    Debug("login success");
    [conn getServerInfo:^(bool result) {
        Debug("Get server info result: %d", result);
        [SVProgressHUD dismiss];
        connection.loginDelegate = nil;
        BOOL ret = [startController saveAccount:connection];
        if (ret) {
            [self.navigationController dismissViewControllerAnimated:YES completion:nil];
            [startController checkSelectAccount:connection];
        } else {
            Warning("Failed to save account.");
            [self alertWithTitle:NSLocalizedString(@"Failed to save account", @"Seafile")];
        }
    }];
}

- (void)twoStepVerification
{
    [self popupTwoStepVerificationViewHandler:^(NSString *input, BOOL remember) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Verification code must not be empty", @"Seafile")];
            return;
        }
        
        NSString *username = usernameTextField.text;
        NSString *password = passwordTextField.text;
        [connection loginWithUsername:username password:password otp:input rememberDevice:remember];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Connecting to server", @"Seafile")];
    }];
}

- (void)loginFailed:(SeafConnection *)conn response:(NSHTTPURLResponse *)response error:(NSError *)error
{
    Debug("Failed to login: %@ %@\n", conn.address, error);
    if (conn != connection)
        return;

    if (error.code == kCFURLErrorCancelled) {
        return;
    }
    
    long errorCode = response.statusCode;
    if (errorCode == HTTP_ERR_LOGIN_INCORRECT_PASSWORD) {
        [SVProgressHUD dismiss];
        NSString * otp = [response.allHeaderFields objectForKey:@"X-Seafile-OTP"];
        if ([@"required" isEqualToString:otp]) {
            [self twoStepVerification];
        } else
            [self alertWithTitle:NSLocalizedString(@"Wrong username or password", @"Seafile")];
    } else {
        NSString *msg = NSLocalizedString(@"Failed to login", @"Seafile");
        [SVProgressHUD showErrorWithStatus:[msg stringByAppendingFormat:@": %@", error.localizedDescription]];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    if (textField == self.serverTextField) {
        [self.usernameTextField becomeFirstResponder];
    } else if (textField == self.usernameTextField) {
        [self.passwordTextField becomeFirstResponder];
    } else {
        [self.passwordTextField resignFirstResponder];
        [self login:nil];
    }
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    return YES;
}

- (IBAction)readPrivacyPolocy:(id)sender {
    SeafPrivacyPolicyViewController *vc = [[SeafPrivacyPolicyViewController alloc] init];
    if (IsIpad()) {
        UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:vc];
        [nc setModalPresentationStyle:UIModalPresentationFullScreen];
        nc.navigationBar.tintColor = BAR_COLOR;
        [self presentViewController:nc animated:true completion:nil];
    } else {
        vc.hidesBottomBarWhenPushed = true;
        [self.navigationController pushViewController:vc animated:true];
    }
}
@end
