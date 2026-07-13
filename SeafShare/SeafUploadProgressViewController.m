//
//  SeafUploadProgressViewController.m
//  SeafShare
//
//  Custom alert-style overlay that shows upload progress.
//  Presented with UIModalPresentationOverCurrentContext so it floats
//  above the current content with a dimmed background.
//

#import "SeafUploadProgressViewController.h"
#import "SeafTheme.h"

static CGFloat const kAlertWidth       = 270.0;
static CGFloat const kCornerRadius     = 14.0;
static CGFloat const kButtonHeight     = 44.0;
static CGFloat const kHorizontalInset  = 20.0;

@interface SeafUploadProgressViewController ()

@property (nonatomic, strong, readwrite) UILabel *fileNameLabel;
@property (nonatomic, strong, readwrite) UIProgressView *progressView;
@property (nonatomic, strong, readwrite) UILabel *countLabel;

@property (nonatomic, copy)   NSString  *initialFileName;
@property (nonatomic, assign) NSInteger  totalCount;

@property (nonatomic, strong) UIView *dimmingView;
@property (nonatomic, strong) UIView *alertContainer;

@end

@implementation SeafUploadProgressViewController

#pragma mark - Init

- (instancetype)initWithFileName:(NSString *)fileName totalCount:(NSInteger)totalCount {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _initialFileName = [fileName copy];
        _totalCount      = totalCount;
        self.modalPresentationStyle = UIModalPresentationOverCurrentContext;
        self.modalTransitionStyle   = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

#pragma mark - View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    // ── Dimming background ──
    self.dimmingView = [[UIView alloc] init];
    self.dimmingView.translatesAutoresizingMaskIntoConstraints = NO;
    self.dimmingView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
    [self.view addSubview:self.dimmingView];

    [NSLayoutConstraint activateConstraints:@[
        [self.dimmingView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.dimmingView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.dimmingView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.dimmingView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // ── Alert container (mimics system alert card) ──
    self.alertContainer = [[UIView alloc] init];
    self.alertContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.alertContainer.layer.cornerRadius = kCornerRadius;
    self.alertContainer.clipsToBounds = YES;

    // Use system grouped background so it looks correct in both light & dark mode
    if (@available(iOS 13.0, *)) {
        self.alertContainer.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    } else {
        self.alertContainer.backgroundColor = [UIColor whiteColor];
    }
    [self.view addSubview:self.alertContainer];

    [NSLayoutConstraint activateConstraints:@[
        [self.alertContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.alertContainer.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.alertContainer.widthAnchor constraintEqualToConstant:kAlertWidth],
    ]];

    // ── Title ──
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = NSLocalizedString(@"Uploading", @"Seafile");
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    if (@available(iOS 13.0, *)) {
        titleLabel.textColor = [UIColor labelColor];
    }
    [self.alertContainer addSubview:titleLabel];

    // ── File name ──
    self.fileNameLabel = [[UILabel alloc] init];
    self.fileNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.fileNameLabel.text = self.initialFileName ?: @"";
    self.fileNameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    self.fileNameLabel.textColor = [SeafTheme secondaryText];
    self.fileNameLabel.textAlignment = NSTextAlignmentCenter;
    self.fileNameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.fileNameLabel.numberOfLines = 1;
    [self.alertContainer addSubview:self.fileNameLabel];

    // ── Progress bar ──
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressView.progress = 0.f;
    self.progressView.progressTintColor = [SeafTheme accentOrange];
    self.progressView.trackTintColor = [SeafTheme fill];
    self.progressView.layer.cornerRadius = 2.0;
    self.progressView.clipsToBounds = YES;
    [self.alertContainer addSubview:self.progressView];

    // ── Count label ──
    BOOL showCount = (self.totalCount > 1);
    self.countLabel = [[UILabel alloc] init];
    self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.countLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    self.countLabel.textColor = [SeafTheme secondaryText];
    self.countLabel.textAlignment = NSTextAlignmentCenter;
    self.countLabel.hidden = !showCount;
    if (showCount) {
        self.countLabel.text = [NSString stringWithFormat:@"1 / %ld", (long)self.totalCount];
    }
    [self.alertContainer addSubview:self.countLabel];

    // ── Separator ──
    UIView *separator = [[UIView alloc] init];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(iOS 13.0, *)) {
        separator.backgroundColor = [UIColor separatorColor];
    } else {
        separator.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    }
    [self.alertContainer addSubview:separator];

    // ── Cancel button ──
    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelButton setTitle:NSLocalizedString(@"Cancel", @"Seafile") forState:UIControlStateNormal];
    cancelButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
    [cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.alertContainer addSubview:cancelButton];

    // ── Layout ──
    CGFloat countBottom = showCount ? 12.0 : 0.0;

    [NSLayoutConstraint activateConstraints:@[
        // Title
        [titleLabel.topAnchor constraintEqualToAnchor:self.alertContainer.topAnchor constant:20],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.alertContainer.leadingAnchor constant:kHorizontalInset],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.alertContainer.trailingAnchor constant:-kHorizontalInset],

        // File name
        [self.fileNameLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
        [self.fileNameLabel.leadingAnchor constraintEqualToAnchor:self.alertContainer.leadingAnchor constant:kHorizontalInset],
        [self.fileNameLabel.trailingAnchor constraintEqualToAnchor:self.alertContainer.trailingAnchor constant:-kHorizontalInset],

        // Progress bar
        [self.progressView.topAnchor constraintEqualToAnchor:self.fileNameLabel.bottomAnchor constant:16],
        [self.progressView.leadingAnchor constraintEqualToAnchor:self.alertContainer.leadingAnchor constant:kHorizontalInset],
        [self.progressView.trailingAnchor constraintEqualToAnchor:self.alertContainer.trailingAnchor constant:-kHorizontalInset],
        [self.progressView.heightAnchor constraintEqualToConstant:4],

        // Count label
        [self.countLabel.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor constant:countBottom],
        [self.countLabel.leadingAnchor constraintEqualToAnchor:self.alertContainer.leadingAnchor constant:kHorizontalInset],
        [self.countLabel.trailingAnchor constraintEqualToAnchor:self.alertContainer.trailingAnchor constant:-kHorizontalInset],

        // Separator
        [separator.topAnchor constraintEqualToAnchor:self.countLabel.bottomAnchor constant:16],
        [separator.leadingAnchor constraintEqualToAnchor:self.alertContainer.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:self.alertContainer.trailingAnchor],
        [separator.heightAnchor constraintEqualToConstant:1.0 / [UIScreen mainScreen].scale],

        // Cancel button
        [cancelButton.topAnchor constraintEqualToAnchor:separator.bottomAnchor],
        [cancelButton.leadingAnchor constraintEqualToAnchor:self.alertContainer.leadingAnchor],
        [cancelButton.trailingAnchor constraintEqualToAnchor:self.alertContainer.trailingAnchor],
        [cancelButton.heightAnchor constraintEqualToConstant:kButtonHeight],
        [cancelButton.bottomAnchor constraintEqualToAnchor:self.alertContainer.bottomAnchor],
    ]];

    self.view.backgroundColor = [UIColor clearColor];
}

#pragma mark - Actions

- (void)cancelTapped {
    if (self.onCancel) {
        self.onCancel();
    }
}

@end
