//
//  SeafISOBMFFParser.h
//  Seafile
//
//  Created for Motion Photo support.
//  Parser for ISO Base Media File Format (ISOBMFF) used in HEIC/MP4 files.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - SeafISOBMFFBox

/**
 * Represents a single box in an ISOBMFF file structure.
 * ISOBMFF boxes are the basic building blocks of HEIC, MP4, MOV files.
 */
@interface SeafISOBMFFBox : NSObject

/// Box type identifier (e.g., "ftyp", "meta", "mdat", "moov")
@property (nonatomic, copy) NSString *type;

/// Offset of this box in the file (bytes from start)
@property (nonatomic, assign) uint64_t offset;

/// Total size of this box including header (in bytes)
@property (nonatomic, assign) uint64_t size;

/// Size of the box header (typically 8 bytes, or 16 for extended size)
@property (nonatomic, assign) uint32_t headerSize;

/// Box payload data (loaded on demand, may be nil)
@property (nonatomic, strong, nullable) NSData *payload;

/// Child boxes for container boxes (e.g., moov contains trak, meta contains iloc)
@property (nonatomic, strong, nullable) NSArray<SeafISOBMFFBox *> *children;

/// Convenience method to get payload offset
- (uint64_t)payloadOffset;

/// Convenience method to get payload size
- (uint64_t)payloadSize;

@end

#pragma mark - SeafISOBMFFParser

/**
 * Parser for ISO Base Media File Format files.
 * Supports parsing HEIC, HEIF, MP4, MOV file structures.
 */
@interface SeafISOBMFFParser : NSObject

/// The raw data being parsed (readonly)
@property (nonatomic, strong, readonly) NSData *data;

/// Initialize with file data
- (instancetype)initWithData:(NSData *)data;

/// Initialize with file path
- (instancetype)initWithPath:(NSString *)path;

/// Parse all top-level boxes in the file
- (NSArray<SeafISOBMFFBox *> *)parseTopLevelBoxes;

/// Parse boxes within a specific range (for parsing child boxes)
- (NSArray<SeafISOBMFFBox *> *)parseBoxesInRange:(NSRange)range;

/// Find a box by type at the top level
- (nullable SeafISOBMFFBox *)findBoxWithType:(NSString *)type;

/// Find all boxes with a specific type
- (NSArray<SeafISOBMFFBox *> *)findAllBoxesWithType:(NSString *)type;

/// Find a nested box by path (e.g., @[@"moov", @"trak", @"mdia"])
- (nullable SeafISOBMFFBox *)findBoxAtPath:(NSArray<NSString *> *)path;

/// Get payload data for a specific box
- (nullable NSData *)payloadDataForBox:(SeafISOBMFFBox *)box;

/// Check if data appears to be a valid ISOBMFF file (checks for valid ftyp)
+ (BOOL)isValidISOBMFFData:(NSData *)data;

/// Check if the file is HEIC/HEIF format
+ (BOOL)isHEICData:(NSData *)data;

/// Check if the file is MP4/MOV format
+ (BOOL)isMP4Data:(NSData *)data;

#pragma mark - XMP Extraction Helpers

/// Extract XMP data from HEIC file (looks in meta box)
- (nullable NSData *)extractXMPFromHEIC;

/// Extract XMP data from JPEG-style APP1 marker (if present in data)
+ (nullable NSData *)extractXMPFromJPEGData:(NSData *)data;

@end

#pragma mark - iloc Box Data Models

@class SeafIlocExtent;
@class SeafIlocItem;
@class SeafIlocData;

/**
 * Represents an extent (data range) within an iloc item.
 */
@interface SeafIlocExtent : NSObject
@property (nonatomic, assign) uint64_t extentIndex;
@property (nonatomic, assign) uint64_t extentOffset;
@property (nonatomic, assign) uint64_t extentLength;
@end

/**
 * Represents an item entry in the iloc box.
 */
