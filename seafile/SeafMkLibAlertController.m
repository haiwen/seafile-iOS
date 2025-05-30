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
#import "SeafGlobal.h"

// Define the custom UITextField subclass here
@interface PaddedRightViewTextField : UITextField
@property (nonatomic, assign) CGFloat rightViewPaddingOffset; // Amount to shift left
@end

@implementation PaddedRightViewTextField

- (instancetype)init { // Using init as it's called by createStyledTextFieldWithPlaceholder
    self = [super init];
    if (self) {
        _rightViewPaddingOffset = 8.0; // Default shift to the left
    }
    return self;
}

- (CGRect)rightViewRectForBounds:(CGRect)bounds {
    CGRect originalRect = [super rightViewRectForBounds:bounds];
    originalRect.origin.x -= self.rightViewPaddingOffset; // Shift left
    return originalRect;
}

@end
// End of custom UITextField subclass definition

@interface SeafMkLibAlertController ()<UITextFieldDelegate>

// Main container views
@property (nonatomic, strong) UIView *backgroundDimmingView;
@property (nonatomic, strong) UIView *alertView;

// UI Elements
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UITextField *nameTextField;
@property (nonatomic, strong) UILabel *encryptLabel;
@property (nonatomic, strong) UISwitch *encryptSwitch;
@property (nonatomic, strong) UITextField *passwordTextField;
@property (nonatomic, strong) UIButton *passwordVisibilityButton;
@property (nonatomic, strong) UITextField *confirmPasswordTextField;
@property (nonatomic, strong) UIButton *confirmPasswordVisibilityButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *confirmButton;

// Constraints for dynamic layout
@property (nonatomic, strong) NSLayoutConstraint *alertViewBottomConstraint;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *passwordRelatedConstraints;

// Constraints for button's top anchor, to switch between anchoring to encryptSwitch or confirmPasswordTextField
@property (nonatomic, strong) NSLayoutConstraint *cancelButtonTopAnchorToEncryptSwitchConstraint;
@property (nonatomic, strong) NSLayoutConstraint *cancelButtonTopAnchorToConfirmPasswordConstraint;

@property (nonatomic, strong) NSLayoutConstraint *ipadAlertViewHeightConstraint; // Added for dynamic height on iPad

// Keyboard and state management
@property (nonatomic, assign) BOOL isBeingDismissedProgrammatically;
@property (nonatomic, assign) BOOL currentDismissalWasCancel;

@end

// Define a constant for the initial off-screen position
static CGFloat const kMkLibInitialOffScreenBottomConstant = 450.0; // Adjusted for potentially taller content
static CGFloat const kIPadAlertHeightNoEncrypt = 275.0f; // Calculated height for non-encrypted state
static CGFloat const kIPadAlertHeightEncrypted = 395.0f; // Calculated height for encrypted state

@implementation SeafMkLibAlertController

