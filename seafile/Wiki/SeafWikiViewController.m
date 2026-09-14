//
//  SeafWikiViewController.m
//  seafile
//
//  Created on 2026/5/12.
//

#import "SeafWikiViewController.h"
#import "SeafWikiModel.h"
#import "SeafAppDelegate.h"
#import "SeafWikiWebViewController.h"
#import "SeafLoadingView.h"
#import "SVProgressHUD.h"
#import "Debug.h"
#import "UIViewController+Extend.h"
#import "SeafNavigationBarStyler.h"
#import "SeafTheme.h"
#import "SeafWikiCell.h"
#import "SeafWikiGroupHeader.h"

#pragma mark - SeafWikiViewController

// Grid metrics from the 260819 wiki home redline.
static const CGFloat kGridMargin  = 16.0;   // leading / trailing page margin
static const CGFloat kGridSpacing = 12.0;   // between cards, both axes

@interface SeafWikiViewController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) SeafLoadingView *loadingView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray *sections; // array of arrays; each section = @[SeafWikiGroup, SeafWikiInfo, ...]
@property (nonatomic, assign) NSUInteger loadGeneration;
@end

@implementation SeafWikiViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"Wikis", @"Seafile");
    self.view.backgroundColor = [SeafTheme primaryBackgroundColor];

    // On iPadOS 18+, the tab bar is hidden but still reserves layout space at the
    // bottom of the screen. Allow this VC's view to extend under the opaque (hidden)
    // tab bar so the content reaches the screen edge.
    if (IsIpad()) {
        self.extendedLayoutIncludesOpaqueBars = YES;
    }

    [SeafNavigationBarStyler applyStandardAppearanceToNavigationController:self.navigationController];

    _sections = @[];
    [self setupCollectionView];
    _loadingView = [SeafLoadingView loadingViewWithParentView:self.view];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.sections.count == 0) {
        [self loadData];
    }
}

- (void)setConnection:(SeafConnection *)connection {
    if (_connection != connection) {
        _connection = connection;
        _sections = @[];
        _loadGeneration++;
        // Clear the placeholder until the new connection's data has loaded.
        self.collectionView.backgroundView = nil;
        [self.collectionView reloadData];
    }
}

#pragma mark - Setup

- (void)setupCollectionView {
    UICollectionViewCompositionalLayout *layout = [self createLayout];
    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    _collectionView.backgroundColor = [SeafTheme primaryBackgroundColor];
    _collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    // Sections carry no bottom inset so the gap before the next header comes from that
    // header alone; this keeps the same breathing room after the last row.
    _collectionView.contentInset = UIEdgeInsetsMake(0, 0, kGridSpacing, 0);
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    [_collectionView registerClass:[SeafWikiCell class] forCellWithReuseIdentifier:SeafWikiCell.reuseIdentifier];
    [_collectionView registerClass:[SeafWikiGroupHeader class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:SeafWikiGroupHeader.reuseIdentifier];

    _refreshControl = [[UIRefreshControl alloc] init];
    [_refreshControl addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
    _collectionView.refreshControl = _refreshControl;

    // Centered plain-text placeholder shown when there is no wiki data.
    // As a UICollectionView backgroundView the label fills the bounds, so
    // centered text alignment positions it both horizontally and vertically.
    _emptyLabel = [[UILabel alloc] init];
    _emptyLabel.text = NSLocalizedString(@"No data", @"Seafile");
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.textColor = [SeafTheme secondaryText];
    _emptyLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    _emptyLabel.numberOfLines = 0;

    [self.view addSubview:_collectionView];
    [NSLayoutConstraint activateConstraints:@[
        [_collectionView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (UICollectionViewCompositionalLayout *)createLayout {
    UICollectionViewCompositionalLayout *layout = [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> env) {
        // The design specifies two columns on a phone; wider containers keep filling the
        // row so cards do not stretch out on iPad. The sectionProvider is re-evaluated on
        // rotation / resize automatically.
        CGFloat width = env.container.effectiveContentSize.width;
        NSInteger columns;
        if (width >= 1000) {
            columns = 5;       // iPad landscape
        } else if (width >= 750) {
            columns = 4;       // iPad portrait / large iPhone landscape
        } else if (width >= 500) {
            columns = 3;       // iPhone landscape
        } else {
            columns = 2;       // iPhone portrait (default)
        }

        // A count-based group divides the row itself, so the item's own width dimension
        // is ignored and the spacing below is what separates the cards.
        NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                          heightDimension:[NSCollectionLayoutDimension fractionalHeightDimension:1.0]];
        NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

        NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                           heightDimension:[NSCollectionLayoutDimension absoluteDimension:SeafWikiCell.cardHeight]];
        NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitem:item count:columns];
        group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:kGridSpacing];

        NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
        section.interGroupSpacing = kGridSpacing;
        // The header supplies its own top spacing, so sections do not add any of their own.
        section.contentInsets = NSDirectionalEdgeInsetsMake(0, kGridMargin, 0, kGridMargin);

        NSCollectionLayoutSize *headerSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                            heightDimension:[NSCollectionLayoutDimension absoluteDimension:SeafWikiGroupHeader.headerHeight]];
        NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:headerSize elementKind:UICollectionElementKindSectionHeader alignment:NSRectAlignmentTop];
        section.boundarySupplementaryItems = @[header];

        return section;
    }];
    return layout;
}

