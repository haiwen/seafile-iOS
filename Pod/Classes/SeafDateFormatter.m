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

+ (NSString *)stringFromLongLong:(long long)time
{
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:time];
    NSCalendar* calendar = [NSCalendar currentCalendar];
    NSDateComponents* comp1 = [calendar components:unitFlags fromDate:date];
    NSDateComponents* comp2 = [calendar components:unitFlags fromDate:[NSDate date]];
    BOOL sameYear = [comp1 year] == [comp2 year];
    BOOL sameDay = sameYear &&  ([comp1 month] == [comp2 month]) && ([comp1 day]  == [comp2 day]);
    if (sameDay)
        return [[SeafDateFormatter sharedLoaderSameDay] stringFromDate:date];
    else if(sameYear)
        return [[SeafDateFormatter sharedLoaderSameYear] stringFromDate:date];
    else
        return [[SeafDateFormatter sharedLoader] stringFromDate:date];
}

+(NSString *)compareCurrentFromGMTDate:(NSString *)timeStr {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
    NSTimeZone *localTimeZone = [NSTimeZone localTimeZone];
    [dateFormatter setTimeZone:localTimeZone];
    NSDate *dateFormatted = [dateFormatter dateFromString:timeStr];

    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSDate *timeDate = [dateFormatter dateFromString:[dateFormatter stringFromDate:dateFormatted]];
    NSDate *currentDate = [NSDate date];
    
    NSTimeInterval timeInterval = [currentDate timeIntervalSinceDate:timeDate];
    long temp = 0;
    NSString *result;
    if (timeInterval/60 < 1) {
        result = NSLocalizedString(@"a few seconds ago", @"Seafile");
    } else if (timeInterval/60 == 1) {
        result = NSLocalizedString(@"a minute ago", @"Seafile");
    } else if ((temp = timeInterval/60) < 60 ) {
        result = [NSString stringWithFormat:NSLocalizedString(@"%ld minutes ago", @"Seafile"), temp];
    } else if ((temp = timeInterval/60) == 60) {
        result = [NSString stringWithFormat:NSLocalizedString(@"an hour ago", @"Seafile"), temp];
    } else if ((temp = timeInterval/3600) < 24 ) {
        result = [NSString stringWithFormat:NSLocalizedString(@"%ld hours ago", @"Seafile"), temp];
    } else if ((temp = timeInterval/3600) == 24 ) {
        result = NSLocalizedString(@"a day ago", @"Seafile");
    } else if((temp = timeInterval/(3600*24)) < 30 ) {
        result = [NSString stringWithFormat:NSLocalizedString(@"%ld days ago", @"Seafile"), temp];
    } else if((temp = timeInterval/(3600*24)) == 30 ) {
        result = [NSString stringWithFormat:NSLocalizedString(@"a month ago", @"Seafile"), temp];
    } else if((temp = timeInterval/(3600*24*30)) < 12 ) {
        result = [NSString stringWithFormat:NSLocalizedString(@"%ld months ago", @"Seafile"), temp];
    } else if((temp = timeInterval/(3600*24*30)) == 12 ) {
        result = [NSString stringWithFormat:NSLocalizedString(@"a year ago", @"Seafile"), temp];
    } else {
        temp = timeInterval/(3600*24*30*12);
        result = [NSString stringWithFormat:NSLocalizedString(@"%ld years ago", @"Seafile"), temp];
    }
    return  result;
}

@end
