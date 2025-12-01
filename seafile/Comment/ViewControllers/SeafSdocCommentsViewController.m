//  SeafSdocCommentsViewController.m

#import "SeafSdocCommentsViewController.h"
#import "SeafDocCommentItem.h"
#import "SeafDocCommentCell.h"
#import "SeafDocCommentInputView.h"
#import "SDocPageOptionsModel.h"
#import "SeafDocsCommentService.h"
#import "SeafDocCommentParser.h"
#import "SeafDocCommentContentItem.h"
#import "SeafImageAttachment.h"
#import "SeafConnection.h"
#import "SeafActionSheet.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>
#import "SeafImagePreviewController.h"
#import "SeafDocCommentCell.h"
#import "SeafDataTaskManager.h"
#import "SVProgressHUD.h"
#import "SeafMentionSuggestionView.h"
#import "SeafSdocService.h"
#import "SeafGlobal.h"
#import "SeafMentionSheetViewController.h"
#import "SeafSdocUserMapper.h"

static NSString * const kSeafDocCommentCellId = @"kSeafDocCommentCellId";
static NSTimeInterval const kRelatedUsersCacheTTL = 300.0; // 5 minutes
static NSMutableDictionary<NSString *, NSArray<NSDictionary *> *> *gRelatedUsersCache;
static NSMutableDictionary<NSString *, NSDate *> *gRelatedUsersCacheTS;

@interface SeafSdocCommentsViewController () <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
, UIAdaptivePresentationControllerDelegate
#endif
>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) SeafDocCommentInputView *inputViewBar;

@property (nonatomic, strong) NSMutableArray<SeafDocCommentItem *> *items;

@property (nonatomic, strong) SeafDocsCommentService *service;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, strong) UITapGestureRecognizer *bgTap;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, assign) NSInteger pendingUploads;
@property (nonatomic, assign) CGFloat currentKeyboardOverlap;
@property (nonatomic, strong) NSMapTable<SeafImageAttachment *, UIButton *> *attachmentDeleteButtons;
@property (nonatomic, strong) NSMapTable<SeafImageAttachment *, UIView *> *attachmentLoadingOverlays;
@property (nonatomic, strong) NSMapTable<SeafImageAttachment *, NSDictionary *> *attachmentUploadPayloads; // { data, fileName, mime }
@property (nonatomic, assign) BOOL isPostingComment;
@property (nonatomic, assign) BOOL hasDoneInitialScrollToBottom;

// Mention suggestions
@property (nonatomic, strong) SeafMentionSuggestionView *mentionView;
@property (nonatomic, strong) NSArray<NSDictionary *> *mentionAllUsers;
@property (nonatomic, assign) BOOL mentionUsersLoaded;
@property (nonatomic, strong) SeafSdocService *sdocService;
@property (nonatomic, assign) NSRange currentMentionRange; // range of '@token' in plain string space
@property (nonatomic, strong) SeafMentionSheetViewController *mentionSheetVC;
@property (nonatomic, assign) BOOL isMentionSheetPresented;
@property (nonatomic, assign) NSUInteger lastPlainTextLength;
@property (nonatomic, assign) NSRange lastSelectedRange;

@end

@implementation SeafSdocCommentsViewController

 
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    _attachmentDeleteButtons = [NSMapTable strongToWeakObjectsMapTable];

    self.navigationItem.title = self.docDisplayName.length > 0 ? self.docDisplayName : NSLocalizedString(@"Comments", nil);
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(onClose)];

    _items = [NSMutableArray array];
    _service = [SeafDocsCommentService new];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    // Match unresolved comment cell background: #F5F5F5
    _tableView.backgroundColor = [UIColor colorWithRed:245.0/255.0 green:245.0/255.0 blue:245.0/255.0 alpha:1.0];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    // Allow dismissing keyboard by dragging
    if (@available(iOS 7.0, *)) {
        _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    }
    // Provide estimated height to reduce synchronous measurements on first render
    _tableView.estimatedRowHeight = 120.0;
    [_tableView registerClass:SeafDocCommentCell.class forCellReuseIdentifier:kSeafDocCommentCellId];
    [self.view addSubview:_tableView];

    _refreshControl = [UIRefreshControl new];
    [_refreshControl addTarget:self action:@selector(onPullRefresh) forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 10.0, *)) {
        _tableView.refreshControl = _refreshControl;
    } else {
        [_tableView addSubview:_refreshControl];
    }

    _emptyView = [self buildEmptyView];

    _inputViewBar = [[SeafDocCommentInputView alloc] initWithFrame:CGRectZero];
    __weak typeof(self) wself = self;
    _inputViewBar.onTapPhoto = ^{ [wself onTapPhoto]; };
    _inputViewBar.onTapSend = ^(NSString * _Nonnull text) { [wself onTapSend:text]; };
    [self.view addSubview:_inputViewBar];

    // Mention view
    _mentionView = [SeafMentionSuggestionView new];
    __weak typeof(_mentionView) wMention = _mentionView;
    _mentionView.onSelectUser = ^(NSDictionary *user) {
        __strong typeof(wself) sself = wself; if (!sself) return;
        [sself insertMentionUser:user];
        [wMention hide];
    };
    [self.view addSubview:_mentionView];
    _mentionUsersLoaded = NO;
    _sdocService = [[SeafSdocService alloc] initWithConnection:self.connection ?: [SeafGlobal sharedObject].connection];

    // Remove risky KVO; rely on viewDidLayoutSubviews and text-change notifications to drive layout

    // Compatibility: do not rely on onTextDidChange; observe text change notifications instead
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_onInputTextChanged:)
                                                 name:UITextViewTextDidChangeNotification
                                               object:_inputViewBar.textView];

    [self registerKeyboardNotifications];

    // initial load
    [self loadComments];

    // tap to dismiss keyboard when tapping background/table area
    _bgTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onBackgroundTapped:)];
    _bgTap.cancelsTouchesInView = NO; // allow taps to pass through to cells/buttons
    _bgTap.delegate = self;
    _bgTap.numberOfTapsRequired = 1;
    [self.view addGestureRecognizer:_bgTap];

    // placeholder initial state
    [_inputViewBar updatePlaceholderVisibility];

    // loading indicator
    if (!_loadingIndicator) {
        UIActivityIndicatorViewStyle style = UIActivityIndicatorViewStyleMedium;
        if (@available(iOS 13.0, *)) style = UIActivityIndicatorViewStyleMedium; else style = UIActivityIndicatorViewStyleGray;
        _loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:style];
        _loadingIndicator.hidesWhenStopped = YES;
        _loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:_loadingIndicator];
        [NSLayoutConstraint activateConstraints:@[
            [_loadingIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [_loadingIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
        ]];
    }
    
    // Init mention change tracking
    _lastPlainTextLength = _inputViewBar.textView.text.length;
    _lastSelectedRange = _inputViewBar.textView.selectedRange;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    // Keep input bar at the correct position depending on current keyboard overlap
    [self layoutBottomBarForKeyboardHeight:self.currentKeyboardOverlap animated:NO];
    // Also refresh overlay delete buttons position after layout changes
    [self updateAttachmentDeleteButtonsLayout];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    // Ensure baseline layout is correct before first keyboard show
    [self layoutBottomBarForKeyboardHeight:0 animated:NO];
}

- (void)layoutBottomBarForKeyboardHeight:(CGFloat)kbHeight animated:(BOOL)animated
{
    CGSize sz = self.view.bounds.size;
    CGFloat inputContentH = [_inputViewBar intrinsicContentSize].height;
    CGFloat safeBottom = 0;
    if (@available(iOS 11.0, *)) safeBottom = self.view.safeAreaInsets.bottom;

    // Input bar intrinsic now returns pure content height:
    // - No keyboard: add safeBottom, align to bottom without being covered by Home Indicator
    // - With keyboard: do not add safeBottom; stick to the top of the keyboard
    CGFloat inputHForLayout = (kbHeight > 0) ? inputContentH : (inputContentH + safeBottom);

    // When no keyboard, keep a small extra inset so the last row is not tight to the input bar; with keyboard, add no extra padding
    CGFloat extraContentInsetNoKb = 8.0;

    void (^changes)(void) = ^{
        // Always ensure table view fills the view; insets will provide spacing
        self->_tableView.frame = CGRectMake(0, 0, sz.width, sz.height);
        if (kbHeight > 0) {
            self->_inputViewBar.frame = CGRectMake(0, sz.height - inputHForLayout - kbHeight, sz.width, inputHForLayout);
            self->_tableView.contentInset = UIEdgeInsetsMake(0, 0, inputHForLayout + kbHeight, 0);
        } else {
            self->_inputViewBar.frame = CGRectMake(0, sz.height - inputHForLayout, sz.width, inputHForLayout);
            self->_tableView.contentInset = UIEdgeInsetsMake(0, 0, inputHForLayout + extraContentInsetNoKb, 0);
        }
        self->_tableView.scrollIndicatorInsets = self->_tableView.contentInset;
    };
    if (animated) {
        [UIView animateWithDuration:0.25 animations:changes];
    } else {
        changes();
    }
}

