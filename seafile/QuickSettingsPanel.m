//
//  SettingsBlock.m
//  SettingsAnimation
//
//  Created by Max on 30/09/2017.
//  Copyright © 2017 34x. All rights reserved.
//

#import "QuickSettingsPanel.h"

NSString* const QuickSettingsFontSizeIncrement = @"QuickSettingsFontSizeIncrement";
NSString* const QuickSettingsFontSizeDecrement = @"QuickSettingsFontSizeDecrement";;

@interface QuickSettingsPanel()
@property (nonatomic) UIView* settingsBlock;
@property (nonatomic) UIButton* settingsToggle;
@property (nonatomic) CGSize elementSize;
@property (nonatomic) CGSize panelSize;
@property (nonatomic) UIButton* fontSizeIncrementButton;
@property (nonatomic) UIButton* fontSizeDecrementButton;
@property (nonatomic, readonly) BOOL isOpen;
@end

@implementation QuickSettingsPanel

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self configureView];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self configureView];
    }
    return self;
}

- (void)layoutSubviews {
    // Moving settings overlay to the right bottom corner
    CGSize parentSize = self.superview.bounds.size;
    CGFloat margin = self.elementSize.width * 0.25;
    self.frame = CGRectMake(parentSize.width - self.panelSize.width - margin,
                            parentSize.height - self.panelSize.height - margin,
                            self.panelSize.width, self.panelSize.height);
    
    self.settingsBlock.center = CGPointMake(self.bounds.size.width, self.bounds.size.height);
}

- (void)orientationChanged:(NSNotification*)notification {
    [self layoutSubviews];
}

- (void)configureView {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged:) name:UIDeviceOrientationDidChangeNotification object:nil];
    
    self.elementSize = CGSizeMake(52.0, 52.0);
    self.panelSize = CGSizeMake(self.elementSize.width * 3, self.elementSize.height);

    UIView* settingsBlock = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.panelSize.width, self.panelSize.height)];
    settingsBlock.layer.anchorPoint = CGPointMake(1.0, 1.0);
    
    
    settingsBlock.backgroundColor = [[UIColor orangeColor] colorWithAlphaComponent:0.9];
    settingsBlock.layer.cornerRadius = self.elementSize.height / 8.0;
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle:)];
    [settingsBlock addGestureRecognizer:tap];
    
    self.settingsBlock = settingsBlock;
    
    CGFloat x = settingsBlock.bounds.size.width;
    
    UIButton *settings = [[UIButton alloc] initWithFrame:CGRectMake(0.0, 0, self.elementSize.width, self.elementSize.height)];
    [settings setTitle:@"→" forState:UIControlStateNormal];
    settings.titleLabel.font = [UIFont systemFontOfSize: self.elementSize.height * 0.8];
    [settings addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
    settings.alpha = 0.8;
    self.settingsToggle = settings;
    [self.settingsBlock addSubview:settings];
    
    UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(self.elementSize.width, 0, 2.0, self.elementSize.height)];
    separator.backgroundColor = [[UIColor whiteColor]colorWithAlphaComponent:0.4];
    [self.settingsBlock addSubview:separator];
    
    x = x - self.elementSize.width;
    
    self.fontSizeIncrementButton = [[UIButton alloc] initWithFrame:CGRectMake(x, 0, self.elementSize.width, self.elementSize.height)];
    
    [self.fontSizeIncrementButton setTitle:@"A" forState:UIControlStateNormal];
    self.fontSizeIncrementButton.titleLabel.font = [UIFont systemFontOfSize: self.elementSize.height * 0.8];
    [self.fontSizeIncrementButton addTarget:self action:@selector(settingsDidChange:) forControlEvents:UIControlEventTouchUpInside];
    [self.settingsBlock addSubview:self.fontSizeIncrementButton];
    
    x = x - self.elementSize.width;
    
    self.fontSizeDecrementButton = [[UIButton alloc] initWithFrame:CGRectMake(x, 0, self.elementSize.width, self.elementSize.height)];
    [self.fontSizeDecrementButton setTitle:@"A" forState:UIControlStateNormal];
    self.fontSizeDecrementButton.titleLabel.font = [UIFont systemFontOfSize:self.elementSize.height / 2.0];
    [self.fontSizeDecrementButton addTarget:self action:@selector(settingsDidChange:) forControlEvents:UIControlEventTouchUpInside];
    [self.settingsBlock addSubview:self.fontSizeDecrementButton];
    
    [self addSubview:settingsBlock];
    
    [self toggleAnimate:NO];
}

