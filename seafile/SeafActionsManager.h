//
//  SeafActionsManager.h
//  seafileApp
//
//  Created by three on 2018/11/26.
//  Copyright © 2018 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SeafBase.h"
#import "SeafDir.h"

typedef void(^ActionType)(NSString *typeTile);

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
    EDITOP_EXPORT,
};

#define S_MKDIR NSLocalizedString(@"New Folder", @"Seafile")
#define S_MKLIB NSLocalizedString(@"New Library", @"Seafile")
#define S_NEWFILE NSLocalizedString(@"New File", @"Seafile")
#define S_SORT_NAME NSLocalizedString(@"Sort by Name", @"Seafile")
#define S_SORT_MTIME NSLocalizedString(@"Sort by Last Modifed Time", @"Seafile")

#define S_STAR NSLocalizedString(@"Star", @"Seafile")
#define S_UNSTAR NSLocalizedString(@"Unstar", @"Seafile")

#define S_RENAME NSLocalizedString(@"Rename", @"Seafile")
#define S_EDIT NSLocalizedString(@"Edit", @"Seafile")
#define S_DELETE NSLocalizedString(@"Delete", @"Seafile")
#define S_MORE NSLocalizedString(@"More", @"Seafile")
#define S_DOWNLOAD NSLocalizedString(@"Download", @"Seafile")
#define S_PHOTOS_ALBUM NSLocalizedString(@"Save all photos to album", @"Seafile")
#define S_SAVING_PHOTOS_ALBUM NSLocalizedString(@"Saving all photos to album", @"Seafile")

#define S_PHOTOS_BROWSER NSLocalizedString(@"Open photo browser", @"Seafile")

#define S_SHARE_EMAIL NSLocalizedString(@"Send share link via email", @"Seafile")
#define S_SHARE_LINK NSLocalizedString(@"Copy share link to clipboard", @"Seafile")
#define S_REDOWNLOAD NSLocalizedString(@"Redownload", @"Seafile")
#define S_UPLOAD NSLocalizedString(@"Upload", @"Seafile")
#define S_RESET_PASSWORD NSLocalizedString(@"Reset repo password", @"Seafile")
#define S_CLEAR_REPO_PASSWORD NSLocalizedString(@"Clear password", @"Seafile")
#define S_SHARE_TO_WECHAT NSLocalizedString(@"Share to WeChat", "Seafile")
#define S_SHARE NSLocalizedString(@"Share", "Seafile")

NS_ASSUME_NONNULL_BEGIN

@interface SeafActionsManager : NSObject

+ (void)directoryAction:(SeafDir*)directory photos:(NSArray *)photos inTargetVC:(UIViewController *)targetVC fromItem:(UIBarButtonItem *)item actionBlock:(ActionType)block;

+ (void)entryAction:(SeafBase *)entry inEncryptedRepo:(BOOL)encrypted inTargetVC:(UIViewController *)targetVC fromView:(UIView *)view actionBlock:(ActionType)block;

+ (void)exportByActivityView:(NSArray <NSURL *> *)urls item:(UIBarButtonItem * _Nullable)barButtonItem targerVC:(UIViewController *)targetVC;

@end

NS_ASSUME_NONNULL_END
