//
//  SeafPhotoView.h
//  seafilePro
//
//  Created by Wang Wei on 8/2/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>
#import "Utils.h"

#import "SeafDetailViewController.h"


@interface SeafPhotoView : UIScrollView
@property NSUInteger index;
@property (nonatomic) id<SeafPreView> photo;

- (id)initWithPhotoBrowser:(SeafDetailViewController *)browser;

- (void)displayImage;
- (void)displayImageFailure;
- (void)setMaxMinZoomScalesForCurrentBounds;
- (void)setProgress:(float)progress;
- (void)prepareForReuse;

@end
