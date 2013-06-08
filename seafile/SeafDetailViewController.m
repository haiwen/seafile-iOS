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

#import "UIViewController+AlertMessage.h"
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
@property (strong) UIBarButtonItem *uploadItem;

@property (strong) UIDocumentInteractionController *docController;
@property int buttonIndex;

@end


@implementation SeafDetailViewController
@synthesize masterPopoverController = _masterPopoverController;
@synthesize preViewItem;

@synthesize fileViewController;
@synthesize failedView;
@synthesize progressView;
@synthesize webView;
@synthesize state;

@synthesize barItemsStar;
@synthesize barItemsUnStar;
@synthesize editItem;
@synthesize uploadItem;
@synthesize buttonIndex;
@synthesize docController;


#pragma mark - Managing the detail item

- (BOOL)previewSuccess
{
    return (self.state == PREVIEW_SUCCESS) || (self.state == PREVIEW_WEBVIEW) || (self.state == PREVIEW_WEBVIEW_JS);
}
- (void)checkNavItems
{
    NSMutableArray *array = [[NSMutableArray alloc] init];
    if ([preViewItem isKindOfClass:[SeafFile class]]) {
        if ([(SeafFile *)preViewItem isStarred])
            [array addObjectsFromArray:barItemsStar];
        else
            [array addObjectsFromArray:barItemsUnStar];
    }
    if ([preViewItem editable] && [self previewSuccess]
        && [preViewItem.mime hasPrefix:@"text/"])
        [array addObject:self.editItem];
    //if (IsIpad() && [preViewItem isKindOfClass:[SeafFile class]] && ((SeafFile *)preViewItem).mpath)
    //    [array addObject:self.uploadItem];
    self.navigationItem.rightBarButtonItems = array;
}

- (void)clearPreView
{
    if (self.state == PREVIEW_FAILED)
        [failedView removeFromSuperview];
    if (self.state == PREVIEW_DOWNLOADING)
        [progressView removeFromSuperview];
    if (self.state == PREVIEW_SUCCESS)
        [self.fileViewController.view removeFromSuperview];
    if (self.state == PREVIEW_WEBVIEW || self.state == PREVIEW_WEBVIEW_JS) {
        [webView removeFromSuperview];
        [webView loadHTMLString:@"" baseURL:nil];
    }
}

- (void)refreshView
{
    NSURLRequest *request;
    if (IsIpad())
        self.title = preViewItem.previewItemTitle;
    else {
        UILabel* tlabel = [[UILabel alloc] initWithFrame:CGRectMake(0,0, 60, 40)];
        tlabel.text = preViewItem.previewItemTitle;
        tlabel.textColor = [UIColor whiteColor];
        tlabel.backgroundColor = [UIColor clearColor];
        tlabel.adjustsFontSizeToFitWidth = YES;
        self.navigationItem.titleView = tlabel;
    }
    [self clearPreView];
    if (!preViewItem) {
        self.state = PREVIEW_NONE;
    } else if (preViewItem.previewItemURL) {
        if (![QLPreviewController canPreviewItem:preViewItem]) {
            self.state = PREVIEW_FAILED;
        } else {
            Debug (@"Preview file %@ mime=%@ success\n", preViewItem.previewItemTitle, preViewItem.mime);
            self.state = PREVIEW_SUCCESS;
            if ([preViewItem.mime hasPrefix:@"audio"] || [preViewItem.mime hasPrefix:@"video"] || [preViewItem.mime isEqualToString:@"image/svg+xml"])
                self.state = PREVIEW_WEBVIEW;
            else if([preViewItem.mime isEqualToString:@"text/x-markdown"] || [preViewItem.mime isEqualToString:@"text/x-seafile"])
                self.state = PREVIEW_WEBVIEW_JS;
        }
    } else {
        self.state = PREVIEW_DOWNLOADING;
    }
    [self checkNavItems];
    switch (self.state) {
        case PREVIEW_DOWNLOADING:
            Debug (@"DownLoading file %@\n", preViewItem.previewItemTitle);
            progressView.frame = self.view.frame;
            [self.view addSubview:progressView];
            [progressView configureViewWithItem:preViewItem completeness:0];
            break;
        case PREVIEW_FAILED:
            Debug ("Can not preview file %@ %@\n", preViewItem.previewItemTitle, preViewItem.previewItemURL);
            failedView.frame = self.view.frame;
            [self.view addSubview:failedView];
            [failedView configureViewWithPrevireItem:preViewItem];
            break;
        case PREVIEW_SUCCESS:
            Debug("Preview SUCCESS\n");
            [self.fileViewController setPreItem:preViewItem];
            fileViewController.view.frame = self.view.frame;
            [self.view addSubview:self.fileViewController.view];
            break;
        case PREVIEW_WEBVIEW_JS:
        case PREVIEW_WEBVIEW:
            Debug("Preview by webview\n");
            request = [[NSURLRequest alloc] initWithURL:preViewItem.previewItemURL cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
            if (!webView) {
                webView = [[UIWebView alloc] initWithFrame:self.view.frame];
                webView.scalesPageToFit = YES;
                webView.autoresizesSubviews = YES;
                webView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
                if (self.state == PREVIEW_WEBVIEW_JS)
                    webView.delegate = self;
                else
                    webView.delegate = nil;
            }
            [webView loadRequest:request];
            [self.view addSubview:webView];
            webView.center = self.view.center;
            break;
        case PREVIEW_NONE:
            break;
        default:
            break;
    }
}

- (void)setPreViewItem:(SeafFile *)item
{
    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }

    preViewItem = item;
    [self refreshView];
}

