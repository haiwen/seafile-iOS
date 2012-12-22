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
@end

@interface Utils : NSObject

+ (NSString *)applicationDocumentsDirectory;
+ (BOOL)checkMakeDir:(NSString *)path;
+ (void)clearAllFiles:(NSString *)path;
+ (long long)folderSizeAtPath:(NSString*)folderPath;
+ (int)copyFile:(NSURL *)from to:(NSURL *)to;

+ (void)setRepo:(NSString *)repoId password:(NSString *)password;
+ (NSString *)getRepoPassword:(NSString *)repoId;

@end
