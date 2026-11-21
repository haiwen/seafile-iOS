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

#pragma mark - Download operation

typedef NS_ENUM(NSInteger, SeafWikiExportKind) {
    SeafWikiExportKindNone = 0,     // a file response that is not a wiki export
    SeafWikiExportKindMarkdown,
    SeafWikiExportKindSdoc,
};

typedef NS_ENUM(NSInteger, SeafWikiDownloadPhase) {
    SeafWikiDownloadPhaseAwaitingResponse = 0, // export request sent, no response yet
    SeafWikiDownloadPhaseDownloading,          // WKDownload is writing the file
    SeafWikiDownloadPhaseAwaitingSave,         // file ready, save sheet not on screen yet
    SeafWikiDownloadPhaseSaving,               // save sheet on screen
    SeafWikiDownloadPhaseFinished,
};

typedef NS_ENUM(NSInteger, SeafWikiDownloadOutcome) {
    SeafWikiDownloadOutcomeSaved,
    SeafWikiDownloadOutcomeCancelled,   // closed by the user, nothing to report
    SeafWikiDownloadOutcomeFailed,
    SeafWikiDownloadOutcomeAbandoned,   // the wiki page was left
};

// Routes relative to the server root (connection.address may carry a sub path).
static NSString * const SeafWikiExportEntryPattern = @"^api/v2\\.1/wiki2/[-0-9a-f]{36}/page/[-0-9a-zA-Z]{4}/export/?$";
static NSString * const SeafSdocExportTargetPattern = @"^api/v2\\.1/seadoc/export/[-0-9a-f]{36}/?$";
static NSString * const SeafWikiRootPattern = @"^wikis/([-0-9a-f]{36})/?$";
static NSString * const SeafWikiPagePattern = @"^wikis/([-0-9a-f]{36})/[-0-9a-zA-Z]{4}/?$";

/// Script message the history observer posts to (see -historyObserverScript).
static NSString * const SeafWikiHistoryMessageName = @"seafWikiHistory";

/// One download-and-save flow: from the export tap (or a file response) until
/// the save sheet closes, the download fails, or the wiki page is left.
@interface SeafWikiDownloadOperation : NSObject
@property (nonatomic, assign) SeafWikiExportKind kind;
@property (nonatomic, assign) SeafWikiDownloadPhase phase;
@property (nonatomic, copy, nullable) NSString *pageTitle;
@property (nonatomic, strong, nullable) NSURL *exportURL;
@property (nonatomic, strong, nullable) WKNavigation *navigation;
/// WKNavigationResponsePolicyDownload was returned for the navigation's response.
/// WebKit hands over the WKDownload later (once the download has started) and may
/// still drop the conversion (e.g. a Safe Browsing warning the user backs out of),
/// so this is not the same as having a download: see `download`.
@property (nonatomic, assign) BOOL downloadRequested;
/// The sdoc export's one expected redirect target, recorded on its navigation.
@property (nonatomic, strong, nullable) NSURL *sdocTargetURL;
/// Blocks any remaining policy callbacks on the rejected export navigation.
@property (nonatomic, assign) BOOL rejectedRedirect;
/// The response that was turned into a download. A retry can have the same URL.
@property (nonatomic, strong, nullable) WKNavigationResponse *downloadResponse;
@property (nonatomic, assign) BOOL waitingForDownloadDelivery;
/// The WKDownload WebKit delivered for this operation (nil until then).
@property (nonatomic, strong, nullable) WKDownload *download;
@property (nonatomic, strong, nullable) NSURL *directoryURL;
@property (nonatomic, strong, nullable) NSURL *fileURL;
@property (nonatomic, strong, nullable) UIDocumentPickerViewController *picker;
/// The save sheet's presentation completed (its completion block ran).
@property (nonatomic, assign) BOOL pickerPresented;
@property (nonatomic, assign) NSInteger presentFailures;
@end

@implementation SeafWikiDownloadOperation
@end

#pragma mark - Header helpers

static NSString *SeafResponseHeader(NSURLResponse *response, NSString *name)
{
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) return nil;
    return [(NSHTTPURLResponse *)response valueForHTTPHeaderField:name];
}

static BOOL SeafIsAttachmentDisposition(NSString *disposition)
{
    if (disposition.length == 0) return NO;
    NSString *type = [[disposition componentsSeparatedByString:@";"].firstObject
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [type caseInsensitiveCompare:@"attachment"] == NSOrderedSame;
}

static BOOL SeafDispositionHasFileName(NSString *disposition)
{
    if (disposition.length == 0) return NO;
    return [disposition rangeOfString:@"(^|;)\\s*filename\\*?\\s*="
                              options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;
}

/// Seahub's Markdown export writes `'attachment;filename*=utf-8''%s;filename="%s"'`;
/// Python joins the adjacent literals and drops the `''`, so the header reads
/// `filename*=utf-8<quoted>;filename="<quoted>"`. Returns the still percent-encoded
/// fallback name when the header has exactly that shape, nil otherwise.
static NSString *SeafMalformedSeahubFileName(NSString *disposition)
{
    if (disposition.length == 0) return nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"filename\\*\\s*=\\s*utf-8([^;'\"\\s]+)\\s*;\\s*filename\\s*=\\s*\"([^\"]*)\""
                                                                        options:NSRegularExpressionCaseInsensitive
                                                                          error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:disposition options:0 range:NSMakeRange(0, disposition.length)];
    if (!m) return nil;
    NSString *star = [disposition substringWithRange:[m rangeAtIndex:1]];
    NSString *plain = [disposition substringWithRange:[m rangeAtIndex:2]];
    return [star isEqualToString:plain] ? plain : nil;
}

static NSString *SeafSanitizedFileName(NSString *name)
{
    if (name.length == 0) return @"";
    NSMutableCharacterSet *bad = [NSMutableCharacterSet controlCharacterSet];
    [bad addCharactersInString:@"/\\:"];
    NSArray<NSString *> *parts = [name componentsSeparatedByCharactersInSet:bad];
    NSString *joined = [parts componentsJoinedByString:@"_"];
    return [joined stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/// Content types of pages and error payloads, never of an exported file.
static BOOL SeafIsErrorBodyMIMEType(NSString *mime)
{
    if (mime.length == 0) return NO;
    return [mime isEqualToString:@"text/html"]
        || [mime isEqualToString:@"application/xhtml+xml"]
        || [mime isEqualToString:@"application/json"]
        || [mime isEqualToString:@"text/json"]
        || [mime hasSuffix:@"+json"];
}

static NSInteger SeafDefaultPortForScheme(NSString *scheme)
{
    if ([scheme caseInsensitiveCompare:@"https"] == NSOrderedSame) return 443;
    if ([scheme caseInsensitiveCompare:@"http"] == NSOrderedSame) return 80;
    return -1;
}

/// Same origin, path and query (ignores the fragment).
static BOOL SeafIsSameResource(NSURL *a, NSURL *b)
{
    if (!a || !b) return NO;
    NSURLComponents *ca = [NSURLComponents componentsWithURL:a resolvingAgainstBaseURL:YES];
    NSURLComponents *cb = [NSURLComponents componentsWithURL:b resolvingAgainstBaseURL:YES];
    if (!ca || !cb) return NO;
    if ([ca.scheme ?: @"" caseInsensitiveCompare:cb.scheme ?: @""] != NSOrderedSame) return NO;
    if ([ca.host ?: @"" caseInsensitiveCompare:cb.host ?: @""] != NSOrderedSame) return NO;
    NSInteger portA = ca.port ? ca.port.integerValue : SeafDefaultPortForScheme(ca.scheme);
    NSInteger portB = cb.port ? cb.port.integerValue : SeafDefaultPortForScheme(cb.scheme);
    if (portA != portB) return NO;
    return [ca.percentEncodedPath ?: @"" isEqualToString:cb.percentEncodedPath ?: @""]
        && [ca.percentEncodedQuery ?: @"" isEqualToString:cb.percentEncodedQuery ?: @""];
}

static BOOL SeafIsLoginRedirectURL(NSURL *url)
{
    if (!url) return NO;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (![components.path hasSuffix:@"login/"] || [components.path hasSuffix:@"mobile-login/"]) return NO;
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"next"]) return YES;
    }
    return NO;
}

