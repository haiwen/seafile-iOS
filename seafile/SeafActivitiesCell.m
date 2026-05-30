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
    // Set text colors
    self.authorLabel.textColor = [UIColor blackColor];
    // desLabel color is now driven by NSAttributedString from the model
    self.timeLabel.textColor = [UIColor grayColor];
    self.repoNameLabel.textColor = BAR_COLOR_ORANGE;
    
    // Set operation label and container colors
    self.operationLabel.textColor = [UIColor darkGrayColor];
    self.operationContainer.backgroundColor = [[UIColor lightGrayColor] colorWithAlphaComponent:0.2];
}

- (void)showWithImage:(NSURL *)imageURL author:(NSString *)author operation:(NSString *)operation time:(NSString *)time attributedDetail:(NSAttributedString *)attributedDetail repoName:(NSString *)repoName {
    
    self.accountImageView.layer.cornerRadius = 20.0f;
    self.accountImageView.clipsToBounds = YES;
    UIImage *defaultAccountImage = [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"account" ofType:@"png"]];
    [self.accountImageView sd_setImageWithURL:imageURL placeholderImage:defaultAccountImage];
    
    self.repoNameLabel.text = repoName;
    self.authorLabel.text = author;
    self.timeLabel.text = time;
    self.desLabel.attributedText = attributedDetail;
    
    if (operation && operation.length > 0) {
        self.operationContainer.hidden = NO;
        self.operationLabel.hidden = NO;
        self.operationContainer.layer.cornerRadius = 3.0;
        self.operationContainer.layer.masksToBounds = YES;
        self.operationLabel.text = operation;
    } else {
        self.operationContainer.hidden = YES;
        self.operationLabel.hidden = YES;
        self.operationLabel.text = @"";
    }
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
