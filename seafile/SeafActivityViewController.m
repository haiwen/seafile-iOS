//
//  SeafActivityViewController.m
//  seafilePro
//
//  Created by Wang Wei on 5/18/13.
//  Copyright (c) 2013 Seafile Ltd. All rights reserved.
//

#import <UIScrollView+SVPullToRefresh.h>
#import <UIScrollView+SVInfiniteScrolling.h>

#import "SeafActivityViewController.h"
#import "SeafAppDelegate.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "SeafEventCell.h"
#import "SeafDateFormatter.h"
#import "ExtentedString.h"
#import "Debug.h"

enum {
    ACTIVITY_INIT = 0,
    ACTIVITY_START,
    ACTIVITY_END,
};

@interface SeafActivityViewController ()
@property int state;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *loadingView;
@property (strong) NSArray *events;
@property BOOL eventsMore;
@property int eventsOffset;

@property NSMutableDictionary *eventDetails;
@end

@implementation SeafActivityViewController
@synthesize connection = _connection;


- (void)refresh:(id)sender
{
    [self showLoadingView];
    [self moreEvents:0];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)])
        [self.tableView setSeparatorInset:UIEdgeInsetsMake(0, 0, 0, 0)];
    // Do any additional setup after loading the view from its nib.
    self.title = NSLocalizedString(@"Activities", @"Seafile");
    self.navigationItem.rightBarButtonItem = [self getBarItemAutoSize:@"refresh".navItemImgName action:@selector(refresh:)];
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    self.tableView.rowHeight = 60;
    self.eventsMore = true;
    self.eventsOffset = 0;
    _eventDetails = [NSMutableDictionary new];

    __weak typeof(self) weakSelf = self;
    [self.tableView addPullToRefreshWithActionHandler:^{
        [weakSelf moreEvents:weakSelf.eventsOffset];
    } position:SVPullToRefreshPositionBottom];
}

- (void)reloadData
{
    [self.tableView.pullToRefreshView stopAnimating];
    self.tableView.showsPullToRefresh = _eventsMore;
    [self dismissLoadingView];
    [self.tableView reloadData];
}
- (void)moreEvents:(int)offset
{
    NSString *url = [NSString stringWithFormat:API_URL"/events/?start=%d", _eventsOffset];
    [_connection sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        Debug("Success to get events %d: %@", _eventsOffset, JSON);
        NSArray *arr = [JSON objectForKey:@"events"];
        if (offset == 0)
            _events = nil;

        NSMutableArray *marray = [NSMutableArray new];
        [marray addObjectsFromArray:_events];
        [marray addObjectsFromArray:arr];
        _events = marray;
        _eventsMore = [[JSON objectForKey:@"more"] boolValue];
        _eventsOffset = [[JSON objectForKey:@"more_offset"] intValue];
        Debug("%d events, more:%d, offset:%d", _events.count, _eventsMore, _eventsOffset);
        [self reloadData];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        [self dismissLoadingView];
        [self.tableView.pullToRefreshView stopAnimating];
        if (self.isVisible)
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to get events", @"Seafile")];
    }];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    _eventDetails = [NSMutableDictionary new];
    // Dispose of any resources that can be recreated.
}

- (void)setConnection:(SeafConnection *)connection
{
    if (IsIpad())
        [self.navigationController popToRootViewControllerAnimated:NO];

    self.state = ACTIVITY_INIT;
    if (_connection != connection) {
        _connection = connection;
        _events = nil;
        self.eventsMore = true;
        self.eventsOffset = 0;
        _eventDetails = [NSMutableDictionary new];
        [self.tableView reloadData];
    }
}

- (void)showLoadingView
{
    if (!self.loadingView) {
        self.loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        self.loadingView.color = [UIColor darkTextColor];
        self.loadingView.hidesWhenStopped = YES;
        [self.view addSubview:self.loadingView];
    }
    self.loadingView.center = self.view.center;
    self.loadingView.frame = CGRectMake(self.loadingView.frame.origin.x, (self.view.frame.size.height-self.loadingView.frame.size.height)/2, self.loadingView.frame.size.width, self.loadingView.frame.size.height);
    [self.loadingView startAnimating];
}

