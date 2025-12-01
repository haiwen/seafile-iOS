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
#import "SeafSdocWebViewController.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "SeafEventCell.h"
#import "SeafRepos.h"
#import "SeafBase.h"
#import "SeafActivitiesCell.h"
#import "SeafActivityModel.h"
#import "SeafDetailViewController.h"
#import "SeafVideoPlayerViewController.h"
#import "SeafPhotoGalleryViewController.h"
#import "SeafCacheManager.h"
#import "SeafRealmManager.h"

#import "SeafDateFormatter.h"
#import "ExtentedString.h"
#import "Debug.h"
#import "SeafLoadingView.h"

typedef void (^ModificationHandler)(NSString *repoId, NSString *path);

@interface SeafActivityViewController ()<UITableViewDelegate,UITableViewDataSource, SeafDentryDelegate>
@property (strong) NSArray *events;
@property BOOL eventsMore;
@property int eventsOffset;

@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (strong, nonatomic) SeafLoadingView *loadingView;

@property NSMutableDictionary *eventDetails;
@property UIImage *defaultAccountImage;
@property (strong, nonatomic) NSDictionary *opsMap;
@property NSDictionary *prefixMap;
@property NSDictionary *typesMap;

@property (strong, nonatomic) SeafFile *pendingVideoFile;
@property (strong, nonatomic) SeafDetailViewController *activeDetailViewController;

@end

@implementation SeafActivityViewController
@synthesize connection = _connection;


- (void)viewDidLoad
{
    [super viewDidLoad];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeAll;

    // Do any additional setup after loading the view from its nib.
    self.title = NSLocalizedString(@"Activities", @"Seafile");
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60.0;
    self.tableView.tableFooterView = [UIView new];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    // Initialize loading view
    self.loadingView = [SeafLoadingView loadingViewWithParentView:self.view];
    
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barAppearance = [UINavigationBarAppearance new];
        barAppearance.backgroundColor = [UIColor whiteColor];
        
        self.navigationController.navigationBar.standardAppearance = barAppearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = barAppearance;
    }
    
    // Initialize basic properties
    self.eventsMore = true;
    self.eventsOffset = 0;
    _eventDetails = [NSMutableDictionary new];
    
    // Move time-consuming operations to background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Load default account image
        UIImage *defaultImage = [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"account" ofType:@"png"]];
        
        // Initialize dictionaries
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
        NSDictionary *prefixMap = [NSDictionary dictionaryWithObjects:values2 forKeys:keys2];
        
        NSDictionary *typesMap = [NSDictionary dictionaryWithObjectsAndKeys:
                                 NSLocalizedString(@"files", @"Seafile"), @"files",
                                 NSLocalizedString(@"directories", @"Seafile"), @"directories",
                                 nil];
        
        // Update UI on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_defaultAccountImage = defaultImage;
            self.prefixMap = prefixMap;
            self.typesMap = typesMap;
        });
    });
    
    __weak typeof(self) weakSelf = self;
    [self.tableView addInfiniteScrollingWithActionHandler:^{
        __strong typeof (weakSelf) strongSelf = weakSelf;
        [strongSelf moreEvents:strongSelf.eventsOffset];
    }];
    
    // Setup pull to refresh control and its target action
    self.tableView.refreshControl = [[UIRefreshControl alloc] init];
    [self.tableView.refreshControl addTarget:self action:@selector(refreshControlChanged) forControlEvents:UIControlEventValueChanged];
}

#pragma mark - pull to Refresh
- (void)refreshControlChanged {
    if (!self.tableView.isDragging) {
        [self refresh:nil];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (self.tableView.refreshControl.isRefreshing) {
        [self refresh:nil];
    }
}

- (void)refresh:(id)sender {
    // Hide accessibility elements during refresh to avoid user interaction
    self.tableView.accessibilityElementsHidden = YES;
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.tableView.refreshControl);
    [self moreEvents:0];
}

// Ends the refresh process and updates UI
- (void)endRefreshing {
    // Re-enable accessibility elements
    self.tableView.accessibilityElementsHidden = NO;
    [self.tableView.refreshControl endRefreshing];
}

- (void)reloadData
{
    [self.tableView.infiniteScrollingView stopAnimating];
    
    // Determine if the infinite scrolling should be shown based on if more events are expected
    self.tableView.showsInfiniteScrolling = _eventsMore;
    [self endRefreshing];
    [self.tableView reloadData];
}