@interface SeafIlocItem : NSObject
@property (nonatomic, assign) uint32_t itemID;
@property (nonatomic, assign) uint16_t constructionMethod;
@property (nonatomic, assign) uint16_t dataReferenceIndex;
@property (nonatomic, assign) uint64_t baseOffset;
@property (nonatomic, strong) NSMutableArray<SeafIlocExtent *> *extents;
@end

/**
 * Represents the parsed iloc box structure.
 */
@interface SeafIlocData : NSObject
@property (nonatomic, assign) uint8_t version;
@property (nonatomic, assign) uint32_t flags;
@property (nonatomic, assign) uint8_t offsetSize;
@property (nonatomic, assign) uint8_t lengthSize;
@property (nonatomic, assign) uint8_t baseOffsetSize;
@property (nonatomic, assign) uint8_t indexSize;
@property (nonatomic, strong) NSMutableArray<SeafIlocItem *> *items;
@end

#pragma mark - iinf Box Data Models

@class SeafIinfItem;
@class SeafIinfData;

/**
 * Represents an item entry (infe box) in the iinf box.
 */
@interface SeafIinfItem : NSObject
@property (nonatomic, assign) uint8_t version;
@property (nonatomic, assign) uint32_t itemID;
@property (nonatomic, assign) uint16_t itemProtectionIndex;
@property (nonatomic, copy) NSString *itemType;           // 4 character code (e.g., "hvc1", "Exif", "mime")
@property (nonatomic, copy, nullable) NSString *itemName;
@property (nonatomic, copy, nullable) NSString *contentType;     // For mime type items
@property (nonatomic, copy, nullable) NSString *contentEncoding; // Optional
@property (nonatomic, strong) NSData *rawData;           // Original infe box data for preservation
@end

/**
 * Represents the parsed iinf box structure.
 */
@interface SeafIinfData : NSObject
@property (nonatomic, assign) uint8_t version;
@property (nonatomic, assign) uint32_t flags;
@property (nonatomic, strong) NSMutableArray<SeafIinfItem *> *items;
@end

#pragma mark - SeafISOBMFFParser iloc/iinf Box Manipulation Methods

/**
 * Extension on SeafISOBMFFParser for iloc and iinf box manipulation.
 */
@interface SeafISOBMFFParser (IlocManipulation)

#pragma mark - iloc Methods

/**
 * Parse iloc box data into structured format.
 * @param ilocBox The iloc box to parse
 * @return Parsed iloc data, or nil on failure
 */
- (nullable SeafIlocData *)parseIlocBox:(SeafISOBMFFBox *)ilocBox;

/**
 * Adjust all offsets in iloc data by a delta value.
 * Used when inserting data before mdat box.
 * @param ilocData The iloc data to modify
 * @param delta The offset adjustment (positive to shift forward)
 * @param threshold Only adjust offsets >= this value (typically mdat offset)
 */
- (void)adjustIlocOffsets:(SeafIlocData *)ilocData byDelta:(int64_t)delta forOffsetsAbove:(uint64_t)threshold;

/**
 * Serialize iloc data back to binary format.
 * @param ilocData The iloc data to serialize
 * @return Serialized iloc box data (including box header), or nil on failure
 */
- (nullable NSData *)serializeIlocData:(SeafIlocData *)ilocData;

/**
 * Find iloc box within meta box children.
 * @param metaBox The meta box to search in
 * @return The iloc box if found, nil otherwise
 */
- (nullable SeafISOBMFFBox *)findIlocInMetaBox:(SeafISOBMFFBox *)metaBox;

/**
 * Add a new item to iloc data.
 * @param ilocData The iloc data to modify
 * @param itemID The item ID for the new item
 * @param offset The offset where the item data is located
 * @param length The length of the item data
 */
- (void)addItemToIlocData:(SeafIlocData *)ilocData
                   itemID:(uint32_t)itemID
                   offset:(uint64_t)offset
                   length:(uint64_t)length;

