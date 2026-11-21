#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// App-hosted, offline regressions. Exercise the real storyboard/controllers
// without adding test accounts or launch-time fixtures to the shipping app.
@interface NSObject (LayoutTestAppAPI)
- (void)initTabController;
- (UINavigationController *)masterNavController:(int)index;
- (UIViewController *)detailViewControllerAtIndex:(int)index;
- (void)setPreViewItem:(id)item master:(UIViewController *)master;
- (void)setupToolbar;
+ (id)actionSheetWithTitles:(NSArray *)titles;
- (void)showFromView:(id)source;
- (void)dismissAnimated:(BOOL)animated;
- (instancetype)initWithConnection:(id)connection;
- (instancetype)initWithConnection:(id)connection andRepoId:(NSString *)repoId andRepoName:(NSString *)name;
- (instancetype)initWithConnection:(id)connection oid:(NSString *)oid repoId:(NSString *)repoId
                              name:(NSString *)name path:(NSString *)path mtime:(long long)mtime size:(unsigned long long)size;
- (instancetype)initWithConnection:(id)connection oid:(NSString *)oid repoId:(NSString *)repoId
                              perm:(NSString *)perm name:(NSString *)name path:(NSString *)path mime:(NSString *)mime;
- (void)applyViewMode;
- (void)searchAction:(id)sender;
- (void)customSearchDismissAction:(UIButton *)sender;
- (void)searchCancelled:(NSNotification *)notification;
- (void)didDismissSearchController:(UISearchController *)searchController;
- (void)openSearchResultDirectory:(id)directory;
@end

// Runtime subclassing keeps the app-hosted fixture independent of the app's
// private header search paths. Only the test subclass bypasses network/task data;
// production SeafDir and the pushed SeafFileViewController remain unchanged.
static Class LayoutOfflineSearchDirectoryClass(void) {
    static Class fixtureClass;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class directoryClass = NSClassFromString(@"SeafDir");
        NSCAssert(directoryClass != Nil, @"The app must provide SeafDir");
        fixtureClass = objc_allocateClassPair(directoryClass, "LayoutOfflineSearchDirectory", 0);
        SEL load = NSSelectorFromString(@"loadContent:");
        class_addMethod(fixtureClass, load, imp_implementationWithBlock(^(id directory, BOOL force) {}),
                        method_getTypeEncoding(class_getInstanceMethod(directoryClass, load)));
        for (NSString *getter in @[@"allItems", @"items", @"uploadItems", @"uploadFiles"]) {
            SEL selector = NSSelectorFromString(getter);
            class_addMethod(fixtureClass, selector, imp_implementationWithBlock(^id(id directory) {
                return [NSMutableArray array];
            }), method_getTypeEncoding(class_getInstanceMethod(directoryClass, selector)));
        }
        SEL hasCache = NSSelectorFromString(@"hasCache");
        class_addMethod(fixtureClass, hasCache, imp_implementationWithBlock(^BOOL(id directory) { return YES; }),
                        method_getTypeEncoding(class_getInstanceMethod(directoryClass, hasCache)));
        objc_registerClassPair(fixtureClass);
    });
    return fixtureClass;
}

@interface LayoutPreviewItem : NSObject
@property (nonatomic, strong) NSURL *previewItemURL;
@end
@implementation LayoutPreviewItem
- (NSString *)previewItemTitle { return @"Layout fixture.txt"; }
- (NSString *)name { return self.previewItemTitle; }
- (NSString *)mime { return @"text/plain"; }
- (BOOL)editable { return NO; }
- (BOOL)hasCache { return YES; }
- (void)load:(id)delegate force:(BOOL)force {}
- (void)cancelAnyLoading {}
@end

@interface IPadLayoutTests : XCTestCase
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIViewController *originalRoot;
@property (nonatomic, strong) UIViewController *container;
@property (nonatomic, strong) UIViewController *content;
@end

@implementation IPadLayoutTests

- (void)setUp {
    [super setUp];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) self.window = window;
        }
    }
    XCTAssertNotNil(self.window);
    self.originalRoot = self.window.rootViewController;
    self.container = [UIViewController new];
    self.container.view.backgroundColor = UIColor.systemBackgroundColor;
    self.window.rootViewController = self.container;
    [self.window makeKeyAndVisible];
}

- (void)tearDown {
    [self.container dismissViewControllerAnimated:NO completion:nil];
    self.window.rootViewController = self.originalRoot;
    self.content = nil;
    self.container = nil;
    [super tearDown];
}

- (void)settle {
    [self.window layoutIfNeeded];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    [self.content.view layoutIfNeeded];
}

- (void)resize:(CGSize)size category:(UIContentSizeCategory)category {
    UITraitCollection *traits = [UITraitCollection traitCollectionWithTraitsFromCollections:@[
        [UITraitCollection traitCollectionWithHorizontalSizeClass:size.width < 600 ? UIUserInterfaceSizeClassCompact : UIUserInterfaceSizeClassRegular],
        [UITraitCollection traitCollectionWithPreferredContentSizeCategory:category]
    ]];
    [self.container setOverrideTraitCollection:traits forChildViewController:self.content];
    self.content.view.frame = (CGRect){CGPointZero, size};
    [self.content.view setNeedsLayout];
    [self settle];
}

- (void)mount:(UIViewController *)controller size:(CGSize)size category:(UIContentSizeCategory)category {
    self.content = controller;
    [self.container addChildViewController:controller];
    [self.container.view addSubview:controller.view];
    [controller didMoveToParentViewController:self.container];
    [self resize:size category:category];
}

- (UITabBarController *)appTabs {
    id app = UIApplication.sharedApplication.delegate;
    [app initTabController];
    return [app valueForKey:@"tabbarController"];
}

