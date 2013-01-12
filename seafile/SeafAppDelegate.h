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
#import "SeafUploadsViewController.h"
#import "SeafStarredFilesViewController.h"
#import "SeafDetailViewController.h"
#import "SeafSettingsViewController.h"
#import "Reachability.h"


@interface SeafAppDelegate : UIResponder <UIApplicationDelegate> {
    Reachability* internetReach;
    Reachability* wifiReach;
}

@property (strong, nonatomic) UIWindow *window;

@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;

@property (readonly) UINavigationController *startNav;
@property (readonly) StartViewController *startVC;
@property (readonly) UISplitViewController *splitVC;
@property (readonly) SeafFileViewController *masterVC;
@property (readonly) SeafDetailViewController *detailVC;
@property (readonly) SeafUploadsViewController *uploadVC;
@property (readonly) SeafStarredFilesViewController *starredVC;
@property (readonly) SeafSettingsViewController *settingVC;
@property (readonly) UINavigationController *masterNavController;
@property (readonly) UITabBarController *tabbarController;

@property (readonly) NSArray *toolItems1;
@property (readonly) NSArray *toolItems2;
@property (readonly) NSArray *toolItems3;

- (void)saveContext;
- (NSURL *)applicationDocumentsDirectory;
- (BOOL)checkNetworkStatus;

@end
