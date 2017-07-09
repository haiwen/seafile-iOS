//
//  SeafActionSheet.m
//  seafilePro
//
//  Created by three on 2017/6/14.
//  Copyright © 2017年 Seafile. All rights reserved.
//

#import "SeafActionSheet.h"

#define kHostsCornerRadius 3.0f

#define kSpacing 5.0f

#define kArrowBaseWidth 20.0f
#define kArrowHeight 10.0f

#define kShadowRadius 4.0f
#define kShadowOpacity 0.2f

#define kFixedWidth 320.0f
#define kFixedWidthContinuous 300.0f
#define kScreenHeight [UIScreen mainScreen].bounds.size.height

#define kAnimationDurationForSectionCount(count) MAX(0.22f, MIN(count*0.12f, 0.45f))

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

    if (arrowDirection == SFActionSheetArrowDirectionBottom) {
        [path moveToPoint:CGPointZero];
        [path addLineToPoint:(CGPoint){CGRectGetWidth(rect)/2.0f, CGRectGetHeight(rect)}];
        [path addLineToPoint:(CGPoint){CGRectGetWidth(rect), 0.0f}];
    }
    else if (arrowDirection == SFActionSheetArrowDirectionLeft) {
        [path moveToPoint:(CGPoint){CGRectGetWidth(rect), 0.0f}];
        [path addLineToPoint:(CGPoint){0.0f, CGRectGetHeight(rect)/2.0f}];
        [path addLineToPoint:(CGPoint){CGRectGetWidth(rect), CGRectGetHeight(rect)}];
    }
    else if (arrowDirection == SFActionSheetArrowDirectionRight) {
        [path moveToPoint:CGPointZero];
        [path addLineToPoint:(CGPoint){CGRectGetWidth(rect), CGRectGetHeight(rect)/2.0f}];
        [path addLineToPoint:(CGPoint){0.0f, CGRectGetHeight(rect)}];
    }
    else if (arrowDirection == SFActionSheetArrowDirectionTop) {
        [path moveToPoint:(CGPoint){0.0f, CGRectGetHeight(rect)}];
        [path addLineToPoint:(CGPoint){CGRectGetWidth(rect)/2.0f, 0.0f}];
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

- (void)setUpForContinuous:(BOOL)continuous;

@end

@implementation SeafActionSheetSection

+ (instancetype)cancelSection {
    return [self sectionWithTitle:nil message:nil buttonTitles:@[NSLocalizedString(@"Cancel",)] buttonStyle:SFActionSheetButtonStyleCancel];
}

+(instancetype)sectionWithTitle:(NSString *)title message:(NSString *)message buttonTitles:(NSArray *)buttonTitles buttonStyle:(SFActionSheetButtonStyle)buttonStyle {
    return [[self alloc] initWithTitle:title message:message buttonTitles:buttonTitles buttonStyle:buttonStyle];
}

-(instancetype)initWithTitle:(NSString *)title message:(NSString *)message buttonTitles:(NSArray *)buttonTitles buttonStyle:(SFActionSheetButtonStyle)buttonStyle {
    self = [super init];

    if (self) {
        if (title) {
            UILabel *titleLabel = [[UILabel alloc] init];
            titleLabel.backgroundColor = [UIColor clearColor];
            titleLabel.textAlignment = NSTextAlignmentCenter;
            titleLabel.font = [UIFont boldSystemFontOfSize:14.0f];
            titleLabel.textColor = [UIColor blackColor];
            titleLabel.numberOfLines = 1;

            titleLabel.text = title;

            _titleLabel = titleLabel;

            [self addSubview:_titleLabel];
        }

        if (message) {
            UILabel *messageLabel = [[UILabel alloc] init];
            messageLabel.backgroundColor = [UIColor clearColor];
            messageLabel.textAlignment = NSTextAlignmentCenter;
            messageLabel.font = [UIFont systemFontOfSize:12.0f];
            messageLabel.textColor = [UIColor blackColor];
            messageLabel.numberOfLines = 0;

            messageLabel.text = message;

            _messageLabel = messageLabel;

            [self addSubview:_messageLabel];
        }

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

- (void)setUpForContinuous:(BOOL)continuous {
    if (continuous) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.cornerRadius = 0.0f;
        self.layer.shadowOpacity = 0.0f;
    }
    else {
        self.backgroundColor = [UIColor clearColor];
        self.layer.cornerRadius = kHostsCornerRadius;

    }
}

- (void)setButtonStyle:(SFActionSheetButtonStyle)buttonStyle forButtonAtIndex:(NSUInteger)index {
    if (index < self.buttons.count) {
        UIButton *button = self.buttons[index];

        [self setButtonStyle:buttonStyle forButton:button];
    }
    else {
        NSLog(@"ERROR: Index out of bounds");
        return;
    }
}

- (void)setButtonStyle:(SFActionSheetButtonStyle)buttonStyle forButton:(UIButton *)button {
    UIColor *backgroundColor, *borderColor, *titleColor = nil;
    UIFont *font = nil;

    if (buttonStyle == SFActionSheetButtonStyleDefault) {
        font = [UIFont systemFontOfSize:15.0f];
        titleColor = [UIColor blackColor];

        backgroundColor = [UIColor colorWithWhite:1.0 alpha:1.0];
        borderColor = [UIColor colorWithWhite:1.0 alpha:1.0];
    }
    else if (buttonStyle == SFActionSheetButtonStyleCancel) {
        font = [UIFont boldSystemFontOfSize:15.0f];
        titleColor = [UIColor blackColor];

        backgroundColor = [UIColor colorWithWhite:1.0 alpha:1.0];
        borderColor = [UIColor colorWithWhite:1.0 alpha:1.0];
    }
    else if (buttonStyle == SFActionSheetButtonStyleRed) {
        font = [UIFont systemFontOfSize:15.0f];
        titleColor = [UIColor whiteColor];

        backgroundColor = rgb(231.0f, 76.0f, 60.0f);
        borderColor = rgb(192.0f, 57.0f, 43.0f);
    }
    else if (buttonStyle == SFActionSheetButtonStyleBlue) {
        font = [UIFont systemFontOfSize:15.0f];
        titleColor = [UIColor whiteColor];

        backgroundColor = rgb(52.0f, 152.0f, 219.0f);
        borderColor = rgb(41.0f, 128.0f, 185.0f);
    }

    [button setTitleColor:titleColor forState:UIControlStateNormal];

    button.titleLabel.font = font;

    [button setBackgroundImage:[self pixelImageWithColor:backgroundColor] forState:UIControlStateNormal];
    [button setBackgroundImage:[self pixelImageWithColor:borderColor] forState:UIControlStateHighlighted];

    button.layer.borderColor = borderColor.CGColor;
}

- (UIImage *)pixelImageWithColor:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions((CGSize){1.0f, 1.0f}, YES, 0.0f);

    [color setFill];

    [[UIBezierPath bezierPathWithRect:(CGRect){CGPointZero, {1.0f, 1.0f}}] fill];

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();

    UIGraphicsEndImageContext();

    return [img resizableImageWithCapInsets:UIEdgeInsetsZero];
}

- (SeafSectionButton *)makeButtonWithTitle:(NSString *)title style:(SFActionSheetButtonStyle)style {
    SeafSectionButton *b = [[SeafSectionButton alloc] init];

//    b.layer.cornerRadius = 2.0f;
//    b.layer.masksToBounds = YES;
//    b.layer.borderWidth = 1.0f;

    [b setTitle:title forState:UIControlStateNormal];

    [b addTarget:self action:@selector(buttonPressed:) forControlEvents:UIControlEventTouchUpInside];

    [self setButtonStyle:style forButton:b];

    return b;
}

- (void)buttonPressed:(SeafSectionButton *)button {
    if (self.buttonPressedBlock) {
        self.buttonPressedBlock([NSIndexPath indexPathForRow:(NSInteger)button.row inSection:(NSInteger)self.index]);
    }
}

- (CGRect)layoutForWidth:(CGFloat)width {
    CGFloat buttonHeight = 44.0f;
    CGFloat spacing = 0;

    CGFloat height = 0.0f;

    if (self.titleLabel) {
        height += spacing;

        [self.titleLabel sizeToFit];
        height += CGRectGetHeight(self.titleLabel.frame);

        self.titleLabel.frame = (CGRect){{spacing, spacing}, {width-spacing*2.0f, CGRectGetHeight(self.titleLabel.frame)}};
    }

    if (self.messageLabel) {
        height += spacing;

        CGSize maxLabelSize = {width-spacing*2.0f, width};

        CGFloat messageLabelHeight = 0.0f;

        NSDictionary *attributes = @{NSFontAttributeName : self.messageLabel.font};

        messageLabelHeight = CGRectGetHeight([self.messageLabel.text boundingRectWithSize:maxLabelSize options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes context:nil]);

        self.messageLabel.frame = (CGRect){{spacing, height}, {width-spacing*2.0f, messageLabelHeight}};

        height += messageLabelHeight;
    }

    for (UIButton *button in self.buttons) {
        height += spacing;

        NSInteger index = [self.buttons indexOfObject:button];

        button.frame = (CGRect){{spacing, height}, {width-spacing*2.0f, buttonHeight}};

        UIView *l = [[UIView alloc] initWithFrame:CGRectMake(10, CGRectGetHeight(button.frame)-0.5, button.bounds.size.width - 20, 0.5)];
        l.backgroundColor = rgba(210.0f, 210.0f, 210.0f,0.5);
        [button addSubview:l];

        if (iPad) {
            if (index == self.buttons.count - 1) {
                [l removeFromSuperview];
            }
        }

        height += buttonHeight;
    }

    if (self.contentView) {
        height += spacing;

        self.contentView.frame = (CGRect){{spacing, height}, {width-spacing*2.0f, self.contentView.frame.size.height}};

        height += CGRectGetHeight(self.contentView.frame);
    }

    height += spacing;

    self.frame = (CGRect){CGPointZero, {width, height}};

    self.backgroundColor = [UIColor clearColor];
    return self.frame;
}

@end

@interface SeafActionSheet ()<UIGestureRecognizerDelegate> {
    UIScrollView *_scrollView;
    SeafActionSheetTriangle *_arrowView;
    SeafActionSheetView *_scrollViewHost;

    CGRect _finalContentFrame;

    UIColor *_realBGColor;

    BOOL _anchoredAtPoint;
    CGPoint _anchorPoint;
    SFActionSheetArrowDirection _anchoredArrowDirection;
}

@end

@implementation SeafActionSheet

+ (instancetype)actionSheetWithSections:(NSArray *)sections {
    return [[self alloc] initWithSections:sections];
}

- (instancetype)initWithSections:(NSArray *)sections {
    NSAssert(sections.count > 0, @"Must at least provide 1 section");

    self = [super init];

    if (self) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        tap.delegate = self;

        [self addGestureRecognizer:tap];

        _scrollViewHost = [[SeafActionSheetView alloc] init];
        _scrollViewHost.backgroundColor = [UIColor clearColor];

        _scrollView = [[UIScrollView alloc] init];
        _scrollView.backgroundColor = [UIColor clearColor];
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.showsVerticalScrollIndicator = NO;

        [_scrollViewHost addSubview:_scrollView];
        [self addSubview:_scrollViewHost];

        self.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.3f];

        _sections = sections;

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
    if ([self hitTest:[gestureRecognizer locationInView:self] withEvent:nil] == self && self.outsidePressBlock) {
        return YES;
    }

    return NO;
}

