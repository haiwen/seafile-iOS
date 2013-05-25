//
//  SeafAppDelegate.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "Debug.h"
#import "Utils.h"

enum {
    TABBED_SEAFILE = 0,
    TABBED_UPLOADS,
    TABBED_STARRED,
    TABBED_SETTINGS,
};

@interface SeafAppDelegate ()
@property (readonly) UINavigationController *activityNavController;

@property UIBackgroundTaskIdentifier bgTask;
@property int downloadnum;
@property int uploadnum;
@property NSInteger moduleIdx;

@end

@implementation SeafAppDelegate

@synthesize window = _window;
@synthesize managedObjectContext = __managedObjectContext;
@synthesize managedObjectModel = __managedObjectModel;
@synthesize persistentStoreCoordinator = __persistentStoreCoordinator;
@synthesize startNav = _startNav;
@synthesize startVC = _startVC;
@synthesize splitVC = _splitVC;
@synthesize detailVC = _detailVC;
@synthesize masterNavController = _masterNacController;
@synthesize tabbarController = _tabbarController;
@synthesize toolItems1 = _toolItems1;

@synthesize actvityVC = _actvityVC;
@synthesize activityNavController = _activityNavController;
@synthesize discussVC = _discussVC;
@synthesize dismasterVC = _dismasterVC;
@synthesize disdetailVC = _disdetailVC;
@synthesize switchItem;

@synthesize bgTask;
@synthesize downloadnum;
@synthesize uploadnum;
@synthesize moduleIdx;


- (void)reachabilityChanged:(NSNotification* )note
{
    Reachability* curReach = [note object];
    NSParameterAssert([curReach isKindOfClass:[Reachability class]]);
}

