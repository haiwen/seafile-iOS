//
//  SeafDisDetailViewController.m
//  Discussion
//
//  Created by Wang Wei on 5/21/13.
//  Copyright (c) 2013 Wang Wei. All rights reserved.
//

#import "SeafDisDetailViewController.h"
#import "SVProgressHUD.h"
#import "Debug.h"

@interface SeafDisDetailViewController ()
@property (strong, nonatomic) UIPopoverController *masterPopoverController;
@property (readonly) UIWebView *webview;
- (void)configureView;
@end

@implementation SeafDisDetailViewController
@synthesize connection;

#pragma mark - Managing the detail item

- (UIWebView *)webview
{
    return (UIWebView *)self.view;
}

- (void)setGroup:(id)g
{
    if (_group != g) {
        _group = g;

        // Update the view.
        [self configureView];
    }

    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }
}

- (void)configureView
{
    // Update the user interface for the detail item.
    if (self.connection && self.group) {
        NSString *urlStr = [self.connection.address stringByAppendingFormat:API_URL"/discussion/%@/", self.group];
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:urlStr] cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
        [request setHTTPMethod:@"GET"];
        [request setValue:[NSString stringWithFormat:@"Token %@", self.connection.token] forHTTPHeaderField:@"Authorization"];
        [self.webview loadRequest: request];
    } else {
        NSURLRequest *request = [[NSURLRequest alloc] initWithURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"]] cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
        [self.webview loadRequest: request];
    }
}

- (void)goBack:(id)sender
{
    [self.navigationController dismissViewControllerAnimated:NO completion:nil];
}

- (void)refresh:(id)sender
{
    [self configureView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.title = @"Discussion";
    self.webview.delegate = self;
    if (!IsIpad()) {
        UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStyleDone target:self action:@selector(goBack:)];
        [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh:)];
    [self configureView];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Split view

- (void)splitViewController:(UISplitViewController *)splitController willHideViewController:(UIViewController *)viewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)popoverController
{
    barButtonItem.title = NSLocalizedString(@"Groups", @"Groups");
    [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    self.masterPopoverController = popoverController;
}

- (void)splitViewController:(UISplitViewController *)splitController willShowViewController:(UIViewController *)viewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    // Called when the view is shown again in the split view, invalidating the button and popover controller.
    [self.navigationItem setLeftBarButtonItem:nil animated:YES];
    self.masterPopoverController = nil;
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }
    [super viewWillDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!IsIpad()) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
    return YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [SVProgressHUD dismiss];
    NSString *js = [NSString stringWithFormat:@"setToken(\"%@\");", self.connection.token];
    [webView stringByEvaluatingJavaScriptFromString:js];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    [SVProgressHUD showErrorWithStatus:@"Failed to load discussion"];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSMutableURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    Debug("Request %@, %@\n", request.URL, request.allHTTPHeaderFields);
    NSString *urlStr = request.URL.absoluteString;
    if ([urlStr hasPrefix:@"file://"] || [urlStr hasPrefix:[self.connection.address stringByAppendingString:API_URL]]) {
        return YES;
    }
    return NO;
}

@end
