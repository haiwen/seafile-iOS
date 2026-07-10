//
//  SeafShareDestinationViewController.m
//  SeafShare
//
//  Destination picker for Share Extension.
//  UI structure copied from SeafDestinationPickerViewController (move file page),
//  adapted for 2-tab share flow aligned with Android.
//

#import "SeafShareDestinationViewController.h"
#import "SeafShareDirViewController.h"
#import "SeafShareStarredViewController.h"
#import "SeafShareRecentViewController.h"
#import "SeafRecentDirsStore.h"
#import "SeafUploadFile.h"
#import "SeafDataTaskManager.h"
#import "SeafInputItemsProvider.h"
#import "SeafUploadFileModel.h"
#import "SeafStorage.h"
#import "SeafGlobal.h"
#import "SeafRepos.h"
#import "SeafConnection.h"
#import "SeafTheme.h"
#import "UIViewController+Extend.h"
#import "Debug.h"
#import "Constants.h"
#import "ExtentedString.h"
#import "SeafFileOperationManager.h"

static NSString *const kShareLastRepoId = @"SeafShare_LastRepoId";
static NSString *const kShareLastPath   = @"SeafShare_LastPath";
static NSString *const kShareLastAccount = @"SeafShare_LastAccount";

typedef NS_ENUM(NSInteger, SeafShareTab) {
    SeafShareTabLibraries = 0,
    SeafShareTabStarred   = 1,
    SeafShareTabRecent    = 2,
};

@interface SeafShareDestinationViewController () <UINavigationControllerDelegate, SeafUploadDelegate>

@property (nonatomic, strong) SeafConnection *connection;
@property (nonatomic, copy)   NSString *startRepoId;
@property (nonatomic, copy)   NSString *startPath;

// --- UI (copied from SeafDestinationPickerViewController) ---
// Tabs bar
@property (nonatomic, strong) UIView *tabsBar;
@property (nonatomic, strong) NSArray<UIButton *> *tabButtons;
@property (nonatomic, strong) UIView *underlineView;
@property (nonatomic, strong) NSLayoutConstraint *underlineLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *underlineWidthConstraint;

// Content
@property (nonatomic, strong) UIView *contentContainerView;
@property (nonatomic, strong) UIView *cardContainerView;
@property (nonatomic, strong) UIView *listContainerView;
@property (nonatomic, strong) NSLayoutConstraint *listTopConstraint;

// Fixed return header — shown only inside a sub-directory of the Libraries tab.
@property (nonatomic, strong) UIView *fixedReturnHeaderView;
@property (nonatomic, strong) NSLayoutConstraint *fixedReturnHeaderHeightConstraint;
@property (nonatomic, strong) UIImageView *returnIcon;
@property (nonatomic, strong) UILabel *headerLabel;
@property (nonatomic, strong) UILabel *currentPathLabel;

// Tabs bar height (for dynamic show/hide)
@property (nonatomic, strong) NSLayoutConstraint *tabsBarHeightConstraint;

// Child controllers
@property (nonatomic, strong) UINavigationController *childNavController;
@property (nonatomic, strong) SeafShareDirViewController *rootDirController;
@property (nonatomic, strong) SeafShareStarredViewController *starredVC;
@property (nonatomic, strong) SeafShareRecentViewController *recentVC;

@property (nonatomic, assign) SeafShareTab currentTab;

// Upload state
@property (nonatomic, strong) UIAlertController *uploadAlert;
@property (nonatomic, strong) UIProgressView *uploadProgressView;
@property (nonatomic, strong) UILabel *uploadFileNameLabel;
@property (nonatomic, strong) UILabel *uploadCountLabel;
@property (nonatomic, strong) NSArray *ufiles;
@property (nonatomic, assign) NSInteger uploadFileCount;
@property (nonatomic, assign) NSInteger completedCount;
@property (nonatomic, strong) SeafDir *uploadDirectory;

@end

@implementation SeafShareDestinationViewController

#pragma mark - Init

- (instancetype)initWithConnection:(SeafConnection *)connection {
    return [self initWithConnection:connection repoId:nil path:nil];
}

- (instancetype)initWithConnection:(SeafConnection *)connection repoId:(NSString *)repoId path:(NSString *)path {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _connection = connection;
        _startRepoId = repoId;
        _startPath = path;
    }
    return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SeafTheme primaryBackgroundColor];

    [self setupNavigationBar];
    [self setupTabsBar];
    [self setupContentContainer];
    [self setupFixedReturnHeader];
    [self setupContentBottomConstraint];

    self.currentTab = SeafShareTabLibraries;
    [self showLibrariesTab];
    [self updateUnderlineForIndex:SeafShareTabLibraries];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
}

#pragma mark - Navigation Bar (Liquid Glass style per Figma design)

