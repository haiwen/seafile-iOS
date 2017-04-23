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

#define IMAGE_MAX_SIZE 2048
@interface Utils : NSObject

+ (BOOL)fileExistsAtPath:(NSString *)path;
+ (BOOL)checkMakeDir:(NSString *)path;
+ (void)clearAllFiles:(NSString *)path;
+ (BOOL)removeFile:(NSString *)path;
+ (void)removeDirIfEmpty:(NSString *)path;

+ (long long)folderSizeAtPath:(NSString*)folderPath;
+ (BOOL)copyFile:(NSURL *)from to:(NSURL *)to;
+ (BOOL)linkFileAtURL:(NSURL *)from to:(NSURL *)to;
+ (BOOL)linkFileAtPath:(NSString *)from to:(NSString *)to;

+ (long long)fileSizeAtPath1:(NSString*)filePath;

+ (BOOL)tryTransformEncoding:(NSString *)outfile fromFile:(NSString *)fromfile;

+ (NSString *)stringContent:(NSString *)path;

+ (NSData *)JSONEncode:(id)obj;
+ (id)JSONDecode:(NSData *)data error:(NSError **)error;
+ (NSString *)JSONEncodeDictionary:(NSDictionary *)dict;
+ (BOOL)isImageFile:(NSString *)name;
+ (BOOL)isVideoFile:(NSString *)name;

+ (BOOL)isVideoExt:(NSString *)ext;

+ (BOOL)writeDataToPath:(NSString*)filePath andAsset:(ALAsset*)asset;


+ (CGSize)textSizeForText:(NSString *)txt font:(UIFont *)font width:(float)width;

+ (void)alertWithTitle:(NSString *)title message:(NSString*)message yes:(void (^)())yes no:(void (^)())no from:(UIViewController *)c;
+ (void)alertWithTitle:(NSString *)title message:(NSString*)message handler:(void (^)())handler from:(UIViewController *)c;
+ (void)popupInputView:(NSString *)title placeholder:(NSString *)tip secure:(BOOL)secure handler:(void (^)(NSString *input))handler from:(UIViewController *)c;
+ (UIAlertController *)generateAlert:(NSArray *)arr withTitle:(NSString *)title handler:(void (^)(UIAlertAction *action))handler cancelHandler:(void (^)(UIAlertAction *action))cancelHandler preferredStyle:(UIAlertControllerStyle)preferredStyle;

+ (UIImage *)reSizeImage:(UIImage *)image toSquare:(float)length;
+ (UIImage *)imageFromPath:(NSString *)path withMaxSize:(float)length cachePath:(NSString *)cachePath;

+ (NSDictionary *)queryToDict:(NSString *)query;
+ (void)dict:(NSMutableDictionary *)dict setObject:(id)value forKey:(NSString *)defaultName;
+ (NSString *)assertName:(ALAsset *)asset;
@end
