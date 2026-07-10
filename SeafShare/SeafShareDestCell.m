//
//  SeafShareDestCell.m
//  SeafShare
//
//  Lightweight destination-style cell for Share Extension.
//  Layout metrics match SeafCell.xib (35×35 icon, 15pt title, 12pt subtitle,
//  top 10 / gap 4 / bottom 12) so Recent and Starred rows share the same height.
//

#import "SeafShareDestCell.h"
#import "SeafTheme.h"

@interface SeafShareDestCell ()
@property (nonatomic, assign) BOOL checkboxSelected;
@end

@implementation SeafShareDestCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    _checkboxSelected = NO;

    // Icon 35×35 — same as SeafCell.xib
    _iconView = [[UIImageView alloc] init];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.layer.cornerRadius = 5.0;
    _iconView.clipsToBounds = YES;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:_iconView];

    // Title 15pt, single line (SeafCell title)
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    _titleLabel.textColor = [SeafTheme primaryText];
    _titleLabel.numberOfLines = 1;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.contentView addSubview:_titleLabel];

    // Subtitle 12pt, single line (SeafCell detail)
    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFont systemFontOfSize:12];
    _subtitleLabel.textColor = [SeafTheme secondaryText];
    _subtitleLabel.numberOfLines = 1;
    _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:_subtitleLabel];

    // Checkbox (trailing)
    _checkboxView = [[UIImageView alloc] init];
    _checkboxView.translatesAutoresizingMaskIntoConstraints = NO;
    _checkboxView.contentMode = UIViewContentModeScaleAspectFit;
    _checkboxView.hidden = YES;
    [self.contentView addSubview:_checkboxView];

    // Vertical metrics from SeafCell.xib: title top 10, subtitle gap ≥4, subtitle bottom 12.
    // Use equality on the bottom so AutomaticDimension yields a stable row height.
    [NSLayoutConstraint activateConstraints:@[
        [_iconView.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor constant:8],
        [_iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:35],
        [_iconView.heightAnchor constraintEqualToConstant:35],

        [_checkboxView.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor constant:-4],
        [_checkboxView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_checkboxView.widthAnchor constraintEqualToConstant:24],
        [_checkboxView.heightAnchor constraintEqualToConstant:24],

        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:10],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_checkboxView.leadingAnchor constant:-8],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
    ]];

    return self;
}

- (void)updateCheckboxImageForSelected:(BOOL)selected
{
    self.checkboxSelected = selected;
    NSString *imageName = selected ? @"ic_checkbox_checked" : @"ic_checkbox_unchecked";
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    UIImage *image = [UIImage imageNamed:imageName inBundle:bundle compatibleWithTraitCollection:self.traitCollection];
    if (!image) {
        image = [UIImage imageNamed:imageName];
    }
    if (@available(iOS 13.0, *)) {
        if (image && self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            self.checkboxView.tintColor = selected
                ? [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.7]
                : [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.2];
        } else if (image) {
            image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            self.checkboxView.tintColor = nil;
        }
    }
    self.checkboxView.image = image;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]
            && !self.checkboxView.hidden) {
            [self updateCheckboxImageForSelected:self.checkboxSelected];
        }
    }
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.layer.cornerRadius = 0;
    self.layer.maskedCorners = 0;
    self.layer.masksToBounds = NO;
    _iconView.image = nil;
    _iconView.alpha = 1.0;
    _titleLabel.text = nil;
    _titleLabel.alpha = 1.0;
    _subtitleLabel.text = nil;
    _subtitleLabel.alpha = 1.0;
    _checkboxView.image = nil;
    _checkboxView.hidden = YES;
    _checkboxView.tintColor = nil;
    _checkboxView.alpha = 1.0;
    _checkboxSelected = NO;
    self.contentView.alpha = 1.0;
}

@end
