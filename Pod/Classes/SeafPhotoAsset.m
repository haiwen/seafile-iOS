//
//  SeafPhotoAsset.m
//  Seafile
//
//  Created by three on 2018/10/20.
//

#import "SeafPhotoAsset.h"
#import "Utils.h"
#import <objc/runtime.h>
#import "Debug.h"

@implementation SeafPhotoAsset

- (instancetype)initWithAsset:(PHAsset *)asset isCompress:(BOOL)isCompress {
    self = [super init];
    if (self) {
        _isCompress = isCompress;
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
        //it's very slow to get the originalFilename
        NSArray *resources = [PHAssetResource assetResourcesForAsset:asset];
        name = ((PHAssetResource*)resources.firstObject).originalFilename;
    }
    if ([name hasPrefix:@"IMG_"]) {
        name = [self nameFormat:[name substringFromIndex:4] creationDate:asset.creationDate];
    } else if ([asset respondsToSelector:NSSelectorFromString(@"cloudAssetGUID")] && [asset valueForKey:@"cloudAssetGUID"] && [name containsString:[asset valueForKey:@"cloudAssetGUID"]]) {
        //name of image from icloud: E5DBF99D-E62F-4E29-BCF9-EBC253E3A1C8.PNG
        NSRange range = [name rangeOfString:@"." options:NSBackwardsSearch];
        if (range.location > 4) {
            name = [self nameFormat:[name substringFromIndex:range.location-4] creationDate:asset.creationDate];
        }
    }
    if ([name hasSuffix:@"HEIC"] && _isCompress == YES) {
        name = [name stringByReplacingOccurrencesOfString:@"HEIC" withString:@"JPG"];
    }
    return name;
}

- (NSString *)nameFormat:(NSString *)name creationDate:(NSDate *)date {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyyMMdd_HHmmss"];
    if (date == nil) {
        date = [NSDate date];
    }
    NSString *dateStr = [dateFormatter stringFromDate:date];
    name = [NSString stringWithFormat:@"IMG_%@_%@", dateStr, name];
    return name;
}

- (NSURL *)assetURL:(PHAsset *)asset {
    NSURL *URL;
    unsigned int count;
    objc_property_t *propertyList = class_copyPropertyList([asset class], &count);
    for (unsigned int i = 0; i < count; i++) {
        const char *propertyName = property_getName(propertyList[i]);
        if ([[NSString stringWithUTF8String:propertyName] isEqualToString:@"ALAssetURL"]) {
            if ([[asset valueForKey:@"ALAssetURL"] isKindOfClass:[NSURL class]]) {//may be not NSURL
                URL = [asset valueForKey:@"ALAssetURL"];
            }
            break;
        }
    }
    free(propertyList);
    return URL;
}


@end
