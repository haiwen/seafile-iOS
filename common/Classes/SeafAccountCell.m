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
#import "SeafStorage.h"

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
    // Server label show user name
    self.serverLabel.text = conn.name;
    // Email label show server address
    self.emailLabel.text = conn.address;

    // Round avatar
    self.imageview.clipsToBounds = YES;
    self.imageview.layer.cornerRadius = self.imageview.frame.size.height / 2.0;
    self.imageview.layer.masksToBounds = YES;
    self.checkImageView.hidden = YES;

    NSString *defaultServer = [SeafStorage.sharedObject objectForKey:@"DEAULT-SERVER"];
    NSString *defaultUser = [SeafStorage.sharedObject objectForKey:@"DEAULT-USER"];
    BOOL isSelected = ([conn.address isEqualToString:defaultServer] && [conn.username isEqualToString:defaultUser]);
    
    if (isSelected) {
        self.checkImageView.hidden = NO;
    }
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    // Ensure avatar stays circular when cell size changes
    self.imageview.layer.cornerRadius = self.imageview.bounds.size.height / 2.0;
    self.imageview.layer.masksToBounds = YES;

    // Adjust label vertical positions only once to avoid cumulative shifts on multiple layout passes
    if (!self.framesAdjusted) {
        CGRect nameFrame = self.serverLabel.frame;
        nameFrame.origin.y += 2.0; // move down 2pt
        self.serverLabel.frame = nameFrame;

        CGRect addrFrame = self.emailLabel.frame;
        addrFrame.origin.y -= 1.0; // move up 1pt
        self.emailLabel.frame = addrFrame;

        self.framesAdjusted = YES;
    }
}

@end
