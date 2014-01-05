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
#import "REComposeViewController.h"

#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "ExtentedString.h"
#import "Debug.h"

enum PREVIEW_STATE {
    PREVIEW_NONE = 0,
    PREVIEW_SUCCESS,
    PREVIEW_WEBVIEW,
    PREVIEW_WEBVIEW_JS,
    PREVIEW_DOWNLOADING,
    PREVIEW_PHOTO,
    PREVIEW_FAILED
};

#define SHARE_TITLE NSLocalizedString(@"How would you like to share this file?", @"How would you like to share this file?")
#define POST_DISCUSSION NSLocalizedString(@"Post a discussion to group", @"Post a discussion to group")

@interface SeafDetailViewController ()<UIWebViewDelegate, UIActionSheetDelegate, UIPrintInteractionControllerDelegate, MFMailComposeViewControllerDelegate, REComposeViewControllerDelegate, PreViewSelectDelegate>
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
//@property (strong) UIBarButtonItem *cancelItem;
@property (strong) UIBarButtonItem *commentItem;

@property (strong, nonatomic) UIBarButtonItem *fullscreenItem;
@property (strong, nonatomic) UIBarButtonItem *exitfsItem;
@property (strong, nonatomic) UIBarButtonItem *leftItem;

@property (strong) UIDocumentInteractionController *docController;
@property int buttonIndex;
@property (readwrite, nonatomic) bool hideMaster;
@property (readwrite, nonatomic) NSString *gid;

@end


@implementation SeafDetailViewController
@synthesize buttonIndex;
@synthesize fullscreenItem = _fullscreenItem;
@synthesize exitfsItem = _exitfsItem;
@synthesize preViewItem = _preViewItem;
@synthesize hideMaster = _hideMaster;
@synthesize gid = _gid;


#pragma mark - Managing the detail item
- (BOOL)previewSuccess
{
    return (self.state == PREVIEW_SUCCESS) || (self.state == PREVIEW_WEBVIEW) || (self.state == PREVIEW_WEBVIEW_JS);
}

- (BOOL)isPrintable:(SeafFile *)file
{
    NSArray *exts = [NSArray arrayWithObjects:@"pdf", @"doc", @"docx", @"jpeg", @"jpg", @"rtf", nil];
    NSString *ext = file.name.pathExtension.lowercaseString;
    if (ext && ext.length != 0 && [exts indexOfObject:ext] != NSNotFound) {
        if ([UIPrintInteractionController canPrintURL:file.checkoutURL])
            return true;
    }
    return false;
}

- (void)checkNavItems
{
    NSMutableArray *array = [[NSMutableArray alloc] init];
    if ([self.preViewItem isKindOfClass:[SeafFile class]]) {
        if ([(SeafFile *)self.preViewItem isStarred])
            [array addObjectsFromArray:self.barItemsStar];
        else
            [array addObjectsFromArray:self.barItemsUnStar];

        if ([self.preViewItem checkoutURL])
            [self.exportItem setEnabled:YES];
        else
            [self.exportItem setEnabled:NO];
#if 0
        if (self.state == PREVIEW_DOWNLOADING) {
            [array addObject:self.cancelItem];
            [array addObject:[self getSpaceBarItem]];
        }
#endif
        if (((SeafFile *)self.preViewItem).groups.count > 0) {
            [array addObject:self.commentItem];
            [array addObject:[self getSpaceBarItem]];
        }
    }
    if ([self.preViewItem editable] && [self previewSuccess]
        && [self.preViewItem.mime hasPrefix:@"text/"])
        [array addObject:self.editItem];
    self.navigationItem.rightBarButtonItems = array;
}

- (void)clearPreView
{
    self.failedView.hidden = YES;
    self.progressView.hidden = YES;
    self.fileViewController.view.hidden = YES;
    self.webView.hidden = YES;
    [self.webView loadHTMLString:@"" baseURL:nil];
}

