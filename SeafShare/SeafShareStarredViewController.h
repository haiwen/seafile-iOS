//
//  SeafShareStarredViewController.h
//  SeafShare
//
//  Starred directory list for share extension.
//  Tapping a library/folder navigates into Libraries (via directoryTapHandler).
//

#import "SeafShareBaseListViewController.h"
@class SeafDir;

typedef void (^SeafShareStarredDirectoryTapHandler)(SeafDir *dir);

@interface SeafShareStarredViewController : SeafShareBaseListViewController

/// Called when the user taps a starred library or directory.
@property (nonatomic, copy) SeafShareStarredDirectoryTapHandler directoryTapHandler;

/// Always returns nil — Starred is browse-to-Libraries, not a selection source.
- (SeafDir *)selectedDirectory;

@end
