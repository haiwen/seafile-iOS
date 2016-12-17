//
//  SKFileTypeImageLoader.m
//  SparkleShare
//
//  Created by Sergey Klimov on 16.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "SKFileTypeImageLoader.h"
#import "Debug.h"

#define FILENAMEFORMAT @"{size}_{basename}{extension}"

@implementation SKFileTypeImageLoader
@synthesize config = _config;


static SKFileTypeImageLoader *sharedLoader = nil;


- (id)init
{
    if (self=[super init]) {
        NSString *path = [SeafileBundle() pathForResource:
                          @"FileTypeIcons" ofType:@"plist"];
        _config = [[NSDictionary alloc] initWithContentsOfFile:path];
        images = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (NSString*)constructFilenameWithBasename:(NSString*)basename size:(unsigned int)size
{
    NSString *sizeString = [NSString stringWithFormat:@"%d", size];
    return  [[[FILENAMEFORMAT stringByReplacingOccurrencesOfString:@"{size}" withString:sizeString]
              stringByReplacingOccurrencesOfString:@"{basename}" withString:basename]
             stringByReplacingOccurrencesOfString:@"{extension}" withString:@""];
}

- (UIImage*)loadImageWithName:(NSString*)imageName
{
    if ([images objectForKey:imageName])
        return [images objectForKey:imageName];

    NSString *resourcePath = [NSString stringWithFormat:@"Icons/%@", imageName];
    NSString* path = [SeafileBundle() pathForResource:resourcePath ofType:@"png"];
    if (path) {
        UIImage* image = [UIImage imageWithContentsOfFile:path];
        [images setValue:image forKey:imageName];
        return image;
    } else {
        //NSLog(@"WARNING! Image %@ not found", imageName);
        return nil;
    }
}


- (UIImage *)imageForMimeType:(NSString *)mimeType ext:(NSString *)ext
{
    if (ext && ext.length > 0) {
        UIImage *img = [self loadImageWithName:ext];
        if (img)
            return img;
    }
    if (!mimeType)
        return [self loadImageWithName:@"unknown-file"];

    NSString *basename = [mimeType stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    UIImage * image = [self loadImageWithName:basename];
    if (image)
        return image;
    if ((basename=[[_config objectForKey:@"Synonyms"] objectForKey:basename])) {
        image = [self loadImageWithName:basename];
    } else {
        basename = [mimeType.pathComponents objectAtIndex:0];
        if (![mimeType isEqualToString:basename])
            return [self imageForMimeType:basename ext:nil];
    }
    if (!image)
        return [self loadImageWithName:@"unknown-file"];

    return image;
}

+ (SKFileTypeImageLoader *)sharedLoader
{
    if (sharedLoader == nil)
        sharedLoader = [[SKFileTypeImageLoader alloc] init];
    return sharedLoader;
}

+ (UIImage *)imageForMimeType:(NSString *)mimeType
{
    return [[self sharedLoader] imageForMimeType:mimeType ext:nil];
}
+ (UIImage *)imageForMimeType:(NSString *)mimeType ext:(NSString *)ext
{
    return [[self sharedLoader] imageForMimeType:mimeType ext:ext];
}

@end
