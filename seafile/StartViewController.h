//
//  StartViewController.h
//  seafile
//
//  Created by Wang Wei on 8/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "SeafConnection.h"
#import "ColorfulButton.h"


@interface StartViewController : UIViewController

- (bool)saveAccount:(SeafConnection *)conn;
- (void)checkSelectAccount:(SeafConnection *)conn;
- (void)selectDefaultAccount:(void (^)(bool success))handler;

@end
