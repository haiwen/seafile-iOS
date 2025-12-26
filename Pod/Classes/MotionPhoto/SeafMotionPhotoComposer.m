//
//  SeafMotionPhotoComposer.m
//  Seafile
//
//  Created for Motion Photo support.
//  Implements standard HEIC Motion Photo container format based on ISO Base Media File Format.
//

#import "SeafMotionPhotoComposer.h"
#import "Debug.h"
#import "SeafXMPHandler.h"
#import "SeafISOBMFFParser.h"
#import "SeafVideoConverter.h"

#pragma mark - Helper Structures

// Structure to track box positions and offsets
typedef struct {
    uint64_t originalOffset;
    uint64_t newOffset;
    uint64_t size;
} BoxOffsetMapping;

@implementation SeafMotionPhotoComposer

#pragma mark - Box Creation Methods

/// Create XMP UUID box for storing Motion Photo metadata at file level
+ (NSData *)createXMPUuidBox:(NSData *)xmpData {
    // UUID for XMP: BE7ACFCB-97A9-42E8-9C71-999491E3AFAC (Adobe XMP UUID)
    uint8_t xmpUUID[16] = {
        0xBE, 0x7A, 0xCF, 0xCB, 0x97, 0xA9, 0x42, 0xE8,
        0x9C, 0x71, 0x99, 0x94, 0x91, 0xE3, 0xAF, 0xAC
    };
    
    NSMutableData *box = [NSMutableData data];
    
    // Box size: header(8) + UUID(16) + xmpData
    uint32_t boxSize = 8 + 16 + (uint32_t)xmpData.length;
    uint32_t boxSizeBE = CFSwapInt32HostToBig(boxSize);
    
    [box appendBytes:&boxSizeBE length:4];
    [box appendBytes:"uuid" length:4];
    [box appendBytes:xmpUUID length:16];
    [box appendData:xmpData];
    
    return [box copy];
}

/// Create MPVD (Motion Photo Video Data) box containing the video
/// This follows the structure shown in the user's diagram
+ (NSData *)createMPVDBox:(NSData *)videoData {
    NSMutableData *box = [NSMutableData data];
    
    // mpvd box structure:
    // - size (4 bytes)
    // - type 'mpvd' (4 bytes)  
    // - video data (complete MP4/MOV file)
    
    uint32_t boxSize = 8 + (uint32_t)videoData.length;
    
    // Use extended size if video is larger than 4GB - 8 bytes
    if (videoData.length > (UINT32_MAX - 8)) {
        // Extended size format
        uint32_t sizeBE = CFSwapInt32HostToBig(1); // 1 indicates extended size
        uint64_t extSizeBE = CFSwapInt64HostToBig(16 + videoData.length);
        
        [box appendBytes:&sizeBE length:4];
        [box appendBytes:"mpvd" length:4];
        [box appendBytes:&extSizeBE length:8];
    } else {
        uint32_t sizeBE = CFSwapInt32HostToBig(boxSize);
        [box appendBytes:&sizeBE length:4];
        [box appendBytes:"mpvd" length:4];
    }
    
    [box appendData:videoData];
    
    return [box copy];
}

#pragma mark - Alternative: Rebuild Meta Box with XMP (More Complex)

/// This method rebuilds the entire meta box to include XMP data
/// It also updates iloc offsets if necessary
+ (nullable NSData *)rebuildMetaBoxWithXMP:(NSData *)xmpData 
                            originalMeta:(SeafISOBMFFBox *)metaBox 
                                fromData:(NSData *)heicData
                          offsetAdjustment:(int64_t)offsetAdjustment {
    if (!metaBox || !xmpData) {
        return nil;
    }
    
    // Get original meta content
    NSData *originalMetaData = [heicData subdataWithRange:NSMakeRange(metaBox.offset, metaBox.size)];
    
    // Parse meta box children
    SeafISOBMFFParser *metaParser = [[SeafISOBMFFParser alloc] initWithData:originalMetaData];
    
    // For now, we use the simpler approach of adding XMP as a uuid box at file level
    // Full meta box reconstruction with iloc offset updates is very complex
    // and would require understanding the complete HEIC specification
    
    return nil;
}

