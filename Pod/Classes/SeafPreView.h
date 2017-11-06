//
//  SeafPreView.h
//  seafilePro
//
//  Created by Wang Wei on 8/3/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuickLook/QuickLook.h>

@class SeafBase;

enum SET_REPO_PASSWORD_RET {
    RET_SUCCESS,
    RET_WRONG_PASSWORD,
    RET_FAILED,
};

@protocol SeafRepoPasswordDelegate <NSObject>
- (void)entry:(SeafBase *)entry repoPasswordSet:(int)ret;
@end

@protocol SeafDentryDelegate
- (void)download:(SeafBase *)entry progress:(float)progress;
- (void)download:(SeafBase *)entry complete:(BOOL)updated;
- (void)download:(SeafBase *)entry failed:(NSError *)error;
@end

@protocol SeafSortable <NSObject>
- (NSString *)name;
- (long long)mtime;
@end


@protocol SeafPreView <QLPreviewItem, SeafSortable>
- (UIImage *)image;
- (UIImage *)thumb;
- (UIImage *)icon;
- (NSURL *)exportURL;
- (NSString *)mime;
- (BOOL)editable;
- (long long )filesize;
- (NSString *)strContent;
- (BOOL)saveStrContent:(NSString *)content;
- (BOOL)hasCache;
- (BOOL)isImageFile;
- (long long) mtime;
- (void)cancelAnyLoading;
- (void)setDelegate:(id)delegate;

- (void)load:(id<SeafDentryDelegate>)delegate force:(BOOL)force;
@end
