//  SeafSDocOutlineSheetViewController.m

#import "SeafSDocOutlineSheetViewController.h"
#import "OutlineItemModel.h"

@interface SeafSDocOutlineCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) NSLayoutConstraint *leadingConstraint;
@end

@implementation SeafSDocOutlineCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        self.contentView.preservesSuperviewLayoutMargins = NO;
        self.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.numberOfLines = 2;
        if (@available(iOS 13.0, *)) {
            label.textColor = [UIColor labelColor];
        } else {
            label.textColor = [UIColor blackColor];
        }
        label.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
        [self.contentView addSubview:label];
        self.titleLabel = label;

        self.contentView.layoutMargins = UIEdgeInsetsMake(0, 0, 0, 0);
        self.leadingConstraint = [label.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16];
        [NSLayoutConstraint activateConstraints:@[
            [label.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
            self.leadingConstraint,
            [label.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [label.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:48],
        ]];

        UIView *selBg = [[UIView alloc] initWithFrame:CGRectZero];
        if (@available(iOS 13.0, *)) {
            selBg.backgroundColor = [UIColor tertiarySystemFillColor];
        } else {
            selBg.backgroundColor = [[UIColor lightGrayColor] colorWithAlphaComponent:0.2];
        }
        self.selectedBackgroundView = selBg;
    }
    return self;
}

@end

@interface SeafSDocOutlineSheetViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UIView *dimmingView;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) NSArray<OutlineItemModel *> *items;
@property (nonatomic, strong) NSArray *originArray;
@property (nonatomic, strong) NSArray<NSNumber *> *originIndexMap;
@property (nonatomic, assign) BOOL didShowAnimation;

@end

@implementation SeafSDocOutlineSheetViewController

- (CGFloat)safeBottomInset
{
    CGFloat safeBottom = 0;
    if (@available(iOS 11.0, *)) { safeBottom = self.view.safeAreaInsets.bottom; }
    return safeBottom;
}

- (instancetype)initWithItems:(NSArray<OutlineItemModel *> *)items origin:(NSArray *)origin
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _originArray = [origin isKindOfClass:[NSArray class]] ? origin : @[];
        NSDictionary *pair = [self.class buildFilteredPairFrom:items origin:_originArray];
        _items = [pair objectForKey:@"items"] ?: @[];
        _originIndexMap = [pair objectForKey:@"indexMap"] ?: @[];
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        // For iPad popover, provide a reasonable preferred size so the outline list
        // looks like a lightweight panel instead of a full-screen view.
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
            CGFloat height = MIN(480.0, screenH * 0.6);
            self.preferredContentSize = CGSizeMake(420.0, height);
        }
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if (@available(iOS 15.0, *)) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
        [self buildTableIntoView:self.view edgeInsets:UIEdgeInsetsZero];
    } else {
        [self buildCustomSheet];
    }

    // Build empty view (same style as comments page) and attach when no data
    self.emptyView = [self buildEmptyView];
    if (self.items.count == 0) {
        self.tableView.backgroundView = self.emptyView;
    } else {
        self.tableView.backgroundView = nil;
    }
}

- (void)buildTableIntoView:(UIView *)host edgeInsets:(UIEdgeInsets)insets
{
    UITableView *tv = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tv.delegate = self;
    tv.dataSource = self;
    tv.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    tv.separatorStyle = UITableViewCellSeparatorStyleNone;
    tv.estimatedRowHeight = 48;
    tv.rowHeight = UITableViewAutomaticDimension;
    if (@available(iOS 13.0, *)) {
        tv.backgroundColor = [UIColor systemBackgroundColor];
    }
    [tv registerClass:[SeafSDocOutlineCell class] forCellReuseIdentifier:@"cell"];
    [host addSubview:tv];
    self.tableView = tv;
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor constraintEqualToAnchor:host.topAnchor constant:insets.top],
        [tv.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:insets.left],
        [tv.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-insets.right],
        [tv.bottomAnchor constraintEqualToAnchor:host.bottomAnchor constant:-insets.bottom],
    ]];
    tv.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 0)];
    if (@available(iOS 15.0, *)) {
        UIView *spacer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 32)];
        spacer.backgroundColor = [UIColor clearColor];
        tv.tableHeaderView = spacer;
    }
}

- (void)buildCustomSheet
{
    self.view.backgroundColor = [UIColor clearColor];
    UIView *dimming = [[UIView alloc] initWithFrame:self.view.bounds];
    dimming.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    dimming.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    dimming.alpha = 0.0;
    [self.view addSubview:dimming];
    self.dimmingView = dimming;

    CGFloat safeBottom = [self safeBottomInset];
    CGFloat sheetHeight = MIN(480.0, self.view.bounds.size.height * 0.7);
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height, self.view.bounds.size.width, sheetHeight + safeBottom)];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    container.backgroundColor = [UIColor whiteColor];
    container.layer.cornerRadius = 12.0;
    container.layer.masksToBounds = YES;
    [self.view addSubview:container];
    self.containerView = container;

    UIView *grabber = [[UIView alloc] initWithFrame:CGRectMake((container.bounds.size.width-36)/2.0, 8, 36, 4)];
    grabber.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    grabber.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    grabber.layer.cornerRadius = 2.0;
    [container addSubview:grabber];

    UIEdgeInsets insets = UIEdgeInsetsMake(40, 0, safeBottom, 0);
    [self buildTableIntoView:container edgeInsets:insets];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapDimming)];
    [dimming addGestureRecognizer:tap];

}

