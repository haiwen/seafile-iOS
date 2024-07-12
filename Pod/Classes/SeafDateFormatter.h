//
//  SeafDateFormatter.h
//  seafile
//
//  Created by Wang Wei on 8/30/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SeafDateFormatter : NSDateFormatter

/**
 * Converts a timestamp to a more readable string based on its temporal distance from the current date.
 * @param time A long long timestamp value representing a date.
 * @return A formatted string representing the date in a human-readable form based on its proximity to now.
 */
+ (NSString *)stringFromLongLong:(long long)time;

/**
 * Compares a GMT time string to the current time and returns a string describing how long ago it was.
 * @param gmtTimeStr A string representing a date in GMT time format.
 * @return A localized string describing how long ago the date represented by gmtTimeStr was.
 */
+ (NSString *)compareGMTTimeWithNow:(NSString *)gmtTimeStr;

@end