- (void)tapped:(UITapGestureRecognizer *)gesture {
    if ([self hitTest:[gesture locationInView:self] withEvent:nil] == self && self.outsidePressBlock) {
        self.outsidePressBlock(self);
    }
}

- (void)orientationChanged {
    if (_targetView && !CGRectEqualToRect(self.bounds, _targetView.bounds)) {
        disableCustomEasing = YES;
        [UIView animateWithDuration:(iPad ? 0.4 : 0.3) delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
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

- (void)layoutSheetForFrame:(CGRect)frame fitToRect:(BOOL)fitToRect initialSetUp:(BOOL)initial continuous:(BOOL)continuous {
    if (continuous) {
        frame.size.width = kFixedWidthContinuous;
    }

    CGFloat spacing = 2.0f*kSpacing;

    CGFloat width = CGRectGetWidth(frame);

    CGFloat height = (continuous ? 0.0f : spacing);

    for (SeafActionSheetSection *section in self.sections) {
        if (initial) {
            [section setUpForContinuous:continuous];
        }

        CGRect f = [section layoutForWidth:width];

        f.origin.y = height;

        f.origin.x = 0;

        section.frame = f;

        height += CGRectGetHeight(f);
    }

    _scrollView.contentSize = (CGSize){CGRectGetWidth(frame), height};

    if (!fitToRect && !continuous) {
        frame.size.height = CGRectGetHeight(_targetView.bounds)-CGRectGetMinY(frame);
    }

    if (height > CGRectGetHeight(frame)) {
        _scrollViewHost.frame = frame;
    } else {
        CGFloat finalY = 0.0f;

        if (fitToRect) {
            finalY = CGRectGetMaxY(frame)-height;
        }
        else if (continuous) {
            finalY = CGRectGetMinY(frame);
        }
        else {
            finalY = CGRectGetMinY(frame)+(CGRectGetHeight(frame)-height)/2.0f;
        }

        _scrollViewHost.frame = (CGRect){{CGRectGetMinX(frame), finalY}, _scrollView.contentSize};
    }

    _finalContentFrame = _scrollViewHost.frame;

    _scrollView.frame = _scrollViewHost.bounds;

    [_scrollView scrollRectToVisible:(CGRect){{0.0f, _scrollView.contentSize.height-1.0f}, {1.0f, 1.0f}} animated:NO];

    UIVisualEffectView *effectView = [[UIVisualEffectView alloc]initWithEffect:[UIVibrancyEffect effectForBlurEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]]];
    effectView.frame = _scrollView.bounds;
    [_scrollViewHost insertSubview:effectView belowSubview:_scrollView];
}

- (void)layoutForVisible:(BOOL)visible {
    UIView *viewToModify = _scrollViewHost;

    if (visible) {
        self.backgroundColor = _realBGColor;

        if (iPad) {
            viewToModify.alpha = 1.0f;
            _arrowView.alpha = 1.0f;
        }
        else {
            viewToModify.frame = _finalContentFrame;
        }
    }
    else {
        super.backgroundColor = [UIColor clearColor];

        if (iPad) {
            viewToModify.alpha = 0.0f;
            _arrowView.alpha = 0.0f;
        }
        else {
            viewToModify.frame = (CGRect){{viewToModify.frame.origin.x, CGRectGetHeight(_targetView.bounds)}, _scrollView.contentSize};
        }
    }
}

#pragma mark Showing

- (void)showInView:(UIView *)view animated:(BOOL)animated {

    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

    _targetView = view;

    [self layoutSheetInitial:YES];

    void (^completion)(void) = ^{
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    };

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged) name:UIApplicationDidChangeStatusBarFrameNotification object:nil];

    [self layoutForVisible:!animated];

    [_targetView addSubview:self];

    if (!animated) {
        completion();
    }
    else {
        CGFloat duration = (iPad ? 0.3f : kAnimationDurationForSectionCount(self.sections.count));

        [UIView animateWithDuration:duration animations:^{
            [self layoutForVisible:YES];
        } completion:^(BOOL finished) {
            completion();
        }];
    }
}

