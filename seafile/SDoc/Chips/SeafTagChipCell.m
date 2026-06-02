//  SeafTagChipCell.m
//  UICollectionViewCell wrapper. Dot-style delegates to SeafTagChipView;
//  filled-style keeps a simple colored background for multi-select options.

#import "SeafTagChipCell.h"
#import "SeafTagChipView.h"

@interface SeafTagChipCell ()
/// Filled-style label (for multi-select options)
@property (nonatomic, strong) UILabel *filledLabel;
/// Dot-style tag chip view (shared component)
@property (nonatomic, strong) SeafTagChipView *chipView;
@end

@implementation SeafTagChipCell

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        self.contentView.layer.masksToBounds = YES;

        // Filled-style label (visible for configureWithText: mode)
        _filledLabel = [UILabel new];
        _filledLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        _filledLabel.textColor = [UIColor whiteColor];
        _filledLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_filledLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_filledLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
            [_filledLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
            [_filledLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:2],
            [_filledLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-2]
        ]];

        // Dot-style chip view (shared component, initially hidden)
        _chipView = [[SeafTagChipView alloc] init];
        _chipView.translatesAutoresizingMaskIntoConstraints = NO;
        _chipView.hidden = YES;
        [self.contentView addSubview:_chipView];
        [NSLayoutConstraint activateConstraints:@[
            [_chipView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_chipView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_chipView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_chipView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        ]];
    }
    return self;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.contentView.backgroundColor = [UIColor clearColor];
    self.contentView.layer.borderWidth = 0;
    self.contentView.layer.borderColor = nil;
    self.filledLabel.text = @"";
    self.filledLabel.textColor = [UIColor secondaryLabelColor];
    self.filledLabel.hidden = NO;
    self.chipView.hidden = YES;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    // Dynamic capsule corner radius for both filled and dot styles
    CGFloat h = CGRectGetHeight(self.contentView.bounds);
    self.contentView.layer.cornerRadius = h * 0.5;
}

#pragma mark - Filled style (multi-select options)

- (void)configureWithText:(NSString *)text color:(NSString *)colorHex textColor:(NSString *)textColorHex
{
    self.filledLabel.hidden = NO;
    self.chipView.hidden = YES;

    self.filledLabel.text = text ?: @"";
    UIColor *bg = [SeafTagChipView colorFromHex:colorHex] ?: [UIColor clearColor];
    UIColor *tc = [SeafTagChipView colorFromHex:textColorHex] ?: [UIColor colorWithRed:0x21/255.0 green:0x25/255.0 blue:0x29/255.0 alpha:1.0];
    self.contentView.backgroundColor = bg;
    self.filledLabel.textColor = tc;
    self.contentView.layer.borderWidth = 0;
}

#pragma mark - Dot style (tags — delegates to SeafTagChipView)

- (void)configureDotStyleWithText:(NSString *)text dotColor:(NSString *)dotColorHex textColor:(NSString *)textColorHex
{
    self.filledLabel.hidden = YES;
    self.chipView.hidden = NO;

    // Clear contentView styling so chip view's own styling shows through
    self.contentView.backgroundColor = [UIColor clearColor];
    self.contentView.layer.borderWidth = 0;

    [self.chipView configureWithName:text color:dotColorHex];
}

@end
