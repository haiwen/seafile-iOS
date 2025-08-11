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
    // Create container with provisional width; will resize after measuring text
    SeafNavLeftItem *view = [[SeafNavLeftItem alloc] initWithFrame:CGRectMake(0, 0, 10, 44)];

    BOOL needsBackButton = ((directory && ![directory isKindOfClass:[SeafRepos class]]) || title != nil);
    CGFloat leftPadding = needsBackButton ? 30.0f : 5.0f;
    CGFloat rightPadding = 6.0f;

    if (needsBackButton) {
        UIButton *customButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [customButton setImage:[UIImage imageNamed:@"arrowLeft_black"] forState:UIControlStateNormal];
        customButton.frame = CGRectMake(0, 0, 30, 44);
        customButton.imageEdgeInsets = UIEdgeInsetsMake(12, 0, 12, 18);
        customButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [customButton addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
        [view addSubview:customButton];
    }

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.text = title ?: directory.name;
    titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor blackColor];
    titleLabel.numberOfLines = 1;
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    // Auto-fit: allow shrinking up to 2pt (20 -> 18)
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = (18.0f / 20.0f);
    titleLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;

    // Measure required width for the title text
    CGSize constraint = CGSizeMake(CGFLOAT_MAX, 44);
    CGRect textRect = [titleLabel.text boundingRectWithSize:constraint
                                                    options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                 attributes:@{NSFontAttributeName: titleLabel.font}
                                                    context:nil];

    CGFloat titleWidth = ceil(textRect.size.width);

    // Cap the maximum width to avoid overlapping other nav items
    CGFloat maxAllowedWidth = MIN([UIScreen mainScreen].bounds.size.width * 0.7f, 600.0f);
    CGFloat totalWidth = MIN(leftPadding + titleWidth + rightPadding, maxAllowedWidth);

    titleLabel.frame = CGRectMake(leftPadding, 0, totalWidth - leftPadding - rightPadding, 44);
    [view addSubview:titleLabel];

    // Resize container to fit content
    CGRect frame = view.frame;
    frame.size.width = totalWidth;
    view.frame = frame;

    return view;
}

@end
