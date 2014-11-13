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
+ (int)copyFile:(NSURL *)from to:(NSURL *)to;

+ (long long)fileSizeAtPath1:(NSString*)filePath;

+ (BOOL)tryTransformEncoding:(NSString *)outfile fromFile:(NSString *)fromfile;

+ (NSString *)stringContent:(NSString *)path;

+ (id)JSONDecode:(NSData *)data error:(NSError **)error;
+ (NSString *)JSONEncodeDictionary:(NSDictionary *)dict;
+ (BOOL)isImageFile:(NSString *)name;

+ (BOOL)writeDataToPath:(NSString*)filePath andAsset:(ALAsset*)asset;

+ (BOOL)fileExistsAtPath:(NSString *)path;

+ (CGSize)textSizeForText:(NSString *)txt font:(UIFont *)font width:(float)width;

@end
