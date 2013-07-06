//
//  SeafActivityViewController.h
//  seafilePro
//
//  Created by Wang Wei on 5/18/13.
//  Copyright (c) 2013 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafConnection.h"

@interface SeafActivityViewController : UIViewController<UIWebViewDelegate>

@property (strong, nonatomic) SeafConnection *connection;

@end
