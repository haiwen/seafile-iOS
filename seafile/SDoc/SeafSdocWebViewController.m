//  SeafSdocWebViewController.m
//  Seafile

#import "SeafSdocWebViewController.h"
#import "SeafSdocStylePopupViewController.h"
#import "SeafSdocEditorToolbar.h"
#import "SeafAppDelegate.h"
#import "SeafFile.h"
#import "SeafConnection.h"
#import "SDocPageOptionsModel.h"
#import "OutlineItemModel.h"
#import "SeafSDocOutlineSheetViewController.h"
#import "SeafSdocCommentsViewController.h"
#import "SeafSdocService.h"
#import "SeafSdocProfileAssembler.h"
#import "SeafNavLeftItem.h"
#import "SeafSdocProfileSheetViewController.h"
#import "SVProgressHUD.h"
#import "Constants.h"
#import <string.h>

typedef void (^SeafJSCallback)(NSString * _Nullable data);

static NSString * const kSeafBridgeShimScript =
@"(function(){\n"
"  var w=window;\n"
"  if(!w.WebViewJavascriptBridge){\n"
"    var _handlers={};\n"
"    w.WebViewJavascriptBridge={\n"
"      registerHandler:function(name,handler){ try{ _handlers[name]=handler; }catch(e){} },\n"
"      callHandler:function(name,data,resp){ try{ if(w.webkit && w.webkit.messageHandlers && w.webkit.messageHandlers[name]){ var payload=(typeof data==='string')?data:JSON.stringify(data||{}); w.webkit.messageHandlers[name].postMessage(payload); if(typeof resp==='function'){ resp(''); } } }catch(e){} },\n"
"      _invoke:function(name,data){ try{ var h=_handlers[name]; if(typeof h==='function'){ h(data, function(res){ try{ if(w.webkit && w.webkit.messageHandlers && w.webkit.messageHandlers.callAndroidFunction){ w.webkit.messageHandlers.callAndroidFunction.postMessage(JSON.stringify({action:'N_N_N_N_Callback',data:res||''})); } }catch(e){} }); } }catch(e){} }\n"
"    };\n"
"  }\n"
"})();";

static NSString * const kSeafBridgeHelperScript =
@"window.callAndroidFunction = window.callAndroidFunction || function(payload){ if(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.callAndroidFunction){ window.webkit.messageHandlers.callAndroidFunction.postMessage(payload); } };";

@interface SeafWeakScriptMessageHandler : NSObject<WKScriptMessageHandler>

@property (nonatomic, weak) id<WKScriptMessageHandler> target;

- (instancetype)initWithTarget:(id<WKScriptMessageHandler>)target;

@end

@implementation SeafWeakScriptMessageHandler

- (instancetype)initWithTarget:(id<WKScriptMessageHandler>)target
{
    if (self = [super init]) {
        _target = target;
    }
    return self;
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    [self.target userContentController:userContentController didReceiveScriptMessage:message];
}

@end

@interface SeafSdocWebViewController () <SeafSdocStylePopupDelegate, SeafSdocEditorToolbarDelegate>

@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIBarButtonItem *editItem;
@property (nonatomic, strong) UIButton *editButton;
@property (nonatomic, assign) CGFloat editButtonFixedWidth;
@property (nonatomic, assign) BOOL nextEditMode; // YES -> edit
@property (nonatomic, strong) NSTimer *timeoutTimer;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, strong) SDocPageOptionsModel *pageOptions;
@property (nonatomic, strong) NSArray *outlineOriginArray; // original JSON array for precise callback
@property (nonatomic, strong) NSMutableArray<SeafJSCallback> *callbackQueue;

// Preview Bottom Bar
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIView *bottomDivider;
@property (nonatomic, strong) UIButton *btnOutline;
@property (nonatomic, strong) UIButton *btnProfile;
@property (nonatomic, strong) UIButton *btnComment;
@property (nonatomic, strong) UIStackView *bottomStack;
@property (nonatomic, strong) NSLayoutConstraint *bottomBarHeightConstraint;

// Editor Toolbar
@property (nonatomic, strong) SeafSdocEditorToolbar *editorToolbar;
@property (nonatomic, strong) NSLayoutConstraint *editorBarBottomConstraint;


@property (nonatomic, strong) SeafWeakScriptMessageHandler *weakBridgeHandler;
@property (nonatomic, strong) NSLayoutConstraint *webViewBottomConstraint;

@property (nonatomic, assign) BOOL isEditing;
@property (nonatomic, assign) CGFloat keyboardVisibleHeight;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, copy) NSString *currentStyleType; // Current paragraph style type

@end

@implementation SeafSdocWebViewController

- (instancetype)initWithFile:(SeafFile *)file fileName:(NSString *)fileName
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _file = file;
        _fileName = fileName;
        _nextEditMode = YES;
        _isEditing = NO;
        _keyboardVisibleHeight = 0;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setupAppearance];
    [self configureNavigationItems];
    [self configureEditButton];
    [self setupWebView];
    [self setupBottomToolbar];
    [self setupEditorToolbar];
    [self setupUserAgentAndLoad];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // Observe keyboard frame changes; used to adjust WebView bottom in editing mode
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onKeyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onKeyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)setupAppearance
{
    self.hidesBottomBarWhenPushed = YES;
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.view.backgroundColor = [UIColor whiteColor];
}

