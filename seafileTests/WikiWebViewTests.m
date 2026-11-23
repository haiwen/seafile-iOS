#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

// App-hosted, offline regressions for SeafWikiWebViewController: in-page history,
// the JS bridge's trusted frames and the download hand-over. Pages are served with
// -loadSimulatedRequest:responseHTMLString:, so no server or account is involved.
// (-loadHTMLString:baseURL: would not do: it adds no back/forward list items.)

@interface NSObject (WikiWebViewTestAPI)
- (instancetype)initWithURL:(NSString *)urlString connection:(id)connection showSafariToolbar:(BOOL)showSafariToolbar wikiName:(NSString *)wikiName;
- (WKWebView *)webView;
- (id)currentDownload;
- (WKBackForwardListItem *)backTargetItem;
- (void)beginExportWithKind:(NSInteger)kind URL:(NSURL *)url navigation:(WKNavigation *)navigation;
- (void)awaitDownloadDeliveryForOperation:(id)op;
- (void)applicationDidBecomeActive:(NSNotification *)notification;
- (BOOL)isApplicationActive;
- (void)wikiDidLeave;
@end

static const NSInteger WikiTestExportKindMarkdown = 1;
static const NSInteger WikiTestPhaseAwaitingResponse = 0;
static const NSInteger WikiTestPhaseDownloading = 1;
static NSString * const WikiTestId = @"0f8c3c52-7a5e-4f0e-9a1b-2d3c4e5f6a7b";

static BOOL WikiTestAppActive = YES;

/// The controller with -isApplicationActive answered by the test.
static Class WikiTestControllerClass(void)
{
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class base = NSClassFromString(@"SeafWikiWebViewController");
        cls = objc_allocateClassPair(base, "SeafWikiWebViewControllerUnderTest", 0);
        IMP imp = imp_implementationWithBlock(^BOOL(id controller) { return WikiTestAppActive; });
        NSString *types = [NSString stringWithFormat:@"%s@:", @encode(BOOL)];
        class_addMethod(cls, @selector(isApplicationActive), imp, types.UTF8String);
        objc_registerClassPair(cls);
    });
    return cls;
}

@interface WikiTestConnection : NSObject
@property (nonatomic, copy) NSString *address;
@property (nonatomic, copy) NSString *token;
@end
@implementation WikiTestConnection
@end

/// Stands in for WKDownload: the controller only cancels it or sets its delegate.
@interface WikiTestDownload : NSObject
@property (nonatomic, weak) id delegate;
@property (nonatomic, assign) BOOL cancelled;
@end
@implementation WikiTestDownload
- (void)cancel:(void (^)(NSData *))completionHandler
{
    self.cancelled = YES;
    if (completionHandler) completionHandler(nil);
}
@end

@interface WikiTestProbe : NSObject <WKScriptMessageHandler>
@property (nonatomic, strong) NSMutableArray *bodies;
@end
@implementation WikiTestProbe
- (instancetype)init
{
    if (self = [super init]) _bodies = [NSMutableArray array];
    return self;
}
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    [self.bodies addObject:message.body ?: [NSNull null]];
}
@end

@interface WikiWebViewTests : XCTestCase
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIViewController *originalRoot;
@property (nonatomic, strong) UINavigationController *nav;
@property (nonatomic, strong) WikiTestProbe *probe;
@end

@implementation WikiWebViewTests

- (void)setUp
{
    [super setUp];
    WikiTestAppActive = YES;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) self.window = window;
        }
    }
    XCTAssertNotNil(self.window);
    self.originalRoot = self.window.rootViewController;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.systemBackgroundColor;
    self.nav = [[UINavigationController alloc] initWithRootViewController:root];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    self.probe = [WikiTestProbe new];
}

- (void)tearDown
{
    for (UIViewController *vc in self.nav.viewControllers) {
        if ([vc respondsToSelector:@selector(webView)]) {
            [vc.webView.configuration.userContentController removeScriptMessageHandlerForName:@"testProbe"];
        }
    }
    self.window.rootViewController = self.originalRoot;
    self.nav = nil;
    self.probe = nil;
    WikiTestAppActive = YES;
    [super tearDown];
}

