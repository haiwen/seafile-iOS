#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>

// The app-hosted test target does not import the app's Pod headers.
@interface SeafActivityViewController : UIViewController
@property (nonatomic, strong) id connection;
- (void)showEvent:(NSString *)repoId detail:(NSDictionary *)detail fromCell:(UITableViewCell *)cell eventTime:(long long)eventTime;
- (void)showBatchDetailDialog:(NSDictionary *)event fromCell:(UITableViewCell *)cell;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)refresh:(id)sender;
- (void)moreEvents:(int)offset;
@end

typedef void (^PopoverRequestSuccess)(NSURLRequest *, NSHTTPURLResponse *, id);
typedef void (^PopoverRequestFailure)(NSURLRequest *, NSHTTPURLResponse *, id, NSError *);

@interface ActivityPopoverRequest : NSObject
@property (nonatomic, copy) PopoverRequestSuccess success;
- (void)complete;
@end
@implementation ActivityPopoverRequest
- (void)complete {
    self.success(nil, nil, @{@"added_files": @[@"movie.mp4"]});
}
@end

@interface ActivityPopoverRepo : NSObject
@end
@implementation ActivityPopoverRepo
- (BOOL)passwordRequired { return NO; }
- (BOOL)passwordRequiredWithSyncRefresh { return NO; }
@end

@interface ActivityPopoverConnection : NSObject
@property (nonatomic, strong) NSMutableArray<ActivityPopoverRequest *> *requests;
@end
@implementation ActivityPopoverConnection
- (instancetype)init {
    if ((self = [super init])) _requests = [NSMutableArray array];
    return self;
}
- (BOOL)isNewActivitiesApiSupported { return NO; }
- (id)getRepo:(NSString *)repoId { return [ActivityPopoverRepo new]; }
- (NSURLSessionDataTask *)sendRequest:(NSString *)url success:(PopoverRequestSuccess)success failure:(PopoverRequestFailure)failure {
    ActivityPopoverRequest *request = [ActivityPopoverRequest new];
    request.success = success;
    [self.requests addObject:request];
    return nil;
}
@end

@interface ActivityPopoverTableFixture : NSObject <UITableViewDataSource>
@property (nonatomic, copy) NSArray<NSDictionary *> *events;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UITableViewCell *> *rowCells;
@end
@implementation ActivityPopoverTableFixture
- (instancetype)init {
    if ((self = [super init])) _rowCells = [NSMutableDictionary dictionary];
    return self;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.events.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Reuse each row's real UIKit cell across reloads. This guarantees that a
    // captured cell can now display a different event, without timing guesses.
    NSNumber *row = @(indexPath.row);
    UITableViewCell *cell = self.rowCells[row];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        self.rowCells[row] = cell;
    }
    cell.textLabel.text = self.events[indexPath.row][@"commit_id"];
    return cell;
}
@end

@interface ActivityPopoverTransition : NSObject
@property (nonatomic, copy) void (^completion)(id<UIViewControllerTransitionCoordinatorContext>);
@property (nonatomic) NSUInteger registrationCount;
- (void)finish;
@end
@implementation ActivityPopoverTransition
- (BOOL)animateAlongsideTransition:(void (^)(id<UIViewControllerTransitionCoordinatorContext>))animation
                       completion:(void (^)(id<UIViewControllerTransitionCoordinatorContext>))completion {
    self.registrationCount += 1;
    self.completion = completion;
    return YES;
}
- (void)finish {
    void (^completion)(id<UIViewControllerTransitionCoordinatorContext>) = self.completion;
    self.completion = nil;
    if (completion) completion(nil);
}
@end

@interface ActivityPopoverDismissingController : UIViewController
@property (nonatomic, strong) ActivityPopoverTransition *fixtureTransition;
@end
@implementation ActivityPopoverDismissingController
- (BOOL)isBeingDismissed { return YES; }
- (id<UIViewControllerTransitionCoordinator>)transitionCoordinator { return (id)self.fixtureTransition; }
@end

@interface ActivityPopoverController : SeafActivityViewController
@property (nonatomic, strong) UIAlertController *lastAlert;
@property (nonatomic) NSUInteger presentationCount;
@property (nonatomic, strong) UIViewController *fixturePresentedController;
@end
@implementation ActivityPopoverController
- (void)loadView { self.view = [[UIView alloc] initWithFrame:CGRectZero]; }
- (void)viewDidLoad {}
- (void)moreEvents:(int)offset {}
- (UIViewController *)presentedViewController {
    return self.fixturePresentedController ?: [super presentedViewController];
}
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    self.presentationCount += 1;
    self.lastAlert = (UIAlertController *)controller;
}
@end

