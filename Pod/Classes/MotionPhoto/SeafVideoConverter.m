//
//  SeafVideoConverter.m
//  Seafile
//
//  Created for Motion Photo support.
//  Implements video format conversion for Motion Photo compliance.
//

#import "SeafVideoConverter.h"
#import "Debug.h"
#import <CoreMedia/CoreMedia.h>

#pragma mark - SeafVideoInfo Implementation

@implementation SeafVideoInfo

- (instancetype)init {
    self = [super init];
    if (self) {
        _containerType = SeafVideoContainerTypeUnknown;
        _videoCodec = SeafVideoCodecTypeUnknown;
        _audioCompliance = SeafAudioComplianceStatusNoAudio;
        _duration = kCMTimeZero;
        _videoSize = CGSizeZero;
        _frameRate = 0;
        _audioSampleRate = 0;
        _audioChannelCount = 0;
    }
    return self;
}

- (BOOL)isVideoCodecCompliant {
    return self.videoCodec == SeafVideoCodecTypeH264 ||
           self.videoCodec == SeafVideoCodecTypeHEVC ||
           self.videoCodec == SeafVideoCodecTypeAV1;
}

- (BOOL)isFullyCompliant {
    // Container must be MP4 (not MOV)
    BOOL containerOK = (self.containerType == SeafVideoContainerTypeMP4);
    
    // Video codec must be AVC/HEVC/AV1
    BOOL codecOK = [self isVideoCodecCompliant];
    
    // Audio is optional, but if present must be compliant
    BOOL audioOK = (self.audioCompliance == SeafAudioComplianceStatusNoAudio ||
                    self.audioCompliance == SeafAudioComplianceStatusCompliant);
    
    return containerOK && codecOK && audioOK;
}

- (NSString *)complianceReport {
    NSMutableString *report = [NSMutableString string];
    
    [report appendFormat:@"Container: %@ (%@) - %@\n",
     self.containerBrand ?: @"unknown",
     [self containerTypeName],
     self.containerType == SeafVideoContainerTypeMP4 ? @"✓" : @"✗ (needs conversion to MP4)"];
    
    [report appendFormat:@"Video Codec: %@ - %@\n",
     self.videoCodecString ?: [SeafVideoConverter codecNameForType:self.videoCodec],
     [self isVideoCodecCompliant] ? @"✓" : @"✗ (unsupported)"];
    
    [report appendFormat:@"Audio: %@\n", [self audioComplianceDescription]];
    
    [report appendFormat:@"Resolution: %.0fx%.0f\n", self.videoSize.width, self.videoSize.height];
    [report appendFormat:@"Frame Rate: %.2f fps\n", self.frameRate];
    [report appendFormat:@"Duration: %.2f seconds\n", CMTimeGetSeconds(self.duration)];
    
    [report appendFormat:@"\nOverall Compliance: %@",
     [self isFullyCompliant] ? @"✓ COMPLIANT" : @"✗ NEEDS CONVERSION"];
    
    return [report copy];
}

- (NSString *)containerTypeName {
    switch (self.containerType) {
        case SeafVideoContainerTypeQuickTime: return @"QuickTime/MOV";
        case SeafVideoContainerTypeMP4: return @"MP4";
        case SeafVideoContainerTypeM4V: return @"M4V";
        default: return @"Unknown";
    }
}

- (NSString *)audioComplianceDescription {
    switch (self.audioCompliance) {
        case SeafAudioComplianceStatusNoAudio:
            return @"No audio track (OK - audio is optional)";
        case SeafAudioComplianceStatusCompliant:
            return [NSString stringWithFormat:@"AAC %.1fkHz %dch ✓",
                    self.audioSampleRate / 1000.0, self.audioChannelCount];
        case SeafAudioComplianceStatusNonCompliant:
            return [NSString stringWithFormat:@"%@ %.1fkHz %dch ✗ (needs conversion)",
                    self.audioCodecString ?: @"Unknown",
                    self.audioSampleRate / 1000.0, self.audioChannelCount];
    }
}

@end

#pragma mark - SeafVideoConverter Implementation

@implementation SeafVideoConverter

#pragma mark - Video Analysis

