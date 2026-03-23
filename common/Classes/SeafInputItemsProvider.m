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
#import <MobileCoreServices/UTCoreTypes.h>
#import "SeafUploadFile.h"

@interface SeafInputItemsProvider()

@property (nonatomic, strong) NSMutableArray *ufiles;
@property (nonatomic, strong) CompleteBlock completeBlock;
@property (nonatomic, copy) NSString *tmpdir;
@property (nonatomic, strong) NSArray *pendingProviders;  // All item providers to process
@property (nonatomic, assign) NSInteger currentIndex;      // Current processing index

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
                self.completeBlock(false, nil, @"Failed to load file");
            }
        });
        return;
    }
    
    NSItemProvider *itemProvider = self.pendingProviders[self.currentIndex];
    Debug("Processing item %ld/%lu: %@", (long)(self.currentIndex + 1), (unsigned long)self.pendingProviders.count, itemProvider);
    
    if ([itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeItem] || 
        [itemProvider hasItemConformingToTypeIdentifier:@"public.url"]) {
        
        // Image or ics need to call with "public.url" as identifier
        NSString *typeIdentifier = (NSString *)kUTTypeItem;
        if ([itemProvider hasItemConformingToTypeIdentifier:@"public.url"]) {
            typeIdentifier = @"public.url";
        }
        
        [itemProvider loadItemForTypeIdentifier:typeIdentifier 
                                        options:nil 
                              completionHandler:^(id<NSSecureCoding, NSObject> _Nullable item, NSError * _Null_unspecified error) {
            @autoreleasepool {
                if (!error) {
                    [self loadMatchingItem:item provider:itemProvider handler:^(BOOL result) {
                        // Process next item regardless of result
                        self.currentIndex++;
                        // Use dispatch_async to avoid stack overflow with many items
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                            [self processNextItem];
                        });
                    }];
                } else {
                    Warning("Failed to load item at index %ld: %@", (long)self.currentIndex, error);
                    // Continue processing next item even if this one failed
                    self.currentIndex++;
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        [self processNextItem];
                    });
                }
            }
        }];
    } else {
        Warning("Unsupported item type at index %ld", (long)self.currentIndex);
        // Skip unsupported item and continue
        self.currentIndex++;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self processNextItem];
        });
    }
}

- (void)loadMatchingItem:(id<NSSecureCoding, NSObject>)item provider:(NSItemProvider*)itemProvider handler:(ItemLoadHandler)handler {
    Debug("load Matching items");
    if ([item isKindOfClass:[UIImage class]]) {
        UIImage *image = (UIImage *)item;
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH'-'mm'-'ss"];
        
        NSString *name = [NSString stringWithFormat:@"IMG_%@.JPG", [formatter stringFromDate:[NSDate date]] ];
        NSData *data = [self UIImageToDataJPEG:image];
        NSURL *targetUrl = [NSURL fileURLWithPath:[self.tmpdir stringByAppendingPathComponent:name]];
        
        [self loadPreviewImageWith:itemProvider writeData:data toTargetUrl:targetUrl handler:handler];
    } else if ([item isKindOfClass:[NSData class]]) {
        [self handleFailure:handler withErrorDisplayMessage:@"Sharing of NSData format is not supported."];
    } else if ([item isKindOfClass:[NSURL class]]) {
        NSURL *url = (NSURL *)item;
        // Get file modificationDate or creationDate
        NSDate *modificationDate = nil;
        [url getResourceValue:&modificationDate forKey:NSURLContentModificationDateKey error:nil];

        NSDate *creationDate = nil;
        [url getResourceValue:&creationDate forKey:NSURLCreationDateKey error:nil];
        NSDate *modDate = modificationDate ?: creationDate;
        NSString *name = url.lastPathComponent;
        NSURL *targetUrl = [NSURL fileURLWithPath:[self.tmpdir stringByAppendingPathComponent:name]];
        BOOL ret = [Utils copyFile:url to:targetUrl];
        if (ret) {
            SeafUploadFile *ufile = [[SeafUploadFile alloc] initWithPath:targetUrl.path];
            if (modDate) {
                ufile.lastModified = modDate;
            }
            [self.ufiles addObject:ufile];
            [self loadPreviewImageWith:itemProvider toTargetUrl:targetUrl lastModified:modDate handler:handler];
        } else {
            [self handleFailure:handler];
        }
    } else if ([item isKindOfClass:[NSString class]]) {
        NSString *string = (NSString *)item;
        if (string.length > 0) {
            NSString *name = [NSString stringWithFormat:@"%@.txt", item.description];
            NSURL *targetUrl = [NSURL fileURLWithPath:[self.tmpdir stringByAppendingPathComponent:name]];
            NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
            [self writeData:data toTarget:targetUrl andPrivewImage:nil handler:handler];
        } else {
            [self handleFailure:handler];
        }
    } else {
        [self handleFailure:handler];
    }
}

- (void)loadPreviewImageWith:(NSItemProvider *)itemProvider writeData:(NSData *)data toTargetUrl:(NSURL *)targetUrl handler:(ItemLoadHandler)handler {
    [itemProvider loadPreviewImageWithOptions:nil completionHandler:^(id<NSSecureCoding, NSObject>  _Nullable item, NSError * _Null_unspecified error) {
        if (!error && item && [item isKindOfClass:[UIImage class]]) {
            [self writeData:data toTarget:targetUrl andPrivewImage:(UIImage*)item handler:handler];
        } else {
            [self writeData:data toTarget:targetUrl andPrivewImage:nil handler:handler];
        }
    }];
}

- (void)loadPreviewImageWith:(NSItemProvider *)itemProvider toTargetUrl:(NSURL *)targetUrl lastModified:(NSDate *)modDate handler:(ItemLoadHandler)handler {
    [itemProvider loadPreviewImageWithOptions:nil completionHandler:^(id<NSSecureCoding, NSObject>  _Nullable item, NSError * _Null_unspecified error) {
        if (!error && item && [item isKindOfClass:[UIImage class]]) {
            [self handleFile:targetUrl andPriview:(UIImage*)item lastModified:modDate handler:handler];
        } else {
            [self handleFile:targetUrl andPriview:nil lastModified:modDate handler:handler];
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
    if (preview) {
        ufile.previewImage = preview;
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
    if (handler) {
        handler(false);
    }
    // Note: In serial mode, we don't call completeBlock here.
    // The processNextItem method will continue with the next item
    // and call completeBlock when all items are processed.
}

@end
