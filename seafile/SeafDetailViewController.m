//
//  SeafDetailViewController.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafDetailViewController.h"
#import "FileViewController.h"
#import "FailToPreview.h"
#import "DownloadingProgressView.h"
#import "SeafTextEditorViewController.h"
#import "M13InfiniteTabBarController.h"
#import "SeafUploadFile.h"

#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "ExtentedString.h"
#import "Debug.h"

enum PREVIEW_STATE {
    PREVIEW_NONE = 0,
    PREVIEW_INIT,
    PREVIEW_SUCCESS,
    PREVIEW_WEBVIEW,
    PREVIEW_WEBVIEW_JS,
    PREVIEW_DOWNLOADING,
    PREVIEW_FAILED
};

@interface SeafDetailViewController ()
@property (strong, nonatomic) UIPopoverController *masterPopoverController;

@property (retain) FileViewController *fileViewController;
@property (retain) FailToPreview *failedView;
@property (retain) DownloadingProgressView *progressView;
@property (retain) UIWebView *webView;
@property int state;

@property (strong) NSArray *barItemsStar;
@property (strong) NSArray *barItemsUnStar;
@property (strong) UIBarButtonItem *editItem;
@property (strong) UIBarButtonItem *exportItem;
@property (strong) UIBarButtonItem *shareItem;
@property (strong, nonatomic) UIBarButtonItem *fullscreenItem;
@property (strong, nonatomic) UIBarButtonItem *exitfsItem;
@property (strong, nonatomic) UIBarButtonItem *leftItem;


@property (strong) UIDocumentInteractionController *docController;
@property int buttonIndex;
@property (readwrite, nonatomic) bool hideMaster;

@end


@implementation SeafDetailViewController
@synthesize buttonIndex;
@synthesize fullscreenItem = _fullscreenItem;
@synthesize exitfsItem = _exitfsItem;
@synthesize preViewItem = _preViewItem;
@synthesize hideMaster = _hideMaster;


#pragma mark - Managing the detail item
- (BOOL)previewSuccess
{
    return (self.state == PREVIEW_SUCCESS) || (self.state == PREVIEW_WEBVIEW) || (self.state == PREVIEW_WEBVIEW_JS);
}

- (void)checkNavItems
{
    NSMutableArray *array = [[NSMutableArray alloc] init];
    if ([self.self.preViewItem isKindOfClass:[SeafFile class]]) {
        if ([(SeafFile *)self.preViewItem isStarred])
            [array addObjectsFromArray:self.barItemsStar];
        else
            [array addObjectsFromArray:self.barItemsUnStar];
    }
    if ([self.preViewItem editable] && [self previewSuccess]
        && [self.preViewItem.mime hasPrefix:@"text/"])
        [array addObject:self.editItem];
    self.navigationItem.rightBarButtonItems = array;
}

- (void)clearPreView
{
    if (self.state == PREVIEW_FAILED)
        [self.failedView removeFromSuperview];
    if (self.state == PREVIEW_DOWNLOADING)
        [self.progressView removeFromSuperview];
    if (self.state == PREVIEW_SUCCESS)
        [self.fileViewController.view removeFromSuperview];
    if (self.state == PREVIEW_WEBVIEW || self.state == PREVIEW_WEBVIEW_JS) {
        [self.webView removeFromSuperview];
        [self.webView loadHTMLString:@"" baseURL:nil];
    }
}

