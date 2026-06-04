//
//  SeafWikiWebViewController.m
//  seafile
//
//  Created on 2026/5/12.
//

#import "SeafWikiWebViewController.h"
#import "SeafWebViewBridge.h"
#import "SeafSafariStyleToolbar.h"
#import <WebKit/WebKit.h>
#import "SVProgressHUD.h"
#import "Debug.h"

@interface SeafWikiWebViewController () <WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate, UIDocumentInteractionControllerDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, copy) NSString *urlString;
@property (nonatomic, strong) SeafConnection *connection;
@property (nonatomic, assign) BOOL showSafariToolbar;
@property (nonatomic, copy, nullable) NSString *wikiName;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) SeafWeakScriptMessageHandler *weakBridgeHandler;
@property (nonatomic, strong) UIDocumentInteractionController *docInteractionController;
@property (nonatomic, strong) SeafSafariStyleToolbar *safariToolbar;
@property (nonatomic, strong) NSLayoutConstraint *webViewBottomConstraint;
@end

@implementation SeafWikiWebViewController

- (instancetype)initWithURL:(NSString *)urlString connection:(SeafConnection *)connection {
    return [self initWithURL:urlString connection:connection showSafariToolbar:NO wikiName:nil];
}

- (instancetype)initWithURL:(NSString *)urlString connection:(SeafConnection *)connection showSafariToolbar:(BOOL)showSafariToolbar wikiName:(NSString *)wikiName {
    if (self = [super init]) {
        _urlString = urlString;
        _connection = connection;
        _showSafariToolbar = showSafariToolbar;
        _wikiName = [wikiName copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = NSLocalizedString(@"Wiki", @"Seafile");

    // On iPadOS 18+, the tab bar is hidden (hidesBottomBarWhenPushed) but still
    // reserves layout space. Extend under it so the view reaches the screen edge.
    if (IsIpad()) {
        self.extendedLayoutIncludesOpaqueBars = YES;
    }

    // WebView with JS Bridge
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *uc = [[WKUserContentController alloc] init];
    self.weakBridgeHandler = [uc seaf_addBridgeMessageHandlerWithTarget:self];
    [uc seaf_injectBridgeScripts];
    config.userContentController = uc;

    _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    _webView.navigationDelegate = self;
    _webView.UIDelegate = self;
    _webView.translatesAutoresizingMaskIntoConstraints = NO;
    _webView.allowsBackForwardNavigationGestures = YES;

    [self.view addSubview:_webView];

    if (_showSafariToolbar) {
        // Safari toolbar mode: full-screen WebView with floating toolbar at bottom
        NSLayoutYAxisAnchor *topAnchor = self.view.topAnchor;

        [NSLayoutConstraint activateConstraints:@[
            [_webView.topAnchor constraintEqualToAnchor:topAnchor],
            [_webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [_webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        ]];

        [self setupSafariToolbar];
    } else {
        // Standard mode: progress bar at top, WebView below safe area
        _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _progressView.progressTintColor = [UIColor colorWithRed:236/255.0 green:114/255.0 blue:31/255.0 alpha:1.0];
        _progressView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:_progressView];

        _webViewBottomConstraint = [_webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
        [NSLayoutConstraint activateConstraints:@[
            [_progressView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [_progressView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [_progressView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [_progressView.heightAnchor constraintEqualToConstant:2],

            [_webView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [_webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [_webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            _webViewBottomConstraint,
        ]];
    }

    [_webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];

    [self setupUserAgentAndLoad];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_showSafariToolbar) {
        [self.navigationController setNavigationBarHidden:YES animated:animated];

        // Reveal toolbar only after push transition fully completes.
        // On iPad split view, viewDidAppear fires during the transition,
        // so transitionCoordinator completion is the only reliable timing.
        id<UIViewControllerTransitionCoordinator> tc = self.transitionCoordinator;
        if (tc) {
            [tc animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
                if (!ctx.isCancelled) {
                    [self revealSafariToolbar];
                }
            }];
        } else {
            // No transition (e.g. appeared without animation), show immediately
            [self revealSafariToolbar];
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

/// Show the floating toolbar and shrink the webView to make room.
- (void)revealSafariToolbar {
    if (!_safariToolbar || _safariToolbar.alpha > 0) return;

    _webViewBottomConstraint.active = NO;
    _webViewBottomConstraint = [_webView.bottomAnchor constraintEqualToAnchor:_safariToolbar.topAnchor constant:-4];
    _webViewBottomConstraint.active = YES;

    [_safariToolbar showAnimated:YES];

    // Animate webView bottom in sync with toolbar spring animation
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
        [self.view layoutIfNeeded];
    } completion:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (_showSafariToolbar && self.isMovingFromParentViewController) {
        [self.navigationController setNavigationBarHidden:NO animated:animated];
    }
}

#pragma mark - Safari Style Toolbar

- (void)setupSafariToolbar {
    _safariToolbar = [[SeafSafariStyleToolbar alloc] initWithFrame:CGRectZero];
    _safariToolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_safariToolbar];

    // Toolbar starts hidden (alpha=0, translateY); shown in viewDidAppear: after push transition completes

    // Display wiki name immediately before web page loads
    if (_wikiName.length > 0) {
        [_safariToolbar updateTitle:_wikiName];
    }

    // Toolbar layout: pinned to bottom safe area with horizontal padding
    [NSLayoutConstraint activateConstraints:@[
        [_safariToolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_safariToolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_safariToolbar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [_safariToolbar.heightAnchor constraintEqualToConstant:44],
    ]];

    // Initially extend WebView to bottom (no gap while toolbar is hidden during push)
    _webViewBottomConstraint = [_webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    _webViewBottomConstraint.active = YES;

    // Setup callbacks
    __weak typeof(self) wself = self;
    _safariToolbar.onBackTapped = ^{
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        if (sself.navigationController) {
            [sself.navigationController popViewControllerAnimated:YES];
        } else {
            [sself dismissViewControllerAnimated:YES completion:nil];
        }
    };
    _safariToolbar.onRefreshTapped = ^{
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        [sself.webView reload];
    };
    _safariToolbar.onMoreTapped = ^{
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        [sself showMoreActions];
    };
}

- (void)showMoreActions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    // Get Link (matches SeaTable's "获取链接" behavior)
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Get Link", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showLinkInfo];
    }]];

    // Cancel
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIAlertActionStyleCancel handler:nil]];

    // iPad popover
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMaxX(self.view.bounds) - 60, CGRectGetMaxY(self.view.bounds) - 80, 44, 44);

    [self presentViewController:alert animated:YES completion:nil];
}

/// Show link info (title + URL + copy option), matching SeaTable's showLinkInfo
- (void)showLinkInfo {
    NSURL *url = self.webView.URL ?: [NSURL URLWithString:self.urlString];
    if (!url) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.webView.title
                                                                  message:url.absoluteString
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Copy Link", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = url.absoluteString;
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Link copied", @"Seafile")];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIAlertActionStyleCancel handler:nil]];

    // iPad popover
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMaxX(self.view.bounds) - 60, CGRectGetMaxY(self.view.bounds) - 80, 44, 44);

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)dealloc {
    @try {
        [_webView removeObserver:self forKeyPath:@"estimatedProgress"];
    } @catch (NSException *e) {}
    _webView.navigationDelegate = nil;
    _webView.UIDelegate = nil;
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
        if (_showSafariToolbar && _safariToolbar) {
            [_safariToolbar updateProgress:progress];
        } else {
            [self.progressView setProgress:progress animated:YES];
            self.progressView.hidden = (progress >= 1.0);
        }
    }
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    if (_showSafariToolbar && _safariToolbar) {
        [_safariToolbar updateProgress:0.1];
    } else {
        self.progressView.hidden = NO;
        [self.progressView setProgress:0.1 animated:NO];
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (_showSafariToolbar && _safariToolbar) {
        [_safariToolbar updateProgress:1.0];
        if (webView.title.length > 0) {
            [_safariToolbar updateTitle:webView.title];
        }
    } else {
        self.progressView.hidden = YES;
    }
    // Update title from page title
    if (webView.title.length > 0) {
        self.title = webView.title;
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (_showSafariToolbar && _safariToolbar) {
        [_safariToolbar updateProgress:1.0];
    } else {
        self.progressView.hidden = YES;
    }
    Warning("Wiki webview load failed: %@", error);
    // Skip our own cancellations: NSURLErrorCancelled from the navigation-action
    // policy, WebKit error 102 from cancelling a response to download it.
    BOOL policyCancelled = ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102);
    if (error.code != NSURLErrorCancelled && !policyCancelled) {
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

#pragma mark - Download Handling

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    // Download non-renderable responses (attachments) instead of dropping them.
    if (navigationResponse.forMainFrame && !navigationResponse.canShowMIMEType) {
        decisionHandler(WKNavigationResponsePolicyCancel);
        [self downloadFileFromURL:navigationResponse.response.URL
                suggestedFilename:navigationResponse.response.suggestedFilename];
        return;
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)downloadFileFromURL:(NSURL *)url suggestedFilename:(NSString *)suggestedFilename {
    if (!url) return;
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Downloading", @"Seafile")];

    // suggestedFilename already decodes Content-Disposition (incl. RFC 5987)
    NSString *fileName = suggestedFilename.lastPathComponent;
    if (fileName.length == 0) {
        fileName = url.lastPathComponent.length > 0 ? url.lastPathComponent : @"download";
    }

    // Copy the WKWebView session cookies so authenticated links work.
    __weak typeof(self) wself = self;
    NSString *userAgent = self.webView.customUserAgent;
    WKHTTPCookieStore *cookieStore = self.webView.configuration.websiteDataStore.httpCookieStore;
    [cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        for (NSHTTPCookie *cookie in cookies) {
            [config.HTTPCookieStorage setCookie:cookie];
        }

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        if (userAgent.length > 0) {
            [request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
        }

        NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
        NSURLSessionDownloadTask *task = [session downloadTaskWithRequest:request completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
            NSURL *destURL = nil;
            if (!error && location && status < 400) {
                NSURL *dir = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"WikiDownloads" isDirectory:YES];
                [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
                destURL = [dir URLByAppendingPathComponent:fileName];
                [[NSFileManager defaultManager] removeItemAtURL:destURL error:nil];
                NSError *moveError = nil;
                if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:destURL error:&moveError]) {
                    Warning("Failed to move downloaded file: %@", moveError);
                    destURL = nil;
                }
            } else {
                Warning("Wiki download failed (status %ld): %@", (long)status, error);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (destURL) {
                    [SVProgressHUD dismiss];
                    [wself presentDownloadedFileAtURL:destURL];
                } else {
                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to download file", @"Seafile")];
                }
            });
            [session finishTasksAndInvalidate];
        }];
        [task resume];
    }];
}

- (void)presentDownloadedFileAtURL:(NSURL *)fileURL {
    if (!self.view.window) return; // controller left the screen during download
    self.docInteractionController = [UIDocumentInteractionController interactionControllerWithURL:fileURL];
    self.docInteractionController.delegate = self;
    CGRect rect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    if (![self.docInteractionController presentOptionsMenuFromRect:rect inView:self.view animated:YES]) {
        [self.docInteractionController presentPreviewAnimated:YES];
    }
}

#pragma mark - UIDocumentInteractionControllerDelegate

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    return self;
}

#pragma mark - WKUIDelegate

// target=_blank links are silently ignored without a UIDelegate; load them in place.
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    if (!navigationAction.targetFrame || !navigationAction.targetFrame.isMainFrame) {
        [webView loadRequest:navigationAction.request];
    }
    return nil;
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

    id callbackId = dict[@"__cbId"]; // response-callback id from the bridge shim

    if ([action isEqualToString:@"app.version.get"]) {
        NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
        NSString *version = [infoDict objectForKey:@"CFBundleShortVersionString"] ?: @"";
        NSString *build = [infoDict objectForKey:@"CFBundleVersion"] ?: @"";
        // Android returns "{versionName}-{versionCode}"
        NSString *result = build.length > 0 ? [NSString stringWithFormat:@"%@-%@", version, build] : version;
        [self sendBridgeCallback:result forCallbackId:callbackId];
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
        [self sendBridgeCallback:[@(h) stringValue] forCallbackId:callbackId];
    }
}

#pragma mark - Bridge Callback

- (void)sendBridgeCallback:(NSString *)text forCallbackId:(id)callbackId {
    // Empty results never fire the callback, matching Android.
    [self.webView seaf_sendBridgeResponse:text forCallbackId:callbackId];
}

@end
