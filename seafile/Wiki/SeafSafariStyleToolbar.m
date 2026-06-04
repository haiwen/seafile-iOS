//
//  SeafSafariStyleToolbar.m
//  seafile
//
//  Safari-style floating toolbar for WebView pages.
//  Transliterated from STBSafariStyleToolbar.swift (SeaTable project).
//

#import "SeafSafariStyleToolbar.h"
#import "SeafTheme.h"

@interface SeafSafariStyleToolbar ()

// MARK: - UI Components

/// Back button container (left circular glass button)
@property (nonatomic, strong) UIVisualEffectView *backContainer;
/// Back button
@property (nonatomic, strong) UIButton *backButton;

/// Center title capsule container
@property (nonatomic, strong) UIVisualEffectView *titleContainer;
/// Title label
@property (nonatomic, strong) UILabel *titleLabel;
/// Refresh button (inside title capsule, right side)
@property (nonatomic, strong) UIButton *refreshButton;

/// More button container (right glass capsule)
@property (nonatomic, strong) UIVisualEffectView *moreContainer;
/// More button (...)
@property (nonatomic, strong) UIButton *moreButton;

/// Progress bar (Safari-style, inside title capsule at bottom edge)
@property (nonatomic, strong) UIView *progressBar;
/// Progress bar width constraint
@property (nonatomic, strong) NSLayoutConstraint *progressWidthConstraint;

/// Visibility state
@property (nonatomic, assign) BOOL isToolbarVisible;

@end

@implementation SeafSafariStyleToolbar

#pragma mark - Init

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _isToolbarVisible = NO;
        // Initially hidden to avoid flashing during push transition
        self.alpha = 0;
        self.transform = CGAffineTransformMakeTranslation(0, 20);
        [self setupUI];
        [self setupActions];
    }
    return self;
}

#pragma mark - Setup

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];

    // Create containers
    _backContainer = [self makeGlassContainerWithCornerRadius:22];
    _titleContainer = [self makeGlassContainerWithCornerRadius:22];
    _moreContainer = [self makeGlassContainerWithCornerRadius:22];

    [self addSubview:_backContainer];
    [self addSubview:_titleContainer];
    [self addSubview:_moreContainer];

    // Back button
    _backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _backButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *backConfig = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
    [_backButton setImage:[UIImage systemImageNamed:@"chevron.left" withConfiguration:backConfig] forState:UIControlStateNormal];
    _backButton.tintColor = [UIColor labelColor];
    [_backContainer.contentView addSubview:_backButton];

    // Title label
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [_titleContainer.contentView addSubview:_titleLabel];

    // Title tap gesture
    UITapGestureRecognizer *titleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTitleTapped)];
    _titleLabel.userInteractionEnabled = YES;
    [_titleLabel addGestureRecognizer:titleTap];

    // Refresh button (inside title capsule)
    _refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *refreshConfig = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightMedium];
    [_refreshButton setImage:[UIImage systemImageNamed:@"arrow.clockwise" withConfiguration:refreshConfig] forState:UIControlStateNormal];
    _refreshButton.tintColor = [UIColor secondaryLabelColor];
    [_titleContainer.contentView addSubview:_refreshButton];

    // Progress bar (inside title capsule, at bottom edge)
    _progressBar = [[UIView alloc] init];
    _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    _progressBar.backgroundColor = [SeafTheme accentOrange];
    _progressBar.alpha = 0;
    [_titleContainer.contentView addSubview:_progressBar];

    // More button
    _moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *moreConfig = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    [_moreButton setImage:[UIImage systemImageNamed:@"ellipsis" withConfiguration:moreConfig] forState:UIControlStateNormal];
    _moreButton.tintColor = [UIColor labelColor];
    [_moreContainer.contentView addSubview:_moreButton];

    // Progress bar constraints
    _progressWidthConstraint = [_progressBar.widthAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [_progressBar.leadingAnchor constraintEqualToAnchor:_titleContainer.contentView.leadingAnchor],
        [_progressBar.bottomAnchor constraintEqualToAnchor:_titleContainer.contentView.bottomAnchor],
        [_progressBar.heightAnchor constraintEqualToConstant:2.5],
        _progressWidthConstraint,
    ]];

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Back container (left) - circular back button
        [_backContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_backContainer.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_backContainer.heightAnchor constraintEqualToConstant:44],
        [_backContainer.widthAnchor constraintEqualToConstant:44],

        [_backButton.centerXAnchor constraintEqualToAnchor:_backContainer.contentView.centerXAnchor],
        [_backButton.centerYAnchor constraintEqualToAnchor:_backContainer.contentView.centerYAnchor],

        // Title container (center) - title capsule
        [_titleContainer.leadingAnchor constraintEqualToAnchor:_backContainer.trailingAnchor constant:8],
        [_titleContainer.trailingAnchor constraintEqualToAnchor:_moreContainer.leadingAnchor constant:-8],
        [_titleContainer.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_titleContainer.heightAnchor constraintEqualToConstant:44],

        // Title label (left padding, right space for refresh button)
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_titleContainer.contentView.leadingAnchor constant:14],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_refreshButton.leadingAnchor constant:-8],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_titleContainer.contentView.centerYAnchor],

        // Refresh button (right side of title capsule)
        [_refreshButton.trailingAnchor constraintEqualToAnchor:_titleContainer.contentView.trailingAnchor constant:-12],
        [_refreshButton.centerYAnchor constraintEqualToAnchor:_titleContainer.contentView.centerYAnchor],
        [_refreshButton.widthAnchor constraintEqualToConstant:24],
        [_refreshButton.heightAnchor constraintEqualToConstant:24],

        // More container (right) - more button
        [_moreContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_moreContainer.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_moreContainer.heightAnchor constraintEqualToConstant:44],
        [_moreContainer.widthAnchor constraintEqualToConstant:44],

        [_moreButton.centerXAnchor constraintEqualToAnchor:_moreContainer.contentView.centerXAnchor],
        [_moreButton.centerYAnchor constraintEqualToAnchor:_moreContainer.contentView.centerYAnchor],
    ]];
}

