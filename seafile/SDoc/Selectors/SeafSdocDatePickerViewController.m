//  SeafSdocDatePickerViewController.m
//  Date & time picker presented as a bottom sheet (centered card on iPad).

#import "SeafSdocDatePickerViewController.h"

@interface SeafSdocDatePickerViewController ()
@property (nonatomic, copy) NSString *pickerTitle;
@property (nonatomic, strong) NSDate *initialDate;
@property (nonatomic, copy) SeafSdocDatePickerCompletion completion;
@property (nonatomic, strong) UIDatePicker *datePicker;
@end

@implementation SeafSdocDatePickerViewController

- (instancetype)initWithTitle:(NSString *)title
                  initialDate:(NSDate *)initialDate
                   completion:(SeafSdocDatePickerCompletion)completion
{
    if (self = [super init]) {
        _pickerTitle = [title copy];
        _initialDate = initialDate;
        _completion = [completion copy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // Bottom sheet on iPhone; centered card on iPad (align SeafTagSelectorViewController)
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[
                UISheetPresentationControllerDetent.mediumDetent,
                UISheetPresentationControllerDetent.largeDetent
            ];
            sheet.prefersGrabberVisible = YES;
            sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
        }
    }

    // Top toolbar: Cancel | Title | Done
    UIView *toolbar = [UIView new];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    toolbar.backgroundColor = [UIColor systemBackgroundColor];
    [self.view addSubview:toolbar];

    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancelBtn setTitle:NSLocalizedString(@"Cancel", @"cancel button") forState:UIControlStateNormal];
    cancelBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelBtn addTarget:self action:@selector(onCancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [toolbar addSubview:cancelBtn];

    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [doneBtn setTitle:NSLocalizedString(@"Done", @"done button") forState:UIControlStateNormal];
    doneBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    doneBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [doneBtn addTarget:self action:@selector(onDoneTapped) forControlEvents:UIControlEventTouchUpInside];
    [toolbar addSubview:doneBtn];

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = self.pickerTitle;
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbar addSubview:titleLabel];

    self.datePicker = [[UIDatePicker alloc] init];
    self.datePicker.datePickerMode = UIDatePickerModeDateAndTime;
    if (@available(iOS 13.4, *)) {
        self.datePicker.preferredDatePickerStyle = UIDatePickerStyleWheels;
    }
    if (self.initialDate) {
        self.datePicker.date = self.initialDate;
    }
    self.datePicker.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.datePicker];

    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],
        [toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:44],

        [cancelBtn.leadingAnchor constraintEqualToAnchor:toolbar.safeAreaLayoutGuide.leadingAnchor constant:16],
        [cancelBtn.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [doneBtn.trailingAnchor constraintEqualToAnchor:toolbar.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [doneBtn.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [titleLabel.centerXAnchor constraintEqualToAnchor:toolbar.centerXAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [self.datePicker.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:8],
        [self.datePicker.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [self.datePicker.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [self.datePicker.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [self.datePicker.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
    ]];
}

#pragma mark - Actions

- (void)onCancelTapped
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onDoneTapped
{
    if (self.completion) {
        self.completion(self.datePicker.date);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
