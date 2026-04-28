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


#define SEAF_SEPARATOR_INSET UIEdgeInsetsMake(0, 25, 0, 15)
#define SEAF_CELL_CORNER 6

#define UIColorFromRGB(rgbValue) [UIColor \
    colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 \
    green:((float)((rgbValue & 0xFF00) >> 8))/255.0 \
    blue:((float)(rgbValue & 0xFF))/255.0 \
    alpha:1.0]


