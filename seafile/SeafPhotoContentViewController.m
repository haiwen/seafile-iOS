//
//  SeafPhotoContentViewController.m
//  seafileApp
//
//  Created by henry on 2025/4/17.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import "SeafPhotoContentViewController.h"
#import <ImageIO/ImageIO.h>
#import "FileSizeFormatter.h"
#import "Debug.h"
#import "ExtentedString.h"
#import "SeafConnection.h"
#import <SDWebImage/UIImageView+WebCache.h>
#import "SeafFile.h"
#import "SeafStorage.h"

@interface SeafPhotoContentViewController ()<UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView  *scrollView;
@property (nonatomic, strong) UIImageView   *imageView;
@property (nonatomic, strong) UIView        *infoView;
@property (nonatomic, strong) UIScrollView  *infoScrollView;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGesture;

// Declare internal setup method
- (void)setupLoadingIndicator;
@end

@implementation SeafPhotoContentViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0]; // Light gray background
    [self setupScrollView];
    [self setupInfoView];
    [self setupLoadingIndicator];
    [self loadImage];
    
    // Initialize with info view hidden
    self.infoVisible = NO;
    self.infoView.hidden = YES;
}

- (void)setupScrollView {
    // Create a scroll view that fills the entire view
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.scrollView.delegate = self;
    self.scrollView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0]; // Light gray background
    // Keep default zoom at 1.0, so the image is displayed at its original scale
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 3.0;
    // Show horizontal and vertical scroll indicators
    self.scrollView.showsHorizontalScrollIndicator = YES;
    self.scrollView.showsVerticalScrollIndicator = YES;
    [self.view addSubview:self.scrollView];

    // Create an image view that matches the size of the scroll view
    self.imageView = [[UIImageView alloc] initWithFrame:self.scrollView.bounds];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit; // Ensure image fits view and maintains aspect ratio
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.scrollView addSubview:self.imageView];
    
    // Add tap gesture for toggling UI visibility
    self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self.scrollView addGestureRecognizer:self.tapGesture];
    
    // Add double tap gesture for zooming
    self.doubleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    self.doubleTapGesture.numberOfTapsRequired = 2;
    [self.scrollView addGestureRecognizer:self.doubleTapGesture];
    
    // Ensure single tap gesture doesn't interfere with double tap
    [self.tapGesture requireGestureRecognizerToFail:self.doubleTapGesture];
}

- (void)setupInfoView {
    // Create the info view that will display metadata
    CGFloat infoHeight = roundf(self.view.bounds.size.height * 0.6); // 3/5 of screen height
    
    // Position initially off-screen at the bottom
    CGRect infoFrame = CGRectMake(0,
                                  self.view.bounds.size.height,
                                  self.view.bounds.size.width,
                                  infoHeight);
    
    // Create info view with a slightly translucent background
    self.infoView = [[UIView alloc] initWithFrame:infoFrame];
    self.infoView.backgroundColor = [UIColor colorWithWhite:0.98 alpha:1.0];
    
    // Add autoresizing mask to maintain width and position relative to bottom
    self.infoView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    
    // Add to view hierarchy as a top-level view (above scroll view)
    [self.view addSubview:self.infoView];
    
    // Create a scroll view inside the info view for scrollable content
    self.infoScrollView = [[UIScrollView alloc] initWithFrame:self.infoView.bounds];
    self.infoScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.infoScrollView.contentInset = UIEdgeInsetsMake(0, 0, 20, 0); // Add bottom padding
    self.infoScrollView.delegate = self; // Add delegate to detect scrolling
    [self.infoView addSubview:self.infoScrollView];
    
    // Add swipe gesture recognizer to detect down swipes on the info view
    UISwipeGestureRecognizer *swipeDownGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleInfoViewSwipeDown:)];
    swipeDownGesture.direction = UISwipeGestureRecognizerDirectionDown;
    [self.infoView addGestureRecognizer:swipeDownGesture];
    
    // Initially hidden
    self.infoView.hidden = YES;
}