- (void)layoutSheetInitial:(BOOL)initial {
    self.frame = _targetView.bounds;

    _scrollViewHost.layer.cornerRadius = 0.0f;
    _scrollViewHost.layer.shadowOpacity = 0.0f;
    _scrollViewHost.backgroundColor = [UIColor clearColor];

    CGRect frame = self.frame;

    if (iPad) {
        CGFloat fixedWidth = kFixedWidth;

        frame.origin.x = (CGRectGetWidth(frame)-fixedWidth)/2.0f;

        frame.size.width = fixedWidth;
    }

    frame = UIEdgeInsetsInsetRect(frame, self.insets);

    [self layoutSheetForFrame:frame fitToRect:!iPad initialSetUp:initial continuous:NO];
}

#pragma mark Showing From Point

- (void)showFromPoint:(CGPoint)point inView:(UIView *)view arrowDirection:(SFActionSheetArrowDirection)arrowDirection animated:(BOOL)animated {

    if (!iPad) {
        return [self showInView:view animated:animated];
    }

    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

    _targetView = view;

    if (point.y > kScreenHeight - 320 - 50) {
        arrowDirection = SFActionSheetArrowDirectionBottom;
    }

    [self moveToPoint:point arrowDirection:arrowDirection animated:NO];

    void (^completion)(void) = ^{
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    };

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged) name:UIApplicationDidChangeStatusBarFrameNotification object:nil];

    [self layoutForVisible:!animated];

    [_targetView addSubview:self];

    if (!animated) {
        completion();
    } else {
        CGFloat duration = 0.3f;

        [UIView animateWithDuration:duration animations:^{
            [self layoutForVisible:YES];
        } completion:^(BOOL finished) {
            completion();
        }];
    }
}

