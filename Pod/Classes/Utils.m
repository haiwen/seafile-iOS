//
//  Utils.m
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//


#include <ImageIO/ImageIO.h>

#import "Utils.h"
#import "Debug.h"
#import "ExtentedString.h"
#import "SeafConstants.h"
#import <sys/stat.h>
#import <dirent.h>
#import <sys/xattr.h>
#import <Photos/Photos.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <UniversalDetector/UniversalDetector.h>
@implementation Utils


+ (BOOL)addSkipBackupAttributeToItemAtPath:(NSString *)path
{
    NSURL *url = [NSURL fileURLWithPath:path];
    NSError *error = nil;
    [url setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsExcludedFromBackupKey error:&error];
    return error == nil;
}

+ (BOOL)checkMakeDir:(NSString *)path
{
    NSError *error;
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
        //Does directory already exist?
        if (!isDirectory) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
        }
        if (![[NSFileManager defaultManager] createDirectoryAtPath:path
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error]) {
            Warning("Failed to create directory %@:%@\n", path, error);
            return NO;
        }
    }
    [Utils addSkipBackupAttributeToItemAtPath:path];
    return YES;
}

+ (void)clearAllFiles:(NSString *)path
{
    NSError *error;
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
    if (!dirContents) {
        Warning("unable to get the contents of directory: %@, error: %@", path, error);
        return;
    }

    for (NSString *entry in dirContents) {
        [[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingPathComponent:entry] error:nil];
    }
}

+ (BOOL)removeFile:(NSString *)path
{
    NSError *error = nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        return true;
    BOOL ret = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    if (!ret)
        Warning("Failed to remove file %@: %@", path, error);
    return ret;
}

+ (void)removeDirIfEmpty:(NSString *)path
{
    NSError *error;
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
    if (!dirContents) {
        Warning("unable to get the contents of directory: %@, error: %@", path, error);
        return;
    }
    if (dirContents.count == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

+ (BOOL)copyFile:(NSURL *)from to:(NSURL *)to
{
    NSError *error = nil;
    NSFileManager* fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:to.path]
        || ![[NSFileManager defaultManager] copyItemAtURL:from toURL:to error:&error]) {
        Warning("Failed to copy file from %@ to %@: %@\n", from, to, error);
        return false;
    }
    return true;
}

+ (BOOL)linkFileAtURL:(NSURL *)from to:(NSURL *)to error:(NSError **)error
{
    return [Utils linkFileAtPath:from.path to:to.path error:error];
}

+ (BOOL)linkFileAtPath:(NSString *)from to:(NSString *)to error:(NSError **)error
{
    if (!from || !to || [Utils fileExistsAtPath:to]) return false;
    NSError *err = nil;
    NSFileManager* fm = [NSFileManager defaultManager];
    // file import from Files.app,sometime file size is 0
    if ([fm fileExistsAtPath:to]
        || ![[NSFileManager defaultManager] linkItemAtPath:from toPath:to error:&err]) {
        Warning("Failed to link file from %@ to %@: %@\n", from, to, err);
        if (error) *error = err;
        return false;
    }
    return true;
}

+ (long long)fileSizeAtPath1:(NSString*)filePath
{
    NSFileManager* manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:filePath]){
        NSError *error = nil;
        long long ans = [[manager attributesOfItemAtPath:filePath error:&error] fileSize];
        if (error) {
            Warning("Failed to get file %@ size: %@", filePath, error);
        }
        return ans;
    } else {
        Warning("File %@ does not exist", filePath);
    }
    return 0;
}

+ (long long)fileSizeAtPath2:(NSString*)filePath
{
    struct stat st;
    if(lstat([filePath cStringUsingEncoding:NSUTF8StringEncoding], &st) == 0){
        return st.st_size;
    }
    return 0;
}

