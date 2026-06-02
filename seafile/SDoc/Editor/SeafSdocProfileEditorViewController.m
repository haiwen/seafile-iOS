//  SeafSdocProfileEditorViewController.m
//  Align Android: FileProfileEditorActivity

#import "SeafSdocProfileEditorViewController.h"
#import "SeafSdocLongTextEditorViewController.h"
#import "../Selectors/SeafSdocOptionSelectorViewController.h"
#import "../Selectors/SeafSdocDatePickerViewController.h"
#import "../SeafSdocProfileAssembler.h"
#import "../Chips/SeafCollaboratorChipView.h"
#import "../Chips/SeafTagChipView.h"
#import "../Selectors/SeafTagSelectorViewController.h"
#import "../Services/SeafSdocService.h"
#import "SeafConnection.h"
#import "SeafNavigationBarStyler.h"
#import "SVProgressHUD.h"
#import <objc/runtime.h>

static NSInteger const kContainerTagBase = 9000;
static NSInteger const kContentViewTag = 8888;

#pragma mark - Cell styling helpers (align Android shape_task_view_editable / no_editable)

/// Apply editable cell style: white bg + #E0E5EC border + 4pt corner radius
/// Align Android: shape_task_view_editable (light: white bg, #E0E5EC border; dark: #2F2F2F bg, #212121 border)
static void applyEditableCellStyle(UIView *view) {
    view.layer.cornerRadius = 4.0;
    view.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) {
        view.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            return tc.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0x2F/255.0 green:0x2F/255.0 blue:0x2F/255.0 alpha:1.0]
                : [UIColor whiteColor];
        }];
        view.layer.borderColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            return tc.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0x21/255.0 green:0x21/255.0 blue:0x21/255.0 alpha:1.0]
                : [UIColor colorWithRed:0xE0/255.0 green:0xE5/255.0 blue:0xEC/255.0 alpha:1.0];
        }].CGColor;
    } else {
        view.backgroundColor = [UIColor whiteColor];
        view.layer.borderColor = [UIColor colorWithRed:0xE0/255.0 green:0xE5/255.0 blue:0xEC/255.0 alpha:1.0].CGColor;
    }
    view.layer.borderWidth = 1.0;
}

/// Apply non-editable cell style: #f8f8f8 bg + no border + 4pt corner radius
/// Align Android: shape_task_view_no_editable (light: #f8f8f8; dark: #2F2F2F)
static void applyNonEditableCellStyle(UIView *view) {
    view.layer.cornerRadius = 4.0;
    view.layer.masksToBounds = YES;
    view.layer.borderWidth = 0;
    if (@available(iOS 13.0, *)) {
        view.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            return tc.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0x2F/255.0 green:0x2F/255.0 blue:0x2F/255.0 alpha:1.0]
                : [UIColor colorWithRed:0xF8/255.0 green:0xF8/255.0 blue:0xF8/255.0 alpha:1.0];
        }];
    } else {
        view.backgroundColor = [UIColor colorWithRed:0xF8/255.0 green:0xF8/255.0 blue:0xF8/255.0 alpha:1.0];
    }
}

/// Title color aligned with Android profile_editor_title (light: #666666, dark: #d3d3d3)
static UIColor *editorTitleColor(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            return tc.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0xD3/255.0 green:0xD3/255.0 blue:0xD3/255.0 alpha:1.0]
                : [UIColor colorWithRed:0x66/255.0 green:0x66/255.0 blue:0x66/255.0 alpha:1.0];
        }];
    }
    return [UIColor colorWithRed:0x66/255.0 green:0x66/255.0 blue:0x66/255.0 alpha:1.0];
}

#pragma mark - supportedFieldMap (align Android MetadataViewUtils.getSupportedFieldMap)

/// Returns { key: @(editable) } for underscore-prefixed fields.
/// true = editable, false = readonly.  Non-underscore fields default to editable.
static NSDictionary<NSString *, NSNumber *> *supportedFieldMap(void) {
    static NSDictionary *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"_size":           @NO,
            @"_file_modifier":  @NO,
            @"_file_mtime":     @NO,
            @"_owner":          @YES,
            @"_description":    @YES,
            @"_collaborators":  @YES,
            @"_reviewer":       @YES,
            @"_status":         @YES,
            @"_location":       @NO,
            @"_tags":           @YES,
            @"_rate":           @YES,
            @"_expire_time":    @YES,
        };
    });
    return map;
}

#pragma mark - Localized titles (align Android ColumnTypeUtils)

static NSString *localizedTitleForKey(NSString *key) {
    // Map metadata keys to iOS localized string keys
    static NSDictionary *titleMap;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        titleMap = @{
            @"_description":    NSLocalizedString(@"Description", @"metadata field"),
            @"_file_modifier":  NSLocalizedString(@"Last Modifier", @"metadata field"),
            @"_file_mtime":     NSLocalizedString(@"Last Modified Time", @"metadata field"),
            @"_status":         NSLocalizedString(@"File Status", @"metadata field"),
            @"_collaborators":  NSLocalizedString(@"Collaborators", @"metadata field"),
            @"_size":           NSLocalizedString(@"Size", @"metadata field"),
            @"_reviewer":       NSLocalizedString(@"Reviewer", @"metadata field"),
            @"_owner":          NSLocalizedString(@"Owner", @"metadata field"),
            @"_tags":           NSLocalizedString(@"Tags", @"metadata field"),
            @"_rate":           NSLocalizedString(@"Rate", @"metadata field"),
            @"_location":       NSLocalizedString(@"Location", @"metadata field"),
            @"_expire_time":    NSLocalizedString(@"Expire Time", @"metadata field"),
        };
    });
    return titleMap[key];
}

#pragma mark - Type normalization (align Android)

static NSString *normalizeType(NSString *rawType, NSString *key) {
    if ([key isEqualToString:@"_file_modifier"]) return @"collaborator";
    if (!rawType || rawType.length == 0) return @"text";
    // Normalize long-text → long_text (Android ColumnType uses "long-text", iOS uses "long_text")
    if ([rawType isEqualToString:@"long-text"]) return @"long_text";
    // Normalize single-select / multiple-select hyphen variants
    if ([rawType isEqualToString:@"single-select"]) return @"single_select";
    if ([rawType isEqualToString:@"multiple-select"]) return @"multiple_select";
    return rawType;
}

@interface SeafSdocProfileEditorViewController () <UITextViewDelegate>
@property (nonatomic, weak) SeafConnection *connection;
@property (nonatomic, copy) NSString *repoId;
@property (nonatomic, strong) SeafFileProfileAggregate *aggregate;

// Internal state (align Android FileProfileEditorActivity)
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *orderedMetadataList;   // ordered metadata field dicts
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *recordMetaDataMap;  // key → mutable metadata dict (with .value)
@property (nonatomic, strong) NSDictionary *detailsSettingsMap;   // key → @(BOOL)
@property (nonatomic, strong) NSArray *relatedUserList;
@property (nonatomic, strong) NSArray *tagList;
@property (nonatomic, copy) NSString *recordId;

/// User edits: key → new value
@property (nonatomic, strong) NSMutableDictionary *contentMap;

// UI
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) SeafSdocService *service;
@end

@implementation SeafSdocProfileEditorViewController

- (instancetype)initWithConnection:(SeafConnection *)connection
                            repoId:(NSString *)repoId
                         aggregate:(SeafFileProfileAggregate *)aggregate
{
    if (self = [super init]) {
        _connection = connection;
        _repoId = repoId;
        _aggregate = aggregate;
        _contentMap = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = NSLocalizedString(@"Edit", @"editor title");
    
    // Apply standard navigation bar appearance (align file list page: white bg, black tint)
    [SeafNavigationBarStyler applyStandardAppearanceToNavigationController:self.navigationController];
    
    // Navigation bar back button (align file list page: arrowLeft_black icon)
    UIBarButtonItem *backItem = [SeafNavigationBarStyler createBackButtonWithTarget:self action:@selector(onCancelTapped) color:nil];
    self.navigationItem.leftBarButtonItem = backItem;
    
    // Navigation bar save button (align Android: blue text)
    UIBarButtonItem *saveItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Save", @"save button")
                                                                style:UIBarButtonItemStyleDone
                                                               target:self
                                                               action:@selector(onSaveTapped)];
    saveItem.tintColor = [UIColor systemBlueColor];
    self.navigationItem.rightBarButtonItem = saveItem;
    
    // Init service
    self.service = [[SeafSdocService alloc] initWithConnection:self.connection];
    
    // Setup scrollable UI
    [self setupScrollView];
    
    // Tap to dismiss keyboard (align Android clearFocus + hideSoftInput)
    UITapGestureRecognizer *tapDismiss = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onBackgroundTapped)];
    tapDismiss.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapDismiss];
    
    // Keyboard avoidance (align Android adaptInputMethod + view_placeholder)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    
    // Parse aggregate into internal state and build UI
    [self parseAggregateAndBuildUI];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onCancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onBackgroundTapped {
    [self.view endEditing:YES];
}