- (void)attach:(NSString *)name {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:self.content.view.bounds];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [self.content.view drawViewHierarchyInRect:self.content.view.bounds afterScreenUpdates:YES];
    }];
    XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
    attachment.name = name;
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
}

- (void)testSettingsSurvivePortraitAndCompactRoundTrip {
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) return;
    UITabBarController *tabs = [self appTabs];
    tabs.selectedIndex = 4;
    [self mount:tabs size:CGSizeMake(768, 1024) category:UIContentSizeCategoryLarge];
    UISplitViewController *split = (id)tabs.selectedViewController;
    id app = UIApplication.sharedApplication.delegate;
    UINavigationController *primary = [app masterNavController:4];
    UIViewController *detail = [app detailViewControllerAtIndex:4];
    XCTAssertEqual(split.style, UISplitViewControllerStyleDoubleColumn);
    XCTAssertNotEqual(split.displayMode, UISplitViewControllerDisplayModeSecondaryOnly);
    XCTAssertNotNil(primary.view.window, @"Portrait must show the settings list, not only the empty detail");
    for (UIView *view in detail.view.subviews) {
        if (![view isKindOfClass:UIImageView.class]) continue;
        CGRect safe = detail.view.safeAreaLayoutGuide.layoutFrame;
        XCTAssertEqualWithAccuracy(view.center.x, CGRectGetMidX(safe), 1, @"Placeholder must be centered in the visible detail, outside the floating sidebar");
    }
    [self attach:@"settings-portrait"];
    [self resize:CGSizeMake(390, 844) category:UIContentSizeCategoryLarge];
    XCTAssertTrue(split.isCollapsed);
    XCTAssertEqual([app masterNavController:4], primary);
    XCTAssertEqual([app detailViewControllerAtIndex:4], detail);
    XCTAssertEqual(primary.topViewController, primary.viewControllers.firstObject);
    XCTAssertNotNil(primary.topViewController.view.window);
    XCTAssertFalse(tabs.tabBar.hidden, @"Compact iPad must retain its bottom tabs");
    tabs.selectedIndex = 0;
    [self settle];
    XCTAssertNotNil([app masterNavController:0].view.window);
    tabs.selectedIndex = 4;
    [self settle];
    [self attach:@"settings-compact"];
    [self resize:CGSizeMake(1024, 768) category:UIContentSizeCategoryLarge];
    XCTAssertFalse(split.isCollapsed);
    XCTAssertNotNil(primary.view.window);
    XCTAssertEqual([app detailViewControllerAtIndex:4], detail);
    [self attach:@"settings-landscape-after-expand"];
}

- (void)testCompactDetailNavigationReturnsToPrimary {
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) return;
    UITabBarController *tabs = [self appTabs];
    [self mount:tabs size:CGSizeMake(390, 844) category:UIContentSizeCategoryLarge];
    UISplitViewController *split = (id)tabs.selectedViewController;
    id app = UIApplication.sharedApplication.delegate;
    UINavigationController *primary = [app masterNavController:0];
    UIViewController *detail = [app detailViewControllerAtIndex:0];
    LayoutPreviewItem *item = [LayoutPreviewItem new];
    item.previewItemURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"layout-fixture.txt"]];
    [@"Offline layout preview\nThe first line must remain below the navigation bar." writeToURL:item.previewItemURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [detail setPreViewItem:item master:primary.topViewController];
    [self settle];
    XCTAssertNotNil(detail.view.window);
    XCTAssertNotNil(detail.navigationController);
    UITextView *text = [detail valueForKey:@"textView"];
    XCTAssertGreaterThan(text.text.length, 0u);
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(text.frame), detail.view.safeAreaInsets.top);
    [self attach:@"compact-detail-back-navigation"];
    // A column-style split keeps the supplied navigation controllers intact
    // and owns the collapsed stack itself. Popping the detail's root nav is a no-op.
    [split hideColumn:UISplitViewControllerColumnSecondary];
    [self settle];
    XCTAssertNotNil(primary.topViewController.view.window);
    XCTAssertFalse(CGRectIntersectsRect([detail.view convertRect:detail.view.bounds toView:tabs.view], tabs.view.bounds)
                   && detail.view.window != nil, @"Returning must remove the detail from the visible compact column");
    XCTAssertEqual([app detailViewControllerAtIndex:0], detail);
    [self resize:CGSizeMake(1024, 768) category:UIContentSizeCategoryLarge];
    XCTAssertNotNil(detail.view.window);
    XCTAssertGreaterThanOrEqual(CGRectGetMinX(text.frame), detail.view.safeAreaInsets.left);
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(text.frame), detail.view.safeAreaInsets.top);
    [self attach:@"expanded-text-preview"];
    [NSFileManager.defaultManager removeItemAtURL:item.previewItemURL error:nil];
}

