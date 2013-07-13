//
//  SeafDisDetailViewController.m
//  Discussion
//
//  Created by Wang Wei on 5/21/13.
//  Copyright (c) 2013 Wang Wei. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafDisDetailViewController.h"
#import "REComposeViewController.h"
#import "InputAlertPrompt.h"

#import "SVProgressHUD.h"
#import "UIViewController+Extend.h"
#import "ExtentedString.h"
#import "Debug.h"

@interface SeafDisDetailViewController ()<UITextFieldDelegate, REComposeViewControllerDelegate>
@property (strong, nonatomic) UIPopoverController *masterPopoverController;
@property (strong, nonatomic) NSString *url;
@property (strong) UIBarButtonItem *msgItem;
@property (strong) UIBarButtonItem *refreshItem;
@property (strong) REComposeViewController *composeVC;

@property (strong, nonatomic) NSString *group;
@property (strong, nonatomic) NSString *groupName;


- (void)configureView;
@end

@implementation SeafDisDetailViewController
@synthesize connection = _connection;
@synthesize url = _url;
@synthesize composeVC = _composeVC;

#pragma mark - Managing the detail item

- (void)setGroup:(NSString *)groupName groupId:(NSString *)groupId
{
    if (_group != groupId) {
        _group = groupId;
        self.groupName = groupName;
        self.title = groupName;
        [self configureView];
        if (IsIpad())
            [self.navigationController popToRootViewControllerAnimated:NO];
    }

    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }
}

- (UIWebView *)webview
{
    return (UIWebView *)self.view;
}

- (void)setConnection:(SeafConnection *)connection
{
    if (IsIpad())
        [self.navigationController popToRootViewControllerAnimated:NO];
    _connection = connection;
    [self configureView];
}

- (NSString *)url
{
    if (!_url && _group)
        return [self.connection.address stringByAppendingFormat:API_URL"/html/discussions/%@/", self.group];
    return _url;
}

- (void)setUrl:(NSString *)url connection:(SeafConnection *)conn
{
    _connection = conn;
    _url = url;
}

- (BOOL)isReply
{
    if (_url)
        return YES;
    return NO;
}

- (void)configureView
{
    // Update the user interface for the detail item.
    [self.msgItem setEnabled:NO];
    if (self.connection && self.url) {
        [self.refreshItem setEnabled:YES];
        if (self.isReply)
            self.title = @"Reply";
        else
            self.title = self.groupName;
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:self.url] cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
        [request setHTTPMethod:@"GET"];
        [request setValue:[NSString stringWithFormat:@"Token %@", self.connection.token] forHTTPHeaderField:@"Authorization"];
        self.webview.delegate = self;
        [self.webview loadRequest:request];
    } else {
        self.title = @"Discussions";
        [self.refreshItem setEnabled:NO];
        NSURLRequest *request = [[NSURLRequest alloc] initWithURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"]] cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
        self.webview.delegate = nil;
        [self.webview loadRequest:request];
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

- (void)compose:(id)sender
{
    if (![self isReply])
        [self popupInputView:@"Discussion" placeholder:@"discussion"];
    else
        [self popupInputView:@"Reply" placeholder:@"reply"];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.title = @"Discussions";
    if (!IsIpad() && !self.isReply) {
        UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStylePlain target:self action:@selector(goBack:)];
        [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    }

    self.refreshItem = [self getBarItemAutoSize:@"refresh.png" action:@selector(refresh:)];
    self.msgItem = [self getBarItemAutoSize:@"addmsg.png" action:@selector(compose:)];
    UIBarButtonItem *space = [self getSpaceBarItem:16.0];
    self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:self.refreshItem, space, self.msgItem, nil];

    [self.msgItem setEnabled:NO];
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
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

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!IsIpad()) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
    return YES;
}

- (BOOL)htmlOK:(UIWebView *)webView
{
    NSString *res = [webView stringByEvaluatingJavaScriptFromString:@"getToken()"];
    if ([@"TOKEN" isEqualToString:res] || [self.connection.token isEqualToString:res])
        return YES;
    return NO;
}
- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [SVProgressHUD dismiss];
    if (![self htmlOK:webView])
        return;
    NSString *js = [NSString stringWithFormat:@"setToken(\"%@\");", self.connection.token];
    [webView stringByEvaluatingJavaScriptFromString:js];
    [self.msgItem setEnabled:YES];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    Debug("error=%@\n", error);
      if (error.code != NSURLErrorCancelled && error.code != 102)
        [SVProgressHUD showErrorWithStatus:@"Failed to load discussions"];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSMutableURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    Debug("Request %@, self=%@\n", request.URL, self.url);
    NSString *urlStr = request.URL.absoluteString;
    if ([urlStr hasPrefix:@"file://"] || [urlStr isEqualToString:self.url]) {
        return YES;
    } else if ([urlStr hasPrefix:[self.connection.address stringByAppendingString:API_URL"/html/discussion/"]]) {
        SeafDisDetailViewController *c = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"DISDETAILVC"];
        [c setUrl:urlStr connection:self.connection];
        [self.navigationController pushViewController:c animated:NO];
    }
    return NO;
}

- (void)popupInputView:(NSString *)title placeholder:(NSString *)tip
{
    _composeVC = [[REComposeViewController alloc] init];
    _composeVC.title = title;
    _composeVC.hasAttachment = NO;
    _composeVC.delegate = self;
    _composeVC.text = @"";
    _composeVC.placeholderText = tip;
    _composeVC.lineWidth = 0;
    _composeVC.navigationBar.tintColor = BAR_COLOR;
    [_composeVC presentFromRootViewController];
}

- (void)composeViewController:(REComposeViewController *)composeViewController didFinishWithResult:(REComposeResult)result
{
    if (result == REComposeResultCancelled) {
        [composeViewController dismissViewControllerAnimated:YES completion:nil];
    } else if (result == REComposeResultPosted) {
        NSLog(@"Text: %@", composeViewController.text);
        NSString *form = [NSString stringWithFormat:@"message=%@", [composeViewController.text escapedPostForm]];
        [self.connection sendPost:self.url repo:nil form:form success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
            [_composeVC dismissViewControllerAnimated:YES completion:nil];
            NSString *html = [JSON objectForKey:@"html"];
            NSString *js = [NSString stringWithFormat:@"addMessage(\"%@\");", [html stringEscapedForJavasacript]];
            [self.webview stringByEvaluatingJavaScriptFromString:js];
            [SVProgressHUD dismiss];
        } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
            if (_composeVC) {
                [SVProgressHUD showErrorWithStatus:@"Failed to add discussion"];
            }
        }];
        //[SVProgressHUD showWithStatus:@"Adding discussion ..."];
    }
}

@end
