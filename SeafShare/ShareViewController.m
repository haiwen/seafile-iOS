//
//  ShareViewController.m
//  SeafShare
//
//  Created by three on 2018/9/1.
//  Copyright © 2018年 Seafile. All rights reserved.
//

#import "ShareViewController.h"
#import "SeafGlobal.h"
#import "SeafAccountCell.h"
#import "Debug.h"
#import "UIViewController+Extend.h"
#import "SeafShareDestinationViewController.h"
#import "SeafNavLeftItem.h"
#import "Constants.h"

/// Horizontal inset for the account card / title (matches design).
static const CGFloat kAccountListHorizontalInset = 16.0;
/// Title band above the card (slightly taller than a single label line).
static const CGFloat kAccountHeaderHeight = 44.0;
/// Avatar inset from the card's left edge (tighter than the xib default ~16–20).
static const CGFloat kAccountAvatarLeadingInset = 12.0;
/// Separator inset relative to the card edge. Library lists use SEAF_SEPARATOR_INSET
/// which already includes SEAF_CARD_HORIZONTAL_PADDING; this tableView *is* the card,
/// so subtract that padding to match the same visual gap (left 13 / right 6).
static inline UIEdgeInsets SeafAccountSeparatorInset(void) {
    return UIEdgeInsetsMake(0,
                            SEAF_SEPARATOR_LEFT_INSET - SEAF_CARD_HORIZONTAL_PADDING,
                            0,
                            SEAF_SEPARATOR_RIGHT_INSET - SEAF_CARD_HORIZONTAL_PADDING);
}

@interface ShareViewController ()<UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) UILabel *headerLabel;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSLayoutConstraint *tableHeightConstraint;
@property (nonatomic, strong) UIAlertController *alert;
/// Hides the account list during the initial auto-push; cleared once pushed or on pop-back.
@property (nonatomic, assign) BOOL hidingAccountListForAutoPush;
/// Account chosen during this share session; drives the account list checkmark.
@property (nonatomic, copy) NSString *selectedAccountIdentifier;

@end

@implementation ShareViewController

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        if (@available(iOS 13.0, *)) {
            self.modalInPresentation = true;
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [SeafTheme applyPreferenceToViewController:self];
    self.view.backgroundColor = [SeafTheme primaryBackgroundColor];

    // Liquid Glass navigation bar: standard UIBarButtonItem (iOS 26 auto-applies glass)
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Cancel", @"Seafile")
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(cancel:)];
    self.title = @"Seafile";

    // Widen share UI on iPad to better utilize available space
    if (IsIpad()) {
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        CGFloat preferredWidth = MIN(ceil(screenWidth * 0.75f), 800.0f);
        [self setPreferredContentSize:CGSizeMake(preferredWidth, 540.0f)];
    }

    [self setupAccountListUI];

    [SeafGlobal.sharedObject loadAccounts];
    NSInteger accountCount = SeafGlobal.sharedObject.conns.count;
    if (accountCount == 0) {
        [self showNoAccountsAlert];
    } else {
        NSDictionary *lastPath = [SeafShareDestinationViewController lastUsedPathInfo];
        SeafConnection *lastConn = lastPath ? [self connectionForAccountIdentifier:lastPath[@"account"]] : nil;
        SeafConnection *autoConn = lastConn;
        if (!autoConn && accountCount == 1) {
            autoConn = SeafGlobal.sharedObject.conns.firstObject;
        }
        if (autoConn) {
            self.hidingAccountListForAutoPush = YES;
            self.headerContainer.hidden = YES;
            self.tableView.hidden = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self pushViewControllerConnIfAllowed:autoConn restoreLastPath:YES];
            });
        }
    }
}

