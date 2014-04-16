//
//  SeafDisDetailViewController.h
//  Discussion
//
//  Created by Wang Wei on 5/21/13.
//  Copyright (c) 2013 Wang Wei. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafConnection.h"
#import "JSMessagesViewController.h"
#import "SeafMessage.h"

@interface SeafDisDetailViewController : JSMessagesViewController <UISplitViewControllerDelegate>

@property (strong, nonatomic) SeafConnection *connection;
@property (readonly, strong, nonatomic) NSMutableDictionary *info;
@property (readonly, nonatomic) int msgtype;

- (void)setMsgtype:(int)msgtype info:(NSMutableDictionary *)info;

@end
