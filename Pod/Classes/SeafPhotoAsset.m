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
    // Check if asset is a Live Photo
    _isLivePhoto = (asset.mediaSubtypes & PHAssetMediaSubtypePhotoLive) != 0;
    
    if (!_isLivePhoto) {
        return;
    }
    
    // Get asset resources to find paired video
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    
    for (PHAssetResource *resource in resources) {
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
    
    // If we couldn't find the paired video resource, mark as not Live Photo
    if (!_pairedVideoResource) {
        Debug(@"SeafPhotoAsset: Live Photo detected but no paired video resource found");
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
    
    // ============ Restored HEIC→JPG filename conversion logic ============
    // When isCompress is YES (uploadHeic is NO), convert HEIC filename to JPG
    // This ensures the filename matches the actual converted file format
    if (_isCompress) {
        NSString *ext = [name.pathExtension lowercaseString];
        if ([ext isEqualToString:@"heic"] || [ext isEqualToString:@"heif"]) {
            name = [[name stringByDeletingPathExtension] stringByAppendingPathExtension:@"jpg"];
        }
    }
    // ============ End of restored HEIC→JPG filename conversion logic ============
    
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
    // ============ Motion Photo functionality temporarily disabled ============
    // If this is a Live Photo and the setting is enabled, use .heic extension for Motion Photo
    // if (_isLivePhoto && livePhotoEnabled) {
    //     NSString *ext = [_name.pathExtension lowercaseString];
    //     if (![ext isEqualToString:@"heic"]) {
    //         return [[_name stringByDeletingPathExtension] stringByAppendingPathExtension:@"heic"];
    //     }
    // }
    // ============ End of disabled Motion Photo code ============
    
    // Current behavior: Just return the original filename (HEIC→JPG conversion is handled by assetName:)
    return _name;
}

@end
