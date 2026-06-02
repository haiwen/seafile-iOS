//  SeafSdocOptionSelectorViewController.m
//  Generic multi-select checkmark list presented as a bottom sheet.
//  Replaces the recursive action-sheet flow (which had no popover anchor and
//  crashed on iPad) for multiple-select and collaborator fields.

#import "SeafSdocOptionSelectorViewController.h"

static NSString *const kOptionSelectorCellId = @"OptionSelectorCell";

@interface SeafSdocOptionSelectorViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *selectorTitle;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedIdSet;
@property (nonatomic, copy) SeafSdocOptionSelectorCompletion completion;
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation SeafSdocOptionSelectorViewController

- (instancetype)initWithTitle:(NSString *)title
                        items:(NSArray<NSDictionary *> *)items
                  selectedIds:(NSArray<NSString *> *)selectedIds
                   completion:(SeafSdocOptionSelectorCompletion)completion
{
    if (self = [super init]) {
        _selectorTitle = [title copy];
        _items = items ?: @[];
        _completion = [completion copy];
        _selectedIdSet = [NSMutableSet set];
        for (NSString *itemId in selectedIds) {
            if ([itemId isKindOfClass:[NSString class]] && itemId.length > 0) {
                [_selectedIdSet addObject:itemId];
            }
        }
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
    titleLabel.text = self.selectorTitle;
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbar addSubview:titleLabel];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 0);
    _tableView.backgroundColor = [UIColor systemBackgroundColor];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kOptionSelectorCellId];
    [self.view addSubview:_tableView];

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

        [_tableView.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

#pragma mark - Actions

- (void)onCancelTapped
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onDoneTapped
{
    NSMutableArray<NSString *> *selectedIds = [NSMutableArray array];
    for (NSDictionary *item in self.items) {
        NSString *itemId = item[@"id"] ?: @"";
        if ([self.selectedIdSet containsObject:itemId]) {
            [selectedIds addObject:itemId];
        }
    }

    if (self.completion) {
        self.completion([selectedIds copy]);
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kOptionSelectorCellId forIndexPath:indexPath];
    NSDictionary *item = self.items[indexPath.row];
    cell.textLabel.text = item[@"name"] ?: @"";
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    BOOL selected = [self.selectedIdSet containsObject:item[@"id"] ?: @""];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = [UIColor systemBlueColor];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary *item = self.items[indexPath.row];
    NSString *itemId = item[@"id"] ?: @"";
    if (itemId.length == 0) return;

    if ([self.selectedIdSet containsObject:itemId]) {
        [self.selectedIdSet removeObject:itemId];
    } else {
        [self.selectedIdSet addObject:itemId];
    }

    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 44;
}

@end
