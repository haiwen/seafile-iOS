#import "SeafPhotoInfoView.h"
#import "FileSizeFormatter.h"
#import "Debug.h"
#import <ImageIO/ImageIO.h>
#import <SDWebImage/UIImageView+WebCache.h>

@interface SeafPhotoInfoView()

@property (nonatomic, strong) UIScrollView *infoScrollView;

@end

@implementation SeafPhotoInfoView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.98 alpha:1.0];
        self.layer.cornerRadius = 8.0;
        self.layer.masksToBounds = YES;
        
        // Create a scroll view inside the info view for scrollable content
        self.infoScrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
        self.infoScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.infoScrollView.contentInset = UIEdgeInsetsMake(0, 0, 20, 0); // Add bottom padding
        [self addSubview:self.infoScrollView];
    }
    return self;
}

- (void)updateInfoView {
    // Clear only the standard info rows (assuming they don't have tag 999)
    for (UIView *subview in [self.infoScrollView.subviews copy]) {
        if (subview.tag != 999) { // Do not remove the EXIF container
            [subview removeFromSuperview];
        }
    }
    
    if (!self.infoModel || self.infoModel.count == 0) {
        return;
    }
    
    CGFloat padding = 16.0;
    CGFloat iconSize = 18.0;
    CGFloat verticalSpacing = 13.0;
    CGFloat horizontalSpacing = 10.0;
    CGFloat currentY = padding + 10;
    CGFloat availableWidth = self.infoScrollView.bounds.size.width - (2 * padding);

    UIFont *keyLabelFont = [UIFont systemFontOfSize:14];
    UIFont *valueLabelFont = [UIFont systemFontOfSize:14];
    UIColor *keyLabelColor = [UIColor darkGrayColor];
    UIColor *valueLabelColor = [UIColor blackColor];

    // Keep track of the last standard row's bottom position
    CGFloat lastStandardRowBottomY = currentY;

    // Define the items to display based on the design
    NSArray *infoItems = @[
        @{@"icon": @"detail_photo_size",     @"key": @"Size",        @"label": NSLocalizedString(@"Size", @"Seafile"), @"placeholder": @"N/A"},
        @{@"icon": @"detail_photo_calendar", @"key": @"Modified",    @"label": NSLocalizedString(@"Modified Time", @"Seafile"), @"placeholder": NSLocalizedString(@"Unknown Date", @"Seafile")},
        @{@"icon": @"detail_photo_user",     @"key": @"Owner",       @"label": NSLocalizedString(@"Last Modifier", @"Seafile"), @"placeholder": NSLocalizedString(@"Unknown User", @"Seafile")}
    ];

    for (NSDictionary *itemInfo in infoItems) {
        NSString *iconName = itemInfo[@"icon"];
        NSString *dataKey = itemInfo[@"key"];
        NSString *displayLabelText = itemInfo[@"label"];
        NSString *placeholder = itemInfo[@"placeholder"];
        
        NSString *value = [self.infoModel objectForKey:dataKey];
        if (!value || [value isKindOfClass:[NSNull class]] || [value isEqualToString:@""]) {
            value = placeholder;
        } else {
            if ([dataKey isEqualToString:@"Size"]) {
                long long sizeBytes = [value longLongValue];
                if (sizeBytes > 0) {
                    value = [FileSizeFormatter stringFromLongLong:sizeBytes];
                } else {
                    value = placeholder;
                }
            }
            else if ([dataKey isEqualToString:@"Modified"]) {
                NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
                [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"];
                
                NSDate *date = [inputFormatter dateFromString:value];
                if (date) {
                    NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
                    [outputFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                    value = [outputFormatter stringFromDate:date];
                } else {
                    [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
                    date = [inputFormatter dateFromString:value];
                    
                    if (date) {
                        NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
                        [outputFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                        value = [outputFormatter stringFromDate:date];
                    }
                }
            }
        }

        // Create Row Container
        UIView *rowView = [[UIView alloc] initWithFrame:CGRectMake(padding, currentY, availableWidth, iconSize)];
        
        // Icon
        UIImageView *iconImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, iconSize, iconSize)];
        iconImageView.image = [UIImage imageNamed:iconName];
        iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        [rowView addSubview:iconImageView];
        
        // Key Label
        UILabel *keyLabel = [[UILabel alloc] init];
        keyLabel.font = keyLabelFont;
        keyLabel.textColor = keyLabelColor;
        keyLabel.text = displayLabelText;
        [keyLabel sizeToFit];
        
        CGFloat keyLabelX = iconSize + horizontalSpacing;
        CGFloat keyLabelY = (iconSize - keyLabel.frame.size.height) / 2.0;
        keyLabel.frame = CGRectMake(keyLabelX, keyLabelY, keyLabel.frame.size.width, keyLabel.frame.size.height);
        [rowView addSubview:keyLabel];
        
        CGFloat standardRowHeight = 26.0;
        
        if ([dataKey isEqualToString:@"Owner"]) {
            UIView *ownerTagView = [self createOwnerTagViewWithValue:value availableWidth:availableWidth standardRowHeight:standardRowHeight];
            [rowView addSubview:ownerTagView];
        } else {
            UILabel *valueLabel = [[UILabel alloc] init];
            valueLabel.font = valueLabelFont;
            valueLabel.textColor = valueLabelColor;
            valueLabel.text = value;
            valueLabel.textAlignment = NSTextAlignmentRight;
            valueLabel.numberOfLines = 0;
            
            CGFloat valueLabelX = CGRectGetMaxX(keyLabel.frame) + horizontalSpacing;
            CGFloat valueLabelWidth = availableWidth - valueLabelX;
            valueLabel.frame = CGRectMake(valueLabelX, 0, valueLabelWidth, standardRowHeight);
            valueLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
            
            [rowView addSubview:valueLabel];
        }

        CGRect rowFrame = rowView.frame;
        rowFrame.size.height = standardRowHeight;
        rowView.frame = rowFrame;
        
        CGRect iconFrame = iconImageView.frame;
        iconFrame.origin.y = (standardRowHeight - iconSize) / 2.0;
        iconImageView.frame = iconFrame;
        
        CGRect keyLabelFrame = keyLabel.frame;
        keyLabelFrame.origin.y = (standardRowHeight - keyLabel.frame.size.height) / 2.0;
        keyLabel.frame = keyLabelFrame;
        
        [self.infoScrollView addSubview:rowView];
        
        currentY += standardRowHeight + verticalSpacing;
        lastStandardRowBottomY = currentY;
    }

    CGFloat totalContentHeight = lastStandardRowBottomY + padding;
    CGFloat minContentHeight = self.infoScrollView.bounds.size.height + 1;
    self.infoScrollView.contentSize = CGSizeMake(self.infoScrollView.bounds.size.width, MAX(totalContentHeight, minContentHeight));
}

- (UIView *)createOwnerTagViewWithValue:(NSString *)value availableWidth:(CGFloat)availableWidth standardRowHeight:(CGFloat)standardRowHeight {
    UIView *ownerTagView = [[UIView alloc] init];
    ownerTagView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0];
    ownerTagView.layer.cornerRadius = 13.0;
    ownerTagView.layer.masksToBounds = YES;

    UIImageView *avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(5, 2, 22, 22)];
    avatarView.contentMode = UIViewContentModeScaleAspectFill;
    avatarView.layer.cornerRadius = 11.0;
    avatarView.layer.masksToBounds = YES;
    avatarView.backgroundColor = [UIColor lightGrayColor];
    
    NSString *avatarURL = [self.infoModel objectForKey:@"OwnerAvatar"];
    if (avatarURL) {
        NSURL *url = [NSURL URLWithString:avatarURL];
        if (url) {
            // set avatar
            [avatarView sd_setImageWithURL:url placeholderImage:[UIImage imageNamed:@"account"]];
        }
    }
    [ownerTagView addSubview:avatarView];

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.font = [UIFont systemFontOfSize:14];
    nameLabel.textColor = [UIColor darkGrayColor];
    nameLabel.text = value;
    [nameLabel sizeToFit];

    CGFloat nameLabelWidth = nameLabel.frame.size.width;
    CGFloat tagWidth = 5 + 22 + 5 + nameLabelWidth + 8;
    CGFloat tagHeight = 26;

    ownerTagView.frame = CGRectMake(availableWidth - tagWidth, (standardRowHeight - tagHeight) / 2, tagWidth, tagHeight);
    nameLabel.frame = CGRectMake(5 + 22 + 5, (tagHeight - nameLabel.frame.size.height) / 2, nameLabelWidth, nameLabel.frame.size.height);
    [ownerTagView addSubview:nameLabel];

    return ownerTagView;
}

- (void)clearExifDataView {
    NSInteger exifSectionTag = 999;
    UIView *exifSectionView = [self.infoScrollView viewWithTag:exifSectionTag];
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
    UIColor *textColor = [UIColor darkGrayColor];
    UIColor *lightGrayColor = [UIColor lightGrayColor];
    UIColor *cardBackgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0]; // Light gray background for card
    UIColor *modelBackgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0]; // Slightly darker for model row

    // --- Find Position ---
    UIView *lastStandardRowView = nil;
    for (UIView *subview in self.infoScrollView.subviews) {
        if ([subview isKindOfClass:[UIView class]] && subview.tag != 999) {
            lastStandardRowView = subview;
        }
    }
    CGFloat startY = outerPadding; // Default start Y
    if (lastStandardRowView) {
        startY = CGRectGetMaxY(lastStandardRowView.frame) + outerPadding * 1.5; // Position below the last standard row
    }

    // --- Create Card Container View ---
    UIView *exifSectionContainer = [[UIView alloc] initWithFrame:CGRectMake(outerPadding, startY, availableWidth, 0)]; // Height calculated later
    exifSectionContainer.tag = 999; // Important: tag it for identification later
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
        modelLabel.textColor = [UIColor blackColor]; // Use black for model
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
