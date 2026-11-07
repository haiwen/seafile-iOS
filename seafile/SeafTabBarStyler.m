//
//  SeafTabBarStyler.m
//  seafile
//

#import "SeafTabBarStyler.h"
#import "SeafTheme.h"
#import "Constants.h"

@implementation SeafTabBarStyler

+ (void)applyStandardAppearanceToTabBar:(UITabBar *)tabBar {
    tabBar.tintColor = [SeafTheme accentOrange];
    tabBar.unselectedItemTintColor = [SeafTheme secondaryText];
    tabBar.translucent = [self tabBarNeedsTranslucency:tabBar];

    UITabBarAppearance *appearance = [UITabBarAppearance new];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = [SeafTheme primaryBackgroundColor];
    appearance.shadowColor = [UIColor opaqueSeparatorColor];
    for (UITabBarItemAppearance *item in @[appearance.stackedLayoutAppearance,
                                          appearance.inlineLayoutAppearance,
                                          appearance.compactInlineLayoutAppearance]) {
        item.normal.iconColor = [SeafTheme secondaryText];
        item.normal.titleTextAttributes = @{NSForegroundColorAttributeName: [SeafTheme secondaryText]};
        item.selected.iconColor = [SeafTheme accentOrange];
        item.selected.titleTextAttributes = @{NSForegroundColorAttributeName: [SeafTheme accentOrange]};
    }
    tabBar.standardAppearance = appearance;
    tabBar.scrollEdgeAppearance = appearance;
}

+ (BOOL)tabBarNeedsTranslucency:(UITabBar *)tabBar {
    CGSize size = tabBar.bounds.size;
    return size.height > size.width;
}

@end
