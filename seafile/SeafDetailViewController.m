//
//  SeafDetailViewController.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafDetailViewController.h"
#import "FailToPreview.h"
#import "DownloadingProgressView.h"
#import "SeafTextEditorViewController.h"
#import "SeafUploadFile.h"
#import "REComposeViewController.h"
#import "SeafPhotoView.h"
#import "SeafFileViewController.h"

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

#define PADDING                  10
#define ACTION_SHEET_OLD_ACTIONS 2000

#define SHARE_TITLE NSLocalizedString(@"How would you like to share this file?", @"Seafile")
#define POST_DISCUSSION NSLocalizedString(@"Post a discussion to group", @"Seafile")

@interface SeafDetailViewController ()<UIWebViewDelegate, UIActionSheetDelegate, UIPrintInteractionControllerDelegate, MFMailComposeViewControllerDelegate, REComposeViewControllerDelegate, QLPreviewControllerDelegate, QLPreviewControllerDataSource, UIScrollViewDelegate>
@property (strong, nonatomic) UIPopoverController *masterPopoverController;

@property (retain) QLPreviewController *fileViewController;
@property (retain) FailToPreview *failedView;
@property (retain) DownloadingProgressView *progressView;
@property (retain) UIWebView *webView;

@property (retain, nonatomic) UIScrollView *pagingScrollView;
@property CGRect previousLayoutBounds;
@property BOOL performingLayout;
@property BOOL rotating;
@property BOOL viewIsActive;
@property (retain) NSArray *photos;
@property (retain) NSMutableSet *visiblePages;
@property (retain) NSMutableSet *recycledPages;
@property NSUInteger currentPageIndex;

@property int state;

@property (strong) NSArray *barItemsStar;
@property (strong) NSArray *barItemsUnStar;
@property (strong) UIBarButtonItem *editItem;
@property (strong) UIBarButtonItem *exportItem;
@property (strong) UIBarButtonItem *shareItem;
@property (strong) UIBarButtonItem *commentItem;

@property (strong, nonatomic) UIBarButtonItem *fullscreenItem;
@property (strong, nonatomic) UIBarButtonItem *exitfsItem;
@property (strong, nonatomic) UIBarButtonItem *leftItem;

@property (strong) UIDocumentInteractionController *docController;
@property int buttonIndex;
@property (readwrite, nonatomic) bool hideMaster;
@property (readwrite, nonatomic) NSString *gid;

@property (strong) UIActionSheet *actionSheet;

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
        if ([UIPrintInteractionController canPrintURL:file.exportURL])
            return true;
    }
    return false;
}
- (BOOL)isModal
{
    return self.presentingViewController.presentedViewController == self
    || self.navigationController.presentingViewController.presentedViewController == self.navigationController
    || [self.tabBarController.presentingViewController isKindOfClass:[UITabBarController class]];
}

- (void)updateNavigation
{
    self.title = self.preViewItem.previewItemTitle;
    NSMutableArray *array = [[NSMutableArray alloc] init];
    if ([self.preViewItem isKindOfClass:[SeafFile class]]) {
        SeafFile *sfile = (SeafFile *)self.preViewItem;
        if ([sfile isStarred])
            [array addObjectsFromArray:self.barItemsStar];
        else
            [array addObjectsFromArray:self.barItemsUnStar];

        [self.exportItem setEnabled:([self.preViewItem exportURL] != nil)];
        if (sfile.groups.count > 0) {
            [array addObject:self.commentItem];
            [array addObject:[self getSpaceBarItem]];
        }
    }
    if ([self.preViewItem editable] && [self previewSuccess])
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
    if (!self.isViewLoaded) return;
    NSURLRequest *request;
    if (self.state == PREVIEW_PHOTO && !self.photos)
        [self clearPhotosVIew];
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

    [self updateNavigation];
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
            [self.fileViewController reloadData];
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
            Debug("Preview photo %@\n", self.preViewItem.previewItemTitle);
            if (!self.preViewItem.isDownloading) {
                SeafPhotoView *page = [self pageDisplayingPhoto:(SeafFile *)self.preViewItem];
                [page displayImage];
                if ([self.preViewItem hasCache]) {
                    [self loadAdjacentPhotosIfNecessary:(SeafFile *)self.preViewItem];
                }
            }
            break;
        case PREVIEW_NONE:
            break;
        default:
            break;
    }
}

