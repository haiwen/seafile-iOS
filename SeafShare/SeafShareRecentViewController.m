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
#import "Constants.h"
#import "Utils.h"

static const NSInteger kMaxRecentPaths = 20;

@interface SeafShareRecentViewController ()

@property (nonatomic, strong) NSArray<NSDictionary *> *recentItems;

@end

@implementation SeafShareRecentViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadRecentItems];
}

#pragma mark - Subclass Hooks

- (NSInteger)dataSourceCount {
    return self.recentItems.count;
}

- (SeafDir *)selectedDirectory {
    if (self.selectedIndex < 0 || self.selectedIndex >= (NSInteger)self.recentItems.count) {
        return nil;
    }

    NSDictionary *item = self.recentItems[self.selectedIndex];
    return [[SeafRecentDirsStore shared] directoryFromRecord:item connection:self.connection];
}

#pragma mark - Load Data

- (void)loadRecentItems {
    self.recentItems = [[SeafRecentDirsStore shared] recentDirectoriesForConnection:self.connection maxCount:kMaxRecentPaths];
    [self.tableView reloadData];
    [self updateEmptyStateWithMessage:NSLocalizedString(@"No recent records", @"Seafile")];
}

#pragma mark - Subtitle

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

#pragma mark - UITableViewDataSource

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SeafShareDestCell *cell = [tableView dequeueReusableCellWithIdentifier:kShareDestCellId forIndexPath:indexPath];
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

    [self handleSelectionAtIndexPath:indexPath inTableView:tableView];
}

@end
