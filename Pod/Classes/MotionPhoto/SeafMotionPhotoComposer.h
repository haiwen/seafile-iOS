//
//  SeafMotionPhotoComposer.h
//  Seafile
//
//  Created for Motion Photo support.
//  Composes Motion Photo files from separate image and video components.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Composer for creating Motion Photo files.
 * Combines a static image (HEIC/JPEG) with a video (MOV/MP4) into a single Motion Photo file.
 */
@interface SeafMotionPhotoComposer : NSObject

#pragma mark - Validation Methods

/**
 * Check if image data is a valid format for Motion Photo composition.
 * Supports HEIC and JPEG formats.
 *
 * @param imageData Image data to validate
 * @return YES if the format is supported
 */
+ (BOOL)isValidImageDataForComposition:(NSData *)imageData;

/**
 * Check if video data is a valid format for Motion Photo composition.
 * Supports MOV and MP4 formats.
 *
 * @param videoData Video data to validate
 * @return YES if the format is supported
 */
+ (BOOL)isValidVideoDataForComposition:(NSData *)videoData;

/**
 * Get the MIME type for the image data.
 *
 * @param imageData Image data
 * @return MIME type string (e.g., "image/heic", "image/jpeg"), or nil if unknown
 */
+ (nullable NSString *)mimeTypeForImageData:(NSData *)imageData;

/**
 * Get the MIME type for the video data.
 *
 * @param videoData Video data
 * @return MIME type string (e.g., "video/mp4", "video/quicktime"), or nil if unknown
 */
+ (nullable NSString *)mimeTypeForVideoData:(NSData *)videoData;

#pragma mark - V1+V2 Hybrid Format

/**
 * Compose a Motion Photo with V1+V2 hybrid XMP format.
 * This format:
 * - Uses original QuickTime MOV video without conversion
 * - Wraps video in mpvd box
 * - Includes V1 fields (GCamera:MotionPhoto, MotionPhotoVersion, MotionPhotoPresentationTimestampUs)
 * - Includes legacy V1 fields (GCamera:MicroVideo, MicroVideoVersion, MicroVideoOffset)
 * - Includes V2 fields (MotionPhotoPresentationTimestampUs, Container:Directory)
 *
 * @param imageData HEIC image data (original from iOS)
 * @param videoData MOV video data (original QuickTime format from iOS Live Photo)
 * @return Combined Motion Photo data in V1+V2 hybrid format, or nil on failure
 */
+ (nullable NSData *)composeV1V2MotionPhotoWithImageData:(NSData *)imageData
                                               videoData:(NSData *)videoData;

@end

NS_ASSUME_NONNULL_END