#pragma mark - Build Empty View
- (UIView *)buildEmptyView
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
    // Match Android layout_empty.xml margins: top/bottom 64dp, horizontal 16dp
    v.layoutMargins = UIEdgeInsetsMake(64, 16, 64, 16);

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 20; // Match Android TextView layout_marginTop=20dp
    // Add internal padding 30dp equivalent
    stack.layoutMargins = UIEdgeInsetsMake(30, 30, 30, 30);
    stack.layoutMarginsRelativeArrangement = YES;
    [v addSubview:stack];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:v.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:v.layoutMarginsGuide.trailingAnchor],
        [stack.topAnchor constraintGreaterThanOrEqualToAnchor:v.layoutMarginsGuide.topAnchor],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:v.layoutMarginsGuide.bottomAnchor],
        [stack.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:v.centerYAnchor constant:0.0]
    ]];

    UIImageView *img = [[UIImageView alloc] initWithFrame:CGRectZero];
    // Prefer Android drawable name if available; fallback to SF Symbol
    UIImage *tipImage = [UIImage imageNamed:@"tip_no_items"];
    if (tipImage) {
        img.image = tipImage;
    } else if (@available(iOS 13.0, *)) {
        img.image = [UIImage systemImageNamed:@"tray"];
        img.tintColor = [UIColor tertiaryLabelColor];
    }
    img.contentMode = UIViewContentModeScaleAspectFit;
    img.translatesAutoresizingMaskIntoConstraints = NO;
    [img.widthAnchor constraintEqualToConstant:100].active = YES;
    [img.heightAnchor constraintEqualToConstant:100].active = YES;

    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectZero];
    // Strictly align with Android string key if present
    NSString *androidEmpty = NSLocalizedString(@"empty_data", nil);
    if (androidEmpty.length == 0 || [androidEmpty isEqualToString:@"empty_data"]) {
        androidEmpty = NSLocalizedString(@"No comments", nil);
    }
    lab.text = androidEmpty;
    lab.textColor = [UIColor labelColor];
    lab.textAlignment = NSTextAlignmentCenter;
    lab.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    lab.numberOfLines = 0;

    [stack addArrangedSubview:img];
    [stack addArrangedSubview:lab];

    // Tap empty view to retry
    v.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onEmptyViewTapped:)];
    [v addGestureRecognizer:tap];
    return v;
}

#pragma mark - Actions
- (void)onClose {
    // Before closing, cancel all comment image downloads via the data task manager
    [[SeafDataTaskManager sharedObject] cancelAllCommentImageDownloads:self.connection];
    // Clean overlays and delete buttons in the input area to avoid retained views
    @try {
        NSEnumerator *btnEnum = [_attachmentDeleteButtons objectEnumerator];
        UIButton *btn = nil;
        while ((btn = [btnEnum nextObject])) { [btn removeFromSuperview]; }
        [_attachmentDeleteButtons removeAllObjects];
    } @catch (__unused NSException *e) {}
    @try {
        if (_attachmentLoadingOverlays) {
            for (SeafImageAttachment *key in _attachmentLoadingOverlays) {
                UIView *v = [_attachmentLoadingOverlays objectForKey:key];
                if (v) [v removeFromSuperview];
            }
            [_attachmentLoadingOverlays removeAllObjects];
        }
    } @catch (__unused NSException *e) {}
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onPullRefresh
{
    [self loadComments];
}

- (void)onEmptyViewTapped:(UITapGestureRecognizer *)gr
{
    if (gr.state == UIGestureRecognizerStateRecognized) {
        [self loadComments];
    }
}

- (void)onTapPhoto
{
    // Simple image picker: PHPicker preferred
    __weak typeof(self) wself = self;
    void (^presentLegacyPicker)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself; if (!sself) return;
            UIImagePickerController *picker = [UIImagePickerController new];
            picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            picker.modalPresentationStyle = UIModalPresentationFullScreen;
            picker.delegate = (id<UINavigationControllerDelegate, UIImagePickerControllerDelegate>)sself;
            [sself presentViewController:picker animated:YES completion:nil];
        });
    };
    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
        config.selectionLimit = 1;
        config.filter = [PHPickerFilter imagesFilter];
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
        picker.delegate = (id<PHPickerViewControllerDelegate>)self;
        [self presentViewController:picker animated:YES completion:nil];
    } else {
        PHAuthorizationStatus st = [PHPhotoLibrary authorizationStatus];
        if (st == PHAuthorizationStatusAuthorized) {
            presentLegacyPicker();
        } else if (st == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                if (status == PHAuthorizationStatusAuthorized) presentLegacyPicker();
            }];
        } else {
            // no-op
        }
    }
}

- (void)onTapSend:(NSString *)text
{
    // Only block duplicate sends, not image uploads
    if (self.isPostingComment) return;
    if (self.pageOptions.docUuid.length == 0 || self.pageOptions.seadocServerUrl.length == 0 || self.pageOptions.seadocAccessToken.length == 0) return;
    // Serialize attributed content into markdown string (text + images with uploadedURL)
    NSMutableString *md = [NSMutableString string];
    NSAttributedString *attr = self->_inputViewBar.textView.attributedText ?: [[NSAttributedString alloc] initWithString:self->_inputViewBar.textView.text ?: @""];
    __block NSInteger attachmentCount = 0;
    __block NSInteger uploadedUrlCount = 0;
    __block NSMutableArray<NSString *> *urls = [NSMutableArray array];
    [attr enumerateAttributesInRange:NSMakeRange(0, attr.length) options:0 usingBlock:^(NSDictionary<NSAttributedStringKey,id> *attrs, NSRange range, BOOL *stop) {
        id att = attrs[NSAttachmentAttributeName];
        if ([att isKindOfClass:[SeafImageAttachment class]]) {
            SeafImageAttachment *imgAtt = (SeafImageAttachment *)att;
            attachmentCount += 1;
            if (imgAtt.uploadedURL.length > 0) {
                uploadedUrlCount += 1;
                [md appendFormat:@"![](%@)\n\n", imgAtt.uploadedURL];
                [urls addObject:imgAtt.uploadedURL];
            }
        } else {
            NSString *s = [[attr attributedSubstringFromRange:range] string];
            if (s.length > 0) {
                [md appendString:s];
            }
        }
    }];
    
    // Block send if there are images not uploaded yet (show alert with OK)
    if (attachmentCount > uploadedUrlCount) {
        [self showOKAlert:NSLocalizedString(@"Please wait until the image upload is complete and try again.", nil)];
        return;
    }
    NSString *finalText = md.length > 0 ? md.copy : (text ?: @"");
    if ([[finalText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
        
        [self showToast:NSLocalizedString(@"Content is empty", nil)];
        return;
    }
    
    // Enter posting state: disable Send immediately and show loading spinner
    self.isPostingComment = YES;
    [self->_inputViewBar setSendEnabled:NO];
    if (self.loadingIndicator) {
        [self.loadingIndicator startAnimating];
    }
    [_service postCommentForDocUUID:self.pageOptions.docUuid
                        seadocServer:self.pageOptions.seadocServerUrl
                               token:self.pageOptions.seadocAccessToken
                             comment:finalText
                              author:@""
                           updatedAt:@""
                          completion:^(NSDictionary * _Nullable resp, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isPostingComment = NO;
            if (self.loadingIndicator) {
                [self.loadingIndicator stopAnimating];
            }
            if (!error) {
                
                // Clear input content (ensure attachments removed)
                self->_inputViewBar.textView.attributedText = [[NSAttributedString alloc] initWithString:@""];
                self->_inputViewBar.textView.text = @"";
                // Reset mention tracking state so next '@' can trigger immediately
                self.lastPlainTextLength = 0;
                self.lastSelectedRange = NSMakeRange(0, 0);
                [self hideMentionUI];
                // Reset scroll position to top
                self->_inputViewBar.textView.contentOffset = CGPointZero;
                // Remove any remaining overlay buttons
                if (self.attachmentDeleteButtons) {
                    NSMutableArray<SeafImageAttachment *> *keys = [NSMutableArray array];
                    NSEnumerator *e = self.attachmentDeleteButtons.keyEnumerator;
                    SeafImageAttachment *k = nil;
                    while ((k = [e nextObject])) { if (k) [keys addObject:k]; }
                    for (SeafImageAttachment *ak in keys) {
                        UIButton *btn = [self.attachmentDeleteButtons objectForKey:ak];
                        if (btn) [btn removeFromSuperview];
                        [self.attachmentDeleteButtons removeObjectForKey:ak];
                    }
                }
                // Force height recalculation and layout
                // Toggle scrollEnabled to ensure UITextView recalculates its intrinsic height immediately
                self->_inputViewBar.textView.scrollEnabled = NO;
                [self->_inputViewBar invalidateIntrinsicContentSize];
                [self->_inputViewBar setNeedsLayout];
                [self->_inputViewBar layoutIfNeeded];
                [self.view setNeedsLayout];
                [self.view layoutIfNeeded];
                [self layoutBottomBarForKeyboardHeight:self.currentKeyboardOverlap animated:NO];
                self->_inputViewBar.textView.scrollEnabled = YES;
                [self updateAttachmentDeleteButtonsLayout];
                [self->_inputViewBar setSendEnabled:NO];
                [self->_inputViewBar updatePlaceholderVisibility];
                [self loadComments];
            } else {
                
                [self updateSendEnabledState];
            }
        });
    }];
}

- (void)reloadAndScrollToBottom
{
    [_tableView reloadData];
    // fade-in animation for visible cells for a smoother feel
    NSArray<NSIndexPath *> *ips = [_tableView indexPathsForVisibleRows];
    for (NSIndexPath *ip in ips) {
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:ip];
        cell.alpha = 0.0;
        [UIView animateWithDuration:0.2 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{ cell.alpha = 1.0; } completion:nil];
    }
    if (_items.count > 0) {
        NSIndexPath *last = [NSIndexPath indexPathForRow:_items.count - 1 inSection:0];
        [_tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    }
}

// Determine whether two comment items are content-equal (aligns with Android areContentsTheSame)
- (BOOL)_commentItem:(SeafDocCommentItem *)a equalsTo:(SeafDocCommentItem *)b
{
    if (!a || !b) return NO;
    if (a.commentId != b.commentId) return NO;
    BOOL same = YES;
    same = same && (a.resolved == b.resolved);
    same = same && ((a.timeString ?: @"").length == (b.timeString ?: @"").length ? [a.timeString ?: @"" isEqualToString:b.timeString ?: @""] : NO);
    same = same && ((a.avatarURL ?: @"").length == (b.avatarURL ?: @"").length ? [a.avatarURL ?: @"" isEqualToString:b.avatarURL ?: @""] : NO);
    same = same && ((a.author ?: @"").length == (b.author ?: @"").length ? [a.author ?: @"" isEqualToString:b.author ?: @""] : NO);
    // Coarse content comparison: same count and each item is same type with identical string content
    if (same) {
        NSArray *ac = a.contentItems ?: @[];
        NSArray *bc = b.contentItems ?: @[];
        if (ac.count != bc.count) return NO;
        for (NSUInteger i = 0; i < ac.count; i++) {
            SeafDocCommentContentItem *ai = ac[i];
            SeafDocCommentContentItem *bi = bc[i];
            if (ai.type != bi.type) return NO;
            NSString *as = ai.content ?: @"";
            NSString *bs = bi.content ?: @"";
            if (![as isEqualToString:bs]) return NO;
        }
    }
    return same;
}

