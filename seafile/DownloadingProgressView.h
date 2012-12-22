//
//  DownloadingProgressView.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>

#import "Utils.h"


@interface DownloadingProgressView : UIView
@property (strong, nonatomic) IBOutlet UIImageView *imageView;
@property (strong, nonatomic) IBOutlet UILabel *nameLabel;
@property (strong, nonatomic) IBOutlet UIProgressView *progress;

- (void)configureViewWithItem:(id<QLPreviewItem, PreViewDelegate>)item completeness:(int)percent;


@end
