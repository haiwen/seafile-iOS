//
//  SeafWikiCell.m
//  seafilePro
//

#import "SeafWikiCell.h"
#import "SeafWikiModel.h"
#import "SeafIconFont.h"
#import "SeafTheme.h"
#import "SeafTagChipView.h"
#import "SeafDateFormatter.h"

#pragma mark - Design spec

// All values are points, taken from the 260819 wiki home redline.
static const CGFloat kCardHeight        = 180.0;
static const CGFloat kCardCornerRadius  = 8.0;
static const CGFloat kCardPadding       = 16.0;   // leading / trailing / top
static const CGFloat kCardBottomPadding = 8.0;
static const CGFloat kCardBorderWidth   = 1.0;

// The card is lifted off the page in light mode only; on the dark page the border
// alone separates it, which is what the design calls for.
// Design: drop shadow X 0, Y 4, blur 8, spread 0, #000000 at 2%. A CSS/Figma blur is
// roughly twice the Gaussian sigma that CALayer.shadowRadius takes, hence 8 -> 4.
static const CGFloat kCardShadowOpacity = 0.02;
static const CGFloat kCardShadowRadius  = 4.0;   // = design blur 8 / 2
static const CGSize  kCardShadowOffset  = (CGSize){ 0.0, 4.0 };

static const CGFloat kIconBoxSize       = 32.0;
static const CGFloat kIconBoxRadius     = 8.0;
static const CGFloat kIconGlyphSize     = 20.0;
// The spec's 20pt is the icon's frame. Glyphs in haiwen-iconfont are inset inside
// their em box, so a 20pt font only inks ~16pt; scaling up matches the design's
// optical size. Only affects the font, not the fallback image.
static const CGFloat kIconFontSize      = 25.0;
static const CGFloat kIconBackgroundAlpha = 0.10;

static const CGFloat kBadgeHeight       = 20.0;
static const CGFloat kBadgePaddingX     = 8.0;
static const CGFloat kBadgeFontSize     = 12.0;
static const CGFloat kBadgeBorderWidth  = 1.0;

static const CGFloat kTitleTopSpacing   = 12.0;   // below the icon row
static const CGFloat kTitleFontSize     = 14.0;
static const CGFloat kTitleLineHeight   = 22.0;
static const NSInteger kTitleMaxLines   = 2;

static const CGFloat kTimeFontSize      = 12.0;
static const CGFloat kTimeLineHeight    = 24.0;

static const CGFloat kMoreGlyphSize     = 24.0;
static const CGFloat kMoreTapTargetSize = 48.0;

#pragma mark - Padded badge label

/// "Published" pill: a label that carries its own horizontal padding so it can be laid
/// out purely from its intrinsic size in any language.
@interface SeafWikiBadgeLabel : UILabel
@end

@implementation SeafWikiBadgeLabel

- (CGSize)intrinsicContentSize
{
    CGSize size = [super intrinsicContentSize];
    size.width += kBadgePaddingX * 2;
    size.height = kBadgeHeight;
    return size;
}

- (void)drawTextInRect:(CGRect)rect
{
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, UIEdgeInsetsMake(0, kBadgePaddingX, 0, kBadgePaddingX))];
}

@end

#pragma mark - More button

/// The glyph is 24pt but the design calls for a 48pt tap target. Growing the frame
/// instead would push the button past the card's clipped bounds, so the extra area is
/// claimed in pointInside: — the card still receives the touch and forwards it here.
@interface SeafWikiMoreButton : UIButton
@end

@implementation SeafWikiMoreButton

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    CGFloat dx = MAX(0, (kMoreTapTargetSize - CGRectGetWidth(self.bounds)) / 2);
    CGFloat dy = MAX(0, (kMoreTapTargetSize - CGRectGetHeight(self.bounds)) / 2);
    return CGRectContainsPoint(CGRectInset(self.bounds, -dx, -dy), point);
}

@end

#pragma mark - SeafWikiCell

@interface SeafWikiCell ()
@property (nonatomic, strong) UIView *iconContainer;
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UIImageView *iconFallbackView;
@property (nonatomic, strong) SeafWikiBadgeLabel *publishBadge;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong, readwrite) UIButton *moreButton;
@end

@implementation SeafWikiCell

+ (NSString *)reuseIdentifier { return NSStringFromClass(self); }

+ (CGFloat)cardHeight { return kCardHeight; }

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self setupViews];
    }
    return self;
}

