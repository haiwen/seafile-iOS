//
//  SeafAppDelegate.h
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MessageUI/MFMailComposeViewController.h>
#import <CoreLocation/CoreLocation.h>

#import "SeafConnection.h"
#import "StartViewController.h"
#import "SeafFileViewController.h"
#import "SeafStarredFilesViewController.h"
#import "SeafDetailViewController.h"
#import "SeafSettingsViewController.h"
#import "SeafActivityViewController.h"
#import "SeafGlobal.h"

enum {
    TABBED_SEAFILE = 0,
    TABBED_STARRED,
    TABBED_ACTIVITY,
    TABBED_SETTINGS,
    TABBED_ACCOUNTS,
    TABBED_COUNT,
};

@protocol SeafBackgroundMonitor <NSObject>
- (void)enterBackground;
- (void)enterForeground;
@end


/* Additional strings for agi18n */
#define STR_1 NSLocalizedString(@"Release to refresh...", @"Release to refresh status")
#define STR_2 NSLocalizedString(@"Pull down to refresh...", @"Pull down to refresh status")
#define STR_3 NSLocalizedString(@"Loading...", @"Loading Status")
#define STR_4 NSLocalizedString(@"Last Updated: %@", nil)
#define STR_5 NSLocalizedString(@"SEAFILE_LOC_KEY_FORMAT", @"Seafile push notification message")
#define STR_6 NSLocalizedString(@"Send", nil)
#define STR_7 NSLocalizedString(@"%@ can't verify the identity of the website \"%@\"", @"Seafile"), challenge.protectionSpace.host];
#define STR_8 NSLocalizedString(@"The certificate from this website has been changed. Would you like to connect to the server anyway?", @"Seafile")
#define STR_9 NSLocalizedString(@"The certificate from this website is invalid. Would you like to connect to the server anyway?", @"Seafile");
#define STR_10 NSLocalizedString(@"uploading", @"Seafile")
#define STR_11 NSLocalizedString(@"modified", @"Seafile")
#define STR_12 NSLocalizedString(@"A file with the same name already exists, do you want to overwrite?", @"Seafile")
#define STR_13 NSLocalizedString(@"Files with the same name already exist, do you want to overwrite?", @"Seafile")
#define STR_15 NSLocalizedString(@"Your device cannot authenticate using Touch ID.", @"Seafile")


@interface SeafAppDelegate : UIResponder <UIApplicationDelegate, SeafConnectionDelegate>
@property (strong, nonatomic) UIWindow *window;

@property (readonly) UINavigationController *startNav;

@property (strong, readonly) StartViewController *startVC;
@property (readonly) SeafFileViewController *fileVC;
@property (readonly) SeafStarredFilesViewController *starredVC;
@property (readonly) SeafSettingsViewController *settingVC;
@property (readonly) SeafActivityViewController *actvityVC;
@property (readonly) MFMailComposeViewController *globalMailComposer;
@property (readonly) NSData *deviceToken;

- (void)enterAccount:(SeafConnection *)conn;
- (void)exitAccount;

- (UIViewController *)detailViewControllerAtIndex:(int)index;

- (void)showDetailView:(UIViewController *) c;
- (void)cycleTheGlobalMailComposer;

- (void)addBackgroundMonitor:(id<SeafBackgroundMonitor>)monitor;

- (void)startSignificantChangeUpdates;
- (void)stopSignificantChangeUpdates;
- (void)checkBackgroundUploadStatus;

+ (void)checkOpenLink:(SeafFileViewController *)c;

@end
