//
//  FileMimeType.m
//  seafile
//
//  Created by Wang Wei on 10/17/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "FileMimeType.h"
#import "Debug.h"

@interface FileMimeType ()

@property (retain) NSDictionary* config;

@end

@implementation FileMimeType
@synthesize config = _config;

static FileMimeType *_sharedLoader = nil;

- (id)init
{
    if (self = [super init]) {
        NSString *path = [SeafileBundle() pathForResource:
                          @"FileMimeType" ofType:@"plist"];
        _config = [[NSDictionary alloc] initWithContentsOfFile:path];
    }
    return self;
}

- (NSString *)mimeType:(NSString *)fileName
{
    NSString *mime = nil;
    NSString *ext = fileName.pathExtension.lowercaseString;
    if (ext && ext.length != 0) {
        mime = [_config objectForKey:ext];
        if (!mime)
            mime = ext;
    }
    return mime;
}

+ (FileMimeType *)sharedLoader
{
    if (_sharedLoader == nil)
        _sharedLoader = [[FileMimeType alloc] init];
    return _sharedLoader;
}

+ (NSString *)mimeType:(NSString *)fileName
{
    return [[FileMimeType sharedLoader] mimeType:fileName];
}


@end
