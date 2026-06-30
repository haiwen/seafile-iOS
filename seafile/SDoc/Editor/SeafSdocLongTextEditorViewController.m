//  SeafSdocLongTextEditorViewController.m
//  Align Android: LongTextSelectorActivity
//  Full-screen editor for long text (description) fields.
//  Layout: Cancel | Title | Done (blue)
//          Full-width UITextView with 24pt padding

#import "SeafSdocLongTextEditorViewController.h"

@interface SeafSdocLongTextEditorViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, copy) NSString *metadataKey;
@property (nonatomic, copy) NSString *initialText;
@property (nonatomic, copy) SeafLongTextEditorCompletion completion;
@property (nonatomic, strong) UITextView *textView;
@end

@implementation SeafSdocLongTextEditorViewController

- (instancetype)initWithKey:(NSString *)key
                      title:(NSString *)title
                initialText:(NSString *)text
                 completion:(SeafLongTextEditorCompletion)completion
{
    if (self = [super init]) {
        _metadataKey = [key copy];
        _initialText = [text copy] ?: @"";
        _completion = [completion copy];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Cancel button (left) — align Android: toolbar cancel
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Cancel", @"cancel button")
                                        style:UIBarButtonItemStylePlain
                                       target:self
                                       action:@selector(onCancel)];
    
    // Done button (right, blue) — align Android: toolbar done
    UIBarButtonItem *doneItem =
        [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Done", @"done button")
                                        style:UIBarButtonItemStyleDone
                                       target:self
                                       action:@selector(onDone)];
    doneItem.tintColor = [UIColor systemBlueColor];
    self.navigationItem.rightBarButtonItem = doneItem;
    
    // Full-screen text view — align Android: EditText with wrap_content, 24dp padding, 16sp
    self.textView = [[UITextView alloc] init];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.font = [UIFont systemFontOfSize:16]; // align Android: 16sp
    self.textView.textColor = [UIColor labelColor];
    self.textView.text = self.initialText;
    self.textView.textContainerInset = UIEdgeInsetsMake(16, 12, 16, 12); // align Android: padding inside border
    self.textView.backgroundColor = [UIColor systemBackgroundColor];
    self.textView.alwaysBounceVertical = YES;
    self.textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.textView.accessibilityIdentifier = @"longtext_editor_textview";
    
    // Border styling (align Android: shape_task_view_editable — #E0E5EC border, 4pt corner radius)
    self.textView.layer.cornerRadius = 4.0;
    self.textView.layer.masksToBounds = YES;
    self.textView.layer.borderWidth = 1.0;
    self.textView.layer.borderColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0x21/255.0 green:0x21/255.0 blue:0x21/255.0 alpha:1.0]
            : [UIColor colorWithRed:0xE0/255.0 green:0xE5/255.0 blue:0xEC/255.0 alpha:1.0];
    }].CGColor;
    
    [self.view addSubview:self.textView];
    
    // Horizontal anchors use the safe area (landscape notch); width is capped
    // on iPad so the editing column doesn't stretch edge-to-edge.
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *fullWidth = [self.textView.widthAnchor constraintEqualToAnchor:safeArea.widthAnchor constant:-32];
    fullWidth.priority = UILayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:16],
        [self.textView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor constant:-16],
        [self.textView.centerXAnchor constraintEqualToAnchor:safeArea.centerXAnchor],
        [self.textView.widthAnchor constraintLessThanOrEqualToConstant:700],
        fullWidth,
    ]];
    
    // Tap blank area to dismiss keyboard (align Android: clearFocus + hideSoftInput)
    UITapGestureRecognizer *tapDismiss = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTextViewBlankAreaTapped:)];
    tapDismiss.delegate = self;
    [self.textView addGestureRecognizer:tapDismiss];
    
    // Tap outside textView to dismiss keyboard
    UITapGestureRecognizer *tapOutside = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onOutsideTapped)];
    tapOutside.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapOutside];
    
    // Keyboard avoidance
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    
    // Auto-focus the text view
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.textView becomeFirstResponder];
    });
}

- (void)onOutsideTapped {
    [self.view endEditing:YES];
}

- (void)onCancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onDone {
    if (self.completion) {
        self.completion(self.metadataKey, self.textView.text ?: @"");
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Tap blank area to dismiss keyboard

/// Check if the tap point is in the blank area (below/outside text content)
- (BOOL)isTapInBlankArea:(CGPoint)point {
    UITextView *tv = self.textView;
    // Convert tap point to text container coordinates
    CGPoint textPoint = CGPointMake(point.x - tv.textContainerInset.left - tv.textContainer.lineFragmentPadding,
                                   point.y - tv.textContainerInset.top);
    
    // Get the character index at the tap point
    NSUInteger charIndex = [tv.layoutManager characterIndexForPoint:textPoint
                                                   inTextContainer:tv.textContainer
                          fractionOfDistanceBetweenInsertionPoints:NULL];
    
    // Get the bounding rect of the glyph at that index
    if (charIndex < tv.text.length) {
        CGRect glyphRect = [tv.layoutManager boundingRectForGlyphRange:NSMakeRange(charIndex, 1)
                                                       inTextContainer:tv.textContainer];
        // Offset glyphRect to textView coordinates
        glyphRect.origin.x += tv.textContainerInset.left;
        glyphRect.origin.y += tv.textContainerInset.top;
        
        // If the tap is within the glyph rect, it's on text, not blank
        if (CGRectContainsPoint(glyphRect, point)) {
            return NO;
        }
    }
    
    // Tap is beyond text content or outside glyph bounds → blank area
    return YES;
}

- (void)onTextViewBlankAreaTapped:(UITapGestureRecognizer *)tap {
    CGPoint point = [tap locationInView:self.textView];
    if ([self isTapInBlankArea:point]) {
        [self.textView resignFirstResponder];
    }
}

#pragma mark - UIGestureRecognizerDelegate

/// Decide at touch-down time whether the dismiss gesture participates at all.
/// This must be done here rather than in the tap action: the textView's
/// built-in tap begins editing (becomeFirstResponder) before our action
/// fires, so by then isFirstResponder is always YES and resigning would
/// kill the just-started editing session. At touchesBegan the state still
/// reflects whether the keyboard was up before this tap.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return self.textView.isFirstResponder;
}

/// Allow the tap gesture to work simultaneously with the textView's built-in gestures
/// so that normal text selection and cursor movement are not affected.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

#pragma mark - Keyboard avoidance

- (void)keyboardWillChangeFrame:(NSNotification *)notification {
    CGRect kbFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:kbFrame fromView:nil];
    CGFloat overlap = CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(converted);
    CGFloat bottomInset = MAX(0, overlap);
    
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    NSUInteger curve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue];
    
    [UIView animateWithDuration:duration delay:0 options:(curve << 16) animations:^{
        self.textView.contentInset = UIEdgeInsetsMake(0, 0, bottomInset, 0);
        self.textView.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, bottomInset, 0);
    } completion:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
