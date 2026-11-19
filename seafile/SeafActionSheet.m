//
//  SeafActionSheet.m
//  seafilePro
//
//  Created by three on 2017/6/14.
//  Copyright © 2017年 Seafile. All rights reserved.
//

#import "SeafActionSheet.h"
#import "SeafCell.h"
#import "SeafAppDelegate.h"
#import "SeafTheme.h"
#import "Constants.h"

#define kHostsCornerRadius 12.0f

#define kSpacing 5.0f

#define kArrowBaseWidth 14.0f
#define kArrowHeight 8.0f

#define kShadowRadius 5.0f
#define kShadowOpacity 0.3f

#define kFixedWidth 200.0f
#define kFixedWidthContinuous 200.0f
#define KButtonHeight = 44.0f

#define kAnimationDurationForSectionCount(count) MAX(0.25f, MIN(count*0.08f, 0.35f))

#define rgba(r, g, b, a) [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:a]

#define rgb(r, g, b) rgba(r, g, b, 1.0f)

#ifndef iPad
#define iPad (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad)
#endif

#pragma mark - Helpers

@interface SeafSectionButton : UIButton

@property (nonatomic, assign) NSUInteger row;
@property (nonatomic, strong) UIColor *normalColor;
@property (nonatomic, strong) UIColor *highlightColor;

@end

@implementation SeafSectionButton

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? self.highlightColor : self.normalColor;
}

@end

NS_INLINE UIBezierPath *trianglePath(CGRect rect, SFActionSheetArrowDirection arrowDirection, BOOL closePath) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat arrowCurveAmount = 0.5; // Add a subtle curve to the arrow sides

    if (arrowDirection == SFActionSheetArrowDirectionBottom) {
        [path moveToPoint:CGPointZero];
        
        // Create slightly curved arrow sides
        CGPoint midPoint = CGPointMake(CGRectGetWidth(rect)/2.0f, CGRectGetHeight(rect));
        CGPoint controlPoint1 = CGPointMake(CGRectGetWidth(rect)/2.0f - arrowCurveAmount, CGRectGetHeight(rect) * 0.3);
        CGPoint controlPoint2 = CGPointMake(CGRectGetWidth(rect)/2.0f + arrowCurveAmount, CGRectGetHeight(rect) * 0.3);
        
        [path addLineToPoint:midPoint];
        [path addLineToPoint:(CGPoint){CGRectGetWidth(rect), 0.0f}];
    }
    else if (arrowDirection == SFActionSheetArrowDirectionLeft) {
        [path moveToPoint:(CGPoint){CGRectGetWidth(rect), 0.0f}];
        
        // Create slightly curved arrow sides
        CGPoint midPoint = CGPointMake(0.0f, CGRectGetHeight(rect)/2.0f);
        CGPoint controlPoint1 = CGPointMake(CGRectGetWidth(rect) * 0.3, CGRectGetHeight(rect)/2.0f - arrowCurveAmount);
        CGPoint controlPoint2 = CGPointMake(CGRectGetWidth(rect) * 0.3, CGRectGetHeight(rect)/2.0f + arrowCurveAmount);
        
        [path addLineToPoint:midPoint];
        [path addLineToPoint:(CGPoint){CGRectGetWidth(rect), CGRectGetHeight(rect)}];
    }
    else if (arrowDirection == SFActionSheetArrowDirectionRight) {
        [path moveToPoint:CGPointZero];
        
        // Create slightly curved arrow sides
        CGPoint midPoint = CGPointMake(CGRectGetWidth(rect), CGRectGetHeight(rect)/2.0f);
        CGPoint controlPoint1 = CGPointMake(CGRectGetWidth(rect) * 0.7, CGRectGetHeight(rect)/2.0f - arrowCurveAmount);
        CGPoint controlPoint2 = CGPointMake(CGRectGetWidth(rect) * 0.7, CGRectGetHeight(rect)/2.0f + arrowCurveAmount);
        
        [path addLineToPoint:midPoint];
        [path addLineToPoint:(CGPoint){0.0f, CGRectGetHeight(rect)}];
    }
    else if (arrowDirection == SFActionSheetArrowDirectionTop) {
        [path moveToPoint:(CGPoint){0.0f, CGRectGetHeight(rect)}];
        
        // Create slightly curved arrow sides
        CGPoint midPoint = CGPointMake(CGRectGetWidth(rect)/2.0f, 0.0f);
        CGPoint controlPoint1 = CGPointMake(CGRectGetWidth(rect)/2.0f - arrowCurveAmount, CGRectGetHeight(rect) * 0.7);
        CGPoint controlPoint2 = CGPointMake(CGRectGetWidth(rect)/2.0f + arrowCurveAmount, CGRectGetHeight(rect) * 0.7);
        
        [path addLineToPoint:midPoint];
        [path addLineToPoint:(CGPoint){CGRectGetWidth(rect), CGRectGetHeight(rect)}];
    }

    if (closePath) {
        [path closePath];
    }

    return path;
}

static BOOL disableCustomEasing = NO;

