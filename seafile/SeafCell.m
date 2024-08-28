//
//  SeafCell.m
//  seafile
//
//  Created by Wang Wei on 1/19/13.
//  Copyright (c) 2013 Seafile Ltd. All rights reserved.
//

#import "SeafCell.h"

@implementation SeafCell
@synthesize imageView;
@synthesize textLabel;
@synthesize detailTextLabel;
@synthesize progressView;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        // Initialization code
    }
    return self;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)reset
{
    self.detailTextLabel.text = nil;
    self.detailTextLabel.textColor = [UIColor colorWithRed:0.666667 green:0.666667 blue:0.666667 alpha:1];
    self.badgeImage.hidden = true;
    self.badgeLabel.hidden = true;
    self.cacheStatusView.hidden = true;
    self.progressView.hidden = true;
    self.imageView.image = nil;
}

- (IBAction)moreButtonTouch:(id)sender {
    if (self.moreButtonBlock) {
        self.moreButtonBlock(self.cellIndexPath);
    }
}
@end
