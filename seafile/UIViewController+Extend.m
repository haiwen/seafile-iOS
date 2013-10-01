//
//  UIViewController+AlertMessage.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "UIViewController+Extend.h"

@implementation UIViewController (Extend)

- (id)initWithAutoNibName
{
    return [self initWithNibName:(NSStringFromClass ([self class])) bundle:nil];
}

- (id)initWithAutoPlatformNibName
{
    NSString* className = NSStringFromClass ([self class]);
    NSString* plaformSuffix;
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        plaformSuffix = @"iPhone";
    } else {
        plaformSuffix = @"iPad";
    }
    return [self initWithNibName:[NSString stringWithFormat:@"%@_%@", className, plaformSuffix] bundle:nil];
}

- (id)initWithAutoPlatformLangNibName:(NSString *)lang
{
    NSString* className = NSStringFromClass ([self class]);
    NSString* plaformSuffix;
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        plaformSuffix = @"iPhone";
    } else {
        plaformSuffix = @"iPad";
    }
    return [self initWithNibName:[NSString stringWithFormat:@"%@_%@_%@", className, plaformSuffix, lang] bundle:nil];
}

- (void)alertWithMessage:(NSString*)message;
{
    UIAlertView *alert = [[UIAlertView alloc]initWithTitle:message
                                                   message:nil
                                                  delegate:self
                                         cancelButtonTitle:@"OK"
                                         otherButtonTitles:nil, nil];
    alert.transform = CGAffineTransformTranslate( alert.transform, 0.0, 130.0 );
    alert.alertViewStyle = UIAlertViewStyleDefault;

    [alert show];
}

- (UIBarButtonItem *)getBarItem:(NSString *)imageName action:(SEL)action size:(float)size;
{
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0,0,size,size);
    UIImage *img = [UIImage imageNamed:imageName];
    [btn setImage:img forState:UIControlStateNormal];
    btn.showsTouchWhenHighlighted = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:btn];
    return item;
}

- (UIBarButtonItem *)getBarItemAutoSize:(NSString *)imageName action:(SEL)action
{
    return [self getBarItem:imageName action:action size:22];
}

- (UIBarButtonItem *)getSpaceBarItem:(float)width
{
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:self action:nil];
    space.width = width;
    return space;
}

@end