- (void)refreshView
{
    NSURLRequest *request;
    if (IsIpad())
        self.title = self.preViewItem.previewItemTitle;
    else {
        UILabel* tlabel = [[UILabel alloc] initWithFrame:CGRectMake(0,0, 60, 40)];
        tlabel.text = self.preViewItem.previewItemTitle;
        tlabel.textColor = [UIColor whiteColor];
        tlabel.backgroundColor = [UIColor clearColor];
        tlabel.adjustsFontSizeToFitWidth = YES;
        self.navigationItem.titleView = tlabel;
    }
    [self clearPreView];
    if (!self.preViewItem) {
        self.state = PREVIEW_NONE;
    } else if (self.preViewItem.previewItemURL) {
        if (![QLPreviewController canPreviewItem:self.preViewItem]) {
            self.state = PREVIEW_FAILED;
        } else {
            self.state = PREVIEW_SUCCESS;
            if ([self.preViewItem.mime hasPrefix:@"audio"] || [self.preViewItem.mime hasPrefix:@"video"] || [self.preViewItem.mime isEqualToString:@"image/svg+xml"])
                self.state = PREVIEW_WEBVIEW;
            else if([self.preViewItem.mime isEqualToString:@"text/x-markdown"] || [self.preViewItem.mime isEqualToString:@"text/x-seafile"])
                self.state = PREVIEW_WEBVIEW_JS;
        }
    } else {
        self.state = PREVIEW_DOWNLOADING;
    }
    [self checkNavItems];
    switch (self.state) {
        case PREVIEW_DOWNLOADING:
            Debug (@"DownLoading file %@\n", self.preViewItem.previewItemTitle);
            self.progressView.frame = self.view.frame;
            [self.view addSubview:self.progressView];
            [self.progressView configureViewWithItem:self.preViewItem completeness:0];
            break;
        case PREVIEW_FAILED:
            Debug ("Can not preview file %@ %@\n", self.preViewItem.previewItemTitle, self.preViewItem.previewItemURL);
            self.failedView.frame = self.view.frame;
            [self.view addSubview:self.failedView];
            [self.failedView configureViewWithPrevireItem:self.preViewItem];
            break;
        case PREVIEW_SUCCESS:
            Debug (@"Preview file %@ mime=%@ success\n", self.preViewItem.previewItemTitle, self.preViewItem.mime);
            [self.fileViewController setPreItem:self.preViewItem];
            self.fileViewController.view.frame = self.view.frame;
            [self.view addSubview:self.fileViewController.view];
            break;
        case PREVIEW_WEBVIEW_JS:
        case PREVIEW_WEBVIEW:
            Debug("Preview by webview\n");
            request = [[NSURLRequest alloc] initWithURL:self.preViewItem.previewItemURL cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
            if (!self.webView) {
                self.webView = [[UIWebView alloc] initWithFrame:self.view.frame];
                self.webView.scalesPageToFit = YES;
                self.webView.autoresizesSubviews = YES;
                self.webView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
                if (self.state == PREVIEW_WEBVIEW_JS)
                    self.webView.delegate = self;
                else
                    self.webView.delegate = nil;
            }
            [self.webView loadRequest:request];
            [self.view addSubview:self.webView];
            self.webView.center = self.view.center;
            break;
        case PREVIEW_NONE:
            break;
        default:
            break;
    }
}

- (void)setPreViewItem:(id<QLPreviewItem, PreViewDelegate>)item
{
    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }
    _preViewItem = item;
    if ([item isKindOfClass:[SeafFile class]])
        [(SeafFile *)item loadContent:NO];
    if (IsIpad() && UIInterfaceOrientationIsLandscape(self.interfaceOrientation) && !self.hideMaster) {
        if (_preViewItem == nil) {
            self.navigationItem.leftBarButtonItem = nil;
        } else {
            self.navigationItem.leftBarButtonItem = self.fullscreenItem;
        }
    }
    [self refreshView];
}

