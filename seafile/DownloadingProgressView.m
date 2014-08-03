//
//  DownloadingProgressView.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "DownloadingProgressView.h"
#import "Debug.h"

@interface DownloadingProgressView ()
@property id<SeafPreView> item;
@end

@implementation DownloadingProgressView
@synthesize imageView = _imageView;
@synthesize nameLabel = _nameLabel;
@synthesize progress = _progress;
@synthesize item = _item;



- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];
    for (UIView *v in self.subviews) {
        v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin| UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin;
    }
    self.autoresizesSubviews = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    if (ios7) {
        self.cancelBt.layer.borderColor = [[UIColor lightGrayColor] CGColor];
        self.cancelBt.layer.borderWidth = 0.5f;
        self.cancelBt.layer.cornerRadius = 5.0f;
    } else {
        self.cancelBt.reversesTitleShadowWhenHighlighted = NO;
        self.cancelBt.tintColor=[UIColor whiteColor];
    }
    return self;
}

- (void)configureViewWithItem:(id<QLPreviewItem, SeafPreView>)item completeness:(int)percent
{
    if (_item != item) {
        _item = item;
        self.imageView.image = item.icon;
        self.nameLabel.text = item.previewItemTitle;
    }
    _progress.progress = percent * 1.0f/100;
}


@end
