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

#define kHostsCornerRadius 12.0f

#define kSpacing 5.0f

#define kArrowBaseWidth 14.0f
#define kArrowHeight 8.0f

#define kShadowRadius 5.0f
#define kShadowOpacity 0.15f

#define kFixedWidth 200.0f
#define kFixedWidthContinuous 200.0f
#define kScreenHeight [UIScreen mainScreen].bounds.size.height
#define KButtonHeight = 44.0f

#define kAnimationDurationForSectionCount(count) MAX(0.25f, MIN(count*0.08f, 0.35f))

#define rgba(r, g, b, a) [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:a]

#define rgb(r, g, b) rgba(r, g, b, 1.0f)

#ifndef iPad
#define iPad (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
#endif

#pragma mark - Helpers

@interface SeafSectionButton : UIButton

@property (nonatomic, assign) NSUInteger row;

@end

@implementation SeafSectionButton

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
    
    self.layer.contentsScale = [UIScreen mainScreen].scale;
    ((CAShapeLayer *)self.layer).fillColor = [UIColor whiteColor].CGColor;
    ((CAShapeLayer *)self.layer).strokeColor = [UIColor clearColor].CGColor;
}

+ (Class)layerClass {
    return [SeafActionSheetLayer class];
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
        if (@available(iOS 11.0, *)) {
            buttonHeight += [[UIApplication sharedApplication] delegate].window.safeAreaInsets.bottom;
            titleInsets = UIEdgeInsetsMake(0, 10, [[UIApplication sharedApplication] delegate].window.safeAreaInsets.bottom, 0);
        }
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
    [b setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [b setTitleEdgeInsets:titleInsets];
    [b addTarget:self action:@selector(buttonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [b setBackgroundImage:[self pixelImageWithColor:[UIColor colorWithWhite:1.0 alpha:1.0]] forState:UIControlStateNormal];
    [b setBackgroundImage:[self pixelImageWithColor:[UIColor colorWithWhite:0.8 alpha:1.0]] forState:UIControlStateHighlighted];
    
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
        [b setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
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
    CGFloat spacing = 0;
    CGFloat height = 0.0f;

    for (UIButton *button in self.buttons) {
        height += spacing;
        button.frame = (CGRect){{spacing, height}, {width, button.bounds.size.height}};
        height += button.bounds.size.height;
        
        for (UIView *subview in button.subviews) {
            if (subview.frame.size.height <= 0.5) {
                [subview removeFromSuperview];
            }
        }
    }

    height += spacing;
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
    CGPoint _anchorPoint;// The point at which the action sheet is anchored
    SFActionSheetArrowDirection _anchoredArrowDirection;// The direction of the arrow when the action sheet is anchored
}

@property (nonatomic, strong) NSArray *sections;// Array of sections within the action sheet

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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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

- (void)orientationChanged {
    if (_targetVC.view && !CGRectEqualToRect(self.bounds, _targetVC.view.bounds)) {
        disableCustomEasing = YES;
        [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
            if (_anchoredAtPoint) {
                [self moveToPoint:_anchorPoint arrowDirection:_anchoredArrowDirection animated:NO];
            }
            else {
                [self layoutSheetInitial:NO];
            }
        } completion:^(BOOL finished) {
            disableCustomEasing = NO;
        }];
    }
}

- (void)buttonPressed:(NSIndexPath *)indexPath {
    if (self.buttonPressedBlock) {
        self.buttonPressedBlock(self, indexPath);
    }
}

#pragma mark Layout
// Lays out the sections within the action sheet based on the given frame.
- (void)layoutSheetForFrame:(CGRect)frame fitToRect:(BOOL)fitToRect initialSetUp:(BOOL)initial {
    // Force fixed width
    frame.size.width = kFixedWidth;
    
    // Calculate content height
    CGFloat width = CGRectGetWidth(frame);
    CGFloat height = 0;

    for (SeafActionSheetSection *section in self.sections) {
        CGRect f = [section layoutForWidth:width];
        f.origin.y = height;
        f.origin.x = 0;
        section.frame = f;
        height += CGRectGetHeight(f);
    }

    // Set content size
    _scrollView.contentSize = (CGSize){width, height};
    
    // Directly use content height as popup height
    CGFloat finalY = frame.origin.y;
    _scrollViewHost.frame = (CGRect){{frame.origin.x, finalY}, {width, height}};

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

    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

    [self layoutSheetInitial:YES];

    void (^completion)(void) = ^{
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    };

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged) name:UIApplicationDidChangeStatusBarFrameNotification object:nil];
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

- (void)layoutSheetInitial:(BOOL)initial {
    self.frame = [self topWindow].bounds;
    
    _scrollViewHost.backgroundColor = [UIColor whiteColor]; // White background

    CGRect frame = self.frame;
    // Use fixed width of 200
    frame.origin.x = (CGRectGetWidth(frame) - kFixedWidth) / 2.0f;
    frame.size.width = kFixedWidth;

    // Use 5px spacing
    frame = UIEdgeInsetsInsetRect(frame, UIEdgeInsetsMake(kSpacing, kSpacing, kSpacing, kSpacing));
    [self layoutSheetForFrame:frame fitToRect:YES initialSetUp:initial];
}

#pragma mark Showing From Point

- (void)showFromPoint:(CGPoint)point inView:(UIView *)view arrowDirection:(SFActionSheetArrowDirection)arrowDirection animated:(BOOL)animated {
    CGRect sourceRect = CGRectMake(point.x - 1, point.y - 1, 2, 2); // Default small area
    [self showFromPoint:point sourceRect:sourceRect arrowDirection:arrowDirection animated:animated];
}

// ShowFromView method - For displaying the action sheet from a specific view
- (void)showFromView:(id)view {
    CGPoint point = CGPointZero;
    CGRect sourceRect = CGRectZero; // Record animation starting position
    
    if ([view isKindOfClass:[SeafCell class]]) {
        SeafCell *cell = (SeafCell*)view;
        point = (CGPoint){CGRectGetMidX(cell.moreButton.frame), CGRectGetMaxY(cell.moreButton.frame) - cell.moreButton.frame.size.height/2};
        sourceRect = cell.moreButton.frame;
        point = [_targetVC.navigationController.view convertPoint:point fromView:cell];
        sourceRect = [_targetVC.navigationController.view convertRect:sourceRect fromView:cell];
    } else if ([view isKindOfClass:[UIBarButtonItem class]]) {
        UIBarButtonItem *item = (UIBarButtonItem*)view;
        UIView *itemView = [item valueForKey:@"view"];
        
        if (itemView) {
            // Get the button position in navigation bar
            CGRect frameInNaviView = [_targetVC.navigationController.view convertRect:itemView.frame fromView:itemView.superview];
            
            // Use the bottom right corner of the button as anchor point
            point = (CGPoint){CGRectGetMaxX(frameInNaviView), CGRectGetMaxY(frameInNaviView)};
            sourceRect = frameInNaviView;
            
            // Log anchor position for debugging
            NSLog(@"Anchor position: x=%f, y=%f", point.x, point.y);
        } else {
            // If unable to get specific view, use top right corner of navigation bar
            CGRect navBarFrame = _targetVC.navigationController.navigationBar.frame;
            point = CGPointMake(CGRectGetMaxX(navBarFrame) - 10, CGRectGetMaxY(navBarFrame));
            sourceRect = CGRectMake(point.x - 20, point.y - 20, 40, 40);
            
            NSLog(@"Using default top right corner position: x=%f, y=%f", point.x, point.y);
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
        CGRect navBarFrame = _targetVC.navigationController.navigationBar.frame;
        point = CGPointMake(CGRectGetMaxX(navBarFrame) - 10, CGRectGetMaxY(navBarFrame));
        sourceRect = CGRectMake(point.x - 20, point.y - 20, 40, 40);
    }
    
    [self showFromPoint:point sourceRect:sourceRect arrowDirection:SFActionSheetArrowDirectionTop animated:YES];
}

// Show from specific point with source rectangle and animation
- (void)showFromPoint:(CGPoint)point sourceRect:(CGRect)sourceRect arrowDirection:(SFActionSheetArrowDirection)arrowDirection animated:(BOOL)animated {
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

    // Automatically adjust arrow direction based on screen space
    if (point.y > kScreenHeight - 320 - 50) {
        arrowDirection = SFActionSheetArrowDirectionBottom;
    }

    [self moveToPoint:point arrowDirection:arrowDirection animated:NO];
    
    // Get current calculated dimensions
    CGRect finalFrame = _scrollViewHost.frame;
    CGFloat contentHeight = 0;
    
    // Recalculate content height to ensure precision
    for (SeafActionSheetSection *section in self.sections) {
        contentHeight += CGRectGetHeight(section.frame);
    }
    
    // Ensure height exactly matches content
    finalFrame.size.height = contentHeight;
    
    // If popping from top button, adjust popup position
    if (arrowDirection == SFActionSheetArrowDirectionTop) {
        // Align the top right corner of popup to anchor point
        CGFloat newX = point.x - finalFrame.size.width;
        // Ensure not exceeding left screen edge
        if (newX < kSpacing) {
            newX = kSpacing;
        }
        _scrollViewHost.frame = CGRectMake(newX, finalFrame.origin.y, 
                                         finalFrame.size.width, finalFrame.size.height);
    } else {
        _scrollViewHost.frame = finalFrame;
    }

    void (^completion)(void) = ^{
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    };

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged) name:UIApplicationDidChangeStatusBarFrameNotification object:nil];

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
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

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

        _scrollViewHost.backgroundColor = [UIColor whiteColor]; // Maintain white background
        
        // Let layoutSheetForFrame calculate exact content height
        [self layoutSheetForFrame:finalFrame fitToRect:NO initialSetUp:YES];
        
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
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
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
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

    void (^completion)(void) = ^{
        // Reset transform and anchor point
        self->_scrollViewHost.layer.anchorPoint = CGPointMake(0.5, 0.5);
        self->_scrollViewHost.transform = CGAffineTransformIdentity;
        self->_scrollViewHost.alpha = 1.0f; // Reset alpha
        
        [self removeFromSuperview];

        _anchoredAtPoint = NO;
        _anchoredArrowDirection = 0;
        _anchorPoint = CGPointZero;

        [[NSNotificationCenter defaultCenter] removeObserver:self];

        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
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
    return [SeafAppDelegate topViewController].view.window;
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

@end
