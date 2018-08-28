//
//  SeafAccountCell.h
//  seafile
//
//  Created by Wang Wei on 1/17/13.
//  Copyright (c) 2013 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
@class SeafConnection;

@interface SeafAccountCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UILabel *serverLabel;
@property (strong, nonatomic) IBOutlet UILabel *emailLabel;
@property (strong, nonatomic) IBOutlet UIImageView *imageview;

+ (SeafAccountCell *)getInstance:(UITableView *)tableView WithOwner:(id)owner;
- (void)updateAccountCell:(SeafConnection *)conn;
@end
