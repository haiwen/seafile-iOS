//
//  SeafVideoConverter.h
//  Seafile
//
//  Created for Motion Photo support.
//  Handles video format conversion and validation for Motion Photo compliance.
//  Based on Android Motion Photo specification:
//  https://developer.android.com/media/platform/motion-photo-format
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Video Codec Types

/**
 * Video codec types supported by Motion Photo specification.
 * According to Android spec, video must be encoded in AVC, HEVC, or AV1.
 */
typedef NS_ENUM(NSInteger, SeafVideoCodecType) {
    SeafVideoCodecTypeUnknown = 0,
    SeafVideoCodecTypeH264,      // AVC (H.264) - Most common for iOS Live Photos
    SeafVideoCodecTypeHEVC,      // HEVC (H.265) - Used in newer iOS devices
    SeafVideoCodecTypeAV1,       // AV1 - Rare but supported
    SeafVideoCodecTypeUnsupported
};

/**
 * Video container format types.
 */
typedef NS_ENUM(NSInteger, SeafVideoContainerType) {
    SeafVideoContainerTypeUnknown = 0,
    SeafVideoContainerTypeQuickTime,  // MOV (qt brand) - iOS Live Photo default
    SeafVideoContainerTypeMP4,        // MP4 (isom/mp4x brands) - Motion Photo required
    SeafVideoContainerTypeM4V         // M4V (Apple variant)
};

/**
 * Audio codec compliance status.
 * Motion Photo spec: optional AAC audio at 44.1/48/96 kHz, mono or stereo.
 */
typedef NS_ENUM(NSInteger, SeafAudioComplianceStatus) {
    SeafAudioComplianceStatusNoAudio = 0,
    SeafAudioComplianceStatusCompliant,
    SeafAudioComplianceStatusNonCompliant
};

#pragma mark - SeafVideoInfo

/**
 * Information about a video file for Motion Photo processing.
 */
@interface SeafVideoInfo : NSObject

@property (nonatomic, assign) SeafVideoContainerType containerType;
@property (nonatomic, assign) SeafVideoCodecType videoCodec;
@property (nonatomic, assign) SeafAudioComplianceStatus audioCompliance;
@property (nonatomic, assign) CMTime duration;
@property (nonatomic, assign) CGSize videoSize;
@property (nonatomic, assign) float frameRate;
@property (nonatomic, assign) double audioSampleRate;
@property (nonatomic, assign) int audioChannelCount;
@property (nonatomic, copy, nullable) NSString *containerBrand;
@property (nonatomic, copy, nullable) NSString *videoCodecString;
@property (nonatomic, copy, nullable) NSString *audioCodecString;

/// Check if video codec is compliant with Motion Photo spec
- (BOOL)isVideoCodecCompliant;

/// Check if the entire video is compliant with Motion Photo spec
- (BOOL)isFullyCompliant;

/// Human-readable description
- (NSString *)complianceReport;

@end

#pragma mark - SeafVideoConverter

/**
 * Converter for video format transformation and validation.
 * Handles MOV to MP4 conversion for Motion Photo compliance.
 */
@interface SeafVideoConverter : NSObject

#pragma mark - Video Analysis

/**
 * Analyze video data and return detailed information.
 * @param videoData Video file data
 * @return Video information object, or nil if analysis fails
 */
+ (nullable SeafVideoInfo *)analyzeVideoData:(NSData *)videoData;

/**
 * Analyze video file at path.
 * @param videoPath Path to video file
 * @return Video information object, or nil if analysis fails
 */
+ (nullable SeafVideoInfo *)analyzeVideoAtPath:(NSString *)videoPath;

/**
 * Analyze AVAsset.
 * @param asset AVAsset to analyze
 * @return Video information object
 */
+ (SeafVideoInfo *)analyzeAsset:(AVAsset *)asset;

#pragma mark - Format Detection

/**
 * Detect container type from video data.
 * @param videoData Video file data
 * @return Container type
 */
+ (SeafVideoContainerType)detectContainerType:(NSData *)videoData;

/**
 * Detect container brand string from video data.
 * @param videoData Video file data
 * @return Brand string (e.g., "qt  ", "isom", "mp41")
 */
