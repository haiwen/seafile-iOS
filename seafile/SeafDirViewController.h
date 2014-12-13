//
//  SeafUploadDirVontrollerViewController.h
//  seafile
//
//  Created by Wang Wei on 10/20/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "SeafDir.h"

@protocol SeafDirDelegate <NSObject>
- (void)chooseDir:(UIViewController *)c dir:(SeafDir *)dir;
- (void)cancelChoose:(UIViewController *)c;

@end

@interface SeafDirViewController : UITableViewController

- (id)initWithSeafDir:(SeafDir *)dir delegate:(id<SeafDirDelegate>)delegate chooseRepo:(BOOL)chooseRepo;

@end