@interface SeafWikiWebViewController () <WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate, WKDownloadDelegate, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate>
@property (nonatomic, strong) WKWebView *webView;
// Re-routes of a login redirect through mobile-login (see -shouldRerouteToMobileLogin).
@property (nonatomic, assign) NSUInteger mobileLoginReroutes;
@property (nonatomic, strong) NSDate *mobileLoginRerouteWindowStart;
@property (nonatomic, copy) NSString *urlString;
@property (nonatomic, strong) SeafConnection *connection;
@property (nonatomic, assign) BOOL showSafariToolbar;
@property (nonatomic, copy, nullable) NSString *wikiName;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) SeafWeakScriptMessageHandler *weakBridgeHandler;
@property (nonatomic, strong) SeafWeakScriptMessageHandler *weakHistoryHandler;
@property (nonatomic, strong) SeafSafariStyleToolbar *safariToolbar;
/// Wiki root entries wiki2 leaves behind when it pushes its first page right after
/// loading: going back to one changes the address but not the page, so the back
/// button skips them. One per wiki2 document opened at its root (another wiki can
/// be opened in the same web view); pruned once they leave the history.
@property (nonatomic, strong) NSMutableArray<WKBackForwardListItem *> *placeholderHistoryItems;
@property (nonatomic, strong) NSLayoutConstraint *webViewBottomConstraint;

// Download and save (one flow at a time)
@property (nonatomic, strong, nullable) SeafWikiDownloadOperation *currentDownload;
/// Operations by navigation, kept until that navigation's last callback so a late
/// callback is matched to its own operation rather than to the current one.
@property (nonatomic, strong) NSMapTable<WKNavigation *, SeafWikiDownloadOperation *> *operationsByNavigation;
@property (nonatomic, strong) NSMapTable<WKDownload *, SeafWikiDownloadOperation *> *operationsByDownload;
@property (nonatomic, strong, nullable) WKNavigation *provisionalNavigation;
/// On older iOS, wait for a navigation callback before rerouting an ambiguous
/// login request that arrives while an export is provisional.
@property (nonatomic, strong, nullable) NSURL *deferredLoginURL;
@property (nonatomic, assign) BOOL needsWebContentReload;
@property (nonatomic, strong, nullable) NSDate *lastWebContentReload;
/// The "More" / "Get Link" sheet this controller is showing; a finished download
/// waits for it to close before presenting the save sheet.
@property (nonatomic, weak, nullable) UIAlertController *ownActionSheet;
@property (nonatomic, assign) BOOL saveSheetRetryScheduled;
@property (nonatomic, assign) BOOL wikiExitInProgress;
@property (nonatomic, assign) BOOL leavingWiki;
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
        NSPointerFunctionsOptions keyOptions = NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality;
        _operationsByNavigation = [NSMapTable mapTableWithKeyOptions:keyOptions valueOptions:NSPointerFunctionsStrongMemory];
        _operationsByDownload = [NSMapTable mapTableWithKeyOptions:keyOptions valueOptions:NSPointerFunctionsStrongMemory];
        _placeholderHistoryItems = [NSMutableArray array];
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
    NSString *historyScript = [self historyObserverScript];
    if (historyScript) {
        // Same-document history changes (pushState, image previews) have no
        // navigation callback; the page reports them so the back button keeps up.
        self.weakHistoryHandler = [[SeafWeakScriptMessageHandler alloc] initWithTarget:self];
        [uc addScriptMessageHandler:self.weakHistoryHandler name:SeafWikiHistoryMessageName];
        [uc addUserScript:[[WKUserScript alloc] initWithSource:historyScript
                                                 injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                              forMainFrameOnly:YES]];
    }
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
    // Back button state and the toolbar title follow in-page navigation too.
    [_webView addObserver:self forKeyPath:@"canGoBack" options:NSKeyValueObservingOptionNew context:nil];
    [_webView addObserver:self forKeyPath:@"URL" options:NSKeyValueObservingOptionNew context:nil];
    [_webView addObserver:self forKeyPath:@"title" options:NSKeyValueObservingOptionNew context:nil];
    [_webView addObserver:self forKeyPath:@"loading" options:NSKeyValueObservingOptionNew context:nil];

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
    [self reloadTerminatedWebContentIfVisible];
    // A download that finished while this page was off screen (e.g. another tab
    // was selected) presents its save sheet once the page is back.
    [self presentSaveSheetIfPossible];
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
    BOOL leaving = self.isMovingFromParentViewController || self.isBeingDismissed || self.navigationController.isBeingDismissed;
    if (!leaving) return;
    self.wikiExitInProgress = YES;

    // Defer until the transition completes: if the interactive pop gesture is
    // cancelled, the page stays (nav bar hidden, download flow kept).
    UINavigationController *nav = self.navigationController;
    BOOL restoreNavBar = _showSafariToolbar && self.isMovingFromParentViewController;
    __weak typeof(self) wself = self;
    id<UIViewControllerTransitionCoordinator> tc = self.transitionCoordinator;
    BOOL observing = [tc animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
        if (ctx.isCancelled) {
            wself.wikiExitInProgress = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [wself reloadTerminatedWebContentIfVisible];
                [wself presentSaveSheetIfPossible];
            });
            return;
        }
        if (restoreNavBar) {
            [nav setNavigationBarHidden:NO animated:NO];
        }
        [wself wikiDidLeave];
    }];
    if (!observing) {
        if (restoreNavBar) {
            [nav setNavigationBarHidden:NO animated:animated];
        }
        [self wikiDidLeave];
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

    // Nothing to go back to until the page has history of its own.
    [_safariToolbar setBackEnabled:NO animated:NO];

    // Setup callbacks
    __weak typeof(self) wself = self;
    _safariToolbar.onBackTapped = ^{
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        [sself goBackInPage];
    };
    _safariToolbar.onCloseTapped = ^{
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        [sself closeWiki];
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

/// Leaves the whole wiki page (toolbar close, the page's `page.finish`).
- (void)closeWiki {
    UINavigationController *nav = self.navigationController;
    if ([self isClosingWiki]) return;
    if (nav ? (nav.topViewController != self || nav.viewControllers.count < 2) : !self.presentingViewController) return;
    self.wikiExitInProgress = YES;
    void (^leave)(void) = ^{
        if (nav) {
            if (nav.topViewController == self && [nav popViewControllerAnimated:YES]) return;
            if ([nav.viewControllers containsObject:self]) {
                self.wikiExitInProgress = NO;
                [self presentSaveSheetIfPossible];
            } else {
                [self wikiDidLeave];
            }
        } else {
            [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
                [self wikiDidLeave];
            }];
        }
    };
    // Close a sheet this page is presenting (e.g. the save sheet) first.
    UIViewController *presented = self.presentedViewController;
    id<UIViewControllerTransitionCoordinator> dismissal = presented.isBeingDismissed ? presented.transitionCoordinator : nil;
    if (dismissal && [dismissal animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
        if (ctx.isCancelled) {
            [self dismissViewControllerAnimated:NO completion:leave];
        } else {
            leave();
        }
    }]) {
        return;
    }
    if (presented && !presented.isBeingDismissed) {
        [self dismissViewControllerAnimated:NO completion:leave];
    } else {
        leave();
    }
}

