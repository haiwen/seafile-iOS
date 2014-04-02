//
//  SeafDisDetailViewController.m
//  Discussion
//
//  Created by Wang Wei on 5/21/13.
//  Copyright (c) 2013 Wang Wei. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafDisDetailViewController.h"

#import "SeafBase.h"
#import "SVProgressHUD.h"
#import "UIViewController+Extend.h"
#import "ExtentedString.h"
#import "Debug.h"

static const CGFloat kJSLabelPadding = 5.0f;
static const CGFloat kJSTimeStampLabelHeight = 15.0f;
static const CGFloat kJSSubtitleLabelHeight = 15.0f;

@interface SeafDisDetailViewController ()<JSMessagesViewDataSource, JSMessagesViewDelegate, EGORefreshTableHeaderDelegate, UIScrollViewDelegate>
@property (strong, nonatomic) UIPopoverController *masterPopoverController;
@property (strong) UIBarButtonItem *msgItem;
@property (strong) UIBarButtonItem *refreshItem;
@property (strong) NSArray *items;

@property (strong, nonatomic) NSMutableArray *messages;
@property (strong, nonatomic) NSMutableDictionary *info;
@property (readwrite, nonatomic) int msgtype;
@property (readwrite, nonatomic) int next_page;


@property (readonly) EGORefreshTableHeaderView* refreshHeaderView;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *loadingView;

@end

@implementation SeafDisDetailViewController
@synthesize connection = _connection;
@synthesize refreshHeaderView = _refreshHeaderView;

#pragma mark - Managing the detail item

- (void)showLodingView
{
    if (!self.loadingView) {
        self.loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        self.loadingView.color = [UIColor darkTextColor];
        self.loadingView.hidesWhenStopped = YES;
        [self.view addSubview:self.loadingView];
    }
    self.loadingView.center = self.view.center;
    self.loadingView.frame = CGRectMake(self.loadingView.frame.origin.x, (self.navigationController.view.frame.size.height-self.loadingView.frame.size.height-80)/2, self.loadingView.frame.size.width, self.loadingView.frame.size.height);
    [self.loadingView startAnimating];
}

- (void)dismissLoadingView
{
    [self.loadingView stopAnimating];
}

- (UIWebView *)webview
{
    return (UIWebView *)self.view;
}

- (void)setConnection:(SeafConnection *)connection
{
     _connection = connection;
    self.sender = self.connection.username;
    [self setMsgtype:MSG_NONE info:nil];
}

- (void)setMsgtype:(int)msgtype info:(NSMutableDictionary *)info
{
    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }
    self.msgtype = msgtype;
    self.info = info;
    self.messages = [[NSMutableArray alloc] init];
    [self loadCacheData];
    if (self.isViewLoaded)
        [self refreshView];
    [self.messageInputView.textView resignFirstResponder];
    self.messageInputView.textView.text = @"";
    self.next_page = 2;
}

- (NSString *)msgUrl
{
    NSString *url = nil;
    switch (self.msgtype) {
        case MSG_NONE:
            break;
        case MSG_REPLY:
            url =  [NSString stringWithFormat:API_URL"/group/%@/msg/%@/", [self.info objectForKey:@"group_id"], [self.info objectForKey:@"msg_id"]];
            break;
        case MSG_GROUP:
            url =  [NSString stringWithFormat:API_URL"/group/msgs/%@/", [self.info objectForKey:@"id"]];
            break;
        case MSG_USER:
            url =  [NSString stringWithFormat:API_URL"/user/msgs/%@/", [self.info objectForKey:@"email"]];
            break;
    }
    return url;
}

- (NSMutableArray *)paseMessageData:(id)JSON
{
    NSMutableArray *messages = [[NSMutableArray alloc] init];
    Debug("JSON=%@", JSON);
    if (!JSON || ![JSON isKindOfClass:[NSDictionary class]])
        return messages;
    switch (self.msgtype) {
        case MSG_NONE:
            break;
        case MSG_REPLY: {
            SeafMessage *msg = [[SeafMessage alloc] initWithGroupMsg:JSON conn:self.connection];
            [messages addObject:msg];
            break;
        }
        case MSG_GROUP: {
            for (NSDictionary *dict in [JSON objectForKey:@"msgs"]) {
                SeafMessage *msg = [[SeafMessage alloc] initWithGroupMsg:dict conn:self.connection];
                [messages addObject:msg];
            }
            break;
        }
        case MSG_USER:{
            for (NSDictionary *dict in [JSON objectForKey:@"msgs"]) {
                SeafMessage *msg = [[SeafMessage alloc] initWithUserMsg:dict conn:self.connection];
                [messages addObject:msg];
            }
            break;
        }
    }
    [messages sortUsingComparator:^NSComparisonResult(SeafMessage *obj1, SeafMessage *obj2) {
        return [obj1.date compare:obj2.date];
    }];
    return messages;
}

