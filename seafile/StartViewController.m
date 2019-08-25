//
//  StartViewController.m
//  seafile
//
//  Created by Wang Wei on 8/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

@import LocalAuthentication;

#import "StartViewController.h"
#import "SeafAccountViewController.h"
#import "SeafAppDelegate.h"
#import "SeafAccountCell.h"
#import "SeafStorage.h"
#import "UIViewController+Extend.h"
#import "ColorfulButton.h"
#import "SeafButtonCell.h"
#import "SVProgressHUD.h"
#import "ExtentedString.h"
#import "Debug.h"

#define TABLE_HEADER_HEIGHT 100

@interface StartViewController ()<UIDocumentPickerDelegate>
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet ColorfulButton *backButton;
@property (weak, nonatomic) IBOutlet UILabel *welcomeLabel;
@property (weak, nonatomic) IBOutlet UILabel *msgLabel;
@end

@implementation StartViewController

- (bool)saveAccount:(SeafConnection *)conn
{
    BOOL ret = [[SeafGlobal sharedObject] saveConnection:conn];
    [self.tableView reloadData];
    return ret;
}

- (void)setExtraCellLineHidden:(UITableView *)tableView
{
    UIView *view = [UIView new];
    view.backgroundColor = [UIColor clearColor];
    [tableView setTableFooterView:view];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    [self setExtraCellLineHidden:self.tableView];
    self.title = NSLocalizedString(@"Accounts", @"Seafile");

    self.welcomeLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Welcome to %@", @"Seafile"), APP_NAME];
    self.msgLabel.text = NSLocalizedString(@"Choose an account to start", @"Seafile");

    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
//    self.navigationItem.rightBarButtonItem = [self getBarItemAutoSize:@"ellipsis".navItemImgName action:@selector(editSheet:)];

    [self.backButton addTarget:self action:@selector(goToDefaultBtclicked:) forControlEvents:UIControlEventTouchUpInside];
    self.backButton.layer.cornerRadius = 0;
    self.backButton.layer.borderWidth = .5f;
    self.backButton.layer.masksToBounds = YES;
    self.backButton.layer.borderColor = [[UIColor lightGrayColor] CGColor];
    self.backButton.backgroundColor = [UIColor colorWithRed:249.0f/255 green:249.0f/255 blue:249.0f/255 alpha:1];
    [self.backButton setTitleColor:[UIColor colorWithRed:112/255.0 green:112/255.0 blue:112/255.0 alpha:1.0] forState:UIControlStateNormal];
    [self.backButton setTitle:NSLocalizedString(@"Back to Last Account", @"Seafile") forState:UIControlStateNormal];
    self.backButton.showsTouchWhenHighlighted = true;

    [self.tableView reloadData];
}

- (void)editSheet:(id)sender
{
    NSString *import = NSLocalizedString(@"Import client certificate", @"Seafile");
    NSString *remove = NSLocalizedString(@"Remove client certificate", @"Seafile");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *importAction = [UIAlertAction actionWithTitle:import style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self handleImprotCertificate];
    }];
    UIAlertAction *removeAction = [UIAlertAction actionWithTitle:remove style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self handleRemoveCertificate];
    }];
    [alert addAction:importAction];
    [alert addAction:removeAction];

    if (!IsIpad()){
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:STR_CANCEL style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:cancelAction];
    } else {
        [alert.view layoutIfNeeded];
    }
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:alert animated:true completion:nil];
}

- (void)handleImprotCertificate
{
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data"] inMode:UIDocumentPickerModeImport];
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)handleRemoveCertificate
{
    NSDictionary *dict = [SeafStorage.sharedObject getAllSecIdentities];
    if (dict.count == 0) {
        Warning("No client certificates.");
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"No available certificates", @"Seafile")];
        return;
    }
    [SeafStorage.sharedObject chooseCertFrom:dict handler:^(CFDataRef persistentRef, SecIdentityRef identity) {
        if (!identity || ! persistentRef) return;
        if ([SeafGlobal.sharedObject isCertInUse:(__bridge NSData*)(persistentRef)]) {
            Warning("Can not remove cert because it is still inuse.");
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Can not remove certificate because it is still in use", @"Seafile")];
            return;
        }

        BOOL ret = [SeafStorage.sharedObject removeIdentity:identity forPersistentRef:persistentRef];
        Debug("RemoveCertificate ret: %d", ret);
        if (ret) {
            [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Succeeded to remove certificate", @"Seafile")];
        } else {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to remove certificate", @"Seafile")];
        }
    } from:self];
}

