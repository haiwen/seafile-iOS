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

@interface SeafShibbolethViewController ()<WKNavigationDelegate, NSURLConnectionDelegate,UINavigationControllerDelegate>

@property (strong) SeafConnection *sconn;// Connection to the Seafile server
@property (strong) NSURLRequest *FailedRequest;
@property (strong) NSURLConnection *conn;// Network connection used for certain requests
@property (strong, nonatomic) WKWebView *webView;// WebKit view for handling Shibboleth authentication
@property (strong, nonatomic) UIProgressView *progressView;
@property BOOL authenticated;// Flag to check if authentication has occurred
@property (strong, nonatomic) NSTimer *timer;//to get the sso login status every 15s.
@property (strong, nonatomic) NSString *ssoLinkToken;//sso login urlString.
@property (assign, nonatomic) BOOL isSSOLoginSuccess;// Indicate whether the SSO login was successful.

@end

@implementation SeafShibbolethViewController

- (id)init:(SeafConnection *)sconn// Custom initializer with a SeafConnection instance
{
    if (self = [super initWithNibName:nil bundle:nil]) {
        self.sconn = sconn;
    }
    return self;
}

- (NSString *)shibbolethUrl// Constructs the URL needed for Shibboleth authentication
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

- (NSString *)serverInfo
{
    return [_sconn.address stringByAppendingString:@"/api2/server-info/"];
}

- (NSString *)ssoLink {
    return [_sconn.address stringByAppendingString:@"/api2/client-sso-link/"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNotifications];
    // Do any additional setup after loading the view from its nib.
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationController.delegate = self;
    [self start];
}

//navigation back button clicked
- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (viewController != self) {
        if (self.timer) {
            if (self.timer.isValid) {
                [self.timer invalidate];
            }
            self.timer = nil;
        }
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// Starts the authentication or ping process
- (void)start
{
    //From 2.9.27
    _authenticated = true;
    _ssoLinkToken = @"";
    _isSSOLoginSuccess = false;
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:self.serverInfo]];

    @weakify(self)
    [self sendRequest:request completionHandler:^(NSDictionary *responseDict, NSError *error) {
        @strongify(self)
        if (!self) return;
        
        if (error) {
            Debug(@"Failed to retrieve server info: %@", error.localizedDescription);
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to connect to SSO Server Info server", @"Seafile")];
        } else {
            Debug(@"Server Info Retrieved Successfully");
            // Process the server's response
            NSArray *features = responseDict[@"features"];
            if ([features containsObject:@"client-sso-via-local-browser"]) {
                Debug(@"Client SSO via local browser is supported");
                // Execute additional code for client SSO via local browser
                if ([features containsObject:@"client-sso-via-local-browser"]) {
                    Debug("Feature client-sso-via-local-browser is supported");
                    //Send request to get the sso link url.
                    [self sendClintSSOLinkRequest];
                } else {//old sso login
                    Debug("Using standard Shibboleth login");
                    [self oldSSOLoginStart];
                }
            } else {
                Debug(@"Using standard login method");
                [self oldSSOLoginStart];
            }
        }
    }];
    
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Connecting to server", @"Seafile")];
}

- (void)oldSSOLoginStart {
    //Before 2.9.26
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
}

- (void)sendClintSSOLinkRequest {
    NSMutableURLRequest *ssoRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:self.ssoLink]];
    ssoRequest.HTTPMethod = @"POST";
    Debug("Send SSO request: %@", self.ssoLink);
    @weakify(self)
    [self sendRequest:ssoRequest completionHandler:^(NSDictionary *responseDict, NSError *error) {
        @strongify(self)
        if (!self) return;
        
        if (error) {
            Debug(@"Failed to retrieve server info: %@", error.localizedDescription);
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to connect to SSO link server", @"Seafile")];
        } else {
            Debug(@"Server Info Retrieved Successfully");
            // Process the server's response
            //Get SSO Link
            NSString *link = responseDict[@"link"];
            if (link && [link isKindOfClass:[NSString class]] && link.length > 0) {
                Debug(@"'link' exists and is not empty: %@", link);
//                NSString *urlString = [self modifyLinkString:link];
                NSString *urlString = link;

                self.ssoLinkToken = [self getSSOTokenFromURLString:urlString];
                [self startTimerWithUrlString:[self.ssoLink stringByAppendingString:self.ssoLinkToken]];
                
                [self openURLInSafari:urlString];

            } else {
                Debug(@"'link' does not exist or is empty");
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to get SSO link", @"Seafile")];
            }
        }
    }];
}

