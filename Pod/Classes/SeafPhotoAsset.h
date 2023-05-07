//
//  SeafPhotoAsset.h
//  Seafile
//
//  Created by three on 2018/10/20.
//

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafPhotoAsset : NSObject

/**
 asset.localIdentifier
 */
@property (nonatomic, copy) NSString *localIdentifier;

/**
 name
 */
@property (nonatomic, copy) NSString *name;

/**
 ALAssetURL
 */
@property (nonatomic, strong) NSURL *ALAssetURL;

/**
 compress
 */
@property (nonatomic, assign) BOOL isCompress;

- (instancetype)initWithAsset:(PHAsset*)asset isCompress:(BOOL)isCompress;

@end

NS_ASSUME_NONNULL_END
