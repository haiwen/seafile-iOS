//
//  SeafGridCell.m
//  seafile
//

#import "SeafGridCell.h"
#import "SeafFile.h"
#import "SeafDir.h"
#import "SeafUploadFile.h"
#import "SeafUploadFileModel.h"
#import "SeafTheme.h"
#import "UIImage+FileType.h"

static const CGFloat kThumbnailCornerRadius = 10.0;
static const CGFloat kTitleTopSpacing = 8.0;
static const CGFloat kStatusContainerSize = 22.0;
static const CGFloat kStatusIconSize = 18.0;
static const CGFloat kCheckboxVisualSize = 22.0;
static const CGFloat kCheckboxHitSize = 44.0;
static const CGFloat kIconDisplaySize = 40.0;
static const NSInteger kTitleMaxLines = 2;

@interface SeafGridCell ()
@property (nonatomic, strong, readwrite) UIImageView *thumbnailView;
@property (nonatomic, strong) UIView *thumbnailContainer;
@property (nonatomic, strong) UIView *highlightOverlay;
@property (nonatomic, strong) UIView *selectionOverlay;
@property (nonatomic, strong) UIView *checkboxHitArea;
@property (nonatomic, strong) UIImageView *checkboxImageView;
@property (nonatomic, strong) UIView *cacheStatusView;
@property (nonatomic, strong) UIImageView *downloadStatusImageView;
@property (nonatomic, strong) UIActivityIndicatorView *downloadingIndicator;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) NSLayoutConstraint *thumbnailEdgeTop;
@property (nonatomic, strong) NSLayoutConstraint *thumbnailEdgeLeading;
@property (nonatomic, strong) NSLayoutConstraint *thumbnailEdgeTrailing;
@property (nonatomic, strong) NSLayoutConstraint *thumbnailEdgeBottom;
@property (nonatomic, strong) NSLayoutConstraint *thumbnailImageWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *thumbnailImageHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *cacheStatusWidthConstraint;
@property (nonatomic, copy, nullable) NSString *accessibilityStatusText;
@end

@implementation SeafGridCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self buildViews];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