- (void)goBack:(id)sender
{
    //[self.navigationController popViewControllerAnimated:YES];
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
        UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStyleDone target:self action:@selector(goBack:)];
        [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    }
    self.view.autoresizesSubviews = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;

    self.editItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(editFile:)];
    NSString* path = [[NSBundle mainBundle] pathForResource:@"upload" ofType:@"png"];
    self.uploadItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageWithContentsOfFile:path] style:UIBarButtonItemStylePlain target:self action:@selector(uploadFile:)];

    UIBarButtonItem *item1 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(openElsewhere:)];
    path = [[NSBundle mainBundle] pathForResource:@"gray-share-icon" ofType:@"png"];
    UIBarButtonItem *item2 = [[UIBarButtonItem alloc] initWithImage:[UIImage imageWithContentsOfFile:path] style:UIBarButtonItemStylePlain target:self action:@selector(share:)];
    path = [[NSBundle mainBundle] pathForResource:@"gray-star-icon" ofType:@"png"];
    UIBarButtonItem *item3 = [[UIBarButtonItem alloc] initWithImage:[UIImage imageWithContentsOfFile:path] style:UIBarButtonItemStylePlain target:self action:@selector(unstarFile:)];

    path = [[NSBundle mainBundle] pathForResource:@"gray-unstar-icon" ofType:@"png"];
    UIBarButtonItem *item4 = [[UIBarButtonItem alloc] initWithImage:[UIImage imageWithContentsOfFile:path] style:UIBarButtonItemStylePlain target:self action:@selector(starFile:)];

    barItemsStar  = [NSArray arrayWithObjects:item1, item2, item3, nil];
    barItemsUnStar  = [NSArray arrayWithObjects:item1, item2, item4, nil];

    [self.navigationItem setHidesBackButton:YES];
    if(IsIpad()) {
        NSArray *views = [[NSBundle mainBundle] loadNibNamed:@"FailToPreview_iPad" owner:self options:nil];
        failedView = [views objectAtIndex:0];
        views = [[NSBundle mainBundle] loadNibNamed:@"DownloadingProgress_iPad" owner:self options:nil];
        progressView = [views objectAtIndex:0];
    } else {
        NSArray *views = [[NSBundle mainBundle] loadNibNamed:@"FailToPreview_iPhone" owner:self options:nil];
        failedView = [views objectAtIndex:0];
        views = [[NSBundle mainBundle] loadNibNamed:@"DownloadingProgress_iPhone" owner:self options:nil];
        progressView = [views objectAtIndex:0];
    }
    fileViewController = [[FileViewController alloc] init];
    self.state = PREVIEW_NONE;
    self.view.autoresizesSubviews = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
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
    Debug("self.view=%f %f\n", self.view.frame.size.width, self.view.frame.size.height);
    if (self.state == PREVIEW_SUCCESS)
        fileViewController.view.frame = self.view.frame;
    else if (self.state == PREVIEW_NONE) {
        UIView *v = [self.view.subviews objectAtIndex:0];
        v.center = self.view.center;
    }
}