- (BOOL)checkLastAccount
{
    NSString *server = [SeafStorage.sharedObject objectForKey:@"DEAULT-SERVER"];
    NSString *username = [SeafStorage.sharedObject objectForKey:@"DEAULT-USER"];
    if (server && username) {
        SeafConnection *connection = [[SeafGlobal sharedObject] getConnection:server username:username];
        if (connection)
            return YES;
    }
    return NO;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
}

- (void)viewDidUnload
{
    [self setTableView:nil];
    [super viewDidUnload];
}

- (void)showAccountView:(SeafConnection *)conn type:(int)type
{
    SeafAccountViewController *controller = [[SeafAccountViewController alloc] initWithController:self connection:conn type:type];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    if (IsIpad()) {
        navController.modalPresentationStyle = UIModalPresentationFormSheet;
    } else {
        navController.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    dispatch_async(dispatch_get_main_queue(), ^ {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate.window.rootViewController presentViewController:navController animated:YES completion:nil];
    });
}

- (IBAction)addAccount:(id)sender
{
    NSString *title = NSLocalizedString(@"Choose a Seafile server", @"Seafile");
    NSString *privserver = NSLocalizedString(@"Other Server", @"Seafile");
    NSArray *arr = [NSArray arrayWithObjects:SERVER_SEACLOUD_NAME, SERVER_SHIB_NAME, privserver, nil];
    UIAlertController *alert = [self generateAlert:arr withTitle:title handler:^(UIAlertAction *action) {
        long index = [arr indexOfObject:action.title];
        if (index >= 0 && index <= ACCOUNT_OTHER) {
            [self showAccountView:nil type:(int)index];
        }
    }];
    if (IsIpad()) {
        CGRect rect = [((UIView *)sender) frame];
        alert.popoverPresentationController.sourceRect = CGRectMake(rect.size.width/2, 0, 0, 0);
        alert.popoverPresentationController.sourceView = sender;
    } else {
        alert.popoverPresentationController.sourceView = sender;
    }
    [self presentViewController:alert animated:true completion:nil];
}

#pragma mark - Table view data source
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0)
        return SeafGlobal.sharedObject.conns.count;
    else
        return 1;
}

- (void)showEditMenu:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state != UIGestureRecognizerStateBegan)
        return;

    NSString *strEdit = NSLocalizedString(@"Edit", @"Seafile");
    NSString *strDelete = NSLocalizedString(@"Delete", @"Seafile");
    NSArray *arr = [NSArray arrayWithObjects:strEdit, strDelete, nil];
    CGPoint touchPoint = [gestureRecognizer locationInView:self.tableView];
    NSIndexPath *pressedIndex = [self.tableView indexPathForRowAtPoint:touchPoint];
    if (!pressedIndex)
        return;

    UIAlertController *alert = [self generateAlert:arr withTitle:nil handler:^(UIAlertAction *action) {
        long index = [arr indexOfObject:action.title];
        if (index < 0 || index >= arr.count)
            return;
        SeafConnection *conn = [SeafGlobal.sharedObject.conns objectAtIndex:pressedIndex.row];
        if (index == 0) { //Edit
            int type = conn.isShibboleth ? ACCOUNT_SHIBBOLETH : ACCOUNT_OTHER;
            [self showAccountView:conn type:type];
        } else if (index == 1) { //Delete
            [conn clearAccount];
            [SeafGlobal.sharedObject removeConnection:conn];
            [self.tableView reloadData];
        }
    }];

    [alert view];
    alert.popoverPresentationController.sourceRect = CGRectMake(touchPoint.x, touchPoint.y, 10, 10);
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self presentViewController:alert animated:true completion:nil];
    });
}

- (UITableViewCell *)getAddAccountCell:(UITableView *)tableView
{
    NSString *CellIdentifier = @"SeafButtonCell";
    SeafButtonCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:@"SeafButtonCell" owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    [cell.button setTitle:NSLocalizedString(@"Add account", @"Seafile") forState:UIControlStateNormal];
    [cell.button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    cell.button.backgroundColor = SEAF_COLOR_DARK;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    [cell.button addTarget:self action:@selector(addAccount:) forControlEvents:UIControlEventTouchUpInside];

    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 1) {
        return [self getAddAccountCell:tableView];
    }
    SeafAccountCell *cell = [SeafAccountCell getInstance:tableView WithOwner:self];
    SeafConnection *conn = [[SeafGlobal sharedObject].conns objectAtIndex:indexPath.row];
    [cell updateAccountCell:conn];
    cell.imageview.layer.cornerRadius = 25;

    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showEditMenu:)];
    [cell addGestureRecognizer:longPressGesture];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 66;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleNone;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    return [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 20)];
}

