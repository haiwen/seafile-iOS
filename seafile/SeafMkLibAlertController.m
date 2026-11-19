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
#import "SeafTheme.h"

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
@property (nonatomic, strong) UIScrollView *formScrollView;
@property (nonatomic, strong) UIStackView *formStackView;
@property (nonatomic, strong) UIStackView *buttonStackView;

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

// The available area follows both the window's safe area and the keyboard.
@property (nonatomic, strong) UILayoutGuide *availableLayoutGuide;
@property (nonatomic, strong) NSLayoutConstraint *availableBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *alertViewBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *alertViewCenterYConstraint;
@property (nonatomic, assign) CGSize previousFormViewportSize;

@property (nonatomic, assign) BOOL hasPresentedAlert;
@property (nonatomic, assign) BOOL isBeingDismissedProgrammatically;

@end

static CGFloat const kMkLibMaximumWidth = 480.0;
static CGFloat const kMkLibCenteredLayoutMinimumWidth = 520.0;

@implementation SeafMkLibAlertController

- (instancetype)init {
    self = [super init];
    if (self) {
        if (IsIpad()) {
            self.modalPresentationStyle = UIModalPresentationFormSheet;
        } else {
            self.modalPresentationStyle = UIModalPresentationOverFullScreen;
            self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViews];
    [self setupConstraints];
    [self updateEncryptionFieldsVisibility:self.encryptSwitch.isOn animated:NO];

    if (!IsIpad()) {
        self.alertView.alpha = 0;
        self.backgroundDimmingView.alpha = 0;
        self.alertView.transform = CGAffineTransformMakeTranslation(0, 30);
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleBackgroundTap:)];
        [self.backgroundDimmingView addGestureRecognizer:tapGesture];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.hasPresentedAlert) return;
    self.hasPresentedAlert = YES;
    [UIView animateWithDuration:0.25 animations:^{
        self.alertView.alpha = 1.0;
        self.alertView.transform = CGAffineTransformIdentity;
        self.backgroundDimmingView.alpha = 1.0;
    }];
    [self.nameTextField becomeFirstResponder];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL centered = IsIpad() || CGRectGetWidth(self.view.safeAreaLayoutGuide.layoutFrame) >= kMkLibCenteredLayoutMinimumWidth;
    if (self.alertViewCenterYConstraint.active != centered) {
        self.alertViewBottomConstraint.active = NO;
        self.alertViewCenterYConstraint.active = NO;
        self.alertViewCenterYConstraint.active = centered;
        self.alertViewBottomConstraint.active = !centered;
    }
    self.availableBottomConstraint.constant = centered ? -8.0 : 0.0;
    self.alertView.layer.maskedCorners = centered
        ? kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner
        : kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;

    CGSize viewportSize = self.formScrollView.bounds.size;
    if (!CGSizeEqualToSize(viewportSize, self.previousFormViewportSize)) {
        self.previousFormViewportSize = viewportSize;
        [self scrollActiveTextFieldIntoViewAnimated:NO];
    }
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self.view setNeedsLayout];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    // CGColor is a snapshot; re-apply so the cancel button border tracks the theme.
    if (self.cancelButton) {
        self.cancelButton.layer.borderColor = [SeafTheme primaryText].CGColor;
    }
}