- (void)setupAccountListUI {
    // Title band outside the white card (same idea as library group headers).
    self.headerContainer = [[UIView alloc] init];
    self.headerContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerContainer.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.headerContainer];

    self.headerLabel = [[UILabel alloc] init];
    self.headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerLabel.text = NSLocalizedString(@"Select an account", @"Seafile");
    self.headerLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    self.headerLabel.textColor = [SeafTheme primaryText];
    [self.headerContainer addSubview:self.headerLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 64;
    self.tableView.tableFooterView = [UIView new];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    // Same visual gap as library lists (card-relative, not cell-relative).
    self.tableView.separatorInset = SeafAccountSeparatorInset();
    self.tableView.backgroundColor = [SeafTheme primarySurface];
    self.tableView.layer.cornerRadius = 16.0;
    self.tableView.layer.masksToBounds = YES;
    self.tableView.scrollEnabled = NO; // Card hugs content; enable only when taller than viewport.
    self.tableView.alwaysBounceVertical = YES;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0;
    }
    [self.view addSubview:self.tableView];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    self.tableHeightConstraint = [self.tableView.heightAnchor constraintEqualToConstant:0];
    NSLayoutConstraint *tableBottom = [self.tableView.bottomAnchor constraintLessThanOrEqualToAnchor:guide.bottomAnchor constant:-16];
    tableBottom.priority = UILayoutPriorityRequired;
    [NSLayoutConstraint activateConstraints:@[
        [self.headerContainer.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.headerContainer.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.headerContainer.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [self.headerContainer.heightAnchor constraintEqualToConstant:kAccountHeaderHeight],

        [self.headerLabel.centerYAnchor constraintEqualToAnchor:self.headerContainer.centerYAnchor],
        [self.headerLabel.leadingAnchor constraintEqualToAnchor:self.headerContainer.leadingAnchor constant:kAccountListHorizontalInset],
        [self.headerLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.headerContainer.trailingAnchor constant:-kAccountListHorizontalInset],

        [self.tableView.topAnchor constraintEqualToAnchor:self.headerContainer.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:kAccountListHorizontalInset],
        [self.tableView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-kAccountListHorizontalInset],
        tableBottom,
        self.tableHeightConstraint,
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateTableHeight];
}

- (void)updateTableHeight {
    [self.tableView layoutIfNeeded];
    CGFloat contentHeight = self.tableView.contentSize.height;
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    CGFloat maxHeight = CGRectGetMaxY(guide.layoutFrame) - 16.0 - CGRectGetMinY(self.tableView.frame);
    if (maxHeight < 0) maxHeight = 0;
    CGFloat height = MIN(contentHeight, maxHeight);
    if (fabs(self.tableHeightConstraint.constant - height) > 0.5) {
        self.tableHeightConstraint.constant = height;
    }
    self.tableView.scrollEnabled = contentHeight > maxHeight + 0.5;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController.topViewController != self) return;

    // Keep hidden only while waiting for the initial auto-push on first load.
    if (self.hidingAccountListForAutoPush &&
        self.navigationController.viewControllers.count == 1) {
        return;
    }

    self.hidingAccountListForAutoPush = NO;
    self.headerContainer.hidden = NO;
    self.tableView.hidden = NO;
    // Refresh so the checkmark reflects the account chosen in this session.
    [self.tableView reloadData];
    [self updateTableHeight];
}

- (void)showNoAccountsAlert {
    if (!_alert) {
        self.alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"There is no account available", @"Seafile") message:nil preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:STR_CANCEL style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [self cancel:nil];
        }];
        [self.alert addAction:cancelAction];
    }
    [self presentViewController:self.alert animated:true completion:nil];
}

- (void)cancel:(id)sender {
    [self.extensionContext completeRequestReturningItems:self.extensionContext.inputItems completionHandler:nil];
}