#pragma mark - iinf Methods

/**
 * Find iinf box within meta box children.
 * @param metaBox The meta box to search in
 * @return The iinf box if found, nil otherwise
 */
- (nullable SeafISOBMFFBox *)findIinfInMetaBox:(SeafISOBMFFBox *)metaBox;

/**
 * Parse iinf box data into structured format.
 * @param iinfBox The iinf box to parse
 * @return Parsed iinf data, or nil on failure
 */
- (nullable SeafIinfData *)parseIinfBox:(SeafISOBMFFBox *)iinfBox;

/**
 * Serialize iinf data back to binary format.
 * @param iinfData The iinf data to serialize
 * @return Serialized iinf box data (including box header), or nil on failure
 */
- (nullable NSData *)serializeIinfData:(SeafIinfData *)iinfData;

/**
 * Create a new mime type infe box for XMP data.
 * @param itemID The item ID
 * @param version The infe version (2 for standard)
 * @return The new infe item
 */
- (SeafIinfItem *)createMimeInfeItemWithID:(uint32_t)itemID version:(uint8_t)version;

/**
 * Get the maximum item ID from iinf data.
 * @param iinfData The iinf data
 * @return The maximum item ID, or 0 if no items
 */
- (uint32_t)getMaxItemIDFromIinfData:(SeafIinfData *)iinfData;

#pragma mark - Meta Box Rebuild Methods

/**
 * Rebuild meta box with modified iloc, iinf, and appended XMP in mdat.
 * This is the main method for injecting XMP as a mime item.
 * @param metaBox Original meta box
 * @param ilocData Modified iloc data
 * @param iinfData Modified iinf data  
 * @return Rebuilt meta box data, or nil on failure
 */
- (nullable NSData *)rebuildMetaBoxWithIlocData:(SeafIlocData *)ilocData
                                       iinfData:(SeafIinfData *)iinfData
                                originalMetaBox:(SeafISOBMFFBox *)metaBox;

/**
 * Rebuild meta box with modified iloc and optional new XMP uuid box.
 * @param metaBox Original meta box
 * @param newIlocData Modified iloc data (or nil to keep original)
 * @param xmpData XMP data to add as uuid box (or nil to skip)
 * @return Rebuilt meta box data, or nil on failure
 */
- (nullable NSData *)rebuildMetaBox:(SeafISOBMFFBox *)metaBox
                    withNewIlocData:(nullable SeafIlocData *)newIlocData
                            xmpData:(nullable NSData *)xmpData;

#pragma mark - iref Methods

/**
 * Find iref box within meta box children.
 * @param metaBox The meta box to search in
 * @return The iref box if found, nil otherwise
 */
- (nullable SeafISOBMFFBox *)findIrefInMetaBox:(SeafISOBMFFBox *)metaBox;

/**
 * Parse iref box and return the raw data with reference entries.
 * @param irefBox The iref box to parse
 * @return Dictionary containing version, flags, and reference entries
 */
- (nullable NSDictionary *)parseIrefBox:(SeafISOBMFFBox *)irefBox;

/**
 * Add a cdsc (content description) reference to iref data.
 * This links a metadata item (like XMP) to the primary image.
 * @param irefData Original iref raw data
 * @param fromItemID The item ID of the metadata (e.g., XMP item)
 * @param toItemID The item ID of the primary image
 * @return New iref box data with added cdsc reference, or nil on failure
 */
- (nullable NSData *)addCdscReferenceToIrefData:(NSData *)irefData
                                    fromItemID:(uint32_t)fromItemID
                                      toItemID:(uint32_t)toItemID;

/**
 * Get primary item ID from pitm box in meta.
 * @param metaBox The meta box to search in
 * @return Primary item ID, or 0 if not found
 */
- (uint32_t)getPrimaryItemIDFromMetaBox:(SeafISOBMFFBox *)metaBox;

@end

NS_ASSUME_NONNULL_END