- (void)setupNavigationBar {
    // Title: "Seafile" (centered, per design)
    self.title = @"Seafile";

    // Left: back button (iOS 26 auto-applies Liquid Glass pill to standard UIBarButtonItem)
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(onBack:)];

    // Right: circular new-folder button + blue pill "确定" button
    // Smaller SF Symbol so the Liquid Glass chrome stays circular (wide icons stretch into a pill).
    UIImage *folderIcon = nil;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *symbolConfig =
            [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightRegular];
        folderIcon = [UIImage systemImageNamed:@"folder.badge.plus" withConfiguration:symbolConfig];
    }
    UIBarButtonItem *plusItem = [[UIBarButtonItem alloc] initWithImage:folderIcon
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(onCreateFolder:)];
    plusItem.accessibilityLabel = NSLocalizedString(@"New folder", @"Seafile");
    // Keep the folder button as its own circular glass chip, separate from the OK pill.
    if (@available(iOS 26.0, *)) {
        plusItem.sharesBackground = NO;
    }

    // Blue pill confirm button — standard UIBarButtonItem text style
    // iOS 26: system renders it as a Liquid Glass pill automatically
    UIBarButtonItem *confirmItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"OK", @"Seafile")
                                                                   style:UIBarButtonItemStyleDone
                                                                  target:self
                                                                  action:@selector(onConfirm:)];
    // Blue tint to match design (#3884F2)
    confirmItem.tintColor = [UIColor colorWithRed:0.22 green:0.52 blue:0.95 alpha:1.0];

    self.navigationItem.rightBarButtonItems = @[confirmItem, plusItem];
}

#pragma mark - Tabs Bar (from SeafDestinationPickerViewController L298-357, adapted for 2 tabs)

- (UIButton *)createTabButtonWithTitle:(NSString *)title tag:(NSInteger)tag {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    btn.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    btn.titleLabel.adjustsFontSizeToFitWidth = YES;
    btn.titleLabel.minimumScaleFactor = 0.85;
    btn.titleLabel.textAlignment = NSTextAlignmentCenter;
    [btn setTitleColor:[SeafTheme secondaryText] forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(onTabTapped:) forControlEvents:UIControlEventTouchUpInside];
    btn.tag = tag;
    return btn;
}

- (void)setupTabsBar {
    self.tabsBar = [[UIView alloc] init];
    self.tabsBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabsBar.backgroundColor = [SeafTheme primarySurface];
    [self.view addSubview:self.tabsBar];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    // Tab bar always visible in destination picker (hidden only on account selection page)
    self.tabsBarHeightConstraint = [self.tabsBar.heightAnchor constraintEqualToConstant:44];
    [NSLayoutConstraint activateConstraints:@[
        [self.tabsBar.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.tabsBar.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.tabsBar.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        self.tabsBarHeightConstraint,
    ]];

    // 3 Tabs: Libraries + Starred + Recent (per Figma design)
    UIButton *b0 = [self createTabButtonWithTitle:NSLocalizedString(@"Libraries", @"Seafile") tag:SeafShareTabLibraries];
    UIButton *b1 = [self createTabButtonWithTitle:NSLocalizedString(@"Starred", @"Seafile") tag:SeafShareTabStarred];
    UIButton *b2 = [self createTabButtonWithTitle:NSLocalizedString(@"Recent", @"Seafile") tag:SeafShareTabRecent];
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

    // Orange underline indicator (from move page)
    self.underlineView = [[UIView alloc] init];
    self.underlineView.translatesAutoresizingMaskIntoConstraints = NO;
    UIColor *primaryColor = BAR_COLOR_ORANGE ?: [UIColor systemOrangeColor];
    self.underlineView.backgroundColor = primaryColor;
    [self.tabsBar addSubview:self.underlineView];

    UIView *first = b0;
    self.underlineLeadingConstraint = [self.underlineView.leadingAnchor constraintEqualToAnchor:first.leadingAnchor];
    self.underlineWidthConstraint = [self.underlineView.widthAnchor constraintEqualToAnchor:first.widthAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.underlineView.bottomAnchor constraintEqualToAnchor:self.tabsBar.bottomAnchor],
        [self.underlineView.heightAnchor constraintEqualToConstant:3],
        self.underlineLeadingConstraint,
        self.underlineWidthConstraint,
    ]];
}

- (void)onTabTapped:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx == self.currentTab) return;

    self.currentTab = (SeafShareTab)idx;
    [self updateUnderlineForIndex:idx];

    // Show/hide new folder button (only in Libraries tab)
    // rightBarButtonItems: [0]=confirm, [1]=plus
    if (self.navigationItem.rightBarButtonItems.count > 1) {
        UIBarButtonItem *plusItem = self.navigationItem.rightBarButtonItems[1];
        BOOL showPlus = (idx == SeafShareTabLibraries);
        plusItem.enabled = showPlus;
        plusItem.tintColor = showPlus ? nil : [UIColor clearColor];
    }

    switch (self.currentTab) {
        case SeafShareTabLibraries: [self showLibrariesTab]; break;
        case SeafShareTabStarred:   [self showStarredTab]; break;
        case SeafShareTabRecent:    [self showRecentTab]; break;
    }
}

- (void)updateUnderlineForIndex:(NSInteger)idx {
    if (idx < 0 || idx >= (NSInteger)self.tabButtons.count) return;
    UIView *target = self.tabButtons[idx];
    self.underlineLeadingConstraint.active = NO;
    self.underlineWidthConstraint.active = NO;
    self.underlineLeadingConstraint = [self.underlineView.leadingAnchor constraintEqualToAnchor:target.leadingAnchor];
    self.underlineWidthConstraint = [self.underlineView.widthAnchor constraintEqualToAnchor:target.widthAnchor];
    self.underlineLeadingConstraint.active = YES;
    self.underlineWidthConstraint.active = YES;

    UIColor *primaryColor = BAR_COLOR_ORANGE ?: [UIColor systemOrangeColor];
    UIColor *normalColor = [SeafTheme secondaryText];
    [self.tabButtons enumerateObjectsUsingBlock:^(UIButton *b, NSUInteger i, BOOL *stop) {
        BOOL selected = (i == (NSUInteger)idx);
        [b setTitleColor:(selected ? primaryColor : normalColor) forState:UIControlStateNormal];
    }];
    [UIView animateWithDuration:0.25 animations:^{ [self.tabsBar layoutIfNeeded]; }];
}

