//  SeafSdocProfileSheetViewController.m

#import "SeafSdocProfileSheetViewController.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface RightAlignedCollectionViewFlowLayout : UICollectionViewFlowLayout
@end

@implementation RightAlignedCollectionViewFlowLayout
- (NSArray<__kindof UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect
{
    NSArray *attrs = [[super layoutAttributesForElementsInRect:rect] copy];
    if (!attrs || attrs.count == 0) return attrs;
    NSMutableDictionary<NSNumber *, NSMutableArray<UICollectionViewLayoutAttributes *> *> *rows = [NSMutableDictionary dictionary];
    for (UICollectionViewLayoutAttributes *a in attrs) {
        if (a.representedElementCategory != UICollectionElementCategoryCell) continue;
        NSNumber *y = @(round(a.frame.origin.y));
        if (!rows[y]) rows[y] = [NSMutableArray array];
        [rows[y] addObject:a];
    }
    CGFloat width = self.collectionView.bounds.size.width;
    [rows enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSMutableArray<UICollectionViewLayoutAttributes *> *objs, BOOL *stop) {
        [objs sortUsingComparator:^NSComparisonResult(UICollectionViewLayoutAttributes *a, UICollectionViewLayoutAttributes *b) { return a.frame.origin.x < b.frame.origin.x ? NSOrderedAscending : NSOrderedDescending; }];
        CGFloat totalWidth = 0;
        for (NSUInteger i = 0; i < objs.count; i++) {
            totalWidth += objs[i].frame.size.width;
            if (i != objs.count - 1) totalWidth += self.minimumInteritemSpacing;
        }
        CGFloat startX = width - self.sectionInset.right - totalWidth;
        CGFloat x = startX;
        for (UICollectionViewLayoutAttributes *a in objs) {
            CGRect f = a.frame; f.origin.x = x; a.frame = f; x += f.size.width + self.minimumInteritemSpacing;
        }
    }];
    return attrs;
}
@end

@interface SeafInlineChipsDataSource : NSObject <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, copy) NSString *type;
@property (nonatomic, strong) NSArray *vals;
@end

@implementation SeafInlineChipsDataSource
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView { return 1; }
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return self.vals.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.vals[indexPath.item];
    if ([self.type isEqualToString:@"collaborator"]) {
        UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"collab" forIndexPath:indexPath];
        NSString *name = item[@"user_name"] ?: @"";
        NSString *avatar = item[@"avatar"] ?: @"";
        if ([cell respondsToSelector:@selector(configureWithName:avatarURL:)]) {
            ((void (*)(id, SEL, NSString*, NSString*))objc_msgSend)(cell, @selector(configureWithName:avatarURL:), name, avatar);
        }
        cell.isAccessibilityElement = YES;
        cell.accessibilityLabel = name ?: @"";
        return cell;
    } else {
        UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"tag" forIndexPath:indexPath];
        if ([cell respondsToSelector:@selector(configureWithText:color:textColor:)]) {
            NSString *text = item[@"text"] ?: @"";
            NSString *color = item[@"color"] ?: @"";
            NSString *textColor = item[@"textColor"] ?: @"";
            // For link type (i.e., _tags), use dot style per design
            if ([self.type isEqualToString:@"link"] && [cell respondsToSelector:@selector(configureDotStyleWithText:dotColor:textColor:)]) {
                ((void (*)(id, SEL, NSString*, NSString*, NSString*))objc_msgSend)(cell, @selector(configureDotStyleWithText:dotColor:textColor:), text, color, textColor);
            } else {
                ((void (*)(id, SEL, NSString*, NSString*, NSString*))objc_msgSend)(cell, @selector(configureWithText:color:textColor:), text, color, textColor);
            }
        }
        cell.isAccessibilityElement = YES;
        cell.accessibilityLabel = item[@"text"] ?: @"";
        return cell;
    }
}
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    if ([self.type isEqualToString:@"collaborator"]) {
        NSDictionary *item = self.vals[indexPath.item];
        NSString *name = item[@"user_name"] ?: @"";
        UIFont *font = [UIFont systemFontOfSize:15];
        CGFloat nameW = ceil([name sizeWithAttributes:@{NSFontAttributeName:font}].width);
        CGFloat width = 8 + 18 + 4 + nameW + 8;
        CGFloat height = 24;
        return CGSizeMake(MAX(32, width), height);
    } else {
        NSDictionary *item = self.vals[indexPath.item];
        NSString *text = item[@"text"] ?: @"";
        UIFont *font = [UIFont systemFontOfSize:15];
        CGFloat textW = ceil([text sizeWithAttributes:@{NSFontAttributeName:font}].width);
        CGFloat baseLeft = 10.0;
        CGFloat baseRight = -10.0;
        CGFloat height = 24;
        if ([self.type isEqualToString:@"link"]) {
            // Include dot size and spacing: dot ~ 60% of height, min 14, max 18
            CGFloat d = MIN(18.0, MAX(14.0, height * 0.6));
            CGFloat spacing = 6.0;
            CGFloat width = baseLeft + d + spacing + textW + (-baseRight);
            return CGSizeMake(MAX(28, width), height);
        } else {
            CGFloat width = baseLeft + textW + (-baseRight);
            return CGSizeMake(MAX(28, width), height);
        }
    }
}
@end

