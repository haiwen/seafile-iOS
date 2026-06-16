//  SeafTagChipView.m
//  Reusable capsule view for tag display (color dot + name + optional remove button).
//  Aligned with Android layout_detail_tag.xml: MaterialCardView with colored indicator dot,
//  text label, and optional remove (×) button.

#import "SeafTagChipView.h"

@interface SeafTagChipView ()
@property (nonatomic, strong) UIView *dotView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIButton *removeButton;
@property (nonatomic, copy) SeafTagChipRemoveHandler removeHandler;
@property (nonatomic, assign) BOOL isSetup;
@end

@implementation SeafTagChipView

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super initWithCoder:coder]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI
{
    if (self.isSetup) return;
    self.isSetup = YES;

    // Align Android: MaterialCardView with cardCornerRadius=16dp, strokeWidth=1dp, strokeColor=profile_tag_stroke
    self.backgroundColor = [UIColor whiteColor];
    self.layer.masksToBounds = YES;
    // Border: align Android profile_tag_stroke (#DBDBDB)
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [UIColor colorWithRed:0xDB/255.0 green:0xDB/255.0 blue:0xDB/255.0 alpha:1.0].CGColor;

    // Horizontal stack: dot + name + (optional) remove
    UIStackView *h = [UIStackView new];
    h.axis = UILayoutConstraintAxisHorizontal;
    h.alignment = UIStackViewAlignmentCenter;
    h.spacing = 4; // align Android: layout_marginStart=4dp between dot and text
    h.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:h];

    // Color dot: 14x14 circle (align Android: indicator 14dp x 14dp, cardCornerRadius=7dp)
    _dotView = [UIView new];
    _dotView.translatesAutoresizingMaskIntoConstraints = NO;
    _dotView.layer.cornerRadius = 7;
    _dotView.layer.masksToBounds = YES;
    _dotView.backgroundColor = [UIColor lightGrayColor];
    [_dotView.widthAnchor constraintEqualToConstant:14].active = YES;
    [_dotView.heightAnchor constraintEqualToConstant:14].active = YES;

    // Name label: 12sp (align Android: textSize=12sp, item_title_color)
    _nameLabel = [UILabel new];
    _nameLabel.font = [UIFont systemFontOfSize:12];
    _nameLabel.textColor = [UIColor colorWithRed:0x21/255.0 green:0x25/255.0 blue:0x29/255.0 alpha:1.0]; // #212529
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameLabel.numberOfLines = 1;

    // Remove button: 16x16 tap area, small × icon (align Android: remove 16dp x 16dp)
    _removeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _removeButton.translatesAutoresizingMaskIntoConstraints = NO;
    // Render icon at smaller size (8pt) while keeping button frame 16x16 for tap area
    UIImageSymbolConfiguration *smallConfig = [UIImageSymbolConfiguration configurationWithPointSize:8 weight:UIImageSymbolWeightSemibold];
    UIImage *closeImg = [[UIImage systemImageNamed:@"xmark"] imageByApplyingSymbolConfiguration:smallConfig];
    if (!closeImg) closeImg = [UIImage imageNamed:@"baseline_close_24"];
    [_removeButton setImage:closeImg forState:UIControlStateNormal];
    _removeButton.tintColor = [UIColor colorWithRed:0x99/255.0 green:0x99/255.0 blue:0x99/255.0 alpha:1.0]; // grey
    [_removeButton.widthAnchor constraintEqualToConstant:16].active = YES;
    [_removeButton.heightAnchor constraintEqualToConstant:16].active = YES;
    _removeButton.hidden = YES;
    [_removeButton addTarget:self action:@selector(onRemoveTapped) forControlEvents:UIControlEventTouchUpInside];

    [h addArrangedSubview:_dotView];
    [h addArrangedSubview:_nameLabel];
    [h addArrangedSubview:_removeButton];

    // Padding: align Android contentPaddingLeft=5dp, contentPaddingRight=8dp, top/bottom=3dp
    [NSLayoutConstraint activateConstraints:@[
        [h.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:5],
        [h.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [h.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
        [h.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4]
    ]];

    // Explicit height constraint to prevent UIStackView stretching
    [self.heightAnchor constraintEqualToConstant:26].active = YES;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    // Dynamic capsule corner radius (align SeafTagChipCell dot style)
    CGFloat h = CGRectGetHeight(self.bounds);
    self.layer.cornerRadius = h * 0.5;
    self.layer.borderColor = [UIColor colorWithRed:0xDB/255.0 green:0xDB/255.0 blue:0xDB/255.0 alpha:1.0].CGColor;
}

- (void)configureWithName:(NSString *)name color:(NSString *)colorHex
{
    [self configureWithName:name color:colorHex showRemove:NO removeHandler:nil];
}

- (void)configureWithName:(NSString *)name color:(NSString *)colorHex showRemove:(BOOL)showRemove removeHandler:(SeafTagChipRemoveHandler)handler
{
    self.nameLabel.text = name ?: @"";
    self.dotView.backgroundColor = [self.class colorFromHex:colorHex] ?: [UIColor lightGrayColor];
    self.removeButton.hidden = !showRemove;
    self.removeHandler = handler;
}

- (void)onRemoveTapped
{
    if (self.removeHandler) {
        self.removeHandler();
    }
}

/// Intrinsic content size for auto layout
- (CGSize)intrinsicContentSize
{
    CGFloat nameW = ceil([self.nameLabel.text sizeWithAttributes:@{NSFontAttributeName: self.nameLabel.font}].width);
    // left 5 + dot 14 + spacing 4 + text + spacing 4 + (remove 16 if shown) + right 8
    CGFloat width = 5 + 14 + 4 + nameW + 8;
    if (!self.removeButton.hidden) {
        width += 4 + 16; // spacing + remove button
    }
    // Height: top 4 + content (max of 14 dot, ~16 label) + bottom 4 = 26
    return CGSizeMake(MAX(28, width), 26);
}

+ (CGFloat)widthForText:(NSString *)text showRemove:(BOOL)showRemove
{
    UIFont *font = [UIFont systemFontOfSize:12];
    CGFloat nameW = ceil([text sizeWithAttributes:@{NSFontAttributeName: font}].width);
    // left 5 + dot 14 + spacing 4 + text + right 8
    CGFloat width = 5 + 14 + 4 + nameW + 8;
    if (showRemove) {
        width += 4 + 16; // spacing + remove button
    }
    return MAX(28, width);
}

+ (UIColor *)colorFromHex:(NSString *)hex
{
    if (![hex isKindOfClass:[NSString class]] || hex.length == 0) return nil;
    NSString *h = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (h.length < 6) return nil;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:h] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb>>16)&0xFF)/255.0 green:((rgb>>8)&0xFF)/255.0 blue:(rgb&0xFF)/255.0 alpha:1];
}

@end