/// Refresh layer.borderColor on dark/light mode change (CGColor doesn't dynamically resolve)
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            UIColor *borderColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
                return tc.userInterfaceStyle == UIUserInterfaceStyleDark
                    ? [UIColor colorWithRed:0x21/255.0 green:0x21/255.0 blue:0x21/255.0 alpha:1.0]
                    : [UIColor colorWithRed:0xE0/255.0 green:0xE5/255.0 blue:0xEC/255.0 alpha:1.0];
            }];
            CGColorRef resolved = [borderColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
            [self updateBorderColorRecursively:self.stackView color:resolved];
        }
    }
}

- (void)updateBorderColorRecursively:(UIView *)view color:(CGColorRef)color {
    if (view.layer.borderWidth > 0) {
        view.layer.borderColor = color;
    }
    for (UIView *sub in view.subviews) {
        [self updateBorderColorRecursively:sub color:color];
    }
}

#pragma mark - UI Setup

- (void)setupScrollView {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];
    
    self.stackView = [[UIStackView alloc] init];
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 0;
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.stackView];
    
    // Fill the frame width on iPhone, but cap the form width on iPad so fields
    // don't stretch edge-to-edge on wide screens (centered column instead).
    NSLayoutConstraint *fullWidth = [self.stackView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor];
    fullWidth.priority = UILayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        // Horizontal anchors use the safe area so content isn't clipped by the
        // notch / rounded corners in landscape.
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.stackView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.stackView.centerXAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.centerXAnchor],
        [self.stackView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.scrollView.contentLayoutGuide.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],
        [self.stackView.widthAnchor constraintLessThanOrEqualToConstant:700],
        fullWidth,
    ]];
}

#pragma mark - Data Parsing (align Android FileProfileConfigModel + setData)

- (void)parseAggregateAndBuildUI {
    if (!self.aggregate) return;
    
    NSDictionary *metadataConfig = self.aggregate.metadataConfig ?: @{};
    NSDictionary *recordWrapper = self.aggregate.recordWrapper ?: @{};
    NSDictionary *relatedUsers = self.aggregate.relatedUsers ?: @{};
    NSDictionary *tagWrapper = self.aggregate.tagWrapper ?: @{};
    
    BOOL metaEnabled = [metadataConfig[@"enabled"] boolValue];
    
    // Build detailsSettingsMap (reuse assembler logic)
    self.detailsSettingsMap = [SeafSdocProfileAssembler buildDetailsSettingsMapFromConfig:metadataConfig metaEnabled:metaEnabled];
    if (!self.detailsSettingsMap) {
        self.detailsSettingsMap = @{};
    }
    
    // Extract metadata and results
    NSArray *metadata = recordWrapper[@"metadata"];
    NSArray *results = recordWrapper[@"results"];
    NSDictionary *singleResult = (results.count > 0 ? results.firstObject : nil);
    
    if (![metadata isKindOfClass:[NSArray class]] || metadata.count == 0 || ![singleResult isKindOfClass:[NSDictionary class]]) {
        return; // No editable metadata
    }
    
    // Record ID
    self.recordId = [singleResult[@"_id"] description];
    
    // Build recordMetaDataMap (ordered, align Android setRecordWrapperModel)
    self.orderedMetadataList = [NSMutableArray array];
    self.recordMetaDataMap = [NSMutableDictionary dictionary];
    
    // Move _size to top (align Android swapSizePosition)
    NSMutableArray *orderedMeta = [NSMutableArray arrayWithArray:metadata];
    NSInteger sizeIdx = NSNotFound;
    for (NSInteger i = 0; i < orderedMeta.count; i++) {
        NSDictionary *m = orderedMeta[i];
        if ([m[@"key"] isEqualToString:@"_size"]) { sizeIdx = i; break; }
    }
    if (sizeIdx != NSNotFound && sizeIdx != 0) {
        NSDictionary *s = orderedMeta[sizeIdx];
        [orderedMeta removeObjectAtIndex:sizeIdx];
        [orderedMeta insertObject:s atIndex:0];
    }
    
    for (NSDictionary *m in orderedMeta) {
        NSString *key = m[@"key"];
        NSString *name = m[@"name"] ?: key;
        if (![key isKindOfClass:[NSString class]]) continue;
        
        NSMutableDictionary *metaMut = [m mutableCopy];
        // Attach value from singleResult (align Android setRecordWrapperModel)
        id rawValue = singleResult[name];
        if ([key isEqualToString:@"_file_modifier"]) {
            metaMut[@"type"] = @"collaborator";
            metaMut[@"value"] = (rawValue ? @[rawValue] : @[]);
        } else {
            metaMut[@"value"] = rawValue ?: [NSNull null];
        }
        
        self.recordMetaDataMap[key] = metaMut;
        [self.orderedMetadataList addObject:metaMut];
    }
    
    // Related users
    NSArray *userList = relatedUsers[@"user_list"];
    self.relatedUserList = [userList isKindOfClass:[NSArray class]] ? userList : @[];
    
    // Tags
    NSArray *tagResults = tagWrapper[@"results"];
    self.tagList = [tagResults isKindOfClass:[NSArray class]] ? tagResults : @[];
    
    // Build UI fields (align Android setData + parseViewByType)
    [self buildFieldViews];
}

#pragma mark - Build Field Views (align Android setData + parseViewByType)

