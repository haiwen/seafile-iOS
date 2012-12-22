//
//  SeafUploadDirVontrollerViewController.h
//  seafile
//
//  Created by Wang Wei on 10/20/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "InputAlertPrompt.h"
#import "SeafDir.h"

@interface SeafUploadDirViewController : UITableViewController<SeafDentryDelegate, InputDoneDelegate, UIAlertViewDelegate>

@property (strong, readonly) SeafDir *directory;

- (id)initWithSeafDir:(SeafDir *)dir;

@end
