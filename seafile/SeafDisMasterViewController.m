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
#import "SeafMessageCell.h"
#import "Debug.h"

#define S_ADDCONTACT NSLocalizedString(@"Add contact", @"Seafile")

@interface SeafDisMasterViewController ()<EGORefreshTableHeaderDelegate, UIScrollViewDelegate, UIActionSheetDelegate, SeafBackgroundMonitor>
@property (readonly) EGORefreshTableHeaderView* refreshHeaderView;
@property (readwrite, nonatomic) UIView *headerView;
@property (readwrite, nonatomic) NSMutableArray *msgSources;
@property (readwrite, nonatomic) NSMutableArray *addditions;
@property (strong) UIActionSheet *actionSheet;
@property (strong) UIBarButtonItem *addItem;
@property (strong) NSTimer *timer;

@end

@implementation SeafDisMasterViewController
@synthesize connection = _connection;
@synthesize refreshHeaderView = _refreshHeaderView;

- (void)awakeFromNib
{
    if (IsIpad()) {
        self.preferredContentSize = CGSizeMake(320.0, 600.0);
    }
    [super awakeFromNib];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = NSLocalizedString(@"Message", @"Seafile");

    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)])
        [self.tableView setSeparatorInset:UIEdgeInsetsMake(0, 0, 0, 0)];
    // Do any additional setup after loading the view, typically from a nib.
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    self.detailViewController = (SeafDisDetailViewController *)[appdelegate detailViewControllerAtIndex:TABBED_DISCUSSION];
    self.detailViewController.connection = _connection;
    self.tableView.rowHeight = 58;
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
    [appdelegate addBackgroundMonitor:self];
}

- (void)showAlertWithAction:(NSArray *)arr fromRect:(CGRect)rect
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *title in arr) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self handleAction:title];
        }];
        [alert addAction:action];
    }
    if (!IsIpad()){
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        }];
        [alert addAction:cancelAction];
    }
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = rect;
    [self presentViewController:alert animated:true completion:nil];
}

- (void)addContact:(id)sender
{
    if (ios8) {
        NSMutableArray *arr = [[NSMutableArray alloc] initWithObjects:S_ADDCONTACT, nil];
        for (NSDictionary *dict in self.addditions) {
            [arr addObject:[dict objectForKey:@"email"]];
        }
        [self showAlertWithAction:arr fromRect:self.addItem.customView.frame];
    } else {
        if (self.actionSheet) {
            [self.actionSheet dismissWithClickedButtonIndex:-1 animated:NO];
            self.actionSheet = nil;
        } else {
            NSString *cancelTitle = IsIpad() ? nil : NSLocalizedString(@"Cancel", @"Seafile");
            self.actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:cancelTitle destructiveButtonTitle:nil otherButtonTitles:S_ADDCONTACT, nil];
            for (NSDictionary *dict in self.addditions) {
                [self.actionSheet addButtonWithTitle:[dict objectForKey:@"email"]];
            }
            if (IsIpad())
                [self.actionSheet showFromBarButtonItem:self.addItem animated:YES];
            else
                [self.actionSheet showInView:[UIApplication sharedApplication].keyWindow];
        }
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
    NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
    if (IsIpad() && indexPath) {
        NSDictionary *dict = [self.msgSources objectAtIndex:indexPath.row];
        [self.tableView reloadData];
        long row = [self.msgSources indexOfObject:dict];
        if (row != NSNotFound)
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
    } else
        [self.tableView reloadData];
}

- (void)refreshBadge
{
    NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
    if (!indexPath) return;
    SeafMessageCell *cell = (SeafMessageCell *)[self.tableView cellForRowAtIndexPath:indexPath];
    NSMutableDictionary *dict = [self.msgSources objectAtIndex:indexPath.row];
    [self checkCellBadge:cell info:dict];
    [self refreshTabBarItem];
}

- (void)updateLastMessage
{
    NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
    SeafMessageCell *cell = (SeafMessageCell *)[self.tableView cellForRowAtIndexPath:indexPath];
    NSMutableDictionary *dict = [self.msgSources objectAtIndex:indexPath.row];
    cell.detailLabel.text = [[dict objectForKey:@"lastmsg"] stringValue];
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
    [_connection getSeafGroupAndContacts:^(NSHTTPURLResponse *response, id JSON) {
        @synchronized(self) {
            [self refreshView];
            [self doneLoadingTableViewData];
        }
    }
    failure:^(NSHTTPURLResponse *response, NSError *error) {
        Warning("Failed to get groups ...error=%ld\n", (long)error.code);
        [self doneLoadingTableViewData];
    }];
}

- (void)refresh:(id)sender
{
    [_connection getSeafGroupAndContacts:^(NSHTTPURLResponse *response, id JSON) {
        @synchronized(self) {
            Debug("Success to get groups ...\n");
            [self refreshView];
            [self doneLoadingTableViewData];
            [self.connection performSelector:@selector(downloadAvatars:) withObject:[NSNumber numberWithBool:YES] afterDelay:2.0];
        }
    }
    failure:^(NSHTTPURLResponse *response, NSError *error) {
        Warning("Failed to get groups ...error=%ld\n", (long)error.code);
        if (self.isVisible && error.code != NSURLErrorCancelled && error.code != 102) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to get groups ...", @"Seafile")];
        }
        [self doneLoadingTableViewData];
    }];
}

