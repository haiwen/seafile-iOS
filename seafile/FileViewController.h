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
@interface FileViewController : QLPreviewController <QLPreviewControllerDataSource>;

- (void)setPreItem:(id<QLPreviewItem, PreViewDelegate>)prevItem;

@end
