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
#import <Bugly/Bugly.h>

@interface SeafAppDelegate () <UITabBarControllerDelegate, PHPhotoLibraryChangeObserver, CLLocationManagerDelegate, WXApiDelegate>

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

- (BOOL)shouldContinue
{
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        if (conn.inAutoSync) return true;
    }
    NSInteger totalDownloadingNum = 0;
    NSInteger totalUploadingNum = 0;
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        SeafAccountTaskQueue *accountQueue =[SeafDataTaskManager.sharedObject accountQueueForConnection:conn];
        totalUploadingNum += accountQueue.fileQueue.taskNumber + accountQueue.uploadQueue.taskNumber;
    }
    return totalUploadingNum != 0 || totalDownloadingNum != 0;
}

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
#if !(TARGET_IPHONE_SIMULATOR)
    if (self.deviceToken)
        [conn registerDevice:self.deviceToken];
#endif
    return updated;
}

- (void)enterAccount:(SeafConnection *)conn
{
    BOOL updated = [self selectAccount:conn];
    if (self.window.rootViewController == self.tabbarController)
        return;

    Debug("isActivityEnabled:%d tabbarController: %ld", conn.isActivityEnabled, (long)self.tabbarController.viewControllers.count);
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
        [SeafDataTaskManager.sharedObject startLastTimeUnfinshTaskWithConnection:conn];
        [self.tabbarController setSelectedIndex:TABBED_SEAFILE];
    }
    self.window.rootViewController = self.tabbarController;
    [self.window makeKeyAndVisible];
    
}

- (void)exitAccount
{
    self.window.rootViewController = _startNav;
    [self.window makeKeyAndVisible];
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

- (void)uploadFile:(NSString *)path
{
    [[self masterNavController:TABBED_SEAFILE] popToRootViewControllerAnimated:NO];
    SeafUploadFile *file = [[SeafUploadFile alloc] initWithPath:path];
    [self.fileVC uploadFile:file];
}

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

    BOOL registeredChangeObserver = false;
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        [conn checkAutoSync];
        if (conn.inAutoSync && !registeredChangeObserver) {
            [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
            registeredChangeObserver = true;
        }
    }

    [self checkBackgroundUploadStatus];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    Info("%@", [[NSBundle mainBundle] infoDictionary]);
    _global = [SeafGlobal sharedObject];
    [_global migrate];
    [self initTabController];
    [[UITabBar appearance] setTintColor:[UIColor colorWithRed:101.0/255.0 green:191.0/255.0 blue:42.0/255.0 alpha:1.0]];
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
        } else {
            //not work in iOS 13, and while call in app  become active next time
            [weakSelf startBackgroundTask];
        }
    };

    [SVProgressHUD setBackgroundColor:[UIColor colorWithRed:250.0/256 green:250.0/256 blue:250.0/256 alpha:1.0]];

    [self performSelectorInBackground:@selector(delayedInit) withObject:nil];

    [UIApplication sharedApplication].delegate.window.backgroundColor = [UIColor whiteColor];
    [SeafWechatHelper registerWechat];
    [Bugly startWithAppId:@"67d77f8636"];
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
    UIApplication* app = [UIApplication sharedApplication];
    if (UIBackgroundTaskInvalid != self.bgTask) {
        [app endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
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
    for (id <SeafBackgroundMonitor> monitor in _monitors) {
        [monitor enterBackground];
    }
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
        NSNotification *note = [NSNotification notificationWithName:@"photosDidChange" object:nil userInfo:@{@"force" : @(YES)}];
        [self photosDidChange:note];
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

- (void)outOfQuota:(SeafConnection *)connection
{
    Warning("Out of quota.");
    [Utils alertWithTitle:NSLocalizedString(@"Out of quota", @"Seafile") message:nil handler:nil from:self.window.rootViewController];
}

#pragma mark - PHPhotoLibraryChangeObserver
- (void)photoLibraryDidChange:(PHChange *)changeInstance
{
    Debug("Photos library changed.");
    // Call might come on any background queue. Re-dispatch to the main queue to handle it.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self photosDidChange:nil];
    });
}

- (void)addBackgroundMonitor:(id<SeafBackgroundMonitor>)monitor
{
    [_monitors addObject:monitor];
}

#pragma mark - CLLocationManagerDelegate
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    Debug("Location updated: %@", locations);
    [self photosDidChange:nil];
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

# pragma mark- wechat callback
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

- (UIViewController *)topViewController {
    UIViewController *rootVC = [self.window rootViewController];
    UIViewController *topVC = [self findTopViewController:rootVC];
    while (topVC.presentedViewController) {
        topVC = [self findTopViewController:topVC.presentedViewController];
    }
    return topVC;
}

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
