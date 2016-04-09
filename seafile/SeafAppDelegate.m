//
//  SeafAppDelegate.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Photos/Photos.h>

#import "SeafAppDelegate.h"
#import "SVProgressHUD.h"
#import "AFNetworking.h"
#import "Debug.h"
#import "Utils.h"


@interface SeafAppDelegate () <UITabBarControllerDelegate, UIAlertViewDelegate, PHPhotoLibraryChangeObserver, CLLocationManagerDelegate>

@property UIBackgroundTaskIdentifier bgTask;

@property NSInteger moduleIdx;
@property (readonly) SeafDetailViewController *detailVC;
@property (readonly) UINavigationController *disDetailNav;
@property (strong) NSArray *viewControllers;
@property (readwrite) SeafGlobal *global;

@property (strong) void (^handler_ok)();
@property (strong) void (^handler_cancel)();
@property (strong, nonatomic) dispatch_block_t expirationHandler;
@property BOOL background;
@property (strong) NSMutableArray *monitors;
@property (readwrite) CLLocationManager *locationManager;

@property (retain) NSString *gotoRepo;
@property (retain) NSString *gotoPath;

@end

@implementation SeafAppDelegate
@synthesize startVC = _startVC;
@synthesize tabbarController = _tabbarController;
@synthesize globalMailComposer = _globalMailComposer;

- (BOOL)shouldContinue
{
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        if (conn.inAutoSync) return true;
    }
    return SeafGlobal.sharedObject.uploadingnum != 0 || SeafGlobal.sharedObject.downloadingnum != 0;
}

- (void)selectAccount:(SeafConnection *)conn;
{
    conn.delegate = self;
    @synchronized(self) {
        if ([[SeafGlobal sharedObject] connection] != conn) {
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
#if !(TARGET_IPHONE_SIMULATOR)
    if (self.deviceToken)
        [conn registerDevice:self.deviceToken];
#endif
}

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
            if (!success) return;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^(void){
                [self openFile:repoId path:path];
            });
        }];
    } else
        [self openFile:repoId path:path];
    return true;
}

- (void)uploadFile:(NSString *)path
{
    [[self masterNavController:TABBED_SEAFILE] popToRootViewControllerAnimated:NO];
    SeafUploadFile *file = [SeafGlobal.sharedObject.connection getUploadfile:path];
    [self.fileVC uploadFile:file];
}

- (BOOL)openFileURL:(NSURL*)url
{
    Debug("open %@", url);
    NSString *uploadDir = [SeafGlobal.sharedObject uniqueUploadDir];
    NSURL *to = [NSURL fileURLWithPath:[uploadDir stringByAppendingPathComponent:url.lastPathComponent]];
    Debug("Copy %@, to %@, %@, %@\n", url, to, to.absoluteString, to.path);
    BOOL ret = [Utils checkMakeDir:uploadDir];
    if (!ret) return false;
    ret = [Utils copyFile:url to:to];
    if (!ret) return false;
    if (self.window.rootViewController == self.startNav) {
        [self.startVC selectDefaultAccount:^(bool success) {
            if (success) {
                [self uploadFile:to.path];
            }
        }];
    } else
        [self uploadFile:to.path];

    return true;
}

- (BOOL)openURL:(NSURL*)url
{
    if (!url) return false;
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
    return [self openURL:url];
}


- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation
{
    Debug("Calling Application Bundle ID: %@, url: %@", sourceApplication, url);
    return [self openURL:url];
}


- (void)checkPhotoChanges:(NSNotification *)notification
{
    Debug("Start check photos changes.");
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        [conn checkPhotoChanges:notification];
    }
}

- (void)delayedInit
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
    Debug("Current app version is %@\n%@\n", version, infoDictionary);
    [SeafGlobal.sharedObject setObject:version forKey:@"VERSION"];
    [SeafGlobal.sharedObject startTimer];
    [Utils clearAllFiles:SeafGlobal.sharedObject.tempDir];

    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        [conn checkAutoSync];
    }
    if (ios8)
         [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
    else
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkPhotoChanges:) name:ALAssetsLibraryChangedNotification object:SeafGlobal.sharedObject.assetsLibrary];
    [self checkBackgroundUploadStatus];
    [SeafGlobal.sharedObject synchronize];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    Debug("%@", [[NSBundle mainBundle] infoDictionary]);
    _global = [SeafGlobal sharedObject];
    [_global migrate];
    [self initTabController];

    if (ios7)
        [[UITabBar appearance] setTintColor:[UIColor colorWithRed:238.0f/256 green:136.0f/256 blue:51.0f/255 alpha:1.0]];
    else
        [[UITabBar appearance] setSelectedImageTintColor:[UIColor colorWithRed:238.0f/256 green:136.0f/256 blue:51.0f/255 alpha:1.0]];

    [SeafGlobal.sharedObject loadAccounts];

    _monitors = [[NSMutableArray alloc] init];
    _startNav = (UINavigationController *)self.window.rootViewController;
    _startVC = (StartViewController *)_startNav.topViewController;

    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:OBJECTS_DIR]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:AVATARS_DIR]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:CERTS_DIR]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:BLOCKS_DIR]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:UPLOADS_DIR]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:EDIT_DIR]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:THUMB_DIR]];

    [Utils checkMakeDir:SeafGlobal.sharedObject.tempDir];

