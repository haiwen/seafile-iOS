//
//  SeafShareRecentViewController.m
//  SeafShare
//
//  Recently used directories for share extension.
//  Reads shared history from SeafRecentDirsStore (App Group).
//  UI uses SeafShareDestCell with checkbox single-select.
//

#import "SeafShareRecentViewController.h"
#import "SeafShareDestCell.h"
#import "SeafConnection.h"
#import "SeafDir.h"
#import "SeafRecentDirsStore.h"
#import "SeafDateFormatter.h"
#import "SeafTheme.h"
#import "Constants.h"
#import "Utils.h"

static NSString *const kRecentCellId = @"SeafShareRecentDestCell";
static const NSInteger kMaxRecentPaths = 20;

@interface SeafShareRecentViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) SeafConnection *connection;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *recentItems;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, strong) UILabel *emptyLabel;

@end

@implementation SeafShareRecentViewController

- (instancetype)initWithConnection:(SeafConnection *)connection {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _connection = connection;
        _selectedIndex = -1;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    // TableView *is* the card (inset by SEAF_CARD_HORIZONTAL_PADDING like Libraries'
    // SeafCell.cellBackgroundView). Separator / margins are card-relative, so subtract
    // that padding from the cell-edge metrics used by Libraries.
    self.tableView.separatorInset = UIEdgeInsetsMake(0,
                                                     SEAF_SEPARATOR_LEFT_INSET - SEAF_CARD_HORIZONTAL_PADDING,
                                                     0,
                                                     SEAF_SEPARATOR_RIGHT_INSET - SEAF_CARD_HORIZONTAL_PADDING);
    self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
    self.tableView.layoutMargins = UIEdgeInsetsMake(0,
                                                    15.0 - SEAF_CARD_HORIZONTAL_PADDING,
                                                    0,
                                                    15.0 - SEAF_CARD_HORIZONTAL_PADDING);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    // Match SeafCell.xib / Starred estimated height.
    self.tableView.estimatedRowHeight = 68;

    self.tableView.backgroundColor = [SeafTheme primarySurface];
    self.tableView.layer.cornerRadius = 16.0;
    self.tableView.layer.masksToBounds = YES;

    [self.tableView registerClass:[SeafShareDestCell class] forCellReuseIdentifier:kRecentCellId];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:SEAF_CARD_HORIZONTAL_PADDING],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-SEAF_CARD_HORIZONTAL_PADDING],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0;
    }

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = NSLocalizedString(@"No recent records", @"Seafile");
    self.emptyLabel.textColor = [SeafTheme secondaryText];
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    [self loadRecentItems];
}

#pragma mark - Load Data

- (void)loadRecentItems {
    self.recentItems = [[SeafRecentDirsStore shared] recentDirectoriesForConnection:self.connection maxCount:kMaxRecentPaths];
    [self.tableView reloadData];
    // Keep the rounded card chrome visible when empty (same as Starred); only toggle the label.
    BOOL isEmpty = (self.recentItems.count == 0);
    self.emptyLabel.hidden = !isEmpty;
    if (isEmpty) {
        [self.view bringSubviewToFront:self.emptyLabel];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.recentItems.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return nil;
}

/// Subtitle format aligned with Starred:
/// - repo root (`path == "/"`) → time only (same as SeafStarredRepo)
/// - folder → `repoName · time` (same as SeafStarredDir)
- (NSString *)subtitleForRecentItem:(NSDictionary *)item {
    NSString *repoName = [item[@"repoName"] isKindOfClass:[NSString class]] ? item[@"repoName"] : @"";
    NSString *path = [item[@"path"] isKindOfClass:[NSString class]] ? item[@"path"] : @"/";
    NSNumber *timeNum = [item[@"time"] isKindOfClass:[NSNumber class]] ? item[@"time"] : nil;
    NSString *timeStr = nil;
    if (timeNum) {
        timeStr = [SeafDateFormatter stringFromLongLong:(long long)timeNum.doubleValue];
    }

    BOOL isRepoRoot = [path isEqualToString:@"/"] || path.length <= 1;
    if (isRepoRoot) {
        return timeStr.length > 0 ? timeStr : @"";
    }
    if (repoName.length > 0 && timeStr.length > 0) {
        return [NSString stringWithFormat:@"%@ · %@", repoName, timeStr];
    }
    if (repoName.length > 0) {
        return repoName;
    }
    return timeStr ?: @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SeafShareDestCell *cell = [tableView dequeueReusableCellWithIdentifier:kRecentCellId forIndexPath:indexPath];
    if (indexPath.row >= (NSInteger)self.recentItems.count) return cell;

    NSDictionary *item = self.recentItems[indexPath.row];
    NSString *dirName = item[@"dirName"] ?: @"";
    NSString *path = item[@"path"] ?: @"/";

    cell.titleLabel.text = dirName.length > 0 ? dirName : path.lastPathComponent;
    cell.subtitleLabel.text = [self subtitleForRecentItem:item];
    cell.subtitleLabel.textColor = Utils.cellDetailTextTextColor;

    // Resolve icon the same way as the main-app destination recent list / Starred tab.
    SeafDir *dir = [[SeafRecentDirsStore shared] directoryFromRecord:item connection:self.connection];
    cell.iconView.image = dir.icon;

    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];

    cell.checkboxView.hidden = NO;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    BOOL isSelected = (indexPath.row == self.selectedIndex);
    [cell updateCheckboxImageForSelected:isSelected];

    // Keep separator on every row, including the last (rounded card still clips at bottom).
    cell.separatorInset = UIEdgeInsetsMake(0,
                                           SEAF_SEPARATOR_LEFT_INSET - SEAF_CARD_HORIZONTAL_PADDING,
                                           0,
                                           SEAF_SEPARATOR_RIGHT_INSET - SEAF_CARD_HORIZONTAL_PADDING);

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.recentItems.count) return;

    if (self.selectedIndex == indexPath.row) {
        self.selectedIndex = -1;
    } else {
        NSInteger previousIndex = self.selectedIndex;
        self.selectedIndex = indexPath.row;
        if (previousIndex >= 0 && previousIndex < (NSInteger)self.recentItems.count) {
            [tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:previousIndex inSection:0]]
                             withRowAnimation:UITableViewRowAnimationNone];
        }
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - Public

- (SeafDir *)selectedDirectory {
    if (self.selectedIndex < 0 || self.selectedIndex >= (NSInteger)self.recentItems.count) {
        return nil;
    }

    NSDictionary *item = self.recentItems[self.selectedIndex];
    return [[SeafRecentDirsStore shared] directoryFromRecord:item connection:self.connection];
}

@end
