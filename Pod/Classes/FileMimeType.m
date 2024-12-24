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

@property (nonatomic, strong) NSDictionary *config;
@property (nonatomic, strong) NSDictionary *utiToExtensionMapping;

@end

@implementation FileMimeType
@synthesize config = _config;
@synthesize utiToExtensionMapping = _utiToExtensionMapping;

static FileMimeType *_sharedLoader = nil;

- (id)init {
    if (self = [super init]) {
        // Load MIME type mapping from plist
        NSString *path = [SeafileBundle() pathForResource:@"FileMimeType" ofType:@"plist"];
        _config = [[NSDictionary alloc] initWithContentsOfFile:path];

        // Load UTI to file extension mapping from plist
        NSString *utiPath = [SeafileBundle() pathForResource:@"DataUTIToExtension" ofType:@"plist"];
        _utiToExtensionMapping = [[NSDictionary alloc] initWithContentsOfFile:utiPath];
    }
    return self;
}

- (NSString *)mimeType:(NSString *)fileName {
    NSString *mime = nil;
    NSString *ext = fileName.pathExtension.lowercaseString;
    if (ext && ext.length != 0) {
        mime = [_config objectForKey:ext];
        if (!mime)
            mime = ext;
    }
    return mime;
}

- (NSString *)fileExtensionForUTI:(NSString *)dataUTI {
    if (!dataUTI || dataUTI.length == 0) {
        return nil;
    }

    // Lookup UTI in the mapping dictionary
    NSString *extension = [_utiToExtensionMapping objectForKey:dataUTI];
    return extension ?: nil; // Return nil if not found
}

+ (FileMimeType *)sharedLoader {
    if (_sharedLoader == nil)
        _sharedLoader = [[FileMimeType alloc] init];
    return _sharedLoader;
}

+ (NSString *)mimeType:(NSString *)fileName {
    return [[FileMimeType sharedLoader] mimeType:fileName];
}

+ (NSString *)fileExtensionForUTI:(NSString *)dataUTI {
    return [[FileMimeType sharedLoader] fileExtensionForUTI:dataUTI];
}

@end