- (void)setupViews
{
    UIView *cv = self.contentView;
    cv.backgroundColor = [SeafTheme primarySurface];
    cv.layer.cornerRadius = kCardCornerRadius;
    cv.layer.borderWidth = kCardBorderWidth;
    cv.layer.borderColor = [SeafTheme cardBorder].CGColor;
    cv.clipsToBounds = YES;

    // The contentView has to clip so the corner radius takes, and a clipped layer
    // cannot draw a shadow - so the shadow lives on the cell's own layer instead.
    self.layer.masksToBounds = NO;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOffset = kCardShadowOffset;
    self.layer.shadowRadius = kCardShadowRadius;
    [self updateShadowForCurrentTraits];

    _iconContainer = [[UIView alloc] init];
    _iconContainer.layer.cornerRadius = kIconBoxRadius;
    _iconContainer.clipsToBounds = YES;
    _iconContainer.translatesAutoresizingMaskIntoConstraints = NO;

    _iconLabel = [[UILabel alloc] init];
    _iconLabel.textAlignment = NSTextAlignmentCenter;
    _iconLabel.translatesAutoresizingMaskIntoConstraints = NO;

    // Shown instead of the glyph when the icon font is unavailable.
    _iconFallbackView = [[UIImageView alloc] init];
    _iconFallbackView.image = [UIImage systemImageNamed:@"book.fill"];
    _iconFallbackView.contentMode = UIViewContentModeScaleAspectFit;
    _iconFallbackView.hidden = YES;
    _iconFallbackView.translatesAutoresizingMaskIntoConstraints = NO;

    _publishBadge = [[SeafWikiBadgeLabel alloc] init];
    _publishBadge.text = NSLocalizedString(@"Published", @"Seafile");
    _publishBadge.font = [UIFont systemFontOfSize:kBadgeFontSize];
    _publishBadge.textColor = [SeafTheme secondaryText];   // spec #666666
    _publishBadge.textAlignment = NSTextAlignmentCenter;
    _publishBadge.layer.cornerRadius = kBadgeHeight / 2;
    _publishBadge.layer.borderWidth = kBadgeBorderWidth;
    // Spec says rgba(0, 40, 100, 0.12); that is within a hair of the card's own #EEE
    // outline, so both hairlines share one token rather than differing invisibly.
    _publishBadge.layer.borderColor = [SeafTheme cardBorder].CGColor;
    _publishBadge.clipsToBounds = YES;
    _publishBadge.hidden = YES;
    _publishBadge.translatesAutoresizingMaskIntoConstraints = NO;

    _nameLabel = [[UILabel alloc] init];
    _nameLabel.numberOfLines = kTitleMaxLines;
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _timeLabel = [[UILabel alloc] init];
    _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _moreButton = [SeafWikiMoreButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *moreConfig =
        [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
    [_moreButton setImage:[UIImage systemImageNamed:@"ellipsis" withConfiguration:moreConfig]
                 forState:UIControlStateNormal];
    _moreButton.tintColor = [SeafTheme secondaryText];   // spec #666666
    _moreButton.hidden = YES;   // shown only for wikis the user owns
    _moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_moreButton addTarget:self action:@selector(moreButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    [_iconContainer addSubview:_iconLabel];
    [_iconContainer addSubview:_iconFallbackView];
    [cv addSubview:_iconContainer];
    [cv addSubview:_publishBadge];
    [cv addSubview:_nameLabel];
    [cv addSubview:_timeLabel];
    [cv addSubview:_moreButton];

    // The badge must yield to the icon before it truncates itself.
    [_publishBadge setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh - 1
                                                   forAxis:UILayoutConstraintAxisHorizontal];

    NSLayoutConstraint *badgeLeading =
        [_publishBadge.leadingAnchor constraintGreaterThanOrEqualToAnchor:_iconContainer.trailingAnchor constant:8];
    badgeLeading.priority = UILayoutPriorityRequired;

    [NSLayoutConstraint activateConstraints:@[
        [_iconContainer.topAnchor constraintEqualToAnchor:cv.topAnchor constant:kCardPadding],
        [_iconContainer.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:kCardPadding],
        [_iconContainer.widthAnchor constraintEqualToConstant:kIconBoxSize],
        [_iconContainer.heightAnchor constraintEqualToConstant:kIconBoxSize],

        [_iconLabel.centerXAnchor constraintEqualToAnchor:_iconContainer.centerXAnchor],
        [_iconLabel.centerYAnchor constraintEqualToAnchor:_iconContainer.centerYAnchor],

        [_iconFallbackView.centerXAnchor constraintEqualToAnchor:_iconContainer.centerXAnchor],
        [_iconFallbackView.centerYAnchor constraintEqualToAnchor:_iconContainer.centerYAnchor],
        [_iconFallbackView.widthAnchor constraintEqualToConstant:kIconGlyphSize],
        [_iconFallbackView.heightAnchor constraintEqualToConstant:kIconGlyphSize],

        [_publishBadge.centerYAnchor constraintEqualToAnchor:_iconContainer.centerYAnchor],
        [_publishBadge.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-kCardPadding],
        [_publishBadge.heightAnchor constraintEqualToConstant:kBadgeHeight],
        badgeLeading,

        [_nameLabel.topAnchor constraintEqualToAnchor:_iconContainer.bottomAnchor constant:kTitleTopSpacing],
        [_nameLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:kCardPadding],
        [_nameLabel.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-kCardPadding],

        [_timeLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:kCardPadding],
        [_timeLabel.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-kCardBottomPadding],
        [_timeLabel.heightAnchor constraintEqualToConstant:kTimeLineHeight],
        [_timeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_moreButton.leadingAnchor constant:-8],

        [_moreButton.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-kCardPadding],
        [_moreButton.centerYAnchor constraintEqualToAnchor:_timeLabel.centerYAnchor],
        [_moreButton.widthAnchor constraintEqualToConstant:kMoreGlyphSize],
        [_moreButton.heightAnchor constraintEqualToConstant:kMoreGlyphSize],
    ]];
}

// An explicit shadowPath keeps the blur off the render server's offscreen pass while
// the grid scrolls; it has to follow the card, whose width changes with the column
// count.
- (void)layoutSubviews
{
    [super layoutSubviews];
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                                      cornerRadius:kCardCornerRadius].CGPath;
}

- (void)updateShadowForCurrentTraits
{
    BOOL isDark = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    self.layer.shadowOpacity = isDark ? 0.0 : kCardShadowOpacity;
}

#pragma mark - Configure

- (void)configureWithWiki:(SeafWikiInfo *)wiki
{
    UIColor *iconColor = [SeafTagChipView colorFromHex:wiki.iconColorHex] ?: [SeafTheme accentOrange];
    self.iconContainer.backgroundColor = [iconColor colorWithAlphaComponent:kIconBackgroundAlpha];
    self.iconLabel.textColor = iconColor;
    self.iconFallbackView.tintColor = iconColor;

    UIFont *iconFont = [[SeafIconFont sharedInstance] fontOfSize:kIconFontSize];
    NSString *glyph = [[SeafIconFont sharedInstance] glyphForName:wiki.iconGlyphName];
    BOOL hasGlyph = (iconFont != nil && glyph != nil);
    self.iconLabel.font = iconFont;
    self.iconLabel.text = hasGlyph ? glyph : nil;
    self.iconLabel.hidden = !hasGlyph;
    self.iconFallbackView.hidden = hasGlyph;

    self.nameLabel.attributedText = [self.class attributedText:wiki.name
                                                          font:[UIFont systemFontOfSize:kTitleFontSize]
                                                    lineHeight:kTitleLineHeight
                                                         color:[SeafTheme primaryText]];   // spec #212529

    self.timeLabel.attributedText = [self.class attributedText:[self.class displayTimeForWiki:wiki]
                                                          font:[UIFont systemFontOfSize:kTimeFontSize]
                                                    lineHeight:kTimeLineHeight
                                                         color:[SeafTheme secondaryText]];   // spec #666666

    self.publishBadge.hidden = !wiki.isPublished;
    // Renaming / publishing / deleting is only offered for wikis the user owns.
    self.moreButton.hidden = ![wiki.type isEqualToString:SeafWikiTypeMine];
}

/// The design shows relative times ("6 months ago"), matching the Android client and
/// the web UI. Falls back to the absolute date when the timestamp cannot be parsed.
+ (NSString *)displayTimeForWiki:(SeafWikiInfo *)wiki
{
    if (wiki.updatedAt.length == 0) return @"";

    NSString *relative = [SeafDateFormatter compareGMTTimeWithNow:wiki.updatedAt];
    if (relative.length > 0) return relative;

    long long timestamp = [SeafDateFormatter timestampFromLastModified:wiki.updatedAt];
    return timestamp > 0 ? [SeafDateFormatter stringFromLongLong:timestamp] : wiki.updatedAt;
}

/// UILabel's natural leading does not match the spec's line heights, so the text is
/// built with an explicit paragraph style.
+ (NSAttributedString *)attributedText:(NSString *)text
                                  font:(UIFont *)font
                            lineHeight:(CGFloat)lineHeight
                                 color:(UIColor *)color
{
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.minimumLineHeight = lineHeight;
    style.maximumLineHeight = lineHeight;
    style.lineBreakMode = NSLineBreakByTruncatingTail;

    return [[NSAttributedString alloc] initWithString:text ?: @""
                                           attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: style,
        // A fixed line height leaves the glyphs sitting on the bottom of the line box.
        // Lifting them by half the slack re-centers them, which also lines the meta row
        // up with the "more" button next to it.
        NSBaselineOffsetAttributeName: @((lineHeight - font.lineHeight) / 2.0),
    }];
}

#pragma mark - Reuse / traits

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.onMoreTapped = nil;
    self.moreButton.hidden = YES;
    self.publishBadge.hidden = YES;
    self.iconLabel.text = nil;
    self.iconContainer.backgroundColor = nil;
    self.nameLabel.attributedText = nil;
    self.timeLabel.attributedText = nil;
}

// CALayer.borderColor holds a resolved CGColor that does not follow the trait
// collection, so it has to be re-resolved whenever the appearance flips. The shadow
// is only drawn in light mode, so it is toggled here too.
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.contentView.layer.borderColor = [SeafTheme cardBorder].CGColor;
        self.publishBadge.layer.borderColor = [SeafTheme cardBorder].CGColor;
        [self updateShadowForCurrentTraits];
    }
}

- (void)moreButtonTapped:(UIButton *)sender
{
    if (self.onMoreTapped) self.onMoreTapped();
}

@end
