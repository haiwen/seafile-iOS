//
//  SeafDestinationPickerViewController.m
//  seafile
//
//  A wrapper controller that provides the new UI shell (title with filename,
//  segmented control, and bottom action bar) while embedding the existing
//  SeafDirViewController for browsing directories.
//

#import "SeafDestinationPickerViewController.h"
#import "SeafDirViewController.h"
#import "SeafRepos.h"
#import "SeafAppDelegate.h"
#import "SeafGlobal.h"
#import "SeafRecentDirsStore.h"
#import "SeafCell.h"
#import "SeafDestCell.h"
#import "SeafFileOperationManager.h"
#import "ExtentedString.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "Debug.h"
#import "SeafDateFormatter.h"

typedef NS_ENUM(NSInteger, SeafDestSegment) {
    SeafDestSegmentCurrent = 0,
    SeafDestSegmentOthers  = 1,
    SeafDestSegmentRecent  = 2,
};

@interface SeafDestinationPickerViewController ()<UITableViewDataSource, UITableViewDelegate, UINavigationControllerDelegate>

@property (nonatomic, strong) SeafConnection *connection;
@property (nonatomic, strong) SeafDir *sourceDirectory;
@property (nonatomic, strong) NSArray<NSString *> *fileNames;

@property (nonatomic, strong) UIView *tabsBar;
@property (nonatomic, strong) NSArray<UIButton *> *tabButtons;
@property (nonatomic, strong) UIView *underlineView;
@property (nonatomic, strong) NSLayoutConstraint *underlineLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *underlineWidthConstraint;

@property (nonatomic, strong) UIView *contentContainerView;
@property (nonatomic, strong) UIView *cardContainerView;
@property (nonatomic, strong) UIView *fixedReturnHeaderView;
@property (nonatomic, strong) NSLayoutConstraint *fixedReturnHeaderHeightConstraint;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIView *listContainerView;
@property (nonatomic, strong) NSLayoutConstraint *listTopConstraint;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *confirmButton;
@property (nonatomic, strong) UILabel *titleLabel;

// Child navigation stack for directory browsing (reusing SeafDirViewController)
@property (nonatomic, strong) UINavigationController *childNavController;
@property (nonatomic, strong) SeafDirViewController *rootDirController;

@property (nonatomic, strong) UITableView *recentTableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *recentData;
@property (nonatomic, assign) SeafDestSegment currentSegment;

@end

@implementation SeafDestinationPickerViewController

- (instancetype)initWithConnection:(SeafConnection *)connection
                   sourceDirectory:(SeafDir *)sourceDirectory
                           delegate:(id<SeafDirDelegate>)delegate
                    operationState:(OperationState)operationState
                          fileNames:(NSArray<NSString *> *)fileNames
{
    if (self = [super initWithNibName:nil bundle:nil]) {
        _connection = connection;
        _sourceDirectory = sourceDirectory;
        _delegate = delegate;
        _operationState = operationState;
        _fileNames = fileNames ?: @[];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = kPrimaryBackgroundColor;

    [self setupNavigationBar];
    [self setupTabsBar];
    [self setupContentContainer];
    [self setupFixedTopReturnHeader];
    [self setupBottomBar];
    self.currentSegment = SeafDestSegmentCurrent;
    [self embedCurrentLibraryBrowser];
    [self updateTitleView];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self logListContainerLayoutWithTag:@"viewDidLayoutSubviews"];
    [self applyRoundedCornersForRecentIfNeeded];
}
- (void)setupFixedTopReturnHeader
{
    // Build a fixed header pinned above the embedded table views
    self.fixedReturnHeaderView = [[UIView alloc] init];
    self.fixedReturnHeaderView.translatesAutoresizingMaskIntoConstraints = NO;
    self.fixedReturnHeaderView.backgroundColor = [UIColor clearColor];
    self.fixedReturnHeaderView.hidden = NO;
    [self.cardContainerView addSubview:self.fixedReturnHeaderView];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"return"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [UIColor systemGrayColor];
    [self.fixedReturnHeaderView addSubview:icon];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = NSLocalizedString(@"Return to previous level", @"Seafile");
    if (@available(iOS 13.0, *)) label.textColor = [UIColor secondaryLabelColor]; else label.textColor = [UIColor grayColor];
    label.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    [self.fixedReturnHeaderView addSubview:label];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapFixedReturnHeader)];
    [self.fixedReturnHeaderView addGestureRecognizer:tap];
    self.fixedReturnHeaderView.isAccessibilityElement = YES;
    self.fixedReturnHeaderView.accessibilityLabel = label.text;

    CGFloat headerH = 44.0;
    self.fixedReturnHeaderHeightConstraint = [self.fixedReturnHeaderView.heightAnchor constraintEqualToConstant:headerH];
    [NSLayoutConstraint activateConstraints:@[
        [self.fixedReturnHeaderView.topAnchor constraintEqualToAnchor:self.cardContainerView.topAnchor],
        [self.fixedReturnHeaderView.leadingAnchor constraintEqualToAnchor:self.cardContainerView.leadingAnchor],
        [self.fixedReturnHeaderView.trailingAnchor constraintEqualToAnchor:self.cardContainerView.trailingAnchor],
        self.fixedReturnHeaderHeightConstraint,

        [icon.leadingAnchor constraintEqualToAnchor:self.fixedReturnHeaderView.leadingAnchor constant:16],
        [icon.centerYAnchor constraintEqualToAnchor:self.fixedReturnHeaderView.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:20],
        [icon.heightAnchor constraintEqualToConstant:20],

        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8],
        [label.centerYAnchor constraintEqualToAnchor:self.fixedReturnHeaderView.centerYAnchor],
        [self.fixedReturnHeaderView.trailingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:8]
    ]];

    // Bottom separator for visual separation from list
    UIView *sep = [[UIView alloc] init];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(iOS 13.0, *)) sep.backgroundColor = [UIColor separatorColor]; else sep.backgroundColor = [UIColor lightGrayColor];
    [self.fixedReturnHeaderView addSubview:sep];
    [NSLayoutConstraint activateConstraints:@[
        [sep.leadingAnchor constraintEqualToAnchor:self.fixedReturnHeaderView.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:self.fixedReturnHeaderView.trailingAnchor],
        [sep.bottomAnchor constraintEqualToAnchor:self.fixedReturnHeaderView.bottomAnchor],
        [sep.heightAnchor constraintEqualToConstant:(1.0/UIScreen.mainScreen.scale)]
    ]];
    // Transparent background: hide separator to avoid list-like appearance
    sep.hidden = YES;

    // Make list container start below fixed header
    if (self.listTopConstraint) {
        self.listTopConstraint.active = NO;
    }
    self.listTopConstraint = [self.listContainerView.topAnchor constraintEqualToAnchor:self.fixedReturnHeaderView.bottomAnchor];
    self.listTopConstraint.active = YES;
}


