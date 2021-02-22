//
//  Utils.h
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
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
+ (BOOL)linkFileAtURL:(NSURL *)from to:(NSURL *)to error:(NSError **)error;
+ (BOOL)linkFileAtPath:(NSString *)from to:(NSString *)to error:(NSError **)error;
+ (BOOL)writeDataWithMeta:(NSData *)imageData toPath:(NSString*)filePath;
+ (BOOL)writeCIImage:(CIImage *)ciImage toPath:(NSString*)filePath API_AVAILABLE(ios(10.0));

+ (long long)fileSizeAtPath1:(NSString*)filePath;

+ (BOOL)tryTransformEncoding:(NSString *)outfile fromFile:(NSString *)fromfile;

+ (NSString *)stringContent:(NSString *)path;

+ (NSData *)JSONEncode:(id)obj;
+ (id)JSONDecode:(NSData *)data error:(NSError **)error;
+ (NSString *)JSONEncodeDictionary:(NSDictionary *)dict;
+ (BOOL)isImageFile:(NSString *)name;
+ (BOOL)isVideoFile:(NSString *)name;

+ (BOOL)isVideoExt:(NSString *)ext;

+ (CGSize)textSizeForText:(NSString *)txt font:(UIFont *)font width:(float)width;

+ (void)alertWithTitle:(NSString *)title message:(NSString*)message yes:(void (^)(void))yes no:(void (^)(void))no from:(UIViewController *)c;
+ (void)alertWithTitle:(NSString *)title message:(NSString*)message handler:(void (^)(void))handler from:(UIViewController *)c;
+ (void)popupInputView:(NSString *)title placeholder:(NSString *)tip inputs:(NSString *)inputs secure:(BOOL)secure handler:(void (^)(NSString *input))handler from:(UIViewController *)c;
+ (UIAlertController *)generateAlert:(NSArray *)arr withTitle:(NSString *)title handler:(void (^)(UIAlertAction *action))handler cancelHandler:(void (^)(UIAlertAction *action))cancelHandler preferredStyle:(UIAlertControllerStyle)preferredStyle;

+ (UIImage *)reSizeImage:(UIImage *)image toSquare:(float)length;
+ (UIImage *)imageFromPath:(NSString *)path withMaxSize:(float)length cachePath:(NSString *)cachePath;

+ (NSDictionary *)queryToDict:(NSString *)query;
+ (void)dict:(NSMutableDictionary *)dict setObject:(id)value forKey:(NSString *)defaultName;

+ (NSString *)encodePath:(NSString *)server username:(NSString *)username repo:(NSString *)repoId path:(NSString *)path;
+ (void)decodePath:(NSString *)encodedStr server:(NSString **)server username:(NSString **)username repo:(NSString **)repoId path:(NSString **)path;

+ (NSError *)defaultError;
+ (NSString *)convertToALAssetUrl:(NSString *)fileURL andIdentifier:(NSString *)identifier;

+ (NSURL *)generateFileTempPath:(NSString *)name;

+ (NSString *)currentBundleIdentifier;

@end