@interface SeafActionSheetLayer : CAShapeLayer

@end

@implementation SeafActionSheetLayer

- (void)addAnimation:(CAAnimation *)anim forKey:(NSString *)key {
    if (!disableCustomEasing && [anim isKindOfClass:[CABasicAnimation class]]) {
        CAMediaTimingFunction *func = [CAMediaTimingFunction functionWithControlPoints:0.215f: 0.61f: 0.355f: 1.0f];

        anim.timingFunction = func;
    }

    [super addAnimation:anim forKey:key];
}

@end

@interface SeafActionSheetTriangle : UIView

- (void)setFrame:(CGRect)frame arrowDirection:(SFActionSheetArrowDirection)direction;

@end

@implementation SeafActionSheetTriangle

- (void)setFrame:(CGRect)frame arrowDirection:(SFActionSheetArrowDirection)direction {
    self.frame = frame;

    [((CAShapeLayer *)self.layer) setPath:trianglePath(frame, direction, YES).CGPath];
    self.layer.shadowPath = trianglePath(frame, direction, NO).CGPath;

    BOOL leftOrRight = (direction == SFActionSheetArrowDirectionLeft || direction == SFActionSheetArrowDirectionRight);

    CGRect pathRect = (CGRect){CGPointZero, {CGRectGetWidth(frame)+(leftOrRight ? kShadowRadius+1.0f : 2.0f*(kShadowRadius+1.0f)), CGRectGetHeight(frame)+(leftOrRight ? 2.0f*(kShadowRadius+1.0f) : kShadowRadius+1.0f)}};

    if (direction == SFActionSheetArrowDirectionTop) {
        pathRect.origin.y -= kShadowRadius+1.0f;
    }
    else if (direction == SFActionSheetArrowDirectionLeft) {
        pathRect.origin.x -= kShadowRadius+1.0f;
    }

    UIBezierPath *path = [UIBezierPath bezierPathWithRect:pathRect];

    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.path = path.CGPath;
    mask.fillColor = [UIColor blackColor].CGColor;
    
    self.layer.mask = mask;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeZero;
    self.layer.shadowRadius = kShadowRadius;
    self.layer.shadowOpacity = kShadowOpacity;
    
    self.layer.contentsScale = SeafDisplayScale(self);
    ((CAShapeLayer *)self.layer).fillColor = [SeafTheme elevatedSurface].CGColor;
    ((CAShapeLayer *)self.layer).strokeColor = [UIColor clearColor].CGColor;
}

+ (Class)layerClass {
    return [SeafActionSheetLayer class];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    // CAShapeLayer.fillColor is a CGColor snapshot; re-resolve against the current theme.
    ((CAShapeLayer *)self.layer).fillColor = [SeafTheme elevatedSurface].CGColor;
}

@end

@interface SeafActionSheetView : UIView

@end

@implementation SeafActionSheetView

+ (Class)layerClass {
    return [SeafActionSheetLayer class];
}

@end

#pragma mark - SeafActionSheetSection

@interface SeafActionSheetSection ()

@property (nonatomic, assign) NSUInteger index;

@property (nonatomic, copy) void (^buttonPressedBlock)(NSIndexPath *indexPath);

@end

@implementation SeafActionSheetSection

+ (instancetype)cancelSection {
    return [self sectionWithButtonTitles:@[NSLocalizedString(@"Cancel",)] buttonStyle:SFActionSheetButtonStyleCancel];
}

+(instancetype)sectionWithButtonTitles:(NSArray *)buttonTitles buttonStyle:(SFActionSheetButtonStyle)buttonStyle {
    return [[self alloc] initWithButtonTitles:buttonTitles buttonStyle:buttonStyle];
}

-(instancetype)initWithButtonTitles:(NSArray *)buttonTitles buttonStyle:(SFActionSheetButtonStyle)buttonStyle {
    self = [super init];

    if (self) {
        if (buttonTitles.count) {
            NSMutableArray *buttons = [NSMutableArray arrayWithCapacity:buttonTitles.count];
            NSInteger index = 0;

            for (NSString *str in buttonTitles) {
                SeafSectionButton *b = [self makeButtonWithTitle:str style:buttonStyle];
                b.row = (NSUInteger)index;
                [self addSubview:b];
                [buttons addObject:b];
                index++;
            }
            _buttons = buttons.copy;
        }
    }

    return self;
}
#pragma mark UI

- (UIImage *)pixelImageWithColor:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions((CGSize){1.0f, 1.0f}, YES, 0.0f);

    [color setFill];

    [[UIBezierPath bezierPathWithRect:(CGRect){CGPointZero, {1.0f, 1.0f}}] fill];

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();

    UIGraphicsEndImageContext();

    return [img resizableImageWithCapInsets:UIEdgeInsetsZero];
}

