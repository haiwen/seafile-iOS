//
//  SeafDetailViewController.h
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafFile.h"


@interface SeafDetailViewController : UIViewController <UISplitViewControllerDelegate, SeafShareDelegate, SeafDentryDelegate>

@property (nonatomic) id<SeafPreView> preViewItem;
@property (nonatomic) UIViewController<SeafDentryDelegate> *masterVc;
- (void)refreshView;
- (void)setPreViewItem:(id<SeafPreView>)item master:(UIViewController<SeafDentryDelegate> *)c;

- (void)setPreViewItems:(NSArray *)items current:(id<SeafPreView>)item master:(UIViewController<SeafDentryDelegate> *)c;

@end
