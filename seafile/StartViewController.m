//
//  StartViewController.m
//  seafile
//
//  Created by Wang Wei on 8/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafRepos.h"

#import "StartViewController.h"
#import "SeafAppDelegate.h"
#import "SeafFileViewController.h"
#import "SeafDetailViewController.h"
#import "SeafServersViewController.h"

#import "UIViewController+AlertMessage.h"
#import "UIViewController+AutoPlatformNibName.h"
#import "ExtentedString.h"
#import "Debug.h"

#import "SVProgressHUD.h"


@interface StartViewController ()
@property SeafConnection *connection;
@property (readonly) BOOL visible;
@end

@implementation StartViewController
@synthesize serverUrlLabel;
@synthesize connection;
@synthesize nameTextField = _nameTextField;
@synthesize passwordTextField = _passwordTextField;
@synthesize otherServerButton, registerButton, loginButton;


- (id)init
{
    if (self = [self initWithAutoPlatformNibName]) {
    }
    return self;
}

- (void)keyboardWillShow:(NSNotification *)noti
{
    float height = 216.0;
    CGRect frame = self.view.frame;
    frame.size = CGSizeMake(frame.size.width, frame.size.height - height);
    [UIView beginAnimations:@"Curl"context:nil];
    [UIView setAnimationDuration:0.30];
    [UIView setAnimationDelegate:self];
    [self.view setFrame:frame];
    [UIView commitAnimations];
}

- (void)keyboardWillHide:(NSNotification *)noti
{
    float height = 216.0;
    CGRect frame = self.view.frame;
    frame.size = CGSizeMake(frame.size.width, frame.size.height + height);
    [UIView beginAnimations:@"Curl"context:nil];
    [UIView setAnimationDuration:0.30];
    [UIView setAnimationDelegate:self];
    [self.view setFrame:frame];
    [UIView commitAnimations];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (!IsIpad()) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWillShow:)
                                                     name:UIKeyboardWillShowNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWillHide:)
                                                     name:UIKeyboardWillHideNotification
                                                   object:nil];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [SVProgressHUD dismiss];
    if (!IsIpad()) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    }
    [super viewWillDisappear:animated];
}

- (BOOL)visible
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    return appdelegate.window.rootViewController == self;
}

-(NSString *)getSelectedServer
{
    return connection.address;
}

- (void)selectServer:(NSString *)url
{
    serverUrlLabel.text = url.trimUrl;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    connection = [appdelegate getConnection:url];
    self.nameTextField.text = connection.username;
    self.passwordTextField.text = connection.password;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    CGRect rect = CGRectMake(0, 0, 90, 25);
    UILabel *nameLabel = [[UILabel alloc] initWithFrame:rect];
    nameLabel.text = @"Username";
    nameLabel.font = [UIFont boldSystemFontOfSize:14];
    _nameTextField.leftView = nameLabel;
    _nameTextField.leftViewMode = UITextFieldViewModeAlways;
    UILabel *passwordLabel = [[UILabel alloc] initWithFrame:rect];
    passwordLabel.text = @"Password";
    passwordLabel.font = [UIFont boldSystemFontOfSize:14];
    _passwordTextField.leftView = passwordLabel;
    _passwordTextField.leftViewMode = UITextFieldViewModeAlways;
    //[self.registerButton setHighColor:[UIColor whiteColor] lowColor:[UIColor whiteColor]];
    //[self.loginButton setHighColor:[UIColor whiteColor] lowColor:[UIColor whiteColor]];

    [self selectServer:DEFAULT_SERVER_URL];
    for (UIView *v in self.view.subviews) {
        v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin
        | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    }

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *server = [userDefaults objectForKey:@"DEAULT-SERVER"];
    if (server) {
        [self selectServer:server];
        [self transferToReposView];
    }
}

- (void)viewDidUnload
{
    [self setNameTextField:nil];
    [self setPasswordTextField:nil];
    [self setRegisterButton:nil];
    [self setLoginButton:nil];
    [self setOtherServerButton:nil];
    [self setServerUrlLabel:nil];
    [super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!IsIpad()) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
    return YES;
}

