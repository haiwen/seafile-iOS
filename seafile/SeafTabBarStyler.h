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

@end

NS_ASSUME_NONNULL_END
