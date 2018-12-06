//
//  SeafSearchResultViewController.h
//  seafileApp
//
//  Created by three on 2018/12/4.
//  Copyright © 2018 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafDir.h"
#import "SeafFile.h"

NS_ASSUME_NONNULL_BEGIN

@interface SeafSearchResultViewController : UIViewController <UISearchResultsUpdating>

@property (strong, nonatomic) SeafConnection *connection;

@property (strong, nonatomic) SeafDir *directory;

@end

NS_ASSUME_NONNULL_END