#pragma mark - Helpers

- (UIViewController *)controllerForAddress:(NSString *)address
{
    WikiTestConnection *connection = [WikiTestConnection new];
    connection.address = address;
    // An empty URL keeps the controller from loading anything itself.
    UIViewController *vc = [[WikiTestControllerClass() alloc] initWithURL:@"" connection:connection showSafariToolbar:YES wikiName:@"Wiki"];
    [vc setValue:@(0.2) forKey:@"downloadDeliveryGracePeriod"];
    return vc;
}

- (UIViewController *)pushedControllerForAddress:(NSString *)address
{
    UIViewController *vc = [self controllerForAddress:address];
    [self.nav pushViewController:vc animated:NO];
    [self spin:0.3];
    [vc.webView.configuration.userContentController addScriptMessageHandler:self.probe name:@"testProbe"];
    return vc;
}

- (void)spin:(NSTimeInterval)seconds
{
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

- (BOOL)waitFor:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0) {
        [self spin:0.05];
    }
    return condition();
}

/// Serves html as the page at url, as a real load would (with a history item).
- (void)serve:(NSString *)html at:(NSString *)url inController:(UIViewController *)vc
{
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    [vc.webView loadSimulatedRequest:request responseHTMLString:html];
}

/// Serves html as the page at baseURL and waits for its `testProbe` message.
- (void)loadPage:(NSString *)html baseURL:(NSString *)baseURL inController:(UIViewController *)vc
{
    NSUInteger before = self.probe.bodies.count;
    [self serve:html at:baseURL inController:vc];
    XCTAssertTrue([self waitFor:^BOOL{ return self.probe.bodies.count > before; } timeout:10], @"page at %@ did not report", baseURL);
    [self spin:0.3]; // let the controller handle messages posted just before
}

/// A page that pushes one history entry after loading, like wiki2 does.
static NSString *WikiTestPushPage(NSString *stateJSON, NSString *pushedPath)
{
    return [NSString stringWithFormat:
            @"<html><body><script>\n"
            "window.addEventListener('load', function () {\n"
            "  history.pushState(%@, '', '%@');\n"
            "  webkit.messageHandlers.testProbe.postMessage('pushed');\n"
            "});\n"
            "</script></body></html>", stateJSON, pushedPath];
}

static NSString *WikiTestBridgeCall(NSString *action)
{
    return [NSString stringWithFormat:@"webkit.messageHandlers.callAndroidFunction.postMessage(JSON.stringify({action: '%@'}));", action];
}

#pragma mark - In-page history

- (void)testWikiRootPlaceholderIsSkipped
{
    UIViewController *vc = [self pushedControllerForAddress:@"https://server.test/seahub"];
    NSString *page = [NSString stringWithFormat:@"/seahub/wikis/%@/ab12/", WikiTestId];
    NSString *state = [NSString stringWithFormat:@"{url: '%@', path: '/a.sdoc', pageId: 'ab12'}", page];
    [self loadPage:WikiTestPushPage(state, page)
           baseURL:[NSString stringWithFormat:@"https://server.test/seahub/wikis/%@/", WikiTestId]
      inController:vc];
    XCTAssertNotNil(vc.webView.backForwardList.backItem);
    XCTAssertNil([vc backTargetItem], @"the wiki root left behind by the first push is a placeholder");
}

- (void)testPublishedWikiRootPlaceholderIsSkipped
{
    UIViewController *vc = [self pushedControllerForAddress:@"https://server.test/seahub"];
    NSString *page = @"/seahub/wiki/publish/team-notes/ab12/";
    NSString *state = [NSString stringWithFormat:@"{url: '%@', path: '/a.sdoc', pageId: 'ab12'}", page];
    [self loadPage:WikiTestPushPage(state, page)
           baseURL:@"https://server.test/seahub/wiki/publish/team-notes/"
      inController:vc];
    XCTAssertNotNil(vc.webView.backForwardList.backItem);
    XCTAssertNil([vc backTargetItem], @"a published wiki's root is a placeholder too");
}

