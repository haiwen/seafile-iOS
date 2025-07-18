//
//  SeafNavLeftItem.m
//  seafileApp
//
//  Created by henry on 2025/3/24.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import "SeafNavLeftItem.h"
#import "SeafDir.h"
#import "SeafRepos.h" // Used to determine directory type

@implementation SeafNavLeftItem

+ (instancetype)navLeftItemWithDirectory:(nullable SeafDir *)directory title:(nullable NSString *)title target:(id)target action:(SEL)action {
    SeafNavLeftItem *view = [[SeafNavLeftItem alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
    
    // Create title label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    
    // If the directory is not of SeafRepos type, or if a title is provided (implying a custom view that needs a back button)
    if ((directory && ![directory isKindOfClass:[SeafRepos class]]) || title) {
        UIButton *customButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [customButton setImage:[UIImage imageNamed:@"arrowLeft_black"] forState:UIControlStateNormal];
        // Expand button touch area
        customButton.frame = CGRectMake(0, 0, 30, 44);
        customButton.imageEdgeInsets = UIEdgeInsetsMake(12, 0, 12, 18);
        customButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [customButton addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
        [view addSubview:customButton];
        
        titleLabel.frame = CGRectMake(30, 0, 210, 44);
    } else {
        titleLabel.frame = CGRectMake(5, 0, 210, 44);
    }
    
    titleLabel.text = title ?: directory.name;
    titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor blackColor];
    [view addSubview:titleLabel];
    
    return view;
}

@end
