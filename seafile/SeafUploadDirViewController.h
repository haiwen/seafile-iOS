//
//  SeafUploadDirVontrollerViewController.h
//  seafile
//
//  Created by Wang Wei on 10/20/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafDir.h"
#import "SeafPreView.h"

@interface SeafUploadDirViewController : UIViewController

- (id)initWithSeafConnection:(SeafConnection *)conn uploadFile:(id<SeafPreView>) ufile;

@end