+ (nullable SeafVideoInfo *)analyzeVideoData:(NSData *)videoData {
    if (!videoData || videoData.length < 12) {
        return nil;
    }
    
    // Write to temp file for AVAsset analysis
    NSString *tempPath = [self temporaryFilePathWithExtension:@"mov"];
    if (![videoData writeToFile:tempPath atomically:YES]) {
        return nil;
    }
    
    SeafVideoInfo *info = [self analyzeVideoAtPath:tempPath];
    
    // Also get container info from raw data
    info.containerType = [self detectContainerType:videoData];
    info.containerBrand = [self detectContainerBrand:videoData];
    
    // Cleanup
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
    
    return info;
}

+ (nullable SeafVideoInfo *)analyzeVideoAtPath:(NSString *)videoPath {
    NSURL *videoURL = [NSURL fileURLWithPath:videoPath];
    AVAsset *asset = [AVAsset assetWithURL:videoURL];
    
    if (!asset) {
        return nil;
    }
    
    SeafVideoInfo *info = [self analyzeAsset:asset];
    
    // Get container info from file
    NSData *headerData = [NSData dataWithContentsOfFile:videoPath
                                                options:NSDataReadingMappedIfSafe
                                                  error:nil];
    if (headerData) {
        info.containerType = [self detectContainerType:headerData];
        info.containerBrand = [self detectContainerBrand:headerData];
    }
    
    return info;
}

+ (SeafVideoInfo *)analyzeAsset:(AVAsset *)asset {
    SeafVideoInfo *info = [[SeafVideoInfo alloc] init];
    
    // Get duration
    info.duration = asset.duration;
    
    // Analyze video track
    NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count > 0) {
        AVAssetTrack *videoTrack = videoTracks.firstObject;
        info.videoSize = videoTrack.naturalSize;
        info.frameRate = videoTrack.nominalFrameRate;
        
        // Get video codec
        info.videoCodec = [self detectVideoCodecFromTrack:videoTrack];
        info.videoCodecString = [self videoCodecStringFromTrack:videoTrack];
    }
    
    // Analyze audio track
    NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    if (audioTracks.count > 0) {
        AVAssetTrack *audioTrack = audioTracks.firstObject;
        
        // Get audio format
        NSArray *formatDescriptions = audioTrack.formatDescriptions;
        if (formatDescriptions.count > 0) {
            CMAudioFormatDescriptionRef audioDesc = (__bridge CMAudioFormatDescriptionRef)formatDescriptions.firstObject;
            const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioDesc);
            
            if (asbd) {
                info.audioSampleRate = asbd->mSampleRate;
                info.audioChannelCount = asbd->mChannelsPerFrame;
                info.audioCodecString = [self audioCodecStringFromDescription:audioDesc];
            }
        }
        
        info.audioCompliance = [self checkAudioComplianceForTrack:audioTrack];
    } else {
        info.audioCompliance = SeafAudioComplianceStatusNoAudio;
    }
    
    return info;
}

#pragma mark - Format Detection

+ (SeafVideoContainerType)detectContainerType:(NSData *)videoData {
    NSString *brand = [self detectContainerBrand:videoData];
    
    if (!brand) {
        return SeafVideoContainerTypeUnknown;
    }
    
    // QuickTime brands
    if ([brand isEqualToString:@"qt  "] || [brand hasPrefix:@"qt"]) {
        return SeafVideoContainerTypeQuickTime;
    }
    
    // M4V brand
    if ([brand isEqualToString:@"M4V "] || [brand hasPrefix:@"M4V"]) {
        return SeafVideoContainerTypeM4V;
    }
    
    // MP4 brands
    NSSet *mp4Brands = [NSSet setWithArray:@[@"isom", @"iso2", @"iso3", @"iso4", @"iso5", @"iso6",
                                              @"mp41", @"mp42", @"mp71",
                                              @"avc1", @"hvc1", @"hev1",
                                              @"3gp4", @"3gp5", @"3gp6"]];
    if ([mp4Brands containsObject:brand]) {
        return SeafVideoContainerTypeMP4;
    }
    
    return SeafVideoContainerTypeUnknown;
}

+ (nullable NSString *)detectContainerBrand:(NSData *)videoData {
    if (videoData.length < 12) {
        return nil;
    }
    
    // Check for ftyp box
    char typeBytes[5] = {0};
    [videoData getBytes:typeBytes range:NSMakeRange(4, 4)];
    
    if (strcmp(typeBytes, "ftyp") != 0) {
        // Some files might have moov/mdat first (legacy QuickTime)
        if (strcmp(typeBytes, "moov") == 0 || strcmp(typeBytes, "mdat") == 0 || strcmp(typeBytes, "wide") == 0) {
            return @"qt  "; // Legacy QuickTime
        }
        return nil;
    }
    
    // Read brand (4 bytes after ftyp)
    char brand[5] = {0};
    [videoData getBytes:brand range:NSMakeRange(8, 4)];
    
    return [NSString stringWithUTF8String:brand];
}

