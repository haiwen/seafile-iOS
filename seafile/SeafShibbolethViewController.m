//
//  SeafShibbolethViewController.m
//  seafilePro
//
//  Created by Wang Wei on 4/25/15.
//  Copyright (c) 2015 Seafile. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafShibbolethViewController.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "ExtentedString.h"

#import "Debug.h"

@interface SeafShibbolethViewController ()<UIWebViewDelegate>

@property (strong) SeafConnection *sconn;
@property (strong) NSURLRequest *FailedRequest;
@property (strong) NSURLConnection *conn;

@end

@implementation SeafShibbolethViewController

- (id)init:(SeafConnection *)sconn
{
    if (self = [super initWithAutoNibName]) {
        self.sconn = sconn;
        [self start];
    }
    return self;
}

- (NSString *)shibbolethUrl
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDictionary objectForKey:@"CFBundleVersion"];
    NSString *platform = @"ios";
    NSString *platformVersion = [infoDictionary objectForKey:@"DTPlatformVersion"];
    NSString *deviceID = [UIDevice currentDevice].identifierForVendor.UUIDString;
    NSString *deviceName = UIDevice.currentDevice.name;

    if (!platformVersion) {//For simulator
        platformVersion = @"8.0";
    }
    NSString *url = [_sconn.address stringByAppendingFormat:@"/shib-login/?shib_platform_version=%@&shib_device_name=%@&shib_platform=%@&shib_device_id=%@&shib_client_version=%@", platformVersion.escapedUrl, deviceName.escapedUrl, platform.escapedUrl, deviceID.escapedUrl, version.escapedUrl];
    Debug("shibbolethUrl: %@", url);
    return url;
}

- (NSString *)pingUrl
{
    return[_sconn.address stringByAppendingString:@"/api2/ping/"];
}

- (UIWebView *)webView
{
    return (UIWebView *)self.view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)start
{
    if ([_sconn.address hasPrefix:@"http://"]) {
        NSURLRequest *request = [[NSURLRequest alloc] initWithURL:[NSURL URLWithString:self.shibbolethUrl]];
        [self.webView loadRequest:request];
    } else {
        NSURLRequest *request = [[NSURLRequest alloc] initWithURL:[NSURL URLWithString:self.pingUrl]];
        [self loadRequestBackground:request];
    }
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Connecting to server", @"Seafile")];
}

- (void)loadRequestBackground:(NSURLRequest *)request
{
    AFHTTPSessionManager *manager = _sconn.loginMgr;
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    NSURLSessionDataTask *dataTask = [manager dataTaskWithRequest:request completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
        if (error) {
            [SVProgressHUD dismiss];
            Warning("Error: %@", error);
        } else {
            NSMutableURLRequest *r = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:self.shibbolethUrl]];
            r.HTTPShouldHandleCookies = true;
            [self.webView loadRequest:r];
        }
    }];
    [dataTask resume];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [SVProgressHUD dismiss];
    [super viewWillDisappear:animated];
}

# pragma - UIWebViewDelegate
- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [SVProgressHUD dismiss];
    NSArray *arr = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:[NSURL URLWithString:self.shibbolethUrl]];
    for (NSHTTPCookie *cookie in arr) {
        if ([cookie.name isEqualToString:@"seahub_auth"]) {
            Debug("Got seahub_auth: %@", cookie.value);
            NSString *str = [cookie.value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
            NSRange range = [str rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"@"] options:NSBackwardsSearch];
            if (range.location == NSNotFound) {
                Warning("Can not seahub_auth cookie invalid");
            } else {
                NSString *username = [str substringToIndex:range.location];
                NSString *token = [str substringFromIndex:range.location+1];
                Debug("Token=%@, username=%@", token, username);
                [_sconn setToken:token forUser:username isShib:true];
            }
        }
    }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    Warning("Failed to load request: %@", error);
    [SVProgressHUD dismiss];
}

-(BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    Debug("load request: %@", request.URL);
    return true;
}

@end