#pragma mark - In-page history (back button)

/// Back goes back within the page only; leaving is the close button's job.
- (void)goBackInPage {
    WKBackForwardListItem *target = [self backTargetItem];
    if (target) {
        // An explicit item rather than -goBack: WebKit may skip entries a script
        // added without user interaction when going back through the API.
        [self.webView goToBackForwardListItem:target];
    }
}

/// The closest back entry, skipping wiki2's initial placeholders.
- (nullable WKBackForwardListItem *)backTargetItem {
    WKBackForwardList *list = self.webView.backForwardList;
    NSArray<WKBackForwardListItem *> *backList = list.backList;
    NSArray<WKBackForwardListItem *> *forwardList = list.forwardList;
    WKBackForwardListItem *current = list.currentItem;
    // Entries that have left the history (e.g. dropped by a new navigation).
    NSIndexSet *gone = [self.placeholderHistoryItems indexesOfObjectsPassingTest:^BOOL(WKBackForwardListItem *item, NSUInteger idx, BOOL *stop) {
        return item != current && ![backList containsObject:item] && ![forwardList containsObject:item];
    }];
    [self.placeholderHistoryItems removeObjectsAtIndexes:gone];

    for (WKBackForwardListItem *item in backList.reverseObjectEnumerator) {
        if (![self.placeholderHistoryItems containsObject:item]) {
            return item;
        }
    }
    return nil;
}

- (void)updateBackButtonState {
    if (!_safariToolbar) return;
    [_safariToolbar setBackEnabled:([self backTargetItem] != nil) animated:YES];
}

/// Origin of the server as `location.origin` writes it (default port omitted).
- (nullable NSString *)serverOrigin {
    NSURL *base = [NSURL URLWithString:self.connection.address];
    if (!base.scheme || !base.host) return nil;
    NSString *scheme = base.scheme.lowercaseString;
    NSString *origin = [NSString stringWithFormat:@"%@://%@", scheme, base.host.lowercaseString];
    if (base.port && base.port.integerValue != SeafDefaultPortForScheme(scheme)) {
        origin = [origin stringByAppendingFormat:@":%@", base.port];
    }
    return origin;
}

/// Document-start script for pages of this server: reports pushState,
/// replaceState and popstate after the page's own call has run, so the native
/// side reads an already updated back/forward list. The page's History
/// behaviour is unchanged.
- (nullable NSString *)historyObserverScript {
    NSString *origin = [self serverOrigin];
    if (!origin) return nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[origin] options:0 error:nil];
    NSString *originLiteral = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
    if (!originLiteral) return nil;
    return [NSString stringWithFormat:
            @"(function(){\n"
            "  if (location.origin !== %@[0] || window.__seafWikiHistoryObserver) return;\n"
            "  window.__seafWikiHistoryObserver = true;\n"
            "  var handlers = window.webkit && window.webkit.messageHandlers;\n"
            "  var handler = handlers && handlers.%@;\n"
            "  if (!handler) return;\n"
            "  var pushes = 0;\n"
            "  function notify(kind, prevPath, prevStateNull) {\n"
            "    try { handler.postMessage({kind: kind, path: location.pathname, prevPath: prevPath, prevStateNull: prevStateNull, pushIndex: pushes}); } catch (e) {}\n"
            "  }\n"
            "  ['pushState', 'replaceState'].forEach(function (name) {\n"
            "    var original = history[name];\n"
            "    if (typeof original !== 'function') return;\n"
            "    history[name] = function () {\n"
            "      var prevPath = location.pathname;\n"
            "      var prevStateNull = (history.state === null || history.state === undefined);\n"
            "      var result = original.apply(this, arguments);\n"
            "      if (name === 'pushState') pushes += 1;\n"
            "      notify(name, prevPath, prevStateNull);\n"
            "      return result;\n"
            "    };\n"
            "  });\n"
            "  window.addEventListener('popstate', function () { notify('popstate', null, false); });\n"
            "})();", originLiteral, SeafWikiHistoryMessageName];
}

- (BOOL)isServerSecurityOrigin:(WKSecurityOrigin *)origin {
    NSURL *base = [NSURL URLWithString:self.connection.address];
    if (!origin || !base.scheme || !base.host) return NO;
    if ([origin.protocol caseInsensitiveCompare:base.scheme] != NSOrderedSame) return NO;
    if ([origin.host caseInsensitiveCompare:base.host] != NSOrderedSame) return NO;
    NSInteger originPort = origin.port != 0 ? origin.port : SeafDefaultPortForScheme(origin.protocol);
    NSInteger basePort = base.port ? base.port.integerValue : SeafDefaultPortForScheme(base.scheme);
    return originPort == basePort;
}

- (void)handleHistoryMessage:(WKScriptMessage *)message {
    if (!message.frameInfo.isMainFrame || ![self isServerSecurityOrigin:message.frameInfo.securityOrigin]) return;
    NSDictionary *body = [message.body isKindOfClass:[NSDictionary class]] ? message.body : nil;
    if (!body) return;

    // wiki2 opened at its root pushes its first page right after loading. The root
    // entry it leaves behind has no state, so going back to it changes nothing.
    // Mark it only when exactly that is confirmed; otherwise history is used as is.
    NSString *kind = [body[@"kind"] isKindOfClass:[NSString class]] ? body[@"kind"] : nil;
    NSString *path = [body[@"path"] isKindOfClass:[NSString class]] ? body[@"path"] : nil;
    NSString *prevPath = [body[@"prevPath"] isKindOfClass:[NSString class]] ? body[@"prevPath"] : nil;
    BOOL firstPush = [body[@"pushIndex"] isKindOfClass:[NSNumber class]] && [body[@"pushIndex"] integerValue] == 1;
    BOOL prevStateNull = [body[@"prevStateNull"] isKindOfClass:[NSNumber class]] && [body[@"prevStateNull"] boolValue];
    if ([kind isEqualToString:@"pushState"] && firstPush && prevStateNull && path && prevPath) {
        NSString *wikiId = [self wikiIdInURL:[self serverURLForPagePath:prevPath] pattern:SeafWikiRootPattern];
        NSString *pageWikiId = [self wikiIdInURL:[self serverURLForPagePath:path] pattern:SeafWikiPagePattern];
        if (wikiId && [wikiId isEqualToString:pageWikiId]) {
            WKBackForwardListItem *rootItem = self.webView.backForwardList.backItem;
            if (rootItem && [wikiId isEqualToString:[self wikiIdInURL:rootItem.URL pattern:SeafWikiRootPattern]]
                && ![self.placeholderHistoryItems containsObject:rootItem]) {
                [self.placeholderHistoryItems addObject:rootItem];
            }
        }
    }
    [self updateBackButtonState];
}

/// A `location.pathname` (percent-encoded, absolute) on this server as a URL.
- (nullable NSURL *)serverURLForPagePath:(NSString *)pathname {
    NSURL *base = [NSURL URLWithString:self.connection.address];
    if (!base || pathname.length == 0) return nil;
    return [NSURL URLWithString:pathname relativeToURL:base].absoluteURL;
}

