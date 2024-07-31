//
//  SeafAppDelegate.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Photos/Photos.h>
#import "SVProgressHUD.h"
#import "AFNetworking.h"

#import "SeafAppDelegate.h"
#import "SeafDataTaskManager.h"
#import "SeafStorage.h"

#import "Debug.h"
#import "Utils.h"
#import "Version.h"
#import "SeafWechatHelper.h"
#import "SeafRealmManager.h"

@interface SeafAppDelegate () <UITabBarControllerDelegate, CLLocationManagerDelegate, WXApiDelegate>

@property UIBackgroundTaskIdentifier bgTask;

@property NSInteger moduleIdx;
@property (readonly) UITabBarController *tabbarController;
@property (readonly) SeafDetailViewController *detailVC;
@property (readonly) UINavigationController *disDetailNav;
@property (strong) NSArray *viewControllers;
@property (readwrite) SeafGlobal *global;

@property (strong, nonatomic) dispatch_block_t expirationHandler;
@property BOOL background;
@property (strong) NSMutableArray *monitors;
@property (readwrite) CLLocationManager *locationManager;

@property (retain) NSString *gotoRepo;
@property (retain) NSString *gotoPath;
@property BOOL autoBackToDefaultAccount;
@property (nonatomic, assign) BOOL needReset;
@property (nonatomic, strong) NSMutableArray *backgroundTaskIDs;
@end

@implementation SeafAppDelegate
@synthesize startVC = _startVC;
@synthesize tabbarController = _tabbarController;
@synthesize globalMailComposer = _globalMailComposer;

// Determines whether the app has ongoing tasks that would require it to keep running in the background.
- (BOOL)shouldContinue
{
    // Check if any connection is in auto-sync mode.
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        if (conn.inAutoSync) return true;
    }
    NSInteger totalDownloadingNum = 0;
    NSInteger totalUploadingNum = 0;
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        SeafAccountTaskQueue *accountQueue =[SeafDataTaskManager.sharedObject accountQueueForConnection:conn];
        totalUploadingNum += accountQueue.fileQueue.taskNumber + accountQueue.uploadQueue.taskNumber;
    }
    // Continue if there are any active uploads or downloads.
    return totalUploadingNum != 0 || totalDownloadingNum != 0;
}

- (void)checkAndUpgradeRealmDB {
    
//    NSString *currentVersion = [SeafStorage.sharedObject objectForKey:@"VERSION"];
//
//    NSString *newVersion = SEAFILE_VERSION;
//    
//    //Versions before 2.9.26 need to be updated
//    NSString *numericString = [currentVersion stringByReplacingOccurrencesOfString:@"." withString:@""];
//    
//    int versionNumber = [numericString intValue];
//    
//    //less than 2.9.27 and need update
//    if (versionNumber < 2927 && [Utils needsUpdateCurrentVersion:currentVersion newVersion:SEAFILE_VERSION]){
//        [[SeafRealmManager shared] deletePhotoWithNotUploadedStatus];
//    }
    
    //test
    [[SeafRealmManager shared] deletePhotoWithNotUploadedStatus];

}

// Selects the provided Seafile connection as the active account, updates navigation state.
- (BOOL)selectAccount:(SeafConnection *)conn
{
    conn.delegate = self;
    BOOL updated = ([[SeafGlobal sharedObject] connection] != conn);
    @synchronized(self) {
        if (updated) {
            [[SeafGlobal sharedObject] setConnection: conn];
            [[self masterNavController:TABBED_SEAFILE] popToRootViewControllerAnimated:NO];
            [[self masterNavController:TABBED_STARRED] popToRootViewControllerAnimated:NO];
            [[self masterNavController:TABBED_SETTINGS] popToRootViewControllerAnimated:NO];
            [[self masterNavController:TABBED_ACTIVITY] popToRootViewControllerAnimated:NO];
            self.fileVC.connection = conn;
            self.starredVC.connection = conn;
            self.settingVC.connection = conn;
            self.actvityVC.connection = conn;
        }
    }
    // Register device for push notifications if token available.
#if !(TARGET_IPHONE_SIMULATOR)
    if (self.deviceToken)
        [conn registerDevice:self.deviceToken];
#endif
    return updated;
}

