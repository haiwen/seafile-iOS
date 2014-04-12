//
//  SeafAvatar.h
//  seafilePro
//
//  Created by Wang Wei on 4/11/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SeafConnection.h"

@interface SeafUserAvatar : NSObject<SeafDownloadDelegate>
- (id)initWithConnection:(SeafConnection *)aConnection username:(NSString *)username;

+ (NSString *)pathForUserAvatar:(SeafConnection *)conn username:(NSString *)username;

@end
