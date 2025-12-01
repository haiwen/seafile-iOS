#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

@class SeafUploadFile;

@interface SeafAssetManager : NSObject

// Set asset for a file
- (void)setAsset:(PHAsset *)asset url:(NSURL *)url forFile:(SeafUploadFile *)file;

// Check asset for a file
- (void)checkAssetWithFile:(SeafUploadFile *)file completion:(void (^)(BOOL success, NSError *error))completion;

// Get image data for a file's asset
- (void)getImageDataForAsset:(SeafUploadFile *)file completion:(void (^)(BOOL success, NSError *error))completion;

// Get video data for a file's asset
- (void)getVideoForAsset:(SeafUploadFile *)file completion:(void (^)(BOOL success, NSError *error))completion;

// Convert HEIC to JPEG
- (BOOL)convertHEICToJPEG:(NSURL *)sourceURL destination:(NSURL *)destinationURL;

#pragma mark - Live Photo / Motion Photo Support

/**
 * Check if the asset is a Live Photo
 * @param asset The PHAsset to check
 * @return YES if the asset is a Live Photo
 */
- (BOOL)isLivePhotoAsset:(PHAsset *)asset;

/**
 * Get Motion Photo data for a Live Photo asset.
 * Combines the image and video into a single Motion Photo file.
 * @param file The upload file with a Live Photo asset
 * @param completion Completion handler
 */
- (void)getMotionPhotoDataForAsset:(SeafUploadFile *)file 
                        completion:(void (^)(BOOL success, NSError *error))completion;

@end