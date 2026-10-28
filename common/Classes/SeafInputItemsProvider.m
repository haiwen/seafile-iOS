//
//  SeafInputItemsProvider.m
//  seafilePro
//
//  Created by three on 2018/8/16.
//  Copyright © 2018年 Seafile. All rights reserved.
//

#import "SeafInputItemsProvider.h"
#import "Debug.h"
#import "Utils.h"
#import "SeafStorage.h"
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "SeafUploadFile.h"

@interface SeafInputItemsProvider()

@property (nonatomic, strong) NSMutableArray *ufiles;
@property (nonatomic, strong) CompleteBlock completeBlock;
@property (nonatomic, copy) NSString *tmpdir;
@property (nonatomic, strong) NSArray *pendingProviders;  // All item providers to process
@property (nonatomic, assign) NSInteger currentIndex;      // Current processing index
@property (nonatomic, copy) NSString *lastErrorMessage;    // Last error message from failed items

@end

@implementation SeafInputItemsProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        self.ufiles = [[NSMutableArray alloc] init];
        self.currentIndex = 0;
    }
    return self;
}

+ (void)loadInputs:(NSExtensionContext *)extensionContext complete:(CompleteBlock)block {
    SeafInputItemsProvider *provider = [[SeafInputItemsProvider alloc] init];

    [provider.ufiles removeAllObjects];
    provider.completeBlock = block;
        
    NSString *tmpdir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.tempDir];
    if (![Utils checkMakeDir:tmpdir]) {
        Warning("Failed to create temp dir.");
        provider.completeBlock(false, nil, @"Failed to load file");
        return;
    }
    provider.tmpdir = tmpdir;
    
    // Collect all item providers for serial processing
    NSMutableArray *allProviders = [NSMutableArray array];
    for (NSExtensionItem *item in extensionContext.inputItems) {
        for (NSItemProvider *itemProvider in item.attachments) {
            [allProviders addObject:itemProvider];
        }
    }
    
    provider.pendingProviders = allProviders;
    provider.currentIndex = 0;
    
    Debug("Total items to process: %lu", (unsigned long)allProviders.count);
    
    // Start serial processing
    [provider processNextItem];
}

#pragma mark - Serial Processing

/// Process items one by one to avoid memory pressure
- (void)processNextItem {
    // All items processed
    if (self.currentIndex >= self.pendingProviders.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.ufiles.count > 0) {
                // At least one file was processed successfully
                Debug("Completed: %lu items processed successfully", (unsigned long)self.ufiles.count);
                self.completeBlock(true, self.ufiles, @"");
            } else {
                // No files were processed successfully
                Warning("Failed: no items were processed successfully");
                NSString *errorMsg = self.lastErrorMessage ?: @"Failed to load file";
                self.completeBlock(false, nil, errorMsg);
            }
        });
        return;
    }
    
    NSItemProvider *itemProvider = self.pendingProviders[self.currentIndex];
    Debug("Processing item %ld/%lu: %@ registered=%@", (long)(self.currentIndex + 1), (unsigned long)self.pendingProviders.count, itemProvider, itemProvider.registeredTypeIdentifiers);

    // Advance to the next item regardless of this item's result.
    // dispatch_async avoids stack growth when many items are shared at once.
    ItemLoadHandler advance = ^(BOOL result) {
        self.currentIndex++;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self processNextItem];
        });
    };

    if ([self isStillImageProvider:itemProvider]) {
        // Photos hands us a file already exported per the share sheet's Format /
        // Location options. Ask for that concrete image type so the exported file
        // keeps its EXIF / GPS. The generic public.url / public.item load below
        // returns a file without the image property dictionary (issue #555).
        [self loadImageItem:itemProvider handler:advance];
    } else {
        [self loadLegacyItem:itemProvider handler:advance];
    }
}

#pragma mark - Still images (issue #555)

/// YES when the attachment is a still image and not a movie (Live Photo video parts are movies).
- (BOOL)isStillImageProvider:(NSItemProvider *)itemProvider {
    return [itemProvider hasItemConformingToTypeIdentifier:UTTypeImage.identifier]
        && ![itemProvider hasItemConformingToTypeIdentifier:UTTypeMovie.identifier];
}