- (void)setPreViewItem:(id<SeafPreView>)item master:(UIViewController *)c
{
    if (self.masterPopoverController != nil)
        [self.masterPopoverController dismissPopoverAnimated:YES];
    Debug("preview %@", item.previewItemTitle);
    self.masterVc = c;
    self.photos = nil;
    self.preViewItem = item;
    if (IsIpad() && UIInterfaceOrientationIsLandscape(self.interfaceOrientation) && !self.hideMaster && self.masterVc) {
        if (_preViewItem == nil)
            self.navigationItem.leftBarButtonItem = nil;
        else
            self.navigationItem.leftBarButtonItem = self.fullscreenItem;
    }
    [item load:self force:NO];
    [self refreshView];
}

- (void)setPreViewItems:(NSArray *)items current:(id<SeafPreView>)item master:(UIViewController *)c
{
    [self clearPreView];
    if (self.masterPopoverController != nil)
        [self.masterPopoverController dismissPopoverAnimated:YES];
    self.masterVc = c;
    self.photos = items;
    self.state = PREVIEW_PHOTO;
    self.preViewItem = item;
    self.currentPageIndex = [items indexOfObject:item];
    [self.view addSubview:self.pagingScrollView];
    if (IsIpad() && UIInterfaceOrientationIsLandscape(self.interfaceOrientation) && !self.hideMaster && self.masterVc) {
        if (_preViewItem == nil)
            self.navigationItem.leftBarButtonItem = nil;
        else
            self.navigationItem.leftBarButtonItem = self.fullscreenItem;
    }
    [self setupPhotosView];
    [self updateNavigation];
    [self.view setNeedsLayout];
}

- (void)goBack:(id)sender
{
    if (self.isModal)
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    else
        [self.navigationController popViewControllerAnimated:NO];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    // Do any additional setup after loading the view, typically from a nib.

    if (self.isModal) {
        UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Back", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(goBack:)];
        [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    }
    self.view.autoresizesSubviews = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;

    self.editItem = [self getBarItem:@"editfile".navItemImgName action:@selector(editFile:)size:18];
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
    self.fileViewController = [[QLPreviewController alloc] init];
    self.fileViewController.delegate = self;
    self.fileViewController.dataSource = self;
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
    [super viewWillLayoutSubviews];
    if (IsIpad() && self.hideMaster && ios7) {
        self.view.frame = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y, self.view.frame.size.width, self.view.frame.size.height + self.splitViewController.tabBarController.tabBar.frame.size.height);
    }
    CGRect r = CGRectMake(self.view.frame.origin.x, 0, self.view.frame.size.width, self.view.frame.size.height);
    if (self.state == PREVIEW_SUCCESS) {
        self.fileViewController.view.frame = r;
    } else if (self.state == PREVIEW_PHOTO){
        [self layoutVisiblePages];
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
    [self.splitViewController willRotateToInterfaceOrientation:[UIApplication sharedApplication].statusBarOrientation duration:0];
    _rotating = NO;
    [self.splitViewController.view setNeedsLayout];
}

- (IBAction)fullscreen:(id)sender
{
    self.hideMaster = YES;
    self.navigationItem.leftBarButtonItem = self.exitfsItem;
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
    _rotating = YES;
    if (IsIpad()) self.splitViewController.delegate = self;
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
    if (self.state == PREVIEW_SUCCESS)
        [self layoutVisiblePages];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    _rotating = NO;
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

- (void)entry:(SeafBase *)entry updated:(BOOL)updated progress:(int)percent
{
    if (_preViewItem != entry) return;
    if (updated || self.state == PREVIEW_DOWNLOADING)
        [self fileContentLoaded:(SeafFile *)entry result:YES completeness:percent];
    else if (self.state == PREVIEW_PHOTO) {
        SeafPhotoView *page = [self pageDisplayingPhoto:(SeafFile *)self.preViewItem];
        [page setProgress:percent *1.0f/100];
    }
}

- (void)entry:(SeafBase *)entry downloadingFailed:(NSUInteger)errCode;
{
    Debug("Failed to download %@ : %ld ", entry.name, (long)errCode);
    if (self.preViewItem != entry) return;
    if (self.state == PREVIEW_PHOTO) {
        if (self.preViewItem.hasCache)   return;
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:@"Failed to download file '%@'",self.preViewItem.previewItemTitle]];
        SeafPhotoView *page = [self pageDisplayingPhoto:(SeafFile *)self.preViewItem];
        [page displayImageFailure];
    } else
        [self fileContentLoaded:(SeafFile *)entry result:NO completeness:0];
}

