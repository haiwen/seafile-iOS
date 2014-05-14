//
//  SeafMessage.m
//  seafilePro
//
//  Created by Wang Wei on 3/14/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//
#import "JSAvatarImageFactory.h"

#import "SeafMessage.h"
#import "SeafBase.h"
#import "FileMimeType.h"
#import "UIImage+FileType.h"
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
    NSString *content = [[dict objectForKey:@"msg"] stringByAppendingString:@"\n\n"];
    NSString *email = [dict objectForKey:@"from_email"];
    NSString *nickname = [dict objectForKey:@"nickname"];
    long long timestamp = [[dict objectForKey:@"timestamp"] integerValue:0];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
    NSString *msgId = [dict objectForKey:@"msgid"];
    SeafMessage *msg = [self initWithText:content email:email sender:nil date:date msgId:msgId conn:conn];
    for (NSDictionary *r in [dict objectForKey:@"replies"]) {
        [msg.replies addObject:r];
    }
    NSMutableArray *atts = [[NSMutableArray alloc] init];
    for (NSDictionary *r in [dict objectForKey:@"atts"]) {
        [atts addObject:r];
    }
    msg.atts = atts;
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

- (BOOL)hasAtts
{
    return self.atts && self.atts.count > 0;
}

- (BOOL)hasReplies
{
    return self.replies && self.replies.count > 0;
}

- (NSDictionary *)toDictionary
{
    NSString *timestamp = [NSString stringWithFormat:@"%d", (int)[self.date timeIntervalSince1970]];
     NSMutableDictionary *dict =  [[NSMutableDictionary alloc] initWithObjectsAndKeys:self.msgId, @"msgid", self.email, @"from_email", self.nickname, @"nickname", timestamp, @"timestamp", self.text, @"msg", self.replies, @"replies", nil];
    if (self.replies && self.replies.count > 0)
        [dict setObject:self.replies forKey:@"replies"];
    if (self.atts && self.atts.count > 0)
        [dict setObject:self.atts forKey:@"atts"];
    return dict;
}

#pragma mark - Table view delegate
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self hasAtts] ? 2 :1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0 && [self hasAtts])
        return self.atts.count;
    return self.replies.count;
}

- (CGFloat)heightForMsgReply:(NSDictionary *)reply width:(float)width
{
    CGSize s = [Utils textSizeForText:[reply objectForKey:@"msg"] font:[UIFont systemFontOfSize:FONT_SIZE] width:MSGLABEL_WIDTH(width)];
    return 45 + s.height - 15 +5;
}
- (CGFloat)heightForMsgAtt:(NSDictionary *)att width:(float)width
{
    return 22;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if ([self hasAtts] && indexPath.section == 0) {
        NSDictionary *att = [self.atts objectAtIndex:indexPath.row];
        return [self heightForMsgAtt:att width:tableView.frame.size.width];
    }
    NSDictionary *reply = [self.replies objectAtIndex:indexPath.row];
    return [self heightForMsgReply:reply width:tableView.frame.size.width];
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (![self hasReplies])
        return nil;
    if (([self hasAtts] && [self hasReplies] && section == 1) || (![self hasAtts] && section == 0)) {
        UIView *lineView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, tableView.frame.size.width, 1.0f)];
        [lineView setBackgroundColor:[UIColor lightGrayColor]];
        return lineView;
    }
    return nil;
}
- (UITableViewCell *)getAttCell:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UIImageView *imageView = nil;
    UILabel *nameLabel = nil;
    NSString *CellIdentifier = @"SeafAttCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        cell.backgroundColor = tableView.backgroundColor;

        imageView = [[UIImageView alloc] init];
        imageView.tag = 400;
        [cell.contentView addSubview:imageView];

        nameLabel = [[UILabel alloc] init];
        nameLabel.tag = 401;
        nameLabel.textColor = BAR_COLOR;
        nameLabel.font = [UIFont systemFontOfSize:12.0];
        [cell.contentView addSubview:nameLabel];
    } else {
        imageView = (UIImageView *)[cell viewWithTag:400];
        nameLabel = (UILabel *)[cell viewWithTag:401];
    }

    NSDictionary *att = [self.atts objectAtIndex:indexPath.row];
    NSString *name = [[att objectForKey:@"path"] lastPathComponent];
    NSString *mime = [FileMimeType mimeType:name];
    imageView.image = [UIImage imageForMimeType:mime ext:name.pathExtension.lowercaseString];
    nameLabel.text = name;
    float width = MSGLABEL_WIDTH(tableView.frame.size.width);
    imageView.frame = CGRectMake(AVATAR_OFFSET, 2, 18.0, 18.0);
    nameLabel.frame = CGRectMake(25, 2, width, 18.0);
    return cell;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self hasAtts] && indexPath.section == 0) {
        return [self getAttCell:tableView cellForRowAtIndexPath:indexPath];
    }
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
    nameLabel.frame = CGRectMake(NAME_OFFSET, 3, width, 22.0);
    msgLabel.frame = CGRectMake(NAME_OFFSET, 25.0, width, s.height);
    return cell;
}

- (CGFloat)neededHeightForReplies:(float)width
{
    float height = 0;
    for (NSDictionary *r in self.replies) {
        height += [self heightForMsgReply:r width:width] + 1;
    }
    for (NSDictionary *a in self.atts) {
        height += [self heightForMsgAtt:a width:width] + 1;
    }
    if (height > 0) {
        height += 5;
    }
    return height;
}

@end
