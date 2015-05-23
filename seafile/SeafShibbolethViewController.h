//
//  SeafShibbolethViewController.h
//  seafilePro
//
//  Created by Wang Wei on 4/25/15.
//  Copyright (c) 2015 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SeafShibbolethViewController : UIViewController

- (id)init:(SeafConnection *)sconn;
- (void)start;

@end
