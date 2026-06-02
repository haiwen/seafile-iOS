//
//  SeafTabBarStyler.m
//  seafile
//

#import "SeafTabBarStyler.h"
#import "SeafTheme.h"
#import "Constants.h"

@implementation SeafTabBarStyler

+ (void)applyStandardAppearanceToTabBar:(UITabBar *)tabBar {
    tabBar.tintColor = BAR_COLOR_ORANGE;
    tabBar.translucent = NO;

    if (@available(iOS 15.0, *)) {
        UITabBarAppearance *appearance = [UITabBarAppearance new];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [SeafTheme primaryBackgroundColor];
        appearance.shadowColor = [UIColor opaqueSeparatorColor];
        tabBar.standardAppearance = appearance;
        tabBar.scrollEdgeAppearance = appearance;
    }
}

@end