- (void)startTimer
{
    Debug("Start timer");
    if (_timer != nil)
        [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:5 * 60
                                     target:self
                                   selector:@selector(tick:)
                                   userInfo:nil
                                    repeats:YES];
}

- (void)stopTimer
{
    Debug("Stop timer");
    if (_timer != nil)
        [_timer invalidate];
    _timer = nil;
}

- (void)tick:(NSTimer *)timer
{
    if (self.connection)
        [self refreshBackground:nil];
}

- (void)setConnection:(SeafConnection *)conn
{
    _connection = conn;
    [self.detailViewController setConnection:conn];
    [self refreshView];
    [self performSelector:@selector(refreshBackground:) withObject:nil afterDelay:1.5f];
}

- (void)viewWillAppear:(BOOL)animated
{
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
- (void)checkCellBadge:(SeafMessageCell *)cell info:(NSDictionary *)dict
{
    if ([[dict objectForKey:@"msgnum"] integerValue:0] > 0 ) {
        cell.badgeLabel.text = [NSString stringWithFormat:@"%lld", [[dict objectForKey:@"msgnum"] integerValue:0]];
        cell.badgeLabel.hidden = NO;
        cell.badgeImage.hidden = NO;
    } else {
        cell.badgeLabel.hidden = YES;
        cell.badgeImage.hidden = YES;
    }
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafMessageCell";
    SeafMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
        cell.selectedBackgroundView = [[UIView alloc] initWithFrame:cell.frame];
        cell.selectedBackgroundView.backgroundColor = [UIColor colorWithRed:252.0/256 green:171.0/256 blue:128.0/256 alpha:1.0];
    }
    NSMutableDictionary *dict = nil;
    @try {
        dict = [self.msgSources objectAtIndex:indexPath.row];
    } @catch(NSException *exception) {
        return cell;
    }
    cell.textLabel.text = [dict objectForKey:@"name"];
    long long mtime = [[dict objectForKey:@"mtime"] integerValue:0];
    cell.timestampLabel.text = mtime ? [NSString stringWithFormat:@"%@", [SeafDateFormatter stringFromLongLong:mtime]] : nil;
    cell.detailLabel.text = [[dict objectForKey:@"lastmsg"] stringValue];

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
    cell.imageView.image = [JSAvatarImageFactory avatarImage:[UIImage imageWithContentsOfFile:avatar] croppedToCircle:YES];
    [self checkCellBadge:cell info:dict];
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
    NSMutableDictionary *dict;
    @try {
        dict = [self.msgSources objectAtIndex:indexPath.row];
    } @catch(NSException *exception) {
        [self performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
        return;
    }
    Debug("select %@", dict);
    if (self.detailViewController.msgtype == MSG_REPLY && dict != self.detailViewController.info) {
        [self refreshView];
    }

    long long msgtype = [[dict objectForKey:@"type"] integerValue:MSG_NONE];
    if (!IsIpad()) {
        self.detailViewController = appdelegate.msgDetailView;
        [self.detailViewController setMsgtype:(int)msgtype info:dict];
        [self.navigationController pushViewController:self.detailViewController animated:YES];
    } else {
        [self.detailViewController setMsgtype:(int)msgtype info:dict];
        [self.detailViewController.navigationController popToRootViewControllerAnimated:NO];
    }
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

#pragma mark - UIActionSheetDelegate
- (void)handleAction:(NSString *)title
{
    if ([S_ADDCONTACT isEqualToString:title]) {
        [self popupInputView:S_ADDCONTACT placeholder:NSLocalizedString(@"Email", @"Seafile") secure:false handler:^(NSString *input) {
            NSString *email = input;
            if (!email || email.length < 1) {
                [self alertWithTitle:NSLocalizedString(@"Username must not be empty", @"Seafile")];
                return;
            }
            NSArray* items = [email componentsSeparatedByString:@"@"];
            if (items.count != 2 || [[items objectAtIndex:0] length] < 1 || [[items objectAtIndex:1] length] < 1) {
                [self alertWithTitle:NSLocalizedString(@"Invalid email", @"Seafile")];
                return;
            }
            NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
            [dict setObject:[NSString stringWithFormat:@"%d", MSG_USER] forKey:@"type"];
            [dict setObject:email forKey:@"email"];
            [dict setObject:email forKey:@"name"];
            NSString *timestamp = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];
            [dict setObject:timestamp forKey:@"mtime"];
            [dict setObject:@"0" forKey:@"msgnum"];
            [self.msgSources addObject:dict];
            [self reloadData];
        }];
    } else {
        NSDictionary *selected = nil;
        for (NSDictionary *dict in self.addditions) {
            if ([title isEqualToString:[dict objectForKey:@"email"]]) {
                selected = dict;
                [self.msgSources addObject:dict];
                [self reloadData];
            }
        }
        if (selected)
            [self.addditions removeObject:selected];
    }
}
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)bIndex
{
    self.actionSheet = nil;
    if (bIndex < 0 || bIndex >= actionSheet.numberOfButtons)
        return;
    NSString *title = [actionSheet buttonTitleAtIndex:bIndex];
    [self handleAction:title];
}

#pragma -mark SeafBackgroundMonitor
- (void)enterBackground
{
    [self stopTimer];
}
- (void)enterForeground
{
    [self startTimer];
}

@end
