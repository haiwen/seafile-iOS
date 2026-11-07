//
//  SeafNavigationBarStyler.m
//  seafileApp
//
//  Created by Seafile Ltd. on 2025/4/18.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import "SeafNavigationBarStyler.h"
#import "SeafTheme.h"

@implementation SeafNavigationBarStyler

#pragma mark - Navigation Bar Appearance

+ (void)applyStandardAppearanceToNavigationController:(UINavigationController *)navigationController {
    NSDictionary *titleAttributes = @{NSForegroundColorAttributeName: [SeafTheme primaryText]};
    navigationController.navigationBar.titleTextAttributes = titleAttributes;
    navigationController.navigationBar.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [SeafTheme primaryText]};

    navigationController.navigationBar.barStyle = UIBarStyleDefault;

    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = [SeafTheme primarySurface];
    appearance.shadowColor = [UIColor opaqueSeparatorColor];
    appearance.titleTextAttributes = titleAttributes;
    appearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [SeafTheme primaryText]};

    navigationController.navigationBar.standardAppearance = appearance;
    navigationController.navigationBar.scrollEdgeAppearance = appearance;

    navigationController.navigationBar.tintColor = [SeafTheme primaryText];
    navigationController.view.backgroundColor = [SeafTheme primaryBackgroundColor];
}

#pragma mark - Back arrow

+ (UIImage *)backArrowImage
{
    // The same symbol UIKit uses for the system back button, so custom back items
    // (modal gallery, previews, search) look like the pushed-list back button.
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithWeight:UIImageSymbolWeightSemibold];
    return [UIImage systemImageNamed:@"chevron.backward" withConfiguration:config];
}

#pragma mark - List page chrome

+ (void)applyListPageBackgroundToViewController:(UIViewController *)viewController
{
    UIColor *background = [SeafTheme primaryBackgroundColor];
    viewController.view.backgroundColor = background;
    viewController.navigationController.view.backgroundColor = background;
}

+ (void)pinView:(UIView *)subview inHostView:(UIView *)hostView extendPastBottomSafeArea:(BOOL)extendPastBottomSafeArea
{
    subview.translatesAutoresizingMaskIntoConstraints = NO;
    if (subview.superview != hostView) {
        [hostView addSubview:subview];
    }
    UILayoutGuide *guide = hostView.safeAreaLayoutGuide;
    NSLayoutYAxisAnchor *bottomAnchor = extendPastBottomSafeArea ? hostView.bottomAnchor : guide.bottomAnchor;
    [NSLayoutConstraint activateConstraints:@[
        [subview.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [subview.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [subview.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [subview.bottomAnchor constraintEqualToAnchor:bottomAnchor],
    ]];
}

+ (void)pinViewToSafeArea:(UIView *)subview inHostView:(UIView *)hostView
{
    [self pinView:subview inHostView:hostView extendPastBottomSafeArea:NO];
}

+ (void)pinViewToSafeAreaExtendingToHostBottom:(UIView *)subview inHostView:(UIView *)hostView
{
    [self pinView:subview inHostView:hostView extendPastBottomSafeArea:YES];
}

+ (void)updateTableViewBackgroundViewFrame:(UITableView *)tableView
{
    if (tableView.backgroundView) {
        tableView.backgroundView.frame = tableView.bounds;
    }
}

#pragma mark - Title View

+ (UILabel *)createCustomTitleViewWithText:(NSString *)title maxWidthPercentage:(CGFloat)maxWidthPercentage viewController:(UIViewController *)viewController {
    // Create custom title view to control width
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title ?: @"";
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]; // Use system font
    titleLabel.textColor = [SeafTheme primaryText];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    
    // Calculate maximum width - specified percentage of screen width
    CGFloat maxWidth = viewController.view.bounds.size.width * maxWidthPercentage;
    
    // Set label's maximum width
    titleLabel.frame = CGRectMake(0, 0, maxWidth, 44);
    titleLabel.adjustsFontSizeToFitWidth = YES; // Allow font to shrink to fit available space
    titleLabel.minimumScaleFactor = 0.8; // Minimum scale factor
    
    return titleLabel;
}

+ (void)updateTitleView:(UILabel *)titleView withText:(NSString *)title {
    if ([titleView isKindOfClass:[UILabel class]]) {
        titleView.text = title ?: @"";
    }
}

#pragma mark - Back Button

+ (UIBarButtonItem *)createBackButtonWithTarget:(id)target action:(SEL)action color:(nullable UIColor *)color {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:[self backArrowImage]
                                                          style:UIBarButtonItemStylePlain
                                                         target:target action:action];
    item.title = NSLocalizedString(@"Back", @"Seafile");
    item.accessibilityLabel = item.title;
    item.accessibilityIdentifier = @"navigation_back_button";
    item.tintColor = color ?: [SeafTheme glassBarIconColor];
    return item;
}

+ (UIBarButtonItem *)createCloseButtonWithTarget:(id)target action:(SEL)action {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                       target:target action:action];
    item.accessibilityLabel = NSLocalizedString(@"Close", @"Seafile");
    item.accessibilityIdentifier = @"navigation_close_button";
    return item;
}

// Maintain method without tint parameter for backward compatibility
+ (UIBarButtonItem *)createBackButtonWithTarget:(id)target action:(SEL)action {
    return [self createBackButtonWithTarget:target action:action color:nil];
}

#pragma mark - Utility Methods

// Helper method to tint an image with a specific color
+ (UIImage *)imageWithTintColor:(UIColor *)tintColor image:(UIImage *)image {
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    CGRect rect = CGRectMake(0, 0, image.size.width, image.size.height);
    
    [image drawInRect:rect];
    [tintColor set];
    UIRectFillUsingBlendMode(rect, kCGBlendModeSourceAtop);
    
    UIImage *tintedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return tintedImage;
}

@end