#pragma mark - Content Container (from SeafDestinationPickerViewController L391-436)

- (void)setupContentContainer {
    self.contentContainerView = [[UIView alloc] init];
    self.contentContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentContainerView.backgroundColor = [SeafTheme primaryBackgroundColor];
    [self.view addSubview:self.contentContainerView];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.contentContainerView.topAnchor constraintEqualToAnchor:self.tabsBar.bottomAnchor constant:8],
        [self.contentContainerView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.contentContainerView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
    ]];

    // Card container with left/right padding
    self.cardContainerView = [[UIView alloc] init];
    self.cardContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardContainerView.backgroundColor = [UIColor clearColor];
    [self.contentContainerView addSubview:self.cardContainerView];

    [NSLayoutConstraint activateConstraints:@[
        [self.cardContainerView.topAnchor constraintEqualToAnchor:self.contentContainerView.topAnchor],
        [self.cardContainerView.leadingAnchor constraintEqualToAnchor:self.contentContainerView.leadingAnchor],
        [self.cardContainerView.trailingAnchor constraintEqualToAnchor:self.contentContainerView.trailingAnchor],
        [self.cardContainerView.bottomAnchor constraintEqualToAnchor:self.contentContainerView.bottomAnchor],
    ]];

    // Inner list container
    self.listContainerView = [[UIView alloc] init];
    self.listContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.listContainerView.backgroundColor = [UIColor clearColor];
    [self.cardContainerView addSubview:self.listContainerView];

    self.listTopConstraint = [self.listContainerView.topAnchor constraintEqualToAnchor:self.cardContainerView.topAnchor];
    [NSLayoutConstraint activateConstraints:@[
        self.listTopConstraint,
        [self.listContainerView.leadingAnchor constraintEqualToAnchor:self.cardContainerView.leadingAnchor],
        [self.listContainerView.trailingAnchor constraintEqualToAnchor:self.cardContainerView.trailingAnchor],
        [self.listContainerView.bottomAnchor constraintEqualToAnchor:self.cardContainerView.bottomAnchor],
    ]];
}

#pragma mark - Fixed Return Header

/// Fixed "Return to previous level" bar pinned to the top of the card, above the list.
/// Hidden at the library root; shown (with the current path) once inside a sub-directory.
- (void)setupFixedReturnHeader {
    self.fixedReturnHeaderView = [[UIView alloc] init];
    self.fixedReturnHeaderView.translatesAutoresizingMaskIntoConstraints = NO;
    self.fixedReturnHeaderView.backgroundColor = [UIColor clearColor];
    self.fixedReturnHeaderView.hidden = YES;
    [self.cardContainerView addSubview:self.fixedReturnHeaderView];

    self.returnIcon = [[UIImageView alloc] initWithImage:[[UIImage imageNamed:@"return"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    self.returnIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.returnIcon.tintColor = [SeafTheme primaryText];
    self.returnIcon.contentMode = UIViewContentModeScaleAspectFit;
    [self.fixedReturnHeaderView addSubview:self.returnIcon];

    self.headerLabel = [[UILabel alloc] init];
    self.headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerLabel.textColor = [SeafTheme primaryText];
    self.headerLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    self.headerLabel.text = NSLocalizedString(@"Return to previous level", @"Seafile");
    [self.fixedReturnHeaderView addSubview:self.headerLabel];

    self.currentPathLabel = [[UILabel alloc] init];
    self.currentPathLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.currentPathLabel.textColor = [SeafTheme secondaryText];
    self.currentPathLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    self.currentPathLabel.textAlignment = NSTextAlignmentRight;
    self.currentPathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.fixedReturnHeaderView addSubview:self.currentPathLabel];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapFixedReturnHeader)];
    [self.fixedReturnHeaderView addGestureRecognizer:tap];
    self.fixedReturnHeaderView.isAccessibilityElement = YES;
    self.fixedReturnHeaderView.accessibilityLabel = self.headerLabel.text;

    self.fixedReturnHeaderHeightConstraint = [self.fixedReturnHeaderView.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [self.fixedReturnHeaderView.topAnchor constraintEqualToAnchor:self.cardContainerView.topAnchor],
        [self.fixedReturnHeaderView.leadingAnchor constraintEqualToAnchor:self.cardContainerView.leadingAnchor],
        [self.fixedReturnHeaderView.trailingAnchor constraintEqualToAnchor:self.cardContainerView.trailingAnchor],
        self.fixedReturnHeaderHeightConstraint,

        [self.returnIcon.leadingAnchor constraintEqualToAnchor:self.fixedReturnHeaderView.leadingAnchor constant:16],
        [self.returnIcon.centerYAnchor constraintEqualToAnchor:self.fixedReturnHeaderView.centerYAnchor],
        [self.returnIcon.widthAnchor constraintEqualToConstant:20],
        [self.returnIcon.heightAnchor constraintEqualToConstant:20],

        [self.headerLabel.leadingAnchor constraintEqualToAnchor:self.returnIcon.trailingAnchor constant:8],
        [self.headerLabel.centerYAnchor constraintEqualToAnchor:self.fixedReturnHeaderView.centerYAnchor],

        [self.currentPathLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.headerLabel.trailingAnchor constant:8],
        [self.currentPathLabel.trailingAnchor constraintEqualToAnchor:self.fixedReturnHeaderView.trailingAnchor constant:-16],
        [self.currentPathLabel.centerYAnchor constraintEqualToAnchor:self.fixedReturnHeaderView.centerYAnchor],
        [self.currentPathLabel.widthAnchor constraintLessThanOrEqualToConstant:220],
    ]];

    // List container starts below the fixed header.
    if (self.listTopConstraint) {
        self.listTopConstraint.active = NO;
    }
    self.listTopConstraint = [self.listContainerView.topAnchor constraintEqualToAnchor:self.fixedReturnHeaderView.bottomAnchor];
    self.listTopConstraint.active = YES;
}