- (void)configureNavigationItems
{
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil; // Clear any center title view

    // Back button matching SeafNavLeftItem style
    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [backButton setImage:[UIImage imageNamed:@"arrowLeft_black"] forState:UIControlStateNormal];
    backButton.imageEdgeInsets = UIEdgeInsetsMake(12, 0, 12, 18);
    backButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [backButton addTarget:self action:@selector(onTapBack) forControlEvents:UIControlEventTouchUpInside];
    // Frame is not strictly needed for stack view but width constraint might be good if it's too small
    [backButton.widthAnchor constraintEqualToConstant:30].active = YES;
    [backButton.heightAnchor constraintEqualToConstant:44].active = YES;

    // Title Label
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = self.fileName ?: self.file.name;
    self.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold]; // Matches SeafNavLeftItem
    self.titleLabel.textColor = [UIColor blackColor];
    
    // Status Label
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.textColor = [UIColor grayColor];
    self.statusLabel.text = @"";

    // Title and Status aligned by baseline
    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.statusLabel]];
    textStack.axis = UILayoutConstraintAxisHorizontal;
    textStack.alignment = UIStackViewAlignmentFirstBaseline;
    textStack.spacing = 6;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;

    // Main stack: Back Button + Text Stack
    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[backButton, textStack]];
    stackView.axis = UILayoutConstraintAxisHorizontal;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.spacing = 6;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;

    // Allow title to shrink if needed, but keep priority high enough to be visible
    [self.titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [self.statusLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    // Wrap in a UIView because UIBarButtonItem customView behavior can be quirky with direct StackView on some iOS versions
    UIView *containerView = [[UIView alloc] init];
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:stackView];
    
    [NSLayoutConstraint activateConstraints:@[
        [stackView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
        [stackView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
        [stackView.topAnchor constraintEqualToAnchor:containerView.topAnchor],
        [stackView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor],
        // Max width constraint to avoid overlapping right items
        [containerView.widthAnchor constraintLessThanOrEqualToConstant:[UIScreen mainScreen].bounds.size.width * 0.75]
    ]];

    UIBarButtonItem *leftItem = [[UIBarButtonItem alloc] initWithCustomView:containerView];
    self.navigationItem.leftBarButtonItem = leftItem;
    
    // Tint color
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barApp = [UINavigationBarAppearance new];
        barApp.backgroundColor = [UIColor whiteColor];
        self.navigationController.navigationBar.standardAppearance = barApp;
        self.navigationController.navigationBar.scrollEdgeAppearance = barApp;
    }
}

- (void)configureEditButton
{
    UIButton *editBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [editBtn setTitle:NSLocalizedString(@"Edit", nil) forState:UIControlStateNormal];
    // Font 17px, Weight Semibold (590)
    editBtn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    editBtn.titleLabel.adjustsFontSizeToFitWidth = NO;
    editBtn.titleLabel.minimumScaleFactor = 1.0;
    // Right edge 16px: alignment right with 0 right inset
    editBtn.contentEdgeInsets = UIEdgeInsetsZero;
    editBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;

    // Compute a fixed width that can accommodate both states to avoid layout jumps
    CGFloat fixedWidth = [self preferredEditButtonWidthForFont:editBtn.titleLabel.font edgeInsets:editBtn.contentEdgeInsets];
    self.editButtonFixedWidth = fixedWidth;
    CGRect ebf = CGRectZero;
    ebf.size.height = 32;
    ebf.size.width = fixedWidth;
    editBtn.frame = ebf;
    
    // Color #007AFF
    UIColor *blueColor = [UIColor colorWithRed:0.0 green:122.0/255.0 blue:1.0 alpha:1.0];
    if (@available(iOS 13.0, *)) {
        blueColor = [UIColor systemBlueColor];
    }
    [editBtn setTitleColor:blueColor forState:UIControlStateNormal];

    [editBtn addTarget:self action:@selector(onToggleEdit) forControlEvents:UIControlEventTouchUpInside];
    self.editButton = editBtn;
    self.editItem = [[UIBarButtonItem alloc] initWithCustomView:editBtn];
    self.editItem.enabled = NO;
    self.navigationItem.rightBarButtonItems = @[self.editItem];
}

- (void)setupWebView
{
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *uc = [[WKUserContentController alloc] init];
    self.weakBridgeHandler = [[SeafWeakScriptMessageHandler alloc] initWithTarget:self];
    [uc addScriptMessageHandler:self.weakBridgeHandler name:@"callAndroidFunction"];
    [self injectBridgeScriptsIntoUserContentController:uc];
    config.userContentController = uc;

    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.backgroundColor = [UIColor whiteColor];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(iOS 11.0, *)) {
        self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    [self.view addSubview:self.webView];

    NSLayoutYAxisAnchor *topAnchor = nil;
    if (@available(iOS 11.0, *)) {
        topAnchor = self.view.safeAreaLayoutGuide.topAnchor;
    } else {
        topAnchor = self.topLayoutGuide.bottomAnchor;
    }
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.topAnchor constraintEqualToAnchor:topAnchor]
    ]];
    // By default the WebView bottom follows the safe area bottom to avoid being covered by the home indicator
    [self updateWebViewBottomConstraintWithAnchor:[self contentBottomAnchor] constant:0];
    if (self.webViewBottomConstraint) {
        [constraints addObject:self.webViewBottomConstraint];
    }
    [NSLayoutConstraint activateConstraints:constraints];

    self.callbackQueue = [NSMutableArray array];
}

- (void)injectBridgeScriptsIntoUserContentController:(WKUserContentController *)controller
{
    NSArray<NSString *> *baseScripts = @[kSeafBridgeShimScript, kSeafBridgeHelperScript];
    for (NSString *source in baseScripts) {
        WKUserScript *script = [[WKUserScript alloc] initWithSource:source injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
        [controller addUserScript:script];
    }
}

- (void)updateWebViewBottomConstraintWithAnchor:(NSLayoutYAxisAnchor *)anchor constant:(CGFloat)constant
{
    if (!self.webView) return;
    if (self.webViewBottomConstraint) {
        self.webViewBottomConstraint.active = NO;
    }
    self.webViewBottomConstraint = [self.webView.bottomAnchor constraintEqualToAnchor:anchor constant:constant];
    self.webViewBottomConstraint.active = YES;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self stopEditTimeout];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (void)onTapBack
{
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - Bottom Toolbar (Visual)

- (UIButton *)makeBottomIconButtonWithImage:(UIImage *)image
{
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tintColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0];
    [btn setImage:image forState:UIControlStateNormal];
    btn.contentEdgeInsets = UIEdgeInsetsZero;
    btn.imageEdgeInsets = UIEdgeInsetsZero;
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    btn.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    return btn;
}

- (UIImage *)symbolImageNamed:(NSString *)name fallback:(UIImage *)fallback
{
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightRegular];
        UIImage *img = [UIImage systemImageNamed:name withConfiguration:cfg];
        if (img) return img;
    }
    return fallback;
}

