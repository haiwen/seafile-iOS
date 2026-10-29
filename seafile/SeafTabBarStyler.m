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
    tabBar.translucent = [self tabBarNeedsTranslucency:tabBar];

    UITabBarAppearance *appearance = [UITabBarAppearance new];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = [SeafTheme primaryBackgroundColor];
    appearance.shadowColor = [UIColor opaqueSeparatorColor];
    tabBar.standardAppearance = appearance;
    tabBar.scrollEdgeAppearance = appearance;
}

+ (BOOL)tabBarNeedsTranslucency:(UITabBar *)tabBar {
    CGSize size = tabBar.bounds.size;
    return size.height > size.width;
}

@end
