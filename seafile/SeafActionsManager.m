//
//  SeafActionsManager.m
//  seafileApp
//
//  Created by three on 2018/11/26.
//  Copyright © 2018 Seafile. All rights reserved.
//

#import "SeafActionsManager.h"
#import "SeafRepos.h"
#import "SeafFile.h"
#import "SeafWechatHelper.h"
#import "SeafActionSheet.h"
#import "Debug.h"
#import "SVProgressHUD.h"

@implementation SeafActionsManager

+ (void)entryAction:(SeafBase *)entry inEncryptedRepo:(BOOL)inEncryptedRepo inTargetVC:(UIViewController *)targetVC fromView:(UIView *)view actionBlock:(ActionType)block {
    NSMutableArray *titles;
    if ([entry isKindOfClass:[SeafRepo class]]) {
        SeafRepo *repo = (SeafRepo *)entry;
        if (repo.encrypted) {
            titles = [NSMutableArray arrayWithObjects:S_DOWNLOAD, S_RESET_PASSWORD, nil];
        } else {
            titles = [NSMutableArray arrayWithObjects:S_DOWNLOAD, nil];
        }
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        SeafDir *dir = (SeafDir *)entry;
        if (dir.editable) {
            titles = [NSMutableArray arrayWithObjects:S_DOWNLOAD, S_DELETE, S_RENAME, nil];
        } else {
            titles = [NSMutableArray arrayWithObjects:S_DOWNLOAD, nil];
        }
    } else if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)entry;
        
        NSString *star = file.isStarred ? S_UNSTAR : S_STAR;
        if (file.mpath)
            titles = [NSMutableArray arrayWithObjects:star, S_DELETE, S_UPLOAD, nil];
        else
            titles = [NSMutableArray arrayWithObjects:star, S_DELETE, S_REDOWNLOAD, S_RENAME, nil];
        
        if ([SeafWechatHelper wechatInstalled]) {
            [titles addObject:S_SHARE_TO_WECHAT];
        }
    } else if ([entry isKindOfClass:[SeafUploadFile class]]) {
        [titles addObjectsFromArray:@[S_DOWNLOAD, S_DELETE, S_RENAME]];
    }
    
    if (![entry isKindOfClass:[SeafRepo class]] && !inEncryptedRepo) {
        [titles addObjectsFromArray:@[S_SHARE_EMAIL, S_SHARE_LINK]];
    }
    
    SeafActionSheet *actionSheet = [SeafActionSheet actionSheetWithTitles:[titles copy]];
    actionSheet.targetVC = targetVC;
    
    [actionSheet setButtonPressedBlock:^(SeafActionSheet *actionSheet, NSIndexPath *indexPath){
        [actionSheet dismissAnimated:YES];
        if (indexPath.section == 0) {
            block(titles[indexPath.row]);
        }
    }];
    
    [actionSheet showFromView:view];
    
}

+ (void)directoryAction:(SeafDir*)directory photos:(NSArray *)photos inTargetVC:(UIViewController *)targetVC fromItem:(UIBarButtonItem *)item actionBlock:(ActionType)block {
    NSMutableArray *titles = nil;
    if ([directory isKindOfClass:[SeafRepos class]]) {
        titles = [NSMutableArray arrayWithObjects:S_MKLIB,S_SORT_NAME, S_SORT_MTIME, nil];
    } else if (directory.editable) {
        titles = [NSMutableArray arrayWithObjects:S_EDIT, S_NEWFILE, S_MKDIR, S_SORT_NAME, S_SORT_MTIME, S_PHOTOS_ALBUM, nil];
        if (photos.count >= 3) [titles addObject:S_PHOTOS_BROWSER];
    } else {
        titles = [NSMutableArray arrayWithObjects:S_SORT_NAME, S_SORT_MTIME, S_PHOTOS_ALBUM, nil];
        if (photos.count >= 3) [titles addObject:S_PHOTOS_BROWSER];
    }
    
    SeafActionSheet *actionSheet = [SeafActionSheet actionSheetWithTitles:titles];
    actionSheet.targetVC = targetVC;
    
    [actionSheet setButtonPressedBlock:^(SeafActionSheet *actionSheet, NSIndexPath *indexPath){
        [actionSheet dismissAnimated:YES];
        if (indexPath.section == 0) {
            block(titles[indexPath.row]);
        }
    }];
    
    [actionSheet showFromView:item];
}

+ (void)exportByActivityView:(NSArray <NSURL *> *)urls item:(UIBarButtonItem *)barButtonItem targerVC:(UIViewController *)targetVC {
    UIActivityViewController *controller = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
    controller.completionWithItemsHandler = ^(UIActivityType __nullable activityType, BOOL completed, NSArray * __nullable returnedItems, NSError * __nullable activityError) {
        Debug("activityType=%@ completed=%d, returnedItems=%@, activityError=%@", activityType, completed, returnedItems, activityError);
        if ([UIActivityTypeSaveToCameraRoll isEqualToString:activityType]) {
            [self savedToPhotoAlbumWithError:activityError];
        }
    };
    if (barButtonItem) {
        controller.popoverPresentationController.barButtonItem = barButtonItem;
    }
    
    [targetVC presentViewController:controller animated:true completion:nil];
}

+ (void)savedToPhotoAlbumWithError:(NSError *)error {
    if (!error) {
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Successfully saved", @"Seafile")];
    } else {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Save failed", @"Seafile")];
    }
}

@end
