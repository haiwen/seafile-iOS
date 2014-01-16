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
#import "SeafBase.h"
#import "ExtentedString.h"
#import "SVProgressHUD.h"
#import "SeafCell.h"
#import "Debug.h"


@interface SeafDisMasterViewController ()<EGORefreshTableHeaderDelegate, UIScrollViewDelegate>
@property (readonly) EGORefreshTableHeaderView* refreshHeaderView;
@property (readwrite, nonatomic) UIView *headerView;
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
    NSArray *views = [[NSBundle mainBundle] loadNibNamed:@"SeafStartFooterView" owner:self options:nil];
    ColorfulButton *bt = [views objectAtIndex:0];
    bt.frame = CGRectMake(0,0, self.tableView.frame.size.width, 50);
    self.headerView.backgroundColor = [UIColor clearColor];
    [bt addTarget:self action:@selector(newReplies:) forControlEvents:UIControlEventTouchUpInside];
    bt.layer.cornerRadius = 0;
    [bt.layer setBorderColor:[[UIColor colorWithRed:224/255.0 green:224/255.0 blue:224/255.0 alpha:1.0] CGColor]];
    [bt setHighColor:[UIColor colorWithRed:244/255.0 green:244/255.0 blue:244/255.0 alpha:1.0] lowColor:[UIColor colorWithRed:244/255.0 green:244/255.0 blue:244/255.0 alpha:1.0]];
    [bt setTitleColor:[UIColor colorWithRed:112/255.0 green:112/255.0 blue:112/255.0 alpha:1.0] forState:UIControlStateNormal];

    self.headerView = bt;
    [self startTimer];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)refreshTabBarItem
{
    int num = 0;
    for (NSDictionary *dict in self.connection.seafGroups) {
        if ([[dict objectForKey:@"msgnum"] integerValue:0] > 0 )
            num ++;
    }
    for (NSDictionary *dict in self.connection.seafContacts) {
        if ([[dict objectForKey:@"msgnum"] integerValue:0] > 0 )
            num ++;
    }

    UITabBarItem *tbi = nil;
    if (IsIpad()) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        tbi = (UITabBarItem *)[appdelegate.tabbarController.tabBar.items objectAtIndex:TABBED_DISCUSSION];
    } else
        tbi = self.navigationController.tabBarItem;
    Debug("num=%d, tbi=%@, %@\n", num, tbi, tbi.title);
    tbi.badgeValue = num > 0 ? [NSString stringWithFormat:@"%d", num] : nil;
}

- (void)refreshView
{
    if (self.connection.newreply > 0) {
        ColorfulButton *bt = (ColorfulButton *)self.headerView;
        NSString *text = [NSString stringWithFormat:NSLocalizedString(@"%d new replies", @"%d new replies"), self.connection.newreply];
        [bt setTitle:text forState:UIControlStateNormal];
        [bt setTitle:text forState:UIControlStateSelected];
        [bt setTitle:text forState:UIControlStateHighlighted];
        self.tableView.tableHeaderView = self.headerView;
    } else
        self.tableView.tableHeaderView = nil;
    [self.tableView reloadData];
    [self refreshTabBarItem];
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate checkIconBadgeNumber];
}

- (void)refreshBackground:(id)sender
{
    [_connection getSeafGroups:^(NSHTTPURLResponse *response, id JSON, NSData *data) {
        @synchronized(self) {
            [self refreshView];
            [self doneLoadingTableViewData];
        }
    }
                       failure:^(NSHTTPURLResponse *response, NSError *error, id JSON) {
                           Warning("Failed to get groups ...error=%d\n", error.code);
                           [self doneLoadingTableViewData];
                       }];
}