/// The wiki id when url's path (relative to the server root) matches pattern.
- (nullable NSString *)wikiIdInURL:(nullable NSURL *)url pattern:(NSString *)pattern {
    NSString *relative = url ? [self serverRelativePathForURL:url] : nil;
    if (!relative) return nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:relative options:0 range:NSMakeRange(0, relative.length)];
    return m ? [relative substringWithRange:[m rangeAtIndex:1]] : nil;
}

- (void)showMoreActions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    // Get Link (matches SeaTable's "获取链接" behavior)
    __weak typeof(self) wself = self;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Get Link", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [wself showLinkInfo];
        [wself ownActionSheetDidClose];
    }]];

    // Cancel (on iPad, tapping outside the popover also runs this handler)
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [wself ownActionSheetDidClose];
    }]];

    // iPad popover anchored to the actual More button
    UIView *moreView = _safariToolbar.moreButtonView;
    if (moreView) {
        alert.popoverPresentationController.sourceView = moreView;
        alert.popoverPresentationController.sourceRect = moreView.bounds;
    } else {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMaxX(self.view.bounds) - 60, CGRectGetMaxY(self.view.bounds) - 80, 44, 44);
    }

    self.ownActionSheet = alert;
    [self presentViewController:alert animated:YES completion:nil];
}

/// Show link info (title + URL + copy option), matching SeaTable's showLinkInfo
- (void)showLinkInfo {
    // While an export navigation is pending, webView.URL is the export API
    // address; the committed history item is the page the user is looking at.
    NSURL *url = self.webView.backForwardList.currentItem.URL ?: self.webView.URL ?: [NSURL URLWithString:self.urlString];
    if (!url) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.webView.title
                                                                  message:url.absoluteString
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) wself = self;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Copy Link", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = url.absoluteString;
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Link copied", @"Seafile")];
        [wself ownActionSheetDidClose];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [wself ownActionSheetDidClose];
    }]];

    // iPad popover anchored to the actual More button
    UIView *moreView = _safariToolbar.moreButtonView;
    if (moreView) {
        alert.popoverPresentationController.sourceView = moreView;
        alert.popoverPresentationController.sourceRect = moreView.bounds;
    } else {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMaxX(self.view.bounds) - 60, CGRectGetMaxY(self.view.bounds) - 80, 44, 44);
    }

    self.ownActionSheet = alert;
    [self presentViewController:alert animated:YES completion:nil];
}

/// Called from every action of the "More" / "Get Link" sheets: a download that
/// finished while one of them was open presents its save sheet now. A chained
/// sheet (Get Link) is still on screen at this point and is waited for.
- (void)ownActionSheetDidClose {
    __weak typeof(self) wself = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [wself presentSaveSheetIfPossible];
    });
}

- (void)dealloc {
    for (NSString *keyPath in @[@"estimatedProgress", @"canGoBack", @"URL", @"title", @"loading"]) {
        @try {
            [_webView removeObserver:self forKeyPath:keyPath];
        } @catch (NSException *e) {}
    }
    _webView.navigationDelegate = nil;
    _webView.UIDelegate = nil;
    WKUserContentController *uc = _webView.configuration.userContentController;
    if (uc) {
        [uc seaf_removeBridgeMessageHandler];
        if (_weakHistoryHandler) {
            [uc removeScriptMessageHandlerForName:SeafWikiHistoryMessageName];
        }
    }
    // Fallback only: leaving the page normally ends the flow in -wikiDidLeave.
    SeafWikiDownloadOperation *op = _currentDownload;
    if (op && op.phase != SeafWikiDownloadPhaseFinished) {
        BOOL showsProgress = (op.phase == SeafWikiDownloadPhaseAwaitingResponse || op.phase == SeafWikiDownloadPhaseDownloading);
        NSURL *dir = op.directoryURL;
        if (op.phase == SeafWikiDownloadPhaseDownloading && op.download) {
            [op.download cancel:^(NSData *resumeData) {
                if (dir) [[NSFileManager defaultManager] removeItemAtURL:dir error:nil];
            }];
        } else if (dir) {
            [[NSFileManager defaultManager] removeItemAtURL:dir error:nil];
        }
        op.phase = SeafWikiDownloadPhaseFinished;
        if (showsProgress) {
            [SVProgressHUD dismiss];
        }
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
    } else if ([keyPath isEqualToString:@"title"]) {
        // wiki2 switches pages in place and only updates document.title.
        NSString *title = self.webView.title;
        if (title.length > 0) {
            self.title = title;
            [_safariToolbar updateTitle:title];
        }
    } else if ([keyPath isEqualToString:@"canGoBack"] || [keyPath isEqualToString:@"URL"]) {
        [self updateBackButtonState];
    } else if ([keyPath isEqualToString:@"loading"] && !self.webView.isLoading) {
        [self awaitDownloadDeliveryForOperation:self.currentDownload];
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

    self.provisionalNavigation = navigation;
    SeafWikiDownloadOperation *pending = [self pendingExportOperation];
    if (pending && navigation && pending.navigation != navigation) {
        if (!pending.navigation && SeafIsSameResource(webView.URL, pending.exportURL)) {
            [self bindOperation:pending toNavigation:navigation];
        } else {
            // A different main-frame load replaced the uncommitted export.
            [self finishDownloadOperation:pending outcome:SeafWikiDownloadOutcomeCancelled];
        }
    }

    NSURL *loginURL = self.deferredLoginURL;
    if (navigation && pending.navigation != navigation && SeafIsSameResource(webView.URL, loginURL)) {
        // The new provisional navigation owns this login request.
        self.deferredLoginURL = nil;
        if (![self isClosingWiki] && [self shouldRerouteToMobileLogin]) {
            [self loadMobileLoginForRedirectURL:loginURL];
        }
    }
}

- (void)webView:(WKWebView *)webView didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation {
    SeafWikiDownloadOperation *op = [self.operationsByNavigation objectForKey:navigation];
    if (!op || op != self.currentDownload || op.phase != SeafWikiDownloadPhaseAwaitingResponse || op.downloadRequested) return;
    self.deferredLoginURL = nil;
    NSURL *target = webView.URL;
    // This callback identifies the navigation and its actual server redirect.
    if (op.kind == SeafWikiExportKindSdoc && !op.sdocTargetURL && [self isSdocExportTargetURL:target]) {
        op.sdocTargetURL = target;
        return;
    }
    [self rejectExportRedirectForOperation:op toURL:target];
    [webView stopLoading];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    SeafWikiDownloadOperation *op = [self.operationsByNavigation objectForKey:navigation];
    [self.operationsByNavigation removeObjectForKey:navigation];
    if (self.provisionalNavigation == navigation) self.provisionalNavigation = nil;
    if (op.downloadRequested) {
        [self awaitDownloadDeliveryForOperation:op];
    } else if (op && op == [self pendingExportOperation]) {
        [self finishDownloadOperation:op outcome:SeafWikiDownloadOutcomeFailed];
    }
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
    [self updateBackButtonState];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (self.provisionalNavigation == navigation) {
        self.provisionalNavigation = nil;
        if (_showSafariToolbar && _safariToolbar) {
            [_safariToolbar updateProgress:1.0];
        } else {
            self.progressView.hidden = YES;
        }
    }

    // WebKit error 102: the response was cancelled by policy (to download it or
    // because the page was not wanted); NSURLErrorCancelled: our own cancellations.
    BOOL policyCancelled = ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102);
    BOOL cancelled = ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled);

    SeafWikiDownloadOperation *op = [self.operationsByNavigation objectForKey:navigation];
    if (!op) {
        SeafWikiDownloadOperation *pending = [self pendingExportOperation];
        NSURL *failedURL = error.userInfo[NSURLErrorFailingURLErrorKey];
        if (pending && !pending.navigation && [failedURL isKindOfClass:[NSURL class]]
            && SeafIsSameResource(failedURL, pending.exportURL)) {
            op = pending;
        }
    }
    if (op) {
        // This is the navigation's last callback.
        [self.operationsByNavigation removeObjectForKey:navigation];
        // A navigation turned into a download ends with 102, sometimes only after
        // the download (and even its save sheet) is done: it is not a failure.
        // But WebKit may also drop the conversion without ever delivering a
        // WKDownload; then nothing else would end the operation.
        if (op.downloadRequested) {
            if (!op.download && op.phase == SeafWikiDownloadPhaseAwaitingResponse) {
                [self awaitDownloadDeliveryForOperation:op];
            }
            return;
        }
        if (op.phase == SeafWikiDownloadPhaseAwaitingResponse) {
            if (!cancelled) {
                Warning("Wiki export failed before a response: %@", error);
            }
            // Cancelled: another navigation replaced the export, end it silently.
            [self finishDownloadOperation:op
                                  outcome:cancelled ? SeafWikiDownloadOutcomeCancelled : SeafWikiDownloadOutcomeFailed];
        }
        return;
    }

    Warning("Wiki webview load failed: %@", error);
    if (!cancelled && !policyCancelled && ![self isClosingWiki]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self isClosingWiki] && ![self isDownloadInProgress]) {
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load wiki page", @"Seafile")];
            }
        });
    }
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView
{
    self.provisionalNavigation = nil;
    self.deferredLoginURL = nil;
    [self.operationsByNavigation removeAllObjects];
    SeafWikiDownloadOperation *op = self.currentDownload;
    if (op && op.phase == SeafWikiDownloadPhaseAwaitingResponse) {
        [self finishDownloadOperation:op outcome:SeafWikiDownloadOutcomeFailed];
    }
    // Handling this callback replaces WebKit's automatic reload. Recover the
    // committed page once per 30 seconds to avoid crash loops.
    self.needsWebContentReload = YES;
    [self reloadTerminatedWebContentIfVisible];
}

