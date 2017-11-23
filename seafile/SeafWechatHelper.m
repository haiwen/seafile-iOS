//
//  SeafWechatHelper.m
//  seafileApp
//
//  Created by three on 2017/11/23.
//  Copyright © 2017年 Seafile. All rights reserved.
//

#import "SeafWechatHelper.h"
#import <SVProgressHUD/SVProgressHUD.h>

@implementation SeafWechatHelper

+ (void)registerWechat {
    [WXApi registerApp:@"wx4799bc7f5242c55a"];
}

+ (BOOL)wechatInstalled {
    return [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"wechat://"]];
}

+ (void)shareToWechatWithFile:(SeafFile *)file {
    NSURL *url = [file exportURL];
    if (!url) {
        [SVProgressHUD showWithStatus:NSLocalizedString(@"File can not be shared", @"Seafile")];
        return;
    }
    
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
    [WXApi sendReq:req];
}

@end
