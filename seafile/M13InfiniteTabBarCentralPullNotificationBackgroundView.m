//
//  M13InfiniteTabBarCentralPullNotificationBackgroundView.m
//  M13InfiniteTabBar
/*
 Copyright (c) 2013 Brandon McQuilkin

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 One does not claim this software as ones own.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import "M13InfiniteTabBarCentralPullNotificationBackgroundView.h"

@interface M13InfiniteTabBarCentralPullNotificationBackgroundView ()

@property (nonatomic, assign) CGFloat notificationPatternRepeatDistance;

@end

@implementation M13InfiniteTabBarCentralPullNotificationBackgroundView
{
    CGFloat _offset; //Band offset distance
    CGSize _distance; //Used to calculate drawing points
    UIColor *_notificationColor; //Instance Variable for color
    CGFloat _notificationLineWidth; //Band Thickness
}

- (id)initWithFrame:(CGRect)frame
{
    frame.size.height = 127.5;
    self = [super initWithFrame:frame];
    if (self) {
        //Defaults
        _isEmergency = NO;

        //Used specifically by this pattern
        _notificationPatternRepeatDistance = 42.5;
        _offset = 42.5;
        _distance = CGSizeMake((self.bounds.size.width / 2.0) + 15, (self.bounds.size.width / 2.0) + 15);
        _notificationLineWidth = 15.0;
        _notificationNonEmergencyColor = [UIColor colorWithRed:0.0 green:0.149 blue:1.0 alpha:0.2];
        _notificationEmergencyColor = [UIColor colorWithRed:1.0 green:0.149 blue:0.0 alpha:0.2];
        _notificationColor = _notificationNonEmergencyColor; //Set start color

        //System setting
        self.opaque = NO; // Enable Tranparency when drawing
    }
    return self;
}

- (void)setIsEmergency:(BOOL)isEmergency
{
    _isEmergency = isEmergency;

    //Change Notification Color
    if (!_isEmergency) {
        _notificationColor = _notificationNonEmergencyColor;
    } else {
        _notificationColor = _notificationEmergencyColor;
    }
}


- (void)drawRect:(CGRect)rect
{
    [super drawRect:rect];
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    CGPoint center = CGPointMake(rect.size.width / 2.0, rect.size.height);
    CGContextSetStrokeColorWithColor(context, _notificationColor.CGColor);
    CGContextSetRGBFillColor(context, 0, 0, 0, 0);
    CGContextFillRect(context, rect);

    //Path
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, center.x - _distance.width, center.y + _distance.height);
    BOOL reverse = NO;
    //Iterate and create a pattern of upward chevrons
    for (int i = 0; i <= (rect.size.width / _offset); i++) {
        if (reverse) {
            CGPathAddLineToPoint(path, NULL, center.x + _distance.width, center.y + _distance.height);
            CGPathAddLineToPoint(path, NULL, center.x, center.y);
            CGPathAddLineToPoint(path, NULL, center.x - _distance.width, center.y + _distance.height);
        } else {
            CGPathAddLineToPoint(path, NULL, center.x - _distance.width, center.y + _distance.height);
            CGPathAddLineToPoint(path, NULL, center.x, center.y);
            CGPathAddLineToPoint(path, NULL, center.x + _distance.width, center.y + _distance.height);
        }
        reverse = !reverse;
        center.y = center.y - _offset;
    }
    //Draw Path
    CGContextAddPath(context, path);
    CGContextSetLineWidth(context, _notificationLineWidth);
    CGContextSetLineJoin(context, kCGLineJoinMiter);
    CGContextSetLineCap(context, kCGLineCapButt);
    CGContextSetMiterLimit(context, 100.0);
    CGContextStrokePath(context);
    //Clean up
    CGContextRestoreGState(context);
    CGPathRelease(path);
}

@end
