//
//  SeafDisMasterViewController.m
//  Discussion
//
//  Created by Wang Wei on 5/21/13.
//  Copyright (c) 2013 Wang Wei. All rights reserved.
//

#import "SeafDisMasterViewController.h"
#import "SeafDisDetailViewController.h"
#import "SeafAppDelegate.h"

#import "SeafDateFormatter.h"
#import "UIViewController+Extend.h"
#import "SeafBase.h"
#import "ExtentedString.h"
#import "SVProgressHUD.h"
#import "SeafCell.h"
#import "Debug.h"

#define S_ADDCONTACT NSLocalizedString(@"Add contact", @"Seafile")

@interface SeafDisMasterViewController ()<EGORefreshTableHeaderDelegate, UIScrollViewDelegate, UIActionSheetDelegate>
@property (readonly) EGORefreshTableHeaderView* refreshHeaderView;
@property (readwrite, nonatomic) UIView *headerView;
@property (readwrite, nonatomic) NSMutableArray *msgSources;
@property (readwrite, nonatomic) NSMutableArray *addditions;
@property (strong) UIActionSheet *actionSheet;
@property (strong) UIBarButtonItem *addItem;

@end

@implementation SeafDisMasterViewController
@synthesize connection = _connection;
@synthesize refreshHeaderView = _refreshHeaderView;

- (void)awakeFromNib
{
    if (IsIpad()) {
        self.clearsSelectionOnViewWillAppear = NO;
        self.contentSizeForViewInPopover = CGSizeMake(320.0, 600.0);
    }
    [super awakeFromNib];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)])
        [self.tableView setSeparatorInset:UIEdgeInsetsMake(0, 0, 0, 0)];
    // Do any additional setup after loading the view, typically from a nib.
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    self.detailViewController = (SeafDisDetailViewController *)[appdelegate detailViewController:TABBED_DISCUSSION];
    self.tableView.rowHeight = 50;
    self.detailViewController.connection = _connection;
    if (_refreshHeaderView == nil) {
        EGORefreshTableHeaderView *view = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.tableView.bounds.size.height, self.view.frame.size.width, self.tableView.bounds.size.height)];
        view.delegate = self;
        [self.tableView addSubview:view];
        _refreshHeaderView = view;
    }
    [_refreshHeaderView refreshLastUpdatedDate];
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    self.addItem = [self getBarItem:@"plus".navItemImgName action:@selector(addContact:)size:20];
    self.navigationItem.rightBarButtonItem = self.addItem;
    [self startTimer];
}

- (void)addContact:(id)sender
{
    if (self.actionSheet) {
        [self.actionSheet dismissWithClickedButtonIndex:-1 animated:NO];
        self.actionSheet = nil;
    } else {
        NSString *cancelTitle = IsIpad() ? nil : NSLocalizedString(@"Cancel", @"Seafile");
        self.actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:cancelTitle destructiveButtonTitle:nil otherButtonTitles:S_ADDCONTACT, nil];
        for (NSDictionary *dict in self.addditions) {
            [self.actionSheet addButtonWithTitle:[dict objectForKey:@"email"]];
        }
        [self.actionSheet showFromBarButtonItem:self.addItem animated:YES];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)refreshTabBarItem
{
    long long num = self.connection.newmsgnum;
    UITabBarItem *tbi = nil;
    if (IsIpad()) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        tbi = (UITabBarItem *)[appdelegate.tabbarController.tabBar.items objectAtIndex:TABBED_DISCUSSION];
    } else
        tbi = self.navigationController.tabBarItem;
    tbi.badgeValue = num > 0 ? [NSString stringWithFormat:@"%lld", num] : nil;
    [(SeafAppDelegate *)[[UIApplication sharedApplication] delegate] checkIconBadgeNumber];
}
- (void)reloadData
{
    [self.msgSources sortUsingComparator:(NSComparator)^NSComparisonResult(id obj1, id obj2){
        long long x = [[obj1 objectForKey:@"mtime"] integerValue:0];
        long long y = [[obj2 objectForKey:@"mtime"] integerValue:0];
        if (x < y) {
            return (NSComparisonResult)NSOrderedDescending;
        }
        if (x > y) {
            return (NSComparisonResult)NSOrderedAscending;
        }
        return (NSComparisonResult)NSOrderedSame;
    }];
    [self.tableView reloadData];
}