+ (BOOL)isQuickTimeFormat:(NSData *)videoData {
    return [self detectContainerType:videoData] == SeafVideoContainerTypeQuickTime;
}

+ (BOOL)isMP4Format:(NSData *)videoData {
    return [self detectContainerType:videoData] == SeafVideoContainerTypeMP4;
}

+ (SeafVideoCodecType)detectVideoCodec:(AVAsset *)asset {
    NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count == 0) {
        return SeafVideoCodecTypeUnknown;
    }
    
    return [self detectVideoCodecFromTrack:videoTracks.firstObject];
}

+ (SeafVideoCodecType)detectVideoCodecFromTrack:(AVAssetTrack *)videoTrack {
    NSArray *formatDescriptions = videoTrack.formatDescriptions;
    if (formatDescriptions.count == 0) {
        return SeafVideoCodecTypeUnknown;
    }
    
    CMFormatDescriptionRef formatDesc = (__bridge CMFormatDescriptionRef)formatDescriptions.firstObject;
    FourCharCode codecType = CMFormatDescriptionGetMediaSubType(formatDesc);
    
    // H.264/AVC
    if (codecType == kCMVideoCodecType_H264 ||
        codecType == 'avc1' ||
        codecType == 'avc2' ||
        codecType == 'avc3') {
        return SeafVideoCodecTypeH264;
    }
    
    // HEVC/H.265
    if (codecType == kCMVideoCodecType_HEVC ||
        codecType == kCMVideoCodecType_HEVCWithAlpha ||
        codecType == 'hvc1' ||
        codecType == 'hev1') {
        return SeafVideoCodecTypeHEVC;
    }
    
    // AV1
    if (codecType == 'av01') {
        return SeafVideoCodecTypeAV1;
    }
    
    return SeafVideoCodecTypeUnsupported;
}

+ (NSString *)videoCodecStringFromTrack:(AVAssetTrack *)videoTrack {
    NSArray *formatDescriptions = videoTrack.formatDescriptions;
    if (formatDescriptions.count == 0) {
        return @"Unknown";
    }
    
    CMFormatDescriptionRef formatDesc = (__bridge CMFormatDescriptionRef)formatDescriptions.firstObject;
    FourCharCode codecType = CMFormatDescriptionGetMediaSubType(formatDesc);
    
    char codecStr[5] = {0};
    codecStr[0] = (codecType >> 24) & 0xFF;
    codecStr[1] = (codecType >> 16) & 0xFF;
    codecStr[2] = (codecType >> 8) & 0xFF;
    codecStr[3] = codecType & 0xFF;
    
    return [NSString stringWithFormat:@"%s (%@)", codecStr, [self codecNameForType:[self detectVideoCodecFromTrack:videoTrack]]];
}

+ (NSString *)audioCodecStringFromDescription:(CMAudioFormatDescriptionRef)audioDesc {
    AudioFormatID formatID = CMAudioFormatDescriptionGetStreamBasicDescription(audioDesc)->mFormatID;
    
    switch (formatID) {
        case kAudioFormatMPEG4AAC:
        case kAudioFormatMPEG4AAC_HE:
        case kAudioFormatMPEG4AAC_HE_V2:
        case kAudioFormatMPEG4AAC_LD:
        case kAudioFormatMPEG4AAC_ELD:
            return @"AAC";
        case kAudioFormatLinearPCM:
            return @"PCM";
        case kAudioFormatAppleLossless:
            return @"ALAC";
        case kAudioFormatMPEGLayer3:
            return @"MP3";
        default: {
            char formatStr[5] = {0};
            formatStr[0] = (formatID >> 24) & 0xFF;
            formatStr[1] = (formatID >> 16) & 0xFF;
            formatStr[2] = (formatID >> 8) & 0xFF;
            formatStr[3] = formatID & 0xFF;
            return [NSString stringWithUTF8String:formatStr];
        }
    }
}

+ (NSString *)codecNameForType:(SeafVideoCodecType)codecType {
    switch (codecType) {
        case SeafVideoCodecTypeH264: return @"H.264/AVC";
        case SeafVideoCodecTypeHEVC: return @"H.265/HEVC";
        case SeafVideoCodecTypeAV1: return @"AV1";
        case SeafVideoCodecTypeUnsupported: return @"Unsupported";
        default: return @"Unknown";
    }
}

