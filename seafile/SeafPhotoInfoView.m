#import "SeafPhotoInfoView.h"
#import "Debug.h"
#import "SDoc/Chips/SeafCollaboratorChipView.h"
#import <ImageIO/ImageIO.h>
#import <SDWebImage/UIImageView+WebCache.h>
#import "SeafTheme.h"

// Subview tags inside `infoScrollView`: EXIF card, profile rows section,
// and the fixed-height loading placeholder for profile rows.
static const NSInteger kExifSectionTag = 999;
static const NSInteger kProfileSectionTag = 998;
static const NSInteger kProfileLoadingTag = 997;

@interface SeafPhotoInfoView()

@property (nonatomic, strong) UIScrollView *infoScrollView;

@end

@implementation SeafPhotoInfoView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [SeafTheme secondarySurface];
        self.layer.cornerRadius = 8.0;
        self.layer.masksToBounds = YES;
        
        // Create a scroll view inside the info view for scrollable content
        self.infoScrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
        self.infoScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.infoScrollView.contentInset = UIEdgeInsetsMake(0, 0, 20, 0); // Add bottom padding
        // This nested scroll view lives entirely outside the device safe
        // area; default `.automatic` would later apply the screen's
        // safe-area top inset and silently shift contentOffset.y, cropping
        // the top of the panel until the user pulls down. Opt out.
        if (@available(iOS 11.0, *)) {
            self.infoScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        }
        [self addSubview:self.infoScrollView];
    }
    return self;
}


- (void)clearExifDataView {
    UIView *exifSectionView = [self.infoScrollView viewWithTag:kExifSectionTag];
    if (exifSectionView) {
        [exifSectionView removeFromSuperview];
    }
}

- (void)displayExifData:(NSData *)imageData {
    [self clearExifDataView];

    if (!imageData) return;

    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)imageData, NULL);
    if (!source) return;

    NSDictionary *metadata = (NSDictionary *)CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);

    if (!metadata) return;

    NSDictionary *exifDict = metadata[(NSString *)kCGImagePropertyExifDictionary];
    NSDictionary *tiffDict = metadata[(NSString *)kCGImagePropertyTIFFDictionary];

    if (!exifDict && !tiffDict) return;

    // Get EXIF data
    NSString *cameraModel = tiffDict[(NSString *)kCGImagePropertyTIFFModel];
    NSString *dateTimeOriginal = exifDict[(NSString *)kCGImagePropertyExifDateTimeOriginal];
    NSNumber *pixelWidth = metadata[(NSString *)kCGImagePropertyPixelWidth];
    NSNumber *pixelHeight = metadata[(NSString *)kCGImagePropertyPixelHeight];
    NSNumber *focalLength = exifDict[(NSString *)kCGImagePropertyExifFocalLength];
    NSNumber *aperture = exifDict[(NSString *)kCGImagePropertyExifFNumber];
    NSNumber *exposure = exifDict[(NSString *)kCGImagePropertyExifExposureTime];

    // Get color space
    NSString *colorSpace = NSLocalizedString(@"Unknown", @"Seafile");
    NSNumber *exifColorSpaceVal = exifDict[(NSString *)kCGImagePropertyExifColorSpace];
    if (exifColorSpaceVal) {
        int cs = [exifColorSpaceVal intValue];
        switch (cs) {
            case 1:
                colorSpace = @"RGB";
                break;
            case 2:
                colorSpace = @"RGB";
                break;
            case 65535:
                colorSpace = NSLocalizedString(@"Uncalibrated", @"Seafile");
                break;
            default:
                colorSpace = [NSString stringWithFormat:NSLocalizedString(@"ColorSpace %d", @"Seafile"), cs];
                break;
        }
    } else {
        NSString *modelVal = metadata[(NSString *)kCGImagePropertyColorModel];
        if (modelVal) {
            colorSpace = modelVal;
        }
    }

    // Create and layout EXIF section
    [self createAndLayoutExifSectionWithModel:cameraModel
                                        time:dateTimeOriginal
                                  dimensions:CGSizeMake([pixelWidth doubleValue], [pixelHeight doubleValue])
                                colorSpace:colorSpace
                               focalLength:focalLength
                                  aperture:aperture
                                 exposure:exposure];
}

