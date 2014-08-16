//
//  SeafAppDelegate.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//


#import "SeafAppDelegate.h"
#import "AFNetworking.h"
#import "Debug.h"
#import "Utils.h"


@interface SeafAppDelegate () <UITabBarControllerDelegate>
@property (retain) NSMutableArray *ufiles;
@property (retain) NSMutableArray *dfiles;

@property UIBackgroundTaskIdentifier bgTask;
@property int downloadnum;
@property int uploadnum;
@property int failedNum;

@property NSInteger moduleIdx;
@property (readonly) SeafDetailViewController *detailVC;
@property (readonly) SeafDisDetailViewController *disDetailVC;
@property (strong) NSArray *viewControllers;
@property (readwrite, strong) NSString *token;

@end

@implementation SeafAppDelegate

@synthesize managedObjectContext = __managedObjectContext;
@synthesize managedObjectModel = __managedObjectModel;
@synthesize persistentStoreCoordinator = __persistentStoreCoordinator;
@synthesize startNav = _startNav;
@synthesize startVC = _startVC;
@synthesize detailVC = _detailVC;
@synthesize disDetailVC = _disDetailVC;
@synthesize tabbarController = _tabbarController;

@synthesize connection = _connection;



- (SeafConnection *)connection
{
    return _connection;
}

