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
@property (retain) ColorfulButton *footer;
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
    BOOL exist = NO;
    if (![self.conns containsObject:conn]) {
        for (int i = 0; i < self.conns.count; ++i) {
            SeafConnection *c = self.conns[i];
            if ([c.address isEqual:conn.address] && [conn.username isEqual:c.username]) {
                self.conns[i] = conn;
                exist = YES;
                break;
            }
        }
        if (!exist)
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
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
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
    self.footer = bt;
    [self.view addSubview:bt];
    self.footer.hidden = YES;
}

- (BOOL)checkLastAccount
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *server = [userDefaults objectForKey:@"DEAULT-SERVER"];
    NSString *username = [userDefaults objectForKey:@"DEAULT-USER"];
    if (server && username) {
        SeafConnection *connection = [self getConnection:server username:username];
        if (connection)
            return YES;
    }
    return NO;
}

- (void)viewWillAppear:(BOOL)animated
{
    if ([self checkLastAccount])
        self.footer.hidden = NO;
    else
        self.footer.hidden = YES;
}

- (void)viewWillLayoutSubviews
{
    ColorfulButton *bt = self.footer;
    if (IsIpad()) {
        bt.frame = CGRectMake(self.view.frame.origin.x-1, self.view.frame.size.height-57, self.tableView.frame.size.width+2, 58);
        bt.backgroundColor = [UIColor colorWithRed:227.0/255.0 green:227.0/255.0 blue:227.0/255.0 alpha:1.0];
    } else
        bt.frame = CGRectMake(self.view.frame.origin.x-1, self.view.frame.size.height-51, self.tableView.frame.size.width+2, 52);
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
    [self presentViewController:navController animated:YES completion:nil];
}

- (IBAction)addAccount:(id)sender
{
    UIActionSheet *actionSheet;
    pressedIndex = nil;
    if (IsIpad())
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:@"Private Seafile Server", @"SeaCloud.cc", @"cloud.seafile.com", nil];
    else
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Private Seafile Server", @"SeaCloud.cc", @"cloud.seafile.com", nil];
    [actionSheet showFromBarButtonItem:sender animated:YES];
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
    [self selectAccount:[self.conns objectAtIndex:indexPath.row]];
}


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return IsIpad() || (interfaceOrientation == UIInterfaceOrientationPortrait);
}

#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (pressedIndex) {// Long press account
        if (buttonIndex == 0) {
            [self showAccountView:[self.conns objectAtIndex:pressedIndex.row] type:0];
        } else if (buttonIndex == 1) {
            [self.conns removeObjectAtIndex:pressedIndex.row];
            [self saveAccounts];
            [self.tableView reloadData];
        }
    } else {
        if (buttonIndex >= 0 && buttonIndex <=2) {
            [self showAccountView:nil type:buttonIndex];
        }
    }
}

#pragma mark - SSConnectionDelegate
- (void)delayOP
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate.tabbarController setSelectedIndex:TABBED_SEAFILE];

}
- (void)transferToReposView:(SeafConnection *)conn
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:conn.address forKey:@"DEAULT-SERVER"];
    [userDefaults setObject:conn.username forKey:@"DEAULT-USER"];
    [userDefaults synchronize];

    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    appdelegate.connection = conn;
    appdelegate.window.rootViewController = appdelegate.tabbarController;
    [appdelegate.window makeKeyAndVisible];
    [self performSelector:@selector(delayOP) withObject:nil afterDelay:0.01];
}

- (BOOL)goToDefaultReposView
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *server = [userDefaults objectForKey:@"DEAULT-SERVER"];
    NSString *username = [userDefaults objectForKey:@"DEAULT-USER"];
    if (server && username) {
        SeafConnection *connection = [self getConnection:server username:username];
        if (connection) {
            [self transferToReposView:connection];
            return YES;
        }
    }
    return NO;
}

- (IBAction)goToDefaultBtclicked:(id)sender
{
    [self goToDefaultReposView];
}

@end
