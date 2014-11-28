//
//  SeafAppDelegate.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//


#import "SeafAppDelegate.h"
#import "SeafDisDetailViewController.h"
#import "AFNetworking.h"
#import "Debug.h"
#import "Utils.h"


@interface SeafAppDelegate () <UITabBarControllerDelegate>

@property UIBackgroundTaskIdentifier bgTask;

@property NSInteger moduleIdx;
@property (readonly) SeafDetailViewController *detailVC;
@property (readonly) SeafDisDetailViewController *disDetailVC;
@property (readonly) UINavigationController *disDetailNav;
@property (strong) NSArray *viewControllers;
@property (readwrite) SeafGlobal *global;

@end

@implementation SeafAppDelegate
@synthesize startVC = _startVC;
@synthesize tabbarController = _tabbarController;

- (void)selectAccount:(SeafConnection *)conn;
{
    @synchronized(self) {
        if ([[SeafGlobal sharedObject] connection] != conn) {
            conn.delegate = self;
            [[SeafGlobal sharedObject] setConnection: conn];
            [[self masterNavController:TABBED_SEAFILE] popToRootViewControllerAnimated:NO];
            [[self masterNavController:TABBED_STARRED] popToRootViewControllerAnimated:NO];
            [[self masterNavController:TABBED_SETTINGS] popToRootViewControllerAnimated:NO];
            [[self masterNavController:TABBED_ACTIVITY] popToRootViewControllerAnimated:NO];
            [[self masterNavController:TABBED_DISCUSSION] popToRootViewControllerAnimated:NO];
            self.fileVC.connection = conn;
            self.starredVC.connection = conn;
            self.settingVC.connection = conn;
            self.actvityVC.connection = conn;
            self.discussVC.connection = conn;
        }
    }
    if (self.deviceToken)
        [conn registerDevice:self.deviceToken];
}

- (BOOL)application:(UIApplication*)application handleOpenURL:(NSURL*)url
{
    if (url != nil && [url isFileURL]) {
        NSURL *to = [NSURL fileURLWithPath:[[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"] stringByAppendingPathComponent:url.lastPathComponent ]];
        Debug("Copy %@, to %@, %@, %@\n", url, to, to.absoluteString, to.path);
        [Utils copyFile:url to:to];
        if (self.window.rootViewController == self.startNav)
            if (![self.startVC selectDefaultAccount])
                return NO;
        ;
        [[self masterNavController:TABBED_SEAFILE] popToRootViewControllerAnimated:NO];
        SeafUploadFile *file = [SeafGlobal.sharedObject.connection getUploadfile:to.path];
        [self.fileVC uploadFile:file];
    }
    return YES;
}

- (void)delayedInit
{
    [[AFNetworkReachabilityManager sharedManager] startMonitoring];
    [self cycleTheGlobalMailComposer];
    [SeafGlobal.sharedObject startTimer];
    [SeafGlobal.sharedObject clearRepoPasswords];
    [Utils clearAllFiles:[SeafGlobal.sharedObject applicationTempDirectory]];

    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        [conn checkAutoSync];
    }
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.
    _global = [SeafGlobal sharedObject];
    [_global migrate];
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDictionary objectForKey:@"CFBundleVersion"];
    Debug("Current app version is %@\n%@\n", version, infoDictionary);
    [SeafGlobal.sharedObject setObject:version forKey:@"VERSION"];
    [SeafGlobal.sharedObject synchronize];
    [self initTabController];

    if (ios7)
        [[UITabBar appearance] setTintColor:[UIColor colorWithRed:238.0f/256 green:136.0f/256 blue:51.0f/255 alpha:1.0]];
    else
        [[UITabBar appearance] setSelectedImageTintColor:[UIColor colorWithRed:238.0f/256 green:136.0f/256 blue:51.0f/255 alpha:1.0]];

    [SeafGlobal.sharedObject loadAccounts];

    _startNav = (UINavigationController *)self.window.rootViewController;
    _startVC = (StartViewController *)_startNav.topViewController;

    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"avatars"]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"certs"]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"objects"]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"blocks"]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"edit"]];
    [Utils checkMakeDir:[SeafGlobal.sharedObject applicationTempDirectory]];

    if (ios8) {
        [[UIApplication sharedApplication] registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge) categories:nil]];
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    } else
        [[UIApplication sharedApplication] registerForRemoteNotificationTypes:UIRemoteNotificationTypeBadge|UIRemoteNotificationTypeAlert|UIRemoteNotificationTypeSound];

    NSDictionary *dict = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (dict) {
        [self application:application didReceiveRemoteNotification:dict];
    } else
        [self.startVC selectDefaultAccount];
    [self performSelector:@selector(delayedInit) withObject:nil afterDelay:2.0];
    return YES;
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

