//
//  M13InfiniteTabBar.h
//  M13InfiniteTabBar
/*
 Copyright (c) 2013 Brandon McQuilkin

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 One does not claim this software as ones own.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import <UIKit/UIKit.h>

@class M13InfiniteTabBarController;
@class M13InfiniteTabBar;
@class M13InfiniteTabBarItem;

@protocol M13InfiniteTabBarDelegate <NSObject>

//Requiered Method
- (void)infiniteTabBar:(M13InfiniteTabBar *)tabBar didSelectItem:(M13InfiniteTabBarItem *)item;

//Suggested Method
- (BOOL)infiniteTabBar:(M13InfiniteTabBar *)tabBar shouldSelectItem:(M13InfiniteTabBarItem *)item;

//Method to run animations in sequence with M13InfiniteTabBarController
- (void)infiniteTabBar:(M13InfiniteTabBar *)tabBar animateInViewControllerForItem:(M13InfiniteTabBarItem *)item;

@end

@interface M13InfiniteTabBar : UIScrollView <UIScrollViewDelegate, UIGestureRecognizerDelegate>

- (id)initWithInfiniteTabBarItems:(NSArray *)items;

//delegate
@property (nonatomic, retain) id<M13InfiniteTabBarDelegate> tabBarDelegate;

//Selected Item
@property (nonatomic, retain) M13InfiniteTabBarItem *selectedItem;
- (void)rotateItemsToOrientation:(UIDeviceOrientation)orientation;

@end