- (NSString *)modifyLinkString:(NSString *)originalURLString {
    // Use regular expression to replace duplicate 'seahub/' with single 'seahub/'
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(seahub/)+"
                                                                            options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    if (error) {
        Debug(@"Error creating regex: %@", error.localizedDescription);
    } else {
        NSString *modifiedURLString = [regex stringByReplacingMatchesInString:originalURLString
                                                                       options:0
                                                                         range:NSMakeRange(0, [originalURLString length])
                                                                  withTemplate:@"seahub/"];
        return modifiedURLString;
    }
    return @"";
}

- (void)sendRequest:(NSURLRequest *)request completionHandler:(void (^)(NSDictionary *responseDict, NSError *error))completionHandler {
    AFHTTPSessionManager *manager = _sconn.loginMgr;
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    NSURLSessionDataTask *dataTask = [manager dataTaskWithRequest:request uploadProgress:nil downloadProgress:nil completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            Debug("Response Received: %@", response);
            if (error) {
                Warning("Error: %@", error);
                //            [SVProgressHUD showErrorWithStatus:error.localizedDescription];
                if (completionHandler) {
                    completionHandler(nil, error);
                }
            } else {
                NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:responseObject options:0 error:nil];
                Debug("Response Data: %@", responseDict);
                if (completionHandler) {
                    completionHandler(responseDict, nil);
                }
            }
        });
    }];
    [dataTask resume];
    Debug("Request Sent: %@", request.URL);
}

// Loads a given URL request in the background
- (void)loadRequestBackground:(NSURLRequest *)request
{
    AFHTTPSessionManager *manager = _sconn.loginMgr;
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    NSURLSessionDataTask *dataTask = [manager dataTaskWithRequest:request uploadProgress:^(NSProgress * _Nonnull uploadProgress) {
        
    } downloadProgress:^(NSProgress * _Nonnull downloadProgress) {
        
    } completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        Debug("Response Received: %@", response);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                Warning("Error: %@", error);
                [SVProgressHUD showErrorWithStatus:error.localizedDescription];
            } else {
                NSString *url = self.shibbolethUrl;
                Debug("Send request: %@", url);
                NSMutableURLRequest *r = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
                r.HTTPShouldHandleCookies = true;
                [self webviewLoadRequest:r];
                
                NSString *responseString = [[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
                Debug("Response Data: %@", responseString);
            }
        });
    }];
    [dataTask resume];
    Debug("Request Sent: %@", request.URL);
}

// Loads a given URL request in the webView
- (void)webviewLoadRequest:(NSURLRequest *)request {
    WKWebView *wekview = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:[WKWebViewConfiguration new]];
    wekview.configuration.processPool = [[WKProcessPool alloc] init];
    wekview.navigationDelegate = self;
    // Add customUserAgent to bypass Google's OAUTH2 user-agent restriction.
    wekview.customUserAgent = [self customUserAgent];
    [self.view addSubview:wekview];
    [self.view addSubview:self.progressView];
    [wekview loadRequest:request];
    [self deleteCookiesForURL:request.URL];
    [wekview addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
   self.webView = wekview;
}