// Update the info view with data from the info model
- (void)updateInfoView {
    // Preserve the EXIF section view if it exists
    UIView *exifSectionContainer = [self.infoScrollView viewWithTag:999];

    // Clear only the standard info rows (assuming they don't have tag 999)
    for (UIView *subview in [self.infoScrollView.subviews copy]) {
        if (subview.tag != 999) { // Do not remove the EXIF container
            [subview removeFromSuperview];
        }
    }
    
    if (!self.infoModel || self.infoModel.count == 0) {
        // If no info model, remove EXIF view if it exists
        [exifSectionContainer removeFromSuperview];
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

    // --- Keep track of the last standard row's bottom position ---
    CGFloat lastStandardRowBottomY = currentY;

    // Define the items to display based on the design
    // Added "label" key for the display text
    NSArray *infoItems = @[
        @{@"icon": @"detail_photo_size",     @"key": @"Size",        @"label": @"大小",         @"placeholder": @"N/A"},
        @{@"icon": @"detail_photo_calendar", @"key": @"Modified",    @"label": @"修改时间",     @"placeholder": @"未知日期"},
        @{@"icon": @"detail_photo_user",     @"key": @"Owner",       @"label": @"修改者",        @"placeholder": @"未知用户"}
    ];

    for (NSDictionary *itemInfo in infoItems) {
        NSString *iconName = itemInfo[@"icon"];
        NSString *dataKey = itemInfo[@"key"];
        NSString *displayLabelText = itemInfo[@"label"]; // Get the Chinese label
        NSString *placeholder = itemInfo[@"placeholder"];
        
        // Get the value from the model, use placeholder if not found
        NSString *value = [self.infoModel objectForKey:dataKey];
        if (!value || [value isKindOfClass:[NSNull class]] || [value isEqualToString:@""]) {
            value = placeholder;
        } else {
            // Format the size value specifically
            if ([dataKey isEqualToString:@"Size"]) {
                long long sizeBytes = [value longLongValue];
                if (sizeBytes > 0) { // Format only if valid size
                    value = [FileSizeFormatter stringFromLongLong:sizeBytes];
                } else {
                    value = placeholder; // Use placeholder for invalid/zero size
                }
            }
            // 添加对修改时间的格式处理
            else if ([dataKey isEqualToString:@"Modified"]) {
                // Add handling for modification time formatting
                NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
                [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"]; // ISO8601 format returned by API
                
                NSDate *date = [inputFormatter dateFromString:value];
                if (date) {
                    // Create output formatter
                    NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
                    [outputFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                    
                    // Format the date
                    value = [outputFormatter stringFromDate:date];
                } else {
                    // If parsing fails, try other possible date formats
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
        
        // --- Create Row Container ---
        // Use availableWidth for the row, height will be adjusted
        UIView *rowView = [[UIView alloc] initWithFrame:CGRectMake(padding, currentY, availableWidth, iconSize)];
        
        // --- Icon ---
        UIImageView *iconImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, iconSize, iconSize)];
        iconImageView.image = [UIImage imageNamed:iconName];
        iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        // iconImageView.tintColor = [UIColor grayColor]; // Optional tint
        [rowView addSubview:iconImageView];
        
        // --- Key Label ("size", "modify time", etc.) ---
        UILabel *keyLabel = [[UILabel alloc] init]; // Frame will be set later
        keyLabel.font = keyLabelFont;
        keyLabel.textColor = keyLabelColor;
        keyLabel.text = displayLabelText;
        [keyLabel sizeToFit]; // Get the intrinsic size
        
        // Position key label next to icon
        CGFloat keyLabelX = iconSize + horizontalSpacing;
        CGFloat keyLabelY = (iconSize - keyLabel.frame.size.height) / 2.0; // Center vertically with icon
        keyLabel.frame = CGRectMake(keyLabelX, keyLabelY, keyLabel.frame.size.width, keyLabel.frame.size.height);
        [rowView addSubview:keyLabel];
        
        // Determine the standard row height - use the same height for all rows
        CGFloat standardRowHeight = 26.0; // Use the same height as the modifier label
        
        // Special handling for the "Owner" item
        if ([dataKey isEqualToString:@"Owner"]) {
            // Create a rounded corner background container to serve as the tag background
            UIView *ownerTagView = [self createOwnerTagViewWithValue:value availableWidth:availableWidth standardRowHeight:standardRowHeight];
            // 添加到行视图
            [rowView addSubview:ownerTagView];
        } else {
            // Standard value label (non-Owner item)
            UILabel *valueLabel = [[UILabel alloc] init];
            valueLabel.font = valueLabelFont;
            valueLabel.textColor = valueLabelColor;
            valueLabel.text = value;
            valueLabel.textAlignment = NSTextAlignmentRight;
            valueLabel.numberOfLines = 0;
            
            // Calculate the position and size of the value label
            CGFloat valueLabelX = CGRectGetMaxX(keyLabel.frame) + horizontalSpacing;
            CGFloat valueLabelWidth = availableWidth - valueLabelX;
            
            // Use a fixed height to maintain consistency, do not use dynamic height calculation
            valueLabel.frame = CGRectMake(valueLabelX, 0, valueLabelWidth, standardRowHeight);
            
            valueLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
            
            [rowView addSubview:valueLabel];
        }
        
        // Adjust the row view height to the standard height
        CGRect rowFrame = rowView.frame;
        rowFrame.size.height = standardRowHeight;
        rowView.frame = rowFrame;
        
        // Adjust the vertical position of the icon and key label to center them within the row
        CGRect iconFrame = iconImageView.frame;
        iconFrame.origin.y = (standardRowHeight - iconSize) / 2.0;
        iconImageView.frame = iconFrame;
        
        CGRect keyLabelFrame = keyLabel.frame;
        keyLabelFrame.origin.y = (standardRowHeight - keyLabel.frame.size.height) / 2.0;
        keyLabel.frame = keyLabelFrame;
        
        [self.infoScrollView addSubview:rowView];
        
        // Update the Y position for the next row using a fixed row spacing
        currentY += standardRowHeight + verticalSpacing;
        
        // --- Track the bottom of the last standard row ---
        lastStandardRowBottomY = currentY;
    }
    
    // --- EXIF Data Section ---
    // Re-add the preserved EXIF container if it existed
    if (exifSectionContainer) {
        // Reposition it below the last standard row
        CGRect exifFrame = exifSectionContainer.frame;
        // Add more spacing before the EXIF section starts
        exifFrame.origin.y = lastStandardRowBottomY + verticalSpacing * 2;
        exifSectionContainer.frame = exifFrame;

        // Calculate total height including the repositioned EXIF section
        CGFloat totalContentHeight = CGRectGetMaxY(exifSectionContainer.frame) + padding;
        CGFloat minContentHeight = self.infoScrollView.bounds.size.height + 1;
        self.infoScrollView.contentSize = CGSizeMake(self.infoScrollView.bounds.size.width, MAX(totalContentHeight, minContentHeight));
    } else {
        // adding the section and updating contentSize later if needed.
        CGFloat totalContentHeight = lastStandardRowBottomY + padding; // Height of standard rows + padding
        CGFloat minContentHeight = self.infoScrollView.bounds.size.height + 1;
        self.infoScrollView.contentSize = CGSizeMake(self.infoScrollView.bounds.size.width, MAX(totalContentHeight, minContentHeight));
    }
}

// Helper method to create the owner tag view
- (UIView *)createOwnerTagViewWithValue:(NSString *)value availableWidth:(CGFloat)availableWidth standardRowHeight:(CGFloat)standardRowHeight {
    // Create a rounded corner background container to serve as the tag background
    UIView *ownerTagView = [[UIView alloc] init];
    ownerTagView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0]; // Light gray background
    ownerTagView.layer.cornerRadius = 13.0; // Rounded corners
    ownerTagView.layer.masksToBounds = YES;

    // Create circular avatar view
    UIImageView *avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(5, 2, 22, 22)];
    avatarView.contentMode = UIViewContentModeScaleAspectFill;
    avatarView.layer.cornerRadius = 11.0; // Circular
    avatarView.layer.masksToBounds = YES;
    avatarView.backgroundColor = [UIColor lightGrayColor]; // Default background color

    // Get avatar URL
    NSString *avatarURL = [self.infoModel objectForKey:@"OwnerAvatar"];
    // Use SDWebImage to asynchronously load and cache avatar
    NSURL *url = [NSURL URLWithString:avatarURL];
    UIImage *placeholder = [UIImage imageNamed:@"account"];
    [avatarView sd_setImageWithURL:url
                  placeholderImage:placeholder
                           options:SDWebImageRetryFailed];
    [ownerTagView addSubview:avatarView];

    // Create username label
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.font = [UIFont systemFontOfSize:14];
    nameLabel.textColor = [UIColor darkGrayColor];
    nameLabel.text = value;
    [nameLabel sizeToFit];

    // Calculate total tag width
    CGFloat nameLabelWidth = nameLabel.frame.size.width;
    CGFloat tagWidth = 5 + 22 + 5 + nameLabelWidth + 8;
    CGFloat tagHeight = 26;

    // Set tag container size and position
    ownerTagView.frame = CGRectMake(availableWidth - tagWidth, (standardRowHeight - tagHeight) / 2, tagWidth, tagHeight);

    // Set username label position
    nameLabel.frame = CGRectMake(5 + 22 + 5, (tagHeight - nameLabel.frame.size.height) / 2, nameLabelWidth, nameLabel.frame.size.height);
    [ownerTagView addSubview:nameLabel];

    return ownerTagView;
}

// Toggle the info view visibility
- (void)toggleInfoView:(BOOL)show animated:(BOOL)animated {
    // Skip if already in the requested state
    if (show == self.infoVisible) return;
    
    // First update our internal state
    self.infoVisible = show;
    
    // Update gesture recognizers based on info visibility
    [self updateGestureRecognizersForInfoVisibility:show];
    
    // Get parent navigation controller and top view controller for controlling navigation bar and bottom UI
    UIViewController *parentVC = self.parentViewController;
    while (parentVC && ![parentVC isKindOfClass:[UINavigationController class]]) {
        parentVC = parentVC.parentViewController;
    }
    
    if ([parentVC isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navController = (UINavigationController *)parentVC;
        UIViewController *galleryVC = navController.topViewController;
        
        // When showing info panel
        if (show) {
            // Check if we're in dark mode (black background)
            BOOL isInDarkMode = [self.view.backgroundColor isEqual:[UIColor blackColor]];
            
            // If in dark mode, first transition to light mode
            if (isInDarkMode) {
                // First show navigation bar if hidden (will be hidden again after color transition)
                if (navController.navigationBar.hidden) {
                    [navController setNavigationBarHidden:NO animated:NO];
                    navController.navigationBar.alpha = 0.0;
                }
                
                // Animate background color transition
                [UIView animateWithDuration:0.15 animations:^{
                    // Change background to light gray
                    self.view.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
                    self.scrollView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
                    self.imageView.backgroundColor = [UIColor clearColor];
                    
                    // Fix status bar style for light mode
                    if (@available(iOS 13.0, *)) {
                        UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                        while (topVC.presentedViewController) {
                            topVC = topVC.presentedViewController;
                        }
                        
                        if ([topVC isKindOfClass:[UINavigationController class]]) {
                            UINavigationController *navVC = (UINavigationController *)topVC;
                            navVC.navigationBar.barStyle = UIBarStyleBlackTranslucent;
                            [navVC setNeedsStatusBarAppearanceUpdate];
                        }
                    } else {
                        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
                    }
                } completion:^(BOOL finished) {
                    // Now proceed with hiding the navigation bar with fade
                    [UIView animateWithDuration:0.15 animations:^{
                        navController.navigationBar.alpha = 0.0;
                    } completion:^(BOOL finished) {
                        [navController setNavigationBarHidden:YES animated:NO];
                    }];
                }];
            } else {
                // Normal behavior - add fade transition for hiding navigation bar
                [UIView animateWithDuration:0.15 animations:^{
                    navController.navigationBar.alpha = 0.0;
                } completion:^(BOOL finished) {
                    [navController setNavigationBarHidden:YES animated:NO];
                }];
            }
            
            if ([galleryVC isKindOfClass:NSClassFromString(@"SeafPhotoGalleryViewController")]) {
                @try {
                    UIView *thumbnailCollection = [galleryVC valueForKey:@"thumbnailCollection"];
                    UIView *toolbarView = [galleryVC valueForKey:@"toolbarView"];
                    
                    // Hide thumbnails immediately without animation
                    if (thumbnailCollection) {
                        thumbnailCollection.hidden = YES;
                        thumbnailCollection.alpha = 0.0;
                    }
                    
                    // Keep toolbar visible
                    if (toolbarView) {
                        toolbarView.hidden = NO;
                        toolbarView.alpha = 1.0;
                    }
                } @catch (NSException *exception) {
                    NSLog(@"Exception when accessing gallery properties: %@", exception);
                }
            }
        }
        // When hiding info panel, restore navigation bar and thumbnails later
        else {
            // Add fade transition for showing navigation bar
            [navController setNavigationBarHidden:NO animated:NO];
            navController.navigationBar.alpha = 0.0;
            [UIView animateWithDuration:0.15 animations:^{
                navController.navigationBar.alpha = 1.0;
            }];
            
            if ([galleryVC isKindOfClass:NSClassFromString(@"SeafPhotoGalleryViewController")]) {
                @try {
                    UIView *thumbnailCollection = [galleryVC valueForKey:@"thumbnailCollection"];
                    UIView *toolbarView = [galleryVC valueForKey:@"toolbarView"];
                    
                    // Keep toolbar visible
                    if (toolbarView) {
                        toolbarView.hidden = NO;
                        toolbarView.alpha = 1.0;
                    }
                    
                    // Keep thumbnails hidden until info panel animation completes
                    if (thumbnailCollection) {
                        thumbnailCollection.hidden = YES;
                        thumbnailCollection.alpha = 0.0;
                    }
                } @catch (NSException *exception) {
                    Debug(@"Exception when accessing gallery properties: %@", exception);
                }
            }
        }
    }
    
    // If we need to show the info view, make sure it's updated and visible
    if (show) {
        [self updateInfoView];
        self.infoView.hidden = NO;
    }
    
    // Get bounds for calculations - these won't change during animation
    CGRect bounds = self.view.bounds;
    CGFloat infoHeight = roundf(bounds.size.height * 0.6); // 3/5 of height for info view
    CGFloat scrollHeight = roundf(bounds.size.height * 0.4); // 2/5 of height for scroll view
    
    // For non-animated transitions
    if (!animated) {
        // Update info panel position immediately
        if (show) {
            // Slide info panel up to show 3/5 of screen
            self.infoView.frame = CGRectMake(0, scrollHeight, bounds.size.width, infoHeight);
        } else {
            // Slide info panel down off screen
            self.infoView.frame = CGRectMake(0, bounds.size.height, bounds.size.width, infoHeight);
        }
        
        // Update scroll view frame without animation
        [self updateScrollViewForInfoVisibility:show animated:NO];
        
        // Hide the info view if we're hiding it
        if (!show) {
            self.infoView.hidden = YES;
            [self showThumbnailCollectionAfterInfoHidden];
        }
        
        return;
    }
    
    // Save current state before animation
    CGPoint contentOffset = self.scrollView.contentOffset;
    CGFloat zoomScale = self.scrollView.zoomScale;
    
    // Calculate target frames
    CGRect infoTargetFrame = show ?
        CGRectMake(0, scrollHeight, bounds.size.width, infoHeight) :
        CGRectMake(0, bounds.size.height, bounds.size.width, infoHeight);
        
    // Calculate scroll view target frame
    CGRect targetScrollFrame;
    
    if (show) {
        // When showing info, calculate proper scroll view position
        CGFloat visibleAreaCenterY = scrollHeight / 2.0; // Center of top 2/5 area
        CGFloat yOffset = visibleAreaCenterY - (bounds.size.height / 2.0);
        targetScrollFrame = CGRectMake(0, yOffset, bounds.size.width, bounds.size.height);
    } else {
        // When hiding info, scroll view takes full screen
        targetScrollFrame = bounds;
    }
    
    // Animated version
    if (show) {
        // Position info view initially off-screen
        self.infoView.frame = CGRectMake(0, bounds.size.height, bounds.size.width, infoHeight);
        
        // Animate both the info panel and scroll view together
        [UIView animateWithDuration:0.2
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            // Slide info panel up
            self.infoView.frame = infoTargetFrame;
            
            // Move scroll view to target position
            self.scrollView.frame = targetScrollFrame;
            
            // Restore content offset and scale
            self.scrollView.contentOffset = contentOffset;
            self.scrollView.zoomScale = zoomScale;
            
            // Update image center with animation
            [self scrollViewDidZoom:self.scrollView];
        } completion:^(BOOL finished) {
            // Ensure content is properly centered after animation
            [self centerZoomedImageIfNeeded];
        }];
    } else {
        // Animate both info panel sliding down and scroll view moving back to full screen
        [UIView animateWithDuration:0.2
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
            // Slide info panel down
            self.infoView.frame = infoTargetFrame;
            
            // Move scroll view to target position
            self.scrollView.frame = targetScrollFrame;
            
            // Restore content offset and scale
            self.scrollView.contentOffset = contentOffset;
            self.scrollView.zoomScale = zoomScale;
            
            // Update image center with animation
            [self scrollViewDidZoom:self.scrollView];
        } completion:^(BOOL finished) {
            // After animation completes, hide the info view
            self.infoView.hidden = YES;
            
            // Ensure content is properly centered
            [self centerZoomedImageIfNeeded];
            
            // Show thumbnails after info panel is hidden
            [self showThumbnailCollectionAfterInfoHidden];
        }];
    }
}

// Helper method to update scroll view frame separately from info panel animation
- (void)updateScrollViewForInfoVisibility:(BOOL)infoVisible animated:(BOOL)animated {
    CGRect bounds = self.view.bounds;
    CGFloat scrollHeight = roundf(bounds.size.height * 0.4); // 2/5 of height for scroll view
    
    // Save current state
    CGPoint contentOffset = self.scrollView.contentOffset;
    CGFloat zoomScale = self.scrollView.zoomScale;
    
    // Calculate target frame
    CGRect targetFrame;
    
    if (infoVisible) {
        // Calculate the center point of the top 2/5 area - it should be at 1/5 of screen height from top
        CGFloat visibleAreaCenterY = scrollHeight / 2.0; // Center of top 2/5 area
        
        // Use negative y-offset to position the scroll view's center at the center of the visible area
        CGFloat yOffset = visibleAreaCenterY - (bounds.size.height / 2.0);
        targetFrame = CGRectMake(0, yOffset, bounds.size.width, bounds.size.height);
    } else {
        // When info is hidden, scroll view takes full screen
        targetFrame = bounds;
    }
    
    // Apply changes with or without animation
    if (animated) {
        [UIView animateWithDuration:0.2 animations:^{
            self.scrollView.frame = targetFrame;
            
            // Restore offset and scale
            self.scrollView.contentOffset = contentOffset;
            self.scrollView.zoomScale = zoomScale;
            
            // Update image center with animation
            [self scrollViewDidZoom:self.scrollView];
        } completion:^(BOOL finished) {
            // Ensure content is properly centered after animation
            [self centerZoomedImageIfNeeded];
        }];
    } else {
        // Apply changes immediately
        self.scrollView.frame = targetFrame;
        
        // Restore offset and scale
        self.scrollView.contentOffset = contentOffset;
        self.scrollView.zoomScale = zoomScale;
        
        // Center the content within the visible area
        [self centerZoomedImageIfNeeded];
    }
    
    // Force immediate layout update
    [self.scrollView setNeedsLayout];
    [self.scrollView layoutIfNeeded];
}

// Helper method to update frames based on info visibility - separate from animation
- (void)updateViewFramesForInfoVisibility:(BOOL)infoVisible {
    CGRect bounds = self.view.bounds;
    CGFloat infoHeight = roundf(bounds.size.height * 0.6); // 3/5 of height for info view
    CGFloat scrollHeight = roundf(bounds.size.height * 0.4); // 2/5 of height for scroll view
    
    // Update info panel position
    if (infoVisible) {
        self.infoView.frame = CGRectMake(0, scrollHeight, bounds.size.width, infoHeight);
    } else {
        self.infoView.frame = CGRectMake(0, bounds.size.height, bounds.size.width, infoHeight);
    }
    
    // Update scroll view separately - use NO for animation to avoid unwanted animations during layout updates
    [self updateScrollViewForInfoVisibility:infoVisible animated:NO];
}

// Show thumbnails after hiding info panel
- (void)showThumbnailCollectionAfterInfoHidden {
    UIViewController *parentVC = self.parentViewController;
    while (parentVC && ![parentVC isKindOfClass:[UINavigationController class]]) {
        parentVC = parentVC.parentViewController;
    }
    
    if ([parentVC isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navController = (UINavigationController *)parentVC;
        UIViewController *galleryVC = navController.topViewController;
        
        if ([galleryVC isKindOfClass:NSClassFromString(@"SeafPhotoGalleryViewController")]) {
            @try {
                UIView *thumbnailCollection = [galleryVC valueForKey:@"thumbnailCollection"];
                if (thumbnailCollection) {
                    // Add fade-in animation effect instead of showing immediately
                    thumbnailCollection.hidden = NO;
                    thumbnailCollection.alpha = 0.0;
                    
                    [UIView animateWithDuration:0.15
                                          delay:0.0
                                        options:UIViewAnimationOptionCurveEaseIn
                                     animations:^{
                        thumbnailCollection.alpha = 1.0;
                    } completion:nil];
                }
            } @catch (NSException *exception) {
                NSLog(@"Exception when accessing gallery properties: %@", exception);
            }
        }
    }
}

// Helper method to enable/disable gesture recognizers based on info visibility
- (void)updateGestureRecognizersForInfoVisibility:(BOOL)infoVisible {
    // When info is hidden, enable gestures for normal interaction
    self.tapGesture.enabled = !infoVisible;
    self.doubleTapGesture.enabled = !infoVisible;
}

// Helper method to center image after frame changes
- (void)centerZoomedImageIfNeeded {
    // Call scrollViewDidZoom to re-center the image with the updated frame
    [self scrollViewDidZoom:self.scrollView];
}

// Handle tap to toggle UI visibility
- (void)handleTap:(UITapGestureRecognizer *)gesture {
    // 获取父级导航控制器
    UIViewController *parentVC = self.parentViewController;
    while (parentVC && ![parentVC isKindOfClass:[UINavigationController class]]) {
        parentVC = parentVC.parentViewController;
    }
    
    if ([parentVC isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navController = (UINavigationController *)parentVC;
        
        // 切换导航栏可见性
        BOOL isHidden = navController.navigationBar.hidden;
        
        // Use fade transition instead of standard animation
        if (isHidden) {
            // Show navigation bar with fade in effect
            [navController setNavigationBarHidden:NO animated:NO];
            navController.navigationBar.alpha = 0.0;
            [UIView animateWithDuration:0.15 animations:^{
                navController.navigationBar.alpha = 1.0;
            }];
        } else {
            // Hide navigation bar with fade out effect
            [UIView animateWithDuration:0.15 animations:^{
                navController.navigationBar.alpha = 0.0;
            } completion:^(BOOL finished) {
                [navController setNavigationBarHidden:YES animated:NO];
            }];
        }
        
        // 查找 SeafPhotoGalleryViewController
        UIViewController *galleryVC = navController.topViewController;
        if ([galleryVC isKindOfClass:NSClassFromString(@"SeafPhotoGalleryViewController")]) {
            // 尝试获取并切换缩略图集合的可见性
            @try {
                UIView *thumbnailCollection = [galleryVC valueForKey:@"thumbnailCollection"];
                UIView *toolbarView = [galleryVC valueForKey:@"toolbarView"];
                
                if (isHidden) {
                    // 从隐藏状态恢复 - 先设置可见但透明，然后动画淡入
                    if (thumbnailCollection && [thumbnailCollection isKindOfClass:[UIView class]]) {
                        thumbnailCollection.hidden = NO;
                        thumbnailCollection.alpha = 0.0;
                    }
                    
                    if (toolbarView && [toolbarView isKindOfClass:[UIView class]]) {
                        toolbarView.hidden = NO;
                        toolbarView.alpha = 0.0;
                    }
                    
                    // 开始淡入动画，同时将背景色由黑色渐变为白色
                    [UIView animateWithDuration:0.15
                                          delay:0.05
                                        options:UIViewAnimationOptionCurveEaseIn
                                     animations:^{
                        // 恢复缩略图和工具栏的显示
                        if (thumbnailCollection) thumbnailCollection.alpha = 1.0;
                        if (toolbarView) toolbarView.alpha = 1.0;
                        
                        // 将背景色从黑色渐变为淡灰色
                        self.view.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
                        self.scrollView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
                        self.imageView.backgroundColor = [UIColor clearColor];
                    } completion:nil];
                    
                } else {
                    // 切换到隐藏状态 - 动画淡出然后设置为隐藏，同时将背景色由白色渐变为黑色
                    [UIView animateWithDuration:0.15
                                     animations:^{
                        // 隐藏缩略图和工具栏
                        if (thumbnailCollection) thumbnailCollection.alpha = 0.0;
                        if (toolbarView) toolbarView.alpha = 0.0;
                        
                        // 将背景色从灰色渐变为黑色
                        self.view.backgroundColor = [UIColor blackColor];
                        self.scrollView.backgroundColor = [UIColor blackColor];
                        self.imageView.backgroundColor = [UIColor clearColor];
                    } completion:^(BOOL finished) {
                        if (thumbnailCollection) thumbnailCollection.hidden = YES;
                        if (toolbarView) toolbarView.hidden = YES;
                    }];
                }
            } @catch (NSException *exception) {
                // 处理可能的异常，保持应用稳定
                NSLog(@"Exception when accessing gallery properties: %@", exception);
            }
        }
        
        // 设置状态栏样式 - 根据背景色调整状态栏样式
        if (@available(iOS 13.0, *)) {
            UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
            while (topVC.presentedViewController) {
                topVC = topVC.presentedViewController;
            }
            
            // 当背景是黑色时，状态栏应该是亮色的；当背景是白色时，状态栏应该是深色的
            if ([topVC isKindOfClass:[UINavigationController class]]) {
                UINavigationController *navVC = (UINavigationController *)topVC;
                navVC.navigationBar.barStyle = isHidden ? UIBarStyleBlackTranslucent : UIBarStyleBlack;
            }
            
            // 更新状态栏偏好
            [topVC setNeedsStatusBarAppearanceUpdate];
        } else {
            [[UIApplication sharedApplication] setStatusBarHidden:!isHidden withAnimation:UIStatusBarAnimationFade];
            [[UIApplication sharedApplication] setStatusBarStyle:isHidden ? UIStatusBarStyleDefault : UIStatusBarStyleLightContent animated:YES];
        }
    }
}

- (void)loadImage {
    Debug(@"[PhotoContent] loadImage called for %@, seafFile: %@, has ooid: %@", self.photoURL, self.seafFile.name, self.seafFile.ooid ? @"YES" : @"NO");
    
    // If seafFile is available, use it to load the image
    if (self.seafFile) {
        // Only show indicator if the file is NOT yet downloaded/cached (ooid is nil)
        if (![self.seafFile hasCache]) {
            [self showLoadingIndicator];
            Debug(@"[PhotoContent] File needs download, showing indicator: %@", self.seafFile.name);
            // If we have repoId and filePath, fetch file metadata from API (can happen concurrently)
            if (self.repoId && self.filePath) {
                [self fetchFileMetadata];
            }
            return;
        } else {
            // Add a loading indicator while we load the image (might be large)
            [self showLoadingIndicator];
            
            // File exists, proceed with loading
            [self.seafFile getImageWithCompletion:^(UIImage *image) {
                Debug(@"[PhotoContent] getImageWithCompletion callback for %@, image: %@", self.seafFile.name, image ? @"SUCCESS" : @"FAILED");
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Check if this view controller is still active and valid
                    if (!self.view.window) {
                        Debug(@"[PhotoContent] View is no longer visible, skipping image update for %@", self.seafFile.name);
                        [self hideLoadingIndicator];
                        return;
                    }
                    
                    if (image) {
                        // This prevents the brief flash of white/blank screen
                        self.imageView.image = image;
                        [self updateScrollViewContentSize];
                        Debug(@"[PhotoContent] Image set successfully for %@", self.seafFile.name);
                        
                        // If we have the file path, get the data to display EXIF info
                        if (self.seafFile.ooid) {
                            NSString *path = [SeafStorage.sharedObject documentPath:self.seafFile.ooid];
                            NSData *data = [NSData dataWithContentsOfFile:path];
                            if (data) {
                                [self displayExifData:data];
                            } else {
                                Debug(@"[PhotoContent] WARNING: Could not read file data for EXIF from path: %@", path);
                            }
                        }
                        // Explicitly hide indicator AFTER image is set
                        [self hideLoadingIndicator];
                        Debug(@"[PhotoContent] Image loading complete, indicator hidden for %@", self.seafFile.name);
                    } else {
                        Debug(@"[PhotoContent] Image loading failed for %@", self.seafFile.name);
                        self.imageView.image = [UIImage imageNamed:@"gallery_failed.png"];
                        [self clearExifDataView];
                        // Explicitly hide indicator even on failure
                        [self hideLoadingIndicator];
                    }
                });
            }];
            
            // Fetch metadata if needed (can happen concurrently)
            if (self.repoId && self.filePath) {
                [self fetchFileMetadata];
            }
            return;
        }
    }
    else {
        Debug(@"[PhotoContent] No SeafFile available to show image");
        self.imageView.image = [UIImage imageNamed:@"placeholder"];
        [self hideLoadingIndicator];
    }
}

// Add method to fetch file metadata from API
- (void)fetchFileMetadata {
    if (!self.repoId || !self.filePath) {
        NSLog(@"Cannot fetch file metadata: repoId or filePath is missing");
        return;
    }
    
    // Use the connection property instead of getting it from app delegate
    if (!self.connection || !self.connection.authorized) {
        NSLog(@"No valid connection available for API request");
        return;
    }
    
    // Build the API URL
    NSString *requestUrl = [NSString stringWithFormat:@"%@/repos/%@/file/detail/?p=%%2F%@", API_URL, self.repoId, [self.filePath escapedUrl]];
    NSLog(@"Fetching file metadata from URL: %@", requestUrl);
    
    // Use SeafConnection's sendRequest method
    [self.connection sendRequest:requestUrl
                    success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        // Handle success response
        if (!JSON) {
            NSLog(@"No data received from file metadata API");
            return;
        }
        
        // Log the response for debugging
        NSLog(@"File metadata response: %@", JSON);
        
        // Extract the needed information
        NSNumber *fileSize = JSON[@"size"];
        NSString *lastModified = JSON[@"last_modified"];
        NSString *lastModifierName = JSON[@"last_modifier_name"];
        NSString *lastModifierAvatar = JSON[@"last_modifier_avatar"]; // Avatar URL field
        
        // Create info model dictionary with the extracted data
        NSMutableDictionary *infoDict = [NSMutableDictionary dictionary];
        
        if (fileSize) {
            [infoDict setObject:[fileSize stringValue] forKey:@"Size"];
        }
        
        if (lastModified) {
            [infoDict setObject:lastModified forKey:@"Modified"];
        }
        
        if (lastModifierName) {
            [infoDict setObject:lastModifierName forKey:@"Owner"];
        }
        
        // If avatar URL exists, add it to the data model
        if (lastModifierAvatar) {
            [infoDict setObject:lastModifierAvatar forKey:@"OwnerAvatar"];
        }
        
        // Update the infoModel on the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            self.infoModel = infoDict;
            
            // Update the info view if it's visible
            if (self.infoVisible) {
                [self updateInfoView];
            }
        });
    }
    failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        NSLog(@"Error fetching file metadata: %@", error);
    }];
}

