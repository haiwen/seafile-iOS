//
//  InputAlertPrompt.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

@class InputAlertPrompt;

@protocol InputDoneDelegate <NSObject>
- (BOOL)inputDone:(InputAlertPrompt *)alertView input:(NSString *)input errmsg:(NSString **)errmsg;
@end

@interface InputAlertPrompt : UIAlertView <UITextFieldDelegate>

@property(nonatomic, retain, readonly) UITextField *inputTextField;

@property id <InputDoneDelegate> inputDoneDelegate;

- (id)initWithTitle:(NSString *)title delegate:(id /*<UIAlertViewDelegate>*/)delegate autoDismiss:(BOOL)dismiss;

@end
