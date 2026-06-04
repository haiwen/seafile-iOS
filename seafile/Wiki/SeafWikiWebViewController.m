//
//  SeafWikiWebViewController.m
//  seafile
//
//  Created on 2026/5/12.
//

#import "SeafWikiWebViewController.h"
#import "SeafWebViewBridge.h"
#import <WebKit/WebKit.h>
#import "SVProgressHUD.h"
#import "Debug.h"

@interface SeafWikiWebViewController () <WKNavigationDelegate, WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, copy) NSString *urlString;
@property (nonatomic, strong) SeafConnection *connection;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) SeafWeakScriptMessageHandler *weakBridgeHandler;
@end

@implementation SeafWikiWebViewController

- (instancetype)initWithURL:(NSString *)urlString connection:(SeafConnection *)connection {
    if (self = [super init]) {
        _urlString = urlString;
        _connection = connection;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = NSLocalizedString(@"Wiki", @"Seafile");

    // Progress bar
    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progressView.progressTintColor = [UIColor colorWithRed:236/255.0 green:114/255.0 blue:31/255.0 alpha:1.0];
    _progressView.translatesAutoresizingMaskIntoConstraints = NO;

    // WebView with JS Bridge
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *uc = [[WKUserContentController alloc] init];
    self.weakBridgeHandler = [uc seaf_addBridgeMessageHandlerWithTarget:self];
    [uc seaf_injectBridgeScripts];
    config.userContentController = uc;

    _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    _webView.navigationDelegate = self;
    _webView.translatesAutoresizingMaskIntoConstraints = NO;
    _webView.allowsBackForwardNavigationGestures = YES;

    [self.view addSubview:_webView];
    [self.view addSubview:_progressView];

    [NSLayoutConstraint activateConstraints:@[
        [_progressView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_progressView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_progressView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_progressView.heightAnchor constraintEqualToConstant:2],

        [_webView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [_webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];

    [self setupUserAgentAndLoad];
}

- (void)dealloc {
    @try {
        [_webView removeObserver:self forKeyPath:@"estimatedProgress"];
    } @catch (NSException *e) {}
    _webView.navigationDelegate = nil;
    WKUserContentController *uc = _webView.configuration.userContentController;
    if (uc) {
        [uc seaf_removeBridgeMessageHandler];
    }
}

#pragma mark - User Agent & Loading

- (void)setupUserAgentAndLoad {
    __weak typeof(self) wself = self;
    [self.webView evaluateJavaScript:@"navigator.userAgent" completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        NSString *ua = ([result isKindOfClass:[NSString class]]) ? (NSString *)result : nil;
        NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"";
        NSString *suffix = [NSString stringWithFormat:@" Seafile iOS/%@", appVersion.length > 0 ? appVersion : @"unknown"];
        if (ua && [ua isKindOfClass:[NSString class]]) {
            if ([ua rangeOfString:suffix].location == NSNotFound) {
                sself.webView.customUserAgent = [ua stringByAppendingString:suffix];
            } else {
                sself.webView.customUserAgent = ua;
            }
        } else {
            sself.webView.customUserAgent = suffix;
        }
        [sself loadWikiPage];
    }];
}

- (void)loadWikiPage {
    if (self.urlString.length == 0) return;

    // One-shot cookie cleanup after account switch (matching SDoc behavior)
    NSString *clearHost = [[NSUserDefaults standardUserDefaults] objectForKey:@"SEAF_COOKIE_CLEAR_HOST"];
    NSString *currentHost = [NSURL URLWithString:self.connection.address].host;
    if (clearHost.length > 0 && currentHost.length > 0 && [clearHost isEqualToString:currentHost]) {
        WKHTTPCookieStore *store = WKWebsiteDataStore.defaultDataStore.httpCookieStore;
        [store getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
            for (NSHTTPCookie *c in cookies) {
                if ([c.domain containsString:currentHost]) {
                    [store deleteCookie:c completionHandler:nil];
                }
            }
        }];
        NSHTTPCookieStorage *cookieStorage = NSHTTPCookieStorage.sharedHTTPCookieStorage;
        for (NSHTTPCookie *each in cookieStorage.cookies) {
            if ([each.domain containsString:currentHost]) {
                [cookieStorage deleteCookie:each];
            }
        }
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SEAF_COOKIE_CLEAR_HOST"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    NSString *token = self.connection.token;
    if (!token) {
        // Load without token
        NSURL *url = [NSURL URLWithString:self.urlString];
        if (url) {
            [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
        }
        return;
    }

    // Use mobile-login to establish web session, same as SDoc pages
    NSString *encodedNext = [self.urlString stringByAddingPercentEncodingWithAllowedCharacters:
                             [NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *mobileLoginURL = [NSString stringWithFormat:@"%@/mobile-login/?next=%@",
                                self.connection.address, encodedNext ?: self.urlString];
    NSURLRequest *req = [self.connection buildRequest:mobileLoginURL method:@"GET" form:nil];
    [self.webView loadRequest:req];
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        float progress = self.webView.estimatedProgress;
        [self.progressView setProgress:progress animated:YES];
        self.progressView.hidden = (progress >= 1.0);
    }
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    self.progressView.hidden = NO;
    [self.progressView setProgress:0.1 animated:NO];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.progressView.hidden = YES;
    // Update title from page title
    if (webView.title.length > 0) {
        self.title = webView.title;
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    self.progressView.hidden = YES;
    Warning("Wiki webview load failed: %@", error);
    // Show user-visible error (skip cancellation errors, e.g. from decidePolicyForNavigationAction)
    if (error.code != NSURLErrorCancelled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load wiki page", @"Seafile")];
        });
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSString *abs = navigationAction.request.URL.absoluteString ?: @"";
    if ([abs containsString:@"login/?next"] && ![abs containsString:@"mobile-login/?next"]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        // Extract the original target URL from the login redirect's 'next' parameter
        NSString *targetURL = nil;
        NSURLComponents *components = [NSURLComponents componentsWithString:abs];
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name isEqualToString:@"next"] && item.value.length > 0) {
                targetURL = item.value;
                break;
            }
        }
        if (!targetURL) {
            targetURL = webView.URL.absoluteString ?: self.urlString;
        }
        NSString *encodedNext = [targetURL stringByAddingPercentEncodingWithAllowedCharacters:
                                 [NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *mobileLoginURL = [NSString stringWithFormat:@"%@/mobile-login/?next=%@",
                                    self.connection.address, encodedNext ?: targetURL];
        NSURLRequest *req = [self.connection buildRequest:mobileLoginURL method:@"GET" form:nil];
        [webView loadRequest:req];
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

#pragma mark - WKScriptMessageHandler (JS Bridge)

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:SeafBridgeMessageName]) return;

    NSString *body = nil;
    if ([message.body isKindOfClass:[NSString class]]) {
        body = (NSString *)message.body;
    } else {
        return;
    }

    NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;

    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![dict isKindOfClass:[NSDictionary class]]) return;

    NSString *action = dict[@"action"];
    if (![action isKindOfClass:[NSString class]]) return;

    if ([action isEqualToString:@"app.version.get"]) {
        NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"";
        [self sendBridgeCallback:version];
    } else if ([action isEqualToString:@"app.toast.show"]) {
        id payload = dict[@"data"];
        if ([payload isKindOfClass:[NSString class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SVProgressHUD showInfoWithStatus:(NSString *)payload];
            });
        }
    } else if ([action isEqualToString:@"page.finish"]) {
        // Close the current wiki page, matching Android's PageFinishStrategy → activity.finish()
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.navigationController) {
                [self.navigationController popViewControllerAnimated:YES];
            } else {
                [self dismissViewControllerAnimated:YES completion:nil];
            }
        });
    } else if ([action isEqualToString:@"page.status.height.get"]) {
        CGFloat h = 0;
        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = self.view.window.windowScene;
            h = scene.statusBarManager.statusBarFrame.size.height;
        } else {
            h = UIApplication.sharedApplication.statusBarFrame.size.height;
        }
        [self sendBridgeCallback:[@(h) stringValue]];
    }
}

#pragma mark - Bridge Callback

- (void)sendBridgeCallback:(NSString *)text {
    // Match SDoc's bridge callback pattern.
    // The JS bridge shim's _invoke method dispatches to registered handlers.
    // For now this is a stub matching SDoc; the full callback mechanism
    // will be implemented when the web side adds callback ID support.
}

@end
