//
//  SeafTheme.m
//  seafilePro
//

#import "SeafTheme.h"
#import "Constants.h"

NSString * const SeafThemeDidChangeNotification = @"SeafThemeDidChangeNotification";
NSString * const kSeafThemePreferenceKey = @"SeafThemePreference";

@implementation SeafTheme

#pragma mark - Preference

+ (NSUserDefaults *)sharedDefaults
{
    static NSUserDefaults *defaults;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaults = [[NSUserDefaults alloc] initWithSuiteName:SEAFILE_SUITE_NAME];
    });
    return defaults;
}

+ (SeafThemePreference)currentPreference
{
    NSNumber *stored = [[self sharedDefaults] objectForKey:kSeafThemePreferenceKey];
    if (!stored) return SeafThemePreferenceSystem;
    NSInteger value = [stored integerValue];
    if (value < SeafThemePreferenceSystem || value > SeafThemePreferenceDark) {
        return SeafThemePreferenceSystem;
    }
    return (SeafThemePreference)value;
}

+ (void)setPreference:(SeafThemePreference)preference
{
    [[self sharedDefaults] setObject:@(preference) forKey:kSeafThemePreferenceKey];
    // Observers (AppDelegate in the main app) are responsible for applying the preference
    // to their window. Intentionally avoid +sharedApplication here so SeafTheme.m stays
    // compilable under -fapplication-extension.
    [[NSNotificationCenter defaultCenter] postNotificationName:SeafThemeDidChangeNotification object:nil];
}

+ (void)applyPreferenceToWindow:(UIWindow *)window
{
    if (!window) return;
    if (@available(iOS 13.0, *)) {
        window.overrideUserInterfaceStyle = [self userInterfaceStyleForPreference:[self currentPreference]];
    }
}

+ (void)applyPreferenceToViewController:(UIViewController *)viewController
{
    if (!viewController) return;
    if (@available(iOS 13.0, *)) {
        // Extensions: when the main app has no stored preference (fresh install or
        // cleared app-group defaults), fall back to Light instead of following the
        // host so share/action UIs match pre-dark-mode behavior.
        NSNumber *stored = [[self sharedDefaults] objectForKey:kSeafThemePreferenceKey];
        UIUserInterfaceStyle style = stored
            ? [self userInterfaceStyleForPreference:[self currentPreference]]
            : UIUserInterfaceStyleLight;
        viewController.overrideUserInterfaceStyle = style;
        if (viewController.navigationController) {
            viewController.navigationController.overrideUserInterfaceStyle = style;
        }
    } else {
        // Pre-iOS 13: force Light to preserve pre-dark-mode behavior.
        // overrideUserInterfaceStyle is unavailable; no-op is effectively Light since we only ship Light assets.
    }
}

+ (UIUserInterfaceStyle)userInterfaceStyleForPreference:(SeafThemePreference)preference API_AVAILABLE(ios(13.0))
{
    switch (preference) {
        case SeafThemePreferenceLight: return UIUserInterfaceStyleLight;
        case SeafThemePreferenceDark:  return UIUserInterfaceStyleDark;
        case SeafThemePreferenceSystem:
        default:                       return UIUserInterfaceStyleUnspecified;
    }
}

#pragma mark - Dynamic color helper

+ (UIColor *)dynamicColorWithLight:(UIColor *)light dark:(UIColor *)dark
{
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
        }];
    }
    return light;
}

#pragma mark - Brand / legacy tokens

+ (UIColor *)primaryBackgroundColor
{
    UIColor *light = [UIColor colorWithRed:247.0/255.0 green:247.0/255.0 blue:247.0/255.0 alpha:1.0];
    UIColor *dark  = [UIColor colorWithRed: 28.0/255.0 green: 28.0/255.0 blue: 30.0/255.0 alpha:1.0];
    return [self dynamicColorWithLight:light dark:dark];
}

+ (UIColor *)barColor
{
    UIColor *light = [UIColor colorWithRed:102.0/255.0 green:102.0/255.0 blue:102.0/255.0 alpha:1.0];
    UIColor *dark  = [UIColor colorWithRed:170.0/255.0 green:170.0/255.0 blue:170.0/255.0 alpha:1.0];
    return [self dynamicColorWithLight:light dark:dark];
}

+ (UIColor *)barColorOrange
{
    return [UIColor colorWithRed:240.0/256.0 green:128.0/256.0 blue:48.0/256.0 alpha:1.0];
}

+ (UIColor *)headerColor
{
    UIColor *light = [UIColor colorWithRed:238.0/256.0 green:238.0/256.0 blue:238.0/256.0 alpha:1.0];
    UIColor *dark  = [UIColor colorWithRed: 44.0/255.0 green: 44.0/255.0 blue: 46.0/255.0 alpha:1.0];
    return [self dynamicColorWithLight:light dark:dark];
}

+ (UIColor *)accentOrange
{
    return [UIColor colorWithRed:236.0/256.0 green:114.0/256.0 blue:31.0/256.0 alpha:1.0];
}

+ (UIColor *)accentOrangeLight
{
    return [UIColor colorWithRed:255.0/256.0 green:196.0/256.0 blue:115.0/256.0 alpha:1.0];
}

+ (UIColor *)bottomToolDisabledColor
{
    UIColor *light = [UIColor colorWithWhite:0.85 alpha:1.0];
    UIColor *dark  = [UIColor colorWithWhite:0.30 alpha:1.0];
    return [self dynamicColorWithLight:light dark:dark];
}

#pragma mark - Surfaces

+ (UIColor *)primarySurface
{
    if (@available(iOS 13.0, *)) return [UIColor systemBackgroundColor];
    return [UIColor whiteColor];
}

+ (UIColor *)secondarySurface
{
    if (@available(iOS 13.0, *)) return [UIColor secondarySystemBackgroundColor];
    return [UIColor colorWithRed:247.0/255.0 green:247.0/255.0 blue:247.0/255.0 alpha:1.0];
}

+ (UIColor *)groupedSurface
{
    UIColor *light = [UIColor colorWithRed:247.0/255.0 green:247.0/255.0 blue:247.0/255.0 alpha:1.0];
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor systemGroupedBackgroundColor]
                : light;
        }];
    }
    return light;
}

+ (UIColor *)elevatedSurface
{
    if (@available(iOS 13.0, *)) return [UIColor tertiarySystemBackgroundColor];
    return [UIColor whiteColor];
}

#pragma mark - Text

+ (UIColor *)primaryText
{
    if (@available(iOS 13.0, *)) return [UIColor labelColor];
    return [UIColor blackColor];
}

+ (UIColor *)secondaryText
{
    if (@available(iOS 13.0, *)) return [UIColor secondaryLabelColor];
    return [UIColor darkGrayColor];
}

+ (UIColor *)tertiaryText
{
    if (@available(iOS 13.0, *)) return [UIColor tertiaryLabelColor];
    return [UIColor lightGrayColor];
}

+ (UIColor *)placeholderText
{
    if (@available(iOS 13.0, *)) return [UIColor placeholderTextColor];
    return [UIColor lightGrayColor];
}

#pragma mark - Lines / fills

+ (UIColor *)separator
{
    if (@available(iOS 13.0, *)) return [UIColor separatorColor];
    return [UIColor colorWithWhite:0.85 alpha:1.0];
}

+ (UIColor *)fill
{
    if (@available(iOS 13.0, *)) return [UIColor systemFillColor];
    return [UIColor colorWithWhite:0.90 alpha:1.0];
}

@end