- (void)buildFieldViews {
    NSDictionary *sfMap = supportedFieldMap();
    
    for (NSInteger i = 0; i < (NSInteger)self.orderedMetadataList.count; i++) {
        NSDictionary *metadata = self.orderedMetadataList[i];
        NSString *key = metadata[@"key"];
        NSString *rawType = metadata[@"type"] ?: @"text";
        NSString *type = normalizeType(rawType, key);
        
        // Step 1: detailsSettings visibility filter
        NSNumber *isShown = self.detailsSettingsMap[key];
        if (isShown == nil || ![isShown boolValue]) continue;
        
        // Step 2: whitelist filter for underscore fields
        if ([key hasPrefix:@"_"]) {
            if (!sfMap[key]) continue;
        }
        
        // Step 3: determine editability
        BOOL editable = YES;
        NSNumber *editableNum = sfMap[key];
        if (editableNum) editable = [editableNum boolValue];
        
        // Step 4: title
        NSString *title = localizedTitleForKey(key);
        if (!title) title = metadata[@"name"] ?: key;
        
        // Step 5: build section container
        // Use actual orderedMetadataList index (i) for tag so rebuildFieldUIForKey can map back correctly
        UIView *sectionView = [self buildSectionForKey:key
                                                title:title
                                                 type:type
                                             metadata:metadata
                                             editable:editable
                                                  tag:kContainerTagBase + i];
        if (sectionView) {
            [self.stackView addArrangedSubview:sectionView];
        }
    }
    
    // Add bottom padding
    UIView *spacer = [[UIView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer.heightAnchor constraintEqualToConstant:60].active = YES;
    [self.stackView addArrangedSubview:spacer];
}

/// Build a section view for one metadata field (align Android addMetadataView + parseViewByType)
- (UIView *)buildSectionForKey:(NSString *)key
                         title:(NSString *)title
                          type:(NSString *)type
                      metadata:(NSDictionary *)metadata
                      editable:(BOOL)editable
                           tag:(NSInteger)tag
{
    UIView *container = [[UIView alloc] init];
    container.tag = tag;
    container.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Title label
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular]; // align Android: 16sp Regular
    titleLabel.textColor = editorTitleColor(); // align Android: profile_editor_title #666666
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:titleLabel];
    
    // Content area (will be populated by type-specific builder)
    UIView *contentView = [self buildContentViewForType:type key:key metadata:metadata editable:editable];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.tag = kContentViewTag;
    [container addSubview:contentView];
    
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:16],
        [titleLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [titleLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        
        [contentView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6],
        [contentView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [contentView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [contentView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-4],
    ]];
    
    return container;
}

#pragma mark - Type-specific content builders (align Android MetadataViewUtils.buildEditable*)

- (UIView *)buildContentViewForType:(NSString *)type
                                key:(NSString *)key
                           metadata:(NSDictionary *)metadata
                           editable:(BOOL)editable
{
    id value = metadata[@"value"];
    if (value == (id)[NSNull null]) value = nil;
    
    if ([type isEqualToString:@"text"] || [type isEqualToString:@"url"] || [type isEqualToString:@"email"]) {
        return [self buildTextFieldForKey:key value:value editable:editable];
    }
    else if ([type isEqualToString:@"long_text"] || [type isEqualToString:@"long-text"]) {
        return [self buildLongTextViewForKey:key value:value editable:editable];
    }
    else if ([type isEqualToString:@"number"]) {
        return [self buildNumberFieldForKey:key value:value editable:editable metadata:metadata];
    }
    else if ([type isEqualToString:@"date"]) {
        return [self buildDateFieldForKey:key value:value editable:editable metadata:metadata];
    }
    else if ([type isEqualToString:@"single_select"] || [type isEqualToString:@"single-select"]) {
        return [self buildSingleSelectForKey:key value:value editable:editable metadata:metadata];
    }
    else if ([type isEqualToString:@"multiple_select"] || [type isEqualToString:@"multiple-select"]) {
        return [self buildMultiSelectForKey:key value:value editable:editable metadata:metadata];
    }
    else if ([type isEqualToString:@"collaborator"]) {
        return [self buildCollaboratorViewForKey:key value:value editable:editable];
    }
    else if ([type isEqualToString:@"rate"]) {
        return [self buildRateViewForKey:key value:value editable:editable metadata:metadata];
    }
    else if ([type isEqualToString:@"checkbox"]) {
        return [self buildCheckboxForKey:key value:value editable:editable];
    }
    else if ([type isEqualToString:@"geolocation"]) {
        return [self buildReadonlyTextForValue:[self geolocationDisplayString:value]];
    }
    else if ([type isEqualToString:@"link"]) {
        if ([key isEqualToString:@"_tags"]) {
            return [self buildTagViewForKey:key metadata:metadata editable:editable];
        }
        return [self buildReadonlyTextForValue:@""];
    }
    else {
        // Default: readonly text
        NSString *display = [value isKindOfClass:[NSString class]] ? value : [value description];
        return [self buildReadonlyTextForValue:display ?: @""];
    }
}

#pragma mark - Text Field (align Android buildEditableText)

- (UIView *)buildTextFieldForKey:(NSString *)key value:(id)value editable:(BOOL)editable {
    UITextField *textField = [[UITextField alloc] init];
    textField.text = [value isKindOfClass:[NSString class]] ? value : [value description];
    textField.borderStyle = UITextBorderStyleNone; // align Android: custom border via layer
    textField.font = [UIFont systemFontOfSize:16]; // align Android: 16sp
    textField.enabled = editable;
    textField.textColor = editable ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    textField.accessibilityIdentifier = [NSString stringWithFormat:@"editor_text_%@", key];
    
    // Align Android: shape_task_view_editable / shape_task_view_no_editable
    if (editable) {
        applyEditableCellStyle(textField);
    } else {
        applyNonEditableCellStyle(textField);
    }
    
    // Internal padding (align Android: padding 16dp/8dp)
    textField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 16, 0)];
    textField.leftViewMode = UITextFieldViewModeAlways;
    textField.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 16, 0)];
    textField.rightViewMode = UITextFieldViewModeAlways;
    
    if (editable) {
        [textField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
        objc_setAssociatedObject(textField, "metadataKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    
    [textField.heightAnchor constraintGreaterThanOrEqualToConstant:40].active = YES;
    return textField;
}

- (void)textFieldDidChange:(UITextField *)textField {
    NSString *key = objc_getAssociatedObject(textField, "metadataKey");
    if (key) {
        self.contentMap[key] = textField.text ?: @"";
    }
}

#pragma mark - Number Field (align Android buildEditableNumber)

- (UIView *)buildNumberFieldForKey:(NSString *)key value:(id)value editable:(BOOL)editable metadata:(NSDictionary *)metadata {
    UITextField *textField = [[UITextField alloc] init];
    
    // Get configData for formatting (align Android MetadataConfigDataModel)
    NSDictionary *configData = metadata[@"data"];
    if ([configData isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)configData;
        configData = arr.count > 0 ? arr.firstObject : nil;
    }
    
    // Display formatted number (align Android getFormattedNumber)
    NSString *displayValue = @"";
    if ([value isKindOfClass:[NSNumber class]]) {
        if ([key isEqualToString:@"_size"]) {
            displayValue = [SeafSdocProfileAssembler readableSize:[(NSNumber *)value longLongValue]];
        } else {
            displayValue = [SeafSdocProfileAssembler formatNumber:(NSNumber *)value withMetadata:metadata];
        }
    } else if ([value isKindOfClass:[NSString class]]) {
        displayValue = value;
    }
    
    textField.text = displayValue;
    textField.borderStyle = UITextBorderStyleNone; // align Android: custom border via layer
    textField.font = [UIFont systemFontOfSize:16]; // align Android: 16sp
    textField.keyboardType = UIKeyboardTypeDecimalPad;
    textField.enabled = editable;
    textField.textColor = editable ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    textField.accessibilityIdentifier = [NSString stringWithFormat:@"editor_number_%@", key];
    
    // Align Android: shape_task_view_editable / shape_task_view_no_editable
    if (editable) {
        applyEditableCellStyle(textField);
    } else {
        applyNonEditableCellStyle(textField);
    }
    
    // Internal padding (align Android: padding 16dp/8dp)
    textField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 16, 0)];
    textField.leftViewMode = UITextFieldViewModeAlways;
    textField.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 16, 0)];
    textField.rightViewMode = UITextFieldViewModeAlways;
    
    if (editable) {
        [textField addTarget:self action:@selector(numberFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
        objc_setAssociatedObject(textField, "metadataKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(textField, "metadataDict", metadata, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // Align Android: show raw number on focus, formatted number on blur
        [textField addTarget:self action:@selector(numberFieldDidBeginEditing:) forControlEvents:UIControlEventEditingDidBegin];
        [textField addTarget:self action:@selector(numberFieldDidEndEditing:) forControlEvents:UIControlEventEditingDidEnd];
    }
    
    [textField.heightAnchor constraintGreaterThanOrEqualToConstant:40].active = YES;
    return textField;
}

/// Strip formatting (thousands separator, currency symbol, percent sign) to get raw number string
/// Align Android: MetadataViewUtils.getOriginalNumberByFormattedString()
- (NSString *)getOriginalNumberFromFormattedString:(NSString *)formattedString configData:(NSDictionary *)configData {
    if (!formattedString || formattedString.length == 0) return @"0";
    
    // Remove non-numeric characters except digits, minus, dot, comma, space
    NSMutableString *cleaned = [NSMutableString string];
    BOOL foundNumeric = NO;
    BOOL foundNegative = NO;
    BOOL isPercentage = [formattedString containsString:@"%"];
    
    for (NSUInteger i = 0; i < formattedString.length; i++) {
        unichar c = [formattedString characterAtIndex:i];
        if (c == '-' && !foundNumeric && !foundNegative) {
            foundNegative = YES;
            [cleaned appendFormat:@"%C", c];
            foundNumeric = YES;
        } else if (c >= '0' && c <= '9') {
            [cleaned appendFormat:@"%C", c];
            foundNumeric = YES;
        } else if (c == '.' || c == ',' || c == ' ') {
            [cleaned appendFormat:@"%C", c];
            foundNumeric = YES;
        }
    }
    
    if (cleaned.length == 0) return @"0";
    
    NSString *thousands = configData[@"thousands"] ?: @"no";
    NSString *decimal = configData[@"decimal"] ?: @"dot";
    NSString *result = [cleaned copy];
    
    // Determine and remove thousands separator
    if ([thousands isEqualToString:@"comma"]) {
        if ([decimal isEqualToString:@"comma"]) {
            // Both comma: last comma is decimal point (align Android special handling)
            NSRange lastComma = [result rangeOfString:@"," options:NSBackwardsSearch];
            if (lastComma.location != NSNotFound) {
                NSString *afterLast = [result substringFromIndex:lastComma.location + 1];
                NSString *beforeLast = [result substringToIndex:lastComma.location];
                if (afterLast.length != 3 || ([configData[@"enable_precision"] boolValue] && [configData[@"precision"] integerValue] == 3)) {
                    result = [NSString stringWithFormat:@"%@.%@", beforeLast, afterLast];
                } else {
                    result = [beforeLast stringByAppendingString:afterLast];
                }
            }
            result = [result stringByReplacingOccurrencesOfString:@"," withString:@""];
        } else {
            result = [result stringByReplacingOccurrencesOfString:@"," withString:@""];
        }
    } else if ([thousands isEqualToString:@"space"]) {
        result = [result stringByReplacingOccurrencesOfString:@" " withString:@""];
    }
    
    // Replace decimal separator with standard dot
    if ([decimal isEqualToString:@"comma"] && ![thousands isEqualToString:@"comma"]) {
        result = [result stringByReplacingOccurrencesOfString:@"," withString:@"."];
    }
    
    // Remove remaining spaces
    result = [result stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    if (result.length == 0 || [result isEqualToString:@"-"]) return @"0";
    
    // Handle percentage: divide by 100 (align Android)
    if (isPercentage) {
        double val = [result doubleValue] / 100.0;
        result = [NSString stringWithFormat:@"%g", val];
    }
    
    return result;
}

- (void)numberFieldDidBeginEditing:(UITextField *)textField {
    // On focus: show raw number (align Android onFocusChange hasFocus=true)
    NSDictionary *metadata = objc_getAssociatedObject(textField, "metadataDict");
    NSDictionary *configData = metadata[@"data"];
    if ([configData isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)configData;
        configData = arr.count > 0 ? arr.firstObject : nil;
    }
    NSString *raw = [self getOriginalNumberFromFormattedString:textField.text configData:configData];
    textField.text = raw;
}

- (void)numberFieldDidEndEditing:(UITextField *)textField {
    // On blur: show formatted number (align Android onFocusChange hasFocus=false)
    NSString *inputStr = textField.text;
    if (!inputStr || inputStr.length == 0) return;
    
    NSDictionary *metadata = objc_getAssociatedObject(textField, "metadataDict");
    @try {
        double val = [inputStr doubleValue];
        NSString *formatted = [SeafSdocProfileAssembler formatNumber:@(val) withMetadata:metadata];
        textField.text = formatted;
    } @catch (NSException *e) {
        // If parsing fails, keep as is
    }
}

- (void)numberFieldDidChange:(UITextField *)textField {
    NSString *key = objc_getAssociatedObject(textField, "metadataKey");
    if (key) {
        NSDictionary *metadata = objc_getAssociatedObject(textField, "metadataDict");
        NSDictionary *configData = metadata[@"data"];
        if ([configData isKindOfClass:[NSArray class]]) {
            NSArray *arr = (NSArray *)configData;
            configData = arr.count > 0 ? arr.firstObject : nil;
        }
        NSString *raw = [self getOriginalNumberFromFormattedString:textField.text configData:configData];
        double val = [raw doubleValue];
        self.contentMap[key] = @(val);
    }
}

#pragma mark - Date Field (align Android buildEditableDate)

- (UIView *)buildDateFieldForKey:(NSString *)key value:(id)value editable:(BOOL)editable metadata:(NSDictionary *)metadata {
    UIView *wrapper = [[UIView alloc] init];
    
    // Align Android: shape_task_view_editable / shape_task_view_no_editable
    if (editable) {
        applyEditableCellStyle(wrapper);
    } else {
        applyNonEditableCellStyle(wrapper);
    }
    
    UILabel *dateLabel = [[UILabel alloc] init];
    dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    dateLabel.font = [UIFont systemFontOfSize:16]; // align Android: 16sp
    dateLabel.textColor = editable ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    
    NSString *displayDate = @"";
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        displayDate = value;
    }
    dateLabel.text = displayDate;
    
    [wrapper addSubview:dateLabel];
    [NSLayoutConstraint activateConstraints:@[
        [dateLabel.topAnchor constraintEqualToAnchor:wrapper.topAnchor constant:8],
        [dateLabel.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:16], // align Android: padding 16dp
        [dateLabel.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor constant:-16],
        [dateLabel.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor constant:-8],
    ]];
    
    if (editable) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onDateTapped:)];
        wrapper.userInteractionEnabled = YES;
        [wrapper addGestureRecognizer:tap];
        objc_setAssociatedObject(wrapper, "metadataKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(wrapper, "metadataDict", metadata, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // Add disclosure indicator
        UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        arrow.translatesAutoresizingMaskIntoConstraints = NO;
        arrow.tintColor = [UIColor tertiaryLabelColor];
        [wrapper addSubview:arrow];
        [NSLayoutConstraint activateConstraints:@[
            [arrow.centerYAnchor constraintEqualToAnchor:wrapper.centerYAnchor],
            [arrow.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor constant:-16],
            [arrow.widthAnchor constraintEqualToConstant:12],
            [arrow.heightAnchor constraintEqualToConstant:16],
        ]];
    }
    
    [wrapper.heightAnchor constraintGreaterThanOrEqualToConstant:40].active = YES;
    return wrapper;
}