#pragma mark - UI Setup

- (void)setupNavigationBar
{
    // Title: Move/Copy + filename(s)
    NSString *action = self.operationState == OPERATION_STATE_MOVE ? NSLocalizedString(@"Move", @"Seafile") : NSLocalizedString(@"Copy", @"Seafile");
    NSString *namePart = @"";
    if (self.fileNames.count == 1) {
        namePart = [NSString stringWithFormat:@" %@", self.fileNames.firstObject ?: @""];
    } else if (self.fileNames.count > 1) {
        namePart = [NSString stringWithFormat:@" %lu %@", (unsigned long)self.fileNames.count, NSLocalizedString(@"items", @"Seafile")];
    }
    self.title = [NSString stringWithFormat:@"%@%@", action, namePart];

    // Left: back chevron style (works for modal). Prefer SF Symbol when available, fallback to text.
    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *backImg = nil;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (@available(iOS 13.0, *)) {
        backImg = [UIImage systemImageNamed:@"chevron.left"];
    }
#endif
    if (backImg) {
        [backBtn setImage:backImg forState:UIControlStateNormal];
    }
    [backBtn addTarget:self action:@selector(onBack:) forControlEvents:UIControlEventTouchUpInside];
    backBtn.accessibilityLabel = NSLocalizedString(@"Back", @"Seafile");
    // Make the icon visually closer to the left screen edge
    backBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    backBtn.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 8);
    NSLayoutConstraint *bw = [backBtn.widthAnchor constraintEqualToConstant:32];
    NSLayoutConstraint *bh = [backBtn.heightAnchor constraintEqualToConstant:32];
    bw.active = YES; bh.active = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:backBtn];

    // Right: outlined add-folder button with custom icon
    UIButton *plusBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    plusBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *addIcon = [[UIImage imageNamed:@"share_addFile"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (addIcon) {
        [plusBtn setImage:addIcon forState:UIControlStateNormal];
        // Slightly larger icon while keeping tap area (32x32) unchanged
        plusBtn.imageEdgeInsets = UIEdgeInsetsMake(4, 4, 4, 4);
        if (@available(iOS 13.0, *)) {
            plusBtn.tintColor = [UIColor labelColor];
        } else {
            plusBtn.tintColor = [UIColor blackColor];
        }
    }
    // Remove outlined style (no border)
    plusBtn.layer.borderWidth = 0.0;
    plusBtn.layer.cornerRadius = 0.0;
    [plusBtn addTarget:self action:@selector(onCreateFolder:) forControlEvents:UIControlEventTouchUpInside];
    plusBtn.accessibilityLabel = NSLocalizedString(@"New folder", @"Seafile");
    // Make the icon visually closer to the right screen edge
    plusBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    plusBtn.contentEdgeInsets = UIEdgeInsetsMake(0, 4, 0, -4);
    NSLayoutConstraint *pw = [plusBtn.widthAnchor constraintEqualToConstant:32];
    NSLayoutConstraint *ph = [plusBtn.heightAnchor constraintEqualToConstant:32];
    pw.active = YES; ph.active = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:plusBtn];

    // Make navigation bar opaque with white background so the status bar area is also white
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *navAp = [UINavigationBarAppearance new];
        [navAp configureWithOpaqueBackground];
        navAp.backgroundColor = [UIColor whiteColor];
        self.navigationController.navigationBar.standardAppearance = navAp;
        self.navigationController.navigationBar.scrollEdgeAppearance = navAp;
    } else {
        self.navigationController.navigationBar.barTintColor = [UIColor whiteColor];
        self.navigationController.navigationBar.translucent = NO;
    }
#else
    self.navigationController.navigationBar.barTintColor = [UIColor whiteColor];
    self.navigationController.navigationBar.translucent = NO;
#endif
}