- (instancetype)init {
    self = [super init];
    if (self) {
        if (IsIpad()) {
            self.modalPresentationStyle = UIModalPresentationFormSheet;
        } else {
            self.modalPresentationStyle = UIModalPresentationOverCurrentContext;
            self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        }
        _passwordRelatedConstraints = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (IsIpad()) {
        self.view.backgroundColor = [UIColor clearColor];
        CGFloat initialHeight = self.encryptSwitch.isOn ? kIPadAlertHeightEncrypted : kIPadAlertHeightNoEncrypt;
        self.preferredContentSize = CGSizeMake(480, initialHeight); // Set initial preferred size

        [self setupViews];
        [self setupConstraints]; // This will now use the preferredContentSize for ipadAlertViewHeightConstraint
        self.alertView.alpha = 1.0;
        [self updateEncryptionFieldsVisibility:self.encryptSwitch.isOn animated:NO];
        // No keyboard notifications or background tap for iPad form sheet style
    } else { // iPhone
        [self setupViews];
        [self setupConstraints];
        
        self.alertView.alpha = 0;
        self.backgroundDimmingView.alpha = 0;
        self.alertViewBottomConstraint.constant = kMkLibInitialOffScreenBottomConstant;
        [self.view layoutIfNeeded];

        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleBackgroundTap:)];
        [self.backgroundDimmingView addGestureRecognizer:tapGesture];
        
        [self registerForKeyboardNotifications];
        [self updateEncryptionFieldsVisibility:self.encryptSwitch.isOn animated:NO];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!IsIpad()) { // iPhone: focus nameTextField or password fields
        if (!self.nameTextField.isFirstResponder &&
            !(self.encryptSwitch.isOn && (self.passwordTextField.isFirstResponder || self.confirmPasswordTextField.isFirstResponder))) {
            [self.nameTextField becomeFirstResponder];
        }
    } else { // iPad: focus nameTextField if nothing else appropriate is focused
        if (!self.nameTextField.isFirstResponder &&
            !(self.encryptSwitch.isOn && (self.passwordTextField.isFirstResponder || self.confirmPasswordTextField.isFirstResponder))) {
             [self.nameTextField becomeFirstResponder];
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (!IsIpad()) {
        [self unregisterForKeyboardNotifications];
    }
}

- (void)dealloc {
    if (!IsIpad()) {
        [self unregisterForKeyboardNotifications];
    }
}

- (void)setupViews {
    self.view.backgroundColor = [UIColor clearColor];

    if (!IsIpad()) {
        self.backgroundDimmingView = [[UIView alloc] initWithFrame:self.view.bounds];
        self.backgroundDimmingView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        self.backgroundDimmingView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:self.backgroundDimmingView];
    }

    self.alertView = [[UIView alloc] init];
    self.alertView.backgroundColor = [UIColor whiteColor];
    self.alertView.layer.masksToBounds = YES;
    self.alertView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.alertView];

    if (IsIpad()) {
        self.alertView.layer.cornerRadius = 14.0; // Standard rounded corners for iPad
    } else {
        self.alertView.layer.cornerRadius = 14.0;
        if (@available(iOS 11.0, *)) {
            self.alertView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        }
    }

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = NSLocalizedString(@"New Library", @"New Library Title");
    self.titleLabel.font = [UIFont systemFontOfSize:17.0];
    self.titleLabel.textColor = [UIColor blackColor];
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.alertView addSubview:self.titleLabel];

    self.nameTextField = [self createStyledTextFieldWithPlaceholder:NSLocalizedString(@"New library name", @"Library Name Placeholder") isPassword:NO];
    self.nameTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.alertView addSubview:self.nameTextField];

    self.encryptLabel = [[UILabel alloc] init];
    self.encryptLabel.text = NSLocalizedString(@"Encrypted", @"Encrypt Label");
    self.encryptLabel.font = [UIFont systemFontOfSize:16.0];
    self.encryptLabel.textColor = [UIColor blackColor];
    self.encryptLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.alertView addSubview:self.encryptLabel];

    self.encryptSwitch = [[UISwitch alloc] init];
    self.encryptSwitch.onTintColor = [UIColor orangeColor];
    [self.encryptSwitch addTarget:self action:@selector(encryptSwitchValueChanged:) forControlEvents:UIControlEventValueChanged];
    self.encryptSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.alertView addSubview:self.encryptSwitch];

    self.passwordTextField = (UITextField *)[self createStyledTextFieldWithPlaceholder:NSLocalizedString(@"Password (at least 8 characters)", @"Password Placeholder") isPassword:YES];
    self.passwordTextField.secureTextEntry = YES;
    self.passwordVisibilityButton = [self createPasswordVisibilityButtonForTextField:self.passwordTextField];
    self.passwordTextField.rightView = self.passwordVisibilityButton;
    self.passwordTextField.rightViewMode = UITextFieldViewModeAlways;
    self.passwordTextField.alpha = 0; // Initial alpha
    [self.alertView addSubview:self.passwordTextField];

    self.confirmPasswordTextField = (UITextField *)[self createStyledTextFieldWithPlaceholder:NSLocalizedString(@"Please enter your password again", @"Confirm Password Placeholder") isPassword:YES];
    self.confirmPasswordTextField.secureTextEntry = YES;
    self.confirmPasswordVisibilityButton = [self createPasswordVisibilityButtonForTextField:self.confirmPasswordTextField];
    self.confirmPasswordTextField.rightView = self.confirmPasswordVisibilityButton;
    self.confirmPasswordTextField.rightViewMode = UITextFieldViewModeAlways;
    self.confirmPasswordTextField.alpha = 0; // Initial alpha
    [self.alertView addSubview:self.confirmPasswordTextField];
    
    self.cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cancelButton setTitle:NSLocalizedString(@"Cancel", @"Cancel Button Title") forState:UIControlStateNormal];
    [self.cancelButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.cancelButton.titleLabel.font = [UIFont systemFontOfSize:17.0];
    self.cancelButton.backgroundColor = [UIColor whiteColor];
    self.cancelButton.layer.cornerRadius = 8.0;
    self.cancelButton.layer.borderColor = [UIColor blackColor].CGColor;
    self.cancelButton.layer.borderWidth = 1.0;
    [self.cancelButton addTarget:self action:@selector(cancelButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.alertView addSubview:self.cancelButton];

    self.confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.confirmButton setTitle:NSLocalizedString(@"OK", @"Confirm Button Title") forState:UIControlStateNormal];
    [self.confirmButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.confirmButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    self.confirmButton.backgroundColor = [UIColor orangeColor];
    self.confirmButton.layer.cornerRadius = 8.0;
    [self.confirmButton addTarget:self action:@selector(confirmButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.confirmButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.alertView addSubview:self.confirmButton];
}

- (UITextField *)createStyledTextFieldWithPlaceholder:(NSString *)placeholder isPassword:(BOOL)isPassword {
    UITextField *textField;
    if (isPassword) {
        textField = [[PaddedRightViewTextField alloc] init];
    } else {
        textField = [[UITextField alloc] init];
    }
    textField.placeholder = placeholder;
    textField.font = [UIFont systemFontOfSize:14.0];
    textField.borderStyle = UITextBorderStyleNone;
    textField.autocorrectionType = UITextAutocorrectionTypeNo;
    textField.delegate = self;
    textField.layer.cornerRadius = 8.0;
    textField.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0]; // Adjusted light gray
    
    UIView *leftPaddingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 15, 10)]; // Increased left padding
    textField.leftView = leftPaddingView;
    textField.leftViewMode = UITextFieldViewModeAlways;
    
    textField.translatesAutoresizingMaskIntoConstraints = NO;
    return textField;
}

