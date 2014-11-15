//
//  SeafProviderFileViewController.h
//  seafilePro
//
//  Created by Wang Wei on 11/14/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DocumentPickerViewController.h"
#import "SeafDir.h"

@interface SeafProviderFileViewController : UITableViewController

@property (strong, nonatomic) SeafDir *directory;
@property (strong) DocumentPickerViewController *root;

@end
