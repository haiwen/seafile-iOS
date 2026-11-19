#import "SeafNavLeftItem.h"
#import "SeafTheme.h"

@interface SeafNavLeftItem ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, copy, readwrite, nullable) NSString *statusText;
@end

@implementation SeafNavLeftItem

+ (instancetype)titleViewWithTitle:(NSString *)title {
    SeafNavLeftItem *view = [[self alloc] initWithFrame:CGRectZero];
    view.titleLabel = [[UILabel alloc] init];
    view.titleLabel.text = title;
    view.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    view.titleLabel.textColor = [SeafTheme primaryText];
    view.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    view.statusLabel = [[UILabel alloc] init];
    view.statusLabel.font = [UIFont systemFontOfSize:12];
    view.statusLabel.textColor = [SeafTheme secondaryText];
    view.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [view addSubview:view.titleLabel];
    [view addSubview:view.statusLabel];
    view.userInteractionEnabled = NO;
    view.isAccessibilityElement = YES;
    view.accessibilityLabel = title;
    view.accessibilityIdentifier = @"sdoc_document_title";
    view.accessibilityTraits = UIAccessibilityTraitHeader;
    [view setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [view sizeToFit];
    return view;
}

- (CGSize)intrinsicContentSize {
    CGFloat statusWidth = self.statusText.length ? [self.statusLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, 44)].width + 6 : 0;
    return CGSizeMake(ceil([self.titleLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, 44)].width + statusWidth), 44);
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize natural = self.intrinsicContentSize;
    return CGSizeMake(size.width > 0 ? MIN(size.width, natural.width) : natural.width, natural.height);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat statusWidth = self.statusText.length ? MIN([self.statusLabel sizeThatFits:self.bounds.size].width, width * 0.4) : 0;
    CGFloat gap = statusWidth > 0 ? 6 : 0;
    self.titleLabel.frame = CGRectMake(0, 0, MAX(0, width - statusWidth - gap), CGRectGetHeight(self.bounds));
    self.statusLabel.frame = CGRectMake(width - statusWidth, 0, statusWidth, CGRectGetHeight(self.bounds));
}

- (void)applyStatusText:(nullable NSString *)statusText {
    self.statusText = statusText.length ? statusText : nil;
    self.statusLabel.text = self.statusText;
    self.accessibilityValue = self.statusText;
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
}
@end