/// First registered type that conforms to public.image and carries a concrete file
/// extension (e.g. public.heic, public.jpeg, public.png). Photos registers the type
/// matching the Format option, so Current keeps HEIC and Most Compatible yields JPEG.
/// Falls back to any registered image type, then the generic image type.
- (NSString *)preferredImageTypeIdentifierForProvider:(NSItemProvider *)itemProvider {
    NSString *firstImageType = nil;
    for (NSString *typeId in itemProvider.registeredTypeIdentifiers) {
        UTType *type = [UTType typeWithIdentifier:typeId];
        if (type && [type conformsToType:UTTypeImage]) {
            if (type.preferredFilenameExtension.length > 0) {
                return typeId;
            }
            if (!firstImageType) {
                firstImageType = typeId;
            }
        }
    }
    return firstImageType ?: UTTypeImage.identifier;
}

/// Load the image as a file representation of its concrete type, copying it into
/// the temp dir before the callback returns (the system deletes the source after).
/// Falls back to the data representation, then to the legacy loadItem flow.
- (void)loadImageItem:(NSItemProvider *)itemProvider handler:(ItemLoadHandler)handler {
    NSString *typeId = [self preferredImageTypeIdentifierForProvider:itemProvider];
    Debug("Load image item as %@", typeId);

    [itemProvider loadFileRepresentationForTypeIdentifier:typeId
                                        completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
        @autoreleasepool {
            if (url) {
                NSString *actualExt = [self imageExtensionForFileURL:url];
                if (actualExt.length > 0) {
                    NSString *fileName = [self fileName:url.lastPathComponent ensuringExtension:actualExt];
                    NSURL *targetUrl = [self uniqueTargetUrlForName:fileName];
                    if ([Utils copyFile:url to:targetUrl]) {
                        NSDate *modDate = [self modificationDateOfURL:url];
                        [self addUploadFileAtURL:targetUrl lastModified:modDate];
                        [self loadPreviewImageWith:itemProvider toTargetUrl:targetUrl lastModified:modDate handler:handler];
                        return;
                    }
                    Warning("Failed to copy image file representation %@", url);
                } else {
                    // When the host shares an in-memory UIImage via UIActivityItemProvider
                    // (e.g. iOS screenshot markup preview), NSItemProvider writes an
                    // NSKeyedArchiver plist of the UIImage to `url` instead of a real
                    // image file. Unarchive it into real image container bytes.
                    NSData *fileData = [NSData dataWithContentsOfURL:url];
                    if ([self saveNormalizedImageData:fileData
                                             provider:itemProvider
                                       typeIdentifier:typeId
                                         fallbackName:url.lastPathComponent
                                              handler:handler]) {
                        return;
                    }
                    Warning("File representation at %@ is not a readable image container", url);
                }
            } else {
                Warning("loadFileRepresentation(%@) failed at index %ld: %@", typeId, (long)self.currentIndex, error);
            }
            [self loadImageDataItem:itemProvider typeIdentifier:typeId handler:handler];
        }
    }];
}

- (void)loadImageDataItem:(NSItemProvider *)itemProvider typeIdentifier:(NSString *)typeId handler:(ItemLoadHandler)handler {
    [itemProvider loadDataRepresentationForTypeIdentifier:typeId
                                        completionHandler:^(NSData * _Nullable data, NSError * _Nullable error) {
        @autoreleasepool {
            if (data.length > 0) {
                if ([self saveNormalizedImageData:data
                                         provider:itemProvider
                                   typeIdentifier:typeId
                                     fallbackName:nil
                                          handler:handler]) {
                    return;
                }
                Warning("Data representation for %@ is not a readable image container", typeId);
            } else {
                Warning("loadDataRepresentation(%@) failed at index %ld: %@", typeId, (long)self.currentIndex, error);
            }
            // Some providers only vend a UIImage; let the legacy flow handle it.
            [self loadLegacyItem:itemProvider handler:handler];
        }
    }];
}

#pragma mark - Legacy loadItem flow

