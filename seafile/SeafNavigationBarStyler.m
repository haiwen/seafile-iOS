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
    if (@available(iOS 11.0, *)) {
        navigationController.navigationBar.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [SeafTheme primaryText]};
    }

    navigationController.navigationBar.barStyle = UIBarStyleDefault;

    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [SeafTheme primarySurface];
        appearance.shadowColor = [SeafTheme separator];
        appearance.titleTextAttributes = titleAttributes;
        appearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [SeafTheme primaryText]};

        navigationController.navigationBar.standardAppearance = appearance;
        navigationController.navigationBar.scrollEdgeAppearance = appearance;

        navigationController.navigationBar.tintColor = [SeafTheme primaryText];
    } else {
        navigationController.navigationBar.barTintColor = [SeafTheme primarySurface];
        navigationController.navigationBar.translucent = NO;
        navigationController.navigationBar.tintColor = [SeafTheme primaryText];

        navigationController.navigationBar.shadowImage = [self createSinglePixelImageWithColor:[SeafTheme separator]];
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