- (void)refreshView
{
    NSURLRequest *request;
    if (self.state != PREVIEW_PHOTO) {
        [self clearPreView];
        if (!self.preViewItem) {
            self.state = PREVIEW_NONE;
        } else if (self.preViewItem.previewItemURL) {
            if (![QLPreviewController canPreviewItem:self.preViewItem]) {
                self.state = PREVIEW_FAILED;
            } else {
                self.state = PREVIEW_SUCCESS;
                if ([self.preViewItem.mime hasPrefix:@"audio"]
                    || [self.preViewItem.mime hasPrefix:@"video"]
                    || [self.preViewItem.mime isEqualToString:@"image/svg+xml"])
                    self.state = PREVIEW_WEBVIEW;
                else if([self.preViewItem.mime isEqualToString:@"text/x-markdown"] || [self.preViewItem.mime isEqualToString:@"text/x-seafile"])
                    self.state = PREVIEW_WEBVIEW_JS;
            }
        } else {
            self.state = PREVIEW_DOWNLOADING;
        }
    }
    self.title = self.preViewItem.previewItemTitle;
    [self checkNavItems];
    CGRect r = CGRectMake(self.view.frame.origin.x, 0, self.view.frame.size.width, self.view.frame.size.height);
    switch (self.state) {
        case PREVIEW_DOWNLOADING:
            Debug (@"DownLoading file %@\n", self.preViewItem.previewItemTitle);
            self.progressView.frame = r;
            self.progressView.hidden = NO;
            [self.progressView configureViewWithItem:self.preViewItem completeness:0];
            break;
        case PREVIEW_FAILED:
            Debug ("Can not preview file %@ %@\n", self.preViewItem.previewItemTitle, self.preViewItem.previewItemURL);
            self.failedView.frame = r;
            self.failedView.hidden = NO;
            [self.failedView configureViewWithPrevireItem:self.preViewItem];
            break;
        case PREVIEW_SUCCESS:
            Debug (@"Preview file %@ mime=%@ success\n", self.preViewItem.previewItemTitle, self.preViewItem.mime);
            [self.fileViewController setPreItem:self.preViewItem];
            self.fileViewController.view.frame = r;
            self.fileViewController.view.hidden = NO;
            break;
        case PREVIEW_WEBVIEW_JS:
        case PREVIEW_WEBVIEW:
            Debug("Preview by webview %@\n", self.preViewItem.previewItemTitle);
            request = [[NSURLRequest alloc] initWithURL:self.preViewItem.previewItemURL cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
            if (self.state == PREVIEW_WEBVIEW_JS)
                self.webView.delegate = self;
            else
                self.webView.delegate = nil;
            self.webView.frame = r;
            [self.webView loadRequest:request];
            self.webView.hidden = NO;
            break;
        case PREVIEW_PHOTO:
            //[self.fileViewController refreshCurrentPreviewItem];
            break;
        case PREVIEW_NONE:
            break;
        default:
            break;
    }
}

- (void)setPreViewItem:(id<QLPreviewItem, PreViewDelegate>)item master:(UIViewController *)c
{
    if (self.masterPopoverController != nil)
        [self.masterPopoverController dismissPopoverAnimated:YES];
    Debug("preview %@", item.previewItemTitle);
    self.masterVc = c;
    _preViewItem = item;
    if (IsIpad() && UIInterfaceOrientationIsLandscape(self.interfaceOrientation) && !self.hideMaster && self.masterVc) {
        if (_preViewItem == nil)
            self.navigationItem.leftBarButtonItem = nil;
        else
            self.navigationItem.leftBarButtonItem = self.fullscreenItem;
    }
    if (self.state == PREVIEW_PHOTO)
        self.state = PREVIEW_SUCCESS;
    if ([item isKindOfClass:[SeafFile class]]) {
        ((SeafFile *)item).delegate = self;
        [(SeafFile *)item loadContent:NO];
    }
    [self refreshView];
}

- (void)setPreViewItems:(NSArray *)items current:(id<QLPreviewItem, PreViewDelegate>)item master:(UIViewController *)c
{
    [self clearPreView];
    self.state = PREVIEW_PHOTO;
    if ([item isKindOfClass:[SeafFile class]]) {
        ((SeafFile *)item).delegate = self;
        [(SeafFile *)item loadContent:NO];
    }
    self.fileViewController.view.frame = CGRectMake(self.view.frame.origin.x, 0, self.view.frame.size.width, self.view.frame.size.height);
    self.fileViewController.view.hidden = NO;
    [self.fileViewController setPreItems:items current:item];
}

- (void)goBack:(id)sender
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    // Do any additional setup after loading the view, typically from a nib.

    if (!IsIpad()) {
        UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStylePlain target:self action:@selector(goBack:)];
        [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    }
    self.view.autoresizesSubviews = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;

    self.editItem = [self getBarItem:@"editfile".navItemImgName action:@selector(editFile:)size:18];
    //self.cancelItem = [self getBarItem:@"close".navItemImgName action:@selector(cancelDownload:)size:18];
    self.exportItem = [self getBarItemAutoSize:@"export".navItemImgName action:@selector(export:)];
    self.shareItem = [self getBarItemAutoSize:@"share".navItemImgName action:@selector(share:)];
    self.commentItem = [self getBarItem:@"addmsg".navItemImgName action:@selector(comment:) size:20];
    UIBarButtonItem *item3 = [self getBarItem:@"star".navItemImgName action:@selector(unstarFile:)size:24];
    UIBarButtonItem *item4 = [self getBarItem:@"unstar".navItemImgName action:@selector(starFile:)size:24];
    UIBarButtonItem *space = [self getSpaceBarItem];
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
    [self.progressView.cancelBt addTarget:self action:@selector(cancelDownload:) forControlEvents:UIControlEventTouchUpInside];
    self.fileViewController = [[FileViewController alloc] init];
    //self.fileViewController.selectDelegate = self;
    self.webView = [[UIWebView alloc] initWithFrame:self.view.frame];
    self.webView.scalesPageToFit = YES;
    self.webView.autoresizesSubviews = YES;
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.failedView];
    [self.view addSubview:self.progressView];
    [self.view addSubview:self.fileViewController.view];
    [self.view addSubview:self.webView];

    self.state = PREVIEW_NONE;
    self.view.autoresizesSubviews = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    _hideMaster = NO;
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
    return IsIpad() || (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)viewWillLayoutSubviews
{
    if (IsIpad() && self.hideMaster && ios7) {
        self.view.frame = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y, self.view.frame.size.width, self.view.frame.size.height + self.splitViewController.tabBarController.tabBar.frame.size.height);
    }
    CGRect r = CGRectMake(self.view.frame.origin.x, 0, self.view.frame.size.width, self.view.frame.size.height);
    if (self.state == PREVIEW_SUCCESS) {
        self.fileViewController.view.frame = r;
    } else {
        if (self.view.subviews.count > 1) {
            UIView *v = [self.view.subviews objectAtIndex:0];
            v.frame = r;
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
    } else {
        contentView.frame = CGRectMake(tabBarController.view.bounds.origin.x,
                                       tabBarController.view.bounds.origin.y,
                                       tabBarController.view.bounds.size.width,
                                       tabBarController.view.bounds.size.height - tabBarController.tabBar.frame.size.height);
    }
    tabBarController.tabBar.hidden = hide;
}

