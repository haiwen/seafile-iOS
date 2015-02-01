//
//  SeafAccountViewController.m
//  seafile
//
//  Created by Wang Wei on 1/12/13.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafAccountViewController.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "SeafRepos.h"
#import "Debug.h"

#define HTTP @"http://"
#define HTTPS @"https://"

@interface SeafAccountViewController ()<SeafConnectionDelegate>
@property (strong, nonatomic) IBOutlet UITextField *serverTextField;
@property (strong, nonatomic) IBOutlet UITextField *usernameTextField;
@property (strong, nonatomic) IBOutlet UITextField *passwordTextField;
@property (strong, nonatomic) IBOutlet UIButton *loginButton;
@property (strong, nonatomic) IBOutlet UIButton *cancelButton;
@property (strong, nonatomic) IBOutlet UILabel *msgLabel;
@property StartViewController *startController;
@property SeafConnection *connection;
@property int type;
@end

@implementation SeafAccountViewController
@synthesize loginButton;
@synthesize cancelButton;
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

- (IBAction)login:(id)sender
{
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
        connection = [[SeafConnection alloc] initWithUrl:url username:username];
    connection.loginDelegate = self;
    connection.delegate = self;
    [connection loginWithAddress:url username:username password:password];
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Connecting to server", @"Seafile")];
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
    if (ios7) {
        loginButton.layer.borderColor = [[UIColor lightGrayColor] CGColor];
        loginButton.layer.borderWidth = 0.5f;
        loginButton.layer.cornerRadius = 5.0f;
        cancelButton.layer.borderColor = [[UIColor lightGrayColor] CGColor];
        cancelButton.layer.borderWidth = 0.5f;
        cancelButton.layer.cornerRadius = 5.0f;
    } else {
        loginButton.reversesTitleShadowWhenHighlighted = NO;
        cancelButton.reversesTitleShadowWhenHighlighted = NO;
        loginButton.tintColor=[UIColor whiteColor];
        cancelButton.tintColor=[UIColor whiteColor];
    }
    [loginButton setTitle:NSLocalizedString(@"Login", @"Seafile") forState:UIControlStateNormal];
    [loginButton setTitle:NSLocalizedString(@"Login", @"Seafile") forState:UIControlStateHighlighted];
    [cancelButton setTitle:NSLocalizedString(@"Cancel", @"Seafile") forState:UIControlStateNormal];
    [cancelButton setTitle:NSLocalizedString(@"Cancel", @"Seafile") forState:UIControlStateHighlighted];


    _msgLabel.text = NSLocalizedString(@"For example: https://seacloud.cc or http://192.168.1.24:8000", @"Seafile");
    serverTextField.placeholder = NSLocalizedString(@"Server, like https://seafile.cc", @"Seafile");

    self.title = [NSString stringWithFormat:NSLocalizedString(@"%@ Account", @"Seafile"), APP_NAME];
    CGRect rect = CGRectMake(0, 0, 90, 25);
    NSString *align = ios7 ? @"  " :  @"";
    UILabel *serverLabel = [[UILabel alloc] initWithFrame:rect];
    serverLabel.text = [align stringByAppendingString:NSLocalizedString(@"Server", @"Seafile")];
    serverLabel.font = [UIFont boldSystemFontOfSize:14];
    serverTextField.leftView = serverLabel;
    serverTextField.leftViewMode = UITextFieldViewModeAlways;

    UILabel *nameLabel = [[UILabel alloc] initWithFrame:rect];
    nameLabel.text = [align stringByAppendingString:NSLocalizedString(@"Username", @"Seafile")];
    nameLabel.font = [UIFont boldSystemFontOfSize:14];
    usernameTextField.leftView = nameLabel;
    usernameTextField.leftViewMode = UITextFieldViewModeAlways;
    UILabel *passwordLabel = [[UILabel alloc] initWithFrame:rect];
    passwordLabel.text = [align stringByAppendingString:NSLocalizedString(@"Password", @"Seafile")];
    passwordLabel.font = [UIFont boldSystemFontOfSize:14];
    passwordTextField.leftView = passwordLabel;
    passwordTextField.leftViewMode = UITextFieldViewModeAlways;
    if (self.connection) {
        serverTextField.text = connection.address;
        usernameTextField.text = connection.username;
        passwordTextField.text = connection.password;
    } else {
        if (self.type == 1)
            serverTextField.text = @"https://seacloud.cc";
        else if (self.type == 2)
            serverTextField.text = @"https://cloud.seafile.com";
        else {
#if DEBUG
            serverTextField.text = @"https://dev.seafile.com/seahub/";
            usernameTextField.text = @"demo@seafile.com";
            passwordTextField.text = @"demo";
#endif
        }
    }
    usernameTextField.placeholder = NSLocalizedString(@"Email", @"Seafile");
    passwordTextField.placeholder = NSLocalizedString(@"Password", @"Seafile");

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
    [self setCancelButton:nil];
    [super viewDidUnload];
}

#pragma mark - SeafLoginDelegate
- (void)loginSuccess:(SeafConnection *)conn
{
    if (conn != connection)
        return;

    Debug("login success");
    [SVProgressHUD dismiss];
    conn.rootFolder = [[SeafRepos alloc] initWithConnection:conn];
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    connection.loginDelegate = nil;
    [startController saveAccount:connection];
    [startController selectAccount:connection];
}

- (void)loginFailed:(SeafConnection *)conn error:(int)error
{
    Debug("%@, error=%d\n", conn.address, error);
    if (conn != connection)
        return;

    if (error == HTTP_ERR_LOGIN_INCORRECT_PASSWORD) {
        [SVProgressHUD dismiss];
        [self alertWithTitle:NSLocalizedString(@"Wrong username or password", @"Seafile")];
    } else if (error == 0){
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Network unavailable", @"Seafile")];
    } else {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to login", @"Seafile")];
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

#pragma - SeafConnectionDelegate
- (void)loginRequired:(SeafConnection *)connection
{
}

- (void)continueWithInvalidCert:(NSString *)title message:(NSString*)message yes:(void (^)())yes no:(void (^)())no
{
    [self alertWithTitle:title message:message yes:yes no:no];
}

@end