- (void)setupViews {
    self.view.backgroundColor = [UIColor clearColor];

    if (!IsIpad()) {
        self.backgroundDimmingView = [[UIView alloc] initWithFrame:self.view.bounds];
        self.backgroundDimmingView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5]; // modal scrim (both modes)
        self.backgroundDimmingView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:self.backgroundDimmingView];
    }

    self.alertView = [[UIView alloc] init];
    self.alertView.backgroundColor = [SeafTheme primarySurface];
    self.alertView.layer.masksToBounds = YES;
    self.alertView.translatesAutoresizingMaskIntoConstraints = NO;
    self.alertView.accessibilityIdentifier = @"new_library_dialog";
    [self.view addSubview:self.alertView];

    self.formScrollView = [[UIScrollView alloc] init];
    self.formScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.formScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.formScrollView.accessibilityIdentifier = @"new_library_form";
    [self.alertView addSubview:self.formScrollView];

    self.formStackView = [[UIStackView alloc] init];
    self.formStackView.axis = UILayoutConstraintAxisVertical;
    self.formStackView.spacing = 18.0;
    self.formStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.formScrollView addSubview:self.formStackView];

    if (IsIpad()) {
        self.alertView.layer.cornerRadius = 14.0; // Standard rounded corners for iPad
    } else {
        self.alertView.layer.cornerRadius = 14.0;
        self.alertView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = NSLocalizedString(@"New Library", @"New Library Title");
    self.titleLabel.font = [UIFont systemFontOfSize:17.0];
    self.titleLabel.textColor = [SeafTheme primaryText];
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.formStackView addArrangedSubview:self.titleLabel];

    self.nameTextField = [self createStyledTextFieldWithPlaceholder:NSLocalizedString(@"New library name", @"Library Name Placeholder") isPassword:NO];
    self.nameTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.nameTextField.accessibilityIdentifier = @"new_library_name";
    [self.formStackView addArrangedSubview:self.nameTextField];

    self.encryptLabel = [[UILabel alloc] init];
    self.encryptLabel.text = NSLocalizedString(@"Encrypted", @"Encrypt Label");
    self.encryptLabel.font = [UIFont systemFontOfSize:16.0];
    self.encryptLabel.textColor = [SeafTheme primaryText];
    self.encryptLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.encryptSwitch = [[UISwitch alloc] init];
    self.encryptSwitch.onTintColor = [UIColor orangeColor];
    [self.encryptSwitch addTarget:self action:@selector(encryptSwitchValueChanged:) forControlEvents:UIControlEventValueChanged];
    self.encryptSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.encryptSwitch.accessibilityIdentifier = @"new_library_encrypt";
    self.encryptSwitch.accessibilityLabel = self.encryptLabel.text;
    [self.encryptSwitch setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.encryptSwitch setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *encryptionRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.encryptLabel, self.encryptSwitch]];
    encryptionRow.alignment = UIStackViewAlignmentCenter;
    encryptionRow.spacing = 10.0;
    [self.formStackView addArrangedSubview:encryptionRow];
    [self.formStackView setCustomSpacing:23.0 afterView:self.nameTextField];

    self.passwordTextField = (UITextField *)[self createStyledTextFieldWithPlaceholder:NSLocalizedString(@"Password (at least 8 characters)", @"Password Placeholder") isPassword:YES];
    self.passwordTextField.secureTextEntry = YES;
    self.passwordVisibilityButton = [self createPasswordVisibilityButtonForTextField:self.passwordTextField];
    self.passwordTextField.rightView = self.passwordVisibilityButton;
    self.passwordTextField.rightViewMode = UITextFieldViewModeAlways;
    self.passwordTextField.accessibilityIdentifier = @"new_library_password";
    [self.formStackView addArrangedSubview:self.passwordTextField];
    [self.formStackView setCustomSpacing:10.0 afterView:self.passwordTextField];

    self.confirmPasswordTextField = (UITextField *)[self createStyledTextFieldWithPlaceholder:NSLocalizedString(@"Please enter your password again", @"Confirm Password Placeholder") isPassword:YES];
    self.confirmPasswordTextField.secureTextEntry = YES;
    self.confirmPasswordVisibilityButton = [self createPasswordVisibilityButtonForTextField:self.confirmPasswordTextField];
    self.confirmPasswordTextField.rightView = self.confirmPasswordVisibilityButton;
    self.confirmPasswordTextField.rightViewMode = UITextFieldViewModeAlways;
    self.confirmPasswordTextField.accessibilityIdentifier = @"new_library_password_confirmation";
    [self.formStackView addArrangedSubview:self.confirmPasswordTextField];
    
    self.cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cancelButton setTitle:NSLocalizedString(@"Cancel", @"Cancel Button Title") forState:UIControlStateNormal];
    [self.cancelButton setTitleColor:[SeafTheme primaryText] forState:UIControlStateNormal];
    self.cancelButton.titleLabel.font = [UIFont systemFontOfSize:17.0];
    self.cancelButton.backgroundColor = [SeafTheme primarySurface];
    self.cancelButton.layer.cornerRadius = 8.0;
    self.cancelButton.layer.borderColor = [SeafTheme primaryText].CGColor;
    self.cancelButton.layer.borderWidth = 1.0;
    [self.cancelButton addTarget:self action:@selector(cancelButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.cancelButton.accessibilityIdentifier = @"new_library_cancel";

    self.confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.confirmButton setTitle:NSLocalizedString(@"OK", @"Confirm Button Title") forState:UIControlStateNormal];
    [self.confirmButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.confirmButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    self.confirmButton.backgroundColor = [UIColor orangeColor];
    self.confirmButton.layer.cornerRadius = 8.0;
    [self.confirmButton addTarget:self action:@selector(confirmButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.confirmButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.confirmButton.accessibilityIdentifier = @"new_library_confirm";

    self.buttonStackView = [[UIStackView alloc] initWithArrangedSubviews:@[self.cancelButton, self.confirmButton]];
    self.buttonStackView.distribution = UIStackViewDistributionFillEqually;
    self.buttonStackView.spacing = 15.0;
    self.buttonStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.alertView addSubview:self.buttonStackView];
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
    textField.backgroundColor = [SeafTheme fill];
    
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

    button.tintColor = [SeafTheme secondaryText];
    
    if (textField == self.passwordTextField) {
        [button addTarget:self action:@selector(togglePasswordVisibility:) forControlEvents:UIControlEventTouchUpInside];
    } else if (textField == self.confirmPasswordTextField) {
        [button addTarget:self action:@selector(toggleConfirmPasswordVisibility:) forControlEvents:UIControlEventTouchUpInside];
    }
    return button;
}

- (void)setupConstraints {
    self.availableLayoutGuide = [[UILayoutGuide alloc] init];
    [self.view addLayoutGuide:self.availableLayoutGuide];
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    self.availableBottomConstraint = [self.availableLayoutGuide.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor];
    self.alertViewBottomConstraint = [self.alertView.bottomAnchor constraintEqualToAnchor:self.availableLayoutGuide.bottomAnchor];
    self.alertViewCenterYConstraint = [self.alertView.centerYAnchor constraintEqualToAnchor:self.availableLayoutGuide.centerYAnchor];

    // Prefer the full safe width on compact windows; cap the form on larger ones.
    NSLayoutConstraint *preferredWidth = [self.alertView.widthAnchor constraintEqualToAnchor:self.availableLayoutGuide.widthAnchor];
    preferredWidth.priority = UILayoutPriorityDefaultHigh;
    // Only the form scrolls when the keyboard leaves too little vertical space.
    NSLayoutConstraint *preferredFormHeight = [self.formScrollView.heightAnchor constraintEqualToAnchor:self.formStackView.heightAnchor];
    preferredFormHeight.priority = UILayoutPriorityDefaultHigh - 1;

    [NSLayoutConstraint activateConstraints:@[
        [self.availableLayoutGuide.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [self.availableLayoutGuide.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
        [self.availableLayoutGuide.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:8.0],
        self.availableBottomConstraint,
        [self.alertView.centerXAnchor constraintEqualToAnchor:self.availableLayoutGuide.centerXAnchor],
        [self.alertView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.availableLayoutGuide.leadingAnchor],
        [self.alertView.trailingAnchor constraintLessThanOrEqualToAnchor:self.availableLayoutGuide.trailingAnchor],
        [self.alertView.widthAnchor constraintLessThanOrEqualToConstant:kMkLibMaximumWidth],
        preferredWidth,
        [self.alertView.topAnchor constraintGreaterThanOrEqualToAnchor:self.availableLayoutGuide.topAnchor],
        [self.alertView.bottomAnchor constraintLessThanOrEqualToAnchor:self.availableLayoutGuide.bottomAnchor],
        self.alertViewBottomConstraint,

        [self.formScrollView.topAnchor constraintEqualToAnchor:self.alertView.topAnchor constant:30.0],
        [self.formScrollView.leadingAnchor constraintEqualToAnchor:self.alertView.leadingAnchor],
        [self.formScrollView.trailingAnchor constraintEqualToAnchor:self.alertView.trailingAnchor],
        preferredFormHeight,
        [self.formStackView.topAnchor constraintEqualToAnchor:self.formScrollView.contentLayoutGuide.topAnchor],
        [self.formStackView.leadingAnchor constraintEqualToAnchor:self.formScrollView.contentLayoutGuide.leadingAnchor constant:25.0],
        [self.formStackView.trailingAnchor constraintEqualToAnchor:self.formScrollView.contentLayoutGuide.trailingAnchor constant:-25.0],
        [self.formStackView.bottomAnchor constraintEqualToAnchor:self.formScrollView.contentLayoutGuide.bottomAnchor],
        [self.formStackView.widthAnchor constraintEqualToAnchor:self.formScrollView.frameLayoutGuide.widthAnchor constant:-50.0],
        [self.nameTextField.heightAnchor constraintEqualToConstant:48.0],

        [self.buttonStackView.topAnchor constraintEqualToAnchor:self.formScrollView.bottomAnchor constant:30.0],
        [self.buttonStackView.leadingAnchor constraintEqualToAnchor:self.alertView.leadingAnchor constant:25.0],
        [self.buttonStackView.trailingAnchor constraintEqualToAnchor:self.alertView.trailingAnchor constant:-25.0],
        [self.buttonStackView.heightAnchor constraintEqualToConstant:44.0],
        [self.buttonStackView.bottomAnchor constraintEqualToAnchor:self.alertView.bottomAnchor constant:-20.0],
    ]];

    for (UITextField *field in @[self.passwordTextField, self.confirmPasswordTextField]) {
        NSLayoutConstraint *height = [field.heightAnchor constraintEqualToConstant:48.0];
        // UIStackView collapses a hidden arranged view to zero height.
        height.priority = UILayoutPriorityRequired - 1;
        height.active = YES;
    }
}

- (void)updatePreferredContentSize {
    if (!IsIpad()) return;
    CGSize formSize = [self.formStackView systemLayoutSizeFittingSize:CGSizeMake(kMkLibMaximumWidth - 50.0, 0)
                                    withHorizontalFittingPriority:UILayoutPriorityRequired
                                          verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    // Form padding, button spacing/height, and 8pt above and below the panel.
    self.preferredContentSize = CGSizeMake(kMkLibMaximumWidth, formSize.height + 30.0 + 30.0 + 44.0 + 20.0 + 16.0);
    self.navigationController.preferredContentSize = self.preferredContentSize;
}

- (void)scrollActiveTextFieldIntoViewAnimated:(BOOL)animated {
    for (UITextField *field in @[self.nameTextField, self.passwordTextField, self.confirmPasswordTextField]) {
        if (field.isFirstResponder && !field.hidden) {
            CGRect rect = [self.formScrollView convertRect:field.bounds fromView:field];
            [self.formScrollView scrollRectToVisible:CGRectInset(rect, 0, -8.0) animated:animated];
            break;
        }
    }
}

#pragma mark - Actions

- (void)handleBackgroundTap:(UITapGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        [self dismissAlertIsCancel:YES];
    }
}

- (void)cancelButtonTapped:(UIButton *)sender {
    [self dismissAlertIsCancel:YES];
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

    [self dismissAlertIsCancel:NO];
}

- (void)dismissAlertIsCancel:(BOOL)isCancel {
    if (self.isBeingDismissedProgrammatically) return;
    self.isBeingDismissedProgrammatically = YES;
    NSString *name = [self.nameTextField.text copy];
    NSString *password = self.encryptSwitch.isOn ? [self.passwordTextField.text copy] : nil;
    HandlerBlock handler = isCancel ? nil : [self.handlerBlock copy];
    [self.view endEditing:YES];

    void (^completion)(void) = ^{
        if (handler) handler(name, password);
    };
    if (IsIpad()) {
        [self dismissViewControllerAnimated:YES completion:completion];
    } else {
        // Dismiss directly even when no software keyboard is present.
        [UIView animateWithDuration:0.2 animations:^{
            self.alertView.alpha = 0.0;
            self.alertView.transform = CGAffineTransformMakeTranslation(0, 30);
            self.backgroundDimmingView.alpha = 0.0;
        } completion:^(BOOL finished) {
            [self dismissViewControllerAnimated:NO completion:completion];
        }];
    }
}

- (void)encryptSwitchValueChanged:(UISwitch *)sender {
    BOOL encrypted = sender.isOn;
    if (!encrypted && (self.passwordTextField.isFirstResponder || self.confirmPasswordTextField.isFirstResponder)) {
        [self.nameTextField becomeFirstResponder];
    }
    [self updateEncryptionFieldsVisibility:encrypted animated:YES];
    if (encrypted) {
        [self.passwordTextField becomeFirstResponder];
    }
}

- (void)updateEncryptionFieldsVisibility:(BOOL)show animated:(BOOL)animated {
    self.passwordTextField.hidden = !show;
    self.confirmPasswordTextField.hidden = !show;
    [self updatePreferredContentSize];
    [UIView animateWithDuration:animated ? 0.25 : 0.0 animations:^{
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        [self scrollActiveTextFieldIntoViewAnimated:animated];
    }];
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
- (void)textFieldDidBeginEditing:(UITextField *)textField {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.view layoutIfNeeded];
        [self scrollActiveTextFieldIntoViewAnimated:YES];
    });
}

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