- (void)testLibrarySidebarDisclosureAndEmptyPreviewLayout {
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) return;
    UITabBarController *tabs = [self appTabs];
    [self mount:tabs size:CGSizeMake(1120, 820) category:UIContentSizeCategoryLarge];
    UISplitViewController *split = (id)tabs.selectedViewController;
    UINavigationController *primary = (id)[split viewControllerForColumn:UISplitViewControllerColumnPrimary];
    UINavigationController *secondary = (id)[split viewControllerForColumn:UISplitViewControllerColumnSecondary];
    UIViewController *files = primary.topViewController;
    UIViewController *detail = secondary.topViewController;

    id repos = [[NSClassFromString(@"SeafRepos") alloc] initWithConnection:nil];
    NSMutableArray *libraries = [NSMutableArray array];
    for (NSUInteger i = 0; i < 22; i++) {
        NSString *name = [NSString stringWithFormat:@"Sample library %lu", (unsigned long)i + 1];
        [libraries addObject:[[NSClassFromString(@"SeafRepo") alloc] initWithConnection:nil andRepoId:name andRepoName:name]];
    }
    [repos setValue:[NSMutableArray arrayWithObject:libraries] forKey:@"repoGroups"];
    [files setValue:repos forKey:@"_directory"];
    files.title = NSLocalizedString(@"Libraries", nil);
    [files applyViewMode];
    UITableView *table = [files valueForKey:@"tableView"];
    [table reloadData];
    [self settle];

    UITableViewHeaderFooterView *header = [table headerViewForSection:0];
    UIButton *disclosure = (id)header.contentView.subviews.firstObject;
    XCTAssertTrue([disclosure isKindOfClass:UIButton.class]);
    XCTAssertTrue(disclosure.isAccessibilityElement);
    XCTAssertGreaterThan(disclosure.accessibilityLabel.length, 0u);
    XCTAssertGreaterThanOrEqual(disclosure.bounds.size.height, 44);
    NSString *expanded = disclosure.accessibilityValue;
    XCTAssertGreaterThan(expanded.length, 0u);
    [disclosure sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    [self settle];
    XCTAssertEqual([table numberOfRowsInSection:0], 0);
    XCTAssertNotEqualObjects(disclosure.accessibilityValue, expanded);
    [disclosure sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    [self settle];
    XCTAssertEqual([table numberOfRowsInSection:0], libraries.count);
    XCTAssertEqualObjects(disclosure.accessibilityValue, expanded);

    if (@available(iOS 26.0, *)) {
        XCTAssertEqualObjects(table.topEdgeEffect.style, UIScrollEdgeEffectStyle.hardStyle);
    }
    [table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:10 inSection:0]
               atScrollPosition:UITableViewScrollPositionTop animated:NO];
    [self settle];
    XCTAssertNotNil([table headerViewForSection:0].window);
    [self attach:@"files-sidebar-after-scroll"];

    UIView *placeholder = [detail valueForKey:@"filePreviewPlaceholder"];
    XCTAssertNotNil(placeholder);
    XCTAssertFalse(placeholder.hidden);
    CGRect sidebarFrame = [primary.view convertRect:primary.view.bounds toView:split.view];
    CGRect detailSafeFrame = [detail.view convertRect:detail.view.safeAreaLayoutGuide.layoutFrame toView:split.view];
    CGRect placeholderFrame = [detail.view convertRect:placeholder.frame toView:split.view];
    XCTAssertGreaterThanOrEqual(CGRectGetMinX(placeholderFrame) + 1, CGRectGetMaxX(sidebarFrame));
    XCTAssertEqualWithAccuracy(CGRectGetMaxX(placeholderFrame), CGRectGetMaxX(detailSafeFrame), 1);

    [split hideColumn:UISplitViewControllerColumnPrimary];
    [self settle];
    XCTAssertEqual(split.displayMode, UISplitViewControllerDisplayModeSecondaryOnly);
    XCTAssertEqualWithAccuracy(CGRectGetMidX(placeholder.frame), CGRectGetMidX(detail.view.safeAreaLayoutGuide.layoutFrame), 1);

    [split showColumn:UISplitViewControllerColumnPrimary];
    [table setContentOffset:CGPointMake(0, -table.adjustedContentInset.top) animated:NO];
    [self settle];
    header = [table headerViewForSection:0];
    disclosure = (id)header.contentView.subviews.firstObject;
    UILabel *groupTitle = (id)disclosure.subviews.firstObject;
    XCTAssertEqualWithAccuracy(CGRectGetHeight(header.bounds), 45, 0.5);
    XCTAssertEqualObjects(groupTitle.font, [UIFont systemFontOfSize:15]);
    [self resize:CGSizeMake(1120, 820) category:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge];
    header = [table headerViewForSection:0];
    UIButton *resizedDisclosure = (id)header.contentView.subviews.firstObject;
    groupTitle = (id)resizedDisclosure.subviews.firstObject;
    XCTAssertEqualWithAccuracy(CGRectGetHeight(header.bounds), 45, 0.5);
    XCTAssertEqualObjects(groupTitle.font, [UIFont systemFontOfSize:15]);
    [repos setValue:[NSMutableArray arrayWithArray:@[libraries, @[]]] forKey:@"repoGroups"];
    [resizedDisclosure sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    [self settle];
    XCTAssertEqual(table.numberOfSections, 2);
    XCTAssertEqual([table numberOfRowsInSection:0], 0);
}

- (void)testFilesPreviewSelectionFollowsDetailInListAndGrid {
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) return;
    UITabBarController *tabs = [self appTabs];
    [self mount:tabs size:CGSizeMake(1120, 820) category:UIContentSizeCategoryLarge];
    id app = UIApplication.sharedApplication.delegate;
    UIViewController *files = [app masterNavController:0].topViewController;
    UIViewController *detail = [app detailViewControllerAtIndex:0];

    Class fileClass = NSClassFromString(@"SeafFile");
    id first = [[fileClass alloc] initWithConnection:nil oid:nil repoId:@"fixture" name:@"First.txt" path:@"/First.txt" mtime:0 size:0];
    id firstFromRefresh = [[fileClass alloc] initWithConnection:nil oid:nil repoId:@"fixture" name:@"First.txt" path:@"/First.txt" mtime:0 size:0];
    id second = [[fileClass alloc] initWithConnection:nil oid:nil repoId:@"fixture" name:@"Second.txt" path:@"/Second.txt" mtime:0 size:0];
    [files setValue:@[firstFromRefresh, second] forKey:@"allItems"];
    [files setValue:@NO forKey:@"gridModeEnabled"];
    [files applyViewMode];
    UITableView *table = [files valueForKey:@"tableView"];
    [table reloadData];
    [self settle];
    NSIndexPath *firstPath = [NSIndexPath indexPathForRow:0 inSection:0];
    NSIndexPath *secondPath = [NSIndexPath indexPathForRow:1 inSection:0];
    UITableViewCell *firstRow = [table cellForRowAtIndexPath:firstPath];
    UITableViewCell *secondRow = [table cellForRowAtIndexPath:secondPath];
    XCTAssertNotNil(firstRow);
    XCTAssertNotNil(secondRow);

    [detail setValue:first forKey:@"preViewItem"];
    XCTAssertEqualObjects([firstRow valueForKey:@"previewSelected"], @YES);
    XCTAssertEqualObjects([secondRow valueForKey:@"previewSelected"], @NO);
    XCTAssertNil(table.indexPathForSelectedRow);
    XCTAssertTrue(((UIView *)[detail valueForKey:@"filePreviewPlaceholder"]).hidden);

    [detail setValue:second forKey:@"preViewItem"];
    XCTAssertEqualObjects([firstRow valueForKey:@"previewSelected"], @NO);
    XCTAssertEqualObjects([secondRow valueForKey:@"previewSelected"], @YES);

    [files setValue:@YES forKey:@"gridModeEnabled"];
    [files applyViewMode];
    UICollectionView *grid = [files valueForKey:@"collectionView"];
    [grid reloadData];
    [self settle];
    UICollectionViewCell *secondItem = [grid cellForItemAtIndexPath:secondPath];
    XCTAssertNotNil(secondItem);
    XCTAssertEqualObjects([secondItem valueForKey:@"previewSelected"], @YES);
    XCTAssertEqual(grid.indexPathsForSelectedItems.count, 0u);

    [detail setValue:nil forKey:@"preViewItem"];
    XCTAssertEqualObjects([secondItem valueForKey:@"previewSelected"], @NO);
    XCTAssertFalse(((UIView *)[detail valueForKey:@"filePreviewPlaceholder"]).hidden);

    UILabel *gridTitle = [secondItem valueForKey:@"titleLabel"];
    XCTAssertEqualWithAccuracy(gridTitle.font.pointSize, 13, 0.5);
    [self resize:CGSizeMake(1120, 820) category:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge];
    gridTitle = [[grid cellForItemAtIndexPath:secondPath] valueForKey:@"titleLabel"];
    XCTAssertGreaterThan(gridTitle.font.pointSize, 13);
}

