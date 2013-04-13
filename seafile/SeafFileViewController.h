//
//  SeafMasterViewController.h
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>


enum {
    EDITOP_SPACE = 0,
    EDITOP_MKDIR = 1,
    EDITOP_COPY,
    EDITOP_MOVE,
    EDITOP_DELETE,
    EDITOP_PASTE,
    EDITOP_MOVETO,
    EDITOP_CANCEL,
    EDITOP_NUM,
};


@class SeafDetailViewController;

#import <CoreData/CoreData.h>

#import "EGORefreshTableHeaderView.h"
#import "InputAlertPrompt.h"
#import "SeafDir.h"
#import "SeafFile.h"


@interface SeafFileViewController : UITableViewController <UIAlertViewDelegate, UIActionSheetDelegate, SeafDentryDelegate, EGORefreshTableHeaderDelegate, InputDoneDelegate, SeafFileUploadDelegate> {
}

@property (strong, nonatomic) SeafDetailViewController *detailViewController;
@property (strong, nonatomic) SeafDir *directory;
@property (readonly) EGORefreshTableHeaderView* refreshHeaderView;

- (void)initTabBarItem;
- (void)refreshView;


@end
