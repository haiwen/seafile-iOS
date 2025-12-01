// SeafSdocEditorToolbar.m

#import "SeafSdocEditorToolbar.h"
#import "Constants.h"

// Base width for iPhone XS Max (standard layout)
static const CGFloat kBaseWidth = 414.0;

@interface SeafSdocEditorToolbar ()

@property (nonatomic, strong) UIButton *btnUndo;
@property (nonatomic, strong) UIButton *btnRedo;
@property (nonatomic, strong) UIButton *btnStyle;
@property (nonatomic, strong) UIButton *btnUnordered;
@property (nonatomic, strong) UIButton *btnOrdered;
@property (nonatomic, strong) UIButton *btnCheck;
@property (nonatomic, strong) UIButton *btnKeyboard;
@property (nonatomic, strong) UIImageView *styleArrowView;

// StackViews for dynamic margin adjustment
@property (nonatomic, strong) UIStackView *undoRedoStack;
@property (nonatomic, strong) UIStackView *listStack;
@property (nonatomic, strong) UIStackView *kbStack;

// Constraints for dynamic adjustment
@property (nonatomic, strong) NSLayoutConstraint *styleLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *arrowTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *styleContainerMinWidthConstraint;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *buttonWidthConstraints;

// Track last applied scale to avoid redundant updates
@property (nonatomic, assign) CGFloat lastAppliedScale;

@end

@implementation SeafSdocEditorToolbar

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self setupUI];
    }
    return self;
}

#pragma mark - Setup

