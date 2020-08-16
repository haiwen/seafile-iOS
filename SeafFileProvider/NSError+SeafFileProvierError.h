//
//  NSError+SeafFileProvierError.h
//  SeafFileProvider
//
//  Created by three on 2018/6/13.
//  Copyright © 2018年 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSError (SeafFileProvierError)

+ (NSError *)fileProvierErrorServerUnreachable;
+ (NSError *)fileProvierErrorNotAuthenticated;
+ (NSError *)fileProvierErrorNoSuchItem;
+ (NSError *)fileProvierErrorPageExpired;
+ (NSError *)fileProvierErrorFilenameCollision;
+ (NSError *)fileProvierErrorInsufficientQuota;
+ (NSError *)fileProvierErrorNoAccount;

@end