- (void)setupBottomToolbar
{
    if (self.bottomBar) return;

    UIView *bar = [[UIView alloc] initWithFrame:CGRectZero];
    bar.backgroundColor = [UIColor whiteColor];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];
    self.bottomBar = bar;
    // Top divider inside bar
    UIView *divider = [[UIView alloc] initWithFrame:CGRectZero];
    divider.backgroundColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1.0];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:divider];
    self.bottomDivider = divider;

    // Build buttons via config array
    UIImage *outlineImg = [[UIImage imageNamed:@"outline"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImage *infoImg = [[UIImage imageNamed:@"attribute"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImage *commentImg = [[UIImage imageNamed:@"comment"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

    NSArray<NSDictionary *> *items = @[
        @{ @"img": outlineImg ?: [NSNull null], @"sel": NSStringFromSelector(@selector(onBottomOutlineTapped)) },
        @{ @"img": infoImg ?: [NSNull null],    @"sel": NSStringFromSelector(@selector(onBottomProfileTapped)) },
        @{ @"img": commentImg ?: [NSNull null], @"sel": NSStringFromSelector(@selector(onBottomCommentTapped)) }
    ];

    NSMutableArray<UIButton *> *buttons = [NSMutableArray arrayWithCapacity:items.count];
    for (NSDictionary *it in items) {
        UIImage *img = ([it[@"img"] isKindOfClass:[UIImage class]] ? it[@"img"] : nil);
        UIButton *btn = [self makeBottomIconButtonWithImage:img];
        SEL action = NSSelectorFromString(it[@"sel"] ?: @"");
        if (action) {
            [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        }
        [buttons addObject:btn];
    }
    self.btnOutline = buttons.count > 0 ? buttons[0] : nil;
    self.btnProfile = buttons.count > 1 ? buttons[1] : nil;
    self.btnComment = buttons.count > 2 ? buttons[2] : nil;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:stack];
    self.bottomStack = stack;

    CGFloat dividerHeight = 1.0 / [UIScreen mainScreen].scale;
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];
    [constraints addObjectsFromArray:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [divider.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [divider.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [divider.topAnchor constraintEqualToAnchor:bar.topAnchor],
        [divider.heightAnchor constraintEqualToConstant:dividerHeight],
        [stack.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:divider.bottomAnchor]
    ]];
    [constraints addObject:[stack.heightAnchor constraintEqualToConstant:36.0]];
    self.bottomBarHeightConstraint = [bar.heightAnchor constraintEqualToConstant:36.0 + [self currentSafeAreaBottomInset]];
    [constraints addObject:self.bottomBarHeightConstraint];
    [NSLayoutConstraint activateConstraints:constraints];

    [self updateWebViewBottomConstraintWithAnchor:bar.topAnchor constant:0];
    [self refreshBottomBarHeight];
}

#pragma mark - Editor Toolbar

- (void)setupEditorToolbar
{
    if (self.editorToolbar) return;
    
    self.editorToolbar = [[SeafSdocEditorToolbar alloc] initWithFrame:CGRectZero];
    self.editorToolbar.delegate = self;
    self.editorToolbar.translatesAutoresizingMaskIntoConstraints = NO;
    self.editorToolbar.hidden = YES;
    [self.view addSubview:self.editorToolbar];
    
    CGFloat height = 40.0;
    NSLayoutConstraint *bottomC = [self.editorToolbar.bottomAnchor constraintEqualToAnchor:[self contentBottomAnchor]];
    self.editorBarBottomConstraint = bottomC;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.editorToolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.editorToolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        bottomC,
        [self.editorToolbar.heightAnchor constraintEqualToConstant:height]
    ]];
}

#pragma mark - Editor Actions

- (void)triggerJsSdocEditorMenu:(NSString *)type
{
    NSDictionary *payload = @{@"type": type};
    [self callJsFunction:@"sdoc.toolbar.menu.trigger" payload:payload completion:^(NSString * _Nullable data) {
        [self updateUndoRedoState];
    }];
}

#pragma mark - SeafSdocEditorToolbarDelegate

- (void)editorToolbarDidTapUndo { [self triggerJsSdocEditorMenu:@"undo"]; }
- (void)editorToolbarDidTapRedo { [self triggerJsSdocEditorMenu:@"redo"]; }
- (void)editorToolbarDidTapUnorderedList { [self triggerJsSdocEditorMenu:@"unordered_list"]; }
- (void)editorToolbarDidTapOrderedList { [self triggerJsSdocEditorMenu:@"ordered_list"]; }
- (void)editorToolbarDidTapCheckList { [self triggerJsSdocEditorMenu:@"check_list_item"]; }
- (void)editorToolbarDidTapKeyboard { [self.view endEditing:YES]; }

- (void)editorToolbarDidTapStyle:(UIButton *)sender
{
    SeafSdocStylePopupViewController *popupVC = [[SeafSdocStylePopupViewController alloc] init];
    popupVC.delegate = self;
    popupVC.currentStyle = self.currentStyleType ?: @"paragraph";
    
    popupVC.modalPresentationStyle = UIModalPresentationPopover;
    UIPopoverPresentationController *popover = popupVC.popoverPresentationController;
    if (popover) {
        popover.sourceView = sender;
        popover.sourceRect = sender.bounds;
        popover.permittedArrowDirections = UIPopoverArrowDirectionDown | UIPopoverArrowDirectionUp;
        popover.delegate = (id<UIPopoverPresentationControllerDelegate>)self;
        popover.backgroundColor = [UIColor whiteColor];
    }
    
    [self presentViewController:popupVC animated:YES completion:nil];
}

#pragma mark - SeafSdocStylePopupDelegate

- (void)didSelectStyle:(NSString *)style {
    [self triggerJsSdocEditorMenu:style];
}

#pragma mark - UIPopoverPresentationControllerDelegate

- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller {
    return UIModalPresentationNone;
}

- (void)updateEditorBarStateWithModel:(NSDictionary *)model
{
    [self.editorToolbar updateWithStyleModel:model];
    
    // Save current style type for style popup
    NSString *type = model[@"type"];
    if (type) {
        self.currentStyleType = type;
    }
}

- (void)updateUndoRedoState
{
    NSString *js = @"(function(){if(window.seadroid&&window.seadroid.history){return JSON.stringify(window.seadroid.history);}else{return null;}})();";
    [self.webView evaluateJavaScript:js completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        NSString *val = [self normalizedJSONStringFromEvaluateResult:result];
        if (val.length > 0) {
            NSData *d = [val dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *history = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            if ([history isKindOfClass:[NSDictionary class]]) {
                NSArray *undos = history[@"undos"];
                NSArray *redos = history[@"redos"];
                BOOL canUndo = (undos && undos.count > 0);
                BOOL canRedo = (redos && redos.count > 0);
                [self.editorToolbar updateUndoEnabled:canUndo redoEnabled:canRedo];
            }
        }
    }];
}

- (void)presentSheetViewController:(UIViewController *)vc
{
    if (!vc) return;
    if (@available(iOS 15.0, *)) {
        vc.modalPresentationStyle = UIModalPresentationPageSheet;
        UISheetPresentationController *sheet = vc.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
            sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
            sheet.prefersGrabberVisible = YES;
            sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
            sheet.largestUndimmedDetentIdentifier = nil;
        }
        vc.modalInPresentation = NO;
        [self presentViewController:vc animated:YES completion:nil];
    } else {
        vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
        [self presentViewController:vc animated:NO completion:nil];
    }
}

- (void)presentOutlineViewController:(SeafSDocOutlineSheetViewController *)vc
{
    if (!vc) return;
    // On iPad, present outline as a popover anchored to the outline button for better UX
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        vc.modalPresentationStyle = UIModalPresentationPopover;
        UIPopoverPresentationController *popover = vc.popoverPresentationController;
        UIView *sourceView = self.btnOutline ?: self.bottomBar ?: self.view;
        popover.sourceView = sourceView;
        CGRect sourceRect = CGRectZero;
        if (self.btnOutline) {
            sourceRect = self.btnOutline.bounds;
        } else if (self.bottomBar) {
            CGFloat midX = CGRectGetMidX(self.bottomBar.bounds);
            CGFloat maxY = CGRectGetMaxY(self.bottomBar.bounds);
            sourceRect = CGRectMake(midX, maxY, 1, 1);
        } else {
            CGFloat midX = CGRectGetMidX(self.view.bounds);
            CGFloat maxY = CGRectGetMaxY(self.view.bounds);
            sourceRect = CGRectMake(midX, maxY, 1, 1);
        }
        popover.sourceRect = sourceRect;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
        if (@available(iOS 13.0, *)) {
            popover.backgroundColor = [UIColor systemBackgroundColor];
        }
        [self presentViewController:vc animated:YES completion:nil];
    } else {
        [self presentSheetViewController:vc];
    }
}

- (BOOL)ensureEditModeAndEndEditing
{
    if (!self.nextEditMode) {
        [self onToggleEdit];
    }
    [self.view endEditing:YES];
    return YES;
}
- (void)onBottomProfileTapped
{
    [self ensureEditModeAndEndEditing];
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Loading...", nil)];
    SeafSdocService *service = [[SeafSdocService alloc] initWithConnection:self.file.connection];
    NSString *repoId = self.file.repoId ?: @"";
    NSString *path = self.file.path ?: @"";

    __weak typeof(self) wself = self;
    [service fetchFileProfileAggregateWithRepoId:repoId path:path completion:^(id agg, NSError *error) {
        __strong typeof(wself) sself = wself; if (!sself) return;
        NSDictionary *aggregate = nil;
        if (agg) {
            aggregate = @{
                @"fileDetail": [agg valueForKey:@"fileDetail"] ?: @{},
                @"metadataConfig": [agg valueForKey:@"metadataConfig"] ?: @{},
                @"recordWrapper": [agg valueForKey:@"recordWrapper"] ?: @{},
                @"relatedUsers": [agg valueForKey:@"relatedUsers"] ?: @{},
                @"tagWrapper": [agg valueForKey:@"tagWrapper"] ?: @{}
            };
        } else {
            aggregate = @{};
        }
        NSArray *rows = [SeafSdocProfileAssembler buildRowsFromAggregate:aggregate];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error && rows.count > 0) {
                SeafSdocProfileSheetViewController *vc = [[SeafSdocProfileSheetViewController alloc] initWithRows:rows];
                [sself presentSheetViewController:vc];
                // Dismiss SVProgressHUD one frame after the presentation completes
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD dismiss];
                });
            } else {
                [SVProgressHUD dismiss];
                NSString *msg = error.localizedDescription ?: NSLocalizedString(@"Unknown error", nil);
                [sself showToast:msg];
            }
        });
    }];
}