- (void)testPreviewControlsHaveAccessibleTouchTargets {
    NSString *storyboard = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"FolderView_iPad" : @"FolderView_iPhone";
    UIViewController *detail = [[UIStoryboard storyboardWithName:storyboard bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
    [self mount:detail size:CGSizeMake(390, 844) category:UIContentSizeCategoryLarge];
    UIView *toolbar = [detail valueForKey:@"toolbarView"];
    XCTAssertNotNil(toolbar);
    NSUInteger count = 0;
    for (UIView *view in toolbar.subviews) {
        if (![view isKindOfClass:UIButton.class]) continue;
        count++;
        XCTAssertGreaterThanOrEqual(view.bounds.size.height, 44);
        XCTAssertGreaterThanOrEqual(view.bounds.size.width, 44);
        XCTAssertGreaterThan(view.accessibilityLabel.length, 0u);
        XCTAssertTrue([view.accessibilityIdentifier hasPrefix:@"preview_"]);
    }
    XCTAssertEqual(count, 3u);
}

- (void)testFileRowsKeepFixedFontsAcrossTextSizes {
    UIViewController *controller = [UIViewController new];
    [self mount:controller size:CGSizeMake(320, 800) category:UIContentSizeCategoryLarge];
    UITableViewCell *cell = [NSBundle.mainBundle loadNibNamed:@"SeafCell" owner:nil options:nil].firstObject;
    [controller.view addSubview:cell];
    cell.textLabel.text = @"Very long file name for checking readable wrapped text.txt";
    cell.detailTextLabel.text = @"Modified yesterday · 25 MB";
    cell.bounds = CGRectMake(0, 0, 320, 80);
    XCTAssertEqualObjects(cell.textLabel.font, [UIFont systemFontOfSize:15]);
    XCTAssertEqualObjects(cell.detailTextLabel.font, [UIFont systemFontOfSize:12]);
    CGFloat normalHeight = [cell.contentView systemLayoutSizeFittingSize:CGSizeMake(320, UILayoutFittingCompressedSize.height)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    [self resize:CGSizeMake(320, 800) category:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge];
    CGFloat largeHeight = [cell.contentView systemLayoutSizeFittingSize:CGSizeMake(320, UILayoutFittingCompressedSize.height)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    XCTAssertEqualObjects(cell.textLabel.font, [UIFont systemFontOfSize:15]);
    XCTAssertEqualObjects(cell.detailTextLabel.font, [UIFont systemFontOfSize:12]);
    XCTAssertEqualWithAccuracy(largeHeight, normalHeight, 0.5);
    cell.frame = CGRectMake(0, 60, 320, largeHeight);
    [cell setNeedsLayout];
    [cell layoutIfNeeded];
    XCTAssertLessThanOrEqual(CGRectGetMaxY(cell.textLabel.frame), CGRectGetMinY(cell.detailTextLabel.frame));
    [self attach:@"file-row-fixed-fonts"];
}

- (void)testSettingsRowsKeepFixedFontsAtNarrowWidth {
    UITabBarController *tabs = [self appTabs];
    tabs.selectedIndex = 4;
    [self mount:tabs size:CGSizeMake(320, 844) category:UIContentSizeCategoryLarge];
    id app = UIApplication.sharedApplication.delegate;
    UITableViewController *settings = (id)[app masterNavController:4].topViewController;
    UITableView *table = settings.tableView;
    UIView *header = [table.delegate tableView:table viewForHeaderInSection:0];
    UILabel *headerTitle = (id)header.subviews.firstObject;
    XCTAssertEqualObjects(headerTitle.font, [UIFont systemFontOfSize:14]);
    [self resize:CGSizeMake(320, 844) category:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge];
    header = [table.delegate tableView:table viewForHeaderInSection:0];
    headerTitle = (id)header.subviews.firstObject;
    XCTAssertEqualObjects(headerTitle.font, [UIFont systemFontOfSize:14]);
    // Include the programmatic pause row without enabling photo access or sync.
    [settings setValue:@YES forKey:@"backupControlRowVisible"];
    [table reloadData];
    [self settle];
    for (NSInteger section = 0; section < [table numberOfSections]; section++) {
        for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
            [table scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionTop animated:NO];
            [self settle];
            UITableViewCell *cell = [table cellForRowAtIndexPath:path];
            if (!cell) continue;
            for (UIView *view in cell.contentView.subviews) {
                if (![view isKindOfClass:UILabel.class] || view.hidden || !((UILabel *)view).text.length) continue;
                UILabel *label = (id)view;
                XCTAssertEqualObjects(label.font, [UIFont systemFontOfSize:17], @"Unexpected font at %@: %@", path, label.text);
                CGFloat required = [label sizeThatFits:CGSizeMake(label.bounds.size.width, CGFLOAT_MAX)].height;
                XCTAssertGreaterThanOrEqual(label.bounds.size.height + 1, required, @"Text clipped at %@: %@", path, label.text);
                XCTAssertGreaterThanOrEqual(CGRectGetMinY(label.frame), -1, @"Text above row %@", path);
                XCTAssertLessThanOrEqual(CGRectGetMaxY(label.frame), cell.contentView.bounds.size.height + 1, @"Text below row %@: %@", path, label.text);
            }
        }
    }
    UILabel *pausedLabel = [settings valueForKey:@"backupPausedLabel"];
    XCTAssertEqualObjects(pausedLabel.font, [UIFont systemFontOfSize:14]);
    [table setContentOffset:CGPointMake(0, -table.adjustedContentInset.top) animated:NO];
    [self settle];
    [self attach:@"settings-fixed-fonts"];
}

- (void)assertTabBar:(UITabBarController *)tabs visible:(BOOL)expected context:(NSString *)context {
    UITabBar *bar = tabs.tabBar;
    CGRect frame = [bar convertRect:bar.bounds toView:tabs.view];
    BOOL visible = bar.window != nil && !bar.hidden && bar.alpha > 0 &&
        !CGRectIsEmpty(frame) && CGRectIntersectsRect(frame, tabs.view.bounds);
    XCTAssertEqual(visible, expected, @"%@: tab bar frame=%@ hidden=%d alpha=%g", context,
                   NSStringFromCGRect(frame), bar.hidden, bar.alpha);
}

- (void)testIPhoneTabNavigationHidesAndRestoresTabBar {
    XCTSkipUnless(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone,
                  @"Requires an iPhone simulator");
    UITabBarController *tabs = [self appTabs];
    [self mount:tabs size:self.window.bounds.size category:UIContentSizeCategoryLarge];
    XCTAssertEqual(tabs.viewControllers.count, 5u);
    Class navigationClass = NSClassFromString(@"SeafNavigationController");
    XCTAssertNotNil(navigationClass);

    for (NSUInteger index = 0; index < tabs.viewControllers.count; index++) {
        UINavigationController *navigation = (id)tabs.viewControllers[index];
        XCTAssertTrue([navigation isKindOfClass:navigationClass], @"Tab %lu must use the shared navigation policy", (unsigned long)index);
        tabs.selectedIndex = index;
        [self settle];
        [self assertTabBar:tabs visible:YES context:@"Tab root"];
        XCTAssertFalse(navigation.viewControllers.firstObject.hidesBottomBarWhenPushed);

        UIViewController *first = [UIViewController new];
        UIViewController *second = [UIViewController new];
        [navigation pushViewController:first animated:NO];
        [self settle];
        XCTAssertTrue(first.hidesBottomBarWhenPushed);
        [self assertTabBar:tabs visible:NO context:@"First pushed page"];
        [navigation pushViewController:second animated:NO];
        [self settle];
        [self assertTabBar:tabs visible:NO context:@"Second pushed page"];
        [navigation popViewControllerAnimated:NO];
        [self settle];
        [self assertTabBar:tabs visible:NO context:@"Returned to first pushed page"];

        // A programmatic tab change must use the selected stack's state.
        tabs.selectedIndex = (index + 1) % tabs.viewControllers.count;
        [self settle];
        [self assertTabBar:tabs visible:YES context:@"Another tab's root"];
        tabs.selectedIndex = index;
        [self settle];
        [self assertTabBar:tabs visible:NO context:@"Returned to a tab with a pushed page"];
        [navigation popToRootViewControllerAnimated:NO];
        [self settle];
        [self assertTabBar:tabs visible:YES context:@"Popped to tab root"];
    }
}

- (void)testIPhoneReplacedNavigationStackHidesAndRestoresTabBar {
    XCTSkipUnless(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone,
                  @"Requires an iPhone simulator");
    UITabBarController *tabs = [self appTabs];
    tabs.selectedIndex = 0;
    [self mount:tabs size:self.window.bounds.size category:UIContentSizeCategoryLarge];
    UINavigationController *navigation = (id)tabs.selectedViewController;
    UIViewController *root = navigation.viewControllers.firstObject;
    UIViewController *library = [UIViewController new];
    UIViewController *folder = [UIViewController new];
    // Starred-file location builds the Files stack in one operation.
    [navigation setViewControllers:@[root, library, folder] animated:NO];
    [self settle];
    XCTAssertFalse(root.hidesBottomBarWhenPushed);
    XCTAssertTrue(library.hidesBottomBarWhenPushed);
    XCTAssertTrue(folder.hidesBottomBarWhenPushed);
    [self assertTabBar:tabs visible:NO context:@"Batch-created directory path"];
    [navigation popViewControllerAnimated:NO];
    [self settle];
    [self assertTabBar:tabs visible:NO context:@"Parent in a batch-created path"];
    navigation.viewControllers = @[root];
    [self settle];
    [self assertTabBar:tabs visible:YES context:@"Reset stack to root"];

    // The property setter must apply the same policy as the animated method.
    navigation.viewControllers = @[root, folder];
    [self settle];
    [self assertTabBar:tabs visible:NO context:@"Property-created directory path"];
    [navigation popToRootViewControllerAnimated:NO];
    [self settle];
    [self assertTabBar:tabs visible:YES context:@"Returned from property-created path"];
}

- (void)testIPhoneFileListTabBarLayout {
    XCTSkipUnless(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone,
                  @"Requires an iPhone simulator");
    UITabBarController *tabs = [self appTabs];
    tabs.selectedIndex = 0;
    [self mount:tabs size:self.window.bounds.size category:UIContentSizeCategoryLarge];
    [self assertTabBar:tabs visible:YES context:@"Libraries root"];

    if (@available(iOS 26.0, *)) {
        XCTAssertTrue(tabs.tabBar.isTranslucent, @"The iPhone root keeps its native glass tab bar");
    } else {
        XCTAssertFalse(tabs.tabBar.isTranslucent, @"The legacy iPhone tab bar remains opaque");
    }
    UINavigationController *navigation = (id)tabs.selectedViewController;
    // Reuse the folder controller that the Libraries tab pushes in production.
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil];
    UIViewController *folder = [storyboard instantiateViewControllerWithIdentifier:@"MASTERVC"];
    folder.title = @"Offline layout fixture";
    [navigation pushViewController:folder animated:NO];
    [self settle];
    UITableView *table = [folder valueForKey:@"tableView"];
    XCTAssertNotNil(table.window, @"The pushed folder's list must be mounted before scrolling");
    if (!table.window) return;

    NSMutableArray *files = [NSMutableArray array];
    Class fileClass = NSClassFromString(@"SeafFile");
    for (NSUInteger i = 0; i < 48; i++) {
        NSString *name = [NSString stringWithFormat:@"Layout file %02lu.txt", (unsigned long)(i + 1)];
        [files addObject:[[fileClass alloc] initWithConnection:nil oid:nil repoId:@"fixture"
                                                        name:name path:[@"/" stringByAppendingString:name]
                                                       mtime:0 size:0]];
    }
    [folder setValue:files forKey:@"allItems"];
    [folder setValue:@NO forKey:@"gridModeEnabled"];
    [folder applyViewMode];
    [table reloadData];
    [self settle];

    [self assertTabBar:tabs visible:NO context:@"Directory list"];
    XCTAssertEqual([table numberOfRowsInSection:0], (NSInteger)files.count);
    XCTAssertEqualWithAccuracy(folder.view.safeAreaInsets.bottom, tabs.view.safeAreaInsets.bottom, 1,
                               @"A hidden tab bar must not leave an extra bottom safe-area inset");

    CGFloat firstOffset = -table.adjustedContentInset.top;
    CGFloat lastOffset = table.contentSize.height - CGRectGetHeight(table.bounds) + table.adjustedContentInset.bottom;
    XCTAssertGreaterThan(lastOffset, firstOffset);
    [table setContentOffset:CGPointMake(table.contentOffset.x, (firstOffset + lastOffset) / 2) animated:NO];
    [self settle];

    CGRect viewport = [table convertRect:table.bounds toView:tabs.view];
    CGRect safe = [folder.view convertRect:folder.view.safeAreaLayoutGuide.layoutFrame toView:tabs.view];
    [self attach:@"iphone-directory-with-hidden-tab-bar"];
    XCTAssertGreaterThanOrEqual(CGRectGetMaxY(viewport) + 1, CGRectGetMaxY(safe),
                                @"The directory viewport must fill the space freed by the tab bar");
    [self assertTabBar:tabs visible:NO context:@"Scrolled directory list"];

    NSIndexPath *last = [NSIndexPath indexPathForRow:files.count - 1 inSection:0];
    [table scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    [self settle];
    CGRect lastRow = [table convertRect:[table rectForRowAtIndexPath:last] toView:tabs.view];
    [self attach:@"iphone-directory-last-row"];
    XCTAssertNotNil([table cellForRowAtIndexPath:last]);
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(lastRow) + 1, CGRectGetMinY(safe));
    XCTAssertLessThanOrEqual(CGRectGetMaxY(lastRow), CGRectGetMaxY(safe) + 1,
                             @"The last file must be fully visible above the home indicator");
    [navigation popToRootViewControllerAnimated:NO];
    [self settle];
    [self assertTabBar:tabs visible:YES context:@"Returned from directory to Libraries"];
}

- (void)configureOfflineSearchFixture:(UIViewController *)files library:(BOOL)library {
    // Assign the backing ivar rather than setDirectory:, which loads a listing.
    // These fixtures have no connection and never submit a search request.
    id directory = library
        ? [[NSClassFromString(@"SeafRepo") alloc] initWithConnection:nil andRepoId:@"search-fixture" andRepoName:@"Offline search library"]
        : [[NSClassFromString(@"SeafRepos") alloc] initWithConnection:nil];
    if (!library) {
        [directory setValue:[NSMutableArray arrayWithObject:@[]] forKey:@"repoGroups"];
    }
    [files setValue:directory forKey:@"_directory"];
    [files setValue:@[] forKey:@"allItems"];
    [files setValue:@NO forKey:@"gridModeEnabled"];
    [files applyViewMode];
}

- (UISearchController *)openOfflineSearchOn:(UIViewController *)files {
    [files searchAction:nil];
    UISearchController *search = [files valueForKey:@"searchController"];
    XCTAssertNotNil(search);
    XCTestExpectation *active = [self expectationForPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        UISearchController *controller = object;
        return controller.active && controller.presentingViewController != nil &&
            controller.viewIfLoaded.window != nil && !controller.isBeingPresented &&
            controller.transitionCoordinator == nil;
    }] evaluatedWithObject:search handler:nil];
    [self waitForExpectations:@[active] timeout:5];
    [self settle];
    XCTAssertTrue(search.active, @"The real search action must present an active search controller");
    return search;
}

