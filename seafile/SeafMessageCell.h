//
//  SeafMessageCellTableViewCell.h
//  seafilePro
//
//  Created by Wang Wei on 4/18/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SeafMessageCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UIImageView *imageView;
@property (strong, nonatomic) IBOutlet UILabel *textLabel;
@property (strong, nonatomic) IBOutlet UILabel *timestampLabel;
@property (strong, nonatomic) IBOutlet UILabel *badgeLabel;
@property (strong, nonatomic) IBOutlet UIImageView *badgeImage;
@property (strong, nonatomic) IBOutlet UILabel *detailLabel;

@end
