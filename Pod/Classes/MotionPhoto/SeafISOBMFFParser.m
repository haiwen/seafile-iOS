//
//  SeafISOBMFFParser.m
//  Seafile
//
//  Created for Motion Photo support.
//

#import "SeafISOBMFFParser.h"
#import "Debug.h"

#pragma mark - SeafIlocExtent Implementation

@implementation SeafIlocExtent
@end

#pragma mark - SeafIlocItem Implementation

@implementation SeafIlocItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _extents = [NSMutableArray array];
    }
    return self;
}

@end

#pragma mark - SeafIlocData Implementation

@implementation SeafIlocData

- (instancetype)init {
    self = [super init];
    if (self) {
        _items = [NSMutableArray array];
    }
    return self;
}

@end

#pragma mark - SeafIinfItem Implementation

@implementation SeafIinfItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _version = 2;
        _itemID = 0;
        _itemProtectionIndex = 0;
        _itemType = @"";
    }
    return self;
}

@end

#pragma mark - SeafIinfData Implementation

@implementation SeafIinfData

- (instancetype)init {
    self = [super init];
    if (self) {
        _items = [NSMutableArray array];
    }
    return self;
}

@end

#pragma mark - SeafISOBMFFBox Implementation

@implementation SeafISOBMFFBox

- (uint64_t)payloadOffset {
    return self.offset + self.headerSize;
}

- (uint64_t)payloadSize {
    if (self.size < self.headerSize) {
        return 0;
    }
    return self.size - self.headerSize;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<SeafISOBMFFBox: type='%@', offset=%llu, size=%llu, headerSize=%u>",
            self.type, self.offset, self.size, self.headerSize];
}

@end

#pragma mark - SeafISOBMFFParser Implementation

@interface SeafISOBMFFParser ()
@property (nonatomic, strong, readwrite) NSData *data;
@property (nonatomic, strong, nullable) NSArray<SeafISOBMFFBox *> *cachedTopLevelBoxes;
@end

@implementation SeafISOBMFFParser

#pragma mark - Initialization

- (instancetype)initWithData:(NSData *)data {
    self = [super init];
    if (self) {
        _data = data;
    }
    return self;
}

- (instancetype)initWithPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        return nil;
    }
    return [self initWithData:data];
}

#pragma mark - Box Parsing

- (NSArray<SeafISOBMFFBox *> *)parseTopLevelBoxes {
    if (self.cachedTopLevelBoxes) {
        return self.cachedTopLevelBoxes;
    }
    
    self.cachedTopLevelBoxes = [self parseBoxesInRange:NSMakeRange(0, self.data.length)];
    return self.cachedTopLevelBoxes;
}

- (NSArray<SeafISOBMFFBox *> *)parseBoxesInRange:(NSRange)range {
    NSMutableArray<SeafISOBMFFBox *> *boxes = [NSMutableArray array];
    
    uint64_t offset = range.location;
    uint64_t endOffset = range.location + range.length;
    
    while (offset + 8 <= endOffset) {
        SeafISOBMFFBox *box = [self parseBoxAtOffset:offset maxOffset:endOffset];
        if (!box || box.size == 0) {
            break;
        }
        
        [boxes addObject:box];
        offset += box.size;
    }
    
    return [boxes copy];
}

- (nullable SeafISOBMFFBox *)parseBoxAtOffset:(uint64_t)offset maxOffset:(uint64_t)maxOffset {
    if (offset + 8 > maxOffset || offset + 8 > self.data.length) {
        return nil;
    }
    
    SeafISOBMFFBox *box = [[SeafISOBMFFBox alloc] init];
    box.offset = offset;
    
    // Read size (4 bytes, big-endian)
    uint32_t size32 = 0;
    [self.data getBytes:&size32 range:NSMakeRange(offset, 4)];
    size32 = CFSwapInt32BigToHost(size32);
    
    // Read type (4 bytes)
    char typeBytes[5] = {0};
    [self.data getBytes:typeBytes range:NSMakeRange(offset + 4, 4)];
    box.type = [NSString stringWithUTF8String:typeBytes];
    
    box.headerSize = 8;
    
    if (size32 == 1) {
        // Extended size (64-bit)
        if (offset + 16 > maxOffset || offset + 16 > self.data.length) {
            return nil;
        }
        uint64_t size64 = 0;
        [self.data getBytes:&size64 range:NSMakeRange(offset + 8, 8)];
        box.size = CFSwapInt64BigToHost(size64);
        box.headerSize = 16;
    } else if (size32 == 0) {
        // Box extends to end of file
        box.size = self.data.length - offset;
    } else {
        box.size = size32;
    }
    
    // Validate box size
    if (box.size < box.headerSize || offset + box.size > self.data.length) {
        // Invalid box, might be at end of parseable content
        return nil;
    }
    
    // Parse children for container boxes
    if ([self isContainerBoxType:box.type]) {
        uint64_t childOffset = box.offset + box.headerSize;
        
        // Handle fullbox types (have version + flags)
        if ([self isFullBoxType:box.type]) {
            childOffset += 4; // Skip version (1 byte) + flags (3 bytes)
        }
        
        // Special handling for meta box - it's a fullbox
        if ([box.type isEqualToString:@"meta"]) {
            childOffset = box.offset + box.headerSize + 4;
        }
        
        if (childOffset < box.offset + box.size) {
            NSRange childRange = NSMakeRange(childOffset, box.offset + box.size - childOffset);
            box.children = [self parseBoxesInRange:childRange];
        }
    }
    
    return box;
}

- (BOOL)isContainerBoxType:(NSString *)type {
    static NSSet *containerTypes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        containerTypes = [NSSet setWithArray:@[
            @"moov", @"trak", @"mdia", @"minf", @"stbl", @"dinf",
            @"edts", @"udta", @"meta", @"iloc", @"iinf", @"ipro",
            @"sinf", @"schi", @"rinf", @"iprp", @"ipco"
        ]];
    });
    return [containerTypes containsObject:type];
}

