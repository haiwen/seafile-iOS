//  SeafTagChipCell.m

#import "SeafTagChipCell.h"
#import "SeafTheme.h"

@interface SeafTagChipCell ()
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) NSLayoutConstraint *labelLeadingConstraint;
@property (nonatomic, strong) CALayer *dotLayer;
@property (nonatomic, assign) CGFloat lastDotDiameter;
@property (nonatomic, assign) BOOL usesDynamicBorder;
@end

@implementation SeafTagChipCell

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        self.contentView.backgroundColor = [UIColor systemGrayColor];
        self.contentView.layer.cornerRadius = 16;
        self.contentView.layer.masksToBounds = YES;

        _label = [UILabel new];
        _label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        _label.textColor = [SeafTheme primaryText];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_label];

        self.labelLeadingConstraint = [_label.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10];
        [NSLayoutConstraint activateConstraints:@[
            self.labelLeadingConstraint,
            [_label.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
            [_label.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:2],
            [_label.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-2]
        ]];
    }
    return self;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.contentView.backgroundColor = [UIColor clearColor];
    self.label.textColor = [SeafTheme secondaryText];
    self.label.text = @"";
    self.contentView.layer.borderWidth = 0;
    self.contentView.layer.borderColor = nil;
    self.labelLeadingConstraint.constant = 10;
    self.lastDotDiameter = 0;
    self.dotLayer.hidden = YES;
    self.usesDynamicBorder = NO;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat h = CGRectGetHeight(self.contentView.bounds);
    self.contentView.layer.cornerRadius = h * 0.5;
    if (self.dotLayer && !self.dotLayer.hidden) {
        // Dot padding: left 5px, top/bottom 4px per design spec
        CGFloat d = (self.lastDotDiameter > 0) ? self.lastDotDiameter : (h - 8.0);
        if (d < 10.0) d = 10.0; // minimum dot size
        CGFloat y = 4.0; // top padding 4px
        self.dotLayer.frame = CGRectMake(5, y, d, d); // left padding 5px
        self.dotLayer.cornerRadius = d * 0.5;
    }
}

- (void)configureWithText:(NSString *)text color:(NSString *)colorHex textColor:(NSString *)textColorHex
{
    self.label.text = text ?: @"";
    UIColor *bg = [self.class colorFromHex:colorHex] ?: [UIColor clearColor];
    // Text color falls back to the adaptive primary label so the chip remains readable in dark
    // mode when the server didn't supply an explicit color pair.
    UIColor *tc = [self.class colorFromHex:textColorHex] ?: [SeafTheme primaryText];
    self.contentView.backgroundColor = bg;
    self.label.textColor = tc;
    self.contentView.layer.borderWidth = 0;
    self.labelLeadingConstraint.constant = 10;
    self.lastDotDiameter = 0;
    self.dotLayer.hidden = YES;
}

- (void)configureDotStyleWithText:(NSString *)text dotColor:(NSString *)dotColorHex textColor:(NSString *)textColorHex
{
    self.label.text = text ?: @"";
    UIColor *tc = [self.class colorFromHex:textColorHex] ?: [SeafTheme primaryText];
    UIColor *dot = [self.class colorFromHex:dotColorHex] ?: [SeafTheme fill];
    self.contentView.backgroundColor = [SeafTheme primarySurface];
    self.contentView.layer.borderColor = [SeafTheme separator].CGColor;
    self.contentView.layer.borderWidth = 1.0;
    self.usesDynamicBorder = YES;
    self.label.textColor = tc;

    // Ensure dot layer
    if (!self.dotLayer) {
        self.dotLayer = [CALayer layer];
        self.dotLayer.name = @"dotLayer";
        [self.contentView.layer insertSublayer:self.dotLayer atIndex:0];
    }
    CGFloat h = CGRectGetHeight(self.contentView.bounds);
    // Dot padding: left 5px, top/bottom 4px per design spec
    // Dot size = height - top padding - bottom padding = h - 4 - 4 = h - 8
    CGFloat d = h - 8.0;
    if (d < 10.0) d = 10.0; // minimum dot size
    self.lastDotDiameter = d;
    self.dotLayer.hidden = NO;
    self.dotLayer.backgroundColor = dot.CGColor;
    CGFloat y = 4.0; // top padding 4px
    self.dotLayer.frame = CGRectMake(5, y, d, d); // left padding 5px
    self.dotLayer.cornerRadius = d * 0.5;

    // Shift label to the right of dot: left padding 5 + dot size + spacing to text (4 for right padding of dot area)
    self.labelLeadingConstraint.constant = 5 + d + 4;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    // CGColor is a static snapshot; re-resolve the dynamic separator when the trait collection changes.
    if (self.usesDynamicBorder) {
        self.contentView.layer.borderColor = [SeafTheme separator].CGColor;
    }
}

+ (UIColor *)colorFromHex:(NSString *)hex
{
    if (![hex isKindOfClass:[NSString class]] || hex.length == 0) return nil;
    NSString *h = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int rgb = 0; [[NSScanner scannerWithString:h] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb>>16)&0xFF)/255.0 green:((rgb>>8)&0xFF)/255.0 blue:(rgb&0xFF)/255.0 alpha:1];
}

@end

