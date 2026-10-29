//
//  SeafTabBarStyler.h
//  seafile
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Utility class for applying consistent tab bar styling across the app.
 * Centralizes all UITabBar appearance configuration.
 */
@interface SeafTabBarStyler : NSObject

/**
 * Apply standard tab bar appearance to a specific tab bar instance.
 * Sets tintColor, translucent, backgroundColor, and shadowColor.
 * @param tabBar The tab bar to style
 */
+ (void)applyStandardAppearanceToTabBar:(UITabBar *)tabBar;

/**
 * Whether the tab bar must be translucent for its current placement.
 * An opaque bar makes child navigation controllers subtract its height from
 * theirs; when iOS lays the bar out vertically along a side (iPhone Duo's outer
 * display) that height is the whole window, leaving the content 0pt tall.
 */
+ (BOOL)tabBarNeedsTranslucency:(UITabBar *)tabBar;

@end

NS_ASSUME_NONNULL_END