- (void)goBack:(id)sender
{
    [self.navigationController dismissViewControllerAnimated:NO completion:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    if (!IsIpad()) {
        UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStylePlain target:self action:@selector(goBack:)];
        [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    }
    self.view.autoresizesSubviews = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;

    self.editItem = [self getBarItem:@"editfile.png" action:@selector(editFile:)size:18];
    self.exportItem = [self getBarItemAutoSize:@"export.png" action:@selector(openElsewhere:)];
    self.shareItem = [self getBarItemAutoSize:@"share.png" action:@selector(share:)];
    UIBarButtonItem *item3 = [self getBarItem:@"star.png" action:@selector(unstarFile:)size:24];
    UIBarButtonItem *item4 = [self getBarItem:@"unstar.png" action:@selector(starFile:)size:24];
    UIBarButtonItem *space = [self getSpaceBarItem:20.0];
    self.barItemsStar  = [NSArray arrayWithObjects:self.exportItem, space, self.shareItem, space, item3, space, nil];
    self.barItemsUnStar  = [NSArray arrayWithObjects:self.exportItem, space, self.shareItem, space, item4, space, nil];

    if(IsIpad()) {
        NSArray *views = [[NSBundle mainBundle] loadNibNamed:@"FailToPreview_iPad" owner:self options:nil];
        self.failedView = [views objectAtIndex:0];
        views = [[NSBundle mainBundle] loadNibNamed:@"DownloadingProgress_iPad" owner:self options:nil];
        self.progressView = [views objectAtIndex:0];
    } else {
        NSArray *views = [[NSBundle mainBundle] loadNibNamed:@"FailToPreview_iPhone" owner:self options:nil];
        self.failedView = [views objectAtIndex:0];
        views = [[NSBundle mainBundle] loadNibNamed:@"DownloadingProgress_iPhone" owner:self options:nil];
        self.progressView = [views objectAtIndex:0];
    }
    self.fileViewController = [[FileViewController alloc] init];
    self.state = PREVIEW_NONE;
    self.view.autoresizesSubviews = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    self.hideMaster = NO;
    [self refreshView];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    self.preViewItem = nil;
    self.fileViewController = nil;
    self.failedView = nil;
    self.progressView = nil;
    self.docController = nil;
    self.webView = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!IsIpad()) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
    return YES;
}

- (void)viewWillLayoutSubviews
{
    if (self.state == PREVIEW_SUCCESS)
        self.fileViewController.view.frame = self.view.frame;
    else if (self.state == PREVIEW_NONE) {
        if (self.view.subviews.count > 0) {
            UIView *v = [self.view.subviews objectAtIndex:0];
            v.center = self.view.center;
        }
    }
}

#pragma mark - Split view

- (void)splitViewController:(UISplitViewController *)splitController willHideViewController:(UIViewController *)viewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)popoverController
{
    self.hideMaster = NO;
    [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    self.masterPopoverController = popoverController;
}

- (void)splitViewController:(UISplitViewController *)splitController willShowViewController:(UIViewController *)viewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    // Called when the view is shown again in the split view, invalidating the button and popover controller.
    self.leftItem = barButtonItem;
    [self.navigationItem setLeftBarButtonItem:nil animated:YES];
    self.masterPopoverController = nil;
    if (_preViewItem)
        [self.navigationItem setLeftBarButtonItem:self.fullscreenItem animated:YES];
}

- (BOOL)splitViewController:(UISplitViewController *)svc shouldHideViewController:(UIViewController *)vc inOrientation:(UIInterfaceOrientation)orientation
{
    if (UIInterfaceOrientationIsLandscape(orientation))
        return self.hideMaster;
    else
        return YES;
}

-(void)makeTabBarHidden:(BOOL)hide
{
    // Custom code to hide TabBar
    UITabBarController *tabBarController = self.splitViewController.tabBarController;
    if ( [tabBarController.view.subviews count] < 2 ) {
        return;
    }

    UIView *contentView;

    if ( [[tabBarController.view.subviews objectAtIndex:0] isKindOfClass:[UITabBar class]] ) {
        contentView = [tabBarController.view.subviews objectAtIndex:1];
    } else {
        contentView = [tabBarController.view.subviews objectAtIndex:0];
    }

    if (hide) {
        contentView.frame = tabBarController.view.bounds;
    }
    else {
        contentView.frame = CGRectMake(tabBarController.view.bounds.origin.x,
                                       tabBarController.view.bounds.origin.y,
                                       tabBarController.view.bounds.size.width,
                                       tabBarController.view.bounds.size.height - tabBarController.tabBar.frame.size.height);
    }

    tabBarController.tabBar.hidden = hide;
}
- (void)setHideMaster:(bool)hideMaster
{
    _hideMaster = hideMaster;
    [self makeTabBarHidden:hideMaster];
    self.splitViewController.delegate = nil;
    self.splitViewController.delegate = self;
    [self.splitViewController willRotateToInterfaceOrientation:[UIApplication sharedApplication].statusBarOrientation duration:0];
    [self.splitViewController.view setNeedsLayout];
}