- (void)createAndLayoutExifSectionWithModel:(NSString *)model
                                      time:(NSString *)time
                                dimensions:(CGSize)dimensions
                                colorSpace:(NSString *)colorSpace
                               focalLength:(NSNumber *)focalLength
                                  aperture:(NSNumber *)aperture
                                 exposure:(NSNumber *)exposure {
    // --- Prepare UI Elements ---
    CGFloat outerPadding = 16.0;
    CGFloat cardPadding = 12.0; // Internal padding for the card
    CGFloat verticalSpacing = 6.0;
    CGFloat availableWidth = self.infoScrollView.bounds.size.width - (2 * outerPadding);
    
    UIFont *modelFont = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    UIFont *mediumFont = [UIFont systemFontOfSize:13];
    UIFont *smallFont = [UIFont systemFontOfSize:12];
    UIColor *textColor = [SeafTheme secondaryText];
    UIColor *lightGrayColor = [SeafTheme separator];
    UIColor *cardBackgroundColor = [SeafTheme secondarySurface];
    UIColor *modelBackgroundColor = [SeafTheme fill];

    // --- Find Position ---
    // Anchor strictly against the profile area (real section preferred,
    // loading placeholder as fallback). Iterating all subviews is unsafe:
    // UIScrollView's own scroll indicators (tag==0) can be picked as the
    // "last row" once contentSize is non-zero, sending EXIF far down.
    UIView *anchorView = [self.infoScrollView viewWithTag:kProfileSectionTag];
    if (!anchorView) {
        anchorView = [self.infoScrollView viewWithTag:kProfileLoadingTag];
    }
    CGFloat startY = outerPadding;
    if (anchorView) {
        startY = CGRectGetMaxY(anchorView.frame) + outerPadding * 1.5; // 24pt gap below profile
    }

    // --- Create Card Container View ---
    UIView *exifSectionContainer = [[UIView alloc] initWithFrame:CGRectMake(outerPadding, startY, availableWidth, 0)]; // Height calculated later
    exifSectionContainer.tag = kExifSectionTag; // Important: tag it for identification later
    exifSectionContainer.backgroundColor = cardBackgroundColor;
    exifSectionContainer.layer.cornerRadius = 8.0;
    exifSectionContainer.layer.masksToBounds = YES;
    [self.infoScrollView addSubview:exifSectionContainer];

    // --- Create Sub-Background Views ---
    UIView *modelBackgroundView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, availableWidth, 0)]; // Height set later
    modelBackgroundView.backgroundColor = modelBackgroundColor;
    [exifSectionContainer addSubview:modelBackgroundView];

    UIView *detailsBackgroundView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, availableWidth, 0)]; // Position & Height set later
    detailsBackgroundView.backgroundColor = cardBackgroundColor;
    [exifSectionContainer addSubview:detailsBackgroundView];
    
    CGFloat currentModelY = cardPadding; // Y relative to modelBackgroundView
    CGFloat currentDetailsY = cardPadding; // Y relative to detailsBackgroundView

    // --- Row 1: Camera Model (in modelBackgroundView) ---
    CGFloat modelRowHeight = 0;
    if (model && model.length > 0) {
        UILabel *modelLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardPadding, currentModelY, availableWidth - 2 * cardPadding, 0)];
        modelLabel.font = modelFont;
        modelLabel.textColor = [SeafTheme primaryText];
        modelLabel.text = model;
        [modelLabel sizeToFit]; // Adjust height
        CGRect modelFrame = modelLabel.frame;
        modelFrame.size.width = availableWidth - 2 * cardPadding; // Ensure it takes full width
        modelLabel.frame = modelFrame;
        [modelBackgroundView addSubview:modelLabel];
        modelRowHeight = modelLabel.frame.size.height + cardPadding;
    }
    currentModelY += modelRowHeight;
    
    // Set model background height
    CGRect modelBgFrame = modelBackgroundView.frame;
    modelBgFrame.size.height = currentModelY;
    modelBackgroundView.frame = modelBgFrame;

    // --- Separator Line (below model background) ---
    UIView *separatorTop = [[UIView alloc] initWithFrame:CGRectMake(0, CGRectGetMaxY(modelBackgroundView.frame), availableWidth, 1.0 / [UIScreen mainScreen].scale)];
    separatorTop.backgroundColor = lightGrayColor;
    [exifSectionContainer addSubview:separatorTop]; // Add to main container
    
    // --- Position details background view ---
    CGRect detailsBgFrame = detailsBackgroundView.frame;
    detailsBgFrame.origin.y = CGRectGetMaxY(separatorTop.frame);
    detailsBackgroundView.frame = detailsBgFrame;

    // --- Row 2: Time & Dimensions ---
    CGFloat row2Height = 0;
    NSString *formattedTime = @"-";
    NSString *dimensionsString = @"-";

    // Format capture time
    if (time && time.length > 0) {
        NSDateFormatter *inFormatter = [[NSDateFormatter alloc] init];
        [inFormatter setDateFormat:@"yyyy:MM:dd HH:mm:ss"];
        NSDate *date = [inFormatter dateFromString:time];
        if (date) {
            NSDateFormatter *outFormatter = [[NSDateFormatter alloc] init];
            [outFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            formattedTime = [outFormatter stringFromDate:date];
        }
    }

    // Format dimensions
    if (dimensions.width > 0 && dimensions.height > 0) {
        dimensionsString = [NSString stringWithFormat:@"%.0f×%.0f", dimensions.width, dimensions.height];
    }

    // Add time label
    if (formattedTime && ![formattedTime isEqualToString:@"-"]) {
        UILabel *timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardPadding, currentDetailsY, availableWidth - 2 * cardPadding, 0)];
        timeLabel.font = mediumFont;
        timeLabel.textColor = textColor;
        timeLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Capture Time • %@", @"Seafile"), formattedTime];
        [timeLabel sizeToFit];
        timeLabel.frame = CGRectMake(cardPadding, currentDetailsY, availableWidth - 2 * cardPadding, timeLabel.frame.size.height);
        [detailsBackgroundView addSubview:timeLabel];
        currentDetailsY += timeLabel.frame.size.height + cardPadding - 2;
        row2Height += timeLabel.frame.size.height + cardPadding - 2;
    }

    // Add dimensions label
    if (dimensionsString && ![dimensionsString isEqualToString:@"-"]) {
        UILabel *dimLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardPadding, currentDetailsY, availableWidth - 2 * cardPadding, 0)];
        dimLabel.font = mediumFont;
        dimLabel.textColor = textColor;
        dimLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Dimensions • %@", @"Seafile"), dimensionsString];
        [dimLabel sizeToFit];
        dimLabel.frame = CGRectMake(cardPadding, currentDetailsY, availableWidth - 2 * cardPadding, dimLabel.frame.size.height);
        [detailsBackgroundView addSubview:dimLabel];
        currentDetailsY += dimLabel.frame.size.height;
        row2Height += dimLabel.frame.size.height;
    }

    currentDetailsY += verticalSpacing * 1.5; // More space after this block

    // --- Separator Line (within detailsBackgroundView) ---
    UIView *separator1 = [[UIView alloc] initWithFrame:CGRectMake(0, currentDetailsY, availableWidth, 1.0 / [UIScreen mainScreen].scale)];
    separator1.backgroundColor = lightGrayColor;
    [detailsBackgroundView addSubview:separator1];
    currentDetailsY += separator1.frame.size.height + verticalSpacing * 1.5; // Space after separator

    // --- Row 3: Technical details row ---
    // Prepare data items
    NSMutableArray *detailItems = [NSMutableArray array];
    
    // Color Space
    [detailItems addObject:colorSpace];
    
    // Focal Length
    NSString *focalString = @"-";
    if (focalLength) focalString = [NSString stringWithFormat:@"%@ mm", focalLength];
    [detailItems addObject:focalString];
    
    // Aperture 
    NSString *apertureNumberString = @"-";
    if (aperture) apertureNumberString = [NSString stringWithFormat:@"f/%.1f", aperture.doubleValue];
    [detailItems addObject:apertureNumberString];
    
    // Exposure
    NSString *exposureString = @"-";
    if (exposure) {
        double expVal = exposure.doubleValue;
        if (expVal > 0 && expVal < 1.0) {
            exposureString = [NSString stringWithFormat:@"1/%d s", (int)round(1.0 / expVal)];
        } else {
            exposureString = [NSString stringWithFormat:@"%.1f s", expVal];
        }
    }
    [detailItems addObject:exposureString];
    
    // Layout these items in a row with equal spacing
    CGFloat detailItemWidth = availableWidth / detailItems.count;
    CGFloat currentDetailX = 0;
    CGFloat detailRowHeight = 0;
    
    for (int i = 0; i < detailItems.count; i++) {
        NSString *text = detailItems[i];
        UILabel *label = [[UILabel alloc] init];
        label.font = smallFont;
        label.textColor = textColor;
        label.text = text;
        label.textAlignment = NSTextAlignmentCenter;
        [label sizeToFit];
        
        // Center label in its section
        CGFloat labelX = currentDetailX + (detailItemWidth - label.frame.size.width) / 2.0;
        label.frame = CGRectMake(labelX, currentDetailsY, label.frame.size.width, label.frame.size.height);
        [detailsBackgroundView addSubview:label];
        detailRowHeight = MAX(detailRowHeight, label.frame.size.height);
        
        // Add vertical separator (except for the last item)
        if (i < detailItems.count - 1) {
            UIView *vSeparator = [[UIView alloc] initWithFrame:CGRectMake(currentDetailX + detailItemWidth - (1.0 / [UIScreen mainScreen].scale) / 2.0,
                                                                       currentDetailsY,
                                                                       1.0 / [UIScreen mainScreen].scale,
                                                                       label.frame.size.height)];
            vSeparator.backgroundColor = lightGrayColor;
            [detailsBackgroundView addSubview:vSeparator];
        }
        
        currentDetailX += detailItemWidth;
    }
    
    // Center labels vertically in case of different heights
    for (UIView *subview in detailsBackgroundView.subviews) {
        if ([subview isKindOfClass:[UILabel class]] && 
            subview.frame.origin.y >= currentDetailsY && 
            subview.frame.origin.y < currentDetailsY + detailRowHeight) {
            CGRect frame = subview.frame;
            frame.origin.y = currentDetailsY + (detailRowHeight - frame.size.height) / 2.0;
            subview.frame = frame;
        } else if (subview.frame.origin.y >= currentDetailsY && 
                   subview.frame.origin.y < currentDetailsY + detailRowHeight &&
                   subview.frame.size.width < 2.0) {
            // Vertical separators - match their height to row height
            CGRect frame = subview.frame;
            frame.size.height = detailRowHeight;
            frame.origin.y = currentDetailsY;
            subview.frame = frame;
        }
    }
    
    currentDetailsY += detailRowHeight + cardPadding; // Add final padding
    
    // --- Finalize container sizes ---
    // Set details background height
    detailsBgFrame = detailsBackgroundView.frame;
    detailsBgFrame.size.height = currentDetailsY;
    detailsBackgroundView.frame = detailsBgFrame;
    
    // Set overall container height
    CGRect containerFrame = exifSectionContainer.frame;
    containerFrame.size.height = modelBackgroundView.frame.size.height + separatorTop.frame.size.height + detailsBackgroundView.frame.size.height;
    exifSectionContainer.frame = containerFrame;
    
    // Update scroll view content size
    CGFloat newContentHeight = CGRectGetMaxY(exifSectionContainer.frame) + outerPadding;
    CGFloat minContentHeight = self.infoScrollView.bounds.size.height + 1;
    self.infoScrollView.contentSize = CGSizeMake(self.infoScrollView.bounds.size.width, MAX(newContentHeight, minContentHeight));
}

