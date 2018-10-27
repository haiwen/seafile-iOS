//
//  SeafPrivacyPolicyViewController.m
//  seafileApp
//
//  Created by three on 2018/10/27.
//  Copyright © 2018 Seafile. All rights reserved.
//

#import "SeafPrivacyPolicyViewController.h"
#import <WebKit/WebKit.h>
#import "Debug.h"

@interface SeafPrivacyPolicyViewController ()<WKNavigationDelegate>

@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIProgressView *progressView;

@end

@implementation SeafPrivacyPolicyViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.title = NSLocalizedString(@"Privacy Policy", @"Seafile");
    
    _webView = [[WKWebView alloc]initWithFrame:self.view.bounds];
    _webView.navigationDelegate  = self;
    [self.view addSubview:_webView];
    NSURL *url = [NSURL URLWithString:NSLocalizedString(@"https://www.seafile.com/en/privacy_policy/", @"Seafile")];
    [_webView loadRequest:[NSURLRequest requestWithURL:url]];
    
    [self.view addSubview:self.progressView];
    
    [_webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
    if (self.presentingViewController) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Back", @"Seafile") style:UIBarButtonItemStyleDone target:self action:@selector(dismiss)];
    }
}

- (void)dismiss {
    [self dismissViewControllerAnimated:true completion:nil];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (object == self.webView && [keyPath isEqualToString:@"estimatedProgress"]) {
        CGFloat newprogress = [[change objectForKey:NSKeyValueChangeNewKey] doubleValue];
        if (newprogress == 1) {
            self.progressView.hidden = YES;
            [self.progressView setProgress:0 animated:NO];
        }else {
            self.progressView.hidden = NO;
            [self.progressView setProgress:newprogress animated:YES];
        }
    }
}

- (UIProgressView *)progressView {
    if (!_progressView) {
        CGFloat y = [[UIApplication sharedApplication] statusBarFrame].size.height + self.navigationController.navigationBar.frame.size.height;
        _progressView = [[UIProgressView alloc] initWithFrame:CGRectMake(0, y, self.view.bounds.size.width, 2)];
        _progressView.progressTintColor = BAR_COLOR;
        _progressView.trackTintColor = [UIColor whiteColor];
        _progressView.progress  = 0.005;
    }
    return _progressView;
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