- (UIButton *)createPasswordVisibilityButtonForTextField:(UITextField *)textField {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *eyeSlashImage, *eyeImage;
    eyeSlashImage = [UIImage imageNamed:@"icon_eye_close"];
    eyeImage = [UIImage imageNamed:@"icon_eye_open"];
    [button setImage:eyeSlashImage forState:UIControlStateNormal]; // Eye closed = password hidden
    [button setImage:eyeImage forState:UIControlStateSelected];    // Eye open = password visible
    
    // Adjust button frame to change its visible size
    button.frame = CGRectMake(0, 0, 30, 30); // Adjust frame for a smaller button

    // Ensure the imageView's contentMode is appropriate to prevent image stretching
    button.imageView.contentMode = UIViewContentModeScaleAspectFit;
    button.imageView.clipsToBounds = YES; // Ensure image stays within the imageView bounds

    button.tintColor = [UIColor grayColor];
    
    if (textField == self.passwordTextField) {
        [button addTarget:self action:@selector(togglePasswordVisibility:) forControlEvents:UIControlEventTouchUpInside];
    } else if (textField == self.confirmPasswordTextField) {
        [button addTarget:self action:@selector(toggleConfirmPasswordVisibility:) forControlEvents:UIControlEventTouchUpInside];
    }
    return button;
}

