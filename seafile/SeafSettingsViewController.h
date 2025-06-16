//
//  SeafSettingsViewController.h
//  seafile
//
//  Created by Wang Wei on 10/27/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "SeafConnection.h"
#import "SeafBackupGuideViewController.h"

@interface SeafSettingsViewController : UITableViewController<SeafBackupGuideDelegate>

@property (strong, nonatomic) SeafConnection *connection;

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status;

@end
