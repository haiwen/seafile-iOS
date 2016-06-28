//
//  SeafCell.h
//  seafile
//
//  Created by Wang Wei on 1/19/13.
//  Copyright (c) 2013 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MarqueeLabel.h"

@interface SeafEventCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UIImageView *accountImageView;
@property (strong, nonatomic) IBOutlet MarqueeLabel *textLabel;
@property (strong, nonatomic) IBOutlet UILabel *authorLabel;
@property (strong, nonatomic) IBOutlet UILabel *timeLabel;
@property (strong, nonatomic) IBOutlet MarqueeLabel *repoNameLabel;


@end
