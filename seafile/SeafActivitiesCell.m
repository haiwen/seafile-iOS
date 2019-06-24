//
//  SeafActivitiesCell.m
//  seafileApp
//
//  Created by three on 2019/6/9.
//  Copyright © 2019 Seafile. All rights reserved.
//

#import "SeafActivitiesCell.h"
#import <SDWebImage/UIImageView+WebCache.h>

@implementation SeafActivitiesCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code    
}

- (void)showWithImage:(NSURL *)imageURL author:(NSString *)author operation:(NSString *)operation time:(NSString *)time detail:(NSString *)detail repoName:(NSString *)repoName {
    
    self.accountImageView.layer.cornerRadius = 20.0f;
    self.accountImageView.clipsToBounds = YES;
    UIImage *defaultAccountImage = [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"account" ofType:@"png"]];
    [self.accountImageView sd_setImageWithURL:imageURL placeholderImage:defaultAccountImage];
    
    self.repoNameLabel.text = repoName;
    self.authorLabel.text = author;
    self.timeLabel.text = time;
    self.desLabel.text = detail;
    
    if (operation && operation.length > 0) {
        self.operationContainer.hidden = false;
        self.operationContainer.layer.cornerRadius = 3.0;
        self.operationContainer.layer.masksToBounds = true;
        self.operationLabel.text = operation;
    } else {
        self.operationContainer.hidden = true;
    }
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