- (void)settingsDidChange:(id)element {
    NSString* key;
    
    if (element == self.fontSizeIncrementButton) {
        key = QuickSettingsFontSizeIncrement;
    } else if (element == self.fontSizeDecrementButton) {
        key = QuickSettingsFontSizeDecrement;
    }
    
    if (key && self.actionHandler) {
        self.actionHandler(key, nil);
    }
}

- (void)toggle:(id)button {
    [self toggleAnimate:YES];
}

- (void)toggleAnimate:(BOOL)animate {
    CGFloat targetWidth = 0;
    CGFloat rotateFrom = 0.0;
    CGFloat rotateTo = 0.0;
    CGFloat scaleFrom = 1.0;
    CGFloat scaleTo = 0.0;
    CGFloat alphaFrom = 0.0;
    CGFloat alphaTo = 0.0;
    
    // going to close
    if (self.isOpen) {
        targetWidth = self.elementSize.width;
        rotateFrom = 0;
        rotateTo = M_PI;
        scaleTo = 0.5;
        alphaFrom = 1.0;
        alphaTo = 0.4;
    // going to open
    } else {
        targetWidth = self.panelSize.width;
        rotateFrom = M_PI;
        rotateTo = 0;
        scaleTo = 1.0;
        scaleFrom = 0.5;
        alphaFrom = 0.4;
        alphaTo = 1.0;
    }
    
    CGRect bounds = self.settingsBlock.bounds;
    NSTimeInterval commonDuration = 0.4;
    
    CABasicAnimation* toggleRotate = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    toggleRotate.fromValue = @(rotateFrom);
    toggleRotate.toValue = @(rotateTo);
    toggleRotate.fillMode = kCAFillModeBackwards;
    toggleRotate.duration = commonDuration;
    CGAffineTransform zero = CGAffineTransformMakeRotation(0);
    
    self.settingsToggle.transform = CGAffineTransformRotate(zero, rotateTo);
    
    CABasicAnimation* commonWidth = [CABasicAnimation animationWithKeyPath:@"bounds.size.width"];
    commonWidth.fromValue = @(bounds.size.width);
    commonWidth.toValue = @(targetWidth);
    commonWidth.duration = commonDuration;
    
    CABasicAnimation* commonScale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    commonScale.fromValue = @(scaleFrom);
    commonScale.toValue = @(scaleTo);
    commonScale.duration = commonDuration;
    commonScale.fillMode = kCAFillModeBackwards;
    
    CABasicAnimation* commonAlpha = [CABasicAnimation animationWithKeyPath:@"opacity"];
    commonAlpha.fromValue = @(alphaFrom);
    commonAlpha.toValue = @(alphaTo);
    commonAlpha.duration = commonDuration;
    
    if (animate) {
        [self.settingsToggle.layer addAnimation:toggleRotate forKey:nil];
        [self.settingsBlock.layer addAnimation:commonWidth forKey:nil];
        [self.settingsBlock.layer addAnimation:commonScale forKey:nil];
        [self.settingsBlock.layer addAnimation:commonAlpha forKey:nil];
    }
    
    self.settingsBlock.bounds = CGRectMake(0, 0, targetWidth, bounds.size.height);
    CGAffineTransform zeroScale = CGAffineTransformMakeScale(1.0, 1.0);
    self.settingsBlock.transform = CGAffineTransformScale(zeroScale, scaleTo, scaleTo);
    self.settingsBlock.alpha = alphaTo;
}

- (BOOL)isOpen {
    return self.settingsBlock.bounds.size.width > self.elementSize.width;
}

- (void)setOpen:(BOOL)isOpen animate:(BOOL)animate {
    // if it's already the same do nothing
    if (self.isOpen == isOpen) {
        return;
    }
    
    [self toggleAnimate:animate];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end