- (SeafSectionButton *)makeButtonWithTitle:(NSString *)title style:(SFActionSheetButtonStyle)style {
    CGFloat buttonHeight = 44.0f;
    UIEdgeInsets titleInsets = UIEdgeInsetsMake(0, 10, 0, 0);
    
    if (style == SFActionSheetButtonStyleCancel) {
        buttonHeight += [[UIApplication sharedApplication] delegate].window.safeAreaInsets.bottom;
        titleInsets = UIEdgeInsetsMake(0, 10, [[UIApplication sharedApplication] delegate].window.safeAreaInsets.bottom, 0);
    }
    
    SeafSectionButton *b = [[SeafSectionButton alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.bounds), buttonHeight)];

    NSString *displayTitle = title;
    BOOL enabled = YES;
    static NSString * const disabledPrefix = @"DISABLED:";
    if ([title hasPrefix:disabledPrefix]) {
        displayTitle = [title substringFromIndex:disabledPrefix.length];
        enabled = NO;
    }

    [b setTitle:displayTitle forState:UIControlStateNormal];
    [b setTitleColor:[SeafTheme primaryText] forState:UIControlStateNormal];
    [b setTitleEdgeInsets:titleInsets];
    [b addTarget:self action:@selector(buttonPressed:) forControlEvents:UIControlEventTouchUpInside];
    b.normalColor = [SeafTheme elevatedSurface];
    b.highlightColor = [SeafTheme fill];
    b.backgroundColor = b.normalColor;
    
    // Configure adaptive font size
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.titleLabel.minimumScaleFactor = 0.75; // Scale down to 75% if needed
    b.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    
    // Set font after enabling adaptive sizing
    if (style == SFActionSheetButtonStyleCancel) {
        b.titleLabel.font = [UIFont boldSystemFontOfSize:14.0f];
    } else {
        b.titleLabel.font = [UIFont systemFontOfSize:14.0f];
    }
    
    if (!enabled) {
        b.enabled = NO;
        [b setTitleColor:[SeafTheme tertiaryText] forState:UIControlStateNormal];
    }
    
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    
    return b;
}

- (void)buttonPressed:(SeafSectionButton *)button {
    if (self.buttonPressedBlock) {
        self.buttonPressedBlock([NSIndexPath indexPathForRow:(NSInteger)button.row inSection:(NSInteger)self.index]);
    }
}

- (CGRect)layoutForWidth:(CGFloat)width {
    CGFloat height = 0.0f;

    for (UIButton *button in self.buttons) {
        button.frame = (CGRect){{0, height}, {width, button.bounds.size.height}};
        height += button.bounds.size.height;
    }

    self.frame = (CGRect){CGPointZero, {width, height}};
    return self.frame;
}

@end

@interface SeafActionSheet ()<UIGestureRecognizerDelegate> {
    UIScrollView *_scrollView;
    SeafActionSheetTriangle *_arrowView;// View for displaying a directional arrow pointing to the action sheet's origin
    SeafActionSheetView *_scrollViewHost;

    CGRect _finalContentFrame;

    UIColor *_realBGColor;

    BOOL _anchoredAtPoint;
    BOOL _anchoredToBarButton;
    CGPoint _anchorPoint;// The point at which the action sheet is anchored
    SFActionSheetArrowDirection _anchoredArrowDirection;// The direction of the arrow when the action sheet is anchored
    CGSize _laidOutSize;

    NSUInteger _interactionSuspendCount;// Show/move/dismiss nest their suspend calls, so this has to be counted
    __weak UIView *_interactionSuspendedWindow;
}

@property (nonatomic, strong) NSArray *sections;// Array of sections within the action sheet
@property (nonatomic, weak) UIAlertController *systemAlert;

@end

@implementation SeafActionSheet

// Initializes the action sheet with titles for each button in the sections.
+ (instancetype)actionSheetWithTitles:(NSArray *)titles {
    return [[self alloc] initWithSectionTitles:titles];
}

+ (instancetype)actionSheetWithoutCancelWithTitles:(NSArray *)titles {
    return [[self alloc] initWithoutCancelWithSectionTitles:titles];
}

- (instancetype)initWithoutCancelWithSectionTitles:(NSArray *)titles {
    NSAssert(titles.count > 0, @"Must at least provide 1 section");

    self = [super init];

    if (self) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        tap.delegate = self;

        [self addGestureRecognizer:tap];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        _scrollViewHost = [[SeafActionSheetView alloc] init];
        _scrollViewHost.backgroundColor = [UIColor clearColor];
        // Always use rounded corners for popover style
        _scrollViewHost.layer.cornerRadius = kHostsCornerRadius;
        _scrollViewHost.layer.masksToBounds = YES;

        _scrollView = [[UIScrollView alloc] init];
        _scrollView.backgroundColor = [UIColor clearColor];
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.showsVerticalScrollIndicator = NO;

        [_scrollViewHost addSubview:_scrollView];
        [self addSubview:_scrollViewHost];

        // Completely transparent background, no overlay
        self.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.0f]; 
        
        // No separate section for cancel in popover style
        SeafActionSheetSection *section = [SeafActionSheetSection sectionWithButtonTitles:titles buttonStyle:SFActionSheetButtonStyleDefault];
        
        _sections = @[section];

        NSInteger index = 0;

        __weak __typeof(self) weakSelf = self;

        void (^pressedBlock)(NSIndexPath *) = ^(NSIndexPath *indexPath) {
            [weakSelf buttonPressed:indexPath];
        };

        for (SeafActionSheetSection *section in self.sections) {
            section.index = index;

            [_scrollView addSubview:section];

            [section setButtonPressedBlock:pressedBlock];

            index++;
        }
    }

    return self;
}