#pragma mark - Validation Methods

+ (BOOL)isValidImageDataForComposition:(NSData *)imageData {
    return [self isJPEGData:imageData] || [self isHEICData:imageData];
}

+ (BOOL)isValidVideoDataForComposition:(NSData *)videoData {
    return [self isMOVData:videoData] || [self isMP4Data:videoData];
}

+ (BOOL)isJPEGData:(NSData *)data {
    if (data.length < 4) {
        return NO;
    }
    
    uint8_t header[4];
    [data getBytes:header range:NSMakeRange(0, 4)];
    
    // JPEG starts with FF D8 FF
    return header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF;
}

+ (BOOL)isHEICData:(NSData *)data {
    return [SeafISOBMFFParser isHEICData:data];
}

+ (BOOL)isMOVData:(NSData *)data {
    if (data.length < 12) {
        return NO;
    }
    
    char typeBytes[5] = {0};
    [data getBytes:typeBytes range:NSMakeRange(4, 4)];
    
    if (strcmp(typeBytes, "ftyp") != 0) {
        // Some MOV files might have moov first
        if (strcmp(typeBytes, "moov") == 0 || strcmp(typeBytes, "mdat") == 0 || strcmp(typeBytes, "wide") == 0) {
            return YES;
        }
        return NO;
    }
    
    char brand[5] = {0};
    [data getBytes:brand range:NSMakeRange(8, 4)];
    
    // QuickTime brands
    return strcmp(brand, "qt  ") == 0 || strcmp(brand, "M4V ") == 0;
}

+ (BOOL)isMP4Data:(NSData *)data {
    return [SeafISOBMFFParser isMP4Data:data];
}

+ (nullable NSString *)mimeTypeForImageData:(NSData *)imageData {
    if ([self isJPEGData:imageData]) {
        return @"image/jpeg";
    } else if ([self isHEICData:imageData]) {
        return @"image/heic";
    }
    return nil;
}

+ (nullable NSString *)mimeTypeForVideoData:(NSData *)videoData {
    if (videoData.length < 12) {
        return nil;
    }
    
    char typeBytes[5] = {0};
    [videoData getBytes:typeBytes range:NSMakeRange(4, 4)];
    
    if (strcmp(typeBytes, "ftyp") != 0) {
        return @"video/quicktime";
    }
    
    char brand[5] = {0};
    [videoData getBytes:brand range:NSMakeRange(8, 4)];
    
    if (strcmp(brand, "qt  ") == 0 || strcmp(brand, "M4V ") == 0) {
        return @"video/quicktime";
    }
    
    return @"video/mp4";
}

#pragma mark - V1+V2 Hybrid Format

