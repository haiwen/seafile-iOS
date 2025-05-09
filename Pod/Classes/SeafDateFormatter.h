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

/// Converts an ISO-8601 "last_modified" string (e.g., 2025‑05‑09T08:22:30+08:00)
/// into the legacy mtime format (seconds since January 1, 1970).
+ (long long)timestampFromLastModified:(NSString *)isoString;

@end
