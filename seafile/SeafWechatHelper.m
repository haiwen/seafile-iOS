//
//  SeafWechatHelper.m
//  seafileApp
//
//  Created by three on 2017/11/23.
//  Copyright © 2017年 Seafile. All rights reserved.
//

#import "SeafWechatHelper.h"
#import <SVProgressHUD/SVProgressHUD.h>

// libWeChatSDK.a has no arm64-simulator slice, so simulator builds don't link it
// (see Podfile post_install). Every WXApi symbol reference must stay inside
// !TARGET_OS_SIMULATOR.
@implementation SeafWechatHelper

+ (void)registerWechat {
#if !TARGET_OS_SIMULATOR
    [WXApi registerApp:@"wx4799bc7f5242c55a" universalLink:@""];
#endif
}

+ (BOOL)wechatInstalled {
    return [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"wechat://"]];
}

+ (BOOL)handleOpenURL:(NSURL *)url delegate:(id<WXApiDelegate>)delegate {
#if TARGET_OS_SIMULATOR
    return NO;
#else
    return [WXApi handleOpenURL:url delegate:delegate];
#endif
}

+ (void)shareToWechatWithFile:(SeafFile *)file {
    NSURL *url = [file exportURL];
    if (!url) {
        [SVProgressHUD showWithStatus:NSLocalizedString(@"File can not be shared", @"Seafile")];
        return;
    }
#if !TARGET_OS_SIMULATOR
    WXMediaMessage *message = [WXMediaMessage message];
    message.title = file.name;
    message.description = file.name;
    message.messageExt = [file.path pathExtension];
    
    if ([Utils isImageFile:file.name]) {
        WXImageObject *imageObj = [WXImageObject object];
        imageObj.imageData = [NSData dataWithContentsOfURL:url];
        [message setThumbImage:[file icon]];
        message.mediaObject = imageObj;
    } else {
        WXFileObject *fileObj = [WXFileObject object];
        fileObj.fileData = [NSData dataWithContentsOfURL:url];
        fileObj.fileExtension = [file.path pathExtension];
        message.mediaObject = fileObj;
    }
    SendMessageToWXReq *req = [[SendMessageToWXReq alloc] init];
    req.bText = NO;
    req.message = message;
    req.scene = WXSceneSession;
    [WXApi sendReq:req completion:^(BOOL success) {

    }];
#endif
}

@end
