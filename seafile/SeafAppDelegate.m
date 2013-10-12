//
//  SeafAppDelegate.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafEmptyViewController.h"
#import "Debug.h"
#import "Utils.h"

#import "M13InfiniteTabBarController.h"
#import "M13InfiniteTabBarItem.h"

@interface SeafAppDelegate () <M13InfiniteTabBarControllerDelegate, UITabBarControllerDelegate>

@property UIBackgroundTaskIdentifier bgTask;
@property int downloadnum;
@property int uploadnum;
@property NSInteger moduleIdx;
@property (readonly) SeafDetailViewController *detailVC;
@property (readonly) SeafDisDetailViewController *disDetailVC;

@end

@implementation SeafAppDelegate

@synthesize window = _window;
@synthesize managedObjectContext = __managedObjectContext;
@synthesize managedObjectModel = __managedObjectModel;
@synthesize persistentStoreCoordinator = __persistentStoreCoordinator;
@synthesize startNav = _startNav;
@synthesize startVC = _startVC;
@synthesize detailVC = _detailVC;
@synthesize disDetailVC = _disDetailVC;
@synthesize tabbarController = _tabbarController;

@synthesize actvityVC;
@synthesize discussVC;
@synthesize connection = _connection;

@synthesize bgTask;
@synthesize downloadnum;
@synthesize uploadnum;
@synthesize moduleIdx;


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
}

- (void)reachabilityChanged:(NSNotification* )note
{
    Reachability* curReach = [note object];
    NSParameterAssert([curReach isKindOfClass:[Reachability class]]);
}

