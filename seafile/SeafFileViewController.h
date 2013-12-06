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
    EDITOP_CREATE,
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
#import "SeafDir.h"
#import "SeafFile.h"


@interface SeafFileViewController : UITableViewController <UIAlertViewDelegate, UIActionSheetDelegate, SeafDentryDelegate, SeafFileUpdateDelegate> {
}

@property (strong, nonatomic) SeafConnection *connection;

@property (strong, readonly) SeafDetailViewController *detailViewController;

- (void)refreshView;
- (void)uploadFile:(SeafUploadFile *)file;
- (void)chooseUploadDir:(SeafDir *)dir file:(id<PreViewDelegate>)ufile;

@end
