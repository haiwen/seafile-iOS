//
//  SeafUploadFileCell.m
//  seafile
//
//  Created by Wang Wei on 10/20/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafUploadingFileCell.h"
#import "Debug.h"

@implementation SeafUploadingFileCell

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

- (void) layoutSubviews
{
    CGRect r = self.imageView.frame;
    Debug(">>>>%f %f %f %f", r.origin.x, r.origin.y, r.size.width, r.size.height);

}

@end