- (void)reloadTerminatedWebContentIfVisible
{
    if (!self.needsWebContentReload || [self isClosingWiki] || !self.viewIfLoaded.window) return;
    self.needsWebContentReload = NO;
    if (self.lastWebContentReload && -self.lastWebContentReload.timeIntervalSinceNow < 30) return;
    self.lastWebContentReload = [NSDate date];
    if (self.webView.backForwardList.currentItem) {
        [self.webView reload];
    } else {
        [self loadWikiPage];
    }
}

/// A login redirect is answered by loading mobile-login, which signs the web
/// view in and sends it back. When the page then redirects to the login page
/// again (the session cookie was not kept) that would go round for as long as
/// the page is open: after a few re-routes in a short time the login page is
/// let through instead.
- (BOOL)shouldRerouteToMobileLogin
{
    NSDate *now = [NSDate date];
    if (!self.mobileLoginRerouteWindowStart || [now timeIntervalSinceDate:self.mobileLoginRerouteWindowStart] > 30.0) {
        self.mobileLoginRerouteWindowStart = now;
        self.mobileLoginReroutes = 0;
    }
    self.mobileLoginReroutes += 1;
    return self.mobileLoginReroutes <= 3;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *requestURL = navigationAction.request.URL;
    BOOL isMainFrame = navigationAction.targetFrame.isMainFrame;
    BOOL isLoginRedirect = SeafIsLoginRedirectURL(requestURL);
    NSString *serverHost = [NSURL URLWithString:self.connection.address].host;
    BOOL isServerLogin = isLoginRedirect && serverHost && [serverHost isEqualToString:requestURL.host];
    if (isMainFrame) self.deferredLoginURL = nil;

    WKNavigation *navigation = nil;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
    if (@available(iOS 27.0, *)) {
        navigation = navigationAction.mainFrameNavigation;
    }
#endif
    if (isMainFrame && [self.operationsByNavigation objectForKey:navigation].rejectedRedirect) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    SeafWikiDownloadOperation *pending = [self pendingExportOperation];
    if (isMainFrame && pending && navigation && navigation == pending.navigation) {
        if (isLoginRedirect || ![self serverRelativePathForURL:requestURL]) {
            [self rejectExportRedirectForOperation:pending toURL:requestURL];
            decisionHandler(WKNavigationActionPolicyCancel);
        } else {
            decisionHandler(WKNavigationActionPolicyAllow);
        }
        return;
    }

    SeafWikiExportKind exportKind = isMainFrame ? [self exportKindForURL:requestURL] : SeafWikiExportKindNone;
    if (exportKind != SeafWikiExportKindNone) {
        if ([self isClosingWiki] || [self isDownloadInProgress]) {
            // One download-and-save flow at a time. The running one keeps its own
            // feedback: "Downloading" is already shown, a save sheet speaks for itself.
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }
        [self beginExportWithKind:exportKind URL:requestURL navigation:navigation];
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }

    if (isMainFrame && pending) {
        if (isServerLogin && (!navigation || !pending.navigation)) {
            // Older action callbacks cannot tell a redirect from a fresh load.
            // A fresh load gets didStart; an export redirect gets didReceiveServerRedirect.
            self.deferredLoginURL = requestURL;
            decisionHandler(WKNavigationActionPolicyAllow);
            return;
        }
        if (navigation && pending.navigation) {
            [self finishDownloadOperation:pending outcome:SeafWikiDownloadOutcomeCancelled];
        }
    }

    // External domains handle their own login flows.
    if (isServerLogin && ![self isClosingWiki] && [self shouldRerouteToMobileLogin]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        [self loadMobileLoginForRedirectURL:requestURL];
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)loadMobileLoginForRedirectURL:(NSURL *)url
{
    NSString *targetURL = nil;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"next"] && item.value.length > 0) {
            targetURL = item.value;
            break;
        }
    }
    if (!targetURL) targetURL = self.webView.URL.absoluteString ?: self.urlString;
    NSString *encodedNext = [targetURL stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *mobileLoginURL = [NSString stringWithFormat:@"%@/mobile-login/?next=%@",
                                self.connection.address, encodedNext ?: targetURL];
    [self.webView loadRequest:[self.connection buildRequest:mobileLoginURL method:@"GET" form:nil]];
}

#pragma mark - Download Handling

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (!navigationResponse.forMainFrame) {
        decisionHandler(WKNavigationResponsePolicyAllow);
        return;
    }
    NSURLResponse *response = navigationResponse.response;
    WKNavigation *navigation = self.provisionalNavigation;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
    if (@available(iOS 27.0, *)) {
        navigation = navigationResponse.mainFrameNavigation ?: navigation;
    }