#pragma mark - Split view

- (void)splitViewController:(UISplitViewController *)splitController willHideViewController:(UIViewController *)viewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)popoverController
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    barButtonItem.title = appdelegate.fileVC.title;
    [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    self.masterPopoverController = popoverController;
}

- (void)splitViewController:(UISplitViewController *)splitController willShowViewController:(UIViewController *)viewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    // Called when the view is shown again in the split view, invalidating the button and popover controller.
    [self.navigationItem setLeftBarButtonItem:nil animated:YES];
    self.masterPopoverController = nil;
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }
    [super viewWillDisappear:animated];
}

- (void)fileContentLoaded :(SeafFile *)file result:(BOOL)res completeness:(int)percent
{
    if (file != preViewItem)
        return;
    if (self.state != PREVIEW_DOWNLOADING) {
        [self refreshView];
        return;
    }
    if (!res) {
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:@"Failed to download file '%@'",preViewItem.previewItemTitle]];
        [self setPreViewItem:nil];
    } else {
        //Debug ("DownLoading file %@, percent=%d\n", preViewItem.previewItemTitle, percent);
        [progressView configureViewWithItem:preViewItem completeness:percent];
        if (percent == 100)
            [self refreshView];
    }
}

#pragma mark - file operations
- (IBAction)starFile:(id)sender
{
    [(SeafFile *)preViewItem setStarred:YES];
    [self checkNavItems];
}

- (IBAction)unstarFile:(id)sender
{
    [(SeafFile *)preViewItem setStarred:NO];
    [self checkNavItems];
}

- (IBAction)editFile:(id)sender
{
    SeafTextEditorViewController *editViewController = [[SeafTextEditorViewController alloc] init];
    editViewController.detailViewController = self;
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:editViewController];
    [editViewController setFile:preViewItem];
    [navController setModalPresentationStyle:UIModalPresentationFullScreen];
    [self presentViewController:navController animated:NO completion:nil];
}

- (IBAction)uploadFile:(id)sender
{
    if ([preViewItem isKindOfClass:[SeafFile class]]) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [((SeafFile *)preViewItem) upload:appdelegate.fileVC];
        [appdelegate.fileVC refreshView];
    }
}

- (IBAction)openElsewhere:(id)sender
{
    NSURL *url = [preViewItem checkoutURL];
    if (!url)
        return;

    if (docController)
        [docController dismissMenuAnimated:NO];
    docController = [UIDocumentInteractionController interactionControllerWithURL:url];
    BOOL ret = [docController presentOpenInMenuFromBarButtonItem:sender animated:YES];
    if (ret == NO) {
        [SVProgressHUD showErrorWithStatus:@"There is no app which can open this type of file on this machine"];
    }
}

- (IBAction)share:(id)sender
{
    if (![preViewItem isKindOfClass:[SeafFile class]])
        return;

    UIActionSheet *actionSheet;
    if (IsIpad())
        actionSheet = [[UIActionSheet alloc] initWithTitle:@"How would you like to share this file?" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:@"Email", @"Copy Link to Clipboard", nil ];
    else
        actionSheet = [[UIActionSheet alloc] initWithTitle:@"How would you like to share this file?" delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Email", @"Copy Link to Clipboard", nil ];

    [actionSheet showFromBarButtonItem:sender animated:YES];
}

#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)bIndex
{
    buttonIndex = bIndex;
    if (buttonIndex == 0 || buttonIndex == 1) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        if (![appdelegate checkNetworkStatus])
            return;

        SeafFile *file = (SeafFile *)preViewItem;
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
    if (entry != preViewItem)
        return;

    SeafFile *file = (SeafFile *)preViewItem;
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

    SeafFile *file = (SeafFile *)preViewItem;
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
    if (preViewItem) {
        NSString *js = [NSString stringWithFormat:@"setContent(\"%@\");", [preViewItem.content stringEscapedForJavasacript]];
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