- (void)setupUI
{
    self.backgroundColor = [UIColor colorWithRed:242.0/255.0 green:242.0/255.0 blue:242.0/255.0 alpha:1.0];
    self.buttonWidthConstraints = [NSMutableArray array];
    self.lastAppliedScale = 1.0;
    
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFill;
    stack.alignment = UIStackViewAlignmentFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];
    
    self.undoRedoStack = [self createGroupStack];
    // Keep spacing visually even with imageEdgeInsets.
    self.undoRedoStack.spacing = 5.0;
    self.undoRedoStack.layoutMargins = UIEdgeInsetsMake(0, 16, 0, 16);
    self.undoRedoStack.layoutMarginsRelativeArrangement = YES;
    
    UIImage *undoImg = [[UIImage imageNamed:@"Revoke-black-nomal"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImage *redoImg = [[UIImage imageNamed:@"redo-black-nomal"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    
    self.btnUndo = [self createButtonWithImageName:@"Revoke-black-nomal" action:@selector(onUndoTapped)];
    [self.btnUndo setImage:undoImg forState:UIControlStateNormal];
    [self.btnUndo setImage:undoImg forState:UIControlStateDisabled];
    
    self.btnRedo = [self createButtonWithImageName:@"redo-black-nomal" action:@selector(onRedoTapped)];
    [self.btnRedo setImage:redoImg forState:UIControlStateNormal];
    [self.btnRedo setImage:redoImg forState:UIControlStateDisabled];
    
    [self updateUndoRedoTint];
    
    [self.undoRedoStack addArrangedSubview:self.btnUndo];
    [self.undoRedoStack addArrangedSubview:self.btnRedo];
    
    UIView *styleContainer = [[UIView alloc] init];
    styleContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    UIColor *iconColor = [UIColor colorWithRed:0x67/255.0 green:0x67/255.0 blue:0x67/255.0 alpha:1.0];
    
    self.btnStyle = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *paraImg = [[UIImage imageNamed:@"sdoc-text"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.btnStyle setImage:paraImg forState:UIControlStateNormal];
    self.btnStyle.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.btnStyle.translatesAutoresizingMaskIntoConstraints = NO;
    self.btnStyle.tintColor = iconColor;
    self.btnStyle.userInteractionEnabled = NO; // Tap handled by overlay button.
    [styleContainer addSubview:self.btnStyle];
    
    // Store constraint for dynamic adjustment
    self.styleLeadingConstraint = [self.btnStyle.leadingAnchor constraintEqualToAnchor:styleContainer.leadingAnchor constant:16];
    [NSLayoutConstraint activateConstraints:@[
        self.styleLeadingConstraint,
        [self.btnStyle.centerYAnchor constraintEqualToAnchor:styleContainer.centerYAnchor],
        [self.btnStyle.widthAnchor constraintEqualToConstant:18],
        [self.btnStyle.heightAnchor constraintEqualToConstant:18]
    ]];
    
    self.styleArrowView = [[UIImageView alloc] initWithImage:[[UIImage imageNamed:@"arrow down-nomal"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    self.styleArrowView.translatesAutoresizingMaskIntoConstraints = NO;
    self.styleArrowView.contentMode = UIViewContentModeScaleAspectFit;
    self.styleArrowView.userInteractionEnabled = NO;
    self.styleArrowView.tintColor = [UIColor colorWithRed:0x99/255.0 green:0x99/255.0 blue:0x99/255.0 alpha:1.0];
    [styleContainer addSubview:self.styleArrowView];
    
    // Store constraint for dynamic adjustment
    self.arrowTrailingConstraint = [self.styleArrowView.trailingAnchor constraintEqualToAnchor:styleContainer.trailingAnchor constant:-15];
    [NSLayoutConstraint activateConstraints:@[
        self.arrowTrailingConstraint,
        [self.styleArrowView.centerYAnchor constraintEqualToAnchor:styleContainer.centerYAnchor],
        [self.styleArrowView.widthAnchor constraintEqualToConstant:16],
        [self.styleArrowView.heightAnchor constraintEqualToConstant:16]
    ]];
    
    UIButton *overlayBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    overlayBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [overlayBtn addTarget:self action:@selector(onStyleTapped:) forControlEvents:UIControlEventTouchUpInside];
    [styleContainer addSubview:overlayBtn];
    
    [NSLayoutConstraint activateConstraints:@[
        [overlayBtn.leadingAnchor constraintEqualToAnchor:styleContainer.leadingAnchor],
        [overlayBtn.trailingAnchor constraintEqualToAnchor:styleContainer.trailingAnchor],
        [overlayBtn.topAnchor constraintEqualToAnchor:styleContainer.topAnchor],
        [overlayBtn.bottomAnchor constraintEqualToAnchor:styleContainer.bottomAnchor]
    ]];
    
    // Store constraint for dynamic adjustment
    self.styleContainerMinWidthConstraint = [styleContainer.widthAnchor constraintGreaterThanOrEqualToConstant:60.0];
    self.styleContainerMinWidthConstraint.active = YES;
    
    self.listStack = [self createGroupStack];
    // Tuned margins/spacing to align separators and keep buttons evenly spaced.
    self.listStack.layoutMargins = UIEdgeInsetsMake(0, 8, 0, 8);
    self.listStack.layoutMarginsRelativeArrangement = YES;
    self.listStack.spacing = 8.0;
    
    UIColor *selectedBgColor = [UIColor colorWithRed:0.933 green:0.886 blue:0.816 alpha:1.0];
    UIImage *selectedBgImg = [self createResizableRoundedImageWithColor:selectedBgColor cornerRadius:6.0 inset:6.0];
    
    self.btnUnordered = [self createButtonWithImageName:@"unordered list-nomal" action:@selector(onUnorderedTapped)];
    UIImage *unorderedImg = [[UIImage imageNamed:@"unordered list-nomal"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.btnUnordered setImage:unorderedImg forState:UIControlStateNormal];
    [self.btnUnordered setImage:unorderedImg forState:UIControlStateSelected];
    [self.btnUnordered setBackgroundImage:selectedBgImg forState:UIControlStateSelected];
    
    self.btnOrdered = [self createButtonWithImageName:@"ordered list-nomal" action:@selector(onOrderedTapped)];
    UIImage *orderedImg = [[UIImage imageNamed:@"ordered list-nomal"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.btnOrdered setImage:orderedImg forState:UIControlStateNormal];
    [self.btnOrdered setImage:orderedImg forState:UIControlStateSelected];
    [self.btnOrdered setBackgroundImage:selectedBgImg forState:UIControlStateSelected];
    
    self.btnCheck = [self createButtonWithImageName:@"To-do list-nomal" action:@selector(onCheckTapped)];
    UIImage *checkImg = [[UIImage imageNamed:@"To-do list-nomal"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.btnCheck setImage:checkImg forState:UIControlStateNormal];
    [self.btnCheck setImage:checkImg forState:UIControlStateSelected];
    [self.btnCheck setBackgroundImage:selectedBgImg forState:UIControlStateSelected];
    
    [self.listStack addArrangedSubview:self.btnUnordered];
    [self.listStack addArrangedSubview:self.btnOrdered];
    [self.listStack addArrangedSubview:self.btnCheck];
    
    self.kbStack = [self createGroupStack];
    self.kbStack.layoutMargins = UIEdgeInsetsMake(0, 5, 0, 5);
    self.kbStack.layoutMarginsRelativeArrangement = YES;
    
    self.btnKeyboard = [self createButtonWithImageName:@"keyboard-off-nomal" action:@selector(onKeyboardTapped)];
    [self.kbStack addArrangedSubview:self.btnKeyboard];
    
    [stack addArrangedSubview:self.undoRedoStack];
    [stack addArrangedSubview:[self createVerticalSeparatorWithOffset:-2]];
    [stack addArrangedSubview:styleContainer];
    [stack addArrangedSubview:[self createVerticalSeparatorWithOffset:-4]];
    [stack addArrangedSubview:self.listStack];
    [stack addArrangedSubview:[self createVerticalSeparatorWithOffset:4]];
    [stack addArrangedSubview:self.kbStack];
    
    [self updateListSelectionTint];
    
    [self.undoRedoStack setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.kbStack setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.listStack setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [styleContainer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [styleContainer setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

#pragma mark - Layout

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    CGFloat width = CGRectGetWidth(self.bounds);
    if (width <= 0) return;
    
    // Calculate scale factor (only scale down when width < 414pt)
    CGFloat scale = (width < kBaseWidth) ? (width / kBaseWidth) : 1.0;
    
    // Avoid redundant updates
    if (fabs(scale - self.lastAppliedScale) < 0.001) return;
    self.lastAppliedScale = scale;
    
    // Update StackView margins and spacing
    // undoRedoStack: base margins (16, 16), spacing 5
    self.undoRedoStack.layoutMargins = UIEdgeInsetsMake(0, 16 * scale, 0, 16 * scale);
    self.undoRedoStack.spacing = 5.0 * scale;
    
    // listStack: base margins (8, 8), spacing 8
    self.listStack.layoutMargins = UIEdgeInsetsMake(0, 8 * scale, 0, 8 * scale);
    self.listStack.spacing = 8.0 * scale;
    
    // kbStack: base margins (5, 5)
    self.kbStack.layoutMargins = UIEdgeInsetsMake(0, 5 * scale, 0, 5 * scale);
    
    // Update constraints
    self.styleLeadingConstraint.constant = 16 * scale;
    self.arrowTrailingConstraint.constant = -15 * scale;
    self.styleContainerMinWidthConstraint.constant = 60 * scale;
    
    // Update button widths and imageEdgeInsets
    CGFloat buttonWidth = 40 * scale;
    CGFloat inset = 11 * scale;
    
    for (NSLayoutConstraint *constraint in self.buttonWidthConstraints) {
        constraint.constant = buttonWidth;
    }
    
    NSArray<UIButton *> *allButtons = @[self.btnUndo, self.btnRedo, self.btnUnordered, self.btnOrdered, self.btnCheck, self.btnKeyboard];
    for (UIButton *btn in allButtons) {
        btn.imageEdgeInsets = UIEdgeInsetsMake(inset, inset, inset, inset);
    }
}

#pragma mark - Helper Methods

- (UIStackView *)createGroupStack
{
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.alignment = UIStackViewAlignmentFill;
    return stack;
}

- (UIView *)createVerticalSeparatorWithOffset:(CGFloat)offset
{
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [container.widthAnchor constraintEqualToConstant:1].active = YES;
    
    UIView *line = [[UIView alloc] init];
    line.backgroundColor = [UIColor colorWithRed:0.75 green:0.75 blue:0.75 alpha:1.0];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:line];
    
    [NSLayoutConstraint activateConstraints:@[
        [line.widthAnchor constraintEqualToConstant:1],
        [line.centerXAnchor constraintEqualToAnchor:container.centerXAnchor constant:offset],
        [line.topAnchor constraintEqualToAnchor:container.topAnchor constant:11],
        [line.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-11]
    ]];
    return container;
}

- (UIButton *)createButtonWithImageName:(NSString *)imageName action:(SEL)action
{
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *img = [[UIImage imageNamed:imageName] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [btn setImage:img forState:UIControlStateNormal];
    btn.imageView.contentMode = UIViewContentModeScaleAspectFit;
    btn.contentVerticalAlignment = UIControlContentVerticalAlignmentFill;
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
    btn.imageEdgeInsets = UIEdgeInsetsMake(11, 11, 11, 11);
    btn.tintColor = [UIColor colorWithRed:0x67/255.0 green:0x67/255.0 blue:0x67/255.0 alpha:1.0];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    
    // Store width constraint for dynamic adjustment
    NSLayoutConstraint *widthConstraint = [btn.widthAnchor constraintEqualToConstant:40];
    widthConstraint.active = YES;
    [self.buttonWidthConstraints addObject:widthConstraint];
    
    return btn;
}

- (UIImage *)createResizableRoundedImageWithColor:(UIColor *)color cornerRadius:(CGFloat)radius inset:(CGFloat)inset
{
    CGFloat capSize = inset + radius;
    CGFloat side = capSize * 2 + 1;
    CGSize size = CGSizeMake(side, side);
    
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextClearRect(context, CGRectMake(0, 0, side, side));
    CGContextSetFillColorWithColor(context, color.CGColor);
    
    CGRect fillRect = CGRectMake(inset, inset, side - 2*inset, side - 2*inset);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:fillRect cornerRadius:radius];
    [path fill];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(capSize, capSize, capSize, capSize) resizingMode:UIImageResizingModeStretch];
}

#pragma mark - Button Actions

- (void)onUndoTapped
{
    if ([self.delegate respondsToSelector:@selector(editorToolbarDidTapUndo)]) {
        [self.delegate editorToolbarDidTapUndo];
    }
}

- (void)onRedoTapped
{
    if ([self.delegate respondsToSelector:@selector(editorToolbarDidTapRedo)]) {
        [self.delegate editorToolbarDidTapRedo];
    }
}

- (void)onStyleTapped:(UIButton *)sender
{
    if ([self.delegate respondsToSelector:@selector(editorToolbarDidTapStyle:)]) {
        [self.delegate editorToolbarDidTapStyle:sender];
    }
}

- (void)onUnorderedTapped
{
    if ([self.delegate respondsToSelector:@selector(editorToolbarDidTapUnorderedList)]) {
        [self.delegate editorToolbarDidTapUnorderedList];
    }
}

- (void)onOrderedTapped
{
    if ([self.delegate respondsToSelector:@selector(editorToolbarDidTapOrderedList)]) {
        [self.delegate editorToolbarDidTapOrderedList];
    }
}

- (void)onCheckTapped
{
    if ([self.delegate respondsToSelector:@selector(editorToolbarDidTapCheckList)]) {
        [self.delegate editorToolbarDidTapCheckList];
    }
}

- (void)onKeyboardTapped
{
    if ([self.delegate respondsToSelector:@selector(editorToolbarDidTapKeyboard)]) {
        [self.delegate editorToolbarDidTapKeyboard];
    }
}

#pragma mark - Public Methods

- (void)updateWithStyleModel:(NSDictionary *)model
{
    if (!model || ![model isKindOfClass:[NSDictionary class]]) return;
    
    NSString *type = model[@"type"];
    
    NSDictionary *headerImageMap = @{
        @"paragraph": @"sdoc-text",
        @"header1": @"sdoc-header1",
        @"header2": @"sdoc-header2",
        @"header3": @"sdoc-header3",
        @"header4": @"sdoc-header4",
        @"header5": @"sdoc-header5",
        @"header6": @"sdoc-header6",
        @"title": @"titel",
        @"subtitle": @"subtitel"
    };
    
    NSString *imageName = headerImageMap[type];
    if (imageName) {
        UIImage *img = [[UIImage imageNamed:imageName] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [self.btnStyle setImage:img forState:UIControlStateNormal];
        [self.btnStyle setTitle:nil forState:UIControlStateNormal];
    }
    
    self.btnUnordered.selected = [type isEqualToString:@"unordered_list"];
    self.btnOrdered.selected = [type isEqualToString:@"ordered_list"];
    self.btnCheck.selected = [type isEqualToString:@"check_list_item"];
    
    BOOL isCheck = [type isEqualToString:@"check_list_item"];
    
    UIColor *disabledTint = [UIColor lightGrayColor];
    UIColor *styleNormalColor = [UIColor colorWithRed:0x67/255.0 green:0x67/255.0 blue:0x67/255.0 alpha:1.0];
    
    if (isCheck) {
        self.btnStyle.enabled = NO;
        [self.btnStyle setTitleColor:disabledTint forState:UIControlStateNormal];
        self.btnStyle.tintColor = disabledTint;
        self.styleArrowView.tintColor = disabledTint;
        self.btnUnordered.enabled = NO;
        self.btnOrdered.enabled = NO;
    } else {
        self.btnStyle.enabled = YES;
        [self.btnStyle setTitleColor:styleNormalColor forState:UIControlStateNormal];
        self.btnStyle.tintColor = styleNormalColor;
        self.styleArrowView.tintColor = [UIColor colorWithRed:0x99/255.0 green:0x99/255.0 blue:0x99/255.0 alpha:1.0];
        self.btnUnordered.enabled = YES;
        self.btnOrdered.enabled = YES;
    }
    
    [self updateListSelectionTint];
}

- (void)updateUndoEnabled:(BOOL)canUndo redoEnabled:(BOOL)canRedo
{
    self.btnUndo.enabled = canUndo;
    self.btnRedo.enabled = canRedo;
    [self updateUndoRedoTint];
}

- (UIButton *)styleButton
{
    return self.btnStyle;
}

- (void)updateUndoRedoTint
{
    UIColor *normalTint = [UIColor colorWithRed:0x67/255.0 green:0x67/255.0 blue:0x67/255.0 alpha:1.0];
    UIColor *disabledTint = [UIColor colorWithWhite:0.75 alpha:1.0];
    self.btnUndo.tintColor = self.btnUndo.enabled ? normalTint : disabledTint;
    self.btnRedo.tintColor = self.btnRedo.enabled ? normalTint : disabledTint;
}

- (void)updateListSelectionTint
{
    UIColor *normalTint = [UIColor colorWithRed:0x67/255.0 green:0x67/255.0 blue:0x67/255.0 alpha:1.0];
    UIColor *selectedTint = BAR_COLOR_ORANGE ?: [UIColor colorWithRed:240.0/256 green:128.0/256 blue:48.0/256 alpha:1.0];
    UIColor *disabledTint = [UIColor colorWithWhite:0.75 alpha:1.0];
    
    NSArray<UIButton *> *buttons = @[self.btnUnordered, self.btnOrdered, self.btnCheck];
    for (UIButton *btn in buttons) {
        BOOL enabled = btn.enabled;
        BOOL selected = btn.selected;
        UIColor *tint = enabled ? (selected ? selectedTint : normalTint) : disabledTint;
        btn.tintColor = tint;
    }
}

@end
