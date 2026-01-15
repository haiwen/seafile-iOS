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

@interface SeafPhotoAsset ()

@property (nonatomic, assign, readwrite) BOOL isLivePhoto;
@property (nonatomic, assign, readwrite) BOOL isModified;
@property (nonatomic, strong, readwrite, nullable) PHAssetResource *pairedVideoResource;
@property (nonatomic, strong, readwrite, nullable) PHAssetResource *photoResource;

@end

@implementation SeafPhotoAsset

- (instancetype)initWithAsset:(PHAsset *)asset isCompress:(BOOL)isCompress {
    self = [super init];
    if (self) {
        _isCompress = isCompress;
        _localIdentifier = asset.localIdentifier;
        _ALAssetURL = [self assetURL:asset];
        
        // Detect Live Photo and extract resources
        [self detectLivePhotoFromAsset:asset];
        
        // Get the name (must be after Live Photo detection for proper handling)
        _name = [self assetName:asset];
    }
    return self;
}

#pragma mark - Live Photo Detection

- (void)detectLivePhotoFromAsset:(PHAsset *)asset {
    _isLivePhoto = (asset.mediaSubtypes & PHAssetMediaSubtypePhotoLive) != 0;
    _isModified = NO;
    
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    
    for (PHAssetResource *resource in resources) {
        if (resource.type == PHAssetResourceTypeAdjustmentData) {
            _isModified = YES;
        }
        
        if (_isLivePhoto) {
            switch (resource.type) {
                case PHAssetResourceTypePhoto:
                case PHAssetResourceTypeFullSizePhoto:
                    if (!_photoResource) {
                        _photoResource = resource;
                    }
                    break;
                    
                case PHAssetResourceTypePairedVideo:
                case PHAssetResourceTypeFullSizePairedVideo:
                    if (!_pairedVideoResource) {
                        _pairedVideoResource = resource;
                    }
                    break;
                    
                default:
                    break;
            }
        }
    }
    
    if (_isLivePhoto && !_pairedVideoResource) {
        _isLivePhoto = NO;
    }
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
    
    // Normalize file extension to lowercase
    NSString *ext = name.pathExtension;
    if (ext.length > 0) {
        NSString *lowercaseExt = [ext lowercaseString];
        if (![ext isEqualToString:lowercaseExt]) {
            name = [[name stringByDeletingPathExtension] stringByAppendingPathExtension:lowercaseExt];
        }
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

- (NSString *)uploadNameWithLivePhotoEnabled:(BOOL)livePhotoEnabled {
    if (_isLivePhoto && livePhotoEnabled) {
        NSString *ext = [_name.pathExtension lowercaseString];
        if (![ext isEqualToString:@"heic"]) {
            return [[_name stringByDeletingPathExtension] stringByAppendingPathExtension:@"heic"];
        }
    }
    return _name;
}

#pragma mark - Resource Size for Live Photo Detection

- (unsigned long long)photoResourceSize {
    if (!_photoResource) {
        return 0;
    }
    NSNumber *size = [_photoResource valueForKey:@"fileSize"];
    return size ? [size unsignedLongLongValue] : 0;
}

- (unsigned long long)pairedVideoResourceSize {
    if (!_pairedVideoResource) {
        return 0;
    }
    NSNumber *size = [_pairedVideoResource valueForKey:@"fileSize"];
    return size ? [size unsignedLongLongValue] : 0;
}

@end
