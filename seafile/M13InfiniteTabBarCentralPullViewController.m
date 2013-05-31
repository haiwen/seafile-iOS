//
//  M13InfiniteTabBarCentralPullViewController.m
//  M13InfiniteTabBar
/*
 Copyright (c) 2013 Brandon McQuilkin
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 One does not claim this software as ones own.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import "M13InfiniteTabBarCentralPullViewController.h"

@interface M13InfiniteTabBarCentralPullViewController ()

@property (readwrite, assign) BOOL isOpen;

@end

@implementation M13InfiniteTabBarCentralPullViewController
{
    //Used for math
    CGPoint _startPosition;
    CGPoint _minPosition;
    CGPoint _maxPosition;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        //General properties
        _animationDuration = 0.2;
        self.exclusiveTouch = NO;
        _isOpen = NO;
        
        //Create handle view
        _handleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.frame.size.width, 30.0)];
        _handleView.exclusiveTouch = NO;
        [self addSubview:_handleView];
        
        //Add pan gesture
        _panRecognizer = [[M13PanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
        _panRecognizer.panDirection = M13PanGestureRecognizerDirectionVertical;
        _panRecognizer.minimumNumberOfTouches = 1;
        _panRecognizer.maximumNumberOfTouches = 1;
        [_handleView addGestureRecognizer:_panRecognizer];
    }
    return self;
}

-(void)handleDrag:(UIPanGestureRecognizer *)sender
{
    if ([sender state] == UIGestureRecognizerStateBegan) {
        
        _startPosition = self.center;
        
        //Get min and maximum points on the axis
        _minPosition = _closedCenter.y < _openCenter.y ? _closedCenter : _openCenter;
        _maxPosition = _closedCenter.y > _openCenter.y ? _closedCenter : _openCenter;
        
    } else if ([sender state] == UIGestureRecognizerStateChanged) {
        
        //Move the view, keeping it within the bounds
        CGPoint translate = [sender translationInView:self.superview];
        CGPoint newPos = CGPointMake(_startPosition.x, _startPosition.y + translate.y);
        
        if (newPos.y < _minPosition.y) {
            newPos.y = _minPosition.y;
            translate = CGPointMake(0, newPos.y - _startPosition.y);
        } else if (newPos.y > _maxPosition.y) {
            newPos.y = _maxPosition.y;
            translate = CGPointMake(0, newPos.y - _startPosition.y);
        }
        
    [sender setTranslation:translate inView:self.superview];
    self.center = newPos;
    
    } else if ([sender state] == UIGestureRecognizerStateEnded) {
    
        //Get the velocity of the gesture, to determine which endpoint to travel to.
        CGFloat velocity = [sender velocityInView:self.superview].y;
    
        if (velocity == 0.0) {
            BOOL setOpen = self.center.y >= (_minPosition.y + _maxPosition.y) / 2 ? YES : NO;
            [self setOpened:setOpen animated:YES];
        } else {
            CGPoint target = velocity <= 0 ? _minPosition : _maxPosition;
            BOOL setOpen =  CGPointEqualToPoint(target, _openCenter);
            [self setOpened:setOpen animated:YES];
        }
    }
}

- (void)setOpened:(BOOL)opened animated:(BOOL)animated
{
    _isOpen = opened;
    
    if (animated) {
        [UIView beginAnimations:@"TogglePullView" context:nil];
        [UIView setAnimationDuration:_animationDuration];
        [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
        [UIView setAnimationDelegate:self];
        [UIView setAnimationDidStopSelector:@selector(animationDidStop:finished:context:)];
    }
    
    self.center = _isOpen ? _openCenter : _closedCenter;
    
    if (animated) {
        //Prevent interaction during animation
        _panRecognizer.enabled = NO;
        
        [UIView commitAnimations];
    } else {
        if ([_delegate respondsToSelector:@selector(pullableView:didChangeState:)]) {
            [_delegate pullableView:self didChangeState:_isOpen];
        }
    }
}

- (void)animationDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)content
{
    if (finished) {
        //restore interaction
        _panRecognizer.enabled = YES;
        
        if ([_delegate respondsToSelector:@selector(pullableView:didChangeState:)]) {
            [_delegate pullableView:self didChangeState:_isOpen];
        }
    }
}

@end
