//
//  SeafDisDetailViewController.h
//  Discussion
//
//  Created by Wang Wei on 5/21/13.
//  Copyright (c) 2013 Wang Wei. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafConnection.h"

@interface SeafDisDetailViewController : UIViewController <UISplitViewControllerDelegate, UIWebViewDelegate>

@property (strong, nonatomic, readonly) IBOutlet UIWebView *webview;

@property (strong, nonatomic) SeafConnection *connection;
@property (readwrite, nonatomic) BOOL hiddenAddmsg;


- (void)setGroup:(NSString *)groupName groupId:(NSString *)groupId;
- (void)setUrl:(NSString *)url connection:(SeafConnection *)conn;
- (void)configureView;


@end
