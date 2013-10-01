//
//  SeafDateFormatter.h
//  seafile
//
//  Created by Wang Wei on 8/30/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SeafDateFormatter : NSDateFormatter

+ (NSString *)stringFromLongLong:(long long)time;

@end
