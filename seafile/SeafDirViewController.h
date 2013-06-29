//
//  SeafUploadDirVontrollerViewController.h
//  seafile
//
//  Created by Wang Wei on 10/20/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafDir.h"

@protocol SeafDirDelegate <NSObject>
- (void)chooseDir:(SeafDir *)dir;
@end

@interface SeafDirViewController : UITableViewController

- (id)initWithSeafDir:(SeafDir *)dir delegate:(id<SeafDirDelegate>)delegate;

@end
