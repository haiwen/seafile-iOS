//
//  SeafDetailViewController.h
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MessageUI/MFMailComposeViewController.h>

#import "SeafFile.h"


@interface SeafDetailViewController : UIViewController <UISplitViewControllerDelegate, UIWebViewDelegate, UIActionSheetDelegate, MFMailComposeViewControllerDelegate, SeafFileDelegate>

@property (nonatomic) id<QLPreviewItem, PreViewDelegate> preViewItem;

- (void)fileContentLoaded :(SeafFile *)file result:(BOOL)res completeness:(int)percent;

- (void)refreshView;

@end