// Update the setRepoId:filePath: method to also accept a connection parameter
- (void)setRepoId:(NSString *)repoId filePath:(NSString *)filePath connection:(SeafConnection *)connection {
    _repoId = repoId;
    _filePath = filePath;
    _connection = connection;
    
    // If we already have the view loaded, fetch metadata
    if (self.isViewLoaded) {
        [self fetchFileMetadata];
    }
}

// Keep the existing method for backward compatibility
- (void)setRepoId:(NSString *)repoId filePath:(NSString *)filePath {
    [self setRepoId:repoId filePath:filePath connection:self.connection];
}

// Helper method to remove existing EXIF views
- (void)clearExifDataView {
     // Assign a specific tag or class to EXIF views for easy identification
     NSInteger exifSectionTag = 999; // Tag for the EXIF section container
     UIView *exifSectionView = [self.infoScrollView viewWithTag:exifSectionTag];
     if (exifSectionView) {
         [exifSectionView removeFromSuperview];
     }
}

// Method to extract and display EXIF data
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

    // Only proceed if we have some data to show
    if (!exifDict && !tiffDict) return;

    // --- Get Data ---
    NSString *cameraModel = tiffDict[(NSString *)kCGImagePropertyTIFFModel];
    NSString *dateTimeOriginal = exifDict[(NSString *)kCGImagePropertyExifDateTimeOriginal];
    NSNumber *pixelWidth = metadata[(NSString *)kCGImagePropertyPixelWidth];
    NSNumber *pixelHeight = metadata[(NSString *)kCGImagePropertyPixelHeight];
    NSNumber *focalLength = exifDict[(NSString *)kCGImagePropertyExifFocalLength];
    NSNumber *aperture = exifDict[(NSString *)kCGImagePropertyExifFNumber];
    NSNumber *exposure = exifDict[(NSString *)kCGImagePropertyExifExposureTime];

    // Get color space
    NSString *colorSpace = @"Unknown";
    // First try to read color space from EXIF dictionary
    NSNumber *exifColorSpaceVal = exifDict[(NSString *)kCGImagePropertyExifColorSpace];
    if (exifColorSpaceVal) {
        int cs = [exifColorSpaceVal intValue];
        switch (cs) {
            case 1:
                colorSpace = @"RGB";//sRGB
                break;
            case 2:
                colorSpace = @"RGB";//Adobe RGB
                break;
            case 65535:
                colorSpace = @"Uncalibrated";
                break;
            default:
                colorSpace = [NSString stringWithFormat:@"ColorSpace %d", cs];
                break;
        }
    } else {
        // Fallback to metadata ColorModel
        NSString *modelVal = metadata[(NSString *)kCGImagePropertyColorModel];
        if (modelVal) {
            colorSpace = modelVal;
        }
    }

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
    exifSectionContainer.tag = 999;
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
    if (cameraModel && cameraModel.length > 0) {
        modelRowHeight = [self createExifModelRow:cameraModel
                                         inView:modelBackgroundView
                                      yPosition:currentModelY
                                 availableWidth:availableWidth
                                      modelFont:modelFont
                                      textColor:[UIColor blackColor] // Use black for model
                                    cardPadding:cardPadding];
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

    // --- Row 2: Shooting Time & Dimensions (in detailsBackgroundView) ---
    CGFloat row2Height = 0;
    NSString *formattedTime = @"-";
    NSString *dimensionsString = @"-";

    if (dateTimeOriginal && dateTimeOriginal.length > 0) {
        NSDateFormatter *inFormatter = [[NSDateFormatter alloc] init];
        [inFormatter setDateFormat:@"yyyy:MM:dd HH:mm:ss"];
        NSDate *date = [inFormatter dateFromString:dateTimeOriginal];
        if (date) {
            NSDateFormatter *outFormatter = [[NSDateFormatter alloc] init];
            [outFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            formattedTime = [outFormatter stringFromDate:date];
        }
    }

    if (pixelWidth && pixelHeight) {
        dimensionsString = [NSString stringWithFormat:@"%@x%@", pixelWidth, pixelHeight];
    }

    row2Height = [self createExifTimeAndDimensionsRows:formattedTime
                                          dimensions:dimensionsString
                                              inView:detailsBackgroundView
                                           yPosition:currentDetailsY
                                      availableWidth:availableWidth
                                          mediumFont:mediumFont
                                           textColor:textColor
                                         cardPadding:cardPadding];

    currentDetailsY += row2Height + verticalSpacing * 1.5; // More space after this block

    // --- Separator Line (within detailsBackgroundView) ---
    UIView *separator1 = [[UIView alloc] initWithFrame:CGRectMake(0, currentDetailsY, availableWidth, 1.0 / [UIScreen mainScreen].scale)];
    separator1.backgroundColor = lightGrayColor;
    // Add to details background view
    [detailsBackgroundView addSubview:separator1];
    currentDetailsY += separator1.frame.size.height + verticalSpacing * 1.5; // Space after separator

    // --- Row 3: Details (RGB | Focal | EV | Aperture | Exposure) (in detailsBackgroundView) ---
    NSMutableArray *detailItems = [NSMutableArray array];

    // 1. Color Space
    [detailItems addObject:colorSpace];

    // 2. Focal Length
    NSString *focalString = @"-";
    if (focalLength) focalString = [NSString stringWithFormat:@"%@ mm", focalLength];
    [detailItems addObject:focalString];
    
    // 4. Aperture Number (FNumber)
    NSString *apertureNumberString = @"-";
    if (aperture) apertureNumberString = [NSString stringWithFormat:@"f/%.1f", aperture.doubleValue];
    [detailItems addObject:apertureNumberString];

    // 5. Exposure Time
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

    // Call helper to layout the detail row
    CGFloat detailRowHeight = [self layoutExifDetailRow:detailItems
                                                inView:detailsBackgroundView
                                             yPosition:currentDetailsY
                                        availableWidth:availableWidth
                                            smallFont:smallFont
                                            textColor:textColor
                                       lightGrayColor:lightGrayColor];

    currentDetailsY += detailRowHeight + cardPadding; // Add final padding at the bottom

    // Set details background height
    detailsBgFrame = detailsBackgroundView.frame;
    detailsBgFrame.size.height = currentDetailsY;
    detailsBackgroundView.frame = detailsBgFrame;
    
    // Set overall container height
    CGRect containerFrame = exifSectionContainer.frame;
    // Height is sum of model bg height, separator height, and details bg height
    containerFrame.size.height = modelBackgroundView.frame.size.height + separatorTop.frame.size.height + detailsBackgroundView.frame.size.height;
    exifSectionContainer.frame = containerFrame;

    // --- Update Scroll View Content Size ---
    CGFloat newContentHeight = CGRectGetMaxY(exifSectionContainer.frame) + outerPadding; // Use outer padding
    CGFloat minContentHeight = self.infoScrollView.bounds.size.height + 1;
    self.infoScrollView.contentSize = CGSizeMake(self.infoScrollView.bounds.size.width, MAX(newContentHeight, minContentHeight));
}

// Helper method to layout the EXIF detail row (Color Space, Focal, Aperture, Exposure)
- (CGFloat)layoutExifDetailRow:(NSArray<NSString *> *)detailItems
                        inView:(UIView *)parentView
                     yPosition:(CGFloat)yPosition
                availableWidth:(CGFloat)availableWidth
                     smallFont:(UIFont *)smallFont
                     textColor:(UIColor *)textColor
                lightGrayColor:(UIColor *)lightGrayColor
{
    if (detailItems.count == 0) return 0;

    NSMutableArray<UILabel *> *detailLabels = [NSMutableArray arrayWithCapacity:detailItems.count];
    for (NSString *itemText in detailItems) {
        [detailLabels addObject:[self createDetailLabel:itemText font:smallFont color:textColor]];
    }

    // Layout Detail Labels Horizontally - Divide the card width evenly
    CGFloat detailItemWidth = availableWidth / detailLabels.count; // Each item gets equal width
    CGFloat currentDetailX = 0; // Start layout from left edge
    CGFloat detailRowHeight = 0;

    for (int i = 0; i < detailLabels.count; i++) {
        UILabel *label = detailLabels[i];
        // Center the label within its allocated space
        CGFloat labelX = currentDetailX + (detailItemWidth - label.frame.size.width) / 2.0;
        label.frame = CGRectMake(labelX, yPosition, label.frame.size.width, label.frame.size.height);
        [parentView addSubview:label];
        detailRowHeight = MAX(detailRowHeight, label.frame.size.height); // Track max height for the row

        // Add vertical separator (except for the last item)
        if (i < detailLabels.count - 1) {
            UIView *vSeparator = [[UIView alloc] initWithFrame:CGRectMake(currentDetailX + detailItemWidth - (1.0 / [UIScreen mainScreen].scale) / 2.0,
                                                                        yPosition,
                                                                        1.0 / [UIScreen mainScreen].scale,
                                                                        label.frame.size.height)]; // Separator height matches label
            vSeparator.backgroundColor = lightGrayColor;
            [parentView addSubview:vSeparator];
        }
        currentDetailX += detailItemWidth;
    }

    // Adjust vertical position of labels and separators if heights varied significantly
     for (UIView *subview in parentView.subviews) {
         // Check if it's a label in the correct Y position range
         if ([subview isKindOfClass:[UILabel class]] && subview.frame.origin.y >= yPosition && subview.frame.origin.y < yPosition + detailRowHeight) {
             CGRect frame = subview.frame;
             frame.origin.y = yPosition + (detailRowHeight - frame.size.height) / 2.0; // Center vertically
             subview.frame = frame;
         // Check if it's a vertical separator in the correct Y position range
         } else if (![subview isKindOfClass:[UILabel class]] && subview.frame.origin.y >= yPosition && subview.frame.origin.y < yPosition + detailRowHeight) {
             // Check if it's one of our separators (basic check, might need refinement if other views exist)
             if (subview.frame.size.width < 2.0 && subview.backgroundColor == lightGrayColor) {
                 CGRect frame = subview.frame;
                 frame.size.height = detailRowHeight; // Match max label height
                 frame.origin.y = yPosition; // Align top with labels
                 subview.frame = frame;
             }
         }
     }

    return detailRowHeight;
}

// Helper method to create detail labels for the bottom row
- (UILabel *)createDetailLabel:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.font = font;
    label.textColor = color;
    label.text = text;
    label.textAlignment = NSTextAlignmentCenter;
    [label sizeToFit];
    return label;
}