- (void)entry:(SeafBase *)entry repoPasswordSet:(BOOL)success;
{
    Debug("Repo password set: %d", success);
}

#pragma mark - file operations
- (IBAction)comment:(id)sender
{
    if (self.actionSheet) {
        [self.actionSheet dismissWithClickedButtonIndex:-1 animated:NO];
        self.actionSheet = nil;
        return;
    }
    NSString *cancelTitle = IsIpad() ? nil : NSLocalizedString(@"Cancel", @"Seafile");
    self.actionSheet = [[UIActionSheet alloc] initWithTitle:POST_DISCUSSION delegate:self cancelButtonTitle:cancelTitle destructiveButtonTitle:nil otherButtonTitles:nil ];
    for (NSDictionary *grp in ((SeafFile *)self.preViewItem).groups) {
        [self.actionSheet addButtonWithTitle:[grp objectForKey:@"name"]];
    }
    [self.actionSheet showFromBarButtonItem:self.commentItem animated:YES];
}

- (IBAction)starFile:(id)sender
{
    [(SeafFile *)self.preViewItem setStarred:YES];
    [self updateNavigation];
}

- (IBAction)unstarFile:(id)sender
{
    [(SeafFile *)self.preViewItem setStarred:NO];
    [self updateNavigation];
}

- (IBAction)editFile:(id)sender
{
    if (self.preViewItem.filesize > 10 * 1024 * 1024) {
        [self alertWithMessage:[NSString stringWithFormat:NSLocalizedString(@"File '%@' is too large to edit", @"Seafile"), self.preViewItem.name]];
        return;
    }
    if (!self.preViewItem.strContent) {
        [self alertWithMessage:[NSString stringWithFormat:NSLocalizedString(@"Failed to identify the coding of '%@'", @"Seafile"), self.preViewItem.name]];
        return;
    }
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
    if (!IsIpad())
        [self goBack:nil];
}

- (IBAction)openElsewhere
{
    NSURL *url = [self.preViewItem exportURL];
    if (!url)   return;

    if (self.docController)
        [self.docController dismissMenuAnimated:NO];
    self.docController = [UIDocumentInteractionController interactionControllerWithURL:url];
    BOOL ret = [self.docController presentOpenInMenuFromBarButtonItem:self.exportItem animated:YES];
    if (ret == NO) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"There is no app which can open this type of file on this machine", @"Seafile")];
    }
}

- (IBAction)export:(id)sender
{
    if (![self.preViewItem isKindOfClass:[SeafFile class]]) return;

    //image :save album, copy clipboard, print
    //pdf :print
    if (self.actionSheet) {
        [self.actionSheet dismissWithClickedButtonIndex:-1 animated:NO];
        self.actionSheet = nil;
        return;
    }

    NSMutableArray *bts = [[NSMutableArray alloc] init];
    SeafFile *file = (SeafFile *)self.preViewItem;
    if ([Utils isImageFile:file.name]) {
        [bts addObject:NSLocalizedString(@"Save to album", @"Seafile")];
        [bts addObject:NSLocalizedString(@"Copy image to clipboard", @"Seafile")];
    }
    if ([self isPrintable:file])
        [bts addObject:NSLocalizedString(@"Print", @"Seafile")];
    if (bts.count == 0) {
        [self openElsewhere];
    } else {
        NSString *cancelTitle = IsIpad() ? nil : NSLocalizedString(@"Cancel", @"Seafile");
        self.actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:cancelTitle destructiveButtonTitle:nil otherButtonTitles:nil ];
        for (NSString *title in bts) {
            [self.actionSheet addButtonWithTitle:title];
        }
        [self.actionSheet addButtonWithTitle:NSLocalizedString(@"Open elsewhere...", "Seafile")];
        [self.actionSheet showFromBarButtonItem:self.exportItem animated:YES];
    }
}

