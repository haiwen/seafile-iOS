//
//  SeafShareStarredViewController.m
//  SeafShare
//
//  Starred directory list for share extension.
//  Uses SeafShareDestCell (the same extension-owned cell as the Recent tab).
//  Tappable rows (library / directory, not deleted) notify the parent via
//  directoryTapHandler so the destination picker can jump to Libraries.
//  Files and deleted items are dimmed and not tappable.
//

#import "SeafShareStarredViewController.h"
#import "SeafShareDestCell.h"
#import "SeafConnection.h"
#import "SeafStarredFile.h"
#import "SeafStarredDir.h"
#import "SeafStarredRepo.h"
#import "SeafRepos.h"
#import "SeafDir.h"
#import "SeafBase.h"
#import "Constants.h"
#import "Utils.h"
#import "Debug.h"

@interface SeafShareStarredViewController () <SeafDentryDelegate>

@property (nonatomic, strong) NSMutableArray *starredItems;

@end

@implementation SeafShareStarredViewController

- (instancetype)initWithConnection:(SeafConnection *)connection {
    self = [super initWithConnection:connection];
    if (self) {
        _starredItems = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadStarredItems];
}

#pragma mark - Subclass Hooks

- (NSInteger)dataSourceCount {
    return self.starredItems.count;
}

- (BOOL)isItemSelectableAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.starredItems.count) return NO;
    return [self isEntryTappable:self.starredItems[index]];
}

- (SeafDir *)selectedDirectory {
    // Starred no longer selects an upload target; navigate to Libraries instead.
    return nil;
}

#pragma mark - Load Data

- (void)loadStarredItems {
    self.emptyLabel.hidden = YES;
    [self.loadingView startAnimating];

    __weak typeof(self) weakSelf = self;
    [self.connection getStarredFiles:^(NSHTTPURLResponse *response, id JSON) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.loadingView stopAnimating];
            [weakSelf handleData:JSON];
            [weakSelf.tableView reloadData];
            [weakSelf updateEmptyStateWithMessage:NSLocalizedString(@"No starred folders", @"Seafile")];
        });
    } failure:^(NSHTTPURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.loadingView stopAnimating];
            Warning("Failed to load starred files: %@", error);
            [weakSelf updateEmptyStateWithMessage:NSLocalizedString(@"Failed to get starred files", @"Seafile")];
        });
    }];
}

- (void)handleData:(id)JSON {
    NSMutableArray *jsonDataArray = [NSMutableArray array];
    if (![JSON isKindOfClass:[NSDictionary class]]) {
        if ([JSON isKindOfClass:[NSArray class]]) {
            JSON = @{@"starred_item_list": JSON};
        } else {
            self.starredItems = jsonDataArray;
            return;
        }
    }

    NSArray *starredItems = [JSON objectForKey:@"starred_item_list"];
    if (![starredItems isKindOfClass:[NSArray class]]) {
        self.starredItems = jsonDataArray;
        return;
    }

    NSMutableArray *starFiles = [NSMutableArray array];
    for (NSDictionary *info in starredItems) {
        NSNumber *isDirNum = [info objectForKey:@"is_dir"];
        int isDir = [isDirNum intValue];
        if (isDir != 0) {
            NSString *path = [info objectForKey:@"path"];
            if ([path isKindOfClass:[NSString class]] && [path length] > 1) {
                SeafStarredDir *starredDir = [[SeafStarredDir alloc] initWithConnection:self.connection Info:info];
                [jsonDataArray addObject:starredDir];
            } else {
                SeafStarredRepo *starredRepo = [[SeafStarredRepo alloc] initWithConnection:self.connection Info:info];
                [jsonDataArray addObject:starredRepo];
            }
        } else {
            SeafStarredFile *sfile = [[SeafStarredFile alloc] initWithConnection:self.connection Info:info];
            [starFiles addObject:sfile];
        }
    }

    [jsonDataArray addObjectsFromArray:starFiles];

    for (NSObject *item in jsonDataArray) {
        if ([item isKindOfClass:[SeafStarredFile class]]) {
            [(SeafStarredFile *)item loadCache];
        }
    }

    self.starredItems = jsonDataArray;
}

#pragma mark - Helpers

- (BOOL)isEntryTappable:(NSObject *)entry {
    if ([entry isKindOfClass:[SeafStarredFile class]]) {
        return NO;
    }
    if (![entry isKindOfClass:[SeafBase class]]) {
        return NO;
    }
    SeafBase *base = (SeafBase *)entry;
    if (base.isDeleted) {
        return NO;
    }
    return YES;
}

