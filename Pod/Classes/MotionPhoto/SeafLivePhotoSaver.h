//
//  SeafLivePhotoSaver.h
//  Seafile
//
//  Saves Motion Photos (HEIC with embedded video) as iOS Live Photos.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Completion block for Live Photo save operations.
 * @param success YES if save was successful
 * @param error Error object if save failed, nil on success
 */
typedef void (^SeafLivePhotoSaveCompletion)(BOOL success, NSError * _Nullable error);

/**
 * Utility class for saving Motion Photos as iOS Live Photos to the photo library.
 *
 * This class handles the complete workflow:
 * 1. Extract image and video from Motion Photo
 * 2. Add required Live Photo metadata to both components
 * 3. Convert video to MOV format with proper metadata
 * 4. Save as paired Live Photo to Photos library
 */
@interface SeafLivePhotoSaver : NSObject

#pragma mark - Main Save Methods

/**
 * Save a Motion Photo file as an iOS Live Photo to the photo library.
 *
 * @param path Path to the Motion Photo file (HEIC with embedded video)
 * @param completion Completion block called when save finishes
 */
+ (void)saveLivePhotoFromPath:(NSString *)path
                   completion:(nullable SeafLivePhotoSaveCompletion)completion;

/**
 * Save a Motion Photo from data as an iOS Live Photo to the photo library.
 *
 * @param data Motion Photo file data
 * @param completion Completion block called when save finishes
 */
+ (void)saveLivePhotoFromData:(NSData *)data
                   completion:(nullable SeafLivePhotoSaveCompletion)completion;

#pragma mark - Detection Helper

/**
 * Check if a file at path is a Motion Photo that can be saved as Live Photo.
 *
 * @param path Path to the file
 * @return YES if the file is a Motion Photo
 */
+ (BOOL)canSaveAsLivePhotoAtPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END