- (void)updateTitleView
{
    NSString *action = self.operationState == OPERATION_STATE_MOVE ? NSLocalizedString(@"Move", @"Seafile") : NSLocalizedString(@"Copy", @"Seafile");
    UIColor *primary = BAR_COLOR_ORANGE ?: [UIColor systemOrangeColor];

    NSMutableAttributedString *attr;
    if (self.fileNames.count == 1 && self.fileNames.firstObject.length > 0) {
        NSString *fileName = self.fileNames.firstObject;
        NSString *full = [NSString stringWithFormat:@"%@ %@", action, fileName];
        attr = [[NSMutableAttributedString alloc] initWithString:full attributes:@{ NSForegroundColorAttributeName: UIColor.labelColor }];
        NSRange nameRange = [full rangeOfString:fileName options:NSBackwardsSearch];
        if (nameRange.location != NSNotFound) {
            [attr addAttributes:@{ NSForegroundColorAttributeName: primary } range:nameRange];
        }
    } else if (self.fileNames.count > 1) {
        NSString *full = [NSString stringWithFormat:@"%@ %lu %@", action, (unsigned long)self.fileNames.count, NSLocalizedString(@"items", @"Seafile")];
        attr = [[NSMutableAttributedString alloc] initWithString:full attributes:@{ NSForegroundColorAttributeName: UIColor.labelColor }];
    } else {
        attr = [[NSMutableAttributedString alloc] initWithString:action attributes:@{ NSForegroundColorAttributeName: UIColor.labelColor }];
    }

    if (!self.titleLabel) {
        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.numberOfLines = 1;
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        self.titleLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightSemibold];
        self.titleLabel.adjustsFontSizeToFitWidth = YES;
        self.titleLabel.minimumScaleFactor = 0.8;
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.navigationItem.titleView = self.titleLabel;
    }
    self.titleLabel.attributedText = attr;
    [self.titleLabel sizeToFit];
}

- (UIButton *)createTabButtonWithTitle:(NSString *)title tag:(NSInteger)tag
{
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    // Add horizontal padding and enable adaptive title sizing while keeping centered alignment
    btn.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    btn.titleLabel.adjustsFontSizeToFitWidth = YES;
    btn.titleLabel.minimumScaleFactor = 0.85;
    btn.titleLabel.textAlignment = NSTextAlignmentCenter;
    UIColor *normalColor = nil;
    if (@available(iOS 13.0, *)) normalColor = [UIColor secondaryLabelColor]; else normalColor = [UIColor grayColor];
    [btn setTitleColor:normalColor forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(onTabTapped:) forControlEvents:UIControlEventTouchUpInside];
    btn.tag = tag;
    return btn;
}

- (void)setupTabsBar
{
    self.tabsBar = [[UIView alloc] init];
    self.tabsBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabsBar.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.tabsBar];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tabsBar.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.tabsBar.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.tabsBar.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [self.tabsBar.heightAnchor constraintEqualToConstant:44],
    ]];

    UIButton *b0 = [self createTabButtonWithTitle:NSLocalizedString(@"Current library", @"Seafile") tag:SeafDestSegmentCurrent];
    UIButton *b1 = [self createTabButtonWithTitle:NSLocalizedString(@"Other libraries", @"Seafile") tag:SeafDestSegmentOthers];
    UIButton *b2 = [self createTabButtonWithTitle:NSLocalizedString(@"Recent", @"Seafile") tag:SeafDestSegmentRecent];
    self.tabButtons = @[b0, b1, b2];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:self.tabButtons];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentFill;
    stack.distribution = UIStackViewDistributionFillEqually;
    [self.tabsBar addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.tabsBar.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:self.tabsBar.trailingAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:self.tabsBar.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.tabsBar.bottomAnchor constant:-2],
    ]];

    self.underlineView = [[UIView alloc] init];
    self.underlineView.translatesAutoresizingMaskIntoConstraints = NO;
    UIColor *primaryColor = BAR_COLOR_ORANGE ?: [UIColor systemOrangeColor];
    self.underlineView.backgroundColor = primaryColor;
    [self.tabsBar addSubview:self.underlineView];

    // Initial underline under first tab
    UIView *first = b0;
    [self.tabsBar layoutIfNeeded];
    self.underlineLeadingConstraint = [self.underlineView.leadingAnchor constraintEqualToAnchor:first.leadingAnchor];
    self.underlineWidthConstraint = [self.underlineView.widthAnchor constraintEqualToAnchor:first.widthAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.underlineView.bottomAnchor constraintEqualToAnchor:self.tabsBar.bottomAnchor],
        [self.underlineView.heightAnchor constraintEqualToConstant:3],
        self.underlineLeadingConstraint,
        self.underlineWidthConstraint,
    ]];

    // Accessibility
    self.tabsBar.isAccessibilityElement = NO;
    for (UIButton *b in self.tabButtons) {
        b.accessibilityTraits |= UIAccessibilityTraitButton;
    }
    // initial selected appearance
    [self updateUnderlineForIndex:SeafDestSegmentCurrent];
}

- (void)onTabTapped:(UIButton *)sender
{
    NSInteger idx = sender.tag;
    self.currentSegment = (SeafDestSegment)idx;
    [self updateUnderlineForIndex:idx];
    switch (self.currentSegment) {
        case SeafDestSegmentCurrent: [self embedCurrentLibraryBrowser]; break;
        case SeafDestSegmentOthers: [self embedOtherLibrariesBrowser]; break;
        case SeafDestSegmentRecent: [self showRecentList]; break;
    }
}

- (void)updateUnderlineForIndex:(NSInteger)idx
{
    if (idx < 0 || idx >= (NSInteger)self.tabButtons.count) return;
    UIView *target = self.tabButtons[idx];
    self.underlineLeadingConstraint.active = NO;
    self.underlineWidthConstraint.active = NO;
    self.underlineLeadingConstraint = [self.underlineView.leadingAnchor constraintEqualToAnchor:target.leadingAnchor];
    self.underlineWidthConstraint = [self.underlineView.widthAnchor constraintEqualToAnchor:target.widthAnchor];
    self.underlineLeadingConstraint.active = YES;
    self.underlineWidthConstraint.active = YES;
    UIColor *primaryColor = BAR_COLOR_ORANGE ?: [UIColor systemOrangeColor];
    UIColor *normalColor = nil;
    if (@available(iOS 13.0, *)) normalColor = [UIColor secondaryLabelColor]; else normalColor = [UIColor grayColor];
    [self.tabButtons enumerateObjectsUsingBlock:^(UIButton * _Nonnull b, NSUInteger i, BOOL * _Nonnull stop) {
        BOOL selected = (i == (NSUInteger)idx);
        [b setTitleColor:(selected ? primaryColor : normalColor) forState:UIControlStateNormal];
        if (selected) b.accessibilityTraits |= UIAccessibilityTraitSelected; else b.accessibilityTraits &= ~UIAccessibilityTraitSelected;
    }];
    [UIView animateWithDuration:0.25 animations:^{ [self.tabsBar layoutIfNeeded]; }];
}