- (void)refreshView
{
    self.msgSources = [[NSMutableArray alloc] initWithArray:self.connection.seafGroups];
    self.addditions = [[NSMutableArray alloc] init];
    for (NSDictionary *dict in self.connection.seafContacts) {
        if ([[dict objectForKey:@"mtime"] integerValue:0] > 0)
            [self.msgSources addObject:dict];
        else
            [self.addditions addObject:dict];
    }
    for (NSDictionary *dict in self.connection.seafReplies) {
        if ([[dict objectForKey:@"msgnum"] integerValue:0] > 0)
            [self.msgSources addObject:dict];
    }
    Debug("group=%lu, user=%lu, reply=%lu, total=%lu", (unsigned long)self.connection.seafGroups.count, (unsigned long)self.connection.seafContacts.count, (unsigned long)self.connection.seafReplies.count, (unsigned long)self.msgSources.count);
   
    [self reloadData];
    [self refreshTabBarItem];
}

- (void)refreshBackground:(id)sender
{
    [_connection getSeafGroupAndContacts:^(NSHTTPURLResponse *response, id JSON, NSData *data) {
        @synchronized(self) {
            [self refreshView];
            [self doneLoadingTableViewData];
        }
    }
    failure:^(NSHTTPURLResponse *response, NSError *error, id JSON) {
        Warning("Failed to get groups ...error=%ld\n", (long)error.code);
        [self doneLoadingTableViewData];
    }];
}

- (void)refresh:(id)sender
{
    [_connection getSeafGroupAndContacts:^(NSHTTPURLResponse *response, id JSON, NSData *data) {
        @synchronized(self) {
            Debug("Success to get groups ...\n");
            [self refreshView];
            [self doneLoadingTableViewData];
        }
    }
    failure:^(NSHTTPURLResponse *response, NSError *error, id JSON) {
        Warning("Failed to get groups ...error=%ld\n", (long)error.code);
        if (self.isVisible && error.code != NSURLErrorCancelled && error.code != 102) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to get groups ...", @"Seafile")];
        }
        [self doneLoadingTableViewData];
    }];
}

- (void)startTimer
{
    [NSTimer scheduledTimerWithTimeInterval:5*60
                                     target:self
                                   selector:@selector(tick:)
                                   userInfo:nil
                                    repeats:YES];
}

- (void)tick:(NSTimer *)timer
{
    //if (self.connection)
    //    [self refreshBackground:nil];
}

- (void)setConnection:(SeafConnection *)conn
{
    _connection = conn;
    [self.detailViewController setConnection:conn];
    [self performSelector:@selector(refresh:) withObject:nil afterDelay:1.5f];
}

- (void)viewWillAppear:(BOOL)animated
{
    [self refreshView];
    [super viewWillAppear:animated];
}

