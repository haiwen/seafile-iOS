//
//  SeafShareRecentViewController.h
//  SeafShare
//
//  Recently used directories for share extension.
//  Shows paths where user has previously uploaded files.
//

#import "SeafShareBaseListViewController.h"
@class SeafDir;

@interface SeafShareRecentViewController : SeafShareBaseListViewController

/// Returns the currently selected recent directory, or nil if nothing is selected.
- (SeafDir *)selectedDirectory;

@end