- (void)setupContentContainer
{
    self.contentContainerView = [[UIView alloc] init];
    self.contentContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentContainerView.backgroundColor = kPrimaryBackgroundColor;
    [self.view addSubview:self.contentContainerView];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.contentContainerView.topAnchor constraintEqualToAnchor:self.tabsBar.bottomAnchor constant:8],
        [self.contentContainerView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.contentContainerView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
    ]];

    // Card container inside content, with unified rounded corners
    self.cardContainerView = [[UIView alloc] init];
    self.cardContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardContainerView.backgroundColor = [UIColor clearColor];
    self.cardContainerView.layer.cornerRadius = 0.0;
    self.cardContainerView.layer.masksToBounds = NO;
    [self.contentContainerView addSubview:self.cardContainerView];

    [NSLayoutConstraint activateConstraints:@[
        [self.cardContainerView.topAnchor constraintEqualToAnchor:self.contentContainerView.topAnchor],
        [self.cardContainerView.leadingAnchor constraintEqualToAnchor:self.contentContainerView.leadingAnchor constant:12],
        [self.cardContainerView.trailingAnchor constraintEqualToAnchor:self.contentContainerView.trailingAnchor constant:-12],
        [self.cardContainerView.bottomAnchor constraintEqualToAnchor:self.contentContainerView.bottomAnchor],
    ]];

    // Inner list container with rounded corners, below the fixed return header
    self.listContainerView = [[UIView alloc] init];
    self.listContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    // The tableView itself will carry the rounded corners; container stays clear
    self.listContainerView.backgroundColor = [UIColor clearColor];
    self.listContainerView.layer.cornerRadius = 0.0;
    self.listContainerView.clipsToBounds = NO;
    [self.cardContainerView addSubview:self.listContainerView];

    self.listTopConstraint = [self.listContainerView.topAnchor constraintEqualToAnchor:self.cardContainerView.topAnchor];
    [NSLayoutConstraint activateConstraints:@[
        self.listTopConstraint,
        [self.listContainerView.leadingAnchor constraintEqualToAnchor:self.cardContainerView.leadingAnchor],
        [self.listContainerView.trailingAnchor constraintEqualToAnchor:self.cardContainerView.trailingAnchor],
        [self.listContainerView.bottomAnchor constraintEqualToAnchor:self.cardContainerView.bottomAnchor],
    ]];
}

