//
//  SeafActionsManager.m
//  seafileApp
//
//  Created by three on 2018/11/26.
//  Copyright © 2018 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafActionsManager.h"
#import "SeafRepos.h"
#import "SeafFile.h"
#import "SeafWechatHelper.h"
#import "SeafActionSheet.h"
#import "Debug.h"
#import "SVProgressHUD.h"
#import "SeafGlobal.h"
#import "Utils.h"

@interface SeafShareURLItem : NSObject <UIActivityItemSource>

@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, assign) BOOL isImage;
@property (nonatomic, assign) BOOL isVideo;

- (instancetype)initWithURL:(NSURL *)url;

@end

@implementation SeafShareURLItem

- (instancetype)initWithURL:(NSURL *)url
{
    self = [super init];
    if (self) {
        _fileURL = url;
        NSString *fileName = url.lastPathComponent ?: @"";
        _isImage = [Utils isImageFile:fileName];
        _isVideo = [Utils isVideoFile:fileName];
    }
    return self;
}

- (id)activityViewControllerPlaceholderItem:(UIActivityViewController *)activityViewController
{
    return self.fileURL ?: [NSURL URLWithString:@"about:blank"];
}

- (id)activityViewController:(UIActivityViewController *)activityViewController
        itemForActivityType:(UIActivityType)activityType
{
    if (!activityType) {
        return self.fileURL;
    }
    if ([activityType isEqualToString:UIActivityTypeSaveToCameraRoll]) {
        if (self.isImage || self.isVideo) {
            if (self.isImage) {
                UIImage *image = [UIImage imageWithContentsOfFile:self.fileURL.path];
                if (image) {
                    return image;
                }
            }
            if (self.isVideo) {
                return self.fileURL;
            }
        }
        return nil;
    }
    return self.fileURL;
}

@end

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
            titles = [NSMutableArray arrayWithObjects:star, S_DELETE, S_RE_UPLOAD_FILE, nil];
        else
            titles = [NSMutableArray arrayWithObjects:star, S_DELETE, S_REDOWNLOAD, S_RENAME, nil];
        
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
        titles = [NSMutableArray arrayWithObjects:S_UPLOAD, S_UPLOAD_FILE, S_EDIT,S_NEWFILE, S_MKDIR, S_SORT_NAME, S_SORT_MTIME, nil];
    } else {
        titles = [NSMutableArray arrayWithObjects:S_SORT_NAME, S_SORT_MTIME, nil];
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

+ (void)exportByActivityView:(NSArray <NSURL *> *)urls item:(id)item targerVC:(UIViewController *)targetVC {
    NSMutableArray *shareItems = [NSMutableArray arrayWithCapacity:urls.count];
    for (NSURL *url in urls) {
        if (![url isKindOfClass:[NSURL class]]) continue;
        SeafShareURLItem *itemSource = [[SeafShareURLItem alloc] initWithURL:url];
        [shareItems addObject:itemSource];
    }
    UIActivityViewController *controller = [[UIActivityViewController alloc] initWithActivityItems:shareItems.count > 0 ? shareItems : urls applicationActivities:nil];
    controller.completionWithItemsHandler = ^(UIActivityType __nullable activityType, BOOL completed, NSArray * __nullable returnedItems, NSError * __nullable activityError) {
        Debug("activityType=%@ completed=%d, returnedItems=%@, activityError=%@", activityType, completed, returnedItems, activityError);
        if ([UIActivityTypeSaveToCameraRoll isEqualToString:activityType]) {
            [self savedToPhotoAlbumWithError:activityError];
        }
    };

    if (IsIpad()) {
        UIPopoverPresentationController *popover = controller.popoverPresentationController;
        if (targetVC.view.window) {
            popover.sourceView = targetVC.view.window;
            popover.sourceRect = CGRectMake(CGRectGetMidX(targetVC.view.window.bounds), CGRectGetMidY(targetVC.view.window.bounds), 0, 0);
        } else {
            popover.sourceView = targetVC.view;
            popover.sourceRect = CGRectMake(CGRectGetMidX(targetVC.view.bounds), CGRectGetMidY(targetVC.view.bounds), 0, 0);
        }
        popover.permittedArrowDirections = 0;
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
