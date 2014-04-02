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
    Debug("reply count=%ld", (unsigned long)self.replies.count);
    return self.replies.count;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 20;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafReplyCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }
    NSDictionary *reply = [self.replies objectAtIndex:indexPath.row];
    NSString *nickname = [reply objectForKey:@"nickname"];
    cell.textLabel.text = [NSString stringWithFormat:@"%@: %@", nickname, [reply objectForKey:@"msg"]];
    cell.textLabel.font = [UIFont boldSystemFontOfSize:12.0f];
    cell.textLabel.textColor = [UIColor colorWithRed:0.533f green:0.573f blue:0.647f alpha:1.0f];
    cell.textLabel.backgroundColor = [UIColor clearColor];

    cell.backgroundColor = tableView.backgroundColor;
    return cell;
}

@end