- (UIButton *)buildActionButtonWithTitle:(NSString *)title background:(UIColor *)background titleColor:(UIColor *)titleColor selector:(SEL)selector
{
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:titleColor forState:UIControlStateNormal];
    btn.backgroundColor = background;
    btn.layer.cornerRadius = 14.0;
    [btn addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)setupBottomBar
{
    self.bottomBar = [[UIView alloc] init];
    self.bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomBar.backgroundColor = kPrimaryBackgroundColor;
    [self.view addSubview:self.bottomBar];

    // Fill the area below safe area (home indicator) with the same background color
    UIView *bottomSafeFillView = [[UIView alloc] init];
    bottomSafeFillView.translatesAutoresizingMaskIntoConstraints = NO;
    bottomSafeFillView.backgroundColor = kPrimaryBackgroundColor;
    [self.view addSubview:bottomSafeFillView];

    UIColor *primaryColor = BAR_COLOR_ORANGE ?: [UIColor systemOrangeColor];
    self.cancelButton = [self buildActionButtonWithTitle:NSLocalizedString(@"Cancel", @"Seafile")
                                              background:[UIColor whiteColor]
                                              titleColor:[UIColor labelColor]
                                                selector:@selector(onCancel:)];
    self.cancelButton.isAccessibilityElement = YES;
    self.cancelButton.accessibilityLabel = NSLocalizedString(@"Cancel", @"Seafile");
    // outline style
    self.cancelButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    UIColor *deepGray = [UIColor colorWithWhite:0.15 alpha:1.0]; // slightly lighter than pure black
    self.cancelButton.layer.borderColor = deepGray.CGColor;

    NSString *confirmTitle = self.operationState == OPERATION_STATE_MOVE ? NSLocalizedString(@"Move here", @"Seafile") : NSLocalizedString(@"Copy here", @"Seafile");
    self.confirmButton = [self buildActionButtonWithTitle:confirmTitle
                                               background:primaryColor
                                               titleColor:[UIColor whiteColor]
                                                 selector:@selector(onConfirm:)];
    self.confirmButton.isAccessibilityElement = YES;
    self.confirmButton.accessibilityLabel = confirmTitle;
    self.confirmButton.accessibilityHint = NSLocalizedString(@"Confirm move or copy to current directory", @"Seafile");

    [self.bottomBar addSubview:self.cancelButton];
    [self.bottomBar addSubview:self.confirmButton];

    // No separator line between list and bottom area

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.bottomBar.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.bottomBar.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [self.bottomBar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],

        [self.cancelButton.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor constant:12],
        [self.cancelButton.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor constant:8],
        [self.cancelButton.bottomAnchor constraintEqualToAnchor:self.bottomBar.bottomAnchor constant:-8],

        [self.confirmButton.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor constant:-12],
        [self.confirmButton.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor constant:8],
        [self.confirmButton.bottomAnchor constraintEqualToAnchor:self.bottomBar.bottomAnchor constant:-8],

        [self.cancelButton.widthAnchor constraintEqualToAnchor:self.confirmButton.widthAnchor],
        [self.cancelButton.trailingAnchor constraintEqualToAnchor:self.confirmButton.leadingAnchor constant:-16],
        [self.cancelButton.heightAnchor constraintEqualToConstant:44],
        [self.confirmButton.heightAnchor constraintEqualToConstant:44],
    ]];

    // Constrain safe-area fill view below the bottom bar to the view's bottom
    [NSLayoutConstraint activateConstraints:@[
        [bottomSafeFillView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bottomSafeFillView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bottomSafeFillView.topAnchor constraintEqualToAnchor:self.bottomBar.bottomAnchor],
        [bottomSafeFillView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // Constrain container bottom to top of bottom bar
    [self.contentContainerView.bottomAnchor constraintEqualToAnchor:self.bottomBar.topAnchor].active = YES;
}

#pragma mark - Embedding Browsers

- (void)clearEmbeddedContent
{
    if (self.childNavController) {
        [self.childNavController willMoveToParentViewController:nil];
        [self.childNavController.view removeFromSuperview];
        [self.childNavController removeFromParentViewController];
        self.childNavController = nil;
        self.rootDirController = nil;
    }
    [self.recentTableView removeFromSuperview];
    self.recentTableView = nil;
}

- (SeafDir *)repoRootForSourceDirectory
{
    NSString *repoId = self.sourceDirectory.repoId ?: @"";
    NSString *repoName = self.sourceDirectory.repoName ?: @"";
    SeafDir *root = [[SeafDir alloc] initWithConnection:self.connection oid:nil repoId:repoId perm:nil name:repoName path:@"/" mtime:0];
    root.repoName = repoName;
    return root;
}

- (void)embedCurrentLibraryBrowser
{
    [self clearEmbeddedContent];
    SeafDir *root = [self repoRootForSourceDirectory];
    // The existing browser will call its choose block when we trigger chooseFolder:
    __weak typeof(self) weakSelf = self;
    SeafDirViewController *dirVC = [[SeafDirViewController alloc] initWithSeafDir:root dirChosen:^(UIViewController *c, SeafDir *dir) {
        __strong typeof(weakSelf) selfRef = weakSelf;
        if (!selfRef) return;
        if ([selfRef.delegate respondsToSelector:@selector(chooseDir:dir:)]) {
            [selfRef.delegate chooseDir:self dir:dir];
        }
    } cancel:^(UIViewController *c) {
        __strong typeof(weakSelf) selfRef = weakSelf;
        if (!selfRef) return;
        if ([selfRef.delegate respondsToSelector:@selector(cancelChoose:)]) {
            [selfRef.delegate cancelChoose:self];
        }
    } chooseRepo:false];
    dirVC.operationState = self.operationState;
    dirVC.useDestinationStyle = YES;
    dirVC.showReturnHeaderOnRoot = YES; // Current library wants header at entry
    self.rootDirController = dirVC;

    self.childNavController = [[UINavigationController alloc] initWithRootViewController:dirVC];
    self.childNavController.navigationBarHidden = YES;
    self.childNavController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self addChildViewController:self.childNavController];
    [self.cardContainerView addSubview:self.childNavController.view];
    [self.childNavController didMoveToParentViewController:self];

    [NSLayoutConstraint activateConstraints:@[
        [self.childNavController.view.topAnchor constraintEqualToAnchor:self.listContainerView.topAnchor],
        [self.childNavController.view.leadingAnchor constraintEqualToAnchor:self.listContainerView.leadingAnchor],
        [self.childNavController.view.trailingAnchor constraintEqualToAnchor:self.listContainerView.trailingAnchor],
        [self.childNavController.view.bottomAnchor constraintEqualToAnchor:self.listContainerView.bottomAnchor],
    ]];
    self.childNavController.view.backgroundColor = [UIColor clearColor];

    self.childNavController.delegate = self;
    [self suppressInternalReturnHeaderIfNeeded:self.childNavController.topViewController];
    [self updateFixedReturnHeaderVisibility];

    // Navigate the stack to the current file's directory inside the same repo
    [self navigateToSourceDirectoryIfNeeded];
    [self logListContainerLayoutWithTag:@"embedCurrentLibraryBrowser:end"];
}

// Build a navigation stack from repo root to the source directory path
- (void)navigateToSourceDirectoryIfNeeded
{
    if (!self.sourceDirectory || self.sourceDirectory.path.length == 0) return;
    NSString *path = self.sourceDirectory.path;
    if ([path isEqualToString:@"/"]) return; // already at root
    NSString *repoId = self.sourceDirectory.repoId ?: @"";
    __weak typeof(self) weakSelf = self;
    NSArray<NSString *> *comps = [path componentsSeparatedByString:@"/"];
    NSMutableString *accum = [NSMutableString stringWithString:@""];
    for (NSString *seg in comps) {
        if (seg.length == 0) continue; // skip leading '/'
        [accum appendFormat:@"/%@", seg];
        SeafDir *levelDir = [[SeafDir alloc] initWithConnection:self.connection oid:nil repoId:repoId perm:nil name:seg path:[accum copy] mtime:0];
        SeafDirViewController *vc = [[SeafDirViewController alloc] initWithSeafDir:levelDir dirChosen:^(UIViewController *c, SeafDir *dir) {
            __strong typeof(weakSelf) selfRef = weakSelf; if (!selfRef) return;
            if ([selfRef.delegate respondsToSelector:@selector(chooseDir:dir:)]) {
                [selfRef.delegate chooseDir:selfRef dir:dir];
            }
        } cancel:^(UIViewController *c) {
            __strong typeof(weakSelf) selfRef = weakSelf; if (!selfRef) return;
            if ([selfRef.delegate respondsToSelector:@selector(cancelChoose:)]) {
                [selfRef.delegate cancelChoose:selfRef];
            }
        } chooseRepo:false];
        vc.operationState = self.operationState;
        vc.useDestinationStyle = YES;
        vc.showReturnHeaderOnRoot = YES;
        [self.childNavController pushViewController:vc animated:NO];
    }
}

- (void)embedOtherLibrariesBrowser
{
    [self clearEmbeddedContent];
    SeafDir *root = self.connection.rootFolder; // shows repo groups and repos
    __weak typeof(self) weakSelf = self;
    SeafDirViewController *dirVC = [[SeafDirViewController alloc] initWithSeafDir:root dirChosen:^(UIViewController *c, SeafDir *dir) {
        __strong typeof(weakSelf) selfRef = weakSelf; if (!selfRef) return;
        if ([selfRef.delegate respondsToSelector:@selector(chooseDir:dir:)]) {
            [selfRef.delegate chooseDir:self dir:dir];
        }
    } cancel:^(UIViewController *c) {
        __strong typeof(weakSelf) selfRef = weakSelf; if (!selfRef) return;
        if ([selfRef.delegate respondsToSelector:@selector(cancelChoose:)]) {
            [selfRef.delegate cancelChoose:self];
        }
    } chooseRepo:false];
    dirVC.operationState = self.operationState;
    dirVC.useDestinationStyle = YES;
    dirVC.showReturnHeaderOnRoot = NO; // Other libraries keep header hidden at root
    self.rootDirController = dirVC;
    self.childNavController = [[UINavigationController alloc] initWithRootViewController:dirVC];
    self.childNavController.navigationBarHidden = YES;
    self.childNavController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self addChildViewController:self.childNavController];
    [self.cardContainerView addSubview:self.childNavController.view];
    [self.childNavController didMoveToParentViewController:self];
    [NSLayoutConstraint activateConstraints:@[
        [self.childNavController.view.topAnchor constraintEqualToAnchor:self.listContainerView.topAnchor],
        [self.childNavController.view.leadingAnchor constraintEqualToAnchor:self.listContainerView.leadingAnchor],
        [self.childNavController.view.trailingAnchor constraintEqualToAnchor:self.listContainerView.trailingAnchor],
        [self.childNavController.view.bottomAnchor constraintEqualToAnchor:self.listContainerView.bottomAnchor],
    ]];
    self.childNavController.delegate = self;
    [self suppressInternalReturnHeaderIfNeeded:self.childNavController.topViewController];
    [self updateFixedReturnHeaderVisibility];
    [self logListContainerLayoutWithTag:@"embedOtherLibrariesBrowser:end"];
}