- (void)buildViews {
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.contentView.clipsToBounds = NO;
    self.clipsToBounds = NO;

    _thumbnailContainer = [[UIView alloc] init];
    _thumbnailContainer.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(iOS 13.0, *)) {
        _thumbnailContainer.backgroundColor = [UIColor tertiarySystemFillColor];
    } else {
        _thumbnailContainer.backgroundColor = [SeafTheme fill];
    }
    _thumbnailContainer.layer.cornerRadius = kThumbnailCornerRadius;
    _thumbnailContainer.clipsToBounds = YES;
    if (@available(iOS 13.0, *)) {
        _thumbnailContainer.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [self.contentView addSubview:_thumbnailContainer];

    _thumbnailView = [[UIImageView alloc] init];
    _thumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
    _thumbnailView.contentMode = UIViewContentModeScaleAspectFit;
    _thumbnailView.clipsToBounds = YES;
    [_thumbnailContainer addSubview:_thumbnailView];

    _highlightOverlay = [[UIView alloc] init];
    _highlightOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    _highlightOverlay.backgroundColor = [SeafColor_Label colorWithAlphaComponent:0.12];
    _highlightOverlay.hidden = YES;
    _highlightOverlay.userInteractionEnabled = NO;
    [_thumbnailContainer addSubview:_highlightOverlay];

    _selectionOverlay = [[UIView alloc] init];
    _selectionOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    _selectionOverlay.backgroundColor = [[SeafTheme accentOrange] colorWithAlphaComponent:0.12];
    _selectionOverlay.hidden = YES;
    _selectionOverlay.userInteractionEnabled = NO;
    [_thumbnailContainer addSubview:_selectionOverlay];

    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    _progressView.translatesAutoresizingMaskIntoConstraints = NO;
    _progressView.hidden = YES;
    if (@available(iOS 13.0, *)) {
        _progressView.trackTintColor = [SeafColor_Label colorWithAlphaComponent:0.12];
        _progressView.progressTintColor = [SeafTheme accentOrange];
    }
    [_thumbnailContainer addSubview:_progressView];

    // Same cache checkmark presentation as SeafCell (list): original asset, 15pt in 21pt slot.
    _cacheStatusView = [[UIView alloc] init];
    _cacheStatusView.translatesAutoresizingMaskIntoConstraints = NO;
    _cacheStatusView.hidden = YES;
    _cacheStatusView.backgroundColor = UIColor.clearColor;
    [self.contentView addSubview:_cacheStatusView];

    _downloadStatusImageView = [[UIImageView alloc] init];
    _downloadStatusImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _downloadStatusImageView.hidden = YES;
    _downloadStatusImageView.contentMode = UIViewContentModeScaleAspectFit;
    [_cacheStatusView addSubview:_downloadStatusImageView];

    if (@available(iOS 13.0, *)) {
        _downloadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    } else {
        _downloadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    }
    _downloadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _downloadingIndicator.hidesWhenStopped = YES;
    [_cacheStatusView addSubview:_downloadingIndicator];

    _checkboxHitArea = [[UIView alloc] init];
    _checkboxHitArea.translatesAutoresizingMaskIntoConstraints = NO;
    _checkboxHitArea.hidden = YES;
    _checkboxHitArea.userInteractionEnabled = NO;
    [_thumbnailContainer addSubview:_checkboxHitArea];

    // Light frosted disc only for contrast on busy thumbnails (not a heavy dark plate).
    UIView *checkboxPlate = [[UIView alloc] init];
    checkboxPlate.translatesAutoresizingMaskIntoConstraints = NO;
    checkboxPlate.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45];
    checkboxPlate.layer.cornerRadius = (kCheckboxVisualSize + 4.0) / 2.0;
    [_checkboxHitArea addSubview:checkboxPlate];

    _checkboxImageView = [[UIImageView alloc] init];
    _checkboxImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _checkboxImageView.contentMode = UIViewContentModeScaleAspectFit;
    [_checkboxHitArea addSubview:_checkboxImageView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [[self class] titleFont];
    _titleLabel.textColor = [SeafTheme primaryText];
    _titleLabel.numberOfLines = kTitleMaxLines;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _titleLabel.adjustsFontForContentSizeCategory = YES;
    [self.contentView addSubview:_titleLabel];

    // Keep a true 1:1 preview from the first layout pass (avoid the
    // "rectangle then square" flash from updating height in layoutSubviews).
    NSLayoutConstraint *thumbnailAspect = [_thumbnailContainer.heightAnchor constraintEqualToAnchor:_thumbnailContainer.widthAnchor
                                                                                          multiplier:1.0 / [[self class] thumbnailAspectRatio]];
    _thumbnailEdgeTop = [_thumbnailView.topAnchor constraintEqualToAnchor:_thumbnailContainer.topAnchor];
    _thumbnailEdgeLeading = [_thumbnailView.leadingAnchor constraintEqualToAnchor:_thumbnailContainer.leadingAnchor];
    _thumbnailEdgeTrailing = [_thumbnailView.trailingAnchor constraintEqualToAnchor:_thumbnailContainer.trailingAnchor];
    _thumbnailEdgeBottom = [_thumbnailView.bottomAnchor constraintEqualToAnchor:_thumbnailContainer.bottomAnchor];
    _thumbnailImageWidthConstraint = [_thumbnailView.widthAnchor constraintEqualToConstant:kIconDisplaySize];
    _thumbnailImageHeightConstraint = [_thumbnailView.heightAnchor constraintEqualToConstant:kIconDisplaySize];

    [NSLayoutConstraint activateConstraints:@[
        [_thumbnailContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [_thumbnailContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [_thumbnailContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        thumbnailAspect,

        _thumbnailEdgeTop,
        _thumbnailEdgeLeading,
        _thumbnailEdgeTrailing,
        _thumbnailEdgeBottom,
        [_thumbnailView.centerXAnchor constraintEqualToAnchor:_thumbnailContainer.centerXAnchor],
        [_thumbnailView.centerYAnchor constraintEqualToAnchor:_thumbnailContainer.centerYAnchor],

        [_highlightOverlay.topAnchor constraintEqualToAnchor:_thumbnailContainer.topAnchor],
        [_highlightOverlay.leadingAnchor constraintEqualToAnchor:_thumbnailContainer.leadingAnchor],
        [_highlightOverlay.trailingAnchor constraintEqualToAnchor:_thumbnailContainer.trailingAnchor],
        [_highlightOverlay.bottomAnchor constraintEqualToAnchor:_thumbnailContainer.bottomAnchor],

        [_selectionOverlay.topAnchor constraintEqualToAnchor:_thumbnailContainer.topAnchor],
        [_selectionOverlay.leadingAnchor constraintEqualToAnchor:_thumbnailContainer.leadingAnchor],
        [_selectionOverlay.trailingAnchor constraintEqualToAnchor:_thumbnailContainer.trailingAnchor],
        [_selectionOverlay.bottomAnchor constraintEqualToAnchor:_thumbnailContainer.bottomAnchor],

        [_progressView.leadingAnchor constraintEqualToAnchor:_thumbnailContainer.leadingAnchor],
        [_progressView.trailingAnchor constraintEqualToAnchor:_thumbnailContainer.trailingAnchor],
        [_progressView.bottomAnchor constraintEqualToAnchor:_thumbnailContainer.bottomAnchor],
        [_progressView.heightAnchor constraintEqualToConstant:3.0],

        [_checkboxHitArea.topAnchor constraintEqualToAnchor:_thumbnailContainer.topAnchor],
        [_checkboxHitArea.leadingAnchor constraintEqualToAnchor:_thumbnailContainer.leadingAnchor],
        [_checkboxHitArea.widthAnchor constraintEqualToConstant:kCheckboxHitSize],
        [_checkboxHitArea.heightAnchor constraintEqualToConstant:kCheckboxHitSize],

        [checkboxPlate.centerXAnchor constraintEqualToAnchor:_checkboxHitArea.centerXAnchor constant:-6.0],
        [checkboxPlate.centerYAnchor constraintEqualToAnchor:_checkboxHitArea.centerYAnchor constant:-6.0],
        [checkboxPlate.widthAnchor constraintEqualToConstant:kCheckboxVisualSize + 4.0],
        [checkboxPlate.heightAnchor constraintEqualToConstant:kCheckboxVisualSize + 4.0],

        [_checkboxImageView.centerXAnchor constraintEqualToAnchor:checkboxPlate.centerXAnchor],
        [_checkboxImageView.centerYAnchor constraintEqualToAnchor:checkboxPlate.centerYAnchor],
        [_checkboxImageView.widthAnchor constraintEqualToConstant:kCheckboxVisualSize],
        [_checkboxImageView.heightAnchor constraintEqualToConstant:kCheckboxVisualSize],

        [_cacheStatusView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:2.0],
        [_cacheStatusView.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [_cacheStatusView.heightAnchor constraintEqualToConstant:kStatusContainerSize],

        [_downloadStatusImageView.centerXAnchor constraintEqualToAnchor:_cacheStatusView.centerXAnchor],
        [_downloadStatusImageView.centerYAnchor constraintEqualToAnchor:_cacheStatusView.centerYAnchor],
        [_downloadStatusImageView.widthAnchor constraintEqualToConstant:kStatusIconSize],
        [_downloadStatusImageView.heightAnchor constraintEqualToConstant:kStatusIconSize],

        [_downloadingIndicator.centerXAnchor constraintEqualToAnchor:_cacheStatusView.centerXAnchor],
        [_downloadingIndicator.centerYAnchor constraintEqualToAnchor:_cacheStatusView.centerYAnchor],

        [_titleLabel.topAnchor constraintEqualToAnchor:_thumbnailContainer.bottomAnchor constant:kTitleTopSpacing],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-2.0],
        [_titleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor],
    ]];

    _cacheStatusWidthConstraint = [_cacheStatusView.widthAnchor constraintEqualToConstant:0.0];
    _cacheStatusWidthConstraint.active = YES;
    _titleLeadingConstraint = [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:2.0];
    _titleLeadingConstraint.active = YES;

    _thumbnailImageWidthConstraint.active = NO;
    _thumbnailImageHeightConstraint.active = NO;
}

#pragma mark - Metrics

+ (UIFont *)titleFont {
    UIFont *base = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    if (@available(iOS 11.0, *)) {
        return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote] scaledFontForFont:base];
    }
    return [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
}

+ (CGFloat)thumbnailAspectRatio {
    return 1.0;
}

+ (CGFloat)titleAreaHeight {
    UIFont *font = [self titleFont];
    CGFloat lineHeight = ceil(font.lineHeight);
    return kTitleTopSpacing + lineHeight * kTitleMaxLines + 2.0;
}

+ (CGFloat)preferredItemHeightForWidth:(CGFloat)width {
    CGFloat thumbHeight = width / [self thumbnailAspectRatio];
    return ceil(thumbHeight + [self titleAreaHeight]);
}

#pragma mark - Highlight / Selection

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    BOOL show = highlighted && !self.isUserEditing;
    if (show) {
        self.highlightOverlay.alpha = 0;
        self.highlightOverlay.hidden = NO;
        [UIView animateWithDuration:0.12 animations:^{
            self.highlightOverlay.alpha = 1.0;
            self.thumbnailContainer.transform = CGAffineTransformMakeScale(0.98, 0.98);
        }];
    } else {
        [UIView animateWithDuration:0.18 animations:^{
            self.highlightOverlay.alpha = 0;
            self.thumbnailContainer.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            if (!self.isHighlighted) {
                self.highlightOverlay.hidden = YES;
            }
        }];
    }
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    if (self.isUserEditing) {
        [self updateCheckboxForSelected:selected];
    }
    [self refreshAccessibilityTraits];
}

- (void)setIsUserEditing:(BOOL)isUserEditing {
    _isUserEditing = isUserEditing;
    self.checkboxHitArea.hidden = !isUserEditing;
    if (isUserEditing) {
        [self updateCheckboxForSelected:self.isSelected];
    } else {
        self.checkboxImageView.image = nil;
        self.checkboxImageView.tintColor = nil;
        self.selectionOverlay.hidden = YES;
        self.thumbnailContainer.layer.borderWidth = 0.0;
    }
    [self refreshAccessibilityTraits];
}

- (void)updateCheckboxForSelected:(BOOL)selected {
    // Keep the same asset + light/dark rules as SeafCell (list mode).
    NSString *imageName = selected ? @"ic_checkbox_checked" : @"ic_checkbox_unchecked";
    UIImage *image = [UIImage imageNamed:imageName];
    if (@available(iOS 13.0, *)) {
        if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            self.checkboxImageView.tintColor = selected
                ? [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.7]
                : [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.2];
        } else {
            image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            self.checkboxImageView.tintColor = nil;
        }
    }
    self.checkboxImageView.image = image;
    // Soft brand-colored veil instead of a systemBlue border.
    self.selectionOverlay.hidden = !(self.isUserEditing && selected);
    self.thumbnailContainer.layer.borderWidth = 0.0;
    [self refreshAccessibilityTraits];
}

