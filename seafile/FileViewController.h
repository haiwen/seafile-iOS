//
//  FileViewController.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>
#import <MessageUI/MFMailComposeViewController.h>

@interface FileViewController : QLPreviewController <QLPreviewControllerDataSource, MFMailComposeViewControllerDelegate, UIActionSheetDelegate, SeafFileDelegate>;

- (id)initWithNavigationItem:(UINavigationItem *)navItem;

- (void)setPreItem:(id<QLPreviewItem, PreViewDelegate>)prevItem;

- (void)updateDownloadProgress:(BOOL)res completeness:(int)percent;

@end