// Profile loading overlay removed; using SVProgressHUD instead


- (void)onBottomOutlineTapped
{
    [self ensureEditModeAndEndEditing];

    __weak typeof(self) wself = self;
    [self readOutlinesWithCompletion:^(NSArray<OutlineItemModel *> *items) {
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        SeafSDocOutlineSheetViewController *vc = [[SeafSDocOutlineSheetViewController alloc] initWithItems:items origin:sself.outlineOriginArray];
        vc.onSelect = ^(NSDictionary * _Nullable payload, NSUInteger index, OutlineItemModel * _Nonnull item) {
            if (payload && [payload isKindOfClass:[NSDictionary class]]) {
                NSDictionary *finalPayload = payload;
                NSString *payloadText = [[payload objectForKey:@"text"] isKindOfClass:[NSString class]] ? [payload objectForKey:@"text"] : @"";
                if (item.text.length > 0 && ![payloadText isEqualToString:item.text]) {
                    NSMutableDictionary *md = [payload mutableCopy];
                    if (!md) md = [NSMutableDictionary dictionary];
                    [md setObject:item.text forKey:@"text"];
                    finalPayload = md.copy;
                }
                [sself callJsFunction:@"sdoc.outline.data.select" payload:finalPayload completion:^(NSString * _Nullable data) { }];
            } else {
                [sself selectOutlineAtIndex:index];
            }
        };
        [sself presentOutlineViewController:vc];
    }];
}

