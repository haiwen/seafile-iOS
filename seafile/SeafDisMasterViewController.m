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
    [super viewWillAppear:animated];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.connection.seafGroups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafCell";
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:@"SeafCell" owner:self options:nil];
        cell = [cells objectAtIndex:0];
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
