//
//  FileSizeFormatter.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "FileSizeFormatter.h"

static const char sUnits[] = {
    '\0', 'K', 'M', 'G', 'T', 'P', 'E', 'Z', 'Y'
};
static int sMaxUnits = sizeof sUnits - 1;

@implementation FileSizeFormatter
static FileSizeFormatter *sharedLoader = nil;

- (id)init
{
    if (self = [super init]) {
        [self setNumberStyle:NSNumberFormatterDecimalStyle];
        [self setMaximumFractionDigits:1];
    }
    return self;
}

- (NSString *)stringFromNumber:(NSNumber *)number useBaseTen:(BOOL)useBaseTen
{
    int multiplier = useBaseTen ? 1000 : 1024;
    int exponent = 0;

    double bytes = [number doubleValue];

    while ( (bytes >= multiplier) && (exponent < sMaxUnits) ) {
        bytes /= multiplier;
        exponent++;
    }

    return [NSString stringWithFormat:@"%@ %cB", [super stringFromNumber:[NSNumber numberWithDouble:bytes]], sUnits[exponent]];
}

+ (FileSizeFormatter *)sharedLoader
{
    if (sharedLoader==nil)
        sharedLoader = [[FileSizeFormatter alloc] init];
    return sharedLoader;
}

+ (NSString *)stringFromNumber:(NSNumber *)number useBaseTen:(BOOL)useBaseTen
{
    return [[FileSizeFormatter sharedLoader] stringFromNumber:number useBaseTen:useBaseTen];
}

+ (NSString *)stringFromLongLong:(long long)number
{
    if (number < 0)
        return @"?";
    return [[FileSizeFormatter sharedLoader] stringFromNumber:[NSNumber numberWithLongLong:number] useBaseTen:true];
}

@end
