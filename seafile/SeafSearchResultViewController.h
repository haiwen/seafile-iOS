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

@class SeafDir;
@class SeafFile;
@class SeafConnection;
@class SeafFileViewController;
@class SeafCell;

@interface SeafSearchResultViewController : UIViewController <UISearchResultsUpdating>

@property (nonatomic, strong) SeafDir *directory;
@property (nonatomic, strong) SeafConnection *connection;
@property (weak, nonatomic) SeafFileViewController *masterVC;

- (void)searchWithText:(NSString *)text;
- (SeafCell *)getEntryCell:(id)entry;

@end

NS_ASSUME_NONNULL_END
