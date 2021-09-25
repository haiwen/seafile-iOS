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
#import <BuglyExtension/CrashReporterLite.h>

@interface ShareViewController ()<UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UIAlertController *alert;

@end

@implementation ShareViewController

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [CrashReporterLite startWithApplicationGroupIdentifier:SEAFILE_SUITE_NAME];
        if (@available(iOS 13.0, *)) {
            self.modalInPresentation = true;
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = NSLocalizedString(@"Save to Seafile", @"Seafile");
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
    
    [SeafGlobal.sharedObject loadAccounts];
    if (SeafGlobal.sharedObject.conns.count == 0) {
        [self showNoAccountsAlert];
    }
    
    self.tableView.rowHeight = 64;
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