- (IBAction)share:(id)sender
{
    if (![self.preViewItem isKindOfClass:[SeafFile class]]) return;
    if (self.actionSheet) {
        [self.actionSheet dismissWithClickedButtonIndex:-1 animated:NO];
        self.actionSheet = nil;
        return;
    }

    NSString *email = NSLocalizedString(@"Email", @"Seafile");
    NSString *copy = NSLocalizedString(@"Copy Link to Clipboard", @"Seafile");
    if (IsIpad())
        self.actionSheet = [[UIActionSheet alloc] initWithTitle:SHARE_TITLE delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:email, copy, nil ];
    else
        self.actionSheet = [[UIActionSheet alloc] initWithTitle:SHARE_TITLE delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"Seafile") destructiveButtonTitle:nil otherButtonTitles:email, copy, nil ];

    [self.actionSheet showFromBarButtonItem:self.shareItem animated:YES];
}

- (void)thisImage:(UIImage *)image hasBeenSavedInPhotoAlbumWithError:(NSError *)error usingContextInfo:(void *)ctxInfo
{
    Debug("error=%@\n", error);
    SeafFile *file = (__bridge SeafFile *)ctxInfo;

    if (error) {
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to save %@ to album", @"Seafile"), file.name]];
    } else {
        [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Success to save %@ to album", @"Seafile"), file.name]];
    }
}

- (void)printFile:(SeafFile *)file
{
    UIPrintInteractionController *pic = [UIPrintInteractionController sharedPrintController];
    if  (pic && [UIPrintInteractionController canPrintURL:file.exportURL] ) {
        pic.delegate = self;

        UIPrintInfo *printInfo = [UIPrintInfo printInfo];
        printInfo.outputType = UIPrintInfoOutputGeneral;
        printInfo.jobName = file.name;
        printInfo.duplex = UIPrintInfoDuplexLongEdge;
        pic.printInfo = printInfo;
        pic.showsPageRange = YES;
        pic.printingItem = file.exportURL;

        void (^completionHandler)(UIPrintInteractionController *, BOOL, NSError *) =
        ^(UIPrintInteractionController *pic, BOOL completed, NSError *error) {
            if (!completed && error)
                NSLog(@"FAILED! due to error in domain %@ with error code %ld",
                      error.domain, (long)error.code);
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
        Debug("Text: %@", composeViewController.text);
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Sending...", @"Seafile")];
        SeafFile *file = (SeafFile *)self.preViewItem;
        NSString *form = [NSString stringWithFormat:@"message=%@&repo_id=%@&path=%@", [composeViewController.text escapedPostForm], file.repoId, [file.path escapedPostForm]];
        NSString *url = [NSString stringWithFormat:API_URL"/html/discussions/%@/", _gid];
        [file->connection sendPost:url form:form success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
            [SVProgressHUD dismiss];
            [composeViewController dismissViewControllerAnimated:YES completion:nil];
            NSString *html = [JSON objectForKey:@"html"];
            NSString *js = [NSString stringWithFormat:@"addMessage(\"%@\");", [html stringEscapedForJavasacript]];
            [self.webView stringByEvaluatingJavaScriptFromString:js];
        } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to add discussion", @"Seafile") duration:1.0];
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
    self.actionSheet = nil;
    buttonIndex = (int)bIndex;
    if (bIndex < 0 || bIndex >= actionSheet.numberOfButtons)
        return;
    SeafFile *file = (SeafFile *)self.preViewItem;
    if ([SHARE_TITLE isEqualToString:actionSheet.title]) {
        if (buttonIndex == 0 || buttonIndex == 1) {
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            if (![appdelegate checkNetworkStatus])
                return;

            if (!file.shareLink) {
                [SVProgressHUD showWithStatus:NSLocalizedString(@"Generate share link ...", @"Seafile")];
                [file generateShareLink:self];
            } else {
                [self generateSharelink:file WithResult:YES];
            }
        }
    } else if ([POST_DISCUSSION isEqualToString:actionSheet.title]) {
        NSArray *groups = ((SeafFile *)self.preViewItem).groups;
        NSString *gid = [[groups objectAtIndex:bIndex] objectForKey:@"id"];
        [self popupInputView:NSLocalizedString(@"Discussion", @"Seafile") placeholder:NSLocalizedString(@"Discussion", @"Seafile") groupid:gid];
    } else {
        NSString *title = [actionSheet buttonTitleAtIndex:bIndex];
        if ([NSLocalizedString(@"Open elsewhere...", @"Seafile") isEqualToString:title]) {
            [self openElsewhere];
        } else if ([NSLocalizedString(@"Save to album", @"Seafile") isEqualToString:title]) {
            UIImage *img = [UIImage imageWithContentsOfFile:file.previewItemURL.path];
            UIImageWriteToSavedPhotosAlbum(img, self, @selector(thisImage:hasBeenSavedInPhotoAlbumWithError:usingContextInfo:), (void *)CFBridgingRetain(file));
        }  else if ([NSLocalizedString(@"Copy image to clipboard", @"Seafile") isEqualToString:title]) {
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            NSData *data = [NSData dataWithContentsOfFile:file.previewItemURL.path];
            [pasteboard setData:data forPasteboardType:file.name];
        } else if ([NSLocalizedString(@"Print", @"Seafile") isEqualToString:title]) {
            [self printFile:file];
        }
    }
}

#pragma mark - SeafShareDelegate
- (void)generateSharelink:(SeafBase*)entry WithResult:(BOOL)success
{
    if (entry != self.preViewItem) {
        [SVProgressHUD dismiss];
        return;
    }

    SeafFile *file = (SeafFile *)self.preViewItem;
    if (!success) {
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to generate share link of file '%@'", @"Seafile"), file.name]];
        return;
    }
    [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Generate share link success", @"Seafile")];

    if (buttonIndex == 0) {
        [self sendMailInApp:file.name shareLink:file.shareLink];
    } else if (buttonIndex == 1){
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        [pasteboard setString:file.shareLink];
    }
}

#pragma mark - sena mail inside app
- (void)sendMailInApp:(NSString *)name shareLink:(NSString *)shareLink
{
    Class mailClass = (NSClassFromString(@"MFMailComposeViewController"));
    if (!mailClass) {
        [self alertWithMessage:NSLocalizedString(@"This function is not supportted yet，you can copy it to the pasteboard and send mail by yourself", @"Seafile")];
        return;
    }
    if (![mailClass canSendMail]) {
        [self alertWithMessage:NSLocalizedString(@"The mail account has not been set yet", @"Seafile")];
        return;
    }

    MFMailComposeViewController *mailPicker = [[MFMailComposeViewController alloc] init];
    mailPicker.mailComposeDelegate = self;

    [mailPicker setSubject:[NSString stringWithFormat:NSLocalizedString(@"File '%@' is shared with you using seafile", @"Seafile"), name]];
    NSString *emailBody = [NSString stringWithFormat:NSLocalizedString(@"Hi,<br/><br/>Here is a link to <b>'%@'</b> in my Seafile:<br/><br/> <a href=\"%@\">%@</a>\n\n", @"Seafile"), name, shareLink, shareLink];
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
        NSString *js = [NSString stringWithFormat:@"setContent(\"%@\");", [self.preViewItem.strContent stringEscapedForJavasacript]];
        [self.webView stringByEvaluatingJavaScriptFromString:js];
    }
}
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    if ([request.URL.absoluteString hasPrefix:@"file://"])
        return YES;
    return NO;
}

- (UIBarButtonItem *)getSpaceBarItem
{
    float spacewidth = 20.0;
    if (!IsIpad())
        spacewidth = 10.0;
    UIBarButtonItem *space = [self getSpaceBarItem:spacewidth];
    return space;
}

#pragma -mark QLPreviewControllerDataSource
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller
{
    return 1;
}

- (id <QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index;
{
    Debug("index=%ld", (long)index);
    if (!ios7 && index < 0) index = 0;
    if (index < 0 || index >= 1) {
        return nil;
    }
    return self.preViewItem;
}

#pragma -mark - pagingScrollView for photots

- (CGRect)frameForPagingScrollView {
    CGRect frame = self.view.bounds;// [[UIScreen mainScreen] bounds];
    frame.origin.x -= PADDING;
    frame.size.width += (2 * PADDING);
    return CGRectIntegral(frame);
}
- (CGRect)frameForPageAtIndex:(NSUInteger)index {
    // We have to use our paging scroll view's bounds, not frame, to calculate the page placement. When the device is in
    // landscape orientation, the frame will still be in portrait because the pagingScrollView is the root view controller's
    // view, so its frame is in window coordinate space, which is never rotated. Its bounds, however, will be in landscape
    // because it has a rotation transform applied.
    CGRect bounds = _pagingScrollView.bounds;
    CGRect pageFrame = bounds;
    pageFrame.size.width -= (2 * PADDING);
    pageFrame.origin.x = (bounds.size.width * index) + PADDING;
    return CGRectIntegral(pageFrame);
}

- (NSUInteger)numberOfPhotos {
    if (!self.photos) return 0;
    return self.photos.count;
}
- (CGSize)contentSizeForPagingScrollView {
    // We have to use the paging scroll view's bounds to calculate the contentSize, for the same reason outlined above.
    CGRect bounds = _pagingScrollView.bounds;
    return CGSizeMake(bounds.size.width * [self numberOfPhotos], bounds.size.height);
}
- (CGPoint)contentOffsetForPageAtIndex:(NSUInteger)index {
    CGFloat pageWidth = _pagingScrollView.bounds.size.width;
    CGFloat newOffset = index * pageWidth;
    return CGPointMake(newOffset, 0);
}

- (UIScrollView *)pagingScrollView
{
    if (!_pagingScrollView) {
        CGRect pagingScrollViewFrame = [self frameForPagingScrollView];
        _pagingScrollView = [[UIScrollView alloc] initWithFrame:pagingScrollViewFrame];
        _pagingScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _pagingScrollView.pagingEnabled = YES;
        _pagingScrollView.delegate = self;
        _pagingScrollView.showsHorizontalScrollIndicator = NO;
        _pagingScrollView.showsVerticalScrollIndicator = NO;
        _pagingScrollView.backgroundColor = [UIColor whiteColor];
        _pagingScrollView.contentSize = [self contentSizeForPagingScrollView];
        _visiblePages = [[NSMutableSet alloc] init];
        _recycledPages = [[NSMutableSet alloc] init];
    }
    return _pagingScrollView;
}
- (BOOL)isDisplayingPageForIndex:(NSUInteger)index {
    for (SeafPhotoView *page in _visiblePages)
        if (page.index == index) return YES;
    return NO;
}
- (SeafPhotoView *)dequeueRecycledPage {
    SeafPhotoView *page = [_recycledPages anyObject];
    if (page) {
        [_recycledPages removeObject:page];
    }
    return page;
}
- (SeafPhotoView *)pageDisplayingPhoto:(id<SeafPreView>)photo {
    SeafPhotoView *thePage = nil;
    for (SeafPhotoView *page in _visiblePages) {
        if (page.photo == photo) {
            thePage = page; break;
        }
    }
    return thePage;
}

- (void)configurePage:(SeafPhotoView *)page forIndex:(NSUInteger)index {
    page.frame = [self frameForPageAtIndex:index];
    page.index = index;
    page.photo = [self.photos objectAtIndex:index];
}

- (void)tilePages
{
    // Calculate which pages should be visible
    // Ignore padding as paging bounces encroach on that
    // and lead to false page loads
    CGRect visibleBounds = _pagingScrollView.bounds;
    NSInteger iFirstIndex = (NSInteger)floorf((CGRectGetMinX(visibleBounds)+PADDING*2) / CGRectGetWidth(visibleBounds));
    NSInteger iLastIndex  = (NSInteger)floorf((CGRectGetMaxX(visibleBounds)-PADDING*2-1) / CGRectGetWidth(visibleBounds));
    if (iFirstIndex < 0) iFirstIndex = 0;
    if (iFirstIndex > [self numberOfPhotos] - 1) iFirstIndex = [self numberOfPhotos] - 1;
    if (iLastIndex < 0) iLastIndex = 0;
    if (iLastIndex > [self numberOfPhotos] - 1) iLastIndex = [self numberOfPhotos] - 1;

    // Recycle no longer needed pages
    NSInteger pageIndex;
    for (SeafPhotoView *page in _visiblePages) {
        pageIndex = page.index;
        if (pageIndex < (NSUInteger)iFirstIndex || pageIndex > (NSUInteger)iLastIndex) {
            [_recycledPages addObject:page];
            [page prepareForReuse];
            [page removeFromSuperview];
            Debug("Removed page at index %lu", (unsigned long)pageIndex);
        }
    }
    [_visiblePages minusSet:_recycledPages];
    while (_recycledPages.count > 2) // Only keep 2 recycled pages
        [_recycledPages removeObject:[_recycledPages anyObject]];

    // Add missing pages
    for (NSUInteger index = (NSUInteger)iFirstIndex; index <= (NSUInteger)iLastIndex; index++) {
        if (![self isDisplayingPageForIndex:index]) {
            // Add new page
            SeafPhotoView *page = [self dequeueRecycledPage];
            if (!page) {
                page = [[SeafPhotoView alloc] initWithPhotoBrowser:self];
            }
            [_visiblePages addObject:page];
            [self configurePage:page forIndex:index];
            [_pagingScrollView addSubview:page];
            Debug("Added page at index %lu subviews=%ld", (unsigned long)index, (long)_pagingScrollView.subviews.count);
        }
    }
}

- (void)setupPhotosView
{
    self.pagingScrollView.contentOffset = [self contentOffsetForPageAtIndex:self.currentPageIndex];
    [self tilePages];
}

- (void)clearPhotosVIew
{
    [self.pagingScrollView removeFromSuperview];
    _pagingScrollView = nil;
    _photos = nil;
    _visiblePages = nil;
    _recycledPages = nil;
    self.state = PREVIEW_NONE;
}


- (void)layoutVisiblePages
{
    _performingLayout = YES;

    // Remember index
    NSUInteger indexPriorToLayout = _currentPageIndex;

    // Get paging scroll view frame to determine if anything needs changing
    CGRect pagingScrollViewFrame = [self frameForPagingScrollView];
    _pagingScrollView.frame = pagingScrollViewFrame;

    // Recalculate contentSize based on current orientation
    self.pagingScrollView.contentSize = [self contentSizeForPagingScrollView];
    // Adjust frames and configuration of each visible page
    for (SeafPhotoView *page in _visiblePages) {
        NSUInteger index = page.index;
        page.frame = [self frameForPageAtIndex:index];
        // Adjust scales if bounds has changed since last time
        if (!CGRectEqualToRect(_previousLayoutBounds, self.view.bounds)) {
            // Update zooms for new bounds
            [page setMaxMinZoomScalesForCurrentBounds];
            _previousLayoutBounds = self.view.bounds;
        }
    }

    // Adjust contentOffset to preserve page location based on values collected prior to location
    _pagingScrollView.contentOffset = [self contentOffsetForPageAtIndex:indexPriorToLayout];
    [self didStartViewingPageAtIndex:_currentPageIndex]; // initial

    // Reset
    _currentPageIndex = indexPriorToLayout;
    _performingLayout = NO;
}

#pragma mark - UIScrollView Delegate
// Handle page changes
- (void)didStartViewingPageAtIndex:(NSUInteger)index {

    if (![self numberOfPhotos]) {
        return;
    }

    // Release images further away than +/-1
    NSUInteger i;
    if (index > 0) {
        // Release anything < index - 1
        for (i = 0; i < index-1; i++) {
            [(id<SeafPreView>)[_photos objectAtIndex:i] unload];
        }
    }
    if (index < [self numberOfPhotos] - 1) {
        // Release anything > index + 1
        for (i = index + 2; i < _photos.count; i++) {
            [(id<SeafPreView>)[_photos objectAtIndex:i] unload];
        }
    }

    // Load adjacent images if needed and the photo is already
    // loaded. Also called after photo has been loaded in background
    [self.preViewItem load:self force:NO];
    if ([self.preViewItem hasCache])
        [self loadAdjacentPhotosIfNecessary:self.preViewItem];

    // Update nav
    [self updateNavigation];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (!self.isVisible || _performingLayout || _rotating) return;
    [self tilePages];

    // Calculate current page
    CGRect visibleBounds = _pagingScrollView.bounds;
    NSInteger index = (NSInteger)(floorf(CGRectGetMidX(visibleBounds) / CGRectGetWidth(visibleBounds)));
    if (index < 0) index = 0;
    if (index > [self numberOfPhotos] - 1) index = [self numberOfPhotos] - 1;
    NSUInteger previousCurrentPage = _currentPageIndex;
    _currentPageIndex = index;
    id<SeafPreView> pre = self.preViewItem;
    self.preViewItem = [self.photos objectAtIndex:index];
    if (_currentPageIndex != previousCurrentPage) {
        [self didStartViewingPageAtIndex:index];
        if (IsIpad() && [self.masterVc isKindOfClass: [SeafFileViewController class]]) {
            SeafFileViewController *c = (SeafFileViewController *)self.masterVc;
            [c photoSelectedChanged:pre to:self.preViewItem];
        }
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    // Update nav when page changes
    [self updateNavigation];
}

- (void)loadAdjacentPhotosIfNecessary:(id<SeafPreView>)photo
{
    NSUInteger index = [self.photos indexOfObject:photo] + 1;
    NSUInteger num = [self numberOfPhotos];
    if (index < num) {
        id<SeafPreView> next = [self.photos objectAtIndex:index];
        if (![next hasCache])
            [next load:self force:NO];
    }
}

@end
