//
//  SeafXMPHandler.m
//  Seafile
//
//  Created for Motion Photo support.
//

#import "SeafXMPHandler.h"
#import "Debug.h"
#import "SeafISOBMFFParser.h"

#pragma mark - SeafMotionPhotoXMP Implementation

@implementation SeafMotionPhotoXMP

- (instancetype)init {
    self = [super init];
    if (self) {
        _isMotionPhoto = NO;
        _motionPhotoVersion = 1;
        _presentationTimestampUs = -1;
        _videoLength = 0;
        _videoPadding = 0;
        _primaryLength = 0;
        _primaryPadding = 0;
        _primaryMime = @"image/heic";
        _videoMime = @"video/mp4";
    }
    return self;
}

- (NSUInteger)videoOffsetInFileOfSize:(NSUInteger)fileSize {
    if (self.videoLength == 0 || self.videoLength > fileSize) {
        return NSNotFound;
    }
    // Calculate actual video data offset:
    // mpvd box starts at: fileSize - videoLength
    // Video data starts at: mpvd box start + padding (mpvd header size)
    // If padding is 0 (legacy), assume it's the raw video offset without mpvd wrapper
    NSUInteger mpvdBoxOffset = fileSize - self.videoLength;
    return mpvdBoxOffset + self.videoPadding;
}

- (BOOL)isValidMotionPhoto {
    return self.isMotionPhoto && self.videoLength > 0;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<SeafMotionPhotoXMP: isMotionPhoto=%d, version=%ld, timestamp=%lld, videoLength=%lu>",
            self.isMotionPhoto, (long)self.motionPhotoVersion, self.presentationTimestampUs, (unsigned long)self.videoLength];
}

@end

#pragma mark - SeafXMPHandler Implementation

@implementation SeafXMPHandler

#pragma mark - Parsing

+ (nullable SeafMotionPhotoXMP *)parseXMPData:(NSData *)xmpData {
    if (!xmpData || xmpData.length == 0) {
        return nil;
    }
    
    NSString *xmpString = [[NSString alloc] initWithData:xmpData encoding:NSUTF8StringEncoding];
    if (!xmpString) {
        return nil;
    }
    
    SeafMotionPhotoXMP *xmp = [[SeafMotionPhotoXMP alloc] init];
    
    // Parse GCamera:MotionPhoto
    NSString *motionPhotoValue = [self extractAttributeValue:@"GCamera:MotionPhoto" fromXML:xmpString];
    xmp.isMotionPhoto = [motionPhotoValue isEqualToString:@"1"];
    
    // Parse GCamera:MotionPhotoVersion
    NSString *versionValue = [self extractAttributeValue:@"GCamera:MotionPhotoVersion" fromXML:xmpString];
    if (versionValue) {
        xmp.motionPhotoVersion = [versionValue integerValue];
    }
    
    // Parse GCamera:MotionPhotoPresentationTimestampUs
    NSString *timestampValue = [self extractAttributeValue:@"GCamera:MotionPhotoPresentationTimestampUs" fromXML:xmpString];
    if (timestampValue) {
        xmp.presentationTimestampUs = [timestampValue longLongValue];
    }
    
    // Parse Container:Directory for video length
    [self parseContainerDirectory:xmpString intoXMP:xmp];
    
    return xmp;
}

