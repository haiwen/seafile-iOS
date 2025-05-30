//
//  SeafCustomInputAlertViewController.m
//  Seafile
//

#import "SeafCustomInputAlertViewController.h"
#import "Debug.h"

@interface SeafCustomInputAlertViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UIView *alertView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UITextField *inputTextField;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *confirmButton;
@property (nonatomic, strong) UIView *backgroundDimmingView;

// For keyboard-aware animation
@property (nonatomic, strong) NSLayoutConstraint *alertViewBottomConstraint;
@property (nonatomic, assign) BOOL isBeingDismissedProgrammatically;
@property (nonatomic, strong) id finalCompletionHandler; // To store either confirm or cancel block

@end

// Define a constant for the initial off-screen position to make it clear
static CGFloat const kInitialOffScreenBottomConstant = 350.0; // Adjust if alert can be very tall

@implementation SeafCustomInputAlertViewController

- (instancetype)initWithTitle:(NSString *)title
                  placeholder:(NSString *)placeholder
                 initialInput:(nullable NSString *)initialInput
            completionHandler:(void (^)(NSString * _Nullable inputText))completionHandler
                cancelHandler:(nullable void (^)(void))cancelHandler {
    self = [super init];
    if (self) {
        _alertTitle = [title copy];
        _placeholderText = [placeholder copy];
        _initialInputText = [initialInput copy];
        _completionHandler = [completionHandler copy];
        _cancelHandler = [cancelHandler copy];
        
        if (IsIpad()) {
            self.modalPresentationStyle = UIModalPresentationFormSheet;
            // FormSheet has its own transition, no need for UIModalTransitionStyleCrossDissolve
        } else {
            self.modalPresentationStyle = UIModalPresentationOverCurrentContext;
            self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve; // Actual slide is manual
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (IsIpad()) {
        self.view.backgroundColor = [UIColor clearColor]; // The form sheet content is alertView
        self.preferredContentSize = CGSizeMake(450, 240); // Set preferredContentSize BEFORE setupViews/setupConstraints

        [self setupViews]; // alertView needs to be created
        [self setupConstraints]; // alertView needs to be constrained
        self.alertView.alpha = 1.0; // Visible by default for form sheet
        // Estimate height: title(20) + space(20) + field(40) + space(25) + button(44) + padding(30+30) = 209. Let's use 240.
    } else {
        [self setupViews];
        [self setupConstraints]; // Constraints are set up here
        
        // Initial state before animation for iPhone
        self.alertView.alpha = 0;
        self.backgroundDimmingView.alpha = 0;
        self.alertViewBottomConstraint.constant = kInitialOffScreenBottomConstant; // Start off-screen
        [self.view layoutIfNeeded]; // Apply initial constraint

        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleBackgroundTap:)];
        [self.backgroundDimmingView addGestureRecognizer:tapGesture];
        
        [self registerForKeyboardNotifications];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Trigger keyboard presentation
    if (!self.inputTextField.isFirstResponder) {
      [self.inputTextField becomeFirstResponder];
    }
    // iPhone specific animation is triggered by keyboardWillShow
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (!IsIpad()) {
        [self unregisterForKeyboardNotifications];
    }
}

- (void)dealloc {
    if (!IsIpad()) {
        [self unregisterForKeyboardNotifications]; // Just in case
    }
}

- (void)setupViews {
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
    [self.view addSubview:self.alertView]; // alertView is always added to self.view

    if (IsIpad()) {
        self.alertView.layer.cornerRadius = 14.0; // Standard corner radius for alerts/sheets
    } else {
        self.alertView.layer.cornerRadius = 14.0;
        if (@available(iOS 11.0, *)) {
            self.alertView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        }
    }

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = self.alertTitle;
    self.titleLabel.font = [UIFont systemFontOfSize:17.0];
    self.titleLabel.textColor = [UIColor blackColor];
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.alertView addSubview:self.titleLabel];

    self.inputTextField = [[UITextField alloc] init];
    self.inputTextField.placeholder = self.placeholderText;
    self.inputTextField.text = self.initialInputText;
    self.inputTextField.font = [UIFont systemFontOfSize:14.0];
    self.inputTextField.borderStyle = UITextBorderStyleNone;
    self.inputTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.inputTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.inputTextField.delegate = self;
    self.inputTextField.returnKeyType = UIReturnKeyDone;
    self.inputTextField.layer.borderWidth = 0;
    self.inputTextField.layer.cornerRadius = 6.0;
    self.inputTextField.backgroundColor = [UIColor colorWithWhite:0.97 alpha:1.0];
    UIView *paddingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    self.inputTextField.leftView = paddingView;
    self.inputTextField.leftViewMode = UITextFieldViewModeAlways;
    UIView *paddingRightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    self.inputTextField.rightView = paddingRightView;
    self.inputTextField.rightViewMode = UITextFieldViewModeAlways;
    self.inputTextField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.alertView addSubview:self.inputTextField];

    self.cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cancelButton setTitle:NSLocalizedString(@"Cancel", @"Cancel button title") forState:UIControlStateNormal];
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
    [self.confirmButton setTitle:NSLocalizedString(@"OK", @"Seafile") forState:UIControlStateNormal];
    [self.confirmButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.confirmButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    self.confirmButton.backgroundColor = UIColor.orangeColor;
    self.confirmButton.layer.cornerRadius = 8.0;
    [self.confirmButton addTarget:self action:@selector(confirmButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.confirmButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.alertView addSubview:self.confirmButton];
}

- (void)setupConstraints {
    // alertView constraints (leading/trailing for full width, bottom constraint for vertical positioning)
    if (IsIpad()) {
        // Center alertView and set its size based on preferredContentSize
        [NSLayoutConstraint activateConstraints:@[
            [self.alertView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [self.alertView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
            [self.alertView.widthAnchor constraintEqualToConstant:self.preferredContentSize.width],
            [self.alertView.heightAnchor constraintEqualToConstant:self.preferredContentSize.height]
        ]];
    } else {
        self.alertViewBottomConstraint = [self.alertView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:kInitialOffScreenBottomConstant];
        [NSLayoutConstraint activateConstraints:@[ // Full width, bottom constraint set above for iPhone
            [self.alertView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.alertView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            self.alertViewBottomConstraint
        ]];
    }

    CGFloat horizontalPadding = 25.0;
    CGFloat verticalPadding = 30.0;
    CGFloat interItemSpacing = 20.0;
    CGFloat buttonTopMargin = 25.0;
    CGFloat buttonHeight = 44.0;
    CGFloat buttonSpacing = 15.0;

    [NSLayoutConstraint activateConstraints:@[ // titleLabel constraints
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.alertView.topAnchor constant:verticalPadding],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.alertView.leadingAnchor constant:horizontalPadding],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.alertView.trailingAnchor constant:-horizontalPadding],
    ]];

    [NSLayoutConstraint activateConstraints:@[ // inputTextField constraints
        [self.inputTextField.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:interItemSpacing],
        [self.inputTextField.leadingAnchor constraintEqualToAnchor:self.alertView.leadingAnchor constant:horizontalPadding],
        [self.inputTextField.trailingAnchor constraintEqualToAnchor:self.alertView.trailingAnchor constant:-horizontalPadding],
        [self.inputTextField.heightAnchor constraintEqualToConstant:40],
    ]];

    [NSLayoutConstraint activateConstraints:@[ // cancelButton constraints
        [self.cancelButton.topAnchor constraintEqualToAnchor:self.inputTextField.bottomAnchor constant:buttonTopMargin],
        [self.cancelButton.leadingAnchor constraintEqualToAnchor:self.alertView.leadingAnchor constant:horizontalPadding],
        [self.cancelButton.heightAnchor constraintEqualToConstant:buttonHeight],
        [self.cancelButton.bottomAnchor constraintEqualToAnchor:self.alertView.safeAreaLayoutGuide.bottomAnchor constant:-verticalPadding], // Consider safe area for bottom buttons
    ]];

    [NSLayoutConstraint activateConstraints:@[ // confirmButton constraints
        [self.confirmButton.topAnchor constraintEqualToAnchor:self.cancelButton.topAnchor],
        [self.confirmButton.leadingAnchor constraintEqualToAnchor:self.cancelButton.trailingAnchor constant:buttonSpacing],
        [self.confirmButton.trailingAnchor constraintEqualToAnchor:self.alertView.trailingAnchor constant:-horizontalPadding],
        [self.confirmButton.widthAnchor constraintEqualToAnchor:self.cancelButton.widthAnchor],
        [self.confirmButton.heightAnchor constraintEqualToAnchor:self.cancelButton.heightAnchor],
        [self.confirmButton.bottomAnchor constraintEqualToAnchor:self.cancelButton.bottomAnchor],
    ]];
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
    if (IsIpad()) return; // Only for iPhone
    NSDictionary *userInfo = notification.userInfo;
    CGRect keyboardFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval animationDuration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve animationCurve = [userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue];
    
    self.alertViewBottomConstraint.constant = -keyboardFrame.size.height;
    
    [UIView animateWithDuration:animationDuration
                          delay:0.0
                        options:(animationCurve << 16) | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         self.alertView.alpha = 1.0;
                         self.backgroundDimmingView.alpha = 1.0; 
                         [self.view layoutIfNeeded];
                     } completion:nil];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    if (IsIpad()) return; // Only for iPhone
    NSDictionary *userInfo = notification.userInfo;
    NSTimeInterval animationDuration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve animationCurve = [userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue];
    
    self.alertViewBottomConstraint.constant = kInitialOffScreenBottomConstant;
    
    [UIView animateWithDuration:animationDuration
                          delay:0.0
                        options:(animationCurve << 16) | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         self.alertView.alpha = 0.0;
                         self.backgroundDimmingView.alpha = 0.0;
                         [self.view layoutIfNeeded];
                     } completion:^(BOOL finished) {
                         if (self.isBeingDismissedProgrammatically) {
                             [self dismissViewControllerAnimated:NO completion:^{
                                 if (self.finalCompletionHandler) {
                                     // Check which handler it is (void vs void(^)(NSString*))
                                     if (self.cancelHandler == self.finalCompletionHandler && [self.finalCompletionHandler respondsToSelector:@selector(description)]) { // crude check for block type
                                         ((void(^)(void))self.finalCompletionHandler)();
                                     } else if (self.completionHandler == self.finalCompletionHandler && [self.finalCompletionHandler respondsToSelector:@selector(description)]) {
                                         ((void(^)(NSString *))self.finalCompletionHandler)(self.inputTextField.text);
                                     }
                                 }
                                 self.isBeingDismissedProgrammatically = NO;
                                 self.finalCompletionHandler = nil;
                             }];
                         }
                     }];
}