// Shared type sets
static NSSet *SeafPlainTextTypes(void)
{
    static NSSet *s; static dispatch_once_t onceToken; dispatch_once(&onceToken, ^{
        s = [NSSet setWithArray:@[@"text", @"long_text", @"number", @"date", @"url", @"email", @"duration", @"geolocation"]];
    });
    return s;
}

static NSSet *SeafChipTypes(void)
{
    static NSSet *s; static dispatch_once_t onceToken; dispatch_once(&onceToken, ^{
        s = [NSSet setWithArray:@[@"collaborator", @"single_select", @"multiple_select", @"link"]];
    });
    return s;
}

@interface SeafSdocProfileSheetViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, assign) CGFloat contentHeight;
@property (nonatomic, assign) CGFloat baseMaxHeight; // snapshot of container height for detent cap
@property (nonatomic, assign) CGFloat lastDesiredDetent; // last desired height to avoid thrash
@property (nonatomic, strong) NSMutableArray<UICollectionView *> *chipCollections;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *chipHeightConstraints;
@property (nonatomic, strong) NSMutableArray *chipDataSources; // strong retain data sources/delegates
// < iOS 15 bottom-panel simulation
@property (nonatomic, strong) UIView *panelView;
@property (nonatomic, strong) NSLayoutConstraint *panelHeightConstraint;
@end

@implementation SeafSdocProfileSheetViewController