#endif

    if ([self.operationsByNavigation objectForKey:navigation].rejectedRedirect) {
        decisionHandler(WKNavigationResponsePolicyCancel);
        return;
    }

    SeafWikiDownloadOperation *pending = [self pendingExportOperation];
    if (navigation && pending.navigation == navigation) {
        if (!self.leavingWiki && [self isAcceptableExportResponse:response forOperation:pending]) {
            pending.downloadRequested = YES;
            pending.downloadResponse = navigationResponse;
            decisionHandler(WKNavigationResponsePolicyDownload);
            if (!webView.isLoading) [self awaitDownloadDeliveryForOperation:pending];
            return;
        }
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        Warning("Wiki export got an unusable response (status %ld, %@) from %@", (long)status, response.MIMEType, response.URL);
        [self finishDownloadOperation:pending outcome:SeafWikiDownloadOutcomeFailed];
        decisionHandler(WKNavigationResponsePolicyCancel);
        return;
    }

    // Other main-frame responses: attachments and content the web view cannot show
    // are files. HTTP errors are reported, never saved.
    BOOL isFile = SeafIsAttachmentDisposition(SeafResponseHeader(response, @"Content-Disposition")) || !navigationResponse.canShowMIMEType;
    if (isFile) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        BOOL success = (status == 0) || (status >= 200 && status < 300 && status != 204 && status != 205);
        // Page and flow state first: a page being left reports nothing, and a running
        // flow keeps its own feedback ("Downloading", the save sheet).
        if ([self isClosingWiki] || ((status >= 400 || success) && [self isDownloadInProgress])) {
            // For a success, only here is it known to be a download: one flow at a time.
            decisionHandler(WKNavigationResponsePolicyCancel);
            return;
        }
        if (status >= 400) {
            Warning("Wiki file response failed (status %ld): %@", (long)status, response.URL);
            decisionHandler(WKNavigationResponsePolicyCancel);
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to download file", @"Seafile")];
            return;
        }
        if (success) {
            SeafWikiDownloadOperation *op = [[SeafWikiDownloadOperation alloc] init];
            op.kind = SeafWikiExportKindNone;
            op.phase = SeafWikiDownloadPhaseAwaitingResponse;
            op.downloadRequested = YES;
            op.downloadResponse = navigationResponse;
            self.currentDownload = op;
            [self bindOperation:op toNavigation:navigation];
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Downloading", @"Seafile")];
            decisionHandler(WKNavigationResponsePolicyDownload);
            if (!webView.isLoading) [self awaitDownloadDeliveryForOperation:op];
            return;
        }
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)navigationResponse didBecomeDownload:(WKDownload *)download {
    // WebKit returns the selected response object with the new download.
    SeafWikiDownloadOperation *op = self.currentDownload;
    if (self.leavingWiki || !op || !op.downloadRequested || op.download || op.phase != SeafWikiDownloadPhaseAwaitingResponse
        || op.downloadResponse != navigationResponse) {
        [download cancel:nil];
        return;
    }
    op.downloadResponse = nil;
    op.download = download;
    op.phase = SeafWikiDownloadPhaseDownloading;
    [self.operationsByDownload setObject:op forKey:download];
    download.delegate = self;
}

#pragma mark - Export recognition

/// Path of url relative to the server root, without the leading slash; nil when
/// url is not on the server's origin.
- (nullable NSString *)serverRelativePathForURL:(NSURL *)url
{
    NSURL *base = [NSURL URLWithString:self.connection.address];
    if (!url.host || !base.host) return nil;
    if (!url.scheme || [url.scheme caseInsensitiveCompare:base.scheme] != NSOrderedSame) return nil;
    if ([url.host caseInsensitiveCompare:base.host] != NSOrderedSame) return nil;
    NSInteger urlPort = url.port ? url.port.integerValue : SeafDefaultPortForScheme(url.scheme);
    NSInteger basePort = base.port ? base.port.integerValue : SeafDefaultPortForScheme(base.scheme);
    if (urlPort != basePort) return nil;

    NSString *path = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].path ?: @"";
    NSString *basePath = [NSURLComponents componentsWithURL:base resolvingAgainstBaseURL:NO].path ?: @"";
    while ([basePath hasSuffix:@"/"]) {
        basePath = [basePath substringToIndex:basePath.length - 1];
    }
    NSString *prefix = [basePath stringByAppendingString:@"/"];
    if (![path hasPrefix:prefix]) return nil;
    return [path substringFromIndex:prefix.length];
}

- (SeafWikiExportKind)exportKindForURL:(NSURL *)url
{
    NSString *path = [self serverRelativePathForURL:url];
    if (!path || [path rangeOfString:SeafWikiExportEntryPattern options:NSRegularExpressionSearch].location == NSNotFound) {
        return SeafWikiExportKindNone;
    }
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if (![item.name isEqualToString:@"export_type"]) continue;
        if ([item.value isEqualToString:@"markdown"]) return SeafWikiExportKindMarkdown;
        if ([item.value isEqualToString:@"sdoc"]) return SeafWikiExportKindSdoc;
    }
    return SeafWikiExportKindNone;
}

- (BOOL)isSdocExportTargetURL:(NSURL *)url
{
    NSString *path = [self serverRelativePathForURL:url];
    return path && [path rangeOfString:SeafSdocExportTargetPattern options:NSRegularExpressionSearch].location != NSNotFound;
}

/// The success responses an export can end with (see the export endpoints in
/// seahub: errors are always non-2xx JSON, sdoc goes through one redirect).
- (BOOL)isAcceptableExportResponse:(NSURLResponse *)response forOperation:(SeafWikiDownloadOperation *)op
{
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) return NO;
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    if (http.statusCode != 200) return NO;

    NSArray<NSString *> *types = nil;
    if (op.kind == SeafWikiExportKindMarkdown) {
        if (!SeafIsSameResource(http.URL, op.exportURL)) return NO;
        types = @[@"application/octet-stream", @"text/plain", @"text/markdown", @"text/x-markdown"];
    } else if (op.kind == SeafWikiExportKindSdoc) {
        // sdoc ends on the one redirect target recorded for this export.
        if (!op.sdocTargetURL || !SeafIsSameResource(http.URL, op.sdocTargetURL)) return NO;
        types = @[@"application/x-zip-compressed", @"application/zip", @"application/octet-stream"];
    } else {
        return NO;
    }
    NSString *mime = http.MIMEType.lowercaseString ?: @"";
    // Error bodies are never the export, attachment header or not (e.g. a proxy's
    // login page or error JSON that kept the upstream headers).
    if (SeafIsErrorBodyMIMEType(mime)) return NO;
    if (SeafIsAttachmentDisposition(SeafResponseHeader(http, @"Content-Disposition"))) return YES;
    return [types containsObject:mime];
}

#pragma mark - Download operations

/// The export that is waiting for its response, if any.
- (nullable SeafWikiDownloadOperation *)pendingExportOperation
{
    SeafWikiDownloadOperation *op = self.currentDownload;
    if (op && op.kind != SeafWikiExportKindNone && op.phase == SeafWikiDownloadPhaseAwaitingResponse && !op.downloadRequested) {
        return op;
    }
    return nil;
}

- (BOOL)isDownloadInProgress
{
    return self.currentDownload && self.currentDownload.phase != SeafWikiDownloadPhaseFinished;
}

- (void)beginExportWithKind:(SeafWikiExportKind)kind URL:(NSURL *)url navigation:(nullable WKNavigation *)navigation
{
    SeafWikiDownloadOperation *op = [[SeafWikiDownloadOperation alloc] init];
    op.kind = kind;
    op.phase = SeafWikiDownloadPhaseAwaitingResponse;
    op.exportURL = url;
    // wiki2 sets document.title to the page name; used when the response carries
    // no usable file name (see -fileNameForOperation:response:suggestedFilename:).
    op.pageTitle = self.webView.title;
    self.currentDownload = op;
    [self bindOperation:op toNavigation:navigation];
    // Seahub converts the page before it answers: show progress from the tap.
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Downloading", @"Seafile")];
}