#if !(TARGET_IPHONE_SIMULATOR)
    if (ios8) {
        [[UIApplication sharedApplication] registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge) categories:nil]];
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    } else
        [[UIApplication sharedApplication] registerForRemoteNotificationTypes:UIRemoteNotificationTypeBadge|UIRemoteNotificationTypeAlert|UIRemoteNotificationTypeSound];
#endif

    NSDictionary *locationOptions = [launchOptions objectForKey:UIApplicationLaunchOptionsLocationKey];
    if (locationOptions) {
        Debug("Location: %@", locationOptions);
    }
    NSDictionary *dict = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (dict) {
        [self application:application didReceiveRemoteNotification:dict];
    } else
        [self.startVC selectDefaultAccount:^(bool success) {}];
    [[AFNetworkReachabilityManager sharedManager] startMonitoring];

    self.bgTask = UIBackgroundTaskInvalid;
    __weak typeof(self) weakSelf = self;
    self.expirationHandler = ^{
        Debug("Expired, Time Remain = %f, restart background task.", [application backgroundTimeRemaining]);
        [weakSelf startBackgroundTask];
    };

    [SVProgressHUD setBackgroundColor:[UIColor colorWithRed:250.0/256 green:250.0/256 blue:250.0/256 alpha:1.0]];

    [self performSelectorInBackground:@selector(delayedInit) withObject:nil];
    return YES;
}

- (void)enterBackground
{
    Debug("Enter background");
    self.background = YES;
    [self startBackgroundTask];
}

- (void)startBackgroundTask
{
    // Start the long-running task.
    Debug("start background task");
    UIApplication* app = [UIApplication sharedApplication];
    if (UIBackgroundTaskInvalid != self.bgTask) {
        [app endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
    if (!self.shouldContinue) return;

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
    NSString *status = [NSString stringWithFormat:@"Notification received:\n%@",[userInfo description]];
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
    for (id <SeafBackgroundMonitor> monitor in _monitors) {
        [monitor enterBackground];
    }
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    Debug("Seafile will enter foreground");
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    [SeafGlobal.sharedObject loadSettings:[NSUserDefaults standardUserDefaults]];
    [self checkPhotoChanges:nil];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    [application cancelAllLocalNotifications];
    self.background = false;
    for (id <SeafBackgroundMonitor> monitor in _monitors) {
        [monitor enterForeground];
    }
}


- (void)applicationWillTerminate:(UIApplication *)application
{
    // Saves changes in the application's managed object context before the application terminates.
    [[SeafGlobal sharedObject] saveContext];
}


- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController
{
    if ([self.viewControllers indexOfObject:viewController] == TABBED_ACCOUNTS) {
        self.window.rootViewController = _startNav;
        [self.window makeKeyAndVisible];
        return NO;
    }
    return YES;
}

#pragma mark - ViewController
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
    UINavigationController *activityController = [tabs.viewControllers objectAtIndex:TABBED_ACTIVITY];
    UIViewController *accountvc = [tabs.viewControllers objectAtIndex:TABBED_ACCOUNTS];

    fileController.tabBarItem.title = NSLocalizedString(@"Libraries", @"Seafile");
    fileController.tabBarItem.image = [UIImage imageNamed:@"tab-home.png"];
    starredController.tabBarItem.title = NSLocalizedString(@"Starred", @"Seafile");
    starredController.tabBarItem.image = [UIImage imageNamed:@"tab-star.png"];
    settingsController.tabBarItem.title = NSLocalizedString(@"Settings", @"Seafile");
    settingsController.tabBarItem.image = [UIImage imageNamed:@"tab-settings.png"];
    activityController.tabBarItem.title = NSLocalizedString(@"Activity", @"Seafile");
    activityController.tabBarItem.image = [UIImage imageNamed:@"tab-modify.png"];
    accountvc.tabBarItem.title = NSLocalizedString(@"Accounts", @"Seafile");
    accountvc.tabBarItem.image = [UIImage imageNamed:@"tab-account.png"];

    if (IsIpad()) {
        ((UISplitViewController *)fileController).delegate = (id)[[((UISplitViewController *)fileController).viewControllers lastObject] topViewController];
        ((UISplitViewController *)starredController).delegate = (id)[[((UISplitViewController *)starredController).viewControllers lastObject] topViewController];
        ((UISplitViewController *)settingsController).delegate = (id)[[((UISplitViewController *)settingsController).viewControllers lastObject] topViewController];
    }
    self.viewControllers = [NSArray arrayWithArray:tabs.viewControllers];
    _tabbarController = tabs;
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
        if (!_detailVC)
            _detailVC = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
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

- (BOOL)checkNetworkStatus
{
    NSLog(@"network status=%@\n", [[AFNetworkReachabilityManager sharedManager] localizedNetworkReachabilityStatusString]);
    if (![[AFNetworkReachabilityManager sharedManager] isReachable]) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Network unavailable", @"Seafile")
                                                        message:nil
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"OK", @"Seafile")
                                              otherButtonTitles:nil];
        [alert show];
        return NO;
    }
    return YES;
}

