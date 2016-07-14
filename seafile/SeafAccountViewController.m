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
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "SeafRepos.h"
#import "SecurityUtilities.h"
#import "UIViewController+Extend.h"
#import "Debug.h"
#import <openssl/x509.h>


#define HTTP @"http://"
#define HTTPS @"https://"

@interface SeafAccountViewController ()<SeafLoginDelegate, UITextFieldDelegate>
@property (strong, nonatomic) IBOutlet UITextField *serverTextField;
@property (strong, nonatomic) IBOutlet UITextField *usernameTextField;
@property (strong, nonatomic) IBOutlet UITextField *passwordTextField;
@property (strong, nonatomic) IBOutlet UIButton *loginButton;
@property (strong, nonatomic) IBOutlet UILabel *msgLabel;
@property (strong, nonatomic) IBOutlet UISwitch *httpsSwitch;
@property (strong, nonatomic) IBOutlet UILabel *httpsLabel;
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
    return [str stringByReplacingOccurrencesOfString:prefix withString:target options:0 range:NSMakeRange(0, prefix.length)];
}

- (IBAction)httpsSwitchFlip:(id)sender
{
    BOOL https = _httpsSwitch.on;
    BOOL cur = [serverTextField.text hasPrefix:HTTPS];
    if (cur == https) return;
    if (https) {
        serverTextField.text = [self replaceString:serverTextField.text prefix:HTTP withString:HTTPS];
    } else {
        serverTextField.text = [self replaceString:serverTextField.text prefix:HTTPS withString:HTTP];
    }
}

- (IBAction)shibboleth:(id)sender
{
    NSString *url = serverTextField.text;
    if (!url || url.length < 1) {
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
        connection = [[SeafConnection alloc] init:url];
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
    NSString *url = serverTextField.text;

    if (!url || url.length < 1) {
        [self alertWithTitle:NSLocalizedString(@"Server must not be empty", @"Seafile")];
        return;
    }
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
        connection = [[SeafConnection alloc] init:url];
    if (![url isEqualToString:connection.address]) {
        connection.address = url;
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

    if (ios7) {
        loginButton.layer.borderColor = [[UIColor lightGrayColor] CGColor];
        loginButton.layer.borderWidth = 0.5f;
        loginButton.layer.cornerRadius = 5.0f;

    } else {
        loginButton.reversesTitleShadowWhenHighlighted = NO;
        loginButton.tintColor=[UIColor whiteColor];
    }
    [loginButton setTitle:NSLocalizedString(@"Login", @"Seafile") forState:UIControlStateNormal];
    [loginButton setTitle:NSLocalizedString(@"Login", @"Seafile") forState:UIControlStateHighlighted];

    _httpsLabel.text = @"https";
    serverTextField.clearButtonMode = UITextFieldViewModeNever;
    serverTextField.placeholder = NSLocalizedString(@"Server, like https://seafile.cc", @"Seafile");
    if (self.type != ACCOUNT_SHIBBOLETH) {
        _msgLabel.text = NSLocalizedString(@"For example: https://seacloud.cc or http://192.168.1.24:8000", @"Seafile");
        self.title = [APP_NAME stringByAppendingFormat:@" %@", NSLocalizedString(@"Account", @"Seafile")];
        usernameTextField.placeholder = NSLocalizedString(@"Email or Username", @"Seafile");
        passwordTextField.placeholder = NSLocalizedString(@"Password", @"Seafile");
    } else {
        self.title = NSLocalizedString(@"Shibboleth Login", @"Seafile");
        [usernameTextField removeFromSuperview];
        [passwordTextField removeFromSuperview];
        [_msgLabel removeFromSuperview];
    }
    BOOL https = true;
    _httpsSwitch.on = true;
    switch (self.type) {
        case ACCOUNT_SEACLOUD:
            serverTextField.text = SERVER_SEACLOUD;
            break;
        case ACCOUNT_OTHER:{
#if DEBUG
            serverTextField.text = @"https://dev.seafile.com/seahub";
            usernameTextField.text = @"demo@seafile.com";
            passwordTextField.text = @"";
#else
            serverTextField.text = HTTPS;
#endif
        }
            break;
        case ACCOUNT_SHIBBOLETH:
#if DEBUG
            serverTextField.text = @"https://dev2.seafile.com/seahub/";
#else
            serverTextField.text = HTTPS;
#endif
            break;
        default:
            break;
    }
    if (self.connection) {
        https = [connection.address hasPrefix:HTTPS];
        _httpsSwitch.on = https;
        serverTextField.text = connection.address;
        usernameTextField.text = connection.username;
        passwordTextField.text = nil;
        serverTextField.enabled = false;
        usernameTextField.enabled = false;
        _httpsSwitch.enabled = false;
    }
    [self.serverTextField setDelegate:self];
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
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
- (id)getClientCertPersistentRef:(NSURLCredential *__autoreleasing *)credential
{
    __block NSURLCredential *b_cred = NULL;
    __block id b_key;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    BOOL ret = [self getClientCert:^(id key, NSURLCredential *cred) {
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

- (BOOL)getClientCert:(void (^)(id key, NSURLCredential *cred))completeHandler
{
    NSDictionary *dict = [SeafGlobal.sharedObject getAllSecIdentities];
    if (dict.count == 0) {
        Warning("No client certificates.");
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"No available certificates", @"Seafile")];
        return false;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [SeafGlobal.sharedObject chooseCertFrom:dict handler:^(CFDataRef persistentRef, SecIdentityRef identity) {
            if (!identity || ! persistentRef) completeHandler(nil, nil);
            completeHandler((__bridge id)persistentRef, [SecurityUtilities getCredentialFromSecIdentity:identity]);
        } from:self];
    });
    return true;
}

- (void)authorizeInvalidCert:(NSURLProtectionSpace *)protectionSpace yes:(void (^)())yes no:(void (^)())no
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
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
        [startController saveAccount:connection];
        [startController checkSelectAccount:connection];
    }];
}

- (void)twoStepVerification
{
    NSString *placeHolder = NSLocalizedString(@"Two step verification code", @"Seafile");;
    [self popupInputView:placeHolder placeholder:placeHolder secure:false handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Verification code must not be empty", @"Seafile")];
            return;
        }
        NSString *username = usernameTextField.text;
        NSString *password = passwordTextField.text;
        [connection loginWithUsername:username password:password otp:input];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Connecting to server", @"Seafile")];
    }];
}

- (void)loginFailed:(SeafConnection *)conn response:(NSURLResponse *)response error:(NSError *)error
{
    Debug("Failed to login: %@\n", conn.address);
    if (conn != connection)
        return;

    [SVProgressHUD dismiss];
    if (error.code == kCFURLErrorCancelled) {
        return;
    }

    NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
    long errorCode = resp.statusCode;
    if (errorCode == HTTP_ERR_LOGIN_INCORRECT_PASSWORD) {
        NSString * otp = [resp.allHeaderFields objectForKey:@"X-Seafile-OTP"];
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
    if (textField != serverTextField)
        return true;
    BOOL https = _httpsSwitch.on;
    NSString *prefix = https ? HTTPS: HTTP;
    NSRange substringRange = NSMakeRange(0, prefix.length);

    if (range.location >= substringRange.location && range.location < substringRange.location + substringRange.length) {
        return NO;
    }

    return YES;
}

@end
