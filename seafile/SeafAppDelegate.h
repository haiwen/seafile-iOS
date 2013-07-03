//
//  SeafAppDelegate.h
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "SeafConnection.h"
#import "StartViewController.h"
#import "SeafFileViewController.h"
#import "SeafStarredFilesViewController.h"
#import "SeafDetailViewController.h"
#import "SeafSettingsViewController.h"
#import "SeafActivityViewController.h"
#import "SeafDisMasterViewController.h"
#import "Reachability.h"

#define BAR_COLOR     [UIColor colorWithRed:240.0/256 green:128.0/256 blue:48.0/256 alpha:1.0]
#define HEADER_COLOR     [UIColor colorWithRed:246.0/256 green:176.0/256 blue:90.0/256 alpha:1.0]


enum {
    TABBED_SEAFILE = 0,
    TABBED_STARRED,
    TABBED_ACTIVITY,
    TABBED_DISCUSSION,
    TABBED_SETTINGS,
    TABBED_ACCOUNTS,
};


@interface SeafAppDelegate : UIResponder <UIApplicationDelegate> {
    Reachability* internetReach;
    Reachability* wifiReach;
}

@property (strong, nonatomic) UIWindow *window;

@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;

@property (readonly) UINavigationController *startNav;
@property (readonly) UITabBarController *tabbarController;

@property (readonly) StartViewController *startVC;
@property (readonly) SeafFileViewController *fileVC;
@property (readonly) SeafStarredFilesViewController *starredVC;
@property (readonly) SeafSettingsViewController *settingVC;
@property (readonly) SeafActivityViewController *actvityVC;
@property (readonly) SeafDisMasterViewController *discussVC;

@property (readwrite) SeafConnection *connection;

- (UINavigationController *)masterNavController:(int)index;
- (UIViewController *)detailViewController:(int)index;

- (void)showDetailView:(UIViewController *) c;


- (void)saveContext;
- (NSURL *)applicationDocumentsDirectory;
- (BOOL)checkNetworkStatus;
- (void) deleteAllObjects: (NSString *) entityDescription;

+ (void)incDownloadnum;
+ (void)decDownloadnum;

+ (void)incUploadnum;
+ (void)decUploadnum;

@end