- (instancetype)initWithRows:(NSArray<NSDictionary *> *)rows
{
    if (self = [super init]) {
        _rows = rows ?: @[];
        self.modalPresentationStyle = UIModalPresentationPageSheet;
        _chipCollections = [NSMutableArray array];
        _chipHeightConstraints = [NSMutableArray array];
        _chipDataSources = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if (@available(iOS 15.0, *)) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        // Dim background and host a bottom panel
        self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    }

    UIView *host = self.view;
    if (@available(iOS 15.0, *)) {
        // keep host as self.view
    } else {
        UIView *panel = [UIView new];
        panel.translatesAutoresizingMaskIntoConstraints = NO;
        panel.backgroundColor = [UIColor systemBackgroundColor];
        panel.layer.cornerRadius = 12.0;
        panel.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        panel.clipsToBounds = YES;
        [self.view addSubview:panel];
        self.panelView = panel;

        UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [panel.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
        ]];
        self.panelHeightConstraint = [panel.heightAnchor constraintEqualToConstant:280.0];
        self.panelHeightConstraint.active = YES;

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onBackgroundTapped)];
        tap.delegate = self;
        [self.view addGestureRecognizer:tap];

        host = panel;
    }

    _scrollView = [UIScrollView new];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:_scrollView];

    _stack = [UIStackView new];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 14;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:_stack];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:host.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor],
        [_stack.leadingAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.leadingAnchor constant:20],
        [_stack.trailingAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.trailingAnchor constant:-20],
        // Critical: keep content equal-width to scrollView to get accurate contentSize
        [_stack.widthAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.widthAnchor constant:-40]
    ]];

    // Top spacer to leave blank area between sheet top and content
    UIView *topSpacer = [UIView new];
    topSpacer.translatesAutoresizingMaskIntoConstraints = NO;
    [topSpacer.heightAnchor constraintEqualToConstant:40.0].active = YES;
    [_stack addArrangedSubview:topSpacer];

    [self renderRows];

    // Pre-compute content height for dynamic sheet detent selection
    [self.view layoutIfNeeded];
    // Measure against a fixed width equal to frameLayoutGuide width minus horizontal padding
    CGFloat targetWidth = _scrollView.bounds.size.width - 32.0;
    if (targetWidth <= 0) targetWidth = self.view.bounds.size.width - 32.0;
    CGSize fit = [_stack systemLayoutSizeFittingSize:CGSizeMake(targetWidth, UILayoutFittingCompressedSize.height)];
    self.contentHeight = fit.height;
    
    self.baseMaxHeight = self.view.bounds.size.height;

    if (!@available(iOS 15.0, *)) {
        CGFloat maxH = self.view.bounds.size.height * 0.9;
        CGFloat desired = MIN(MAX(120.0, self.contentHeight), maxH);
        self.panelHeightConstraint.constant = desired;
        [self.view layoutIfNeeded];
        
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        if (sheet) {
        sheet.prefersGrabberVisible = YES;
        sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
        [self configureSheetDetentsForSheet:sheet initial:YES];
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
}

- (void)configureSheetDetentsForSheet:(UISheetPresentationController *)sheet initial:(BOOL)initial API_AVAILABLE(ios(15.0))
{
    // Use a stable base height, not current bounds (which changes with sheet drag)
    CGFloat maxH = (self.baseMaxHeight > 0 ? self.baseMaxHeight : self.view.bounds.size.height);
    // Clamp desired height between 120 and 90% of screen
    CGFloat desired = MIN(MAX(120.0, self.contentHeight), maxH * 0.9);
    // Avoid thrashing: only update detents if delta is significant
    if (fabs(desired - self.lastDesiredDetent) < 2.0 && !initial) {
        return;
    }
    self.lastDesiredDetent = desired;
    if (@available(iOS 16.0, *)) {
        UISheetPresentationControllerDetent *contentDetent = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"content" resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext>  _Nonnull context) {
            CGFloat limit = context.maximumDetentValue;
            CGFloat ret = MIN(desired, limit);
            return ret;
        }];
        sheet.detents = @[ contentDetent, UISheetPresentationControllerDetent.largeDetent ];
        if (initial) {
            sheet.selectedDetentIdentifier = @"content";
            sheet.largestUndimmedDetentIdentifier = nil; // always dim background
            
        }
    } else {
        // iOS 15: choose medium or large depending on desired height threshold (~50%)
        CGFloat threshold = maxH * 0.5;
        sheet.detents = @[ UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent ];
        if (initial) {
            if (desired <= threshold) {
                sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
                sheet.largestUndimmedDetentIdentifier = nil; // always dim background
                
            } else {
                sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
                sheet.largestUndimmedDetentIdentifier = nil; // always dim background
                
            }
        }
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    // Re-compute content height when layout changes (rotation, Dynamic Type)
    CGFloat targetWidth2 = _scrollView.bounds.size.width - 32.0;
    if (targetWidth2 <= 0) targetWidth2 = self.view.bounds.size.width - 32.0;
    // Update chips heights to their content size before measuring
    for (NSUInteger i = 0; i < self.chipCollections.count; i++) {
        UICollectionView *cv = self.chipCollections[i];
        NSLayoutConstraint *hc = (i < self.chipHeightConstraints.count ? self.chipHeightConstraints[i] : nil);
        if (!cv || !hc) continue;
        [cv.collectionViewLayout invalidateLayout];
        CGSize cs = cv.collectionViewLayout.collectionViewContentSize;
        hc.constant = MAX(24, cs.height);
    }
    CGSize fit = [_stack systemLayoutSizeFittingSize:CGSizeMake(targetWidth2, UILayoutFittingCompressedSize.height)];
    CGFloat newH = fit.height;
    // Only react to growth to avoid interfering with user's drag (prevent shrink feedback)
    if (newH - self.contentHeight > 1.0) {
        
        self.contentHeight = newH;
        if (@available(iOS 15.0, *)) {
            UISheetPresentationController *sheet = self.sheetPresentationController;
            if (sheet) {
                [self configureSheetDetentsForSheet:sheet initial:NO];
            }
        } else {
            CGFloat maxH = self.view.bounds.size.height * 0.9;
            CGFloat desired = MIN(MAX(120.0, self.contentHeight), maxH);
            self.panelHeightConstraint.constant = desired;
            [self.view layoutIfNeeded];
            
        }
    }
}

