//
//  SeafNavigationBarStyler.m
//  seafileApp
//
//  Created by Seafile Ltd. on 2025/4/18.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import "SeafNavigationBarStyler.h"

@implementation SeafNavigationBarStyler

#pragma mark - Navigation Bar Appearance

+ (void)applyStandardAppearanceToNavigationController:(UINavigationController *)navigationController {
    // Set navigation bar title text attributes
    NSDictionary *titleAttributes = @{NSForegroundColorAttributeName: [UIColor blackColor]};
    navigationController.navigationBar.titleTextAttributes = titleAttributes;
    
    // Set navigation bar style
    navigationController.navigationBar.barStyle = UIBarStyleDefault;
    
    // Configure navigation bar appearance based on iOS version
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor whiteColor];
        appearance.shadowColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.1]; // Subtle shadow
        
        navigationController.navigationBar.standardAppearance = appearance;
        navigationController.navigationBar.scrollEdgeAppearance = appearance;
        
        // Ensure navigation bar buttons are dark to contrast with white background
        navigationController.navigationBar.tintColor = [UIColor blackColor];
    } else {
        // Handle styling for iOS versions below 15
        navigationController.navigationBar.barTintColor = [UIColor whiteColor];
        navigationController.navigationBar.translucent = NO;
        navigationController.navigationBar.tintColor = [UIColor blackColor];
        
        // Add bottom hairline
        navigationController.navigationBar.shadowImage = [self createSinglePixelImageWithColor:[UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.1]];
    }
}

#pragma mark - Title View

+ (UILabel *)createCustomTitleViewWithText:(NSString *)title maxWidthPercentage:(CGFloat)maxWidthPercentage viewController:(UIViewController *)viewController {
    // Create custom title view to control width
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title ?: @"";
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]; // Use system font
    titleLabel.textColor = [UIColor blackColor];
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
    // Create more precise back button using custom view
    UIButton *customBackButton = [UIButton buttonWithType:UIButtonTypeCustom];
    
    // Get original image
    UIImage *originalImage = [UIImage imageNamed:@"arrowLeft_black"];
    
    // Apply tint if color specified
    if (color) {
        originalImage = [self imageWithTintColor:color image:originalImage];
    }
    
    [customBackButton setImage:originalImage forState:UIControlStateNormal];
    
    // Set button size and hit area
    customBackButton.frame = CGRectMake(0, 0, 30, 44); // Increase touch area
    
    // Set image padding to ensure correct icon size and position
    customBackButton.imageEdgeInsets = UIEdgeInsetsMake(12, 0, 12, 18);

    // Set image view content mode to ensure proper image scaling
    customBackButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    
    // Add tap event
    [customBackButton addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    
    // Create UIBarButtonItem with custom view
    UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithCustomView:customBackButton];
    
    return backButton;
}

// Maintain method without tint parameter for backward compatibility
+ (UIBarButtonItem *)createBackButtonWithTarget:(id)target action:(SEL)action {
    return [self createBackButtonWithTarget:target action:action color:nil];
}

#pragma mark - Utility Methods

// Helper method to create a 1px image for the shadow
+ (UIImage *)createSinglePixelImageWithColor:(UIColor *)color {
    CGRect rect = CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
    UIGraphicsBeginImageContext(rect.size);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGContextSetFillColorWithColor(context, [color CGColor]);
    CGContextFillRect(context, rect);
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

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