- (void)onTapFixedReturnHeader {
    if (self.currentTab != SeafShareTabLibraries) return;
    if (self.childNavController.viewControllers.count > 1) {
        [self.childNavController popViewControllerAnimated:YES];
    }
}

/// Show the fixed header only when inside a sub-directory of the Libraries tab;
/// hide it at the library root (where "My Own Libraries" is a section header in the list).
- (void)updateFixedHeaderVisibility {
    [self updateFixedHeaderVisibilityAnimated:NO];
}

/// Animate the return header when crossing the root ↔ sub-directory boundary
/// (e.g. user push/pop). Pass `animated:NO` for tab switches and remembered-path restore.
- (void)updateFixedHeaderVisibilityAnimated:(BOOL)animated {
    BOOL isInSubDir = (self.currentTab == SeafShareTabLibraries) && (self.childNavController.viewControllers.count > 1);
    BOOL currentlyVisible = !self.fixedReturnHeaderView.hidden && self.fixedReturnHeaderHeightConstraint.constant > 0;

    if (isInSubDir) {
        NSString *newPath = @"";
        UIViewController *topVC = self.childNavController.topViewController;
        if ([topVC isKindOfClass:[SeafShareDirViewController class]]) {
            SeafDir *dir = ((SeafShareDirViewController *)topVC).currentDirectory;
            newPath = [self locationTextForDir:dir] ?: @"";
        }

        // Already showing (deeper/shallower subdir) — only path text needs updating.
        if (currentlyVisible) {
            if (![self.currentPathLabel.text isEqualToString:newPath]) {
                if (animated) {
                    [UIView transitionWithView:self.currentPathLabel
                                      duration:0.25
                                       options:UIViewAnimationOptionTransitionCrossDissolve
                                    animations:^{
                        self.currentPathLabel.text = newPath;
                    } completion:nil];
                } else {
                    self.currentPathLabel.text = newPath;
                }
            }
            return;
        }

        // First time showing the header — set path immediately; visibility animates below.
        self.currentPathLabel.text = newPath;
        self.fixedReturnHeaderView.hidden = NO;
        if (animated) {
            self.fixedReturnHeaderView.alpha = 0;
            self.fixedReturnHeaderHeightConstraint.constant = 0;
            [self.view layoutIfNeeded];
            self.fixedReturnHeaderHeightConstraint.constant = 44.0;
            [UIView animateWithDuration:0.25 animations:^{
                self.fixedReturnHeaderView.alpha = 1;
                [self.view layoutIfNeeded];
            }];
        } else {
            self.fixedReturnHeaderView.alpha = 1;
            self.fixedReturnHeaderHeightConstraint.constant = 44.0;
            [self.view setNeedsLayout];
            [self.view layoutIfNeeded];
        }
    } else {
        if (!currentlyVisible) {
            self.fixedReturnHeaderHeightConstraint.constant = 0;
            self.fixedReturnHeaderView.hidden = YES;
            self.fixedReturnHeaderView.alpha = 1;
            return;
        }

        if (animated) {
            self.fixedReturnHeaderHeightConstraint.constant = 0;
            [UIView animateWithDuration:0.25 animations:^{
                self.fixedReturnHeaderView.alpha = 0;
                [self.view layoutIfNeeded];
            } completion:^(BOOL finished) {
                BOOL stillShouldHide = !(self.currentTab == SeafShareTabLibraries
                                         && self.childNavController.viewControllers.count > 1);
                if (stillShouldHide) {
                    self.fixedReturnHeaderView.hidden = YES;
                    self.fixedReturnHeaderView.alpha = 1;
                }
            }];
        } else {
            self.fixedReturnHeaderHeightConstraint.constant = 0;
            self.fixedReturnHeaderView.hidden = YES;
            self.fixedReturnHeaderView.alpha = 1;
            [self.view setNeedsLayout];
            [self.view layoutIfNeeded];
        }
    }
}