- (void)setupActions {
    [_backButton addTarget:self action:@selector(handleBackTapped) forControlEvents:UIControlEventTouchUpInside];
    [_refreshButton addTarget:self action:@selector(handleRefreshTapped) forControlEvents:UIControlEventTouchUpInside];
    [_moreButton addTarget:self action:@selector(handleMoreTapped) forControlEvents:UIControlEventTouchUpInside];
}

#pragma mark - Glass Container Factory

- (UIVisualEffectView *)makeGlassContainerWithCornerRadius:(CGFloat)radius {
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.layer.cornerRadius = radius;
    blur.layer.masksToBounds = YES;
    blur.layer.borderWidth = 0.5;
    blur.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.3].CGColor;
    return blur;
}

#pragma mark - Actions

- (void)handleBackTapped {
    [self generateHapticFeedbackWithStyle:UIImpactFeedbackStyleLight];
    [self animateButtonPress:_backButton];
    if (self.onBackTapped) self.onBackTapped();
}

- (void)handleRefreshTapped {
    [self generateHapticFeedbackWithStyle:UIImpactFeedbackStyleLight];
    [self animateRefreshButton];
    if (self.onRefreshTapped) self.onRefreshTapped();
}

- (void)handleMoreTapped {
    [self generateHapticFeedbackWithStyle:UIImpactFeedbackStyleLight];
    [self animateButtonPress:_moreButton];
    if (self.onMoreTapped) self.onMoreTapped();
}

- (void)handleTitleTapped {
    [self generateHapticFeedbackWithStyle:UIImpactFeedbackStyleLight];
    if (self.onTitleTapped) self.onTitleTapped();
}

#pragma mark - Public Methods

- (void)updateTitle:(NSString *)title {
    NSString *displayTitle = (title.length > 0) ? title : NSLocalizedString(@"Loading...", @"Seafile");
    if (self.window) {
        // Animate only when already on screen; cross-dissolve requires a rendered snapshot.
        [UIView transitionWithView:_titleLabel
                          duration:0.2
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{
            self.titleLabel.text = displayTitle;
        } completion:nil];
    } else {
        // During viewDidLoad the view is not in a window yet; set text directly
        // so it is visible as soon as the push transition begins.
        _titleLabel.text = displayTitle;
    }
}

- (void)updateProgress:(float)progress {
    float clamped = MAX(0, MIN(progress, 1.0f));

    // Calculate target width for progress bar
    CGFloat capsuleWidth = _titleContainer.bounds.size.width;
    CGFloat targetWidth = capsuleWidth * clamped;

    if (clamped < 1.0f) {
        // Show progress bar
        _progressBar.alpha = 1;
        _progressWidthConstraint.constant = targetWidth;
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            [self.titleContainer.contentView layoutIfNeeded];
        } completion:nil];
    } else {
        // Progress complete: fill, then fade out
        _progressWidthConstraint.constant = capsuleWidth;
        [UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            [self.titleContainer.contentView layoutIfNeeded];
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.3 delay:0.1 options:0 animations:^{
                self.progressBar.alpha = 0;
            } completion:^(BOOL finished2) {
                // Reset width for next load
                self.progressWidthConstraint.constant = 0;
                [self.titleContainer.contentView layoutIfNeeded];
            }];
        }];
    }
}

- (void)setProgressTintColor:(UIColor *)color {
    _progressBar.backgroundColor = color;
}

- (void)showAnimated:(BOOL)animated {
    if (_isToolbarVisible) return;
    _isToolbarVisible = YES;

    if (animated) {
        [UIView animateWithDuration:0.35
                              delay:0
             usingSpringWithDamping:0.8
              initialSpringVelocity:0.5
                            options:0
                         animations:^{
            self.alpha = 1;
            self.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        self.alpha = 1;
        self.transform = CGAffineTransformIdentity;
    }
}

- (void)hideAnimated:(BOOL)animated {
    if (!_isToolbarVisible) return;
    _isToolbarVisible = NO;

    if (animated) {
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            self.alpha = 0;
            self.transform = CGAffineTransformMakeTranslation(0, 20);
        } completion:nil];
    } else {
        self.alpha = 0;
        self.transform = CGAffineTransformMakeTranslation(0, 20);
    }
}

#pragma mark - Private Helpers

- (void)generateHapticFeedbackWithStyle:(UIImpactFeedbackStyle)style {
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:style];
    [generator impactOccurred];
}

- (void)animateButtonPress:(UIButton *)button {
    [UIView animateWithDuration:0.1 animations:^{
        button.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.1 animations:^{
            button.transform = CGAffineTransformIdentity;
        }];
    }];
}

/// Refresh button rotation animation
- (void)animateRefreshButton {
    [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.refreshButton.transform = CGAffineTransformMakeRotation(M_PI);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.refreshButton.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

#pragma mark - Trait Collection

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    // Update border colors for dark/light mode switch
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            CGColorRef borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.3].CGColor;
            _backContainer.layer.borderColor = borderColor;
            _titleContainer.layer.borderColor = borderColor;
            _moreContainer.layer.borderColor = borderColor;
        }
    }
}

@end
