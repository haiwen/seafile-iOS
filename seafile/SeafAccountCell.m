//
//  SeafAccountCell.m
//  seafile
//
//  Created by Wang Wei on 1/17/13.
//  Copyright (c) 2013 Seafile Ltd. All rights reserved.
//
#import "SeafAccountCell.h"
#import "Debug.h"

@implementation SeafAccountCell

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

- (void)setFrame:(CGRect)frame
{
    int width = MIN(340, frame.size.width);
    float inset = (frame.size.width - width)/2;
    frame.origin.x += inset;
    frame.size.width = width;
    [super setFrame:frame];
}

+ (SeafAccountCell *)getInstance:(UITableView *)tableView WithOwner:(id)owner
{
    NSString *CellIdentifier = @"SeafAccountCell";
    SeafAccountCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:@"SeafAccountCell" owner:owner options:nil];
        cell = [cells objectAtIndex:0];
    }
    cell.contentView.backgroundColor = [UIColor whiteColor];
    cell.accessoryType = UITableViewCellAccessoryNone;
    //cell.selectionStyle = UITableViewCellSelectionStyleGray;
    return cell;
}

@end