// Shows the action sheet with an optional animation.
- (instancetype)initWithSectionTitles:(NSArray *)titles {
    NSAssert(titles.count > 0, @"Must at least provide 1 section");

    self = [super init];

    if (self) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        tap.delegate = self;

        [self addGestureRecognizer:tap];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        _scrollViewHost = [[SeafActionSheetView alloc] init];
        _scrollViewHost.backgroundColor = [UIColor clearColor];
        // Always use rounded corners for popover style
        _scrollViewHost.layer.cornerRadius = kHostsCornerRadius;
        _scrollViewHost.layer.masksToBounds = YES;

        _scrollView = [[UIScrollView alloc] init];
        _scrollView.backgroundColor = [UIColor clearColor];
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.showsVerticalScrollIndicator = NO;

        [_scrollViewHost addSubview:_scrollView];
        [self addSubview:_scrollViewHost];

        // Completely transparent background, no overlay
        self.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.0f];
        
        // No separate section for cancel in popover style
        SeafActionSheetSection *section = [SeafActionSheetSection sectionWithButtonTitles:titles buttonStyle:SFActionSheetButtonStyleDefault];

        _sections = @[section];

        NSInteger index = 0;

        __weak __typeof(self) weakSelf = self;

        void (^pressedBlock)(NSIndexPath *) = ^(NSIndexPath *indexPath) {
            [weakSelf buttonPressed:indexPath];
        };

        for (SeafActionSheetSection *section in self.sections) {
            section.index = index;

            [_scrollView addSubview:section];

            [section setButtonPressedBlock:pressedBlock];

            index++;
        }
    }

    return self;
}

#pragma mark Overrides

+ (Class)layerClass {
    return [SeafActionSheetLayer class];
}

// The sheet covers its window and follows it through autoresizing, so a window
// size change (rotation, iPhone Duo fold, iPad resize) shows up here.
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    BOOL resized = !CGSizeEqualToSize(_laidOutSize, CGSizeZero) && !CGSizeEqualToSize(_laidOutSize, size);
    _laidOutSize = size;
    if (!resized || !self.superview) {
        return;
    }
    if (_anchoredToBarButton) {
        // The bar can move to a different edge on rotation or folding.
        [self dismissAnimated:NO];
        return;
    }
    if (_anchoredAtPoint) {
        [self moveToPoint:_anchorPoint arrowDirection:_anchoredArrowDirection animated:NO];
    } else {
        [self layoutSheetInitial];
    }
}

- (void)dealloc {
    // Never leave the window unresponsive if the sheet goes away mid-animation.
    if (_interactionSuspendCount > 0) {
        _interactionSuspendedWindow.userInteractionEnabled = YES;
    }
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
    [super setBackgroundColor:backgroundColor];
    _realBGColor = backgroundColor;
}

#pragma mark Callbacks

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([self hitTest:[gestureRecognizer locationInView:self] withEvent:nil] == self) {
        return YES;
    }

    return NO;
}

- (void)tapped:(UITapGestureRecognizer *)gesture {
    if ([self hitTest:[gesture locationInView:self] withEvent:nil] == self) {
        [self dismissAnimated:YES];
    }
}

- (void)buttonPressed:(NSIndexPath *)indexPath {
    if (self.buttonPressedBlock) {
        self.buttonPressedBlock(self, indexPath);
    }
}

#pragma mark Layout
- (void)layoutSheetForFrame:(CGRect)frame {
    CGRect available = CGRectNull;
    if (_anchoredToBarButton) {
        UIView *content = self.targetVC.viewIfLoaded;
        UIWindow *window = content.window;
        if (window) {
            CGRect safeContent = [content convertRect:content.safeAreaLayoutGuide.layoutFrame toView:window];
            available = CGRectInset(CGRectIntersection(safeContent, window.safeAreaLayoutGuide.layoutFrame), kSpacing, kSpacing);
        }
    }

    BOOL fitsToContent = !CGRectIsEmpty(available);
    CGFloat width = fitsToContent ? MIN(kFixedWidth, CGRectGetWidth(available)) : kFixedWidth;
    CGFloat height = 0;

    for (SeafActionSheetSection *section in self.sections) {
        CGRect f = [section layoutForWidth:width];
        f.origin.y = height;
        f.origin.x = 0;
        section.frame = f;
        height += CGRectGetHeight(f);
    }

    frame.size = CGSizeMake(width, height);
    if (fitsToContent) {
        frame.size.height = MIN(height, CGRectGetHeight(available));
        frame.origin.x = MAX(CGRectGetMinX(available), MIN(frame.origin.x, CGRectGetMaxX(available) - width));
        frame.origin.y = MAX(CGRectGetMinY(available), MIN(frame.origin.y, CGRectGetMaxY(available) - frame.size.height));
    }
    _scrollViewHost.frame = frame;

    // Apply consistent styling
    _scrollViewHost.layer.cornerRadius = kHostsCornerRadius;
    _scrollViewHost.layer.masksToBounds = NO; // Don't clip shadows
    
    // Add shadow
    _scrollViewHost.layer.shadowColor = [UIColor blackColor].CGColor;
    _scrollViewHost.layer.shadowOffset = CGSizeMake(0, 2);
    _scrollViewHost.layer.shadowRadius = kShadowRadius;
    _scrollViewHost.layer.shadowOpacity = kShadowOpacity;
    
    _finalContentFrame = _scrollViewHost.frame;
    _scrollView.frame = _scrollViewHost.bounds;
    _scrollView.contentSize = CGSizeMake(width, height);
    _scrollView.showsVerticalScrollIndicator = height > frame.size.height;
}

