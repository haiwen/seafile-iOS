//
//  FileViewController.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>

#import "Utils.h"

@protocol PreViewSelectDelegate <NSObject>
- (void)selectItem:(id<QLPreviewItem, PreViewDelegate>)prevItem;
- (void)willSelect:(id<QLPreviewItem, PreViewDelegate>)prevItem;

@end

@interface FileViewController : QLPreviewController;

- (void)setPreItem:(id<QLPreviewItem, PreViewDelegate>)prevItem;

- (void)setPreItems:(NSArray *)prevItems current:(id<QLPreviewItem, PreViewDelegate>)item;

@property id<PreViewSelectDelegate> selectDelegate;

@end
