//
//  Debug.h
//  seafile
//
//  Created by Wang Wei on 10/8/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>


#define API_URL  @"/api2"
#if DEBUG
#define Debug(fmt, args...) NSLog(@"#%d %s:" fmt, __LINE__, __FUNCTION__, ##args)
#else
#define Debug(fmt, args...) do{}while(0)
#endif

#define Warning(fmt, args...) NSLog(@"#%d %s:[WARNING]" fmt, __LINE__, __FUNCTION__, ##args)

static inline BOOL IsIpad()
{
    return ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad);
}

#define ios7 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7)

/* Additional strings for agi18n */
#define STR_1 NSLocalizedString(@"Release to refresh...", @"Release to refresh status")
#define STR_2 NSLocalizedString(@"Pull down to refresh...", @"Pull down to refresh status")
#define STR_3 NSLocalizedString(@"Loading...", @"Loading Status")
#define STR_4 NSLocalizedString(@"Last Updated: %@", nil)
#define STR_5 NSLocalizedString(@"SEAFILE_LOC_KEY_FORMAT", @"Seafile push notification message")
#define STR_6 NSLocalizedString(@"Send", nil)