@interface ActivityPopoverTests : XCTestCase
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIWindow *originalKeyWindow;
@property (nonatomic, strong) ActivityPopoverController *controller;
@property (nonatomic, strong) ActivityPopoverConnection *connection;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) ActivityPopoverTableFixture *fixture;
@end

@implementation ActivityPopoverTests

- (void)setUp {
    [super setUp];
    UIWindowScene *windowScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                self.originalKeyWindow = window;
                windowScene = (UIWindowScene *)scene;
            }
        }
    }
    XCTAssertNotNil(windowScene);
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.frame = windowScene.coordinateSpace.bounds;
    self.controller = [ActivityPopoverController new];
    self.connection = [ActivityPopoverConnection new];
    self.controller.connection = self.connection;
    [self.controller loadViewIfNeeded];
    self.fixture = [ActivityPopoverTableFixture new];
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.dataSource = self.fixture;
    self.table.rowHeight = 76;
    self.table.estimatedRowHeight = 0;
    self.table.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.controller.view addSubview:self.table];
    [self.controller setValue:self.table forKey:@"tableView"];
    NSMutableArray *events = [NSMutableArray array];
    for (NSUInteger row = 0; row < 40; row++) {
        [events addObject:@{@"etype": @"repo-update", @"repo_id": @"repo-id",
                            @"commit_id": [NSString stringWithFormat:@"commit-%lu", (unsigned long)row], @"time": @123}];
    }
    [self replaceEvents:events];
    self.window.rootViewController = self.controller;
    [self.window makeKeyAndVisible];
    [self.window layoutIfNeeded];
    CGRect bounds = self.controller.view.bounds;
    self.table.frame = CGRectMake(16, 32, CGRectGetWidth(bounds) - 32, CGRectGetHeight(bounds) - 80);
    [self settle];
}

- (void)tearDown {
    self.window.hidden = YES;
    [self settle];
    self.window.rootViewController = nil;
    [self.originalKeyWindow makeKeyAndVisible];
    [self settle];
    self.controller = nil;
    self.fixture = nil;
    self.table = nil;
    self.connection = nil;
    self.window = nil;
    self.originalKeyWindow = nil;
    [super tearDown];
}

- (void)settle {
    [self.window layoutIfNeeded];
    [self.controller.view layoutIfNeeded];
    [self.table layoutIfNeeded];
    // UIWindow appearance transitions finish on a later run-loop pass, after
    // ordinary main-queue callbacks. Finish them before replacing its root.
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    [self.window layoutIfNeeded];
    [self.controller.view layoutIfNeeded];
    [self.table layoutIfNeeded];
}

- (void)replaceEvents:(NSArray<NSDictionary *> *)events {
    self.fixture.events = events;
    [self.controller setValue:events forKey:@"events"];
    [self.table reloadData];
    [self.table layoutIfNeeded];
}

- (CGRect)visibleRectForCell:(UITableViewCell *)cell {
    CGRect rect = [cell convertRect:cell.bounds toView:self.controller.view];
    rect = CGRectIntersection(rect, [self.table convertRect:self.table.bounds toView:self.controller.view]);
    rect = CGRectIntersection(rect, self.controller.view.bounds);
    return CGRectIntersection(rect, self.controller.view.safeAreaLayoutGuide.layoutFrame);
}

- (UITableViewCell *)safeVisibleCell {
    for (NSIndexPath *indexPath in self.table.indexPathsForVisibleRows) {
        UITableViewCell *cell = [self.table cellForRowAtIndexPath:indexPath];
        CGRect rect = [self visibleRectForCell:cell];
        if (!CGRectIsNull(rect) && !CGRectIsEmpty(rect)) return cell;
    }
    XCTFail(@"Fixture needs a visible cell inside the safe area");
    return nil;
}

