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
#import "M13InfiniteTabBarController.h"
#import "M13InfiniteTabBarItem.h"
#import "SVProgressHUD.h"
#import "SeafCell.h"
#import "Debug.h"


@interface SeafDisMasterViewController ()<EGORefreshTableHeaderDelegate, UIScrollViewDelegate>
@property (readonly) EGORefreshTableHeaderView* refreshHeaderView;
@property (readwrite, nonatomic) int newReplyNum;

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
    // Do any additional setup after loading the view, typically from a nib.

    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    self.detailViewController = (SeafDisDetailViewController *)[appdelegate detailViewController:TABBED_DISCUSSION];
    self.title = @"Groups";
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
    [self refresh:nil];
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
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (IsIpad()) {
        UITabBarItem *tbi = (UITabBarItem *)[appdelegate.tabbarController.tabBar.items objectAtIndex:TABBED_DISCUSSION];
        if (num > 0)
            tbi.badgeValue = [NSString stringWithFormat:@"%d", num];
        else
            tbi.badgeValue = nil;
    } else {
        M13InfiniteTabBarController *bvc = (M13InfiniteTabBarController *)appdelegate.tabbarController;
        M13InfiniteTabBarItem *tbi = [bvc.tabBarItems objectAtIndex:TABBED_DISCUSSION];
        [tbi setBadge:num];
    }
}

- (void)refreshView
{
    [self.tableView reloadData];
    [self refreshTabBarItem];
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
                             Warning("Failed to get groups ...\n");
                             [SVProgressHUD showErrorWithStatus:@"Failed to get groups ..."];
                             [self doneLoadingTableViewData];
                         }];
}

- (void)setConnection:(SeafConnection *)conn
{
    _connection = conn;
    [self.detailViewController setGroup:nil groupId:nil];
    self.detailViewController.connection = conn;
}

- (void)viewWillAppear:(BOOL)animated
{
    [self refreshView];
    [self refresh:nil];
    [super viewWillAppear:animated];
}

- (int)newReplyNum
{
    int num = 0;
    for (NSDictionary *dict in self.connection.seafGroups) {
        if ([[dict objectForKey:@"replynum"] integerValue:0] > 0 )
            num ++;
    }
    return num;
}

- (void)clearnewReplyNum
{
    for (NSMutableDictionary *dict in self.connection.seafGroups) {
        if ([[dict objectForKey:@"replynum"] integerValue:0] > 0 )
            [dict setObject:@"0" forKey:@"replynum"];
    }
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0)
        return 1;
    else
        return self.connection.seafGroups.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section{
    if (section)
        return 22;
    return 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (section == 0)
        return nil;
    NSString *text = @"Groups";
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 2, tableView.bounds.size.width - 10, 18)];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor clearColor];
    [headerView setBackgroundColor:HEADER_COLOR];
    [headerView addSubview:label];
    return headerView;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafCell";
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:@"SeafCell" owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    if (indexPath.section == 0) {
        cell.textLabel.text = @"New Replies";
        cell.detailTextLabel.text = nil;
        cell.imageView.image = [UIImage imageNamed:@"group.png"];
        int num = self.newReplyNum;
        if (num > 0)
            cell.accLabel.text = [NSString stringWithFormat:@"%d", num];
        else
            cell.accLabel.text = nil;
        return cell;
    }
    NSMutableDictionary *dict = [self.connection.seafGroups objectAtIndex:indexPath.row];
    cell.textLabel.text = [dict objectForKey:@"name"];
#if 0
    int ctime = [[dict objectForKey:@"ctime"] integerValue:0];
    NSString *creator = [dict objectForKey:@"creator"];
    creator = [creator substringToIndex:[creator indexOf:'@']];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ created at %@", creator, [SeafDateFormatter stringFromInt:ctime]];
#else
    int mtime = [[dict objectForKey:@"mtime"] integerValue:0];
    if (mtime)
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Last dicsussion at %@",  [SeafDateFormatter stringFromInt:mtime]];
    else
        cell.detailTextLabel.text = nil;
#endif
    cell.imageView.image = [UIImage imageNamed:@"group.png"];
    if ([[dict objectForKey:@"msgnum"] integerValue:0] > 0 ) {
        cell.accLabel.text = [NSString stringWithFormat:@"%lld", [[dict objectForKey:@"msgnum"] integerValue:0]];
    } else {
        cell.accLabel.text = nil;
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
    if (!IsIpad()) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate showDetailView:self.detailViewController];
    }
    if (indexPath.section == 0){
        NSString *urlStr = [self.connection.address stringByAppendingString:API_URL"/html/newreply/"];
        self.detailViewController.hiddenAddmsg = YES;
        [self.detailViewController setUrl:urlStr connection:self.connection];
        return;
    }
    self.detailViewController.hiddenAddmsg = NO;
    NSMutableDictionary *dict = [self.connection.seafGroups objectAtIndex:indexPath.row];
    NSString *gid = [dict objectForKey:@"id"];
    NSString *name = [dict objectForKey:@"name"];
    if ([[dict objectForKey:@"msgnum"] integerValue:0] > 0 ) {
        [dict setObject:@"0" forKey:@"msgnum"];
        [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self refreshTabBarItem];
    }
    [self.detailViewController setGroup:name groupId:gid];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!IsIpad()) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
    return YES;
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

@end
