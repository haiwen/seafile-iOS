//
//  SeafLivePhotoSaver.m
//  Seafile
//
//  Saves Motion Photos (HEIC with embedded video) as iOS Live Photos.
//

#import "SeafLivePhotoSaver.h"
#import "SeafMotionPhotoExtractor.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>

@implementation SeafLivePhotoSaver

#pragma mark - Main Save Methods

+ (void)saveLivePhotoFromPath:(NSString *)path
                   completion:(nullable SeafLivePhotoSaveCompletion)completion {
    NSData *fileData = [NSData dataWithContentsOfFile:path];
    if (!fileData) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"SeafLivePhotoSaver" 
                                                 code:-1 
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to read file"}];
            completion(NO, error);
        }
        return;
    }
    
    [self saveLivePhotoFromData:fileData completion:completion];
}

+ (void)saveLivePhotoFromData:(NSData *)data
                   completion:(nullable SeafLivePhotoSaveCompletion)completion {
    // Step 1: Extract image and video from Motion Photo
    NSData *imageData = [SeafMotionPhotoExtractor extractImageFromMotionPhoto:data];
    NSString *tempVideoPath = [SeafMotionPhotoExtractor extractVideoToTempFileFromMotionPhoto:data];
    
    if (!imageData || !tempVideoPath) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"SeafLivePhotoSaver" 
                                                 code:-2 
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to extract Motion Photo components"}];
            completion(NO, error);
        }
        return;
    }
    
    // Step 2: Generate shared content identifier for Live Photo pairing
    NSString *contentIdentifier = [[NSUUID UUID] UUIDString];
    
    // Step 3: Write image with Live Photo metadata
    NSString *tempImagePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"livephoto_image_%@.heic", [[NSUUID UUID] UUIDString]]];
    
    BOOL imageWriteSuccess = [self writeImageDataWithLivePhotoMetadata:imageData 
                                                                toPath:tempImagePath 
                                                     contentIdentifier:contentIdentifier];
    if (!imageWriteSuccess) {
        // Fallback: try writing without metadata modification
        NSError *writeError = nil;
        imageWriteSuccess = [imageData writeToFile:tempImagePath options:NSDataWritingAtomic error:&writeError];
        if (!imageWriteSuccess) {
            [[NSFileManager defaultManager] removeItemAtPath:tempVideoPath error:nil];
            if (completion) {
                NSError *error = [NSError errorWithDomain:@"SeafLivePhotoSaver" 
                                                     code:-3 
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to write image file"}];
                completion(NO, error);
            }
            return;
        }
    }
    
    // Step 4: Convert video to MOV format with Live Photo metadata
    [self convertVideoToLivePhotoFormat:tempVideoPath 
                      contentIdentifier:contentIdentifier 
                             completion:^(NSString *convertedVideoPath, NSError *error) {
        if (!convertedVideoPath) {
            [[NSFileManager defaultManager] removeItemAtPath:tempImagePath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:tempVideoPath error:nil];
            if (completion) {
                completion(NO, error);
            }
            return;
        }
        
        // Clean up original temp video if different from converted
        if (![tempVideoPath isEqualToString:convertedVideoPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:tempVideoPath error:nil];
        }
        
        // Step 5: Save to Photos library as Live Photo
        [self saveLivePhotoToLibraryWithImagePath:tempImagePath
                                        videoPath:convertedVideoPath
                                       completion:completion];
    }];
}

+ (BOOL)canSaveAsLivePhotoAtPath:(NSString *)path {
    return [SeafMotionPhotoExtractor mightBeMotionPhotoAtPath:path] &&
           [SeafMotionPhotoExtractor isMotionPhotoAtPath:path];
}

#pragma mark - Private Methods

/**
 * Write HEIC image data with Live Photo content identifier metadata.
 */
+ (BOOL)writeImageDataWithLivePhotoMetadata:(NSData *)imageData 
                                     toPath:(NSString *)path 
                          contentIdentifier:(NSString *)contentIdentifier {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    if (!source) {
        return NO;
    }
    
    CFStringRef uti = CGImageSourceGetType(source);
    if (!uti) {
        CFRelease(source);
        return NO;
    }
    
    NSURL *destURL = [NSURL fileURLWithPath:path];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)destURL, uti, 1, NULL);
    if (!destination) {
        CFRelease(source);
        return NO;
    }
    
    // Copy existing properties and add Live Photo content identifier
    CFDictionaryRef sourceProps = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
    NSMutableDictionary *props = sourceProps ? [(__bridge NSDictionary *)sourceProps mutableCopy] : [NSMutableDictionary dictionary];
    if (sourceProps) {
        CFRelease(sourceProps);
    }
    
    // Add content identifier to Apple maker note (key 17 is the Live Photo content identifier)
    NSMutableDictionary *makerApple = [props[@"{MakerApple}"] mutableCopy] ?: [NSMutableDictionary dictionary];
    makerApple[@"17"] = contentIdentifier;
    props[@"{MakerApple}"] = makerApple;
    
    CGImageDestinationAddImageFromSource(destination, source, 0, (__bridge CFDictionaryRef)props);
    BOOL success = CGImageDestinationFinalize(destination);
    
    CFRelease(destination);
    CFRelease(source);
    
    return success;
}

