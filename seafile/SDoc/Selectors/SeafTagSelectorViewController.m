//  SeafTagSelectorViewController.m
//  Custom tag multi-select bottom sheet, aligned with Android TagSelectorFragment.
//  Uses UITableView with chip-style tag cells and selection checkmarks.

#import "SeafTagSelectorViewController.h"
#import "../Chips/SeafTagChipView.h"

#pragma mark - Tag Selector Cell

static NSString *const kTagSelectorCellId = @"TagSelectorCell";

@interface SeafTagSelectorCell : UITableViewCell
@property (nonatomic, strong) SeafTagChipView *chipView;
@property (nonatomic, strong) UIImageView *checkImageView;
@end

@implementation SeafTagSelectorCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];

        // Shared tag chip view (single source of truth for chip UI)
        _chipView = [[SeafTagChipView alloc] init];
        _chipView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_chipView];

        // Checkmark image (align Android: user_selected, pop_selected icon)
        _checkImageView = [[UIImageView alloc] init];
        _checkImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _checkImageView.contentMode = UIViewContentModeScaleAspectFit;
        UIImage *checkImg = [UIImage systemImageNamed:@"checkmark"];
        _checkImageView.image = checkImg;
        _checkImageView.tintColor = [UIColor systemBlueColor];
        _checkImageView.hidden = YES;
        [self.contentView addSubview:_checkImageView];

        [NSLayoutConstraint activateConstraints:@[
            // Chip view: left-aligned, vertically centered
            [_chipView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_chipView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

            // Checkmark: right side
            [_checkImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_checkImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_checkImageView.widthAnchor constraintEqualToConstant:20],
            [_checkImageView.heightAnchor constraintEqualToConstant:20],

            // Chip doesn't overlap checkmark
            [_chipView.trailingAnchor constraintLessThanOrEqualToAnchor:_checkImageView.leadingAnchor constant:-8],
        ]];
    }
    return self;
}

- (void)configureWithName:(NSString *)name color:(NSString *)colorHex selected:(BOOL)selected
{
    [self.chipView configureWithName:name color:colorHex];
    self.checkImageView.hidden = !selected;
}

@end

#pragma mark - Tag Selector View Controller

@interface SeafTagSelectorViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *columnKey;
@property (nonatomic, strong) NSArray<NSDictionary *> *allTags;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedIdSet;
@property (nonatomic, copy) SeafTagSelectorCompletion completion;
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation SeafTagSelectorViewController

- (instancetype)initWithKey:(NSString *)key
                    allTags:(NSArray<NSDictionary *> *)allTags
               selectedTags:(NSArray<NSDictionary *> *)selectedTags
                 completion:(SeafTagSelectorCompletion)completion
{
    if (self = [super init]) {
        _columnKey = key;
        _allTags = allTags ?: @[];
        _completion = completion;

        // Build selected ID set from initial selection
        _selectedIdSet = [NSMutableSet set];
        for (NSDictionary *tag in selectedTags) {
            NSString *tagId = tag[@"id"] ?: tag[@"_id"] ?: @"";
            if (tagId.length > 0) [_selectedIdSet addObject:tagId];
        }
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // Configure sheet presentation (align Android: BottomSheetDialogFragment)
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

    // Top toolbar (align Android: ToolbarActionbarForSelectorWithDragBinding — Cancel / Done)
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
    titleLabel.text = NSLocalizedString(@"Tags", @"tag selector title");
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbar addSubview:titleLabel];



    // Table view
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 0);
    _tableView.backgroundColor = [UIColor systemBackgroundColor];
    [_tableView registerClass:[SeafTagSelectorCell class] forCellReuseIdentifier:kTagSelectorCellId];
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        // Toolbar
        [toolbar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],
        [toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:44],

        [cancelBtn.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor constant:16],
        [cancelBtn.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [doneBtn.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor constant:-16],
        [doneBtn.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [titleLabel.centerXAnchor constraintEqualToAnchor:toolbar.centerXAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        // Table
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
    // Build selected tags list
    NSMutableArray<NSDictionary *> *selectedTags = [NSMutableArray array];
    for (NSDictionary *tag in self.allTags) {
        NSString *tagId = tag[@"_id"] ?: @"";
        if ([self.selectedIdSet containsObject:tagId]) {
            [selectedTags addObject:@{
                @"id": tagId,
                @"name": tag[@"_tag_name"] ?: @"",
                @"color": tag[@"_tag_color"] ?: @""
            }];
        }
    }

    if (self.completion) {
        self.completion(self.columnKey, selectedTags);
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.allTags.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafTagSelectorCell *cell = [tableView dequeueReusableCellWithIdentifier:kTagSelectorCellId forIndexPath:indexPath];
    NSDictionary *tag = self.allTags[indexPath.row];
    NSString *tagId = tag[@"_id"] ?: @"";
    NSString *name = tag[@"_tag_name"] ?: @"";
    NSString *color = tag[@"_tag_color"] ?: @"";
    BOOL selected = [self.selectedIdSet containsObject:tagId];
    [cell configureWithName:name color:color selected:selected];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Toggle selection (align Android: adapter.getItems().get(i).isSelected = !isSelected)
    NSDictionary *tag = self.allTags[indexPath.row];
    NSString *tagId = tag[@"_id"] ?: @"";
    if (tagId.length == 0) return;

    if ([self.selectedIdSet containsObject:tagId]) {
        [self.selectedIdSet removeObject:tagId];
    } else {
        [self.selectedIdSet addObject:tagId];
    }

    // Refresh just this row (align Android: notifyItemChanged(i))
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 44;
}

@end