- (void)waitForOfflineSearchDismissal:(UISearchController *)search {
    // active becomes NO before UIKit finishes removing its presentation. Wait
    // for the hierarchy and coordinator before pushing or starting another search.
    XCTestExpectation *dismissed = [self expectationForPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        UISearchController *controller = object;
        return !controller.active && controller.presentingViewController == nil &&
            controller.viewIfLoaded.window == nil && controller.transitionCoordinator == nil;
    }] evaluatedWithObject:search handler:nil];
    [self waitForExpectations:@[dismissed] timeout:5];
    [self settle];
    XCTAssertNil(search.presentingViewController);
    XCTAssertNil(search.viewIfLoaded.window);
}

- (void)testIPhoneSearchHidesTabsAndRestoresSelectedNavigationState {
    XCTSkipUnless(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone,
                  @"Requires an iPhone simulator");
    UITabBarController *tabs = [self appTabs];
    tabs.selectedIndex = 0;
    [self mount:tabs size:self.window.bounds.size category:UIContentSizeCategoryLarge];
    UINavigationController *navigation = (id)tabs.selectedViewController;
    UIViewController *root = navigation.viewControllers.firstObject;
    [self configureOfflineSearchFixture:root library:NO];
    [self settle];
    [self assertTabBar:tabs visible:YES context:@"Libraries before search"];

    for (NSUInteger attempt = 0; attempt < 2; attempt++) {
        UISearchController *search = [self openOfflineSearchOn:root];
        [self assertTabBar:tabs visible:NO context:@"Active Libraries search"];
        if (attempt == 0) {
            UITextField *field = search.searchBar.searchTextField;
            XCTAssertTrue(field.isFirstResponder, @"Search must focus its field before testing keyboard dismissal");
            [field resignFirstResponder];
            [self settle];
            XCTAssertFalse(field.isFirstResponder);
            XCTAssertTrue(search.active, @"Hiding the keyboard must keep the search session active");
            [self assertTabBar:tabs visible:NO context:@"Libraries search with keyboard dismissed"];
            [self attach:@"iphone-search-hidden-tabs"];
        }
        [root customSearchDismissAction:nil];
        [self waitForOfflineSearchDismissal:search];
        XCTAssertFalse(search.active);
        [self assertTabBar:tabs visible:YES context:@"Cancelled Libraries search"];
        if (attempt == 0) [self attach:@"iphone-search-cancel-restored-tabs"];
    }

    // Programmatic/system dismissal must restore tabs without the custom button.
    UISearchController *rootSearch = [self openOfflineSearchOn:root];
    [self assertTabBar:tabs visible:NO context:@"Libraries search before system dismissal"];
    rootSearch.active = NO;
    [self waitForOfflineSearchDismissal:rootSearch];
    XCTAssertFalse(rootSearch.active);
    [self assertTabBar:tabs visible:YES context:@"System-dismissed Libraries search"];

    UIViewController *folder = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil]
        instantiateViewControllerWithIdentifier:@"MASTERVC"];
    [self configureOfflineSearchFixture:folder library:YES];
    [navigation pushViewController:folder animated:NO];
    [self settle];
    [self assertTabBar:tabs visible:NO context:@"Directory before search"];
    UISearchController *folderSearch = [self openOfflineSearchOn:folder];
    [self assertTabBar:tabs visible:NO context:@"Active directory search"];
    [folder customSearchDismissAction:nil];
    [self waitForOfflineSearchDismissal:folderSearch];
    XCTAssertFalse(folderSearch.active);
    [self assertTabBar:tabs visible:NO context:@"Cancelled directory search"];

    folderSearch = [self openOfflineSearchOn:folder];
    [self assertTabBar:tabs visible:NO context:@"Directory search before system dismissal"];
    folderSearch.active = NO;
    [self waitForOfflineSearchDismissal:folderSearch];
    XCTAssertFalse(folderSearch.active);
    [self assertTabBar:tabs visible:NO context:@"System-dismissed directory search"];
    [navigation popToRootViewControllerAnimated:NO];
    [self settle];
    [self assertTabBar:tabs visible:YES context:@"Returned from searched directory to Libraries"];

    // Use the production pending-result path: dismiss the actual search first,
    // then asynchronously push its selected directory without a visible tab gap.
    rootSearch = [self openOfflineSearchOn:root];
    id result = [[LayoutOfflineSearchDirectoryClass() alloc] initWithConnection:nil oid:nil repoId:@"search-fixture"
                                                                 perm:@"r" name:@"Offline search result"
                                                                 path:@"/Offline search result" mime:@"text/directory"];
    [root openSearchResultDirectory:result];
    [self assertTabBar:tabs visible:NO context:@"Pending search result keeps tabs hidden"];
    [self waitForOfflineSearchDismissal:rootSearch];
    XCTestExpectation *pushed = [self expectationForPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        UINavigationController *controller = object;
        return controller.viewControllers.count == 2 && controller.transitionCoordinator == nil;
    }] evaluatedWithObject:navigation handler:nil];
    [self waitForExpectations:@[pushed] timeout:5];
    [self settle];
    XCTAssertFalse(rootSearch.active);
    XCTAssertEqual([navigation.topViewController valueForKey:@"directory"], result);
    XCTAssertNil([root valueForKey:@"pendingSearchResultDirectory"]);
    [self assertTabBar:tabs visible:NO context:@"Pushed search result directory"];
    [navigation popToRootViewControllerAnimated:NO];
    [self settle];
    [self assertTabBar:tabs visible:YES context:@"Returned from search result to Libraries"];
}