/// Original flow: load public.url (files, ics) or public.item and dispatch on the
/// returned object class (NSURL / UIImage / NSString).
- (void)loadLegacyItem:(NSItemProvider *)itemProvider handler:(ItemLoadHandler)handler {
    if ([itemProvider hasItemConformingToTypeIdentifier:UTTypeItem.identifier] ||
        [itemProvider hasItemConformingToTypeIdentifier:@"public.url"]) {

        // Files or ics need to call with "public.url" as identifier
        NSString *typeIdentifier = UTTypeItem.identifier;
        if ([itemProvider hasItemConformingToTypeIdentifier:@"public.url"]) {
            typeIdentifier = @"public.url";
        }

        [itemProvider loadItemForTypeIdentifier:typeIdentifier
                                        options:nil
                              completionHandler:^(id<NSSecureCoding, NSObject> _Nullable item, NSError * _Null_unspecified error) {
            @autoreleasepool {
                if (!error) {
                    [self loadMatchingItem:item provider:itemProvider handler:handler];
                } else {
                    Warning("Failed to load item at index %ld: %@", (long)self.currentIndex, error);
                    if (handler) handler(false);
                }
            }
        }];
    } else {
        Warning("Unsupported item type at index %ld", (long)self.currentIndex);
        if (handler) handler(false);
    }
}

#pragma mark - Helpers

- (NSString *)timestampString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    // Fixed-format output: Gregorian year and ASCII digits regardless of the
    // device calendar / locale, so the file name is stable.
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    [formatter setDateFormat:@"yyyy'-'MM'-'dd'_'HH'-'mm'-'ss"];
    return [formatter stringFromDate:[NSDate date]];
}

- (NSDate *)modificationDateOfURL:(NSURL *)url {
    NSDate *modificationDate = nil;
    [url getResourceValue:&modificationDate forKey:NSURLContentModificationDateKey error:nil];
    NSDate *creationDate = nil;
    [url getResourceValue:&creationDate forKey:NSURLCreationDateKey error:nil];
    return modificationDate ?: creationDate;
}

/// jpg/jpeg and tif/tiff are the same container under two extensions. heic/heif
/// are both still images the gallery accepts, so either name is kept.
- (BOOL)fileName:(NSString *)name hasExtensionEquivalentTo:(NSString *)ext {
    NSString *current = name.pathExtension.lowercaseString;
    NSString *preferred = ext.lowercaseString;
    if (current.length == 0 || preferred.length == 0) {
        return NO;
    }
    if ([current isEqualToString:preferred]) {
        return YES;
    }
    NSArray<NSArray<NSString *> *> *groups = @[
        @[@"jpg", @"jpeg", @"jpe"],
        @[@"tif", @"tiff"],
        @[@"heic", @"heif"],
    ];
    for (NSArray<NSString *> *group in groups) {
        if ([group containsObject:current] && [group containsObject:preferred]) {
            return YES;
        }
    }
    return NO;
}

/// Append ext unless the name already ends with that type. Screenshot titles
/// contain dots ("14.41.08", "2.41.08 PM"); pathExtension is then "08" / "08 PM"
/// and must not be treated as a real extension. If the name already has a known
/// image extension that differs from the actual image container (e.g. a ".jpeg"
/// temp filename whose payload decoded as PNG), replace that extension.
- (NSString *)fileName:(NSString *)name ensuringExtension:(NSString *)ext {
    if (name.length == 0 || ext.length == 0) {
        return name;
    }
    if ([self fileName:name hasExtensionEquivalentTo:ext]) {
        return name;
    }
    NSString *currentExt = name.pathExtension;
    if (currentExt.length > 0) {
        UTType *currentType = [UTType typeWithFilenameExtension:currentExt];
        UTType *targetType = [UTType typeWithFilenameExtension:ext];
        if ([currentType conformsToType:UTTypeImage] && [targetType conformsToType:UTTypeImage]) {
            NSString *stripped = name.stringByDeletingPathExtension;
            if (stripped.length > 0) {
                name = stripped;
            }
        }
    }
    return [name stringByAppendingPathExtension:ext] ?: name;
}

