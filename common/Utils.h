//
//  Utils.h
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <UIKit/UIKit.h>

@interface Utils : NSObject

+ (BOOL)checkMakeDir:(NSString *)path;
+ (void)clearAllFiles:(NSString *)path;
+ (long long)folderSizeAtPath:(NSString*)folderPath;
+ (NSURL *)copyFile:(NSURL *)from to:(NSURL *)to;

+ (long long)fileSizeAtPath1:(NSString*)filePath;

+ (BOOL)tryTransformEncoding:(NSString *)outfile fromFile:(NSString *)fromfile;

+ (NSString *)stringContent:(NSString *)path;

+ (NSData *)JSONEncode:(id)obj;
+ (id)JSONDecode:(NSData *)data error:(NSError **)error;
+ (NSString *)JSONEncodeDictionary:(NSDictionary *)dict;
+ (BOOL)isImageFile:(NSString *)name;
+ (BOOL)isImageExt:(NSString *)ext;

+ (BOOL)writeDataToPath:(NSString*)filePath andAsset:(ALAsset*)asset;

+ (BOOL)fileExistsAtPath:(NSString *)path;

+ (CGSize)textSizeForText:(NSString *)txt font:(UIFont *)font width:(float)width;

+ (void)alertWithTitle:(NSString *)title message:(NSString*)message yes:(void (^)())yes no:(void (^)())no from:(UIViewController *)c;
+ (void)alertWithTitle:(NSString *)title message:(NSString*)message handler:(void (^)())handler from:(UIViewController *)c;
+ (void)popupInputView:(NSString *)title placeholder:(NSString *)tip secure:(BOOL)secure handler:(void (^)(NSString *input))handler from:(UIViewController *)c;

+ (UIImage *)reSizeImage:(UIImage *)image toSquare:(float)length;

@end
