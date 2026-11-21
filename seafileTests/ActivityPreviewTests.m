#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Narrow declarations keep these app-hosted tests independent of Pod headers.
@interface SeafActivityViewController : UIViewController
@property (nonatomic, strong) id connection;
- (void)openFile:(NSString *)path inRepo:(NSString *)repoId mtime:(long long)mtime;
- (void)previewFile:(NSString *)path inRepo:(NSString *)repoId mtime:(long long)mtime;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
@end

typedef void (^ActivityRequestSuccess)(NSURLRequest *, NSHTTPURLResponse *, id);
typedef void (^ActivityRequestFailure)(NSURLRequest *, NSHTTPURLResponse *, id, NSError *);

@interface ActivityPreviewRequest : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) ActivityRequestSuccess success;
@property (nonatomic, copy) ActivityRequestFailure failure;
- (void)finishWithStatus:(NSInteger)status;
- (void)failOffline;
@end

@implementation ActivityPreviewRequest
- (NSURLRequest *)request {
    return [NSURLRequest requestWithURL:[NSURL URLWithString:[@"https://example.invalid" stringByAppendingString:self.url]]];
}
- (void)finishWithStatus:(NSInteger)status {
    NSURLRequest *request = [self request];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:nil];
    if (status == 200) {
        self.success(request, response, @{@"id": @"current-file-id", @"size": @42, @"mtime": @123});
    } else {
        NSError *error = [NSError errorWithDomain:@"ActivityPreviewHTTPError" code:status userInfo:nil];
        self.failure(request, response, @{@"error_msg": @"Request failed"}, error);
    }
}
- (void)failOffline {
    self.failure([self request], nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
}
@end

@interface ActivityPreviewConnection : NSObject
@property (nonatomic, strong) NSMutableArray<ActivityPreviewRequest *> *requests;
@end

@implementation ActivityPreviewConnection
- (BOOL)isNewActivitiesApiSupported { return NO; }
- (instancetype)init {
    if ((self = [super init])) _requests = [NSMutableArray array];
    return self;
}
- (NSURLSessionDataTask *)sendRequest:(NSString *)url success:(ActivityRequestSuccess)success failure:(ActivityRequestFailure)failure {
    ActivityPreviewRequest *request = [ActivityPreviewRequest new];
    request.url = url;
    request.success = success;
    request.failure = failure;
    [self.requests addObject:request];
    return nil;
}
@end

@interface ActivityPreviewController : SeafActivityViewController
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *previews;
@property (nonatomic) NSUInteger presentationCount;
@end

@implementation ActivityPreviewController
- (instancetype)init {
    if ((self = [super init])) _previews = [NSMutableArray array];
    return self;
}
- (void)previewFile:(NSString *)path inRepo:(NSString *)repoId mtime:(long long)mtime {
    [self.previews addObject:@{@"path": path, @"repo": repoId, @"mtime": @(mtime)}];
}
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    self.presentationCount += 1;
}
@end

static NSString *ActivityPreviewLastError;

@interface ActivityPreviewTests : XCTestCase
@property (nonatomic, strong) ActivityPreviewController *controller;
@property (nonatomic, strong) ActivityPreviewConnection *connection;
@property (nonatomic) IMP originalError;
@property (nonatomic) IMP originalLoading;
@property (nonatomic) IMP originalDismiss;
@property (nonatomic) IMP errorReplacement;
@property (nonatomic) IMP loadingReplacement;
@property (nonatomic) IMP dismissReplacement;
@end

@implementation ActivityPreviewTests

- (void)setUp {
    [super setUp];
    ActivityPreviewLastError = nil;
    Class hud = NSClassFromString(@"SVProgressHUD");
    XCTAssertNotNil(hud);
    self.errorReplacement = imp_implementationWithBlock(^(id receiver, NSString *message) {
        ActivityPreviewLastError = [message copy];
    });
    self.loadingReplacement = imp_implementationWithBlock(^(id receiver, NSString *message) {});
    self.dismissReplacement = imp_implementationWithBlock(^(id receiver) {});
    self.originalError = method_setImplementation(class_getClassMethod(hud, NSSelectorFromString(@"showErrorWithStatus:")), self.errorReplacement);
    self.originalLoading = method_setImplementation(class_getClassMethod(hud, NSSelectorFromString(@"showWithStatus:")), self.loadingReplacement);
    self.originalDismiss = method_setImplementation(class_getClassMethod(hud, NSSelectorFromString(@"dismiss")), self.dismissReplacement);
    self.connection = [ActivityPreviewConnection new];
    self.controller = [ActivityPreviewController new];
    self.controller.connection = self.connection;
}

