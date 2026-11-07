//
//  SeafNavigationBarStyler.h
//  seafileApp
//
//  Created by Seafile Ltd. on 2025/4/18.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Utility class for applying consistent navigation bar styling across the app
 */
@interface SeafNavigationBarStyler : NSObject

/**
 * Apply standard navigation bar appearance settings to a navigation controller
 * @param navigationController The navigation controller to style
 */
+ (void)applyStandardAppearanceToNavigationController:(UINavigationController *)navigationController;

/**
 * Create a custom title view with controlled width for navigation bar
 * @param title The title text to display
 * @param maxWidthPercentage The percentage of screen width (0.0-1.0) that the title should use
 * @param viewController The view controller that will use this title
 * @return A UILabel configured as a title view
 */
+ (UILabel *)createCustomTitleViewWithText:(NSString *)title 
                      maxWidthPercentage:(CGFloat)maxWidthPercentage
                           viewController:(UIViewController *)viewController;

/**
 * Update an existing title view with new text
 * @param titleView The existing title view (UILabel)
 * @param title The new title text
 */
+ (void)updateTitleView:(UILabel *)titleView withText:(NSString *)title;

/**
 * Create a custom back button with standard appearance
 * @param target The target object for the button action
 * @param action The action selector to call when button is pressed
 * @param color The tint color for the button image (nil for default black)
 * @return A configured UIBarButtonItem
 */
+ (UIBarButtonItem *)createBackButtonWithTarget:(id)target action:(SEL)action color:(nullable UIColor *)color;

/// `arrowLeft_black` drawn at a fixed 10×20 pt as a template image. The asset
/// is an 18×36 px 1x bitmap; image edge insets stretch it into whatever content
/// box the button has, which on iPhone Duo made the chevron tall, thin, and blurry.
+ (UIImage *)backArrowImage;

/// Page backdrop for card-style lists (Duo outer display: gray fills camera/status gutters).
+ (void)applyListPageBackgroundToViewController:(UIViewController *)viewController;

/// Pin a scroll view to the host view's safe area so separators/backgrounds do not bleed into layout margins.
+ (void)pinViewToSafeArea:(UIView *)subview inHostView:(UIView *)hostView;

/// Top and horizontal edges stay in the safe area. The bottom edge follows the
/// host view, so rows remain visible in the bottom safe area (home indicator).
+ (void)pinViewToSafeAreaExtendingToHostBottom:(UIView *)subview inHostView:(UIView *)hostView;

+ (void)updateTableViewBackgroundViewFrame:(UITableView *)tableView;

@end

NS_ASSUME_NONNULL_END 