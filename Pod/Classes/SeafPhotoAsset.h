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
 URL
 */
@property (nonatomic, strong) NSURL *url;

/**
 asset.localIdentifier
 */
@property (nonatomic, copy) NSString *localIdentifier;

/**
 name
 */
@property (nonatomic, copy) NSString *name;

- (instancetype)initWithAsset:(PHAsset*)asset;

@end

NS_ASSUME_NONNULL_END
