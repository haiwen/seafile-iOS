//
//  SeafDisDetailViewController.h
//  Discussion
//
//  Created by Wang Wei on 5/21/13.
//  Copyright (c) 2013 Wang Wei. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafConnection.h"

enum {
    MSG_GROUP = 0,
    MSG_GROUP_REPLY,
    MSG_NEW_REPLY,
    MSG_USER,
};

@interface SeafDisDetailViewController : UIViewController <UISplitViewControllerDelegate, UIWebViewDelegate>

@property (strong, nonatomic, readonly) IBOutlet UIWebView *webview;

@property (strong, nonatomic) SeafConnection *connection;
@property (readwrite, nonatomic) int msgtype;

- (void)setUrl:(NSString *)url connection:(SeafConnection *)conn title:(NSString *)title;

- (void)configureView;


@end