/// Resolve the full location path shown on the right side of the return header,
/// in the form "<libraryName>/<sub>/<dir>" (e.g. "66666/0/subDir").
/// `repoName` is not populated during the extension's browse flow, so the library
/// name is derived from the connection (falling back to the directory's own name).
- (NSString *)locationTextForDir:(SeafDir *)dir {
    if (!dir) return @"";

    NSString *libraryName = @"";
    SeafRepo *repo = dir.repoId ? [dir.connection getRepo:dir.repoId] : nil;
    if (repo.name.length > 0) {
        libraryName = repo.name;
    } else if (dir.repoName.length > 0) {
        libraryName = dir.repoName;
    } else if ([dir isKindOfClass:[SeafRepo class]]) {
        libraryName = dir.name ?: @"";
    }

    NSString *path = dir.path ?: @"/";
    // Trim a trailing slash so we don't produce "66666/0/".
    if (path.length > 1 && [path hasSuffix:@"/"]) {
        path = [path substringToIndex:path.length - 1];
    }
    // At the library root the path is "/", so just show the library name.
    if (path.length <= 1) {
        return libraryName;
    }
    // `path` starts with "/", so appending yields "<libraryName>/sub/dir".
    return [libraryName stringByAppendingString:path];
}

#pragma mark - Content Bottom Constraint

- (void)setupContentBottomConstraint {
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [self.contentContainerView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor].active = YES;
}

#pragma mark - Embedding Tabs

/// Hide all tab contents without destroying them, so switching back to Libraries
/// restores the in-session browse stack instead of re-navigating to the last-upload path.
- (void)hideAllTabContents {
    if (self.childNavController) {
        self.childNavController.view.hidden = YES;
    }
    if (self.starredVC) {
        self.starredVC.view.hidden = YES;
    }
    if (self.recentVC) {
        self.recentVC.view.hidden = YES;
    }
}

- (void)showLibrariesTab {
    [self hideAllTabContents];

    if (!self.childNavController) {
        self.rootDirController = [[SeafShareDirViewController alloc] initWithSeafDir:self.connection.rootFolder];
        self.rootDirController.browseOnly = YES;
        self.rootDirController.useDestinationStyle = YES;

        self.childNavController = [[UINavigationController alloc] initWithRootViewController:self.rootDirController];
        self.childNavController.navigationBarHidden = YES;
        self.childNavController.view.translatesAutoresizingMaskIntoConstraints = NO;
        self.childNavController.delegate = self;

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

        // Only restore the last-upload path on first creation of the Libraries tab.
        [self navigateToRememberedPathIfNeeded];
    }

    self.childNavController.view.hidden = NO;
    [self.cardContainerView bringSubviewToFront:self.childNavController.view];
    // Keep the fixed return header above the libraries nav (both live on cardContainerView).
    if (self.fixedReturnHeaderView) {
        [self.cardContainerView bringSubviewToFront:self.fixedReturnHeaderView];
    }
    [self updateFixedHeaderVisibility];
}

#pragma mark - Remembered Path Navigation

- (void)navigateToRememberedPathIfNeeded {
    if (self.startRepoId.length == 0) return;

    SeafRepo *repo = [self.connection getRepo:self.startRepoId];
    if (!repo) return;

    if (repo.passwordRequired && ![self.connection getRepoPassword:repo.repoId]) {
        __weak typeof(self) weakSelf = self;
        [self popupSetRepoPassword:repo handler:^{
            __strong typeof(weakSelf) selfRef = weakSelf;
            if (!selfRef) return;
            [selfRef pushRememberedPathStackStartingFromRepo:repo];
        }];
        return;
    }

    [self pushRememberedPathStackStartingFromRepo:repo];
}

- (void)pushRememberedPathStackStartingFromRepo:(SeafRepo *)repo {
    [self pushShareDirViewControllerForDir:repo animated:NO];

    NSString *path = self.startPath.length > 0 ? self.startPath : @"/";
    if ([path isEqualToString:@"/"]) return;

    NSArray<NSString *> *comps = [path componentsSeparatedByString:@"/"];
    NSMutableString *accum = [NSMutableString stringWithString:@""];
    for (NSString *seg in comps) {
        if (seg.length == 0) continue;
        [accum appendFormat:@"/%@", seg];
        SeafDir *levelDir = [[SeafDir alloc] initWithConnection:self.connection
                                                            oid:nil
                                                         repoId:repo.repoId
                                                           perm:nil
                                                           name:seg
                                                           path:[accum copy]
                                                          mtime:0];
        levelDir.repoName = repo.name;
        [self pushShareDirViewControllerForDir:levelDir animated:NO];
    }
}

- (void)pushShareDirViewControllerForDir:(SeafDir *)dir animated:(BOOL)animated {
    SeafShareDirViewController *vc = [[SeafShareDirViewController alloc] initWithSeafDir:dir];
    vc.browseOnly = YES;
    vc.useDestinationStyle = YES;
    [self.childNavController pushViewController:vc animated:animated];
}

