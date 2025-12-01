//
//  SeafMotionPhotoExtractor.m
//  Seafile
//
//  Created for Motion Photo support.
//  Supports standard HEIC Motion Photo container format with mpvd box.
//

#import "SeafMotionPhotoExtractor.h"
#import "Debug.h"
#import "SeafXMPHandler.h"
#import "SeafISOBMFFParser.h"
#import <AVFoundation/AVFoundation.h>

@implementation SeafMotionPhotoExtractor

#pragma mark - Detection Methods

+ (BOOL)isMotionPhoto:(NSData *)data {
    if (!data || data.length < 100) {
        return NO;
    }
    
    // Method 1: Check for mpvd box (standard HEIC Motion Photo format)
    if ([self hasMPVDBox:data]) {
        Debug(@"SeafMotionPhotoExtractor: Detected Motion Photo via mpvd box");
        return YES;
    }
    
    // Method 2: Check XMP metadata
    SeafMotionPhotoXMP *xmp = [SeafXMPHandler parseXMPFromImageData:data];
    if (xmp && xmp.isValidMotionPhoto) {
        Debug(@"SeafMotionPhotoExtractor: Detected Motion Photo via XMP metadata");
        return YES;
    }
    
    // Method 3: Search for video signatures in the data (fallback for non-standard formats)
    if ([self hasEmbeddedVideoSignature:data]) {
        Debug(@"SeafMotionPhotoExtractor: Detected Motion Photo via video signature");
        return YES;
    }
    
    return NO;
}

+ (BOOL)isMotionPhotoAtPath:(NSString *)path {
    // First do a quick check
    if (![self mightBeMotionPhotoAtPath:path]) {
        return NO;
    }
    
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        return NO;
    }
    
    return [self isMotionPhoto:data];
}

+ (BOOL)mightBeMotionPhotoAtPath:(NSString *)path {
    NSString *ext = path.pathExtension.lowercaseString;
    
    // Motion Photos are typically HEIC or JPEG
    if (![@[@"heic", @"heif", @"jpg", @"jpeg"] containsObject:ext]) {
        return NO;
    }
    
    // Check file size - Motion Photos are typically larger than regular photos
    // A Motion Photo with video should be at least 500KB
    NSError *error = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
    if (error) {
        return NO;
    }
    
    unsigned long long fileSize = [attrs fileSize];
    return fileSize > 500 * 1024; // 500KB minimum
}

#pragma mark - MPVD Box Detection (Standard Format)

+ (BOOL)hasMPVDBox:(NSData *)data {
    SeafISOBMFFParser *parser = [[SeafISOBMFFParser alloc] initWithData:data];
    NSArray<SeafISOBMFFBox *> *boxes = [parser parseTopLevelBoxes];
    
    for (SeafISOBMFFBox *box in boxes) {
        if ([box.type isEqualToString:@"mpvd"]) {
            return YES;
        }
    }
    return NO;
}

+ (nullable SeafISOBMFFBox *)findMPVDBox:(NSData *)data {
    SeafISOBMFFParser *parser = [[SeafISOBMFFParser alloc] initWithData:data];
    NSArray<SeafISOBMFFBox *> *boxes = [parser parseTopLevelBoxes];
    
    for (SeafISOBMFFBox *box in boxes) {
        if ([box.type isEqualToString:@"mpvd"]) {
            return box;
        }
    }
    return nil;
}

+ (nullable SeafISOBMFFBox *)findXMPUuidBox:(NSData *)data {
    SeafISOBMFFParser *parser = [[SeafISOBMFFParser alloc] initWithData:data];
    NSArray<SeafISOBMFFBox *> *boxes = [parser parseTopLevelBoxes];
    
    // XMP UUID: BE7ACFCB-97A9-42E8-9C71-999491E3AFAC
    uint8_t xmpUUID[16] = {
        0xBE, 0x7A, 0xCF, 0xCB, 0x97, 0xA9, 0x42, 0xE8,
        0x9C, 0x71, 0x99, 0x94, 0x91, 0xE3, 0xAF, 0xAC
    };
    
    for (SeafISOBMFFBox *box in boxes) {
        if ([box.type isEqualToString:@"uuid"]) {
            // Check if this is the XMP UUID
            if (box.size >= 24) { // 8 (header) + 16 (UUID)
                uint8_t boxUUID[16];
                [data getBytes:boxUUID range:NSMakeRange(box.offset + 8, 16)];
                if (memcmp(boxUUID, xmpUUID, 16) == 0) {
                    return box;
                }
            }
        }
    }
    return nil;
}

#pragma mark - Video Signature Detection (Fallback)