// Update scroll view content size to match image size
- (void)updateScrollViewContentSize {
    if (!self.imageView.image) return;
    
    // When info panel is visible, make sure the image view remains centered in the visible portion
    if (self.infoVisible) {
        // Keep the image view filling the scroll view frame
        self.imageView.frame = self.scrollView.bounds;
        self.scrollView.zoomScale = 1.0;
        
        // Make sure the content is centered in the visible part
        [self scrollViewDidZoom:self.scrollView];
    } else {
        // For normal full-screen mode, just fill the scroll view
        self.imageView.frame = self.scrollView.bounds;
        self.scrollView.zoomScale = 1.0;
    }
}

// Update scroll view zoom scales
- (void)updateZoomScalesForSize:(CGSize)size {
    if (!self.imageView.image) return;
    
    // Reset minimum/maximum zoom levels
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 3.0;
    self.scrollView.zoomScale = 1.0;
    
    // Update image view size
    self.imageView.frame = CGRectMake(0, 0, size.width, size.height);
}

// Setter for infoModel that updates the view when it changes
- (void)setInfoModel:(NSDictionary *)infoModel {
    _infoModel = infoModel;
    // Update the standard info view section first
    [self updateInfoView];
}

#pragma mark - UIScrollViewDelegate
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    // Save current zoom scale
    CGFloat savedZoomScale = self.scrollView.zoomScale;
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // Reset zoom
        self.scrollView.zoomScale = 1.0;
        
        // Update zoom range and center
        [self updateZoomScalesForSize:size];
        [self scrollViewDidZoom:self.scrollView];
        
        // Refresh info view to adapt to new width
        if (self.infoVisible) {
            [self updateInfoView];
        }
        
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // Restore zoom scale
        if (savedZoomScale != 1.0) {
            self.scrollView.zoomScale = MIN(savedZoomScale, self.scrollView.maximumZoomScale);
        }
    }];
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    // Center image in scroll view as user zooms
    CGFloat offsetX = MAX((scrollView.bounds.size.width - scrollView.contentSize.width) * 0.5, 0.0);
    CGFloat offsetY = MAX((scrollView.bounds.size.height - scrollView.contentSize.height) * 0.5, 0.0);
    
    // If info panel is visible, we need to adjust vertical centering for the top 2/5 visible area
    if (self.infoVisible) {
        // Calculate the visible area height (2/5 of screen height)
        CGFloat visibleAreaHeight = self.view.bounds.size.height * 0.4; // 2/5 of screen
        CGFloat visibleAreaCenterY = visibleAreaHeight / 2.0; // Center point of visible area
        
        // When scrollView's frame is larger than its visible portion, we need special handling
        if (scrollView.contentSize.height < visibleAreaHeight) {
            // Calculate adjustment to center content in the visible area (top 2/5 of screen)
            // The scroll view's center is at visibleAreaCenterY (1/5 of screen height from top)
            CGFloat scrollViewCenterY = (scrollView.bounds.size.height / 2.0) + scrollView.frame.origin.y;
            offsetY = visibleAreaCenterY - scrollViewCenterY + (visibleAreaHeight - scrollView.contentSize.height) / 2.0;
        }
    }
    
    // Update image center position
    self.imageView.center = CGPointMake(scrollView.contentSize.width * 0.5 + offsetX,
                                       scrollView.contentSize.height * 0.5 + offsetY);
}