#pragma mark - MOV to MP4 Conversion

+ (void)convertMOVToMP4:(NSURL *)sourceURL
             completion:(void (^)(NSURL * _Nullable, NSError * _Nullable))completion {
    [self convertMOVToMP4:sourceURL options:nil completion:completion];
}

+ (void)convertMOVDataToMP4:(NSData *)movData
                 completion:(void (^)(NSData * _Nullable, NSError * _Nullable))completion {
    if (!movData || movData.length == 0) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"SeafVideoConverter"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Empty video data"}];
            completion(nil, error);
        }
        return;
    }
    
    // Check if already MP4
    if ([self isMP4Format:movData]) {
        Debug(@"SeafVideoConverter: Video is already MP4 format, no conversion needed");
        if (completion) {
            completion(movData, nil);
        }
        return;
    }
    
    // Write to temp file
    NSString *tempInputPath = [self temporaryFilePathWithExtension:@"mov"];
    NSError *writeError = nil;
    if (![movData writeToFile:tempInputPath options:NSDataWritingAtomic error:&writeError]) {
        if (completion) {
            completion(nil, writeError);
        }
        return;
    }
    
    NSURL *inputURL = [NSURL fileURLWithPath:tempInputPath];
    
    [self convertMOVToMP4:inputURL completion:^(NSURL *outputURL, NSError *error) {
        // Cleanup input file
        [[NSFileManager defaultManager] removeItemAtPath:tempInputPath error:nil];
        
        if (error || !outputURL) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        // Read output file
        NSData *outputData = [NSData dataWithContentsOfURL:outputURL];
        
        // Cleanup output file
        [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
        
        if (completion) {
            completion(outputData, nil);
        }
    }];
}

+ (void)convertMOVToMP4:(NSURL *)sourceURL
                options:(nullable NSDictionary *)options
             completion:(void (^)(NSURL * _Nullable, NSError * _Nullable))completion {
    
    Debug(@"SeafVideoConverter: Starting MOV to MP4 conversion for %@", sourceURL.lastPathComponent);
    
    // Create asset
    AVAsset *asset = [AVAsset assetWithURL:sourceURL];
    if (!asset) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"SeafVideoConverter"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to load video asset"}];
            completion(nil, error);
        }
        return;
    }
    
    // Check if video track exists
    NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count == 0) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"SeafVideoConverter"
                                                 code:-2
                                             userInfo:@{NSLocalizedDescriptionKey: @"No video track found"}];
            completion(nil, error);
        }
        return;
    }
    
    // Log input format
    SeafVideoCodecType codec = [self detectVideoCodec:asset];
    Debug(@"SeafVideoConverter: Input video codec: %@", [self codecNameForType:codec]);
    
    // Create export session
    // Use passthrough preset to preserve original video quality
    NSString *presetName = AVAssetExportPresetPassthrough;
    
    // Check if passthrough is compatible
    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    if (![compatiblePresets containsObject:presetName]) {
        // Fallback to highest quality preset
        Debug(@"SeafVideoConverter: Passthrough not available, using high quality preset");
        presetName = AVAssetExportPresetHighestQuality;
    }
    
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset
                                                                           presetName:presetName];
    if (!exportSession) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"SeafVideoConverter"
                                                 code:-3
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to create export session"}];
            completion(nil, error);
        }
        return;
    }
    
    // Set output file type to MP4
    exportSession.outputFileType = AVFileTypeMPEG4;
    
    // Generate output path
    NSString *outputPath = [self temporaryFilePathWithExtension:@"mp4"];
    NSURL *outputURL = [NSURL fileURLWithPath:outputPath];
    exportSession.outputURL = outputURL;
    
    // Check if we should preserve audio
    BOOL preserveAudio = YES;
    if (options[@"preserveAudio"]) {
        preserveAudio = [options[@"preserveAudio"] boolValue];
    }
    
    // If not preserving audio, export only video
    if (!preserveAudio) {
        NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
        if (audioTracks.count > 0) {
            // Create a composition without audio
            AVMutableComposition *composition = [AVMutableComposition composition];
            AVMutableCompositionTrack *videoCompTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                                  preferredTrackID:kCMPersistentTrackID_Invalid];
            [videoCompTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, asset.duration)
                                   ofTrack:videoTracks.firstObject
                                    atTime:kCMTimeZero
                                     error:nil];
            
            // Create new export session with composition
            exportSession = [[AVAssetExportSession alloc] initWithAsset:composition
                                                             presetName:presetName];
            exportSession.outputFileType = AVFileTypeMPEG4;
            exportSession.outputURL = outputURL;
        }
    }
    
    // Start export
    Debug(@"SeafVideoConverter: Exporting to MP4...");
    
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        switch (exportSession.status) {
            case AVAssetExportSessionStatusCompleted: {
                Debug(@"SeafVideoConverter: Conversion completed successfully");
                
                // Verify output format
                NSData *outputData = [NSData dataWithContentsOfURL:outputURL];
                NSString *outputBrand = [self detectContainerBrand:outputData];
                Debug(@"SeafVideoConverter: Output container brand: %@", outputBrand);
                
                if (completion) {
                    completion(outputURL, nil);
                }
                break;
            }
            case AVAssetExportSessionStatusFailed: {
                Debug(@"SeafVideoConverter: Conversion failed: %@", exportSession.error);
                if (completion) {
                    completion(nil, exportSession.error);
                }
                break;
            }
            case AVAssetExportSessionStatusCancelled: {
                Debug(@"SeafVideoConverter: Conversion cancelled");
                NSError *error = [NSError errorWithDomain:@"SeafVideoConverter"
                                                     code:-4
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Export cancelled"}];
                if (completion) {
                    completion(nil, error);
                }
                break;
            }
            default:
                break;
        }
    }];
}