- (void)testIPhoneTabSwitchDuringActiveSearchRestoresSelectedTabVisibility {
    XCTSkipUnless(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone,
                  @"Requires an iPhone simulator");
    UITabBarController *tabs = [self appTabs];
    tabs.selectedIndex = 0;
    [self mount:tabs size:self.window.bounds.size category:UIContentSizeCategoryLarge];
    UINavigationController *navigation = (id)tabs.selectedViewController;
    UIViewController *root = navigation.viewControllers.firstObject;
    [self configureOfflineSearchFixture:root library:NO];
    UISearchController *search = [self openOfflineSearchOn:root];
    [self assertTabBar:tabs visible:NO context:@"Libraries search before tab switch"];

    tabs.selectedIndex = 1;
    [self settle];
    [self assertTabBar:tabs visible:YES context:@"Another tab root during Libraries search"];
    tabs.selectedIndex = 0;
    [self settle];
    // UIKit may dismiss the old search when its tab becomes inactive. If it
    // retains the session, returning to that search must hide the tabs again.
    [self assertTabBar:tabs visible:!search.active context:@"Returned to Libraries after tab switch"];
    [root customSearchDismissAction:nil];
    [self waitForOfflineSearchDismissal:search];
    XCTAssertFalse(search.active);
    [self assertTabBar:tabs visible:YES context:@"Libraries root after cancelling switched search"];
}

