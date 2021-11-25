//
//  SeafAccountViewController.h
//  seafile
//
//  Created by Wang Wei on 1/12/13.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "StartViewController.h"
enum ACCOUNT_TYPE {
    ACCOUNT_SEACLOUD = 0,
    ACCOUNT_SHIBBOLETH,
    ACCOUNT_OTHER,
};

#define SERVER_SEACLOUD         @"luckyclound.cc"

#define SERVER_SEACLOUD_NAME    @"LuckyCloud.cc"
#define SERVER_SHIB_NAME        NSLocalizedString(@"Single Sign On", @"Seafile")


@interface SeafAccountViewController : UIViewController

- (id)initWithController:(StartViewController *)controller connection: (SeafConnection *)conn type:(int)type;

@end
