//
//  SeafAccountViewController.m
//  seafile
//
//  Created by Wang Wei on 1/12/13.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAccountViewController.h"
#import "UIViewController+AlertMessage.h"
#import "SVProgressHUD.h"
#import "Debug.h"

#define HTTP @"http://"
#define HTTPS @"https://"

@interface SeafAccountViewController ()
@property (strong, nonatomic) IBOutlet UISwitch *httpsSwitch;
@property (strong, nonatomic) IBOutlet UITextField *serverTextField;
@property (strong, nonatomic) IBOutlet UITextField *usernameTextField;
@property (strong, nonatomic) IBOutlet UITextField *passwordTextField;
@property StartViewController *startController;
@property SeafConnection *connection;
@end

@implementation SeafAccountViewController
@synthesize httpsSwitch;
@synthesize serverTextField;
@synthesize usernameTextField;
@synthesize passwordTextField;
@synthesize startController;
@synthesize connection;


- (id)initWithController:(StartViewController *)controller connection: (SeafConnection *)conn;
{
    if (self = [super initWithNibName:@"SeafAccountViewController" bundle:nil]) {
        self.startController = controller;
        self.connection = conn;
    }
    return self;
}

- (IBAction)cancel:(id)sender
{
    connection.delegate = nil;
    [SVProgressHUD dismiss];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)login:(id)sender
{
    NSString *username = usernameTextField.text;
    NSString *password = passwordTextField.text;
    NSString *server = serverTextField.text;
    BOOL isHttps = httpsSwitch.on;
    NSString *url = nil;

    if (!server || server.length < 1) {
        [self alertWithMessage:@"Server must not be empty"];
        return;
    }
    if (!username || username.length < 1) {
        [self alertWithMessage:@"Username must not be empty"];
        return;
    }
    if (!password || password.length < 1) {
        [self alertWithMessage:@"Password required"];
        return;
    }

    if (isHttps) {
        url = [NSString stringWithFormat:HTTPS"%@", server];
    } else
        url = [NSString stringWithFormat:HTTP"%@", server];

    if (!self.connection) {
        connection = [[SeafConnection alloc] initWithUrl:url username:username];
    }
    connection.delegate = self;
    [connection loginWithAddress:url username:username password:password];
    [SVProgressHUD showWithStatus:@"Connecting to server"];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    for (UIView *v in self.view.subviews) {
        v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin
        | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    }
    self.title = @"Seafile Account";

    CGRect rect = CGRectMake(0, 0, 90, 25);
    UILabel *serverLabel = [[UILabel alloc] initWithFrame:rect];
    serverLabel.text = @"Server";
    serverLabel.font = [UIFont boldSystemFontOfSize:14];
    serverTextField.leftView = serverLabel;
    serverTextField.leftViewMode = UITextFieldViewModeAlways;

    UILabel *nameLabel = [[UILabel alloc] initWithFrame:rect];
    nameLabel.text = @"Username";
    nameLabel.font = [UIFont boldSystemFontOfSize:14];
    usernameTextField.leftView = nameLabel;
    usernameTextField.leftViewMode = UITextFieldViewModeAlways;
    UILabel *passwordLabel = [[UILabel alloc] initWithFrame:rect];
    passwordLabel.text = @"Password";
    passwordLabel.font = [UIFont boldSystemFontOfSize:14];
    passwordTextField.leftView = passwordLabel;
    passwordTextField.leftViewMode = UITextFieldViewModeAlways;
    if (self.connection) {
        if ([connection.address hasPrefix:HTTPS]) {
            serverTextField.text = [connection.address substringFromIndex:HTTPS.length];
            httpsSwitch.on = YES;
        } else {
            serverTextField.text = [connection.address substringFromIndex:HTTP.length];
            httpsSwitch.on = NO;
        }
        usernameTextField.text = connection.username;
        passwordTextField.text = connection.password;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)viewDidUnload
{
    [self setHttpsSwitch:nil];
    [self setServerTextField:nil];
    [self setUsernameTextField:nil];
    [self setPasswordTextField:nil];
    [super viewDidUnload];
}

#pragma mark - SSConnectionDelegate
- (void)connectionEstablishingSuccess:(SeafConnection *)conn
{
}

- (void)connectionEstablishingFailed:(SeafConnection *)conn
{
}

- (void)connectionLinkingSuccess:(SeafConnection *)conn
{
    Debug("%@", conn.address);
    if (conn != connection) {
        return;
    }
    [SVProgressHUD dismiss];
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    [startController saveAccount:connection];
    [startController selectAccount:connection];
}

- (void)connectionLinkingFailed:(SeafConnection *)conn error:(int)error
{
    Debug("%@, error=%d\n", conn.address, error);
    if (conn != connection) {
        return;
    }
    [SVProgressHUD dismiss];
    if (error == HTTP_ERR_LOGIN_INCORRECT_PASSWORD)
        [self alertWithMessage:@"Wrong username or password"];
    else {
        [SVProgressHUD showErrorWithStatus:@"Failed to login"];
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

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!IsIpad()) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
    return YES;
}

@end
