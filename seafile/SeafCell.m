//
//  SeafCell.m
//  seafile
//
//  Created by Wang Wei on 1/19/13.
//  Copyright (c) 2013 Seafile Ltd. All rights reserved.
//

#import "SeafCell.h"
#import "Utils.h"
#import "SeafTheme.h"

@implementation SeafCell
@synthesize imageView;
@synthesize textLabel;
@synthesize detailTextLabel;
@synthesize progressView;
@synthesize checkboxImageView;
@synthesize checkboxWidthConstraint;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        // Set cell background color to transparent
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        // Disable default selection background view
        self.selectedBackgroundView = [[UIView alloc] init];
        self.selectedBackgroundView.backgroundColor = [UIColor clearColor];
        // Disable multiple selection background
        self.multipleSelectionBackgroundView = [[UIView alloc] init];
        self.multipleSelectionBackgroundView.backgroundColor = [UIColor clearColor];
        _isStarredCell = NO;
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    // Disable default selection background view
    self.selectedBackgroundView = [[UIView alloc] init];
    self.selectedBackgroundView.backgroundColor = [UIColor clearColor];
    // Disable multiple selection background
    self.multipleSelectionBackgroundView = [[UIView alloc] init];
    self.multipleSelectionBackgroundView.backgroundColor = [UIColor clearColor];
    _isStarredCell = NO;
    
    // Initialize checkbox image view
    if (!self.checkboxImageView) {
        self.checkboxImageView = [[UIImageView alloc] init];
        self.checkboxImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.checkboxImageView];
        
        // Add constraints
        self.checkboxWidthConstraint = [self.checkboxImageView.widthAnchor constraintEqualToConstant:0];
        self.checkboxWidthConstraint.active = YES;
        
        [NSLayoutConstraint activateConstraints:@[
            [self.checkboxImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-15],
            [self.checkboxImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.checkboxImageView.heightAnchor constraintEqualToConstant:24],
        ]];
    }
    
    // Set basic properties for cellBackgroundView
    self.cellBackgroundView.backgroundColor = [SeafTheme primarySurface];
    self.cellBackgroundView.clipsToBounds = YES;

    // Add rounded corners to the imageView
    self.imageView.layer.cornerRadius = 5.0f;
}

/// How far this cell still overlaps the table's horizontal unsafe area.
/// File-list tables are pinned inside the safe area, so this is zero and the
/// 23/16 separator inset stays put. Starred is a full-bleed table view
/// controller; on iPhone Duo's outer display the right ~84pt is the camera
/// column, and a cell-edge inset would draw the separator through it.
/// Measured from the table, same as settings, so a content view that is
/// already inset is not inset a second time.
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
    // Assigning separatorInset can re-enter layout. Skip when unchanged.
    if (!UIEdgeInsetsEqualToEdgeInsets(self.separatorInset, inset)) {
        self.separatorInset = inset;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self seaf_applyCardSeparatorInset];
}

- (void)updateCellStyle:(BOOL)isFirstCell isLastCell:(BOOL)isLastCell {
    // Reset corner radius
    self.cellBackgroundView.layer.mask = nil;
    self.cellBackgroundView.layer.cornerRadius = 0;
    self.cellBackgroundView.layer.maskedCorners = 0;
    
    if (!isFirstCell && !isLastCell) {
        // No corner radius for middle cells
        return;
    }
    
    // Set corner radius
    self.cellBackgroundView.layer.cornerRadius = SEAF_CELL_CORNER;
    
    if (isFirstCell && isLastCell) {
        // If it's both the first and last row, all four corners are rounded
        self.cellBackgroundView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
                                                     kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    } else if (isFirstCell) {
        // First row, top two corners are rounded
        self.cellBackgroundView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    } else {
        // Last row, bottom two corners are rounded
        self.cellBackgroundView.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
}

- (void)updateCheckboxImageForSelected:(BOOL)selected
{
    NSString *imageName = selected ? @"ic_checkbox_checked" : @"ic_checkbox_unchecked";
    UIImage *image = [UIImage imageNamed:imageName];
    if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.checkboxImageView.tintColor = selected
            ? [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.7]
            : [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.2];
    } else {
        image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        self.checkboxImageView.tintColor = nil;
    }
    self.checkboxImageView.image = image;
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    // Avoid using system default editing style
//    [super setEditing:editing animated:animated];
    self.isUserEditing = editing;
    if (editing) {
        [self updateCheckboxImageForSelected:self.isSelected];
        self.checkboxWidthConstraint.constant = 24;
    } else {
        self.checkboxImageView.image = nil;
        self.checkboxImageView.tintColor = nil;
        self.checkboxWidthConstraint.constant = 0;
    }
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    // Don't call super method, completely override default behavior
     [super setSelected:selected animated:animated];
    
    // Handle checkbox only in editing mode
    if (self.isUserEditing) {
        [self updateCheckboxImageForSelected:selected];
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]
        && self.isUserEditing) {
        [self updateCheckboxImageForSelected:self.isSelected];
    }
}

- (void)reset
{
    self.detailTextLabel.text = nil;
    self.detailTextLabel.textColor = Utils.cellDetailTextTextColor;
    self.badgeImage.hidden = true;
    self.badgeLabel.hidden = true;
    self.cacheStatusView.hidden = true;
    self.progressView.hidden = true;
    
    // Also clears a Document-style top crop left on the layer by the previous file.
    [Utils setThumbImage:nil onImageView:self.imageView style:SeafThumbPreviewStyleIcon];

    self.moreButton.hidden = self.isStarredCell ? NO : YES;
    [self resetCellFile];
}

// Cancel thumb task, clear cell seafile, and clear cached thumbnail image in memory
- (void)resetCellFile {
    if (self.cellSeafFile){
        [self.cellSeafFile cancelNotDisplayThumb];
        self.cellSeafFile = nil;
    }
}

- (IBAction)moreButtonTouch:(id)sender {
    if (self.moreButtonBlock) {
        self.moreButtonBlock(self.cellIndexPath);
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

@end
