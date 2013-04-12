//
//  Utils.h
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol PreViewDelegate <NSObject>
- (UIImage *)image;
- (NSURL *)checkoutURL;
- (NSString *)mime;
- (NSString *)content;
- (BOOL)saveContent:(NSString *)content;
@end

@interface Utils : NSObject

+ (NSString *)applicationDocumentsDirectory;
+ (NSString *)applicationTempDirectory;

+ (BOOL)checkMakeDir:(NSString *)path;
+ (void)clearAllFiles:(NSString *)path;
+ (long long)folderSizeAtPath:(NSString*)folderPath;
+ (int)copyFile:(NSURL *)from to:(NSURL *)to;

+ (BOOL)tryTransformEncoding:(NSString *)outfile fromFile:(NSString *)fromfile;

+ (NSString *)stringContent:(NSString *)path;

+ (void)setRepo:(NSString *)repoId password:(NSString *)password;
+ (NSString *)getRepoPassword:(NSString *)repoId;
+ (void)clearRepoPasswords;


+ (id)JSONDecode:(NSData *)data error:(NSError **)error;

@end