- (void)setHideMaster:(bool)hideMaster
{
    if (!self.masterVc) return;
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
    if (!_fullscreenItem)
        _fullscreenItem = [self getBarItem:@"arrowleft".navItemImgName action:@selector(fullscreen:) size:22];
    return _fullscreenItem;
}

- (UIBarButtonItem *)exitfsItem
{
    if (!_exitfsItem)
        _exitfsItem = [self getBarItem:@"arrowright".navItemImgName action:@selector(exitfullscreen:) size:22];
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
    if (_preViewItem != file) return;
    if (self.state != PREVIEW_DOWNLOADING) {
        [self refreshView];
        return;
    }
    if (!res) {
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:@"Failed to download file '%@'",self.preViewItem.previewItemTitle]];
        [self setPreViewItem:nil master:nil];
    } else {
        [self.progressView configureViewWithItem:self.preViewItem completeness:percent];
        if (percent == 100) [self refreshView];
    }
}

- (void)entryChanged:(SeafBase *)entry
{
    [self refreshView];
}
- (void)entry:(SeafBase *)entry contentUpdated:(BOOL)updated completeness:(int)percent
{
    if (updated || self.state == PREVIEW_DOWNLOADING)
        [self fileContentLoaded:(SeafFile *)entry result:YES completeness:percent];
}