#pragma mark - Data Loading

- (void)loadData {
    if (!_connection) return;
    NSUInteger currentGen = ++_loadGeneration;

    if (_sections.count == 0) {
        [_loadingView showInView:self.view];
    }

    // Request both wiki v1 and v2 APIs in parallel using dispatch_group for thread safety
    __block NSDictionary *wiki1JSON = nil;
    __block NSDictionary *wiki2JSON = nil;
    __block BOOL wiki1Failed = NO;
    __block BOOL wiki2Failed = NO;

    dispatch_group_t group = dispatch_group_create();

    // Wiki v2 (new)
    dispatch_group_enter(group);
    NSString *url2 = [NSString stringWithFormat:@"%@/wikis2/", API_URL_V21];
    [_connection sendRequest:url2
                     success:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON) {
        wiki2JSON = JSON;
        dispatch_group_leave(group);
    } failure:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON, NSError *err) {
        Warning("Failed to get wiki2: %@", err);
        wiki2Failed = YES;
        dispatch_group_leave(group);
    }];

    // Wiki v1 (legacy)
    dispatch_group_enter(group);
    NSString *url1 = [NSString stringWithFormat:@"%@/wikis/", API_URL_V21];
    [_connection sendRequest:url1
                     success:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON) {
        wiki1JSON = JSON;
        dispatch_group_leave(group);
    } failure:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON, NSError *err) {
        Warning("Failed to get wiki1: %@", err);
        wiki1Failed = YES;
        dispatch_group_leave(group);
    }];

    // When both requests complete, process on main thread
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (currentGen != self.loadGeneration) return; // connection changed, discard stale response
        [self.refreshControl endRefreshing];
        [self.loadingView dismiss];

        // Render whatever succeeded; deliberately more lenient than Android.
        if ((wiki1Failed || wiki2Failed) && self.isVisible)
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load wikis", @"Seafile")];

        if (!wiki1JSON && !wiki2JSON) {
            [self updateEmptyState];
            return;
        }
        [self processWiki1:wiki1JSON wiki2:wiki2JSON];
    });
}