- (BOOL)isFullBoxType:(NSString *)type {
    static NSSet *fullBoxTypes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fullBoxTypes = [NSSet setWithArray:@[
            @"meta", @"hdlr", @"pitm", @"iloc", @"iinf", @"iref",
            @"iprp", @"ipma", @"ispe", @"pixi", @"av1C", @"hvcC"
        ]];
    });
    return [fullBoxTypes containsObject:type];
}

#pragma mark - Box Finding

- (nullable SeafISOBMFFBox *)findBoxWithType:(NSString *)type {
    NSArray<SeafISOBMFFBox *> *boxes = [self parseTopLevelBoxes];
    for (SeafISOBMFFBox *box in boxes) {
        if ([box.type isEqualToString:type]) {
            return box;
        }
    }
    return nil;
}

- (NSArray<SeafISOBMFFBox *> *)findAllBoxesWithType:(NSString *)type {
    NSMutableArray<SeafISOBMFFBox *> *result = [NSMutableArray array];
    [self findAllBoxesWithType:type inBoxes:[self parseTopLevelBoxes] result:result];
    return [result copy];
}

- (void)findAllBoxesWithType:(NSString *)type
                     inBoxes:(NSArray<SeafISOBMFFBox *> *)boxes
                      result:(NSMutableArray<SeafISOBMFFBox *> *)result {
    for (SeafISOBMFFBox *box in boxes) {
        if ([box.type isEqualToString:type]) {
            [result addObject:box];
        }
        if (box.children) {
            [self findAllBoxesWithType:type inBoxes:box.children result:result];
        }
    }
}

- (nullable SeafISOBMFFBox *)findBoxAtPath:(NSArray<NSString *> *)path {
    if (path.count == 0) {
        return nil;
    }
    
    NSArray<SeafISOBMFFBox *> *currentBoxes = [self parseTopLevelBoxes];
    SeafISOBMFFBox *currentBox = nil;
    
    for (NSString *type in path) {
        currentBox = nil;
        for (SeafISOBMFFBox *box in currentBoxes) {
            if ([box.type isEqualToString:type]) {
                currentBox = box;
                break;
            }
        }
        
        if (!currentBox) {
            return nil;
        }
        
        currentBoxes = currentBox.children ?: @[];
    }
    
    return currentBox;
}

#pragma mark - Data Extraction

- (nullable NSData *)payloadDataForBox:(SeafISOBMFFBox *)box {
    if (!box || box.payloadSize == 0) {
        return nil;
    }
    
    uint64_t payloadOffset = box.payloadOffset;
    uint64_t payloadSize = box.payloadSize;
    
    if (payloadOffset + payloadSize > self.data.length) {
        return nil;
    }
    
    return [self.data subdataWithRange:NSMakeRange(payloadOffset, payloadSize)];
}

#pragma mark - Format Detection

+ (BOOL)isValidISOBMFFData:(NSData *)data {
    if (data.length < 12) {
        return NO;
    }
    
    // Check for ftyp box at the beginning
    char typeBytes[5] = {0};
    [data getBytes:typeBytes range:NSMakeRange(4, 4)];
    NSString *type = [NSString stringWithUTF8String:typeBytes];
    
    return [type isEqualToString:@"ftyp"];
}

+ (BOOL)isHEICData:(NSData *)data {
    if (![self isValidISOBMFFData:data]) {
        return NO;
    }
    
    // Read ftyp box to check brand
    if (data.length < 16) {
        return NO;
    }
    
    uint32_t size = 0;
    [data getBytes:&size range:NSMakeRange(0, 4)];
    size = CFSwapInt32BigToHost(size);
    
    if (size < 12 || size > data.length) {
        return NO;
    }
    
    // Read major brand (4 bytes after type)
    char brandBytes[5] = {0};
    [data getBytes:brandBytes range:NSMakeRange(8, 4)];
    NSString *brand = [NSString stringWithUTF8String:brandBytes];
    
    // HEIC brands: heic, heix, hevc, hevx, mif1, msf1
    NSSet *heicBrands = [NSSet setWithArray:@[@"heic", @"heix", @"hevc", @"hevx", @"mif1", @"msf1"]];
    
    if ([heicBrands containsObject:brand]) {
        return YES;
    }
    
    // Also check compatible brands in ftyp box
    if (size > 16) {
        NSUInteger offset = 16; // After major brand and minor version
        while (offset + 4 <= size) {
            char compatBrand[5] = {0};
            [data getBytes:compatBrand range:NSMakeRange(offset, 4)];
            NSString *compat = [NSString stringWithUTF8String:compatBrand];
            if ([heicBrands containsObject:compat]) {
                return YES;
            }
            offset += 4;
        }
    }
    
    return NO;
}

+ (BOOL)isMP4Data:(NSData *)data {
    if (![self isValidISOBMFFData:data]) {
        return NO;
    }
    
    if (data.length < 12) {
        return NO;
    }
    
    char brandBytes[5] = {0};
    [data getBytes:brandBytes range:NSMakeRange(8, 4)];
    NSString *brand = [NSString stringWithUTF8String:brandBytes];
    
    // MP4/MOV brands
    NSSet *mp4Brands = [NSSet setWithArray:@[@"isom", @"iso2", @"mp41", @"mp42", @"avc1", @"qt  ", @"M4V "]];
    return [mp4Brands containsObject:brand];
}

#pragma mark - XMP Extraction

- (nullable NSData *)extractXMPFromHEIC {
    // XMP in HEIC is typically stored in a 'meta' box
    SeafISOBMFFBox *metaBox = [self findBoxWithType:@"meta"];
    if (!metaBox) {
        return nil;
    }
    
    // Look for XMP in iloc referenced items or directly in meta
    // XMP might be stored in an 'xml ' or 'XMP_' box within meta
    // Or referenced through iloc
    
    // Try to find xml or XMP box in meta's children
    for (SeafISOBMFFBox *child in metaBox.children) {
        if ([child.type isEqualToString:@"xml "] || 
            [child.type isEqualToString:@"XMP_"]) {
            return [self payloadDataForBox:child];
        }
    }
    
    // If not found in children, search the raw payload for XMP markers
    NSData *metaPayload = [self payloadDataForBox:metaBox];
    if (metaPayload) {
        return [self extractXMPFromRawData:metaPayload];
    }
    
    return nil;
}