// KVO removed: selectedDetentIdentifier observation no longer used

- (void)dealloc
{
}

#pragma mark - Background tap (< iOS 15)

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if (self.panelView && [touch.view isDescendantOfView:self.panelView]) {
        return NO;
    }
    return YES;
}

- (void)onBackgroundTapped
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)renderRows
{
    for (NSDictionary *row in self.rows) {
        UIView *rowView = [self buildRowView:row];
        [self.stack addArrangedSubview:rowView];
    }
}

- (UIView *)buildRowView:(NSDictionary *)row
{
    UIStackView *h = [UIStackView new];
    h.axis = UILayoutConstraintAxisHorizontal;
    h.alignment = UIStackViewAlignmentTop;
    h.spacing = 8;

    // left
    UIStackView *left = [UIStackView new];
    left.axis = UILayoutConstraintAxisHorizontal;
    left.alignment = UIStackViewAlignmentCenter;
    left.spacing = 8;
    left.translatesAutoresizingMaskIntoConstraints = NO;
    // Allow left section up to 120pt to avoid constraint conflicts on narrow screens
    NSLayoutConstraint *leftW = [left.widthAnchor constraintLessThanOrEqualToConstant:180];
    leftW.priority = UILayoutPriorityDefaultHigh; // 750
    leftW.active = YES;

    UIImage *img = [UIImage imageNamed:row[@"icon"] ?: @"text"];
    if (!img) { img = [UIImage imageNamed:@"text"]; }
    img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImageView *icon = [[UIImageView alloc] initWithImage:img];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = [UIColor secondaryLabelColor];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon.widthAnchor constraintEqualToConstant:16].active = YES;
    [icon.heightAnchor constraintEqualToConstant:16].active = YES;
    [left addArrangedSubview:icon];

    UILabel *title = [UILabel new];
    title.text = NSLocalizedString(row[@"title"] ?: @"", nil);
    title.textColor = [UIColor secondaryLabelColor];
    title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    title.numberOfLines = 0;
    title.lineBreakMode = NSLineBreakByWordWrapping;
    [left addArrangedSubview:title];

    [h addArrangedSubview:left];

    // right
    UIView *right = [self buildRightValuesForRow:row];
    [h addArrangedSubview:right];

    return h;
}

