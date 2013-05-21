//
//  SeafActivityViewController.m
//  seafilePro
//
//  Created by Wang Wei on 5/18/13.
//  Copyright (c) 2013 tsinghua. All rights reserved.
//

#import "SeafActivityViewController.h"
#import "Debug.h"

@interface SeafActivityViewController ()

@end

@implementation SeafActivityViewController
@synthesize connection = _connection;

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

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    self.title = @"Activities";
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
            _connection = connection;
            [self start];
        }
    }
}
- (SeafConnection *)connection
{
    return _connection;
}

- (void)start
{
    NSString *urlStr = [NSString stringWithFormat:@"http://www.seafile.com"];
    NSURL *url = [NSURL URLWithString:urlStr];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
    [(UIWebView *)self.view loadRequest: request];
}

# pragma - UIWebViewDelegate
- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    Debug("...");
}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    Debug("...");
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
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