#pragma mark - Presentation Timestamp Extraction

+ (int64_t)extractPresentationTimestampFromVideo:(NSURL *)videoURL {
    AVAsset *asset = [AVAsset assetWithURL:videoURL];
    if (!asset) {
        return -1;
    }
    
    // Try to get still image time from metadata
    CMTime stillImageTime = [self extractStillImageTimeFromAsset:asset];
    
    if (CMTIME_IS_VALID(stillImageTime) && !CMTIME_IS_INDEFINITE(stillImageTime)) {
        // Convert to microseconds
        Float64 seconds = CMTimeGetSeconds(stillImageTime);
        return (int64_t)(seconds * 1000000);
    }
    
    // Fallback: use middle of video duration
    CMTime duration = asset.duration;
    if (CMTIME_IS_VALID(duration) && CMTimeGetSeconds(duration) > 0) {
        Float64 middleSeconds = CMTimeGetSeconds(duration) / 2.0;
        Debug(@"SeafVideoConverter: Using video midpoint as timestamp: %.3f seconds", middleSeconds);
        return (int64_t)(middleSeconds * 1000000);
    }
    
    return -1;
}

+ (int64_t)extractPresentationTimestampFromVideoData:(NSData *)videoData {
    if (!videoData || videoData.length == 0) {
        return -1;
    }
    
    // Write to temp file
    NSString *tempPath = [self temporaryFilePathWithExtension:@"mov"];
    if (![videoData writeToFile:tempPath atomically:YES]) {
        return -1;
    }
    
    NSURL *videoURL = [NSURL fileURLWithPath:tempPath];
    int64_t timestamp = [self extractPresentationTimestampFromVideo:videoURL];
    
    // Cleanup
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
    
    return timestamp;
}

