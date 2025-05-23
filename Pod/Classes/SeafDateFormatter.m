//
//  SeafDateFormatter.m
//  seafile
//
//  Created by Wang Wei on 8/30/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SeafDateFormatter.h"
#import "Debug.h"

#define unitFlags  (NSCalendarUnitYear | NSCalendarUnitMonth |  NSCalendarUnitDay)


@implementation SeafDateFormatter
static SeafDateFormatter *sharedLoaderSameDay = nil;
static SeafDateFormatter *sharedLoaderSameYear = nil;
static SeafDateFormatter *sharedLoader = nil;
static SeafDateFormatter *sharedLoaderUTC = nil;
static SeafDateFormatter *sharedLoaderChinese = nil;

+ (SeafDateFormatter *)sharedLoader
{
    if (sharedLoader == nil) {
        sharedLoader = [[SeafDateFormatter alloc] init];
        [sharedLoader setDateFormat:@"MMM d yyyy"];
    }
    return sharedLoader;
}

+ (SeafDateFormatter *)sharedLoaderSameDay
{
    if (sharedLoaderSameDay == nil) {
        sharedLoaderSameDay = [[SeafDateFormatter alloc] init];
        [sharedLoaderSameDay setDateFormat:@"h:mm a"];
    }
    return sharedLoaderSameDay;
}

+ (SeafDateFormatter *)sharedLoaderSameYear
{
    if (sharedLoaderSameYear == nil) {
        sharedLoaderSameYear = [[SeafDateFormatter alloc] init];
        [sharedLoaderSameYear setDateFormat:@"MMM d"];
    }
    return sharedLoaderSameYear;
}

+ (SeafDateFormatter *)sharedLoaderUTC {
    if (sharedLoaderUTC == nil) {
        sharedLoaderUTC = [[SeafDateFormatter alloc] init];
        [sharedLoaderUTC setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
        NSTimeZone *utcTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        [sharedLoaderUTC setTimeZone:utcTimeZone];
    }
    return sharedLoaderUTC;
}

+ (SeafDateFormatter *)sharedLoaderChinese
{
    if (sharedLoaderChinese == nil) {
        sharedLoaderChinese = [[SeafDateFormatter alloc] init];
        [sharedLoaderChinese setDateFormat:@"yyyy-MM-dd"];
    }
    return sharedLoaderChinese;
}

+ (NSString *)stringFromLongLong:(long long)time
{
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:time];
    NSCalendar* calendar = [NSCalendar currentCalendar];
    NSDateComponents* comp1 = [calendar components:unitFlags fromDate:date];
    NSDateComponents* comp2 = [calendar components:unitFlags fromDate:[NSDate date]];
    BOOL sameYear = [comp1 year] == [comp2 year];
    BOOL sameDay = sameYear &&  ([comp1 month] == [comp2 month]) && ([comp1 day]  == [comp2 day]);
    
    // Check if system language is Chinese
    BOOL isChinese = [[[NSLocale preferredLanguages] firstObject] hasPrefix:@"zh"];
    
    if (isChinese && !sameDay) {
        // Use Chinese date format for Chinese locale
        return [[SeafDateFormatter sharedLoaderChinese] stringFromDate:date];
    }
    
    if (sameDay)
        return [[SeafDateFormatter sharedLoaderSameDay] stringFromDate:date];
    else if(sameYear)
        return [[SeafDateFormatter sharedLoaderSameYear] stringFromDate:date];
    else
        return [[SeafDateFormatter sharedLoader] stringFromDate:date];
}

+(NSString *)compareGMTTimeWithNow:(NSString *)gmtTimeStr {
    NSDate *dateFormatted = [[SeafDateFormatter sharedLoaderUTC] dateFromString:gmtTimeStr];
    NSTimeInterval timeInterval = [[NSDate date] timeIntervalSinceDate:dateFormatted];
    
    double minutes = timeInterval / 60;
    double hours = minutes / 60;
    double days = hours / 24;
    double months = days / 30;
    double years = months / 12;
    
    if (minutes < 1.0) {
        return NSLocalizedString(@"a few seconds ago", @"Seafile");
    } else if (minutes < 1.5) {
        return NSLocalizedString(@"a minute ago", @"Seafile");
    } else if (minutes < 60.0) {
        return [NSString stringWithFormat:NSLocalizedString(@"%ld minutes ago", @"Seafile"), lround(minutes)];
    } else if (hours < 2.0) {
        return [NSString stringWithFormat:NSLocalizedString(@"an hour ago", @"Seafile")];
    } else if (hours < 24.0) {
        return [NSString stringWithFormat:NSLocalizedString(@"%ld hours ago", @"Seafile"), lround(hours)];
    } else if (days < 1.5) {
        return NSLocalizedString(@"a day ago", @"Seafile");
    } else if (days < 30.0) {
        return [NSString stringWithFormat:NSLocalizedString(@"%ld days ago", @"Seafile"), lround(days)];
    } else if (months < 1.5) {
        return [NSString stringWithFormat:NSLocalizedString(@"a month ago", @"Seafile")];
    } else if (months < 12.0) {
        return [NSString stringWithFormat:NSLocalizedString(@"%ld months ago", @"Seafile"), lround(months)];
    } else if (years < 1.5) {
        return [NSString stringWithFormat:NSLocalizedString(@"a year ago", @"Seafile")];
    } else {
        return [NSString stringWithFormat:NSLocalizedString(@"%ld years ago", @"Seafile"), lround(years)];
    }
}

+ (long long)timestampFromLastModified:(NSString *)isoString
{
    if (!isoString || (id)isoString == [NSNull null])
        return 0;

    NSDate *date = nil;

    // On iOS 10 and above, prefer using the system's built-in ISO‑8601 parser
    if (@available(iOS 10.0, *)) {
        static NSISO8601DateFormatter *isoFormatter;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            isoFormatter = [[NSISO8601DateFormatter alloc] init];
            isoFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        });
        date = [isoFormatter dateFromString:isoString];
    }

    return date ? (long long)round([date timeIntervalSince1970]) : 0;
}

@end
