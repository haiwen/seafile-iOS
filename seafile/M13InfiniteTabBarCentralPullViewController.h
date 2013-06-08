//
//  M13InfiniteTabBarCentralPullViewController.h
//  M13InfiniteTabBar
/*
 Copyright (c) 2013 Brandon McQuilkin

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 One does not claim this software as ones own.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "M13PanGestureRecognizer.h"
@class M13InfiniteTabBarCentralPullViewController;

@protocol M13InfiniteTabBarCentralPullViewControllerDelegate <NSObject>

- (void)pullableView:(M13InfiniteTabBarCentralPullViewController *)pullableView didChangeState:(BOOL)isOpen;

@end

@interface M13InfiniteTabBarCentralPullViewController : UIView

//The handle of the pull view
@property (nonatomic, retain) UIView *handleView;

//Location of the center of the pull view in its super view when closed
@property (readwrite, assign) CGPoint closedCenter;

//Location of the center of the pull view in its super view when open
@property (readwrite, assign) CGPoint openCenter;

//Used to retreive the state of the view
@property (readonly, assign) BOOL isOpen;

//Gesture Recongizier
@property (nonatomic, retain) M13PanGestureRecognizer *panRecognizer;

//Duration of the animation when pulled open or closed, and the gesture is ended
@property (readwrite, assign) CGFloat animationDuration;

//Delegate to be notified about state changes
@property (nonatomic, retain) id<M13InfiniteTabBarCentralPullViewControllerDelegate> delegate;

//Toggle the state
- (void)setOpened:(BOOL)opened animated:(BOOL)animated;

//Drag
-(void)handleDrag:(UIPanGestureRecognizer *)sender;

@end