+ (long long)folderSizeAtPath1:(NSString*)folderPath
{
    NSFileManager* manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:folderPath]) return 0;
    NSEnumerator *childFilesEnumerator = [[manager subpathsAtPath:folderPath] objectEnumerator];
    NSString* fileName;
    long long folderSize = 0;
    while ((fileName = [childFilesEnumerator nextObject]) != nil){
        NSString* fileAbsolutePath = [folderPath stringByAppendingPathComponent:fileName];
        folderSize += [self fileSizeAtPath1:fileAbsolutePath];
    }
    return folderSize;
}

+ (long long)folderSizeAtPath2:(NSString*)folderPath
{
    NSFileManager* manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:folderPath]) return 0;
    NSEnumerator *childFilesEnumerator = [[manager subpathsAtPath:folderPath] objectEnumerator];
    NSString* fileName;
    long long folderSize = 0;
    while ((fileName = [childFilesEnumerator nextObject]) != nil){
        NSString* fileAbsolutePath = [folderPath stringByAppendingPathComponent:fileName];
        folderSize += [self fileSizeAtPath2:fileAbsolutePath];
    }
    return folderSize;
}

+ (long long)_folderSizeAtPath:(const char*)folderPath
{
    long long folderSize = 0;
    DIR* dir = opendir(folderPath);
    if (dir == NULL) return 0;
    struct dirent* child;
    while ((child = readdir(dir))!=NULL) {
        if (child->d_type == DT_DIR && (
                                        (child->d_name[0] == '.' && child->d_name[1] == 0) ||
                                        (child->d_name[0] == '.' && child->d_name[1] == '.' && child->d_name[2] == 0)
                                        )) continue;

        long folderPathLength = strlen(folderPath);
        char childPath[1024];
        stpcpy(childPath, folderPath);
        if (folderPath[folderPathLength-1] != '/'){
            childPath[folderPathLength] = '/';
            folderPathLength++;
        }
        stpcpy(childPath+folderPathLength, child->d_name);
        childPath[folderPathLength + child->d_namlen] = 0;
        if (child->d_type == DT_DIR){
            folderSize += [self _folderSizeAtPath:childPath];
            struct stat st;
            if(lstat(childPath, &st) == 0) folderSize += st.st_size;
        }else if (child->d_type == DT_REG || child->d_type == DT_LNK){ // file or link
            struct stat st;
            if(lstat(childPath, &st) == 0) folderSize += st.st_size;
        }
    }
    return folderSize;
}

+ (long long)folderSizeAtPath:(NSString*)folderPath
{
    return [self folderSizeAtPath1:folderPath];
}

+ (id)JSONDecode:(NSData *)data error:(NSError **)error
{
    NSString *rawData = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if ([rawData hasPrefix:@"\""] && [rawData hasSuffix:@"\""]) {
        return [rawData substringWithRange:NSMakeRange(1, [rawData length] - 2)];
    }
    id ret = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (*error)
        Warning("Parse json error:%@, %@\n", *error, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    return ret;
}

+ (NSData *)JSONEncode:(id)obj
{
    if (!obj)
        return nil;
    if ([obj isKindOfClass:[NSString class]]) {
        return [(NSString *)obj dataUsingEncoding:NSUTF8StringEncoding];
    }
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj
                                                       options:(NSJSONWritingOptions)0
                                                         error:&error];
    if (!jsonData) {
        Warning("Failed to encode Dictionary, error: %@", error.localizedDescription);
    }
    return jsonData;
}

+ (NSString *)JSONEncodeDictionary:(NSDictionary *)dict
{
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict
                                                       options:(NSJSONWritingOptions)0
                                                         error:&error];
    if (!jsonData) {
        Warning("Failed to encode Dictionary, error: %@", error.localizedDescription);
        return @"{}";
    } else {
        return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
}

+ (BOOL)tryTransformEncoding:(NSString *)outfile fromFile:(NSString *)fromfile
{
    NSString *content = [Utils stringContent:fromfile];
    if (!content) return NO;
    [content writeToFile:outfile atomically:YES encoding:NSUTF16StringEncoding error:nil];
    return YES;
}

