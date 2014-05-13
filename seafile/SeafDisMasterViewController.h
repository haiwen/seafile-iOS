//
//  SeafDisMasterViewController.h
//  Discussion
//
//  Created by Wang Wei on 5/21/13.
//  Copyright (c) 2013 Wang Wei. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>
#import "SeafConnection.h"

@class SeafDisDetailViewController;


@interface SeafDisMasterViewController : UITableViewController

@property (strong, nonatomic) SeafDisDetailViewController *detailViewController;
@property (strong, nonatomic) SeafConnection *connection;

- (void)refreshView;
- (void)refreshBadge;
- (void)updateLastMessage;

@end
