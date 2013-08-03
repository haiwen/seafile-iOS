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


@interface SeafDetailViewController : UIViewController <UISplitViewControllerDelegate, SeafFileDelegate, SeafDentryDelegate>

@property (nonatomic) id<QLPreviewItem, PreViewDelegate> preViewItem;
@property (nonatomic) UIViewController *masterVc;
- (void)refreshView;
- (void)setPreViewItem:(id<QLPreviewItem, PreViewDelegate>)item master:(UIViewController *)c;


@end