- (void)onBottomCommentTapped
{
    [self ensureEditModeAndEndEditing];

    __weak typeof(self) wself = self;
    [self readPageOptionsEnsuringWithCompletion:^(BOOL ok) {
        __strong typeof(wself) sself = wself; if (!sself) return;
        if (ok) {
            SeafSdocCommentsViewController *vc = [SeafSdocCommentsViewController new];
            vc.pageOptions = sself.pageOptions;
            vc.docDisplayName = sself.navigationItem.title;
            vc.connection = sself.file.connection;
            vc.repoId = sself.file.repoId;
            vc.latestContributor = sself.pageOptions.latestContributor ?: @"";
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;
            [sself presentViewController:nav animated:YES completion:nil];
        } else {
            [sself showToast:NSLocalizedString(@"Unknown error", nil)];
        }
    }];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    if (!self.webView) return;
    UIEdgeInsets contentInset = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        [self refreshBottomBarHeight];
    }
    self.webView.scrollView.contentInset = contentInset;
    self.webView.scrollView.scrollIndicatorInsets = contentInset;
}

- (void)viewSafeAreaInsetsDidChange
{
    [super viewSafeAreaInsetsDidChange];
    [self refreshBottomBarHeight];
}

- (void)setupUserAgentAndLoad
{
    __weak typeof(self) wself = self;
    [self.webView evaluateJavaScript:@"navigator.userAgent" completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        NSString *ua = ([result isKindOfClass:[NSString class]]) ? (NSString *)result : nil;
        NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"";
        NSString *suffix = [NSString stringWithFormat:@" Seafile iOS/%@", appVersion.length > 0 ? appVersion : @"unknown"];
        if (ua && [ua isKindOfClass:[NSString class]]) {
            if ([ua rangeOfString:suffix].location == NSNotFound) {
                sself.webView.customUserAgent = [ua stringByAppendingString:suffix];
            } else {
                sself.webView.customUserAgent = ua; // already appended
            }
        } else {
            sself.webView.customUserAgent = suffix;
        }
        [sself loadSdocPage];
    }];
}

- (void)dealloc
{
    self.webView.navigationDelegate = nil;
    [self stopEditTimeout];
    WKUserContentController *uc = self.webView.configuration.userContentController;
    if (uc) {
        [uc removeScriptMessageHandlerForName:@"callAndroidFunction"];
    }
}

#pragma mark - Loading
- (void)loadSdocPage
{
    if (![_file isWebOpenFile]) return;
    NSString *urlString = [_file getWebViewURLString];
    if (urlString.length == 0) return;
    // One-shot cookie cleanup after account switch to avoid stale Seahub session
    NSString *clearHost = [[NSUserDefaults standardUserDefaults] objectForKey:@"SEAF_COOKIE_CLEAR_HOST"];
    NSString *currentHost = [NSURL URLWithString:_file.connection.address].host;
    if (clearHost.length > 0 && currentHost.length > 0 && [clearHost isEqualToString:currentHost]) {
        if (@available(iOS 11.0, *)) {
            WKHTTPCookieStore *store = WKWebsiteDataStore.defaultDataStore.httpCookieStore;
            [store getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
                for (NSHTTPCookie *c in cookies) {
                    if ([c.domain containsString:currentHost]) {
                        [store deleteCookie:c completionHandler:nil];
                    }
                }
            }];
        }
        NSHTTPCookieStorage *cookieStorage = NSHTTPCookieStorage.sharedHTTPCookieStorage;
        for (NSHTTPCookie *each in cookieStorage.cookies) {
            if ([each.domain containsString:currentHost]) {
                [cookieStorage deleteCookie:each];
            }
        }
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SEAF_COOKIE_CLEAR_HOST"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    NSURLRequest *req = [_file.connection buildRequest:urlString method:@"GET" form:nil];
    [self.webView loadRequest:req];
}

#pragma mark - Edit Toggle

- (CGFloat)preferredEditButtonWidthForFont:(UIFont *)font edgeInsets:(UIEdgeInsets)insets
{
    NSString *t1 = NSLocalizedString(@"Edit", nil);
    NSString *t2 = NSLocalizedString(@"Done", nil);
    UIFont *f = font ?: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    CGFloat w1 = [t1 sizeWithAttributes:@{ NSFontAttributeName: f }].width;
    CGFloat w2 = [t2 sizeWithAttributes:@{ NSFontAttributeName: f }].width;
    CGFloat textWidth = MAX(w1, w2);
    CGFloat total = ceil(textWidth) + insets.left + insets.right;
    CGFloat minW = 60.0;
    CGFloat maxW = 100.0;
    return MIN(MAX(total, minW), maxW);
}

- (void)onToggleEdit
{
    [self startEditTimeout];
    NSString *payload = self.nextEditMode ? @"{\"edit\": true}" : @"{\"edit\": false}";
    [self callJsFunction:@"sdoc.editor.data.edit" payload:(id)payload completion:^(NSString * _Nullable data){
        [self stopEditTimeout];
        if (data.length == 0) return;
        if ([data rangeOfString:@"success" options:NSCaseInsensitiveSearch].location == NSNotFound) return;
        if ([data rangeOfString:@"true" options:NSCaseInsensitiveSearch].location == NSNotFound) return;
        self.nextEditMode = !self.nextEditMode;
        BOOL isEditing = !self.nextEditMode; // nextEditMode == NO means we are currently in editing mode
        self.isEditing = isEditing;

        // When first entering edit mode, disable undo/redo by default to avoid incorrect button states; then asynchronously sync the actual state from JS
        if (isEditing && self.editorToolbar) {
            [self.editorToolbar updateUndoEnabled:NO redoEnabled:NO];
            [self updateUndoRedoState];
        }

        NSString *newTitle = self.nextEditMode ? NSLocalizedString(@"Edit", nil) : NSLocalizedString(@"Done", nil);
        [self updateBottomBarForEditing:isEditing];
        [self updateEditButtonWithTitle:newTitle];
    }];
}

