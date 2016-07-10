//
//  SeafActivityViewController.m
//  seafilePro
//
//  Created by Wang Wei on 5/18/13.
//  Copyright (c) 2013 Seafile Ltd. All rights reserved.
//

#import "UIScrollView+SVPullToRefresh.h"
#import "UIScrollView+SVInfiniteScrolling.h"
#import <SDWebImage/UIImageView+WebCache.h>

#import "SeafActivityViewController.h"
#import "SeafAppDelegate.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "SeafEventCell.h"
#import "SeafRepos.h"
#import "SeafBase.h"

#import "SeafDateFormatter.h"
#import "ExtentedString.h"
#import "Debug.h"

typedef void (^ModificationHandler)(NSString *repoId, NSString *path);

@interface SeafActivityViewController ()
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *loadingView;
@property (strong) NSArray *events;
@property BOOL eventsMore;
@property int eventsOffset;

@property NSMutableDictionary *eventDetails;
@property UIImage *defaultAccountImage;
@property NSDictionary *opsMap;
@property NSDictionary *prefixMap;
@property NSDictionary *typesMap;

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
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60.0;
    self.eventsMore = true;
    self.eventsOffset = 0;
    _eventDetails = [NSMutableDictionary new];
    _defaultAccountImage = [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"account" ofType:@"png"]];

    NSArray *keys = [NSArray arrayWithObjects:
                     @"Added",
                     @"Added directory",
                     @"Added or modified",
                     @"Deleted", @"Modified",
                     @"Moved",
                     @"Moved directory",
                     @"Removed",
                     @"Removed directory",
                     @"Renamed",
                     @"Renamed directory",
                     nil];
    NSArray *values = [NSArray arrayWithObjects:
                       NSLocalizedString(@"Added", @"Seafile"),
                       NSLocalizedString(@"Added directory", @"Seafile"),
                       NSLocalizedString(@"Added or modified", @"Seafile"),
                       NSLocalizedString(@"Deleted", @"Seafile"),
                       NSLocalizedString(@"Modified", @"Seafile"),
                       NSLocalizedString(@"Moved", @"Seafile"),
                       NSLocalizedString(@"Moved directory", @"Seafile"),
                       NSLocalizedString(@"Removed", @"Seafile"),
                       NSLocalizedString(@"Removed directory", @"Seafile"),
                       NSLocalizedString(@"Renamed", @"Seafile"),
                       NSLocalizedString(@"Renamed directory", @"Seafile"),
                       nil];

    self.opsMap = [NSDictionary dictionaryWithObjects:values forKeys:keys];

    NSArray *keys2 = [NSArray arrayWithObjects:
                      @"Reverted library to status at",
                      @"Recovered deleted directory",
                      @"Changed library name or description",
                      nil];
    NSArray *values2 = [NSArray arrayWithObjects:
                       NSLocalizedString(@"Reverted library to status at", @"Seafile"),
                       NSLocalizedString(@"Recovered deleted directory", @"Seafile"),
                       NSLocalizedString(@"Changed library name or description", @"Seafile"),
                       nil];
    self.prefixMap = [NSDictionary dictionaryWithObjects:values2 forKeys:keys2];
    self.typesMap = [NSDictionary dictionaryWithObjectsAndKeys:
                     NSLocalizedString(@"files", @"Seafile"), @"files",
                     NSLocalizedString(@"directories", @"Seafile"), @"directories",
                     nil];
    __weak typeof(self) weakSelf = self;
    [self.tableView addInfiniteScrollingWithActionHandler:^{
        [weakSelf moreEvents:weakSelf.eventsOffset];
    }];
}