- (void)showRecentList
{
    [self clearEmbeddedContent];
    self.recentTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.recentTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.recentTableView.dataSource = self;
    self.recentTableView.delegate = self;
    // Rounded corners on the table directly
    self.recentTableView.backgroundColor = [UIColor whiteColor];
    [self applyRoundedCornersForRecentIfNeeded];
    // Register destination style cell class for consistent visuals
    [self.recentTableView registerClass:[SeafDestCell class] forCellReuseIdentifier:@"SeafDestCell"];
    [self.cardContainerView addSubview:self.recentTableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.recentTableView.topAnchor constraintEqualToAnchor:self.listContainerView.topAnchor],
        [self.recentTableView.leadingAnchor constraintEqualToAnchor:self.listContainerView.leadingAnchor],
        [self.recentTableView.trailingAnchor constraintEqualToAnchor:self.listContainerView.trailingAnchor],
        [self.recentTableView.bottomAnchor constraintEqualToAnchor:self.listContainerView.bottomAnchor],
    ]];
    // Cells remain transparent so the table's rounded mask is visible

    self.recentData = [[SeafRecentDirsStore shared] recentDirectoriesForConnection:self.connection maxCount:20];
    [self.recentTableView reloadData];
    [self updateFixedReturnHeaderVisibility];
    [self logListContainerLayoutWithTag:@"showRecentList:end"];
}

#pragma mark - Actions

- (void)onBack:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onTapFixedReturnHeader
{
    if (!self.childNavController) return;
    UINavigationController *nav = self.childNavController;
    if (nav.viewControllers.count > 1) {
        [nav popViewControllerAnimated:YES];
        return;
    }
    // When at the root of current library, navigate to repo list; if already at repo list, do nothing
    if (self.currentSegment == SeafDestSegmentCurrent) {
        UIViewController *topVC = nav.topViewController;
        if ([topVC isKindOfClass:[SeafDirViewController class]]) {
            SeafDir *reposRoot = nil;
            @try {
                SeafDir *curDir = [topVC valueForKey:@"directory"]; // KVC
                if ([curDir isKindOfClass:[SeafRepos class]]) return; // already at repo list
                reposRoot = curDir.connection.rootFolder;
            } @catch (NSException *e) { reposRoot = nil; }
            if (reposRoot) {
                __weak typeof(self) weakSelf = self;
                SeafDirViewController *controller = [[SeafDirViewController alloc] initWithSeafDir:reposRoot dirChosen:^(UIViewController *c, SeafDir *dir) {
                    __strong typeof(weakSelf) selfRef = weakSelf; if (!selfRef) return;
                    if ([selfRef.delegate respondsToSelector:@selector(chooseDir:dir:)]) {
                        [selfRef.delegate chooseDir:selfRef dir:dir];
                    }
                } cancel:^(UIViewController *c) {
                    __strong typeof(weakSelf) selfRef = weakSelf; if (!selfRef) return;
                    if ([selfRef.delegate respondsToSelector:@selector(cancelChoose:)]) {
                        [selfRef.delegate cancelChoose:selfRef];
                    }
                } chooseRepo:false];
                controller.operationState = self.operationState;
                controller.useDestinationStyle = YES;
                controller.showReturnHeaderOnRoot = NO;
                [nav pushViewController:controller animated:NO];
            }
        }
    }
}