- (void)handleMessageData:(id)JSON
{
    self.messages = [self paseMessageData:JSON];
}
- (void)loadCacheData
{
    switch (self.msgtype) {
        case MSG_NONE:
        case MSG_REPLY:
            break;
        case MSG_GROUP:
        case MSG_USER:
        {
            id JSON = [self.connection getCachedObj:[self msgUrl]];
            self.messages = [self paseMessageData:JSON];
            break;
        }
    }
    Debug("cache %lu", (unsigned long)self.messages.count);
}

- (void)downloadMessages
{
    switch (self.msgtype) {
        case MSG_NONE:
            break;
        case MSG_REPLY:
        case MSG_GROUP:
        case MSG_USER:
        {
            NSString *url = [self msgUrl];
            [self.connection sendRequest:url repo:nil success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
                [self.connection savetoCacheKey:url value:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
                self.messages = [self paseMessageData:JSON];
                [self.tableView reloadData];
                [self scrollToBottomAnimated:YES];
                [self dismissLoadingView];
                self.refreshItem.enabled = YES;
                long long newmsgnum = [[self.info objectForKey:@"msgnum"] integerValue:0];
                if (newmsgnum > 0) {
                    [self.info setObject:@"0" forKey:@"msgnum"];
                    self.connection.newmsgnum -= newmsgnum;
                    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
                    [appdelegate.discussVC.tableView reloadData];
                    [appdelegate.discussVC refreshTabBarItem];
                }
            } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
                Warning("Failed to get messsages");
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to get messages", @"Failed to get message")];
                [self dismissLoadingView];
                self.refreshItem.enabled = YES;
            }];
            break;
        }
    }
}

- (void)refreshView
{
    Debug("type=%d, count=%lu\n", self.msgtype, (unsigned long)self.messages.count);
    if (self.msgtype != MSG_NONE) {
        long long newmsgnum = [[self.info objectForKey:@"msgnum"] integerValue:0];
        if (self.messages.count == 0 || newmsgnum > 0) {
            [self refresh:nil];
        }
    }
    // Update the user interface for the detail item.
    switch (self.msgtype) {
        case MSG_NONE:
            self.title = NSLocalizedString(@"Message", nil);
            self.navigationItem.rightBarButtonItems = nil;
            [self setInputViewHidden:YES];
            if (self.refreshHeaderView.superview)
                [self.refreshHeaderView removeFromSuperview];
            break;
        case MSG_GROUP:
            self.title = [self.info objectForKey:@"name"];
            self.navigationItem.rightBarButtonItems = self.items;
            [self setInputViewHidden:YES];
            self.msgItem.enabled = YES;
            if (!self.refreshHeaderView.superview)
                [self.tableView addSubview:self.refreshHeaderView];
            break;
        case MSG_USER:
            self.title = [self.info objectForKey:@"name"];
            self.navigationItem.rightBarButtonItems = [NSArray arrayWithObject:self.refreshItem];
            [self setInputViewHidden:NO];
            if (!self.refreshHeaderView.superview)
                [self.tableView addSubview:self.refreshHeaderView];
            break;
        case MSG_REPLY:
            self.title = [self.info objectForKey:@"name"];
            self.navigationItem.rightBarButtonItems = [NSArray arrayWithObject:self.refreshItem];
            if (self.refreshHeaderView.superview)
                [self.refreshHeaderView removeFromSuperview];
            break;
        default:
            break;
    }
    [self.tableView reloadData];
    [self scrollToBottomAnimated:NO];
}

- (void)goBack:(id)sender
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)refresh:(id)sender
{
    self.refreshItem.enabled = NO;
    [self showLodingView];
    [self downloadMessages];
}

- (void)compose:(id)sender
{
    self.msgItem.enabled = NO;
    [self setInputViewHidden:NO];
    [self.messageInputView.textView becomeFirstResponder];
}

