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
 * Sets item tint and translucency. Uses the system background on iPhone
 * starting in iOS 26, and the app's background and shadow elsewhere.
 * @param tabBar The tab bar to style
 */
+ (void)applyStandardAppearanceToTabBar:(UITabBar *)tabBar;

/**
 * Whether the tab bar lets content extend behind it.
 * Outside the system appearance path, only a vertical bar is translucent.
 * An opaque vertical bar can make child navigation controllers subtract the
 * entire window height, leaving the content 0pt tall.
 */
+ (BOOL)tabBarNeedsTranslucency:(UITabBar *)tabBar;

@end

NS_ASSUME_NONNULL_END