#pragma mark - Fixed header visibility
- (void)updateFixedReturnHeaderVisibility
{
    // Always show except on Recent tab
    CGFloat targetHeight = (self.currentSegment == SeafDestSegmentRecent) ? 0.0 : 44.0;
    BOOL disableInteraction = NO;
    if (self.currentSegment != SeafDestSegmentRecent && self.childNavController) {
        UIViewController *topVC = self.childNavController.topViewController;
        if ([topVC isKindOfClass:[SeafDirViewController class]]) {
            @try {
                SeafDir *dir = [topVC valueForKey:@"directory"]; // KVC access
                if ([dir isKindOfClass:[SeafRepos class]]) {
                    disableInteraction = YES; // On repo list, no action when tapping
                }
            } @catch (NSException *e) {}
        }
    }
    self.fixedReturnHeaderHeightConstraint.constant = targetHeight;
    self.fixedReturnHeaderView.hidden = (targetHeight <= 0.0);
    self.fixedReturnHeaderView.userInteractionEnabled = !disableInteraction;
    [self.cardContainerView setNeedsLayout];
    [self.cardContainerView layoutIfNeeded];
    [self logListContainerLayoutWithTag:@"updateFixedReturnHeaderVisibility:end"];
}

#pragma mark - UINavigationControllerDelegate
- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    [self suppressInternalReturnHeaderIfNeeded:viewController];
}

- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    [self suppressInternalReturnHeaderIfNeeded:viewController];
    [self updateFixedReturnHeaderVisibility];
}

- (void)suppressInternalReturnHeaderIfNeeded:(UIViewController *)vc
{
    if (![vc isKindOfClass:[SeafDirViewController class]]) return;
    UITableViewController *tvc = (UITableViewController *)vc;
    tvc.tableView.tableHeaderView = nil;
}

#pragma mark - Debug Layout Logging
- (void)logListContainerLayoutWithTag:(NSString *)tag
{
    CGRect hdrF = self.fixedReturnHeaderView ? self.fixedReturnHeaderView.frame : CGRectZero;
    CGRect listF = self.listContainerView ? self.listContainerView.frame : CGRectZero;
    CGRect cardF = self.cardContainerView ? self.cardContainerView.frame : CGRectZero;
    CGRect childF = self.childNavController.view ? self.childNavController.view.frame : CGRectZero;
    UIViewController *topVC = self.childNavController.topViewController;
    UITableView *tv = nil;
    if ([topVC isKindOfClass:[UITableViewController class]]) {
        tv = ((UITableViewController *)topVC).tableView;
    }
    CGRect tvF = tv ? tv.frame : CGRectZero;

    Debug("[DestPicker][%@] card=%@ list=%@ listCR=%.1f clips=%d bg=%@ hdr=%@ child=%@ tv=%@ tv.layer.masks=%d tv.bg=%@ segment=%ld", tag,
          NSStringFromCGRect(cardF),
          NSStringFromCGRect(listF),
          self.listContainerView.layer.cornerRadius,
          (int)self.listContainerView.clipsToBounds,
          self.listContainerView.backgroundColor,
          NSStringFromCGRect(hdrF),
          NSStringFromCGRect(childF),
          NSStringFromCGRect(tvF),
          (int)tv.layer.masksToBounds,
          tv.backgroundColor,
          (long)self.currentSegment);
}

#pragma mark - Rounded Corner Helpers
- (void)applyRoundedCornersForRecentIfNeeded
{
    if (!self.recentTableView) return;
    CGFloat radius = 16.0;
    self.recentTableView.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) self.recentTableView.layer.cornerCurve = kCACornerCurveContinuous;
    self.recentTableView.clipsToBounds = YES;
    for (UIView *sub in self.recentTableView.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls containsString:@"WrapperView"] || [cls containsString:@"TableView"] || [cls containsString:@"ScrollView"]) {
            sub.layer.cornerRadius = radius;
            sub.clipsToBounds = YES;
        }
    }
}