- (void)viewDidLoad
{
    self.delegate = self;
    self.dataSource = self;
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    [[JSBubbleView appearance] setFont:[UIFont systemFontOfSize:16.0f]];
    [self setBackgroundColor:[UIColor whiteColor]];

    if (!IsIpad()) {
        UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Back", @"Back") style:UIBarButtonItemStylePlain target:self action:@selector(goBack:)];
        [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    }

    self.refreshItem = [self getBarItemAutoSize:@"refresh".navItemImgName action:@selector(refresh:)];
    self.msgItem = [self getBarItemAutoSize:@"addmsg".navItemImgName action:@selector(compose:)];
    UIBarButtonItem *space = [self getSpaceBarItem:16.0];
    self.items = [NSArray arrayWithObjects:self.refreshItem, space, self.msgItem, nil];
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.messageInputView.textView.placeHolder = @"New Message";

    [super viewDidLoad];
    if (_refreshHeaderView == nil) {
        EGORefreshTableHeaderView *view = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.tableView.bounds.size.height, self.view.frame.size.width, self.tableView.bounds.size.height)];
        view.delegate = self;
        _refreshHeaderView = view;
    }
    [_refreshHeaderView refreshLastUpdatedDate];
    [self refreshView];
}

- (void)handleKeyboardWillHideNotification:(NSNotification *)notification
{
    if (self.msgtype == MSG_GROUP) {
        [self setInputViewHidden:YES];
        self.msgItem.enabled = YES;
    }
}
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleKeyboardWillHideNotification:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [self dismissLoadingView];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    [super viewDidDisappear:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Split view

- (void)splitViewController:(UISplitViewController *)splitController willHideViewController:(UIViewController *)viewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)popoverController
{
    barButtonItem.title = NSLocalizedString(@"Message", @"Message");
    [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    self.masterPopoverController = popoverController;
}

- (void)splitViewController:(UISplitViewController *)splitController willShowViewController:(UIViewController *)viewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    // Called when the view is shown again in the split view, invalidating the button and popover controller.
    [self.navigationItem setLeftBarButtonItem:nil animated:YES];
    self.masterPopoverController = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return IsIpad() || (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)setInputViewHidden:(BOOL)hidden
{
    if (self.messageInputView.hidden == hidden)
        return;
    self.messageInputView.hidden = hidden;
    CGFloat inputViewHeight = 0;
    if (!hidden) {
        JSMessageInputViewStyle inputViewStyle = [self.delegate inputViewStyle];
        inputViewHeight = (inputViewStyle == JSMessageInputViewStyleFlat) ? 45.0f : 40.0f;
    }
    UIEdgeInsets insets = UIEdgeInsetsZero;
    if ([self respondsToSelector:@selector(topLayoutGuide)]) {
        insets.top = self.topLayoutGuide.length;
    }
    insets.bottom = inputViewHeight;
    self.tableView.contentInset = insets;
    self.tableView.scrollIndicatorInsets = insets;
}

#pragma mark - Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.messages.count;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat height = [super tableView:tableView heightForRowAtIndexPath:indexPath];
    SeafMessage *msg = [self.messages objectAtIndex:indexPath.row];
    if (msg.replies.count > 0) {
//        height += msg.repliesHeight;
        height += msg.replies.count * 20;

    }
    Debug("row=%ld, height=%f", (long)indexPath.row, height);
    return height;
}

#pragma mark - Messages view delegate: REQUIRED
- (void)saveToCache
{
    NSMutableArray *msgs = [[NSMutableArray alloc] init];
    for (SeafMessage *msg in self.messages) {
        NSDictionary *m = [msg toDictionary];
        [msgs addObject:m];
    }
    NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:msgs, @"msgs", nil];
    [self.connection savetoCacheKey:[self msgUrl] value:[Utils JSONEncodeDictionary:dict]];
}

