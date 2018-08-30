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
    
    dispatch_queue_t queue = dispatch_queue_create("com.seafile.loadinputs", DISPATCH_QUEUE_CONCURRENT);
    
    NSString *tmpdir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.tempDir];
    if (![Utils checkMakeDir:tmpdir]) {
        Warning("Failed to create temp dir.");
        provider.completeBlock(false, nil);
        return;
    }
    
    for (NSExtensionItem *item in extensionContext.inputItems) {
        for (NSItemProvider *itemProvider in item.attachments) {
            dispatch_group_enter(provider.group);
            dispatch_barrier_async(queue, ^{
                Debug("itemProvider: %@", itemProvider);
                if ([itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeItem]) {
                    [itemProvider loadItemForTypeIdentifier:(NSString *)kUTTypeItem options:nil completionHandler:^(id<NSSecureCoding, NSObject>  _Nullable item, NSError * _Null_unspecified error) {
                        if (!error) {
                            if ([item isKindOfClass:[UIImage class]]) {
                                UIImage *image = (UIImage *)item;
                                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                                [formatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH'-'mm'-'ss"];
                                
                                NSString *name = [NSString stringWithFormat:@"IMG_%@.JPG", [formatter stringFromDate:[NSDate date]] ];
                                NSData *data = [provider UIImageToDataJPEG:image];
                                NSURL *targetUrl = [NSURL fileURLWithPath:[tmpdir stringByAppendingPathComponent:name]];
                                
                                [provider writeData:data toTarget:targetUrl];
                            } else if ([item isKindOfClass:[NSData class]]) {
                                NSData *data = (NSData *)item;
                                NSString *name = item.description;
                                NSURL *targetUrl = [NSURL fileURLWithPath:[tmpdir stringByAppendingPathComponent:name]];
                                
                                [provider writeData:data toTarget:targetUrl];
                            } else if ([item isKindOfClass:[NSURL class]]) {
                                NSURL *url = (NSURL *)item;
                                NSString *name = url.lastPathComponent;
                                NSURL *targetUrl = [NSURL fileURLWithPath:[tmpdir stringByAppendingPathComponent:name]];
                                BOOL ret = [Utils copyFile:url to:targetUrl];
                                if (ret) {
                                    [provider handleFile:targetUrl];
                                } else {
                                    [provider handleFailure];
                                }
                            } else if ([item isKindOfClass:[NSString class]]) {
                                NSString *string = (NSString *)item;
                                if (string.length > 0) {
                                    NSString *name = [NSString stringWithFormat:@"%@.txt", item.description];
                                    NSURL *targetUrl = [NSURL fileURLWithPath:[tmpdir stringByAppendingPathComponent:name]];
                                    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
                                    [provider writeData:data toTarget:targetUrl];
                                } else {
                                    [provider handleFailure];
                                }
                            } else {
                                [provider handleFailure];
                            }
                        } else {
                            [provider handleFailure];
                        }
                    }];
                } else {
                    [provider handleFailure];
                }
            });
        }
    }
    
    dispatch_group_notify(provider.group, dispatch_get_main_queue(), ^{
        provider.completeBlock(true, provider.ufiles);
    });
}

- (NSData *)UIImageToDataJPEG:(UIImage *)image {
    @autoreleasepool {
        NSData *data = UIImageJPEGRepresentation(image, 0.9f);
        return data;
    }
}

- (void)writeData:(NSData *)data toTarget:(NSURL *)targetUrl {
    BOOL ret = [data writeToURL:targetUrl atomically:true];
    if (ret) {
        [self handleFile:targetUrl];
    } else {
        [self handleFailure];
    }
}

- (void)handleFile:(NSURL *)url {
    Debug("Received file : %@", url);
    if (!url) {
        Warning("Failed to load file.");
        [self handleFailure];
        return;
    }
    Debug("Upload file %@ %lld", url, [Utils fileSizeAtPath1:url.path]);
    SeafUploadFile *ufile = [[SeafUploadFile alloc] initWithPath:url.path];
    dispatch_barrier_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.ufiles addObject:ufile];
    });
    dispatch_group_leave(self.group);
}

- (void)handleFailure {
    self.completeBlock(false, nil);
}

@end