// Simplified diff:
// 1) Only appended at tail => insertRows
// 2) Same count and order => reloadRows (content-only changes)
// 3) Otherwise => full reload
- (void)_applyDiffWithNewItems:(NSArray<SeafDocCommentItem *> *)newItems scrollToBottom:(BOOL)scroll
{
    NSArray<SeafDocCommentItem *> *oldItems = _items ?: @[];
    NSInteger oldCount = oldItems.count;
    NSInteger newCount = newItems.count;

    // On initial load (no old items), avoid per-row insert animations that cause heavy layout/animation cost
    if (oldCount == 0) {
        _items = [newItems mutableCopy];
        [UIView performWithoutAnimation:^{
            [_tableView reloadData];
        }];
        if (scroll && newCount > 0) {
            NSIndexPath *last = [NSIndexPath indexPathForRow:newCount - 1 inSection:0];
            // Scroll to bottom without animation to keep the initial frame smooth
            [_tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        }
        return;
    }

    // Build id -> index map
    NSMutableDictionary<NSNumber *, NSNumber *> *oldIndexById = [NSMutableDictionary dictionaryWithCapacity:oldCount];
    for (NSInteger i = 0; i < oldCount; i++) {
        SeafDocCommentItem *it = oldItems[i];
        if (it) oldIndexById[@(it.commentId)] = @(i);
    }
    NSMutableDictionary<NSNumber *, NSNumber *> *newIndexById = [NSMutableDictionary dictionaryWithCapacity:newCount];
    for (NSInteger i = 0; i < newCount; i++) {
        SeafDocCommentItem *it = newItems[i];
        if (it) newIndexById[@(it.commentId)] = @(i);
    }

    // Compute deletes/inserts/reloads
    NSMutableArray<NSIndexPath *> *deletes = [NSMutableArray array];
    for (NSInteger i = 0; i < oldCount; i++) {
        SeafDocCommentItem *it = oldItems[i];
        if (!newIndexById[@(it.commentId)]) {
            [deletes addObject:[NSIndexPath indexPathForRow:i inSection:0]];
        }
    }
    NSMutableArray<NSIndexPath *> *inserts = [NSMutableArray array];
    for (NSInteger i = 0; i < newCount; i++) {
        SeafDocCommentItem *it = newItems[i];
        if (!oldIndexById[@(it.commentId)]) {
            [inserts addObject:[NSIndexPath indexPathForRow:i inSection:0]];
        }
    }
    NSMutableArray<NSIndexPath *> *reloads = [NSMutableArray array];
    // Content changed: exists in both and differs
    for (NSNumber *cid in newIndexById) {
        NSNumber *oldIdx = oldIndexById[cid];
        NSNumber *newIdx = newIndexById[cid];
        if (oldIdx && newIdx) {
            SeafDocCommentItem *oldIt = oldItems[oldIdx.integerValue];
            SeafDocCommentItem *newIt = newItems[newIdx.integerValue];
            if (![self _commentItem:oldIt equalsTo:newIt]) {
                [reloads addObject:[NSIndexPath indexPathForRow:newIdx.integerValue inSection:0]];
            }
        }
    }

    // If no change, likely the same ordering => finish and scroll as needed
    if (deletes.count == 0 && inserts.count == 0 && reloads.count == 0) {
        _items = [newItems mutableCopy];
        if (scroll && newCount > 0) {
            NSIndexPath *last = [NSIndexPath indexPathForRow:newCount - 1 inSection:0];
            [_tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        }
        return;
    }

    // Update data source and batch update the table
    _items = [newItems mutableCopy];
    [_tableView beginUpdates];
    if (deletes.count > 0) {
        [_tableView deleteRowsAtIndexPaths:deletes withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    if (inserts.count > 0) {
        [_tableView insertRowsAtIndexPaths:inserts withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    if (reloads.count > 0) {
        [_tableView reloadRowsAtIndexPaths:reloads withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    [_tableView endUpdates];

    if (scroll && newCount > 0) {
        NSIndexPath *last = [NSIndexPath indexPathForRow:newCount - 1 inSection:0];
        [_tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    }
}

- (void)loadComments
{
    if (self.isLoading) return;
    if (self.pageOptions.docUuid.length == 0 || self.pageOptions.seadocServerUrl.length == 0 || self.pageOptions.seadocAccessToken.length == 0) {
        if (_refreshControl.isRefreshing) [_refreshControl endRefreshing];
        return;
    }
    self.isLoading = YES;
    [self showLoading:YES];
    __weak typeof(self) wself = self;
    [_service getCommentsWithDocUUID:self.pageOptions.docUuid
                        seadocServer:self.pageOptions.seadocServerUrl
                               token:self.pageOptions.seadocAccessToken
                           completion:^(NSDictionary * _Nullable resp, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself; if (!sself) return;
            sself.isLoading = NO;
            [sself showLoading:NO];
            if (sself->_refreshControl.isRefreshing) [sself->_refreshControl endRefreshing];
            if (error || ![resp isKindOfClass:[NSDictionary class]]) {
                if (sself->_items.count == 0) {
                    sself->_tableView.backgroundView = sself->_emptyView;
                    [sself->_tableView reloadData];
                } else {
                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Network unavailable", nil)];
                }
                return;
            }
            id listObj = resp[@"comments"];
            if (![listObj isKindOfClass:[NSArray class]]) listObj = @[];
            NSArray *list = (NSArray *)listObj;

            // Offload CPU-intensive parsing, time conversion, and sorting to a background queue
            __weak typeof(sself) wwself = sself;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                __strong typeof(wwself) s2 = wwself; if (!s2) return;
                NSMutableArray<SeafDocCommentItem *> *arr = [NSMutableArray arrayWithCapacity:list.count];
                // Use local date formatters to avoid thread-safety issues with shared singletons
                NSISO8601DateFormatter *isoFmt = nil;
                if (@available(iOS 10.0, *)) {
                    isoFmt = [NSISO8601DateFormatter new];
                }
                NSDateFormatter *fallbackFmt = [NSDateFormatter new];
                fallbackFmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
                NSArray<NSString *> *fmts = @[ @"yyyy-MM-dd'T'HH:mm:ssXXXXX",
                                               @"yyyy-MM-dd HH:mm:ss",
                                               @"yyyy/MM/dd HH:mm:ss" ];
                NSDateFormatter *outputFmt = [NSDateFormatter new];
                outputFmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
                outputFmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";

                for (NSDictionary *c in list) {
                    if (![c isKindOfClass:[NSDictionary class]]) continue;
                    long long cid = [[c valueForKey:@"id"] longLongValue];
                    NSString *author = [c valueForKey:@"user_name"] ?: @"";
                    NSString *avatarURL = [c valueForKey:@"avatar_url"] ?: @"";
                    NSString *time = [c valueForKey:@"created_at"] ?: @"";
                    BOOL resolved = [[c valueForKey:@"resolved"] boolValue];
                    NSString *comment = [c valueForKey:@"comment"] ?: @"";

                    NSArray<SeafDocCommentContentItem *> *contentItems = [SeafDocCommentParser parseCommentToContentItems:comment];

                    NSDate *createdAt = nil;
                    if (time.length > 0) {
                        if (@available(iOS 10.0, *)) {
                            createdAt = [isoFmt dateFromString:time];
                        }
                        if (!createdAt) {
                            for (NSString *f in fmts) {
                                fallbackFmt.dateFormat = f;
                                createdAt = [fallbackFmt dateFromString:time];
                                if (createdAt) break;
                            }
                        }
                    }
                    NSString *displayTime = time;
                    if (createdAt) {
                        displayTime = [outputFmt stringFromDate:createdAt] ?: time;
                    }

                    SeafDocCommentItem *item = [SeafDocCommentItem itemWithAuthor:author
                                                                        avatarURL:avatarURL
                                                                       timeString:displayTime
                                                                     contentItems:contentItems
                                                                           itemId:cid
                                                                         resolved:resolved];
                    item.createdAtDate = createdAt;
                    [arr addObject:item];
                }

                [arr sortUsingComparator:^NSComparisonResult(SeafDocCommentItem *a, SeafDocCommentItem *b) {
                    if (a.createdAtDate && b.createdAtDate) {
                        return [a.createdAtDate compare:b.createdAtDate];
                    } else if (a.createdAtDate) {
                        return NSOrderedAscending;
                    } else if (b.createdAtDate) {
                        return NSOrderedDescending;
                    } else if (a.commentId != b.commentId) {
                        return (a.commentId < b.commentId) ? NSOrderedAscending : NSOrderedDescending;
                    } else {
                        return [a.timeString compare:b.timeString];
                    }
                }];

                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(wwself) s3 = wwself; if (!s3) return;
                    s3->_tableView.backgroundView = (arr.count == 0 ? s3->_emptyView : nil);
                    [s3 _applyDiffWithNewItems:arr.copy scrollToBottom:YES];
                });
            });
        });
    }];
}

- (void)showLoading:(BOOL)loading
{
    if (loading) {
        // When user pull-to-refresh, only show the top UIRefreshControl spinner; do not show center loading
        BOOL isPullRefreshing = NO;
        if (_refreshControl) {
            isPullRefreshing = _refreshControl.isRefreshing;
        } else if (@available(iOS 10.0, *)) {
            isPullRefreshing = _tableView.refreshControl.isRefreshing;
        }
        // For first load or non pull-to-refresh, use local loadingIndicator to avoid center HUD animation impacting the first frame
        if (!isPullRefreshing) {
            if (_loadingIndicator) {
                [_loadingIndicator startAnimating];
            }
            [SVProgressHUD dismiss];
        } else {
            [SVProgressHUD dismiss];
        }
        _tableView.backgroundView = nil; // disable empty state during load
    } else {
        if (_loadingIndicator) {
            [_loadingIndicator stopAnimating];
        }
        [SVProgressHUD dismiss];
    }
}

- (void)updateSendEnabledState
{
    BOOL hasText = self->_inputViewBar.textView.text.length > 0;
    __block BOOL hasUploadedImage = NO;
    NSAttributedString *attr = self->_inputViewBar.textView.attributedText;
    if (attr.length > 0) {
        [attr enumerateAttribute:NSAttachmentAttributeName inRange:NSMakeRange(0, attr.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
            if ([value isKindOfClass:[SeafImageAttachment class]]) {
                SeafImageAttachment *att = (SeafImageAttachment *)value;
                if (att.uploadedURL.length > 0) { hasUploadedImage = YES; *stop = YES; }
            }
        }];
    }
    // Align Android behavior: keep Send enabled if there is any text or at least one uploaded image,
    // even when other images are still uploading.
    // If currently posting, always keep send disabled to avoid duplicate taps
    BOOL enable = (!self.isPostingComment) && (hasText || hasUploadedImage);
    [self->_inputViewBar setSendEnabled:enable];
}

// Format to absolute time "2024-01-15 14:30:00"
- (NSString *)formatAbsoluteTimeFromString:(NSString *)timeStr
{
    if (timeStr.length == 0) return nil;
    NSDate *date = nil;
    if (@available(iOS 10.0, *)) {
        static NSISO8601DateFormatter *isoFmt;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{ isoFmt = [NSISO8601DateFormatter new]; });
        date = [isoFmt dateFromString:timeStr];
    }
    if (!date) {
        // common fallback patterns
        NSArray<NSString *> *fmts = @[ @"yyyy-MM-dd'T'HH:mm:ssXXXXX",
                                       @"yyyy-MM-dd HH:mm:ss",
                                       @"yyyy/MM/dd HH:mm:ss" ];
        NSDateFormatter *df = [NSDateFormatter new];
        df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        for (NSString *f in fmts) {
            df.dateFormat = f;
            date = [df dateFromString:timeStr];
            if (date) break;
        }
    }
    if (!date) return nil;
    
    // Replace "T" with a space (ISO_LOCAL_DATE_TIME)
    // Format: "2024-01-15 14:30:00"
    static NSDateFormatter *outputFormatter;
    static dispatch_once_t onceToken2;
    dispatch_once(&onceToken2, ^{
        outputFormatter = [[NSDateFormatter alloc] init];
        outputFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        outputFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    return [outputFormatter stringFromDate:date];
}

// Parse string into NSDate (same fallback formats as relativeTime/format)
- (NSDate *)parseDateFromString:(NSString *)timeStr
{
    if (timeStr.length == 0) return nil;
    NSDate *date = nil;
    if (@available(iOS 10.0, *)) {
        static NSISO8601DateFormatter *isoFmt;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{ isoFmt = [NSISO8601DateFormatter new]; });
        date = [isoFmt dateFromString:timeStr];
    }
    if (!date) {
        NSArray<NSString *> *fmts = @[ @"yyyy-MM-dd'T'HH:mm:ssXXXXX",
                                       @"yyyy-MM-dd HH:mm:ss",
                                       @"yyyy/MM/dd HH:mm:ss" ];
        NSDateFormatter *df = [NSDateFormatter new];
        df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        for (NSString *f in fmts) {
            df.dateFormat = f;
            date = [df dateFromString:timeStr];
            if (date) break;
        }
    }
    return date;
}

// Format NSDate into an absolute time string
- (NSString *)stringFromDateAbsolute:(NSDate *)date
{
    if (!date) return nil;
    static NSDateFormatter *outputFormatter;
    static dispatch_once_t onceToken2;
    dispatch_once(&onceToken2, ^{
        outputFormatter = [[NSDateFormatter alloc] init];
        outputFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        outputFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    return [outputFormatter stringFromDate:date];
}

// Keep relative time method for other usage
- (NSString *)relativeTimeFromString:(NSString *)timeStr
{
    if (timeStr.length == 0) return nil;
    NSDate *date = nil;
    if (@available(iOS 10.0, *)) {
        static NSISO8601DateFormatter *isoFmt;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{ isoFmt = [NSISO8601DateFormatter new]; });
        date = [isoFmt dateFromString:timeStr];
    }
    if (!date) {
        // common fallback patterns
        NSArray<NSString *> *fmts = @[ @"yyyy-MM-dd'T'HH:mm:ssXXXXX",
                                       @"yyyy-MM-dd HH:mm:ss",
                                       @"yyyy/MM/dd HH:mm:ss" ];
        NSDateFormatter *df = [NSDateFormatter new];
        df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        for (NSString *f in fmts) {
            df.dateFormat = f;
            date = [df dateFromString:timeStr];
            if (date) break;
        }
    }
    if (!date) return nil;
    NSTimeInterval diff = [[NSDate date] timeIntervalSinceDate:date];
    if (diff < 60) return NSLocalizedString(@"just now", nil);
    if (diff < 3600) return [NSString stringWithFormat:NSLocalizedString(@"%ld minutes ago", nil), (long)(diff/60)];
    if (diff < 86400) return [NSString stringWithFormat:NSLocalizedString(@"%ld hours ago", nil), (long)(diff/3600)];
    return [NSString stringWithFormat:NSLocalizedString(@"%ld days ago", nil), (long)(diff/86400)];
}

#pragma mark - UITableView
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _items.count; }

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return a stable estimated height to avoid heavy synchronous measurements on initial render
    return 120.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafDocCommentCell *cell = [tableView dequeueReusableCellWithIdentifier:kSeafDocCommentCellId forIndexPath:indexPath];
    // Pass SeafConnection to reuse authentication when loading images
    [cell configureWithItem:_items[indexPath.row] connection:self.connection];
    
    // Android-style: set image tap callback
    __weak typeof(self) wself = self;
    [cell setImageTapHandler:^(NSString *imageURL) {
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        [sself previewImage:imageURL];
    }];
    
    [cell.moreButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [cell.moreButton addTarget:self action:@selector(onMoreTapped:) forControlEvents:UIControlEventTouchUpInside];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static SeafDocCommentCell *sizing;
    if (!sizing) {
        sizing = [[SeafDocCommentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    }
    
    // Configure cell (recreates content subviews) — sizing cell doesn't load images, so don't pass connection
    [sizing configureWithItem:_items[indexPath.row] connection:nil];
    
    // Set contentView bounds so width is computed correctly
    CGFloat cellWidth = tableView.bounds.size.width;
    if (cellWidth <= 0) {
        cellWidth = UIScreen.mainScreen.bounds.size.width;
    }
    sizing.contentView.bounds = CGRectMake(0, 0, cellWidth, 0);
    
    // Calculate height
    CGSize size = [sizing sizeThatFits:CGSizeMake(cellWidth, CGFLOAT_MAX)];
    return size.height;
}

- (void)onMoreTapped:(UIButton *)sender
{
    UIView *view = sender;
    while (view && ![view isKindOfClass:[SeafDocCommentCell class]]) view = view.superview;
    if (![view isKindOfClass:[SeafDocCommentCell class]]) return;
    SeafDocCommentCell *cell = (SeafDocCommentCell *)view;
    NSIndexPath *ip = [_tableView indexPathForCell:cell];
    if (!ip) return;
    SeafDocCommentItem *item = _items[ip.row];

    // Use unified SeafActionSheet to keep a consistent style
    NSArray *titles = @[NSLocalizedString(@"Mark resolved", nil), NSLocalizedString(@"Delete", nil)];
    SeafActionSheet *actionSheet = [SeafActionSheet actionSheetWithoutCancelWithTitles:titles];
    actionSheet.targetVC = self;
    __weak typeof(self) wself2 = self;
    [actionSheet setButtonPressedBlock:^(SeafActionSheet * _Nonnull sheet, NSIndexPath * _Nonnull indexPath) {
        __strong typeof(wself2) sself2 = wself2; if (!sself2) return;
        [sheet dismissAnimated:YES];
        if (indexPath.row == 0) {
            [sself2 markResolved:item atIndexPath:ip];
        } else if (indexPath.row == 1) {
            [sself2 deleteComment:item atIndexPath:ip];
        }
    }];
    // Anchor the presentation from the cell's moreButton so positioning matches the button
    [actionSheet showFromView:cell.moreButton];
    return;

}

#pragma mark - Custom Sheet Actions

- (void)_dismissCustomSheet:(id)sender
{
    UIView *hostView = self.view.window ?: self.view;
    if (!hostView) return;
    void (^dismiss)(void) = objc_getAssociatedObject(sender, @"dismiss_block");
    // If it's a gesture, prefer reading the callback from the bound view
    if (!dismiss && [sender isKindOfClass:[UIGestureRecognizer class]]) {
        UIView *bindView = ((UIGestureRecognizer *)sender).view;
        if (bindView) {
            dismiss = objc_getAssociatedObject(bindView, @"dismiss_block");
        }
    }
    // Compatible with different popup overlay tags (9101/9001)
    if (!dismiss) {
        UIView *dv = [hostView viewWithTag:9101];
        if (!dv) dv = [hostView viewWithTag:9001];
        if (dv) dismiss = objc_getAssociatedObject(dv, @"dismiss_block");
    }
    if (dismiss) dismiss();
}

- (void)_menuRowTouchDown:(UIButton *)sender
{
    if (@available(iOS 13.0, *)) {
        sender.backgroundColor = [UIColor tertiarySystemFillColor];
    } else {
        sender.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    }
}

- (void)_menuRowTouchUp:(UIButton *)sender
{
    if (@available(iOS 13.0, *)) {
        sender.backgroundColor = UIColor.clearColor;
    } else {
        sender.backgroundColor = UIColor.clearColor;
    }
}

- (void)_onCustomSheetMark:(UIButton *)sender
{
    NSIndexPath *ip = objc_getAssociatedObject(sender, @"comment_indexPath");
    SeafDocCommentItem *item = objc_getAssociatedObject(sender, @"comment_item");
    [self _dismissCustomSheet:sender];
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [gen impactOccurred];
    }
    if (!ip || !item) return;
        [self markResolved:item atIndexPath:ip];
}

- (void)_onCustomSheetDelete:(UIButton *)sender
{
    NSIndexPath *ip = objc_getAssociatedObject(sender, @"comment_indexPath");
    SeafDocCommentItem *item = objc_getAssociatedObject(sender, @"comment_item");
    [self _dismissCustomSheet:sender];
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [gen impactOccurred];
    }
    if (!ip || !item) return;
    [self deleteComment:item atIndexPath:ip];
}

- (void)markResolved:(SeafDocCommentItem *)item atIndexPath:(NSIndexPath *)indexPath
{
    if (self.isLoading) return;
    self.isLoading = YES;
    __weak typeof(self) wself = self;
    [_service markResolvedForDocUUID:self.pageOptions.docUuid commentId:item.commentId seadocServer:self.pageOptions.seadocServerUrl token:self.pageOptions.seadocAccessToken completion:^(NSDictionary * _Nullable resp, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself; if (!sself) return;
            sself.isLoading = NO;
            if (!error) {
                item.resolved = YES;
                [sself->_items replaceObjectAtIndex:indexPath.row withObject:item];
                [sself->_tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            }
        });
    }];
}

- (void)deleteComment:(SeafDocCommentItem *)item atIndexPath:(NSIndexPath *)indexPath
{
    if (self.isLoading) return;
    self.isLoading = YES;
    __weak typeof(self) wself = self;
    [_service deleteCommentForDocUUID:self.pageOptions.docUuid commentId:item.commentId seadocServer:self.pageOptions.seadocServerUrl token:self.pageOptions.seadocAccessToken completion:^(NSDictionary * _Nullable resp, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself; if (!sself) return;
            sself.isLoading = NO;
            if (!error) {
                [sself->_items removeObjectAtIndex:indexPath.row];
                [sself->_tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            }
        });
    }];
}

#pragma mark - Image picker delegates
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info
{
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    NSURL *url = info[UIImagePickerControllerImageURL];
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (!image) return;
    // Immediately insert attachment as square with width = 2/5 of input text area (no stretch; crop center)
    [self.view layoutIfNeeded];
    CGFloat inputTextWidth = MAX(0.0, self->_inputViewBar.textView.bounds.size.width);
    CGFloat showW = floor(MAX(48.0, inputTextWidth * 0.4));
    CGFloat showH = showW; // square
    UIImage *squareImg = [self squareImageFrom:image targetSide:showW];
    SeafImageAttachment *att = [SeafImageAttachment new];
    att.image = squareImg ?: image;
    att.bounds = CGRectMake(0, 0, showW, showH);
    NSAttributedString *imgAttr = [NSAttributedString attributedStringWithAttachment:att];
    NSMutableAttributedString *cur = [[NSMutableAttributedString alloc] initWithAttributedString:self->_inputViewBar.textView.attributedText ?: [[NSAttributedString alloc] initWithString:@""]];
    // Ensure one blank line before the image
    if (cur.length > 0) {
        unichar lastChar = [[cur string] characterAtIndex:cur.length - 1];
        if (lastChar != '\n') {
            [cur appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n"]];
        } else {
            // If there is exactly one trailing newline, add one more to make a blank line
            if (cur.length >= 2) {
                unichar prevChar = [[cur string] characterAtIndex:cur.length - 2];
                if (prevChar != '\n') {
                    [cur appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
                }
            } else {
                [cur appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
            }
        }
    }
    [cur appendAttributedString:imgAttr];
    // Ensure one blank line after the image
    [cur appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n"]];
    // Enforce consistent font for all text runs to avoid font size changing
    UIFont *baseFont = self->_inputViewBar.textView.font ?: [UIFont systemFontOfSize:17];
    [cur addAttribute:NSFontAttributeName value:baseFont range:NSMakeRange(0, cur.length)];
    self->_inputViewBar.textView.attributedText = cur.copy;
    self->_inputViewBar.textView.typingAttributes = @{ NSFontAttributeName: baseFont };
    [self updateSendEnabledState];

 

    // Add delete overlay for this attachment and layout
    [self addDeleteOverlayForAttachment:att];

    // Add loading overlay for upload progress
    [self addLoadingOverlayForAttachment:att];

    // Recalculate input bar height immediately after inserting image
    [self->_inputViewBar invalidateIntrinsicContentSize];
    [self->_inputViewBar setNeedsLayout];
    [self layoutBottomBarForKeyboardHeight:self.currentKeyboardOverlap animated:NO];

    NSData *data = UIImageJPEGRepresentation(image, 0.9);
    if (!data) return;
    NSString *fileName = url.lastPathComponent ?: @"image.jpg";
    self.pendingUploads += 1;
    [self uploadImageData:data fileName:fileName mime:@"image/jpeg" forAttachment:att];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0))
{
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;
    PHPickerResult *r = results.firstObject;
    if (![r.itemProvider canLoadObjectOfClass:[UIImage class]]) return;
    __weak typeof(self) wself = self;
    [r.itemProvider loadObjectOfClass:[UIImage class] completionHandler:^(UIImage *image, NSError * _Nullable error) {
        if (!image || error) return;
        NSData *data = UIImageJPEGRepresentation(image, 0.9);
        if (!data) return;
        // Insert attachment and start upload on main thread where 'att' is created
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself; if (!sself) return;
            [sself.view layoutIfNeeded];
            CGFloat inputTextWidth = MAX(0.0, sself->_inputViewBar.textView.bounds.size.width);
            CGFloat showW = floor(MAX(48.0, inputTextWidth * 0.4));
            CGFloat showH = showW;
            UIImage *squareImg = [sself squareImageFrom:image targetSide:showW];
            SeafImageAttachment *att = [SeafImageAttachment new];
            att.image = squareImg ?: image;
            att.bounds = CGRectMake(0, 0, showW, showH);
            NSAttributedString *imgAttr = [NSAttributedString attributedStringWithAttachment:att];
            NSMutableAttributedString *cur = [[NSMutableAttributedString alloc] initWithAttributedString:sself->_inputViewBar.textView.attributedText ?: [[NSAttributedString alloc] initWithString:@""]];
            if (cur.length > 0) {
                unichar lastChar = [[cur string] characterAtIndex:cur.length - 1];
                if (lastChar != '\n') {
                    [cur appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n"]];
                } else {
                    if (cur.length >= 2) {
                        unichar prevChar = [[cur string] characterAtIndex:cur.length - 2];
                        if (prevChar != '\n') {
                            [cur appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
                        }
                    } else {
                        [cur appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
                    }
                }
            }
            [cur appendAttributedString:imgAttr];
            [cur appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n"]];
            UIFont *baseFont = sself->_inputViewBar.textView.font ?: [UIFont systemFontOfSize:17];
            [cur addAttribute:NSFontAttributeName value:baseFont range:NSMakeRange(0, cur.length)];
            sself->_inputViewBar.textView.attributedText = cur.copy;
            sself->_inputViewBar.textView.typingAttributes = @{ NSFontAttributeName: baseFont };
            [sself updateSendEnabledState];

 

            // Add delete overlay and layout for this attachment
            [sself addDeleteOverlayForAttachment:att];

            // Add loading overlay for upload progress
            [sself addLoadingOverlayForAttachment:att];

            [sself->_inputViewBar invalidateIntrinsicContentSize];
            [sself->_inputViewBar setNeedsLayout];
            [sself layoutBottomBarForKeyboardHeight:sself.currentKeyboardOverlap animated:NO];
            [sself updateAttachmentDeleteButtonsLayout];

            sself.pendingUploads += 1;
            NSString *uniqueFileName = [NSString stringWithFormat:@"IMG_%@.jpg", [[NSUUID UUID] UUIDString]];
            [sself uploadImageData:data fileName:uniqueFileName mime:@"image/jpeg" forAttachment:att];
        });
    }];
}

- (void)uploadImageData:(NSData *)data fileName:(NSString *)fileName mime:(NSString *)mime forAttachment:(SeafImageAttachment *)attachment
{
    if (self.isLoading) return;
    if (self.pageOptions.docUuid.length == 0 || self.pageOptions.seadocServerUrl.length == 0 || self.pageOptions.seadocAccessToken.length == 0) return;
    self.isLoading = YES;
    // Persist payload for retry
    if (!self.attachmentUploadPayloads) {
        self.attachmentUploadPayloads = [NSMapTable strongToStrongObjectsMapTable];
    }
    [self.attachmentUploadPayloads setObject:@{ @"data": data ?: [NSData data], @"fileName": fileName ?: @"image.jpg", @"mime": mime ?: @"image/jpeg" } forKey:attachment];
    __weak typeof(self) wself = self;
    [_service uploadImageForDocUUID:self.pageOptions.docUuid seadocServer:self.pageOptions.seadocServerUrl token:self.pageOptions.seadocAccessToken fileData:data mimeType:mime fileName:fileName completion:^(NSDictionary * _Nullable resp, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself; if (!sself) return;
            sself.isLoading = NO;
            sself.pendingUploads = MAX(0, sself.pendingUploads - 1);
            if (error) {
                // Show retry overlay instead of removing the attachment
                [sself addRetryOverlayForAttachment:attachment];
                [sself updateSendEnabledState];
                return;
            }
            id list = resp[@"relative_path"];
            if (![list isKindOfClass:[NSArray class]] || [list count]==0) return;
            NSString *sName = [list firstObject];
            NSString *rawName = sName;
            while ([sName hasPrefix:@"/"]) { sName = [sName substringFromIndex:1]; }
            NSString *base = sself.pageOptions.seadocServerUrl ?: @"";
            if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length-1];
            if ([base hasSuffix:@"/seadoc"]) base = [base substringToIndex:base.length-7];
            if (![base hasSuffix:@"/seahub"]) base = [base stringByAppendingString:@"/seahub"];
            NSString *absUrl = [NSString stringWithFormat:@"%@/api/v2.1/seadoc/download-image/%@/%@", base, sself.pageOptions.docUuid, sName];
            // Bind to the specific attachment
            attachment.uploadedURL = absUrl;
            [sself removeLoadingOverlayForAttachment:attachment];
            // Clear stored payload on success
            if (sself.attachmentUploadPayloads) {
                [sself.attachmentUploadPayloads removeObjectForKey:attachment];
            }
 
            [sself->_inputViewBar updatePlaceholderVisibility];
            [sself updateSendEnabledState];
        });
    }];
}

#pragma mark - Keyboard
- (void)registerKeyboardNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onKeyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)_onInputTextChanged:(NSNotification *)n
{
    [self updateSendEnabledState];
    // Recalculate and apply the bottom input bar height and position based on the
    // current keyboard overlap so that when the text grows to multiple lines,
    // the entire bar moves up with it and the caret area does not end up under the keyboard.
    [self layoutBottomBarForKeyboardHeight:self.currentKeyboardOverlap animated:NO];
    // After updating the bottom bar layout, refresh the positions of attachment delete
    // buttons and loading overlays to match the latest textView geometry.
    [self updateAttachmentDeleteButtonsLayout];

    UITextView *tv = self->_inputViewBar.textView;
    NSString *plain = tv.text ?: @"";
    NSUInteger curLen = plain.length;
    NSUInteger prevLen = self.lastPlainTextLength;
    NSRange sel = tv.selectedRange;
    BOOL isInsertion = curLen > prevLen;
    BOOL isDeletion = curLen < prevLen;
    BOOL justTypedAt = NO;
    if (isInsertion) {
        NSUInteger delta = curLen - prevLen;
        if (delta == 1 && sel.location > 0) {
            unichar c = [plain characterAtIndex:sel.location - 1];
            justTypedAt = (c == '@');
        }
    }
    BOOL mentionVisible = [self isMentionUIVisible];
    if (justTypedAt) {
        // Only when user typed '@' should we present; start with empty query
        [self handleMentionTokenWithAllowPresent:YES];
    } else if (mentionVisible) {
        // If already visible, keep updating/hiding as user types or deletes
        [self handleMentionTokenWithAllowPresent:NO];
    } else {
        // Do not present on deletion or other typing
    }
    self.lastPlainTextLength = curLen;
    self.lastSelectedRange = sel;
}

#pragma mark - Mention
- (BOOL)isMentionUIVisible
{
    BOOL viewVisible = (self.mentionView && !self.mentionView.hidden);
    BOOL sheetVisible = NO;
    if (@available(iOS 15.0, *)) {
        sheetVisible = (self.isMentionSheetPresented && self.mentionSheetVC.presentingViewController != nil);
    }
    return viewVisible || sheetVisible;
}

- (void)handleMentionTokenWithAllowPresent:(BOOL)allowPresent
{
    UITextView *tv = self->_inputViewBar.textView;
    if (!tv) return;
    NSString *plain = tv.text ?: @"";
    NSRange sel = tv.selectedRange;
    if (sel.location == NSNotFound) { [self hideMentionUI]; return; }
    NSUInteger caret = sel.location;
    if (caret == 0 || caret > plain.length) { [self hideMentionUI]; return; }
    // Scan backwards to find start of token
    NSInteger i = (NSInteger)caret - 1;
    BOOL foundAt = NO;
    while (i >= 0) {
        unichar c = [plain characterAtIndex:(NSUInteger)i];
        if (c == '@') { foundAt = YES; break; }
        // Terminators
        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c] ||
            [[NSCharacterSet punctuationCharacterSet] characterIsMember:c]) {
            break;
        }
        i--;
    }
    if (!foundAt) { [self hideMentionUI]; return; }
    NSUInteger start = (NSUInteger)i;
    NSRange tokenRange = NSMakeRange(start, caret - start);
    if (NSMaxRange(tokenRange) > plain.length) { [self hideMentionUI]; return; }
    NSString *token = [plain substringWithRange:tokenRange];
    // Require token to start with '@'
    if (![token hasPrefix:@"@"]) { [self hideMentionUI]; return; }
    NSString *query = [token substringFromIndex:1];
    self.currentMentionRange = tokenRange;
    __weak typeof(self) wself = self;
    [self ensureRelatedUsersLoaded:^{
        __strong typeof(wself) sself = wself; if (!sself) return;
        BOOL visible = [sself isMentionUIVisible];
        if (@available(iOS 15.0, *)) {
            if (!visible && allowPresent) {
                [sself presentMentionSheetIfNeeded];
            }
            if ([sself isMentionUIVisible]) {
                [sself.mentionSheetVC updateAllUsers:sself.mentionAllUsers];
                [sself.mentionSheetVC applyFilter:query];
            }
        } else {
            if (!visible && allowPresent) {
                [sself.mentionView updateAllUsers:sself.mentionAllUsers];
                [sself.mentionView applyFilter:query];
                [sself.mentionView showInView:sself.view belowView:sself->_inputViewBar];
            } else if ([sself isMentionUIVisible]) {
                [sself.mentionView applyFilter:query];
            }
        }
    }];
}