#pragma mark - Layout helpers

- (void)layoutSubviews {
    [super layoutSubviews];
    self.titleLabel.font = [[self class] titleFont];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]
            && self.isUserEditing) {
            [self updateCheckboxForSelected:self.isSelected];
        }
    }
    if (previousTraitCollection
        && self.traitCollection.preferredContentSizeCategory != previousTraitCollection.preferredContentSizeCategory) {
        self.titleLabel.font = [[self class] titleFont];
        [self setNeedsLayout];
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self resetCellFile];
    self.titleLabel.text = nil;
    self.thumbnailView.image = nil;
    self.thumbnailView.contentMode = UIViewContentModeScaleAspectFit;
    [self applyIconLayoutMode:NO];
    [self setStatusVisible:NO downloading:NO];
    self.progressView.hidden = YES;
    [self.progressView setProgress:0 animated:NO];
    self.checkboxHitArea.hidden = YES;
    self.isUserEditing = NO;
    self.cellIndexPath = nil;
    self.accessibilityStatusText = nil;
    self.highlightOverlay.hidden = YES;
    self.highlightOverlay.alpha = 0;
    self.selectionOverlay.hidden = YES;
    self.thumbnailContainer.transform = CGAffineTransformIdentity;
    self.thumbnailContainer.layer.borderWidth = 0.0;
    self.accessibilityLabel = nil;
    self.accessibilityValue = nil;
}

