//
//  SeafItem.h
//  seafilePro
//
//  Created by Wang Wei on 10/16/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SeafItem <NSObject>

- (void)setDelegate:(id)delegate;
- (NSString *)name;

@end
