//
//  StartViewController.m
//  seafile
//
//  Created by Wang Wei on 8/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "StartViewController.h"
#import "SeafAccountViewController.h"
#import "SeafAppDelegate.h"
#import "SeafAccountCell.h"

#import "Debug.h"


@interface StartViewController ()
@property (retain) NSMutableArray *conns;
@property (retain) NSIndexPath *pressedIndex;
@end

@implementation StartViewController
@synthesize conns;
@synthesize pressedIndex;


- (id)init
{
    if (self = [super init]) {
        self.conns = [[NSMutableArray alloc] init ];
        [self loadAccounts];
    }
    return self;
}

- (void)loadAccounts
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSArray *accounts = [userDefaults objectForKey:@"ACCOUNTS"];
    for (NSDictionary *account in accounts) {
        SeafConnection *conn = [[SeafConnection alloc] initWithUrl:[account objectForKey:@"url"] username:[account objectForKey:@"username"]];
        [self.conns addObject:conn];
    }
}

- (void)saveAccounts
{
    NSMutableArray *accounts = [[NSMutableArray alloc] init];
    for (SeafConnection *connection in conns) {
        NSMutableDictionary *account = [[NSMutableDictionary alloc] init];
        [account setObject:connection.address forKey:@"url"];
        [account setObject:connection.username forKey:@"username"];
        [accounts addObject:account];
    }
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:accounts forKey:@"ACCOUNTS"];
    [userDefaults synchronize];
};

- (void)saveAccount:(SeafConnection *)conn
{
    if (![self.conns containsObject:conn]) {
        [self.conns addObject:conn];
    }
    [self saveAccounts];
    [self.tableView reloadData];
}

- (SeafConnection *)getConnection:(NSString *)url username:(NSString *)username
{
    SeafConnection *conn;
    for (conn in self.conns) {
        if ([conn.address isEqual:url] && [conn.username isEqual:username])
            return conn;
    }
    return nil;
}

- (void)selectAccount:(SeafConnection *)conn;
{
    [self transferToReposView:conn];
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
    [self setExtraCellLineHidden:self.tableView];
    self.title = @"Seafile";
    UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithTitle:@"Add account" style:UIBarButtonItemStyleBordered target:self action:@selector(addAccount:)];
    self.navigationItem.rightBarButtonItem = addItem;

    NSArray *views = [[NSBundle mainBundle] loadNibNamed:@"SeafStartHeaderView" owner:self options:nil];
    UIView *header = [views objectAtIndex:0];
    header.frame = CGRectMake(0,0, self.tableView.frame.size.width, 100);
    header.autoresizesSubviews = YES;
    header.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin| UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin;
    header.backgroundColor = [UIColor clearColor];
    self.tableView.tableHeaderView = header;

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *server = [userDefaults objectForKey:@"DEAULT-SERVER"];
    NSString *username = [userDefaults objectForKey:@"DEAULT-USER"];
    if (server && username) {
        SeafConnection *connection = [self getConnection:server username:username];
        if (connection)
            [self selectAccount:connection];
    }
}

- (void)viewDidUnload
{
    [self setTableView:nil];
    [super viewDidUnload];
}

- (void)showAccountView:(SeafConnection *)conn
{
    SeafAccountViewController *controller = [[SeafAccountViewController alloc] initWithController:self connection:conn];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    navController.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:navController animated:YES completion:nil];
}

- (IBAction)addAccount:(id)sender
{
    [self showAccountView:nil];
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

- (void)showEditMenu:(UILongPressGestureRecognizer *)gestureRecognizer
{
    UIActionSheet *actionSheet;

    if (gestureRecognizer.state != UIGestureRecognizerStateBegan)
        return;
    CGPoint touchPoint = [gestureRecognizer locationInView:self.tableView];
    pressedIndex = [self.tableView indexPathForRowAtPoint:touchPoint];
    if (!pressedIndex)
        return;
    if (IsIpad())
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:@"Edit", @"Delete", nil];
    else
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Edit", @"Delete", nil];

    Debug("index=%d\n", pressedIndex.row);
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:pressedIndex];
    [actionSheet showFromRect:cell.frame inView:self.tableView animated:YES];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafAccountCell";
    SeafAccountCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    SeafConnection *conn = [self.conns objectAtIndex:indexPath.row];
    NSString* path = [[NSBundle mainBundle] pathForResource:@"account" ofType:@"png"];
    cell.imageview.image = [UIImage imageWithContentsOfFile:path];
    cell.serverLabel.text = conn.address;
    cell.emailLabel.text = conn.username;
    cell.accessoryType = UITableViewCellAccessoryNone;

    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showEditMenu:)];
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

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    Debug("%d, %@\n", indexPath.row, [[self.conns objectAtIndex:indexPath.row] address]);
    [self selectAccount:[self.conns objectAtIndex:indexPath.row]];
}


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!IsIpad()) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
    return YES;
}

#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    Debug("buttonIndex=%d, indexpath=%d\n", buttonIndex, pressedIndex.row);
    if (buttonIndex == 0) {
        [self showAccountView:[self.conns objectAtIndex:pressedIndex.row]];
    } else if (buttonIndex == 1) {
        [self.conns removeObjectAtIndex:pressedIndex.row];
        [self saveAccounts];
        [self.tableView reloadData];
    }
}

#pragma mark - SSConnectionDelegate
- (void)transferToReposView:(SeafConnection *)conn
{
    Debug("%@\n", conn.address);
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:conn.address forKey:@"DEAULT-SERVER"];
    [userDefaults setObject:conn.username forKey:@"DEAULT-USER"];
    [userDefaults synchronize];

    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [conn loadRepos:appdelegate.masterVC];
    appdelegate.uploadVC.connection = conn;
    appdelegate.starredVC.connection = conn;
    appdelegate.settingVC.connection = conn;
    [appdelegate.detailVC setPreViewItem:nil];
    if (IsIpad())
        appdelegate.window.rootViewController = appdelegate.splitVC;
    else
        appdelegate.window.rootViewController = appdelegate.tabbarController;

    [appdelegate.masterVC setDirectory:(SeafDir *)conn.rootFolder];
    [appdelegate.window makeKeyAndVisible];
}

@end
