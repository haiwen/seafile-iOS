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

@property (strong, nonatomic) NSString *group;

@property (strong) SeafConnection *connection;

@end
