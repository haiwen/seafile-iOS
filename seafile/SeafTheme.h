//
//  SeafTheme.h
//  seafilePro
//
//  Central theme helper: semantic color tokens + user-selected Light/Dark/System preference.
//  iOS 13+ returns dynamic colors; pre-iOS 13 returns the existing static light-mode colors.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SeafThemePreference) {
    SeafThemePreferenceSystem = 0,
    SeafThemePreferenceLight  = 1,
    SeafThemePreferenceDark   = 2,
};

extern NSString * const SeafThemeDidChangeNotification;
extern NSString * const kSeafThemePreferenceKey;

@interface SeafTheme : NSObject

#pragma mark - Preference

+ (SeafThemePreference)currentPreference;
+ (void)setPreference:(SeafThemePreference)preference;
+ (void)applyPreferenceToWindow:(nullable UIWindow *)window;
+ (void)applyPreferenceToViewController:(nullable UIViewController *)viewController;

#pragma mark - Semantic color tokens

// Brand / legacy macro replacements
+ (UIColor *)primaryBackgroundColor;
+ (UIColor *)barColor;
+ (UIColor *)barColorOrange;
+ (UIColor *)headerColor;
+ (UIColor *)accentOrange;
+ (UIColor *)accentOrangeLight;
+ (UIColor *)bottomToolDisabledColor;

// Surfaces
+ (UIColor *)primarySurface;
+ (UIColor *)secondarySurface;
+ (UIColor *)groupedSurface;
+ (UIColor *)elevatedSurface;

// Text
+ (UIColor *)primaryText;
+ (UIColor *)secondaryText;
+ (UIColor *)tertiaryText;
+ (UIColor *)placeholderText;

// Lines / fills
+ (UIColor *)separator;
+ (UIColor *)fill;

@end

NS_ASSUME_NONNULL_END