- (void)updateEditButtonWithTitle:(NSString *)title
{
    if (!self.editButton) return;
    [UIView performWithoutAnimation:^{
        [self.editButton setTitle:title forState:UIControlStateNormal];
        
        // Always #007AFF
        UIColor *blueColor = [UIColor colorWithRed:0.0 green:122.0/255.0 blue:1.0 alpha:1.0];
        if (@available(iOS 13.0, *)) {
            blueColor = [UIColor systemBlueColor];
        }
        [self.editButton setTitleColor:blueColor forState:UIControlStateNormal];
        
        [self.editButton layoutIfNeeded];
    }];
    CGRect f = self.editButton.frame;
    f.size.height = 32;
    f.size.width = (self.editButtonFixedWidth > 0 ? self.editButtonFixedWidth : f.size.width);
    self.editButton.frame = f;
}

- (void)startEditTimeout
{
    [self stopEditTimeout];
    __weak typeof(self) wself = self;
    self.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:NO block:^(NSTimer * _){
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        [sself showToast:NSLocalizedString(@"Not supported feature", nil)];
    }];
}

- (void)stopEditTimeout
{
    [self.timeoutTimer invalidate];
    self.timeoutTimer = nil;
}

#pragma mark - JS Bridge
- (void)callJsFunction:(NSString *)action payload:(id)payload completion:(SeafJSCallback)completion
{
    if (action.length == 0 || !self.webView) {
        if (completion) completion(nil);
        return;
    }

    NSString *payloadString = nil;
    if ([payload isKindOfClass:[NSString class]]) {
        payloadString = (NSString *)payload;
    } else if (payload) {
        payloadString = [self jsonStringFromObject:payload];
    }
    if (payloadString.length == 0) {
        payloadString = @"{}";
    }

    NSDictionary *model = @{ @"action": action ?: @"",
                              @"data": payloadString,
                              @"v": @2 };
    NSString *modelString = [self jsonStringFromObject:model];
    if (modelString.length == 0) {
        if (completion) completion(nil);
        return;
    }

    NSString *escaped = [self escapedJavaScriptString:modelString];
    if (completion) {
        if (!self.callbackQueue) {
            self.callbackQueue = [NSMutableArray array];
        }
        [self.callbackQueue addObject:[completion copy]];
    }

    NSString *js = [NSString stringWithFormat:
                    @"(function(){\n"
                    @"  var d=\"%@\";\n"
                    @"  if(window.WebViewJavascriptBridge && typeof WebViewJavascriptBridge._invoke==='function'){\n"
                    @"    WebViewJavascriptBridge._invoke('callJsFunction', d);\n"
                    @"    return 'OK';\n"
                    @"  }\n"
                    @"  return 'NO_BRIDGE';\n"
                    @"})();",
                    escaped ?: @"" ];
    [self.webView evaluateJavaScript:js completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        if (error) {
            SeafJSCallback callback = [self dequeuePendingCallbackFromFront:NO];
            if (callback) callback(nil);
            return;
        }
        if ([result isKindOfClass:[NSString class]] && [(NSString *)result isEqualToString:@"NO_BRIDGE"]) {
            SeafJSCallback callback = [self dequeuePendingCallbackFromFront:NO];
            if (callback) callback(nil);
        }
    }];
}

- (void)readPageOptionsIfNeeded
{
    [self readPageOptionsEnsuringWithCompletion:^(BOOL ok){}];
}

- (void)readPageOptionsEnsuringWithCompletion:(void(^)(BOOL ok))completion
{
    if (self.pageOptions && [self.pageOptions canUse]) {
        if (completion) completion(YES);
        return;
    }
    NSString *js = @"(function(){if(window.app&&window.app.pageOptions){return JSON.stringify(window.app.pageOptions);}else{return null;}})();";
    [self.webView evaluateJavaScript:js completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        BOOL ok = NO;
        NSString *value = [self normalizedJSONStringFromEvaluateResult:result];
        if (value.length > 0) {
            self.pageOptions = [SDocPageOptionsModel fromJSONString:value];
            ok = (self.pageOptions && [self.pageOptions canUse]);
        }
        if (completion) completion(ok);
    }];
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    if ([message.name isEqualToString:@"callAndroidFunction"]) {
        if (![message.body isKindOfClass:[NSString class]]) return;
        NSString *data = (NSString *)message.body;
        NSData *d = [data dataUsingEncoding:NSUTF8StringEncoding];
        if (!d) return;
        NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        if (![obj isKindOfClass:[NSDictionary class]]) return;
        NSString *action = obj[@"action"];
        id payload = obj[@"data"];
        
        // Handle JS callback (iOS → JS → iOS response)
        if ([action isEqualToString:@"N_N_N_N_Callback"]) {
            NSString *text = [payload isKindOfClass:[NSString class]] ? (NSString *)payload : nil;
            SeafJSCallback callback = [self dequeuePendingCallbackFromFront:YES];
            if (callback) {
                callback(text);
            }
            return;
        }
        
        if ([action isEqualToString:@"app.version.get"]) {
            NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"";
            [self sendBridgeCallback:version];
        } else if ([action isEqualToString:@"app.toast.show"]) {
            if ([payload isKindOfClass:[NSString class]]) [self showToast:(NSString *)payload];
        } else if ([action isEqualToString:@"page.finish"]) {
        } else if ([action isEqualToString:@"page.status.height.get"]) {
            CGFloat h = UIApplication.sharedApplication.statusBarFrame.size.height;
            [self sendBridgeCallback:[@(h) stringValue]];
        } else if ([action isEqualToString:@"sdoc.editor.content.select"]) {
            // Handle selection change
            if ([payload isKindOfClass:[NSString class]]) {
                NSData *pd = [(NSString *)payload dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:pd options:0 error:nil];
                if (dict) [self updateEditorBarStateWithModel:dict];
            } else if ([payload isKindOfClass:[NSDictionary class]]) {
                 [self updateEditorBarStateWithModel:(NSDictionary *)payload];
            }
        } else if ([action isEqualToString:@"sdoc.editor.operation.execute"]) {
            [self updateUndoRedoState];
        } else if ([action isEqualToString:@"sdoc.editor.system.event"]) {
            if ([payload isKindOfClass:[NSDictionary class]] || [payload isKindOfClass:[NSString class]]) {
                NSDictionary *dict = nil;
                if ([payload isKindOfClass:[NSString class]]) {
                    NSData *pd = [(NSString *)payload dataUsingEncoding:NSUTF8StringEncoding];
                    dict = [NSJSONSerialization JSONObjectWithData:pd options:0 error:nil];
                } else {
                    dict = (NSDictionary *)payload;
                }
                
                if (dict) {
                    NSString *eventType = dict[@"type"];
                    [self handleSdocSystemEvent:eventType];
                }
            }
        }
    }
}