#pragma mark - Table view delegate
- (void)checkSelectAccount:(SeafConnection *)conn
{
    [self checkSelectAccount:conn completeHandler:^(bool success) { }];
}

- (void)checkSelectAccount:(SeafConnection *)conn completeHandler:(void (^)(bool success))handler
{
    if (!conn.touchIdEnabled) {
        BOOL ret = [self selectAccount:conn];
        return handler(ret);
    }
    Debug("verify touchId for %@ %@", conn.address, conn.username);
    [self checkTouchId:^(bool success) {
        if (success) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.), dispatch_get_main_queue(), ^{
                BOOL ret = [self selectAccount:conn];
                handler(ret);
            });
        } else
            handler(false);
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 1)
        return;

    @try {
        SeafConnection *conn = [SeafGlobal.sharedObject.conns objectAtIndex:indexPath.row];
        [self checkSelectAccount:conn];
    } @catch(NSException *exception) {
        [self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
    }
}

#pragma mark - UIDocumentPickerDelegate
- (void)importCertificate:(NSURL *)url
{
    NSString *alertMessage = [NSString stringWithFormat:NSLocalizedString(@"Successfully imported %@", @"Seafile"),[url lastPathComponent]];
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"Password of '%@'", @"Seafile"),[url lastPathComponent]];

    NSString *placeHolder = NSLocalizedString(@"Password", @"Seafile");;
    [self popupInputView:title placeholder:placeHolder secure:true handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Password must not be empty", @"Seafile") handler:^{
                [self importCertificate:url];
            }];
        }

        BOOL ret = [SeafStorage.sharedObject importCert:url.path password:input];
        Debug("import cert %@ ret=%d", url, ret);
        if (!ret) {
            [self alertWithTitle:NSLocalizedString(@"Wrong password", @"Seafile") handler:^{
                [self importCertificate:url];
            }];
        } else {
            [SVProgressHUD showSuccessWithStatus:alertMessage];
        }
    }];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    Debug("Improt file %u url: %@ %d", (unsigned)controller.documentPickerMode , url, [[NSFileManager defaultManager] fileExistsAtPath:url.path]);
    if (controller.documentPickerMode != UIDocumentPickerModeImport)
        return;

    [self importCertificate:url];
}

#pragma mark - SSConnectionDelegate
- (BOOL)selectAccount:(SeafConnection *)conn;
{
    if (!conn) return NO;
    if (![conn authorized]) {
        NSString *title = NSLocalizedString(@"The token is invalid, you need to login again", @"Seafile");
        if (conn.isShibboleth) {
            NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
            for (NSHTTPCookie *each in cookieStorage.cookies) {
                if([each.name isEqualToString:@"sessionid"]) {
                    [cookieStorage deleteCookie:each];
                }
            }
        }
        [self alertWithTitle:title handler:^{
            int type = conn.isShibboleth ? ACCOUNT_SHIBBOLETH : ACCOUNT_OTHER;
            [self showAccountView:conn type:type];
        }];
        return YES;
    }

    [SeafStorage.sharedObject setObject:conn.address forKey:@"DEAULT-SERVER"];
    [SeafStorage.sharedObject setObject:conn.username forKey:@"DEAULT-USER"];

    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate enterAccount:conn];
    return YES;
}

- (void)selectDefaultAccount:(void (^)(bool success))handler
{
    NSString *server = [SeafStorage.sharedObject objectForKey:@"DEAULT-SERVER"];
    NSString *username = [SeafStorage.sharedObject objectForKey:@"DEAULT-USER"];
    if (!username || !server) {
        return handler(false);
    }
    SeafConnection *conn = [SeafGlobal.sharedObject getConnection:server username:username];
    [self checkSelectAccount:conn completeHandler:handler];
}

- (IBAction)goToDefaultBtclicked:(id)sender
{
    [self selectDefaultAccount:^(bool success) { }];
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return (UIInterfaceOrientationMaskAll);
}

@end
