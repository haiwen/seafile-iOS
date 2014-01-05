//
//  StartViewController.h
//  seafile
//
//  Created by Wang Wei on 8/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "SeafConnection.h"
#import "ColorfulButton.h"


@interface StartViewController : UITableViewController<UIActionSheetDelegate>

@property (retain) NSMutableArray *conns;


- (void)saveAccount:(SeafConnection *)conn;
- (BOOL)selectAccount:(SeafConnection *)conn;
- (BOOL)goToDefaultAccount;

- (SeafConnection *)getConnection:(NSString *)url username:(NSString *)username;
- (BOOL)gotoAccount:(NSString *)username server:(NSString *)server;

@end
