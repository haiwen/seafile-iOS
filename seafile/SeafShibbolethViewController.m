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
#import "Debug.h"

@interface SeafShibbolethViewController ()<UIWebViewDelegate, NSURLConnectionDataDelegate>
@property (strong) SeafConnection *sconn;
@property (strong) NSURLRequest *FailedRequest;
@property (strong) NSURLConnection *conn;
@end

@implementation SeafShibbolethViewController

- (id)init:(SeafConnection *)conn
{
    if (self = [super initWithAutoNibName]) {
        self.sconn = conn;
        [self start];
    }
    return self;
}

- (NSString *)shibbolethUrl
{
    if ([_sconn.address hasSuffix:@"/"])
        return[_sconn.address stringByAppendingString:@"shib-login/"];
    else
        return [_sconn.address stringByAppendingString:@"/shib-login/"];
}

- (UIWebView *)webView
{
    return (UIWebView *)self.view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)start
{
    NSString *url = self.shibbolethUrl;
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:[NSURL URLWithString:url] cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 5*60];
    if ([url hasPrefix:@"http://"]) {
        [self.webView loadRequest:request];
    } else {
        [self loadRequestBackground:request];
    }
}


- (void)loadRequestBackground:(NSURLRequest *)request
{
    Debug("...%@ %@ %@", request.URL, _sconn, _sconn.loginMgr);
    _sconn.loginMgr.responseSerializer = [AFHTTPResponseSerializer serializer];

    NSURLRequest *r = [request mutableCopy];
    NSURLSessionDataTask *dataTask = [_sconn.loginMgr dataTaskWithRequest:r completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
        if (error) {
            Warning("Error: %@", error);
        } else {
            Debug("...");
            [self.webView loadRequest:r];
        }
    }];
    Debug("...%@", dataTask);
    [dataTask resume];
}


# pragma - UIWebViewDelegate
- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    Debug("...");
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    Warning("Failed to load request: %@", error);
}


-(BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    Debug("load request: %@", request.URL);
    return true;
}
@end
