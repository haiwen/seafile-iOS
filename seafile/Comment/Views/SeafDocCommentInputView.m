//  SeafDocCommentInputView.m

#import "SeafDocCommentInputView.h"

@interface SeafDocCommentInputView () <UITextViewDelegate>

@property (nonatomic, strong) UIView *separator;
@property (nonatomic, strong) UIButton *photoButton;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UILabel *placeholderLabel;

@end

@implementation SeafDocCommentInputView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor systemBackgroundColor];

        _separator = [[UIView alloc] initWithFrame:CGRectZero];
        _separator.backgroundColor = [UIColor separatorColor];
        [self addSubview:_separator];

        _photoButton = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImage *img = [UIImage systemImageNamed:@"photo.on.rectangle"]; // iOS13+
        if (img) [_photoButton setImage:img forState:UIControlStateNormal];
        if (@available(iOS 13.0, *)) {
            _photoButton.tintColor = [UIColor systemGrayColor];
        } else {
            _photoButton.tintColor = [UIColor lightGrayColor];
        }
        [_photoButton addTarget:self action:@selector(onTapPhotoButton) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_photoButton];

        _textView = [[UITextView alloc] initWithFrame:CGRectZero];
        _textView.font = [UIFont systemFontOfSize:17];
        _textView.layer.cornerRadius = 8.0;
        _textView.layer.borderColor = UIColor.clearColor.CGColor;
        _textView.layer.borderWidth = 0;
        _textView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        _textView.textContainerInset = UIEdgeInsetsMake(4, 8, 4, 8);
        _textView.tintColor = [UIColor colorWithRed:255.0/255.0 green:102.0/255.0 blue:0.0/255.0 alpha:1.0];
        _textView.delegate = self;
    _textView.scrollEnabled = YES;
        [self addSubview:_textView];

        _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_sendButton setTitle:NSLocalizedString(@"Send", nil) forState:UIControlStateNormal];
        // textSize="16sp"
        _sendButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        // textColor="@color/fancy_orange"
        _sendButton.tintColor = [UIColor colorWithRed:255.0/255.0 green:102.0/255.0 blue:0.0/255.0 alpha:1.0];
        [_sendButton addTarget:self action:@selector(onTapSendButton) forControlEvents:UIControlEventTouchUpInside];
        _sendButton.enabled = NO;
        [self addSubview:_sendButton];

        _placeholderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _placeholderLabel.text = NSLocalizedString(@"Write a comment...", nil);
        _placeholderLabel.textColor = [UIColor secondaryLabelColor];
        _placeholderLabel.font = [UIFont systemFontOfSize:15];
        _placeholderLabel.userInteractionEnabled = NO;
        _placeholderLabel.hidden = YES; // always hidden to remove placeholder from UI
        [self addSubview:_placeholderLabel];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat safeBottom = 0;
    if (@available(iOS 11.0, *)) safeBottom = self.safeAreaInsets.bottom;
    
    // Image button 48dp × 48dp, send button 48dp high, vertical margins 6dp
    CGFloat baseHeight = 48.0 + 6.0 + 6.0; // 48pt button height + 6pt top/bottom margins
    CGFloat maxTextHeight = 320.0; // Align closer to Android max_height
    
    // Compute available width: total width - photo button(56) - spacing(8) - send button width - spacing
    CGFloat availableWidth = self.bounds.size.width - (56 + 8 + 60 + 8);
    CGFloat measuredTextHeight = ceilf(MAX(38.0, MIN(maxTextHeight, 
        [self.textView sizeThatFits:CGSizeMake(availableWidth, CGFLOAT_MAX)].height)));
    
    CGFloat contentHeight = MAX(baseHeight, 6.0 + measuredTextHeight + 6.0);
    
    // Divider
    self.separator.frame = CGRectMake(0, 0, self.bounds.size.width, 1.0 / [UIScreen mainScreen].scale);

    // Image button 48dp × 48dp (widened to 56pt here), layout_marginEnd="8dp"
    CGFloat buttonTop = 6.0;
    self.photoButton.frame = CGRectMake(0, buttonTop, 56, 48);
    // padding="12dp" (so the icon renders at 24dp)
    self.photoButton.contentEdgeInsets = UIEdgeInsetsMake(12, 12, 12, 12);
    
    // Send button layout_height="48dp", paddingHorizontal="16dp"
    CGSize sendSize = [self.sendButton.titleLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, 48)];
    CGFloat sendWidth = MAX(60, sendSize.width + 32);  // 16pt horizontal padding
    self.sendButton.frame = CGRectMake(
        self.bounds.size.width - sendWidth, 
        buttonTop, 
        sendWidth, 
        48
    );
    
    // Input container layout_marginVertical="6dp", minHeight="38dp"
    CGFloat textLeft = CGRectGetMaxX(self.photoButton.frame) + 8;
    CGFloat textRight = CGRectGetMinX(self.sendButton.frame) - 8;
    
    // Center the input vertically within 48pt height
    CGFloat lineHeight = self.textView.font.lineHeight;
    if (measuredTextHeight <= 48.0) {
        // Single-line: fix height to 48 and center caret by adjusting insets
        CGFloat topInset = floor((48.0 - lineHeight) / 2.0);
        if (topInset < 4.0) topInset = 4.0;
        self.textView.textContainerInset = UIEdgeInsetsMake(topInset, 8, topInset, 8);
        self.textView.frame = CGRectMake(
            textLeft,
            buttonTop,
            MAX(0, textRight - textLeft),
            48.0
        );
    } else {
        // Multi-line: use measured height with default compact insets
        self.textView.textContainerInset = UIEdgeInsetsMake(4, 8, 4, 8);
        CGFloat textTop = buttonTop; // taller than 48, top align
        self.textView.frame = CGRectMake(
            textLeft,
            textTop,
            MAX(0, textRight - textLeft),
            measuredTextHeight
        );
    }
    
    // Placeholder position
    // placeholder removed: keep frame calculation no-op while hidden
    self.placeholderLabel.frame = CGRectZero;
}