- (void)moveToPoint:(CGPoint)point arrowDirection:(SFActionSheetArrowDirection)arrowDirection animated:(BOOL)animated {
    if (!iPad) {
        return;
    }

    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

    disableCustomEasing = YES;

    void (^changes)(void) = ^{
        self.frame = _targetView.bounds;

        CGRect finalFrame = CGRectZero;

        CGFloat arrowHeight = kArrowHeight;

        CGFloat spacing = kSpacing;

        if (arrowDirection == SFActionSheetArrowDirectionRight) {
            finalFrame.size.width = point.x-arrowHeight;
            finalFrame.size.height = CGRectGetHeight(_targetView.bounds);
        } else if (arrowDirection == SFActionSheetArrowDirectionLeft) {
            finalFrame.size.width = CGRectGetWidth(_targetView.bounds)-point.x-arrowHeight;
            finalFrame.size.height = CGRectGetHeight(_targetView.bounds);
            finalFrame.origin.x = point.x+arrowHeight;
        } else if (arrowDirection == SFActionSheetArrowDirectionTop) {
            finalFrame.size.width = CGRectGetWidth(_targetView.bounds);
            finalFrame.size.height = CGRectGetHeight(_targetView.bounds)-point.y-arrowHeight;
            finalFrame.origin.y = point.y+arrowHeight;
        } else if (arrowDirection == SFActionSheetArrowDirectionBottom) {
            finalFrame.size.width = CGRectGetWidth(_targetView.bounds);
            finalFrame.size.height = point.y-arrowHeight;
        } else {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Invalid arrow direction" userInfo:nil];
        }

        finalFrame.origin.x += spacing;
        finalFrame.origin.y += spacing;
        finalFrame.size.height -= spacing*2.0f;
        finalFrame.size.width -= spacing*2.0f;

        finalFrame = UIEdgeInsetsInsetRect(finalFrame, self.insets);

        _scrollViewHost.backgroundColor = [UIColor clearColor];

        [self layoutSheetForFrame:finalFrame fitToRect:NO initialSetUp:YES continuous:YES];

        [self anchorSheetAtPoint:point withArrowDirection:arrowDirection availableFrame:finalFrame];
    };

    void (^completion)(void) = ^{
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    };

    if (animated) {
        [UIView animateWithDuration:0.3 animations:changes completion:^(BOOL finished) {
            completion();
        }];
    }
    else {
        changes();
        completion();
    }

    disableCustomEasing = NO;
}