// Handle double tap gesture
- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    // Check if current zoom level is near minimum
    if (self.scrollView.zoomScale < self.scrollView.maximumZoomScale / 2) {
        // Zoom to maximum zoom level
        CGPoint location = [gesture locationInView:self.imageView];
        CGSize size = self.scrollView.bounds.size;
        
        CGRect zoomRect = CGRectMake(location.x - (size.width / 4),
                                     location.y - (size.height / 4),
                                     size.width / 2,
                                     size.height / 2);
        
        [self.scrollView zoomToRect:zoomRect animated:YES];
    } else {
        // Zoom to minimum zoom level
        [self.scrollView setZoomScale:self.scrollView.minimumZoomScale animated:YES];
    }
}

- (void)setInfoVisible:(BOOL)infoVisible {
    if (_infoVisible != infoVisible) {
        _infoVisible = infoVisible;
        [self updateGestureRecognizersForInfoVisibility:infoVisible];
    }
}

#pragma mark - Loading Indicator Methods

- (void)showLoadingIndicator {
    Debug(@"[PhotoContent] showLoadingIndicator called for %@", self.seafFile ? self.seafFile.name : self.photoURL);
    
    // Ensure this runs on the main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showLoadingIndicator];
        });
        return;
    }
    
    // Ensure indicator exists and is created if needed
    if (!self.activityIndicator || !self.progressLabel) {
        Debug(@"[PhotoContent] Creating loading indicators that were not initialized for %@", self.seafFile ? self.seafFile.name : @"unknown");
        [self setupLoadingIndicator];
    }
    
    // Only start animating if not already animating
    if (!self.activityIndicator.isAnimating) {
        [self.activityIndicator startAnimating];
        self.progressLabel.text = @"0%";
        self.progressLabel.hidden = NO;
        [self.view bringSubviewToFront:self.activityIndicator];
        [self.view bringSubviewToFront:self.progressLabel];
        Debug(@"[PhotoContent] Loading indicator now visible for %@", self.seafFile ? self.seafFile.name : self.photoURL);
    }
}