- (void)addReply:(SeafMessage *)msg text:(NSString *)text fromSender:(NSString *)sender onDate:(NSDate *)date
{
    Debug("sender=%@, %@ msg=%@, %@", sender, self.sender, msg, [msg toDictionary]);
    NSString *url = [NSString stringWithFormat:API_URL"/group/%@/msg/%@/", [self.info objectForKey:@"group_id"], msg.msgId];
    NSString *form = [NSString stringWithFormat:@"message=%@", [text escapedPostForm]];
    [self.connection sendPost:url repo:nil form:form success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
        [SVProgressHUD dismiss];
        NSString *msgId = [JSON objectForKey:@"msgid"];
        NSString *timestamp = [NSString stringWithFormat:@"%d", (int)[date timeIntervalSince1970]];
        NSDictionary *reply = [[NSDictionary alloc] initWithObjectsAndKeys:msgId, @"msgid", self.sender, @"from_email", [self.connection nickForEmail:self.sender], @"nickname", timestamp, @"timestamp", text, @"msg", nil];
        [msg.replies addObject:reply];
        self.messageInputView.sendButton.enabled = YES;
        [self finishSend];
        [self saveToCache];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to send message", @"Failed to send message")];
        self.messageInputView.sendButton.enabled = YES;
    }];
}
- (void)didSendText:(NSString *)text fromSender:(NSString *)sender onDate:(NSDate *)date
{

    [SVProgressHUD showWithStatus:@"Sending"];
    self.messageInputView.sendButton.enabled = NO;
    if (NO) {
        [self addReply:nil text:text fromSender:sender onDate:date];
        return;
    }
    SeafMessage *msg = [[SeafMessage alloc] initWithText:text email:sender date:date conn:self.connection type:self.msgtype];
    Debug("sender=%@, %@ msg=%@, %@", sender, self.sender, msg, [msg toDictionary]);
    NSString *url = [self msgUrl];
    NSString *form = [NSString stringWithFormat:@"message=%@", [text escapedPostForm]];
    [self.connection sendPost:url repo:nil form:form success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
        [SVProgressHUD dismiss];
        msg.msgId = [JSON objectForKey:@"msgid"];
        [self.messages addObject:msg];
        self.messageInputView.sendButton.enabled = YES;
        [self finishSend];
        [self scrollToBottomAnimated:NO];
        [self saveToCache];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to send message", @"Failed to send message")];
        self.messageInputView.sendButton.enabled = YES;
    }];
}

- (JSBubbleMessageType)messageTypeForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafMessage *msg = [self.messages objectAtIndex:indexPath.row];
    if (self.msgtype == MSG_GROUP)
        return JSBubbleMessageTypeIncoming;
    if ([msg.email isEqualToString:self.sender])
        return JSBubbleMessageTypeOutgoing;
    return JSBubbleMessageTypeIncoming;
}

- (UIImageView *)bubbleImageViewWithType:(JSBubbleMessageType)type
                       forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (type == JSBubbleMessageTypeIncoming) {
        return [JSBubbleImageViewFactory bubbleImageViewForType:type
                                                          color:[UIColor js_bubbleLightGrayColor]];
    }
    return [JSBubbleImageViewFactory bubbleImageViewForType:type
                                                      color:[UIColor js_bubbleBlueColor]];
}

- (JSMessageInputViewStyle)inputViewStyle
{
    return JSMessageInputViewStyleFlat;
}

#pragma mark - Messages view delegate: OPTIONAL

- (BOOL)shouldDisplayTimestampForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

//
//  *** Implement to customize cell further
//
- (void)configureCell:(JSBubbleMessageCell *)cell atIndexPath:(NSIndexPath *)indexPath
{
    if ([cell messageType] == JSBubbleMessageTypeOutgoing) {
        cell.bubbleView.textView.textColor = [UIColor whiteColor];

        if ([cell.bubbleView.textView respondsToSelector:@selector(linkTextAttributes)]) {
            NSMutableDictionary *attrs = [cell.bubbleView.textView.linkTextAttributes mutableCopy];
            [attrs setValue:[UIColor blueColor] forKey:UITextAttributeTextColor];
            cell.bubbleView.textView.linkTextAttributes = attrs;
        }
    }

    if (cell.timestampLabel) {
        cell.timestampLabel.textColor = [UIColor lightGrayColor];
        cell.timestampLabel.shadowOffset = CGSizeZero;
    }

    if (cell.subtitleLabel) {
        cell.subtitleLabel.textColor = [UIColor lightGrayColor];
    }

#if TARGET_IPHONE_SIMULATOR
    cell.bubbleView.textView.dataDetectorTypes = UIDataDetectorTypeNone;
#else
    cell.bubbleView.textView.dataDetectorTypes = UIDataDetectorTypeAll;
#endif
    SeafMessage *msg = [self.messages objectAtIndex:indexPath.row];

    if (self.msgtype == MSG_GROUP || self.msgtype == MSG_REPLY) {
        cell.avatarImageView.frame = CGRectMake(cell.avatarImageView.frame.origin.x,
                                                kJSTimeStampLabelHeight,
                                                cell.avatarImageView.frame.size.width,
                                                cell.avatarImageView.frame.size.height);
       
        cell.avatarImageView.autoresizingMask = (UIViewAutoresizingFlexibleLeftMargin
                                                 | UIViewAutoresizingFlexibleRightMargin);
        cell.subtitleLabel.hidden = YES;
        cell.timestampLabel.text = [NSString stringWithFormat:@"%@  %@", msg.nickname, cell.timestampLabel.text];
        cell.timestampLabel.frame = CGRectMake(cell.bubbleView.frame.origin.x,
                                               kJSLabelPadding,
                                               cell.bubbleView.frame.size.width,
                                               kJSTimeStampLabelHeight);
        cell.timestampLabel.autoresizingMask = (UIViewAutoresizingFlexibleWidth);
    }
    if (msg.replies.count > 0) {
        Debug("...row=%ld reply %lu, %@", (long)indexPath.row, (unsigned long)msg.replies.count, msg.text);
        UITableView *tview = nil;
        for (UIView *v in cell.contentView.subviews) {
            if ([v isKindOfClass:[UITableView class]]) {
                tview = (UITableView *)v;
                break;
            }
        }
        Debug("view=%@", tview);
        CGFloat y = [super tableView:self.tableView heightForRowAtIndexPath:indexPath];
        CGRect frame = CGRectMake(cell.bubbleView.frame.origin.x, y,
                                 cell.contentView.frame.size.width - cell.bubbleView.frame.origin.x,
                                 msg.replies.count * 20);
        Debug("%f %f %f %f\n", tview.frame.origin.x, tview.frame.origin.y, tview.frame.size.width, tview.frame.size.height);
        
        if (!tview)
            tview = [[UITableView alloc] initWithFrame:frame style:UITableViewStylePlain];
        tview.delegate = msg;
        tview.dataSource = msg;
        tview.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        tview.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        tview.backgroundColor = self.tableView.backgroundColor;
        tview.separatorColor = self.tableView.backgroundColor;
        tview.separatorStyle = UITableViewCellSeparatorStyleNone;
        tview.scrollEnabled = NO;
        
        msg.repliesHeight = tview.frame.size.height - 0;
        [cell.contentView addSubview:tview];
        [tview reloadData];
        [cell.contentView bringSubviewToFront:tview];
        Debug("%f %f %f %f\n", tview.frame.origin.x, tview.frame.origin.y, tview.frame.size.width, tview.frame.size.height);
    }
}

