//
//  SeafThumb.m
//  seafilePro
//
//  Created by Wang Wei on 9/9/16.
//  Copyright © 2016 Seafile. All rights reserved.
//

#import "SeafThumb.h"
#import "SeafFile.h"
#import "Debug.h"

@implementation SeafThumb
- (id)initWithSeafFile:(SeafFile *)file
{
    if ((self = [super init])) {
        _file = file;
    }
    return self;
}

- (NSString *)accountIdentifier
{
    return self.file.connection.accountIdentifier;
}

- (NSString *)name
{
    return [_file.name stringByAppendingString:@"(-thumb)"];
}

@end
