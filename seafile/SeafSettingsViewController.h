//
//  SeafSettingsViewController.h
//  seafile
//
//  Created by Wang Wei on 10/27/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MessageUI/MFMailComposeViewController.h>

#import "SeafConnection.h"

@interface SeafSettingsViewController : UITableViewController<UIAlertViewDelegate, SSConnectionAccountDelegate, MFMailComposeViewControllerDelegate>

@property (strong, nonatomic) SeafConnection *connection;

@end