+ (NSString *)stringContent:(NSString *)path
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || data.length > 10 * 1024 * 1024) return nil;

    CFStringEncoding enc = [UniversalDetector encodingWithData:data];
    if (enc == kCFStringEncodingInvalidId) return nil;

    NSStringEncoding nsEnc = CFStringConvertEncodingToNSStringEncoding(enc);
    return [[NSString alloc] initWithData:data encoding:nsEnc];
}

+ (BOOL)isImageFile:(NSString *)name
{
    static NSString *imgexts[] = {@"tif", @"tiff", @"jpg", @"jpeg", @"gif", @"png", @"bmp", @"ico", @"heic",nil};
    NSString *ext = name.pathExtension.lowercaseString;
    return [Utils isExt:ext In:imgexts];
}

+ (BOOL)isVideoFile:(NSString *)name
{
    return [Utils isVideoExt:name.pathExtension.lowercaseString];
}

+ (BOOL)isVideoExt:(NSString *)ext
{
    static NSString *videoexts[] = {@"mp4", @"mov", @"m4v", nil};
    return [Utils isExt:ext In:videoexts];
}


+ (BOOL)isExt:(NSString *)ext In:(__strong NSString *[])exts
{
    if (!ext || ext.length == 0)
        return false;

    for (int i = 0; exts[i]; ++i) {
        if ([exts[i] isEqualToString:ext])
            return true;
    }
    return false;
}

+ (BOOL)writeDataWithMeta:(NSData *)imageData toPath:(NSString*)filePath {
    NSDictionary *options = @{(id)kCGImageSourceShouldCache : @(false)};
    // create an imagesourceref
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef) imageData, (__bridge CFDictionaryRef)options);
    
    // this is the type of image (e.g., public.jpeg)
    CFStringRef UTI = CGImageSourceGetType(source);
    
    // create a new data object and write the new image into it
    NSURL *url = [[NSURL alloc] initFileURLWithPath:filePath];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((CFURLRef)url, UTI, 1, NULL);
    if (!destination) {
        Debug(@"Error: Could not create image destination");
        CFRelease(source);
        CFRelease(UTI);
        return false;
    }
    
    CFDictionaryRef imageProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    if (imageProperties) {
        //add the image contained in the image source to the destination, overidding the old metadata with our modified metadata
        CGImageDestinationAddImageFromSource(destination, source, 0, imageProperties);
        CFRelease(imageProperties);
    }
    
    BOOL success = NO;
    success = CGImageDestinationFinalize(destination);
    if (!success) {
        Debug(@"Error: Could not create data from image destination");
    }
    CFRelease(destination);
    CFRelease(source);
    CFRelease(UTI);
    return success;
}

+ (BOOL)writeCIImage:(CIImage *)ciImage toPath:(NSString*)filePath {
    NSError *error = nil;
    CIContext *context = [[CIContext alloc] init];
    NSURL *url = [[NSURL alloc] initFileURLWithPath:filePath isDirectory:NO];
    return [context writeJPEGRepresentationOfImage:ciImage toURL:url colorSpace:ciImage.colorSpace options:@{(CIImageRepresentationOption)kCGImageDestinationLossyCompressionQuality : @(0.8)} error:&error];
}

+ (BOOL)fileExistsAtPath:(NSString *)path
{
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (CGSize)textSizeForText:(NSString *)txt font:(UIFont *)font width:(float)width
{
    CGFloat maxWidth = width;
    CGFloat maxHeight = 1000;

    CGRect stringRect = [txt boundingRectWithSize:CGSizeMake(maxWidth, maxHeight)
                                          options:NSStringDrawingUsesLineFragmentOrigin
                                       attributes:@{ NSFontAttributeName : font }
                                          context:nil];

    CGSize stringSize = CGRectIntegral(stringRect).size;

    return CGSizeMake(roundf(stringSize.width), roundf(stringSize.height));
}

+ (void)alertWithTitle:(NSString *)title message:(NSString*)message yes:(void (^)(void))yes no:(void (^)(void))no from:(UIViewController *)c
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *yesAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"YES", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (yes) yes();
    }];
    UIAlertAction *noAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"NO", @"Seafile") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        if (no) no();
    }];

    [alert addAction:noAction];
    [alert addAction:yesAction];
    dispatch_async(dispatch_get_main_queue(), ^{
        [c presentViewController:alert animated:true completion:nil];
    });
}

