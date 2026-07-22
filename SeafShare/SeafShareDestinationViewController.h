//
//  SeafShareDestinationViewController.h
//  SeafShare
//
//  Destination picker for Share Extension.
//  Reuses the design of SeafDestinationPickerViewController (move file page):
//  - Tabs bar with UIStackView + orange underline
//  - Card container with 16pt rounded corners
//  - Fixed return header
//  - Dual rounded buttons in bottom bar
//
//  Tabs aligned with Android VersatileShareToSeafileSelectorActivity:
//  - Libraries (browse repos/dirs)
//  - Starred (tap jumps into Libraries at that path)
//  - Recent (select recently used dirs)
//

#import <UIKit/UIKit.h>
@class SeafConnection;

@interface SeafShareDestinationViewController : UIViewController

- (instancetype)initWithConnection:(SeafConnection *)connection;

/// Optionally pre-navigate to a remembered path
- (instancetype)initWithConnection:(SeafConnection *)connection repoId:(NSString *)repoId path:(NSString *)path;

/// Returns the last used path info (account, repoId, path) or nil
+ (NSDictionary *)lastUsedPathInfo;

@end
