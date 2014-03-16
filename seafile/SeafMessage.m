//
//  SeafMessage.m
//  seafilePro
//
//  Created by Wang Wei on 3/14/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import "SeafMessage.h"
#import "SeafBase.h"

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
    return msg;
}

- (instancetype)initWithText:(NSString *)text
                       email:(NSString *)email
                        date:(NSDate *)date
                        conn:(SeafConnection *)conn
{
    return [self initWithText:text email:email sender:[conn nickForEmail:email] date:date msgId:nil];
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
    return [self initWithText:content email:email sender:nickname date:date msgId:msgId];
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
    return [[NSDictionary alloc] initWithObjectsAndKeys:self.msgId, @"msgid", self.email, @"from_email", self.sender, @"nickname", timestamp, @"timestamp", self.text, @"msg", nil];
}

@end
