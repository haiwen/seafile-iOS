//
//  Constants.h
//  Pods
//
//  Created by henry on 2025/3/11.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define kPrimaryBackgroundColor [UIColor colorWithRed:247.0/255.0 green:247.0/255.0 blue:247.0/255.0 alpha:1.0]

#define ios7 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7)
#define ios8 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8)
#define ios9 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 9)
#define ios10 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 10)

#define HEADER_HEIGHT    24
#define BAR_COLOR        [UIColor colorWithRed:102.0/255.0 green:102.0/255.0 blue:102.0/255.0 alpha:1.0]
#define BAR_COLOR_ORANGE      [UIColor colorWithRed:240.0/256 green:128.0/256 blue:48.0/256 alpha:1.0]
#define HEADER_COLOR     [UIColor colorWithRed:238.0/256 green:238.0/256 blue:238.0/256 alpha:1.0]

#define SEAF_COLOR_DARK  [UIColor colorWithRed:236.0/256 green:114.0/256 blue:31.0/256 alpha:1.0]
#define SEAF_COLOR_LIGHT [UIColor colorWithRed:255.0/256 green:196.0/256 blue:115.0/256 alpha:1.0]

#define BOTTOM_TOOL_VIEW_DISABLE_COLOR     [UIColor colorWithWhite:0.85 alpha:1.0]


#define SEAF_SEPARATOR_INSET UIEdgeInsetsMake(0, 25, 0, 15)

#define UIColorFromRGB(rgbValue) [UIColor \
    colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 \
    green:((float)((rgbValue & 0xFF00) >> 8))/255.0 \
    blue:((float)(rgbValue & 0xFF))/255.0 \
    alpha:1.0]