- (void)assertAlertAnchoredToCell:(UITableViewCell *)cell {
    XCTAssertNotNil(self.controller.lastAlert);
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) return;
    UIPopoverPresentationController *popover = self.controller.lastAlert.popoverPresentationController;
    XCTAssertNotNil(popover);
    XCTAssertEqual(popover.sourceView, self.controller.view);
    CGRect expected = [self visibleRectForCell:cell];
    XCTAssertEqualWithAccuracy(popover.sourceRect.origin.x, expected.origin.x, 0.1);
    XCTAssertEqualWithAccuracy(popover.sourceRect.origin.y, expected.origin.y, 0.1);
    XCTAssertEqualWithAccuracy(popover.sourceRect.size.width, expected.size.width, 0.1);
    XCTAssertEqualWithAccuracy(popover.sourceRect.size.height, expected.size.height, 0.1);
}

- (NSDictionary *)batchEvent {
    return @{@"op_type": @"batch_create", @"obj_type": @"file", @"repo_id": @"repo-id", @"time": @123,
             @"details": @[@{@"path": @"/movie.mp4"}]};
}

- (ActivityPopoverRequest *)selectRow:(NSInteger)row {
    [self.controller tableView:self.table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
    return self.connection.requests.lastObject;
}

- (void)testNormalAndBatchAnchorsFollowScrolledCellsAndSafeArea {
    for (NSNumber *safeTop in @[@0, @110]) {
        self.controller.additionalSafeAreaInsets = UIEdgeInsetsMake(safeTop.doubleValue, 0, 0, 0);
        for (NSNumber *offset in @[@0, @43, @157]) {
            self.table.contentOffset = CGPointMake(0, offset.doubleValue);
            [self settle];
            UITableViewCell *cell = [self safeVisibleCell];
            self.controller.lastAlert = nil;
            [self.controller showEvent:@"repo-id" detail:@{@"added_files": @[@"movie.mp4"]} fromCell:cell eventTime:123];
            [self assertAlertAnchoredToCell:cell];
            self.controller.lastAlert = nil;
            [self.controller showBatchDetailDialog:[self batchEvent] fromCell:cell];
            [self assertAlertAnchoredToCell:cell];
        }
    }
    XCTAssertEqual(self.controller.presentationCount, 12u);
}

- (void)testMissingOrDetachedCellNeverUsesFallbackAnchor {
    for (id cell in @[NSNull.null, [UITableViewCell new]]) {
        UITableViewCell *sourceCell = cell == NSNull.null ? nil : cell;
        [self.controller showEvent:@"repo-id" detail:@{} fromCell:sourceCell eventTime:123];
        [self.controller showBatchDetailDialog:[self batchEvent] fromCell:sourceCell];
    }
    XCTAssertEqual(self.controller.presentationCount, 0u);
}

- (void)testCellOutsideSafeAreaDoesNotPresent {
    self.controller.additionalSafeAreaInsets = UIEdgeInsetsMake(250, 0, 0, 0);
    [self settle];
    UITableViewCell *cell = [self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    XCTAssertNotNil(cell);
    XCTAssertTrue(CGRectIsEmpty([self visibleRectForCell:cell]) || CGRectIsNull([self visibleRectForCell:cell]));
    [self.controller showEvent:@"repo-id" detail:@{} fromCell:cell eventTime:123];
    [self.controller showBatchDetailDialog:[self batchEvent] fromCell:cell];
    XCTAssertEqual(self.controller.presentationCount, 0u);
}

- (void)testAsyncDetailFollowsEventToItsCurrentCellAfterReuse {
    ActivityPopoverRequest *request = [self selectRow:1];
    XCTAssertNotNil(request);
    UITableViewCell *originalCell = [self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    NSMutableArray *events = [self.fixture.events mutableCopy];
    [events exchangeObjectAtIndex:1 withObjectAtIndex:3];
    [self replaceEvents:events];
    [self settle];
    XCTAssertEqual(originalCell, [self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]]);
    XCTAssertEqualObjects(originalCell.textLabel.text, @"commit-3");
    [request complete];
    [self settle];
    XCTAssertEqual(self.controller.presentationCount, 1u);
    [self assertAlertAnchoredToCell:[self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]]];
}

- (void)testAsyncDetailDoesNotAnchorToReusedCellWhenEventMovesOffscreen {
    ActivityPopoverRequest *request = [self selectRow:1];
    NSMutableArray *events = [self.fixture.events mutableCopy];
    [events exchangeObjectAtIndex:1 withObjectAtIndex:30];
    [self replaceEvents:events];
    [self settle];
    [request complete];
    [self settle];
    XCTAssertEqual(self.controller.presentationCount, 0u);
}

- (void)testAsyncDetailIgnoresEqualEventFromRefreshedSnapshot {
    ActivityPopoverRequest *request = [self selectRow:1];
    NSMutableArray *events = [self.fixture.events mutableCopy];
    NSDictionary *originalEvent = events[1];
    events[1] = [originalEvent mutableCopy];
    XCTAssertNotEqual(events[1], originalEvent);
    XCTAssertEqualObjects(events[1], originalEvent);
    [self replaceEvents:events];
    [self settle];
    [request complete];
    [self settle];
    XCTAssertEqual(self.controller.presentationCount, 0u);
}

- (void)testLatestActivitySelectionIgnoresEarlierDetail {
    ActivityPopoverRequest *oldRequest = [self selectRow:1];
    ActivityPopoverRequest *newRequest = [self selectRow:3];
    XCTAssertEqual(self.connection.requests.count, 2u);
    [oldRequest complete];
    [self settle];
    XCTAssertEqual(self.controller.presentationCount, 0u);
    [newRequest complete];
    [self settle];
    XCTAssertEqual(self.controller.presentationCount, 1u);
    [self assertAlertAnchoredToCell:[self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]]];
}

