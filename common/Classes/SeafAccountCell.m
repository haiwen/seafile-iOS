//
//  SeafAccountCell.m
//  seafile
//
//  Created by Wang Wei on 1/17/13.
//  Copyright (c) 2013 Seafile Ltd. All rights reserved.
//
#import "SeafAccountCell.h"
#import "Debug.h"
#import "SeafConnection.h"

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

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (highlighted) {
        self.contentView.backgroundColor = [UIColor lightGrayColor];
    } else {
        self.contentView.backgroundColor = [UIColor clearColor];
    }
}

+ (SeafAccountCell *)getInstance:(UITableView *)tableView WithOwner:(id)owner
{
    NSString *CellIdentifier = @"SeafAccountCell2";
    SeafAccountCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:@"SeafAccountCell" owner:owner options:nil];
        cell = [cells objectAtIndex:0];
    }
    cell.contentView.backgroundColor = [UIColor whiteColor];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)updateAccountCell:(SeafConnection *)conn {
    self.imageview.image = [UIImage imageWithContentsOfFile:conn.avatar];
    self.serverLabel.text = conn.address;
    self.emailLabel.text = conn.username;
    self.imageview.clipsToBounds = YES;
}

@end
