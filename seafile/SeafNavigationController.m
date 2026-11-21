//
//  SeafNavigationController.m
//  seafile
//

#import "SeafNavigationController.h"

@implementation SeafNavigationController

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        // Set this before UIKit starts the transition so its animation and
        // safe-area handling also work for interactive back navigation.
        viewController.hidesBottomBarWhenPushed = self.viewControllers.count > 0;
    }
    [super pushViewController:viewController animated:animated];
}

- (void)configureTabBarVisibilityForViewControllers:(NSArray<UIViewController *> *)viewControllers
{
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone)
        return;
    // Locating a starred file rebuilds the entire folder path without a push.
    [viewControllers enumerateObjectsUsingBlock:^(UIViewController *controller, NSUInteger index, BOOL *stop) {
        controller.hidesBottomBarWhenPushed = index > 0;
    }];
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers
{
    [self configureTabBarVisibilityForViewControllers:viewControllers];
    [super setViewControllers:viewControllers];
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated
{
    [self configureTabBarVisibilityForViewControllers:viewControllers];
    [super setViewControllers:viewControllers animated:animated];
}

@end
