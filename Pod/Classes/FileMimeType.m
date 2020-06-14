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
        
        NSArray *array = @[@"ac", @"am", @"bat", @"c", @"cc", @"cmake", @"conf", @"cpp", @"cs", @"css", @"csv", @"diff",
                           @"el", @"go", @"groovy", @"h", @"htm", @"html", @"java", @"js", @"json", @"less", @"log", @"make",
        @"org", @"patch", @"pde", @"php", @"pl", @"properties", @"py", @"rb", @"rst",
        @"sc", @"scala", @"scd", @"schelp", @"script", @"sh", @"sql", @"text", @"tex", @"txt", @"vi", @"vim",
                           @"xhtml", @"xml", @"yml"];
        
        NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
        NSMutableDictionary *temp = [NSMutableDictionary dictionary];
        for (NSString *key in array) {
            [temp setValue:[NSString stringWithFormat:@"text/%@", key] forKey:key];
            if ([dict.allKeys containsObject:key]) {
                [dict removeObjectForKey:key];
            }
        }
        [dict addEntriesFromDictionary:temp];
        _config = [NSDictionary dictionaryWithDictionary:dict];
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