- (void)processWiki1:(NSDictionary *)wiki1JSON wiki2:(NSDictionary *)wiki2JSON {
    NSMutableArray<SeafWikiInfo *> *mineList = [NSMutableArray new];
    NSMutableArray<SeafWikiInfo *> *sharedList = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSMutableArray<SeafWikiInfo *> *> *groupMap = [NSMutableDictionary new];
    NSMutableArray<SeafWikiInfo *> *oldList = [NSMutableArray new];

    // Parse wiki2
    if (wiki2JSON) {
        NSArray *wikis = wiki2JSON[@"wikis"];
        for (NSDictionary *w in wikis) {
            SeafWikiInfo *info = [[SeafWikiInfo alloc] initWithWiki2JSON:w];
            if ([info.type isEqualToString:@"mine"]) {
                [mineList addObject:info];
            } else if ([info.type isEqualToString:@"shared"]) {
                [sharedList addObject:info];
            }
        }

        NSArray *groupWikis = wiki2JSON[@"group_wikis"];
        for (NSDictionary *gw in groupWikis) {
            NSString *groupName = gw[@"group_name"] ?: NSLocalizedString(@"Group", @"Seafile");
            NSNumber *groupId = gw[@"group_id"];
            NSArray *wikiInfos = gw[@"wiki_info"];
            for (NSDictionary *w in wikiInfos) {
                SeafWikiInfo *info = [[SeafWikiInfo alloc] initWithWiki2JSON:w];
                info.groupName = groupName;
                info.groupId = [groupId longLongValue];
                info.groupOwner = gw[@"owner"];
                NSString *key = [NSString stringWithFormat:@"%@-%@", groupId, groupName];
                if (!groupMap[key]) groupMap[key] = [NSMutableArray new];
                [groupMap[key] addObject:info];
            }
        }
    }

    // Parse wiki1 (legacy)
    if (wiki1JSON) {
        NSArray *data = wiki1JSON[@"data"];
        for (NSDictionary *w in data) {
            SeafWikiInfo *info = [[SeafWikiInfo alloc] initWithWiki1JSON:w];
            [oldList addObject:info];
        }
    }

    // Build sections
    NSMutableArray *sections = [NSMutableArray new];

    if (mineList.count > 0) {
        SeafWikiGroup *header = [[SeafWikiGroup alloc] initWithTitle:NSLocalizedString(@"My Wikis", @"Seafile") iconName:@"icon_my_libraries"];
        NSMutableArray *section = [NSMutableArray arrayWithObject:header];
        [section addObjectsFromArray:mineList];
        [sections addObject:section];
    }

    if (sharedList.count > 0) {
        SeafWikiGroup *header = [[SeafWikiGroup alloc] initWithTitle:NSLocalizedString(@"Shared to me", @"Seafile") iconName:@"icon_shared_with_me"];
        NSMutableArray *section = [NSMutableArray arrayWithObject:header];
        [section addObjectsFromArray:sharedList];
        [sections addObject:section];
    }

    // Literal sort matches Android's TreeMap ordering and keeps section order stable.
    NSArray<NSString *> *sortedGroupKeys = [groupMap.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b options:NSLiteralSearch];
    }];
    for (NSString *key in sortedGroupKeys) {
        NSArray<SeafWikiInfo *> *items = groupMap[key];
        NSString *title = items.firstObject.groupName ?: NSLocalizedString(@"Group", @"Seafile");
        SeafWikiGroup *header = [[SeafWikiGroup alloc] initWithTitle:title iconName:@"icon_shared_with_all"];
        NSMutableArray *section = [NSMutableArray arrayWithObject:header];
        [section addObjectsFromArray:items];
        [sections addObject:section];
    }

    if (oldList.count > 0) {
        SeafWikiGroup *header = [[SeafWikiGroup alloc] initWithTitle:NSLocalizedString(@"Old Wikis", @"Seafile") iconName:@"icon_shared_with_all"];
        NSMutableArray *section = [NSMutableArray arrayWithObject:header];
        [section addObjectsFromArray:oldList];
        [sections addObject:section];
    }

    _sections = sections;
    [self.collectionView reloadData];
    [self updateEmptyState];
}

// Toggle the centered placeholder based on whether there is anything to show.
// Only called once loading has finished, so it never appears under the spinner.
- (void)updateEmptyState {
    self.collectionView.backgroundView = (self.sections.count == 0) ? self.emptyLabel : nil;
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    // First item in each section array is the group header, rest are wiki items
    return MAX(0, (NSInteger)[self.sections[section] count] - 1);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SeafWikiCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SeafWikiCell.reuseIdentifier forIndexPath:indexPath];
    SeafWikiInfo *wiki = self.sections[indexPath.section][indexPath.item + 1]; // +1 to skip group header
    [cell configureWithWiki:wiki];
    __weak typeof(self) weakSelf = self;
    cell.onMoreTapped = ^{
        // Convert moreButton frame to the view controller's coordinate space for iPad popover
        CGRect buttonRect = [cell.moreButton convertRect:cell.moreButton.bounds toView:weakSelf.view];
        [weakSelf showActionsForWiki:wiki sourceRect:buttonRect];
    };
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    SeafWikiGroupHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:SeafWikiGroupHeader.reuseIdentifier forIndexPath:indexPath];
    SeafWikiGroup *group = self.sections[indexPath.section][0];
    [header configureWithGroup:group];
    return header;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    SeafWikiInfo *wiki = self.sections[indexPath.section][indexPath.item + 1];
    [self openWiki:wiki];
}

