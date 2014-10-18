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


enum {
    TABBED_SEAFILE = 0,
    TABBED_STARRED,
    TABBED_ACTIVITY,
    TABBED_DISCUSSION,
    TABBED_SETTINGS,
    TABBED_ACCOUNTS,
};


@interface SeafAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;

@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;

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
@property (readonly) ALAssetsLibrary *assetsLibrary;



@property (retain) NSMutableArray *conns;
@property (readwrite) SeafConnection *connection;


- (UINavigationController *)masterNavController:(int)index;
- (UIViewController *)detailViewController:(int)index;

- (void)showDetailView:(UIViewController *) c;
-(void)cycleTheGlobalMailComposer;


- (void)saveContext;
- (NSURL *)applicationDocumentsDirectory;
- (BOOL)checkNetworkStatus;
- (void)deleteAllObjects: (NSString *) entityDescription;

+ (void)incDownloadnum;
+ (void)decDownloadnum;
+ (void)incUploadnum;

+ (void)finishDownload:(id<SeafDownloadDelegate>) file result:(BOOL)result;
+ (void)finishUpload:(SeafUploadFile *) file result:(BOOL)result;

+ (void)backgroundUpload:(SeafUploadFile *)file;
+ (void)backgroundDownload:(id<SeafDownloadDelegate>)file;
+ (void)removeBackgroundUpload:(SeafUploadFile *)file;

+ (ALAssetsLibrary *)assetsLibrary;

- (void)checkIconBadgeNumber;
- (void)saveAccounts;
- (SeafConnection *)getConnection:(NSString *)url username:(NSString *)username;

- (int)uploadnum;

@end
