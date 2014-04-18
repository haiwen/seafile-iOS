//
//  SeafMessageCellTableViewCell.m
//  seafilePro
//
//  Created by Wang Wei on 4/18/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import "SeafMessageCell.h"

@implementation SeafMessageCell
@synthesize imageView;
@synthesize textLabel;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
    }
    return self;
}

- (void)awakeFromNib
{
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