// Transition to the provided account's interface or maintain current if already displayed.
- (void)enterAccount:(SeafConnection *)conn
{
    BOOL updated = [self selectAccount:conn];
    if (self.window.rootViewController == self.tabbarController)
        return;

    Debug("isActivityEnabled:%d tabbarController: %ld", conn.isActivityEnabled, (long)self.tabbarController.viewControllers.count);
    
    // Adjust tab bar controller's tabs based on the account's features
    if (conn.isActivityEnabled) {
        if (self.tabbarController.viewControllers.count != TABBED_COUNT) {
            [self.tabbarController setViewControllers:self.viewControllers];
        }
    } else {
        if (self.tabbarController.viewControllers.count == TABBED_COUNT) {
            NSMutableArray *vcs = [NSMutableArray arrayWithArray:[self.tabbarController viewControllers]];
            [vcs removeObjectAtIndex:TABBED_ACTIVITY];
            [self.tabbarController setViewControllers:vcs];
        }
    }
    if (updated) {
        // Restart any unfinished tasks and default to the files tab.
        [SeafDataTaskManager.sharedObject startLastTimeUnfinshTaskWithConnection:conn];
        [self.tabbarController setSelectedIndex:TABBED_SEAFILE];
    }
    // Make the tab bar controller the root view controller and display it.
    self.window.rootViewController = self.tabbarController;
    [self.window makeKeyAndVisible];
    
}

// Exit current account and display the start (login) screen.
- (void)exitAccount
{
    self.window.rootViewController = _startNav;
    [self.window makeKeyAndVisible];
}

// Handle opening Seafile-specific URLs, typically used for navigating to a specific file or folder.
- (BOOL)openSeafileURL:(NSURL*)url
{
    Debug("open %@", url);
    NSDictionary *dict = [Utils queryToDict:url.query];
    NSString *repoId = [dict objectForKey:@"repo_id"];
    NSString *path = [dict objectForKey:@"path"];
    if (repoId == nil || path == nil) {
        Warning("Invalid url: %@", url);
        return false;
    }

    if (self.window.rootViewController == self.startNav) {
        [self.startVC selectDefaultAccount:^(bool success) {
            if (!success) {
                NSString *title = NSLocalizedString(@"Failed to open file", @"Seafile");
                return [Utils alertWithTitle:title message:nil handler:nil from:self.startVC];
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^(void){
                [self openFile:repoId path:path];
            });
        }];
    } else
        [self openFile:repoId path:path];
    return true;
}

// Handle opening file URLs to upload local files to Seafile.
- (BOOL)openFileURL:(NSURL*)url
{
    Debug("open %@", url);
    if (self.window.rootViewController == self.startNav) {
        [self.startVC selectDefaultAccount:^(bool success) {
            Debug("enter default account: %d", success);
            if (success) {
                [self handleUploadPathWithUrl:url];
            } else {
                NSString *title = NSLocalizedString(@"Failed to upload file", @"Seafile");
                [Utils alertWithTitle:title message:nil handler:nil from:self.startVC];
            }
        }];
    } else
        [self handleUploadPathWithUrl:url];

    return true;
}

// Processes the file URL for uploading by copying it to a designated upload directory.
- (void)handleUploadPathWithUrl:(NSURL*)url {
    NSString *uploadDir = [[SeafGlobal sharedObject].connection uniqueUploadDir];
    NSURL *to = [NSURL fileURLWithPath:[uploadDir stringByAppendingPathComponent:url.lastPathComponent]];
    BOOL ret = [Utils checkMakeDir:uploadDir];
    if (!ret) return;
    ret = [Utils copyFile:url to:to];
    if (ret) {
        [self uploadFile:to.path];
    }
}

