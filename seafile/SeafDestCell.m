//
//  SeafDestCell.m
//  seafile
//

#import "SeafDestCell.h"

@implementation SeafDestCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];

    // Build subviews programmatically (table provides background & separators)

    UIImageView *icon = [[UIImageView alloc] init];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.layer.cornerRadius = 5.0;
    icon.clipsToBounds = YES;
    [self.contentView addSubview:icon];
    self.imageView = icon;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    title.textColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    title.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.contentView addSubview:title];
    self.textLabel = title;

    UILabel *sub = [[UILabel alloc] init];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    sub.font = [UIFont systemFontOfSize:11];
    sub.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    [self.contentView addSubview:sub];
    self.detailTextLabel = sub;

    // Constraints (align to table provided margins; no per-cell background card):
    [NSLayoutConstraint activateConstraints:@[
        // Icon 44x44 centered vertically, leading ~ content leading + 16 (similar to leadingMargin+4)
        [icon.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor constant:4],
        [icon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:36],
        [icon.heightAnchor constraintEqualToConstant:36],

        // Title top 14, leading to icon + 10, trailing to margins - 10
        [title.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [self.contentView.layoutMarginsGuide.trailingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:10],

        // Subtitle below title by 4, align leading/trailing
        [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        [sub.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [self.contentView.bottomAnchor constraintGreaterThanOrEqualToAnchor:sub.bottomAnchor constant:8],
    ]];

    return self;
}

@end