// Generates a custom user agent string to use with the webView
- (NSString *)customUserAgent {
    NSString *userAgent = [[WKWebView new] valueForKey:@"userAgent"];
    NSBundle *webKit = [NSBundle bundleWithIdentifier:@"com.apple.WebKit"];
    if (webKit && [webKit infoDictionary]) {
        NSString *version = [[webKit infoDictionary] objectForKey:@"CFBundleVersion"]; userAgent = [userAgent stringByAppendingFormat:@" Safari/%@", version];
    }
    else {
        userAgent = [userAgent stringByAppendingFormat:@" Safari/605.1.15"];
    }
    return userAgent;
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
            //to save account to app
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

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Connecting to server", @"Seafile")];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    Warning("Failed to load request: %@", error);
    [SVProgressHUD showErrorWithStatus:error.localizedDescription];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (decisionHandler) {
      decisionHandler(WKNavigationResponsePolicyAllow);
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(nonnull WKNavigationAction *)navigationAction decisionHandler:(nonnull void (^)(WKNavigationActionPolicy))decisionHandler {
    Debug("load request: %@, %d", navigationAction.request.URL, _authenticated);
    //whether if ping response correct
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

// Deletes cookies for a given URL
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

// Observes value changes for the web view's progress
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

// Lazily initialized progress view
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

//Open url in safari
- (void)openURLInSafari:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
            if (success) {
                Debug(@"URL was opened successfully");
            } else {
                Debug(@"Failed to open URL");
            }
        }];
    } else {
        Debug(@"URL is not valid or cannot be opened");
    }
}

- (NSString *)getSSOTokenFromURLString:(NSString *)urlString {
    NSString *key = @"client-sso/";
    // Find the location of "client-sso/" in the URL, example: "2c7820f684bc464f81f77fab5c999d49a6cd558eaf4494a22e544ab5a77c/", ends with "/"
    NSRange rangeOfKey = [urlString rangeOfString:key];
    if (rangeOfKey.location != NSNotFound) {
        // Calculate the starting index right after "client-sso/"
        NSUInteger startIndex = rangeOfKey.location + rangeOfKey.length;

        // Extract the string starting right after "client-sso/"
        NSString *substringAfterKey = [urlString substringFromIndex:startIndex];
        return substringAfterKey;
    } else {
        Debug(@"'client-sso/' not found in the URL");
        return @"";
    }
}

- (void)startTimerWithUrlString:(NSString *)urlString {
    if (urlString == nil || [urlString length] == 0 || self.isSSOLoginSuccess) {
        // Early return to prevent timer from starting.
        return;
    }
    
    NSDictionary *userInfo = @{@"urlString": urlString};
    self.timer = [NSTimer scheduledTimerWithTimeInterval:10.0
                                                  target:self
                                                selector:@selector(sendLoginRequest)
                                                userInfo:userInfo
                                                 repeats:YES];
}

//request for Whether safari login is successful
- (void)sendLoginRequest {
    if (self.isSSOLoginSuccess){
        if (self.timer) {
            [self.timer invalidate];
            self.timer = nil;
        }
        return;
    }
    NSDictionary *userInfo = self.timer.userInfo;
    NSString *urlString = userInfo[@"urlString"];
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    @weakify(self)
    [self sendRequest:request completionHandler:^(NSDictionary *responseDict, NSError *error) {
        @strongify(self)
        if (!self) return;
        
        if (!error && [responseDict[@"status"] isEqualToString:@"success"]) {
            Debug(@"login success");
            [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Shibboleth Login", @"Seafile")];
            NSString *username = responseDict[@"username"];
            NSString *apiToken = responseDict[@"apiToken"];
            Debug("Token=%@, username=%@", apiToken, username);
            [self->_sconn setToken:apiToken forUser:username isShib:true s2faToken:nil];
            // stop timer after login success.
            if (self.timer) {
                [self.timer invalidate];
                self.timer = nil;
            }
            self.isSSOLoginSuccess = true;
        }
    }];
}

- (void)setupNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidEnterBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillEnterForeground)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
}

- (void)appDidEnterBackground {
    if (self.timer) {
        if (self.timer.isValid) {
            [self.timer invalidate];
        }
        self.timer = nil;
    }
}

- (void)appWillEnterForeground {
    // Fire `[self sendLoginRequest]` once immediately after a 1-second delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self sendLoginRequest];
    });
    
    //
    [self startTimerWithUrlString:[self.ssoLink stringByAppendingString:self.ssoLinkToken]];

}

- (void)dealloc {
    if (self.timer) {
        if (self.timer.isValid) {
            [self.timer invalidate];
        }
        self.timer = nil;
    }
    
    [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];

}

@end
