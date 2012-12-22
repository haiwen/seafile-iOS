//
//  SeafTableViewRepoCell.h
//  seafile
//
//  Created by Wang Wei on 8/29/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SeafTableViewRepoCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UIImageView *mimeImage;
@property (strong, nonatomic) IBOutlet UILabel *nameLabel;
@property (strong, nonatomic) IBOutlet UILabel *mtimeLabel;
@property (strong, nonatomic) IBOutlet UILabel *sizeLabel;
@property (strong, nonatomic) IBOutlet UILabel *descLabel;

@end