- (void)setupConstraints {
    if (IsIpad()) {
        self.ipadAlertViewHeightConstraint = [self.alertView.heightAnchor constraintEqualToConstant:self.preferredContentSize.height];
        [NSLayoutConstraint activateConstraints:@[
            [self.alertView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [self.alertView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
            [self.alertView.widthAnchor constraintEqualToConstant:self.preferredContentSize.width],
            self.ipadAlertViewHeightConstraint // Use the stored height constraint
        ]];
    } else { // iPhone
        self.alertViewBottomConstraint = [self.alertView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:kMkLibInitialOffScreenBottomConstant];
        [NSLayoutConstraint activateConstraints:@[
            [self.alertView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.alertView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            self.alertViewBottomConstraint
        ]];
    }

    CGFloat horizontalPadding = 25.0;
    CGFloat verticalPaddingFromAlertTop = 30.0;
    CGFloat verticalPaddingToAlertBottom = 20.0;
    CGFloat interElementSpacing = 18.0;
    CGFloat textFieldHeight = 48.0;
    CGFloat buttonHeight = 44.0;
    CGFloat buttonTopMargin = 30.0;
    CGFloat buttonSpacing = 15.0;

    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.alertView.topAnchor constant:verticalPaddingFromAlertTop],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.alertView.leadingAnchor constant:horizontalPadding],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.alertView.trailingAnchor constant:-horizontalPadding],

        [self.nameTextField.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:interElementSpacing],
        [self.nameTextField.leadingAnchor constraintEqualToAnchor:self.alertView.leadingAnchor constant:horizontalPadding],
        [self.nameTextField.trailingAnchor constraintEqualToAnchor:self.alertView.trailingAnchor constant:-horizontalPadding],
        [self.nameTextField.heightAnchor constraintEqualToConstant:textFieldHeight],

        [self.encryptLabel.topAnchor constraintEqualToAnchor:self.nameTextField.bottomAnchor constant:interElementSpacing + 5],
        [self.encryptLabel.leadingAnchor constraintEqualToAnchor:self.alertView.leadingAnchor constant:horizontalPadding],
        
        [self.encryptSwitch.centerYAnchor constraintEqualToAnchor:self.encryptLabel.centerYAnchor],
        [self.encryptSwitch.trailingAnchor constraintEqualToAnchor:self.alertView.trailingAnchor constant:-horizontalPadding],
        [self.encryptLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.encryptSwitch.leadingAnchor constant:-10]
    ]];

    // Password field constraints (managed by self.passwordRelatedConstraints)
    [self.passwordRelatedConstraints addObject:[self.passwordTextField.topAnchor constraintEqualToAnchor:self.encryptLabel.bottomAnchor constant:interElementSpacing]];
    [self.passwordRelatedConstraints addObject:[self.passwordTextField.leadingAnchor constraintEqualToAnchor:self.alertView.leadingAnchor constant:horizontalPadding]];
    [self.passwordRelatedConstraints addObject:[self.passwordTextField.trailingAnchor constraintEqualToAnchor:self.alertView.trailingAnchor constant:-horizontalPadding]];
    [self.passwordRelatedConstraints addObject:[self.passwordTextField.heightAnchor constraintEqualToConstant:textFieldHeight]];

    [self.passwordRelatedConstraints addObject:[self.confirmPasswordTextField.topAnchor constraintEqualToAnchor:self.passwordTextField.bottomAnchor constant:interElementSpacing - 8]];
    [self.passwordRelatedConstraints addObject:[self.confirmPasswordTextField.leadingAnchor constraintEqualToAnchor:self.alertView.leadingAnchor constant:horizontalPadding]];
    [self.passwordRelatedConstraints addObject:[self.confirmPasswordTextField.trailingAnchor constraintEqualToAnchor:self.alertView.trailingAnchor constant:-horizontalPadding]];
    [self.passwordRelatedConstraints addObject:[self.confirmPasswordTextField.heightAnchor constraintEqualToConstant:textFieldHeight]];

    // Button top constraints
    self.cancelButtonTopAnchorToEncryptSwitchConstraint = [self.cancelButton.topAnchor constraintEqualToAnchor:self.encryptSwitch.bottomAnchor constant:buttonTopMargin];
    self.cancelButtonTopAnchorToConfirmPasswordConstraint = [self.cancelButton.topAnchor constraintEqualToAnchor:self.confirmPasswordTextField.bottomAnchor constant:buttonTopMargin];

    [NSLayoutConstraint activateConstraints:@[
        self.cancelButtonTopAnchorToEncryptSwitchConstraint, // Initially active
        [self.cancelButton.leadingAnchor constraintEqualToAnchor:self.alertView.leadingAnchor constant:horizontalPadding],
        [self.cancelButton.heightAnchor constraintEqualToConstant:buttonHeight],
        [self.cancelButton.bottomAnchor constraintEqualToAnchor:self.alertView.safeAreaLayoutGuide.bottomAnchor constant:-verticalPaddingToAlertBottom],

        [self.confirmButton.topAnchor constraintEqualToAnchor:self.cancelButton.topAnchor],
        [self.confirmButton.leadingAnchor constraintEqualToAnchor:self.cancelButton.trailingAnchor constant:buttonSpacing],
        [self.confirmButton.trailingAnchor constraintEqualToAnchor:self.alertView.trailingAnchor constant:-horizontalPadding],
        [self.confirmButton.widthAnchor constraintEqualToAnchor:self.cancelButton.widthAnchor],
        [self.confirmButton.heightAnchor constraintEqualToAnchor:self.cancelButton.heightAnchor],
        [self.confirmButton.bottomAnchor constraintEqualToAnchor:self.cancelButton.bottomAnchor],
    ]];
    self.cancelButtonTopAnchorToConfirmPasswordConstraint.active = NO; // Initially inactive
}

