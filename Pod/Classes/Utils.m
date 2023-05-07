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
#import <sys/stat.h>
#import <dirent.h>
#import <sys/xattr.h>
#import <Photos/Photos.h>
#import <MobileCoreServices/MobileCoreServices.h>

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
    if ([Utils fileSizeAtPath1:path] > 10 * 1024 * 1024)
        return nil;
    NSString *encodeContent;
    NSStringEncoding encode;
    encodeContent = [NSString stringWithContentsOfFile:path usedEncoding:&encode error:nil];
    if (!encodeContent) {
        int i = 0;
        NSStringEncoding encodes[] = {
            NSUTF8StringEncoding,
            CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000),
            CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_2312_80),
            CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGBK_95),
            NSUnicodeStringEncoding,
            NSASCIIStringEncoding,
            0,
        };
        while (encodes[i]) {
            encodeContent = [NSString stringWithContentsOfFile:path encoding:encodes[i] error:nil];
             if (encodeContent) {
                Debug("use encoding %d, %ld\n", i, (unsigned long)encodes[i]);
                break;
            }
            ++i;
        }
    }
    return encodeContent;
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
    NSURL *url = [[NSURL alloc] initFileURLWithPath:filePath];
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

+ (UIImage *)imageFromPath:(NSString *)path withMaxSize:(float)length cachePath:(NSString *)cachePath
{
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
        if (image.size.width > MAX_SIZE || image.size.height > MAX_SIZE) {
            UIImage *img =  [Utils reSizeImage:image toSquare:MAX_SIZE];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND,0), ^{
                [UIImageJPEGRepresentation(img, 1.0) writeToFile:cachePath atomically:YES];
            });
            return img;
        }
        return image;
    }
    return nil;
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
    NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
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

@end
