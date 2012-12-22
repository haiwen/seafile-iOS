//
//  StartViewController.h
//  seafile
//
//  Created by Wang Wei on 8/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "SeafConnection.h"
#import "ColorfulButton.h"


@interface StartViewController : UIViewController <SSConnectionDelegate, UITextFieldDelegate>

@property (strong, nonatomic) IBOutlet UITextField *nameTextField;
@property (strong, nonatomic) IBOutlet UITextField *passwordTextField;
@property (strong, nonatomic) IBOutlet ColorfulButton *registerButton;
@property (strong, nonatomic) IBOutlet ColorfulButton *loginButton;
@property (strong, nonatomic) IBOutlet UIButton *otherServerButton;
@property (strong, nonatomic) IBOutlet UILabel *serverUrlLabel;

- (void)selectServer:(NSString *)url;

@end