#pragma mark - Thumbnail presentation

- (void)applyIconLayoutMode:(BOOL)iconMode {
    self.thumbnailEdgeTop.active = !iconMode;
    self.thumbnailEdgeLeading.active = !iconMode;
    self.thumbnailEdgeTrailing.active = !iconMode;
    self.thumbnailEdgeBottom.active = !iconMode;
    self.thumbnailImageWidthConstraint.active = iconMode;
    self.thumbnailImageHeightConstraint.active = iconMode;

    if (iconMode) {
        self.thumbnailImageWidthConstraint.constant = kIconDisplaySize;
        self.thumbnailImageHeightConstraint.constant = kIconDisplaySize;
        self.thumbnailView.contentMode = UIViewContentModeScaleAspectFit;
    }
}

- (void)applyThumbnailContentModeForMedia:(BOOL)isMedia {
    [self applyIconLayoutMode:!isMedia];
    if (isMedia) {
        self.thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
    } else {
        self.thumbnailView.contentMode = UIViewContentModeScaleAspectFit;
    }
}

#pragma mark - Status

- (void)setCacheStatusImageNamed:(NSString *)imageName {
    // List mode (SeafCell) uses the asset as-is so the orange checkmark colors show through.
    self.downloadStatusImageView.image = imageName.length ? [UIImage imageNamed:imageName] : nil;
}

