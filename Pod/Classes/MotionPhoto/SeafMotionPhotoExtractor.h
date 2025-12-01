//
//  SeafMotionPhotoExtractor.h
//  Seafile
//
//  Created for Motion Photo support.
//  Extracts image and video components from Motion Photo files.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SeafMotionPhotoXMP;

#pragma mark - Android Spec Compliance Types

/**
 * Compliance status for Motion Photo format.
 */
typedef NS_ENUM(NSInteger, SeafMotionPhotoComplianceStatus) {
    SeafMotionPhotoComplianceStatusUnknown = 0,
    SeafMotionPhotoComplianceStatusCompliant,       // Fully compliant with Android spec
    SeafMotionPhotoComplianceStatusPartiallyCompliant, // Works but has minor issues
    SeafMotionPhotoComplianceStatusNonCompliant     // Does not meet spec requirements
};

/**
 * Compliance report for Motion Photo format validation.
 */
@interface SeafMotionPhotoComplianceReport : NSObject

@property (nonatomic, assign) SeafMotionPhotoComplianceStatus status;
@property (nonatomic, assign) BOOL hasMpvdBox;
@property (nonatomic, assign) BOOL hasValidVideoContainer;  // MP4 not MOV
@property (nonatomic, assign) BOOL hasValidVideoCodec;      // AVC/HEVC/AV1
@property (nonatomic, assign) BOOL mpvdAfterHeicBoxes;      // mpvd comes after all HEIC boxes
@property (nonatomic, copy, nullable) NSString *videoContainerBrand;
@property (nonatomic, copy, nullable) NSString *videoCodec;
@property (nonatomic, copy, nullable) NSArray<NSString *> *issues;
@property (nonatomic, copy, nullable) NSArray<NSString *> *warnings;

- (NSString *)formattedReport;

@end

#pragma mark - SeafMotionPhotoExtractor

/**
 * Extractor for Motion Photo files.
 * Detects Motion Photos and extracts their image and video components.
 */
@interface SeafMotionPhotoExtractor : NSObject

#pragma mark - Detection Methods

/**
 * Check if data is a Motion Photo.
 * Checks for both XMP metadata markers and embedded video signatures.
 *
 * @param data File data to check
 * @return YES if the data appears to be a Motion Photo
 */
+ (BOOL)isMotionPhoto:(NSData *)data;

/**
 * Check if file at path is a Motion Photo.
 *
 * @param path Path to file
 * @return YES if the file appears to be a Motion Photo
 */
+ (BOOL)isMotionPhotoAtPath:(NSString *)path;

/**
 * Check if file is a Motion Photo by checking file extension and magic bytes.
 * This is a fast check that doesn't parse the full file.
 *
 * @param path Path to file
 * @return YES if the file might be a Motion Photo (needs further verification)
 */
+ (BOOL)mightBeMotionPhotoAtPath:(NSString *)path;

#pragma mark - Information Extraction

/**
 * Get Motion Photo metadata from file data.
 *
 * @param data Motion Photo file data
 * @return XMP metadata object, or nil if not a Motion Photo
 */
+ (nullable SeafMotionPhotoXMP *)getMotionPhotoInfo:(NSData *)data;

/**
 * Get Motion Photo metadata from file path.
 *
 * @param path Path to Motion Photo file
 * @return XMP metadata object, or nil if not a Motion Photo
 */
+ (nullable SeafMotionPhotoXMP *)getMotionPhotoInfoAtPath:(NSString *)path;

/**
 * Get the video offset in the Motion Photo file.
 *
 * @param data Motion Photo file data
 * @return Video offset (bytes from start), or NSNotFound if not found
 */
+ (NSUInteger)getVideoOffsetInMotionPhoto:(NSData *)data;

/**
 * Get the video length in the Motion Photo file.
 *
 * @param data Motion Photo file data
 * @return Video length in bytes, or 0 if not found
 */
+ (NSUInteger)getVideoLengthInMotionPhoto:(NSData *)data;

#pragma mark - Data Extraction

/**
 * Extract the static image from a Motion Photo (without video data).
 *
 * @param data Motion Photo file data
 * @return Image data without the appended video, or nil on failure
 */
+ (nullable NSData *)extractImageFromMotionPhoto:(NSData *)data;

/**
 * Extract the embedded video from a Motion Photo.
 *
 * @param data Motion Photo file data
 * @return Video data (MOV/MP4), or nil on failure
 */
+ (nullable NSData *)extractVideoFromMotionPhoto:(NSData *)data;

/**
 * Extract the embedded video and save to a temporary file.
 *
 * @param data Motion Photo file data
 * @return Path to temporary video file, or nil on failure
 */
+ (nullable NSString *)extractVideoToTempFileFromMotionPhoto:(NSData *)data;

/**
 * Extract the embedded video from file and save to a temporary file.
 *
 * @param sourcePath Path to Motion Photo file
 * @return Path to temporary video file, or nil on failure
 */
+ (nullable NSString *)extractVideoToTempFileFromMotionPhotoAtPath:(NSString *)sourcePath;

/**
 * Extract both image and video from a Motion Photo.
 *
 * @param data Motion Photo file data
 * @param imageData Output pointer for image data
 * @param videoData Output pointer for video data
 * @return YES on success, NO on failure
 */
+ (BOOL)extractFromMotionPhoto:(NSData *)data
                     imageData:(NSData * _Nullable * _Nullable)imageData
                     videoData:(NSData * _Nullable * _Nullable)videoData;

#pragma mark - File Operations

/**
 * Extract video from Motion Photo file and save to specified path.
 *
 * @param sourcePath Path to Motion Photo file
 * @param destinationPath Path where video should be saved
 * @param error Error pointer
 * @return YES on success, NO on failure
 */
+ (BOOL)extractVideoFromMotionPhotoAtPath:(NSString *)sourcePath
                                   toPath:(NSString *)destinationPath
                                    error:(NSError * _Nullable * _Nullable)error;

/**
 * Create a standard JPEG/HEIC file from Motion Photo (strips video).
 *
 * @param sourcePath Path to Motion Photo file
 * @param destinationPath Path where image should be saved
 * @param error Error pointer
 * @return YES on success, NO on failure
 */
+ (BOOL)extractImageFromMotionPhotoAtPath:(NSString *)sourcePath
                                   toPath:(NSString *)destinationPath
                                    error:(NSError * _Nullable * _Nullable)error;

#pragma mark - Debug / Utility

/**
 * Log the structure of a Motion Photo file for debugging.
 *
 * @param data Motion Photo file data
 */
+ (void)logMotionPhotoStructure:(NSData *)data;

/**
 * Analyze a potential Motion Photo and log detailed diagnostic information.
 * Use this to debug why certain Motion Photos aren't being detected or played correctly.
 *
 * @param data File data to analyze
 * @param fileName Name of the file for logging purposes
 */
+ (void)analyzeAndLogMotionPhotoIssues:(NSData *)data fileName:(NSString *)fileName;

#pragma mark - Android Spec Compliance Validation

/**
 * Validate Motion Photo data against Android Motion Photo specification.
 * Reference: https://developer.android.com/media/platform/motion-photo-format
 *
 * @param data Motion Photo file data
 * @return Compliance report with detailed analysis
 */
+ (SeafMotionPhotoComplianceReport *)validateAndroidSpecCompliance:(NSData *)data;

/**
 * Quick check if Motion Photo is Android spec compliant.
 *
 * @param data Motion Photo file data
 * @return YES if fully compliant with Android spec
 */
+ (BOOL)isAndroidSpecCompliant:(NSData *)data;

@end

NS_ASSUME_NONNULL_END