- (IBAction)otherServer:(id)sender
{
    [SVProgressHUD dismiss];
    SeafServersViewController *controller = [[SeafServersViewController alloc] initWithController:self];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    navController.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:navController animated:YES completion:nil];
}

- (IBAction)registerAccount:(id)sender
{
    [SVProgressHUD dismiss];
    NSString *url = [self getSelectedServer];
    if (!url)
        return;

    NSString *registerUrl = [NSString stringWithFormat:@"%@/accounts/register/", url];
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:registerUrl]];
}

- (IBAction)login:(id)sender
{
    [SVProgressHUD dismiss];
    NSString *url = [self getSelectedServer];
    if (!url)
        return;

    NSString *username = self.nameTextField.text;
    NSString *password = self.passwordTextField.text;
    Debug("name=%@, pass=%@\n", username, password);
    if (!username || username.length < 1) {
        [self alertWithMessage:@"Username must not be empty"];
        return;
    }
    if (!password || password.length < 1) {
        [self alertWithMessage:@"Password required"];
        return;
    }
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    connection = [appdelegate getConnection:url];
    connection.delegate = self;
    [connection loginWithAddress:nil username :username password:password];
    [SVProgressHUD showWithStatus:[NSString stringWithFormat:@"Connecting to server '%@'", url]];
}

#pragma mark - SSConnectionDelegate
- (void)transferToReposView
{
    Debug("%@\n", connection.address);
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:connection.address forKey:@"DEAULT-SERVER"];
    [userDefaults synchronize];

    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [connection loadRepos:appdelegate.masterVC];
    appdelegate.uploadVC.connection = connection;
    appdelegate.starredVC.connection = connection;
    appdelegate.settingVC.connection = connection;
    [appdelegate.detailVC setPreViewItem:nil];
    if (IsIpad())
        appdelegate.window.rootViewController = appdelegate.splitVC;
    else
        appdelegate.window.rootViewController = appdelegate.tabbarController;

    [appdelegate.masterVC setDirectory:(SeafDir *)connection.rootFolder];
    [appdelegate.window makeKeyAndVisible];
}


- (void)connectionEstablishingSuccess:(SeafConnection *)conn
{
}

- (void)connectionEstablishingFailed:(SeafConnection *)conn
{
}

- (void)connectionLinkingSuccess:(SeafConnection *)conn
{
    Debug("%@", conn.address);
    NSString *url = [self getSelectedServer];
    if (!self.visible || ![conn.address isEqualToString:url]) {
        return;
    }

    [SVProgressHUD dismiss];
    [self transferToReposView];
}

- (void)connectionLinkingFailed:(SeafConnection *)conn error:(int)error
{
    Debug("%@, error=%d\n", conn.address, error);
    NSString *url = [self getSelectedServer];
    if (![conn.address isEqualToString:url]) {
        return;
    }

    [SVProgressHUD dismiss];
    if (!self.visible) { //In the case that session is out of date and password is changed
        if (error != HTTP_ERR_LOGIN_INCORRECT_PASSWORD)
            return;
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate.masterNavController popToRootViewControllerAnimated:NO];
        appdelegate.window.rootViewController = self;
        [appdelegate.window makeKeyAndVisible];
        [self alertWithMessage:@"Password has been changed, please reenter"];
    } else {
        if (error == HTTP_ERR_LOGIN_INCORRECT_PASSWORD)
            [self alertWithMessage:@"Wrong username or password"];
        else if ([_nameTextField.text isEqualToString:conn.username]
                 && [_passwordTextField.text isEqualToString:conn.password]
                 && conn.logined) {
            [self alertWithMessage:@"The selected server seems unavailable, you can browser the offline files"];
            [self transferToReposView];
        } else {
            [self alertWithMessage:@"Failed to login"];
        }
    }
}

#pragma mark - UITextFieldDelegate
- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    if (textField == self.passwordTextField) {
        [textField resignFirstResponder];
    } else {
        [self.passwordTextField becomeFirstResponder];
    }
    return YES;
}

@end
