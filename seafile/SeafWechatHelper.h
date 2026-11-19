//
//  SeafWechatHelper.h
//  seafileApp
//
//  Created by three on 2017/11/23.
//  Copyright © 2017年 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <WechatOpenSDK/WXApi.h>
#import "SeafFile.h"

@interface SeafWechatHelper : NSObject

+ (void)registerWechat;
+ (BOOL)wechatInstalled;
+ (BOOL)handleOpenURL:(NSURL *)url delegate:(id<WXApiDelegate>)delegate;
+ (void)shareToWechatWithFile:(SeafFile*)file;

@end