- (void)openWiki:(SeafWikiInfo *)wiki {
    NSString *url;
    if ([wiki.type isEqualToString:SeafWikiTypeOld]) {
        url = [NSString stringWithFormat:@"%@/published/%@", _connection.address, wiki.slug];
    } else {
        url = [NSString stringWithFormat:@"%@/wikis/%@/", _connection.address, wiki.wikiId];
    }

    SeafWikiWebViewController *vc = [[SeafWikiWebViewController alloc] initWithURL:url connection:_connection showSafariToolbar:YES wikiName:wiki.name];
    vc.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Wiki Management Actions

- (void)showActionsForWiki:(SeafWikiInfo *)wiki sourceRect:(CGRect)sourceRect {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    // Rename
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Rename", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self renameWiki:wiki];
    }]];

    // Publish or Unpublish based on current state
    if (wiki.isPublished) {
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Unpublish", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self unpublishWiki:wiki];
        }]];
    } else {
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Publish Wiki", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self publishWiki:wiki];
        }]];
    }

    // Delete
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Delete Wiki", @"Seafile") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self deleteWiki:wiki];
    }]];

    // Cancel
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIAlertActionStyleCancel handler:nil]];

    // iPad popover presentation
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = sourceRect;

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)renameWiki:(SeafWikiInfo *)wiki {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Rename", @"Seafile")
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = wiki.name;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newName = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (newName.length == 0 || [newName isEqualToString:wiki.name]) return;

        [SVProgressHUD showWithStatus:NSLocalizedString(@"Renaming...", @"Seafile")];
        NSString *url = [NSString stringWithFormat:@"%@/wiki2/%@/", API_URL_V21, wiki.wikiId];
        NSString *form = [NSString stringWithFormat:@"wiki_name=%@", [newName escapedPostForm]];
        [weakSelf.connection sendPut:url form:form
                             success:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Rename successful", @"Seafile")];
                [weakSelf loadData];
            });
        } failure:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to rename wiki", @"Seafile")];
            });
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteWiki:(SeafWikiInfo *)wiki {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Delete Wiki", @"Seafile")
                                                                  message:NSLocalizedString(@"Delete wiki tip", @"Seafile")
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Delete", @"Seafile") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting...", @"Seafile")];
        NSString *url = [NSString stringWithFormat:@"%@/wiki2/%@/", API_URL_V21, wiki.wikiId];
        [weakSelf.connection sendDelete:url
                                success:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Deleted", @"Seafile")];
                [weakSelf loadData];
            });
        } failure:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to delete wiki", @"Seafile")];
                // Reload even on failure: the request may have succeeded server-side.
                [weakSelf loadData];
            });
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)publishWiki:(SeafWikiInfo *)wiki {
    NSString *urlPrefix = [NSString stringWithFormat:@"%@/wiki/publish/", _connection.address];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Publish Wiki", @"Seafile")
                                                                  message:NSLocalizedString(@"Publish wiki url tip", @"Seafile")
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = [NSString stringWithFormat:@"%@%@", urlPrefix, NSLocalizedString(@"Publish wiki custom url", @"Seafile")];
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *publishUrl = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (publishUrl.length == 0) return;

        // Custom part of a full publish URL must be 5-30 characters (matches Android).
        if ([publishUrl hasPrefix:urlPrefix]) {
            NSUInteger customLength = publishUrl.length - urlPrefix.length;
            if (customLength < 5 || customLength > 30) {
                [SVProgressHUD showInfoWithStatus:NSLocalizedString(@"Publish wiki url tip", @"Seafile")];
                return;
            }
        }

        [SVProgressHUD showWithStatus:NSLocalizedString(@"Publishing...", @"Seafile")];
        NSString *url = [NSString stringWithFormat:@"%@/wiki2/%@/publish/", API_URL_V21, wiki.wikiId];
        NSString *form = [NSString stringWithFormat:@"publish_url=%@", [publishUrl escapedPostForm]];
        [weakSelf.connection sendPost:url form:form
                              success:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Success", @"Seafile")];
                [weakSelf loadData];
            });
        } failure:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to publish wiki", @"Seafile")];
                // Reload even on failure: the request may have succeeded server-side.
                [weakSelf loadData];
            });
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)unpublishWiki:(SeafWikiInfo *)wiki {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Unpublish", @"Seafile")
                                                                  message:NSLocalizedString(@"Unpublish wiki tip", @"Seafile")
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Processing...", @"Seafile")];
        NSString *url = [NSString stringWithFormat:@"%@/wiki2/%@/publish/", API_URL_V21, wiki.wikiId];
        [weakSelf.connection sendDelete:url
                                success:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Success", @"Seafile")];
                [weakSelf loadData];
            });
        } failure:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to unpublish wiki", @"Seafile")];
                // Reload even on failure: the request may have succeeded server-side.
                [weakSelf loadData];
            });
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
