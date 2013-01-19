//
//  SeafAccountCell.h
//  seafile
//
//  Created by Wang Wei on 1/17/13.
//  Copyright (c) 2013 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SeafAccountCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UILabel *serverLabel;
@property (strong, nonatomic) IBOutlet UILabel *emailLabel;
@property (strong, nonatomic) IBOutlet UIImageView *imageview;

@end
