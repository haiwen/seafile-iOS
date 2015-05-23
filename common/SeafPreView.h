//
//  SeafPreView.h
//  seafilePro
//
//  Created by Wang Wei on 8/3/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuickLook/QuickLook.h>
#import "SeafItem.h"

@class SeafBase;

@protocol SeafDentryDelegate <NSObject>
- (void)entry:(SeafBase *)entry updated:(BOOL)updated progress:(int)percent;
- (void)entry:(SeafBase *)entry downloadingFailed:(NSUInteger)errCode;
- (void)entry:(SeafBase *)entry repoPasswordSet:(BOOL)success;
@end

@protocol SeafPreView <QLPreviewItem, SeafItem>
- (UIImage *)image;
- (UIImage *)icon;
- (NSURL *)exportURL;
- (NSString *)mime;
- (BOOL)editable;
- (long long )filesize;
- (NSString *)strContent;
- (BOOL)saveStrContent:(NSString *)content;
- (BOOL)isDownloading;
- (void)unload;
- (BOOL)hasCache;
- (BOOL)isImageFile;
- (long long) mtime;


- (void)load:(id<SeafDentryDelegate>)delegate force:(BOOL)force;
@end
