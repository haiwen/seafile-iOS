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
#import "UIViewController+Extend.h"
#import "ColorfulButton.h"
#import "SeafButtonCell.h"
#import "Debug.h"


@interface StartViewController ()
@property (retain) NSIndexPath *pressedIndex;
@property (retain) ColorfulButton *footer;
@end

@implementation StartViewController
@synthesize pressedIndex;

- (void)saveAccount:(SeafConnection *)conn
{
    SeafGlobal *global = [SeafGlobal sharedObject];
    BOOL exist = NO;
    if (![global.conns containsObject:conn]) {
        for (int i = 0; i < global.conns.count; ++i) {
            SeafConnection *c = global.conns[i];
            if ([c.address isEqual:conn.address] && [conn.username isEqual:c.username]) {
                global.conns[i] = conn;
                exist = YES;
                break;
            }
        }
        if (!exist)
            [global.conns addObject:conn];
    }
    [global saveAccounts];
    [self.tableView reloadData];
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
    self.title = NSLocalizedString(@"Accounts", @"Seafile");;

    NSArray *views = [[NSBundle mainBundle] loadNibNamed:@"SeafStartHeaderView" owner:self options:nil];
    UIView *header = [views objectAtIndex:0];
    header.frame = CGRectMake(0,0, self.tableView.frame.size.width, 100);
    header.autoresizesSubviews = YES;
    header.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin| UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin;
    header.backgroundColor = [UIColor clearColor];
    UILabel *welcomeLable = (UILabel *)[header viewWithTag:100];
    UILabel *msgLabel = (UILabel *)[header viewWithTag:101];
    welcomeLable.text = [NSString stringWithFormat:NSLocalizedString(@"Welcome to %@", @"Seafile"), APP_NAME];
    msgLabel.text = NSLocalizedString(@"Choose an account to start", @"Seafile");

    self.tableView.tableHeaderView = header;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.navigationController.navigationBar.tintColor = BAR_COLOR;

    views = [[NSBundle mainBundle] loadNibNamed:@"SeafStartFooterView" owner:self options:nil];
    ColorfulButton *bt = [views objectAtIndex:0];
    [bt addTarget:self action:@selector(goToDefaultBtclicked:) forControlEvents:UIControlEventTouchUpInside];
    bt.layer.cornerRadius = 0;
    bt.layer.borderWidth = 1.0f;
    bt.layer.masksToBounds = YES;
    bt.backgroundColor = [UIColor clearColor];
    [bt.layer setBorderColor:[[UIColor grayColor] CGColor]];
    [bt setTitleColor:[UIColor colorWithRed:112/255.0 green:112/255.0 blue:112/255.0 alpha:1.0] forState:UIControlStateNormal];
    [bt setTitle:NSLocalizedString(@"Back to Last Account", @"Seafile") forState:UIControlStateNormal];
    bt.showsTouchWhenHighlighted = true;
    self.footer = bt;
    [self.view addSubview:bt];
    self.footer.hidden = YES;
    self.tableView.sectionHeaderHeight = 20;
    [self.tableView reloadData];

}

- (BOOL)checkLastAccount
{
    NSString *server = [SeafGlobal.sharedObject objectForKey:@"DEAULT-SERVER"];
    NSString *username = [SeafGlobal.sharedObject objectForKey:@"DEAULT-USER"];
    if (server && username) {
        SeafConnection *connection = [[SeafGlobal sharedObject] getConnection:server username:username];
        if (connection)
            return YES;
    }
    return NO;
}

- (void)viewWillAppear:(BOOL)animated
{
    self.footer.hidden = !([self checkLastAccount]);
    [self.tableView reloadData];
    [super viewWillAppear:animated];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    ColorfulButton *bt = self.footer;
    bt.frame = CGRectMake(self.view.frame.origin.x-1, self.view.frame.size.height-57, self.tableView.frame.size.width+2, 58);
    bt.backgroundColor = [UIColor colorWithRed:227.0/255.0 green:227.0/255.0 blue:227.0/255.0 alpha:1.0];
    [bt.layer setBorderColor:[[UIColor grayColor] CGColor]];
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
    navController.modalPresentationStyle = UIModalPresentationFormSheet;
    dispatch_async(dispatch_get_main_queue(), ^ {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate.window.rootViewController presentViewController:navController animated:YES completion:nil];
    });
}