- (void)onDateTapped:(UITapGestureRecognizer *)tap {
    NSString *key = objc_getAssociatedObject(tap.view, "metadataKey");
    NSDictionary *metadata = objc_getAssociatedObject(tap.view, "metadataDict");
    if (!key) return;

    // Current value
    NSDate *initialDate = nil;
    id currentValue = metadata[@"value"];
    if ([currentValue isKindOfClass:[NSString class]] && [(NSString *)currentValue length] > 0) {
        initialDate = [self parseDateString:currentValue];
    }

    __weak typeof(self) weakSelf = self;
    SeafSdocDatePickerViewController *picker =
        [[SeafSdocDatePickerViewController alloc] initWithTitle:NSLocalizedString(@"Select Date", @"date picker title")
                                                    initialDate:initialDate
                                                     completion:^(NSDate *date) {
            NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
            fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSXXX";
            NSString *dateStr = [fmt stringFromDate:date];

            weakSelf.contentMap[key] = dateStr;
            [weakSelf updateFieldUIForKey:key withValue:dateStr];
        }];
    picker.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - Long Text (align Android buildEditableLongText → click to open LongTextSelectorActivity)

- (UIView *)buildLongTextViewForKey:(NSString *)key value:(id)value editable:(BOOL)editable {
    // Align Android: buildEditableLongText uses a non-editable TextView + click to launch LongTextSelectorActivity
    UIView *wrapper = [[UIView alloc] init];
    
    if (editable) {
        applyEditableCellStyle(wrapper);
    } else {
        applyNonEditableCellStyle(wrapper);
    }
    
    // Display label (non-editable, align Android: TextView with Gravity.START)
    UILabel *textLabel = [[UILabel alloc] init];
    textLabel.translatesAutoresizingMaskIntoConstraints = NO;
    textLabel.font = [UIFont systemFontOfSize:16]; // align Android: 16sp
    textLabel.textColor = editable ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    textLabel.numberOfLines = 0; // multi-line
    textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    textLabel.accessibilityIdentifier = [NSString stringWithFormat:@"editor_longtext_%@", key];
    
    NSString *displayText = [value isKindOfClass:[NSString class]] ? value : @"";
    if (displayText.length > 0) {
        textLabel.text = displayText;
    } else {
        textLabel.text = NSLocalizedString(@"Empty", @"placeholder for empty long text");
        textLabel.textColor = [UIColor tertiaryLabelColor];
    }
    
    [wrapper addSubview:textLabel];
    
    // Constraints: padding 16dp horizontal, 8dp vertical (align Android)
    [NSLayoutConstraint activateConstraints:@[
        [textLabel.topAnchor constraintEqualToAnchor:wrapper.topAnchor constant:8],
        [textLabel.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:16],
        [textLabel.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor constant:-16],
        [textLabel.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor constant:-8],
    ]];
    
    // Min height 72pt (align Android: DP_72)
    [wrapper.heightAnchor constraintGreaterThanOrEqualToConstant:72].active = YES;
    
    // Tap to open full-screen editor (align Android: onClick → LongTextSelectorActivity)
    if (editable) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onLongTextTapped:)];
        wrapper.userInteractionEnabled = YES;
        [wrapper addGestureRecognizer:tap];
        objc_setAssociatedObject(wrapper, "metadataKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        
        // Add disclosure indicator (align Android: shows navigability)
        UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        arrow.translatesAutoresizingMaskIntoConstraints = NO;
        arrow.tintColor = [UIColor tertiaryLabelColor];
        [wrapper addSubview:arrow];
        [NSLayoutConstraint activateConstraints:@[
            [arrow.centerYAnchor constraintEqualToAnchor:wrapper.centerYAnchor],
            [arrow.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor constant:-16],
            [arrow.widthAnchor constraintEqualToConstant:12],
            [arrow.heightAnchor constraintEqualToConstant:16],
        ]];
        // Adjust text trailing to not overlap arrow
        for (NSLayoutConstraint *c in textLabel.constraints) {
            // no-op: constraints are on wrapper, not textLabel
        }
        // Re-pin textLabel trailing to leave room for arrow
        for (NSLayoutConstraint *c in wrapper.constraints) {
            if (c.firstItem == textLabel && c.firstAttribute == NSLayoutAttributeTrailing) {
                c.constant = -36; // 16 + 12 (arrow) + 8 (gap)
                break;
            }
        }
    }
    
    return wrapper;
}