// Upload the specified file to the connected Seafile server.
- (void)uploadFile:(NSString *)path
{
    [[self masterNavController:TABBED_SEAFILE] popToRootViewControllerAnimated:NO];
    SeafUploadFile *file = [[SeafUploadFile alloc] initWithPath:path];
    [self.fileVC uploadFile:file];
}

// Generic method to handle different URL schemes with appropriate actions.
- (BOOL)openURL:(NSURL*)url
{
    if (!url) return false;
    self.autoBackToDefaultAccount = false;
    if ([@"seafile" isEqualToString:url.scheme]) {
        return [self openSeafileURL:url];
    } else if (url != nil && [url isFileURL]) {
        return [self openFileURL: url];
    }
    Warning("Unknown scheme %@", url);
    return false;
}

- (BOOL)application:(UIApplication*)application handleOpenURL:(NSURL*)url
{
    Debug("handleOpenURL: %@", url);
    if ([url.host isEqualToString:@"platformId=wechat"]) {
        return [WXApi handleOpenURL:url delegate:self];
    } else {
        return [self openURL:url];
    }
}


- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation
{
    Debug("Calling Application Bundle ID: %@, url: %@", sourceApplication, url);
    if ([url.host isEqualToString:@"platformId=wechat"]) {
        return [WXApi handleOpenURL:url delegate:self];
    } else {
        return [self openURL:url];
    }
}

- (void)photosDidChange:(NSNotification *)notification
{
    Debug("Start check photos changes.");
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        [conn photosDidChange:notification];
    }
}

- (void)delayedInit
{
    NSUserDefaults *defs = [[NSUserDefaults alloc] initWithSuiteName:SEAFILE_SUITE_NAME];
    NSMutableArray *array = [NSMutableArray new];
    for(NSString *key in defs.dictionaryRepresentation) {
        if ([key hasPrefix:@"EXPORTED/"]) {
            [array addObject:key];
        }
    }
    for(NSString *key in array) {
        [defs removeObjectForKey:key];
    }

    Debug("clear tmp dir: %@", SeafStorage.sharedObject.tempDir);
    [Utils clearAllFiles:SeafStorage.sharedObject.tempDir];

    Debug("Current app version is %@\n", SEAFILE_VERSION);
    [SeafGlobal.sharedObject startTimer];
    [self addBackgroundMonitor:SeafGlobal.sharedObject];

    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        [conn checkAutoSync];
    }

    [self checkBackgroundUploadStatus];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    Info("%@", [[NSBundle mainBundle] infoDictionary]);
    //2.9.27:Versions before 2.9.26 need to be updated
    [self checkAndUpgradeRealmDB];
    
    _global = [SeafGlobal sharedObject];
    [_global migrate];
    [self initTabController];
    [[UITabBar appearance] setTintColor:[UIColor colorWithRed:238.0f/256 green:136.0f/256 blue:51.0f/255 alpha:1.0]];
    [SeafGlobal.sharedObject loadAccounts];

    self.window.backgroundColor = [UIColor whiteColor];
    self.autoBackToDefaultAccount = false;
    _monitors = [[NSMutableArray alloc] init];
    _startNav.view.backgroundColor = [UIColor whiteColor];
    _startNav = (UINavigationController *)self.window.rootViewController;

    _startVC = (StartViewController *)_startNav.topViewController;


#if !(TARGET_IPHONE_SIMULATOR)
    [[UIApplication sharedApplication] registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge) categories:nil]];
    [[UIApplication sharedApplication] registerForRemoteNotifications];
