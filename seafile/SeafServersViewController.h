//
//  SeafServersViewController.h
//  seafile
//
//  Created by Wang Wei on 11/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "StartViewController.h"
#import "InputAlertPrompt.h"

#define DEFAULT_SERVER_URL @"https://www.gonggeng.org/seahub"


@interface SeafServersViewController : UITableViewController<InputDoneDelegate>

- (id)initWithController:(StartViewController *)controller;

@end