- (void)testIPhoneInactiveSearchCallbacksDoNotRestoreAnotherSearchTabBar {
    XCTSkipUnless(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone,
                  @"Requires an iPhone simulator");
    UITabBarController *tabs = [self appTabs];
    tabs.selectedIndex = 0;
    [self mount:tabs size:self.window.bounds.size category:UIContentSizeCategoryLarge];
    UINavigationController *navigation = (id)tabs.selectedViewController;
    UIViewController *root = navigation.viewControllers.firstObject;
    [self configureOfflineSearchFixture:root library:NO];
    UIViewController *folder = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil]
        instantiateViewControllerWithIdentifier:@"MASTERVC"];
    [self configureOfflineSearchFixture:folder library:YES];
    [navigation pushViewController:folder animated:NO];
    [self settle];
    UISearchController *oldSearch = [self openOfflineSearchOn:folder];
    [folder customSearchDismissAction:nil];
    [self waitForOfflineSearchDismissal:oldSearch];
    [navigation popToRootViewControllerAnimated:NO];
    [self settle];

    UISearchController *activeSearch = [self openOfflineSearchOn:root];
    [self assertTabBar:tabs visible:NO context:@"Current Libraries search owns hidden tabs"];
    // Deliver only to the inactive observer. Posting globally would correctly
    // cancel the current search too and would not exercise ownership isolation.
    [folder searchCancelled:[NSNotification notificationWithName:@"SeafSearchCancelled" object:nil]];
    [folder didDismissSearchController:oldSearch];
    [self settle];
    XCTAssertTrue(activeSearch.active, @"An inactive page's cancellation must not dismiss the current search");
    [self assertTabBar:tabs visible:NO context:@"Inactive search callbacks preserve current hidden tabs"];
    [root customSearchDismissAction:nil];
    [self waitForOfflineSearchDismissal:activeSearch];
    XCTAssertFalse(activeSearch.active);
    [self assertTabBar:tabs visible:YES context:@"Current search releases tabs on cancellation"];
}