#endif

    NSDictionary *locationOptions = [launchOptions objectForKey:UIApplicationLaunchOptionsLocationKey];
    if (locationOptions) {
        Debug("Location: %@", locationOptions);
    }
    NSDictionary *dict = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (dict) {
        [self application:application didReceiveRemoteNotification:dict];
    } else {
        [self.startVC performSelector:@selector(selectDefaultAccount:) withObject:^(bool success) {} afterDelay:0.5f];
    }

    self.bgTask = UIBackgroundTaskInvalid;
    self.needReset = NO;
    __weak typeof(self) weakSelf = self;
    self.expirationHandler = ^{
        Debug("Expired, Time Remain = %f, restart background task.", [application backgroundTimeRemaining]);
        if (@available(iOS 13.0, *)) {
            [application endBackgroundTask:weakSelf.bgTask];
            weakSelf.needReset = YES;
            if (SeafGlobal.sharedObject.connection.accountIdentifier) {
                [[SeafDataTaskManager.sharedObject accountQueueForConnection:SeafGlobal.sharedObject.connection].uploadQueue clearTasks];
            }
            //reset all upload photos and connection
            for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
                conn.inAutoSync = false;
                [conn.photoBackup resetAll];
                [SeafDataTaskManager.sharedObject cancelAutoSyncTasks:conn];
                [conn clearUploadCache];
            }
        } else {
            //not work in iOS 13, and while call in app  become active next time
            [weakSelf startBackgroundTask];
        }
    };

    [SVProgressHUD setBackgroundColor:[UIColor colorWithRed:250.0/256 green:250.0/256 blue:250.0/256 alpha:1.0]];

    [self performSelectorInBackground:@selector(delayedInit) withObject:nil];

    [UIApplication sharedApplication].delegate.window.backgroundColor = [UIColor whiteColor];

    return YES;
}

- (void)enterBackground
{
    Debug("Enter background");
    self.background = YES;
    [self startBackgroundTask];
}