- (void)layoutForVisible:(BOOL)visible {
    UIView *viewToModify = _scrollViewHost;

    if (visible) {
        // Do not use background overlay
        self.backgroundColor = [UIColor clearColor];
        viewToModify.alpha = 1.0f;
    } else {
        super.backgroundColor = [UIColor clearColor];
        viewToModify.alpha = 0.0f;
    }
}

#pragma mark Showing

- (void)showAnimated:(BOOL)animated {

    [self suspendInteraction];

    [self layoutSheetInitial];

    void (^completion)(void) = ^{
        [self resumeInteraction];
    };

    [self layoutForVisible:!animated];
    [[self topWindow] addSubview:self];

    if (!animated) {
        completion();
    } else {
        CGFloat duration = kAnimationDurationForSectionCount(self.sections.count);

        [UIView animateWithDuration:duration animations:^{
            [self layoutForVisible:YES];
        } completion:^(BOOL finished) {
            completion();
        }];
    }
}

- (void)layoutSheetInitial {
    self.frame = [self topWindow].bounds;
    
    _scrollViewHost.backgroundColor = [SeafTheme elevatedSurface];

    CGRect frame = self.frame;
    // Use fixed width of 200
    frame.origin.x = (CGRectGetWidth(frame) - kFixedWidth) / 2.0f;
    frame.size.width = kFixedWidth;

    // Use 5px spacing
    frame = UIEdgeInsetsInsetRect(frame, UIEdgeInsetsMake(kSpacing, kSpacing, kSpacing, kSpacing));
    [self layoutSheetForFrame:frame];
}

#pragma mark Showing From Point

- (void)showFromPoint:(CGPoint)point inView:(UIView *)view arrowDirection:(SFActionSheetArrowDirection)arrowDirection animated:(BOOL)animated {
    CGRect sourceRect = CGRectMake(point.x - 1, point.y - 1, 2, 2); // Default small area
    [self showFromPoint:point sourceRect:sourceRect arrowDirection:arrowDirection animated:animated];
}

// ShowFromView method - For displaying the action sheet from a specific view.
// The sheet lives in topWindow, so every anchor is converted to window coordinates.
// (The navigation controller's view is not at the window origin in an iPad sidebar.)
- (void)showFromView:(id)view {
    if (self.targetVC.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        [self showSystemActionSheetFromView:view];
        return;
    }
    CGPoint point = CGPointZero;
    CGRect sourceRect = CGRectZero; // Record animation starting position
    _anchoredToBarButton = [view isKindOfClass:UIBarButtonItem.class];
    UIView *window = [self topWindow];

    if ([view isKindOfClass:[SeafCell class]]) {
        SeafCell *cell = (SeafCell*)view;
        UIView *button = cell.moreButton;
        sourceRect = [(button.superview ?: cell) convertRect:button.frame toView:window];
        point = (CGPoint){CGRectGetMidX(sourceRect), CGRectGetMidY(sourceRect)};
    } else if (_anchoredToBarButton) {
        UIBarButtonItem *item = (UIBarButtonItem*)view;
        UIView *itemView = [item valueForKey:@"view"];

        if (itemView.superview) {
            // Use the bottom right corner of the button as anchor point
            sourceRect = [itemView.superview convertRect:itemView.frame toView:window];
            point = (CGPoint){CGRectGetMaxX(sourceRect), CGRectGetMaxY(sourceRect)};
        } else {
            // If unable to get specific view, use top right corner of navigation bar
            sourceRect = [self navigationBarAnchorRectInView:window];
            point = (CGPoint){CGRectGetMidX(sourceRect), CGRectGetMaxY(sourceRect) - 20};
        }
    } else if ([view isKindOfClass:[UIButton class]]) {
        // Anchor to a button: align popup's top-right corner to button's bottom-right corner
        UIView *sourceView = (UIView *)view;
        sourceRect = [sourceView.superview convertRect:sourceView.frame toView:[self topWindow]];
        // Use button's bottom-right as anchor point
        CGFloat px = CGRectGetMaxX(sourceRect);
        CGFloat py = CGRectGetMaxY(sourceRect);
        point = CGPointMake(px, py);
        [self showFromPoint:point sourceRect:sourceRect arrowDirection:SFActionSheetArrowDirectionTop animated:YES];
        return;
    } else if ([view isKindOfClass:[UIView class]]) {
        UIView *sourceView = (UIView *)view;
        sourceRect = [sourceView.superview convertRect:sourceView.frame toView:[self topWindow]];
        // Align the popover's right edge to the button's left edge.
        // moveToPoint calculates final_x = point.x - (popover_width / 2).
        // We want final_x = button.x - popover_width.
        // So, we solve for point.x: point.x = button.x - popover_width / 2.
        CGFloat popoverWidth = kFixedWidth;
        CGFloat pointX = CGRectGetMinX(sourceRect) - popoverWidth / 2.0f;
        point = CGPointMake(pointX + 15, CGRectGetMinY(sourceRect) - 50);
        [self showFromPoint:point sourceRect:sourceRect arrowDirection:SFActionSheetArrowDirectionBottom animated:YES];
        return;
    } else {
        // For other types of views, ensure using top right corner of navigation bar
        sourceRect = [self navigationBarAnchorRectInView:window];
        point = (CGPoint){CGRectGetMidX(sourceRect), CGRectGetMaxY(sourceRect) - 20};
    }

    [self showFromPoint:point sourceRect:sourceRect arrowDirection:SFActionSheetArrowDirectionTop animated:YES];
}