- (IBAction)fullscreen:(id)sender
{
    self.hideMaster = YES;
    self.navigationItem.leftBarButtonItem = self.exitfsItem;
    self.splitViewController.delegate = nil;
    self.splitViewController.delegate = self;
}

- (IBAction)exitfullscreen:(id)sender
{
    self.hideMaster = NO;
    self.navigationItem.leftBarButtonItem = self.fullscreenItem;
}

- (UIBarButtonItem *)fullscreenItem
{
    if (!_fullscreenItem) {
        _fullscreenItem = [self getBarItem:@"arrowleft.png" action:@selector(fullscreen:) size:22];
    }
    return _fullscreenItem;
}

- (UIBarButtonItem *)exitfsItem
{
    if (!_exitfsItem) {
        _exitfsItem = [self getBarItem:@"arrowright.png" action:@selector(exitfullscreen:) size:22];
    }
    return _exitfsItem;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    if (IsIpad()) self.splitViewController.delegate = self;
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    if (IsIpad()) self.splitViewController.delegate = self;
    if (IsIpad() && !UIInterfaceOrientationIsLandscape(self.interfaceOrientation)) {
        if (self.hideMaster) {
            self.navigationItem.leftBarButtonItem = self.leftItem;
            self.hideMaster = NO;
        }
    }
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }
    [super viewWillDisappear:animated];
}

#pragma mark - SeafDentryDelegate
- (void)fileContentLoaded :(SeafFile *)file result:(BOOL)res completeness:(int)percent
{
    if (file != self.preViewItem)
        return;
    if (self.state != PREVIEW_DOWNLOADING) {
        [self refreshView];
        return;
    }
    if (!res) {
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:@"Failed to download file '%@'",self.preViewItem.previewItemTitle]];
        [self setPreViewItem:nil];
    } else {
        [self.progressView configureViewWithItem:self.preViewItem completeness:percent];
        if (percent == 100)
            [self refreshView];
    }
}

- (void)entryChanged:(SeafBase *)entry
{
    if (entry == self.preViewItem) {
        [self setPreViewItem:self.preViewItem];
    }
}
- (void)entry:(SeafBase *)entry contentUpdated:(BOOL)updated completeness:(int)percent
{
    if (entry == self.preViewItem)
        [self fileContentLoaded:(SeafFile *)entry result:YES completeness:percent];
}

- (void)entryContentLoadingFailed:(int)errCode entry:(SeafBase *)entry;
{
    if (entry == self.preViewItem)
        [self fileContentLoaded:(SeafFile *)entry result:NO completeness:0];
}

- (void)repoPasswordSet:(SeafBase *)entry WithResult:(BOOL)success;
{
}

#pragma mark - file operations
- (IBAction)starFile:(id)sender
{
    [(SeafFile *)self.preViewItem setStarred:YES];
    [self checkNavItems];
}

- (IBAction)unstarFile:(id)sender
{
    [(SeafFile *)self.preViewItem setStarred:NO];
    [self checkNavItems];
}

- (IBAction)editFile:(id)sender
{
    SeafTextEditorViewController *editViewController = [[SeafTextEditorViewController alloc] init];
    editViewController.detailViewController = self;
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:editViewController];
    [editViewController setFile:self.preViewItem];
    [navController setModalPresentationStyle:UIModalPresentationFullScreen];
    [self presentViewController:navController animated:NO completion:nil];
}

- (IBAction)uploadFile:(id)sender
{
    if ([self.preViewItem isKindOfClass:[SeafFile class]]) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [((SeafFile *)self.preViewItem) update:appdelegate.fileVC];
        [appdelegate.fileVC refreshView];
    }
}

- (IBAction)openElsewhere:(id)sender
{
    BOOL ret;
    NSURL *url = [self.preViewItem checkoutURL];
    if (!url)
        return;

    if (self.docController)
        [self.docController dismissMenuAnimated:NO];
    self.docController = [UIDocumentInteractionController interactionControllerWithURL:url];
    ret = [self.docController presentOpenInMenuFromBarButtonItem:self.exportItem animated:YES];
    if (ret == NO) {
        [SVProgressHUD showErrorWithStatus:@"There is no app which can open this type of file on this machine"];
    }
}