// Background tasks management to ensure the app can continue operations when sent to background.
- (void)startBackgroundTask
{
    // Start the long-running task.
    UIApplication* app = [UIApplication sharedApplication];
    if (UIBackgroundTaskInvalid != self.bgTask) {
        [app endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
    // Start a new background task if there are tasks that should continue running.
    if (!self.shouldContinue) return;
    Debug("start background task");
    self.bgTask = [app beginBackgroundTaskWithExpirationHandler:self.expirationHandler];
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    Debug("token=%@, %ld\n", deviceToken, (unsigned long)deviceToken.length);
    _deviceToken = deviceToken;
    if (self.deviceToken)
        [SeafGlobal.sharedObject.connection registerDevice:self.deviceToken];
}
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    Debug("error=%@", error);
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
{
    NSString *status __attribute__((unused)) = [NSString stringWithFormat:@"Notification received:\n%@",[userInfo description]];
    NSString *badgeStr = [[userInfo objectForKey:@"aps"] objectForKey:@"badge"];
    NSDictionary *alert = [[userInfo objectForKey:@"aps"] objectForKey:@"alert"];
    NSArray *args = [alert objectForKey:@"loc-args"];
    Debug("status=%@, badge=%@", status, badgeStr);
    if ([args isKindOfClass:[NSArray class]] && args.count == 2) {
        NSString *username = [args objectAtIndex:0];
        NSString *server = [args objectAtIndex:1];
        if (badgeStr && [badgeStr intValue] > 0) {
            SeafConnection *connection = [[SeafGlobal sharedObject] getConnection:server username:username];
            if (!connection) return;
            self.window.backgroundColor = [UIColor whiteColor];
            self.window.rootViewController = self.startNav;
            [self.window makeKeyAndVisible];
            [self.startVC checkSelectAccount:connection];
        }
    }
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [self enterBackground];
    
    //not used
    for (id <SeafBackgroundMonitor> monitor in _monitors) {
        [monitor enterBackground];
    }
    
    //Account Status
    if (self.window.rootViewController != self.startNav && SeafGlobal.sharedObject.connection.touchIdEnabled) {
        Debug("hiding contents when enter background");
        [self exitAccount];
        self.autoBackToDefaultAccount = true;
    } else
        self.autoBackToDefaultAccount = false;
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    Debug("Seafile will enter foreground");
    [application endBackgroundTask:self.bgTask];
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    if (self.needReset == YES) {
        self.needReset = NO;
//        NSNotification *note = [NSNotification notificationWithName:@"photosDidChange" object:nil userInfo:@{@"force" : @(YES)}];
//        [self photosDidChange:note];
        for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
            [conn checkAutoSync];
        }
    } else {
        [self photosDidChange:nil];
    }
    for (id <SeafBackgroundMonitor> monitor in _monitors) {
        [monitor enterForeground];
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    if (!self.background)
        return;
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    [application cancelAllLocalNotifications];
    self.background = false;
    if (self.autoBackToDefaultAccount) {
        self.autoBackToDefaultAccount = false;
        Debug("Verify TouchId and go back to the last account.");
        [self.startVC selectDefaultAccount:^(bool success) {}];
    }
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Saves changes in the application's managed object context before the application terminates.
}

- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController
{
    if ([self.viewControllers indexOfObject:viewController] == TABBED_ACCOUNTS) {
        [self exitAccount];
        return NO;
    }
    return YES;
}

#pragma mark - ViewController
// Method to initialize and setup the tab controller with all required tabs.
- (void)initTabController
{
    UITabBarController *tabs;
    if (IsIpad()) {
        tabs = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"TABVC"];
    } else {
        tabs = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"TABVC"];
    }
    UIViewController *fileController = [tabs.viewControllers objectAtIndex:TABBED_SEAFILE];
    UIViewController *starredController = [tabs.viewControllers objectAtIndex:TABBED_STARRED];
    UIViewController *settingsController = [tabs.viewControllers objectAtIndex:TABBED_SETTINGS];
    UIViewController *activityController = [tabs.viewControllers objectAtIndex:TABBED_ACTIVITY];
    UIViewController *accountvc = [tabs.viewControllers objectAtIndex:TABBED_ACCOUNTS];

    UITabBarItem *homeItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Libraries", @"Seafile") image:[UIImage imageNamed:@"tab-home.png"] tag:0];
    fileController.tabBarItem = homeItem;
    
    UITabBarItem *starItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Starred", @"Seafile") image:[UIImage imageNamed:@"tab-star.png"] tag:1];
    starredController.tabBarItem = starItem;
    
    UITabBarItem *settingsItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Settings", @"Seafile") image:[UIImage imageNamed:@"tab-settings.png"] tag:2];
    settingsController.tabBarItem = settingsItem;
    
    UITabBarItem *activityItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Activity", @"Seafile") image:[UIImage imageNamed:@"tab-modify.png"] tag:3];
    activityController.tabBarItem = activityItem;
    
    UITabBarItem *accountItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Accounts", @"Seafile") image:[UIImage imageNamed:@"tab-account.png"] tag:4];
    accountvc.tabBarItem = accountItem;

    if (IsIpad()) {
        ((UISplitViewController *)fileController).delegate = (id)[[((UISplitViewController *)fileController).viewControllers lastObject] topViewController];
        ((UISplitViewController *)starredController).delegate = (id)[[((UISplitViewController *)starredController).viewControllers lastObject] topViewController];
        ((UISplitViewController *)settingsController).delegate = (id)[[((UISplitViewController *)settingsController).viewControllers lastObject] topViewController];
    }
    self.viewControllers = [NSArray arrayWithArray:tabs.viewControllers];
    _tabbarController = tabs;
    _tabbarController.navigationController.navigationBar.backgroundColor = [UIColor whiteColor];
    _tabbarController.delegate = self;
    if (ios7)
        _tabbarController.view.backgroundColor = [UIColor colorWithRed:150.0f/255 green:150.0f/255 blue:150.0f/255 alpha:1];

}

- (UITabBarController *)tabbarController
{
    if (!_tabbarController)
        [self initTabController];
    return _tabbarController;
}

- (StartViewController *)startVC
{
    if (!_startVC)
        _startVC = [[StartViewController alloc] init];
    return _startVC;
}