- (void)testSwitchingAccountsIgnoresPendingDetail {
    ActivityPopoverRequest *request = [self selectRow:1];
    self.controller.connection = [ActivityPopoverConnection new];
    [request complete];
    [self settle];
    XCTAssertEqual(self.controller.presentationCount, 0u);
}

- (void)testLeavingActivitiesIgnoresPendingDetail {
    ActivityPopoverRequest *request = [self selectRow:1];
    [self.controller beginAppearanceTransition:NO animated:NO];
    [self.controller endAppearanceTransition];
    [request complete];
    [self settle];
    XCTAssertEqual(self.controller.presentationCount, 0u);
}

- (void)testRefreshingActivitiesIgnoresPendingDetail {
    ActivityPopoverRequest *request = [self selectRow:1];
    [self.controller refresh:nil];
    [request complete];
    [self settle];
    XCTAssertEqual(self.controller.presentationCount, 0u);
}

- (void)testDetailWaitsForDismissingModalAndResolvesCurrentCell {
    ActivityPopoverRequest *request = [self selectRow:1];
    ActivityPopoverDismissingController *modal = [ActivityPopoverDismissingController new];
    modal.fixtureTransition = [ActivityPopoverTransition new];
    self.controller.fixturePresentedController = modal;
    [request complete];
    XCTAssertEqual(modal.fixtureTransition.registrationCount, 1u);
    XCTAssertEqual(self.controller.presentationCount, 0u);
    NSMutableArray *events = [self.fixture.events mutableCopy];
    [events exchangeObjectAtIndex:1 withObjectAtIndex:3];
    [self replaceEvents:events];
    [self settle];
    self.controller.fixturePresentedController = nil;
    [modal.fixtureTransition finish];
    [self settle];
    XCTAssertEqual(self.controller.presentationCount, 1u);
    [self assertAlertAnchoredToCell:[self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]]];
}

- (void)testWaitingDetailIgnoresChangedSelectionOrReplacedEvent {
    for (NSNumber *replaceEvent in @[@NO, @YES]) {
        [self.controller setValue:[NSMutableDictionary dictionary] forKey:@"eventDetails"];
        ActivityPopoverRequest *request = [self selectRow:1];
        ActivityPopoverDismissingController *modal = [ActivityPopoverDismissingController new];
        modal.fixtureTransition = [ActivityPopoverTransition new];
        self.controller.fixturePresentedController = modal;
        [request complete];
        XCTAssertEqual(modal.fixtureTransition.registrationCount, 1u);
        XCTAssertEqual(self.controller.presentationCount, 0u);
        if (replaceEvent.boolValue) {
            NSMutableArray *events = [self.fixture.events mutableCopy];
            events[1] = [events[1] mutableCopy];
            [self replaceEvents:events];
        } else {
            [self selectRow:3];
        }
        self.controller.fixturePresentedController = nil;
        [modal.fixtureTransition finish];
        [self settle];
        XCTAssertEqual(self.controller.presentationCount, 0u);
    }
}

@end