- (void)handleSdocSystemEvent:(NSString *)event
{
    if (!event) return;
    // Android maps these events to UI updates (Toolbar status text) or Toasts
    
    if ([event isEqualToString:@"document_is_saved"]) {
        [self updateNavigationTitleWithStatus:NSLocalizedString(@"Saved", nil) isTemporary:YES];
    } else if ([event isEqualToString:@"document_is_saving"]) {
        [self updateNavigationTitleWithStatus:NSLocalizedString(@"Saving", nil) isTemporary:NO];
    } else if ([event isEqualToString:@"server_is_reconnected"]) {
         [self updateNavigationTitleWithStatus:NSLocalizedString(@"Reconnected", nil) isTemporary:YES];
    } else if ([event isEqualToString:@"server_is_disconnected_reconnecting"]) {
         [self updateNavigationTitleWithStatus:NSLocalizedString(@"Reconnecting", nil) isTemporary:NO];
    } else if ([event isEqualToString:@"token_expired_Please_refresh_the_page"] ||
               [event isEqualToString:@"internal_server_exec_operations_error"] ||
               [event isEqualToString:@"failed_to_sync_with_server_operations"] ||
               [event isEqualToString:@"failed_to_execute_operation_on_server"]) {
         [self showToast:NSLocalizedString(@"Server error, please refresh", nil)];
         [self updateNavigationTitleWithStatus:@"" isTemporary:NO];
    }
}

- (void)updateNavigationTitleWithStatus:(NSString *)status isTemporary:(BOOL)temp
{
    if (self.statusLabel) {
        self.statusLabel.text = status;
        if (temp) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if ([self.statusLabel.text isEqualToString:status]) {
                    self.statusLabel.text = @"";
                }
            });
        }
    }
}

- (void)sendBridgeCallback:(NSString *)text
{
}

- (SeafJSCallback)dequeuePendingCallbackFromFront:(BOOL)front
{
    if (self.callbackQueue.count == 0) return nil;
    NSUInteger index = front ? 0 : self.callbackQueue.count - 1;
    SeafJSCallback callback = self.callbackQueue[index];
    [self.callbackQueue removeObjectAtIndex:index];
    return callback;
}

 

- (NSString *)jsonStringFromObject:(id)object
{
    if (!object) return nil;
    if ([object isKindOfClass:[NSNumber class]]) {
        const char *ctype = [(NSNumber *)object objCType];
        if (ctype && strcmp(ctype, @encode(BOOL)) == 0) {
            return [(NSNumber *)object boolValue] ? @"true" : @"false";
        }
        return [(NSNumber *)object stringValue];
    }
    if (![NSJSONSerialization isValidJSONObject:object]) {
        return nil;
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (error || !data) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSString *)escapedJavaScriptString:(NSString *)string
{
    if (string.length == 0) return @"";
    NSMutableString *escaped = [string mutableCopy];
    [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, escaped.length)];
    return escaped;
}