// UIKit keeps popovers attached to their source as the window and sidebar resize,
// adapts them to compact sheets, and scrolls actions at large accessibility sizes.
- (void)showSystemActionSheetFromView:(id)source {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    self.systemAlert = alert;
    for (NSUInteger sectionIndex = 0; sectionIndex < self.sections.count; sectionIndex++) {
        SeafActionSheetSection *section = self.sections[sectionIndex];
        for (NSUInteger row = 0; row < section.buttons.count; row++) {
            UIButton *button = section.buttons[row];
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:sectionIndex];
            // The presented alert retains the facade until the action completes.
            UIAlertAction *action = [UIAlertAction actionWithTitle:button.currentTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self buttonPressed:indexPath];
            }];
            action.enabled = button.enabled;
            [alert addAction:action];
        }
    }
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if ([source isKindOfClass:UIBarButtonItem.class]) {
        popover.barButtonItem = source;
    } else {
        UIView *anchor = [source isKindOfClass:UIView.class] ? source : self.targetVC.view;
        popover.sourceView = anchor;
        popover.sourceRect = anchor.bounds;
    }
    alert.view.accessibilityIdentifier = @"seafile_action_sheet";
    [self.targetVC presentViewController:alert animated:YES completion:nil];
}

/// A 40pt square whose center sits 10pt in from the navigation bar's bottom-right
/// corner, in the given view's coordinates. Fallback anchor when no source view exists.
- (CGRect)navigationBarAnchorRectInView:(UIView *)view {
    UINavigationBar *bar = _targetVC.navigationController.navigationBar;
    CGRect barRect = bar ? [bar convertRect:bar.bounds toView:view] : CGRectZero;
    CGPoint corner = CGPointMake(CGRectGetMaxX(barRect) - 10, CGRectGetMaxY(barRect));
    return CGRectMake(corner.x - 20, corner.y - 20, 40, 40);
}

// Show from specific point with source rectangle and animation
- (void)showFromPoint:(CGPoint)point sourceRect:(CGRect)sourceRect arrowDirection:(SFActionSheetArrowDirection)arrowDirection animated:(BOOL)animated {
    [self suspendInteraction];

    // Bar-button menus use the measured content height and the safe area below.
    if (!_anchoredToBarButton && point.y > CGRectGetHeight([self topWindow].bounds) - 320 - 50) {
        arrowDirection = SFActionSheetArrowDirectionBottom;
    }

    [self moveToPoint:point arrowDirection:arrowDirection animated:NO];

    void (^completion)(void) = ^{
        [self resumeInteraction];
    };

    // Initial state: scale to 0 and set animation anchor point to source button position
    if (animated) {
        CGPoint anchorPoint;
        
        // Calculate animation anchor point (relative to popup position)
        if (arrowDirection == SFActionSheetArrowDirectionTop) {
            // Top right corner as anchor
            anchorPoint = CGPointMake(1.0, 0.0);
        } else if (arrowDirection == SFActionSheetArrowDirectionBottom) {
            anchorPoint = CGPointMake(0.5, 1.0);
        } else if (arrowDirection == SFActionSheetArrowDirectionLeft) {
            anchorPoint = CGPointMake(0.0, 0.5);
        } else {
            anchorPoint = CGPointMake(1.0, 0.5);
        }
        
        // Record original position
        CGRect animFrame = _scrollViewHost.frame;
        
        // Adjust anchor point
        _scrollViewHost.layer.anchorPoint = anchorPoint;
        
        // Need to readjust position due to anchor point change
        if (arrowDirection == SFActionSheetArrowDirectionTop) {
            _scrollViewHost.layer.position = CGPointMake(
                animFrame.origin.x + animFrame.size.width,
                animFrame.origin.y
            );
        } else if (arrowDirection == SFActionSheetArrowDirectionBottom) {
            _scrollViewHost.layer.position = CGPointMake(
                animFrame.origin.x + animFrame.size.width/2,
                animFrame.origin.y + animFrame.size.height
            );
        } else if (arrowDirection == SFActionSheetArrowDirectionLeft) {
            _scrollViewHost.layer.position = CGPointMake(
                animFrame.origin.x,
                animFrame.origin.y + animFrame.size.height/2
            );
        } else {
            _scrollViewHost.layer.position = CGPointMake(
                animFrame.origin.x + animFrame.size.width,
                animFrame.origin.y + animFrame.size.height/2
            );
        }
        
        // Start scaling from click position
        _scrollViewHost.transform = CGAffineTransformMakeScale(0.01, 0.01);
        _scrollViewHost.alpha = 0.0f;
    }

    [[self topWindow] addSubview:self];

    if (!animated) {
        _scrollViewHost.transform = CGAffineTransformIdentity;
        _scrollViewHost.alpha = 1.0f;
        completion();
    } else {
        // Pop-up animation
        CGFloat duration = 0.25f;
        
        // Use spring animation for bouncy effect
        [UIView animateWithDuration:duration delay:0 
                            options:UIViewAnimationOptionCurveEaseOut 
                         animations:^{
            self->_scrollViewHost.transform = CGAffineTransformIdentity;
            self->_scrollViewHost.alpha = 1.0f;
        } completion:^(BOOL finished) {
            completion();
        }];
    }
}