/// Resolve a tappable starred entry to a SeafDir for Libraries navigation.
- (SeafDir *)directoryForEntry:(NSObject *)entry {
    if (![self isEntryTappable:entry]) {
        return nil;
    }

    if ([entry isKindOfClass:[SeafStarredRepo class]]) {
        SeafStarredRepo *starredRepo = (SeafStarredRepo *)entry;
        SeafRepo *repo = [self.connection getRepo:starredRepo.repoId];
        return repo ?: (SeafDir *)starredRepo;
    }

    if ([entry isKindOfClass:[SeafStarredDir class]]) {
        return (SeafDir *)entry;
    }

    return nil;
}

- (void)updateCellContent:(SeafShareDestCell *)cell file:(SeafStarredFile *)sfile {
    NSString *detailText;
    UIColor *textColor;
    if (sfile.isDeleted) {
        detailText = NSLocalizedString(@"Removed", @"Seafile");
        if (@available(iOS 13.0, *)) {
            textColor = UIColor.systemRedColor;
        } else {
            textColor = [UIColor redColor];
        }
    } else {
        detailText = sfile.starredDetailText;
        textColor = Utils.cellDetailTextTextColor;
    }

    cell.titleLabel.text = sfile.name;
    cell.subtitleLabel.text = detailText;
    cell.subtitleLabel.textColor = textColor;
    cell.iconView.image = sfile.icon;
    sfile.delegate = self;
}

- (void)updateCellContent:(SeafShareDestCell *)cell dir:(SeafDir *)entry {
    NSString *detailText;
    UIColor *textColor;
    if (entry.isDeleted) {
        detailText = NSLocalizedString(@"Removed", @"Seafile");
        if (@available(iOS 13.0, *)) {
            textColor = UIColor.systemRedColor;
        } else {
            textColor = [UIColor redColor];
        }
    } else {
        detailText = [entry detailText];
        textColor = Utils.cellDetailTextTextColor;
    }

    cell.titleLabel.text = entry.name;
    cell.subtitleLabel.text = detailText;
    cell.subtitleLabel.textColor = textColor;
    cell.iconView.image = entry.icon;
}

- (SeafShareDestCell *)cellForEntry:(NSObject *)entry {
    NSUInteger index = [self.starredItems indexOfObject:entry];
    if (index == NSNotFound) {
        return nil;
    }
    @try {
        NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
        return (SeafShareDestCell *)[self.tableView cellForRowAtIndexPath:path];
    } @catch (NSException *exception) {
        return nil;
    }
}

#pragma mark - UITableViewDataSource

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SeafShareDestCell *cell = [tableView dequeueReusableCellWithIdentifier:kShareDestCellId forIndexPath:indexPath];
    if (indexPath.row >= (NSInteger)self.starredItems.count) {
        return cell;
    }

    NSObject *entry = self.starredItems[indexPath.row];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];

    if ([entry isKindOfClass:[SeafStarredFile class]]) {
        [self updateCellContent:cell file:(SeafStarredFile *)entry];
    } else {
        [self updateCellContent:cell dir:(SeafDir *)entry];
    }

    BOOL tappable = [self isEntryTappable:entry];
    // Non-tappable rows (files, and deleted dirs/files) are dimmed.
    CGFloat contentAlpha = tappable ? 1.0f : 0.4f;
    cell.iconView.alpha = contentAlpha;
    cell.titleLabel.alpha = contentAlpha;
    cell.subtitleLabel.alpha = contentAlpha;

    // No checkbox — tapping navigates to Libraries instead of selecting.
    cell.checkboxView.hidden = YES;
    cell.checkboxView.image = nil;

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
    if (indexPath.row >= (NSInteger)self.starredItems.count) {
        return;
    }

    NSObject *entry = self.starredItems[indexPath.row];
    SeafDir *dir = [self directoryForEntry:entry];
    if (!dir) {
        return;
    }

    if (self.directoryTapHandler) {
        self.directoryTapHandler(dir);
    }
}

#pragma mark - SeafDentryDelegate

- (void)download:(SeafBase *)entry progress:(float)progress {
}

- (void)download:(SeafBase *)entry complete:(BOOL)updated {
    if (![entry isKindOfClass:[SeafStarredFile class]]) {
        return;
    }
    SeafShareDestCell *cell = [self cellForEntry:entry];
    if (!cell) {
        return;
    }
    cell.iconView.image = [(SeafStarredFile *)entry icon];
}

- (void)download:(SeafBase *)entry failed:(NSError *)error {
}

@end
