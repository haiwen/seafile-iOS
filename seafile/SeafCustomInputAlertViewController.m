//
//  SeafCustomInputAlertViewController.m
//  Seafile
//

#import "SeafCustomInputAlertViewController.h"
#import "Debug.h"
#import "SeafTheme.h"

@interface SeafCustomInputAlertViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UIView *alertView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UITextField *inputTextField;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *confirmButton;
@property (nonatomic, strong) UIView *backgroundDimmingView;

// For keyboard-aware animation
@property (nonatomic, strong) NSLayoutConstraint *alertViewBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *alertViewCenterYConstraint; // Center Y constraint for iPad keyboard adjustments
@property (nonatomic, assign) BOOL isBeingDismissedProgrammatically;
@property (nonatomic, strong) id finalCompletionHandler; // To store either confirm or cancel block

@end

// Define a constant for the initial off-screen position to make it clear
static CGFloat const kInitialOffScreenBottomConstant = 350.0; // Adjust if alert can be very tall
// iPad: centered card width, and the minimum gap to the window edges and keyboard.
static CGFloat const kIpadAlertWidth = 450.0;
static CGFloat const kIpadAlertMargin = 20.0;

@implementation SeafCustomInputAlertViewController

#pragma mark - Lazy Initializers

- (UIView *)backgroundDimmingView {
    if (!_backgroundDimmingView) {
        // This view is primarily for iPhone's custom presentation.
        // Its frame is set to self.view.bounds, and autoresizingMask handles resizes.
        // This is safe as it's accessed within setupViews after self.view is loaded.
        _backgroundDimmingView = [[UIView alloc] initWithFrame:self.view.bounds];
        _backgroundDimmingView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        _backgroundDimmingView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    return _backgroundDimmingView;
}

- (UIView *)alertView {
    if (!_alertView) {
        _alertView = [[UIView alloc] init];
        _alertView.backgroundColor = [SeafTheme primarySurface];
        _alertView.layer.masksToBounds = YES;
        _alertView.translatesAutoresizingMaskIntoConstraints = NO;
        if (IsIpad()) {
            _alertView.layer.cornerRadius = 14.0; // Standard corner radius for alerts/sheets
        } else {
            _alertView.layer.cornerRadius = 14.0;
            _alertView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        }
    }
    return _alertView;
}

- (UILabel *)titleLabel {
    if (!_titleLabel) {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = self.alertTitle; // Assumes self.alertTitle is set during init
        _titleLabel.font = [UIFont systemFontOfSize:17.0];
        _titleLabel.textColor = [SeafTheme primaryText];
        _titleLabel.textAlignment = NSTextAlignmentLeft;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return _titleLabel;
}

- (UITextField *)inputTextField {
    if (!_inputTextField) {
        _inputTextField = [[UITextField alloc] init];
        _inputTextField.placeholder = self.placeholderText; // Assumes self.placeholderText is set
        _inputTextField.text = self.initialInputText;     // Assumes self.initialInputText is set
        _inputTextField.font = [UIFont systemFontOfSize:14.0];
        _inputTextField.borderStyle = UITextBorderStyleNone;
        _inputTextField.autocorrectionType = UITextAutocorrectionTypeNo;
        _inputTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
        _inputTextField.delegate = self;
        _inputTextField.returnKeyType = UIReturnKeyDone;
        _inputTextField.layer.borderWidth = 0;
        _inputTextField.layer.cornerRadius = 6.0;
        _inputTextField.backgroundColor = [SeafTheme fill];
        UIView *paddingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
        _inputTextField.leftView = paddingView;
        _inputTextField.leftViewMode = UITextFieldViewModeAlways;
        UIView *paddingRightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
        _inputTextField.rightView = paddingRightView;
        _inputTextField.rightViewMode = UITextFieldViewModeAlways;
        _inputTextField.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return _inputTextField;
}

- (UIButton *)cancelButton {
    if (!_cancelButton) {
        _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_cancelButton setTitle:NSLocalizedString(@"Cancel", @"Cancel button title") forState:UIControlStateNormal];
        [_cancelButton setTitleColor:[SeafTheme primaryText] forState:UIControlStateNormal];
        _cancelButton.titleLabel.font = [UIFont systemFontOfSize:17.0];
        _cancelButton.backgroundColor = [SeafTheme primarySurface];
        _cancelButton.layer.cornerRadius = 8.0;
        _cancelButton.layer.borderColor = [SeafTheme primaryText].CGColor;
        _cancelButton.layer.borderWidth = 1.0;
        [_cancelButton addTarget:self action:@selector(cancelButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return _cancelButton;
}

- (UIButton *)confirmButton {
    if (!_confirmButton) {
        _confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_confirmButton setTitle:NSLocalizedString(@"OK", @"Seafile") forState:UIControlStateNormal];
        [_confirmButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _confirmButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
        _confirmButton.backgroundColor = UIColor.orangeColor;
        _confirmButton.layer.cornerRadius = 8.0;
        [_confirmButton addTarget:self action:@selector(confirmButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        _confirmButton.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return _confirmButton;
}

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
            // Not a form sheet: on iOS 26 a form sheet draws its own material
            // background, which showed as a large gray panel around the card.
            // Present over the full screen and draw the dimming view here instead.
            self.modalPresentationStyle = UIModalPresentationOverFullScreen;
            self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
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
        self.view.backgroundColor = [UIColor clearColor]; // Dimming view + centered card

        [self setupViews]; // alertView needs to be created
        [self setupConstraints]; // alertView needs to be constrained
        // The cross-dissolve transition fades the dimming view and card in together.
        self.alertView.alpha = 1.0;
        self.backgroundDimmingView.alpha = 1.0;

        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleBackgroundTap:)];
        [self.backgroundDimmingView addGestureRecognizer:tapGesture];

        // Register for keyboard notifications so we can move the alert if it would be covered.
        [self registerForKeyboardNotifications];
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
    [self unregisterForKeyboardNotifications];
}

- (void)dealloc {
    [self unregisterForKeyboardNotifications]; // Ensure removed for all device types
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    // CGColor is a snapshot; re-apply so the cancel button border tracks the theme.
    if (_cancelButton) {
        _cancelButton.layer.borderColor = [SeafTheme primaryText].CGColor;
    }
}

- (void)setupViews {
    // Accessing self.backgroundDimmingView will trigger its lazy initializer.
    // The frame is set within the getter using self.view.bounds, which is available here.
    [self.view addSubview:self.backgroundDimmingView];

    // Accessing self.alertView will trigger its lazy initializer.
    // Properties like backgroundColor, cornerRadius are set in the getter.
    [self.view addSubview:self.alertView]; // alertView is always added to self.view

    // Add subviews to alertView. Accessing these properties triggers their lazy initializers.
    // Properties like text, font, colors, targets are set in their respective getters.
    [self.alertView addSubview:self.titleLabel];
    [self.alertView addSubview:self.inputTextField];
    [self.alertView addSubview:self.cancelButton];
    [self.alertView addSubview:self.confirmButton];
}

- (void)setupConstraints {
    // alertView constraints (leading/trailing for full width, bottom constraint for vertical positioning)
    if (IsIpad()) {
        // Keep a reference to the center-Y constraint so we can move the alert when the keyboard shows up.
        self.alertViewCenterYConstraint = [self.alertView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor];
        NSLayoutConstraint *preferredWidth = [self.alertView.widthAnchor constraintEqualToConstant:kIpadAlertWidth];
        preferredWidth.priority = UILayoutPriorityDefaultHigh; // Narrow windows win over the preferred width
        [NSLayoutConstraint activateConstraints:@[
            [self.alertView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            self.alertViewCenterYConstraint,
            preferredWidth,
            [self.alertView.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-2 * kIpadAlertMargin],
        ]]; // Do not fix height so it can expand with content
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
        [self.cancelButton.bottomAnchor constraintEqualToAnchor:self.alertView.bottomAnchor constant:-verticalPadding],
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
    NSDictionary *userInfo = notification.userInfo;
    CGRect keyboardFrameInScreen = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboardFrame = [self.view convertRect:keyboardFrameInScreen fromView:nil];
    NSTimeInterval animationDuration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions options = (([userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue]) << 16) | UIViewAnimationOptionBeginFromCurrentState;

    if (IsIpad()) {
        // Lift the centered card only as far as needed to clear the keyboard,
        // without pushing it above the top safe area.
        id<UICoordinateSpace> screenSpace = self.view.window.windowScene.screen.coordinateSpace;
        CGRect keyboardInView = screenSpace
            ? [self.view convertRect:keyboardFrameInScreen fromCoordinateSpace:screenSpace]
            : keyboardFrame;
        [self.view layoutIfNeeded];
        CGFloat cardHeight = CGRectGetHeight(self.alertView.bounds);
        if (cardHeight <= 0) {
            cardHeight = [self.alertView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
        }
        CGFloat midY = CGRectGetMidY(self.view.bounds);
        CGFloat overlap = (midY + cardHeight / 2.0) - (CGRectGetMinY(keyboardInView) - kIpadAlertMargin);
        CGFloat room = (midY - cardHeight / 2.0) - (self.view.safeAreaInsets.top + kIpadAlertMargin);
        CGFloat lift = MAX(0, MIN(overlap, room));
        self.alertViewCenterYConstraint.constant = -lift;

        [UIView animateWithDuration:animationDuration delay:0.0 options:options animations:^{
            [self.view layoutIfNeeded];
        } completion:nil];
    } else {
        // keyboardFrame.size.height doesn't change after convertRect; use origin.y instead
        // to get the actual overlap within self.view's coordinate system.
        CGFloat keyboardOverlap = self.view.bounds.size.height - keyboardFrame.origin.y;
        self.alertViewBottomConstraint.constant = -keyboardOverlap;
        [UIView animateWithDuration:animationDuration
                              delay:0.0
                            options:options
                         animations:^{
                             self.alertView.alpha = 1.0;
                             self.backgroundDimmingView.alpha = 1.0;
                             [self.view layoutIfNeeded];
                         } completion:nil];
    }
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSTimeInterval animationDuration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions options = (([userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue]) << 16) | UIViewAnimationOptionBeginFromCurrentState;

    if (IsIpad()) {
        self.alertViewCenterYConstraint.constant = 0; // Reset back to center
        [UIView animateWithDuration:animationDuration delay:0.0 options:options animations:^{
            [self.view layoutIfNeeded];
        } completion:nil];
    } else {
        self.alertViewBottomConstraint.constant = kInitialOffScreenBottomConstant;

        [UIView animateWithDuration:animationDuration
                              delay:0.0
                            options:options
                         animations:^{
                             self.alertView.alpha = 0.0;
                             self.backgroundDimmingView.alpha = 0.0;
                             [self.view layoutIfNeeded];
                         } completion:^(BOOL finished) {
                             if (self.isBeingDismissedProgrammatically) {
                                 [self dismissViewControllerAnimated:NO completion:^{
                                     if (self.finalCompletionHandler) {
                                         // Determine which handler to call
                                         if (self.cancelHandler == self.finalCompletionHandler) {
                                             ((void(^)(void))self.finalCompletionHandler)();
                                         } else if (self.completionHandler == self.finalCompletionHandler) {
                                             ((void(^)(NSString *))self.finalCompletionHandler)(self.inputTextField.text);
                                         }
                                     }
                                     self.isBeingDismissedProgrammatically = NO;
                                     self.finalCompletionHandler = nil;
                                 }];
                             }
                         }];
    }
}

#pragma mark - Actions

- (void)handleBackgroundTap:(UITapGestureRecognizer *)sender {
    // If tap is on background, treat as cancel
    if (sender.state == UIGestureRecognizerStateEnded) {
        if (IsIpad()) {
            [self cancelButtonTapped:nil];
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