+ (BOOL)hasEmbeddedVideoSignature:(NSData *)data {
    if (data.length < 100) {
        return NO;
    }
    
    // Search for video ftyp signatures
    NSArray *signatures = @[
        @"ftypisom",
        @"ftypiso2",
        @"ftypmp41",
        @"ftypmp42",
        @"ftypqt  ",  // QuickTime - used by iOS Live Photo MOV
        @"ftypM4V ",
        @"ftypavc1",
        @"ftypmp4"    // partial match for mp41/mp42
    ];
    
    // For Motion Photo, video is appended at the end of the image
    // Minimum image size is around 50KB, so start from there
    NSUInteger minImageSize = 50 * 1024;
    NSUInteger searchStart = data.length > minImageSize ? minImageSize : 0;
    
    // If file is larger than 10MB, limit search to last 10MB for performance
    if (data.length > 10 * 1024 * 1024) {
        searchStart = data.length - 10 * 1024 * 1024;
    }
    
    NSRange searchRange = NSMakeRange(searchStart, data.length - searchStart);
    
    for (NSString *sig in signatures) {
        NSData *sigData = [sig dataUsingEncoding:NSUTF8StringEncoding];
        NSRange found = [data rangeOfData:sigData options:0 range:searchRange];
        if (found.location != NSNotFound) {
            Debug(@"SeafMotionPhotoExtractor: Found video signature '%@' at offset %lu", sig, (unsigned long)found.location);
            return YES;
        }
    }
    
    // Also check for generic "ftyp" followed by any brand
    NSData *ftypMarker = [@"ftyp" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange found = [data rangeOfData:ftypMarker options:0 range:searchRange];
    if (found.location != NSNotFound && found.location >= 4) {
        Debug(@"SeafMotionPhotoExtractor: Found generic ftyp marker at offset %lu", (unsigned long)found.location);
        return YES;
    }
    
    return NO;
}

#pragma mark - Information Extraction

+ (nullable SeafMotionPhotoXMP *)getMotionPhotoInfo:(NSData *)data {
    if (!data) {
        return nil;
    }
    
    // First check for XMP uuid box at file level
    SeafISOBMFFBox *xmpBox = [self findXMPUuidBox:data];
    if (xmpBox) {
        // Extract XMP data from uuid box (after the 16-byte UUID)
        NSUInteger xmpOffset = xmpBox.offset + 8 + 16; // header(8) + uuid(16)
        NSUInteger xmpLength = xmpBox.size - 8 - 16;
        if (xmpOffset + xmpLength <= data.length) {
            NSData *xmpData = [data subdataWithRange:NSMakeRange(xmpOffset, xmpLength)];
            SeafMotionPhotoXMP *xmp = [SeafXMPHandler parseXMPData:xmpData];
            if (xmp && xmp.isMotionPhoto) {
                // Also get video length from mpvd box if available
                SeafISOBMFFBox *mpvdBox = [self findMPVDBox:data];
                if (mpvdBox) {
                    xmp.videoLength = mpvdBox.size - mpvdBox.headerSize;
                }
                return xmp;
            }
        }
    }
    
    // Try parsing XMP from image metadata
    SeafMotionPhotoXMP *xmp = [SeafXMPHandler parseXMPFromImageData:data];
    
    // If XMP parsing failed but we detect embedded video, create a basic XMP object
    if (!xmp) {
        BOOL hasVideo = [self hasMPVDBox:data] || [self hasEmbeddedVideoSignature:data];
        if (hasVideo) {
            xmp = [[SeafMotionPhotoXMP alloc] init];
            xmp.isMotionPhoto = YES;
            
            // Try to find video length
            SeafISOBMFFBox *mpvdBox = [self findMPVDBox:data];
            if (mpvdBox) {
                xmp.videoLength = mpvdBox.size - mpvdBox.headerSize;
            } else {
                NSUInteger videoOffset = [self findVideoOffsetBySignature:data];
                if (videoOffset != NSNotFound) {
                    xmp.videoLength = data.length - videoOffset;
                }
            }
        }
    }
    
    return xmp;
}

+ (nullable SeafMotionPhotoXMP *)getMotionPhotoInfoAtPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    return [self getMotionPhotoInfo:data];
}

+ (NSUInteger)getVideoOffsetInMotionPhoto:(NSData *)data {
    // Method 1: Check for mpvd box (standard format)
    SeafISOBMFFBox *mpvdBox = [self findMPVDBox:data];
    if (mpvdBox) {
        // Video data starts after the mpvd header
        return mpvdBox.offset + mpvdBox.headerSize;
    }
    
    // Method 2: Use XMP metadata
    SeafMotionPhotoXMP *xmp = [self getMotionPhotoInfo:data];
    if (xmp && xmp.videoLength > 0) {
        return [xmp videoOffsetInFileOfSize:data.length];
    }
    
    // Method 3: Fallback - search for video signature
    return [self findVideoOffsetBySignature:data];
}

+ (NSUInteger)getVideoLengthInMotionPhoto:(NSData *)data {
    // Method 1: Check for mpvd box (standard format)
    SeafISOBMFFBox *mpvdBox = [self findMPVDBox:data];
    if (mpvdBox) {
        return mpvdBox.size - mpvdBox.headerSize;
    }
    
    // Method 2: Use XMP metadata
    SeafMotionPhotoXMP *xmp = [self getMotionPhotoInfo:data];
    if (xmp && xmp.videoLength > 0) {
        return xmp.videoLength;
    }
    
    // Method 3: Fallback - calculate from offset
    NSUInteger offset = [self findVideoOffsetBySignature:data];
    if (offset != NSNotFound && offset < data.length) {
        return data.length - offset;
    }
    
    return 0;
}