- (IBAction)share:(id)sender
{
    if (![self.preViewItem isKindOfClass:[SeafFile class]])
        return;

    UIActionSheet *actionSheet;
    if (IsIpad())
        actionSheet = [[UIActionSheet alloc] initWithTitle:@"How would you like to share this file?" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:@"Email", @"Copy Link to Clipboard", nil ];
    else
        actionSheet = [[UIActionSheet alloc] initWithTitle:@"How would you like to share this file?" delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Email", @"Copy Link to Clipboard", nil ];

    [actionSheet showFromBarButtonItem:self.shareItem animated:YES];
}

#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)bIndex
{
    buttonIndex = bIndex;
    if (buttonIndex == 0 || buttonIndex == 1) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        if (![appdelegate checkNetworkStatus])
            return;

        SeafFile *file = (SeafFile *)self.preViewItem;
        if (!file.shareLink) {
            [SVProgressHUD showWithStatus:@"Generate share link ..."];
            [file generateShareLink:self];
        } else {
            [self generateSharelink:file WithResult:YES];
        }
    }
}

#pragma mark - SeafFileDelegate
- (void)generateSharelink:(SeafFile *)entry WithResult:(BOOL)success
{
    if (entry != self.preViewItem)
        return;

    SeafFile *file = (SeafFile *)self.preViewItem;
    if (!success) {
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:@"Failed to generate share link of file '%@'", file.name]];
        return;
    }
    [SVProgressHUD showSuccessWithStatus:@"Generate share link success"];

    if (buttonIndex == 0) {
        [self sendMailInApp];
    } else if (buttonIndex == 1){
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        [pasteboard setString:file.shareLink];
    }
}

#pragma mark - sena mail inside app
- (void)sendMailInApp
{
    Class mailClass = (NSClassFromString(@"MFMailComposeViewController"));
    if (!mailClass) {
        [self alertWithMessage:@"This function is not supportted yet，you can copy it to the pasteboard and send mail by yourself"];
        return;
    }
    if (![mailClass canSendMail]) {
        [self alertWithMessage:@"The mail account has not been set yet"];
        return;
    }
    [self displayMailPicker];
}

- (void)displayMailPicker
{
    MFMailComposeViewController *mailPicker = [[MFMailComposeViewController alloc] init];
    mailPicker.mailComposeDelegate = self;

    SeafFile *file = (SeafFile *)self.preViewItem;
    [mailPicker setSubject:[NSString stringWithFormat:@"File '%@' is shared with you using seafile", file.name]];
    NSString *emailBody = [NSString stringWithFormat:@"Hi,<br/><br/>Here is a link to <b>'%@'</b> in my Seafile:<br/><br/> <a href=\"%@\">%@</a>\n\n", file.name, file.shareLink, file.shareLink];
    [mailPicker setMessageBody:emailBody isHTML:YES];
    [self presentViewController:mailPicker animated:YES completion:nil];
}

#pragma mark - MFMailComposeViewControllerDelegate
- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
    [self dismissViewControllerAnimated:YES completion:nil];
    NSString *msg;
    switch (result) {
        case MFMailComposeResultCancelled:
            msg = @"cancalled";
            break;
        case MFMailComposeResultSaved:
            msg = @"saved";
            break;
        case MFMailComposeResultSent:
            msg = @"sent";
            break;
        case MFMailComposeResultFailed:
            msg = @"failed";
            break;
        default:
            msg = @"";
            break;
    }
    Debug("share file:send mail %@\n", msg);
}

# pragma - UIWebViewDelegate
- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    if (self.preViewItem) {
        NSString *js = [NSString stringWithFormat:@"setContent(\"%@\");", [self.preViewItem.content stringEscapedForJavasacript]];
        [self.webView stringByEvaluatingJavaScriptFromString:js];
    }
}
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    if ([request.URL.absoluteString hasPrefix:@"file://"])
        return YES;
    return NO;
}

@end
