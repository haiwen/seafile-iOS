//
//  SeafHeaderView.m
//  seafileApp
//
//  Created by henry on 2025/3/25.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import "SeafHeaderView.h"

#define kHeaderHeight 45.0
#define kLeftPadding 24.0
#define kRightPadding 17.0
#define kToggleButtonWidth 13.0

@implementation SeafHeaderView {
    UILabel *_titleLabel;
    UIButton *_toggleButton;
}

- (instancetype)initWithSection:(NSInteger)section
                          title:(NSString *)title
                      expanded:(BOOL)isExpanded {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.section = section;
        self.backgroundColor = kPrimaryBackgroundColor;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        
        // Create title label
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        _titleLabel.text = title;
        _titleLabel.textColor = [UIColor blackColor];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self addSubview:_titleLabel];
        
        // Create right toggle button
        _toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _toggleButton.frame = CGRectZero;
        UIImage *arrowImage = [UIImage imageNamed:@"arrowDown_black"];
        [_toggleButton setImage:arrowImage forState:UIControlStateNormal];
        _toggleButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        _toggleButton.layer.anchorPoint = CGPointMake(0.5, 0.5);
        _toggleButton.tag = section;
        [_toggleButton addTarget:self action:@selector(toggleButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_toggleButton];
        
        // Add tap gesture recognizer to the entire header
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(headerTapped)];
        [self addGestureRecognizer:tapGesture];
        self.tag = section;
        
        // Set expanded state (used to set initial rotation)
        [self setExpanded:isExpanded animated:NO];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // Fix header height
    self.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y, self.superview.bounds.size.width, kHeaderHeight);
    
    // Layout title label
    _titleLabel.frame = CGRectMake(kLeftPadding, 12, self.bounds.size.width - kLeftPadding - kRightPadding, 22);
    
    // Layout toggle button
    _toggleButton.frame = CGRectMake(self.bounds.size.width - kRightPadding - kToggleButtonWidth, 16, kToggleButtonWidth, kToggleButtonWidth);
    _toggleButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
}

#pragma mark - Actions

- (void)toggleButtonTapped:(UIButton *)sender {
    if (self.toggleAction) {
        self.toggleAction(self.section);
    }
}

- (void)headerTapped {
    if (self.tapAction) {
        self.tapAction(self.section);
    }
}

#pragma mark - Public Methods

- (void)setExpanded:(BOOL)isExpanded animated:(BOOL)animated {
    CGFloat targetRotation = isExpanded ? -M_PI : 0;
    if (animated) {
        [UIView animateWithDuration:0.25 animations:^{
            _toggleButton.transform = CGAffineTransformMakeRotation(targetRotation);
        }];
    } else {
        _toggleButton.transform = CGAffineTransformMakeRotation(targetRotation);
    }
}

@end
