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
    ACCOUNT_CLOUD,
    ACCOUNT_SHIBBOLETH,
    ACCOUNT_OTHER,
};

#define SERVER_SEACLOUD         @"https://seacloud.cc"
#define SERVER_CLOUD            @"https://cloud.seafile.de"

#define SERVER_SEACLOUD_NAME    @"SeaCloud.cc"
#define SERVER_CLOUD_NAME       @"cloud.seafile.de"
#define SERVER_SHIB_NAME        @"Shibboleth"

@interface SeafAccountViewController : UIViewController<UITextFieldDelegate>

- (id)initWithController:(StartViewController *)controller connection: (SeafConnection *)conn type:(int)type;

@end
