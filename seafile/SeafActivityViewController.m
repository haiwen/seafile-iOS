//
//  SeafActivityViewController.m
//  seafilePro
//
//  Created by Wang Wei on 5/18/13.
//  Copyright (c) 2013 tsinghua. All rights reserved.
//

#import "SeafActivityViewController.h"
#import "SeafAppDelegate.h"
#import "SVProgressHUD.h"
#import "Debug.h"

@interface SeafActivityViewController ()
@property BOOL flag;
@end

@implementation SeafActivityViewController
@synthesize connection = _connection;
@synthesize flag;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;

}
- (id) init
{
    return [self initWithNibName:(NSStringFromClass ([self class])) bundle:nil];
}

- (void)refresh:(id)sender
{
    [self start];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    self.title = @"Activities";
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    self.navigationItem.leftBarButtonItem = appdelegate.switchItem;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh:)];
    ((UIWebView *)self.view).delegate = self;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setConnection:(SeafConnection *)connection
{
    @synchronized(self) {
        if (_connection != connection) {
            NSURLRequest *request = [[NSURLRequest alloc] initWithURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"]] cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
            [(UIWebView *)self.view loadRequest: request];
            _connection = connection;
            self.flag = YES;
        }
    }
}
- (SeafConnection *)connection
{
    return _connection;
}

- (void)start
{
    [SVProgressHUD showWithStatus:@"Loading ..."];
    NSString *urlStr = [_connection.address stringByAppendingString:API_URL"/activity/"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:urlStr] cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
    [request setHTTPMethod:@"GET"];
    [request setValue:[NSString stringWithFormat:@"Token %@", _connection.token] forHTTPHeaderField:@"Authorization"];
    [(UIWebView *)self.view loadRequest: request];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
}


# pragma - UIWebViewDelegate
- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    if (self.flag) {
        self.flag = NO;
        [self start];
    } else {
        [SVProgressHUD dismiss];
    }
}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    [SVProgressHUD showErrorWithStatus:@"Failed to load activities"];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    Debug("Request %@\n", request.URL);
    return YES;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!IsIpad()) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
    return YES;
}

@end
