//
//  SeafSceneDelegate.h
//  seafile
//
//  Copyright (c) 2026 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

/// Delegate of the app's single window scene. Forwards scene lifecycle and URL
/// events to SeafAppDelegate, which still owns the app's UI state.
@interface SeafSceneDelegate : UIResponder <UIWindowSceneDelegate>

@property (strong, nonatomic) UIWindow *window;

@end
