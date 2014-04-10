//
//  SeafMessage.m
//  seafilePro
//
//  Created by Wang Wei on 3/14/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import "SeafMessage.h"
#import "SeafBase.h"
#import "Debug.h"


#define FONT_SIZE 12.0f
#define CELL_CONTENT_WIDTH 320.0f
#define CELL_CONTENT_MARGIN 1.0f


@implementation SeafMessage


- (instancetype)initWithText:(NSString *)text
                       email:(NSString *)email
                      sender:(NSString *)sender
                        date:(NSDate *)date
                       msgId:(NSString *)msgId
{
    SeafMessage *msg = [super initWithText:text sender:sender date:date];
    msg.email = email;
    msg.msgId = msgId;
    msg.nickname = sender;
    msg.replies = [[NSMutableArray alloc] init];
    return msg;
}

- (instancetype)initWithText:(NSString *)text
                       email:(NSString *)email
                        date:(NSDate *)date
                        conn:(SeafConnection *)conn
                        type:(int)type
{
    if (type == MSG_USER)
        return [self initWithText:text email:email sender:[conn nickForEmail:email] date:date msgId:nil];
    else {
        SeafMessage *msg = [self initWithText:text email:email sender:nil date:date msgId:nil];
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
    SeafMessage *msg = [self initWithText:content email:email sender:nil date:date msgId:msgId];
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
    return [self initWithText:content email:email sender:nickname date:date msgId:msgId];
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
    NSString *nickname = [reply objectForKey:@"nickname"];
    NSString *text = [NSString stringWithFormat:@"%@: %@", nickname, [reply objectForKey:@"msg"]];

    CGSize constraint = CGSizeMake(width - (CELL_CONTENT_MARGIN * 2), 20000.0f);
    CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:FONT_SIZE] constrainedToSize:constraint lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat height = MAX(size.height, 20.0f - (CELL_CONTENT_MARGIN * 2));
    return height + (CELL_CONTENT_MARGIN * 2);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    NSDictionary *reply = [self.replies objectAtIndex:indexPath.row];
    return [self heightForMsgReply:reply width:tableView.frame.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UILabel *label = nil;
    NSString *CellIdentifier = @"SeafReplyCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];

        label = [[UILabel alloc] initWithFrame:CGRectZero];
        [label setLineBreakMode:NSLineBreakByWordWrapping];
        [label setNumberOfLines:0];
        [label setFont:[UIFont systemFontOfSize:FONT_SIZE]];
        [label setTag:1];
        label.backgroundColor = [UIColor clearColor];
        label.textColor = [UIColor colorWithRed:0.533f green:0.573f blue:0.647f alpha:1.0f];
        [[cell contentView] addSubview:label];
    } else
        label = (UILabel*)[cell viewWithTag:1];

    NSDictionary *reply = [self.replies objectAtIndex:indexPath.row];
    NSString *nickname = [reply objectForKey:@"nickname"];
    NSString *text = [NSString stringWithFormat:@"%@: %@", nickname, [reply objectForKey:@"msg"]];
    NSMutableAttributedString *atext = [[NSMutableAttributedString alloc] initWithString:text];
    NSDictionary *attr = [[NSDictionary alloc] initWithObjectsAndKeys:[UIColor blueColor], NSForegroundColorAttributeName, nil];
    [atext setAttributes:attr range:NSMakeRange(0, nickname.length + 2)];
    attr = [[NSDictionary alloc] initWithObjectsAndKeys:[UIColor darkGrayColor], NSForegroundColorAttributeName, nil];
    [atext setAttributes:attr range:NSMakeRange(nickname.length + 2, text.length - nickname.length - 2)];
    CGSize constraint = CGSizeMake(tableView.frame.size.width - (CELL_CONTENT_MARGIN * 2), 20000.0f);
    CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:FONT_SIZE] constrainedToSize:constraint lineBreakMode:NSLineBreakByWordWrapping];
    label.attributedText = atext;
    label.frame = CGRectMake(CELL_CONTENT_MARGIN, CELL_CONTENT_MARGIN, tableView.frame.size.width - (CELL_CONTENT_MARGIN*2), MAX(size.height, 20.0f - (CELL_CONTENT_MARGIN * 2)));

    cell.backgroundColor = tableView.backgroundColor;
    return cell;
}

- (CGFloat)neededHeightForReplies:(float)width
{
    float height = REPLIES_HEADER_HEIGHT;
    for (NSDictionary *r in self.replies) {
        height += [self heightForMsgReply:r width:width];
    }
    return height;
}

@end
