//
//  Debug.h
//  seafile
//
//  Created by Wang Wei on 10/8/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

#define APP_NAME @"luckycloud"


#define API_URL  @"/api2"
#define API_URL_V21  @"/api/v2.1"

#if DEBUG
#define Debug(fmt, args...) NSLog(@"#%d %s %@:" fmt, __LINE__, __FUNCTION__, [NSThread currentThread], ##args)
#else
#define Debug(fmt, args...) do{}while(0)
#endif

#define Info(fmt, args...) NSLog(@"#%d %s %@:" fmt, __LINE__, __FUNCTION__, [NSThread currentThread], ##args)

#define Warning(fmt, args...) NSLog(@"#%d %s:[WARNING]" fmt, __LINE__, __FUNCTION__, ##args)

#define STR_CANCEL NSLocalizedString(@"Cancel", @"Seafile")
static inline BOOL IsIpad()
{
    return ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad);
}

static inline NSString *actionSheetCancelTitle()
{
    return IsIpad() ? nil : STR_CANCEL;
}

#define ios7 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7)
#define ios8 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8)
#define ios9 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 9)
#define ios10 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 10)

#define HEADER_HEIGHT    24
#define BAR_COLOR        [UIColor colorWithRed:240.0/256 green:128.0/256 blue:48.0/256 alpha:1.0]
#define HEADER_COLOR     [UIColor colorWithRed:238.0/256 green:238.0/256 blue:238.0/256 alpha:1.0]

#define SEAF_COLOR_DARK  [UIColor colorWithRed:101.0/255.0 green:191.0/255.0 blue:42.0/255.0 alpha:1.0]
#define SEAF_COLOR_LIGHT [UIColor colorWithRed:255.0/256 green:196.0/256 blue:115.0/256 alpha:1.0]

static inline NSBundle *SeafileBundle() {
    return [NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"Seafile" ofType:@"bundle"]];
}
