//
//  SeafShareStarredViewController.h
//  SeafShare
//
//  Starred directory picker for share extension.
//  Aligned with Android StarredQuickFragment in select mode.
//

#import <UIKit/UIKit.h>
@class SeafConnection;
@class SeafDir;

@interface SeafShareStarredViewController : UIViewController

- (instancetype)initWithConnection:(SeafConnection *)connection;

/// Returns the currently selected starred directory, or nil if nothing is selected.
- (SeafDir *)selectedDirectory;

@end
