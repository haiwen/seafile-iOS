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

@property (nonatomic, strong) dispatch_group_t group;
@property (nonatomic, strong) NSMutableArray *ufiles;
@property (nonatomic, strong) CompleteBlock completeBlock;
@property (nonatomic, copy) NSString *tmpdir;

@end

@implementation SeafInputItemsProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        self.ufiles = [[NSMutableArray alloc] init];
        self.group = dispatch_group_create();
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
        provider.completeBlock(false, nil);
        return;
    }
    provider.tmpdir = tmpdir;
    
    for (NSExtensionItem *item in extensionContext.inputItems) {
        for (NSItemProvider *itemProvider in item.attachments) {
            dispatch_group_enter(provider.group);
            Debug("itemProvider: %@", itemProvider);
            if ([itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeItem] || [itemProvider hasItemConformingToTypeIdentifier:@"public.url"]) {
                //image or ics need to call with "public.url" as identifier
                NSString *typeIdentifier = (NSString *)kUTTypeItem;
                if ([itemProvider hasItemConformingToTypeIdentifier:@"public.url"]) {
                    typeIdentifier = @"public.url";
                }
                [itemProvider loadItemForTypeIdentifier:typeIdentifier options:nil completionHandler:^(id<NSSecureCoding, NSObject>  _Nullable item, NSError * _Null_unspecified error) {
                    if (!error) {
                        [provider loadMatchingItem:item provider:itemProvider handler:^(BOOL result) {
                            dispatch_group_leave(provider.group);
                        }];
                    } else {
                        [provider handleFailure:^(BOOL result) {
                            dispatch_group_leave(provider.group);
                        }];
                    }
                }];
            } else {
                [provider handleFailure:^(BOOL result) {
                    dispatch_group_leave(provider.group);
                }];
            }
        }
    };
    
    dispatch_group_notify(provider.group, dispatch_get_main_queue(), ^{
        provider.completeBlock(true, provider.ufiles);
    });
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
        NSData *data = (NSData *)item;
        NSString *name = item.description;
        NSURL *targetUrl = [NSURL fileURLWithPath:[self.tmpdir stringByAppendingPathComponent:name]];
        
        [self loadPreviewImageWith:itemProvider writeData:data toTargetUrl:targetUrl handler:handler];
    } else if ([item isKindOfClass:[NSURL class]]) {
        NSURL *url = (NSURL *)item;
        NSString *name = url.lastPathComponent;
        NSURL *targetUrl = [NSURL fileURLWithPath:[self.tmpdir stringByAppendingPathComponent:name]];
        BOOL ret = [Utils copyFile:url to:targetUrl];
        if (ret) {
            [self loadPreviewImageWith:itemProvider toTargetUrl:targetUrl handler:handler];
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

- (void)loadPreviewImageWith:(NSItemProvider *)itemProvider toTargetUrl:(NSURL *)targetUrl handler:(ItemLoadHandler)handler {
    [itemProvider loadPreviewImageWithOptions:nil completionHandler:^(id<NSSecureCoding, NSObject>  _Nullable item, NSError * _Null_unspecified error) {
        if (!error && item && [item isKindOfClass:[UIImage class]]) {
            [self handleFile:targetUrl andPriview:(UIImage*)item handler:handler];
        } else {
            [self handleFile:targetUrl andPriview:nil handler:handler];
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
        [self handleFile:targetUrl andPriview:preview handler:handler];
    } else {
        [self handleFailure:handler];
    }
}

- (void)handleFile:(NSURL *)url andPriview:(UIImage *)preview handler:(ItemLoadHandler)handler {
    Debug("Received file : %@", url);
    if (!url) {
        Warning("Failed to load file.");
        [self handleFailure:handler];
        return;
    }
    Debug("Upload file %@ %lld", url, [Utils fileSizeAtPath1:url.path]);
    SeafUploadFile *ufile = [[SeafUploadFile alloc] initWithPath:url.path];
    if (preview) {
        ufile.previewImage = preview;
    }
    [self.ufiles addObject:ufile];
    if (handler) {
        handler(true);
    }
}

- (void)handleFailure:(ItemLoadHandler)handler {
    if (handler) {
        handler(false);
    }
    self.completeBlock(false, nil);
}

@end
