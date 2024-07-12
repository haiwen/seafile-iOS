//
//  SeafAccountViewController.h
//  seafile
//
//  Created by Wang Wei on 1/12/13.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "StartViewController.h"

/**
 * @enum ACCOUNT_TYPE
 * @brief Enumerates the types of accounts supported.
 */
enum ACCOUNT_TYPE {
    ACCOUNT_SEACLOUD = 0,
    ACCOUNT_SHIBBOLETH,
    ACCOUNT_OTHER,
};

/**
 * Constants for SeaCloud server.
 */
#define SERVER_SEACLOUD         @"seacloud.cc"

#define SERVER_SEACLOUD_NAME    @"SeaCloud.cc"
#define SERVER_SHIB_NAME        NSLocalizedString(@"Single Sign On", @"Seafile")

/**A view controller to manage Seafile account login and setup. */
@interface SeafAccountViewController : UIViewController

/**
 * Initializes a new instance of the SeafAccountViewController class.
 * @param controller The starting view controller that presented this view controller.
 * @param conn A SeafConnection object used to manage server communications.
 * @param type The type of account to be set up, based on ACCOUNT_TYPE.
 * @return An instance of SeafAccountViewController.
 */
- (id)initWithController:(StartViewController *)controller connection: (SeafConnection *)conn type:(int)type;

@end