- (IBAction)addAccount:(id)sender
{
    pressedIndex = nil;
    NSString *privserver = NSLocalizedString(@"Other Server", @"Seafile");
    UIActionSheet * actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:actionSheetCancelTitle() destructiveButtonTitle:nil otherButtonTitles:SERVER_SEACLOUD_NAME, SERVER_CLOUD_NAME, SERVER_SHIB_NAME, privserver, nil];

    [actionSheet showInView:self.tableView];
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
    UIActionSheet *actionSheet;

    NSString *strEdit = NSLocalizedString(@"Edit", @"Seafile");
    NSString *strDelete = NSLocalizedString(@"Delete", @"Seafile");

    if (gestureRecognizer.state != UIGestureRecognizerStateBegan)
        return;
    CGPoint touchPoint = [gestureRecognizer locationInView:self.tableView];
    pressedIndex = [self.tableView indexPathForRowAtPoint:touchPoint];
    if (!pressedIndex)
        return;

    actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:actionSheetCancelTitle() destructiveButtonTitle:nil otherButtonTitles:strEdit, strDelete, nil];

    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:pressedIndex];
    [actionSheet showFromRect:cell.frame inView:self.tableView animated:YES];
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
    cell.button.bounds = CGRectMake(0, 0, 339, 64);
    cell.button.layer.cornerRadius = 1;
    cell.button.clipsToBounds = YES;
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
    cell.imageview.image = [UIImage imageWithContentsOfFile:conn.avatar];
    cell.serverLabel.text = conn.address;
    cell.emailLabel.text = conn.username;
    cell.accessoryType = UITableViewCellAccessoryNone;
    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showEditMenu:)];
    cell.imageview.layer.cornerRadius = 5;
    cell.imageview.clipsToBounds = YES;
    [cell addGestureRecognizer:longPressGesture];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 64;
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
    NSError *error = nil;
    LAContext *context = [[LAContext alloc] init];
    if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
        Warning("TouchID unavailable: %@", error);
        return [self alertWithTitle:STR_15];
    }

    [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
            localizedReason:STR_17
                      reply:^(BOOL success, NSError *error) {
                          if (error) {
                              Warning("Failed to evaluate TouchID: %@", error);
                              return [self alertWithTitle:STR_16];
                          }

                          if (!success) {
                              return [self alertWithTitle:STR_18];
                          } else {
                              dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.), dispatch_get_main_queue(), ^{
                                  BOOL ret = [self selectAccount:conn];
                                  handler(ret);
                              });
                          }
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

#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (pressedIndex) {// Long press account
        if (pressedIndex.row >= SeafGlobal.sharedObject.conns.count) return;
        if (buttonIndex == 0) {
            SeafConnection *conn = [[SeafGlobal sharedObject].conns objectAtIndex:pressedIndex.row];
            int type = conn.isShibboleth ? ACCOUNT_SHIBBOLETH : ACCOUNT_OTHER;
            [self showAccountView:conn type:type];
        } else if (buttonIndex == 1) {
            [[[SeafGlobal sharedObject].conns objectAtIndex:pressedIndex.row] clearAccount];
            [[SeafGlobal sharedObject].conns removeObjectAtIndex:pressedIndex.row];
            [[SeafGlobal sharedObject] saveAccounts];
            [self.tableView reloadData];
        }
    } else {
        if (buttonIndex >= 0 && buttonIndex <= ACCOUNT_OTHER) {
            [self showAccountView:nil type:(int)buttonIndex];
        }
    }
}

#pragma mark - SSConnectionDelegate
- (void)delayOP
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate.tabbarController setSelectedIndex:TABBED_SEAFILE];
}

- (BOOL)selectAccount:(SeafConnection *)conn;
{
    if (!conn) return NO;
    if (![conn authorized]) {
        NSString *title = NSLocalizedString(@"The token is invalid, you need to login again", @"Seafile");
        [self alertWithTitle:title handler:^{
            [self showAccountView:conn type:ACCOUNT_OTHER];
        }];
        return YES;
    }
    [SeafGlobal.sharedObject setObject:conn.address forKey:@"DEAULT-SERVER"];
    [SeafGlobal.sharedObject setObject:conn.username forKey:@"DEAULT-USER"];
    [SeafGlobal.sharedObject synchronize];

    [conn loadCache];
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate selectAccount:conn];
    if (appdelegate.window.rootViewController != appdelegate.tabbarController) {
        appdelegate.window.rootViewController = appdelegate.tabbarController;
        [appdelegate.window makeKeyAndVisible];
        [self performSelector:@selector(delayOP) withObject:nil afterDelay:0.01];
    }
    return YES;
}

- (void)selectDefaultAccount:(void (^)(bool success))handler
{
    NSString *server = [SeafGlobal.sharedObject objectForKey:@"DEAULT-SERVER"];
    NSString *username = [SeafGlobal.sharedObject objectForKey:@"DEAULT-USER"];
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
