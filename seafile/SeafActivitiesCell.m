//
//  SeafActivitiesCell.m
//  seafileApp
//
//  Created by three on 2019/6/9.
//  Copyright © 2019 Seafile. All rights reserved.
//

#import "SeafActivitiesCell.h"
#import <SDWebImage/UIImageView+WebCache.h>
#import "SeafTheme.h"

@implementation SeafActivitiesCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Set text colors
    self.authorLabel.textColor = [SeafTheme primaryText];
    // desLabel color is now driven by NSAttributedString from the model
    self.timeLabel.textColor = [SeafTheme secondaryText];
    self.repoNameLabel.textColor = BAR_COLOR_ORANGE;

    self.operationLabel.textColor = [SeafTheme operationText];
    self.operationContainer.backgroundColor = [UIColor colorWithRed:238.0/255.0 green:238.0/255.0 blue:238.0/255.0 alpha:1.0];
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