- (void)checkIconBadgeNumber
{
    int badge = 0;
    for (SeafConnection *conn in [[SeafGlobal sharedObject] conns]) {
        badge += conn.newmsgnum;
    }
    [UIApplication sharedApplication].applicationIconBadgeNumber = badge;
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
            connection.newmsgnum = [badgeStr intValue];
            self.window.rootViewController = self.startNav;
            [self.window makeKeyAndVisible];
            [self.startVC selectAccount:connection];
        }
    }
    [self checkIconBadgeNumber];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    if ([[SeafGlobal sharedObject] uploadingnum] == 0
        && [[SeafGlobal sharedObject] downloadingnum] == 0)
    {
        if (UIBackgroundTaskInvalid != self.bgTask) {
            [application endBackgroundTask:self.bgTask];
            self.bgTask = UIBackgroundTaskInvalid;
        }
        return;
    }
    self.bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
        Debug(@"Time Remain = %f", [application backgroundTimeRemaining]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (UIBackgroundTaskInvalid != self.bgTask) {
                [application endBackgroundTask:self.bgTask];
                self.bgTask = UIBackgroundTaskInvalid;
            }
        });
    }];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    [application cancelAllLocalNotifications];
    if (UIBackgroundTaskInvalid != self.bgTask) {
        [application endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Saves changes in the application's managed object context before the application terminates.
    [[SeafGlobal sharedObject] saveContext];
}


- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController
{
    if (IsIpad() && [self.viewControllers indexOfObject:viewController] == TABBED_ACCOUNTS) {
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
    UIViewController *discussionController = [tabs.viewControllers objectAtIndex:TABBED_DISCUSSION];
    UIViewController *accountvc = [tabs.viewControllers objectAtIndex:TABBED_ACCOUNTS];

    fileController.tabBarItem.title = NSLocalizedString(@"Libraries", @"Seafile");
    fileController.tabBarItem.image = [UIImage imageNamed:@"tab-home.png"];
    starredController.tabBarItem.title = NSLocalizedString(@"Starred", @"Seafile");
    starredController.tabBarItem.image = [UIImage imageNamed:@"tab-star.png"];
    settingsController.tabBarItem.title = NSLocalizedString(@"Settings", @"Seafile");
    settingsController.tabBarItem.image = [UIImage imageNamed:@"tab-settings.png"];
    activityController.tabBarItem.title = NSLocalizedString(@"Activity", @"Seafile");
    activityController.tabBarItem.image = [UIImage imageNamed:@"tab-modify.png"];
    discussionController.tabBarItem.title = NSLocalizedString(@"Message", @"Seafile");
    discussionController.tabBarItem.image = [UIImage imageNamed:@"tab-message.png"];
    accountvc.tabBarItem.title = NSLocalizedString(@"Accounts", @"Seafile");
    accountvc.tabBarItem.image = [UIImage imageNamed:@"tab-account.png"];

    if (IsIpad()) {
        ((UISplitViewController *)fileController).delegate = (id)[[((UISplitViewController *)fileController).viewControllers lastObject] topViewController];
        ((UISplitViewController *)starredController).delegate = (id)[[((UISplitViewController *)starredController).viewControllers lastObject] topViewController];
        ((UISplitViewController *)settingsController).delegate = (id)[[((UISplitViewController *)settingsController).viewControllers lastObject] topViewController];
        ((UISplitViewController *)discussionController).delegate = (id)[[((UISplitViewController *)discussionController).viewControllers lastObject] topViewController];
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
        if (!_disDetailVC)
            _disDetailVC = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"DISDETAILVC"];
        Debug("index=%d %d, %@, %@", index, TABBED_DISCUSSION, _disDetailVC, _detailVC);
        return (index == TABBED_DISCUSSION) ? (UIViewController *)_disDetailVC : _detailVC;
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

- (SeafDisMasterViewController *)discussVC
{
    return (SeafDisMasterViewController *)[[[self masterNavController:TABBED_DISCUSSION] viewControllers] objectAtIndex:0];
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

- (SeafDisDetailViewController *)msgDetailView;
{
    if (!IsIpad()) {
        _disDetailVC = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"DISDETAILVC"];
        _disDetailVC.connection = SeafGlobal.sharedObject.connection;;
        return _disDetailVC;
    } else {
        return (SeafDisDetailViewController *)[self detailViewControllerAtIndex:TABBED_DISCUSSION];
    }
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
    [self.tabbarController setSelectedIndex:TABBED_ACCOUNTS];
    [self.startVC performSelector:@selector(selectAccount:) withObject:connection afterDelay:0.5f];
}

- (UIViewController *)rootViewController
{
    return self.window.rootViewController;
}

@end