- (void)setStatusVisible:(BOOL)visible downloading:(BOOL)downloading {
    self.cacheStatusView.hidden = !visible;
    self.cacheStatusWidthConstraint.constant = visible ? kStatusContainerSize : 0.0;
    // Keep title left-aligned with list: icon then 4pt gap, or flush when hidden.
    self.titleLeadingConstraint.constant = visible ? (2.0 + kStatusContainerSize + 4.0) : 2.0;
    if (!visible) {
        self.downloadStatusImageView.hidden = YES;
        self.downloadStatusImageView.image = nil;
        [self.downloadingIndicator stopAnimating];
        return;
    }
    if (downloading) {
        self.downloadStatusImageView.hidden = YES;
        [self.downloadingIndicator startAnimating];
    } else {
        [self.downloadingIndicator stopAnimating];
        self.downloadStatusImageView.hidden = NO;
    }
}

#pragma mark - Configure

- (void)resetCellFile {
    if (self.cellSeafFile) {
        [self.cellSeafFile cancelNotDisplayThumb];
        self.cellSeafFile = nil;
    }
}

- (void)configureWithDir:(SeafDir *)dir {
    [self resetCellFile];
    self.titleLabel.text = dir.name;
    self.thumbnailView.image = dir.icon;
    [self applyThumbnailContentModeForMedia:NO];
    [self setStatusVisible:NO downloading:NO];
    self.progressView.hidden = YES;
    self.accessibilityStatusText = NSLocalizedString(@"Folder", @"Seafile");
    [self refreshAccessibility];
}

- (void)configureWithFile:(SeafFile *)file {
    [self resetCellFile];
    self.cellSeafFile = file;
    self.titleLabel.text = file.name;
    // file.icon also enqueues thumbnail download for image/video when missing.
    UIImage *icon = file.icon;
    self.thumbnailView.image = icon;
    // Only use full-bleed media layout once a real thumbnail is available;
    // otherwise keep the centered type icon (avoids stretching placeholders).
    BOOL isMediaType = file.isImageFile || file.isVideoFile;
    BOOL hasRealThumb = isMediaType && (file.thumb != nil);
    [self applyThumbnailContentModeForMedia:hasRealThumb];
    [self updateDownloadStatusForFile:file waiting:NO];
    self.progressView.hidden = YES;
    [self refreshAccessibility];
}

