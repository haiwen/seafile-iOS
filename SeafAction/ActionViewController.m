//
//  ActionViewController.m
//  SeafAction
//
//  Created by Wang Wei on 04/12/2016.
//  Copyright © 2016 Seafile. All rights reserved.
//

#import "ActionViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import "SeafActionDirViewController.h"
#import "SeafGlobal.h"
#import "SeafStorage.h"
#import "SeafAccountCell.h"
#import "UIViewController+Extend.h"
#import "Debug.h"
#import "Utils.h"
#import "SeafInputItemsProvider.h"

@interface ActionViewController ()<UITableViewDataSource, UITableViewDelegate>

@property (strong) NSArray *conns;
@property (strong) SeafUploadFile *ufile;

@end

@implementation ActionViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    if (IsIpad()) {
        [self setPreferredContentSize:CGSizeMake(480.0f, 540.0f)];
    }

    [SeafGlobal.sharedObject loadAccounts];
    _conns = SeafGlobal.sharedObject.conns;
    
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Accounts", @"Seafile")
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:nil
                                                                            action:nil];
    self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 10)];
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barAppearance = [UINavigationBarAppearance new];
        barAppearance.backgroundColor = [UIColor systemBackgroundColor];
        
        self.navigationController.navigationBar.standardAppearance = barAppearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = barAppearance;
        
//        self.tableView.sectionHeaderTopPadding = 0;
    }
    
    __weak typeof(self) weakSelf = self;
    [SeafInputItemsProvider loadInputs:weakSelf.extensionContext complete:^(BOOL result, NSArray *array) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (result) {
                weakSelf.ufile = array.firstObject;
            } else {
                [weakSelf alertWithTitle:NSLocalizedString(@"Failed to load file", @"Seafile") handler:^{
                    [weakSelf.extensionContext completeRequestReturningItems:self.extensionContext.inputItems completionHandler:nil];
                }];
            }
        });
    }];
}

- (void)handleFile:(NSURL *)url {
    Debug("Received file : %@", url);
    if (!url) {
        Warning("Failed to load file.");
        [self alertWithTitle:NSLocalizedString(@"Failed to load file", @"Seafile") handler:nil];
        [self.extensionContext completeRequestReturningItems:self.extensionContext.inputItems completionHandler:nil];
    }
    Debug("Upload file %@ %lld", url, [Utils fileSizeAtPath1:url.path]);
    _ufile = [[SeafUploadFile alloc] initWithPath:url.path];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)cancel:(id)sender
{
    [_ufile cancel];
   [self.extensionContext completeRequestReturningItems:self.extensionContext.inputItems completionHandler:nil];
}

#pragma mark - Table view data source
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.conns.count;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 64;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafAccountCell *cell = [SeafAccountCell getInstance:tableView WithOwner:self];
    SeafConnection *conn = [self.conns objectAtIndex:indexPath.row];
    [cell updateAccountCell:conn];
    cell.imageview.layer.cornerRadius = 5;
    return cell;
}

#pragma mark - Table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafConnection *conn = [SeafGlobal.sharedObject.conns objectAtIndex:indexPath.row];
    Debug("TouchId for account %@ %@, %d", conn.address, conn.username, conn.touchIdEnabled);
    if (!conn.touchIdEnabled) {
        return [self pushViewControllerDir:(SeafDir *)conn.rootFolder];
    }
    [self checkTouchId:^(bool success) {
        if (success) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.0), dispatch_get_main_queue(), ^{
                [self pushViewControllerDir:(SeafDir *)conn.rootFolder];
            });
        }
    }];
}

- (void)pushViewControllerDir:(SeafDir *)dir
{
    SeafActionDirViewController *controller = [[SeafActionDirViewController alloc] initWithSeafDir:dir file:self.ufile];
    [self.navigationController pushViewController:controller animated:true];
}

@end