- (void)showLoadingView {
    [self.loadingView showInView:self.view];
}

- (void)dismissLoadingView {
    [self.loadingView dismiss];
}

- (void)moreEvents:(int)offset
{
    // Only show loading view when there's no data
    if (offset == 0 && (!self->_events || self->_events.count == 0)) {
        [self showLoadingView];
    }
    
    // Check for the new API compatibility, if so use new method for requesting events
    if (_connection.isNewActivitiesApiSupported) {
        return [self newApiRequest:offset];
    }
    
    // Standard request for older API versions
    NSString *url = [NSString stringWithFormat:API_URL"/events/?start=%d", offset];
    @weakify(self);
    [_connection sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        // Process data in background thread
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @strongify(self);
            
            NSArray *arr = [JSON objectForKey:@"events"];
            NSMutableArray *marray = [NSMutableArray new];
            if (offset != 0) {
                [marray addObjectsFromArray:self->_events];
            }
            [marray addObjectsFromArray:arr];
            
            BOOL hasMore = [[JSON objectForKey:@"more"] boolValue];
            int newOffset = [[JSON objectForKey:@"more_offset"] intValue];
            
            // Update UI in main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                @strongify(self);
                self->_events = marray;
                self->_eventsMore = hasMore;
                self->_eventsOffset = newOffset;
                
                [self reloadData];
                [self dismissLoadingView];
            });
        });
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @strongify(self);
            [self endRefreshing];
            [self.tableView.infiniteScrollingView stopAnimating];
            [self dismissLoadingView];
            if (self.isVisible)
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load activities", @"Seafile")];
        });
    }];
}

- (void)newApiRequest:(int)page {
    // Only show loading view when there's no data and it's the first page
    if (page == 0) {
        page += 1;// Ensure the page starts from 1 if reset to 0
        if (!self->_events || self->_events.count == 0) {
            [self showLoadingView];
        }
    }
    
    NSString *url = [NSString stringWithFormat:API_URL_V21"/activities/?page=%d", page];
    [_connection sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        // Process data in background thread
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            NSArray *arr = [JSON objectForKey:@"events"];
            NSMutableArray *marray = [NSMutableArray new];
            if (page != 1) {
                [marray addObjectsFromArray:self->_events];
            }
            [marray addObjectsFromArray:arr];
            
            BOOL hasMore = arr.count >= 25;  // Check if there's likely more data based on page size
            
            // Update UI in main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_events = marray;
                self->_eventsMore = hasMore;
                self->_eventsOffset = page + 1;
                
                [self reloadData];
                [self dismissLoadingView];
            });
        });
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self endRefreshing];
            [self.tableView.infiniteScrollingView stopAnimating];
            [self dismissLoadingView];
            if (self.isVisible)
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load activities", @"Seafile")];
        });
    }];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    _eventDetails = [NSMutableDictionary new];
    // Dispose of any resources that can be recreated.
}

// Sets up a new connection and refreshes the event list if the connection changes
- (void)setConnection:(SeafConnection *)connection
{
    if (IsIpad())// On iPad, pop to root to manage navigation stack in split view
        [self.navigationController popToRootViewControllerAnimated:NO];

    if (_connection != connection) {
        _connection = connection;
        _events = nil;// Reset events
        self.eventsMore = true;// Reset loading state
        self.eventsOffset = 0;// Start from the beginning
        self.tableView.showsInfiniteScrolling = true;
        _eventDetails = [NSMutableDictionary new];// Clear event details
        [self.tableView reloadData];
    }
}

// Translates activity line to user-friendly description if it matches known patterns
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
    if (!match) return line;// No pattern matched
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

// Attempts to make complex commit descriptions more user-friendly
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
    // Regular expression to detect and format reverted file descriptions
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