/// Handle tap on long text field: present full-screen editor (align Android: LongTextSelectorActivity)
- (void)onLongTextTapped:(UITapGestureRecognizer *)tap {
    NSString *key = objc_getAssociatedObject(tap.view, "metadataKey");
    if (!key) return;
    
    NSDictionary *metaMut = self.recordMetaDataMap[key];
    id value = metaMut[@"value"];
    if (value == (id)[NSNull null]) value = nil;
    NSString *currentText = [value isKindOfClass:[NSString class]] ? value : @"";
    
    // Get title
    NSString *title = localizedTitleForKey(key);
    if (!title) title = metaMut[@"name"] ?: key;
    
    __weak typeof(self) weakSelf = self;
    SeafSdocLongTextEditorViewController *editor =
        [[SeafSdocLongTextEditorViewController alloc] initWithKey:key
                                                           title:title
                                                     initialText:currentText
                                                      completion:^(NSString *returnedKey, NSString *text) {
            weakSelf.contentMap[returnedKey] = text;
            [weakSelf updateFieldUIForKey:returnedKey withValue:text];
        }];
    
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Checkbox (align Android buildEditableCheckbox)

- (UIView *)buildCheckboxForKey:(NSString *)key value:(id)value editable:(BOOL)editable {
    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = [value boolValue];
    toggle.enabled = editable;
    toggle.accessibilityIdentifier = [NSString stringWithFormat:@"editor_checkbox_%@", key];
    
    if (editable) {
        [toggle addTarget:self action:@selector(checkboxChanged:) forControlEvents:UIControlEventValueChanged];
        objc_setAssociatedObject(toggle, "metadataKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    
    UIView *wrapper = [[UIView alloc] init];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    [wrapper addSubview:toggle];
    [NSLayoutConstraint activateConstraints:@[
        [toggle.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor],
        [toggle.topAnchor constraintEqualToAnchor:wrapper.topAnchor constant:4],
        [toggle.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor constant:-4],
    ]];
    return wrapper;
}

- (void)checkboxChanged:(UISwitch *)sw {
    NSString *key = objc_getAssociatedObject(sw, "metadataKey");
    if (key) {
        self.contentMap[key] = @(sw.isOn);
    }
}

#pragma mark - Rate (align Android buildEditableRate)

- (UIView *)buildRateViewForKey:(NSString *)key value:(id)value editable:(BOOL)editable metadata:(NSDictionary *)metadata {
    NSInteger maxRate = 5;
    NSString *rateStyleColor = nil;
    NSDictionary *configData = metadata[@"data"];
    if ([configData isKindOfClass:[NSDictionary class]]) {
        id rateMax = configData[@"rate_max_number"];
        if ([rateMax isKindOfClass:[NSNumber class]]) maxRate = [rateMax integerValue];
        // Read rate_style_color from config (align Android configDataModel.rate_style_color)
        id colorVal = configData[@"rate_style_color"];
        if ([colorVal isKindOfClass:[NSString class]] && [(NSString *)colorVal length] > 0) {
            rateStyleColor = (NSString *)colorVal;
        }
    }
    
    // Parse the configured color, fallback to grey (229,229,229) as Android does
    UIColor *filledColor = [UIColor colorWithRed:229.0/255.0 green:229.0/255.0 blue:229.0/255.0 alpha:1.0];
    if (rateStyleColor) {
        UIColor *parsed = [self rateColorFromHex:rateStyleColor];
        if (parsed) filledColor = parsed;
    }
    
    NSInteger currentRate = [value isKindOfClass:[NSNumber class]] ? [value integerValue] : 0;
    
    UIStackView *starStack = [[UIStackView alloc] init];
    starStack.axis = UILayoutConstraintAxisHorizontal;
    starStack.spacing = 4;
    starStack.distribution = UIStackViewDistributionFillEqually;
    
    for (NSInteger i = 1; i <= maxRate; i++) {
        UIButton *star = [UIButton buttonWithType:UIButtonTypeSystem];
        NSString *imgName = (i <= currentRate) ? @"star.fill" : @"star";
        [star setImage:[UIImage systemImageNamed:imgName] forState:UIControlStateNormal];
        star.tintColor = (i <= currentRate) ? filledColor : [UIColor tertiaryLabelColor];
        star.tag = i;
        star.enabled = editable;
        star.accessibilityIdentifier = [NSString stringWithFormat:@"editor_rate_%@_%ld", key, (long)i];
        
        if (editable) {
            [star addTarget:self action:@selector(starTapped:) forControlEvents:UIControlEventTouchUpInside];
            objc_setAssociatedObject(star, "metadataKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
            objc_setAssociatedObject(star, "maxRate", @(maxRate), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(star, "rateColor", filledColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        
        [starStack addArrangedSubview:star];
    }
    
    // Fill remaining space
    UIView *spacer = [[UIView alloc] init];
    [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [starStack addArrangedSubview:spacer];
    
    [starStack.heightAnchor constraintEqualToConstant:36].active = YES;
    return starStack;
}

- (void)starTapped:(UIButton *)button {
    NSString *key = objc_getAssociatedObject(button, "metadataKey");
    NSNumber *maxRateNum = objc_getAssociatedObject(button, "maxRate");
    UIColor *rateColor = objc_getAssociatedObject(button, "rateColor") ?: [UIColor colorWithRed:229.0/255.0 green:229.0/255.0 blue:229.0/255.0 alpha:1.0];
    NSInteger maxRate = [maxRateNum integerValue] ?: 5;
    NSInteger tappedRate = button.tag;
    
    if (key) {
        self.contentMap[key] = @(tappedRate);
    }
    
    // Update visual state
    UIStackView *stack = (UIStackView *)button.superview;
    for (UIView *sub in stack.arrangedSubviews) {
        if ([sub isKindOfClass:[UIButton class]]) {
            UIButton *s = (UIButton *)sub;
            BOOL filled = (s.tag <= tappedRate);
            [s setImage:[UIImage systemImageNamed:filled ? @"star.fill" : @"star"] forState:UIControlStateNormal];
            s.tintColor = filled ? rateColor : [UIColor tertiaryLabelColor];
        }
    }
}

#pragma mark - Single Select (align Android buildEditableSingleSelect)

- (UIView *)buildSingleSelectForKey:(NSString *)key value:(id)value editable:(BOOL)editable metadata:(NSDictionary *)metadata {
    NSArray *options = metadata[@"data"][@"options"];
    if (![options isKindOfClass:[NSArray class]]) options = @[];
    
    NSString *selectedName = [value isKindOfClass:[NSString class]] ? value : nil;
    
    // Use a chips-style display with a tap to show picker
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:15];
    label.textColor = [UIColor labelColor];
    label.text = selectedName ?: NSLocalizedString(@"Select...", @"placeholder");
    if (!selectedName) label.textColor = [UIColor tertiaryLabelColor];
    
    if (editable) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onSingleSelectTapped:)];
        label.userInteractionEnabled = YES;
        [label addGestureRecognizer:tap];
        objc_setAssociatedObject(label, "metadataKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(label, "selectOptions", options, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    [label.heightAnchor constraintGreaterThanOrEqualToConstant:40].active = YES;
    return label;
}

- (void)onSingleSelectTapped:(UITapGestureRecognizer *)tap {
    NSString *key = objc_getAssociatedObject(tap.view, "metadataKey");
    NSArray *options = objc_getAssociatedObject(tap.view, "selectOptions");
    if (!key || !options) return;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *opt in options) {
        NSString *name = opt[@"name"] ?: @"";
        [alert addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            weakSelf.contentMap[key] = opt;
            [weakSelf updateFieldUIForKey:key withValue:name];
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:nil]];

    // iPad: action sheets are presented as popovers and require an anchor
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = tap.view;
        popover.sourceRect = tap.view.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Multiple Select (align Android buildEditableMultiSelect)

- (UIView *)buildMultiSelectForKey:(NSString *)key value:(id)value editable:(BOOL)editable metadata:(NSDictionary *)metadata {
    NSArray *options = metadata[@"data"][@"options"];
    if (![options isKindOfClass:[NSArray class]]) options = @[];
    
    NSArray *selectedNames = [value isKindOfClass:[NSArray class]] ? value : @[];
    
    NSString *displayText = [selectedNames componentsJoinedByString:@", "];
    if (displayText.length == 0) displayText = NSLocalizedString(@"Select...", @"placeholder");
    
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:15];
    label.textColor = selectedNames.count > 0 ? [UIColor labelColor] : [UIColor tertiaryLabelColor];
    label.text = displayText;
    label.numberOfLines = 0;
    
    if (editable) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onMultiSelectTapped:)];
        label.userInteractionEnabled = YES;
        [label addGestureRecognizer:tap];
        objc_setAssociatedObject(label, "metadataKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(label, "selectOptions", options, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, "selectedValues", [selectedNames mutableCopy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    [label.heightAnchor constraintGreaterThanOrEqualToConstant:40].active = YES;
    return label;
}

- (void)onMultiSelectTapped:(UITapGestureRecognizer *)tap {
    NSString *key = objc_getAssociatedObject(tap.view, "metadataKey");
    NSArray *options = objc_getAssociatedObject(tap.view, "selectOptions");
    if (!key || !options) return;

    // Get current selections
    NSMutableDictionary *metaMut = self.recordMetaDataMap[key];
    id currentValue = metaMut[@"value"];
    NSArray *currentNames = [currentValue isKindOfClass:[NSArray class]] ? currentValue : @[];

    // Build selector items (align Android SupportMetadataCheckGroup)
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSDictionary *opt in options) {
        NSString *name = opt[@"name"] ?: @"";
        [items addObject:@{ @"id": name, @"name": name }];
    }

    __weak typeof(self) weakSelf = self;
    SeafSdocOptionSelectorViewController *selector =
        [[SeafSdocOptionSelectorViewController alloc] initWithTitle:NSLocalizedString(@"Select Options", @"")
                                                              items:items
                                                        selectedIds:currentNames
                                                         completion:^(NSArray<NSString *> *selectedIds) {
            NSSet *selectedNameSet = [NSSet setWithArray:selectedIds];
            NSMutableArray *selectedOpts = [NSMutableArray array];
            for (NSDictionary *opt in options) {
                if ([selectedNameSet containsObject:opt[@"name"] ?: @""]) {
                    [selectedOpts addObject:opt];
                }
            }
            weakSelf.contentMap[key] = [selectedOpts copy];
            [weakSelf updateFieldUIForKey:key withValue:selectedIds];
        }];
    selector.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:selector animated:YES completion:nil];
}

#pragma mark - Collaborator (align Android buildEditableCollaborator)

- (UIView *)buildCollaboratorViewForKey:(NSString *)key value:(id)value editable:(BOOL)editable {
    NSArray *emails = [value isKindOfClass:[NSArray class]] ? value : @[];
    
    // Build user info (name + avatar) from relatedUserList
    NSMutableArray<NSDictionary *> *userInfos = [NSMutableArray array];
    for (id email in emails) {
        NSString *emailStr = [email isKindOfClass:[NSString class]] ? email : [email description];
        NSString *name = emailStr;
        NSString *avatarURL = @"";
        for (NSDictionary *user in self.relatedUserList) {
            if ([user[@"email"] isEqualToString:emailStr]) {
                name = user[@"name"] ?: emailStr;
                avatarURL = user[@"avatar_url"] ?: @"";
                break;
            }
        }
        [userInfos addObject:@{ @"name": name, @"avatar": avatarURL }];
    }
    
    // Empty state: show placeholder label
    if (userInfos.count == 0) {
        UILabel *label = [[UILabel alloc] init];
        label.font = [UIFont systemFontOfSize:15];
        label.textColor = [UIColor tertiaryLabelColor];
        label.text = NSLocalizedString(@"Select...", @"placeholder");
        label.numberOfLines = 0;
        
        if (editable) {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onCollaboratorTapped:)];
            label.userInteractionEnabled = YES;
            [label addGestureRecognizer:tap];
            objc_setAssociatedObject(label, "metadataKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
        
        [label.heightAnchor constraintGreaterThanOrEqualToConstant:40].active = YES;
        return label;
    }
    
    // Capsule chip flow layout: horizontal wrap with SeafCollaboratorChipView
    UIView *wrapper = [[UIView alloc] init];
    wrapper.translatesAutoresizingMaskIntoConstraints = NO;
    
    if (editable) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onCollaboratorTapped:)];
        wrapper.userInteractionEnabled = YES;
        [wrapper addGestureRecognizer:tap];
        objc_setAssociatedObject(wrapper, "metadataKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    
    // Layout chips in a horizontal flow (left-to-right, wrapping)
    CGFloat chipSpacing = 6.0;
    CGFloat lineSpacing = 6.0;
    SeafCollaboratorChipView *prevChip = nil;
    NSMutableArray<SeafCollaboratorChipView *> *chips = [NSMutableArray array];
    
    for (NSDictionary *info in userInfos) {
        SeafCollaboratorChipView *chip = [[SeafCollaboratorChipView alloc] init];
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        [chip configureWithName:info[@"name"] avatarURL:info[@"avatar"]];
        [wrapper addSubview:chip];
        [chips addObject:chip];
    }
    
    // Use a simple horizontal stack approach with manual wrapping via intrinsic sizes
    // Since we can't do true flow-layout in pure Auto Layout, use a vertical stack of horizontal stacks
    // But for simplicity and correctness, embed chips directly and rely on intrinsic sizing
    // The chips have fixed intrinsic height (22pt) so we stack them horizontally with wrap support
    [self layoutChips:chips inContainer:wrapper spacing:chipSpacing lineSpacing:lineSpacing];
    
    [wrapper.heightAnchor constraintGreaterThanOrEqualToConstant:22].active = YES;
    return wrapper;
}

/// Layout chip views in a flow layout within a container view
- (void)layoutChips:(NSArray<SeafCollaboratorChipView *> *)chips
        inContainer:(UIView *)container
            spacing:(CGFloat)spacing
        lineSpacing:(CGFloat)lineSpacing {
    if (chips.count == 0) return;
    
    // Use a UIStackView-based approach: one horizontal stack per line
    // We calculate max width dynamically via layoutSubviews override
    // For now, use a simple vertical stack with embedded horizontal stacks
    UIStackView *verticalStack = [[UIStackView alloc] init];
    verticalStack.axis = UILayoutConstraintAxisVertical;
    verticalStack.spacing = lineSpacing;
    verticalStack.alignment = UIStackViewAlignmentLeading;
    verticalStack.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Remove chips from container (they were added for configure), re-add to stack
    for (SeafCollaboratorChipView *chip in chips) {
        [chip removeFromSuperview];
    }
    
    [container addSubview:verticalStack];
    [NSLayoutConstraint activateConstraints:@[
        [verticalStack.topAnchor constraintEqualToAnchor:container.topAnchor],
        [verticalStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [verticalStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [verticalStack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    
    // Create a single horizontal stack (wrapping handled by compression resistance)
    UIStackView *currentRow = [self makeChipRowStackWithSpacing:spacing];
    [verticalStack addArrangedSubview:currentRow];
    
    for (SeafCollaboratorChipView *chip in chips) {
        [currentRow addArrangedSubview:chip];
    }
}

/// Present collaborator multi-select with checkmarks (align Android CollaboratorSelectorFragment)
- (void)onCollaboratorTapped:(UITapGestureRecognizer *)tap {
    NSString *key = objc_getAssociatedObject(tap.view, "metadataKey");
    if (!key) return;

    // Get current selected emails
    NSMutableDictionary *metaMut = self.recordMetaDataMap[key];
    id currentValue = metaMut[@"value"];
    NSArray *currentEmails = [currentValue isKindOfClass:[NSArray class]] ? currentValue : @[];
    NSMutableArray<NSString *> *selectedEmails = [NSMutableArray array];
    for (id e in currentEmails) {
        [selectedEmails addObject:[e isKindOfClass:[NSString class]] ? e : [e description]];
    }

    // Build selector items from related users
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    NSMutableSet<NSString *> *knownEmails = [NSMutableSet set];
    for (NSDictionary *user in self.relatedUserList) {
        NSString *email = user[@"email"] ?: @"";
        NSString *name = user[@"name"] ?: user[@"email"] ?: @"";
        [items addObject:@{ @"id": email, @"name": name }];
        if (email.length > 0) [knownEmails addObject:email];
    }

    __weak typeof(self) weakSelf = self;
    SeafSdocOptionSelectorViewController *selector =
        [[SeafSdocOptionSelectorViewController alloc] initWithTitle:NSLocalizedString(@"Select Collaborators", @"")
                                                              items:items
                                                        selectedIds:selectedEmails
                                                         completion:^(NSArray<NSString *> *selectedIds) {
            // Keep previously-selected emails that are not in relatedUserList —
            // they can't be shown in the selector and must not be dropped on save
            NSMutableArray<NSString *> *merged = [selectedIds mutableCopy];
            for (NSString *email in selectedEmails) {
                if (![knownEmails containsObject:email]) {
                    [merged addObject:email];
                }
            }
            weakSelf.contentMap[key] = [merged copy];
            [weakSelf updateFieldUIForKey:key withValue:[merged copy]];
        }];
    selector.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:selector animated:YES completion:nil];
}

#pragma mark - Tag (align Android buildEditableTag + TagSelectorFragment)

- (UIView *)buildTagViewForKey:(NSString *)key metadata:(NSDictionary *)metadata editable:(BOOL)editable {
    // Current tags from metadata value (link type stores tag references)
    NSArray *currentTags = metadata[@"value"];
    if (![currentTags isKindOfClass:[NSArray class]]) currentTags = @[];
    
    // Resolve tag info (id, name, color) from tagList
    NSMutableArray<NSDictionary *> *resolvedTags = [NSMutableArray array];
    for (NSDictionary *tag in currentTags) {
        NSString *tagId = tag[@"row_id"] ?: tag[@"_id"] ?: @"";
        for (NSDictionary *t in self.tagList) {
            if ([t[@"_id"] isEqualToString:tagId]) {
                [resolvedTags addObject:@{
                    @"id": t[@"_id"] ?: @"",
                    @"name": t[@"_tag_name"] ?: @"",
                    @"color": t[@"_tag_color"] ?: @""
                }];
                break;
            }
        }
    }
    
    // Empty state: show placeholder label (align Android: empty FlexboxLayout with + button)
    if (resolvedTags.count == 0 && !editable) {
        UILabel *label = [[UILabel alloc] init];
        label.font = [UIFont systemFontOfSize:15];
        label.textColor = [UIColor tertiaryLabelColor];
        label.text = NSLocalizedString(@"Empty", @"placeholder for empty tags");
        label.numberOfLines = 0;
        [label.heightAnchor constraintGreaterThanOrEqualToConstant:40].active = YES;
        return label;
    }
    
    // Chip flow layout container (align Android: FlexboxLayout with layout_detail_tag chips)
    UIView *wrapper = [[UIView alloc] init];
    wrapper.translatesAutoresizingMaskIntoConstraints = NO;
    
    UIStackView *verticalStack = [[UIStackView alloc] init];
    verticalStack.axis = UILayoutConstraintAxisVertical;
    verticalStack.spacing = 6;
    verticalStack.alignment = UIStackViewAlignmentLeading;
    verticalStack.translatesAutoresizingMaskIntoConstraints = NO;
    [wrapper addSubview:verticalStack];
    
    [NSLayoutConstraint activateConstraints:@[
        [verticalStack.topAnchor constraintEqualToAnchor:wrapper.topAnchor],
        [verticalStack.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor],
        [verticalStack.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor],
        [verticalStack.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor],
    ]];
    
    UIStackView *currentRow = [self makeChipRowStackWithSpacing:6];
    [verticalStack addArrangedSubview:currentRow];
    
    // Add tag chips (align Android: each is layout_detail_tag with indicator + text + remove)
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *tagInfo in resolvedTags) {
        SeafTagChipView *chip = [[SeafTagChipView alloc] init];
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        
        if (editable) {
            NSString *tagId = tagInfo[@"id"];
            [chip configureWithName:tagInfo[@"name"] color:tagInfo[@"color"] showRemove:YES removeHandler:^{
                // Remove this tag (align Android: ltr remove click → remove from FlexboxLayout)
                [weakSelf removeTagWithId:tagId forKey:key];
            }];
        } else {
            [chip configureWithName:tagInfo[@"name"] color:tagInfo[@"color"]];
        }
        
        [currentRow addArrangedSubview:chip];
    }
    
    // Add ➕ button for editable mode (align Android: icon_plus_sign at end of FlexboxLayout)
    if (editable) {
        UIButton *addButton = [UIButton buttonWithType:UIButtonTypeSystem];
        addButton.translatesAutoresizingMaskIntoConstraints = NO;
        // Smaller icon (10pt) with same tap area (24x24)
        UIImageSymbolConfiguration *smallConfig = [UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightMedium];
        UIImage *plusImg = [[UIImage systemImageNamed:@"plus"] imageByApplyingSymbolConfiguration:smallConfig];
        [addButton setImage:plusImg forState:UIControlStateNormal];
        addButton.tintColor = [UIColor colorWithRed:0x99/255.0 green:0x99/255.0 blue:0x99/255.0 alpha:1.0]; // fancy_gray
        [addButton.widthAnchor constraintEqualToConstant:24].active = YES;
        [addButton.heightAnchor constraintEqualToConstant:24].active = YES;
        [addButton addTarget:self action:@selector(onTagAddTapped:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(addButton, "metadataKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        // Extra spacing before the plus button (12pt vs 6pt between chips)
        if (currentRow.arrangedSubviews.count > 0) {
            [currentRow setCustomSpacing:12 afterView:currentRow.arrangedSubviews.lastObject];
        }
        [currentRow addArrangedSubview:addButton];
        
        // Also make the whole wrapper tappable (align Android: flexboxContainer.setOnClickListener)
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTagAddTapped:)];
        wrapper.userInteractionEnabled = YES;
        [wrapper addGestureRecognizer:tap];
        objc_setAssociatedObject(wrapper, "metadataKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    
    [wrapper.heightAnchor constraintGreaterThanOrEqualToConstant:22].active = YES;
    return wrapper;
}

/// Remove a tag by ID and rebuild UI (align Android: remove view from FlexboxLayout)
- (void)removeTagWithId:(NSString *)tagId forKey:(NSString *)key {
    NSMutableDictionary *metaMut = self.recordMetaDataMap[key];
    NSArray *currentValue = [metaMut[@"value"] isKindOfClass:[NSArray class]] ? metaMut[@"value"] : @[];
    
    // Filter out the removed tag
    NSMutableArray *updatedTags = [NSMutableArray array];
    for (NSDictionary *linked in currentValue) {
        NSString *linkedId = linked[@"row_id"] ?: linked[@"_id"] ?: @"";
        if (![linkedId isEqualToString:tagId]) {
            [updatedTags addObject:linked];
        }
    }
    metaMut[@"value"] = updatedTags;
    
    // Also build contentMap entry as tag model list
    NSMutableArray *tagModels = [NSMutableArray array];
    for (NSDictionary *linked in updatedTags) {
        NSString *linkedId = linked[@"row_id"] ?: linked[@"_id"] ?: @"";
        for (NSDictionary *t in self.tagList) {
            if ([t[@"_id"] isEqualToString:linkedId]) {
                [tagModels addObject:@{
                    @"id": t[@"_id"] ?: @"",
                    @"name": t[@"_tag_name"] ?: @"",
                    @"color": t[@"_tag_color"] ?: @""
                }];
                break;
            }
        }
    }
    self.contentMap[key] = tagModels;
    
    [self rebuildFieldUIForKey:key];
}

/// Handle ➕ button or wrapper tap to open tag selector
- (void)onTagAddTapped:(id)sender {
    NSString *key = nil;
    if ([sender isKindOfClass:[UIButton class]]) {
        key = objc_getAssociatedObject(sender, "metadataKey");
    } else if ([sender isKindOfClass:[UITapGestureRecognizer class]]) {
        key = objc_getAssociatedObject(((UITapGestureRecognizer *)sender).view, "metadataKey");
    }
    if (!key) return;
    [self presentTagSelectorForKey:key];
}

/// Present custom tag selector bottom sheet (align Android: TagSelectorFragment)
- (void)presentTagSelectorForKey:(NSString *)key {
    // Get current selected tags
    NSMutableDictionary *metaMut = self.recordMetaDataMap[key];
    NSArray *currentLinkedTags = [metaMut[@"value"] isKindOfClass:[NSArray class]] ? metaMut[@"value"] : @[];
    
    NSMutableArray *selectedTags = [NSMutableArray array];
    for (NSDictionary *linked in currentLinkedTags) {
        NSString *tagId = linked[@"row_id"] ?: linked[@"_id"] ?: @"";
        for (NSDictionary *t in self.tagList) {
            if ([t[@"_id"] isEqualToString:tagId]) {
                [selectedTags addObject:@{
                    @"id": t[@"_id"] ?: @"",
                    @"name": t[@"_tag_name"] ?: @"",
                    @"color": t[@"_tag_color"] ?: @""
                }];
                break;
            }
        }
    }
    
    __weak typeof(self) weakSelf = self;
    SeafTagSelectorViewController *selector = [[SeafTagSelectorViewController alloc]
        initWithKey:key
            allTags:self.tagList
       selectedTags:selectedTags
         completion:^(NSString *returnedKey, NSArray<NSDictionary *> *newSelectedTags) {
            // Update contentMap (align Android: onTagSelectedLiveData → contentMap.put)
            weakSelf.contentMap[returnedKey] = newSelectedTags;
            
            // Update metadata value to reflect new selection for UI rebuild
            NSMutableDictionary *meta = weakSelf.recordMetaDataMap[returnedKey];
            if (meta) {
                // Convert back to linked tag format
                NSMutableArray *linkedTags = [NSMutableArray array];
                for (NSDictionary *tag in newSelectedTags) {
                    [linkedTags addObject:@{ @"row_id": tag[@"id"] ?: @"", @"_id": tag[@"id"] ?: @"" }];
                }
                meta[@"value"] = linkedTags;
            }
            
            [weakSelf rebuildFieldUIForKey:returnedKey];
        }];
    
    selector.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:selector animated:YES completion:nil];
}

#pragma mark - Geolocation (readonly, align Android buildEditableGeoLocation)

/// Align Android GeoLocationModel.getText() priority:
/// 1. address (from _location_translated)
/// 2. country + province + city + district + street
/// 3. lng, lat (Android order: lng first)
- (NSString *)geolocationDisplayString:(id)value {
    if (![value isKindOfClass:[NSDictionary class]]) return @"";
    NSDictionary *geo = (NSDictionary *)value;
    
    // Helper: safely coerce to string
    NSString *(^safeStr)(id) = ^NSString *(id v) {
        if ([v isKindOfClass:[NSString class]]) return (NSString *)v;
        if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
        return @"";
    };
    
    // Priority 1: address (from _location_translated merge)
    NSString *address = safeStr(geo[@"address"]);
    if (address.length > 0) return address;
    
    // Priority 2: concat country + province + city + district + street
    NSString *country = safeStr(geo[@"country"]);
    if (country.length == 0) country = safeStr(geo[@"country_region"]);
    if (country.length == 0) country = safeStr(geo[@"countryRegion"]);
    NSString *province = safeStr(geo[@"province"]);
    NSString *city = safeStr(geo[@"city"]);
    NSString *district = safeStr(geo[@"district"]);
    NSString *street = safeStr(geo[@"street"]);
    if (street.length == 0) street = safeStr(geo[@"detail"]);
    
    NSMutableString *concat = [NSMutableString string];
    if (country.length) [concat appendString:country];
    if (province.length) [concat appendString:province];
    if (city.length) [concat appendString:city];
    if (district.length) [concat appendString:district];
    if (street.length) [concat appendString:street];
    if (concat.length > 0) return [concat copy];
    
    // Priority 3: coordinates in lng, lat order (align Android GeoLocationModel.getLngLat)
    NSString *lat = safeStr(geo[@"lat"]);
    NSString *lng = safeStr(geo[@"lng"]);
    if (lng.length > 0 && lat.length > 0 && ![lat isEqualToString:@"0"] && ![lng isEqualToString:@"0"]) {
        return [NSString stringWithFormat:@"%@, %@", lng, lat];
    }
    return @"";
}

#pragma mark - Readonly text

- (UIView *)buildReadonlyTextForValue:(NSString *)text {
    // Wrap label in a container with non-editable cell style (align Android: shape_task_view_no_editable)
    UIView *wrapper = [[UIView alloc] init];
    applyNonEditableCellStyle(wrapper);
    
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text.length > 0 ? text : @"—";
    label.font = [UIFont systemFontOfSize:16]; // align Android: 16sp
    label.textColor = [UIColor secondaryLabelColor];
    label.numberOfLines = 0;
    
    [wrapper addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:wrapper.topAnchor constant:8],
        [label.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:16],
        [label.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor constant:-16],
        [label.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor constant:-8],
    ]];
    [wrapper.heightAnchor constraintGreaterThanOrEqualToConstant:40].active = YES;
    return wrapper;
}

#pragma mark - rebuildFieldUIForKey (align Android updateConfigMapMetadata → parseViewByType)

/// Rebuild the content view for a field by removing old and creating new (align Android updateConfigMapMetadata)
- (void)rebuildFieldUIForKey:(NSString *)key {
    NSMutableDictionary *metaMut = self.recordMetaDataMap[key];
    if (!metaMut) return;
    
    // Find the section container for this key
    for (UIView *section in self.stackView.arrangedSubviews) {
        NSInteger tagVal = section.tag;
        if (tagVal < kContainerTagBase) continue;
        
        NSInteger idx = tagVal - kContainerTagBase;
        if (idx >= (NSInteger)self.orderedMetadataList.count) continue;
        NSDictionary *meta = self.orderedMetadataList[idx];
        if (![meta[@"key"] isEqualToString:key]) continue;
        
        // Found the section — remove old content view and rebuild
        UIView *oldContent = [section viewWithTag:kContentViewTag];
        UIView *titleLabel = nil;
        for (UIView *sub in section.subviews) {
            if (sub != oldContent) { titleLabel = sub; break; }
        }
        
        if (oldContent) {
            [oldContent removeFromSuperview];
        }
        
        NSString *rawType = metaMut[@"type"] ?: @"text";
        NSString *type = normalizeType(rawType, key);
        BOOL editable = YES;
        NSNumber *editableNum = supportedFieldMap()[key];
        if (editableNum) editable = [editableNum boolValue];
        
        UIView *newContent = [self buildContentViewForType:type key:key metadata:metaMut editable:editable];
        newContent.translatesAutoresizingMaskIntoConstraints = NO;
        newContent.tag = kContentViewTag;
        [section addSubview:newContent];
        
        if (titleLabel) {
            [NSLayoutConstraint activateConstraints:@[
                [newContent.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6],
                [newContent.leadingAnchor constraintEqualToAnchor:section.leadingAnchor constant:16],
                [newContent.trailingAnchor constraintEqualToAnchor:section.trailingAnchor constant:-16],
                [newContent.bottomAnchor constraintEqualToAnchor:section.bottomAnchor constant:-4],
            ]];
        }
        
        break;
    }
}

/// Simple text-based update (used for date picker etc. where only the display label changes)
- (void)updateFieldUIForKey:(NSString *)key withValue:(id)displayValue {
    // Update the recordMetaDataMap value
    NSMutableDictionary *metaMut = self.recordMetaDataMap[key];
    if (metaMut) {
        metaMut[@"value"] = displayValue ?: [NSNull null];
    }
    // Full rebuild
    [self rebuildFieldUIForKey:key];
}

#pragma mark - Save (align Android save + parseParams + parseTagField)

- (void)onSaveTapped {
    if (self.contentMap.count == 0) {
        [SVProgressHUD showInfoWithStatus:NSLocalizedString(@"No changes", @"")];
        return;
    }
    
    if (!self.recordId || self.recordId.length == 0) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Missing record ID", @"")];
        return;
    }
    
    NSDictionary *data = [self parseParams];
    NSArray<NSString *> *tagIds = [self parseTagField];
    
    if (!data && !tagIds) {
        [SVProgressHUD showInfoWithStatus:NSLocalizedString(@"No changes", @"")];
        return;
    }
    
    [SVProgressHUD show];
    
    __weak typeof(self) weakSelf = self;
    [self.service saveProfileWithRepoId:self.repoId
                               recordId:self.recordId
                                   data:data
                                 tagIds:tagIds
                             completion:^(BOOL success, NSError *error) {
        [SVProgressHUD dismiss];
        if (success) {
            [weakSelf.contentMap removeAllObjects];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                          message:NSLocalizedString(@"Successfully saved", @"")
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            [weakSelf presentViewController:alert animated:YES completion:^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [alert dismissViewControllerAnimated:YES completion:^{
                        [weakSelf dismissViewControllerAnimated:YES completion:nil];
                    }];
                });
            }];
        } else {
            NSString *msg = error.localizedDescription ?: NSLocalizedString(@"Save failed", @"");
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @"")
                                                                          message:msg
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"") style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
        }
    }];
}