- (void)showStarredTab {
    [self hideAllTabContents];

    if (!self.starredVC) {
        self.starredVC = [[SeafShareStarredViewController alloc] initWithConnection:self.connection];

        [self addChildViewController:self.starredVC];
        self.starredVC.view.translatesAutoresizingMaskIntoConstraints = NO;
        [self.listContainerView addSubview:self.starredVC.view];
        [self.starredVC didMoveToParentViewController:self];

        [NSLayoutConstraint activateConstraints:@[
            [self.starredVC.view.topAnchor constraintEqualToAnchor:self.listContainerView.topAnchor],
            [self.starredVC.view.leadingAnchor constraintEqualToAnchor:self.listContainerView.leadingAnchor],
            [self.starredVC.view.trailingAnchor constraintEqualToAnchor:self.listContainerView.trailingAnchor],
            [self.starredVC.view.bottomAnchor constraintEqualToAnchor:self.listContainerView.bottomAnchor],
        ]];
    }

    self.starredVC.view.hidden = NO;
    [self.listContainerView bringSubviewToFront:self.starredVC.view];
    [self updateFixedHeaderVisibility];
}

- (void)showRecentTab {
    [self hideAllTabContents];

    if (!self.recentVC) {
        self.recentVC = [[SeafShareRecentViewController alloc] initWithConnection:self.connection];

        [self addChildViewController:self.recentVC];
        self.recentVC.view.translatesAutoresizingMaskIntoConstraints = NO;
        [self.listContainerView addSubview:self.recentVC.view];
        [self.recentVC didMoveToParentViewController:self];

        [NSLayoutConstraint activateConstraints:@[
            [self.recentVC.view.topAnchor constraintEqualToAnchor:self.listContainerView.topAnchor],
            [self.recentVC.view.leadingAnchor constraintEqualToAnchor:self.listContainerView.leadingAnchor],
            [self.recentVC.view.trailingAnchor constraintEqualToAnchor:self.listContainerView.trailingAnchor],
            [self.recentVC.view.bottomAnchor constraintEqualToAnchor:self.listContainerView.bottomAnchor],
        ]];
    }

    self.recentVC.view.hidden = NO;
    [self.listContainerView bringSubviewToFront:self.recentVC.view];
    [self updateFixedHeaderVisibility];
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    [self updateFixedHeaderVisibilityAnimated:animated];
}

#pragma mark - Actions

- (void)onBack:(id)sender {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)onCancel:(id)sender {
    [self.extensionContext completeRequestReturningItems:self.extensionContext.inputItems completionHandler:nil];
}

- (void)onConfirm:(id)sender {
    SeafDir *targetDir = [self selectedDirectory];
    // The libraries-tab root is the repo list itself (a SeafRepos), which is not a real
    // upload destination. Treat it like "nothing selected" so tapping OK there prompts the
    // user to pick a library instead of silently starting an upload to an invalid target.
    if (!targetDir || [targetDir isKindOfClass:[SeafRepos class]]) {
        [self alertWithTitle:NSLocalizedString(@"Please choose a library to save the file", @"Seafile")];
        return;
    }

    // Save path memory
    [self saveLastUsedPath:targetDir];

    // Start upload with popup progress
    [self loadInputsAndUploadToDir:targetDir];
}

#pragma mark - Upload Flow (popup dialog)

- (void)loadInputsAndUploadToDir:(SeafDir *)dir {
    self.uploadDirectory = dir;
    self.completedCount = 0;

    __weak typeof(self) weakSelf = self;
    [SeafInputItemsProvider loadInputs:self.extensionContext complete:^(BOOL result, NSArray *array, NSString *errorDisplayMessage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (result && array.count > 0) {
                weakSelf.ufiles = array;
                weakSelf.uploadFileCount = array.count;
                [weakSelf startUploadToDir:dir];
            } else {
                NSString *msg = errorDisplayMessage ?: @"Failed to load files";
                [weakSelf alertWithTitle:NSLocalizedString(msg, @"Seafile") handler:^{
                    [weakSelf done];
                }];
            }
        });
    }];
}

- (void)startUploadToDir:(SeafDir *)dir {
    SeafRepo *repo = [dir.connection getRepo:dir.repoId];
    // `repo` is authoritative when cached; fall back to the dir's own flag so a starred
    // encrypted library that isn't in the local repo cache is still treated as encrypted.
    BOOL encrypted = repo.encrypted || dir.encrypted;

    if (!encrypted) {
        [self checkOverwriteAndUploadToDir:dir withFiles:self.ufiles];
        return;
    }

    // Verifying/setting an encrypted library's password requires a real SeafRepo.
    if (!repo) {
        [self alertWithTitle:NSLocalizedString(@"Unable to load library information, please try again", @"Seafile") handler:^{
            [self done];
        }];
        return;
    }

    NSString *password = [dir.connection getRepoPassword:dir.repoId];
    if (password) {
        // A password is cached: verify it's still valid before uploading. If it has been
        // changed/expired on the server, ask the user to re-enter it.
        __weak typeof(self) weakSelf = self;
        [repo checkOrSetRepoPassword:password block:^(SeafBase *entry, int ret) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                if (ret == RET_SUCCESS) {
                    [strongSelf checkOverwriteAndUploadToDir:dir withFiles:strongSelf.ufiles];
                } else {
                    [strongSelf promptPasswordForRepo:repo thenUploadToDir:dir];
                }
            });
        }];
    } else {
        [self promptPasswordForRepo:repo thenUploadToDir:dir];
    }
}

/// Prompt for the encrypted library password (reusing the shared alert), then continue
/// the upload once the password is verified. Cancelling leaves the picker as-is.
- (void)promptPasswordForRepo:(SeafRepo *)repo thenUploadToDir:(SeafDir *)dir {
    __weak typeof(self) weakSelf = self;
    [self popupSetRepoPassword:repo handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf checkOverwriteAndUploadToDir:dir withFiles:strongSelf.ufiles];
    }];
}

