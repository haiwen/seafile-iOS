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
        _name = [Utils assetName:asset];
        _url = [Utils assetURL:asset];
        _localIdentifier = asset.localIdentifier;
    }
    return self;
}

@end
