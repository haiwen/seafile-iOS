//
//  SeafSceneDelegate.m
//  seafile
//
//  Copyright (c) 2026 Seafile Ltd. All rights reserved.
//

#import "SeafSceneDelegate.h"
#import "SeafAppDelegate.h"

@implementation SeafSceneDelegate

- (SeafAppDelegate *)appDelegate
{
    return (SeafAppDelegate *)UIApplication.sharedApplication.delegate;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
{
    if (![scene isKindOfClass:[UIWindowScene class]])
        return;
    [self.appDelegate sceneDidConnectWithWindow:self.window options:connectionOptions];
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts
{
    for (UIOpenURLContext *context in URLContexts) {
        [self.appDelegate handleOpenURL:context.URL];
    }
}

- (void)sceneDidBecomeActive:(UIScene *)scene
{
    [self.appDelegate sceneDidBecomeActive];
}

- (void)sceneWillEnterForeground:(UIScene *)scene
{
    [self.appDelegate sceneWillEnterForeground];
}

- (void)sceneDidEnterBackground:(UIScene *)scene
{
    [self.appDelegate sceneDidEnterBackground];
}

@end
