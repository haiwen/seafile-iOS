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

@property (nonatomic) IBOutlet UIImageView * _Nonnull iconView;
@property (nonatomic) IBOutlet UILabel * _Nonnull pathLabel;
@property (nonatomic) IBOutlet UILabel * _Nonnull nameLabel;
@property (nonatomic) IBOutlet UILabel * _Nonnull statusLabel;
@property (nonatomic) IBOutlet UILabel * _Nonnull sizeLabel;
@property (nonatomic) IBOutlet UIProgressView * _Nonnull progressView;

- (void)showCellWithTask:(id<SeafTask> _Nonnull)task;

@end