- (void)setThumbnailImage:(UIImage *)image mediaPreview:(BOOL)mediaPreview {
    self.thumbnailView.image = image;
    [self applyThumbnailContentModeForMedia:mediaPreview];
}

- (void)configureWithUploadFile:(SeafUploadFile *)file completion:(void (^)(UIImage *))completion {
    [self resetCellFile];
    self.titleLabel.text = file.name;
    // Start with a centered type icon; real photo/video previews arrive asynchronously.
    self.thumbnailView.image = [UIImage imageForMimeType:file.mime ext:file.name.pathExtension.lowercaseString];
    [self applyThumbnailContentModeForMedia:NO];
    if (completion) {
        completion(nil);
    }
    [self.downloadingIndicator stopAnimating];
    if (file.model.uploading) {
        self.progressView.hidden = NO;
        [self.progressView setProgress:file.uProgress];
        [self setStatusVisible:NO downloading:NO];
        self.accessibilityStatusText = NSLocalizedString(@"Uploading", @"Seafile");
    } else if (file.uploaded) {
        self.progressView.hidden = YES;
        [self setCacheStatusImageNamed:@"download_finished"];
        [self setStatusVisible:YES downloading:NO];
        self.accessibilityStatusText = NSLocalizedString(@"Uploaded", @"Seafile");
    } else {
        self.progressView.hidden = YES;
        [self setStatusVisible:NO downloading:NO];
        self.accessibilityStatusText = NSLocalizedString(@"Waiting to upload", @"Seafile");
    }
    [self refreshAccessibility];
}

- (void)updateDownloadStatusForFile:(SeafFile *)file waiting:(BOOL)waiting {
    BOOL cached = [file isWebOpenFile] ? NO : file.hasCache;
    BOOL isDownloading = file.isDownloading;
    if (cached || waiting || isDownloading) {
        if (isDownloading) {
            [self setStatusVisible:YES downloading:YES];
            self.accessibilityStatusText = NSLocalizedString(@"Downloading", @"Seafile");
        } else {
            NSString *imageName = waiting ? @"download_waiting" : @"download_finished";
            [self setCacheStatusImageNamed:imageName];
            [self setStatusVisible:YES downloading:NO];
            self.accessibilityStatusText = waiting
                ? NSLocalizedString(@"Waiting to download", @"Seafile")
                : NSLocalizedString(@"Downloaded", @"Seafile");
        }
    } else {
        [self setStatusVisible:NO downloading:NO];
        self.accessibilityStatusText = nil;
    }
    self.progressView.hidden = YES;
    [self refreshAccessibility];
}

- (void)updateUploadProgress:(float)progress uploaded:(BOOL)uploaded filesize:(long long)filesize timestamp:(NSTimeInterval)timestamp {
    (void)filesize;
    (void)timestamp;
    [self.downloadingIndicator stopAnimating];
    if (uploaded) {
        self.progressView.hidden = YES;
        [self setCacheStatusImageNamed:@"download_finished"];
        [self setStatusVisible:YES downloading:NO];
        self.accessibilityStatusText = NSLocalizedString(@"Uploaded", @"Seafile");
    } else {
        self.progressView.hidden = NO;
        [self.progressView setProgress:progress];
        [self setStatusVisible:NO downloading:NO];
        self.accessibilityStatusText = NSLocalizedString(@"Uploading", @"Seafile");
    }
    [self refreshAccessibility];
}

#pragma mark - Accessibility

- (void)refreshAccessibilityTraits {
    UIAccessibilityTraits traits = UIAccessibilityTraitButton;
    if (self.isUserEditing && self.isSelected) {
        traits |= UIAccessibilityTraitSelected;
    }
    self.accessibilityTraits = traits;
}

- (void)refreshAccessibility {
    self.accessibilityLabel = self.titleLabel.text;
    self.accessibilityValue = self.accessibilityStatusText;
    [self refreshAccessibilityTraits];
}

@end