+ (void)parseContainerDirectory:(NSString *)xmpString intoXMP:(SeafMotionPhotoXMP *)xmp {
    // Look for Container:Item elements with MotionPhoto semantic
    // Format: <Container:Item Item:Mime="video/mp4" Item:Semantic="MotionPhoto" Item:Length="12345"/>
    
    // Find Item:Length for MotionPhoto semantic
    NSError *error = nil;
    
    // Pattern to match Container:Item with MotionPhoto semantic
    NSString *pattern = @"Item:Semantic\\s*=\\s*[\"']MotionPhoto[\"'][^>]*Item:Length\\s*=\\s*[\"'](\\d+)[\"']";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    
    NSTextCheckingResult *match = [regex firstMatchInString:xmpString
                                                    options:0
                                                      range:NSMakeRange(0, xmpString.length)];
    
    if (match && match.numberOfRanges > 1) {
        NSRange lengthRange = [match rangeAtIndex:1];
        NSString *lengthStr = [xmpString substringWithRange:lengthRange];
        xmp.videoLength = [lengthStr integerValue];
    } else {
        // Try alternative pattern where Length comes before Semantic
        pattern = @"Item:Length\\s*=\\s*[\"'](\\d+)[\"'][^>]*Item:Semantic\\s*=\\s*[\"']MotionPhoto[\"']";
        regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:&error];
        
        match = [regex firstMatchInString:xmpString options:0 range:NSMakeRange(0, xmpString.length)];
        
        if (match && match.numberOfRanges > 1) {
            NSRange lengthRange = [match rangeAtIndex:1];
            NSString *lengthStr = [xmpString substringWithRange:lengthRange];
            xmp.videoLength = [lengthStr integerValue];
        }
    }
    
    // Parse video MIME type
    pattern = @"Item:Semantic\\s*=\\s*[\"']MotionPhoto[\"'][^>]*Item:Mime\\s*=\\s*[\"']([^\"']+)[\"']";
    regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                      options:NSRegularExpressionCaseInsensitive
                                                        error:&error];
    
    match = [regex firstMatchInString:xmpString options:0 range:NSMakeRange(0, xmpString.length)];
    if (match && match.numberOfRanges > 1) {
        NSRange mimeRange = [match rangeAtIndex:1];
        xmp.videoMime = [xmpString substringWithRange:mimeRange];
    }
    
    // Parse video padding
    pattern = @"Item:Semantic\\s*=\\s*[\"']MotionPhoto[\"'][^>]*Item:Padding\\s*=\\s*[\"'](\\d+)[\"']";
    regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                      options:NSRegularExpressionCaseInsensitive
                                                        error:&error];
    
    match = [regex firstMatchInString:xmpString options:0 range:NSMakeRange(0, xmpString.length)];
    if (match && match.numberOfRanges > 1) {
        NSRange paddingRange = [match rangeAtIndex:1];
        NSString *paddingStr = [xmpString substringWithRange:paddingRange];
        xmp.videoPadding = [paddingStr integerValue];
    }
    
    // Also try to parse from DirectoryItemLength array format (Samsung style)
    // [XMP-GContainer] DirectoryItemLength: 0, 4406605
    pattern = @"DirectoryItemLength[^:]*:\\s*[^,]+,\\s*(\\d+)";
    regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                      options:NSRegularExpressionCaseInsensitive
                                                        error:&error];
    
    match = [regex firstMatchInString:xmpString options:0 range:NSMakeRange(0, xmpString.length)];
    if (match && match.numberOfRanges > 1 && xmp.videoLength == 0) {
        NSRange lengthRange = [match rangeAtIndex:1];
        NSString *lengthStr = [xmpString substringWithRange:lengthRange];
        xmp.videoLength = [lengthStr integerValue];
    }
}

+ (nullable NSString *)extractAttributeValue:(NSString *)attributeName fromXML:(NSString *)xml {
    // Pattern: attributeName="value" or attributeName='value'
    NSString *pattern = [NSString stringWithFormat:@"%@\\s*=\\s*[\"']([^\"']*)[\"']", attributeName];
    
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:0
                                                                             error:&error];
    if (error) {
        return nil;
    }
    
    NSTextCheckingResult *match = [regex firstMatchInString:xml
                                                    options:0
                                                      range:NSMakeRange(0, xml.length)];
    
    if (match && match.numberOfRanges > 1) {
        NSRange valueRange = [match rangeAtIndex:1];
        return [xml substringWithRange:valueRange];
    }
    
    return nil;
}

+ (nullable SeafMotionPhotoXMP *)parseXMPFromImageData:(NSData *)imageData {
    if (!imageData || imageData.length < 12) {
        return nil;
    }
    
    NSData *xmpData = nil;
    
    // Check if JPEG
    uint8_t header[2];
    [imageData getBytes:header range:NSMakeRange(0, 2)];
    
    if (header[0] == 0xFF && header[1] == 0xD8) {
        // JPEG format
        xmpData = [SeafISOBMFFParser extractXMPFromJPEGData:imageData];
    } else {
        // Try HEIC/ISOBMFF format
        SeafISOBMFFParser *parser = [[SeafISOBMFFParser alloc] initWithData:imageData];
        xmpData = [parser extractXMPFromHEIC];
        
        // If not found in HEIC structure, try raw search
        if (!xmpData) {
            xmpData = [self searchXMPInRawData:imageData];
        }
    }
    
    if (xmpData) {
        return [self parseXMPData:xmpData];
    }
    
    return nil;
}

