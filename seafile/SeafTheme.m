//
//  SeafTheme.m
//  seafilePro
//

#import "SeafTheme.h"
#import "Constants.h"

NSString * const SeafThemeDidChangeNotification = @"SeafThemeDidChangeNotification";
NSString * const kSeafThemePreferenceKey = @"SeafThemePreference";
NSString * const kSeafThemePreferenceMigratedKey = @"SeafThemePreferenceMigrated";

// Mirrors the App Group storage key used by SeafGlobal/SeafStorage to persist
// configured accounts. Re-declared here to avoid pulling SeafGlobal/SeafStorage
// into SeafTheme (which is compiled into extensions under -fapplication-extension).
static NSString * const kSeafThemeAccountsKey = @"ACCOUNTS";

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

+ (void)migrateLegacyPreferenceIfNeeded
{
    NSUserDefaults *defaults = [self sharedDefaults];

    // Already migrated, nothing to do.
    if ([defaults boolForKey:kSeafThemePreferenceMigratedKey]) return;

    // User already has an explicit preference (unlikely on first run, but be safe):
    // honor it and just mark migration as done.
    if ([defaults objectForKey:kSeafThemePreferenceKey]) {
        [defaults setBool:YES forKey:kSeafThemePreferenceMigratedKey];
        return;
    }

    // Distinguish upgrade-from-legacy vs fresh install by the presence of any
    // configured account in the shared App Group storage. Legacy versions had
    // no dark mode, so pin those users to Light to avoid a surprise theme flip
    // after upgrading on a system in dark mode. Fresh installs default to
    // System (follow OS) and that value is written explicitly so extensions
    // can read a definitive preference too.
    NSArray *existingAccounts = [defaults objectForKey:kSeafThemeAccountsKey];
    BOOL isUpgradingUser = ([existingAccounts isKindOfClass:[NSArray class]] && existingAccounts.count > 0);
    SeafThemePreference initial = isUpgradingUser ? SeafThemePreferenceLight
                                                  : SeafThemePreferenceSystem;

    [defaults setObject:@(initial) forKey:kSeafThemePreferenceKey];
    [defaults setBool:YES forKey:kSeafThemePreferenceMigratedKey];
}

+ (void)applyPreferenceToWindow:(UIWindow *)window
{
    if (!window) return;
    window.overrideUserInterfaceStyle = [self userInterfaceStyleForPreference:[self currentPreference]];
}

+ (void)applyPreferenceToViewController:(UIViewController *)viewController
{
    if (!viewController) return;
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
}

+ (UIUserInterfaceStyle)userInterfaceStyleForPreference:(SeafThemePreference)preference
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
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}

#pragma mark - Brand / legacy tokens

+ (UIColor *)primaryBackgroundColor
{
    UIColor *light = [UIColor colorWithRed:247.0/255.0 green:247.0/255.0 blue:247.0/255.0 alpha:1.0];
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor systemGroupedBackgroundColor]
            : light;
    }];
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
    return [UIColor secondarySystemGroupedBackgroundColor];
}

+ (UIColor *)secondarySurface
{
    return [UIColor secondarySystemBackgroundColor];
}

+ (UIColor *)groupedSurface
{
    UIColor *light = [UIColor colorWithRed:247.0/255.0 green:247.0/255.0 blue:247.0/255.0 alpha:1.0];
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor systemGroupedBackgroundColor]
            : light;
    }];
}

+ (UIColor *)elevatedSurface
{
    return [UIColor tertiarySystemBackgroundColor];
}

#pragma mark - Text

+ (UIColor *)primaryText
{
    return [UIColor labelColor];
}

+ (UIColor *)secondaryText
{
    return [UIColor secondaryLabelColor];
}

+ (UIColor *)tertiaryText
{
    return [UIColor tertiaryLabelColor];
}

+ (UIColor *)operationText
{
    UIColor *light = [UIColor colorWithRed:60.0/255.0 green:60.0/255.0 blue:60.0/255.0 alpha:0.6];
    UIColor *dark  = [UIColor colorWithRed:60.0/255.0 green:60.0/255.0 blue:60.0/255.0 alpha:0.6];
    return [self dynamicColorWithLight:light dark:dark];
}

+ (UIColor *)galleryOperationText
{
    UIColor *light = [UIColor colorWithRed:102.0/255.0 green:102.0/255.0 blue:102.0/255.0 alpha:1.0];
    UIColor *dark  = [UIColor colorWithRed:255.0/255.0 green:255.0/255.0 blue:255.0/255.0 alpha:0.7];
    return [self dynamicColorWithLight:light dark:dark];
}

+ (UIColor *)placeholderText
{
    return [UIColor placeholderTextColor];
}

#pragma mark - Lines / fills

+ (UIColor *)separator
{
    return [UIColor separatorColor];
}

+ (UIColor *)fill
{
    return [UIColor systemFillColor];
}

@end