/// Build the record data dict from contentMap (align Android parseParams)
- (NSDictionary *)parseParams {
    if (self.contentMap.count == 0) return nil;
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    
    for (NSString *key in self.contentMap) {
        NSDictionary *metadataDict = self.recordMetaDataMap[key];
        if (!metadataDict) continue;
        
        NSString *type = metadataDict[@"type"] ?: @"text";
        NSString *name = metadataDict[@"name"] ?: key;
        id value = self.contentMap[key];
        
        if ([type isEqualToString:@"date"]) {
            // Format date based on configData.format
            id configRaw = metadataDict[@"data"];
            NSDictionary *configData = [configRaw isKindOfClass:[NSDictionary class]] ? configRaw : nil;
            NSString *format = [configData[@"format"] isKindOfClass:[NSString class]] ? configData[@"format"] : nil;

            // Align Android: date edits are only submitted when the column has a format config
            if (format.length > 0 && [value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
                NSDate *date = [self parseDateString:value];
                if (date) {
                    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
                    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

                    if ([format.lowercaseString containsString:@"h:mm"]) {
                        fmt.dateFormat = @"yyyy-MM-dd HH:mm";
                    } else {
                        fmt.dateFormat = @"yyyy-MM-dd";
                    }
                    result[name] = [fmt stringFromDate:date];
                }
            }
        }
        else if ([type isEqualToString:@"single-select"] || [type isEqualToString:@"single_select"]) {
            if ([value isKindOfClass:[NSDictionary class]]) {
                result[name] = value[@"name"] ?: @"";
            } else {
                result[name] = value ?: @"";
            }
        }
        else if ([type isEqualToString:@"multiple-select"] || [type isEqualToString:@"multiple_select"]) {
            if ([value isKindOfClass:[NSArray class]]) {
                NSMutableArray *names = [NSMutableArray array];
                for (id item in (NSArray *)value) {
                    if ([item isKindOfClass:[NSDictionary class]]) {
                        [names addObject:item[@"name"] ?: @""];
                    } else if ([item isKindOfClass:[NSString class]]) {
                        [names addObject:item];
                    }
                }
                result[name] = names;
            }
        }
        else if ([type isEqualToString:@"link"] && [key isEqualToString:@"_tags"]) {
            // Skip tags, handled by parseTagField
            continue;
        }
        else {
            // text, number, rate, checkbox, collaborator, etc.
            result[name] = value;
        }
    }
    
    return result.count > 0 ? result : nil;
}

/// Extract tag IDs from contentMap (align Android parseTagField)
- (NSArray<NSString *> *)parseTagField {
    id tagsValue = self.contentMap[@"_tags"];
    if (![tagsValue isKindOfClass:[NSArray class]]) return nil;
    
    NSMutableArray *tagIds = [NSMutableArray array];
    for (id item in (NSArray *)tagsValue) {
        if ([item isKindOfClass:[NSDictionary class]]) {
            NSString *tagId = item[@"id"] ?: item[@"_id"] ?: @"";
            if (tagId.length > 0) [tagIds addObject:tagId];
        }
    }
    return tagIds;
}

#pragma mark - Chip layout helper

/// Create a horizontal stack view for one row of collaborator chips
- (UIStackView *)makeChipRowStackWithSpacing:(CGFloat)spacing {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = spacing;
    row.alignment = UIStackViewAlignmentCenter;
    row.distribution = UIStackViewDistributionFill;
    return row;
}

#pragma mark - Helpers

- (NSDate *)parseDateString:(NSString *)dateStr {
    NSArray<NSDateFormatter *> *formatters = [SeafSdocProfileAssembler sharedParseDateFormatters];
    for (NSDateFormatter *fmt in formatters) {
        NSDate *d = [fmt dateFromString:dateStr];
        if (d) return d;
    }
    // Try ISO8601
    NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
    iso.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    return [iso dateFromString:dateStr];
}

/// Parse hex color string (e.g. "#FF9800" or "FF9800") to UIColor (align Android Color.parseColor)
- (UIColor *)rateColorFromHex:(NSString *)hex {
    if (![hex isKindOfClass:[NSString class]] || hex.length == 0) return nil;
    NSString *h = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (h.length < 6) return nil;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:h] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb>>16)&0xFF)/255.0
                           green:((rgb>>8)&0xFF)/255.0
                            blue:(rgb&0xFF)/255.0
                           alpha:1.0];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
    NSString *key = objc_getAssociatedObject(textView, "metadataKey");
    if (key) {
        self.contentMap[key] = textView.text ?: @"";
    }
}

