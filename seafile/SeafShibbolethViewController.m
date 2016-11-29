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

@interface SeafShibbolethViewController ()<UIWebViewDelegate, NSURLConnectionDelegate>

@property (strong) SeafConnection *sconn;
@property (strong) NSURLRequest *FailedRequest;
@property (strong) NSURLConnection *conn;
@property BOOL authenticated;

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
    return url;
}

- (NSString *)pingUrl
{
    return [_sconn.address stringByAppendingString:@"/api2/ping/"];
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
        _authenticated = true;
        NSURLRequest *request = [[NSURLRequest alloc] initWithURL:[NSURL URLWithString:self.shibbolethUrl]];
        [self.webView loadRequest:request];
    } else {
        _authenticated = false;
        NSURLRequest *request = [[NSURLRequest alloc] initWithURL:[NSURL URLWithString:self.pingUrl]];
        Debug("Ping %@", self.pingUrl);
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
            NSString *url = self.shibbolethUrl;
            Debug("Send request: %@", url);
            NSMutableURLRequest *r = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
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

-(BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    BOOL result = _authenticated;
    if (!_authenticated) {
        _FailedRequest = request;
        self.conn = [[NSURLConnection alloc] initWithRequest:request delegate:self];
    }
    Debug("load request: %@, %d", request.URL, result);
    return result;
}

-(void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    Debug("authenticationMethod: %@", challenge.protectionSpace.authenticationMethod);
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURL* baseURL = [NSURL URLWithString:self.shibbolethUrl];
        if ([challenge.protectionSpace.host isEqualToString:baseURL.host] || SeafServerTrustIsValid(challenge.protectionSpace.serverTrust)) {
            NSLog(@"trusting connection to host %@", challenge.protectionSpace.host);
            [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
        } else {
            NSLog(@"Not trusting connection to host %@", challenge.protectionSpace.host);
        }
    } else if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodClientCertificate]) {
        Debug("Use NSURLAuthenticationMethodClientCertificate");
        if (self.sconn.clientCred != nil) {
            [challenge.sender useCredential:self.sconn.clientCred forAuthenticationChallenge:challenge];
        }
    }
    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

-(void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)pResponse {
    _authenticated = YES;
    [connection cancel];
    [self.webView loadRequest:_FailedRequest];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    Warning("Failed to load request: %@", error);
    [SVProgressHUD dismiss];
}
@end