- (void)viewWillAppear:(BOOL)animated
{
    if (!_events) {
        [self moreEvents:0];
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
    if (_connection.isNewActivitiesApiSupported) {
        return [self activitiesCell:tableView indexPath:indexPath];
    }
    
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
    cell.textLabel.text = [self getCommitDesc:event];
    cell.repoNameLabel.text = [event objectForKey:@"repo_name"];
    cell.authorLabel.text = [event objectForKey:@"nick"];
    long timestamp = [[event objectForKey:@"time"] longValue];
    cell.timeLabel.text = [SeafDateFormatter stringFromLongLong:timestamp];
    cell.backgroundColor = [UIColor clearColor];

    return cell;
}

- (SeafActivitiesCell *)activitiesCell:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
    NSString *CellIdentifier = @"SeafActivitiesCell";
    SeafActivitiesCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil].firstObject;
    }
    
    SeafActivityModel *event = [[SeafActivityModel alloc] initWithEventJSON:[_events objectAtIndex:indexPath.row] andOpsMap:self.opsMap];
    [cell showWithImage:event.avatarURL author:event.authorName operation:event.operation time:event.time detail:event.detail repoName:event.repoName];
    
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
    [tableView deselectRowAtIndexPath:indexPath animated:true];
    if (indexPath.row >= _events.count)
        return;

    NSDictionary *event = [_events objectAtIndex:indexPath.row];
    NSString *etype = [event objectForKey:@"etype"];
    if ([_connection isNewActivitiesApiSupported]) {
        NSString *name = [event objectForKey:@"name"];
        NSString *op_type = [event objectForKey:@"op_type"];
        NSString *obj_type = [event objectForKey:@"obj_type"];
        if ([obj_type containsString:@"draft"] && [op_type isEqualToString:@"publish"]) {
            return [self openFile:[event valueForKey:@"path"] inRepo:[event valueForKey:@"repo_id"]];
        } else if ([op_type isEqualToString:@"delete"] || [op_type isEqualToString:@"clean-up-trash"] || [name containsString:@"(draft).md"]) {
            return;
        }
    }
    // Handle only 'repo-update' events for showing details
    else if (![etype isEqualToString:@"repo-update"]) {
        return;
    }
    
    NSString *repoId = [event objectForKey:@"repo_id"];
    NSString *commitId = [event objectForKey:@"commit_id"];
    NSString *url = [NSString stringWithFormat:API_URL"/repo_history_changes/%@/?commit_id=%@", repoId, commitId];

    
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    NSDictionary *detail = [_eventDetails objectForKey:url];
    
    SeafRepo *repo = [_connection getRepo:repoId];
    if (!repo) {
        Warning("No such repo %@", repoId);
        return;
    }
    // Show event details if already fetched, or fetch them if necessary
    if (detail && !repo.passwordRequired)
        return [self showEvent:repoId detail:detail fromCell:cell];

    if (repo.passwordRequiredWithSyncRefresh) {
        [self popupSetRepoPassword:repo handler:^{
            [self getCommitModificationDetail:repoId url:url fromCell:cell];
        }];
    } else
        [self getCommitModificationDetail:repoId url:url fromCell:cell];
}