- (void)entryContentLoadingFailed:(int)errCode entry:(SeafBase *)entry;
{
    [self fileContentLoaded:(SeafFile *)entry result:NO completeness:0];
}

- (void)repoPasswordSet:(SeafBase *)entry WithResult:(BOOL)success;
{
}

#pragma mark - file operations
- (IBAction)comment:(id)sender
{
    UIActionSheet *actionSheet;
    if (IsIpad())
        actionSheet = [[UIActionSheet alloc] initWithTitle:POST_DISCUSSION delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil ];
    else
        actionSheet = [[UIActionSheet alloc] initWithTitle:POST_DISCUSSION delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel") destructiveButtonTitle:nil otherButtonTitles:nil ];
    for (NSDictionary *grp in ((SeafFile *)self.preViewItem).groups) {
        [actionSheet addButtonWithTitle:[grp objectForKey:@"name"]];
    }
    [actionSheet showFromBarButtonItem:self.commentItem animated:YES];
}

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
    SeafTextEditorViewController *editViewController = [[SeafTextEditorViewController alloc] initWithFile:self.preViewItem];
    editViewController.detailViewController = self;
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:editViewController];
    [navController setModalPresentationStyle:UIModalPresentationFullScreen];
    [self presentViewController:navController animated:YES completion:nil];
}


- (IBAction)cancelDownload:(id)sender
{
    [(SeafFile *)self.preViewItem cancelDownload];
    [self setPreViewItem:nil master:nil];
}

- (IBAction)uploadFile:(id)sender
{
    if ([self.preViewItem isKindOfClass:[SeafFile class]]) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [((SeafFile *)self.preViewItem) update:appdelegate.fileVC];
        [appdelegate.fileVC refreshView];
    }
}

- (IBAction)openElsewhere
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
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"There is no app which can open this type of file on this machine", @"There is no app which can open this type of file on this machine")];
    }
}

- (IBAction)export:(id)sender
{
    //image :save album, copy clipboard, print
    //pdf :print
    NSMutableArray *bts = [[NSMutableArray alloc] init];
    SeafFile *file = (SeafFile *)self.preViewItem;
    if ([Utils isImageFile:file.name]) {
        [bts addObject:NSLocalizedString(@"Save to album", @"Save to album")];
        [bts addObject:NSLocalizedString(@"Copy image to clipboard", @"Copy image to clipboard")];
    }
    if ([self isPrintable:file])
        [bts addObject:NSLocalizedString(@"Print", @"Print")];
    if (bts.count == 0) {
        [self openElsewhere];
    } else {
        UIActionSheet *actionSheet;
        if (IsIpad())
            actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil ];
        else
            actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel") destructiveButtonTitle:nil otherButtonTitles:nil ];
        for (NSString *title in bts) {
            [actionSheet addButtonWithTitle:title];
        }
        [actionSheet addButtonWithTitle:NSLocalizedString(@"Open elsewhere...", "Open elsewhere...")];
        [actionSheet showFromBarButtonItem:self.exportItem animated:YES];
    }
}

