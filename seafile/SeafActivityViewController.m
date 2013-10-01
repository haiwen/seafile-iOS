//
//  SeafActivityViewController.m
//  seafilePro
//
//  Created by Wang Wei on 5/18/13.
//  Copyright (c) 2013 Seafile Ltd. All rights reserved.
//

#import "SeafActivityViewController.h"
#import "SeafAppDelegate.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "ExtentedString.h"
#import "Debug.h"

enum {
    ACTIVITY_INIT = 0,
    ACTIVITY_START,
    ACTIVITY_END,
};

@interface SeafActivityViewController ()
@property int state;
@property (readonly) UIWebView *webview;
@property (strong) NSString *url;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *loadingView;

@end

@implementation SeafActivityViewController
@synthesize connection = _connection;
@synthesize url = _url;


- (void)refresh:(id)sender
{
    [self start];
}

- (UIWebView *)webview
{
    return (UIWebView *)self.view;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    // Do any additional setup after loading the view from its nib.
    self.title = @"Activities";
    self.navigationItem.rightBarButtonItem = [self getBarItemAutoSize:@"refresh".navItemImgName action:@selector(refresh:)];
    self.webview.delegate = nil;
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setConnection:(SeafConnection *)connection
{
    if (IsIpad())
        [self.navigationController popToRootViewControllerAnimated:NO];
    self.state = ACTIVITY_INIT;
    self.webview.delegate = nil;
    [self.webview loadHTMLString:nil baseURL:nil];
    _connection = connection;
    _url = [_connection.address stringByAppendingString:API_URL"/html/events/"];
}

- (void)showLodingView
{
    if (!self.loadingView) {
        self.loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        self.loadingView.color = [UIColor darkTextColor];
        self.loadingView.hidesWhenStopped = YES;
        [self.view addSubview:self.loadingView];
    }
    self.loadingView.center = self.view.center;
    [self.loadingView startAnimating];
}

- (void)dismissLoadingView
{
    [self.loadingView stopAnimating];
}

- (void)start
{
    [self showLodingView];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:self.url] cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
    [request setHTTPMethod:@"GET"];
    [request setValue:[NSString stringWithFormat:@"Token %@", _connection.token] forHTTPHeaderField:@"Authorization"];
    self.webview.delegate = self;
    [self.webview loadRequest: request];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.state == ACTIVITY_INIT)
        [self start];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [SVProgressHUD dismiss];
    [super viewWillDisappear:animated];
}


# pragma - UIWebViewDelegate
- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [self dismissLoadingView];
    NSString *js = [NSString stringWithFormat:@"setToken(\"%@\");", self.connection.token];
    [webView stringByEvaluatingJavaScriptFromString:js];
    self.state = ACTIVITY_END;
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    [self dismissLoadingView];
    [SVProgressHUD showErrorWithStatus:@"Failed to load activities"];
    self.state = ACTIVITY_END;
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    Debug("Request %@\n", request.URL);
    NSString *urlStr = request.URL.absoluteString;
    if ([urlStr hasPrefix:@"file://"] || [urlStr isEqualToString:self.url] || [@"about:blank" isEqualToString:urlStr]) {
        return YES;
    } else if ([urlStr hasPrefix:@"api://"]) {
        NSString *path = @"/";
        NSRange range;
        NSRange foundRange = [urlStr rangeOfString:@"/repo/" options:NSCaseInsensitiveSearch];
        if (foundRange.location == NSNotFound)
            return NO;
        range.location = foundRange.location + foundRange.length;
        range.length = 36;
        NSString *repo_id = [urlStr substringWithRange:range];

        foundRange = [urlStr rangeOfString:@"files/?p=" options:NSCaseInsensitiveSearch];
        if (foundRange.location != NSNotFound) {
            path = [urlStr substringFromIndex:(foundRange.location+foundRange.length)];
        }
        path = [path stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        Debug("repo=%@, path=%@\n", repo_id, path);
        if (path.length <= 1) return NO;
        SeafFile *sfile = [[SeafFile alloc] initWithConnection:self.connection oid:nil repoId:repo_id name:path.lastPathComponent path:path mtime:0 size:0];
        SeafDetailViewController *detailvc;
        if (IsIpad()) {
            detailvc = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
            [self.navigationController pushViewController:detailvc animated:NO];
        } else {
            detailvc = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate showDetailView:detailvc];
        }
        sfile.delegate = detailvc;
        [detailvc setPreViewItem:sfile master:nil];
    }
    return NO;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!IsIpad()) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
    return YES;
}

@end
