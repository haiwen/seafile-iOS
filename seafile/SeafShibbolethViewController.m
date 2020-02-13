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
#import <WebKit/WebKit.h>

#import "Debug.h"

@interface SeafShibbolethViewController ()<WKNavigationDelegate, NSURLConnectionDelegate>

@property (strong) SeafConnection *sconn;
@property (strong) NSURLRequest *FailedRequest;
@property (strong) NSURLConnection *conn;
@property (strong, nonatomic) WKWebView *webView;
@property (strong, nonatomic) UIProgressView *progressView;
@property BOOL authenticated;

@end

@implementation SeafShibbolethViewController

- (id)init:(SeafConnection *)sconn
{
    if (self = [super initWithAutoNibName]) {
        self.sconn = sconn;
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

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    [self start];
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
        [self webviewLoadRequest:request];
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
            Warning("Error: %@", error);
            [SVProgressHUD showErrorWithStatus:error.localizedDescription];
        } else {
            NSString *url = self.shibbolethUrl;
            Debug("Send request: %@", url);
            NSMutableURLRequest *r = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
            r.HTTPShouldHandleCookies = true;
            [self webviewLoadRequest:r];
        }
    }];
    [dataTask resume];
}

- (void)webviewLoadRequest:(NSURLRequest *)request {
    WKWebView *wekview = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:[WKWebViewConfiguration new]];
    wekview.configuration.processPool = [[WKProcessPool alloc] init];
    wekview.navigationDelegate = self;
    [self.view addSubview:wekview];
    [self.view addSubview:self.progressView];
    [wekview loadRequest:request];
    [self deleteCookiesForURL:request.URL];
    [wekview addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
   self.webView = wekview;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [SVProgressHUD dismiss];
    [super viewWillDisappear:animated];
}

# pragma - WKNavigationDelegate
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [SVProgressHUD dismiss];
    [webView evaluateJavaScript:@"document.cookie" completionHandler:^(id _Nullable response, NSError * _Nullable error) {
        if (response) {
            NSArray *cookies = [(NSString*)response componentsSeparatedByString:@";"];
            for (NSString *value in cookies) {
                if ([value containsString:@"seahub_auth"]) {
                    Debug("Got seahub_auth: %@", value);
                    if ([value componentsSeparatedByString:@"="].lastObject) {
                        NSString *str = [[value componentsSeparatedByString:@"="].lastObject stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
                        NSRange range = [str rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"@"] options:NSBackwardsSearch];
                        if (range.location == NSNotFound) {
                            Warning("Can not seahub_auth cookie invalid");
                            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to login", @"Seafile")];
                        } else {
                            NSString *username = [str substringToIndex:range.location];
                            NSString *token = [str substringFromIndex:range.location+1];
                            Debug("Token=%@, username=%@", token, username);
                            [_sconn setToken:token forUser:username isShib:true s2faToken:nil];
                        }
                    } else {
                        Warning("Can not seahub_auth cookie invalid");
                        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to login", @"Seafile")];
                    }
                }
            }
        }
    }];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    Warning("Failed to load request: %@", error);
    [SVProgressHUD showErrorWithStatus:error.localizedDescription];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    [SVProgressHUD dismiss];
    if (decisionHandler) {
      decisionHandler(WKNavigationResponsePolicyAllow);
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(nonnull WKNavigationAction *)navigationAction decisionHandler:(nonnull void (^)(WKNavigationActionPolicy))decisionHandler {
    Debug("load request: %@, %d", navigationAction.request.URL, _authenticated);
    if (!_authenticated) {
        _FailedRequest = navigationAction.request;
        self.conn = [[NSURLConnection alloc] initWithRequest:_FailedRequest delegate:self];
        decisionHandler(WKNavigationActionPolicyCancel);
    } else {
        decisionHandler(WKNavigationActionPolicyAllow);
    }
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
    [SVProgressHUD showErrorWithStatus:error.localizedDescription];
}

- (void)deleteCookiesForURL:(NSURL *)URL {
    WKWebsiteDataStore *dateStore = [WKWebsiteDataStore defaultDataStore];
    [dateStore fetchDataRecordsOfTypes:[WKWebsiteDataStore allWebsiteDataTypes] completionHandler:^(NSArray<WKWebsiteDataRecord *> * __nonnull records) {
         for (WKWebsiteDataRecord *record in records) {
           if ([URL.host containsString:record.displayName]) {
               [dateStore removeDataOfTypes:record.dataTypes forDataRecords:@[record] completionHandler:^{
                   Debug(@"WKWebsiteDataStore deleted successfully: %@", record.displayName);
               }];
           }
         }
       }
    ];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == self.webView && [keyPath isEqualToString:@"estimatedProgress"]) {
        CGFloat newprogress = [[change objectForKey:NSKeyValueChangeNewKey] doubleValue];
        self.progressView.alpha = 1.0f;
        [self.progressView setProgress:newprogress animated:YES];
        if (newprogress >= 1.0f) {
            [UIView animateWithDuration:0.3f
                                  delay:0.3f
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{
                                 self.progressView.alpha = 0.0f;
                             }
                             completion:^(BOOL finished) {
                                 [self.progressView setProgress:0 animated:NO];
                             }];
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (UIProgressView *)progressView {
    if (!_progressView) {
        CGFloat y = [[UIApplication sharedApplication] statusBarFrame].size.height + self.navigationController.navigationBar.frame.size.height;
        if (IsIpad()) {
            y = self.navigationController.navigationBar.frame.size.height;
        }
        _progressView = [[UIProgressView alloc] initWithFrame:CGRectMake(0, y, [UIScreen mainScreen].bounds.size.width, 2)];
        _progressView.tintColor = SEAF_COLOR_LIGHT;
        _progressView.trackTintColor = [UIColor whiteColor];
    }
    return _progressView;
}

- (void)dealloc {
    [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
}

@end
