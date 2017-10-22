//
//  SeafUpDownloadViewController.h
//  seafilePro
//
//  Created by three on 2017/7/29.
//  Copyright © 2017年 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef enum : NSUInteger {
    UPLOAD_DETAIL,
    DOWNLOAD_DETAIL,
} DETAILTYPE;

@interface SeafSyncInfoViewController : UITableViewController

-(instancetype)initWithType:(DETAILTYPE)type;

@property (nonatomic, assign) DETAILTYPE detailType;

@end