+ (nullable NSString *)detectContainerBrand:(NSData *)videoData;

/**
 * Check if video data is QuickTime MOV format.
 * @param videoData Video file data
 * @return YES if QuickTime format
 */
+ (BOOL)isQuickTimeFormat:(NSData *)videoData;

/**
 * Check if video data is standard MP4 format.
 * @param videoData Video file data
 * @return YES if MP4 format
 */
+ (BOOL)isMP4Format:(NSData *)videoData;

/**
 * Detect video codec type from AVAsset.
 * @param asset AVAsset to check
 * @return Video codec type
 */
+ (SeafVideoCodecType)detectVideoCodec:(AVAsset *)asset;

/**
 * Get human-readable codec name.
 * @param codecType Codec type
 * @return Codec name string
 */
+ (NSString *)codecNameForType:(SeafVideoCodecType)codecType;

#pragma mark - MOV to MP4 Conversion

/**
 * Convert MOV video to MP4 format (async).
 * Uses passthrough for video/audio to preserve quality.
 *
 * @param sourceURL URL to source MOV file
 * @param completion Completion handler with output URL or error
 */
+ (void)convertMOVToMP4:(NSURL *)sourceURL
             completion:(void (^)(NSURL * _Nullable outputURL, NSError * _Nullable error))completion;

/**
 * Convert MOV video data to MP4 format (async).
 *
 * @param movData MOV video data
 * @param completion Completion handler with MP4 data or error
 */
+ (void)convertMOVDataToMP4:(NSData *)movData
                 completion:(void (^)(NSData * _Nullable mp4Data, NSError * _Nullable error))completion;

/**
 * Convert MOV to MP4 with options.
 *
 * @param sourceURL URL to source MOV file
 * @param options Conversion options:
 *                - @"preserveAudio": NSNumber (BOOL) - whether to preserve audio track (default: YES)
 *                - @"videoQuality": NSNumber (float 0.0-1.0) - video quality for re-encoding if needed
 * @param completion Completion handler
 */
+ (void)convertMOVToMP4:(NSURL *)sourceURL
                options:(nullable NSDictionary *)options
             completion:(void (^)(NSURL * _Nullable outputURL, NSError * _Nullable error))completion;

#pragma mark - Presentation Timestamp Extraction

/**
 * Extract the presentation timestamp for the still image frame in a Live Photo video.
 * This is typically the middle frame or a specific keyframe.
 *
 * @param videoURL URL to the Live Photo paired video
 * @return Presentation timestamp in microseconds, or -1 if cannot be determined
 */
+ (int64_t)extractPresentationTimestampFromVideo:(NSURL *)videoURL;

/**
 * Extract presentation timestamp from video data.
 *
 * @param videoData Video file data
 * @return Presentation timestamp in microseconds, or -1 if cannot be determined
 */
+ (int64_t)extractPresentationTimestampFromVideoData:(NSData *)videoData;

/**
 * Extract the still image time from Live Photo video metadata.
 * iOS Live Photos store the still image time in the video's metadata.
 *
 * @param asset AVAsset of the Live Photo video
 * @return Still image time, or kCMTimeInvalid if not found
 */
+ (CMTime)extractStillImageTimeFromAsset:(AVAsset *)asset;

#pragma mark - Audio Validation

/**
 * Check if audio track is compliant with Motion Photo specification.
 * Spec: 16-bit, mono or stereo, 44.1/48/96 kHz, AAC encoded.
 *
 * @param asset AVAsset to check
 * @return Audio compliance status
 */
+ (SeafAudioComplianceStatus)checkAudioCompliance:(AVAsset *)asset;

#pragma mark - Utility Methods

/**
 * Generate a temporary file path for video conversion output.
 * @param extension File extension (e.g., "mp4", "mov")
 * @return Temporary file path
 */
+ (NSString *)temporaryFilePathWithExtension:(NSString *)extension;

/**
 * Clean up temporary files created during conversion.
 * @param paths Array of file paths to delete
 */
+ (void)cleanupTemporaryFiles:(NSArray<NSString *> *)paths;

@end

NS_ASSUME_NONNULL_END