- (IBAction)share:(id)sender
{
    if (![self.preViewItem isKindOfClass:[SeafFile class]])
        return;

    NSString *email = NSLocalizedString(@"Email", @"Email");
    NSString *copy = NSLocalizedString(@"Copy Link to Clipboard", @"Copy Link to Clipboard");
    UIActionSheet *actionSheet;
    if (IsIpad())
        actionSheet = [[UIActionSheet alloc] initWithTitle:SHARE_TITLE delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:email, copy, nil ];
    else
        actionSheet = [[UIActionSheet alloc] initWithTitle:SHARE_TITLE delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel") destructiveButtonTitle:nil otherButtonTitles:email, copy, nil ];

    [actionSheet showFromBarButtonItem:self.shareItem animated:YES];
}

- (void)thisImage:(UIImage *)image hasBeenSavedInPhotoAlbumWithError:(NSError *)error usingContextInfo:(void *)ctxInfo
{
    Debug("error=%@\n", error);
    SeafFile *file = (__bridge SeafFile *)ctxInfo;

    if (error) {
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to save %@ to album", @"Failed to save %@ to album"), file.name]];
    } else {
        [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Success to save %@ to album", @"Success to save %@ to album"), file.name]];
    }
}

- (void)printFile:(SeafFile *)file
{
    UIPrintInteractionController *pic = [UIPrintInteractionController sharedPrintController];
    if  (pic && [UIPrintInteractionController canPrintURL:file.checkoutURL] ) {
        pic.delegate = self;

        UIPrintInfo *printInfo = [UIPrintInfo printInfo];
        printInfo.outputType = UIPrintInfoOutputGeneral;
        printInfo.jobName = file.name;
        printInfo.duplex = UIPrintInfoDuplexLongEdge;
        pic.printInfo = printInfo;
        pic.showsPageRange = YES;
        pic.printingItem = file.checkoutURL;

        void (^completionHandler)(UIPrintInteractionController *, BOOL, NSError *) =
        ^(UIPrintInteractionController *pic, BOOL completed, NSError *error) {
            if (!completed && error)
                NSLog(@"FAILED! due to error in domain %@ with error code %u",
                      error.domain, error.code);
        };
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            [pic presentFromBarButtonItem:self.exportItem animated:YES
                        completionHandler:completionHandler];
        } else {
            [pic presentAnimated:YES completionHandler:completionHandler];
        }
    }
}

#pragma mark - REComposeViewControllerDelegate
- (void)composeViewController:(REComposeViewController *)composeViewController didFinishWithResult:(REComposeResult)result
{
    if (result == REComposeResultCancelled) {
        [composeViewController dismissViewControllerAnimated:YES completion:nil];
    } else if (result == REComposeResultPosted) {
        NSLog(@"Text: %@", composeViewController.text);
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Sending...", nil)];
        SeafFile *file = (SeafFile *)self.preViewItem;
        NSString *form = [NSString stringWithFormat:@"message=%@&repo_id=%@&path=%@", [composeViewController.text escapedPostForm], file.repoId, [file.path escapedPostForm]];
        NSString *url = [file->connection.address stringByAppendingFormat:API_URL"/html/discussions/%@/", _gid];
        [file->connection sendPost:url repo:nil form:form success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
            [SVProgressHUD dismiss];
            [composeViewController dismissViewControllerAnimated:YES completion:nil];
            NSString *html = [JSON objectForKey:@"html"];
            NSString *js = [NSString stringWithFormat:@"addMessage(\"%@\");", [html stringEscapedForJavasacript]];
            [self.webView stringByEvaluatingJavaScriptFromString:js];
        } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to add discussion", @"Failed to add discussion") duration:1.0];
        }];
    }
}

- (void)popupInputView:(NSString *)title placeholder:(NSString *)tip groupid:(NSString *)gid
{
    REComposeViewController *composeVC = [[REComposeViewController alloc] init];
    composeVC.title = title;
    composeVC.hasAttachment = NO;
    composeVC.delegate = self;
    composeVC.text = @"";
    composeVC.placeholderText = tip;
    composeVC.lineWidth = 0;
    composeVC.navigationBar.tintColor = BAR_COLOR;
    [composeVC presentFromRootViewController];
    _gid = gid;
}