+ (NSUInteger)findVideoOffsetBySignature:(NSData *)data {
    if (data.length < 100) {
        return NSNotFound;
    }
    
    // Video signatures to search for (ftyp + brand)
    NSArray *signatures = @[
        @"ftypisom",
        @"ftypiso2",
        @"ftypmp41",
        @"ftypmp42",
        @"ftypqt  ",  // QuickTime - iOS Live Photo
        @"ftypM4V ",
        @"ftypavc1"
    ];
    
    // Minimum image size - start searching after this
    NSUInteger minImageSize = 50 * 1024;
    NSUInteger searchStart = data.length > minImageSize ? minImageSize : 0;
    
    NSUInteger earliestOffset = NSNotFound;
    
    for (NSString *sig in signatures) {
        NSData *sigData = [sig dataUsingEncoding:NSUTF8StringEncoding];
        NSRange searchRange = NSMakeRange(searchStart, data.length - searchStart);
        NSRange found = [data rangeOfData:sigData options:0 range:searchRange];
        
        if (found.location != NSNotFound) {
            // The ftyp box starts 4 bytes before the "ftyp" string (size field)
            NSUInteger videoStart = found.location - 4;
            if (videoStart >= searchStart && videoStart < earliestOffset) {
                earliestOffset = videoStart;
                Debug(@"SeafMotionPhotoExtractor: Found video at offset %lu with signature '%@'", 
                      (unsigned long)videoStart, sig);
            }
        }
    }
    
    // If no specific brand found, try generic ftyp search
    if (earliestOffset == NSNotFound) {
        NSData *ftypMarker = [@"ftyp" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange searchRange = NSMakeRange(searchStart, data.length - searchStart);
        NSRange found = [data rangeOfData:ftypMarker options:0 range:searchRange];
        
        if (found.location != NSNotFound && found.location >= 4) {
            earliestOffset = found.location - 4;
            Debug(@"SeafMotionPhotoExtractor: Found video at offset %lu with generic ftyp marker", 
                  (unsigned long)earliestOffset);
        }
    }
    
    return earliestOffset;
}

#pragma mark - Data Extraction

+ (nullable NSData *)extractImageFromMotionPhoto:(NSData *)data {
    if (!data || data.length < 100) {
        return nil;
    }
    
    // For standard HEIC Motion Photo format, we need to remove trailing boxes (uuid, mpvd)
    // and return just the original HEIC structure (ftyp + meta + mdat)
    SeafISOBMFFParser *parser = [[SeafISOBMFFParser alloc] initWithData:data];
    NSArray<SeafISOBMFFBox *> *boxes = [parser parseTopLevelBoxes];
    
    // Find the last original HEIC box (usually mdat or free)
    // Skip uuid (XMP) and mpvd (video) boxes
    NSUInteger imageEndOffset = 0;
    
    for (SeafISOBMFFBox *box in boxes) {
        if ([box.type isEqualToString:@"uuid"] || [box.type isEqualToString:@"mpvd"]) {
            // These are Motion Photo specific boxes, stop here
            break;
        }
        imageEndOffset = box.offset + box.size;
    }
    
    if (imageEndOffset > 0 && imageEndOffset <= data.length) {
        Debug(@"SeafMotionPhotoExtractor: Extracting image (0 - %lu bytes)", (unsigned long)imageEndOffset);
        return [data subdataWithRange:NSMakeRange(0, imageEndOffset)];
    }
    
    // Fallback: use video offset
    NSUInteger videoOffset = [self getVideoOffsetInMotionPhoto:data];
    if (videoOffset != NSNotFound && videoOffset > 0) {
        return [data subdataWithRange:NSMakeRange(0, videoOffset)];
    }
    
    return nil;
}

+ (nullable NSData *)extractVideoFromMotionPhoto:(NSData *)data {
    if (!data || data.length < 100) {
        return nil;
    }
    
    // Method 1: Extract from mpvd box (standard format)
    SeafISOBMFFBox *mpvdBox = [self findMPVDBox:data];
    if (mpvdBox) {
        NSUInteger videoOffset = mpvdBox.offset + mpvdBox.headerSize;
        NSUInteger videoLength = mpvdBox.size - mpvdBox.headerSize;
        
        if (videoOffset + videoLength <= data.length) {
            Debug(@"SeafMotionPhotoExtractor: Extracting video from mpvd box (%lu bytes)", (unsigned long)videoLength);
            return [data subdataWithRange:NSMakeRange(videoOffset, videoLength)];
        }
    }
    
    // Method 2: Fallback - extract from video offset
    NSUInteger videoOffset = [self getVideoOffsetInMotionPhoto:data];
    if (videoOffset != NSNotFound && videoOffset < data.length) {
        Debug(@"SeafMotionPhotoExtractor: Extracting video from offset %lu", (unsigned long)videoOffset);
        return [data subdataWithRange:NSMakeRange(videoOffset, data.length - videoOffset)];
    }
    
    return nil;
}

+ (nullable NSString *)extractVideoToTempFileFromMotionPhoto:(NSData *)data {
    NSData *videoData = [self extractVideoFromMotionPhoto:data];
    
    if (!videoData) {
        return nil;
    }
    
    // Determine video extension based on format
    NSString *ext = @"mp4"; // Default to MP4
    if (videoData.length >= 12) {
        char typeBytes[5] = {0};
        [videoData getBytes:typeBytes range:NSMakeRange(4, 4)];
        
        if (strcmp(typeBytes, "ftyp") == 0) {
            char brand[5] = {0};
            [videoData getBytes:brand range:NSMakeRange(8, 4)];
            if (strcmp(brand, "qt  ") == 0 || strcmp(brand, "M4V ") == 0) {
                ext = @"mov";
            }
        } else if (strcmp(typeBytes, "moov") == 0 || strcmp(typeBytes, "wide") == 0) {
            ext = @"mov"; // Legacy QuickTime format
        }
    }
    
    // Create temporary file
    NSString *tempDir = NSTemporaryDirectory();
    NSString *filename = [NSString stringWithFormat:@"motion_photo_video_%@.%@",
                          [[NSUUID UUID] UUIDString], ext];
    NSString *tempPath = [tempDir stringByAppendingPathComponent:filename];
    
    NSError *error = nil;
    if (![videoData writeToFile:tempPath options:NSDataWritingAtomic error:&error]) {
        Debug(@"SeafMotionPhotoExtractor: Failed to write video to temp file: %@", error);
        return nil;
    }
    
    Debug(@"SeafMotionPhotoExtractor: Video extracted to temp file: %@", tempPath);
    return tempPath;
}

+ (nullable NSString *)extractVideoToTempFileFromMotionPhotoAtPath:(NSString *)sourcePath {
    NSData *data = [NSData dataWithContentsOfFile:sourcePath];
    if (!data) {
        return nil;
    }
    
    return [self extractVideoToTempFileFromMotionPhoto:data];
}

+ (BOOL)extractFromMotionPhoto:(NSData *)data
                     imageData:(NSData * _Nullable * _Nullable)imageData
                     videoData:(NSData * _Nullable * _Nullable)videoData {
    if (!data || data.length < 100) {
        return NO;
    }
    
    NSData *extractedImage = [self extractImageFromMotionPhoto:data];
    NSData *extractedVideo = [self extractVideoFromMotionPhoto:data];
    
    if (!extractedImage && !extractedVideo) {
        return NO;
    }
    
    if (imageData) {
        *imageData = extractedImage;
    }
    
    if (videoData) {
        *videoData = extractedVideo;
    }
    
    return YES;
}

#pragma mark - File Operations

+ (BOOL)extractVideoFromMotionPhotoAtPath:(NSString *)sourcePath
                                   toPath:(NSString *)destinationPath
                                    error:(NSError * _Nullable * _Nullable)error {
    NSData *data = [NSData dataWithContentsOfFile:sourcePath options:0 error:error];
    if (!data) {
        return NO;
    }
    
    NSData *videoData = [self extractVideoFromMotionPhoto:data];
    if (!videoData) {
        if (error) {
            *error = [NSError errorWithDomain:@"SeafMotionPhotoExtractor"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to extract video from Motion Photo"}];
        }
        return NO;
    }
    
    return [videoData writeToFile:destinationPath options:NSDataWritingAtomic error:error];
}

+ (BOOL)extractImageFromMotionPhotoAtPath:(NSString *)sourcePath
                                   toPath:(NSString *)destinationPath
                                    error:(NSError * _Nullable * _Nullable)error {
    NSData *data = [NSData dataWithContentsOfFile:sourcePath options:0 error:error];
    if (!data) {
        return NO;
    }
    
    NSData *imageData = [self extractImageFromMotionPhoto:data];
    if (!imageData) {
        if (error) {
            *error = [NSError errorWithDomain:@"SeafMotionPhotoExtractor"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to extract image from Motion Photo"}];
        }
        return NO;
    }
    
    return [imageData writeToFile:destinationPath options:NSDataWritingAtomic error:error];
}

#pragma mark - Debug / Utility

+ (void)logMotionPhotoStructure:(NSData *)data {
    Debug(@"╔══════════════════════════════════════════════════════════════════════╗");
    Debug(@"║          MOTION PHOTO STRUCTURE ANALYSIS                              ║");
    Debug(@"╠══════════════════════════════════════════════════════════════════════╣");
    Debug(@"║ Total file size: %lu bytes (%.2f MB)", (unsigned long)data.length, data.length / 1024.0 / 1024.0);
    
    // 1. Check file type
    Debug(@"╠══════════════════════════════════════════════════════════════════════╣");
    Debug(@"║ [Step 1] Checking file type...");
    
    uint8_t header[12];
    [data getBytes:header range:NSMakeRange(0, MIN(12, data.length))];
    Debug(@"║   First 12 bytes: %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X",
          header[0], header[1], header[2], header[3], header[4], header[5],
          header[6], header[7], header[8], header[9], header[10], header[11]);
    
    BOOL isJPEG = (header[0] == 0xFF && header[1] == 0xD8);
    BOOL isHEIC = (header[4] == 'f' && header[5] == 't' && header[6] == 'y' && header[7] == 'p');
    
    if (isJPEG) {
        Debug(@"║   File type: JPEG");
    } else if (isHEIC) {
        char brand[5] = {0};
        memcpy(brand, &header[8], 4);
        Debug(@"║   File type: HEIC/ISOBMFF (brand: %s)", brand);
    } else {
        Debug(@"║   File type: UNKNOWN");
    }
    
    // 2. Parse ISOBMFF structure
    Debug(@"╠══════════════════════════════════════════════════════════════════════╣");
    Debug(@"║ [Step 2] Parsing ISOBMFF box structure...");
    
    SeafISOBMFFParser *parser = [[SeafISOBMFFParser alloc] initWithData:data];
    NSArray<SeafISOBMFFBox *> *boxes = [parser parseTopLevelBoxes];
    
    Debug(@"║   Found %lu top-level boxes:", (unsigned long)boxes.count);
    
    SeafISOBMFFBox *ftypBox = nil;
    SeafISOBMFFBox *metaBox = nil;
    SeafISOBMFFBox *mdatBox = nil;
    SeafISOBMFFBox *mpvdBox = nil;
    SeafISOBMFFBox *xmpUuidBox = nil;
    
    for (SeafISOBMFFBox *box in boxes) {
        Debug(@"║   ├── '%@': offset=%llu, size=%llu, headerSize=%u",
              box.type, box.offset, box.size, box.headerSize);
        
        if ([box.type isEqualToString:@"ftyp"]) {
            ftypBox = box;
            // Show brand info
            if (box.size >= 12) {
                char brand[5] = {0};
                [data getBytes:brand range:NSMakeRange(box.offset + 8, 4)];
                Debug(@"║   │   └── Major brand: %s", brand);
            }
        } else if ([box.type isEqualToString:@"meta"]) {
            metaBox = box;
            // Show children count
            if (box.children.count > 0) {
                Debug(@"║   │   └── Children: %lu boxes", (unsigned long)box.children.count);
                for (SeafISOBMFFBox *child in box.children) {
                    Debug(@"║   │       ├── '%@': size=%llu", child.type, child.size);
                }
            }
        } else if ([box.type isEqualToString:@"mdat"]) {
            mdatBox = box;
        } else if ([box.type isEqualToString:@"mpvd"]) {
            mpvdBox = box;
            Debug(@"║   │   └── Video data size: %llu bytes", box.size - box.headerSize);
        } else if ([box.type isEqualToString:@"uuid"]) {
            // Check UUID type
            if (box.size >= 24) {
                uint8_t boxUUID[16];
                [data getBytes:boxUUID range:NSMakeRange(box.offset + 8, 16)];
                
                // XMP UUID
                uint8_t xmpUUID[16] = {
                    0xBE, 0x7A, 0xCF, 0xCB, 0x97, 0xA9, 0x42, 0xE8,
                    0x9C, 0x71, 0x99, 0x94, 0x91, 0xE3, 0xAF, 0xAC
                };
                
                if (memcmp(boxUUID, xmpUUID, 16) == 0) {
                    xmpUuidBox = box;
                    Debug(@"║   │   └── Contains XMP metadata (Adobe XMP UUID)");
                } else {
                    Debug(@"║   │   └── Unknown UUID: %02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                          boxUUID[0], boxUUID[1], boxUUID[2], boxUUID[3],
                          boxUUID[4], boxUUID[5], boxUUID[6], boxUUID[7],
                          boxUUID[8], boxUUID[9], boxUUID[10], boxUUID[11],
                          boxUUID[12], boxUUID[13], boxUUID[14], boxUUID[15]);
                }
            }
        }
    }
    
    // 3. Check for XMP metadata
    Debug(@"╠══════════════════════════════════════════════════════════════════════╣");
    Debug(@"║ [Step 3] Checking XMP metadata...");
    
    SeafMotionPhotoXMP *xmp = [SeafXMPHandler parseXMPFromImageData:data];
    if (xmp) {
        Debug(@"║   XMP found:");
        Debug(@"║   ├── isMotionPhoto: %@", xmp.isMotionPhoto ? @"YES" : @"NO");
        Debug(@"║   ├── version: %ld", (long)xmp.motionPhotoVersion);
        Debug(@"║   ├── videoLength: %lu bytes", (unsigned long)xmp.videoLength);
        Debug(@"║   ├── presentationTimestampUs: %lld", xmp.presentationTimestampUs);
        Debug(@"║   ├── primaryMime: %@", xmp.primaryMime ?: @"(null)");
        Debug(@"║   └── videoMime: %@", xmp.videoMime ?: @"(null)");
    } else {
        Debug(@"║   XMP NOT found in standard locations");
        
        // Try to find XMP by searching raw data
        NSData *xmpMarker = [@"<x:xmpmeta" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange xmpRange = [data rangeOfData:xmpMarker options:0 range:NSMakeRange(0, data.length)];
        if (xmpRange.location != NSNotFound) {
            Debug(@"║   BUT found '<x:xmpmeta' marker at offset %lu", (unsigned long)xmpRange.location);
        }
    }
    
    // 4. Search for video signatures
    Debug(@"╠══════════════════════════════════════════════════════════════════════╣");
    Debug(@"║ [Step 4] Searching for video signatures...");
    
    NSArray *signatures = @[
        @"ftypisom", @"ftypiso2", @"ftypmp41", @"ftypmp42",
        @"ftypqt  ", @"ftypM4V ", @"ftypavc1", @"ftypmp4"
    ];
    
    NSUInteger searchStart = 50 * 1024; // Start after minimum image size
    if (data.length <= searchStart) {
        searchStart = 0;
    }
    
    BOOL foundVideoSig = NO;
    for (NSString *sig in signatures) {
        NSData *sigData = [sig dataUsingEncoding:NSUTF8StringEncoding];
        NSRange searchRange = NSMakeRange(searchStart, data.length - searchStart);
        NSRange found = [data rangeOfData:sigData options:0 range:searchRange];
        
        if (found.location != NSNotFound) {
            Debug(@"║   ✓ Found '%@' at offset %lu", sig, (unsigned long)found.location);
            foundVideoSig = YES;
            
            // Show first 32 bytes of video data
            if (found.location >= 4) {
                NSUInteger videoStart = found.location - 4;
                NSUInteger previewLen = MIN(32, data.length - videoStart);
                uint8_t preview[32];
                [data getBytes:preview range:NSMakeRange(videoStart, previewLen)];
                NSMutableString *previewStr = [NSMutableString string];
                for (int i = 0; i < previewLen; i++) {
                    [previewStr appendFormat:@"%02X ", preview[i]];
                }
                Debug(@"║     Video preview: %@", previewStr);
            }
        }
    }
    
    if (!foundVideoSig) {
        Debug(@"║   ✗ No video signatures found");
        
        // Additional check: search for generic "ftyp" in the entire file
        NSData *ftypMarker = [@"ftyp" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange found = [data rangeOfData:ftypMarker options:0 range:NSMakeRange(searchStart, data.length - searchStart)];
        if (found.location != NSNotFound) {
            Debug(@"║   BUT found generic 'ftyp' at offset %lu", (unsigned long)found.location);
            
            // Show brand at this location
            if (found.location + 8 <= data.length) {
                char brand[5] = {0};
                [data getBytes:brand range:NSMakeRange(found.location + 4, 4)];
                Debug(@"║     Brand at this location: %s", brand);
            }
        }
    }
    
    // 5. Summary and recommendations
    Debug(@"╠══════════════════════════════════════════════════════════════════════╣");
    Debug(@"║ [Step 5] Detection Summary...");
    
    BOOL hasMPVD = (mpvdBox != nil);
    BOOL hasXMPUUID = (xmpUuidBox != nil);
    BOOL hasXMP = (xmp != nil && xmp.isMotionPhoto);
    BOOL hasVideoSig = foundVideoSig;
    
    Debug(@"║   ├── Has mpvd box: %@", hasMPVD ? @"YES ✓" : @"NO ✗");
    Debug(@"║   ├── Has XMP UUID box: %@", hasXMPUUID ? @"YES ✓" : @"NO ✗");
    Debug(@"║   ├── Has valid XMP metadata: %@", hasXMP ? @"YES ✓" : @"NO ✗");
    Debug(@"║   └── Has video signature: %@", hasVideoSig ? @"YES ✓" : @"NO ✗");
    
    if (hasMPVD) {
        Debug(@"║");
        Debug(@"║   → Format: iOS Seafile Motion Photo (mpvd container)");
        Debug(@"║   → Video extraction method: mpvd box");
    } else if (hasXMP && xmp.videoLength > 0) {
        Debug(@"║");
        Debug(@"║   → Format: Standard Motion Photo (XMP metadata)");
        Debug(@"║   → Video extraction method: XMP videoLength offset");
        Debug(@"║   → Video offset: %lu", (unsigned long)[xmp videoOffsetInFileOfSize:data.length]);
    } else if (hasVideoSig) {
        Debug(@"║");
        Debug(@"║   → Format: Non-standard Motion Photo (no metadata)");
        Debug(@"║   → Video extraction method: Signature detection");
    } else {
        Debug(@"║");
        Debug(@"║   → This file does NOT appear to be a Motion Photo");
    }
    
    // 6. Attempt extraction and show results
    Debug(@"╠══════════════════════════════════════════════════════════════════════╣");
    Debug(@"║ [Step 6] Testing extraction...");
    
    NSData *extractedImage = [self extractImageFromMotionPhoto:data];
    NSData *extractedVideo = [self extractVideoFromMotionPhoto:data];
    
    Debug(@"║   ├── Extracted image: %@",
          extractedImage ? [NSString stringWithFormat:@"%lu bytes ✓", (unsigned long)extractedImage.length] : @"FAILED ✗");
    Debug(@"║   └── Extracted video: %@",
          extractedVideo ? [NSString stringWithFormat:@"%lu bytes ✓", (unsigned long)extractedVideo.length] : @"FAILED ✗");
    
    if (extractedVideo && extractedVideo.length > 12) {
        // Verify video format
        char videoType[5] = {0};
        [extractedVideo getBytes:videoType range:NSMakeRange(4, 4)];
        char videoBrand[5] = {0};
        [extractedVideo getBytes:videoBrand range:NSMakeRange(8, 4)];
        Debug(@"║       Video box type: %s, brand: %s", videoType, videoBrand);
    }
    
    Debug(@"╚══════════════════════════════════════════════════════════════════════╝");
}

+ (void)analyzeAndLogMotionPhotoIssues:(NSData *)data fileName:(NSString *)fileName {
    Debug(@"");
    Debug(@"🔍 Analyzing Motion Photo: %@", fileName);
    [self logMotionPhotoStructure:data];
}

#pragma mark - Android Spec Compliance Validation

+ (SeafMotionPhotoComplianceReport *)validateAndroidSpecCompliance:(NSData *)data {
    SeafMotionPhotoComplianceReport *report = [[SeafMotionPhotoComplianceReport alloc] init];
    NSMutableArray<NSString *> *issues = [NSMutableArray array];
    NSMutableArray<NSString *> *warnings = [NSMutableArray array];
    
    if (!data || data.length < 100) {
        report.status = SeafMotionPhotoComplianceStatusNonCompliant;
        [issues addObject:@"File data is missing or too small"];
        report.issues = issues;
        return report;
    }
    
    // Parse ISOBMFF structure
    SeafISOBMFFParser *parser = [[SeafISOBMFFParser alloc] initWithData:data];
    NSArray<SeafISOBMFFBox *> *boxes = [parser parseTopLevelBoxes];
    
    // 1. Check for mpvd box
    SeafISOBMFFBox *mpvdBox = nil;
    SeafISOBMFFBox *mdatBox = nil;
    uint64_t lastHeicBoxEnd = 0;
    
    for (SeafISOBMFFBox *box in boxes) {
        if ([box.type isEqualToString:@"mpvd"]) {
            mpvdBox = box;
            report.hasMpvdBox = YES;
        } else if ([box.type isEqualToString:@"mdat"]) {
            mdatBox = box;
        }
        
        // Track the end of HEIC-related boxes
        if (![box.type isEqualToString:@"mpvd"] && ![box.type isEqualToString:@"uuid"]) {
            uint64_t boxEnd = box.offset + box.size;
            if (boxEnd > lastHeicBoxEnd) {
                lastHeicBoxEnd = boxEnd;
            }
        }
    }
    
    if (!report.hasMpvdBox) {
        [issues addObject:@"Missing required 'mpvd' box - video must be wrapped in mpvd container"];
    } else {
        // 2. Check that mpvd comes after all HEIC boxes
        if (mpvdBox.offset >= lastHeicBoxEnd) {
            report.mpvdAfterHeicBoxes = YES;
        } else {
            [issues addObject:@"mpvd box must come after all HEIC image file's boxes"];
        }
        
        // 3. Analyze video inside mpvd
        NSData *videoData = [self extractVideoFromMotionPhoto:data];
        if (videoData) {
            // Check video container format
            if (videoData.length >= 12) {
                char typeBytes[5] = {0};
                char brand[5] = {0};
                [videoData getBytes:typeBytes range:NSMakeRange(4, 4)];
                [videoData getBytes:brand range:NSMakeRange(8, 4)];
                
                report.videoContainerBrand = [NSString stringWithUTF8String:brand];
                
                // Check if it's MP4 (not QuickTime MOV)
                if (strcmp(brand, "qt  ") == 0) {
                    report.hasValidVideoContainer = NO;
                    [issues addObject:@"Video container is QuickTime (qt), should be MP4 (isom/mp4x)"];
                } else if (strcmp(brand, "isom") == 0 || 
                           strcmp(brand, "iso2") == 0 ||
                           strcmp(brand, "mp41") == 0 ||
                           strcmp(brand, "mp42") == 0 ||
                           strcmp(brand, "avc1") == 0 ||
                           strcmp(brand, "hvc1") == 0) {
                    report.hasValidVideoContainer = YES;
                } else {
                    report.hasValidVideoContainer = NO;
                    [warnings addObject:[NSString stringWithFormat:@"Unknown video container brand: %s", brand]];
                }
            }
            
            // Check video codec
            NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                  [NSString stringWithFormat:@"compliance_check_%@.mp4", [[NSUUID UUID] UUIDString]]];
            if ([videoData writeToFile:tempPath atomically:YES]) {
                AVAsset *asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:tempPath]];
                NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
                
                if (videoTracks.count > 0) {
                    AVAssetTrack *track = videoTracks.firstObject;
                    NSArray *formatDescriptions = track.formatDescriptions;
                    
                    if (formatDescriptions.count > 0) {
                        CMFormatDescriptionRef formatDesc = (__bridge CMFormatDescriptionRef)formatDescriptions.firstObject;
                        FourCharCode codecType = CMFormatDescriptionGetMediaSubType(formatDesc);
                        
                        // Check for AVC/HEVC/AV1
                        if (codecType == kCMVideoCodecType_H264 || codecType == 'avc1') {
                            report.hasValidVideoCodec = YES;
                            report.videoCodec = @"H.264/AVC";
                        } else if (codecType == kCMVideoCodecType_HEVC || codecType == 'hvc1' || codecType == 'hev1') {
                            report.hasValidVideoCodec = YES;
                            report.videoCodec = @"H.265/HEVC";
                        } else if (codecType == 'av01') {
                            report.hasValidVideoCodec = YES;
                            report.videoCodec = @"AV1";
                        } else {
                            report.hasValidVideoCodec = NO;
                            char codecStr[5] = {0};
                            codecStr[0] = (codecType >> 24) & 0xFF;
                            codecStr[1] = (codecType >> 16) & 0xFF;
                            codecStr[2] = (codecType >> 8) & 0xFF;
                            codecStr[3] = codecType & 0xFF;
                            report.videoCodec = [NSString stringWithFormat:@"%s (unsupported)", codecStr];
                            [issues addObject:[NSString stringWithFormat:@"Video codec '%s' is not supported, must be AVC/HEVC/AV1", codecStr]];
                        }
                    }
                }
                
                [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
            }
        } else {
            [issues addObject:@"Failed to extract video from mpvd box"];
        }
    }
    
    // Check for uuid box (warning, not error - it's not required but also not prohibited)
    for (SeafISOBMFFBox *box in boxes) {
        if ([box.type isEqualToString:@"uuid"]) {
            [warnings addObject:@"File contains uuid box - not required by Android spec but may be ignored"];
        }
    }
    
    // Determine overall status
    report.issues = issues;
    report.warnings = warnings;
    
    if (issues.count == 0) {
        report.status = SeafMotionPhotoComplianceStatusCompliant;
    } else if (report.hasMpvdBox && report.mpvdAfterHeicBoxes) {
        report.status = SeafMotionPhotoComplianceStatusPartiallyCompliant;
    } else {
        report.status = SeafMotionPhotoComplianceStatusNonCompliant;
    }
    
    return report;
}

+ (BOOL)isAndroidSpecCompliant:(NSData *)data {
    SeafMotionPhotoComplianceReport *report = [self validateAndroidSpecCompliance:data];
    return report.status == SeafMotionPhotoComplianceStatusCompliant;
}

@end

#pragma mark - SeafMotionPhotoComplianceReport Implementation

@implementation SeafMotionPhotoComplianceReport

- (instancetype)init {
    self = [super init];
    if (self) {
        _status = SeafMotionPhotoComplianceStatusUnknown;
        _hasMpvdBox = NO;
        _hasValidVideoContainer = NO;
        _hasValidVideoCodec = NO;
        _mpvdAfterHeicBoxes = NO;
    }
    return self;
}

- (NSString *)formattedReport {
    NSMutableString *report = [NSMutableString string];
    
    [report appendString:@"╔══════════════════════════════════════════════════════════════════════╗\n"];
    [report appendString:@"║          ANDROID MOTION PHOTO COMPLIANCE REPORT                      ║\n"];
    [report appendString:@"╠══════════════════════════════════════════════════════════════════════╣\n"];
    
    NSString *statusStr;
    switch (self.status) {
        case SeafMotionPhotoComplianceStatusCompliant:
            statusStr = @"✅ COMPLIANT";
            break;
        case SeafMotionPhotoComplianceStatusPartiallyCompliant:
            statusStr = @"⚠️ PARTIALLY COMPLIANT";
            break;
        case SeafMotionPhotoComplianceStatusNonCompliant:
            statusStr = @"❌ NON-COMPLIANT";
            break;
        default:
            statusStr = @"❓ UNKNOWN";
    }
    
    [report appendFormat:@"║ Overall Status: %@\n", statusStr];
    [report appendString:@"╠══════════════════════════════════════════════════════════════════════╣\n"];
    [report appendString:@"║ Requirement Checks:\n"];
    [report appendFormat:@"║   ├── mpvd box present: %@\n", self.hasMpvdBox ? @"✅" : @"❌"];
    [report appendFormat:@"║   ├── mpvd after HEIC boxes: %@\n", self.mpvdAfterHeicBoxes ? @"✅" : @"❌"];
    [report appendFormat:@"║   ├── Video container (MP4): %@ (%@)\n", 
     self.hasValidVideoContainer ? @"✅" : @"❌",
     self.videoContainerBrand ?: @"unknown"];
    [report appendFormat:@"║   └── Video codec (AVC/HEVC/AV1): %@ (%@)\n",
     self.hasValidVideoCodec ? @"✅" : @"❌",
     self.videoCodec ?: @"unknown"];
    
    if (self.issues.count > 0) {
        [report appendString:@"╠══════════════════════════════════════════════════════════════════════╣\n"];
        [report appendString:@"║ Issues:\n"];
        for (NSString *issue in self.issues) {
            [report appendFormat:@"║   ❌ %@\n", issue];
        }
    }
    
    if (self.warnings.count > 0) {
        [report appendString:@"╠══════════════════════════════════════════════════════════════════════╣\n"];
        [report appendString:@"║ Warnings:\n"];
        for (NSString *warning in self.warnings) {
            [report appendFormat:@"║   ⚠️ %@\n", warning];
        }
    }
    
    [report appendString:@"╚══════════════════════════════════════════════════════════════════════╝"];
    
    return [report copy];
}

@end
