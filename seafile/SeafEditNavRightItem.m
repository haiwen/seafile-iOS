//
//  SeafEditNavRightItem.m
//  seafileApp
//
//  Created by henry on 2025/3/25.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import "SeafEditNavRightItem.h"

@implementation SeafEditNavRightItem

- (instancetype)initWithTitle:(NSString *)title imageName:(NSString *)imageName target:(id)target action:(SEL)action {
    // Create custom container view
    UIView *customView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 90, 30)];
    customView.userInteractionEnabled = YES;
    
    // Add tap gesture recognizer
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:target action:action];
    [customView addGestureRecognizer:tapGesture];
    
    // Adjust offset for iPad
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        CGRect frame = customView.frame;
        frame.origin.x = -16;
        customView.frame = frame;
    }
    
    // Add icon
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(customView.frame.size.width - 20, 5, 20, 20)];
    imageView.image = [UIImage imageNamed:imageName];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    [customView addSubview:imageView];
    
    // Add text label
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, customView.frame.size.width - 20 - 5, 30)];
    label.text = NSLocalizedString(title, @"Seafile");
    label.font = [UIFont systemFontOfSize:18];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.5;
    label.numberOfLines = 1;
    label.textAlignment = NSTextAlignmentRight;
    label.textColor = BAR_COLOR;
    label.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    [customView addSubview:label];
    
    self = [super initWithCustomView:customView];
    if (self) {
    }
    return self;
}

@end