// Opens a file specified by path in a given repository
- (void)openFile:(NSString *)path inRepo:(NSString *)repoId
{
    // Ensure path starts with "/" (repo_history_changes API returns relative paths)
    if (path.length > 0 && ![path hasPrefix:@"/"]) {
        path = [@"/" stringByAppendingString:path];
    }
    
    SeafFile *sfile = [[SeafFile alloc] initWithConnection:self.connection oid:nil repoId:repoId name:path.lastPathComponent path:path mtime:0 size:0];
    // Probe cache before decision
    NSString *cachePathBefore = nil;
    NSURL *exportURLBefore = nil;
    @try {
        cachePathBefore = [sfile cachePath];
        exportURLBefore = [sfile exportURL];
    } @catch(NSException *exception) {}

    // Load cached metadata if any
    [sfile loadCache];
    BOOL hasCacheAfter = [sfile hasCache];
    NSString *cachePathAfter = nil;
    NSURL *exportURLAfter = nil;
    @try {
        cachePathAfter = [sfile cachePath];
        exportURLAfter = [sfile exportURL];
    } @catch(NSException *exception) {}
    BOOL exportExistsAfter = exportURLAfter ? [[NSFileManager defaultManager] fileExistsAtPath:exportURLAfter.path] : NO;
    

    // Try a stronger cache load to populate ooid/oid for encrypted repos
    if (!hasCacheAfter && !exportExistsAfter) {
        BOOL hasCacheReal = [sfile hasCache];
        NSURL *exportURLReal = [sfile exportURL];
        BOOL exportExistsReal = exportURLReal ? [[NSFileManager defaultManager] fileExistsAtPath:exportURLReal.path] : NO;
        
        // Update local variables for subsequent decision
        hasCacheAfter = hasCacheReal;
        exportURLAfter = exportURLReal;
        exportExistsAfter = exportExistsReal;
    }
    if ([sfile.mime isEqualToString:@"application/sdoc"]) {
        SeafSdocWebViewController *vc = [[SeafSdocWebViewController alloc] initWithFile:sfile fileName:sfile.name];
        if (IsIpad()) {
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate showDetailView:vc];
        } else {
            vc.hidesBottomBarWhenPushed = YES;
            [self.navigationController pushViewController:vc animated:YES];
        }
        return;
    }
    // Video files: follow the same strategy as the Starred page
    if ([sfile isVideoFile]) {
        BOOL isEncryptedRepo = [self.connection isEncrypted:repoId];
        BOOL decrypted = [self.connection isDecrypted:repoId];
        

        if (isEncryptedRepo) {
            // treat as cached if export file exists even when hasCache flag is false
            if (decrypted && ([sfile hasCache] || exportExistsAfter)) {
                // Already decrypted and cached locally, play immediately
                [SeafVideoPlayerViewController closeActiveVideoPlayer];
                SeafVideoPlayerViewController *playerVC = [[SeafVideoPlayerViewController alloc] initWithFile:sfile];
                [self presentViewController:playerVC animated:YES completion:nil];
                return;
            }
            // Fallback: if above checks miss but local DB indicates a cached file, play directly to avoid entering detail
            if (decrypted && ![sfile hasCache] && !exportExistsAfter) {
                @try {
                    SeafFileStatus *status = [[SeafRealmManager shared] getFileStatusWithPath:sfile.uniqueKey];
                    BOOL localExists = (status && status.localFilePath && [[NSFileManager defaultManager] fileExistsAtPath:status.localFilePath]);
                    if (localExists) {
                        if (status.serverOID.length > 0) {
                            sfile.oid = status.serverOID;
                            if (![sfile.ooid isEqualToString:status.serverOID]) {
                                [sfile setOoid:status.serverOID];
                            }
                        }
                        NSURL *exportURLTry = [sfile exportURL];
                        BOOL exportExistsTry = exportURLTry ? [[NSFileManager defaultManager] fileExistsAtPath:exportURLTry.path] : NO;
                        
                        if (exportExistsTry || [sfile hasCache]) {
                            [SeafVideoPlayerViewController closeActiveVideoPlayer];
                            SeafVideoPlayerViewController *playerVC = [[SeafVideoPlayerViewController alloc] initWithFile:sfile];
                            [self presentViewController:playerVC animated:YES completion:nil];
                            return;
                        }
                    }
                } @catch(NSException *exception) {}
            }
            // If not cached or decrypted, open the detail page to download, then auto-play after download completes.
            self.pendingVideoFile = sfile;
            SeafDetailViewController *detailvc;
            if (IsIpad()) {
                detailvc = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
            } else {
                detailvc = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
            }
            self.activeDetailViewController = detailvc;
            sfile.delegate = self; // This controller receives download callbacks and forwards them to the detail view controller
            [detailvc setPreViewItem:sfile master:self];
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate showDetailView:detailvc];
            return;
        } else {
            // Non-encrypted library: play directly if cached; otherwise the player supports streaming
            [SeafVideoPlayerViewController closeActiveVideoPlayer];
            SeafVideoPlayerViewController *playerVC = [[SeafVideoPlayerViewController alloc] initWithFile:sfile];
            [self presentViewController:playerVC animated:YES completion:nil];
            return;
        }
    }
    
    // Image files: use SeafPhotoGalleryViewController for Live Photo/Motion Photo support
    if ([sfile isImageFile]) {
        Debug(@"[Activity] Image file detected, using SeafPhotoGalleryViewController: %@", sfile.name);
        
        // Create array with single image file
        NSArray<id<SeafPreView>> *imageFiles = @[sfile];
        
        // Create and setup photo gallery view controller
        SeafPhotoGalleryViewController *gallery = [[SeafPhotoGalleryViewController alloc] initWithPhotos:imageFiles
                                                                                            currentItem:sfile
                                                                                                 master:self];
        
        // Wrap gallery view controller in navigation controller and present modally
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:gallery];
        navController.modalPresentationStyle = UIModalPresentationFullScreen;
        
        [self presentViewController:navController animated:YES completion:nil];
        Debug(@"[Activity] Presented SeafPhotoGalleryViewController for image file");
        return;
    }

    // Non-video, non-image: keep existing behavior
    SeafDetailViewController *detailvc;
    if (IsIpad()) {
        detailvc = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
    } else {
        detailvc = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
    }
    sfile.delegate = detailvc;
    [detailvc setPreViewItem:sfile master:nil];
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate showDetailView:detailvc];
}

