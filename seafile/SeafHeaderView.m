//
//  SeafHeaderView.m
//  seafileApp
//
//  Created by henry on 2025/3/25.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import "SeafHeaderView.h"
#import "SeafTheme.h"

@implementation SeafHeaderView {
    NSInteger _section;
    UIButton *_toggleButton;
    UIImageView *_chevronView;
}

+ (CGFloat)headerHeight {
    return 45.0;
}

- (instancetype)initWithSection:(NSInteger)section
                          title:(NSString *)title
                      expanded:(BOOL)isExpanded {
    self = [super initWithReuseIdentifier:nil];
    if (self) {
        _section = section;
        UIBackgroundConfiguration *background = [UIBackgroundConfiguration clearConfiguration];
        background.backgroundColor = [SeafTheme primaryBackgroundColor];
        self.backgroundConfiguration = background;

        _toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _toggleButton.translatesAutoresizingMaskIntoConstraints = NO;
        _toggleButton.isAccessibilityElement = YES;
        _toggleButton.accessibilityLabel = title;
        _toggleButton.accessibilityTraits |= UIAccessibilityTraitHeader;
        [_toggleButton addTarget:self action:@selector(toggleButtonTapped:) forControlEvents:UIControlEventPrimaryActionTriggered];
        [self.contentView addSubview:_toggleButton];
        self.isAccessibilityElement = NO;
        self.accessibilityElements = @[_toggleButton];

        UILabel *titleLabel = [UILabel new];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.isAccessibilityElement = NO;
        titleLabel.userInteractionEnabled = NO;
        titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
        titleLabel.textColor = [SeafTheme secondaryText];
        titleLabel.text = title;
        [_toggleButton addSubview:titleLabel];

        _chevronView = [UIImageView new];
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        _chevronView.isAccessibilityElement = NO;
        _chevronView.tintColor = [SeafTheme secondaryText];
        _chevronView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:13.0
                                                                                                  weight:UIImageSymbolWeightRegular
                                                                                                   scale:UIImageSymbolScaleSmall];
        [_chevronView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_toggleButton addSubview:_chevronView];

        [NSLayoutConstraint activateConstraints:@[
            [_toggleButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_toggleButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_toggleButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_toggleButton.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:_toggleButton.leadingAnchor constant:24.0],
            [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_chevronView.leadingAnchor constant:-8.0],
            [titleLabel.centerYAnchor constraintEqualToAnchor:_toggleButton.centerYAnchor],
            [_chevronView.trailingAnchor constraintEqualToAnchor:_toggleButton.trailingAnchor constant:-17.0],
            [_chevronView.centerYAnchor constraintEqualToAnchor:_toggleButton.centerYAnchor]
        ]];
        [self setExpanded:isExpanded animated:NO];
    }
    return self;
}

- (void)toggleButtonTapped:(UIButton *)sender {
    if (self.toggleAction) {
        self.toggleAction(_section);
    }
}

- (void)setExpanded:(BOOL)isExpanded animated:(BOOL)animated {
    UIImage *chevron = [UIImage systemImageNamed:isExpanded ? @"chevron.up" : @"chevron.down"];
    _toggleButton.accessibilityValue = isExpanded
        ? NSLocalizedString(@"Expanded", @"Accessibility value of an expanded library section")
        : NSLocalizedString(@"Collapsed", @"Accessibility value of a collapsed library section");
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView transitionWithView:_chevronView duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            self->_chevronView.image = chevron;
        } completion:nil];
    } else {
        _chevronView.image = chevron;
    }
}

@end