- (NSString *)imageExtensionForFileURL:(NSURL *)url {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) {
        return nil;
    }
    NSString *ext = nil;
    CFStringRef uti = CGImageSourceGetType(source);
    if (uti) {
        ext = [UTType typeWithIdentifier:(__bridge NSString *)uti].preferredFilenameExtension;
    }
    CFRelease(source);
    return ext;
}

- (NSString *)imageExtensionForData:(NSData *)data {
    if (data.length == 0) {
        return nil;
    }
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) {
        return nil;
    }
    NSString *ext = nil;
    CFStringRef uti = CGImageSourceGetType(source);
    if (uti) {
        ext = [UTType typeWithIdentifier:(__bridge NSString *)uti].preferredFilenameExtension;
    }
    CFRelease(source);
    return ext;
}

- (NSData *)imageDataFromUIImage:(UIImage *)image {
    if (!image) {
        return nil;
    }
    @autoreleasepool {
        NSData *pngData = UIImagePNGRepresentation(image);
        if (pngData.length > 0) {
            return pngData;
        }
        return [self UIImageToDataJPEG:image];
    }
}

/// Maximum pixel dimension for in-memory preview thumbnails attached to SeafUploadFile.
/// Keeping fallback previews at thumbnail size prevents retaining full-resolution decoded
/// bitmaps (~46 MB per 12 MP photo) across multi-image share sessions.
static const CGFloat kMaxPreviewPixelSize = 160.0;

- (UIImage *)boundedPreviewImage:(UIImage *)image {
    if (!image) {
        return nil;
    }
    CGFloat scale = image.scale > 0 ? image.scale : 1.0;
    CGFloat pixelWidth = image.size.width * scale;
    CGFloat pixelHeight = image.size.height * scale;
    if (pixelWidth <= 0 || pixelHeight <= 0) {
        return nil;
    }
    CGFloat maxDimension = MAX(pixelWidth, pixelHeight);
    if (maxDimension <= kMaxPreviewPixelSize) {
        return image;
    }
    CGFloat ratio = kMaxPreviewPixelSize / maxDimension;
    CGSize targetPixelSize = CGSizeMake(MAX(1.0, floor(pixelWidth * ratio)),
                                        MAX(1.0, floor(pixelHeight * ratio)));
    @autoreleasepool {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1.0;
        format.opaque = NO;
        format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:targetPixelSize format:format];
        return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
            [image drawInRect:CGRectMake(0, 0, targetPixelSize.width, targetPixelSize.height)];
        }];
    }
}

/// Unwrap NSData that NSItemProvider serialized via NSKeyedArchiver.
/// When a host (such as the iOS screenshot markup preview) vends a UIImage or
/// NSData through UIActivityItemProvider, NSItemProvider's file and data
/// representations hand back the raw keyed-archive plist ("bplist00...") instead
/// of an image container. Decode it into real image/file bytes so the uploaded
/// file can be opened and previewed.
- (NSData *)normalizedDataFromItemData:(NSData *)data
                   decodedPreviewImage:(UIImage * _Nullable * _Nullable)outImage {
    if (data.length == 0) {
        return data;
    }
    if ([self imageExtensionForData:data].length > 0) {
        return data;
    }
    static const char kBplistMagic[] = "bplist00";
    if (data.length < sizeof(kBplistMagic) - 1 ||
        memcmp(data.bytes, kBplistMagic, sizeof(kBplistMagic) - 1) != 0) {
        return data;
    }
    NSData *unwrappedImageData = nil;
    UIImage *previewThumbnail = nil;
    @autoreleasepool {
        UIImage *archivedImage = [NSKeyedUnarchiver unarchivedObjectOfClass:[UIImage class]
                                                                   fromData:data
                                                                      error:nil];
        if (archivedImage) {
            unwrappedImageData = [self imageDataFromUIImage:archivedImage];
            if (outImage) {
                previewThumbnail = [self boundedPreviewImage:archivedImage];
            }
        }
    }
    if (outImage && previewThumbnail) {
        *outImage = previewThumbnail;
    }
    if (unwrappedImageData.length > 0) {
        return unwrappedImageData;
    }
    NSData *archivedData = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSData class]
                                                             fromData:data
                                                                error:nil];
    if (archivedData.length > 0) {
        return archivedData;
    }
    return data;
}

