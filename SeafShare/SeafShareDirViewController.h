//
//  SeafShareDirViewController.h
//  seafilePro
//
//  Created by three on 2018/8/2.
//  Copyright © 2018年 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>
@class SeafDir;

@interface SeafShareDirViewController : UIViewController

/// When YES, hides the toolbar OK button and new-folder button.
/// The parent container (SeafShareDestinationViewController) manages those.
@property (nonatomic, assign) BOOL browseOnly;

/// When YES, uses SeafCell / SeafDirCell with card-style list UI,
/// matching the main app's SeafFileViewController visual style.
@property (nonatomic, assign) BOOL useDestinationStyle;

/// The currently displayed directory. Use this to get the selected dir in browseOnly mode.
@property (nonatomic, readonly) SeafDir *currentDirectory;

- (id)initWithSeafDir:(SeafDir *)directory;

@end