#pragma mark - Profile Rows (Metadata from Aggregate API)

- (void)clearProfileRows {
    UIView *container = [self.infoScrollView viewWithTag:kProfileSectionTag];
    if (container) {
        [container removeFromSuperview];
    }
    [self recalculateContentSize];
}

- (void)showProfileLoading {
    // Don't add duplicate loading indicator
    if ([self.infoScrollView viewWithTag:kProfileLoadingTag]) {
        return;
    }

    CGFloat topPadding = 25.0;
    // Reserve height close to the typical profile section to minimise the
    // visual jump when profile rows replace this placeholder.
    CGFloat reservedHeight = 140.0;

    UIView *loadingContainer = [[UIView alloc] initWithFrame:CGRectMake(0, topPadding, self.infoScrollView.bounds.size.width, reservedHeight)];
    loadingContainer.tag = kProfileLoadingTag;

    UIActivityIndicatorView *spinner;
    if (@available(iOS 13.0, *)) {
        spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    } else {
        spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    }
    // Center spinner in the reserved area
    spinner.center = CGPointMake(loadingContainer.bounds.size.width / 2.0, reservedHeight / 2.0);
    spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [spinner startAnimating];
    [loadingContainer addSubview:spinner];

    [self.infoScrollView addSubview:loadingContainer];
    [self recalculateContentSize];
}