/// Maximum UTF-8 byte length for a single file name component on APFS/HFS+ (NAME_MAX = 255).
static const NSUInteger kMaxFileNameBytes = NAME_MAX;
static const NSUInteger kMaxFileExtensionBytes = 64;

- (NSString *)stringByReplacingInvalidFileNameCharacters:(NSString *)input {
    if (input.length == 0) {
        return @"";
    }
    NSMutableString *clean = [NSMutableString stringWithCapacity:input.length];
    [input enumerateSubstringsInRange:NSMakeRange(0, input.length)
                              options:NSStringEnumerationByComposedCharacterSequences
                           usingBlock:^(NSString *sub, NSRange subRange, NSRange enclosingRange, BOOL *stop) {
        if ([sub isEqualToString:@"/"]) {
            sub = @"_";
        } else if ([sub rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) {
            sub = @" ";
        }
        [clean appendString:sub];
    }];
    return clean;
}

- (NSString *)stringByTruncatingFileBaseName:(NSString *)base toMaxUTF8Bytes:(NSUInteger)maxBytes {
    if (base.length == 0 || [base lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= maxBytes) {
        return base;
    }
    NSMutableString *truncated = [NSMutableString stringWithCapacity:base.length];
    __block NSUInteger usedBytes = 0;
    [base enumerateSubstringsInRange:NSMakeRange(0, base.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *sub, NSRange subRange, NSRange enclosingRange, BOOL *stop) {
        NSUInteger subBytes = [sub lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (truncated.length > 0 && usedBytes + subBytes > maxBytes) {
            *stop = YES;
            return;
        }
        if (truncated.length == 0 && subBytes > maxBytes) {
            *stop = YES;
            return;
        }
        [truncated appendString:sub];
        usedBytes += subBytes;
    }];
    return [truncated stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/// Make a string usable as a single path component: no path separators or
/// control characters, and short enough for the file system. Shared text uses
/// its own content as the file name, which can contain "/" or run past NAME_MAX.
- (NSString *)sanitizedFileBaseName:(NSString *)base maxUTF8Bytes:(NSUInteger)maxBytes {
    NSString *clean = [self stringByReplacingInvalidFileNameCharacters:base];
    NSString *trimmed = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // A leading dot would hide the file; ".." is a directory reference.
    while ([trimmed hasPrefix:@"."]) {
        trimmed = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return [self stringByTruncatingFileBaseName:trimmed toMaxUTF8Bytes:maxBytes];
}

- (NSString *)sanitizedFileBaseName:(NSString *)base {
    return [self sanitizedFileBaseName:base maxUTF8Bytes:kMaxFileNameBytes];
}

/// Target URL in the temp dir, appending " (n)" when the name is already taken
/// (e.g. several shared photos exported with the same file name). Preserves valid
/// file names up to NAME_MAX (255 UTF-8 bytes) and only trims the base name when
/// the full name (including extension and any deduplication suffix) would exceed it.
- (NSURL *)uniqueTargetUrlForName:(NSString *)suggestedName {
    NSString *cleanSuggested = [self stringByReplacingInvalidFileNameCharacters:suggestedName ?: @""];
    NSString *rawExt = [cleanSuggested.pathExtension stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL hasValidExt = rawExt.length > 0
        && [rawExt lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= kMaxFileExtensionBytes
        && [rawExt rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]].location == NSNotFound;
    NSString *ext = hasValidExt ? rawExt : @"";
    NSString *rawBase = hasValidExt ? cleanSuggested.stringByDeletingPathExtension : cleanSuggested;

    NSUInteger extBytes = ext.length > 0 ? (1 + [ext lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) : 0;
    NSUInteger maxBaseBytes = (kMaxFileNameBytes > extBytes) ? (kMaxFileNameBytes - extBytes) : 1;

    NSString *base = [self sanitizedFileBaseName:rawBase maxUTF8Bytes:maxBaseBytes];
    if (base.length == 0) {
        base = @"file";
    }
    NSString *name = ext.length > 0 ? [base stringByAppendingPathExtension:ext] : base;
    if (name.length == 0) {
        name = base;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *candidate = [self.tmpdir stringByAppendingPathComponent:name];
    for (NSInteger i = 1; [fm fileExistsAtPath:candidate] && i < 1000; i++) {
        NSString *suffix = [NSString stringWithFormat:@" (%ld)", (long)i];
        NSUInteger suffixBytes = [suffix lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        NSUInteger reservedBytes = extBytes + suffixBytes;
        NSUInteger maxNumberedBaseBytes = (kMaxFileNameBytes > reservedBytes) ? (kMaxFileNameBytes - reservedBytes) : 1;
        NSString *numberedBase = [self stringByTruncatingFileBaseName:base toMaxUTF8Bytes:maxNumberedBaseBytes];
        if (numberedBase.length == 0) {
            numberedBase = @"file";
        }
        NSString *numbered = ext.length > 0
            ? [NSString stringWithFormat:@"%@%@.%@", numberedBase, suffix, ext]
            : [NSString stringWithFormat:@"%@%@", numberedBase, suffix];
        candidate = [self.tmpdir stringByAppendingPathComponent:numbered];
    }
    return [NSURL fileURLWithPath:candidate];
}

- (SeafUploadFile *)addUploadFileAtURL:(NSURL *)url lastModified:(NSDate *)modDate {
    SeafUploadFile *ufile = [[SeafUploadFile alloc] initWithPath:url.path];
    if (modDate) {
        ufile.lastModified = modDate;
    }
    [self.ufiles addObject:ufile];
    return ufile;
}

/// Infer a file extension for raw NSData from the image container header via
/// ImageIO first, then the explicit UTI or the provider's registered UTIs.
- (NSString *)preferredExtensionForData:(NSData *)data
                               provider:(NSItemProvider *)itemProvider
                         typeIdentifier:(NSString *)typeId
                            isImageData:(BOOL *)outIsImage {
    BOOL isImage = [self isStillImageProvider:itemProvider];
    NSString *ext = [self imageExtensionForData:data];
    if (ext.length > 0) {
        isImage = YES;
    }

    if (ext.length == 0 && typeId.length > 0) {
        UTType *type = [UTType typeWithIdentifier:typeId];
        if ([type conformsToType:UTTypeImage]) {
            isImage = YES;
        }
        if (type.preferredFilenameExtension.length > 0) {
            ext = type.preferredFilenameExtension;
        }
    }

    if (ext.length == 0) {
        for (NSString *regTypeId in itemProvider.registeredTypeIdentifiers) {
            UTType *regType = [UTType typeWithIdentifier:regTypeId];
            if (!regType) continue;
            if ([regType conformsToType:UTTypeImage]) {
                isImage = YES;
            }
            if (regType.preferredFilenameExtension.length > 0) {
                ext = regType.preferredFilenameExtension;
                break;
            }
        }
    }

    if (ext.length == 0 && isImage) {
        ext = @"jpg";
    }

    if (outIsImage) {
        *outIsImage = isImage;
    }
    return ext;
}

/// Build a unique target URL named "Screenshot_yyyy-MM-dd_HH-mm-ss.<ext>" for
/// in-memory UIImage / NSKeyedArchiver screenshot payloads, ignoring the host's
/// scraped UI label in suggestedName (e.g. random button/title text on screen).
- (NSURL *)screenshotTargetUrlForData:(NSData *)data
                             provider:(NSItemProvider *)itemProvider
                       typeIdentifier:(NSString *)typeId {
    BOOL isImage = YES;
    NSString *ext = [self preferredExtensionForData:data
                                           provider:itemProvider
                                     typeIdentifier:typeId
                                        isImageData:&isImage];
    NSString *name = [NSString stringWithFormat:@"Screenshot_%@", [self timestampString]];
    name = [self fileName:name ensuringExtension:ext];
    return [self uniqueTargetUrlForName:name];
}

/// Build a unique target URL in tmpdir for raw NSData, preserving suggestedName
/// (or fallbackName) when available and appending an inferred extension if needed.
- (NSURL *)targetUrlForData:(NSData *)data
                   provider:(NSItemProvider *)itemProvider
             typeIdentifier:(NSString *)typeId
               fallbackName:(NSString *)fallbackName {
    BOOL isImage = NO;
    NSString *ext = [self preferredExtensionForData:data
                                           provider:itemProvider
                                     typeIdentifier:typeId
                                        isImageData:&isImage];
    // Keep the provider's own file name (e.g. IMG_1234) when offered.
    NSString *name = itemProvider.suggestedName;
    if (name.length == 0) {
        name = fallbackName;
    }
    if (name.length == 0) {
        NSString *prefix = isImage ? @"Screenshot" : @"FILE";
        name = [NSString stringWithFormat:@"%@_%@", prefix, [self timestampString]];
    }
    name = [self fileName:name ensuringExtension:ext];
    return [self uniqueTargetUrlForName:name];
}

/// Normalize raw item data (unarchiving NSKeyedArchiver UIImage/NSData payloads if
/// needed), verify it is a readable image container, and write it with a preview.
- (BOOL)saveNormalizedImageData:(NSData *)rawData
                       provider:(NSItemProvider *)itemProvider
                 typeIdentifier:(NSString *)typeId
                   fallbackName:(NSString *)fallbackName
                        handler:(ItemLoadHandler)handler {
    if (rawData.length == 0) {
        return NO;
    }
    UIImage *decodedImage = nil;
    NSData *imageData = [self normalizedDataFromItemData:rawData decodedPreviewImage:&decodedImage];
    if ([self imageExtensionForData:imageData].length == 0) {
        return NO;
    }
    NSURL *targetUrl = decodedImage
        ? [self screenshotTargetUrlForData:imageData provider:itemProvider typeIdentifier:typeId]
        : [self targetUrlForData:imageData
                        provider:itemProvider
                  typeIdentifier:typeId
                    fallbackName:fallbackName];
    [self loadPreviewImageWith:itemProvider
                     writeData:imageData
                   toTargetUrl:targetUrl
               fallbackPreview:decodedImage
                       handler:handler];
    return YES;
}

- (void)loadMatchingItem:(id<NSSecureCoding, NSObject>)item provider:(NSItemProvider*)itemProvider handler:(ItemLoadHandler)handler {
    Debug("load Matching items");
    if ([item isKindOfClass:[UIImage class]]) {
        // Only reached when the provider vends no file/data representation.
        // Re-encoding drops EXIF; still images from Photos go through loadImageItem: instead.
        UIImage *image = (UIImage *)item;
        NSData *data = nil;
        UIImage *fallbackPreview = nil;
        @autoreleasepool {
            data = [self imageDataFromUIImage:image];
            fallbackPreview = [self boundedPreviewImage:image];
        }
        NSURL *targetUrl = [self screenshotTargetUrlForData:data
                                                   provider:itemProvider
                                             typeIdentifier:nil];
        [self loadPreviewImageWith:itemProvider
                         writeData:data
                       toTargetUrl:targetUrl
                   fallbackPreview:fallbackPreview
                           handler:handler];
    } else if ([item isKindOfClass:[NSData class]]) {
        NSData *rawData = (NSData *)item;
        if (![self saveNormalizedImageData:rawData
                                  provider:itemProvider
                            typeIdentifier:nil
                              fallbackName:nil
                                   handler:handler]) {
            [self handleFailure:handler];
        }
    } else if ([item isKindOfClass:[NSURL class]]) {
        NSURL *url = (NSURL *)item;
        NSDate *modDate = [self modificationDateOfURL:url];
        NSURL *targetUrl = [self uniqueTargetUrlForName:url.lastPathComponent];
        BOOL ret = [Utils copyFile:url to:targetUrl];
        if (ret) {
            [self addUploadFileAtURL:targetUrl lastModified:modDate];
            [self loadPreviewImageWith:itemProvider toTargetUrl:targetUrl lastModified:modDate handler:handler];
        } else {
            [self handleFailure:handler];
        }
    } else if ([item isKindOfClass:[NSString class]]) {
        NSString *string = (NSString *)item;
        if (string.length > 0) {
            NSString *name = [NSString stringWithFormat:@"%@.txt", item.description];
            NSURL *targetUrl = [self uniqueTargetUrlForName:name];
            NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
            [self writeData:data toTarget:targetUrl andPrivewImage:nil handler:handler];
        } else {
            [self handleFailure:handler];
        }
    } else {
        [self handleFailure:handler];
    }
}

- (void)loadPreviewImageWith:(NSItemProvider *)itemProvider
                   writeData:(NSData *)data
                 toTargetUrl:(NSURL *)targetUrl
             fallbackPreview:(UIImage *)fallbackPreview
                     handler:(ItemLoadHandler)handler {
    UIImage *boundedFallback = [self boundedPreviewImage:fallbackPreview];
    [itemProvider loadPreviewImageWithOptions:nil completionHandler:^(id<NSSecureCoding, NSObject>  _Nullable item, NSError * _Null_unspecified error) {
        @autoreleasepool {
            if (!error && item && [item isKindOfClass:[UIImage class]]) {
                [self writeData:data toTarget:targetUrl andPrivewImage:[self boundedPreviewImage:(UIImage *)item] handler:handler];
            } else {
                [self writeData:data toTarget:targetUrl andPrivewImage:boundedFallback handler:handler];
            }
        }
    }];
}

- (void)loadPreviewImageWith:(NSItemProvider *)itemProvider toTargetUrl:(NSURL *)targetUrl lastModified:(NSDate *)modDate handler:(ItemLoadHandler)handler {
    [itemProvider loadPreviewImageWithOptions:nil completionHandler:^(id<NSSecureCoding, NSObject>  _Nullable item, NSError * _Null_unspecified error) {
        @autoreleasepool {
            if (!error && item && [item isKindOfClass:[UIImage class]]) {
                [self handleFile:targetUrl andPriview:[self boundedPreviewImage:(UIImage *)item] lastModified:modDate handler:handler];
            } else {
                [self handleFile:targetUrl andPriview:nil lastModified:modDate handler:handler];
            }
        }
    }];
}

- (NSData *)UIImageToDataJPEG:(UIImage *)image {
    @autoreleasepool {
        NSData *data = UIImageJPEGRepresentation(image, 0.9f);
        return data;
    }
}

- (void)writeData:(NSData *)data toTarget:(NSURL *)targetUrl andPrivewImage:(UIImage *)preview handler:(ItemLoadHandler)handler {
    BOOL ret = [data writeToURL:targetUrl atomically:true];
    if (ret) {
        [self handleFile:targetUrl andPriview:preview lastModified:nil handler:handler];
    } else {
        [self handleFailure:handler];
    }
}

- (void)handleFile:(NSURL *)url andPriview:(UIImage *)preview lastModified:(NSDate *)modDate handler:(ItemLoadHandler)handler {
    Debug("Received file : %@", url);
    if (!url) {
        Warning("Failed to load file.");
        [self handleFailure:handler];
        return;
    }
    Debug("Upload file %@ %lld", url, [Utils fileSizeAtPath1:url.path]);
    SeafUploadFile *ufile;
    for (SeafUploadFile *file in self.ufiles) {
        if ([file.lpath isEqualToString:url.path]) {
            ufile = file;
            break;
        }
    }
    if (!ufile) {
        // Data written by writeData:toTarget: (UIImage / text / image data) has no
        // SeafUploadFile yet; without this the item silently never uploads.
        ufile = [self addUploadFileAtURL:url lastModified:modDate];
    }
    if (preview) {
        ufile.previewImage = [self boundedPreviewImage:preview];
    }
    if (handler) {
        handler(true);
    }
}

/// Handle failure for a single item - continues processing remaining items
- (void)handleFailure:(ItemLoadHandler)handler {
    Warning("Failed to process item");
    if (handler) {
        handler(false);
    }
    // Note: In serial mode, we don't call completeBlock here.
    // The processNextItem method will continue with the next item
    // and call completeBlock when all items are processed.
}

/// Handle failure with custom error message - continues processing remaining items
- (void)handleFailure:(ItemLoadHandler)handler withErrorDisplayMessage:(NSString *)errorMessage {
    Warning("Failed to process item: %@", errorMessage);
    if (errorMessage) {
        self.lastErrorMessage = errorMessage;
    }
    if (handler) {
        handler(false);
    }
    // Note: In serial mode, we don't call completeBlock here.
    // The processNextItem method will continue with the next item
    // and call completeBlock when all items are processed.
}

@end
