//
//  SeafMessage.h
//  seafilePro
//
//  Created by Wang Wei on 3/14/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import "JSMessage.h"
#import "SeafConnection.h"

#define REPLIES_HEADER_HEIGHT 20.f

@interface SeafMessage : JSMessage<UITableViewDelegate, UITableViewDataSource>

@property CGFloat repliesHeight;

@property NSString *msgId;
@property NSString *email;
@property NSString *nickname;

@property NSMutableArray *replies;

- (instancetype)initWithText:(NSString *)text
                       email:(NSString *)email
                      sender:(NSString *)sender
                        date:(NSDate *)date
                       msgId:(NSString *)msgId;


- (instancetype)initWithText:(NSString *)text
                       email:(NSString *)email
                        date:(NSDate *)date
                        conn:(SeafConnection *)conn
                        type:(int)type;

- (instancetype)initWithGroupMsg:(NSDictionary *)dict
                            conn:(SeafConnection *)conn;
- (instancetype)initWithUserMsg:(NSDictionary *)dict
                           conn:(SeafConnection *)conn;

- (NSDictionary *)toDictionary;

- (CGFloat)neededHeightForReplies:(float)width;

@end
