//
//  SeafShareRecentViewController.h
//  SeafShare
//
//  Recently used directories for share extension.
//  Shows paths where user has previously uploaded files.
//

#import <UIKit/UIKit.h>
@class SeafConnection;
@class SeafDir;

@interface SeafShareRecentViewController : UIViewController

- (instancetype)initWithConnection:(SeafConnection *)connection;

/// Returns the currently selected recent directory, or nil if nothing is selected.
- (SeafDir *)selectedDirectory;

@end