- (UIView *)buildRightValuesForRow:(NSDictionary *)row
{
    NSString *type = row[@"type"] ?: @"text";
    NSArray *values = row[@"values"] ?: @[];

    if ([self isPlainTextType:type]) {
        UIStackView *sv = [UIStackView new];
        sv.axis = UILayoutConstraintAxisVertical;
        sv.spacing = 4;
        sv.alignment = UIStackViewAlignmentTrailing;
        for (NSDictionary *v in values) {
            BOOL isEmpty = [[v objectForKey:@"isEmpty"] boolValue];
            NSString *t = v[@"text"] ?: @"";
            if (isEmpty || ([t isKindOfClass:[NSString class]] && [t isEqualToString:@"empty"])) {
                t = [self emptyDisplayText];
            }
            UILabel *lab = [self makeSecondaryLabelWithText:t titleKey:row[@"title"]];
            [sv addArrangedSubview:lab];
        }
        return sv;
    }

    if ([self isChipsType:type]) {
        
        // Special case: collaborator empty -> show localized empty text
        if ([type isEqualToString:@"collaborator"]) {
            NSDictionary *first = values.firstObject ?: @{};
            BOOL isEmpty = [[first objectForKey:@"isEmpty"] boolValue];
            NSString *t = first[@"text"];
            if (isEmpty || ([t isKindOfClass:[NSString class]] && [t isEqualToString:@"empty"])) {
                UIStackView *sv = [UIStackView new];
                sv.axis = UILayoutConstraintAxisVertical;
                sv.spacing = 4;
                sv.alignment = UIStackViewAlignmentTrailing;
                UILabel *lab = [self makeSecondaryLabelWithText:[self emptyDisplayText] titleKey:row[@"title"]];
                lab.numberOfLines = 1;
                [sv addArrangedSubview:lab];
                return sv;
            }
        }
        // Special case: single_select/multiple_select empty -> show localized empty text
        if ([type isEqualToString:@"single_select"] || [type isEqualToString:@"multiple_select"]) {
            BOOL isEmptyOnly = YES;
            for (NSDictionary *v in values) {
                BOOL vIsEmpty = [[v objectForKey:@"isEmpty"] boolValue];
                NSString *tx = v[@"text"];
                if (!(vIsEmpty || ([tx isKindOfClass:[NSString class]] && [tx isEqualToString:@"empty"]))) {
                    isEmptyOnly = NO; break;
                }
            }
            if (isEmptyOnly) {
                UIStackView *sv = [UIStackView new];
                sv.axis = UILayoutConstraintAxisVertical;
                sv.spacing = 4;
                sv.alignment = UIStackViewAlignmentTrailing;
                UILabel *lab = [self makeSecondaryLabelWithText:[self emptyDisplayText] titleKey:row[@"title"]];
                lab.numberOfLines = 1;
                [sv addArrangedSubview:lab];
                return sv;
            }
        }
        RightAlignedCollectionViewFlowLayout *layout = [RightAlignedCollectionViewFlowLayout new];
        layout.estimatedItemSize = CGSizeZero;
        layout.minimumInteritemSpacing = 12;
        layout.minimumLineSpacing = 12;
        UIView *wrapper = [UIView new];
        wrapper.translatesAutoresizingMaskIntoConstraints = NO;
        UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
        cv.scrollEnabled = NO;
        cv.backgroundColor = UIColor.clearColor;
        cv.translatesAutoresizingMaskIntoConstraints = NO;
        [wrapper addSubview:cv];
        [NSLayoutConstraint activateConstraints:@[
            [cv.topAnchor constraintEqualToAnchor:wrapper.topAnchor],
            [cv.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor],
            [cv.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor],
            [cv.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor]
        ]];
        NSLayoutConstraint *containerH = [wrapper.heightAnchor constraintGreaterThanOrEqualToConstant:24];
        containerH.priority = UILayoutPriorityRequired;
        containerH.active = YES;

        Class tagCellCls = NSClassFromString(@"SeafTagChipCell");
        Class collabCellCls = NSClassFromString(@"SeafCollaboratorChipCell");
        // Fallback to plain cells if custom chip classes are missing to avoid crashes in misconfigured builds
        if (!tagCellCls) { tagCellCls = [UICollectionViewCell class]; }
        if (!collabCellCls) { collabCellCls = [UICollectionViewCell class]; }
        [cv registerClass:tagCellCls forCellWithReuseIdentifier:@"tag"]; 
        [cv registerClass:collabCellCls forCellWithReuseIdentifier:@"collab"]; 

        __block NSArray *vals = values;
        __weak typeof(cv) weakCV = cv;
        SeafInlineChipsDataSource *ds = [SeafInlineChipsDataSource new];
        ds.type = type;
        ds.vals = vals;
        [self.chipDataSources addObject:ds];
        cv.dataSource = ds;
        cv.delegate = ds;

        [cv reloadData];
        [cv.collectionViewLayout invalidateLayout];
        [cv layoutIfNeeded];
        CGSize cs0 = cv.collectionViewLayout.collectionViewContentSize;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakCV) strongCV = weakCV;
            if (!strongCV) return;
            [strongCV.collectionViewLayout invalidateLayout];
            [strongCV layoutIfNeeded];
            CGSize cs = strongCV.collectionViewLayout.collectionViewContentSize;
            CGFloat newH = MAX(24, cs.height);
            containerH.constant = newH;
        });

        [self.chipCollections addObject:cv];
        [self.chipHeightConstraints addObject:containerH];
        [wrapper setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        [wrapper setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        return wrapper;
    }

    if ([type isEqualToString:@"rate"]) {
        UIStackView *stars = [UIStackView new];
        stars.axis = UILayoutConstraintAxisHorizontal;
        stars.spacing = 4;
        NSDictionary *v = values.firstObject ?: @{};
        NSInteger selected = [v[@"ratingSelected"] integerValue];
        NSInteger max = [v[@"ratingMax"] integerValue] ?: 5;
        NSString *ratingColorHex = v[@"ratingColor"] ?: @"";
        UIColor *selColor = [self colorFromHex:ratingColorHex] ?: [self colorFromHex:@"#6E6E6E"];
        for (NSInteger i = 0; i < max; i++) {
            UIImage *img = [[UIImage imageNamed:@"ic_star_32"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            UIImageView *star = [[UIImageView alloc] initWithImage:img];
            star.contentMode = UIViewContentModeScaleAspectFit;
            UIColor *unSel = [self colorFromHex:@"#e9e9e9"]; // Android R.color.light_gray
            star.tintColor = (i < selected) ? selColor : unSel;
            [star.widthAnchor constraintEqualToConstant:16].active = YES;
            [star.heightAnchor constraintEqualToConstant:16].active = YES;
            [stars addArrangedSubview:star];
        }
        return stars;
    }

    if ([type isEqualToString:@"checkbox"]) {
        NSDictionary *v = values.firstObject ?: @{};
        BOOL checked = [v[@"checked"] boolValue];
        UIImage *img = nil;
        if (checked) {
            UIImage *base = [UIImage imageNamed:@"ic_checkbox_checked"];
            if (base) img = [base imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        } else {
            if (@available(iOS 13.0, *)) {
                UIImage *base = [UIImage systemImageNamed:@"square"]; // hollow square, transparent center
                if (base) img = [base imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            }
            if (!img) {
                UIImage *base = [UIImage imageNamed:@"ic_checkbox_unchecked"];
                if (base) img = [base imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            }
        }
        UIImageView *iv = [[UIImageView alloc] initWithImage:img];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        // Requirement: use the theme orange color
        iv.tintColor = BAR_COLOR_ORANGE;
        iv.backgroundColor = UIColor.clearColor;
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        [iv.widthAnchor constraintEqualToConstant:22].active = YES;
        [iv.heightAnchor constraintEqualToConstant:22].active = YES;
        iv.isAccessibilityElement = YES;
        iv.accessibilityLabel = checked ? NSLocalizedString(@"Checked", nil) : NSLocalizedString(@"Unchecked", nil);
        return iv;
    }

    // default
    UIStackView *sv = [UIStackView new];
    sv.axis = UILayoutConstraintAxisVertical;
    sv.spacing = 12;
    sv.alignment = UIStackViewAlignmentTrailing;
    for (NSDictionary *v in values) {
        NSString *t = v[@"text"] ?: @"";
        if ([t isKindOfClass:[NSString class]] && [t isEqualToString:@"empty"]) {
            t = [self emptyDisplayText];
        }
        UILabel *lab = [self makeSecondaryLabelWithText:t titleKey:row[@"title"]];
        [sv addArrangedSubview:lab];
    }
    return sv;
}


- (BOOL)isPlainTextType:(NSString *)type
{
    return [SeafPlainTextTypes() containsObject:type ?: @""];
}

- (BOOL)isChipsType:(NSString *)type
{
    return [SeafChipTypes() containsObject:type ?: @""];
}

- (UIColor *)colorFromHex:(NSString *)hex
{
    if (![hex isKindOfClass:[NSString class]] || hex.length == 0) return nil;
    NSString *h = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int rgb = 0; [[NSScanner scannerWithString:h] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb>>16)&0xFF)/255.0 green:((rgb>>8)&0xFF)/255.0 blue:(rgb&0xFF)/255.0 alpha:1];
}

- (NSString *)emptyDisplayText
{
    NSString *emptyText = NSLocalizedString(@"empty", nil);
    if (emptyText.length == 0 || [emptyText isEqualToString:@"empty"]) {
        emptyText = NSLocalizedString(@"Empty", nil);
    }
    return emptyText ?: @"";
}

- (UILabel *)makeSecondaryLabelWithText:(NSString *)text titleKey:(NSString *)titleKey
{
    UILabel *lab = [UILabel new];
    lab.text = text ?: @"";
    lab.textColor = [UIColor secondaryLabelColor];
    lab.font = [UIFont systemFontOfSize:16];
    lab.numberOfLines = 0;
    lab.textAlignment = NSTextAlignmentNatural;
    lab.isAccessibilityElement = YES;
    NSString *ttl = NSLocalizedString(titleKey ?: @"", nil);
    lab.accessibilityLabel = [NSString stringWithFormat:@"%@: %@", ttl ?: @"", text ?: @""];
    return lab;
}

@end