- (UINavigationController *)masterNavController:(int)index
{
    if (!IsIpad())
        return [self.viewControllers objectAtIndex:index];
    else {
        return (index == TABBED_ACTIVITY)? [self.viewControllers objectAtIndex:index] : [[[self.viewControllers objectAtIndex:index] viewControllers] objectAtIndex:0];
    }
}

- (SeafFileViewController *)fileVC
{
    return (SeafFileViewController *)[[self masterNavController:TABBED_SEAFILE] topViewController];
}

- (UIViewController *)detailViewControllerAtIndex:(int)index
{
    if (IsIpad()) {
        return [[[[self.viewControllers objectAtIndex:index] viewControllers] lastObject] topViewController];
    } else {
        if (!_detailVC) {
            _detailVC = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
        }

        return _detailVC;
    }
}

- (SeafStarredFilesViewController *)starredVC
{
    return (SeafStarredFilesViewController *)[[self masterNavController:TABBED_STARRED] topViewController];
}

- (SeafSettingsViewController *)settingVC
{
    return (SeafSettingsViewController *)[[self masterNavController:TABBED_SETTINGS] topViewController];
}

- (SeafActivityViewController *)actvityVC
{
    return (SeafActivityViewController *)[[self.viewControllers objectAtIndex:TABBED_ACTIVITY] topViewController];
}

- (void)showDetailView:(UIViewController *) c
{
    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:c];
    [nc setModalPresentationStyle:UIModalPresentationFullScreen];
    nc.navigationBar.tintColor = BAR_COLOR;
    [self.window.rootViewController presentViewController:nc animated:YES completion:nil];
}

// Gets or creates the global mail composer to handle email interactions.
- (MFMailComposeViewController *)globalMailComposer
{
    if (_globalMailComposer == nil)
        [self cycleTheGlobalMailComposer];
    return _globalMailComposer;
}

// Recreates the mail composer to handle known iOS bugs with its caching.
-(void)cycleTheGlobalMailComposer
{
    // we are cycling the damned GlobalMailComposer... due to horrible iOS issue
    // http://stackoverflow.com/questions/25604552/i-have-real-misunderstanding-with-mfmailcomposeviewcontroller-in-swift-ios8-in/25864182#25864182
    _globalMailComposer = nil;
    _globalMailComposer = [[MFMailComposeViewController alloc] init];
}

#pragma - SeafConnectionDelegate
- (void)loginRequired:(SeafConnection *)connection
{
    Debug("Token expired, should login again.");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^(void){
        self.window.rootViewController = _startNav;
        [self.window makeKeyAndVisible];
        [self.startVC performSelector:@selector(selectAccount:) withObject:connection afterDelay:0.5f];
    });
}

// Handle quota-related issues by notifying the user if the server quota is exceeded.
- (void)outOfQuota:(SeafConnection *)connection
{
    Warning("Out of quota.");
    [Utils alertWithTitle:NSLocalizedString(@"Out of quota", @"Seafile") message:nil handler:nil from:self.window.rootViewController];
}

// Adds a background monitor to keep track of significant app events like entering or leaving the background.
- (void)addBackgroundMonitor:(id<SeafBackgroundMonitor>)monitor
{
    [_monitors addObject:monitor];
}

#pragma mark - CLLocationManagerDelegate
// Responds to location updates which might trigger background uploads based on significant location changes.
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    Debug("Location updated: %@", locations);
    //    [self photosDidChange:nil];//modified at 2024.7.31
    if (self.needReset == YES) {
        self.needReset = NO;
        for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
            [conn checkAutoSync];
        }
    } else {
        [self photosDidChange:nil];
    }
}

// Starts or stops significant location updates based on the app's current needs.
- (void)startSignificantChangeUpdates
{
    Debug("_locationManager=%@", _locationManager);
    if (nil == _locationManager) {
        Debug("START");
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
        [_locationManager startMonitoringSignificantLocationChanges];
    }
}

- (void)stopSignificantChangeUpdates
{
    if (_locationManager) {
        Debug("STOP");
        [_locationManager stopMonitoringSignificantLocationChanges];
        _locationManager = nil;
    }
}

