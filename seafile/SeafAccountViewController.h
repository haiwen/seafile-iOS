//
//  SeafAccountViewController.h
//  seafile
//
//  Created by Wang Wei on 1/12/13.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "StartViewController.h"

@interface SeafAccountViewController : UIViewController<SSConnectionDelegate, UITextFieldDelegate>

- (id)initWithController:(StartViewController *)controller connection: (SeafConnection *)conn;

@end
