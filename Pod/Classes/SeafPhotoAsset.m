//
//  SeafPhotoAsset.m
//  Seafile
//
//  Created by three on 2018/10/20.
//

#import "SeafPhotoAsset.h"
#import "Utils.h"
#import <objc/runtime.h>

@implementation SeafPhotoAsset

- (instancetype)initWithAsset:(PHAsset *)asset {
    self = [super init];
    if (self) {
        _name = [self assetName:asset];
        _localIdentifier = asset.localIdentifier;
        _ALAssetURL = [self assetURL:asset];
    }
    return self;
}

- (NSString *)assetName:(PHAsset *)asset {
    NSString *name;
    if ([asset valueForKey:@"filename"]) {
        //private api,same as originalFilename, test on iOS12 iOS11.1 iOS10.3 iOS9.0 iOS8.4
        name = [asset valueForKey:@"filename"];
    } else {
        if (@available(iOS 9.0, *)) {
            //it's very slow to get the originalFilename
            NSArray *resources = [PHAssetResource assetResourcesForAsset:asset];
            name = ((PHAssetResource*)resources.firstObject).originalFilename;
        }
    }
    if ([name hasPrefix:@"IMG_"]) {
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyyMMdd_HHmmss"];
        NSDate *date = asset.creationDate;
        if (date == nil) {
            date = [NSDate date];
        }
        NSString *dateStr = [dateFormatter stringFromDate:date];
        name = [NSString stringWithFormat:@"IMG_%@_%@", dateStr, [name substringFromIndex:4]];
    }
    if ([name hasSuffix:@"HEIC"]) {
        name = [name stringByReplacingOccurrencesOfString:@"HEIC" withString:@"JPG"];
    }
    return name;
}

- (NSURL *)assetURL:(PHAsset *)asset {
    NSURL *URL;
    unsigned int count;
    objc_property_t *propertyList = class_copyPropertyList([asset class], &count);
    for (unsigned int i = 0; i < count; i++) {
        const char *propertyName = property_getName(propertyList[i]);
        if ([[NSString stringWithUTF8String:propertyName] isEqualToString:@"ALAssetURL"]) {
            URL = [asset valueForKey:@"ALAssetURL"];
            break;
        }
    }
    free(propertyList);
    return URL;
}


@end