- (void)bindOperation:(SeafWikiDownloadOperation *)op toNavigation:(nullable WKNavigation *)navigation
{
    if (!navigation) return;
    op.navigation = navigation;
    [self.operationsByNavigation setObject:op forKey:navigation];
}

- (void)rejectExportRedirectForOperation:(SeafWikiDownloadOperation *)op toURL:(NSURL *)url
{
    // A process swap can continue loading after stopLoading returns.
    // Keep the rejection with the navigation until WebKit finishes it.
    op.rejectedRedirect = YES;
    Warning("Wiki export redirected unexpectedly to %@", url);
    [self finishDownloadOperation:op outcome:SeafWikiDownloadOutcomeFailed];
}

/// Let WebKit finish delivering the download after the web navigation stops.
/// Start this grace period only once, even if both KVO and the delegate fire.
- (void)awaitDownloadDeliveryForOperation:(SeafWikiDownloadOperation *)op
{
    if (!op.downloadResponse || op.waitingForDownloadDelivery) return;
    op.waitingForDownloadDelivery = YES;
    __weak typeof(self) wself = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(wself) sself = wself;
        if (!sself || op != sself.currentDownload || !op.downloadResponse) return;
        Warning("Wiki download was requested but never started");
        [sself.operationsByNavigation removeObjectForKey:op.navigation];
        [sself finishDownloadOperation:op outcome:SeafWikiDownloadOutcomeFailed];
    });
}

/// Ends an operation exactly once. Only the current operation drives the HUD;
/// a late callback of an older one just cleans up after itself.
- (void)finishDownloadOperation:(SeafWikiDownloadOperation *)op outcome:(SeafWikiDownloadOutcome)outcome
{
    if (!op || op.phase == SeafWikiDownloadPhaseFinished) return;
    SeafWikiDownloadPhase previous = op.phase;
    op.phase = SeafWikiDownloadPhaseFinished;
    op.downloadResponse = nil;
    BOOL isCurrent = (self.currentDownload == op);
    if (isCurrent) {
        self.currentDownload = nil;
    }

    NSURL *dir = op.directoryURL;
    if (outcome == SeafWikiDownloadOutcomeAbandoned && previous == SeafWikiDownloadPhaseDownloading && op.download) {
        // Remove the directory only after WebKit has stopped writing into it.
        [op.download cancel:^(NSData *resumeData) {
            if (dir) [[NSFileManager defaultManager] removeItemAtURL:dir error:nil];
        }];
    } else if (dir) {
        [[NSFileManager defaultManager] removeItemAtURL:dir error:nil];
    }
    if (op.picker.presentingViewController && !op.picker.isBeingDismissed) {
        [op.picker dismissViewControllerAnimated:NO completion:nil];
    }
    op.picker = nil;

    if (!isCurrent) return;
    BOOL showsProgress = (previous == SeafWikiDownloadPhaseAwaitingResponse || previous == SeafWikiDownloadPhaseDownloading);
    switch (outcome) {
        case SeafWikiDownloadOutcomeSaved:
            if (![self isClosingWiki]) {
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Saved to Files", @"Seafile")];
            }
            break;
        case SeafWikiDownloadOutcomeFailed:
            if (![self isClosingWiki]) {
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to download file", @"Seafile")];
            } else if (showsProgress) {
                [SVProgressHUD dismiss];
            }
            break;
        case SeafWikiDownloadOutcomeCancelled:
        case SeafWikiDownloadOutcomeAbandoned:
            if (showsProgress) {
                [SVProgressHUD dismiss];
            }
            break;
    }
}

- (BOOL)isClosingWiki
{
    return self.wikiExitInProgress || self.leavingWiki;
}

/// The wiki page was left (popped, dismissed): end the flow, cancel a running
/// download and make sure no late callback presents anything elsewhere.
- (void)wikiDidLeave
{
    if (self.leavingWiki) return;
    self.leavingWiki = YES;
    SeafWikiDownloadOperation *op = self.currentDownload;
    if (!op) return;
    if (op.phase == SeafWikiDownloadPhaseAwaitingResponse && !op.downloadRequested) {
        [self.webView stopLoading];
    }
    [self finishDownloadOperation:op outcome:SeafWikiDownloadOutcomeAbandoned];
}

/// File name for the downloaded file. Wiki exports are named after the page
/// when the response gives no usable name (see §3.1 of the design document).
- (NSString *)fileNameForOperation:(SeafWikiDownloadOperation *)op
                          response:(NSURLResponse *)response
                 suggestedFilename:(NSString *)suggestedFilename
{
    NSString *disposition = SeafResponseHeader(response, @"Content-Disposition");
    NSString *extension = nil;
    if (op.kind == SeafWikiExportKindMarkdown) extension = @"md";
    else if (op.kind == SeafWikiExportKindSdoc) extension = @"sdoczip";

    NSString *name = nil;
    // Without a filename parameter the suggestion comes from the URL ("export",
    // "export.txt", the document UUID): useless for an export.
    if (op.kind == SeafWikiExportKindNone || SeafDispositionHasFileName(disposition)) {
        name = suggestedFilename.lastPathComponent;
        if (op.kind == SeafWikiExportKindMarkdown) {
            NSString *encoded = SeafMalformedSeahubFileName(disposition);
            NSString *decoded = [encoded stringByRemovingPercentEncoding];
            if (decoded.length > 0) {
                name = decoded;
            }
        }
    }

    if (extension) {
        NSString *suffix = [@"." stringByAppendingString:extension];
        if (![name.lowercaseString hasSuffix:suffix]) {
            // e.g. seahub cuts the sdoc name at '&' or '#' in the page title.
            NSString *title = SeafSanitizedFileName(op.pageTitle);
            name = title.length > 0 ? [title stringByAppendingString:suffix] : nil;
        }
    }

    name = SeafSanitizedFileName(name);
    if (name.length == 0 || [name isEqualToString:@"."] || [name isEqualToString:@".."]) {
        name = extension ? [@"download." stringByAppendingString:extension] : @"download";
    }
    return name;
}

#pragma mark - WKDownloadDelegate

- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response suggestedFilename:(NSString *)suggestedFilename completionHandler:(void (^)(NSURL * _Nullable))completionHandler {
    SeafWikiDownloadOperation *op = [self.operationsByDownload objectForKey:download];
    if (!op || op != self.currentDownload || op.phase != SeafWikiDownloadPhaseDownloading) {
        completionHandler(nil);
        return;
    }

    NSString *fileName = [self fileNameForOperation:op response:response suggestedFilename:suggestedFilename];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"WikiDownloads" isDirectory:YES];
    NSURL *dir = [root URLByAppendingPathComponent:[NSUUID UUID].UUIDString isDirectory:YES];
    NSError *error = nil;
    BOOL created = [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:&error];
    NSURL *destination = [dir URLByAppendingPathComponent:fileName isDirectory:NO];
    if (!created || ![fm isWritableFileAtPath:dir.path] || [fm fileExistsAtPath:destination.path]) {
        Warning("Cannot prepare wiki download directory %@: %@", dir, error);
        if (created) [fm removeItemAtURL:dir error:nil];
        [self finishDownloadOperation:op outcome:SeafWikiDownloadOutcomeFailed];
        completionHandler(nil);
        return;
    }
    op.directoryURL = dir;
    op.fileURL = destination;
    completionHandler(destination);
}