+ (void)alertWithTitle:(NSString *)title message:(NSString*)message handler:(void (^)(void))handler from:(UIViewController *)c
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        if (handler)
            handler();
    }];
    [alert addAction:okAction];
    dispatch_async(dispatch_get_main_queue(), ^{
        [c presentViewController:alert animated:true completion:nil];
    });
}

+ (void)popupInputView:(NSString *)title placeholder:(NSString *)tip inputs:(NSString *)inputs secure:(BOOL)secure handler:(void (^)(NSString *input))handler from:(UIViewController *)c
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:STR_CANCEL style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    }];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *input = [[alert.textFields objectAtIndex:0] text];
        if (handler)
            handler(input);
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = tip;
        if (inputs) {
            textField.text = inputs;
        }
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.secureTextEntry = secure;

    }];
    [alert addAction:cancelAction];
    [alert addAction:okAction];

    dispatch_async(dispatch_get_main_queue(), ^{
        [c presentViewController:alert animated:true completion:nil];
    });
}

+ (UIAlertController *)generateAlert:(NSArray *)arr withTitle:(NSString *)title handler:(void (^ __nullable)(UIAlertAction *action))handler cancelHandler:(void (^ __nullable)(UIAlertAction *action))cancelHandler preferredStyle:(UIAlertControllerStyle)preferredStyle
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:preferredStyle];
    for (NSString *name in arr) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:handler];
        [alert addAction:action];
    }
    if (!IsIpad() || cancelHandler){
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:STR_CANCEL style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            if (cancelHandler) cancelHandler(action);
        }];
        [alert addAction:cancelAction];
    }
    return alert;
}

+ (UIImage *)reSizeImage:(UIImage *)image toSquare:(float)length
{
    @autoreleasepool {
        NSData *imgData = UIImageJPEGRepresentation(image, 1);
        CGImageSourceRef imageSource = CGImageSourceCreateWithData((CFDataRef)imgData, NULL);
        if (!imageSource)
            return nil;

        CFDictionaryRef options = (__bridge CFDictionaryRef)[NSDictionary dictionaryWithObjectsAndKeys:
                                                     (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailWithTransform,
                                                     (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailFromImageIfAbsent,
                                                    (id)[NSNumber numberWithFloat:length], (id)kCGImageSourceThumbnailMaxPixelSize,
                                                     nil];
        CGImageRef imgRef = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options);

        UIImage *reSizeImage = [UIImage imageWithCGImage:imgRef];
         
        CGImageRelease(imgRef);
        CFRelease(imageSource);
        return reSizeImage;
    }
}

+ (NSDictionary *)queryToDict:(NSString *)query
{
    NSArray *components = [query componentsSeparatedByString:@"&"];
    NSMutableDictionary *parameters = [[NSMutableDictionary alloc] init];
    for (NSString *component in components) {
        NSArray *subcomponents = [component componentsSeparatedByString:@"="];
        [parameters setObject:[[subcomponents objectAtIndex:1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]
                       forKey:[[subcomponents objectAtIndex:0] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    }
    return parameters;
}

+ (void)dict:(NSMutableDictionary *)dict setObject:(id)value forKey:(NSString *)defaultName
{
    if (!defaultName || !dict)
        return;
    @synchronized(dict) {
        if (!value)
            [dict removeObjectForKey:defaultName];
        else
            [dict setObject:value forKey:defaultName];
    }
}

+ (void)imageFromPath:(NSString *)path withMaxSize:(float)length cachePath:(NSString *)cachePath completion:(void (^)(UIImage *image))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *image = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
            // Load image from cache if it exists
            image = [UIImage imageWithContentsOfFile:cachePath];
            completion(image);
            return;
        }

        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            NSData *data = [NSData dataWithContentsOfFile:path];
            // Use Image I/O framework to decode the image
            CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, NULL);
            if (source) {
                CGSize maxSize = CGSizeMake(length, length);
                NSDictionary *thumbnailOptions = @{
                    (NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                    (NSString *)kCGImageSourceThumbnailMaxPixelSize: @(MAX(maxSize.width, maxSize.height)),
                    (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES
                };
                // Create a thumbnail of the image with the given options
                CGImageRef cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, (CFDictionaryRef)thumbnailOptions);
                if (cgImage) {
                    image = [UIImage imageWithCGImage:cgImage];
                    CGImageRelease(cgImage);
                }
                CFRelease(source);
            }
            
            // Decode the image
            image = [Utils decodedImageWithImage:image];

            // Save the processed image to the cache path
            if (image) {
                NSData *imageData = UIImageJPEGRepresentation(image, 1.0);
                [imageData writeToFile:cachePath atomically:YES];
            }
            completion(image);
        } else {
            // If neither cache nor original image exists, return nil
            completion(nil);
        }
    });
}

