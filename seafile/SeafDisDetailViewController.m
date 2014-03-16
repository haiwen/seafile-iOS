//
//  SeafDisDetailViewController.m
//  Discussion
//
//  Created by Wang Wei on 5/21/13.
//  Copyright (c) 2013 Wang Wei. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafDisDetailViewController.h"
#import "SeafMessage.h"

#import "SVProgressHUD.h"
#import "UIViewController+Extend.h"
#import "ExtentedString.h"
#import "Debug.h"

@interface SeafDisDetailViewController ()<JSMessagesViewDataSource, JSMessagesViewDelegate>
@property (strong, nonatomic) UIPopoverController *masterPopoverController;
@property (strong) UIBarButtonItem *msgItem;
@property (strong) UIBarButtonItem *refreshItem;
@property (strong) NSArray *items;

@property (strong, nonatomic) NSMutableArray *messages;
@property (strong, nonatomic) NSDictionary *info;
@property (readwrite, nonatomic) int msgtype;

@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *loadingView;

@end

@implementation SeafDisDetailViewController
@synthesize connection = _connection;

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

- (void)setMsgtype:(int)msgtype info:(NSDictionary *)info
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

- (void)handleMessageData:(id)JSON
{
    self.messages = [[NSMutableArray alloc] init];
    NSArray *arr = [JSON objectForKey:@"msgs"];

    switch (self.msgtype) {
        case MSG_NONE:
            break;
        case MSG_REPLY:
            for (NSDictionary *dict in arr) {
                SeafMessage *msg = [[SeafMessage alloc] initWithGroupMsg:dict conn:self.connection];
                [self.messages addObject:msg];
            }
            break;
        case MSG_GROUP: {
            for (NSDictionary *dict in arr) {
                SeafMessage *msg = [[SeafMessage alloc] initWithGroupMsg:dict conn:self.connection];
                [self.messages addObject:msg];
            }
            break;
        }
        case MSG_USER:{
            for (NSDictionary *dict in arr) {
                SeafMessage *msg = [[SeafMessage alloc] initWithUserMsg:dict conn:self.connection];
                [self.messages addObject:msg];
            }
            break;
        }
    }
    [self.messages sortUsingComparator:^NSComparisonResult(SeafMessage *obj1, SeafMessage *obj2) {
        return [obj1.date compare:obj2.date];
    }];
}
- (void)loadCacheData
{
    switch (self.msgtype) {
        case MSG_NONE:
            break;
        case MSG_REPLY:
        case MSG_GROUP:
        case MSG_USER:
        {
            id JSON = [self.connection getCachedObj:[self msgUrl]];
            [self handleMessageData:JSON];
            if (self.messages.count == 0) {
                [self downloadMessages];
            }
            break;
        }
    }
    Debug("cache %d", self.messages.count);
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
                [self handleMessageData:JSON];
                [self.tableView reloadData];
                [self scrollToBottomAnimated:YES];
                [self dismissLoadingView];
                self.refreshItem.enabled = YES;
            } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
                Warning("Failed to get messsages");
                [self dismissLoadingView];
                self.refreshItem.enabled = YES;
            }];
            break;
        }
    }
}

- (void)refreshView
{
    Debug("type=%d, count=%d\n", self.msgtype, self.messages.count);
    // Update the user interface for the detail item.
    switch (self.msgtype) {
        case MSG_NONE:
            self.title = NSLocalizedString(@"Message", nil);
            self.navigationItem.rightBarButtonItems = nil;
            [self setInputViewHidden:YES];
            break;
        case MSG_GROUP:
            self.title = [self.info objectForKey:@"name"];
            self.navigationItem.rightBarButtonItems = self.items;
            [self setInputViewHidden:YES];
            self.msgItem.enabled = YES;
            break;
        case MSG_USER:
        case MSG_REPLY:
            self.title = [self.info objectForKey:@"name"];
            self.navigationItem.rightBarButtonItems = [NSArray arrayWithObject:self.refreshItem];
            [self setInputViewHidden:NO];
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
- (void)didSendText:(NSString *)text fromSender:(NSString *)sender onDate:(NSDate *)date
{
    SeafMessage *msg = [[SeafMessage alloc] initWithText:text email:sender date:date conn:self.connection];
    Debug("sender=%@, %@ msg=%@", sender, self.sender, msg);
    [SVProgressHUD showWithStatus:@"Sending"];
    self.messageInputView.sendButton.enabled = NO;
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

@end