// Move to specified point
- (void)moveToPoint:(CGPoint)point arrowDirection:(SFActionSheetArrowDirection)arrowDirection animated:(BOOL)animated {
    [self suspendInteraction];

    disableCustomEasing = YES;

    void (^changes)(void) = ^{
        self.frame = [self topWindow].bounds;
        CGRect finalFrame = CGRectZero;
        CGFloat spacing = kSpacing; // Use 5px spacing
        
        // Fixed width of 200px
        finalFrame.size.width = kFixedWidth;
        
        // Calculate content height - let layoutSheetForFrame determine height
        finalFrame.size.height = 0; // Height will be determined by content
        
        // Calculate popup position
        if (arrowDirection == SFActionSheetArrowDirectionRight) {
            finalFrame.origin.x = point.x - finalFrame.size.width - spacing;
            finalFrame.origin.y = point.y;
        } else if (arrowDirection == SFActionSheetArrowDirectionLeft) {
            finalFrame.origin.x = point.x + spacing;
            finalFrame.origin.y = point.y;
        } else if (arrowDirection == SFActionSheetArrowDirectionTop) {
            // Special handling for top popup, align top right corner to point
            finalFrame.origin.x = point.x - finalFrame.size.width;
            finalFrame.origin.y = point.y + spacing;
            
            // Ensure not exceeding left screen edge
            if (finalFrame.origin.x < spacing) {
                finalFrame.origin.x = spacing;
            }
        } else if (arrowDirection == SFActionSheetArrowDirectionBottom) {
            finalFrame.origin.x = point.x - finalFrame.size.width / 2.0f;
            finalFrame.origin.y = point.y - spacing;
            
            // Ensure not exceeding screen edges
            if (finalFrame.origin.x < spacing) {
                finalFrame.origin.x = spacing;
            } else if (finalFrame.origin.x + finalFrame.size.width > CGRectGetWidth(_targetVC.view.bounds) - spacing) {
                finalFrame.origin.x = CGRectGetWidth(_targetVC.view.bounds) - finalFrame.size.width - spacing;
            }
        } else {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Invalid arrow direction" userInfo:nil];
        }

        _scrollViewHost.backgroundColor = [SeafTheme elevatedSurface];
        
        // Let layoutSheetForFrame calculate exact content height
        [self layoutSheetForFrame:finalFrame];
        
        // If height is 0, recalculate height (fallback plan)
        if (CGRectGetHeight(_scrollViewHost.frame) == 0) {
            CGFloat contentHeight = 0;
            for (SeafActionSheetSection *section in self.sections) {
                contentHeight += CGRectGetHeight(section.frame);
            }
            CGRect frame = _scrollViewHost.frame;
            frame.size.height = contentHeight;
            _scrollViewHost.frame = frame;
        }
        
        // Record final dimensions
        _finalContentFrame = _scrollViewHost.frame;
        
        // Record anchor information
        _anchoredAtPoint = YES;
        _anchorPoint = point;
        _anchoredArrowDirection = arrowDirection;
    };

    void (^completion)(void) = ^{
        [self resumeInteraction];
    };

    if (animated) {
        [UIView animateWithDuration:0.3 animations:changes completion:^(BOOL finished) {
            completion();
        }];
    } else {
        changes();
        completion();
    }

    disableCustomEasing = NO;
}

