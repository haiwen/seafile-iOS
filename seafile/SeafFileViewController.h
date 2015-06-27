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

#define S_MKDIR NSLocalizedString(@"New Folder", @"Seafile")
#define S_NEWFILE NSLocalizedString(@"New File", @"Seafile")
#define S_SORT_NAME NSLocalizedString(@"Sort by Name", @"Seafile")
#define S_SORT_MTIME NSLocalizedString(@"Sort by Last Modifed Time", @"Seafile")

#define S_RENAME NSLocalizedString(@"Rename", @"Seafile")
#define S_EDIT NSLocalizedString(@"Edit", @"Seafile")
#define S_DELETE NSLocalizedString(@"Delete", @"Seafile")
#define S_SHARE_EMAIL NSLocalizedString(@"Send share link via email", @"Seafile")
#define S_SHARE_LINK NSLocalizedString(@"Copy share link to clipboard", @"Seafile")
#define S_REDOWNLOAD NSLocalizedString(@"Redownload", @"Seafile")
#define S_UPLOAD NSLocalizedString(@"Upload", @"Seafile")


@class SeafDetailViewController;

#import <CoreData/CoreData.h>

#import "EGORefreshTableHeaderView.h"
#import "SeafDir.h"
#import "SeafFile.h"


@interface SeafFileViewController : UITableViewController <SeafDentryDelegate, SeafFileUpdateDelegate> {
}

@property (strong, nonatomic) SeafConnection *connection;

@property (strong, readonly) SeafDetailViewController *detailViewController;

- (void)refreshView;
- (void)uploadFile:(SeafUploadFile *)file;
- (void)chooseUploadDir:(SeafDir *)dir file:(SeafUploadFile *)ufile replace:(BOOL)replace;

- (void)photoSelectedChanged:(id<SeafPreView>)preViewItem to:(id<SeafPreView>)to;

@end
