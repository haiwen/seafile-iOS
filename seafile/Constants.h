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

// ── Dynamic system colors ────────────────────────────────────────────────────

#define SeafColor_SystemBackground          [UIColor systemBackgroundColor]
#define SeafColor_SecondarySystemBackground [UIColor secondarySystemBackgroundColor]
#define SeafColor_Label                     [UIColor labelColor]
#define SeafColor_SecondaryLabel            [UIColor secondaryLabelColor]
#define SeafColor_TertiaryLabel             [UIColor tertiaryLabelColor]
#define SeafColor_Separator                 [UIColor separatorColor]
#define SeafColor_SystemGray                [UIColor systemGrayColor]
