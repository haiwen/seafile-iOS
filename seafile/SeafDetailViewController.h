//
//  SeafDetailViewController.h
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafFile.h"

enum PREVIEW_STATE {
    PREVIEW_NONE = 0,
    PREVIEW_QL_MODAL,
    PREVIEW_WEBVIEW,
    PREVIEW_WEBVIEW_JS,
    PREVIEW_DOWNLOADING,
    PREVIEW_PHOTO,
    PREVIEW_FAILED,
    PREVIEW_TEXT
};

@interface SeafDetailViewController : UIViewController <UISplitViewControllerDelegate, QLPreviewControllerDelegate, QLPreviewControllerDataSource, SeafShareDelegate, SeafDentryDelegate, SeafFileUpdateDelegate>

@property (readonly) int state;

@property (nonatomic) id<SeafPreView> preViewItem;
@property (nonatomic, weak) UIViewController<SeafDentryDelegate> *masterVc;
@property (nonatomic, strong) QLPreviewController *qlViewController;
@property (nonatomic, strong) UIView *toolbarView;

- (void)refreshView;
- (void)setPreViewItem:(id<SeafPreView>)item master:(UIViewController<SeafDentryDelegate> *)c;

- (void)setPreViewPhotos:(NSArray *)items current:(id<SeafPreView>)item master:(UIViewController<SeafDentryDelegate> *)c;

- (void)goBack:(id)sender;

@end
