//
//  InputAlertPrompt.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "InputAlertPrompt.h"
#import "SVProgressHUD.h"
#import "Debug.h"

@interface InputAlertPrompt ()
@property BOOL autoDismiss;
@end

@implementation InputAlertPrompt

@synthesize inputTextField;
@synthesize inputDoneDelegate;
@synthesize autoDismiss = _autoDismiss;

- (id)initWithTitle:(NSString *)title delegate:(id /*<UIAlertViewDelegate>*/)delegate autoDismiss:(BOOL)dismiss
{
    if ((self = [super initWithTitle:title message:nil delegate:delegate cancelButtonTitle:@"Cancel" otherButtonTitles:@"OK", nil])) {
        self.alertViewStyle = UIAlertViewStylePlainTextInput;
    }
    [[self inputTextField] becomeFirstResponder];
    self.inputTextField.delegate = self;
    _autoDismiss = dismiss;
    return self;
}

#pragma mark - Accessors
- (UITextField *)inputTextField
{
    return [self textFieldAtIndex:0];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    if (textField == self.inputTextField) {
        [self dismissWithClickedButtonIndex:1 animated:YES];
    }
    return YES;
}

- (void)dismissWithClickedButtonIndex:(NSInteger)buttonIndex animated:(BOOL)animated
{
    Debug("...buttonIndex=%d", buttonIndex);

    if (buttonIndex == [self cancelButtonIndex]) {
        [SVProgressHUD dismiss];
        [super dismissWithClickedButtonIndex:buttonIndex animated:animated];
    } else {
        if (![self.inputTextField isEnabled])
            return;
        NSString *errmsg = nil;
        if (self.inputDoneDelegate) {
            if (![self.inputDoneDelegate inputDone:self input:self.inputTextField.text errmsg:&errmsg]) {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:errmsg
                                                                message:nil
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
                alert.transform = CGAffineTransformTranslate( alert.transform, 0.0, 130.0 );
                [alert show];
            } else {
                if (_autoDismiss)
                    [super dismissWithClickedButtonIndex:buttonIndex animated:animated];
            }
        } else {
            [super dismissWithClickedButtonIndex:buttonIndex animated:animated];
        }
    }
}
@end