+ (CMTime)extractStillImageTimeFromAsset:(AVAsset *)asset {
    // iOS Live Photo videos contain metadata with the still image time
    // This is stored in the QuickTime metadata
    
    NSArray<AVMetadataItem *> *metadata = asset.metadata;
    
    for (AVMetadataItem *item in metadata) {
        // Look for the still image time key
        // The key varies but typically contains "stillImageTime" or similar
        NSString *keyString = nil;
        
        if ([item.key isKindOfClass:[NSString class]]) {
            keyString = (NSString *)item.key;
        } else if ([item.key isKindOfClass:[NSNumber class]]) {
            // Convert FourCC to string
            uint32_t keyValue = [(NSNumber *)item.key unsignedIntValue];
            char keyChars[5] = {0};
            keyChars[0] = (keyValue >> 24) & 0xFF;
            keyChars[1] = (keyValue >> 16) & 0xFF;
            keyChars[2] = (keyValue >> 8) & 0xFF;
            keyChars[3] = keyValue & 0xFF;
            keyString = [NSString stringWithUTF8String:keyChars];
        }
        
        // Check for known still image time keys
        if (keyString) {
            NSString *lowerKey = [keyString lowercaseString];
            if ([lowerKey containsString:@"stillimage"] || 
                [lowerKey containsString:@"still"] ||
                [keyString isEqualToString:@"com.apple.quicktime.still-image-time"]) {
                
                if ([item.value isKindOfClass:[NSNumber class]]) {
                    Float64 timeValue = [(NSNumber *)item.value doubleValue];
                    Debug(@"SeafVideoConverter: Found still image time in metadata: %.3f", timeValue);
                    return CMTimeMakeWithSeconds(timeValue, 600);
                }
            }
        }
        
        // Also check identifier
        if (item.identifier) {
            if ([item.identifier containsString:@"stillImageTime"] ||
                [item.identifier containsString:@"still-image-time"]) {
                if ([item.value isKindOfClass:[NSNumber class]]) {
                    Float64 timeValue = [(NSNumber *)item.value doubleValue];
                    Debug(@"SeafVideoConverter: Found still image time via identifier: %.3f", timeValue);
                    return CMTimeMakeWithSeconds(timeValue, 600);
                }
            }
        }
    }
    
    // Also try to get from track metadata
    NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    for (AVAssetTrack *track in videoTracks) {
        NSArray<AVMetadataItem *> *trackMetadata = track.metadata;
        for (AVMetadataItem *item in trackMetadata) {
            if (item.identifier && [item.identifier containsString:@"stillImage"]) {
                if ([item.value isKindOfClass:[NSNumber class]]) {
                    Float64 timeValue = [(NSNumber *)item.value doubleValue];
                    return CMTimeMakeWithSeconds(timeValue, 600);
                }
            }
        }
    }
    
    Debug(@"SeafVideoConverter: Still image time not found in metadata, will use fallback");
    return kCMTimeInvalid;
}

#pragma mark - Audio Validation

+ (SeafAudioComplianceStatus)checkAudioCompliance:(AVAsset *)asset {
    NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    if (audioTracks.count == 0) {
        return SeafAudioComplianceStatusNoAudio;
    }
    
    return [self checkAudioComplianceForTrack:audioTracks.firstObject];
}

+ (SeafAudioComplianceStatus)checkAudioComplianceForTrack:(AVAssetTrack *)audioTrack {
    NSArray *formatDescriptions = audioTrack.formatDescriptions;
    if (formatDescriptions.count == 0) {
        return SeafAudioComplianceStatusNoAudio;
    }
    
    CMAudioFormatDescriptionRef audioDesc = (__bridge CMAudioFormatDescriptionRef)formatDescriptions.firstObject;
    const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioDesc);
    
    if (!asbd) {
        return SeafAudioComplianceStatusNonCompliant;
    }
    
    // Check codec - must be AAC
    BOOL isAAC = (asbd->mFormatID == kAudioFormatMPEG4AAC ||
                  asbd->mFormatID == kAudioFormatMPEG4AAC_HE ||
                  asbd->mFormatID == kAudioFormatMPEG4AAC_HE_V2 ||
                  asbd->mFormatID == kAudioFormatMPEG4AAC_LD ||
                  asbd->mFormatID == kAudioFormatMPEG4AAC_ELD);
    
    // Check sample rate - must be 44.1kHz, 48kHz, or 96kHz
    BOOL validSampleRate = (asbd->mSampleRate == 44100.0 ||
                            asbd->mSampleRate == 48000.0 ||
                            asbd->mSampleRate == 96000.0);
    
    // Check channels - must be mono (1) or stereo (2)
    BOOL validChannels = (asbd->mChannelsPerFrame == 1 || asbd->mChannelsPerFrame == 2);
    
    if (isAAC && validSampleRate && validChannels) {
        return SeafAudioComplianceStatusCompliant;
    }
    
    Debug(@"SeafVideoConverter: Audio non-compliant - AAC:%d, SampleRate:%.0f, Channels:%d",
          isAAC, asbd->mSampleRate, asbd->mChannelsPerFrame);
    
    return SeafAudioComplianceStatusNonCompliant;
}

#pragma mark - Utility Methods

+ (NSString *)temporaryFilePathWithExtension:(NSString *)extension {
    NSString *tempDir = NSTemporaryDirectory();
    NSString *filename = [NSString stringWithFormat:@"seafile_video_%@.%@",
                          [[NSUUID UUID] UUIDString], extension];
    return [tempDir stringByAppendingPathComponent:filename];
}

+ (void)cleanupTemporaryFiles:(NSArray<NSString *> *)paths {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        [fm removeItemAtPath:path error:nil];
    }
}

@end