- (void)testServerRenderedPublishedRootIsKept
{
    // Seahub's server-rendered published wiki shows a page at its root and pushes
    // {pageid} only when a page is clicked: going back to the root is real.
    UIViewController *vc = [self pushedControllerForAddress:@"https://server.test/seahub"];
    [self loadPage:WikiTestPushPage(@"{pageid: 'ab12'}", @"/seahub/wiki/publish/team-notes/ab12/")
           baseURL:@"https://server.test/seahub/wiki/publish/team-notes/"
      inController:vc];
    WKBackForwardListItem *root = vc.webView.backForwardList.backItem;
    XCTAssertNotNil(root);
    XCTAssertEqual([vc backTargetItem], root);
}

- (void)testIPv6ServerHistoryIsObserved
{
    UIViewController *vc = [self pushedControllerForAddress:@"http://[::1]:8000/seahub"];
    NSString *page = [NSString stringWithFormat:@"/seahub/wikis/%@/ab12/", WikiTestId];
    NSString *state = [NSString stringWithFormat:@"{url: '%@', path: '/a.sdoc', pageId: 'ab12'}", page];
    [self loadPage:WikiTestPushPage(state, page)
           baseURL:[NSString stringWithFormat:@"http://[::1]:8000/seahub/wikis/%@/", WikiTestId]
      inController:vc];
    XCTAssertNotNil(vc.webView.backForwardList.backItem);
    XCTAssertNil([vc backTargetItem], @"history messages of an IPv6 server reach the controller");
}

#pragma mark - Bridge

- (void)testPageFinishFromServerPageCloses
{
    UIViewController *vc = [self pushedControllerForAddress:@"https://server.test/seahub"];
    NSString *html = [NSString stringWithFormat:@"<script>%@ webkit.messageHandlers.testProbe.postMessage('sent');</script>",
                      WikiTestBridgeCall(@"page.finish")];
    [self serve:html at:@"https://server.test/seahub/wikis/x/" inController:vc];
    XCTAssertTrue([self waitFor:^BOOL{ return self.nav.topViewController != vc; } timeout:10]);
}

- (void)testPageFinishFromOtherSiteIsIgnored
{
    UIViewController *vc = [self pushedControllerForAddress:@"https://server.test/seahub"];
    NSString *html = [NSString stringWithFormat:@"<script>%@ webkit.messageHandlers.testProbe.postMessage('sent');</script>",
                      WikiTestBridgeCall(@"page.finish")];
    [self loadPage:html baseURL:@"https://other.test/" inController:vc];
    [self spin:0.7];
    XCTAssertEqual(self.nav.topViewController, vc);
}

