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

/**
 Whether the asset is a Live Photo (contains both image and video)
 */
@property (nonatomic, assign, readonly) BOOL isLivePhoto;

/// Whether the asset has been edited (iOS exports edited photos as JPEG).
@property (nonatomic, assign, readonly) BOOL isModified;

/**
 The paired video resource for Live Photo (nil if not a Live Photo)
 */
@property (nonatomic, strong, readonly, nullable) PHAssetResource *pairedVideoResource;

/**
 The photo resource (main image)
 */
@property (nonatomic, strong, readonly, nullable) PHAssetResource *photoResource;

/// Photo resource size in bytes (for Live Photo detection).
@property (nonatomic, readonly) unsigned long long photoResourceSize;

/// Paired video resource size in bytes (for Live Photo detection).
@property (nonatomic, readonly) unsigned long long pairedVideoResourceSize;

- (instancetype)initWithAsset:(PHAsset*)asset isCompress:(BOOL)isCompress;

/**
 Get the final upload filename based on Live Photo setting
 @param livePhotoEnabled Whether the "Upload Live Photo" setting is enabled
 @return The filename that will be used for upload:
         - If this is a Live Photo and livePhotoEnabled = YES → returns .heic extension
         - Otherwise → returns original filename
 */
- (NSString *)uploadNameWithLivePhotoEnabled:(BOOL)livePhotoEnabled;

@end

NS_ASSUME_NONNULL_END
