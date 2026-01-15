//
//  SeafXMPHandler.h
//  Seafile
//
//  Created for Motion Photo support.
//  Handles XMP metadata parsing and generation for Motion Photos.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - SeafMotionPhotoXMP

/**
 * Model class representing Motion Photo XMP metadata.
 * Based on Google Camera XMP and Container XMP specifications.
 */
@interface SeafMotionPhotoXMP : NSObject

#pragma mark - GCamera Namespace Properties

/// Whether this is a Motion Photo (GCamera:MotionPhoto)
/// Value of 1 indicates Motion Photo, 0 or missing means not
@property (nonatomic, assign) BOOL isMotionPhoto;

/// Motion Photo format version (GCamera:MotionPhotoVersion)
/// Typically 1
@property (nonatomic, assign) NSInteger motionPhotoVersion;

/// Presentation timestamp in microseconds (GCamera:MotionPhotoPresentationTimestampUs)
/// The video frame timestamp corresponding to the still image
/// Value of -1 means not specified
@property (nonatomic, assign) int64_t presentationTimestampUs;

#pragma mark - Container Directory Properties

/// Primary item MIME type (e.g., "image/heic", "image/jpeg")
@property (nonatomic, copy, nullable) NSString *primaryMime;

/// Video item MIME type (e.g., "video/mp4")
@property (nonatomic, copy, nullable) NSString *videoMime;

/// Video data length in bytes (Container:Item Length for MotionPhoto semantic)
@property (nonatomic, assign) NSUInteger videoLength;

/// Padding before video data (Container:Item Padding)
@property (nonatomic, assign) NSUInteger videoPadding;

/// Primary item length (usually 0, meaning "rest of the data before video")
@property (nonatomic, assign) NSUInteger primaryLength;

/// Primary item padding
@property (nonatomic, assign) NSUInteger primaryPadding;

#pragma mark - Computed Properties

/// Calculate video offset from end of file: fileSize - videoLength
- (NSUInteger)videoOffsetInFileOfSize:(NSUInteger)fileSize;

/// Check if the XMP contains valid Motion Photo metadata
- (BOOL)isValidMotionPhoto;

@end

#pragma mark - SeafXMPHandler

/**
 * Handler for parsing and generating XMP metadata for Motion Photos.
 */
@interface SeafXMPHandler : NSObject

#pragma mark - Parsing

/**
 * Parse XMP metadata from raw XMP data.
 * @param xmpData Raw XMP XML data
 * @return Parsed Motion Photo XMP model, or nil if parsing fails
 */
+ (nullable SeafMotionPhotoXMP *)parseXMPData:(NSData *)xmpData;

/**
 * Parse Motion Photo XMP from image file data (JPEG or HEIC).
 * Automatically detects format and extracts XMP.
 * @param imageData Complete image file data
 * @return Parsed Motion Photo XMP model, or nil if not found/invalid
 */
+ (nullable SeafMotionPhotoXMP *)parseXMPFromImageData:(NSData *)imageData;

/**
 * Check if data contains Motion Photo XMP metadata.
 * @param data Image file data
 * @return YES if Motion Photo XMP is found
 */
+ (BOOL)hasMotionPhotoXMP:(NSData *)data;

#pragma mark - Generation

/**
 * Generate XMP XML string compatible with both V1 and V2 Motion Photo formats.
 * This format combines:
 * - V1 format (GCamera:MotionPhoto, GCamera:MotionPhotoVersion, GCamera:MotionPhotoPresentationTimestampUs)
 * - V2 format (Container:Directory)
 * - Legacy V1 fields (GCamera:MicroVideo, MicroVideoVersion, MicroVideoOffset, MicroVideoPresentationTimestampUs)
 *
 * This provides maximum compatibility across all Motion Photo readers:
 * - V1 readers use GCamera:MotionPhoto, GCamera:MotionPhotoPresentationTimestampUs
 * - V2 readers use Container:Directory for precise item definitions
 * - Legacy readers use deprecated MicroVideo* fields
 *
 * Reference: https://developer.android.com/media/platform/motion-photo-format
 *
 * @param videoLength Video data length in bytes
 * @param presentationTimestampUs Video timestamp for still frame in microseconds (use -1 for unspecified)
 * @return XMP XML string in V1+V2 hybrid format with legacy compatibility
 */
+ (NSString *)generateV1V2HybridXMPWithVideoLength:(NSUInteger)videoLength
                           presentationTimestampUs:(int64_t)presentationTimestampUs;

#pragma mark - XMP Embedding

/**
 * Inject XMP data into JPEG image data.
 * @param xmpData XMP XML data to inject
 * @param jpegData Original JPEG image data
 * @return New JPEG data with XMP embedded, or nil on failure
 */
+ (nullable NSData *)injectXMPData:(NSData *)xmpData intoJPEGData:(NSData *)jpegData;

/**
 * Inject XMP data into HEIC image data.
 * Note: This is more complex and may require rebuilding the file structure.
 * @param xmpData XMP XML data to inject
 * @param heicData Original HEIC image data
 * @return New HEIC data with XMP embedded, or nil on failure
 */
+ (nullable NSData *)injectXMPData:(NSData *)xmpData intoHEICData:(NSData *)heicData;

@end

NS_ASSUME_NONNULL_END

