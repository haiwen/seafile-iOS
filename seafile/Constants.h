//
//  Constants.h
//  Pods
//
//  Created by henry on 2025/3/11.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "SeafTheme.h"

#define SEAFILE_SUITE_NAME @"group.com.seafile.seafilePro"
#define APP_ID @"com.seafile.seafilePro"
#define SEAF_FILE_PROVIDER @"com.seafile.seafilePro.fileprovider"

#define kPrimaryBackgroundColor [SeafTheme primaryBackgroundColor]

#define ios7 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7)
#define ios8 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8)
#define ios9 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 9)
#define ios10 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 10)

#define HEADER_HEIGHT    24

#define BAR_COLOR        [SeafTheme barColor]
#define BAR_COLOR_ORANGE [SeafTheme barColorOrange]
#define HEADER_COLOR     [SeafTheme headerColor]

#define SEAF_COLOR_ORANGE [SeafTheme accentOrange]
#define SEAF_COLOR_LIGHT  [SeafTheme accentOrangeLight]

#define BOTTOM_TOOL_VIEW_DISABLE_COLOR [SeafTheme bottomToolDisabledColor]


// ── Card-style list unified UI constants ─────────────────────────────────────
#define SEAF_CARD_HORIZONTAL_PADDING  10.0   // Card background inset from cell edges
#define SEAF_CELL_CORNER              6      // Card corner radius

// ── Separator unified constants ──────────────────────────────────────────────
// Left inset = card padding (10) + inner offset (13) = 23
// Right inset = card padding (10) + inner offset (6) = 16
#define SEAF_SEPARATOR_LEFT_INSET     23.0
#define SEAF_SEPARATOR_RIGHT_INSET    16.0
#define SEAF_SEPARATOR_INSET UIEdgeInsetsMake(0, SEAF_SEPARATOR_LEFT_INSET, 0, SEAF_SEPARATOR_RIGHT_INSET)

// Native separator height: 1 physical pixel on any screen scale
#define SEAF_SEPARATOR_HEIGHT         (1.0 / [UIScreen mainScreen].scale)

#define UIColorFromRGB(rgbValue) [UIColor \
    colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 \
    green:((float)((rgbValue & 0xFF00) >> 8))/255.0 \
    blue:((float)(rgbValue & 0xFF))/255.0 \
    alpha:1.0]

// ── iOS 13+ Dynamic Color Compatibility ──────────────────────────────────────
// Uses a proper if (@available) guard that Clang recognises, avoiding
// -Wunguarded-availability-new warnings from the ternary @available pattern.

NS_INLINE UIColor * _Nonnull SeafDynamicColor(SEL dynamicSel, UIColor * _Nonnull fallback) {
    if (@available(iOS 13.0, *)) {
        UIColor *color = ((UIColor *(*)(id, SEL))[UIColor methodForSelector:dynamicSel])(UIColor.class, dynamicSel);
        if (color) return color;
    }
    return fallback;
}

#define SeafColor_SystemBackground \
    SeafDynamicColor(@selector(systemBackgroundColor), [UIColor whiteColor])

#define SeafColor_SecondarySystemBackground \
    SeafDynamicColor(@selector(secondarySystemBackgroundColor), [UIColor colorWithWhite:0.95 alpha:1])

#define SeafColor_Label \
    SeafDynamicColor(@selector(labelColor), [UIColor blackColor])

#define SeafColor_SecondaryLabel \
    SeafDynamicColor(@selector(secondaryLabelColor), [UIColor grayColor])

#define SeafColor_TertiaryLabel \
    SeafDynamicColor(@selector(tertiaryLabelColor), [UIColor lightGrayColor])

#define SeafColor_Separator \
    SeafDynamicColor(@selector(separatorColor), [UIColor lightGrayColor])

#define SeafColor_SystemGray \
    SeafDynamicColor(@selector(systemGrayColor), [UIColor grayColor])
