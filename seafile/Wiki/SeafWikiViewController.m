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
#import "SeafDateFormatter.h"
#import "UIViewController+Extend.h"

static NSString * const kWikiCellId = @"SeafWikiCell";
static NSString * const kWikiGroupHeaderId = @"SeafWikiGroupHeader";

#pragma mark - SeafWikiCell

@interface SeafWikiCell : UICollectionViewCell
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *publishBadge;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIButton *moreButton;
@end

@implementation SeafWikiCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.contentView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        self.contentView.layer.cornerRadius = 8;
        self.contentView.layer.borderWidth = 0.5;
        self.contentView.layer.borderColor = [UIColor separatorColor].CGColor;
        self.contentView.clipsToBounds = YES;

        _iconView = [[UIImageView alloc] init];
        _iconView.image = [UIImage systemImageNamed:@"book.fill"];
        _iconView.tintColor = [UIColor colorWithRed:236/255.0 green:114/255.0 blue:31/255.0 alpha:1.0];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;

        _publishBadge = [[UILabel alloc] init];
        _publishBadge.text = NSLocalizedString(@"Published", @"Seafile");
        _publishBadge.font = [UIFont systemFontOfSize:11];
        _publishBadge.textColor = [UIColor secondaryLabelColor];
        _publishBadge.layer.cornerRadius = 8;
        _publishBadge.layer.borderWidth = 0.5;
        _publishBadge.layer.borderColor = [UIColor separatorColor].CGColor;
        _publishBadge.clipsToBounds = YES;
        _publishBadge.textAlignment = NSTextAlignmentCenter;
        _publishBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _publishBadge.hidden = YES;

        _moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_moreButton setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
        _moreButton.tintColor = [UIColor secondaryLabelColor];
        _moreButton.translatesAutoresizingMaskIntoConstraints = NO;
        _moreButton.hidden = YES;

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont systemFontOfSize:13];
        _nameLabel.textColor = [UIColor labelColor];
        _nameLabel.numberOfLines = 3;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _timeLabel = [[UILabel alloc] init];
        _timeLabel.font = [UIFont systemFontOfSize:11];
        _timeLabel.textColor = [UIColor secondaryLabelColor];
        _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;

        UIView *cv = self.contentView;
        [cv addSubview:_iconView];
        [cv addSubview:_publishBadge];
        [cv addSubview:_moreButton];
        [cv addSubview:_nameLabel];
        [cv addSubview:_timeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.topAnchor constraintEqualToAnchor:cv.topAnchor constant:12],
            [_iconView.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:12],
            [_iconView.widthAnchor constraintEqualToConstant:24],
            [_iconView.heightAnchor constraintEqualToConstant:24],

            [_publishBadge.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],
            [_publishBadge.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:6],
            [_publishBadge.widthAnchor constraintGreaterThanOrEqualToConstant:60],
            [_publishBadge.heightAnchor constraintEqualToConstant:20],

            [_moreButton.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],
            [_moreButton.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-8],
            [_moreButton.widthAnchor constraintEqualToConstant:28],
            [_moreButton.heightAnchor constraintEqualToConstant:28],

            [_nameLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:8],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:12],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],

            [_timeLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:12],
            [_timeLabel.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],
            [_timeLabel.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-12],
        ]];
    }
    return self;
}

- (void)configureWithWiki:(SeafWikiInfo *)wiki {
    self.nameLabel.text = wiki.name;
    self.publishBadge.hidden = !wiki.isPublished;
    self.moreButton.hidden = ![wiki.type isEqualToString:SeafWikiTypeMine];

    if (wiki.updatedAt.length > 0) {
        self.timeLabel.text = wiki.updatedAt;
    } else {
        self.timeLabel.text = @"";
    }
}

@end

#pragma mark - SeafWikiGroupHeader

@interface SeafWikiGroupHeader : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *iconView;
@end

@implementation SeafWikiGroupHeader

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _iconView = [[UIImageView alloc] init];
        _iconView.tintColor = [UIColor secondaryLabelColor];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont boldSystemFontOfSize:15];
        _titleLabel.textColor = [UIColor labelColor];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:_iconView];
        [self addSubview:_titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:20],
            [_iconView.heightAnchor constraintEqualToConstant:20],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:6],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        ]];
    }
    return self;
}

