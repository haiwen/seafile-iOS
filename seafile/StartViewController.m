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
// Table view to display accounts and buttons
@property (weak, nonatomic) IBOutlet UITableView *tableView;
// Label for displaying welcome message
@property (weak, nonatomic) IBOutlet UILabel *welcomeLabel;
// Label for additional messages or instructions
@property (weak, nonatomic) IBOutlet UILabel *msgLabel;
@end

@implementation StartViewController

// Saves the account details to persistent storage
- (bool)saveAccount:(SeafConnection *)conn
{
    BOOL ret = [[SeafGlobal sharedObject] saveConnection:conn];
    [self.tableView reloadData];
    return ret;
}

// Hides extra cell lines by setting a clear footer view
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
    
    // Set up welcome and message labels
    self.welcomeLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Welcome to %@", @"Seafile"), APP_NAME];
    self.msgLabel.text = NSLocalizedString(@"Choose an account to start", @"Seafile");

    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.navigationController.navigationBar.tintColor = BAR_COLOR;

    [self.tableView reloadData];
}

// Present an action sheet for importing or removing client certificates
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

// Handles the import of a client certificate
- (void)handleImprotCertificate
{
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data"] inMode:UIDocumentPickerModeImport];
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

// Handles the removal of a client certificate
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

// Checks if the last used account is still valid
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
    [self.tableView reloadData];
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

// Presents the account view controller for a given connection
- (void)showAccountView:(SeafConnection *)conn type:(int)type
{
    SeafAccountViewController *controller = [[SeafAccountViewController alloc] initWithController:self connection:conn type:type];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    if (IsIpad()) {
        navController.modalPresentationStyle = UIModalPresentationFormSheet;
        UINavigationController *nav = self.navigationController;
        if (!nav) {
            dispatch_async(dispatch_get_main_queue(), ^ {
                SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
                [appdelegate.window.rootViewController presentViewController:navController animated:YES completion:nil];
            });
        } else {
            [nav pushViewController:controller animated:YES];
        }
    } else {
        navController.modalPresentationStyle = UIModalPresentationFullScreen;
        dispatch_async(dispatch_get_main_queue(), ^ {
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate.window.rootViewController presentViewController:navController animated:YES completion:nil];
        });
    }
}

// Handles the action for adding a new account
- (IBAction)addAccount:(id)sender
{
    NSString *title = NSLocalizedString(@"Choose a Seafile server", @"Seafile");
    NSString *privserver = NSLocalizedString(@"Other Server", @"Seafile");
    
    // Array of display at login view.
    NSArray *arrZH = [NSArray arrayWithObjects:SERVER_SEACLOUD_NAME, SERVER_SHIB_NAME, privserver, nil];
    NSArray *arrOther = [NSArray arrayWithObjects:SERVER_SHIB_NAME, privserver, nil];
    
    // Detect the current locale
    NSString *currentLanguage = [[NSLocale preferredLanguages] firstObject];
    
    UIAlertController *alert = nil;
    
    // Show different login methods
    if ([currentLanguage hasPrefix:@"zh"]) {
        alert = [self generateAlert:arrZH withTitle:title handler:^(UIAlertAction *action) {
            long index = [arrZH indexOfObject:action.title];
            if (index >= 0 && index <= ACCOUNT_OTHER) {
                [self showAccountView:nil type:(int)index];
            }
        }];
    } else {
        alert = [self generateAlert:arrOther withTitle:title handler:^(UIAlertAction *action) {
            long index = [arrOther indexOfObject:action.title];
            if (index >= 0 && index <= ACCOUNT_OTHER) {
                [self showAccountView:nil type:(int)index + 1];
            }
        }];
    }

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

// Displays an edit menu when a long press gesture is recognized
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
        if (index == 0) { // Edit
            int type = conn.isShibboleth ? ACCOUNT_SHIBBOLETH : ACCOUNT_OTHER;
            // Save original account information
            NSString *originalUsername = conn.username;
            NSString *originalAddress = conn.address;
            
            // Set original information to conn's extended properties
            conn.originalUsername = originalUsername;
            conn.originalAddress = originalAddress;
            
            [self showAccountView:conn type:type];
        } else if (index == 1) { // Delete
            // Get current login account information
            NSString *currentServer = [SeafStorage.sharedObject objectForKey:@"DEAULT-SERVER"];
            NSString *currentUsername = [SeafStorage.sharedObject objectForKey:@"DEAULT-USER"];
            
            // Check if the account to be deleted is the current login account
            if (currentServer && currentUsername && 
                [currentServer isEqualToString:conn.address] && 
                [currentUsername isEqualToString:conn.username]) {
                SeafConnection *oldConn = [SeafGlobal.sharedObject getConnection:currentServer username:currentUsername];
                if (oldConn) {
                    [oldConn logoutAndAccountClear];
                    [SeafGlobal.sharedObject removeConnection:oldConn];
                }
                SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
                [appdelegate exitAccount];
            } else {
                // If it is not the current login account, allow deletion
                [conn clearAccount];
                [SeafGlobal.sharedObject removeConnection:conn];
                [self.tableView reloadData];
            }
        }
    }];

    [alert view];
    alert.popoverPresentationController.sourceRect = CGRectMake(touchPoint.x, touchPoint.y, 10, 10);
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self presentViewController:alert animated:true completion:nil];
    });
}

// Generates a cell for adding a new account
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
// Checks whether the selected account is valid and updates the interface accordingly
- (void)checkSelectAccount:(SeafConnection *)conn
{
    [self checkSelectAccount:conn completeHandler:^(bool success) { }];
}

// Verifies the selected account with optional biometric authentication
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
// Manages the import of a security certificate from the specified URL
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

// Handles the document picked by the user for importing
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    Debug("Improt file %u url: %@ %d", (unsigned)controller.documentPickerMode , url, [[NSFileManager defaultManager] fileExistsAtPath:url.path]);
    if (controller.documentPickerMode != UIDocumentPickerModeImport)
        return;

    [self importCertificate:url];
}

#pragma mark - SSConnectionDelegate
// Selects the given account and updates the app state
- (BOOL)selectAccount:(SeafConnection *)conn
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
    
    [self.tableView reloadData];

    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate enterAccount:conn];
    return YES;
}

// Attempts to select the default account as specified in the app's settings
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

- (BOOL)shouldAutorotate
{
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return (UIInterfaceOrientationMaskAll);
}

#pragma mark - Account Info Refresh
// Refreshes the account information and updates the UI
- (void)refreshAccountInfo:(SeafConnection *)connection
{
    if (!connection) return;
    
    // Show loading status
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Updating account info", @"Seafile")];
    
    // Get account information
    [connection getAccountInfo:^(bool result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Hide loading status
            [SVProgressHUD dismiss];
            
            if (result) {
                // Successfully retrieved account information, refresh the table
                Debug(@"Successfully refreshed account info for %@ %@", connection.address, connection.username);
                [self.tableView reloadData];
            } else {
                // Failed to retrieve account information
                Warning(@"Failed to get account info for %@ %@", connection.address, connection.username);
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to update account info", @"Seafile")];
            }

            [[NSNotificationCenter defaultCenter] postNotificationName:@"SeafAccountInfoUpdated"
                                                                object:connection
                                                              userInfo:@{@"success": @(result)}];
        });
    }];
}

- (void)reloadAccountList {
    [self.tableView reloadData];
}

@end


