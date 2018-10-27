//
//  SeafPhotoAsset.m
//  Seafile
//
//  Created by three on 2018/10/20.
//

#import "SeafPhotoAsset.h"
#import "Utils.h"

@implementation SeafPhotoAsset

- (instancetype)initWithAsset:(PHAsset *)asset {
    self = [super init];
    if (self) {
        _name = [self assetName:asset];
        _url = [self assetURL:asset];
        _localIdentifier = asset.localIdentifier;
    }
    return self;
}

- (NSString *)assetName:(PHAsset *)asset {
    NSString *name;
    if (@available(iOS 9.0, *)) {
        NSArray *resources = [PHAssetResource assetResourcesForAsset:asset];
        name = ((PHAssetResource*)resources.firstObject).originalFilename;
    } else {
        name = [asset valueForKey:@"filename"];
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
    __block NSURL *URL;
    if (asset.mediaType == PHAssetMediaTypeImage) {
        PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
        options.synchronous = YES;
        [PHImageManager.defaultManager requestImageDataForAsset:asset options:options resultHandler:^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info) {
            URL = info[@"PHImageFileURLKey"];
        }];
    } else if (asset.mediaType == PHAssetMediaTypeVideo) {
        PHVideoRequestOptions *options = [[PHVideoRequestOptions alloc] init];
        options.version = PHVideoRequestOptionsVersionCurrent;
        [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:options resultHandler:^(AVAsset * _Nullable asset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
            if ([asset isKindOfClass:[AVURLAsset class]]) {
                AVURLAsset *urlAsset = (AVURLAsset*)asset;
                URL = urlAsset.URL;
            }
        }];
    }
    return URL;
}


@end