- (void)download:(WKDownload *)download didFailWithError:(NSError *)error resumeData:(NSData *)resumeData {
    SeafWikiDownloadOperation *op = [self.operationsByDownload objectForKey:download];
    [self.operationsByDownload removeObjectForKey:download];
    if (!op) return;
    if (op.phase == SeafWikiDownloadPhaseDownloading) {
        Warning("Wiki download failed: %@", error);
        [self finishDownloadOperation:op outcome:SeafWikiDownloadOutcomeFailed];
    } else if (op.phase == SeafWikiDownloadPhaseFinished && op.directoryURL) {
        [[NSFileManager defaultManager] removeItemAtURL:op.directoryURL error:nil];
    }
}

- (void)downloadDidFinish:(WKDownload *)download {
    SeafWikiDownloadOperation *op = [self.operationsByDownload objectForKey:download];
    [self.operationsByDownload removeObjectForKey:download];
    if (!op) return;
    if (op.phase != SeafWikiDownloadPhaseDownloading || op != self.currentDownload) {
        // Ended meanwhile (page left): the file is not wanted.
        if (op.directoryURL) [[NSFileManager defaultManager] removeItemAtURL:op.directoryURL error:nil];
        return;
    }
    op.phase = SeafWikiDownloadPhaseAwaitingSave;
    [SVProgressHUD dismiss];
    [self presentSaveSheetIfPossible];
}

#pragma mark - Save to Files

/// Presents the system "Save to Files" sheet for a finished download, waiting
/// out transitions and sheets that are on screen; gives up after a second
/// refused presentation so the flow never stays busy without a sheet.
- (void)presentSaveSheetIfPossible
{
    SeafWikiDownloadOperation *op = self.currentDownload;
    if (!op || op.phase != SeafWikiDownloadPhaseAwaitingSave) return;
    if (self.leavingWiki) {
        [self finishDownloadOperation:op outcome:SeafWikiDownloadOutcomeAbandoned];
        return;
    }
    if ([self isClosingWiki]) return;

    // A navigation transition in progress (e.g. an interactive back swipe):
    // decide once it is over; a completed pop ends the flow in -wikiDidLeave.
    id<UIViewControllerTransitionCoordinator> navTransition = self.navigationController.transitionCoordinator;
    if (navTransition) {
        __weak typeof(self) wself = self;
        if (![navTransition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [wself presentSaveSheetIfPossible];
            });
        }]) {
            [self scheduleSaveSheetRetry];
        }
        return;
    }

    UIViewController *presenter = self;
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    if (presenter != self) {
        BOOL isOwnSheet = (presenter == self.ownActionSheet);
        BOOL inTransition = presenter.isBeingPresented || presenter.isBeingDismissed || presenter.transitionCoordinator != nil;
        if (isOwnSheet || inTransition) {
            // Own sheets call back from their actions; the retry also covers
            // presentations that have no callback at all.
            [self scheduleSaveSheetRetry];
            return;
        }
    }
    // A full-screen modal can be in the window while the underlying Wiki isn't.
    if (!presenter.viewIfLoaded.window) return;

    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[op.fileURL] asCopy:YES];
    picker.delegate = self;
    // Swipe-to-dismiss on any iOS version ends up in -presentationControllerDidDismiss:.
    picker.presentationController.delegate = self;
    op.picker = picker;
    op.pickerPresented = NO;
    op.phase = SeafWikiDownloadPhaseSaving;

    // The document picker is a remote view controller: UIKit delays its
    // presentation until the remote side is ready, so presentingViewController
    // is not set right away and only the completion confirms it. A refused
    // presentation never calls the completion: after a timeout it counts as a
    // failure, retried once.
    __weak typeof(self) wself = self;
    __weak UIDocumentPickerViewController *wpicker = picker;
    [presenter presentViewController:picker animated:YES completion:^{
        __strong typeof(wself) sself = wself;
        UIDocumentPickerViewController *shown = wpicker;
        if (!shown) return;
        if (!sself || sself.leavingWiki || op != sself.currentDownload) {
            [shown dismissViewControllerAnimated:NO completion:nil];
            return;
        }
        // Check which sheet this is before recording anything on the operation.
        if (op.picker == shown) {
            op.pickerPresented = YES;
            return;
        }
        // A sheet from an earlier attempt that finished presenting after its
        // timeout. While the flow still waits for a sheet, keep this one: it is on
        // screen, and a newer attempt cannot present over it.
        BOOL waiting = (op.phase == SeafWikiDownloadPhaseAwaitingSave || op.phase == SeafWikiDownloadPhaseSaving);
        if (![sself isClosingWiki] && waiting && !op.pickerPresented) {
            op.picker = shown;
            op.pickerPresented = YES;
            op.phase = SeafWikiDownloadPhaseSaving;
            return;
        }
        // The flow ended (e.g. page left) or another sheet is already up.
        [shown dismissViewControllerAnimated:NO completion:nil];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(wself) sself = wself;
        UIDocumentPickerViewController *spicker = wpicker;
        if (!sself || op.phase != SeafWikiDownloadPhaseSaving || op.picker != spicker) return;
        if (op.pickerPresented || spicker.presentingViewController) return;
        op.picker = nil;
        op.phase = SeafWikiDownloadPhaseAwaitingSave;
        op.presentFailures += 1;
        Warning("Save sheet was not presented (%ld)", (long)op.presentFailures);
        if (op.presentFailures >= 2) {
            [sself finishDownloadOperation:op outcome:SeafWikiDownloadOutcomeFailed];
        } else {
            [sself presentSaveSheetIfPossible];
        }
    });
}

- (void)scheduleSaveSheetRetry
{
    if (self.saveSheetRetryScheduled) return;
    self.saveSheetRetryScheduled = YES;
    __weak typeof(self) wself = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        sself.saveSheetRetryScheduled = NO;
        [sself presentSaveSheetIfPossible];
    });
}

- (nullable SeafWikiDownloadOperation *)operationForPicker:(UIViewController *)picker
{
    SeafWikiDownloadOperation *op = self.currentDownload;
    return (op && op.picker == picker && op.phase == SeafWikiDownloadPhaseSaving) ? op : nil;
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    SeafWikiDownloadOperation *op = [self operationForPicker:controller];
    if (!op) return;
    op.picker = nil; // the sheet dismisses itself
    [self finishDownloadOperation:op outcome:SeafWikiDownloadOutcomeSaved];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    SeafWikiDownloadOperation *op = [self operationForPicker:controller];
    if (!op) return;
    op.picker = nil;
    [self finishDownloadOperation:op outcome:SeafWikiDownloadOutcomeCancelled];
}

#pragma mark - UIAdaptivePresentationControllerDelegate

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    SeafWikiDownloadOperation *op = [self operationForPicker:presentationController.presentedViewController];
    if (!op) return;
    op.picker = nil;
    [self finishDownloadOperation:op outcome:SeafWikiDownloadOutcomeCancelled];
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
    if ([message.name isEqualToString:SeafWikiHistoryMessageName]) {
        [self handleHistoryMessage:message];
        return;
    }
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
        __weak typeof(self) wfinish = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [wfinish closeWiki];
        });
    } else if ([action isEqualToString:@"page.status.height.get"]) {
        CGFloat h = 0;
        UIWindowScene *scene = self.view.window.windowScene;
        h = scene.statusBarManager.statusBarFrame.size.height;
        [self sendBridgeCallback:[@(h) stringValue] forCallbackId:callbackId];
    }
}

#pragma mark - Bridge Callback

- (void)sendBridgeCallback:(NSString *)text forCallbackId:(id)callbackId {
    // Empty results never fire the callback, matching Android.
    [self.webView seaf_sendBridgeResponse:text forCallbackId:callbackId];
}

@end
