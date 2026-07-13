//
//  SeafShareBaseListViewController.m
//  SeafShare
//
//  Common infrastructure for Recent / Starred destination-picker tabs.
//  Subclasses override the hook methods to supply data and cell content.
//

#import "SeafShareBaseListViewController.h"
#import "SeafShareDestCell.h"
#import "SeafTheme.h"
#import "Constants.h"

NSString * const kShareDestCellId = @"SeafShareDestCell";

@interface SeafShareBaseListViewController ()

// Redeclare readwrite so the base class can initialise the views.
@property (nonatomic, strong, readwrite) SeafConnection *connection;
@property (nonatomic, strong, readwrite) UITableView *tableView;
@property (nonatomic, strong, readwrite) UILabel *emptyLabel;
@property (nonatomic, strong, readwrite) UIActivityIndicatorView *loadingView;

@end

@implementation SeafShareBaseListViewController

#pragma mark - Init

- (instancetype)initWithConnection:(SeafConnection *)connection {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _connection = connection;
        _selectedIndex = -1;
    }
    return self;
}

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    [self setupTableView];
    [self setupLoadingView];
    [self setupEmptyLabel];
}

#pragma mark - UI Setup (private)

- (void)setupTableView {
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
    // Match SeafCell.xib estimated height.
    self.tableView.estimatedRowHeight = 68;

    self.tableView.backgroundColor = [SeafTheme primarySurface];
    self.tableView.layer.cornerRadius = 16.0;
    self.tableView.layer.masksToBounds = YES;

    [self.tableView registerClass:[SeafShareDestCell class] forCellReuseIdentifier:kShareDestCellId];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        // Top matches left/right (SEAF_CARD_HORIZONTAL_PADDING). Parent contentContainer
        // is flush under the tabs so Libraries headers can stay truly centered.
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:SEAF_CARD_HORIZONTAL_PADDING],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:SEAF_CARD_HORIZONTAL_PADDING],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-SEAF_CARD_HORIZONTAL_PADDING],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0;
    }
}

- (void)setupLoadingView {
    self.loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingView.hidesWhenStopped = YES;
    self.loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.loadingView];
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)setupEmptyLabel {
    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.textColor = [SeafTheme secondaryText];
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

#pragma mark - Subclass Hooks (default implementations)

- (NSInteger)dataSourceCount {
    return 0;
}

- (BOOL)isItemSelectableAtIndex:(NSInteger)index {
    return YES;
}

- (SeafDir *)selectedDirectory {
    return nil;
}

#pragma mark - Helpers for Subclasses

- (void)updateEmptyStateWithMessage:(NSString *)message {
    BOOL isEmpty = ([self dataSourceCount] == 0);
    self.emptyLabel.text = message;
    self.emptyLabel.hidden = !isEmpty;
    if (isEmpty) {
        [self.view bringSubviewToFront:self.emptyLabel];
    }
}

- (void)handleSelectionAtIndexPath:(NSIndexPath *)indexPath inTableView:(UITableView *)tableView {
    if (self.selectedIndex == indexPath.row) {
        self.selectedIndex = -1;
    } else {
        NSInteger previousIndex = self.selectedIndex;
        self.selectedIndex = indexPath.row;
        if (previousIndex >= 0 && previousIndex < [self dataSourceCount]) {
            [tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:previousIndex inSection:0]]
                             withRowAnimation:UITableViewRowAnimationNone];
        }
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - UITableViewDataSource (common)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self dataSourceCount];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return nil;
}

/// Subclasses MUST override this method to provide cell content.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [tableView dequeueReusableCellWithIdentifier:kShareDestCellId forIndexPath:indexPath];
}

@end
