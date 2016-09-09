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

- (id)initWithSeafPreviewIem:(id<SeafPreView>)file
{
    if ((self = [super init])) {
        _file = file;
    }
    return self;
}

# pragma - SeafDownloadDelegate
- (void)download
{
    [(SeafFile *)_file downloadThumb:self];
}

- (NSString *)name
{
    return _file.name;
}

@end