- (void)hideLoadingIndicator {
    Debug(@"[PhotoContent] hideLoadingIndicator called for %@", self.seafFile ? self.seafFile.name : self.photoURL);
    
    // Ensure this runs on the main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideLoadingIndicator];
        });
        return;
    }
    
    // Remove all indicators to ensure none are left behind
    [self cleanupAllLoadingIndicators];
    
    Debug(@"[PhotoContent] Loading indicators hidden and cleaned up for %@", self.seafFile ? self.seafFile.name : self.photoURL);
}

// More thorough cleanup of all loading indicators
- (void)cleanupAllLoadingIndicators {
    // Stop the main activity indicator if it exists
    if (self.activityIndicator && [self.activityIndicator isAnimating]) {
        [self.activityIndicator stopAnimating];
    }
    
    // Hide the main progress label if it exists
    if (self.progressLabel) {
        self.progressLabel.hidden = YES;
    }
    
    // Find and remove any other activity indicators or percentage labels that might exist
    for (UIView *subview in self.view.subviews) {
        // Check for any UIActivityIndicatorView
        if ([subview isKindOfClass:[UIActivityIndicatorView class]]) {
            UIActivityIndicatorView *indicator = (UIActivityIndicatorView *)subview;
            [indicator stopAnimating];
            
            // If it's not our main indicator, remove it
            if (indicator != self.activityIndicator) {
                Debug(@"[PhotoContent] Removing extra indicator: %@", indicator);
                [indicator removeFromSuperview];
            }
        }
        // Check for any UILabel with percentage text
        else if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            NSString *text = label.text;
            
            // If it's a percentage label and not our main one, remove it
            if (text && ([text hasSuffix:@"%"] || label.tag == 1002) && label != self.progressLabel) {
                Debug(@"[PhotoContent] Removing extra progress label: %@", label);
                [label removeFromSuperview];
            }
        }
    }
}

- (void)updateLoadingProgress:(float)progress {
    // Ensure this runs on the main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateLoadingProgress:progress];
        });
        return;
    }
    
    // Ensure we have loading indicators
    if (!self.activityIndicator || !self.progressLabel) {
        Debug(@"[PhotoContent] Creating loading indicators before updating progress for %@", self.seafFile ? self.seafFile.name : @"unknown");
        [self setupLoadingIndicator];
    }
    
    // Only update if we have valid indicators
    if (self.activityIndicator && self.progressLabel) {
        // Start animating if not already
        if (!self.activityIndicator.isAnimating) {
            [self.activityIndicator startAnimating];
            [self.view bringSubviewToFront:self.activityIndicator];
        }
        
        // Update text and ensure visible
        self.progressLabel.text = [NSString stringWithFormat:@"%.0f%%", progress * 100];
        self.progressLabel.hidden = NO;
        [self.view bringSubviewToFront:self.progressLabel];
        
        Debug(@"[PhotoContent] Updated progress to %.0f%% for %@", progress * 100, self.seafFile ? self.seafFile.name : self.photoURL);
    }
}

