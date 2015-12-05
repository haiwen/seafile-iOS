//
//  SeafStarredFilesViewController.h
//  seafile
//
//  Created by Wang Wei on 11/4/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafConnection.h"
#import "SeafStarredFile.h"


@interface SeafStarredFilesViewController : UITableViewController<SeafStarFileDelegate, SeafFileUpdateDelegate, SeafDentryDelegate>

@property (strong, nonatomic) SeafConnection *connection;

- (void)refreshView;
- (void)selectFile:(SeafStarredFile *)sfile;

@end