#pragma mark - Keyboard Notifications

- (void)registerForKeyboardNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification object:nil];
}

- (void)unregisterForKeyboardNotifications {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    if (IsIpad()) return; // iPhone only
    NSDictionary *userInfo = notification.userInfo;
    CGRect keyboardFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval animationDuration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve animationCurve = [userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue];
    CGFloat keyboardHeight = keyboardFrame.size.height;
    
    self.alertViewBottomConstraint.constant = -keyboardHeight;
    
    [UIView animateWithDuration:animationDuration delay:0.0 options:(animationCurve << 16) | UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.alertView.alpha = 1.0;
        self.backgroundDimmingView.alpha = 1.0;
        [self.view layoutIfNeeded];
    } completion:nil];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    if (IsIpad()) return; // iPhone only
    NSDictionary *userInfo = notification.userInfo;
    NSTimeInterval animationDuration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve animationCurve = [userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue];
    
    self.alertViewBottomConstraint.constant = kMkLibInitialOffScreenBottomConstant;
    
    [UIView animateWithDuration:animationDuration delay:0.0 options:(animationCurve << 16) | UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.alertView.alpha = 0.0;
        self.backgroundDimmingView.alpha = 0.0;
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        if (self.isBeingDismissedProgrammatically) {
            [self dismissViewControllerAnimated:NO completion:^{
                if (!self.currentDismissalWasCancel && self.handlerBlock && [self.handlerBlock respondsToSelector:@selector(description)]) {
                    NSString *name = self.nameTextField.text;
                    NSString *pwd = self.encryptSwitch.isOn ? self.passwordTextField.text : nil;
                    self.handlerBlock(name, pwd);
                }
                self.isBeingDismissedProgrammatically = NO;
                self.currentDismissalWasCancel = NO;
            }];
        }
    }];
}

#pragma mark - Actions

- (void)handleBackgroundTap:(UITapGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        [self dismissAlertAndCallHandler:nil isCancel:YES];
    }
}