+ (nullable NSData *)searchXMPInRawData:(NSData *)data {
    // Search for XMP markers in raw data
    NSData *xmpStartMarker = [@"<x:xmpmeta" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *xmpEndMarker = [@"</x:xmpmeta>" dataUsingEncoding:NSUTF8StringEncoding];
    
    NSRange startRange = [data rangeOfData:xmpStartMarker options:0 range:NSMakeRange(0, data.length)];
    if (startRange.location == NSNotFound) {
        return nil;
    }
    
    NSRange searchRange = NSMakeRange(startRange.location, data.length - startRange.location);
    NSRange endRange = [data rangeOfData:xmpEndMarker options:0 range:searchRange];
    
    if (endRange.location == NSNotFound) {
        return nil;
    }
    
    NSUInteger xmpEnd = endRange.location + endRange.length;
    return [data subdataWithRange:NSMakeRange(startRange.location, xmpEnd - startRange.location)];
}

+ (BOOL)hasMotionPhotoXMP:(NSData *)data {
    SeafMotionPhotoXMP *xmp = [self parseXMPFromImageData:data];
    return xmp != nil && xmp.isValidMotionPhoto;
}

#pragma mark - Generation

+ (NSString *)generateV1V2HybridXMPWithVideoLength:(NSUInteger)videoLength
                           presentationTimestampUs:(int64_t)presentationTimestampUs {
    // Generate XMP in V1+V2 hybrid format
    // This format combines:
    // - V1 format (GCamera:MotionPhoto, GCamera:MotionPhotoVersion, GCamera:MotionVideoSize)
    // - V2 format (GCamera:MotionPhotoPresentationTimestampUs, Container:Directory)
    //
    // This provides maximum compatibility across all Motion Photo readers:
    // - V1 readers use GCamera:MotionPhoto, GCamera:MotionVideoSize
    // - V2 readers use Container:Directory for precise item definitions
    
    NSMutableString *xmp = [NSMutableString string];
    
    // XMP header with XMP Core 6.0.0 toolkit identifier
    [xmp appendString:@"<x:xmpmeta xmlns:x=\"adobe:ns:meta/\" x:xmptk=\"XMP Core 6.0.0\">\n"];
    [xmp appendString:@"   <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n"];
    [xmp appendString:@"      <rdf:Description rdf:about=\"\"\n"];
    
    // Namespaces
    [xmp appendString:@"            xmlns:GCamera=\"http://ns.google.com/photos/1.0/camera/\"\n"];
    [xmp appendString:@"            xmlns:Container=\"http://ns.google.com/photos/1.0/container/\"\n"];
    [xmp appendString:@"            xmlns:Item=\"http://ns.google.com/photos/1.0/container/item/\"\n"];
    
    // GCamera fields as attributes (more compact format)
    // V1 format fields (current standard)
    [xmp appendString:@"            GCamera:MotionPhoto=\"1\"\n"];
    [xmp appendString:@"            GCamera:MotionPhotoVersion=\"1\"\n"];
    [xmp appendFormat:@"            GCamera:MotionPhotoPresentationTimestampUs=\"%lld\"\n", presentationTimestampUs];
    
    // Deprecated V1 fields (MicroVideo) - for legacy reader compatibility
    [xmp appendString:@"            GCamera:MicroVideo=\"1\"\n"];
    [xmp appendString:@"            GCamera:MicroVideoVersion=\"1\"\n"];
    [xmp appendFormat:@"            GCamera:MicroVideoOffset=\"%lu\"\n", (unsigned long)videoLength];
    [xmp appendFormat:@"            GCamera:MicroVideoPresentationTimestampUs=\"%lld\">\n", presentationTimestampUs];
    
    // Container:Directory - V2 format structure
    [xmp appendString:@"         <Container:Directory>\n"];
    [xmp appendString:@"            <rdf:Seq>\n"];
    
    // Primary item (image)
    [xmp appendString:@"               <rdf:li rdf:parseType=\"Resource\">\n"];
    [xmp appendString:@"                  <Container:Item\n"];
    [xmp appendString:@"                     Item:Mime=\"image/heic\"\n"];
    [xmp appendString:@"                     Item:Semantic=\"Primary\"\n"];
    [xmp appendString:@"                     Item:Length=\"0\"\n"];
    [xmp appendString:@"                     Item:Padding=\"0\"/>\n"];
    [xmp appendString:@"               </rdf:li>\n"];
    
    // Video item (MotionPhoto) - TESTING: pure video length, padding=8
    [xmp appendString:@"               <rdf:li rdf:parseType=\"Resource\">\n"];
    [xmp appendString:@"                  <Container:Item\n"];
    [xmp appendString:@"                     Item:Mime=\"video/quicktime\"\n"];
    [xmp appendString:@"                     Item:Semantic=\"MotionPhoto\"\n"];
    [xmp appendFormat:@"                     Item:Length=\"%lu\"\n", (unsigned long)videoLength];
    [xmp appendString:@"                     Item:Padding=\"8\"/>\n"];
    [xmp appendString:@"               </rdf:li>\n"];
    
    [xmp appendString:@"            </rdf:Seq>\n"];
    [xmp appendString:@"         </Container:Directory>\n"];
    
    [xmp appendString:@"      </rdf:Description>\n"];
    [xmp appendString:@"   </rdf:RDF>\n"];
    [xmp appendString:@"</x:xmpmeta>"];
    
    return [xmp copy];
}

#pragma mark - XMP Embedding

+ (nullable NSData *)injectXMPData:(NSData *)xmpData intoJPEGData:(NSData *)jpegData {
    if (!xmpData || !jpegData || jpegData.length < 4) {
        return nil;
    }
    
    // Verify JPEG format
    uint8_t header[2];
    [jpegData getBytes:header range:NSMakeRange(0, 2)];
    if (header[0] != 0xFF || header[1] != 0xD8) {
        return nil;
    }
    
    // Create APP1 segment for XMP
    // Format: FF E1 [length:2] "http://ns.adobe.com/xap/1.0/" NULL [xmp data]
    NSString *xmpNamespace = @"http://ns.adobe.com/xap/1.0/";
    NSData *namespaceData = [xmpNamespace dataUsingEncoding:NSUTF8StringEncoding];
    
    // Total APP1 segment length: 2 (length field) + namespace + 1 (null) + xmp data
    NSUInteger segmentDataLength = namespaceData.length + 1 + xmpData.length;
    NSUInteger segmentLength = 2 + segmentDataLength; // Including length field itself
    
    if (segmentLength > 65535) {
        // APP1 segment too large
        return nil;
    }
    
    NSMutableData *result = [NSMutableData data];
    
    // Write SOI marker
    [result appendBytes:header length:2];
    
    // Write APP1 marker
    uint8_t app1Marker[2] = {0xFF, 0xE1};
    [result appendBytes:app1Marker length:2];
    
    // Write segment length (big-endian)
    uint16_t lengthBE = CFSwapInt16HostToBig((uint16_t)segmentLength);
    [result appendBytes:&lengthBE length:2];
    
    // Write XMP namespace
    [result appendData:namespaceData];
    
    // Write null terminator
    uint8_t nullByte = 0;
    [result appendBytes:&nullByte length:1];
    
    // Write XMP data
    [result appendData:xmpData];
    
    // Find position after existing APP markers to insert, or just after SOI
    NSUInteger insertPos = 2; // After SOI
    NSUInteger offset = 2;
    
    // Skip existing APP0 (JFIF) and APP1 segments if present
    while (offset + 4 < jpegData.length) {
        uint8_t marker[2];
        [jpegData getBytes:marker range:NSMakeRange(offset, 2)];
        
        if (marker[0] != 0xFF) {
            break;
        }
        
        // If we hit an existing APP1 with XMP, we need to replace it
        if (marker[1] == 0xE1) {
            // Check if this is XMP
            uint16_t segLen;
            [jpegData getBytes:&segLen range:NSMakeRange(offset + 2, 2)];
            segLen = CFSwapInt16BigToHost(segLen);
            
            NSData *segData = [jpegData subdataWithRange:NSMakeRange(offset + 4, MIN(50, segLen - 2))];
            NSString *segString = [[NSString alloc] initWithData:segData encoding:NSUTF8StringEncoding];
            
            if (segString && [segString containsString:@"http://ns.adobe.com/xap"]) {
                // Skip this existing XMP segment
                insertPos = offset;
                // Append rest of file after this segment
                NSUInteger afterXMP = offset + 2 + segLen;
                [result appendData:[jpegData subdataWithRange:NSMakeRange(afterXMP, jpegData.length - afterXMP)]];
                return [result copy];
            }
        }
        
        // Move to next marker
        if (marker[1] >= 0xD0 && marker[1] <= 0xD9) {
            offset += 2;
        } else {
            uint16_t length;
            [jpegData getBytes:&length range:NSMakeRange(offset + 2, 2)];
            length = CFSwapInt16BigToHost(length);
            offset += 2 + length;
        }
        
        // Keep APP0/APP1 before our new XMP
        if (marker[1] == 0xE0 || marker[1] == 0xE1) {
            insertPos = offset;
        } else {
            // Stop at first non-APP marker
            break;
        }
    }
    
    // Append the rest of the original JPEG (after SOI)
    [result appendData:[jpegData subdataWithRange:NSMakeRange(2, jpegData.length - 2)]];
    
    return [result copy];
}

+ (nullable NSData *)injectXMPData:(NSData *)xmpData intoHEICData:(NSData *)heicData {
    if (!xmpData || !heicData || heicData.length < 12) {
        Debug(@"SeafXMPHandler: Invalid input data for HEIC XMP injection");
        return nil;
    }
    
    // Verify HEIC format
    if (![SeafISOBMFFParser isHEICData:heicData]) {
        Debug(@"SeafXMPHandler: Data is not valid HEIC format");
        return nil;
    }
    
    Debug(@"SeafXMPHandler: Starting XMP injection into HEIC (%lu bytes)", (unsigned long)heicData.length);
    
    // Parse HEIC structure
    SeafISOBMFFParser *parser = [[SeafISOBMFFParser alloc] initWithData:heicData];
    NSArray<SeafISOBMFFBox *> *boxes = [parser parseTopLevelBoxes];
    
    if (boxes.count == 0) {
        Debug(@"SeafXMPHandler: Failed to parse HEIC structure");
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
    
    if (!ftypBox || !metaBox) {
        Debug(@"SeafXMPHandler: Missing required ftyp or meta box");
        return nil;
    }
    
    // Find and parse iloc box
    SeafISOBMFFBox *ilocBox = [parser findIlocInMetaBox:metaBox];
    SeafIlocData *ilocData = nil;
    
    if (ilocBox) {
        ilocData = [parser parseIlocBox:ilocBox];
    }
    
    // Create XMP uuid box to calculate size delta
    NSData *uuidBox = [self createXMPUuidBoxData:xmpData];
    int64_t sizeDelta = (int64_t)uuidBox.length;
    
    Debug(@"SeafXMPHandler: XMP uuid box size: %lld bytes", sizeDelta);
    
    // Adjust iloc offsets if we have iloc and mdat
    if (ilocData && mdatBox) {
        Debug(@"SeafXMPHandler: Adjusting iloc offsets by %lld for offsets >= %llu", sizeDelta, mdatBox.offset);
        [parser adjustIlocOffsets:ilocData byDelta:sizeDelta forOffsetsAbove:mdatBox.offset];
    }
    
    // Rebuild meta box with new iloc and XMP
    NSData *newMetaData = [parser rebuildMetaBox:metaBox withNewIlocData:ilocData xmpData:xmpData];
    
    if (!newMetaData) {
        Debug(@"SeafXMPHandler: Failed to rebuild meta box, using fallback");
        // Fallback: return original data (XMP won't be embedded)
        return nil;
    }
    
    // Build final HEIC file
    NSMutableData *result = [NSMutableData data];
    
    // 1. Copy ftyp box
    [result appendData:[heicData subdataWithRange:NSMakeRange(ftypBox.offset, ftypBox.size)]];
    
    // 2. Add rebuilt meta box
    [result appendData:newMetaData];
    
    // 3. Copy other boxes between meta and mdat
    for (SeafISOBMFFBox *box in otherBoxes) {
        if (mdatBox && box.offset > metaBox.offset && box.offset < mdatBox.offset) {
            [result appendData:[heicData subdataWithRange:NSMakeRange(box.offset, box.size)]];
        }
    }
    
    // 4. Copy mdat box
    if (mdatBox) {
        [result appendData:[heicData subdataWithRange:NSMakeRange(mdatBox.offset, mdatBox.size)]];
    }
    
    // 5. Copy any trailing boxes
    for (SeafISOBMFFBox *box in otherBoxes) {
        if (mdatBox && box.offset > mdatBox.offset) {
            [result appendData:[heicData subdataWithRange:NSMakeRange(box.offset, box.size)]];
        }
    }
    
    Debug(@"SeafXMPHandler: HEIC XMP injection complete. Size: %lu -> %lu bytes", 
          (unsigned long)heicData.length, (unsigned long)result.length);
    
    return [result copy];
}

+ (NSData *)createXMPUuidBoxData:(NSData *)xmpData {
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

+ (NSData *)buildMetaBoxWithXMP:(NSData *)xmpData originalMeta:(SeafISOBMFFBox *)metaBox fromData:(NSData *)heicData {
    // For HEIC, XMP is typically stored in the meta box
    // We'll create a new 'xml ' box inside meta with the XMP data
    
    NSMutableData *result = [NSMutableData data];
    
    // Get original meta content
    NSData *originalMetaPayload = [heicData subdataWithRange:NSMakeRange(metaBox.offset + metaBox.headerSize, 
                                                                         metaBox.size - metaBox.headerSize)];
    
    // Check if there's an existing xml box to replace
    // For simplicity, we'll append the XMP at the end of meta content
    
    // Create xml box
    NSData *xmlBox = [self createXMLBoxWithData:xmpData];
    
    // Calculate new meta size
    uint32_t newMetaSize = (uint32_t)(metaBox.headerSize + originalMetaPayload.length + xmlBox.length);
    
    // Write meta box header
    uint32_t sizeBE = CFSwapInt32HostToBig(newMetaSize);
    [result appendBytes:&sizeBE length:4];
    [result appendBytes:"meta" length:4];
    
    // If meta is a fullbox, include version/flags from original
    if (metaBox.headerSize > 8) {
        NSData *versionFlags = [heicData subdataWithRange:NSMakeRange(metaBox.offset + 8, 4)];
        [result appendData:versionFlags];
    }
    
    // Write original meta content
    [result appendData:originalMetaPayload];
    
    // Append xml box
    [result appendData:xmlBox];
    
    return [result copy];
}

+ (NSData *)createMetaBoxWithXMP:(NSData *)xmpData {
    NSMutableData *result = [NSMutableData data];
    
    // Create xml box first
    NSData *xmlBox = [self createXMLBoxWithData:xmpData];
    
    // Meta box is a fullbox (has version + flags)
    uint32_t metaSize = 8 + 4 + (uint32_t)xmlBox.length; // header + version/flags + xml box
    
    uint32_t sizeBE = CFSwapInt32HostToBig(metaSize);
    [result appendBytes:&sizeBE length:4];
    [result appendBytes:"meta" length:4];
    
    // Version (1 byte) + Flags (3 bytes) = 0
    uint32_t versionFlags = 0;
    [result appendBytes:&versionFlags length:4];
    
    // Append xml box
    [result appendData:xmlBox];
    
    return [result copy];
}

+ (NSData *)createXMLBoxWithData:(NSData *)xmpData {
    NSMutableData *result = [NSMutableData data];
    
    uint32_t boxSize = 8 + (uint32_t)xmpData.length;
    uint32_t sizeBE = CFSwapInt32HostToBig(boxSize);
    
    [result appendBytes:&sizeBE length:4];
    [result appendBytes:"xml " length:4];
    [result appendData:xmpData];
    
    return [result copy];
}

@end