- (void)showDetailView:(UIViewController *) c
{
    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:c];
    [nc setModalPresentationStyle:UIModalPresentationFullScreen];
    nc.navigationBar.tintColor = BAR_COLOR;
    [self.window.rootViewController presentViewController:nc animated:YES completion:nil];
}

- (MFMailComposeViewController *)globalMailComposer
{
    if (_globalMailComposer == nil)
        [self cycleTheGlobalMailComposer];
    return _globalMailComposer;
}
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

- (void)continueWithInvalidCert:(NSURLProtectionSpace *)protectionSpace yes:(void (^)())yes no:(void (^)())no
{
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"%@ can't verify the identity of the website \"%@\"", @"Seafile"), APP_NAME, protectionSpace.host];
    NSString *message = NSLocalizedString(@"The certificate from this website is invalid. Would you like to connect to the server anyway?", @"Seafile");

    UIViewController *c = self.window.rootViewController;
    if (self.window.rootViewController.presentedViewController) {
        c = self.window.rootViewController.presentedViewController;
    }

    if (ios8)
        [Utils alertWithTitle:title message:message yes:yes no:no from:c];
    else {
        [SVProgressHUD dismiss];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.handler_ok = yes;
            self.handler_cancel = no;
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:self cancelButtonTitle:STR_CANCEL otherButtonTitles:NSLocalizedString(@"OK", @"Seafile"), nil];
            alert.alertViewStyle = UIAlertViewStyleDefault;
            [alert show];
        });
    }
}

- (BOOL)continueWithInvalidCert:(NSURLProtectionSpace *)protectionSpace
{
    __block BOOL ret = false;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_block_t block = ^{
        [self continueWithInvalidCert:protectionSpace yes:^{
            ret = true;
            dispatch_semaphore_signal(semaphore);
        } no:^{
            ret = false;
            dispatch_semaphore_signal(semaphore);
        }];
    };
    block();
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    return ret;
}
#pragma mark - UIAlertViewDelegate
- (void)alertView:(UIAlertView *)alertView willDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != alertView.cancelButtonIndex) {
        if (self.handler_ok) {
            self.handler_ok();
        }
    } else {
        if (self.handler_cancel)
            self.handler_cancel();
    }
}

#pragma mark - PHPhotoLibraryChangeObserver
- (void)photoLibraryDidChange:(PHChange *)changeInstance
{
    Debug("Photos library changed.");
    // Call might come on any background queue. Re-dispatch to the main queue to handle it.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self checkPhotoChanges:nil];
    });
}

- (void)addBackgroundMonitor:(id<SeafBackgroundMonitor>)monitor
{
    [_monitors addObject:monitor];
}


+ (void)showActionSheet:(UIActionSheet *)actionSheet fromBarButtonItem:(UIBarButtonItem *)item
{
    if (IsIpad())
        [actionSheet showFromBarButtonItem:item animated:YES];
    else
        [actionSheet showInView:[UIApplication sharedApplication].keyWindow];
}

#pragma mark - CLLocationManagerDelegate
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    Debug("Location updated: %@", locations);
}

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
    if (needLocationService) {
        [self startSignificantChangeUpdates];
    } else {
        [self stopSignificantChangeUpdates];
    }
}

- (void)openFile:(NSString *)repo path:(NSString *)path
{
    [SeafGlobal.sharedObject setObject:repo forKey:@"SEAFILE-OPEN-REPO"];
    [SeafGlobal.sharedObject setObject:path forKey:@"SEAFILE-OPEN-PATH"];

    Debug("open file %@ %@", repo, path);
    self.gotoRepo = repo;
    self.gotoPath = path;
    if (self.tabbarController.selectedIndex != TABBED_SEAFILE)
        [self.tabbarController setSelectedIndex:TABBED_SEAFILE];
    NSArray *arr = [[self masterNavController:TABBED_SEAFILE] popToRootViewControllerAnimated:NO];
    if (arr.count == 0)
        [SeafAppDelegate checkOpenLink:self.fileVC];
}

- (void)endGoto
{
    self.gotoRepo = nil;
    self.gotoPath = nil;
}

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

@end
