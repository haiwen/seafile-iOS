//
//  SeafActionDirViewController.h
//  seafilePro
//
//  Created by Wang Wei on 08/12/2016.
//  Copyright © 2016 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SeafDir.h"
#import "SeafUploadFile.h"

@interface SeafActionDirViewController : UITableViewController

- (id)initWithSeafDir:(SeafDir *)directory file:(SeafUploadFile *)ufile;

@end