- (void)dismissLoadingView
{
    [self.loadingView stopAnimating];
}

- (void)viewWillAppear:(BOOL)animated
{
    if (!_events) {
        [self moreEvents:0];
        [self showLoadingView];
    }
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [SVProgressHUD dismiss];
    [super viewWillDisappear:animated];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 1)
        return 1;
    return _events.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafEventCell";
    SeafEventCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    NSDictionary *event = [_events objectAtIndex:indexPath.row];
    NSString *path = [[NSBundle mainBundle] pathForResource:@"account" ofType:@"png"];
    cell.accountImageView.image = [UIImage imageWithContentsOfFile:path];

    cell.textLabel.text = [event objectForKey:@"desc"];
    cell.repoNameLabel.text = [event objectForKey:@"repo_name"];
    cell.authorLabel.text = [event objectForKey:@"nick"];
    long timestamp = [[event objectForKey:@"time"] longValue];
    cell.timeLabel.text = [SeafDateFormatter stringFromLongLong:timestamp];

    cell.backgroundColor = [UIColor clearColor];
    return cell;
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}

#pragma mark - Table view delegate
- (void)showEvent:(NSDictionary *)event detail:(NSDictionary *)detail {
    Debug(".... event%@, detail:%@", event, detail);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    Debug("...index: %d %d", indexPath.section, indexPath.row);
    if (indexPath.section == 1) {
        return [self moreEvents:_eventsOffset];
    }
    if (indexPath.row >= _events.count)
        return;
    NSDictionary *event = [_events objectAtIndex:indexPath.row];
    NSString *repoId = [event objectForKey:@"repo_id"];
    NSString *commitId = [event objectForKey:@"commit_id"];
    NSString *url = [NSString stringWithFormat:API_URL"/repo_history_changes/%@/?commit_id=%@", repoId, commitId];
    
    NSDictionary *detail = [_eventDetails objectForKey:url];
    if (detail)
        return [self showEvent:event detail:detail];

    [_connection sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        Debug("Success to get event: %@", JSON);
        NSDictionary *detail = (NSDictionary *)JSON;
        [_eventDetails setObject:detail forKey:url];
        [self showEvent:event detail:detail];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        Warning("Failed to get commit detail.");
    }];
}

- (void)openFile:(NSString *)path inRepo:(NSString *)repoId {
    
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    Debug("Request %@\n", request.URL);
    NSString *urlStr = request.URL.absoluteString;
    if ([urlStr hasPrefix:@"api://"]) {
        if (self.navigationController.viewControllers.count != 1) return NO;
        NSString *path = @"/";
        NSRange range;
        NSRange foundRange = [urlStr rangeOfString:@"/repo/" options:NSCaseInsensitiveSearch];
        if (foundRange.location == NSNotFound)
            return NO;
        range.location = foundRange.location + foundRange.length;
        range.length = 36;
        NSString *repo_id = [urlStr substringWithRange:range];

        foundRange = [urlStr rangeOfString:@"files/?p=" options:NSCaseInsensitiveSearch];
        if (foundRange.location != NSNotFound) {
            path = [urlStr substringFromIndex:(foundRange.location+foundRange.length)];
        }
        path = [path stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        Debug("repo=%@, path=%@\n", repo_id, path);
        if (path.length <= 1) return NO;

        SeafFile *sfile = [[SeafFile alloc] initWithConnection:self.connection oid:nil repoId:repo_id name:path.lastPathComponent path:path mtime:0 size:0];
        SeafDetailViewController *detailvc;
        if (IsIpad()) {
            detailvc = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
        } else {
            detailvc = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
        }

        @synchronized(self.navigationController) {
            if (self.navigationController.viewControllers.count == 1) {
                [self.navigationController pushViewController:detailvc animated:YES];
                sfile.delegate = detailvc;
                [detailvc setPreViewItem:sfile master:nil];
            }
        }
    }
    return NO;
}

@end