+ (nullable NSData *)composeV1V2MotionPhotoWithImageData:(NSData *)imageData
                                               videoData:(NSData *)videoData {
    Debug(@"SeafMotionPhotoComposer: Building V1+V2 hybrid HEIC Motion Photo...");
    
    // Validate inputs
    if (![self isValidImageDataForComposition:imageData]) {
        Debug(@"SeafMotionPhotoComposer: Invalid image data format");
        return nil;
    }
    
    if (![self isValidVideoDataForComposition:videoData]) {
        Debug(@"SeafMotionPhotoComposer: Invalid video data format");
        return nil;
    }
    
    // Check if HEIC
    if (![self isHEICData:imageData]) {
        Debug(@"SeafMotionPhotoComposer: V1+V2 format only supports HEIC images");
        return nil;
    }
    
    // Video size for XMP (actual video data size, no mpvd wrapper)
    NSUInteger videoDataSize = videoData.length;
    
    // Extract accurate presentation timestamp from video metadata
    // iOS Live Photo videos contain 'com.apple.quicktime.still-image-time' metadata
    // that indicates the exact frame corresponding to the still image
    int64_t presentationTimestampUs = [SeafVideoConverter extractPresentationTimestampFromVideoData:videoData];
    
    if (presentationTimestampUs < 0) {
        // Keep -1 to indicate "unspecified" per Google Motion Photo spec
        // This tells the player to determine the appropriate frame itself
        Debug(@"SeafMotionPhotoComposer: Could not extract timestamp, using -1 (unspecified)");
    } else {
        Debug(@"SeafMotionPhotoComposer: Extracted presentation timestamp: %lld us (%.3f s)", 
              presentationTimestampUs, presentationTimestampUs / 1000000.0);
    }
    
    // Generate XMP metadata in V1+V2 hybrid format
    // This format is compatible with:
    // - V1 readers (via GCamera:MotionPhoto, GCamera:MotionPhotoVersion, MicroVideoOffset)
    // - Legacy readers (via GCamera:MicroVideo, MicroVideoVersion, MicroVideoOffset)
    // - V2 readers (via GCamera:MotionPhotoPresentationTimestampUs and Container:Directory)
    NSString *xmpString = [SeafXMPHandler generateV1V2HybridXMPWithVideoLength:videoDataSize
                                                       presentationTimestampUs:presentationTimestampUs];
    NSData *xmpData = [xmpString dataUsingEncoding:NSUTF8StringEncoding];
    
    Debug(@"SeafMotionPhotoComposer: Generated V1+V2 hybrid XMP metadata (%lu bytes)", (unsigned long)xmpData.length);
    
    // Parse original HEIC structure
    SeafISOBMFFParser *parser = [[SeafISOBMFFParser alloc] initWithData:imageData];
    NSArray<SeafISOBMFFBox *> *boxes = [parser parseTopLevelBoxes];
    
    if (boxes.count == 0) {
        Debug(@"SeafMotionPhotoComposer: Failed to parse HEIC structure");
        return nil;
    }
    
    // Find key boxes
    SeafISOBMFFBox *ftypBox = nil;
    SeafISOBMFFBox *metaBox = nil;
    SeafISOBMFFBox *mdatBox = nil;
    NSMutableArray *otherBoxes = [NSMutableArray array];
    
    for (SeafISOBMFFBox *box in boxes) {
        if ([box.type isEqualToString:@"ftyp"]) {
            ftypBox = box;
        } else if ([box.type isEqualToString:@"meta"]) {
            metaBox = box;
        } else if ([box.type isEqualToString:@"mdat"]) {
            mdatBox = box;
        } else {
            [otherBoxes addObject:box];
        }
    }
    
    if (!ftypBox || !metaBox || !mdatBox) {
        Debug(@"SeafMotionPhotoComposer: Missing required boxes (ftyp, meta, or mdat)");
        return nil;
    }
    
    // Parse iinf, iloc, and iref from meta box
    SeafISOBMFFBox *iinfBox = [parser findIinfInMetaBox:metaBox];
    SeafISOBMFFBox *ilocBox = [parser findIlocInMetaBox:metaBox];
    SeafISOBMFFBox *irefBox = [parser findIrefInMetaBox:metaBox];
    
    if (!iinfBox || !ilocBox) {
        Debug(@"SeafMotionPhotoComposer: Missing iinf or iloc box in meta");
        return nil;
    }
    
    SeafIinfData *iinfData = [parser parseIinfBox:iinfBox];
    SeafIlocData *ilocData = [parser parseIlocBox:ilocBox];
    
    if (!iinfData || !ilocData) {
        Debug(@"SeafMotionPhotoComposer: Failed to parse iinf or iloc data");
        return nil;
    }
    
    // Get primary item ID for cdsc reference
    uint32_t primaryItemID = [parser getPrimaryItemIDFromMetaBox:metaBox];
    Debug(@"SeafMotionPhotoComposer: Primary item ID: %u", primaryItemID);
    
    // Get max item ID and create new XMP mime item
    uint32_t maxItemID = [parser getMaxItemIDFromIinfData:iinfData];
    uint32_t xmpItemID = maxItemID + 1;
    
    Debug(@"SeafMotionPhotoComposer: Creating XMP mime item with ID %u", xmpItemID);
    
    // Add new mime item to iinf
    SeafIinfItem *xmpItem = [parser createMimeInfeItemWithID:xmpItemID version:iinfData.version == 0 ? 2 : iinfData.version];
    [iinfData.items addObject:xmpItem];
    
    // Serialize new iinf box
    NSData *newIinfBox = [parser serializeIinfData:iinfData];
    int64_t iinfSizeDelta = (int64_t)newIinfBox.length - (int64_t)iinfBox.size;
    
    // Add cdsc reference to iref (XMP item -> primary item)
    NSData *newIrefBox = nil;
    int64_t irefSizeDelta = 0;
    if (irefBox && primaryItemID > 0) {
        NSDictionary *irefInfo = [parser parseIrefBox:irefBox];
        if (irefInfo[@"payload"]) {
            NSData *irefPayload = irefInfo[@"payload"];
            newIrefBox = [parser addCdscReferenceToIrefData:irefPayload
                                                fromItemID:xmpItemID
                                                  toItemID:primaryItemID];
            if (newIrefBox) {
                irefSizeDelta = (int64_t)newIrefBox.length - (int64_t)irefBox.size;
                Debug(@"SeafMotionPhotoComposer: Added cdsc reference for XMP item %u -> primary item %u (iref delta: %lld)", 
                      xmpItemID, primaryItemID, irefSizeDelta);
            }
        }
    } else {
        Debug(@"SeafMotionPhotoComposer: No iref box found or no primary item, skipping cdsc reference");
    }
    
    // Calculate boxes between meta and mdat
    uint64_t boxesBetweenSize = 0;
    for (SeafISOBMFFBox *box in otherBoxes) {
        if (box.offset > metaBox.offset && box.offset < mdatBox.offset) {
            boxesBetweenSize += box.size;
        }
    }
    
    // Original mdat payload size (excluding header)
    uint64_t originalMdatPayloadSize = mdatBox.size - 8;
    
    // Step 1: Add XMP item to iloc with placeholder offset (0)
    [parser addItemToIlocData:ilocData
                       itemID:xmpItemID
                       offset:0  // Placeholder, will be updated
                       length:xmpData.length];
    
    // Serialize iloc to get actual size (with placeholder XMP offset)
    NSData *tempIlocBox = [parser serializeIlocData:ilocData];
    int64_t ilocSizeDelta = (int64_t)tempIlocBox.length - (int64_t)ilocBox.size;
    
    // Calculate actual meta size delta (including iref change)
    int64_t metaSizeDelta = iinfSizeDelta + ilocSizeDelta + irefSizeDelta;
    
    // Step 2: Calculate actual XMP offset based on real meta size
    uint64_t newFtypEnd = ftypBox.size;
    uint64_t newMetaSize = metaBox.size + metaSizeDelta;
    uint64_t newMetaEnd = newFtypEnd + newMetaSize;
    uint64_t newMdatStart = newMetaEnd + boxesBetweenSize;
    uint64_t xmpOffsetInFile = newMdatStart + 8 + originalMdatPayloadSize;
    
    Debug(@"SeafMotionPhotoComposer: XMP will be at offset %llu in new file", xmpOffsetInFile);
    
    // Step 3: Update XMP item's offset with correct value
    for (SeafIlocItem *item in ilocData.items) {
        if (item.itemID == xmpItemID) {
            for (SeafIlocExtent *extent in item.extents) {
                extent.extentOffset = xmpOffsetInFile;
            }
            break;
        }
    }
    
    // Step 4: Adjust existing iloc offsets for items pointing to mdat
    for (SeafIlocItem *item in ilocData.items) {
        if (item.itemID == xmpItemID) {
            continue; // Skip XMP item
        }
        
        if (item.baseOffset >= mdatBox.offset) {
            item.baseOffset += metaSizeDelta;
        }
        
        if (item.baseOffset == 0) {
            for (SeafIlocExtent *extent in item.extents) {
                if (extent.extentOffset >= mdatBox.offset) {
                    extent.extentOffset += metaSizeDelta;
                }
            }
        }
    }
    
    // Serialize final iloc box
    NSData *newIlocBox = [parser serializeIlocData:ilocData];
    
    // Build the new file
    NSMutableData *result = [NSMutableData data];
    
    // 1. Copy ftyp
    [result appendData:[imageData subdataWithRange:NSMakeRange(ftypBox.offset, ftypBox.size)]];
    Debug(@"SeafMotionPhotoComposer: Added ftyp (%llu bytes)", ftypBox.size);
    
    // 2. Build new meta box
    NSMutableData *newMetaContent = [NSMutableData data];
    uint64_t metaPayloadStart = metaBox.offset + metaBox.headerSize;
    [newMetaContent appendData:[imageData subdataWithRange:NSMakeRange(metaPayloadStart, 4)]];
    
    for (SeafISOBMFFBox *child in metaBox.children) {
        if ([child.type isEqualToString:@"iinf"]) {
            [newMetaContent appendData:newIinfBox];
        } else if ([child.type isEqualToString:@"iloc"]) {
            [newMetaContent appendData:newIlocBox];
        } else if ([child.type isEqualToString:@"iref"] && newIrefBox) {
            // Replace iref with updated version containing cdsc reference
            [newMetaContent appendData:newIrefBox];
            Debug(@"SeafMotionPhotoComposer: Replaced iref box (%llu -> %lu bytes)", child.size, (unsigned long)newIrefBox.length);
        } else {
            [newMetaContent appendData:[imageData subdataWithRange:NSMakeRange(child.offset, child.size)]];
        }
    }
    
    uint32_t metaSize = 8 + (uint32_t)newMetaContent.length;
    uint32_t metaSizeBE = CFSwapInt32HostToBig(metaSize);
    [result appendBytes:&metaSizeBE length:4];
    [result appendBytes:"meta" length:4];
    [result appendData:newMetaContent];
    Debug(@"SeafMotionPhotoComposer: Added meta (%u bytes, iref updated: %@)", metaSize, newIrefBox ? @"YES" : @"NO");
    
    // 3. Copy boxes between meta and mdat
    for (SeafISOBMFFBox *box in otherBoxes) {
        if (box.offset > metaBox.offset && box.offset < mdatBox.offset) {
            [result appendData:[imageData subdataWithRange:NSMakeRange(box.offset, box.size)]];
        }
    }
    
    // 4. Build new mdat with XMP appended
    uint64_t newMdatTotalSize = mdatBox.size + xmpData.length;
    uint32_t mdatSizeBE = CFSwapInt32HostToBig((uint32_t)newMdatTotalSize);
    [result appendBytes:&mdatSizeBE length:4];
    [result appendBytes:"mdat" length:4];
    [result appendData:[imageData subdataWithRange:NSMakeRange(mdatBox.offset + 8, mdatBox.size - 8)]];
    [result appendData:xmpData];
    Debug(@"SeafMotionPhotoComposer: Added mdat (%llu bytes, +XMP %lu)", newMdatTotalSize, (unsigned long)xmpData.length);
    
    // 5. Copy trailing boxes from original HEIC (if any)
    for (SeafISOBMFFBox *box in otherBoxes) {
        if (box.offset >= mdatBox.offset + mdatBox.size) {
            [result appendData:[imageData subdataWithRange:NSMakeRange(box.offset, box.size)]];
        }
    }
    
    // 6. Append video with mpvd box wrapper
    NSData *mpvdBox = [self createMPVDBox:videoData];
    [result appendData:mpvdBox];
    Debug(@"SeafMotionPhotoComposer: Added mpvd box (%lu bytes, video: %lu bytes)", (unsigned long)mpvdBox.length, (unsigned long)videoData.length);
    
    Debug(@"SeafMotionPhotoComposer: V1+V2 hybrid HEIC Motion Photo composed. Total: %lu bytes", (unsigned long)result.length);
    Debug(@"SeafMotionPhotoComposer: XMP stored as mime item (ID %u) in mdat", xmpItemID);
    
    return [result copy];
}

@end
