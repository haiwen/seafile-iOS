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
#import "SeafShareDirViewController.h"
#import "SeafNavLeftItem.h"
#import "Constants.h"

@interface ShareViewController ()<UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UIAlertController *alert;

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

    // Force Light mode for share extension UI
    if (@available(iOS 13.0, *)) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        self.navigationController.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        self.navigationController.navigationBar.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    }
    // Custom navigation layout: arrow + title aligned to the left
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:[SeafNavLeftItem navLeftItemWithDirectory:nil title:NSLocalizedString(@"Select an account", @"Seafile") target:self action:@selector(cancel:)]];
    self.navigationItem.title = @"";
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    
    // Widen share UI on iPad to better utilize available space
    if (IsIpad()) {
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        CGFloat preferredWidth = MIN(ceil(screenWidth * 0.75f), 800.0f);
        [self setPreferredContentSize:CGSizeMake(preferredWidth, 540.0f)];
    }
    
    [SeafGlobal.sharedObject loadAccounts];
    if (SeafGlobal.sharedObject.conns.count == 0) {
        [self showNoAccountsAlert];
    }
    
    self.tableView.rowHeight = 64;
    // Add top spacing for first row
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 10)];
    self.tableView.tableHeaderView = header;

    self.tableView.tableFooterView = [UIView new];
    self.tableView.separatorStyle = UITableViewCellSelectionStyleNone;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barAppearance = [UINavigationBarAppearance new];
        barAppearance.backgroundColor = [UIColor systemBackgroundColor];
        
        self.navigationController.navigationBar.standardAppearance = barAppearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = barAppearance;
        
        self.tableView.sectionHeaderTopPadding = 0;
    }
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
    cell.imageview.layer.cornerRadius = 5;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    SeafConnection *conn = [SeafGlobal.sharedObject.conns objectAtIndex:indexPath.row];
    Debug("TouchId for account %@ %@, %d", conn.address, conn.username, conn.touchIdEnabled);
    if (conn.touchIdEnabled) {
        [self checkTouchId:^(bool success) {
            if (success) {
                [self pushViewControllerConn:conn];
            }
        }];
    } else {
        [self pushViewControllerConn:conn];
    }
}

- (void)pushViewControllerConn:(SeafConnection *)conn {
    dispatch_async(dispatch_get_main_queue(), ^{
        SeafShareDirViewController *dirVC = [[SeafShareDirViewController alloc] initWithSeafDir:conn.rootFolder];
        [self.navigationController pushViewController:dirVC animated:true];
    });
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

