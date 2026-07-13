//
//  SeafShareStarredViewController.h
//  SeafShare
//
//  Starred directory picker for share extension.
//  Aligned with Android StarredQuickFragment in select mode.
//

#import "SeafShareBaseListViewController.h"
@class SeafDir;

@interface SeafShareStarredViewController : SeafShareBaseListViewController

/// Returns the currently selected starred directory, or nil if nothing is selected.
- (SeafDir *)selectedDirectory;

@end