+ (UIImage *)imageFromPath:(NSString *)path withMaxSize:(float)length cachePath:(NSString *)cachePath {
    const int MAX_SIZE = length;
    if ([[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
        return [UIImage imageWithContentsOfFile:cachePath];
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        NSString *imageUTType = (__bridge NSString *)CGImageGetUTType(image.CGImage);
        if ([imageUTType isEqualToString:@"public.heic"]) {
            NSData *imageData = [NSData dataWithContentsOfFile:path];
            [imageData writeToFile:cachePath atomically:YES];
            return image;
        }
        UIImage *resizedImage = image;
        if (image.size.width > MAX_SIZE || image.size.height > MAX_SIZE) {
            resizedImage = [Utils reSizeImage:image toSquare:MAX_SIZE];
        }
        UIImage *decodedImage = [Utils decodedImageWithImage:resizedImage];

        // Save the decoded image to cache asynchronously
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            NSData *imageData = UIImageJPEGRepresentation(decodedImage, 1.0);
            [imageData writeToFile:cachePath atomically:YES];
        });

        return decodedImage;
    }
    return nil;
}

+ (UIImage *)decodedImageWithImage:(UIImage *)image {
    if (!image) {
        return nil;
    }
    CGImageRef imageRef = image.CGImage;
    CGSize size = CGSizeMake(CGImageGetWidth(imageRef), CGImageGetHeight(imageRef));

    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 size.width,
                                                 size.height,
                                                 CGImageGetBitsPerComponent(imageRef),
                                                 0,
                                                 CGImageGetColorSpace(imageRef),
                                                 CGImageGetBitmapInfo(imageRef));
    if (!context) {
        return image;
    }

    CGContextDrawImage(context, CGRectMake(0, 0, size.width, size.height), imageRef);
    CGImageRef decompressedImageRef = CGBitmapContextCreateImage(context);
    UIImage *decompressedImage = [UIImage imageWithCGImage:decompressedImageRef];

    CGContextRelease(context);
    CGImageRelease(decompressedImageRef);

    return decompressedImage;
}