#pragma mark - Keyboard avoidance (align Android adaptInputMethod + view_placeholder)

- (void)keyboardWillChangeFrame:(NSNotification *)notification {
    CGRect kbFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:kbFrame fromView:nil];
    CGFloat overlap = CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(converted);
    CGFloat bottomInset = MAX(0, overlap);
    
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    NSUInteger curve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue];
    
    [UIView animateWithDuration:duration delay:0 options:(curve << 16) animations:^{
        self.scrollView.contentInset = UIEdgeInsetsMake(0, 0, bottomInset, 0);
        self.scrollView.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, bottomInset, 0);
    } completion:nil];
    
    // Auto-scroll to make the active responder visible
    UIView *firstResponder = [self findFirstResponderIn:self.scrollView];
    if (firstResponder && bottomInset > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CGRect rect = [firstResponder convertRect:firstResponder.bounds toView:self.scrollView];
            rect = CGRectInset(rect, 0, -20); // add padding
            [self.scrollView scrollRectToVisible:rect animated:YES];
        });
    }
}

- (UIView *)findFirstResponderIn:(UIView *)view {
    if ([view isFirstResponder]) return view;
    for (UIView *sub in view.subviews) {
        UIView *found = [self findFirstResponderIn:sub];
        if (found) return found;
    }
    return nil;
}

@end