- (NSString *)customCellIdentifierForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [NSString stringWithFormat:@"JSMessageCell_%d_%u_%d", self.msgtype, [self messageTypeForRowAtIndexPath:indexPath], [self shouldDisplayTimestampForRowAtIndexPath:indexPath]];
}

#pragma mark - Messages view data source: REQUIRED

- (JSMessage *)messageForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [self.messages objectAtIndex:indexPath.row];
}

- (UIImageView *)avatarImageViewForRowAtIndexPath:(NSIndexPath *)indexPath sender:(NSString *)sender
{
    SeafMessage *msg = [self.messages objectAtIndex:indexPath.row];
    NSString *avatar = [self.connection avatarForEmail:msg.email];
    UIImage *image = [JSAvatarImageFactory avatarImage:[UIImage imageWithContentsOfFile:avatar] croppedToCircle:YES];
    return [[UIImageView alloc] initWithImage:image];
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
- (void)doneLoadingTableViewData
{
    [_refreshHeaderView egoRefreshScrollViewDataSourceDidFinishedLoading:self.tableView];
}
- (void)downloadMoreMessages
{
    switch (self.msgtype) {
        case MSG_NONE:
        case MSG_REPLY:
            break;
        case MSG_GROUP:
        case MSG_USER:
        {
            NSString *url = [[self msgUrl] stringByAppendingFormat:@"?page=%d", self.next_page, nil];
            [self.connection sendRequest:url repo:nil success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
                NSMutableArray *arr = [self paseMessageData:JSON];
                self.next_page = (int)[[JSON objectForKey:@"next_page"] integerValue:-1];
                long long lastID = 0;
                if (arr.count > 0) {
                    lastID = [[[arr objectAtIndex:(arr.count-1)] msgId] integerValue:0];
                    for (SeafMessage *m in self.messages) {
                        if ([m.msgId integerValue:0] > lastID)
                            [arr addObject:m];
                    }
                    long off = arr.count - self.messages.count;
                    self.messages = arr;
                    [self.tableView reloadData];
                    [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:off inSection:0]
                                          atScrollPosition:UITableViewScrollPositionBottom
                                                  animated:NO];
                }
                Debug("msgs count=%lu", (unsigned long)self.messages.count);
                [self doneLoadingTableViewData];
            } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
                Warning("Failed to get messsages");
                [self doneLoadingTableViewData];
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to get messages", @"Failed to get message")];
            }];
            break;
        }
    }
}
- (void)egoRefreshTableHeaderDidTriggerRefresh:(EGORefreshTableHeaderView*)view
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (![appdelegate checkNetworkStatus]) {
        [self performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:0.1];
        return;
    }
    if (self.next_page > 0)
        [self downloadMoreMessages];
    else
        [self performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:0.1];
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