- (void)anchorSheetAtPoint:(CGPoint)point withArrowDirection:(SFActionSheetArrowDirection)arrowDirection availableFrame:(CGRect)frame {
    _anchoredAtPoint = YES;
    _anchorPoint = point;
    _anchoredArrowDirection = arrowDirection;

    CGRect finalFrame = _scrollViewHost.frame;

    CGFloat arrowHeight = kArrowHeight;
    CGFloat arrrowBaseWidth = kArrowBaseWidth;

    BOOL leftOrRight = (arrowDirection == SFActionSheetArrowDirectionLeft || arrowDirection == SFActionSheetArrowDirectionRight);

    CGRect arrowFrame = (CGRect){CGPointZero, {(leftOrRight ? arrowHeight : arrrowBaseWidth), (leftOrRight ? arrrowBaseWidth : arrowHeight)}};

    if (arrowDirection == SFActionSheetArrowDirectionRight) {
        arrowFrame.origin.x = point.x-arrowHeight;
        arrowFrame.origin.y = point.y-arrrowBaseWidth/2.0f;

        finalFrame.origin.x = point.x-CGRectGetWidth(finalFrame)-arrowHeight;
    }
    else if (arrowDirection == SFActionSheetArrowDirectionLeft) {
        arrowFrame.origin.x = point.x;
        arrowFrame.origin.y = point.y-arrrowBaseWidth/2.0f;

        finalFrame.origin.x = point.x+arrowHeight;
    }
    else if (arrowDirection == SFActionSheetArrowDirectionTop) {
        arrowFrame.origin.x = point.x-arrrowBaseWidth/2.0f;
        arrowFrame.origin.y = point.y + kSpacing;

        finalFrame.origin.y = point.y+arrowHeight + kSpacing;
    }
    else if (arrowDirection == SFActionSheetArrowDirectionBottom) {
        arrowFrame.origin.x = point.x-arrrowBaseWidth/2.0f;
        arrowFrame.origin.y = point.y-arrowHeight - kSpacing;

        finalFrame.origin.y = point.y-CGRectGetHeight(finalFrame)-arrowHeight - kSpacing;
    }

    if (leftOrRight) {
        finalFrame.origin.y = MIN(MAX(CGRectGetMaxY(frame)-CGRectGetHeight(finalFrame), CGRectGetMaxY(arrowFrame)-CGRectGetHeight(finalFrame)+kHostsCornerRadius), MIN(MAX(CGRectGetMinY(frame), point.y-CGRectGetHeight(finalFrame)/2.0f), CGRectGetMinY(arrowFrame)-kHostsCornerRadius));
    }
    else {
        finalFrame.origin.x = MIN(MAX(MIN(CGRectGetMinX(frame), CGRectGetMinX(arrowFrame)-kHostsCornerRadius), point.x-CGRectGetWidth(finalFrame)/2.0f), MAX(CGRectGetMaxX(frame)-CGRectGetWidth(finalFrame), CGRectGetMaxX(arrowFrame)+kHostsCornerRadius-CGRectGetWidth(finalFrame)));
    }

    if (!_arrowView) {
        _arrowView = [[SeafActionSheetTriangle alloc] init];
        [self addSubview:_arrowView];
    }

    [_arrowView setFrame:arrowFrame arrowDirection:arrowDirection];

    if (!CGRectContainsRect(_targetView.bounds, finalFrame) || !CGRectContainsRect(_targetView.bounds, arrowFrame)) {
        NSLog(@"WARNING: Action sheet does not fit view bounds!");
    }

    _scrollViewHost.frame = finalFrame;
}

#pragma mark Dismissal

- (void)dismissAnimated:(BOOL)animated {

    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

    void (^completion)(void) = ^{
        [_arrowView removeFromSuperview];
        _arrowView = nil;

        _targetView = nil;

        [self removeFromSuperview];

        _anchoredAtPoint = NO;
        _anchoredArrowDirection = 0;
        _anchorPoint = CGPointZero;

        [[NSNotificationCenter defaultCenter] removeObserver:self];

        [[UIApplication sharedApplication] endIgnoringInteractionEvents];

    };

    if (animated) {
        CGFloat duration = 0.0f;

        if (iPad) {
            duration = 0.3f;
        } else {
            duration = kAnimationDurationForSectionCount(self.sections.count);
        }

        [UIView animateWithDuration:duration animations:^{
            [self layoutForVisible:NO];
        } completion:^(BOOL finished) {
            completion();
        }];
    }
    else {
        [self layoutForVisible:NO];

        completion();
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
