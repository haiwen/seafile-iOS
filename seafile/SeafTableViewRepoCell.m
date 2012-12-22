//
//  SeafTableViewRepoCell.m
//  seafile
//
//  Created by Wang Wei on 8/29/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafTableViewRepoCell.h"

@implementation SeafTableViewRepoCell
@synthesize mimeImage;
@synthesize nameLabel;
@synthesize mtimeLabel;
@synthesize sizeLabel;
@synthesize descLabel;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
    }
    return self;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];
    // Configure the view for the selected state
}

@end