+ (NSString *)encodePath:(NSString *)server username:(NSString *)username repo:(NSString *)repoId path:(NSString *)path
{
    NSMutableCharacterSet *allowedSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLKMNOPQRSTUVWXYZ0123456789"];
    [allowedSet addCharactersInString:@"@.- "];
    NSMutableString *ms = [NSMutableString new];
    if (server) {
        [ms appendFormat:@"%@_%@", [server stringByAddingPercentEncodingWithAllowedCharacters:allowedSet], [username stringByAddingPercentEncodingWithAllowedCharacters:allowedSet]];
    }
    if (repoId) {
        [ms appendFormat:@"_%@", [repoId stringByAddingPercentEncodingWithAllowedCharacters:allowedSet]];
    }
    if (path) {
        [ms appendFormat:@"_%@", [path stringByAddingPercentEncodingWithAllowedCharacters:allowedSet]];
    }

    return ms;
}


+ (void)decodePath:(NSString *)encodedStr server:(NSString **)server username:(NSString **)username repo:(NSString **)repoId path:(NSString **)path
{
    NSArray *arr = [encodedStr componentsSeparatedByString:@"_"];
    *server = nil;
    *username = nil;
    *repoId = nil;
    *path = nil;

    if (arr.count >= 2) {
        *server = [[arr objectAtIndex:0] stringByRemovingPercentEncoding];
        *username = [[arr objectAtIndex:1] stringByRemovingPercentEncoding];
    }
    if (arr.count >= 3) {
        *repoId = [[arr objectAtIndex:2] stringByRemovingPercentEncoding];
    }
    if (arr.count >= 4) {
        *path = [[arr objectAtIndex:3] stringByRemovingPercentEncoding];
    }
}

+ (NSError *)defaultError
{
    NSDictionary *userInfo = @{
                               NSLocalizedDescriptionKey: NSLocalizedString(@"Operation was unsuccessful.", nil),
                               NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"The operation failed.", nil),
                               };
    NSError *error = [NSError errorWithDomain:@"Seafile" code:-1 userInfo:userInfo];
    return error;
}

+ (NSString *)convertToALAssetUrl:(NSString *)fileURL andIdentifier:(NSString *)identifier {
    NSString *name = [identifier componentsSeparatedByString:@"/"].firstObject;
    NSString *ext = fileURL.pathExtension.uppercaseString;
    
    if (name && ext) {
        return [NSString stringWithFormat:@"assets-library://asset/asset.%@?id=%@&ext=%@", ext, name, ext];
    } else {
        return nil;
    }
}

+ (NSURL *)generateFileTempPath:(NSString *)name {
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[name stringByAddingPercentEscapesUsingEncoding:NSUTF16StringEncoding]];
    NSURL *tempURL = [NSURL fileURLWithPath:tempPath isDirectory:NO];
    if ([[NSFileManager defaultManager] fileExistsAtPath:tempPath]) {
        NSError *error;
        [[NSFileManager defaultManager] removeItemAtPath:tempPath error:&error];
        if (error) {
            Warning("Failed to generate temp url, error: %@", error);
        }
    }
    return tempURL;
}

+ (NSString *)currentBundleIdentifier {
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
}

+ (NSString *)creatNewFileName:(NSString *)fileName {
    NSString *name = fileName.stringByDeletingPathExtension;
    NSString *ext = fileName.pathExtension;
    
    if (name.length<3) {
        if (ext.length == 0) {
            fileName = [NSString stringWithFormat:@"%@(1)", name];
        } else {
            fileName = [NSString stringWithFormat:@"%@(1).%@", name, ext];
        }
    } else {
        NSInteger len = name.length;
        NSString *numStr = [name substringWithRange:NSMakeRange(len-2, 1)];
        NSInteger num = [numStr integerValue];
        NSString *par = [name substringWithRange:NSMakeRange(len-3, 1)];
        if ([par isEqualToString:@"("] && num > 0) {
            num+=1;
            name = [name substringToIndex:len-3];
            if (ext.length == 0) {
                fileName = [NSString stringWithFormat:@"%@(%ld)", name, (long)num];
            } else {
                fileName = [NSString stringWithFormat:@"%@(%ld).%@", name, (long)num,ext];
            }
        } else {
            if (ext.length == 0) {
                fileName = [NSString stringWithFormat:@"%@(1)", name];
            } else {
                fileName = [NSString stringWithFormat:@"%@(1).%@", name, ext];
            }
        }
    }
    return fileName;
}

