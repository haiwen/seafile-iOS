//
//  SeafWikiGroupHeader.m
//  seafilePro
//

#import "SeafWikiGroupHeader.h"
#import "SeafWikiModel.h"
#import "SeafTheme.h"

// Points, from the 260819 wiki home redline.
static const CGFloat kHeaderTopSpacing    = 16.0;
static const CGFloat kHeaderBottomSpacing = 12.0;
static const CGFloat kTitleLineHeight     = 24.0;
static const CGFloat kTitleFontSize       = 15.0;
static const CGFloat kIconSize            = 20.0;
static const CGFloat kIconTitleSpacing    = 8.0;

static NSString * const kFallbackIconName = @"icon_shared_with_all";

@interface SeafWikiGroupHeader ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation SeafWikiGroupHeader

+ (NSString *)reuseIdentifier { return NSStringFromClass(self); }

+ (CGFloat)headerHeight { return kHeaderTopSpacing + kTitleLineHeight + kHeaderBottomSpacing; }

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        _iconView = [[UIImageView alloc] init];
        _iconView.tintColor = [SeafTheme secondaryText];   // spec #666666
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:kTitleFontSize weight:UIFontWeightMedium];
        _titleLabel.textColor = [SeafTheme primaryText];   // spec #212529
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:_iconView];
        [self addSubview:_titleLabel];

        // The leading edge comes from the section's content insets, so the header lines
        // up with the cards without repeating the margin here.
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:kHeaderTopSpacing],
            [_titleLabel.heightAnchor constraintEqualToConstant:kTitleLineHeight],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],

            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:kIconSize],
            [_iconView.heightAnchor constraintEqualToConstant:kIconSize],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:kIconTitleSpacing],
        ]];
    }
    return self;
}

- (void)configureWithGroup:(SeafWikiGroup *)group
{
    self.titleLabel.text = group.title;
    NSString *iconName = group.iconName ?: kFallbackIconName;
    self.iconView.image = [[UIImage imageNamed:iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@end
