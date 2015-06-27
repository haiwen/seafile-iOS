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
    ACCOUNT_PRIVATE = 0,
    ACCOUNT_SEACLOUD,
    ACCOUNT_CLOUD,
    ACCOUNT_SHIBBOLETH,
};

@interface SeafAccountViewController : UIViewController<UITextFieldDelegate>

- (id)initWithController:(StartViewController *)controller connection: (SeafConnection *)conn type:(int)type;

@end
