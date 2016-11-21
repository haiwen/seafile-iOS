//
//  ColorfulButton.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "ColorfulButton.h"

@interface ColorfulButton ()
@property (nonatomic, retain) UIColor *highColor;
@property (nonatomic, retain) UIColor *lowColor;
@property (nonatomic, retain) CAGradientLayer *gradientLayer;
@end


@implementation ColorfulButton

@synthesize highColor = _highColor;
@synthesize lowColor = _lowColor;
@synthesize gradientLayer;

- (void)awakeFromNib;
{
    [super awakeFromNib];
    gradientLayer = [[CAGradientLayer alloc] init];
    [gradientLayer setBounds:[self bounds]];
    [gradientLayer setPosition:CGPointMake([self bounds].size.width/2, [self bounds].size.height/2)];
    [self.layer insertSublayer:gradientLayer atIndex:0];
    [self.layer setCornerRadius:5.0f];
    [self.layer setMasksToBounds:YES];
    [self.layer setBorderWidth:0.5f];
}

- (void)drawRect:(CGRect)rect;
{
    if (_highColor && _lowColor) {
        [gradientLayer setColors:[NSArray arrayWithObjects:(id)_highColor.CGColor, (id)_lowColor.CGColor, nil]];
    }
    [super drawRect:rect];
}

- (void)setHighColor:(UIColor*)hcolor lowColor:(UIColor*)lcolor
{
    _highColor = hcolor;
    _lowColor = lcolor;
    [[self layer] setNeedsDisplay];
}

@end