- (void)tearDown {
    Class hud = NSClassFromString(@"SVProgressHUD");
    method_setImplementation(class_getClassMethod(hud, NSSelectorFromString(@"showErrorWithStatus:")), self.originalError);
    method_setImplementation(class_getClassMethod(hud, NSSelectorFromString(@"showWithStatus:")), self.originalLoading);
    method_setImplementation(class_getClassMethod(hud, NSSelectorFromString(@"dismiss")), self.originalDismiss);
    imp_removeBlock(self.errorReplacement);
    imp_removeBlock(self.loadingReplacement);
    imp_removeBlock(self.dismissReplacement);
    self.controller = nil;
    self.connection = nil;
    ActivityPreviewLastError = nil;
    [super tearDown];
}

- (void)drainCallbacks {
    XCTestExpectation *drained = [self expectationWithDescription:@"main-queue file check completed"];
    dispatch_async(dispatch_get_main_queue(), ^{ [drained fulfill]; });
    [self waitForExpectations:@[drained] timeout:1.0];
}

- (void)assertNoPreview {
    XCTAssertEqual(self.controller.previews.count, 0u);
    XCTAssertEqual(self.controller.presentationCount, 0u);
    XCTAssertNil(self.controller.presentedViewController);
}

- (void)testMissingFilesNeverOpenAnyPreview {
    for (NSString *path in @[@"missing.mp4", @"missing.jpg", @"missing.pdf"]) {
        ActivityPreviewLastError = nil;
        [self.controller openFile:path inRepo:@"repo-id" mtime:123];
        [self assertNoPreview];
        [self.connection.requests.lastObject finishWithStatus:404];
        [self drainCallbacks];
        [self assertNoPreview];
        XCTAssertEqualObjects(ActivityPreviewLastError, NSLocalizedString(@"The file has been deleted", @"Seafile"));
    }
}

- (void)testExistingFileOpensOnlyAfterSuccessfulCheck {
    [self.controller openFile:@"movie.mp4" inRepo:@"repo-id" mtime:123];
    [self assertNoPreview];
    XCTAssertEqual(self.connection.requests.count, 1u);
    ActivityPreviewRequest *request = self.connection.requests.lastObject;
    XCTAssertEqualObjects(request.url, @"/api2/repos/repo-id/file/detail/?p=/movie.mp4");
    [request finishWithStatus:200];
    [self drainCallbacks];
    XCTAssertEqual(self.controller.previews.count, 1u);
    XCTAssertEqualObjects(self.controller.previews.firstObject, (@{@"path": @"/movie.mp4", @"repo": @"repo-id", @"mtime": @123}));
    XCTAssertNil(ActivityPreviewLastError);
}

- (void)testFileCheckEscapesQueryCharactersAndNormalizesRelativePath {
    NSString *path = @"目录/my #video & 1.mp4";
    [self.controller openFile:path inRepo:@"repo-id" mtime:123];
    ActivityPreviewRequest *request = self.connection.requests.lastObject;
    NSURLComponents *components = [NSURLComponents componentsWithString:request.url];
    XCTAssertEqualObjects(components.path, @"/api2/repos/repo-id/file/detail/");
    XCTAssertEqual(components.queryItems.count, 1u);
    XCTAssertEqualObjects(components.queryItems.firstObject.name, @"p");
    XCTAssertEqualObjects(components.queryItems.firstObject.value, [@"/" stringByAppendingString:path]);
    XCTAssertNil(components.fragment);
    [request finishWithStatus:200];
    [self drainCallbacks];
    XCTAssertEqualObjects(self.controller.previews.firstObject[@"path"], [@"/" stringByAppendingString:path]);
}