- (void)anchorSheetAtPoint:(CGPoint)point withArrowDirection:(SFActionSheetArrowDirection)arrowDirection availableFrame:(CGRect)frame {
    _anchoredAtPoint = YES;
    _anchorPoint = point;
    _anchoredArrowDirection = arrowDirection;

    // Create frame with fixed width
    CGRect finalFrame = CGRectMake(0, 0, kFixedWidth, 0); // Width fixed at 200px
    finalFrame.size.height = _scrollViewHost.frame.size.height;
    
    CGFloat spacing = kSpacing; // Use 5px spacing

    // Position popup based on arrow direction
    if (arrowDirection == SFActionSheetArrowDirectionRight) {
        finalFrame.origin.x = point.x - finalFrame.size.width - spacing;
        finalFrame.origin.y = point.y - finalFrame.size.height / 2.0f;
    } else if (arrowDirection == SFActionSheetArrowDirectionLeft) {
        finalFrame.origin.x = point.x + spacing;
        finalFrame.origin.y = point.y - finalFrame.size.height / 2.0f;
    } else if (arrowDirection == SFActionSheetArrowDirectionTop) {
        finalFrame.origin.x = point.x - finalFrame.size.width / 2.0f;
        finalFrame.origin.y = point.y + spacing;
    } else if (arrowDirection == SFActionSheetArrowDirectionBottom) {
        finalFrame.origin.x = point.x - finalFrame.size.width / 2.0f;
        finalFrame.origin.y = point.y - finalFrame.size.height - spacing;
    }

    // Ensure popup doesn't exceed screen edges, maintaining 5px spacing
    CGFloat maxX = CGRectGetWidth(_targetVC.view.bounds) - finalFrame.size.width - spacing;
    CGFloat minX = spacing;
    
    if (finalFrame.origin.x > maxX) {
        finalFrame.origin.x = maxX;
    } else if (finalFrame.origin.x < minX) {
        finalFrame.origin.x = minX;
    }
    
    // Ensure not exceeding top and bottom
    CGFloat maxY = CGRectGetHeight(_targetVC.view.bounds) - finalFrame.size.height - spacing;
    CGFloat minY = spacing;
    
    if (finalFrame.origin.y > maxY) {
        finalFrame.origin.y = maxY;
    } else if (finalFrame.origin.y < minY) {
        finalFrame.origin.y = minY;
    }

    // Remove triangle view
    if (_arrowView) {
        [_arrowView removeFromSuperview];
        _arrowView = nil;
    }

    // Ensure shadow effect
    _scrollViewHost.layer.shadowColor = [UIColor blackColor].CGColor;
    _scrollViewHost.layer.shadowOffset = CGSizeMake(0, 2);
    _scrollViewHost.layer.shadowRadius = kShadowRadius;
    _scrollViewHost.layer.shadowOpacity = kShadowOpacity;
    _scrollViewHost.layer.masksToBounds = NO; // Don't clip shadows

    if (!CGRectContainsRect(_targetVC.view.bounds, finalFrame)) {
        NSLog(@"WARNING: Action sheet does not fit view bounds!");
    }

    _scrollViewHost.frame = finalFrame;
}

#pragma mark Dismissal

- (void)dismissAnimated:(BOOL)animated {
    if (self.systemAlert) {
        [self.systemAlert dismissViewControllerAnimated:animated completion:nil];
        return;
    }
    [self suspendInteraction];

    void (^completion)(void) = ^{
        // Reset transform and anchor point
        self->_scrollViewHost.layer.anchorPoint = CGPointMake(0.5, 0.5);
        self->_scrollViewHost.transform = CGAffineTransformIdentity;
        self->_scrollViewHost.alpha = 1.0f; // Reset alpha
        
        [self removeFromSuperview];

        _anchoredAtPoint = NO;
        _anchoredToBarButton = NO;
        _anchoredArrowDirection = 0;
        _anchorPoint = CGPointZero;
        _laidOutSize = CGSizeZero;

        [self resumeInteraction];
    };

    if (animated) {
        // Fade out animation, no scaling
        CGFloat duration = 0.2f;
        
        [UIView animateWithDuration:duration 
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            // Only change opacity, no scaling
            self->_scrollViewHost.alpha = 0.0f;
        } completion:^(BOOL finished) {
            completion();
        }];
    } else {
        completion();
    }
}

- (UIView *)topWindow {
    UIWindow *window = _anchoredToBarButton ? self.targetVC.viewIfLoaded.window : nil;
    return window ?: [SeafAppDelegate topViewController].view.window;
}

// Show/move/dismiss nest their calls, and -layoutSubviews re-enters via -moveToPoint:,
// so the suspensions have to be counted the way the old UIApplication API did it.
- (void)suspendInteraction {
    if (_interactionSuspendCount == 0) {
        _interactionSuspendedWindow = [self topWindow];
        _interactionSuspendedWindow.userInteractionEnabled = NO;
    }
    _interactionSuspendCount++;
}

- (void)resumeInteraction {
    if (_interactionSuspendCount == 0)
        return;
    _interactionSuspendCount--;
    if (_interactionSuspendCount == 0) {
        _interactionSuspendedWindow.userInteractionEnabled = YES;
        _interactionSuspendedWindow = nil;
    }
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

@end