- (void)checkOverwriteAndUploadToDir:(SeafDir *)dir withFiles:(NSArray *)files {
    NSMutableArray *existingNames = [NSMutableArray array];
    for (SeafUploadFile *ufile in files) {
        if ([dir nameExist:ufile.name]) {
            [existingNames addObject:ufile.name];
        }
    }

    if (existingNames.count > 0) {
        NSString *fileList = [existingNames componentsJoinedByString:@", "];
        NSString *message = NSLocalizedString(@"A file with the same name already exists, do you want to overwrite?", @"Seafile");

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:message
                                                                      message:fileList
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Overwrite", @"Seafile")
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            [self doStartUploadToDir:dir withFiles:files overwrite:YES];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile")
                                                  style:UIAlertActionStyleCancel
                                                handler:^(UIAlertAction *action) {
            [self done];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        [self doStartUploadToDir:dir withFiles:files overwrite:YES];
    }
}

- (void)doStartUploadToDir:(SeafDir *)dir withFiles:(NSArray *)files overwrite:(BOOL)overwrite {
    if (files.count == 0) {
        [self done];
        return;
    }

    // Show popup progress for the first file
    SeafUploadFile *firstFile = files[0];
    [self showUploadProgressForFile:firstFile totalCount:files.count];

    for (SeafUploadFile *ufile in files) {
        ufile.model.overwrite = overwrite;
        ufile.udir = dir;
        ufile.delegate = self;
        [ufile setCompletionBlock:^(SeafUploadFile *file, NSString *oid, NSError *error) {
            [self fileUploadComplete:file error:error];
        }];
        [SeafDataTaskManager.sharedObject addUploadTask:ufile];
    }
}

- (void)showUploadProgressForFile:(SeafUploadFile *)file totalCount:(NSInteger)total {
    // Keep the system title short; put the filename / progress into contentViewController
    // so the bar never overlaps the Cancel action (especially under iOS 26 Liquid Glass alerts).
    self.uploadAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Uploading", @"Seafile")
                                                          message:nil
                                                   preferredStyle:UIAlertControllerStyleAlert];

    UIViewController *contentVC = [[UIViewController alloc] init];
    UIView *contentView = contentVC.view;
    contentView.backgroundColor = [UIColor clearColor];

    UILabel *fileNameLabel = [[UILabel alloc] init];
    fileNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    fileNameLabel.text = file.name ?: @"";
    fileNameLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
    fileNameLabel.textColor = [SeafTheme secondaryText];
    fileNameLabel.textAlignment = NSTextAlignmentCenter;
    fileNameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    fileNameLabel.numberOfLines = 1;
    [contentView addSubview:fileNameLabel];
    self.uploadFileNameLabel = fileNameLabel;

    UIProgressView *progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progressView.translatesAutoresizingMaskIntoConstraints = NO;
    progressView.progress = 0.f;
    progressView.progressTintColor = [SeafTheme accentOrange];
    progressView.trackTintColor = [SeafTheme fill];
    progressView.layer.cornerRadius = 2.0;
    progressView.clipsToBounds = YES;
    [contentView addSubview:progressView];
    self.uploadProgressView = progressView;

    UILabel *countLabel = [[UILabel alloc] init];
    countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    countLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    countLabel.textColor = [SeafTheme secondaryText];
    countLabel.textAlignment = NSTextAlignmentCenter;
    BOOL showCount = total > 1;
    countLabel.hidden = !showCount;
    if (showCount) {
        countLabel.text = [NSString stringWithFormat:@"1 / %ld", (long)total];
    }
    [contentView addSubview:countLabel];
    self.uploadCountLabel = countLabel;

    // UIAlertController sizes contentViewController.view by its Auto Layout fitting size,
    // NOT by stretching it to the alert width. Neither UIProgressView (no intrinsic width)
    // nor the short filename label can widen the content, so without an explicit width the
    // content collapses to the filename's text width and leaves big side gaps. Pin an
    // explicit width on the progress bar (at <required so it yields on a narrow alert) to
    // drive the content width; the labels follow via leading/trailing. preferredContentSize
    // only contributes the height.
    CGFloat contentHeight = showCount ? 88.0 : 64.0;
    contentVC.preferredContentSize = CGSizeMake(270.0, contentHeight);

    NSLayoutConstraint *progressWidth = [progressView.widthAnchor constraintEqualToConstant:250.0];
    progressWidth.priority = UILayoutPriorityRequired - 1;

    [NSLayoutConstraint activateConstraints:@[
        [fileNameLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:8],
        [fileNameLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:0],
        [fileNameLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:0],

        [progressView.topAnchor constraintEqualToAnchor:fileNameLabel.bottomAnchor constant:16],
        [progressView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:0],
        [progressView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:0],
        [progressView.heightAnchor constraintEqualToConstant:4],
        progressWidth,

        [countLabel.topAnchor constraintEqualToAnchor:progressView.bottomAnchor constant:12],
        [countLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:0],
        [countLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:0],
        [countLabel.bottomAnchor constraintLessThanOrEqualToAnchor:contentView.bottomAnchor constant:-6],
    ]];

    // Undocumented but widely used; places content between title and actions.
    [self.uploadAlert setValue:contentVC forKey:@"contentViewController"];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile")
                                                          style:UIAlertActionStyleCancel
                                                        handler:^(UIAlertAction *action) {
        [SeafDataTaskManager.sharedObject cancelAllUploadTasks:self.uploadDirectory.connection];
        [self done];
    }];
    [self.uploadAlert addAction:cancelAction];

    [self presentViewController:self.uploadAlert animated:YES completion:nil];
}