- (CGSize)intrinsicContentSize
{
    // Base height = 48dp (button) + 6dp (top) + 6dp (bottom) = 60dp
    CGFloat baseHeight = 48.0 + 6.0 + 6.0;
    CGFloat maxTextHeight = 320.0;

    CGFloat availableWidth = self.bounds.size.width > 0 ?
        self.bounds.size.width - (56 + 8 + 60 + 8) :
        [UIScreen mainScreen].bounds.size.width - (56 + 8 + 60 + 8);

    CGFloat measuredTextHeight = ceilf(MAX(38.0, MIN(maxTextHeight,
        [self.textView sizeThatFits:CGSizeMake(availableWidth, CGFLOAT_MAX)].height)));

    CGFloat contentHeight = MAX(baseHeight, 6.0 + measuredTextHeight + 6.0);

    // Return pure content height (excludes safe area). The controller decides whether to add safe area depending on keyboard state
    return CGSizeMake(UIViewNoIntrinsicMetric, contentHeight);
}

- (void)onTapPhotoButton
{
    if (self.onTapPhoto) self.onTapPhoto();
}

- (void)onTapSendButton
{
    if (self.onTapSend) self.onTapSend(self.textView.text ?: @"");
}

- (void)setSendEnabled:(BOOL)enabled
{
    self.sendButton.enabled = enabled;
}

#pragma mark - UITextViewDelegate
- (void)textViewDidChange:(UITextView *)textView
{
    [self setSendEnabled:textView.text.length > 0];
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
    // Placeholder is not used; keep it hidden
    self.placeholderLabel.hidden = YES;
}

- (void)updatePlaceholderVisibility
{
    // Placeholder removed from UI; keep it hidden to maintain API contract
    self.placeholderLabel.hidden = YES;
}

@end