#pragma mark - Actions

- (void)handleBackgroundTap:(UITapGestureRecognizer *)sender {
    // If tap is on background, treat as cancel
    if (sender.state == UIGestureRecognizerStateEnded) {
        if (IsIpad()) {
            // For FormSheet, system might handle this, or we might not want this behavior.
            // If explicit cancel on tap outside is needed for iPad, it would be configured differently.
            // For now, this action is iPhone-specific due to custom presentation.
            return;
        }
        self.isBeingDismissedProgrammatically = YES;
        self.finalCompletionHandler = self.cancelHandler; // Assume tap outside is a cancel
        [self.inputTextField resignFirstResponder]; // This will trigger keyboardWillHide and dismissal
    }
}

- (void)cancelButtonTapped:(UIButton *)sender {
    if (IsIpad()) {
        [self.inputTextField resignFirstResponder]; // Attempt to hide keyboard first
        [self dismissViewControllerAnimated:YES completion:^{
            if (self.cancelHandler) {
                self.cancelHandler();
            }
        }];
    } else { // iPhone-specific logic
        self.isBeingDismissedProgrammatically = YES;
        self.finalCompletionHandler = self.cancelHandler;
        [self.inputTextField resignFirstResponder]; // This will trigger keyboardWillHide and the actual dismissal
    }
}

- (void)confirmButtonTapped:(UIButton *)sender {
    if (IsIpad()) {
        NSString *inputText = self.inputTextField.text; // Capture text before resigning
        [self.inputTextField resignFirstResponder]; // Attempt to hide keyboard first
        [self dismissViewControllerAnimated:YES completion:^{
            if (self.completionHandler) {
                self.completionHandler(inputText);
            }
        }];
    } else { // iPhone-specific logic
        self.isBeingDismissedProgrammatically = YES;
        self.finalCompletionHandler = self.completionHandler;
        // For iPhone, inputText is read from self.inputTextField.text in keyboardWillHide's completion block
        [self.inputTextField resignFirstResponder]; // This will trigger keyboardWillHide and the actual dismissal
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    // For both iPad and iPhone, pressing return should simulate a confirm action.
    [self confirmButtonTapped:nil]; 
    return YES;
}

#pragma mark - Presentation

- (void)presentOverViewController:(UIViewController *)presentingVC {
    if (IsIpad()) {
        [presentingVC presentViewController:self animated:YES completion:nil];
    } else {
        // iPhone presents without system animation; custom animation is tied to keyboard
        [presentingVC presentViewController:self animated:NO completion:nil]; 
    }
}

@end 
