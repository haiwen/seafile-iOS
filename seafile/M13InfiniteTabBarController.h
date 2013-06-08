//
//  M13InfiniteTabBarController.h
//  M13InfiniteTabBar
//
/*
 Copyright (c) 2013 Brandon McQuilkin

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 One does not claim this software as ones own.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import <UIKit/UIKit.h>
#import "M13InfiniteTabBar.h"
#import "M13InfiniteTabBarCentralPullNotificationBackgroundView.h"
#import "M13InfiniteTabBarCentralPullViewController.h"
@class M13InfiniteTabBarController;

@protocol M13InfiniteTabBarControllerDelegate <NSObject>

//delegate protocols
- (BOOL)infiniteTabBarController:(M13InfiniteTabBarController *)tabBarController shouldSelectViewContoller:(UIViewController *)viewController;
- (void)infiniteTabBarController:(M13InfiniteTabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController;

@end

@interface M13InfiniteTabBarController : UIViewController <M13InfiniteTabBarDelegate, M13InfiniteTabBarCentralPullViewControllerDelegate>

- (id)initWithViewControllers:(NSArray *)viewControllers pairedWithInfiniteTabBarItems:(NSArray *)items;

@property (nonatomic, retain) id<M13InfiniteTabBarControllerDelegate> delegate; //Delegate
@property (nonatomic, readonly) M13InfiniteTabBar *infiniteTabBar; //Infinite tab bar

@property (nonatomic, readonly) NSArray *viewControllers;
@property (nonatomic, assign) UIViewController *selectedViewController;
@property (nonatomic) NSUInteger selectedIndex;

- (void)setSelectedIndex:(NSUInteger)selectedIndex;
- (void)setSelectedViewController:(UIViewController *)selectedViewController;

//Central View controller is shown by dragging up on the tab bar
@property (nonatomic, retain) UIViewController *centralViewController;
@property (nonatomic, readonly) BOOL isCentralViewControllerOpen;
- (void)showAlertForCentralViewControllerIsEmergency:(BOOL)emergency;
- (void)setCentralViewControllerOpened:(BOOL)opened animated:(BOOL)animated;
- (void)endAlertAnimation;

//Delegate
- (void)infiniteTabBar:(M13InfiniteTabBar *)tabBar didSelectItem:(M13InfiniteTabBarItem *)item;
- (void)infiniteTabBar:(M13InfiniteTabBar *)tabBar animateInViewControllerForItem:(M13InfiniteTabBarItem *)item;
- (BOOL)infiniteTabBar:(M13InfiniteTabBar *)tabBar shouldSelectItem:(M13InfiniteTabBarItem *)item;

//Appearance
@property (nonatomic, retain) UIColor *tabBarBackgroundColor UI_APPEARANCE_SELECTOR; //Solid unmoving background color of tab bar

@property (nonatomic, retain) M13InfiniteTabBarCentralPullNotificationBackgroundView *pullNotificatonBackgroundView; //BackgroundView to alert users to a change in the central view controller

@end
