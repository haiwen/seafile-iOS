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

@implementation SeafAppDelegate

@synthesize window = _window;
@synthesize managedObjectContext = __managedObjectContext;
@synthesize managedObjectModel = __managedObjectModel;
@synthesize persistentStoreCoordinator = __persistentStoreCoordinator;
@synthesize startVC = _startVC;
@synthesize splitVC = _splitVC;
@synthesize detailVC = _detailVC;
@synthesize masterNavController = _masterNacController;
@synthesize tabbarController = _tabbarController;
@synthesize toolItems1 = _toolItems1, toolItems2 = _toolItems2, toolItems3 = _toolItems3;


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
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = self.startVC;
    [self.window makeKeyAndVisible];

    [Utils checkMakeDir:[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"objects"]];
    [Utils checkMakeDir:[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"]];

    self.conns = [[NSMutableDictionary alloc] init ];
    [Utils clearAllFiles:NSTemporaryDirectory()];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged:) name:kReachabilityChangedNotification object:nil];

    internetReach = [Reachability reachabilityForInternetConnection];
    [internetReach startNotifier];
    wifiReach = [Reachability reachabilityForLocalWiFi];
    [wifiReach startNotifier];

    [self checkNetworkStatus];
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDictionary objectForKey:@"CFBundleVersion"];
    Debug("Current app version is %@\n", version);
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:version forKey:@"VERSION"];
    [userDefaults synchronize];

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
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
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

    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"seafile.sqlite"];

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
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
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
    fixedSpaceItem.width = 10.0f;

    NSArray *itemsTitles = [NSArray arrayWithObjects:@"New Folder", @"Copy", @"Move", @"Delete", @"Paste", @"MoveTo", @"Cancel", nil ];

    UIBarButtonItem *items[EDITOP_NUM];
    items[0] = flexibleFpaceItem;
    for (i = 1; i < itemsTitles.count + 1; ++i) {
        items[i] = [[UIBarButtonItem alloc] initWithTitle:[itemsTitles objectAtIndex:i-1] style:UIBarButtonItemStyleBordered target:rootViewController action:@selector(editOperation:)];
        items[i].tag = i;
    }

    //_toolItems1 = [NSArray arrayWithObjects:items[1], items[0], items[2], items[0], items[3], fixedSpaceItem, items[4], nil ];
    _toolItems1 = [NSArray arrayWithObjects:items[1], items[0], items[4], nil ];
    _toolItems2 = [NSArray arrayWithObjects:items[5], items[0], items[7], nil ];
    _toolItems3 = [NSArray arrayWithObjects:items[6], items[0], items[7], nil ];

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
        _detailVC = (SeafDetailViewController *)[[[self.splitVC.viewControllers lastObject] viewControllers] objectAtIndex:TABBED_SEAFILE];
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

- (void)saveConnection:(SeafConnection *)conn
{
    [[self conns] setObject:conn forKey:conn.address];
}

- (SeafConnection *)getConnection:(NSString *)url
{
    SeafConnection *connection = [self.conns objectForKey:url];
    if (!connection) {
        connection = [[SeafConnection alloc] initWithUrl:url];
        [self saveConnection:connection];
    }
    return connection;
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

@end
