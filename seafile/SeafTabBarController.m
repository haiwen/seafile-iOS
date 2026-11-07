//
//  SeafTabBarController.m
//  seafile
//

#import "SeafTabBarController.h"
#import "SeafTabBarStyler.h"

@implementation SeafTabBarController

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    BOOL translucent = [SeafTabBarStyler tabBarNeedsTranslucency:self.tabBar];
    if (self.tabBar.translucent == translucent)
        return;
    self.tabBar.translucent = translucent;
    // Children size themselves against the bar on their next layout pass.
    [self.view setNeedsLayout];
    [self.selectedViewController.view setNeedsLayout];
}

@end