- (BOOL)application:(UIApplication*)application handleOpenURL:(NSURL*)url
{
    if (url != nil && [url isFileURL]) {
        NSURL *to = [NSURL fileURLWithPath:[[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"] stringByAppendingPathComponent:url.lastPathComponent ]];
        Debug("Copy %@, to %@\n", url, to);
        [Utils copyFile:url to:to];
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

// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

#pragma mark - ViewController
- (void)initToolItems:(UIViewController *)rootViewController
{
    int i;
    UIBarButtonItem *flexibleFpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:rootViewController action:@selector(editOperation:)];
    UIBarButtonItem *fixedSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:rootViewController action:@selector(editOperation:)];

    NSArray *itemsTitles = [NSArray arrayWithObjects:@"New Folder", @"New File", @"Copy", @"Move", @"Delete", @"Paste", @"MoveTo", @"Cancel", nil ];

    UIBarButtonItem *items[EDITOP_NUM];
    items[0] = flexibleFpaceItem;

    fixedSpaceItem.width = 38.0f;;
    for (i = 1; i < itemsTitles.count + 1; ++i) {
        items[i] = [[UIBarButtonItem alloc] initWithTitle:[itemsTitles objectAtIndex:i-1] style:UIBarButtonItemStyleBordered target:rootViewController action:@selector(editOperation:)];
        items[i].tag = i;
    }

    _toolItems1 = [NSArray arrayWithObjects:items[EDITOP_CREATE], items[EDITOP_MKDIR], items[EDITOP_SPACE], items[EDITOP_DELETE], nil ];
}

- (void)initTabController
{
    if (IsIpad()) {
        _tabbarController = [self.splitVC.viewControllers objectAtIndex:0];
    } else {
        _tabbarController = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"TABVC"];
    }
    UINavigationController *masterNavigationController = [self.tabbarController.viewControllers objectAtIndex:TABBED_SEAFILE];
    UINavigationController *uploadNavigationController = [self.tabbarController.viewControllers objectAtIndex:TABBED_UPLOADS];
    UINavigationController *starredNavigationController = [self.tabbarController.viewControllers objectAtIndex:TABBED_STARRED];
    UINavigationController *settingsNavigationController = [self.tabbarController.viewControllers objectAtIndex:TABBED_SETTINGS];

    SeafFileViewController *rootViewController = (SeafFileViewController *)[masterNavigationController topViewController];
    SeafUploadsViewController *uploadViewController = (SeafUploadsViewController *)[uploadNavigationController topViewController];
    SeafStarredFilesViewController *starredViewController = (SeafStarredFilesViewController *)[starredNavigationController topViewController];
    SeafSettingsViewController *settingsViewController = (SeafSettingsViewController *)[settingsNavigationController topViewController];
    [rootViewController initTabBarItem];
    [uploadViewController initTabBarItem];
    [starredViewController initTabBarItem];
    [settingsViewController initTabBarItem];

    [self initToolItems:rootViewController];
}

- (UISplitViewController *)splitVC
{
    if (_splitVC)
        return _splitVC;

    _splitVC = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"SPLITVC"];

    UINavigationController *detailNavigationController = [_splitVC.viewControllers lastObject];
    _splitVC.delegate = (id)detailNavigationController.topViewController;

    [self initTabController];

    return _splitVC;
}

- (UITabBarController *)tabbarController
{
    if (_tabbarController)
        return _tabbarController;

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

- (SeafFileViewController *)masterVC
{
    return (SeafFileViewController *)self.masterNavController.topViewController;
}

- (UINavigationController *)masterNavController
{
    return [self.tabbarController.viewControllers objectAtIndex:TABBED_SEAFILE];
}

- (SeafDetailViewController *)detailVC
{
    if (_detailVC)
        return _detailVC;
    if (IsIpad())
        _detailVC = (SeafDetailViewController *)[[[self.splitVC.viewControllers lastObject] viewControllers] objectAtIndex:0];
    else {
        _detailVC = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
    }
    return _detailVC;
}

- (SeafUploadsViewController *)uploadVC
{
    UINavigationController *uploadNavigationController = [self.tabbarController.viewControllers objectAtIndex:TABBED_UPLOADS];
    return (SeafUploadsViewController *)[uploadNavigationController.viewControllers objectAtIndex:0];
}
- (SeafStarredFilesViewController *)starredVC
{
    UINavigationController *uploadNavigationController = [self.tabbarController.viewControllers objectAtIndex:TABBED_STARRED];
    return (SeafStarredFilesViewController *)[uploadNavigationController.viewControllers objectAtIndex:0];
}

- (SeafSettingsViewController *)settingVC
{
    UINavigationController *settingsNavigationController = [self.tabbarController.viewControllers objectAtIndex:TABBED_SETTINGS];
    return (SeafSettingsViewController *)[settingsNavigationController.viewControllers objectAtIndex:0];
}

- (SeafActivityViewController *)actvityVC
{
    if (!_actvityVC)
        _actvityVC = [[SeafActivityViewController alloc] init];
    return _actvityVC;
}
- (UINavigationController *)activityNavController
{
    if (!_activityNavController)
        _activityNavController = [[UINavigationController alloc] initWithRootViewController:self.actvityVC];
    return _activityNavController;
}

- (UIViewController *)discussVC
{
    if (!_discussVC) {
        if (IsIpad()) {
            UISplitViewController *split = [[UIStoryboard storyboardWithName:@"DisStoryboard_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"SPLITVC"];
            UINavigationController *detailNavigationController = [split.viewControllers lastObject];
            split.delegate = (id)detailNavigationController.topViewController;
            _dismasterVC = [[[split.viewControllers objectAtIndex:0] viewControllers] objectAtIndex:0];
            _disdetailVC = [[[split.viewControllers lastObject] viewControllers] objectAtIndex:0];
            _discussVC = split;
        } else {
            _discussVC = [[UIStoryboard storyboardWithName:@"DisStoryboard_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERNAV"];
            _dismasterVC = [((UINavigationController *)_discussVC).viewControllers objectAtIndex:0];
            _disdetailVC = [[UIStoryboard storyboardWithName:@"DisStoryboard_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
        }
    }
    return _discussVC;
}

- (BOOL)checkNetworkStatus
{
    NetworkStatus netStatus3G = [internetReach currentReachabilityStatus];
    BOOL connectionRequired3G = [internetReach connectionRequired];

    NetworkStatus netStatusWifi = [internetReach currentReachabilityStatus];
    BOOL connectionRequiredWifi = [internetReach connectionRequired];

    if ((netStatus3G == NotReachable || connectionRequired3G)
        && (netStatusWifi == NotReachable || connectionRequiredWifi)) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"NetWork unavailable"
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
    Debug("%d upload, %d download\n", appdelegate.uploadnum, appdelegate.downloadnum);
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
        appdelegate.uploadnum ++;
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


#pragma mark - UIActionSheetDelegate
- (void)switchModule
{
    if (moduleIdx == 0) {
        if (self.window.rootViewController == self.startNav) return;
        [self.detailVC setPreViewItem:nil];
        self.window.rootViewController = self.startNav;
    } else if (moduleIdx == 1) {
        if (IsIpad()) {
            if (self.window.rootViewController == self.splitVC) return;
            self.window.rootViewController = self.splitVC;
        } else {
            if (self.window.rootViewController == self.tabbarController) return;
            self.window.rootViewController = self.tabbarController;
        }
    } else if (moduleIdx == 2) {
        self.window.rootViewController = self.activityNavController;
        self.actvityVC.connection = self.uploadVC.connection;
    } else if (moduleIdx == 3) {
        self.window.rootViewController = self.discussVC;
        self.dismasterVC.connection = self.uploadVC.connection;
    }
    [self.window makeKeyAndVisible];
}
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    Debug("index=%d\n", buttonIndex);
    moduleIdx = buttonIndex;
    [self performSelector:@selector(switchModule) withObject:nil afterDelay:0];
}
- (void)switchModuleHandler:(id)sender
{
    UIActionSheet *actionSheet;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (IsIpad())
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:appdelegate cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:@"Accounts", @"Files", @"Activities", @"Discussion", nil ];
    else
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:appdelegate cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Accounts", @"Files", @"Activities", @"Discussion", nil ];
    [actionSheet showFromBarButtonItem:sender animated:YES];
}

- (UIBarButtonItem *)switchItem
{
    return [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemOrganize target:self action:@selector(switchModuleHandler:)];
}
@end