/**
 * Convert video to MOV format with Live Photo metadata.
 */
+ (void)convertVideoToLivePhotoFormat:(NSString *)inputPath 
                    contentIdentifier:(NSString *)contentIdentifier
                           completion:(void (^)(NSString *outputPath, NSError *error))completion {
    NSURL *inputURL = [NSURL fileURLWithPath:inputPath];
    AVURLAsset *asset = [AVURLAsset assetWithURL:inputURL];
    
    // Select best export preset - prefer HEVC for Live Photos
    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    NSArray *preferredPresets = @[
        AVAssetExportPresetPassthrough,
        AVAssetExportPresetHEVCHighestQuality,
        AVAssetExportPresetHEVC1920x1080,
        AVAssetExportPresetHighestQuality
    ];
    
    NSString *presetName = nil;
    for (NSString *preset in preferredPresets) {
        if ([compatiblePresets containsObject:preset]) {
            presetName = preset;
            break;
        }
    }
    if (!presetName) {
        presetName = compatiblePresets.firstObject;
    }
    
    if (!presetName) {
        NSError *error = [NSError errorWithDomain:@"SeafLivePhotoSaver" code:-4
                                         userInfo:@{NSLocalizedDescriptionKey: @"No compatible export preset"}];
        if (completion) completion(nil, error);
        return;
    }
    
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset presetName:presetName];
    if (!exportSession) {
        NSError *error = [NSError errorWithDomain:@"SeafLivePhotoSaver" code:-5
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to create export session"}];
        if (completion) completion(nil, error);
        return;
    }
    
    // Configure output
    NSString *outputPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"livephoto_video_%@.mov", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
    
    exportSession.outputURL = [NSURL fileURLWithPath:outputPath];
    exportSession.outputFileType = AVFileTypeQuickTimeMovie;
    exportSession.shouldOptimizeForNetworkUse = NO;
    
    // Add Live Photo metadata
    AVMutableMetadataItem *identifierItem = [AVMutableMetadataItem metadataItem];
    identifierItem.key = @"com.apple.quicktime.content.identifier";
    identifierItem.keySpace = AVMetadataKeySpaceQuickTimeMetadata;
    identifierItem.value = contentIdentifier;
    identifierItem.dataType = (__bridge NSString *)kCMMetadataBaseDataType_UTF8;
    
    AVMutableMetadataItem *stillImageTimeItem = [AVMutableMetadataItem metadataItem];
    stillImageTimeItem.key = @"com.apple.quicktime.still-image-time";
    stillImageTimeItem.keySpace = AVMetadataKeySpaceQuickTimeMetadata;
    stillImageTimeItem.value = @(0);
    stillImageTimeItem.dataType = (__bridge NSString *)kCMMetadataBaseDataType_SInt8;
    
    exportSession.metadata = @[identifierItem, stillImageTimeItem];
    
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        if (exportSession.status == AVAssetExportSessionStatusCompleted) {
            if (completion) completion(outputPath, nil);
        } else {
            if (completion) completion(nil, exportSession.error);
        }
    }];
}

/**
 * Save the prepared image and video files as a Live Photo to the Photos library.
 */
+ (void)saveLivePhotoToLibraryWithImagePath:(NSString *)tempImagePath
                                  videoPath:(NSString *)tempVideoPath
                                 completion:(nullable SeafLivePhotoSaveCompletion)completion {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:tempImagePath] || ![fm fileExistsAtPath:tempVideoPath]) {
        [fm removeItemAtPath:tempImagePath error:nil];
        [fm removeItemAtPath:tempVideoPath error:nil];
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"SeafLivePhotoSaver" code:-6
                                             userInfo:@{NSLocalizedDescriptionKey: @"Missing temp files"}];
            completion(NO, error);
        }
        return;
    }
    
    NSURL *imageURL = [NSURL fileURLWithPath:tempImagePath];
    NSURL *videoURL = [NSURL fileURLWithPath:tempVideoPath];
    
    __block NSString *imagePath = tempImagePath;
    __block NSString *videoPath = tempVideoPath;
    
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
        
        PHAssetResourceCreationOptions *imageOptions = [[PHAssetResourceCreationOptions alloc] init];
        imageOptions.shouldMoveFile = NO;
        [request addResourceWithType:PHAssetResourceTypePhoto
                             fileURL:imageURL
                             options:imageOptions];
        
        PHAssetResourceCreationOptions *videoOptions = [[PHAssetResourceCreationOptions alloc] init];
        videoOptions.shouldMoveFile = NO;
        [request addResourceWithType:PHAssetResourceTypePairedVideo
                             fileURL:videoURL
                             options:videoOptions];
        
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        // Clean up temp files
        [[NSFileManager defaultManager] removeItemAtPath:imagePath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:videoPath error:nil];
        
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(success, error);
            });
        }
    }];
}

@end
