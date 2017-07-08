//
//  SeafSyncInfoCell.h
//  seafilePro
//
//  Created by three on 2017/8/1.
//  Copyright © 2017年 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafFile.h"
#import "SeafUploadFile.h"

@interface SeafSyncInfoCell : UITableViewCell

@property (weak, nonatomic) IBOutlet UIImageView *iconView;
@property (weak, nonatomic) IBOutlet UILabel *pathLabel;
@property (weak, nonatomic) IBOutlet UILabel *nameLabel;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (weak, nonatomic) IBOutlet UILabel *sizeLabel;
@property (weak, nonatomic) IBOutlet UIProgressView *progressView;

- (void)showCellWithSFile:(SeafFile*)sfile;
- (void)showCellWithUploadFile:(SeafUploadFile*)ufile;

@end
