#import "SeafPreviewManager.h"
#import "SeafUploadFile.h"
#import "SeafUploadFileModel.h"
#import "Utils.h"
#import "FileMimeType.h"
#import "Debug.h"

@interface SeafPreviewManager ()
@property (nonatomic, strong) NSCache *imageCache;
@end

@implementation SeafPreviewManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _imageCache = [[NSCache alloc] init];
        _imageCache.countLimit = 100;
    }
    return self;
}

- (NSURL *)previewURLForFile:(SeafUploadFile *)file {
    if (!file.model.lpath) return nil;
    return [NSURL fileURLWithPath:file.model.lpath];
}

- (NSURL *)exportURLForFile:(SeafUploadFile *)file {
    if (!file.model.lpath) return nil;
    
    NSString *exportPath = [self exportPathForFile:file];
    if (!exportPath) return nil;
    
    NSError *error;
    [[NSFileManager defaultManager] copyItemAtPath:file.model.lpath 
                                          toPath:exportPath 
                                           error:&error];
    if (error) {
        Warning("Failed to copy file for export: %@", error);
        return nil;
    }
    
    return [NSURL fileURLWithPath:exportPath];
}

- (UIImage *)iconForFile:(SeafUploadFile *)file {
    NSString *mime = [FileMimeType mimeType:file.model.lpath];
    UIImage *icon = [self.imageCache objectForKey:mime];
    
    if (!icon) {
        icon = [self defaultIconForMimeType:mime];
        if (icon) {
            [self.imageCache setObject:icon forKey:mime];
        }
    }
    
    return icon;
}

- (UIImage *)thumbForFile:(SeafUploadFile *)file {
    if (![self isImageFile:file]) return nil;
    
    UIImage *thumb = [self.imageCache objectForKey:file.model.lpath];
    if (!thumb) {
        thumb = [self generateThumbForFile:file];
        if (thumb) {
            [self.imageCache setObject:thumb forKey:file.model.lpath];
        }
    }
    
    return thumb;
}

- (void)getImageWithFile:(SeafUploadFile *)file completion:(void (^)(UIImage *image))completion {
    if (![self isImageFile:file]) {
        if (completion) completion(nil);
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *image = [UIImage imageWithContentsOfFile:file.model.lpath];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(image);
        });
    });
}

#pragma mark - Helper Methods

- (NSString *)exportPathForFile:(SeafUploadFile *)file {
    NSString *exportDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"SeafExport"];
    if (![Utils checkMakeDir:exportDir]) return nil;
    
    return [exportDir stringByAppendingPathComponent:file.model.lpath.lastPathComponent];
}

- (BOOL)isImageFile:(SeafUploadFile *)file {
    NSString *mime = [FileMimeType mimeType:file.model.lpath];
    return [mime hasPrefix:@"image/"];
}

- (UIImage *)generateThumbForFile:(SeafUploadFile *)file {
    UIImage *image = [UIImage imageWithContentsOfFile:file.model.lpath];
    if (!image) return nil;
    
    CGSize size = CGSizeMake(120, 120);
    UIGraphicsBeginImageContextWithOptions(size, NO, [UIScreen mainScreen].scale);
    
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *thumb = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    return thumb;
}

- (UIImage *)defaultIconForMimeType:(NSString *)mime {
    if ([mime hasPrefix:@"image/"]) {
        return [UIImage imageNamed:@"file_image"];
    } else if ([mime hasPrefix:@"video/"]) {
        return [UIImage imageNamed:@"file_video"];
    } else if ([mime hasPrefix:@"audio/"]) {
        return [UIImage imageNamed:@"file_audio"];
    } else if ([mime hasPrefix:@"text/"]) {
        return [UIImage imageNamed:@"file_text"];
    } else if ([mime hasPrefix:@"application/pdf"]) {
        return [UIImage imageNamed:@"file_pdf"];
    }
    return [UIImage imageNamed:@"file_unknown"];
}

@end 