- (void)cancelButtonTapped:(UIButton *)sender {
    if (IsIpad()) {
        [self.view endEditing:YES]; // Dismiss keyboard if any field is active
        [self dismissViewControllerAnimated:YES completion:nil]; // Cancel action, no handler call from here
    } else { // iPhone logic
        [self dismissAlertAndCallHandler:nil isCancel:YES];
    }
}

- (void)confirmButtonTapped:(UIButton *)sender {
    NSString *name = self.nameTextField.text;
    NSString *pwd = self.passwordTextField.text;
    NSString *pwdRepeat = self.confirmPasswordTextField.text;
    BOOL encrypted = self.encryptSwitch.isOn;
    
    if (!name || name.length == 0) {
        [self showAlertWithTitle:NSLocalizedString(@"Library name must not be empty", @"Seafile")];
        return;
    }
    if (![name isValidFileName]) {
        [self showAlertWithTitle:NSLocalizedString(@"Library name invalid", @"Seafile")];
        return;
    }
    if (encrypted) {
        if (!pwd || pwd.length == 0) {
            [self showAlertWithTitle:NSLocalizedString(@"Password must not be empty", @"Seafile")];
            return;
        }
        if (pwd.length < 4) { // As per image, assuming min length is 4
            [self showAlertWithTitle:NSLocalizedString(@"Password must at least 4 characters", @"Seafile")];
            return;
        }
        if (![pwd isEqualToString:pwdRepeat]) {
            [self showAlertWithTitle:NSLocalizedString(@"Two passwords are different", @"Seafile")];
            return;
        }
    }

    if (IsIpad()) {
        [self.view endEditing:YES]; // Dismiss keyboard
        [self dismissViewControllerAnimated:YES completion:^{
            if (self.handlerBlock) {
                self.handlerBlock(name, encrypted ? pwd : nil); // Pass nil for pwd if not encrypted
            }
        }];
    } else { // iPhone logic
        [self dismissAlertAndCallHandler:self.handlerBlock isCancel:NO];
    }
}

- (void)dismissAlertAndCallHandler:(HandlerBlock)handler isCancel:(BOOL)isCancel {
    self.isBeingDismissedProgrammatically = YES;
    self.currentDismissalWasCancel = isCancel;

    if (self.nameTextField.isFirstResponder) [self.nameTextField resignFirstResponder];
    else if (self.passwordTextField.isFirstResponder) [self.passwordTextField resignFirstResponder];
    else if (self.confirmPasswordTextField.isFirstResponder) [self.confirmPasswordTextField resignFirstResponder];
    else {
        [self.view endEditing:YES];
        if (!self.alertView.alpha == 0) {
             [self manuallyTriggerDismissAnimationIsCancel:isCancel];
        }
    }
}

- (void)manuallyTriggerDismissAnimationIsCancel:(BOOL)isCancel {
    NSTimeInterval animationDuration = 0.25;
    UIViewAnimationCurve animationCurve = UIViewAnimationCurveEaseInOut;
    self.alertViewBottomConstraint.constant = kMkLibInitialOffScreenBottomConstant;
    
    [UIView animateWithDuration:animationDuration delay:0.0 options:(animationCurve << 16) | UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.alertView.alpha = 0.0;
        self.backgroundDimmingView.alpha = 0.0;
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        [self dismissViewControllerAnimated:NO completion:^{
            if (!isCancel && self.handlerBlock) {
                NSString *name = self.nameTextField.text;
                NSString *pwd = self.encryptSwitch.isOn ? self.passwordTextField.text : nil;
                self.handlerBlock(name, pwd);
            }
        }];
    }];
}