// Check and update the background upload status based on connectivity and user preferences.
- (void)checkBackgroundUploadStatus
{
    BOOL needLocationService = false;
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        if (conn.autoSync && conn.backgroundSync && conn.autoSyncRepo.length > 0) {
            Debug("account %@ %@ (%d %d %@) need location service", conn.address, conn.username, conn.autoSync, conn.backgroundSync, conn.autoSyncRepo);
            needLocationService = true;
        }
    }
    Debug("needLocationService: %d", needLocationService);
    // Use CLLocationManager to start or stop monitoring significant location changes based on active features.
    if (needLocationService) {
        [self startSignificantChangeUpdates];
    } else {
        [self stopSignificantChangeUpdates];
    }
}

// Generic method to open any file by path and repository ID.
- (void)openFile:(NSString *)repo path:(NSString *)path
{
    [SeafStorage.sharedObject setObject:repo forKey:@"SEAFILE-OPEN-REPO"];
    [SeafStorage.sharedObject setObject:path forKey:@"SEAFILE-OPEN-PATH"];

    Debug("open file %@ %@", repo, path);
    self.gotoRepo = repo;
    self.gotoPath = path;
    if (self.tabbarController.selectedIndex != TABBED_SEAFILE)
        [self.tabbarController setSelectedIndex:TABBED_SEAFILE];
    NSArray *arr = [[self masterNavController:TABBED_SEAFILE] popToRootViewControllerAnimated:NO];
    if (arr.count == 0)
        [SeafAppDelegate checkOpenLink:self.fileVC];
}

// Ensures navigation ends if a file link cannot be opened.
- (void)endGoto
{
    self.gotoRepo = nil;
    self.gotoPath = nil;
}

// Checks if a direct link to a file can be opened and navigates accordingly.
- (void)checkOpenLink:(SeafFileViewController *)c
{
    if (!self.gotoRepo || !self.gotoPath)
        return;
    Debug("open file %@ %@", self.gotoRepo, self.gotoPath);
    if (![c goTo:self.gotoRepo path:self.gotoPath]) {
        Debug("Stop open file %@ %@", self.gotoRepo, self.gotoPath);
        [self endGoto];
    }
}

+ (void)checkOpenLink:(SeafFileViewController *)c
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^(void){
        [appdelegate checkOpenLink:c];
    });
}

# pragma mark- wechat callback
// Facilitates response handling for WeChat-specific actions within the app.
- (void)onResp:(BaseResp *)resp {
    if([resp isKindOfClass:[SendMessageToWXResp class]]) {
        switch (resp.errCode) {
            case WXSuccess:
                Debug(@"share to wechar success");
                break;
            case WXErrCodeSentFail:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to share to WeChat", @"Seafile")];
                break;
            case WXErrCodeUserCancel:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Share Cancelled", @"Seafile")];
                break;
            default:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to share to WeChat", @"Seafile")];
                break;
        }
    }
}

#pragma mark topViewController
+ (UIViewController *)topViewController {
    SeafAppDelegate *delegate = (SeafAppDelegate*)[UIApplication sharedApplication].delegate;
    return  [delegate topViewController];
}

// Finds the topmost view controller in the navigation stack to handle certain UI actions.
- (UIViewController *)topViewController {
    UIViewController *rootVC = [self.window rootViewController];
    UIViewController *topVC = [self findTopViewController:rootVC];
    while (topVC.presentedViewController) {
        topVC = [self findTopViewController:topVC.presentedViewController];
    }
    return topVC;
}

// Recursively searches for the topmost view controller.
- (UIViewController *)findTopViewController:(UIViewController *)vc {
    if ([vc isKindOfClass:[UINavigationController class]]) {
        return [self findTopViewController:[(UINavigationController *)vc topViewController]];
    } else if ([vc isKindOfClass:[UITabBarController class]]) {
        return [self findTopViewController:[(UITabBarController *)vc selectedViewController]];
    } else {
        return vc;
    }
    return nil;
}

@end