- (void)onTapDimming
{
    if (!self.containerView) { [self dismissViewControllerAnimated:YES completion:nil]; return; }
    [UIView animateWithDuration:0.25 animations:^{
        self.containerView.frame = CGRectMake(0, self.view.bounds.size.height, self.view.bounds.size.width, self.containerView.bounds.size.height);
        self.dimmingView.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self dismissViewControllerAnimated:NO completion:nil];
    }];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (self.didShowAnimation) return;
    if (!self.containerView) return;
    self.didShowAnimation = YES;

    CGFloat safeBottom = [self safeBottomInset];
    CGFloat sheetHeight = MIN(480.0, self.view.bounds.size.height * 0.7);

    CGRect targetFrame = CGRectMake(0, self.view.bounds.size.height - (sheetHeight + safeBottom), self.view.bounds.size.width, sheetHeight + safeBottom);
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.containerView.frame = targetFrame;
        self.dimmingView.alpha = 1.0;
    } completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafSDocOutlineCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    OutlineItemModel *m = self.items[indexPath.row];
    NSString *title = m.text.length > 0 ? m.text : (m.type.length > 0 ? m.type : [NSString stringWithFormat:@"%ld", (long)indexPath.row+1]);
    cell.titleLabel.text = title;
    NSInteger indentLevel = 0;
    if ([m.type isEqualToString:@"header2"]) indentLevel = 1;
    else if ([m.type isEqualToString:@"header3"]) indentLevel = 2;
    CGFloat baseLeft = 16.0;
    cell.leadingConstraint.constant = baseLeft + indentLevel * 16.0;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.onSelect) {
        OutlineItemModel *m = self.items[indexPath.row];
        NSDictionary *payload = nil;
        if (indexPath.row < self.originIndexMap.count) {
            NSUInteger originIndex = self.originIndexMap[indexPath.row].unsignedIntegerValue;
            if (originIndex < self.originArray.count && [self.originArray[originIndex] isKindOfClass:[NSDictionary class]]) {
                payload = (NSDictionary *)self.originArray[originIndex];
            }
        }
        self.onSelect(payload, indexPath.row, m);
    }
    if (self.containerView) {
        [self onTapDimming];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - Helpers

+ (NSDictionary *)buildFilteredPairFrom:(NSArray<OutlineItemModel *> *)originalItems origin:(NSArray *)originArray
{
    if (originalItems.count == 0) return @{ @"items": @[], @"indexMap": @[] };
    NSMutableArray<OutlineItemModel *> *result = [NSMutableArray array];
    NSMutableArray<NSNumber *> *indexMap = [NSMutableArray array];
    NSSet<NSString *> *allowed = [NSSet setWithArray:@[@"header1", @"header2", @"header3"]];
    for (NSUInteger i = 0; i < originalItems.count; i++) {
        OutlineItemModel *m = originalItems[i];
        if (![m isKindOfClass:[OutlineItemModel class]]) continue;
        if (!m.type || ![allowed containsObject:m.type]) continue;
        if ((m.text.length == 0) && (!m.children || m.children.count == 0)) continue;
        OutlineItemModel *display = m;
        if (m.text.length == 0 && m.children.count > 0) {
            NSMutableString *composed = [NSMutableString string];
            for (OutlineItemModel *child in m.children) {
                if (![child isKindOfClass:[OutlineItemModel class]]) continue;
                if (child.text.length == 0) continue;
                NSString *trimmed = [child.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmed.length == 0) continue;
                [composed appendString:trimmed];
            }
            if (composed.length > 0) {
                OutlineItemModel *copy = [OutlineItemModel new];
                copy.type = m.type ?: @"";
                copy.text = composed.copy;
                copy.children = m.children ?: @[];
                display = copy;
            }
        }
        [result addObject:display];
        [indexMap addObject:@(i)];
    }
    return @{ @"items": result.copy, @"indexMap": indexMap.copy };
}

#pragma mark - Empty View (reuse comment page style)
- (UIView *)buildEmptyView
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
    v.layoutMargins = UIEdgeInsetsMake(64, 16, 64, 16);

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 20;
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
        [stack.centerYAnchor constraintEqualToAnchor:v.centerYAnchor constant:-16.0]
    ]];

    UIImageView *img = [[UIImageView alloc] initWithFrame:CGRectZero];
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
    // Outline empty text: use localized "No data" (Chinese locale uses an equivalent string)
    NSString *emptyText = NSLocalizedString(@"No data", nil);
    lab.text = emptyText;
    if (@available(iOS 13.0, *)) {
        lab.textColor = [UIColor labelColor];
    }
    lab.textAlignment = NSTextAlignmentCenter;
    lab.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    lab.numberOfLines = 0;

    [stack addArrangedSubview:img];
    [stack addArrangedSubview:lab];
    return v;
}

@end