- (void)insertMentionUser:(NSDictionary *)user
{
    if (!user) return;
    UITextView *tv = self->_inputViewBar.textView;
    if (!tv) return;
    NSString *name = [user[@"name"] isKindOfClass:NSString.class] ? user[@"name"] : @"";
    NSString *email = [user[@"email"] isKindOfClass:NSString.class] ? user[@"email"] : @"";
    NSString *nameOrEmail = name.length > 0 ? name : email;
    NSString *rep = [NSString stringWithFormat:@"@%@ ", nameOrEmail ?: @""];
    // Build default typing attributes (keep font size consistent)
    NSMutableDictionary<NSAttributedStringKey, id> *attrs = [NSMutableDictionary dictionaryWithDictionary:(tv.typingAttributes ?: @{})];
    if (!attrs[NSFontAttributeName]) {
        UIFont *f = tv.font ?: [UIFont systemFontOfSize:17];
        attrs[NSFontAttributeName] = f;
    }
    if (!attrs[NSForegroundColorAttributeName]) {
        UIColor *c = tv.textColor ?: ([UIColor respondsToSelector:@selector(labelColor)] ? [UIColor labelColor] : [UIColor blackColor]);
        attrs[NSForegroundColorAttributeName] = c;
    }
    // Current content: if not attributed, convert from plain with default attrs
    NSAttributedString *current = tv.attributedText;
    if (current.length == 0) {
        current = [[NSAttributedString alloc] initWithString:(tv.text ?: @"") attributes:attrs];
    }
    NSMutableAttributedString *mut = [[NSMutableAttributedString alloc] initWithAttributedString:current];
    NSRange r = self.currentMentionRange;
    if (NSMaxRange(r) <= mut.length) {
        NSAttributedString *repAttr = [[NSAttributedString alloc] initWithString:rep attributes:attrs];
        [mut replaceCharactersInRange:r withAttributedString:repAttr];
        tv.attributedText = mut;
        tv.typingAttributes = attrs;
        NSUInteger newCaret = r.location + rep.length;
        tv.selectedRange = NSMakeRange(newCaret, 0);
        // Manually sync last change tracking because programmatic setAttributedText may not fire notification immediately
        self.lastPlainTextLength = tv.text.length;
        self.lastSelectedRange = tv.selectedRange;
    }
    [self hideMentionUI];
}

