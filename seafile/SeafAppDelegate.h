//
//  SeafAppDelegate.h
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MessageUI/MFMailComposeViewController.h>

#import "SeafConnection.h"
#import "StartViewController.h"
#import "SeafFileViewController.h"
#import "SeafStarredFilesViewController.h"
#import "SeafDetailViewController.h"
#import "SeafSettingsViewController.h"
#import "SeafActivityViewController.h"
#import "SeafDisMasterViewController.h"
#import "SeafGlobal.h"

enum {
    TABBED_SEAFILE = 0,
    TABBED_STARRED,
    TABBED_ACTIVITY,
    TABBED_DISCUSSION,
    TABBED_SETTINGS,
    TABBED_ACCOUNTS,
};


/* Additional strings for agi18n */
#define STR_1 NSLocalizedString(@"Release to refresh...", @"Release to refresh status")
#define STR_2 NSLocalizedString(@"Pull down to refresh...", @"Pull down to refresh status")
#define STR_3 NSLocalizedString(@"Loading...", @"Loading Status")
#define STR_4 NSLocalizedString(@"Last Updated: %@", nil)
#define STR_5 NSLocalizedString(@"SEAFILE_LOC_KEY_FORMAT", @"Seafile push notification message")
#define STR_6 NSLocalizedString(@"Send", nil)

@interface SeafAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;

@property (readonly) UINavigationController *startNav;
@property (readonly) UITabBarController *tabbarController;

@property (strong, readonly) StartViewController *startVC;
@property (readonly) SeafFileViewController *fileVC;
@property (readonly) SeafStarredFilesViewController *starredVC;
@property (readonly) SeafSettingsViewController *settingVC;
@property (readonly) SeafActivityViewController *actvityVC;
@property (readonly) SeafDisMasterViewController *discussVC;
@property (readonly) MFMailComposeViewController *globalMailComposer;
@property (readonly) NSData *deviceToken;


- (void)selectAccount:(SeafConnection *)conn;

- (UINavigationController *)masterNavController:(int)index;
- (UIViewController *)detailViewControllerAtIndex:(int)index;

- (void)showDetailView:(UIViewController *) c;
- (void)cycleTheGlobalMailComposer;
- (SeafDisDetailViewController *)msgDetailView;

- (BOOL)checkNetworkStatus;
- (void)checkIconBadgeNumber;

@end