+ (BOOL)needsUpdateCurrentVersion:(NSString *)currentVersion newVersion:(NSString *)newVersion {
    NSArray *currentVersionComponents = [currentVersion componentsSeparatedByString:@"."];
    NSArray *newVersionComponents = [newVersion componentsSeparatedByString:@"."];
    
    // Calculate the minimum count of components to compare
    NSUInteger count = MIN([currentVersionComponents count], [newVersionComponents count]);
    
    for (NSUInteger i = 0; i < count; i++) {
        NSInteger currentVersionNumber = [currentVersionComponents[i] integerValue];
        NSInteger newVersionNumber = [newVersionComponents[i] integerValue];
        
        if (newVersionNumber > currentVersionNumber) {
            return YES;  // New version is greater, update is needed
        } else if (newVersionNumber < currentVersionNumber) {
            return NO;   // Current version is greater, no update needed
        }
    }
    
    // If all compared components are equal, check if new version has more components
    if ([newVersionComponents count] > [currentVersionComponents count]) {
        return YES;  // New version might have additional non-zero components
    }
    // If all components are equal or new version is shorter or the same, no update is needed
    return NO;
}

//convert dateString to UTC int
+ (int)convertTimeStringToUTC:(NSString *)timeStr {
    // init NSDateFormatter
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssXXXXX"];
    [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];

    // convert to NSDate
    NSDate *date = [formatter dateFromString:timeStr];
    
    // check if get date successed
    if (date) {
        // get Unix Timestamp from NSDate
        NSTimeInterval timestamp = [date timeIntervalSince1970];

        int intTimestamp = (int)timestamp;

        return intTimestamp;
    } else {
        //failed
        Debug(@"Failed to parse date string. Please check the format.");
        return 0;
    }
}

//Timestamp of the current time
+ (long long)currentTimestampAsLongLong {
    NSTimeInterval timeStamp;
    
    if (@available(iOS 13.0, *)) {
        timeStamp = [[NSDate now] timeIntervalSince1970];
    } else {
        timeStamp = [[NSDate date] timeIntervalSince1970];
    }
    
    long long timeStampLongLong = (long long)timeStamp;
    
    return timeStampLongLong;
}

+ (UIColor *)cellDetailTextTextColor {
    static UIColor *defaultTextColor = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultTextColor = [UIColor colorWithRed:0.666667 green:0.666667 blue:0.666667 alpha:1];
    });
    return defaultTextColor;
}

+ (NSDictionary *)checkNetworkReachability {
    SCNetworkReachabilityFlags flags;
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, "www.apple.com");
    BOOL isReachable = NO;
    BOOL isWiFiReachable = NO;

    if (SCNetworkReachabilityGetFlags(reachability, &flags)) {
        isReachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0 &&
                      (flags & kSCNetworkReachabilityFlagsConnectionRequired) == 0;
        
        BOOL isWWAN = (flags & kSCNetworkReachabilityFlagsIsWWAN) != 0;
        isWiFiReachable = isReachable && !isWWAN;
    }
    if (reachability) {
        CFRelease(reachability);
    }

    return @{
        @"isReachable": @(isReachable),
        @"isWiFiReachable": @(isWiFiReachable)
    };
}

+ (NSString *)uniquePathWithUniKey:(NSString *)uniKey fileName:(NSString *)fileName {
    if (!uniKey || !fileName) {
        NSLog(@"Error: Path or email is nil");
        return nil;
    }
    
    // If uniKey does not end with "
    if (![uniKey hasSuffix:@"/"]) {
        uniKey = [uniKey stringByAppendingString:@"/"];
    }
    
    return [NSString stringWithFormat:@"%@%@", uniKey, fileName];
}

+ (BOOL)isMainApp {
    NSString *bundleId = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
    return [bundleId isEqualToString:APP_ID];
}

@end