#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)bIndex
{
    buttonIndex = bIndex;
    if (bIndex < 0 || bIndex >= actionSheet.numberOfButtons)
        return;
    SeafFile *file = (SeafFile *)self.preViewItem;
    if ([SHARE_TITLE isEqualToString:actionSheet.title]) {
        if (buttonIndex == 0 || buttonIndex == 1) {
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            if (![appdelegate checkNetworkStatus])
                return;

            if (!file.shareLink) {
                [SVProgressHUD showWithStatus:NSLocalizedString(@"Generate share link ...", @"Generate share link ...")];
                [file generateShareLink:self];
            } else {
                [self generateSharelink:file WithResult:YES];
            }
        }
    } else if ([POST_DISCUSSION isEqualToString:actionSheet.title]) {
        NSArray *groups = ((SeafFile *)self.preViewItem).groups;
        NSString *gid = [[groups objectAtIndex:bIndex] objectForKey:@"id"];
        [self popupInputView:NSLocalizedString(@"Discussion", @"Discussion") placeholder:NSLocalizedString(@"Discussion", @"Discussion") groupid:gid];
    } else {
        NSString *title = [actionSheet buttonTitleAtIndex:bIndex];
        if ([NSLocalizedString(@"Open elsewhere...", @"Open elsewhere...") isEqualToString:title]) {
            [self openElsewhere];
        } else if ([NSLocalizedString(@"Save to album", @"Save to album") isEqualToString:title]) {
            UIImage *img = [UIImage imageWithContentsOfFile:file.previewItemURL.path];
            UIImageWriteToSavedPhotosAlbum(img, self, @selector(thisImage:hasBeenSavedInPhotoAlbumWithError:usingContextInfo:), (void *)CFBridgingRetain(file));
        }  else if ([NSLocalizedString(@"Copy image to clipboard", @"Copy image to clipboard") isEqualToString:title]) {
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            NSData *data = [NSData dataWithContentsOfFile:file.previewItemURL.path];
            [pasteboard setData:data forPasteboardType:file.name];
        } else if ([NSLocalizedString(@"Print", @"Print") isEqualToString:title]) {
            [self printFile:file];
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
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to generate share link of file '%@'", @"Failed to generate share link of file '%@'"), file.name]];
        return;
    }
    [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Generate share link success", @"Generate share link success")];

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
        [self alertWithMessage:NSLocalizedString(@"This function is not supportted yet，you can copy it to the pasteboard and send mail by yourself", @"This function is not supportted yet，you can copy it to the pasteboard and send mail by yourself")];
        return;
    }
    if (![mailClass canSendMail]) {
        [self alertWithMessage:NSLocalizedString(@"The mail account has not been set yet", @"The mail account has not been set yet")];
        return;
    }
    [self displayMailPicker];
}

- (void)displayMailPicker
{
    MFMailComposeViewController *mailPicker = [[MFMailComposeViewController alloc] init];
    mailPicker.mailComposeDelegate = self;

    SeafFile *file = (SeafFile *)self.preViewItem;
    [mailPicker setSubject:[NSString stringWithFormat:NSLocalizedString(@"File '%@' is shared with you using seafile", @"File '%@' is shared with you using seafile"), file.name]];
    NSString *emailBody = [NSString stringWithFormat:NSLocalizedString(@"Hi,<br/><br/>Here is a link to <b>'%@'</b> in my Seafile:<br/><br/> <a href=\"%@\">%@</a>\n\n", @"Hi,<br/><br/>Here is a link to <b>'%@'</b> in my Seafile:<br/><br/> <a href=\"%@\">%@</a>\n\n"), file.name, file.shareLink, file.shareLink];
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

# pragma - PreViewSelectedDelegate
- (void)selectItem:(id<QLPreviewItem, PreViewDelegate>)prevItem
{
    if (self.state != PREVIEW_PHOTO) return;
    _preViewItem = prevItem;
    if ([prevItem isKindOfClass:[SeafFile class]]) {
        ((SeafFile *)prevItem).delegate = self;
        [(SeafFile *)prevItem loadContent:NO];
    }
    self.title = self.preViewItem.previewItemTitle;
    Debug("prevItem=%@, title=%@", prevItem, self.title);
    [self checkNavItems];
}
- (void)willSelect:(id<QLPreviewItem, PreViewDelegate>)prevItem
{
    if (self.state != PREVIEW_PHOTO) return;
    if ([prevItem isKindOfClass:[SeafFile class]])
        [(SeafFile *)prevItem loadContent:NO];
}

- (IBAction)handleSwipe:(UISwipeGestureRecognizer*)recognizer
{
}

- (UIBarButtonItem *)getSpaceBarItem
{
    float spacewidth = 20.0;
    if (!IsIpad())
        spacewidth = 10.0;
    UIBarButtonItem *space = [self getSpaceBarItem:spacewidth];
    return space;
}

@end