#pragma mark - SeafDentryDelegate (forward to detail and auto-play video when ready)
- (void)download:(id)entry progress:(float)progress
{
    if (self.activeDetailViewController) {
        [self.activeDetailViewController download:entry progress:progress];
    }
}

- (void)download:(id)entry complete:(BOOL)updated
{
    if (self.activeDetailViewController) {
        [self.activeDetailViewController download:entry complete:updated];
    }
    if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *videoFileTmp = (SeafFile *)entry;
        if (videoFileTmp == self.pendingVideoFile && [videoFileTmp isVideoFile] && videoFileTmp.hasCache) {
            self.pendingVideoFile = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                void (^presentPlayer)(void) = ^{
                    [SeafVideoPlayerViewController closeActiveVideoPlayer];
                    SeafVideoPlayerViewController *playerVC = [[SeafVideoPlayerViewController alloc] initWithFile:videoFileTmp];
                    [self presentViewController:playerVC animated:YES completion:nil];
                };
                if (self.presentedViewController) {
                    [self dismissViewControllerAnimated:NO completion:presentPlayer];
                } else if (self.activeDetailViewController.presentedViewController) {
                    [self.activeDetailViewController dismissViewControllerAnimated:NO completion:presentPlayer];
                } else {
                    presentPlayer();
                }
            });
        }
    }
}

- (void)download:(id)entry failed:(NSError *)error
{
    if (self.activeDetailViewController) {
        [self.activeDetailViewController download:entry failed:error];
    }
    if (entry == self.pendingVideoFile) {
        self.pendingVideoFile = nil;
    }
}

- (NSDictionary *)opsMap {
    if (!_opsMap) {
        if ([_connection isNewActivitiesApiSupported]) {
            NSArray *keys = [NSArray arrayWithObjects:
                             @"create repo",
                             @"rename repo",
                             @"delete repo",
                             @"restore repo",
                             @"create dir",
                             @"rename dir",
                             @"delete dir",
                             @"restore dir",
                             @"move dir",
                             @"create file",
                             @"rename file",
                             @"delete file",
                             @"restore file",
                             @"move file",
                             @"edit file",
                             @"create draft",
                             @"delete draft",
                             @"edit draft",
                             @"publish draft",
                             @"create files",
                             @"clean-up-trash",
                             nil];
            NSArray *values = [NSArray arrayWithObjects:
                               NSLocalizedString(@"Created library", @"Seafile"),
                               NSLocalizedString(@"Renamed library", @"Seafile"),
                               NSLocalizedString(@"Deleted library", @"Seafile"),
                               NSLocalizedString(@"Restored library", @"Seafile"),
                               NSLocalizedString(@"Created folder", @"Seafile"),
                               NSLocalizedString(@"Renamed folder", @"Seafile"),
                               NSLocalizedString(@"Deleted folder", @"Seafile"),
                               NSLocalizedString(@"Restored folder", @"Seafile"),
                               NSLocalizedString(@"Moved folder", @"Seafile"),
                               NSLocalizedString(@"Created file", @"Seafile"),
                               NSLocalizedString(@"Renamed file", @"Seafile"),
                               NSLocalizedString(@"Deleted file", @"Seafile"),
                               NSLocalizedString(@"Restored file", @"Seafile"),
                               NSLocalizedString(@"Moved file", @"Seafile"),
                               NSLocalizedString(@"Updated file", @"Seafile"),
                               NSLocalizedString(@"Created draft", @"Seafile"),
                               NSLocalizedString(@"Deleted draft", @"Seafile"),
                               NSLocalizedString(@"Updated draft", @"Seafile"),
                               NSLocalizedString(@"Publish draft", @"Seafile"),
                               NSLocalizedString(@"Created files", @"Seafile"),
                               NSLocalizedString(@"Removed all items from trash", @"Seafile"),
                               nil];
            _opsMap = [NSDictionary dictionaryWithObjects:values forKeys:keys];
        } else {
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
            
            _opsMap = [NSDictionary dictionaryWithObjects:values forKeys:keys];
        }
    }
    return _opsMap;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.loadingView updatePosition];
}

@end
