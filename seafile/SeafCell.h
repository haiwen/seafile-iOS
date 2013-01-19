//
//  SeafCell.h
//  seafile
//
//  Created by Wang Wei on 1/19/13.
//  Copyright (c) 2013 tsinghua. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SeafCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UIImageView *imageView;
@property (strong, nonatomic) IBOutlet UILabel *textLabel;
@property (strong, nonatomic) IBOutlet UILabel *detailTextLabel;

@end
