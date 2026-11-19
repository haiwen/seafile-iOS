//
//  SeafActivitiesCell.m
//  seafileApp
//
//  Created by three on 2019/6/9.
//  Copyright © 2019 Seafile. All rights reserved.
//

#import "SeafActivitiesCell.h"
#import <SDWebImage/UIImageView+WebCache.h>
#import "SeafTheme.h"
#import "Constants.h"

@implementation SeafActivitiesCell

- (void)awakeFromNib {
    [super awakeFromNib];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    self.selectedBackgroundView = [[UIView alloc] init];
    self.selectedBackgroundView.backgroundColor = [UIColor clearColor];

    if (!self.cellBackgroundView) {
        UIView *bgView = [[UIView alloc] init];
        bgView.translatesAutoresizingMaskIntoConstraints = NO;
        bgView.backgroundColor = [SeafTheme primarySurface];
        bgView.clipsToBounds = YES;
        [self.contentView insertSubview:bgView atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [bgView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:SEAF_CARD_HORIZONTAL_PADDING],
            [bgView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-SEAF_CARD_HORIZONTAL_PADDING],
            [bgView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [bgView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        ]];
        self.cellBackgroundView = bgView;
    }

    // Set text colors
    self.authorLabel.textColor = [SeafTheme primaryText];
    // desLabel color is now driven by NSAttributedString from the model
    self.timeLabel.textColor = [SeafTheme secondaryText];
    self.repoNameLabel.textColor = BAR_COLOR_ORANGE;

    self.operationLabel.textColor = [SeafTheme operationText];
    self.operationContainer.backgroundColor = [UIColor colorWithRed:238.0/255.0 green:238.0/255.0 blue:238.0/255.0 alpha:1.0];
}

- (UIEdgeInsets)seaf_horizontalUnsafeOverlap
{
    UIView *ancestor = self.superview;
    UITableView *tableView = nil;
    while (ancestor) {
        if ([ancestor isKindOfClass:[UITableView class]]) {
            tableView = (UITableView *)ancestor;
            break;
        }
        ancestor = ancestor.superview;
    }
    if (!tableView) return UIEdgeInsetsZero;
    CGFloat tableWidth = CGRectGetWidth(tableView.bounds);
    CGFloat width = CGRectGetWidth(self.bounds);
    if (tableWidth < 1.0 || width < 1.0) return UIEdgeInsetsZero;
    UIEdgeInsets tableSafe = tableView.safeAreaInsets;
    CGRect rect = [self convertRect:self.bounds toView:tableView];
    CGFloat left = tableSafe.left - CGRectGetMinX(rect);
    CGFloat right = CGRectGetMaxX(rect) - (tableWidth - tableSafe.right);
    return UIEdgeInsetsMake(0, MAX(0.0, left), 0, MAX(0.0, right));
}

- (void)seaf_applyCardSeparatorInset
{
    UIEdgeInsets inset;
    if (self.isLastCell) {
        inset = UIEdgeInsetsMake(0, CGRectGetWidth(self.bounds), 0, 0);
    } else {
        UIEdgeInsets overlap = [self seaf_horizontalUnsafeOverlap];
        inset = UIEdgeInsetsMake(0,
                                  SEAF_SEPARATOR_LEFT_INSET + overlap.left,
                                  0,
                                  SEAF_SEPARATOR_RIGHT_INSET + overlap.right);
    }
    if (!UIEdgeInsetsEqualToEdgeInsets(self.separatorInset, inset)) {
        self.separatorInset = inset;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self seaf_applyCardSeparatorInset];
}

- (void)updateCellStyle:(BOOL)isFirstCell isLastCell:(BOOL)isLastCell {
    self.cellBackgroundView.layer.mask = nil;
    self.cellBackgroundView.layer.cornerRadius = 0;
    self.cellBackgroundView.layer.maskedCorners = 0;

    if (!isFirstCell && !isLastCell) {
        return;
    }

    self.cellBackgroundView.layer.cornerRadius = SEAF_CELL_CORNER;

    if (isFirstCell && isLastCell) {
        self.cellBackgroundView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
                                                      kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    } else if (isFirstCell) {
        self.cellBackgroundView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    } else {
        self.cellBackgroundView.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
}

- (void)updateSeparatorInset:(BOOL)isLastCell {
    self.isLastCell = isLastCell;
    if (isLastCell) {
        self.separatorInset = UIEdgeInsetsMake(0, self.bounds.size.width, 0, 0);
    } else {
        [self setNeedsLayout];
    }
}

- (void)showWithImage:(NSURL *)imageURL author:(NSString *)author operation:(NSString *)operation time:(NSString *)time attributedDetail:(NSAttributedString *)attributedDetail repoName:(NSString *)repoName {
    
    self.accountImageView.layer.cornerRadius = 20.0f;
    self.accountImageView.clipsToBounds = YES;
    UIImage *defaultAccountImage = [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"account" ofType:@"png"]];
    [self.accountImageView sd_setImageWithURL:imageURL placeholderImage:defaultAccountImage];
    
    self.repoNameLabel.text = repoName;
    self.authorLabel.text = author;
    self.timeLabel.text = time;
    self.desLabel.attributedText = attributedDetail;
    
    if (operation && operation.length > 0) {
        self.operationContainer.hidden = NO;
        self.operationLabel.hidden = NO;
        self.operationContainer.layer.cornerRadius = 3.0;
        self.operationContainer.layer.masksToBounds = YES;
        self.operationLabel.text = operation;
    } else {
        self.operationContainer.hidden = YES;
        self.operationLabel.hidden = YES;
        self.operationLabel.text = @"";
    }
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
