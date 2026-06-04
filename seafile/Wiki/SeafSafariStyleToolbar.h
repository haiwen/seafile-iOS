//
//  SeafSafariStyleToolbar.h
//  seafile
//
//  Safari-style floating toolbar for WebView pages.
//  Transliterated from STBSafariStyleToolbar.swift (SeaTable project).
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Safari iOS-style liquid glass floating toolbar.
/// Contains: circular back button, center title capsule (with refresh button + progress bar), more button.
@interface SeafSafariStyleToolbar : UIView

#pragma mark - Callbacks

/// Tapped back button (exit current page)
@property (nonatomic, copy, nullable) void (^onBackTapped)(void);
/// Tapped refresh button
@property (nonatomic, copy, nullable) void (^onRefreshTapped)(void);
/// Tapped more button
@property (nonatomic, copy, nullable) void (^onMoreTapped)(void);
/// Tapped title area
@property (nonatomic, copy, nullable) void (^onTitleTapped)(void);

#pragma mark - Public Methods

/// Update the displayed title
- (void)updateTitle:(nullable NSString *)title;

/// Update loading progress (0.0 ~ 1.0). Automatically fades out when >= 1.0.
- (void)updateProgress:(float)progress;

/// Set the progress bar tint color
- (void)setProgressTintColor:(UIColor *)color;

/// Show the toolbar with optional animation
- (void)showAnimated:(BOOL)animated;

/// Hide the toolbar with optional animation
- (void)hideAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
