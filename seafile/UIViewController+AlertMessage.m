//
//  UIViewController+AlertMessage.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "UIViewController+AutoPlatformNibName.h"

@implementation UIViewController (AlertMessage)

- (void)alertWithMessage:(NSString*)message;
{
    UIAlertView *alert = [[UIAlertView alloc]initWithTitle:nil
                                                   message:message
                                                  delegate:nil
                                         cancelButtonTitle:@"OK"
                                         otherButtonTitles:nil, nil];
    alert.transform = CGAffineTransformTranslate( alert.transform, 0.0, 130.0 );
    [alert show];
}

@end