- (void)testPageFinishFromSubframeIsIgnored
{
    UIViewController *vc = [self pushedControllerForAddress:@"https://server.test/seahub"];
    // A same-origin child frame: only the top-level page may close the wiki.
    NSString *frame = [NSString stringWithFormat:@"<script>%@ webkit.messageHandlers.testProbe.postMessage('sent');</script>",
                       WikiTestBridgeCall(@"page.finish")];
    NSString *escaped = [frame stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    NSString *html = [NSString stringWithFormat:@"<iframe srcdoc=\"%@\"></iframe>", escaped];
    [self loadPage:html baseURL:@"https://server.test/seahub/wikis/x/" inController:vc];
    [self spin:0.7];
    XCTAssertEqual(self.nav.topViewController, vc);
}

#pragma mark - Download hand-over

/// An export whose navigation has stopped with the download requested but not
/// yet delivered by WebKit.
- (id)requestedDownloadInController:(UIViewController *)vc response:(id)response
{
    [vc beginExportWithKind:WikiTestExportKindMarkdown
                        URL:[NSURL URLWithString:@"https://server.test/seahub/api/v2.1/wiki2/x/page/ab12/export/?export_type=markdown"]
                 navigation:nil];
    id op = [vc currentDownload];
    XCTAssertNotNil(op);
    [op setValue:@YES forKey:@"downloadRequested"];
    [op setValue:response forKey:@"downloadResponse"];
    [vc awaitDownloadDeliveryForOperation:op];
    return op;
}

- (void)deliver:(id)response download:(WikiTestDownload *)download to:(UIViewController *)vc
{
    WKWebView *webView = vc.webView;
    [(id<WKNavigationDelegate>)vc webView:webView
                       navigationResponse:(WKNavigationResponse *)response
                        didBecomeDownload:(WKDownload *)download];
}

- (void)testDeliveryInTimeIsTaken
{
    UIViewController *vc = [self controllerForAddress:@"https://server.test/seahub"];
    NSObject *response = [NSObject new];
    id op = [self requestedDownloadInController:vc response:response];
    WikiTestDownload *download = [WikiTestDownload new];
    [self deliver:response download:download to:vc];
    XCTAssertEqual([vc currentDownload], op);
    XCTAssertEqual([[op valueForKey:@"phase"] integerValue], WikiTestPhaseDownloading);
    XCTAssertFalse(download.cancelled);
    XCTAssertEqual(download.delegate, vc);
    [vc wikiDidLeave];
}

- (void)testDeliveryAfterWaitRanOutIsStillSaved
{
    UIViewController *vc = [self controllerForAddress:@"https://server.test/seahub"];
    NSObject *response = [NSObject new];
    [self requestedDownloadInController:vc response:response];
    XCTAssertTrue([self waitFor:^BOOL{ return [vc currentDownload] == nil; } timeout:3], @"the wait runs out");

    WikiTestDownload *download = [WikiTestDownload new];
    [self deliver:response download:download to:vc];
    id late = [vc currentDownload];
    XCTAssertNotNil(late, @"a late delivery is taken up");
    XCTAssertEqual([[late valueForKey:@"phase"] integerValue], WikiTestPhaseDownloading);
    XCTAssertEqual([[late valueForKey:@"kind"] integerValue], WikiTestExportKindMarkdown);
    XCTAssertFalse(download.cancelled);
    XCTAssertEqual(download.delegate, vc);
    [vc wikiDidLeave];
}

- (void)testDeliveryAfterNewFlowStartedIsCancelled
{
    UIViewController *vc = [self controllerForAddress:@"https://server.test/seahub"];
    NSObject *response = [NSObject new];
    [self requestedDownloadInController:vc response:response];
    XCTAssertTrue([self waitFor:^BOOL{ return [vc currentDownload] == nil; } timeout:3]);

    [vc beginExportWithKind:WikiTestExportKindMarkdown
                        URL:[NSURL URLWithString:@"https://server.test/seahub/api/v2.1/wiki2/x/page/cd34/export/?export_type=markdown"]
                 navigation:nil];
    id newer = [vc currentDownload];
    WikiTestDownload *download = [WikiTestDownload new];
    [self deliver:response download:download to:vc];
    XCTAssertTrue(download.cancelled, @"the expired flow's download is not saved over a newer flow");
    XCTAssertEqual([vc currentDownload], newer);
    XCTAssertEqual([[newer valueForKey:@"phase"] integerValue], WikiTestPhaseAwaitingResponse);
    [vc wikiDidLeave];
}

- (void)testDeliveryWaitCountsForegroundTimeOnly
{
    UIViewController *vc = [self controllerForAddress:@"https://server.test/seahub"];
    WikiTestAppActive = NO;
    id op = [self requestedDownloadInController:vc response:[NSObject new]];
    [self spin:0.8];
    XCTAssertEqual([vc currentDownload], op, @"no failure while the app is not active");

    WikiTestAppActive = YES;
    [vc applicationDidBecomeActive:nil];
    [self spin:0.1];
    XCTAssertEqual([vc currentDownload], op, @"a full period starts on activation");
    XCTAssertTrue([self waitFor:^BOOL{ return [vc currentDownload] == nil; } timeout:3]);
}

@end