- (void)testIPadMenuUsesSystemAnchorAndSurvivesResize {
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) return;
    UIViewController *presenter = [UIViewController new];
    [self mount:presenter size:CGSizeMake(768, 1024) category:UIContentSizeCategoryLarge];
    UIButton *anchor = [UIButton buttonWithType:UIButtonTypeSystem];
    anchor.frame = CGRectMake(280, 700, 44, 44);
    [presenter.view addSubview:anchor];
    NSMutableArray *titles = [NSMutableArray new];
    for (NSInteger i = 0; i < 20; i++) [titles addObject:[NSString stringWithFormat:@"Action %ld", (long)i]];
    id sheet = [NSClassFromString(@"SeafActionSheet") actionSheetWithTitles:titles];
    [sheet setValue:presenter forKey:@"targetVC"];
    [sheet showFromView:anchor];
    [self settle];
    UIAlertController *alert = (id)presenter.presentedViewController;
    XCTAssertTrue([alert isKindOfClass:UIAlertController.class]);
    XCTAssertEqual(alert.popoverPresentationController.sourceView, anchor);
    XCTAssertTrue(CGRectEqualToRect(alert.popoverPresentationController.sourceRect, anchor.bounds));
    XCTAssertEqual(alert.actions.count, 21u);
    [self resize:CGSizeMake(390, 844) category:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge];
    anchor.frame = CGRectMake(290, 600, 44, 44);
    [self settle];
    XCTAssertNotNil(alert.view.window);
    CGRect frame = [alert.view convertRect:alert.view.bounds toView:self.window];
    XCTAssertTrue(CGRectContainsRect(CGRectInset(self.window.bounds, -1, -1), frame));
    [sheet dismissAnimated:NO];
    [self settle];
    XCTAssertNil(presenter.presentedViewController);
}
@end