- (void)onCreateFolder:(id)sender
{
    SeafDir *currentDir = nil;
    UIViewController *topVC = self.childNavController.topViewController;
    if ([topVC isKindOfClass:[SeafDirViewController class]]) {
        @try { currentDir = [topVC valueForKey:@"directory"]; } @catch (NSException *e) { currentDir = nil; }
    }
    if (!currentDir) return;

    UIAlertController *alert = [UIAlertController
                                alertControllerWithTitle:NSLocalizedString(@"New folder", @"Seafile")
                                message:nil
                                preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = NSLocalizedString(@"New folder name", @"Seafile");
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) selfRef = weakSelf; if (!selfRef) return;
        NSString *name = alert.textFields.firstObject.text;
        if (name.length == 0) return;
        if (![name isValidFileName]) {
            [selfRef alertWithTitle:NSLocalizedString(@"Folder name invalid", @"Seafile")];
            return;
        }
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Creating folder ...", @"Seafile")];
        [[SeafFileOperationManager sharedManager] mkdir:name inDir:currentDir completion:^(BOOL success, NSError * _Nullable error) {
            if (!selfRef) return;
            if (!success) {
                NSString *errMsg = error.localizedDescription ?: NSLocalizedString(@"Failed to create folder", @"Seafile");
                [SVProgressHUD showErrorWithStatus:errMsg];
                return;
            }
            [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Create folder success", @"Seafile")];
            // Reload and scroll to the new folder
            [currentDir loadContentSuccess:^(SeafDir *dir) {
                // Find index in subDirs
                NSArray *dirs = [dir subDirs];
                __block NSInteger row = NSNotFound;
                [dirs enumerateObjectsUsingBlock:^(SeafDir *obj, NSUInteger idx, BOOL *stop) {
                    if ([obj.name isEqualToString:name]) { row = (NSInteger)idx; *stop = YES; }
                }];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([selfRef.childNavController.topViewController isKindOfClass:[SeafDirViewController class]]) {
                        SeafDirViewController *vc = (SeafDirViewController *)selfRef.childNavController.topViewController;
                        [vc.tableView reloadData];
                        if (row != NSNotFound) {
                            NSIndexPath *ip = [NSIndexPath indexPathForRow:row inSection:0];
                            [vc.tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
                        }
                    }
                });
            } failure:^(SeafDir *dir, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{ [SVProgressHUD dismiss]; });
            }];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)onCancel:(id)sender
{
    if ([self.delegate respondsToSelector:@selector(cancelChoose:)]) {
        [self.delegate cancelChoose:self];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)onConfirm:(id)sender
{
    // Get the current directory from the top SeafDirViewController and forward to delegate
    UIViewController *topVC = self.childNavController.topViewController;
    if ([topVC isKindOfClass:[SeafDirViewController class]]) {
        SeafDir *currentDir = nil;
        @try {
            // Access private readonly property via KVC to avoid changing SeafDirViewController's header
            currentDir = [topVC valueForKey:@"directory"];
        } @catch (NSException *exception) {
            currentDir = nil;
        }
        if (currentDir && [self.delegate respondsToSelector:@selector(chooseDir:dir:)]) {
            [[SeafRecentDirsStore shared] addRecentDirectory:currentDir];
            [self.delegate chooseDir:self dir:currentDir];
        }
    }
}

- (void)onSegmentChanged:(UISegmentedControl *)seg
{
    self.currentSegment = (SeafDestSegment)seg.selectedSegmentIndex;
    switch (self.currentSegment) {
        case SeafDestSegmentCurrent:
            [self embedCurrentLibraryBrowser];
            break;
        case SeafDestSegmentOthers:
            [self embedOtherLibrariesBrowser];
            break;
        case SeafDestSegmentRecent:
            [self showRecentList];
            break;
    }
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{ return self.recentData.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SeafDestCell"];
    if (!cell) {
        cell = [[SeafDestCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SeafDestCell"];
    }
    // Ensure transparent background so outer rounded container is visible
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    if ([cell respondsToSelector:@selector(cellBackgroundView)] && [(id)cell cellBackgroundView]) {
        UIView *bg = [(id)cell cellBackgroundView];
        bg.backgroundColor = [UIColor clearColor];
    }
    NSDictionary *rec = self.recentData[indexPath.row];
    NSString *dirName = [rec[@"dirName"] isKindOfClass:[NSString class]] ? rec[@"dirName"] : @"";
    NSString *path = [rec[@"path"] isKindOfClass:[NSString class]] ? rec[@"path"] : @"";
    NSString *repoId = [rec[@"repoId"] isKindOfClass:[NSString class]] ? rec[@"repoId"] : @"";
    NSString *repoName = [rec[@"repoName"] isKindOfClass:[NSString class]] ? rec[@"repoName"] : @"";
    // Fallback: if repoName missing, try look up by repoId
    if (repoName.length == 0 && repoId.length > 0 && [self.connection.rootFolder isKindOfClass:[SeafRepos class]]) {
        SeafRepo *repo = [((SeafRepos *)self.connection.rootFolder) getRepo:repoId];
        if (repo && repo.name.length > 0) repoName = repo.name;
    }
    NSNumber *t = [rec[@"time"] isKindOfClass:[NSNumber class]] ? rec[@"time"] : nil;
    NSString *dateText = t ? [SeafDateFormatter stringFromLongLong:t.longLongValue] : @"";
    cell.textLabel.text = dirName.length ? dirName : path.lastPathComponent;
    // For normal directories, show the repo root name as subtitle; for repo root, keep date
    if ([path isEqualToString:@"/"]) {
        // Repo root still shows date per previous behavior
        cell.detailTextLabel.text = dateText;
    } else {
        // Normal directory shows full path starting with repoName
        NSString *fullPath = repoName.length ? [NSString stringWithFormat:@"%@%@", repoName, path] : path;
        cell.detailTextLabel.text = fullPath;
    }
    UIImage *icon = nil;
    if ([path isEqualToString:@"/"]) {
        // Repo root icon
        if ([self.connection.rootFolder isKindOfClass:[SeafRepos class]] && repoId.length > 0) {
            SeafRepo *repo = [((SeafRepos *)self.connection.rootFolder) getRepo:repoId];
            icon = repo.icon;
        }
    } else {
        // Normal directory: build a temp SeafDir to obtain the correct icon
        NSString *name = dirName.length ? dirName : path.lastPathComponent;
        SeafDir *tmpDir = [[SeafDir alloc] initWithConnection:self.connection oid:nil repoId:repoId perm:nil name:name path:path mtime:0];
        icon = tmpDir.icon;
    }
    cell.imageView.image = icon ?: ([UIImage imageNamed:@"folder"] ?: [UIImage new]);

    // Debug logs to verify subtitle selection
    BOOL isRoot = [path isEqualToString:@"/"];
    Debug("[Recent] row=%ld repoId=%@ repoName(resolved)=%@ path=%@ dirName=%@ isRoot=%d subtitle(full)=%@", (long)indexPath.row, repoId, repoName, path, dirName, isRoot, cell.detailTextLabel.text);
    cell.moreButton.hidden = YES;
    return (UITableViewCell *)cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary *rec = self.recentData[indexPath.row];
    SeafDir *dir = [[SeafRecentDirsStore shared] directoryFromRecord:rec connection:self.connection];
    if (dir && [self.delegate respondsToSelector:@selector(chooseDir:dir:)]) {
        [[SeafRecentDirsStore shared] addRecentDirectory:dir];
        [self.delegate chooseDir:self dir:dir];
    }
}

@end