- (void)reloadData
{
    [self.tableView.infiniteScrollingView stopAnimating];
    self.tableView.showsInfiniteScrolling = _eventsMore;
    [self dismissLoadingView];
    [self.tableView reloadData];
}
- (void)moreEvents:(int)offset
{
    NSString *url = [NSString stringWithFormat:API_URL"/events/?start=%d", offset];
    [_connection sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        Debug("Success to get events start=%d", offset);
        NSArray *arr = [JSON objectForKey:@"events"];
        if (offset == 0)
            _events = nil;

        NSMutableArray *marray = [NSMutableArray new];
        [marray addObjectsFromArray:_events];
        [marray addObjectsFromArray:arr];
        _events = marray;
        _eventsMore = [[JSON objectForKey:@"more"] boolValue];
        _eventsOffset = [[JSON objectForKey:@"more_offset"] intValue];
        Debug("%lu events, more:%d, offset:%d", (unsigned long)_events.count, _eventsMore, _eventsOffset);
        [self reloadData];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        [self dismissLoadingView];
        [self.tableView.infiniteScrollingView stopAnimating];
        if (self.isVisible)
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load activities", @"Seafile")];
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

    if (_connection != connection) {
        _connection = connection;
        _events = nil;
        self.eventsMore = true;
        self.eventsOffset = 0;
        self.tableView.showsInfiniteScrolling = true;
        _eventDetails = [NSMutableDictionary new];
        [self.tableView reloadData];
    }
}

- (NSString *)translateLine:(NSString *)line
{
    if (!line || line.length == 0) return line;
    NSError *error = NULL;
    NSString *operation = [[_opsMap allKeys] componentsJoinedByString:@"|"];
    NSString *pattern = [NSString stringWithFormat:@"(%@) \"(.*)\"\\s?(and ([0-9]+) more (files|directories))?", operation];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, [line length])];
    if (!match) return line;
    NSString *op = [line substringWithRange:[match rangeAtIndex:1]];
    NSString *name = [line substringWithRange:[match rangeAtIndex:2]];
    NSString *num = nil;
    NSString *type = nil;
    NSString *opTranslated = [self.opsMap objectForKey:op];

    if (match.numberOfRanges > 3 && !NSEqualRanges([match rangeAtIndex:3], NSMakeRange(NSNotFound, 0))) {
        num = [line substringWithRange:[match rangeAtIndex:4]];
        type = [line substringWithRange:[match rangeAtIndex:5]];
        NSString *typeTranslated = [self.typesMap objectForKey:type];
        NSString *more = [NSString stringWithFormat:NSLocalizedString(@"and %@ more", @"Seafile"), num];
        return [NSString stringWithFormat:@"%@ \"%@\" %@ %@.", opTranslated, name, more, typeTranslated];
    } else {
        return [NSString stringWithFormat:@"%@ \"%@\".", opTranslated, name];
    }
}

- (NSString *)translateCommitDesc:(NSString *)value
{
    if (!value || value.length == 0) return value;
    if ([value hasPrefix:@"Reverted repo"]) {
        [value stringByReplacingOccurrencesOfString:@"repo" withString:@"library"];
    }
    for (NSString *s in self.prefixMap) {
        if ([value hasPrefix:s])
            return [value stringByReplacingOccurrencesOfString:s withString:[self.prefixMap objectForKey:s]];
    }
    if ([value hasPrefix:@"Merged"] || [value hasPrefix:@"Auto merge"]) {
        return NSLocalizedString(@"Auto merge by seafile system", @"Seafile");
    }

    NSError *error = NULL;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"Reverted file \"(.*)\" to status at (.*)."
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    NSTextCheckingResult *match = [regex firstMatchInString:value options:0 range:NSMakeRange(0, [value length])];
    if (match) {
        NSString *name = [value substringWithRange:[match rangeAtIndex:1]];
        NSString *time = [value substringWithRange:[match rangeAtIndex:2]];
        return [NSString stringWithFormat:NSLocalizedString(@"Reverted file \"%@\" to status at %@.", @"Seafile"), name, time];
    }
    NSArray *lines = [value componentsSeparatedByString:@"\n"];
    NSMutableArray *array = [NSMutableArray new];
    for (NSString *line in lines) {
        if (line && line.length != 0)
            [array addObject:[self translateLine:line]];
    }
    return [array componentsJoinedByString:@" "];
}

- (NSString *)getCommitDesc:(NSDictionary *)event
{
    NSString *etype = [event objectForKey:@"etype"];
    if ([etype isEqualToString:@"repo-delete"]) {
        return [NSString stringWithFormat:NSLocalizedString(@"Deleted library %@", @"Seafile"), [event objectForKey:@"repo_name"]];
    } else if ([etype isEqualToString:@"repo-create"]) {
        return [NSString stringWithFormat:NSLocalizedString(@"Created library %@", @"Seafile"), [event objectForKey:@"repo_name"]];
    } else {
        return [self translateCommitDesc:[event objectForKey:@"desc"]];
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

- (NSURL *)getAvatarUrl:(NSDictionary *)event
{
    NSString *string = [event objectForKey:@"avatar"];
    NSError *error = NULL;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<img src=\"(/.*)\" width=.*/>"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    NSTextCheckingResult *match = [regex firstMatchInString:string options:0 range:NSMakeRange(0, [string length])];
    if (!match) return nil;

    NSString *path = [string substringWithRange:[match rangeAtIndex:1]];
    NSURL *url = [NSURL URLWithString:_connection.address];
    NSURL *target = [NSURL URLWithString:path relativeToURL:url];
    return target;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafEventCell";
    SeafEventCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
        cell.accountImageView.layer.cornerRadius = 5.0f;
        cell.accountImageView.clipsToBounds = YES;
    }

    NSDictionary *event = [_events objectAtIndex:indexPath.row];
    NSURL *url = [self getAvatarUrl:event];
    if (url) {
        [cell.accountImageView sd_setImageWithURL:url placeholderImage:_defaultAccountImage];
    } else {
        cell.accountImageView.image = _defaultAccountImage;
    }
    cell.textLabel.text = [self getCommitDesc:event];;
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
- (void)addEvents:(NSString *)repoId prefix: (NSString *)prefix array:(NSArray *)arr toAlert:(UIAlertController *)alert handler:(void (^)(NSString *repoId, NSString *path))handler
{
    for (NSString *name in arr) {
        NSString *message = [NSString stringWithFormat:@"%@ '%@'", prefix, name];
        UIAlertAction *action = [UIAlertAction actionWithTitle:message style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            handler(repoId, name);
        }];
        [alert addAction:action];
    }
}

- (void)eventRenamed:(NSString *)repoId prefix:(NSString *)prefix array:(NSArray *)arr toAlert:(UIAlertController *)alert
{
    for (int i = 1; i < arr.count; i += 2) {
        NSString *from = [arr objectAtIndex:i-1];
        NSString *to = [arr objectAtIndex:i];

        NSString *message = [NSString stringWithFormat:@"%@ %@ ==> %@", prefix, from, to];
        UIAlertAction *action = [UIAlertAction actionWithTitle:message style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self openFile:to inRepo:repoId];
        }];
        [alert addAction:action];
    }
}

