//
//  SeafMkLibAlertController.m
//  seafileApp
//
//  Created by three on 2018/4/14.
//  Copyright © 2018年 Seafile. All rights reserved.
//

#import "SeafMkLibAlertController.h"
#import "UIViewController+Extend.h"
#import "ExtentedString.h"
#import "Debug.h"

@interface SeafMkLibAlertController ()<UITextFieldDelegate>
@property (weak, nonatomic) IBOutlet UIView *contentView;
@property (weak, nonatomic) IBOutlet UITextField *libNameTextField;
@property (weak, nonatomic) IBOutlet UISwitch *encryptedSwitch;
@property (weak, nonatomic) IBOutlet UITextField *pwdTextField;
@property (weak, nonatomic) IBOutlet UITextField *pwdRepeatTextField;
@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UILabel *encryptedLabel;
@property (weak, nonatomic) IBOutlet UIButton *cancelBtn;
@property (weak, nonatomic) IBOutlet UIButton *okBtn;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *heightConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *centerYConstraint;

@property (weak, nonatomic) IBOutlet UIView *line3;
@property (weak, nonatomic) IBOutlet UIView *line4;


@end

@implementation SeafMkLibAlertController

- (instancetype)init {
    if (self = [super initWithAutoPlatformNibName]) {
        
    }
    return self;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:false animated:true];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:true animated:true];
    [self encryptedSwitchFlip:false];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    self.titleLabel.text = NSLocalizedString(@"New Library", @"Seafile");
    self.libNameTextField.placeholder = NSLocalizedString(@"New library name", @"Seafile");
    self.pwdTextField.placeholder = NSLocalizedString(@"Password (at least 8 characters)", @"Seafile");
    self.pwdRepeatTextField.placeholder = NSLocalizedString(@"Please enter your password again", @"Seafile");
    self.encryptedLabel.text = NSLocalizedString(@"Encrypted", @"Seafile");
    [self.cancelBtn setTitle:STR_CANCEL forState:UIControlStateNormal];
    [self.okBtn setTitle:NSLocalizedString(@"OK", @"Seafile") forState:UIControlStateNormal];
    
    self.libNameTextField.delegate = self;
    self.pwdTextField.delegate = self;
    self.pwdRepeatTextField.delegate = self;
    
    self.contentView.layer.cornerRadius = 7;
    self.contentView.layer.masksToBounds = true;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    if (IsIpad()) return;
    if (self.encryptedSwitch.isOn) {
        [UIView animateWithDuration:0.3 animations:^{
            self.centerYConstraint.constant = -100;
        }];
    } else {
        [UIView animateWithDuration:0.3 animations:^{
            self.centerYConstraint.constant = -50;
        }];
    }
}

- (IBAction)cancel:(id)sender {
    [self dismissViewControllerAnimated:false completion:nil];
}

- (IBAction)ok:(id)sender {
    NSString *name = self.libNameTextField.text;
    NSString *pwd = self.pwdTextField.text;
    NSString *pwdRepeat = self.pwdRepeatTextField.text;
    BOOL encryted = self.encryptedSwitch.isOn;
    
    if (!name || name.length == 0) {
        [self alertWithTitle:NSLocalizedString(@"Library name must not be empty", @"Seafile")];
        return;
    }
    if (![name isValidFileName]) {
        [self alertWithTitle:NSLocalizedString(@"Library name invalid", @"Seafile")];
        return;
    }
    if (encryted) {
        if (!pwd || pwd.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Password must not be empty", @"Seafile")];
            return;
        }
        if (pwd.length < 8) {
            [self alertWithTitle:NSLocalizedString(@"Password must at least 8 characters", @"Seafile")];
            return;
        }
        if (![pwd isEqualToString:pwdRepeat]) {
            [self alertWithTitle:NSLocalizedString(@"Two passwords are different", @"Seafile")];
            return;
        }
    }
    
    if (self.handlerBlock) {
        if (!encryted) pwd = nil;
        self.handlerBlock(name, pwd);
    }
    [self dismissViewControllerAnimated:false completion:nil];
}

- (IBAction)encryptedSwitchFlip:(UISwitch *)sender {
    if (sender.on) {
        [UIView animateWithDuration:0.3 animations:^{
            self.heightConstraint.constant = 290;
        }];
    } else {
        [UIView animateWithDuration:0.3 animations:^{
            self.heightConstraint.constant = 205;
        }];
    }
    [self pwdGroupHidden:!sender.on];
}

- (void)pwdGroupHidden:(BOOL)hidden {
    self.pwdRepeatTextField.hidden = hidden;
    self.pwdTextField.hidden = hidden;
    self.line3.hidden = hidden;
    self.line4.hidden = hidden;
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