#pragma mark - Table view
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return SeafGlobal.sharedObject.conns.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SeafAccountCell *cell = [SeafAccountCell getInstance:tableView WithOwner:self];
    SeafConnection *conn = [SeafGlobal.sharedObject.conns objectAtIndex:indexPath.row];
    [cell updateAccountCell:conn];

    // Design: server host on top, account name below (updateAccountCell uses the reverse).
    NSString *serverTitle = conn.host.length > 0 ? conn.host : conn.address;
    NSString *userSubtitle = conn.name.length > 0 ? conn.name : conn.username;
    cell.serverLabel.text = serverTitle;
    cell.emailLabel.text = userSubtitle;

    // Keep circular avatar from updateAccountCell / layoutSubviews (do not override to 5).
    [cell setAvatarLeadingInset:kAccountAvatarLeadingInset];
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];

    // Checkmark follows the session's selected account, not the global default account.
    BOOL isSelected = self.selectedAccountIdentifier.length > 0
        && [conn.accountIdentifier isEqualToString:self.selectedAccountIdentifier];
    cell.checkImageView.hidden = !isSelected;

    // Match library list visual inset from the card edge; hide under the last row.
    BOOL isLast = (indexPath.row == (NSInteger)SeafGlobal.sharedObject.conns.count - 1);
    cell.separatorInset = isLast
        ? UIEdgeInsetsMake(0, tableView.bounds.size.width, 0, 0)
        : SeafAccountSeparatorInset();

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    SeafConnection *conn = [SeafGlobal.sharedObject.conns objectAtIndex:indexPath.row];
    [self pushViewControllerConnIfAllowed:conn restoreLastPath:NO];
}

- (SeafConnection *)connectionForAccountIdentifier:(NSString *)accountId {
    if (![accountId isKindOfClass:[NSString class]] || accountId.length == 0) return nil;
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        if ([conn.accountIdentifier isEqualToString:accountId]) {
            return conn;
        }
    }
    return nil;
}

- (void)pushViewControllerConnIfAllowed:(SeafConnection *)conn restoreLastPath:(BOOL)restoreLastPath {
    if (!conn) return;
    Debug("TouchId for account %@ %@, %d", conn.address, conn.username, conn.touchIdEnabled);
    if (conn.touchIdEnabled) {
        __weak typeof(self) weakSelf = self;
        [self checkTouchId:^(bool success) {
            if (success) {
                [weakSelf pushViewControllerConn:conn restoreLastPath:restoreLastPath];
            } else {
                // Auth failed: bring the account list back so we don't sit on a blank screen.
                [weakSelf restoreAccountListAfterAbortedAutoPush];
            }
        } cancelHandler:^{
            // User cancelled Face ID / Touch ID. The auto-push hid the account list up-front,
            // so without this the extension would be stuck on a blank first screen.
            [weakSelf restoreAccountListAfterAbortedAutoPush];
        }];
    } else {
        [self pushViewControllerConn:conn restoreLastPath:restoreLastPath];
    }
}

- (void)restoreAccountListAfterAbortedAutoPush {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.hidingAccountListForAutoPush = NO;
        self.headerContainer.hidden = NO;
        self.tableView.hidden = NO;
        [self.tableView reloadData];
        [self updateTableHeight];
    });
}

- (void)pushViewControllerConn:(SeafConnection *)conn restoreLastPath:(BOOL)restoreLastPath {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.hidingAccountListForAutoPush = NO;
        self.selectedAccountIdentifier = conn.accountIdentifier;

        NSString *repoId = nil;
        NSString *path = nil;
        if (restoreLastPath) {
            NSDictionary *lastPath = [SeafShareDestinationViewController lastUsedPathInfo];
            if (lastPath && [lastPath[@"account"] isEqualToString:conn.accountIdentifier]) {
                repoId = lastPath[@"repoId"];
                path = lastPath[@"path"];
            }
        }

        SeafShareDestinationViewController *destVC;
        if (repoId.length > 0) {
            destVC = [[SeafShareDestinationViewController alloc] initWithConnection:conn repoId:repoId path:path];
        } else {
            destVC = [[SeafShareDestinationViewController alloc] initWithConnection:conn];
        }
        [self.navigationController pushViewController:destVC animated:YES];
    });
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