- (UIAlertController *)generateAction:(NSString *)repoId detail:(NSDictionary *)detail withTitle:(NSString *)title
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    ModificationHandler openHandler = ^(NSString *repoId, NSString *path) {
        [self openFile:path inRepo:repoId];
    };
    ModificationHandler emptyHandler = ^(NSString *repoId, NSString *path) {};
    NSString *s1 = NSLocalizedString(@"Added file", @"Seafile");
    NSString *s2 = NSLocalizedString(@"Added directory", @"Seafile");
    NSString *s3 = NSLocalizedString(@"Modified file", @"Seafile");
    NSString *s4 = NSLocalizedString(@"Renamed", @"Seafile");
    NSString *s5 = NSLocalizedString(@"Removed file", @"Seafile");
    NSString *s6 = NSLocalizedString(@"Removed directory", @"Seafile");
    [self addEvents:repoId prefix:s1 array:[detail objectForKey:@"added_files"] toAlert:alert handler:openHandler];
    [self addEvents:repoId prefix:s2 array:[detail objectForKey:@"added_dirs"] toAlert:alert handler:emptyHandler];
    [self addEvents:repoId prefix:s3 array:[detail objectForKey:@"modified_files"] toAlert:alert handler:openHandler];
    [self eventRenamed:repoId prefix:s4 array:[detail objectForKey:@"renamed_files"] toAlert:alert];
    [self addEvents:repoId prefix:s5 array:[detail objectForKey:@"deleted_files"] toAlert:alert handler:emptyHandler];
    [self addEvents:repoId prefix:s6 array:[detail objectForKey:@"deleted_dirs"] toAlert:alert handler:emptyHandler];

    if (!IsIpad()){
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:STR_CANCEL style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        }];
        [alert addAction:cancelAction];
    }
    return alert;
}

- (void)showEvent:(NSString *)repoId detail:(NSDictionary *)detail fromCell:(UITableViewCell *)cell
{
    NSString *title = NSLocalizedString(@"Modification Details", @"Seafile");
    UIAlertController *alert = [self generateAction:repoId detail:detail withTitle:title];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = cell.frame;
    [self presentViewController:alert animated:true completion:nil];
}

- (void)getCommitModificationDetail:(NSString *)repoId url:(NSString *)url fromCell:(UITableViewCell *)cell
{
    [_connection sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        Debug("Success to get event: %@", JSON);
        NSDictionary *detail = (NSDictionary *)JSON;
        [_eventDetails setObject:detail forKey:url];
        [self showEvent:repoId detail:detail fromCell:cell];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        Warning("Failed to get commit detail.");
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to get modification details", @"Seafile")];
    }];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row >= _events.count)
        return;

    NSDictionary *event = [_events objectAtIndex:indexPath.row];
    NSString *etype = [event objectForKey:@"etype"];
    if (![etype isEqualToString:@"repo-update"])
        return;
    NSString *repoId = [event objectForKey:@"repo_id"];
    NSString *commitId = [event objectForKey:@"commit_id"];
    NSString *url = [NSString stringWithFormat:API_URL"/repo_history_changes/%@/?commit_id=%@", repoId, commitId];

    Debug("Select event %@", event);
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    NSDictionary *detail = [_eventDetails objectForKey:url];
    if (detail)
        return [self showEvent:repoId detail:detail fromCell:cell];

    SeafRepo *repo = [_connection getRepo:repoId];
    if (!repo) return;
    if (repo.passwordRequired) {
        [self popupSetRepoPassword:repo handler:^{
            [self getCommitModificationDetail:repoId url:url fromCell:cell];
        }];
    } else
        [self getCommitModificationDetail:repoId url:url fromCell:cell];
}

- (void)openFile:(NSString *)path inRepo:(NSString *)repoId
{
    Debug("open file %@ in repo %@", path, repoId);
    SeafFile *sfile = [[SeafFile alloc] initWithConnection:self.connection oid:nil repoId:repoId name:path.lastPathComponent path:path mtime:0 size:0];
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

@end