- (NSString *)normalizedJSONStringFromEvaluateResult:(id)result
{
    if (![result isKindOfClass:[NSString class]]) return nil;
    NSString *value = (NSString *)result;
    if (value.length >= 2 && [value hasPrefix:@"\""] && [value hasSuffix:@"\""]) {
        value = [value substringWithRange:NSMakeRange(1, value.length - 2)];
        value = [value stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
        value = [value stringByReplacingOccurrencesOfString:@"\\\\" withString:@"\\"];
    }
    return value;
}

- (CGFloat)currentSafeAreaBottomInset
{
    if (@available(iOS 11.0, *)) {
        return self.view.safeAreaInsets.bottom;
    }
    return 0;
}

- (NSLayoutYAxisAnchor *)contentBottomAnchor
{
    if (@available(iOS 11.0, *)) {
        return self.view.safeAreaLayoutGuide.bottomAnchor;
    } else {
        return self.bottomLayoutGuide.topAnchor;
    }
}

- (void)applyKeyboardHeight:(CGFloat)keyboardHeight duration:(NSTimeInterval)duration curve:(UIViewAnimationCurve)curve
{
    self.keyboardVisibleHeight = keyboardHeight;
    
    if (!self.isEditing) {
        // Only in editing mode do we lift the page to sit above the keyboard
        return;
    }
    // Update Editor Bar Constraint: it should sit on top of keyboard
    CGFloat safeBottom = [self currentSafeAreaBottomInset];
    CGFloat offset = 0;
    if (keyboardHeight > 0) {
        offset = -(keyboardHeight - safeBottom);
    }
    self.editorBarBottomConstraint.constant = offset;
    
    CGFloat webPaddingBottom = MAX(0.0, keyboardHeight - safeBottom) + 40.0 + 10.0;
    if (keyboardHeight <= 0) {
        webPaddingBottom = 0;
    }

    UIViewAnimationOptions options = (UIViewAnimationOptions)(curve << 16);
    options |= UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    [UIView animateWithDuration:duration delay:0 options:options animations:^{
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        if (finished) {
            [self updateWebPaddingAndScroll:webPaddingBottom];
        }
    }];
}

- (void)updateWebPaddingAndScroll:(CGFloat)padding {
    NSDictionary *payload = @{@"height": @(padding)};
    [self callJsFunction:@"sdoc.keyboard.height.change" payload:payload completion:nil];
}

- (void)onKeyboardWillChangeFrame:(NSNotification *)note
{
    NSDictionary *userInfo = note.userInfo;
    if (!userInfo) return;
    CGRect endFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect endInView = [self.view convertRect:endFrame fromView:nil];

    // Compute effective keyboard overlap height relative to the view (excluding bottom safe area)
    CGFloat viewBottom = CGRectGetMaxY(self.view.bounds);
    CGFloat overlap = MAX(0.0, viewBottom - CGRectGetMinY(endInView));
    
    // We pass full overlap height to helper
    CGFloat keyboardHeight = overlap;

    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = (UIViewAnimationCurve)[userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    [self applyKeyboardHeight:keyboardHeight duration:duration curve:curve];
}

- (void)onKeyboardWillHide:(NSNotification *)note
{
    NSDictionary *userInfo = note.userInfo;
    if (!userInfo) return;
    self.keyboardVisibleHeight = 0;
    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = (UIViewAnimationCurve)[userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    [self applyKeyboardHeight:0 duration:duration curve:curve];
}

- (void)refreshBottomBarHeight
{
    if (!self.bottomBarHeightConstraint) return;
    self.bottomBarHeightConstraint.constant = 36.0 + [self currentSafeAreaBottomInset];
}

- (void)updateBottomBarForEditing:(BOOL)isEditing
{
    if (!self.bottomBar) return;
    CGFloat barHeight = self.bottomBarHeightConstraint.constant;

    // If the bar is already in the target state, just ensure constraints are correct (no animation)
    if (isEditing && self.bottomBar.hidden) {
        [self.bottomBar setTransform:CGAffineTransformMakeTranslation(0, barHeight)];
        self.editorToolbar.hidden = NO;
        self.bottomBar.hidden = YES;
        [self.view layoutIfNeeded];
        return;
    }
    if (!isEditing && !self.bottomBar.hidden && CGAffineTransformIsIdentity(self.bottomBar.transform)) {
        self.editorToolbar.hidden = YES;
        [self updateWebViewBottomConstraintWithAnchor:self.bottomBar.topAnchor constant:0];
        [self.view layoutIfNeeded];
        return;
    }

    if (isEditing) {
        self.editorToolbar.hidden = NO;
        self.editorToolbar.alpha = 0.0;
        
        self.editorBarBottomConstraint.constant = 0;
        [self updateWebViewBottomConstraintWithAnchor:[self contentBottomAnchor] constant:0];
        [self updateWebPaddingAndScroll:0];
        
        [UIView animateWithDuration:0.25 animations:^{
            self.bottomBar.transform = CGAffineTransformMakeTranslation(0, barHeight);
            self.editorToolbar.alpha = 1.0;
            self.view.backgroundColor = [UIColor colorWithRed:242.0/255.0 green:242.0/255.0 blue:242.0/255.0 alpha:1.0];
            [self.view layoutIfNeeded];
        } completion:^(BOOL finished) {
            self.bottomBar.hidden = YES;
        }];
    } else {
        [self.view endEditing:YES];
        
        self.bottomBar.hidden = NO;
        self.bottomBar.transform = CGAffineTransformMakeTranslation(0, barHeight);
        
        self.editorBarBottomConstraint.constant = 0;
        
        [UIView animateWithDuration:0.25 animations:^{
            self.bottomBar.transform = CGAffineTransformIdentity;
            self.editorToolbar.alpha = 0.0;
            self.view.backgroundColor = [UIColor whiteColor];
            
            [self updateWebPaddingAndScroll:0];
            [self.view layoutIfNeeded];
        } completion:^(BOOL finished) {
             self.editorToolbar.hidden = YES;
             [self updateWebViewBottomConstraintWithAnchor:self.bottomBar.topAnchor constant:0];
        }];
    }
}

#pragma mark - WKNavigationDelegate
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    self.editItem.enabled = YES;
    [self readPageOptionsIfNeeded];
    NSString *initTitle = self.nextEditMode ? NSLocalizedString(@"Edit", nil) : NSLocalizedString(@"Done", nil);
    // Initial state is typically non-editing, ensure bottom bar is visible
    [self updateBottomBarForEditing:!self.nextEditMode ? YES : NO];
    [self updateEditButtonWithTitle:initTitle];
}

// removed empty delegate stubs: didFailNavigation / didFailProvisionalNavigation

- (void)readOutlinesWithCompletion:(void(^)(NSArray<OutlineItemModel *> *items))completion
{
    NSString *js = @"(function(){if(window.seadroid&&window.seadroid.outlines){return JSON.stringify(window.seadroid.outlines);}else{return null;}})();";
    [self.webView evaluateJavaScript:js completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        NSString *value = [self normalizedJSONStringFromEvaluateResult:result];
        if (value.length == 0) { if (completion) completion(@[]); return; }
        // keep origin array for callback payload
        NSData *originData = [value dataUsingEncoding:NSUTF8StringEncoding];
        id origin = originData ? [NSJSONSerialization JSONObjectWithData:originData options:0 error:nil] : nil;
        if ([origin isKindOfClass:[NSArray class]]) {
            self.outlineOriginArray = (NSArray *)origin;
        } else {
            self.outlineOriginArray = @[];
        }
        NSArray<OutlineItemModel *> *items = [OutlineItemModel arrayFromJSONString:value];
        if (completion) completion(items ?: @[]);
    }];
}

 

- (void)selectOutlineAtIndex:(NSUInteger)index
{
    if (index >= self.outlineOriginArray.count) return;
    id obj = self.outlineOriginArray[index];
    if (![obj isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *payload = (NSDictionary *)obj;
    [self callJsFunction:@"sdoc.outline.data.select" payload:payload completion:^(NSString * _Nullable data) {
        // no-op
    }];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURL *originalURL = navigationAction.request.URL;
    NSString *abs = originalURL.absoluteString ?: @"";
    if ([_file isWebOpenFile]) {
        if ([abs containsString:@"login/?next"] && ![abs containsString:@"mobile-login/?next"]) {
            decisionHandler(WKNavigationActionPolicyCancel);
            NSString *webViewURLString = [_file getWebViewURLString];
            NSString *mobileLoginURLString = [NSString stringWithFormat:@"%@/mobile-login/?next=%@", _file.connection.address, webViewURLString];
            NSURLRequest *urlRequest = [_file.connection buildRequest:mobileLoginURLString method:@"GET" form:nil];
            [webView loadRequest:urlRequest];
            return;
        }
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

#pragma mark - Helpers
- (void)showToast:(NSString *)text
{
    if (text.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil message:text preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:ac animated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [ac dismissViewControllerAnimated:YES completion:nil];
        });
    });
}

@end