- (void)encryptSwitchValueChanged:(UISwitch *)sender {
    BOOL przyszloIsOn = sender.isOn;
    CGFloat newHeight = przyszloIsOn ? kIPadAlertHeightEncrypted : kIPadAlertHeightNoEncrypt;

    if (IsIpad()) {
        self.preferredContentSize = CGSizeMake(self.preferredContentSize.width, newHeight);
        if (self.ipadAlertViewHeightConstraint) { // Ensure constraint is already created
            self.ipadAlertViewHeightConstraint.constant = newHeight;
        }
    }

    [self updateEncryptionFieldsVisibility:przyszloIsOn animated:YES];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (przyszloIsOn) {
            if (self.encryptSwitch.isOn) {
                 [self.passwordTextField becomeFirstResponder];
            }
    } else {
            if (!self.encryptSwitch.isOn && (self.passwordTextField.isFirstResponder || self.confirmPasswordTextField.isFirstResponder)) {
                [self.nameTextField becomeFirstResponder];
            }
        }
    });
}

- (void)updateEncryptionFieldsVisibility:(BOOL)show animated:(BOOL)animated {
    if (animated) {
        if (show) {
            self.passwordTextField.hidden = NO;
            self.confirmPasswordTextField.hidden = NO;
            self.passwordTextField.alpha = 0.0;
            self.confirmPasswordTextField.alpha = 0.0;

            [NSLayoutConstraint activateConstraints:self.passwordRelatedConstraints];
            self.cancelButtonTopAnchorToEncryptSwitchConstraint.active = NO;
            self.cancelButtonTopAnchorToConfirmPasswordConstraint.active = YES;

            [self.alertView layoutIfNeeded];

            [UIView animateWithDuration:0.3
                             animations:^{
                                 self.passwordTextField.alpha = 1.0;
                                 self.confirmPasswordTextField.alpha = 1.0;
                                 [self.alertView layoutIfNeeded];
                             }
                             completion:nil];
        } else {
            [UIView animateWithDuration:0.15
                             animations:^{
                                 self.passwordTextField.alpha = 0.0;
                                 self.confirmPasswordTextField.alpha = 0.0;
                             }
                             completion:^(BOOL finishedFadeOut) {
                                 if (finishedFadeOut) {
                                     self.passwordTextField.hidden = YES;
                                     self.confirmPasswordTextField.hidden = YES;

                                     [NSLayoutConstraint deactivateConstraints:self.passwordRelatedConstraints];
                                     self.cancelButtonTopAnchorToConfirmPasswordConstraint.active = NO;
                                     self.cancelButtonTopAnchorToEncryptSwitchConstraint.active = YES;

                                     [UIView animateWithDuration:0.15
                                                      animations:^{
                                                          [self.alertView layoutIfNeeded];
                                                      }];
                                 }
                             }];
        }
    } else {
        if (show) {
            self.passwordTextField.alpha = 1.0;
            self.confirmPasswordTextField.alpha = 1.0;
            self.passwordTextField.hidden = NO;
            self.confirmPasswordTextField.hidden = NO;
        } else {
            self.passwordTextField.alpha = 0.0;
            self.confirmPasswordTextField.alpha = 0.0;
            self.passwordTextField.hidden = YES;
            self.confirmPasswordTextField.hidden = YES;
        }
        [self.alertView layoutIfNeeded];
    }
}

- (void)togglePasswordVisibility:(UIButton *)sender {
    BOOL secure = !self.passwordTextField.secureTextEntry;
    self.passwordTextField.secureTextEntry = secure;
    sender.selected = !secure;
}

- (void)toggleConfirmPasswordVisibility:(UIButton *)sender {
    self.confirmPasswordTextField.secureTextEntry = !self.confirmPasswordTextField.secureTextEntry;
    sender.selected = !self.confirmPasswordTextField.secureTextEntry;
}

#pragma mark - UITextFieldDelegate
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.nameTextField) {
        if (self.encryptSwitch.isOn) [self.passwordTextField becomeFirstResponder];
        else [self confirmButtonTapped:nil];
    } else if (textField == self.passwordTextField) {
        [self.confirmPasswordTextField becomeFirstResponder];
    } else if (textField == self.confirmPasswordTextField) {
        [self confirmButtonTapped:nil];
    }
    return YES;
}

#pragma mark - Helper
- (void)showAlertWithTitle:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIAlertActionStyleDefault handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

@end
