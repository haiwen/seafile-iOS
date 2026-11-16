//
//  IntelligentSplitViewController.m
//  From TexLege by Gregory S. Combs
//
//  Released under the Creative Commons Attribution 3.0 Unported License
//  Please see the included license page for more information.
//
//  In a nutshell, you can use this, just attribute this to me in your "thank you" notes or about box.
//

#import "IntelligentSplitViewController.h"
#import "SeafDetailViewController.h"

@implementation IntelligentSplitViewController

/// Sidebar width. The default 320pt leaves about 26pt for the folder title once
/// the back button and the four trailing glass buttons (search, view mode, more,
/// and the sidebar button UIKit adds on iOS 26) are laid out, so UIKit truncates
/// it to "…". 380pt leaves about 86pt.
static const CGFloat kPrimaryColumnWidth = 380.0;

- (instancetype)initWithPrimaryNavigationController:(UINavigationController *)primary
                     secondaryNavigationController:(UINavigationController *)secondary {
    self = [super initWithStyle:UISplitViewControllerStyleDoubleColumn];
    if (self) {
        [self setViewController:primary forColumn:UISplitViewControllerColumnPrimary];
        [self setViewController:secondary forColumn:UISplitViewControllerColumnSecondary];
        self.delegate = self;
        self.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
    }
    return self;
}

- (UINavigationController *)primaryNavigationController {
    return (UINavigationController *)[self viewControllerForColumn:UISplitViewControllerColumnPrimary];
}

- (UINavigationController *)secondaryNavigationController {
    return (UINavigationController *)[self viewControllerForColumn:UISplitViewControllerColumnSecondary];
}

- (UISplitViewControllerColumn)splitViewController:(UISplitViewController *)splitViewController
        topColumnForCollapsingToProposedTopColumn:(UISplitViewControllerColumn)proposedTopColumn {
    UIViewController *detail = self.secondaryNavigationController.topViewController;
    // UIKit's default may put the empty preview/logo on top of the list.
    if ([detail isKindOfClass:SeafDetailViewController.class] &&
        !((SeafDetailViewController *)detail).preViewItem) {
        return UISplitViewControllerColumnPrimary;
    }
    return proposedTopColumn;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.maximumPrimaryColumnWidth = kPrimaryColumnWidth;
    self.preferredPrimaryColumnWidth = kPrimaryColumnWidth;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self updatePrimaryColumnTopInset];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updatePrimaryColumnTopInset];
}

/// On iOS 26 the sidebar floats below the top tab bar (its column starts where the detail
/// column's safe area does), yet UIKit still gives the primary navigation controller the
/// tab bar's height as a top inset. That puts a blank band above the sidebar's navigation
/// bar and drops its title row below the detail bar's. Cancel only the part already below
/// the tab bar; reset whenever the columns are not side by side.
- (void)updatePrimaryColumnTopInset {
    if (@available(iOS 26.0, *)) {
        UIViewController *primary = self.primaryNavigationController;
        UIView *primaryView = primary.viewIfLoaded;
        if (!primaryView.window) return;
        CGFloat inset = 0;
        UIView *secondaryView = self.secondaryNavigationController.viewIfLoaded;
        if (!self.collapsed && secondaryView.window) {
            // The tab bar's overlay ends where the detail column's safe area begins.
            CGFloat overlayBottom = [secondaryView convertPoint:CGPointMake(0, secondaryView.safeAreaInsets.top) toView:nil].y;
            CGFloat primaryTop = [primaryView convertPoint:CGPointZero toView:nil].y;
            CGFloat needed = MAX(0, overlayBottom - primaryTop);
            CGFloat systemTop = primaryView.safeAreaInsets.top - primary.additionalSafeAreaInsets.top;
            if (systemTop > needed + 0.5) {
                inset = needed - systemTop;
            }
        }
        UIEdgeInsets additional = primary.additionalSafeAreaInsets;
        if (fabs(additional.top - inset) < 0.5) return;
        additional.top = inset;
        primary.additionalSafeAreaInsets = additional;
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    // Settle the inset after UIKit finishes expanding or collapsing the columns.
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self updatePrimaryColumnTopInset];
    }];
}

@end