- (void)refresh:(id)sender
{
    [_connection getSeafGroups:^(NSHTTPURLResponse *response, id JSON, NSData *data) {
        @synchronized(self) {
            Debug("Success to get groups ...\n");
            [self refreshView];
            [self doneLoadingTableViewData];
        }
    }
                       failure:^(NSHTTPURLResponse *response, NSError *error, id JSON) {
                           Warning("Failed to get groups ...error=%d\n", error.code);
                           if (self.view.window && error.code != NSURLErrorCancelled && error.code != 102) {
                               [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to get groups ...", @"Failed to get groups ...")];
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
    if (self.connection)
        [self refreshBackground:nil];
}

- (void)setConnection:(SeafConnection *)conn
{
    _connection = conn;
    [self.detailViewController setUrl:Nil connection:conn title:nil];
    [self refresh:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [self refreshView];
    [super viewWillAppear:animated];
}

- (void)clearnewReplyNum
{
    self.connection.newreply = 0;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate checkIconBadgeNumber];
}

#pragma mark - Table View
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0)
        return self.connection.seafGroups.count;
    return self.connection.seafContacts.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    int row = indexPath.row;
    NSString *CellIdentifier = @"SeafCell";
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:@"SeafCell" owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    NSMutableDictionary *dict = (indexPath.section == 0)? [self.connection.seafGroups objectAtIndex:row] : [self.connection.seafContacts objectAtIndex:row];
    cell.textLabel.text = [dict objectForKey:@"name"];
    long long mtime = [[dict objectForKey:@"mtime"] integerValue:0];
    if (mtime)
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@",  [SeafDateFormatter stringFromLongLong:mtime]];
    else
        cell.detailTextLabel.text = nil;

    if (indexPath.section == 0)
        cell.imageView.image = [UIImage imageNamed:@"group.png"];
    else
        cell.imageView.image = [UIImage imageNamed:@"account.png"];
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
    if (!IsIpad())
        [appdelegate showDetailView:self.detailViewController];

    int row = indexPath.row;
    if (indexPath.section == 0) {
        NSMutableDictionary *dict = [self.connection.seafGroups objectAtIndex:row];
        NSString *gid = [dict objectForKey:@"id"];
        NSString *name = [dict objectForKey:@"name"];
        if ([[dict objectForKey:@"msgnum"] integerValue:0] > 0 ) {
            [dict setObject:@"0" forKey:@"msgnum"];
            [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
        }
        NSString *url = [self.connection.address stringByAppendingFormat:API_URL"/html/discussions/%@/", gid];
        self.detailViewController.msgtype = MSG_GROUP;
        [self.detailViewController setUrl:url connection:self.connection title:name];
    } else {
        NSMutableDictionary *dict = [self.connection.seafContacts objectAtIndex:row];
        NSString *name = [dict objectForKey:@"name"];
        NSString *email = [dict objectForKey:@"email"];
        if ([[dict objectForKey:@"msgnum"] integerValue:0] > 0 ) {
            self.connection.umsgnum -= [[dict objectForKey:@"msgnum"] integerValue:0];
            [dict setObject:@"0" forKey:@"msgnum"];
            [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
            [appdelegate checkIconBadgeNumber];
        }
        NSString *url = [self.connection.address stringByAppendingFormat:API_URL"/html/usermsgs/%@/", email];
        self.detailViewController.msgtype = MSG_USER;
        [self.detailViewController setUrl:url connection:self.connection title:name];
    }
    [self refreshTabBarItem];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSString *text = nil;
    if (section == 0) {
        text = NSLocalizedString(@"Groups", nil);
    } else {
        text = NSLocalizedString(@"Contacts", nil);
    }
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, tableView.bounds.size.width - 10, 18)];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor clearColor];
    [headerView setBackgroundColor:HEADER_COLOR];
    [headerView addSubview:label];
    return headerView;
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

- (IBAction)newReplies:(id)sender
{
    [self clearnewReplyNum];
    NSString *urlStr = [self.connection.address stringByAppendingString:API_URL"/html/newreply/"];
    self.detailViewController.msgtype = MSG_NEW_REPLY;
    [self.detailViewController setUrl:urlStr connection:self.connection title:NSLocalizedString(@"New replies", nil)];
    return;
}

@end