- (void)ensureRelatedUsersLoaded:(void(^)(void))completion
{
    if (self.mentionUsersLoaded) { if (completion) completion(); return; }
    if (self.repoId.length == 0) { if (completion) completion(); return; }
    if (!self.sdocService) {
        self.sdocService = [[SeafSdocService alloc] initWithConnection:self.connection ?: [SeafGlobal sharedObject].connection];
    }
    // Initialize caches
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gRelatedUsersCache = [NSMutableDictionary dictionary];
        gRelatedUsersCacheTS = [NSMutableDictionary dictionary];
    });
    // Try cache
    NSArray<NSDictionary *> *cached = gRelatedUsersCache[self.repoId];
    NSDate *ts = gRelatedUsersCacheTS[self.repoId];
    if (cached.count > 0 && ts && ([[NSDate date] timeIntervalSinceDate:ts] < kRelatedUsersCacheTTL)) {
        self.mentionAllUsers = cached;
        [self.mentionView updateAllUsers:self.mentionAllUsers];
        self.mentionUsersLoaded = YES;
        if (completion) completion();
        return;
    }
    
    __weak typeof(self) wself = self;
    
    // Request two APIs concurrently: related-users (collaborators) and participants
    __block NSArray<NSDictionary *> *collaboratorsResult = @[];
    __block NSArray<NSDictionary *> *participantsResult = @[];
    __block BOOL collaboratorsDone = NO;
    __block BOOL participantsDone = NO;
    
    void (^mergeAndSort)(void) = ^{
        __strong typeof(wself) sself = wself;
        if (!sself || !collaboratorsDone || !participantsDone) return;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray<NSDictionary *> *sortedUsers = [sself sortCollaborators:collaboratorsResult participants:participantsResult];
            
            if (sortedUsers.count > 0) {
                sself.mentionAllUsers = sortedUsers;
                gRelatedUsersCache[sself.repoId] = sself.mentionAllUsers;
                gRelatedUsersCacheTS[sself.repoId] = [NSDate date];
                [sself.mentionView updateAllUsers:sself.mentionAllUsers];
                sself.mentionUsersLoaded = YES;
            } else if (cached.count > 0) {
                // Fallback to stale cache if network failed but we had something
                sself.mentionAllUsers = cached;
                [sself.mentionView updateAllUsers:sself.mentionAllUsers];
                sself.mentionUsersLoaded = YES;
            } else {
                // Keep hidden with empty data
                sself.mentionAllUsers = @[];
                [sself.mentionView updateAllUsers:sself.mentionAllUsers];
                sself.mentionUsersLoaded = YES;
            }
            if (completion) completion();
        });
    };
    
    // Request 1: related-users (collaborators)
    [self.sdocService getRelatedUsersWithRepoId:self.repoId completion:^(NSDictionary * _Nullable resp, NSError * _Nullable error) {
        NSArray *list = (!error && [resp isKindOfClass:NSDictionary.class]) ? (resp[@"user_list"] ?: resp[@"users"] ?: @[]) : @[];
        if (![list isKindOfClass:NSArray.class]) list = @[];
        NSMutableArray<NSDictionary *> *arr = [NSMutableArray array];
        for (id obj in list) {
            if (![obj isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *norm = [SeafSdocUserMapper normalizeUserDict:(NSDictionary *)obj];
            [arr addObject:norm];
        }
        collaboratorsResult = arr.copy;
        collaboratorsDone = YES;
        mergeAndSort();
    }];
    
    // Request 2: participants (uses seahub server, no seadoc token needed)
    if (self.pageOptions.docUuid.length > 0) {
        [self->_service getParticipantsWithDocUUID:self.pageOptions.docUuid
                                         completion:^(NSArray<NSDictionary *> * _Nullable participants, NSError * _Nullable error) {
            NSMutableArray<NSDictionary *> *arr = [NSMutableArray array];
            for (id obj in participants ?: @[]) {
                if (![obj isKindOfClass:NSDictionary.class]) continue;
                NSDictionary *norm = [SeafSdocUserMapper normalizeUserDict:(NSDictionary *)obj];
                [arr addObject:norm];
            }
            participantsResult = arr.copy;
            participantsDone = YES;
            mergeAndSort();
        }];
    } else {
        participantsDone = YES;
        mergeAndSort();
    }
}

// Sort user list according to frontend logic
// Sort order: exclude current user -> lastModifyUser on top -> participants -> other collaborators
- (NSArray<NSDictionary *> *)sortCollaborators:(NSArray<NSDictionary *> *)collaborators
                                   participants:(NSArray<NSDictionary *> *)participants
{
    NSString *loginEmail = (self.connection.email ?: @"").lowercaseString;
    NSString *lastModifyUser = (self.latestContributor ?: @"").lowercaseString;
    
    // Build participantsMap (excluding current user)
    NSMutableDictionary<NSString *, NSDictionary *> *participantsMap = [NSMutableDictionary dictionary];
    for (NSDictionary *item in participants) {
        NSString *email = [item[@"email"] isKindOfClass:NSString.class] ? [item[@"email"] lowercaseString] : @"";
        if (email.length == 0) continue;
        if ([email isEqualToString:loginEmail]) continue; // Exclude current user
        participantsMap[email] = item;
    }
    
    // Process collaborators: exclude those already in participantsMap, exclude current user, extract stickyCollaborator
    NSDictionary *stickyCollaborator = nil;
    NSMutableArray<NSDictionary *> *newCollaborators = [NSMutableArray array];
    
    for (NSDictionary *item in collaborators) {
        NSString *email = [item[@"email"] isKindOfClass:NSString.class] ? [item[@"email"] lowercaseString] : @"";
        if (email.length == 0) continue;
        
        // Exclude current user
        if ([email isEqualToString:loginEmail]) continue;
        
        // Exclude users already in participants
        if (participantsMap[email]) continue;
        
        // Check if this is lastModifyUser
        if (lastModifyUser.length > 0 && [email isEqualToString:lastModifyUser]) {
            stickyCollaborator = item;
            continue; // Don't add to newCollaborators, will be placed on top separately
        }
        
        [newCollaborators addObject:item];
    }
    
    // Get participants array (current user already excluded)
    NSArray<NSDictionary *> *newParticipants = participantsMap.allValues;
    
    // Final order: [stickyCollaborator, ...participants, ...collaborators]
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    if (stickyCollaborator) {
        [result addObject:stickyCollaborator];
    }
    [result addObjectsFromArray:newParticipants];
    [result addObjectsFromArray:newCollaborators];
    
    return result.copy;
}

- (void)presentMentionSheetIfNeeded
{
    if (!@available(iOS 15.0, *)) return;
    if (self.isMentionSheetPresented && self.mentionSheetVC.presentingViewController) {
        return;
    }
    SeafMentionSheetViewController *vc = [SeafMentionSheetViewController new];
    __weak typeof(self) wself = self;
    vc.onSelectUser = ^(NSDictionary *user) {
        __strong typeof(wself) sself = wself; if (!sself) return;
        [sself insertMentionUser:user];
        if (sself.mentionSheetVC) {
            [sself.mentionSheetVC dismissViewControllerAnimated:YES completion:nil];
        }
        sself.isMentionSheetPresented = NO;
    };
    if (@available(iOS 15.0, *)) {
        vc.modalPresentationStyle = UIModalPresentationPageSheet;
    }
    self.mentionSheetVC = vc;
    self.isMentionSheetPresented = YES;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (@available(iOS 13.0, *)) {
        vc.presentationController.delegate = self;
    }
#endif
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)hideMentionUI
{
    if (@available(iOS 15.0, *)) {
        if (self.isMentionSheetPresented && self.mentionSheetVC.presentingViewController) {
            [self.mentionSheetVC dismissViewControllerAnimated:YES completion:nil];
            self.isMentionSheetPresented = NO;
        }
    }
    [self.mentionView hide];
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController API_AVAILABLE(ios(13.0))
{
    if (presentationController.presentedViewController == self.mentionSheetVC) {
        self.isMentionSheetPresented = NO;
        self.mentionSheetVC = nil;
    }
}
#endif

- (void)onKeyboard:(NSNotification *)notification
{
    NSDictionary *info = notification.userInfo;
    CGRect endScreen = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval dur = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = (UIViewAnimationCurve)[info[UIKeyboardAnimationCurveUserInfoKey] integerValue];

    // Convert to view coordinates for robust first-show behavior
    CGRect end = [self.view convertRect:endScreen fromView:nil];
    CGFloat overlap = MAX(0.0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(end));
    self.currentKeyboardOverlap = overlap;

    CGFloat safeBottom = 0;
    if (@available(iOS 11.0, *)) safeBottom = self.view.safeAreaInsets.bottom;

    // Compute target contentOffset during keyboard animation so the list shift matches the input bar
    UIEdgeInsets oldInsets = _tableView.contentInset;
    CGSize oldContentSize = _tableView.contentSize;
    CGPoint oldOffset = _tableView.contentOffset;
    CGFloat viewH = _tableView.bounds.size.height;
    CGFloat oldBottomDistance = (oldContentSize.height + oldInsets.bottom) - (oldOffset.y + viewH);
    if (oldBottomDistance < 0) oldBottomDistance = 0; // clamp

    UIViewAnimationOptions opts = (UIViewAnimationOptions)(curve << 16) | UIViewAnimationOptionBeginFromCurrentState;
    [UIView animateWithDuration:dur delay:0 options:opts animations:^{
        // Apply updates to input bar and insets
        [self layoutBottomBarForKeyboardHeight:overlap animated:NO];
        // Compute new offset from new insets, keeping the prior "distance from bottom"
        UIEdgeInsets newInsets = self->_tableView.contentInset;
        CGSize newContentSize = self->_tableView.contentSize; // May not change much; kept for completeness
        CGFloat targetOffsetY = (newContentSize.height + newInsets.bottom) - (self->_tableView.bounds.size.height) - oldBottomDistance;
        // Do not allow less than the top inset
        targetOffsetY = MAX(-newInsets.top, targetOffsetY);
        // Adjust only when keyboard appears or user is near the bottom to avoid interrupting mid-position browsing
        BOOL nearBottom = (oldBottomDistance <= 8.0);
        if (overlap > 0 && (nearBottom || self->_items.count == 0)) {
            [self->_tableView setContentOffset:CGPointMake(self->_tableView.contentOffset.x, targetOffsetY) animated:NO];
        }
        // Update overlay button layout inside the animation for consistent motion
        [self updateAttachmentDeleteButtonsLayout];
        // Reposition mention suggestions if visible
        if (!self.mentionView.hidden) {
            [self.mentionView showInView:self.view belowView:self->_inputViewBar];
        }
    } completion:nil];
}

#pragma mark - Tap to dismiss
- (void)onBackgroundTapped:(UITapGestureRecognizer *)gr
{
    if (gr.state == UIGestureRecognizerStateEnded) {
        [self.view endEditing:YES];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    // don't intercept taps inside the input bar (textView, buttons)
    if ([touch.view isDescendantOfView:self.inputViewBar]) {
        return NO;
    }
    // Do not intercept UIControls (e.g. more button, image button)
    UIView *v = touch.view;
    while (v) {
        if ([v isKindOfClass:[UIControl class]]) return NO;
        v = v.superview;
    }
    return YES;
}

// Allow background taps to be recognized simultaneously with other gestures (tableView, image preview) so editing ends
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if (gestureRecognizer == _bgTap) {
        return YES;
    }
    return NO;
}

- (void)showToast:(NSString *)text
{
    if (text.length == 0) return;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil message:text preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:ac animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [ac dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)showOKAlert:(NSString *)text
{
    if (text.length == 0) return;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil message:text preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *ok = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:nil];
    [ac addAction:ok];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Image Preview
// Android-style: image preview (equivalent to Android's OnlyImagePreviewActivity)
- (void)previewImage:(NSString *)imageURL
{
    if (imageURL.length == 0) return;
    SeafImagePreviewController *vc = [[SeafImagePreviewController alloc] initWithURL:imageURL connection:self.connection];
    [self presentViewController:vc animated:YES completion:nil];
}

#pragma mark - Attachment square crop & delete overlay

- (UIImage *)squareImageFrom:(UIImage *)image targetSide:(CGFloat)side
{
    if (!image || side <= 0) return image;
    CGSize srcSize = image.size;
    CGFloat minEdge = MIN(srcSize.width, srcSize.height);
    CGRect cropRect = CGRectMake((srcSize.width - minEdge) * 0.5,
                                 (srcSize.height - minEdge) * 0.5,
                                 minEdge,
                                 minEdge);
    CGImageRef cg = CGImageCreateWithImageInRect(image.CGImage, cropRect);
    if (!cg) return image;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [[UIImage imageWithCGImage:cg scale:image.scale orientation:image.imageOrientation] drawInRect:CGRectMake(0, 0, side, side)];
    UIImage *outImg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGImageRelease(cg);
    return outImg ?: image;
}

- (NSRange)rangeOfAttachment:(SeafImageAttachment *)att inTextView:(UITextView *)tv
{
    if (!att || tv.attributedText.length == 0) return NSMakeRange(NSNotFound, 0);
    __block NSRange found = NSMakeRange(NSNotFound, 0);
    [tv.attributedText enumerateAttribute:NSAttachmentAttributeName
                                  inRange:NSMakeRange(0, tv.attributedText.length)
                                  options:0
                               usingBlock:^(id value, NSRange range, BOOL *stop) {
        if ([value isKindOfClass:[SeafImageAttachment class]] && value == att) {
            found = range;
            *stop = YES;
        }
    }];
    return found;
}

- (void)addDeleteOverlayForAttachment:(SeafImageAttachment *)att
{
    if (!att) return;
    if (!self.attachmentDeleteButtons) {
        self.attachmentDeleteButtons = [NSMapTable strongToWeakObjectsMapTable];
    }
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) {
        [btn setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        btn.tintColor = [UIColor systemGrayColor];
    }
    btn.frame = CGRectMake(0, 0, 20, 20);
    btn.contentEdgeInsets = UIEdgeInsetsZero;
    btn.backgroundColor = [UIColor whiteColor];
    btn.layer.cornerRadius = 10.0;
    btn.clipsToBounds = YES;
    [btn addTarget:self action:@selector(onDeleteAttachmentButton:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(btn, @"seaf_attachment", att, OBJC_ASSOCIATION_ASSIGN);
    [self->_inputViewBar.textView addSubview:btn];
    [self.attachmentDeleteButtons setObject:btn forKey:att];
    // Ensure delete button stays above loading overlays
    [self->_inputViewBar.textView bringSubviewToFront:btn];
    [self updateAttachmentDeleteButtonsLayout];
}

- (void)addLoadingOverlayForAttachment:(SeafImageAttachment *)att
{
    if (!att) return;
    if (!self.attachmentLoadingOverlays) {
        self.attachmentLoadingOverlays = [NSMapTable strongToWeakObjectsMapTable];
    }
    if ([self.attachmentLoadingOverlays objectForKey:att]) return;
    UIView *overlay = [[UIView alloc] initWithFrame:CGRectZero];
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.3];
    overlay.userInteractionEnabled = NO;
    UIActivityIndicatorViewStyle style = UIActivityIndicatorViewStyleMedium;
    if (@available(iOS 13.0, *)) style = UIActivityIndicatorViewStyleMedium; else style = UIActivityIndicatorViewStyleWhite;
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:style];
    if (@available(iOS 13.0, *)) {
        spinner.color = [UIColor whiteColor];
    } else {
        spinner.color = [UIColor whiteColor];
    }
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    [overlay addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor]
    ]];
    [self->_inputViewBar.textView addSubview:overlay];
    [self.attachmentLoadingOverlays setObject:overlay forKey:att];
    UIButton *btn = [self.attachmentDeleteButtons objectForKey:att];
    if (btn) [self->_inputViewBar.textView bringSubviewToFront:btn];
    [self updateAttachmentDeleteButtonsLayout];
}

- (void)removeLoadingOverlayForAttachment:(SeafImageAttachment *)att
{
    if (!att) return;
    UIView *overlay = [self.attachmentLoadingOverlays objectForKey:att];
    if (overlay) {
        [overlay removeFromSuperview];
        [self.attachmentLoadingOverlays removeObjectForKey:att];
    }
}

- (void)addRetryOverlayForAttachment:(SeafImageAttachment *)att
{
    if (!att) return;
    if (!self.attachmentLoadingOverlays) {
        self.attachmentLoadingOverlays = [NSMapTable strongToWeakObjectsMapTable];
    }
    // Remove existing overlay if any
    UIView *old = [self.attachmentLoadingOverlays objectForKey:att];
    if (old) { [old removeFromSuperview]; }

    UIView *overlay = [[UIView alloc] initWithFrame:CGRectZero];
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
    overlay.userInteractionEnabled = YES;

    UIButton *retry = [UIButton buttonWithType:UIButtonTypeSystem];
    [retry setTitle:NSLocalizedString(@"Retry", nil) forState:UIControlStateNormal];
    retry.translatesAutoresizingMaskIntoConstraints = NO;
    retry.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.9];
    retry.layer.cornerRadius = 14.0;
    retry.contentEdgeInsets = UIEdgeInsetsMake(6, 12, 6, 12);
    [retry addTarget:self action:@selector(onRetryAttachmentButton:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(retry, @"seaf_attachment", att, OBJC_ASSOCIATION_ASSIGN);
    [overlay addSubview:retry];
    [NSLayoutConstraint activateConstraints:@[
        [retry.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [retry.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor]
    ]];

    [self->_inputViewBar.textView addSubview:overlay];
    [self.attachmentLoadingOverlays setObject:overlay forKey:att];

    UIButton *del = [self.attachmentDeleteButtons objectForKey:att];
    if (del) [self->_inputViewBar.textView bringSubviewToFront:del];
    [self updateAttachmentDeleteButtonsLayout];
}

- (void)onRetryAttachmentButton:(UIButton *)sender
{
    SeafImageAttachment *att = objc_getAssociatedObject(sender, @"seaf_attachment");
    if (!att) return;
    NSDictionary *payload = [self.attachmentUploadPayloads objectForKey:att];
    NSData *data = payload[@"data"]; NSString *fileName = payload[@"fileName"]; NSString *mime = payload[@"mime"]; 
    if (data.length == 0 || fileName.length == 0 || mime.length == 0) return;
    // Switch to loading overlay and re-upload
    [self addLoadingOverlayForAttachment:att];
    self.pendingUploads += 1;
    [self uploadImageData:data fileName:fileName mime:mime forAttachment:att];
}

- (void)updateAttachmentDeleteButtonsLayout
{
    if (!self->_inputViewBar || !self->_inputViewBar.textView) return;
    UITextView *tv = self->_inputViewBar.textView;
    UIEdgeInsets inset = tv.textContainerInset;
    UIEdgeInsets contentInset = tv.contentInset; // UIScrollView inset
    CGPoint offset = tv.contentOffset;
    NSTextContainer *tc = tv.textContainer;
    NSLayoutManager *lm = tv.layoutManager;
    CGFloat padding = tc.lineFragmentPadding;

 
    // For each tracked attachment, compute rect and place button
    NSMutableArray<SeafImageAttachment *> *keys = [NSMutableArray array];
    NSEnumerator *keyEnum = self.attachmentDeleteButtons.keyEnumerator;
    SeafImageAttachment *att = nil;
    while ((att = [keyEnum nextObject])) {
        if (att) [keys addObject:att];
    }
    for (SeafImageAttachment *att in keys) {
        UIButton *btn = [self.attachmentDeleteButtons objectForKey:att];
        if (!btn) continue;
        NSRange range = [self rangeOfAttachment:att inTextView:tv];
        if (range.location == NSNotFound) {
            [btn removeFromSuperview];
            [self.attachmentDeleteButtons removeObjectForKey:att];
            continue;
        }
        NSRange glyphRange = [lm glyphRangeForCharacterRange:range actualCharacterRange:NULL];
        CGRect rectInTC = [lm boundingRectForGlyphRange:glyphRange inTextContainer:tc];
        // Convert to textView content coordinates: add textContainerInset only.
        CGRect rectInTextView = rectInTC;
        rectInTextView.origin.x += inset.left;
        rectInTextView.origin.y += inset.top;
        CGFloat btnSize = 20.0;
        CGRect newFrame = CGRectMake(CGRectGetMaxX(rectInTextView) - btnSize * 0.6,
                                     rectInTextView.origin.y - btnSize * 0.4,
                                     btnSize,
                                     btnSize);
        btn.frame = newFrame;
        // Keep button above overlays
        [tv bringSubviewToFront:btn];
    }

    // Layout loading overlays to cover the image attachment rects
    if (self.attachmentLoadingOverlays) {
        NSMutableArray<SeafImageAttachment *> *overlayKeys = [NSMutableArray array];
        NSEnumerator *overlayEnum = self.attachmentLoadingOverlays.keyEnumerator;
        SeafImageAttachment *oatt = nil;
        while ((oatt = [overlayEnum nextObject])) {
            if (oatt) [overlayKeys addObject:oatt];
        }
        for (SeafImageAttachment *oatt in overlayKeys) {
            UIView *overlay = [self.attachmentLoadingOverlays objectForKey:oatt];
            if (!overlay) continue;
            NSRange range = [self rangeOfAttachment:oatt inTextView:tv];
            if (range.location == NSNotFound) {
                [overlay removeFromSuperview];
                [self.attachmentLoadingOverlays removeObjectForKey:oatt];
                continue;
            }
            NSRange glyphRange = [lm glyphRangeForCharacterRange:range actualCharacterRange:NULL];
            CGRect rectInTC = [lm boundingRectForGlyphRange:glyphRange inTextContainer:tc];
            CGRect rectInTextView = rectInTC;
            rectInTextView.origin.x += inset.left;
            rectInTextView.origin.y += inset.top;
            overlay.frame = rectInTextView;
        }
    }
}

- (void)onDeleteAttachmentButton:(UIButton *)sender
{
    SeafImageAttachment *att = objc_getAssociatedObject(sender, @"seaf_attachment");
    if (!att) return;
    UITextView *tv = self->_inputViewBar.textView;
    NSRange range = [self rangeOfAttachment:att inTextView:tv];
    if (range.location == NSNotFound) return;
    NSMutableAttributedString *cur = [[NSMutableAttributedString alloc] initWithAttributedString:tv.attributedText ?: [[NSAttributedString alloc] initWithString:@""]];
    [cur deleteCharactersInRange:range];
    tv.attributedText = cur.copy;
    [self removeLoadingOverlayForAttachment:att];
    [sender removeFromSuperview];
    [self.attachmentDeleteButtons removeObjectForKey:att];
    [self updateSendEnabledState];
    [self->_inputViewBar invalidateIntrinsicContentSize];
    [self->_inputViewBar setNeedsLayout];
    [self layoutBottomBarForKeyboardHeight:self.currentKeyboardOverlap animated:NO];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if (object == _inputViewBar.textView) {
        if ([keyPath isEqualToString:@"contentOffset"] || [keyPath isEqualToString:@"contentSize"] || [keyPath isEqualToString:@"bounds"]) {
            [self updateAttachmentDeleteButtonsLayout];
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    @try {
        [_inputViewBar.textView removeObserver:self forKeyPath:@"contentOffset"]; 
        [_inputViewBar.textView removeObserver:self forKeyPath:@"contentSize"]; 
        [_inputViewBar.textView removeObserver:self forKeyPath:@"bounds"]; 
    } @catch (__unused NSException *e) {}
    
}


@end