- (void)hideProfileLoading {
    UIView *loadingView = [self.infoScrollView viewWithTag:kProfileLoadingTag];
    if (loadingView) {
        [loadingView removeFromSuperview];
        [self recalculateContentSize];
    }
}

- (void)renderProfileRows:(NSArray<NSDictionary *> *)rows {
    // Always hide loading indicator first
    [self hideProfileLoading];

    if (!rows || rows.count == 0) {
        return;
    }

    // Remove previous profile section if any
    [self clearProfileRows];

    CGFloat outerPadding = 16.0;
    CGFloat topPadding = 25.0;
    CGFloat iconSize = 14.0;
    CGFloat horizontalSpacing = 8.0;
    CGFloat rowSpacing = 10.0;
    CGFloat availableWidth = self.infoScrollView.bounds.size.width - (2 * outerPadding);
    CGFloat leftColumnWidth = 140.0;

    UIFont *titleFont = [UIFont systemFontOfSize:14];
    UIFont *valueFont = [UIFont systemFontOfSize:14];
    UIColor *titleColor = [SeafTheme secondaryText];
    UIColor *valueColor = [SeafTheme primaryText];
    UIColor *emptyColor = [SeafTheme tertiaryText];
    UIColor *iconTint = [SeafTheme tertiaryText];

    // Profile section is the primary content — start from reduced top padding
    CGFloat insertY = topPadding;

    // Create profile section container
    UIView *profileContainer = [[UIView alloc] initWithFrame:CGRectMake(0, insertY, self.infoScrollView.bounds.size.width, 0)];
    profileContainer.tag = kProfileSectionTag;

    CGFloat currentY = rowSpacing;

    for (NSDictionary *row in rows) {
        NSString *type = row[@"type"] ?: @"text";
        NSString *title = NSLocalizedString(row[@"title"] ?: @"", nil);
        NSString *iconName = row[@"icon"] ?: @"text";
        NSArray *values = row[@"values"] ?: @[];

        // --- Left side: icon + title ---
        UIImage *img = [UIImage imageNamed:iconName];
        if (!img) img = [UIImage imageNamed:@"text"];
        img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIImageView *iconView = [[UIImageView alloc] initWithImage:img];
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.tintColor = iconTint;
        iconView.frame = CGRectMake(outerPadding, currentY + 2, iconSize, iconSize);
        [profileContainer addSubview:iconView];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.font = titleFont;
        titleLabel.textColor = titleColor;
        titleLabel.text = title;
        titleLabel.numberOfLines = 1;
        [titleLabel sizeToFit];
        CGFloat titleX = outerPadding + iconSize + horizontalSpacing;
        titleLabel.frame = CGRectMake(titleX, currentY, leftColumnWidth - iconSize - horizontalSpacing, titleLabel.frame.size.height);
        [profileContainer addSubview:titleLabel];

        // --- Right side: values ---
        CGFloat rightX = outerPadding + leftColumnWidth + horizontalSpacing;
        CGFloat rightWidth = availableWidth - leftColumnWidth - horizontalSpacing;
        CGFloat rowHeight = MAX(titleLabel.frame.size.height, 20);

        if ([self isProfilePlainTextType:type]) {
            // Plain text value (right-aligned)
            NSMutableString *combined = [NSMutableString string];
            BOOL isEmpty = NO;
            for (NSDictionary *v in values) {
                NSString *t = v[@"text"] ?: @"";
                isEmpty = [v[@"isEmpty"] boolValue] || [t isEqualToString:@"empty"];
                if (isEmpty) t = NSLocalizedString(@"Empty", nil);
                if (combined.length > 0) [combined appendString:@"\n"];
                [combined appendString:t];
            }
            UILabel *valLabel = [[UILabel alloc] init];
            valLabel.font = valueFont;
            valLabel.textColor = isEmpty ? emptyColor : valueColor;
            valLabel.text = combined;
            valLabel.textAlignment = NSTextAlignmentRight;
            valLabel.numberOfLines = 0;
            valLabel.lineBreakMode = NSLineBreakByWordWrapping;
            CGSize maxSize = CGSizeMake(rightWidth, CGFLOAT_MAX);
            CGSize fitted = [valLabel sizeThatFits:maxSize];
            valLabel.frame = CGRectMake(rightX, currentY, rightWidth, fitted.height);
            [profileContainer addSubview:valLabel];
            rowHeight = MAX(rowHeight, fitted.height);

        } else if ([self isProfileChipsType:type]) {
            // Chips: collaborator, single_select, multiple_select, link (tags)
            CGFloat chipHeight = 22.0;
            CGFloat chipSpacing = 4.0;
            CGFloat chipX = rightX;
            CGFloat chipY = currentY;
            CGFloat chipRowMaxX = rightX + rightWidth;
            BOOL allEmpty = YES;

            for (NSDictionary *v in values) {
                BOOL vEmpty = [v[@"isEmpty"] boolValue];
                NSString *vText = v[@"text"] ?: @"";
                if (!(vEmpty || [vText isEqualToString:@"empty"])) {
                    allEmpty = NO;
                    break;
                }
            }

            if (allEmpty) {
                UILabel *emptyLabel = [[UILabel alloc] init];
                emptyLabel.font = valueFont;
                emptyLabel.textColor = emptyColor;
                emptyLabel.text = NSLocalizedString(@"Empty", nil);
                emptyLabel.textAlignment = NSTextAlignmentRight;
                [emptyLabel sizeToFit];
                emptyLabel.frame = CGRectMake(rightX, currentY, rightWidth, emptyLabel.frame.size.height);
                [profileContainer addSubview:emptyLabel];
                rowHeight = MAX(rowHeight, emptyLabel.frame.size.height);
            } else {
                // --- Two-pass layout: measure first, then place right-aligned ---
                // Pass 1: Calculate widths of all non-empty chips
                NSMutableArray *chipWidths = [NSMutableArray array];
                for (NSDictionary *v in values) {
                    BOOL vEmpty = [v[@"isEmpty"] boolValue];
                    NSString *vText = v[@"text"] ?: @"";
                    if (vEmpty || [vText isEqualToString:@"empty"]) continue;

                    if ([type isEqualToString:@"collaborator"]) {
                        NSString *name = v[@"user_name"] ?: vText;
                        UIFont *chipFont = [UIFont systemFontOfSize:15];
                        CGFloat nameW = ceil([name sizeWithAttributes:@{NSFontAttributeName:chipFont}].width);
                        // Align with SeafCollaboratorChipView: left 4 + avatar 16 + spacing 4 + text + right 8
                        CGFloat chipW = 4 + 16 + 4 + nameW + 8;
                        [chipWidths addObject:@(chipW)];
                    } else {
                        NSString *text = vText;
                        UIFont *chipFont = [UIFont systemFontOfSize:13];
                        CGFloat textW = ceil([text sizeWithAttributes:@{NSFontAttributeName:chipFont}].width);
                        BOOL isDotStyle = [type isEqualToString:@"link"];
                        CGFloat chipW;
                        if (isDotStyle) {
                            CGFloat dotSize = 10.0;
                            chipW = 5 + dotSize + 4 + textW + 8;
                        } else {
                            chipW = 8 + textW + 8;
                        }
                        [chipWidths addObject:@(chipW)];
                    }
                }

                // Calculate total width of chips that fit on the first row
                CGFloat totalFirstRowW = 0;
                for (NSUInteger i = 0; i < chipWidths.count; i++) {
                    CGFloat w = [chipWidths[i] floatValue];
                    CGFloat needed = (i > 0) ? chipSpacing + w : w;
                    if (totalFirstRowW + needed > rightWidth) break;
                    totalFirstRowW += needed;
                }

                // Start X: right-aligned on the first row
                chipX = chipRowMaxX - totalFirstRowW;
                chipY = currentY;

                // Pass 2: Create and place chips
                NSUInteger chipIdx = 0;
                for (NSDictionary *v in values) {
                    BOOL vEmpty = [v[@"isEmpty"] boolValue];
                    NSString *vText = v[@"text"] ?: @"";
                    if (vEmpty || [vText isEqualToString:@"empty"]) continue;

                    CGFloat chipW = [chipWidths[chipIdx] floatValue];
                    chipIdx++;

                    // Wrap to next row if needed (subsequent rows also right-aligned)
                    if (chipX + chipW > chipRowMaxX && chipX > rightX) {
                        // Recalculate remaining chips width for right-alignment on new row
                        CGFloat remainingW = 0;
                        for (NSUInteger j = chipIdx - 1; j < chipWidths.count; j++) {
                            CGFloat w = [chipWidths[j] floatValue];
                            CGFloat needed = (j > chipIdx - 1) ? chipSpacing + w : w;
                            if (remainingW + needed > rightWidth) break;
                            remainingW += needed;
                        }
                        chipX = chipRowMaxX - remainingW;
                        chipY += chipHeight + chipSpacing;
                    }

                    if ([type isEqualToString:@"collaborator"]) {
                        NSString *name = v[@"user_name"] ?: vText;
                        NSString *avatarURL = v[@"avatar"] ?: @"";

                        SeafCollaboratorChipView *chip = [[SeafCollaboratorChipView alloc] initWithFrame:CGRectMake(chipX, chipY, chipW, chipHeight)];
                        [chip configureWithName:name avatarURL:avatarURL];

                        [profileContainer addSubview:chip];
                    } else {
                        // Tag / select chip
                        NSString *text = vText;
                        NSString *bgColor = v[@"color"] ?: @"";
                        NSString *txtColor = v[@"textColor"] ?: @"";
                        UIFont *chipFont = [UIFont systemFontOfSize:13];
                        CGFloat textW = ceil([text sizeWithAttributes:@{NSFontAttributeName:chipFont}].width);
                        BOOL isDotStyle = [type isEqualToString:@"link"];

                        UIView *chip = [[UIView alloc] initWithFrame:CGRectMake(chipX, chipY, chipW, chipHeight)];
                        chip.layer.cornerRadius = chipHeight / 2.0;
                        chip.layer.masksToBounds = YES;

                        if (isDotStyle) {
                            chip.backgroundColor = [SeafTheme fill];
                            CGFloat dotSize = 10.0;
                            UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(5, (chipHeight - dotSize) / 2, dotSize, dotSize)];
                            dot.layer.cornerRadius = dotSize / 2;
                            dot.backgroundColor = [self profileColorFromHex:bgColor] ?: [UIColor grayColor];
                            [chip addSubview:dot];

                            UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(5 + dotSize + 4, 0, textW, chipHeight)];
                            tl.font = chipFont;
                            tl.textColor = [self profileColorFromHex:txtColor] ?: valueColor;
                            tl.text = text;
                            [chip addSubview:tl];
                        } else {
                            UIColor *bg = [self profileColorFromHex:bgColor];
                            chip.backgroundColor = bg ?: [SeafTheme fill];

                            UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, textW, chipHeight)];
                            tl.font = chipFont;
                            tl.textColor = [self profileColorFromHex:txtColor] ?: valueColor;
                            tl.text = text;
                            [chip addSubview:tl];
                        }

                        [profileContainer addSubview:chip];
                    }

                    chipX += chipW + chipSpacing;
                }
                CGFloat chipsBottom = chipY + chipHeight;
                rowHeight = MAX(rowHeight, chipsBottom - currentY);
            }

        } else if ([type isEqualToString:@"rate"]) {
            NSDictionary *v = values.firstObject ?: @{};
            NSInteger selected = [v[@"ratingSelected"] integerValue];
            NSInteger maxRate = [v[@"ratingMax"] integerValue] ?: 5;
            NSString *ratingColorHex = v[@"ratingColor"] ?: @"";
            UIColor *selColor = [self profileColorFromHex:ratingColorHex] ?: [SeafTheme secondaryText];
            UIColor *unSelColor = [SeafTheme separator];
            CGFloat starSize = 16.0;
            CGFloat starSpacing = 3.0;
            // Right-align stars
            CGFloat totalStarsW = maxRate * starSize + (maxRate - 1) * starSpacing;
            CGFloat starStartX = rightX + rightWidth - totalStarsW;
            for (NSInteger i = 0; i < maxRate; i++) {
                UIImage *starImg = [[UIImage imageNamed:@"ic_star_32"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                UIImageView *star = [[UIImageView alloc] initWithImage:starImg];
                star.contentMode = UIViewContentModeScaleAspectFit;
                star.tintColor = (i < selected) ? selColor : unSelColor;
                star.frame = CGRectMake(starStartX + i * (starSize + starSpacing), currentY + 1, starSize, starSize);
                [profileContainer addSubview:star];
            }
            rowHeight = MAX(rowHeight, starSize);

        } else if ([type isEqualToString:@"checkbox"]) {
            NSDictionary *v = values.firstObject ?: @{};
            BOOL checked = [v[@"checked"] boolValue];
            UIImage *cbImg = nil;
            if (@available(iOS 13.0, *)) {
                cbImg = checked ? [UIImage systemImageNamed:@"checkmark.square.fill"] : [UIImage systemImageNamed:@"square"];
            }
            if (!cbImg) {
                cbImg = checked ? [UIImage imageNamed:@"ic_checkbox_checked"] : [UIImage imageNamed:@"ic_checkbox_unchecked"];
            }
            cbImg = [cbImg imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            UIImageView *cbView = [[UIImageView alloc] initWithImage:cbImg];
            cbView.contentMode = UIViewContentModeScaleAspectFit;
            cbView.tintColor = [SeafTheme accentOrange];
            CGFloat cbSize = 18.0;
            cbView.frame = CGRectMake(rightX + rightWidth - cbSize, currentY, cbSize, cbSize);
            [profileContainer addSubview:cbView];
            rowHeight = MAX(rowHeight, cbSize);
        }

        // Vertically center icon with the row
        CGRect iconFrame = iconView.frame;
        iconFrame.origin.y = currentY + (rowHeight - iconSize) / 2.0;
        iconView.frame = iconFrame;

        currentY += rowHeight + rowSpacing;
    }

    currentY += 10; // Bottom padding

    // Set container height
    CGRect containerFrame = profileContainer.frame;
    containerFrame.size.height = currentY;
    profileContainer.frame = containerFrame;
    [self.infoScrollView addSubview:profileContainer];

    // Re-align EXIF against the freshly-rendered profile container.
    UIView *exifView = [self.infoScrollView viewWithTag:kExifSectionTag];
    if (exifView) {
        CGRect exifFrame = exifView.frame;
        CGFloat desiredExifY = CGRectGetMaxY(profileContainer.frame) + 10;
        if (fabs(exifFrame.origin.y - desiredExifY) > 0.5) {
            exifFrame.origin.y = desiredExifY;
            exifView.frame = exifFrame;
        }
    }

    [self recalculateContentSize];
}

- (void)recalculateContentSize {
    CGFloat maxBottom = 0;
    for (UIView *subview in self.infoScrollView.subviews) {
        CGFloat bottom = CGRectGetMaxY(subview.frame);
        if (bottom > maxBottom) maxBottom = bottom;
    }
    CGFloat minContentHeight = self.infoScrollView.bounds.size.height + 1;
    self.infoScrollView.contentSize = CGSizeMake(self.infoScrollView.bounds.size.width, MAX(maxBottom + 20, minContentHeight));
}

- (BOOL)isProfilePlainTextType:(NSString *)type {
    static NSSet *types;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        types = [NSSet setWithArray:@[@"text", @"long_text", @"number", @"date", @"url", @"email", @"duration", @"geolocation"]];
    });
    return [types containsObject:type ?: @""];
}

- (BOOL)isProfileChipsType:(NSString *)type {
    static NSSet *types;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        types = [NSSet setWithArray:@[@"collaborator", @"single_select", @"multiple_select", @"link"]];
    });
    return [types containsObject:type ?: @""];
}

- (UIColor *)profileColorFromHex:(NSString *)hex {
    if (![hex isKindOfClass:[NSString class]] || hex.length == 0) return nil;
    NSString *h = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (h.length < 6) return nil;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:h] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb>>16)&0xFF)/255.0 green:((rgb>>8)&0xFF)/255.0 blue:(rgb&0xFF)/255.0 alpha:1];
}

#pragma mark - Scroll View Property Access Methods

- (CGPoint)contentOffset {
    return self.infoScrollView.contentOffset;
}

- (BOOL)isDragging {
    return self.infoScrollView.isDragging;
}

- (UIPanGestureRecognizer *)panGestureRecognizer {
    return self.infoScrollView.panGestureRecognizer;
}

@end 