#pragma mark - SeafUploadDelegate

- (void)uploadProgress:(SeafUploadFile *)file progress:(float)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.uploadProgressView.progress = progress;
        if (file.name.length > 0) {
            self.uploadFileNameLabel.text = file.name;
        }
        if (self.ufiles.count > 1) {
            self.uploadCountLabel.text = [NSString stringWithFormat:@"%ld / %ld",
                                          (long)(self.completedCount + 1),
                                          (long)self.ufiles.count];
        }
    });
}

- (void)uploadComplete:(BOOL)success file:(SeafUploadFile *)file oid:(NSString *)oid {
    if (success) {
        self.completedCount++;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.uploadProgressView.progress = 1.0f;
        });
    }
}

- (void)fileUploadComplete:(SeafUploadFile *)ufile error:(NSError *)error {
    self.uploadFileCount--;
    if (self.uploadFileCount <= 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [self.uploadAlert dismissViewControllerAnimated:YES completion:^{
                    [self alertWithTitle:NSLocalizedString(@"Failed to upload file", @"Seafile") handler:^{
                        [self done];
                    }];
                }];
            } else {
                // Brief delay so user can see 100% completion
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self.uploadAlert dismissViewControllerAnimated:YES completion:^{
                        [self done];
                    }];
                });
            }
        });
    }
}

- (void)done {
    [self.extensionContext completeRequestReturningItems:self.extensionContext.inputItems completionHandler:nil];
}

- (void)onCreateFolder:(id)sender {
    if (self.currentTab != SeafShareTabLibraries) return;

    SeafDir *currentDir = [self currentLibraryDirectory];
    if (!currentDir || !currentDir.editable) {
        [self alertWithTitle:NSLocalizedString(@"Please choose a library to save the file", @"Seafile")];
        return;
    }

    [self popupInputView:NSLocalizedString(@"New Folder", @"Seafile")
             placeholder:NSLocalizedString(@"New folder name", @"Seafile")
                  secure:NO
                 handler:^(NSString *input) {
        if (!input) return;
        if (input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Folder name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"Folder name invalid", @"Seafile")];
            return;
        }
        [[SeafFileOperationManager sharedManager] mkdir:input inDir:currentDir completion:^(BOOL success, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!success) {
                    [self alertWithTitle:NSLocalizedString(@"Failed to create folder", @"Seafile")];
                } else {
                    [currentDir loadContent:YES];
                }
            });
        }];
    }];
}

#pragma mark - Directory Helpers

- (SeafDir *)selectedDirectory {
    if (self.currentTab == SeafShareTabLibraries) {
        return [self currentLibraryDirectory];
    } else if (self.currentTab == SeafShareTabStarred) {
        return [self.starredVC selectedDirectory];
    } else if (self.currentTab == SeafShareTabRecent) {
        return [self.recentVC selectedDirectory];
    }
    return nil;
}

- (SeafDir *)currentLibraryDirectory {
    if (!self.childNavController) return nil;
    UIViewController *topVC = self.childNavController.topViewController;
    if ([topVC isKindOfClass:[SeafShareDirViewController class]]) {
        return ((SeafShareDirViewController *)topVC).currentDirectory;
    }
    return nil;
}

#pragma mark - Path Memory

- (void)saveLastUsedPath:(SeafDir *)dir {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:SEAFILE_SUITE_NAME];
    [defaults setObject:self.connection.accountIdentifier forKey:kShareLastAccount];
    [defaults setObject:dir.repoId ?: @"" forKey:kShareLastRepoId];
    [defaults setObject:dir.path ?: @"/" forKey:kShareLastPath];
    [defaults synchronize];

    [[SeafRecentDirsStore shared] addRecentDirectory:dir];
}

+ (NSDictionary *)lastUsedPathInfo {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:SEAFILE_SUITE_NAME];
    NSString *account = [defaults stringForKey:kShareLastAccount];
    NSString *repoId  = [defaults stringForKey:kShareLastRepoId];
    NSString *path    = [defaults stringForKey:kShareLastPath];

    if (account.length == 0 || repoId.length == 0) {
        NSUserDefaults *legacy = [[NSUserDefaults alloc] initWithSuiteName:APP_ID];
        account = [legacy stringForKey:kShareLastAccount];
        repoId  = [legacy stringForKey:kShareLastRepoId];
        path    = [legacy stringForKey:kShareLastPath];
        if (account.length > 0 && repoId.length > 0) {
            [defaults setObject:account forKey:kShareLastAccount];
            [defaults setObject:repoId forKey:kShareLastRepoId];
            [defaults setObject:path ?: @"/" forKey:kShareLastPath];
            [defaults synchronize];
        }
    }

    if (account.length > 0 && repoId.length > 0) {
        return @{
            @"account": account,
            @"repoId": repoId,
            @"path": path ?: @"/",
        };
    }
    return nil;
}

@end