// Sets an error image to display when loading fails
- (void)showErrorImage {
    Debug(@"[PhotoContent] Showing error image for %@", self.seafFile ? self.seafFile.name : self.photoURL);
    
    // Ensure this runs on the main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showErrorImage];
        });
        return;
    }
    
    // Set the error image
    self.imageView.image = [UIImage imageNamed:@"gallery_failed.png"];
    
    // Update scroll view if needed
    [self updateScrollViewContentSize];
    
    // Clear any EXIF data
    [self clearExifDataView];
    
    // Make sure the loading indicator is hidden
    [self hideLoadingIndicator];
    
    Debug(@"[PhotoContent] Error image set and loading indicator hidden for %@", self.seafFile ? self.seafFile.name : self.photoURL);
}

// Ensure indicator remains centered during layout changes
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    // Re-center indicator and label
    self.activityIndicator.center = self.view.center;
    self.progressLabel.center = CGPointMake(self.view.center.x, self.view.center.y + self.activityIndicator.bounds.size.height / 2 + 25);

    // Update frames based on current state
    [self updateViewFramesForInfoVisibility:self.infoVisible];

    // Update scroll view and image view
    [self updateZoomScalesForSize:self.scrollView.bounds.size];
}

// New method to setup the loading indicator and progress label
- (void)setupLoadingIndicator {
    // First, remove any existing indicators to prevent duplicates
    [self removeExistingLoadingIndicators];
    
    // Activity Indicator
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.activityIndicator.hidesWhenStopped = YES;
    self.activityIndicator.center = self.view.center; // Center in the main view initially
    self.activityIndicator.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    self.activityIndicator.tag = 1001; // Tag for identification
    [self.view addSubview:self.activityIndicator]; // Add to main view, not scroll view

    // Progress Label
    self.progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 100, 40)];
    self.progressLabel.center = CGPointMake(self.view.center.x, self.view.center.y + self.activityIndicator.bounds.size.height / 2 + 25); // Position below indicator
    self.progressLabel.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    self.progressLabel.textColor = [UIColor grayColor]; // Changed text color to gray
    self.progressLabel.backgroundColor = [UIColor clearColor]; // Removed background color
    self.progressLabel.textAlignment = NSTextAlignmentCenter;
    self.progressLabel.font = [UIFont systemFontOfSize:14];
    self.progressLabel.layer.cornerRadius = 8.0;
    self.progressLabel.layer.masksToBounds = YES;
    self.progressLabel.hidden = YES; // Initially hidden
    self.progressLabel.tag = 1002; // Tag for identification
    [self.view addSubview:self.progressLabel];
    
    Debug(@"[PhotoContent] Setup new loading indicators for %@", self.seafFile ? self.seafFile.name : @"unknown");
}

// Helper method to remove any existing loading indicators
- (void)removeExistingLoadingIndicators {
    // Remove all activity indicators and progress labels from the view
    for (UIView *subview in self.view.subviews) {
        if ([subview isKindOfClass:[UIActivityIndicatorView class]] ||
            ([subview isKindOfClass:[UILabel class]] &&
             (subview.tag == 1002 || [[(UILabel *)subview text] hasSuffix:@"%"]))) {
            
            Debug(@"[PhotoContent] Removing existing indicator/label: %@", subview);
            [subview removeFromSuperview];
        }
    }
    
    // Clear references
    self.activityIndicator = nil;
    self.progressLabel = nil;
}

// Handle swipe down gesture on info view
- (void)handleInfoViewSwipeDown:(UISwipeGestureRecognizer *)gesture {
    // Only trigger if info scroll view is at the top
    if (self.infoScrollView.contentOffset.y <= 0) {
        // If we're at the top, hide the info panel
        [self notifyGalleryViewControllerToHideInfoPanel];
    }
}

// Track start of drag operation
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView == self.infoScrollView) {
        // Reset the tracking flag at the start of each drag operation
        self.draggedBeyondTopEdge = NO;
    }
}

// Detect scroll position for info scroll view
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.infoScrollView) {
        // If at the top and being pulled down, track the dragging progress
        if (scrollView.contentOffset.y < 0) {
            // The more negative the content offset, the more it's being pulled down
            CGFloat pullDistance = -scrollView.contentOffset.y;
            
            // Check if we're actively dragging (not just bouncing back)
            if (scrollView.dragging) {
                // Get the drag direction using the translation of the pan gesture
                CGPoint translation = [scrollView.panGestureRecognizer translationInView:self.view];
                
                // If pulled down more than a threshold and gesture is moving downward
                if (pullDistance > 40 && translation.y > 0) {
                    if (!self.draggedBeyondTopEdge) {
                        self.draggedBeyondTopEdge = YES;
                        [self notifyGalleryViewControllerToHideInfoPanel];
                    }
                }
            }
        }
    } else if (scrollView == self.scrollView) {
        // This is the main image scroll view
        // Center image in scroll view as user zooms
        [self scrollViewDidZoom:scrollView];
    }
}

// Detect when user finishes dragging the info scroll view down
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    // Check if this is the info scroll view
    if (scrollView == self.infoScrollView) {
        // If at the top and being pulled down, hide the info panel
        if (scrollView.contentOffset.y <= 0 && [scrollView.panGestureRecognizer translationInView:self.view].y > 10) {
            // Find the gallery view controller and notify it to hide the info panel
            [self notifyGalleryViewControllerToHideInfoPanel];
        }
    }
}

// Helper method to notify the gallery view controller to hide the info panel
- (void)notifyGalleryViewControllerToHideInfoPanel {
    UIViewController *parentVC = self.parentViewController;
    while (parentVC && ![parentVC isKindOfClass:NSClassFromString(@"SeafPhotoGalleryViewController")]) {
        parentVC = parentVC.parentViewController;
    }
    
    if (parentVC) {
        @try {
            // Try to call the handleSwipeDown method on the gallery view controller
            SEL handleSwipeDownSelector = NSSelectorFromString(@"handleSwipeDown:");
            if ([parentVC respondsToSelector:handleSwipeDownSelector]) {
                [parentVC performSelector:handleSwipeDownSelector withObject:nil];
            }
        } @catch (NSException *exception) {
            NSLog(@"Exception when trying to call handleSwipeDown: %@", exception);
        }
    }
}

// Add setter for connection property
- (void)setConnection:(SeafConnection *)connection {
    _connection = connection;
}

// Add setter method for seafFile
- (void)setSeafFile:(SeafFile *)seafFile {
    // If the same file, ignore
    if (_seafFile == seafFile) {
        return;
    }
    
    // Store previous loading state to determine if we need to update UI
    BOOL wasLoading = _seafFile && [_seafFile hasCache];
    BOOL willBeLoading = seafFile && ![seafFile hasCache];
    
    // Update the stored file
    _seafFile = seafFile;
    
    Debug(@"[PhotoContent] Setting seafFile: %@, ooid: %@",
          seafFile.name,
          seafFile.ooid ? seafFile.ooid : @"nil (needs download)");
    
    // Update loading indicator based on new file state
    if (wasLoading && !willBeLoading) {
        // File was loading but now has loaded - hide indicator
        Debug(@"[PhotoContent] File now loaded, hiding indicator");
        [self hideLoadingIndicator];
    }
    else if (!wasLoading && willBeLoading) {
        Debug(@"[PhotoContent] New file needs download, showing indicator");
        [self showLoadingIndicator];
    }
    
    // If view is loaded, reload image with the new file
    if (self.isViewLoaded) {
        [self loadImage];
    }
}

// Add cleanup when the view is about to disappear
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    if (self.activityIndicator) {
        Debug(@"[PhotoContent] Cleaning up indicators in viewWillDisappear for %@", self.seafFile ? self.seafFile.name : self.photoURL);
        [self cleanupAllLoadingIndicators];
    }
}

// Method to prepare the view controller for reuse (called from gallery when recycling)
- (void)prepareForReuse {
    Debug(@"[PhotoContent] Preparing for reuse %@", self.seafFile ? self.seafFile.name : @"unknown");
    
    // Cancel any ongoing image loading or download requests
    // Only if the image isn't already loaded
    if (!self.imageView.image || !self.seafFile || ![self.seafFile hasCache]) {
        [self cancelImageLoading];
    }
    
    // Clean up any existing UI elements
    [self cleanupAllLoadingIndicators];
    
    // Reset zoom scale
    if (self.scrollView) {
        self.scrollView.zoomScale = 1.0;
    }
    
    // Reset info view if needed
    if (self.infoVisible) {
        self.infoVisible = NO;
        self.infoView.hidden = YES;
    }
    
    Debug(@"[PhotoContent] View controller reset and ready for reuse");
}

