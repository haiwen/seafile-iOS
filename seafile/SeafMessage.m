//
//  SeafMessage.m
//  seafilePro
//
//  Created by Wang Wei on 3/14/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//
#import "JSMessagesViewController.h"

#import "SeafMessage.h"
#import "SeafBase.h"
#import "Utils.h"
#import "Debug.h"


#define FONT_SIZE 12.0f
#define AVATAR_OFFSET 0.0f
#define NAME_OFFSET (AVATAR_OFFSET+43+7)
#define RIGHT_MARGIN 2.0f
#define MSGLABEL_WIDTH(_w) ((_w) - NAME_OFFSET - RIGHT_MARGIN)

#define CELL_CONTENT_MARGIN 1.0f


@implementation SeafMessage


- (instancetype)initWithText:(NSString *)text
                       email:(NSString *)email
                      sender:(NSString *)sender
                        date:(NSDate *)date
                       msgId:(NSString *)msgId
                        conn:(SeafConnection *)conn

{
    SeafMessage *msg = [super initWithText:text sender:sender date:date];
    msg.email = email;
    msg.msgId = msgId;
    msg.nickname = sender;
    msg.replies = [[NSMutableArray alloc] init];
    self.connection = conn;
    return msg;
}

- (instancetype)initWithText:(NSString *)text
                       email:(NSString *)email
                        date:(NSDate *)date
                        conn:(SeafConnection *)conn
                        type:(int)type
{
    if (type == MSG_USER)
        return [self initWithText:text email:email sender:[conn nickForEmail:email] date:date msgId:nil conn:conn];
    else {
        SeafMessage *msg = [self initWithText:text email:email sender:nil date:date msgId:nil conn:conn];
        msg.nickname = [conn nickForEmail:email];
        return msg;
    }
}

- (instancetype)initWithGroupMsg:(NSDictionary *)dict
                            conn:(SeafConnection *)conn
{
    NSString *content = [dict objectForKey:@"msg"];
    NSString *email = [dict objectForKey:@"from_email"];
    NSString *nickname = [dict objectForKey:@"nickname"];
    long long timestamp = [[dict objectForKey:@"timestamp"] integerValue:0];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
    NSString *msgId = [dict objectForKey:@"msgid"];
    SeafMessage *msg = [self initWithText:content email:email sender:nil date:date msgId:msgId conn:conn];
    for (NSDictionary *r in [dict objectForKey:@"replies"]) {
        [msg.replies addObject:r];
    }
    msg.nickname = nickname;
    return msg;
}

- (instancetype)initWithUserMsg:(NSDictionary *)dict
                           conn:(SeafConnection *)conn
{
    NSString *content = [dict objectForKey:@"msg"];
    NSString *email = [dict objectForKey:@"from_email"];
    NSString *nickname = [dict objectForKey:@"nickname"];
    long long timestamp = [[dict objectForKey:@"timestamp"] integerValue:0];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
    NSString *msgId = [dict objectForKey:@"msgid"];
    return [self initWithText:content email:email sender:nickname date:date msgId:msgId conn:conn];
}

- (NSDictionary *)toDictionary
{
    NSString *timestamp = [NSString stringWithFormat:@"%d", (int)[self.date timeIntervalSince1970]];
    return [[NSDictionary alloc] initWithObjectsAndKeys:self.msgId, @"msgid", self.email, @"from_email", self.nickname, @"nickname", timestamp, @"timestamp", self.text, @"msg", self.replies, @"replies", nil];
}

#pragma mark - Table view delegate
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.replies.count;
}

- (CGFloat)heightForMsgReply:(NSDictionary *)reply width:(float)width
{
    CGSize s = [Utils textSizeForText:[reply objectForKey:@"msg"] font:[UIFont systemFontOfSize:FONT_SIZE] width:MSGLABEL_WIDTH(width)];
    return 45 + s.height - 15;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    NSDictionary *reply = [self.replies objectAtIndex:indexPath.row];
    return [self heightForMsgReply:reply width:tableView.frame.size.width];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UIImageView *imageView = nil;
    UILabel *nameLabel = nil;
    UILabel *msgLabel = nil;
    NSString *CellIdentifier = @"SeafReplyCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        cell.textLabel.textColor = BAR_COLOR;
        cell.backgroundColor = tableView.backgroundColor;
        
        imageView = [[UIImageView alloc] init];
        imageView.tag = 300;
        [cell.contentView addSubview:imageView];
        
        nameLabel = [[UILabel alloc] init];
        nameLabel.tag = 301;
        nameLabel.textColor = BAR_COLOR;
        nameLabel.font = [UIFont systemFontOfSize:14.0];
        [cell.contentView addSubview:nameLabel];
        
        msgLabel = [[UILabel alloc] init];
        msgLabel.tag = 302;
        msgLabel.numberOfLines = 0;
        msgLabel.font = [UIFont systemFontOfSize:FONT_SIZE];
        [cell.contentView addSubview:msgLabel];
    } else {
        imageView = (UIImageView *)[cell viewWithTag:300];
        nameLabel = (UILabel *)[cell viewWithTag:301];
        msgLabel = (UILabel *)[cell viewWithTag:302];
    }
    NSDictionary *reply = [self.replies objectAtIndex:indexPath.row];
    NSString *avatar = [self.connection avatarForEmail:[reply objectForKey:@"from_email"]];
    imageView.image = [JSAvatarImageFactory avatarImage:[UIImage imageWithContentsOfFile:avatar] croppedToCircle:YES];
    nameLabel.text = [reply objectForKey:@"nickname"];
    msgLabel.text = [reply objectForKey:@"msg"];
    float width = MSGLABEL_WIDTH(tableView.frame.size.width);
    CGSize s = [Utils textSizeForText:msgLabel.text font:msgLabel.font width:width];
    imageView.frame = CGRectMake(AVATAR_OFFSET, 3, 43.0, 43.0);
    nameLabel.frame = CGRectMake(NAME_OFFSET, 5, width, 22.0);
    msgLabel.frame = CGRectMake(NAME_OFFSET, 28.0, width, s.height);
    return cell;
}

- (CGFloat)neededHeightForReplies:(float)width
{
    float height = 0;
    for (NSDictionary *r in self.replies) {
        height += [self heightForMsgReply:r width:width] + 1;
    }
    return height;
}

@end