- (nullable NSData *)extractXMPFromRawData:(NSData *)data {
    // Look for XMP packet markers
    NSData *xmpStartMarker = [@"<x:xmpmeta" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *xmpEndMarker = [@"</x:xmpmeta>" dataUsingEncoding:NSUTF8StringEncoding];
    
    NSRange startRange = [data rangeOfData:xmpStartMarker options:0 range:NSMakeRange(0, data.length)];
    if (startRange.location == NSNotFound) {
        // Try alternative marker
        xmpStartMarker = [@"<?xpacket begin" dataUsingEncoding:NSUTF8StringEncoding];
        startRange = [data rangeOfData:xmpStartMarker options:0 range:NSMakeRange(0, data.length)];
    }
    
    if (startRange.location == NSNotFound) {
        return nil;
    }
    
    NSRange endRange = [data rangeOfData:xmpEndMarker 
                                 options:0 
                                   range:NSMakeRange(startRange.location, data.length - startRange.location)];
    
    if (endRange.location == NSNotFound) {
        // Try xpacket end
        NSData *packetEnd = [@"<?xpacket end" dataUsingEncoding:NSUTF8StringEncoding];
        endRange = [data rangeOfData:packetEnd 
                             options:0 
                               range:NSMakeRange(startRange.location, data.length - startRange.location)];
        if (endRange.location != NSNotFound) {
            // Find the closing ?>
            NSData *closing = [@"?>" dataUsingEncoding:NSUTF8StringEncoding];
            NSRange closeRange = [data rangeOfData:closing 
                                           options:0 
                                             range:NSMakeRange(endRange.location, MIN(50, data.length - endRange.location))];
            if (closeRange.location != NSNotFound) {
                endRange = NSMakeRange(endRange.location, closeRange.location + closeRange.length - endRange.location);
            }
        }
    } else {
        endRange = NSMakeRange(endRange.location, endRange.length);
    }
    
    if (endRange.location == NSNotFound) {
        return nil;
    }
    
    NSUInteger xmpEnd = endRange.location + endRange.length;
    NSRange xmpRange = NSMakeRange(startRange.location, xmpEnd - startRange.location);
    
    return [data subdataWithRange:xmpRange];
}

+ (nullable NSData *)extractXMPFromJPEGData:(NSData *)data {
    if (data.length < 4) {
        return nil;
    }
    
    // Check JPEG SOI marker
    uint8_t header[2];
    [data getBytes:header range:NSMakeRange(0, 2)];
    if (header[0] != 0xFF || header[1] != 0xD8) {
        return nil; // Not a JPEG
    }
    
    NSUInteger offset = 2;
    
    while (offset + 4 < data.length) {
        uint8_t marker[2];
        [data getBytes:marker range:NSMakeRange(offset, 2)];
        
        if (marker[0] != 0xFF) {
            break;
        }
        
        // Check for APP1 marker (0xFFE1) which contains XMP
        if (marker[1] == 0xE1) {
            uint16_t segmentLength = 0;
            [data getBytes:&segmentLength range:NSMakeRange(offset + 2, 2)];
            segmentLength = CFSwapInt16BigToHost(segmentLength);
            
            if (offset + 2 + segmentLength > data.length) {
                break;
            }
            
            // Check for XMP namespace identifier
            NSData *segmentData = [data subdataWithRange:NSMakeRange(offset + 4, segmentLength - 2)];
            NSString *xmpNS = @"http://ns.adobe.com/xap/1.0/";
            NSData *xmpNSData = [xmpNS dataUsingEncoding:NSUTF8StringEncoding];
            
            if ([segmentData rangeOfData:xmpNSData options:0 range:NSMakeRange(0, MIN(50, segmentData.length))].location != NSNotFound) {
                // Found XMP segment, extract the XMP data after the namespace + null terminator
                NSUInteger xmpStart = xmpNS.length + 1; // +1 for null terminator
                if (xmpStart < segmentData.length) {
                    return [segmentData subdataWithRange:NSMakeRange(xmpStart, segmentData.length - xmpStart)];
                }
            }
        }
        
        // Skip to next marker
        if (marker[1] >= 0xD0 && marker[1] <= 0xD9) {
            // Standalone markers (RST, SOI, EOI)
            offset += 2;
        } else {
            uint16_t length = 0;
            [data getBytes:&length range:NSMakeRange(offset + 2, 2)];
            length = CFSwapInt16BigToHost(length);
            offset += 2 + length;
        }
    }
    
    return nil;
}

@end

#pragma mark - SeafISOBMFFParser iloc Box Manipulation Category

@implementation SeafISOBMFFParser (IlocManipulation)

- (nullable SeafISOBMFFBox *)findIlocInMetaBox:(SeafISOBMFFBox *)metaBox {
    if (!metaBox || !metaBox.children) {
        return nil;
    }
    
    for (SeafISOBMFFBox *child in metaBox.children) {
        if ([child.type isEqualToString:@"iloc"]) {
            return child;
        }
    }
    return nil;
}

- (nullable SeafIlocData *)parseIlocBox:(SeafISOBMFFBox *)ilocBox {
    if (!ilocBox || ![ilocBox.type isEqualToString:@"iloc"]) {
        return nil;
    }
    
    // Get iloc payload (after box header)
    uint64_t payloadOffset = ilocBox.offset + ilocBox.headerSize;
    uint64_t payloadSize = ilocBox.size - ilocBox.headerSize;
    
    if (payloadOffset + payloadSize > self.data.length) {
        return nil;
    }
    
    NSData *payload = [self.data subdataWithRange:NSMakeRange(payloadOffset, payloadSize)];
    if (payload.length < 8) {
        return nil;
    }
    
    SeafIlocData *ilocData = [[SeafIlocData alloc] init];
    NSUInteger offset = 0;
    
    // Read version (1 byte) and flags (3 bytes)
    uint8_t version;
    [payload getBytes:&version range:NSMakeRange(offset, 1)];
    ilocData.version = version;
    offset += 1;
    
    uint8_t flagBytes[3];
    [payload getBytes:flagBytes range:NSMakeRange(offset, 3)];
    ilocData.flags = ((uint32_t)flagBytes[0] << 16) | ((uint32_t)flagBytes[1] << 8) | flagBytes[2];
    offset += 3;
    
    // Read size fields (2 bytes)
    uint8_t sizes[2];
    [payload getBytes:sizes range:NSMakeRange(offset, 2)];
    ilocData.offsetSize = (sizes[0] >> 4) & 0x0F;
    ilocData.lengthSize = sizes[0] & 0x0F;
    ilocData.baseOffsetSize = (sizes[1] >> 4) & 0x0F;
    
    if (version == 1 || version == 2) {
        ilocData.indexSize = sizes[1] & 0x0F;
    } else {
        ilocData.indexSize = 0;
    }
    offset += 2;
    
    // Read item count
    uint32_t itemCount = 0;
    if (version < 2) {
        uint16_t count16;
        [payload getBytes:&count16 range:NSMakeRange(offset, 2)];
        itemCount = CFSwapInt16BigToHost(count16);
        offset += 2;
    } else {
        uint32_t count32;
        [payload getBytes:&count32 range:NSMakeRange(offset, 4)];
        itemCount = CFSwapInt32BigToHost(count32);
        offset += 4;
    }
    
    // Parse each item
    for (uint32_t i = 0; i < itemCount && offset < payload.length; i++) {
        SeafIlocItem *item = [[SeafIlocItem alloc] init];
        
        // Read item_ID
        if (version < 2) {
            uint16_t itemID16;
            [payload getBytes:&itemID16 range:NSMakeRange(offset, 2)];
            item.itemID = CFSwapInt16BigToHost(itemID16);
            offset += 2;
        } else {
            uint32_t itemID32;
            [payload getBytes:&itemID32 range:NSMakeRange(offset, 4)];
            item.itemID = CFSwapInt32BigToHost(itemID32);
            offset += 4;
        }
        
        // Read construction_method (version >= 1)
        if (version >= 1) {
            uint16_t method;
            [payload getBytes:&method range:NSMakeRange(offset, 2)];
            item.constructionMethod = CFSwapInt16BigToHost(method) & 0x0F;
            offset += 2;
        }
        
        // Read data_reference_index
        uint16_t dataRefIndex;
        [payload getBytes:&dataRefIndex range:NSMakeRange(offset, 2)];
        item.dataReferenceIndex = CFSwapInt16BigToHost(dataRefIndex);
        offset += 2;
        
        // Read base_offset
        item.baseOffset = [self readIntFromData:payload atOffset:&offset withSize:ilocData.baseOffsetSize];
        
        // Read extent_count
        uint16_t extentCount;
        [payload getBytes:&extentCount range:NSMakeRange(offset, 2)];
        extentCount = CFSwapInt16BigToHost(extentCount);
        offset += 2;
        
        // Parse extents
        for (uint16_t e = 0; e < extentCount && offset < payload.length; e++) {
            SeafIlocExtent *extent = [[SeafIlocExtent alloc] init];
            
            // Read extent_index (version >= 1 and indexSize > 0)
            if ((version >= 1) && ilocData.indexSize > 0) {
                extent.extentIndex = [self readIntFromData:payload atOffset:&offset withSize:ilocData.indexSize];
            }
            
            // Read extent_offset
            extent.extentOffset = [self readIntFromData:payload atOffset:&offset withSize:ilocData.offsetSize];
            
            // Read extent_length
            extent.extentLength = [self readIntFromData:payload atOffset:&offset withSize:ilocData.lengthSize];
            
            [item.extents addObject:extent];
        }
        
        [ilocData.items addObject:item];
    }
    
    return ilocData;
}

- (uint64_t)readIntFromData:(NSData *)data atOffset:(NSUInteger *)offset withSize:(uint8_t)size {
    if (size == 0 || *offset + size > data.length) {
        return 0;
    }
    
    uint64_t value = 0;
    uint8_t bytes[8] = {0};
    [data getBytes:bytes range:NSMakeRange(*offset, size)];
    
    for (int i = 0; i < size; i++) {
        value = (value << 8) | bytes[i];
    }
    
    *offset += size;
    return value;
}

- (void)adjustIlocOffsets:(SeafIlocData *)ilocData byDelta:(int64_t)delta forOffsetsAbove:(uint64_t)threshold {
    if (!ilocData || delta == 0) {
        return;
    }
    
    for (SeafIlocItem *item in ilocData.items) {
        // Adjust base_offset if it points to or beyond mdat
        if (item.baseOffset >= threshold) {
            item.baseOffset += delta;
        }
        
        // Adjust extent offsets
        for (SeafIlocExtent *extent in item.extents) {
            // If base_offset is 0, extent_offset is absolute
            // If base_offset > 0, extent_offset is relative to base_offset
            if (item.baseOffset == 0 && extent.extentOffset >= threshold) {
                extent.extentOffset += delta;
            }
        }
    }
}

- (nullable NSData *)serializeIlocData:(SeafIlocData *)ilocData {
    if (!ilocData) {
        return nil;
    }
    
    NSMutableData *payload = [NSMutableData data];
    
    // Write version (1 byte) and flags (3 bytes)
    uint8_t versionFlags[4];
    versionFlags[0] = ilocData.version;
    versionFlags[1] = (ilocData.flags >> 16) & 0xFF;
    versionFlags[2] = (ilocData.flags >> 8) & 0xFF;
    versionFlags[3] = ilocData.flags & 0xFF;
    [payload appendBytes:versionFlags length:4];
    
    // Write size fields (2 bytes)
    uint8_t sizes[2];
    sizes[0] = ((ilocData.offsetSize & 0x0F) << 4) | (ilocData.lengthSize & 0x0F);
    sizes[1] = ((ilocData.baseOffsetSize & 0x0F) << 4) | (ilocData.indexSize & 0x0F);
    [payload appendBytes:sizes length:2];
    
    // Write item count
    uint32_t itemCount = (uint32_t)ilocData.items.count;
    if (ilocData.version < 2) {
        uint16_t count16 = CFSwapInt16HostToBig((uint16_t)itemCount);
        [payload appendBytes:&count16 length:2];
    } else {
        uint32_t count32 = CFSwapInt32HostToBig(itemCount);
        [payload appendBytes:&count32 length:4];
    }
    
    // Write each item
    for (SeafIlocItem *item in ilocData.items) {
        // Write item_ID
        if (ilocData.version < 2) {
            uint16_t itemID16 = CFSwapInt16HostToBig((uint16_t)item.itemID);
            [payload appendBytes:&itemID16 length:2];
        } else {
            uint32_t itemID32 = CFSwapInt32HostToBig(item.itemID);
            [payload appendBytes:&itemID32 length:4];
        }
        
        // Write construction_method (version >= 1)
        if (ilocData.version >= 1) {
            uint16_t method = CFSwapInt16HostToBig(item.constructionMethod & 0x0F);
            [payload appendBytes:&method length:2];
        }
        
        // Write data_reference_index
        uint16_t dataRefIndex = CFSwapInt16HostToBig(item.dataReferenceIndex);
        [payload appendBytes:&dataRefIndex length:2];
        
        // Write base_offset
        [self writeInt:item.baseOffset toData:payload withSize:ilocData.baseOffsetSize];
        
        // Write extent_count
        uint16_t extentCount = CFSwapInt16HostToBig((uint16_t)item.extents.count);
        [payload appendBytes:&extentCount length:2];
        
        // Write extents
        for (SeafIlocExtent *extent in item.extents) {
            // Write extent_index (version >= 1 and indexSize > 0)
            if ((ilocData.version >= 1) && ilocData.indexSize > 0) {
                [self writeInt:extent.extentIndex toData:payload withSize:ilocData.indexSize];
            }
            
            // Write extent_offset
            [self writeInt:extent.extentOffset toData:payload withSize:ilocData.offsetSize];
            
            // Write extent_length
            [self writeInt:extent.extentLength toData:payload withSize:ilocData.lengthSize];
        }
    }
    
    // Create iloc box with header
    NSMutableData *ilocBox = [NSMutableData data];
    uint32_t boxSize = CFSwapInt32HostToBig(8 + (uint32_t)payload.length);
    [ilocBox appendBytes:&boxSize length:4];
    [ilocBox appendBytes:"iloc" length:4];
    [ilocBox appendData:payload];
    
    return [ilocBox copy];
}

- (void)writeInt:(uint64_t)value toData:(NSMutableData *)data withSize:(uint8_t)size {
    if (size == 0) {
        return;
    }
    
    uint8_t bytes[8] = {0};
    for (int i = size - 1; i >= 0; i--) {
        bytes[i] = value & 0xFF;
        value >>= 8;
    }
    [data appendBytes:bytes length:size];
}

- (nullable NSData *)rebuildMetaBox:(SeafISOBMFFBox *)metaBox
                    withNewIlocData:(nullable SeafIlocData *)newIlocData
                            xmpData:(nullable NSData *)xmpData {
    if (!metaBox) {
        return nil;
    }
    
    NSMutableData *result = [NSMutableData data];
    
    // Get original meta content offset (after header and version/flags)
    uint64_t metaPayloadStart = metaBox.offset + metaBox.headerSize;
    
    // meta is a fullbox, skip version (1) + flags (3) = 4 bytes for children start
    uint64_t childrenStart = metaPayloadStart + 4;
    
    // Read version/flags from original
    uint8_t versionFlags[4];
    [self.data getBytes:versionFlags range:NSMakeRange(metaPayloadStart, 4)];
    
    // Start building meta content
    NSMutableData *metaContent = [NSMutableData data];
    [metaContent appendBytes:versionFlags length:4]; // version + flags
    
    // Find iloc box position in original data
    SeafISOBMFFBox *ilocBox = [self findIlocInMetaBox:metaBox];
    
    // Copy children, replacing iloc if needed
    for (SeafISOBMFFBox *child in metaBox.children) {
        if ([child.type isEqualToString:@"iloc"] && newIlocData) {
            // Use new iloc data
            NSData *newIlocBox = [self serializeIlocData:newIlocData];
            if (newIlocBox) {
                [metaContent appendData:newIlocBox];
            } else {
                // Fallback to original
                [metaContent appendData:[self.data subdataWithRange:NSMakeRange(child.offset, child.size)]];
            }
        } else {
            // Copy original child box
            [metaContent appendData:[self.data subdataWithRange:NSMakeRange(child.offset, child.size)]];
        }
    }
    
    // Add XMP uuid box if provided
    if (xmpData) {
        NSData *uuidBox = [self createXMPUuidBox:xmpData];
        [metaContent appendData:uuidBox];
    }
    
    // Build final meta box
    uint32_t metaSize = 8 + (uint32_t)metaContent.length;
    uint32_t metaSizeBE = CFSwapInt32HostToBig(metaSize);
    [result appendBytes:&metaSizeBE length:4];
    [result appendBytes:"meta" length:4];
    [result appendData:metaContent];
    
    return [result copy];
}

- (NSData *)createXMPUuidBox:(NSData *)xmpData {
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

#pragma mark - iinf Box Methods

- (nullable SeafISOBMFFBox *)findIinfInMetaBox:(SeafISOBMFFBox *)metaBox {
    if (!metaBox || !metaBox.children) {
        return nil;
    }
    
    for (SeafISOBMFFBox *child in metaBox.children) {
        if ([child.type isEqualToString:@"iinf"]) {
            return child;
        }
    }
    return nil;
}

- (nullable SeafIinfData *)parseIinfBox:(SeafISOBMFFBox *)iinfBox {
    if (!iinfBox || ![iinfBox.type isEqualToString:@"iinf"]) {
        return nil;
    }
    
    // Get iinf payload
    uint64_t payloadOffset = iinfBox.offset + iinfBox.headerSize;
    uint64_t payloadSize = iinfBox.size - iinfBox.headerSize;
    
    if (payloadOffset + payloadSize > self.data.length) {
        return nil;
    }
    
    NSData *payload = [self.data subdataWithRange:NSMakeRange(payloadOffset, payloadSize)];
    if (payload.length < 6) {
        return nil;
    }
    
    SeafIinfData *iinfData = [[SeafIinfData alloc] init];
    NSUInteger offset = 0;
    
    // Read version (1 byte) and flags (3 bytes)
    uint8_t version;
    [payload getBytes:&version range:NSMakeRange(offset, 1)];
    iinfData.version = version;
    offset += 1;
    
    uint8_t flagBytes[3];
    [payload getBytes:flagBytes range:NSMakeRange(offset, 3)];
    iinfData.flags = ((uint32_t)flagBytes[0] << 16) | ((uint32_t)flagBytes[1] << 8) | flagBytes[2];
    offset += 3;
    
    // Read entry count
    uint32_t entryCount = 0;
    if (version == 0) {
        uint16_t count16;
        [payload getBytes:&count16 range:NSMakeRange(offset, 2)];
        entryCount = CFSwapInt16BigToHost(count16);
        offset += 2;
    } else {
        uint32_t count32;
        [payload getBytes:&count32 range:NSMakeRange(offset, 4)];
        entryCount = CFSwapInt32BigToHost(count32);
        offset += 4;
    }
    
    // Parse infe boxes
    for (uint32_t i = 0; i < entryCount && offset + 8 < payload.length; i++) {
        // Read infe box header
        uint32_t infeSize;
        [payload getBytes:&infeSize range:NSMakeRange(offset, 4)];
        infeSize = CFSwapInt32BigToHost(infeSize);
        
        char infeType[5] = {0};
        [payload getBytes:infeType range:NSMakeRange(offset + 4, 4)];
        
        if (strcmp(infeType, "infe") != 0 || infeSize < 12 || offset + infeSize > payload.length) {
            offset += infeSize > 0 ? infeSize : 8;
            continue;
        }
        
        // Save raw infe data for preservation
        NSData *rawInfeData = [payload subdataWithRange:NSMakeRange(offset, infeSize)];
        
        SeafIinfItem *item = [[SeafIinfItem alloc] init];
        item.rawData = rawInfeData;
        
        // Parse infe content
        NSUInteger infeOffset = 8; // After box header
        
        uint8_t infeVersion;
        [rawInfeData getBytes:&infeVersion range:NSMakeRange(infeOffset, 1)];
        item.version = infeVersion;
        infeOffset += 4; // version + flags
        
        if (infeVersion >= 2) {
            // Version 2+: item_ID(2 or 4) + item_protection_index(2) + item_type(4)
            if (infeVersion == 2) {
                uint16_t itemID16;
                [rawInfeData getBytes:&itemID16 range:NSMakeRange(infeOffset, 2)];
                item.itemID = CFSwapInt16BigToHost(itemID16);
                infeOffset += 2;
            } else {
                uint32_t itemID32;
                [rawInfeData getBytes:&itemID32 range:NSMakeRange(infeOffset, 4)];
                item.itemID = CFSwapInt32BigToHost(itemID32);
                infeOffset += 4;
            }
            
            uint16_t protIdx;
            [rawInfeData getBytes:&protIdx range:NSMakeRange(infeOffset, 2)];
            item.itemProtectionIndex = CFSwapInt16BigToHost(protIdx);
            infeOffset += 2;
            
            char itemType[5] = {0};
            [rawInfeData getBytes:itemType range:NSMakeRange(infeOffset, 4)];
            item.itemType = [NSString stringWithUTF8String:itemType];
            infeOffset += 4;
            
            // For mime type, read content_type (null-terminated string after item_name)
            if ([item.itemType isEqualToString:@"mime"] && infeOffset < rawInfeData.length) {
                // item_name (null-terminated)
                NSUInteger nameStart = infeOffset;
                NSUInteger nameEnd = nameStart;
                const uint8_t *bytes = rawInfeData.bytes;
                while (nameEnd < rawInfeData.length && bytes[nameEnd] != 0) {
                    nameEnd++;
                }
                if (nameEnd > nameStart) {
                    item.itemName = [[NSString alloc] initWithBytes:bytes + nameStart
                                                            length:nameEnd - nameStart
                                                          encoding:NSUTF8StringEncoding];
                }
                infeOffset = nameEnd + 1; // Skip null terminator
                
                // content_type (null-terminated)
                if (infeOffset < rawInfeData.length) {
                    NSUInteger ctStart = infeOffset;
                    NSUInteger ctEnd = ctStart;
                    while (ctEnd < rawInfeData.length && bytes[ctEnd] != 0) {
                        ctEnd++;
                    }
                    if (ctEnd > ctStart) {
                        item.contentType = [[NSString alloc] initWithBytes:bytes + ctStart
                                                                    length:ctEnd - ctStart
                                                                  encoding:NSUTF8StringEncoding];
                    }
                }
            }
        }
        
        [iinfData.items addObject:item];
        offset += infeSize;
    }
    
    return iinfData;
}

- (nullable NSData *)serializeIinfData:(SeafIinfData *)iinfData {
    if (!iinfData) {
        return nil;
    }
    
    NSMutableData *payload = [NSMutableData data];
    
    // Write version (1 byte) and flags (3 bytes)
    uint8_t versionFlags[4];
    versionFlags[0] = iinfData.version;
    versionFlags[1] = (iinfData.flags >> 16) & 0xFF;
    versionFlags[2] = (iinfData.flags >> 8) & 0xFF;
    versionFlags[3] = iinfData.flags & 0xFF;
    [payload appendBytes:versionFlags length:4];
    
    // Write entry count
    uint32_t entryCount = (uint32_t)iinfData.items.count;
    if (iinfData.version == 0) {
        uint16_t count16 = CFSwapInt16HostToBig((uint16_t)entryCount);
        [payload appendBytes:&count16 length:2];
    } else {
        uint32_t count32 = CFSwapInt32HostToBig(entryCount);
        [payload appendBytes:&count32 length:4];
    }
    
    // Write infe boxes
    for (SeafIinfItem *item in iinfData.items) {
        if (item.rawData) {
            // Use preserved raw data for existing items
            [payload appendData:item.rawData];
        } else {
            // Build new infe box for new items
            NSData *infeBox = [self createInfeBoxForItem:item];
            if (infeBox) {
                [payload appendData:infeBox];
            }
        }
    }
    
    // Build iinf box with header
    NSMutableData *iinfBox = [NSMutableData data];
    uint32_t boxSize = CFSwapInt32HostToBig(8 + (uint32_t)payload.length);
    [iinfBox appendBytes:&boxSize length:4];
    [iinfBox appendBytes:"iinf" length:4];
    [iinfBox appendData:payload];
    
    return [iinfBox copy];
}

- (NSData *)createInfeBoxForItem:(SeafIinfItem *)item {
    NSMutableData *payload = [NSMutableData data];
    
    // Version + flags
    uint8_t versionFlags[4] = {item.version, 0, 0, 0};
    [payload appendBytes:versionFlags length:4];
    
    // item_ID (version 2: 2 bytes, version 3: 4 bytes)
    if (item.version == 2) {
        uint16_t itemID = CFSwapInt16HostToBig((uint16_t)item.itemID);
        [payload appendBytes:&itemID length:2];
    } else {
        uint32_t itemID = CFSwapInt32HostToBig(item.itemID);
        [payload appendBytes:&itemID length:4];
    }
    
    // item_protection_index
    uint16_t protIdx = CFSwapInt16HostToBig(item.itemProtectionIndex);
    [payload appendBytes:&protIdx length:2];
    
    // item_type (4 bytes)
    const char *typeStr = [item.itemType UTF8String];
    char typeBytes[4] = {0, 0, 0, 0};
    if (typeStr) {
        strncpy(typeBytes, typeStr, 4);
    }
    [payload appendBytes:typeBytes length:4];
    
    // For mime type, add item_name (empty) + null + content_type + null
    if ([item.itemType isEqualToString:@"mime"]) {
        // item_name (empty string, just null terminator)
        uint8_t nullByte = 0;
        [payload appendBytes:&nullByte length:1];
        
        // content_type
        if (item.contentType) {
            const char *ct = [item.contentType UTF8String];
            [payload appendBytes:ct length:strlen(ct)];
        }
        [payload appendBytes:&nullByte length:1];
    }
    
    // Build infe box
    NSMutableData *infeBox = [NSMutableData data];
    uint32_t boxSize = CFSwapInt32HostToBig(8 + (uint32_t)payload.length);
    [infeBox appendBytes:&boxSize length:4];
    [infeBox appendBytes:"infe" length:4];
    [infeBox appendData:payload];
    
    return [infeBox copy];
}

- (SeafIinfItem *)createMimeInfeItemWithID:(uint32_t)itemID version:(uint8_t)version {
    SeafIinfItem *item = [[SeafIinfItem alloc] init];
    item.version = version;
    item.itemID = itemID;
    item.itemProtectionIndex = 0;
    item.itemType = @"mime";
    item.itemName = @"";
    item.contentType = @"application/rdf+xml";
    item.rawData = nil; // Will be serialized from properties
    return item;
}

- (uint32_t)getMaxItemIDFromIinfData:(SeafIinfData *)iinfData {
    uint32_t maxID = 0;
    for (SeafIinfItem *item in iinfData.items) {
        if (item.itemID > maxID) {
            maxID = item.itemID;
        }
    }
    return maxID;
}

- (void)addItemToIlocData:(SeafIlocData *)ilocData
                   itemID:(uint32_t)itemID
                   offset:(uint64_t)offset
                   length:(uint64_t)length {
    if (!ilocData) {
        return;
    }
    
    SeafIlocItem *item = [[SeafIlocItem alloc] init];
    item.itemID = itemID;
    item.constructionMethod = 0;
    item.dataReferenceIndex = 0;
    item.baseOffset = 0;
    
    SeafIlocExtent *extent = [[SeafIlocExtent alloc] init];
    extent.extentIndex = 0;
    extent.extentOffset = offset;
    extent.extentLength = length;
    
    [item.extents addObject:extent];
    [ilocData.items addObject:item];
}

- (nullable NSData *)rebuildMetaBoxWithIlocData:(SeafIlocData *)ilocData
                                       iinfData:(SeafIinfData *)iinfData
                                originalMetaBox:(SeafISOBMFFBox *)metaBox {
    if (!metaBox) {
        return nil;
    }
    
    NSMutableData *metaContent = [NSMutableData data];
    
    // Read original version/flags
    uint64_t metaPayloadStart = metaBox.offset + metaBox.headerSize;
    uint8_t versionFlags[4];
    [self.data getBytes:versionFlags range:NSMakeRange(metaPayloadStart, 4)];
    [metaContent appendBytes:versionFlags length:4];
    
    // Serialize new iinf and iloc
    NSData *newIinfBox = iinfData ? [self serializeIinfData:iinfData] : nil;
    NSData *newIlocBox = ilocData ? [self serializeIlocData:ilocData] : nil;
    
    // Copy children, replacing iinf and iloc as needed
    for (SeafISOBMFFBox *child in metaBox.children) {
        if ([child.type isEqualToString:@"iinf"] && newIinfBox) {
            [metaContent appendData:newIinfBox];
        } else if ([child.type isEqualToString:@"iloc"] && newIlocBox) {
            [metaContent appendData:newIlocBox];
        } else {
            // Copy original child box
            [metaContent appendData:[self.data subdataWithRange:NSMakeRange(child.offset, child.size)]];
        }
    }
    
    // Build final meta box
    NSMutableData *result = [NSMutableData data];
    uint32_t metaSize = 8 + (uint32_t)metaContent.length;
    uint32_t metaSizeBE = CFSwapInt32HostToBig(metaSize);
    [result appendBytes:&metaSizeBE length:4];
    [result appendBytes:"meta" length:4];
    [result appendData:metaContent];
    
    return [result copy];
}

#pragma mark - iref Methods

- (nullable SeafISOBMFFBox *)findIrefInMetaBox:(SeafISOBMFFBox *)metaBox {
    if (!metaBox || !metaBox.children) {
        return nil;
    }
    
    for (SeafISOBMFFBox *child in metaBox.children) {
        if ([child.type isEqualToString:@"iref"]) {
            return child;
        }
    }
    return nil;
}

- (nullable NSDictionary *)parseIrefBox:(SeafISOBMFFBox *)irefBox {
    if (!irefBox || ![irefBox.type isEqualToString:@"iref"]) {
        return nil;
    }
    
    uint64_t payloadOffset = irefBox.offset + irefBox.headerSize;
    uint64_t payloadSize = irefBox.size - irefBox.headerSize;
    
    if (payloadOffset + payloadSize > self.data.length || payloadSize < 4) {
        return nil;
    }
    
    NSData *payload = [self.data subdataWithRange:NSMakeRange(payloadOffset, payloadSize)];
    
    // Read version and flags
    uint8_t version;
    [payload getBytes:&version range:NSMakeRange(0, 1)];
    
    uint8_t flagBytes[3];
    [payload getBytes:flagBytes range:NSMakeRange(1, 3)];
    uint32_t flags = ((uint32_t)flagBytes[0] << 16) | ((uint32_t)flagBytes[1] << 8) | flagBytes[2];
    
    return @{
        @"version": @(version),
        @"flags": @(flags),
        @"payload": payload,
        @"payloadOffset": @(payloadOffset)
    };
}

- (nullable NSData *)addCdscReferenceToIrefData:(NSData *)irefData
                                    fromItemID:(uint32_t)fromItemID
                                      toItemID:(uint32_t)toItemID {
    if (!irefData || irefData.length < 4) {
        return nil;
    }
    
    // Read version
    uint8_t version;
    [irefData getBytes:&version range:NSMakeRange(0, 1)];
    
    // Create new cdsc reference entry
    // SingleItemTypeReferenceBox format:
    // - box_size (4 bytes)
    // - box_type 'cdsc' (4 bytes)
    // - from_item_ID (2 or 4 bytes depending on version)
    // - reference_count (2 bytes)
    // - to_item_ID (2 or 4 bytes) * reference_count
    
    NSMutableData *cdscEntry = [NSMutableData data];
    
    if (version < 2) {
        // Version 0/1: 2-byte item IDs
        // Size = 8 (header) + 2 (from_item_ID) + 2 (ref_count) + 2 (to_item_ID) = 14 bytes
        uint32_t cdscSize = CFSwapInt32HostToBig(14);
        [cdscEntry appendBytes:&cdscSize length:4];
        [cdscEntry appendBytes:"cdsc" length:4];
        
        uint16_t fromID = CFSwapInt16HostToBig((uint16_t)fromItemID);
        [cdscEntry appendBytes:&fromID length:2];
        
        uint16_t refCount = CFSwapInt16HostToBig(1);
        [cdscEntry appendBytes:&refCount length:2];
        
        uint16_t toID = CFSwapInt16HostToBig((uint16_t)toItemID);
        [cdscEntry appendBytes:&toID length:2];
    } else {
        // Version 2+: 4-byte item IDs
        // Size = 8 (header) + 4 (from_item_ID) + 2 (ref_count) + 4 (to_item_ID) = 18 bytes
        uint32_t cdscSize = CFSwapInt32HostToBig(18);
        [cdscEntry appendBytes:&cdscSize length:4];
        [cdscEntry appendBytes:"cdsc" length:4];
        
        uint32_t fromID = CFSwapInt32HostToBig(fromItemID);
        [cdscEntry appendBytes:&fromID length:4];
        
        uint16_t refCount = CFSwapInt16HostToBig(1);
        [cdscEntry appendBytes:&refCount length:2];
        
        uint32_t toID = CFSwapInt32HostToBig(toItemID);
        [cdscEntry appendBytes:&toID length:4];
    }
    
    // Build new iref box: original content + new cdsc entry
    NSMutableData *newIrefPayload = [NSMutableData data];
    [newIrefPayload appendData:irefData]; // Original payload (includes version/flags)
    [newIrefPayload appendData:cdscEntry];
    
    // Build iref box with header
    NSMutableData *newIrefBox = [NSMutableData data];
    uint32_t irefSize = CFSwapInt32HostToBig(8 + (uint32_t)newIrefPayload.length);
    [newIrefBox appendBytes:&irefSize length:4];
    [newIrefBox appendBytes:"iref" length:4];
    [newIrefBox appendData:newIrefPayload];
    
    return [newIrefBox copy];
}

- (uint32_t)getPrimaryItemIDFromMetaBox:(SeafISOBMFFBox *)metaBox {
    if (!metaBox || !metaBox.children) {
        return 0;
    }
    
    // Find pitm (primary item) box
    for (SeafISOBMFFBox *child in metaBox.children) {
        if ([child.type isEqualToString:@"pitm"]) {
            // pitm is a FullBox: version(1) + flags(3) + item_ID(2 or 4)
            uint64_t payloadOffset = child.offset + child.headerSize;
            uint64_t payloadSize = child.size - child.headerSize;
            
            if (payloadOffset + payloadSize > self.data.length || payloadSize < 6) {
                return 0;
            }
            
            uint8_t version;
            [self.data getBytes:&version range:NSMakeRange(payloadOffset, 1)];
            
            if (version == 0) {
                uint16_t itemID;
                [self.data getBytes:&itemID range:NSMakeRange(payloadOffset + 4, 2)];
                return CFSwapInt16BigToHost(itemID);
            } else {
                uint32_t itemID;
                [self.data getBytes:&itemID range:NSMakeRange(payloadOffset + 4, 4)];
                return CFSwapInt32BigToHost(itemID);
            }
        }
    }
    
    return 0;
}

@end