- (void)setConnection:(SeafConnection *)conn
{
    @synchronized(self) {
        if (_connection != conn) {
            _connection = conn;
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
    Debug("self.devicetoken=%@", self.deviceToken);
    if (self.deviceToken)
        [conn registerDevice:self.deviceToken];
}

- (BOOL)application:(UIApplication*)application handleOpenURL:(NSURL*)url
{
    if (url != nil && [url isFileURL]) {
        NSURL *to = [NSURL fileURLWithPath:[[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"] stringByAppendingPathComponent:url.lastPathComponent ]];
        Debug("Copy %@, to %@, %@, %@\n", url, to, to.absoluteString, to.path);
        [Utils copyFile:url to:to];
        if (self.window.rootViewController == self.startNav)
            if (![self.startVC goToDefaultAccount])
                return NO;
        [[self masterNavController:TABBED_SEAFILE] popToRootViewControllerAnimated:NO];
        SeafUploadFile *file = [self.connection getUploadfile:to.path];
        [self.fileVC uploadFile:file];
    }
    return YES;
}

- (SeafConnection *)getConnection:(NSString *)url username:(NSString *)username
{
    SeafConnection *conn;
    if ([url hasSuffix:@"/"])
        url = [url substringToIndex:url.length-1];
    for (conn in self.conns) {
        if ([conn.address isEqual:url] && [conn.username isEqual:username])
            return conn;
    }
    return nil;
}

- (void)saveAccounts
{
    NSMutableArray *accounts = [[NSMutableArray alloc] init];
    for (SeafConnection *connection in self.conns) {
        NSMutableDictionary *account = [[NSMutableDictionary alloc] init];
        [account setObject:connection.address forKey:@"url"];
        [account setObject:connection.username forKey:@"username"];
        [accounts addObject:account];
    }
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:accounts forKey:@"ACCOUNTS"];
    [userDefaults synchronize];
};

- (void)loadAccounts
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSArray *accounts = [userDefaults objectForKey:@"ACCOUNTS"];
    for (NSDictionary *account in accounts) {
        SeafConnection *conn = [[SeafConnection alloc] initWithUrl:[account objectForKey:@"url"] username:[account objectForKey:@"username"]];
        if (conn.username)
            [self.conns addObject:conn];
    }
    [self saveAccounts];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDictionary objectForKey:@"CFBundleVersion"];
    Debug("Current app version is %@\n%@\n", version, infoDictionary);
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:version forKey:@"VERSION"];
    [userDefaults synchronize];
    [self initTabController];
    [[AFNetworkReachabilityManager sharedManager] startMonitoring];

    if (ios7)
        [[UITabBar appearance] setTintColor:[UIColor colorWithRed:238.0f/256 green:136.0f/256 blue:51.0f/255 alpha:1.0]];
    else
        [[UITabBar appearance] setSelectedImageTintColor:[UIColor colorWithRed:238.0f/256 green:136.0f/256 blue:51.0f/255 alpha:1.0]];

    self.ufiles = [[NSMutableArray alloc] init];
    self.dfiles = [[NSMutableArray alloc] init];
    self.conns = [[NSMutableArray alloc] init];
    [self loadAccounts];
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    _startNav = [[UINavigationController alloc] initWithRootViewController:self.startVC];

    self.window.rootViewController = _startNav;
    [self.window makeKeyAndVisible];

    [Utils checkMakeDir:[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"avatars"]];
    [Utils checkMakeDir:[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"certs"]];
    [Utils checkMakeDir:[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"objects"]];
    [Utils checkMakeDir:[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"blocks"]];
    [Utils checkMakeDir:[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"]];
    [Utils checkMakeDir:[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"edit"]];
    [Utils checkMakeDir:[Utils applicationTempDirectory]];
    [Utils clearAllFiles:[Utils applicationTempDirectory]];

    self.downloadnum = 0;
    self.uploadnum = 0;
    [Utils clearRepoPasswords];
    [[UIApplication sharedApplication] registerForRemoteNotificationTypes:UIRemoteNotificationTypeBadge|UIRemoteNotificationTypeAlert|UIRemoteNotificationTypeSound];

    NSDictionary *dict = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (dict) {
        [self application:application didReceiveRemoteNotification:dict];
    } else
        [self.startVC goToDefaultAccount];
    return YES;
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    Debug("token=%@, %ld\n", deviceToken, (unsigned long)deviceToken.length);
    _deviceToken = deviceToken;
    if (self.deviceToken)
        [self.connection registerDevice:self.deviceToken];
}
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    Debug("error=%@", error);
}

- (void)checkIconBadgeNumber
{
    int badge = 0;
    for (SeafConnection *conn in self.conns) {
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
            SeafConnection *connection = [self getConnection:server username:username];
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
    if (self.uploadnum == 0 && self.downloadnum == 0)
        return;
    self.bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
        Debug(@"Time Remain = %f", [application backgroundTimeRemaining]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (UIBackgroundTaskInvalid != self.bgTask) {
                [application endBackgroundTask:self.bgTask];
                self.bgTask = UIBackgroundTaskInvalid;
#if 0
                if (self.uploadnum != 0 || self.downloadnum != 0) {
                    UILocalNotification* alarm = [[UILocalNotification alloc] init];
                    if (alarm) {
                        alarm.fireDate = [NSDate dateWithTimeIntervalSinceNow:0];
                        alarm.timeZone = [NSTimeZone defaultTimeZone];
                        alarm.repeatInterval = 0;
                        alarm.alertBody = @"Time to wake up!";
                        [[UIApplication sharedApplication] presentLocalNotificationNow:alarm];
                    }
                }
#endif
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
    [self saveContext];
}

- (void)saveContext
{
    NSError *error = nil;
    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    if (managedObjectContext != nil) {
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
            // Replace this implementation with code to handle the error appropriately.
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        }
    }
}

#pragma mark - Core Data stack

// Returns the managed object context for the application.
// If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
- (NSManagedObjectContext *)managedObjectContext
{
    if (__managedObjectContext != nil) {
        return __managedObjectContext;
    }

    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        __managedObjectContext = [[NSManagedObjectContext alloc] init];
        [__managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
    return __managedObjectContext;
}

// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (__managedObjectModel != nil) {
        return __managedObjectModel;
    }
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"seafile" withExtension:@"momd"];
    __managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return __managedObjectModel;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (__persistentStoreCoordinator != nil) {
        return __persistentStoreCoordinator;
    }
    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"seafile_pro.sqlite"];

    NSError *error = nil;
    __persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    if (![__persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
        /*
         Replace this implementation with code to handle the error appropriately.

         abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

         Typical reasons for an error here include:
         * The persistent store is not accessible;
         * The schema for the persistent store is incompatible with current managed object model.
         Check the error message to determine what the actual problem was.


         If the persistent store is not accessible, there is typically something wrong with the file path. Often, a file URL is pointing into the application's resources directory instead of a writeable directory.

         If you encounter schema incompatibility errors during development, you can reduce their frequency by:
         * Simply deleting the existing store:
         [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil]

         * Performing automatic lightweight migration by passing the following dictionary as the options parameter:
         [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption, [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];

         Lightweight migration will only work for a limited set of schema changes; consult "Core Data Model Versioning and Data Migration Programming Guide" for details.

         */
        [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil];

        if (![__persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        }
    }

    return __persistentStoreCoordinator;
}

#pragma mark - Application's Documents directory
// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController
{
    if (IsIpad() && [self.viewControllers indexOfObject:viewController] == TABBED_ACCOUNTS) {
        self.window.rootViewController = self.startNav;
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

- (UIViewController *)detailViewController:(int)index
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
    return (SeafDisMasterViewController *)[[self masterNavController:TABBED_DISCUSSION] topViewController];
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

- (void)checkBackgroudTask:(UIApplication *)application
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    //Debug("%d upload, %d download\n", appdelegate.uploadnum, appdelegate.downloadnum);
    if (appdelegate.downloadnum != 0 || appdelegate.uploadnum != 0)
        return;
    if (UIBackgroundTaskInvalid != appdelegate.bgTask) {
        [application endBackgroundTask:appdelegate.bgTask];
        appdelegate.bgTask = UIBackgroundTaskInvalid;
    }
}

- (void)tryUpload
{
    Debug("tryUpload %ld %ld", (long)self.uploadnum, (long)self.ufiles.count);
    if (self.ufiles.count == 0) return;
    NSMutableArray *todo = [[NSMutableArray alloc] init];
    @synchronized (self) {
        NSMutableArray *arr = [self.ufiles mutableCopy];
        for (SeafUploadFile *file in arr) {
            if (self.uploadnum + todo.count + self.failedNum >= 3) break;
            [self.ufiles removeObject:file];
            if (!file.uploaded) {
                [todo addObject:file];
            }
        }
    }
    for (SeafUploadFile *file in todo) {
        if (file.udir) {
            [file doUpload];
        }
    }
}

- (void)tryDownload
{
    if (self.dfiles.count == 0) return;
    NSMutableArray *todo = [[NSMutableArray alloc] init];
    @synchronized (self) {
        NSMutableArray *arr = [self.dfiles mutableCopy];
        for (id<SeafDownloadDelegate> file in arr) {
            if (self.downloadnum + todo.count + self.failedNum >= 3) break;
            [self.dfiles removeObject:file];
            [todo addObject:file];
        }
    }
    for (id<SeafDownloadDelegate> file in todo) {
        [file download];
    }
}

+ (void)incDownloadnum
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    @synchronized (appdelegate) {
        appdelegate.downloadnum ++;
    }
}
+ (void)decDownloadnum
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    @synchronized (appdelegate) {
        appdelegate.downloadnum --;
    }
    [appdelegate checkBackgroudTask:[UIApplication sharedApplication]];
}

+ (void)incUploadnum
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    @synchronized (appdelegate) {
        appdelegate.uploadnum ++;
    }
    Debug("%d upload, %d download\n", appdelegate.uploadnum, appdelegate.downloadnum);
}

- (void)finishDownload:(id<SeafDownloadDelegate>) file result:(BOOL)result
{
    Debug("dowmload %d, result=%d, failcnt=%d", self.downloadnum, result, self.failedNum);
    @synchronized (self) {
        self.downloadnum --;
    }
    [self checkBackgroudTask:[UIApplication sharedApplication]];
    if (result) {
        self.failedNum = 0;
    } else {
        self.failedNum ++;
        [self.dfiles addObject:file];
        if (self.failedNum >= 3) {
            [self performSelector:@selector(tryDownload) withObject:nil afterDelay:10.0];
            self.failedNum = 2;
            return;
        }
    }
    [self performSelector:@selector(tryDownload) withObject:nil afterDelay:0.1];
}

- (void)finishUpload:(SeafUploadFile *)file result:(BOOL)result
{
    Debug("upload %d, result=%d, udir=%@", self.uploadnum, result, file.udir);
    @synchronized (self) {
        self.uploadnum --;
    }
    [self checkBackgroudTask:[UIApplication sharedApplication]];
    if (result) {
        self.failedNum = 0;
    } else {
        self.failedNum ++;
        [self.ufiles addObject:file];
        if (self.failedNum >= 3) {
            [self performSelector:@selector(tryUpload) withObject:nil afterDelay:10.0];
            self.failedNum = 2;
            return;
        }
    }
    [self performSelector:@selector(tryUpload) withObject:nil afterDelay:0.1];
}

+ (void)finishDownload:(id<SeafDownloadDelegate>) file result:(BOOL)result
{
    [(SeafAppDelegate *)[[UIApplication sharedApplication] delegate] finishDownload:file result:result];
}

+ (void)finishUpload:(SeafUploadFile *) file result:(BOOL)result
{
    [(SeafAppDelegate *)[[UIApplication sharedApplication] delegate] finishUpload:file result:result];
}

+ (void)backgroundUpload:(SeafUploadFile *)file
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    @synchronized (appdelegate) {
        if (![appdelegate.ufiles containsObject:file])
            [appdelegate.ufiles addObject:file];
    }
    [appdelegate tryUpload];
}
+ (void)backgroundDownload:(id<SeafDownloadDelegate>)file
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    @synchronized (appdelegate) {
        if (![appdelegate.dfiles containsObject:file])
            [appdelegate.dfiles addObject:file];
    }
    [appdelegate tryDownload];
}

- (void)deleteAllObjects:(NSString *)entityDescription
{
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:entityDescription inManagedObjectContext:__managedObjectContext];
    [fetchRequest setEntity:entity];

    NSError *error;
    NSArray *items = [__managedObjectContext executeFetchRequest:fetchRequest error:&error];

    for (NSManagedObject *managedObject in items) {
        [__managedObjectContext deleteObject:managedObject];
        Debug(@"%@ object deleted",entityDescription);
    }
    if (![__managedObjectContext save:&error]) {
        Debug(@"Error deleting %@ - error:%@",entityDescription,error);
    }
}

- (void)showDetailView:(UIViewController *) c
{
    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:c];
    [nc setModalPresentationStyle:UIModalPresentationFullScreen];
    nc.navigationBar.tintColor = BAR_COLOR;
    [self.window.rootViewController presentViewController:nc animated:YES completion:nil];
}

@end