#pragma mark - Table View
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.msgSources.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafCell";
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:@"SeafCell" owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    NSMutableDictionary *dict = [self.msgSources objectAtIndex:indexPath.row];
    cell.textLabel.text = [dict objectForKey:@"name"];
    long long mtime = [[dict objectForKey:@"mtime"] integerValue:0];
    cell.detailTextLabel.text = mtime ? [NSString stringWithFormat:@"%@", [SeafDateFormatter stringFromLongLong:mtime]] : nil;
    NSString *avatar = nil;
    switch ([[dict objectForKey:@"type"] integerValue:-1]) {
        case MSG_GROUP:
            avatar = [self.connection avatarForGroup:[dict objectForKey:@"id"]];
            break;
        case MSG_USER:
            avatar = [self.connection avatarForEmail:[dict objectForKey:@"email"]];
            break;
        case MSG_REPLY:
            avatar = [self.connection avatarForEmail:[dict objectForKey:@"reply_from"]];
            break;
        default:
            Warning(@"Unknown msg type %@", [dict objectForKey:@"type"]);
            break;
    }
    cell.imageView.image = [JSAvatarImageFactory avatarImage:[UIImage imageWithContentsOfFile:avatar] croppedToCircle:NO];
    if ([[dict objectForKey:@"msgnum"] integerValue:0] > 0 ) {
        cell.badgeLabel.text = [NSString stringWithFormat:@"%lld", [[dict objectForKey:@"msgnum"] integerValue:0]];
        cell.badgeLabel.hidden = NO;
        cell.badgeImage.hidden = NO;
    } else {
        cell.badgeLabel.hidden = YES;
        cell.badgeImage.hidden = YES;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    // The table view should not be re-orderable.
    return NO;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    NSMutableDictionary *dict = [self.msgSources objectAtIndex:indexPath.row];
    Debug("dict=%@", dict);
    if (IsIpad() && self.detailViewController.msgtype == MSG_REPLY) {
        if (dict != self.detailViewController.info)
            [self refreshView];
    } else {
        [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self refreshTabBarItem];
    }
    long long msgtype = [[dict objectForKey:@"type"] integerValue:-1];
    [self.detailViewController setMsgtype:(int)msgtype info:dict];
    if (!IsIpad())    [appdelegate showDetailView:self.detailViewController];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return IsIpad() || (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)doneLoadingTableViewData
{
    [_refreshHeaderView egoRefreshScrollViewDataSourceDidFinishedLoading:self.tableView];
}

#pragma mark - mark UIScrollViewDelegate Methods
- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [_refreshHeaderView egoRefreshScrollViewDidScroll:scrollView];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    [_refreshHeaderView egoRefreshScrollViewDidEndDragging:scrollView];
}

#pragma mark - EGORefreshTableHeaderDelegate Methods
- (void)egoRefreshTableHeaderDidTriggerRefresh:(EGORefreshTableHeaderView*)view
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (![appdelegate checkNetworkStatus]) {
        [self performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:0.1];
        return;
    }
    [self refresh:nil];
}

- (BOOL)egoRefreshTableHeaderDataSourceIsLoading:(EGORefreshTableHeaderView*)view
{
    return NO;
}

- (NSDate*)egoRefreshTableHeaderDataSourceLastUpdated:(EGORefreshTableHeaderView*)view
{
    return [NSDate date];
}

- (void)popupInputView:(NSString *)title placeholder:(NSString *)tip
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"Seafile") otherButtonTitles:NSLocalizedString(@"OK", @"Seafile"), nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *textfield = [alert textFieldAtIndex:0];
    textfield.placeholder = tip;
    textfield.autocorrectionType = UITextAutocorrectionTypeNo;
    [alert show];
}
#pragma mark - UIAlertViewDelegate
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) {
        return;
    } else {
        NSString *email = [alertView textFieldAtIndex:0].text;
        if (!email || email.length < 1) {
            [self alertWithMessage:NSLocalizedString(@"Username must not be empty", @"Seafile")];
            return;
        }
        NSArray* items = [email componentsSeparatedByString:@"@"];
        if (items.count != 2 || [[items objectAtIndex:0] length] < 1 || [[items objectAtIndex:1] length] < 1) {
            [self alertWithMessage:NSLocalizedString(@"Invalid email", @"Seafile")];
            return;
        }
        NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
        [dict setObject:[NSString stringWithFormat:@"%d", MSG_USER] forKey:@"type"];
        [dict setObject:email forKey:@"email"];
        [dict setObject:email forKey:@"name"];
        NSString *timestamp = [NSString stringWithFormat:@"%d", (int)[[NSDate date] timeIntervalSince1970]];
        [dict setObject:timestamp forKey:@"mtime"];
        [dict setObject:@"0" forKey:@"msgnum"];
        [self.msgSources addObject:dict];
        [self.tableView reloadData];
    }
}
#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)bIndex
{
    self.actionSheet = nil;
    if (bIndex < 0 || bIndex >= actionSheet.numberOfButtons)
        return;
    NSString *title = [actionSheet buttonTitleAtIndex:bIndex];
    if ([S_ADDCONTACT isEqualToString:title]) {
        [self popupInputView:S_ADDCONTACT placeholder:NSLocalizedString(@"Email", @"Seafile")];
    } else {
        for (NSDictionary *dict in self.addditions) {
            if ([title isEqualToString:[dict objectForKey:@"email"]]) {
                [self.addditions removeObject:dict];
                [self.msgSources addObject:dict];
                [self reloadData];
            }
        }
    }
}

@end