- (BOOL)application:(UIApplication*)application handleOpenURL:(NSURL*)url
{
    if (url != nil && [url isFileURL]) {
        NSURL *to = [NSURL fileURLWithPath:[[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"] stringByAppendingPathComponent:url.lastPathComponent ]];
        Debug("Copy %@, to %@, %@, %@\n", url, to, to.absoluteString, to.path);
        [Utils copyFile:url to:to];
        if (self.window.rootViewController == self.startNav)
            if (![self.startVC goToDefaultReposView])
                return NO;
        [[self masterNavController:TABBED_SEAFILE] popToRootViewControllerAnimated:NO];
        SeafUploadFile *file = [self.connection getUploadfile:to.path];
        [self.fileVC uploadFile:file];
    }
    return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDictionary objectForKey:@"CFBundleVersion"];
    Debug("Current app version is %@\n", version);
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:version forKey:@"VERSION"];
    [userDefaults synchronize];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    _startNav = [[UINavigationController alloc] initWithRootViewController:self.startVC];

    self.window.rootViewController = _startNav;
    [self.window makeKeyAndVisible];

    [Utils checkMakeDir:[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"objects"]];
    [Utils checkMakeDir:[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"blocks"]];
    [Utils checkMakeDir:[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"]];
     [Utils checkMakeDir:[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"edit"]];
    [Utils checkMakeDir:[Utils applicationTempDirectory]];

    [Utils clearAllFiles:[Utils applicationTempDirectory]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged:) name:kReachabilityChangedNotification object:nil];

    internetReach = [Reachability reachabilityForInternetConnection];
    [internetReach startNotifier];
    wifiReach = [Reachability reachabilityForLocalWiFi];
    [wifiReach startNotifier];

    [self checkNetworkStatus];
    self.downloadnum = 0;
    self.uploadnum = 0;
    [Utils clearRepoPasswords];
    [self.startVC goToDefaultReposView];
    return YES;
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
- (BOOL)infiniteTabBarController:(M13InfiniteTabBarController *)tabBarController shouldSelectViewContoller:(UIViewController *)viewController
{
    if ([self.tabbarController.viewControllers indexOfObject:viewController] == TABBED_ACCOUNTS) {
        self.window.rootViewController = self.startNav;
        [self.window makeKeyAndVisible];
        return NO;
    }
    return YES;
}

- (void)infiniteTabBarController:(M13InfiniteTabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController
{
    Debug("idx=%d\n", [self.tabbarController.viewControllers indexOfObject:viewController]);
    //Do nothing
}

// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController
{
    if ([self.tabbarController.viewControllers indexOfObject:viewController] == TABBED_ACCOUNTS) {
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


    fileController.tabBarItem.title = @"Files";
    fileController.tabBarItem.image = [UIImage imageNamed:@"tab-home.png"];
    starredController.tabBarItem.title = @"Starred";
    starredController.tabBarItem.image = [UIImage imageNamed:@"tab-star.png"];
    settingsController.tabBarItem.title = @"Settings";
    settingsController.tabBarItem.image = [UIImage imageNamed:@"tab-settings.png"];
    activityController.tabBarItem.title = @"Activity";
    activityController.tabBarItem.image = [UIImage imageNamed:@"tab-activity.png"];
    discussionController.tabBarItem.title = @"Discussion";
    discussionController.tabBarItem.image = [UIImage imageNamed:@"tab-discussion.png"];

    UIViewController *accountvc = [[SeafEmptyViewController alloc] init];
    accountvc.tabBarItem.title = @"Accounts";
    accountvc.tabBarItem.image = [UIImage imageNamed:@"tab-account.png"];
    if (IsIpad()) {
        ((UISplitViewController *)fileController).delegate = (id)[[((UISplitViewController *)fileController).viewControllers lastObject] topViewController];
        ((UISplitViewController *)starredController).delegate = (id)[[((UISplitViewController *)starredController).viewControllers lastObject] topViewController];
        ((UISplitViewController *)settingsController).delegate = (id)[[((UISplitViewController *)settingsController).viewControllers lastObject] topViewController];
        ((UISplitViewController *)discussionController).delegate = (id)[[((UISplitViewController *)discussionController).viewControllers lastObject] topViewController];
        _tabbarController = [[UITabBarController alloc] init];
        _tabbarController.viewControllers = [tabs.viewControllers arrayByAddingObject:accountvc];
        _tabbarController.delegate = self;
    } else {
        NSMutableArray *items = [[NSMutableArray alloc] init];
        NSMutableArray *vcs = [NSMutableArray arrayWithArray:tabs.viewControllers];

        for (UIViewController *vc in tabs.viewControllers) {
            M13InfiniteTabBarItem *item = [[M13InfiniteTabBarItem alloc] initWithTitle:vc.tabBarItem.title andIcon:vc.tabBarItem.image];
                [items addObject:item];
        }

        [vcs addObject:accountvc];
        M13InfiniteTabBarItem *item = [[M13InfiniteTabBarItem alloc] initWithTitle:accountvc.tabBarItem.title andIcon:accountvc.tabBarItem.image];
        [items addObject:item];

        M13InfiniteTabBarController *viewController = [[M13InfiniteTabBarController alloc] initWithViewControllers:vcs pairedWithInfiniteTabBarItems:items];
        viewController.delegate = self;
        if([viewController respondsToSelector:@selector(edgesForExtendedLayout)])
            viewController.edgesForExtendedLayout = UIRectEdgeNone;
        _tabbarController = (UITabBarController *)viewController;
    }
}

- (UITabBarController *)tabbarController
{
    if (!_tabbarController)
        [self initTabController];
    return _tabbarController;
}

- (StartViewController *)startVC
{
    if (_startVC)
        return _startVC;
    _startVC = [[StartViewController alloc] init];
    return _startVC;
}

- (UINavigationController *)masterNavController:(int)index
{
    if (!IsIpad())
        return [self.tabbarController.viewControllers objectAtIndex:index];
    else {
        if (index == TABBED_ACTIVITY)
            return [self.tabbarController.viewControllers objectAtIndex:index];
        return [[[self.tabbarController.viewControllers objectAtIndex:index] viewControllers] objectAtIndex:0];
    }
}

- (SeafFileViewController *)fileVC
{
    return (SeafFileViewController *)[[self masterNavController:TABBED_SEAFILE] topViewController];
}

- (UIViewController *)detailViewController:(int)index
{
    if (IsIpad()) {
        return [[[[self.tabbarController.viewControllers objectAtIndex:index] viewControllers] lastObject] topViewController];
    } else {
        if (!_detailVC)
            _detailVC = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
        if (!_disDetailVC)
            _disDetailVC = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"DISDETAILVC"];
        if (index == TABBED_DISCUSSION)
            return (UIViewController *)_disDetailVC;
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
    return (SeafActivityViewController *)[[self.tabbarController.viewControllers objectAtIndex:TABBED_ACTIVITY] topViewController];
}

- (SeafDisMasterViewController *)discussVC
{
    return (SeafDisMasterViewController *)[[self masterNavController:TABBED_DISCUSSION] topViewController];
}

- (BOOL)checkNetworkStatus
{
    NetworkStatus netStatus3G = [internetReach currentReachabilityStatus];
    BOOL connectionRequired3G = [internetReach connectionRequired];

    NetworkStatus netStatusWifi = [internetReach currentReachabilityStatus];
    BOOL connectionRequiredWifi = [internetReach connectionRequired];

    if ((netStatus3G == NotReachable || connectionRequired3G)
        && (netStatusWifi == NotReachable || connectionRequiredWifi)) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Network unavailable"
                                                        message:nil
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
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

+ (void)incDownloadnum
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    @synchronized (appdelegate) {
        appdelegate.downloadnum ++;
    }
    Debug("%d upload, %d download\n", appdelegate.uploadnum, appdelegate.downloadnum);
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

+ (void)decUploadnum
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    @synchronized (appdelegate) {
        appdelegate.uploadnum --;
    }
    [appdelegate checkBackgroudTask:[UIApplication sharedApplication]];
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
    [self.window.rootViewController presentViewController:nc animated:NO completion:nil];
}

@end
