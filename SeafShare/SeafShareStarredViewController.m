//
//  SeafShareStarredViewController.m
//  SeafShare
//
//  Starred directory picker for share extension.
//  Uses SeafShareDestCell (the same extension-owned cell as the Recent tab) so the
//  trailing checkbox renders reliably inside the app extension.
//  Selection logic:
//  - is_dir && !deleted → selectable with checkbox (encrypted libraries included)
//  - others → dimmed, not selectable
//  Encrypted libraries are selectable; SeafShareDestinationViewController prompts for
//  the library password before uploading (mirrors the Libraries browse tab).
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
#import "SeafTheme.h"
#import "Constants.h"
#import "Utils.h"
#import "Debug.h"

static NSString * const kStarredCellId = @"SeafShareStarredDestCell";

@interface SeafShareStarredViewController () <UITableViewDelegate, UITableViewDataSource, SeafDentryDelegate>

@property (nonatomic, strong) SeafConnection *connection;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *loadingView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSMutableArray *starredItems;
@property (nonatomic, assign) NSInteger selectedIndex;

@end

@implementation SeafShareStarredViewController

- (instancetype)initWithConnection:(SeafConnection *)connection {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _connection = connection;
        _selectedIndex = -1;
        _starredItems = [NSMutableArray array];
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
    // Match SeafCell.xib / Recent estimated height.
    self.tableView.estimatedRowHeight = 68;

    self.tableView.backgroundColor = [SeafTheme primarySurface];
    self.tableView.layer.cornerRadius = 16.0;
    self.tableView.layer.masksToBounds = YES;

    [self.tableView registerClass:[SeafShareDestCell class] forCellReuseIdentifier:kStarredCellId];
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

    self.loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingView.hidesWhenStopped = YES;
    self.loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.loadingView];
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    // Match Recent tab empty-state style: centered label over the rounded card.
    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = NSLocalizedString(@"No starred folders", @"Seafile");
    self.emptyLabel.textColor = [SeafTheme secondaryText];
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    [self loadStarredItems];
}

#pragma mark - Empty State

- (void)updateEmptyStateWithMessage:(NSString *)message {
    BOOL isEmpty = (self.starredItems.count == 0);
    self.emptyLabel.text = message;
    self.emptyLabel.hidden = !isEmpty;
    if (isEmpty) {
        [self.view bringSubviewToFront:self.emptyLabel];
    }
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

- (BOOL)isEntrySelectable:(NSObject *)entry {
    if ([entry isKindOfClass:[SeafStarredFile class]]) {
        return NO;
    }
    if (![entry isKindOfClass:[SeafBase class]]) {
        return NO;
    }
    SeafBase *base = (SeafBase *)entry;
    // Encrypted libraries stay selectable; the password is verified in the upload flow.
    if (base.isDeleted) {
        return NO;
    }
    return YES;
}

- (void)updateCellContent:(SeafShareDestCell *)cell file:(SeafStarredFile *)sfile {
    NSString *detailText;
    UIColor *textColor;
    if (sfile.isDeleted) {
        detailText = NSLocalizedString(@"Removed", @"Seafile");
        textColor = UIColor.systemRedColor;
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
        textColor = UIColor.systemRedColor;
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.starredItems.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SeafShareDestCell *cell = [tableView dequeueReusableCellWithIdentifier:kStarredCellId forIndexPath:indexPath];
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

    BOOL selectable = [self isEntrySelectable:entry];
    // Non-selectable rows (files, and deleted dirs/files) are dimmed.
    CGFloat contentAlpha = selectable ? 1.0f : 0.4f;
    cell.iconView.alpha = contentAlpha;
    cell.titleLabel.alpha = contentAlpha;
    cell.subtitleLabel.alpha = contentAlpha;

    if (selectable) {
        cell.checkboxView.hidden = NO;
        BOOL isSelected = (indexPath.row == self.selectedIndex);
        [cell updateCheckboxImageForSelected:isSelected];
    } else {
        cell.checkboxView.hidden = YES;
        cell.checkboxView.image = nil;
    }

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
    if (![self isEntrySelectable:entry]) {
        return;
    }

    if (self.selectedIndex == indexPath.row) {
        self.selectedIndex = -1;
    } else {
        NSInteger previousIndex = self.selectedIndex;
        self.selectedIndex = indexPath.row;
        if (previousIndex >= 0 && previousIndex < (NSInteger)self.starredItems.count) {
            [tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:previousIndex inSection:0]]
                             withRowAnimation:UITableViewRowAnimationNone];
        }
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
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

#pragma mark - Public

- (SeafDir *)selectedDirectory {
    if (self.selectedIndex < 0 || self.selectedIndex >= (NSInteger)self.starredItems.count) {
        return nil;
    }

    NSObject *entry = self.starredItems[self.selectedIndex];
    if (![self isEntrySelectable:entry]) {
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

@end