// Cancel any ongoing image loading or download requests
- (void)cancelImageLoading {
    Debug(@"[PhotoContent] Canceling image loading for %@", self.seafFile ? self.seafFile.name : @"unknown");
    
    // Don't cancel if the image is already loaded and displayed
    if (self.imageView.image != nil && self.seafFile && [self.seafFile hasCache]) {
        Debug(@"[PhotoContent] Not canceling - image already displayed: %@", self.seafFile.name);
        // Still clean up any loading indicators
        [self cleanupAllLoadingIndicators];
        return;
    }
    // Cancel the SeafFile download task
    if (self.seafFile) {
        // Cancel file download
        [self.seafFile cancelDownload];
        
        // Clean up any ongoing requests or operations
        [self.seafFile setDelegate:nil];
    }
    
    // Clean up loading indicators
    [self cleanupAllLoadingIndicators];
    
    Debug(@"[PhotoContent] Image loading canceled for %@", self.seafFile ? self.seafFile.name : @"unknown");
}

// Release the memory of the loaded image
- (void)releaseImageMemory {
    Debug(@"[PhotoContent] Releasing image memory for %@", self.seafFile ? self.seafFile.name : @"unknown");
    
    // Clear the image data to free memory
    if (self.imageView) {
        self.imageView.image = nil;
    }
        
    Debug(@"[PhotoContent] Image memory released for %@", self.seafFile ? self.seafFile.name : @"unknown");
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    // Check if we're still part of the UIPageViewController's view controllers array
    UIViewController *parentVC = self.parentViewController;
    if ([parentVC isKindOfClass:[UIPageViewController class]]) {
        UIPageViewController *pageVC = (UIPageViewController *)parentVC;
        NSArray *viewControllers = pageVC.viewControllers;
        
        // Only cancel loading if this VC is no longer in the viewControllers array
        // AND we're at least 2 pages away from current view
        if (![viewControllers containsObject:self]) {
            NSInteger currentIndex = -1;
            NSInteger thisIndex = -1;
            
            // Try to get the photo gallery view controller
            UIViewController *galleryVC = pageVC.parentViewController;
            if ([galleryVC isKindOfClass:NSClassFromString(@"SeafPhotoGalleryViewController")]) {
                @try {
                    // Try to access the current index and the total array of view controllers
                    NSArray *allPhotoVCs = [galleryVC valueForKey:@"photoViewControllers"];
                    NSNumber *currentIdx = [galleryVC valueForKey:@"currentIndex"];
                    
                    if (allPhotoVCs && currentIdx) {
                        currentIndex = [currentIdx integerValue];
                        thisIndex = [allPhotoVCs indexOfObject:self];
                        
                        // Only cancel if we're at least 2 pages away from current
                        if (thisIndex != NSNotFound && abs((int)(thisIndex - currentIndex)) > 1) {
                            Debug(@"[PhotoContent] View far from current page, canceling loads: %@", self.seafFile.name);
                            [self cancelImageLoading];
                        } else {
                            Debug(@"[PhotoContent] View still near current page, keeping loads: %@", self.seafFile.name);
                        }
                    } else {
                        // Fallback to the old behavior if we can't get index info
                        Debug(@"[PhotoContent] Could not determine page indices, using default behavior for %@", self.seafFile.name);
                        [self cancelImageLoading];
                    }
                } @catch (NSException *exception) {
                    Debug(@"[PhotoContent] Exception when accessing gallery properties: %@", exception);
                    // Fallback to the old behavior
                    [self cancelImageLoading];
                }
            } else {
                // Not in a photo gallery, use old behavior
                Debug(@"[PhotoContent] View disappeared and no longer in page VC: %@", self.seafFile.name);
                [self cancelImageLoading];
            }
        }
    } else {
        // If we're not part of a page view controller at all, we should cancel any downloads
        Debug(@"[PhotoContent] View disappeared: %@", self.seafFile.name);
        [self cancelImageLoading];
    }
}

// Add a new method for preloading images
- (void)preloadImage {
    // Only preload if we have a valid seafFile with an ooid
    if (self.seafFile && [self.seafFile hasCache]) {
        
        if (!self.imageView.image) {
            Debug(@"[PhotoContent] Preloading image for %@", self.seafFile.name);
            
            // Load in background without affecting UI
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self.seafFile getImageWithCompletion:^(UIImage *image) {
                    if (image) {
                        // Store in memory but don't display yet
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (!self.imageView.image) {
                                self.imageView.image = image;
                                Debug(@"[PhotoContent] Image preloaded for %@", self.seafFile.name);
                            }
                        });
                    }
                }];
            });
        }
    }
}

// Add to viewWillAppear to ensure images are loaded when coming into view
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    UIViewController *parentVC = self.parentViewController;
    while (parentVC && ![parentVC isKindOfClass:[UINavigationController class]]) {
        parentVC = parentVC.parentViewController;
    }

    BOOL shouldBeBlackBackground = NO;
    if ([parentVC isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navController = (UINavigationController *)parentVC;
        // If the navigation bar is hidden, assume we are in the black background state triggered by handleTap:
        if (navController.navigationBarHidden) {
            shouldBeBlackBackground = YES;
        }
    }

    // Set background color immediately based on inferred state
    if (shouldBeBlackBackground) {
        // Ensure the view is in the 'dark mode' state
        self.view.backgroundColor = [UIColor blackColor];
        self.scrollView.backgroundColor = [UIColor blackColor];
        self.imageView.backgroundColor = [UIColor clearColor]; // Ensure image view is clear over black
    } else {
        // Ensure the view is in the 'light mode' state
        self.view.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        self.scrollView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        self.imageView.backgroundColor = [UIColor clearColor]; // Ensure image view is clear over light gray
    }
    // When a new view is about to appear during a transition, make sure layout is correct
    [self updateViewFramesForInfoVisibility:self.infoVisible];

    // Update info view if it's supposed to be visible
    if (self.infoVisible) {
        self.infoView.hidden = NO;
        [self updateInfoView];
    }

    // Make sure the image is loaded
    if (!self.imageView.image && self.seafFile) {
        Debug(@"[PhotoContent] Image not loaded yet in viewWillAppear, loading now: %@", self.seafFile.name);
        [self loadImage];
    }
}

// Helper method to create the EXIF Camera Model row
- (CGFloat)createExifModelRow:(NSString *)cameraModel
                       inView:(UIView *)parentView
                    yPosition:(CGFloat)yPosition
               availableWidth:(CGFloat)availableWidth
                    modelFont:(UIFont *)modelFont
                    textColor:(UIColor *)textColor
                  cardPadding:(CGFloat)cardPadding
{
    if (!cameraModel || cameraModel.length == 0) return 0;

    UILabel *modelLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardPadding, yPosition, availableWidth - 2 * cardPadding, 0)];
    modelLabel.font = modelFont;
    modelLabel.textColor = textColor;
    modelLabel.text = cameraModel;
    [modelLabel sizeToFit]; // Adjust height
    CGRect modelFrame = modelLabel.frame;
    modelFrame.size.width = availableWidth - 2 * cardPadding; // Ensure it takes full width
    modelLabel.frame = modelFrame;
    [parentView addSubview:modelLabel];

    // Return height including bottom padding
    return modelLabel.frame.size.height + cardPadding;
}

// Helper method to create the EXIF Time and Dimensions rows
- (CGFloat)createExifTimeAndDimensionsRows:(NSString *)formattedTime
                                dimensions:(NSString *)dimensionsString
                                    inView:(UIView *)parentView
                                 yPosition:(CGFloat)yPosition
                            availableWidth:(CGFloat)availableWidth
                                mediumFont:(UIFont *)mediumFont
                                 textColor:(UIColor *)textColor
                               cardPadding:(CGFloat)cardPadding
{
    CGFloat currentY = yPosition;
    CGFloat rowHeight = 0;

    // Time Label
    if (formattedTime && ![formattedTime isEqualToString:@"-"]) {
        UILabel *timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardPadding, currentY, availableWidth - 2 * cardPadding, 0)];
        timeLabel.font = mediumFont;
        timeLabel.textColor = textColor;
        timeLabel.text = [NSString stringWithFormat:@"Capture Time • %@", formattedTime];
        [timeLabel sizeToFit];
        CGRect timeFrame = timeLabel.frame;
        timeFrame.size.width = availableWidth - 2 * cardPadding;
        timeLabel.frame = timeFrame;
        [parentView addSubview:timeLabel];
        currentY += timeLabel.frame.size.height + cardPadding - 2; // Adjust spacing
        rowHeight += timeLabel.frame.size.height + cardPadding - 2;
    }

    // Dimensions Label
    if (dimensionsString && ![dimensionsString isEqualToString:@"-"]) {
        UILabel *dimLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardPadding, currentY, availableWidth - 2 * cardPadding, 0)];
        dimLabel.font = mediumFont;
        dimLabel.textColor = textColor;
        dimLabel.text = [NSString stringWithFormat:@"Dimensions • %@", dimensionsString];
        [dimLabel sizeToFit];
        CGRect dimFrame = dimLabel.frame;
        dimFrame.size.width = availableWidth - 2 * cardPadding;
        dimLabel.frame = dimFrame;
        [parentView addSubview:dimLabel];
        rowHeight += dimLabel.frame.size.height;
    }

    return rowHeight;
}

@end
