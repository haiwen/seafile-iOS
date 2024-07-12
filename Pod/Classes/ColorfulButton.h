//
//  ColorfulButton.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>


@interface ColorfulButton : UIButton

/**
 * Sets the high and low colors for the gradient on the button.
 * The gradient will transition from the high color at the top to the low color at the bottom.
 *
 * @param hcolor The color to use at the top of the gradient.
 * @param lcolor The color to use at the bottom of the gradient.
 */
- (void)setHighColor:(UIColor*)hcolor lowColor:(UIColor*)lcolor;

@end