- (void)testOfflineFailureDoesNotClaimFileWasDeleted {
    [self.controller openFile:@"/movie.mp4" inRepo:@"repo-id" mtime:123];
    [self.connection.requests.lastObject failOffline];
    [self drainCallbacks];
    [self assertNoPreview];
    XCTAssertEqualObjects(ActivityPreviewLastError, NSLocalizedString(@"Failed to open file", @"Seafile"));
}

- (void)testPermissionFailureDoesNotClaimFileWasDeleted {
    [self.controller openFile:@"/movie.mp4" inRepo:@"repo-id" mtime:123];
    [self.connection.requests.lastObject finishWithStatus:403];
    [self drainCallbacks];
    [self assertNoPreview];
    XCTAssertEqualObjects(ActivityPreviewLastError, NSLocalizedString(@"Failed to open file", @"Seafile"));
}

- (void)testMalformedFileDetailDoesNotOpenPreview {
    [self.controller openFile:@"/movie.mp4" inRepo:@"repo-id" mtime:123];
    ActivityPreviewRequest *request = self.connection.requests.lastObject;
    request.success(nil, nil, NSNull.null);
    [self drainCallbacks];
    [self assertNoPreview];
    XCTAssertEqualObjects(ActivityPreviewLastError, NSLocalizedString(@"Failed to open file", @"Seafile"));
}

- (void)testLatestSelectionIgnoresEarlierSuccessAndFailure {
    [self.controller openFile:@"/old.mp4" inRepo:@"repo-id" mtime:123];
    ActivityPreviewRequest *oldRequest = self.connection.requests.lastObject;
    [self.controller openFile:@"/new.jpg" inRepo:@"repo-id" mtime:456];
    ActivityPreviewRequest *newRequest = self.connection.requests.lastObject;
    [oldRequest finishWithStatus:200];
    [self drainCallbacks];
    [self assertNoPreview];
    [newRequest finishWithStatus:200];
    [self drainCallbacks];
    [oldRequest finishWithStatus:404];
    [self drainCallbacks];
    XCTAssertEqual(self.controller.previews.count, 1u);
    XCTAssertEqualObjects(self.controller.previews.firstObject[@"path"], @"/new.jpg");
    XCTAssertNil(ActivityPreviewLastError);
}

- (void)testSwitchingAccountsIgnoresPendingFileCheck {
    [self.controller openFile:@"/movie.mp4" inRepo:@"repo-id" mtime:123];
    ActivityPreviewRequest *request = self.connection.requests.lastObject;
    self.controller.connection = [ActivityPreviewConnection new];
    [request finishWithStatus:200];
    [self drainCallbacks];
    [self assertNoPreview];
    [request finishWithStatus:404];
    [self drainCallbacks];
    XCTAssertNil(ActivityPreviewLastError);
}

- (void)testLeavingActivitiesIgnoresPendingFileCheck {
    [self.controller openFile:@"/movie.mp4" inRepo:@"repo-id" mtime:123];
    ActivityPreviewRequest *request = self.connection.requests.lastObject;
    [self.controller beginAppearanceTransition:NO animated:NO];
    [self.controller endAppearanceTransition];
    [request finishWithStatus:200];
    [self drainCallbacks];
    [self assertNoPreview];
    [request finishWithStatus:404];
    [self drainCallbacks];
    XCTAssertNil(ActivityPreviewLastError);
}

- (void)testSelectingAnotherActivityIgnoresPendingFileCheck {
    [self.controller openFile:@"/movie.mp4" inRepo:@"repo-id" mtime:123];
    ActivityPreviewRequest *request = self.connection.requests.lastObject;
    // A non-openable activity still supersedes the earlier file selection.
    [self.controller setValue:@[@{@"etype": @"repo-delete"}] forKey:@"events"];
    [self.controller tableView:nil didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    [request finishWithStatus:200];
    [self drainCallbacks];
    [self assertNoPreview];
    [request finishWithStatus:404];
    [self drainCallbacks];
    XCTAssertNil(ActivityPreviewLastError);
}

@end