- (void)configureWithGroup:(SeafWikiGroup *)group {
    self.titleLabel.text = group.title;
    if (group.iconName) {
        self.iconView.image = [[UIImage imageNamed:group.iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    } else {
        self.iconView.image = [[UIImage imageNamed:@"icon_shared_with_all"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
}

@end

#pragma mark - SeafWikiViewController

@interface SeafWikiViewController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) SeafLoadingView *loadingView;
@property (nonatomic, strong) NSArray *sections; // array of arrays; each section = @[SeafWikiGroup, SeafWikiInfo, ...]
@end

@implementation SeafWikiViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"Wikis", @"Seafile");
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barAppearance = [UINavigationBarAppearance new];
        barAppearance.backgroundColor = [UIColor whiteColor];
        self.navigationController.navigationBar.standardAppearance = barAppearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = barAppearance;
    }

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
        [self.collectionView reloadData];
    }
}

#pragma mark - Setup

- (void)setupCollectionView {
    UICollectionViewCompositionalLayout *layout = [self createLayout];
    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    _collectionView.backgroundColor = [UIColor systemBackgroundColor];
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    [_collectionView registerClass:[SeafWikiCell class] forCellWithReuseIdentifier:kWikiCellId];
    [_collectionView registerClass:[SeafWikiGroupHeader class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:kWikiGroupHeaderId];

    _refreshControl = [[UIRefreshControl alloc] init];
    [_refreshControl addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
    _collectionView.refreshControl = _refreshControl;

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
        // Two-column grid
        NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:0.5]
                                                                          heightDimension:[NSCollectionLayoutDimension absoluteDimension:140]];
        NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
        item.contentInsets = NSDirectionalEdgeInsetsMake(4, 4, 4, 4);

        NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                           heightDimension:[NSCollectionLayoutDimension absoluteDimension:140]];
        NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitem:item count:2];

        NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
        section.contentInsets = NSDirectionalEdgeInsetsMake(0, 8, 8, 8);

        // Section header
        NSCollectionLayoutSize *headerSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                            heightDimension:[NSCollectionLayoutDimension absoluteDimension:40]];
        NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:headerSize elementKind:UICollectionElementKindSectionHeader alignment:NSRectAlignmentTop];
        section.boundarySupplementaryItems = @[header];

        return section;
    }];
    return layout;
}

#pragma mark - Data Loading

- (void)loadData {
    if (!_connection) return;

    if (_sections.count == 0) {
        [_loadingView showInView:self.view];
    }

    // Request both wiki v1 and v2 APIs in parallel
    __block NSDictionary *wiki1JSON = nil;
    __block NSDictionary *wiki2JSON = nil;
    __block NSInteger completed = 0;
    __block BOOL hasFailed = NO;

    void (^checkComplete)(void) = ^{
        completed++;
        if (completed < 2) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.refreshControl endRefreshing];
            [self.loadingView dismiss];

            if (hasFailed && !wiki2JSON) {
                if (self.isVisible)
                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load wikis", @"Seafile")];
                return;
            }
            [self processWiki1:wiki1JSON wiki2:wiki2JSON];
        });
    };

    // Wiki v2 (new)
    NSString *url2 = [NSString stringWithFormat:@"%@/wikis2/", API_URL_V21];
    [_connection sendRequest:url2
                     success:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON) {
        wiki2JSON = JSON;
        checkComplete();
    } failure:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON, NSError *err) {
        Warning("Failed to get wiki2: %@", err);
        hasFailed = YES;
        checkComplete();
    }];

    // Wiki v1 (legacy)
    NSString *url1 = [NSString stringWithFormat:@"%@/wikis/", API_URL_V21];
    [_connection sendRequest:url1
                     success:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON) {
        wiki1JSON = JSON;
        checkComplete();
    } failure:^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON, NSError *err) {
        Warning("Failed to get wiki1: %@", err);
        checkComplete();
    }];
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
            NSString *groupName = gw[@"group_name"] ?: @"Group";
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
        SeafWikiGroup *header = [[SeafWikiGroup alloc] initWithTitle:NSLocalizedString(@"Shared with me", @"Seafile") iconName:@"icon_shared_with_me"];
        NSMutableArray *section = [NSMutableArray arrayWithObject:header];
        [section addObjectsFromArray:sharedList];
        [sections addObject:section];
    }

    for (NSString *key in groupMap) {
        NSArray<SeafWikiInfo *> *items = groupMap[key];
        NSString *title = items.firstObject.groupName ?: @"Group";
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
    SeafWikiCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kWikiCellId forIndexPath:indexPath];
    SeafWikiInfo *wiki = self.sections[indexPath.section][indexPath.item + 1]; // +1 to skip group header
    [cell configureWithWiki:wiki];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    SeafWikiGroupHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:kWikiGroupHeaderId forIndexPath:indexPath];
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

    SeafWikiWebViewController *vc = [[SeafWikiWebViewController alloc] initWithURL:url connection:_connection];
    vc.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:vc animated:YES];
}

@end
