//
//  SeafDetailViewController.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "MWPhotoBrowser.h"
#import "SVProgressHUD.h"

#import "SeafAppDelegate.h"
#import "SeafDetailViewController.h"
#import "FailToPreview.h"
#import "DownloadingProgressView.h"
#import "SeafTextEditorViewController.h"
#import "SeafUploadFile.h"
#import "SeafFileViewController.h"

#import "SeafPhoto.h"
#import "UIViewController+Extend.h"
#import "ExtentedString.h"
#import "Debug.h"



enum SHARE_STATUS {
    SHARE_BY_MAIL = 0,
    SHARE_BY_LINK = 1
};

#define PADDING                  10
#define ACTION_SHEET_OLD_ACTIONS 2000

#define SHARE_TITLE NSLocalizedString(@"How would you like to share this file?", @"Seafile")

@interface SeafDetailViewController ()<UIWebViewDelegate, UIPrintInteractionControllerDelegate, MFMailComposeViewControllerDelegate, MWPhotoBrowserDelegate>
@property (strong, nonatomic) UIPopoverController *masterPopoverController;

@property (retain) QLPreviewController *qlSubViewController;

@property (retain) FailToPreview *failedView;
@property (retain) DownloadingProgressView *progressView;
@property (retain) UIWebView *webView;
@property (retain, nonatomic) MWPhotoBrowser *mwPhotoBrowser;

@property BOOL performingLayout;
@property (retain) NSArray *photos;
@property NSUInteger currentPageIndex;

@property (strong) NSArray *barItemsStar;
@property (strong) NSArray *barItemsUnStar;
@property (strong) UIBarButtonItem *editItem;
@property (strong) UIBarButtonItem *exportItem;
@property (strong) UIBarButtonItem *shareItem;
@property (strong) UIBarButtonItem *backItem;

@property (strong) UIDocumentInteractionController *docController;
@property int shareStatus;

@end


@implementation SeafDetailViewController

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];
    self.qlViewController = [[QLPreviewController alloc] init];
    self.qlViewController.delegate = self;
    self.qlViewController.dataSource = self;
    return self;
}
#pragma mark - Managing the detail item
- (BOOL)previewSuccess
{
    return (self.state == PREVIEW_QL_SUBVIEW) || (self.state == PREVIEW_WEBVIEW) || (self.state == PREVIEW_WEBVIEW_JS);
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
    return self.presentingViewController != nil;
}

- (void)updateNavigation
{
    if ([self isModal])
         [self.navigationItem setLeftBarButtonItem:self.backItem animated:NO];
    self.title = self.preViewItem.previewItemTitle;
    NSMutableArray *array = [[NSMutableArray alloc] init];
    if ([self.preViewItem isKindOfClass:[SeafFile class]]) {
        SeafFile *sfile = (SeafFile *)self.preViewItem;
        if ([sfile isStarred])
            [array addObjectsFromArray:self.barItemsStar];
        else
            [array addObjectsFromArray:self.barItemsUnStar];

        [self.exportItem setEnabled:([self.preViewItem exportURL] != nil)];
    }
    if ([self.preViewItem editable] && [self previewSuccess])
        [array addObject:self.editItem];
    self.navigationItem.rightBarButtonItems = array;
}

- (void)clearPreView
{
    self.failedView.hidden = YES;
    self.progressView.hidden = YES;
    self.qlSubViewController.view.hidden = YES;
    self.webView.hidden = YES;
    [self.webView loadHTMLString:@"" baseURL:nil];
    [self clearPhotosVIew];
}

- (void)updatePreviewState
{
    if (self.state == PREVIEW_PHOTO && self.photos)
        return;

    _state = PREVIEW_NONE;
    if (!self.preViewItem) {
    } else if (self.preViewItem.previewItemURL) {
        if (![QLPreviewController canPreviewItem:self.preViewItem]) {
            _state = PREVIEW_FAILED;
        } else {
            _state = PREVIEW_QL_SUBVIEW;
            if ([self.preViewItem.mime hasPrefix:@"audio"]
                || [self.preViewItem.mime hasPrefix:@"video"]
                || [self.preViewItem.mime isEqualToString:@"image/svg+xml"])
                _state = PREVIEW_WEBVIEW;
            else if([self.preViewItem.mime isEqualToString:@"text/x-markdown"] || [self.preViewItem.mime isEqualToString:@"text/x-seafile"])
                _state = PREVIEW_WEBVIEW_JS;
            else if (!IsIpad()) { // if (!IsIpad()) iPhone >= 10.0
                _state = self.preViewItem.editable ? PREVIEW_WEBVIEW : PREVIEW_QL_MODAL;
            } else if ([self.presentingViewController isKindOfClass:[UITabBarController class]]){//open form 2nd tab
                UITabBarController *tabVC = (UITabBarController*)self.presentingViewController;
                if (tabVC.selectedIndex == 2) {
                    _state = PREVIEW_QL_MODAL;
                }
            }
        }
    } else {
        _state = PREVIEW_DOWNLOADING;
    }
    if (_state != PREVIEW_QL_MODAL) {
        [self clearPreView];
    }
    Debug("preview %@ %@ state: %d", self.preViewItem.name, self.preViewItem.previewItemURL, _state);
}

- (void)refreshView
{
    [self updatePreviewState];
    if (!self.isViewLoaded) return;

    [self updateNavigation];
    CGRect r = CGRectMake(self.view.frame.origin.x, 64, self.view.frame.size.width, self.view.frame.size.height - 64);
    switch (self.state) {
        case PREVIEW_DOWNLOADING:
            Debug (@"DownLoading file %@\n", self.preViewItem.previewItemTitle);
            self.progressView.frame = r;
            self.progressView.hidden = NO;
            [self.progressView configureViewWithItem:self.preViewItem progress:0];
            break;
        case PREVIEW_FAILED:
            Debug ("Can not preview file %@ %@\n", self.preViewItem.previewItemTitle, self.preViewItem.previewItemURL);
            self.failedView.frame = r;
            self.failedView.hidden = NO;
            [self.failedView configureViewWithPrevireItem:self.preViewItem];
            break;
        case PREVIEW_QL_SUBVIEW:
            Debug (@"Preview file %@ mime=%@ QL subview\n", self.preViewItem.previewItemTitle, self.preViewItem.mime);
            self.qlSubViewController.view.frame = r;
            [self.qlSubViewController reloadData];
            self.qlSubViewController.view.hidden = NO;
            break;
        case PREVIEW_QL_MODAL: {
            Debug (@"Preview file %@ mime=%@ QL modal\n", self.preViewItem.previewItemTitle, self.preViewItem.mime);
            [self.qlViewController reloadData];
            if (!self.qlViewController.presentingViewController) {
                if (self.isModal && self.isVisible) { // For preview from SeafFileViewController and SeafStarredFileViewController
                    UIViewController *vc = self.presentingViewController;
                    [vc dismissViewControllerAnimated:NO completion:^{
                        [vc presentViewController:self.qlViewController animated:NO completion:^{
                            [self clearPreView];
                        }];
                    }];
                }
            }
            break;
        }
        case PREVIEW_WEBVIEW_JS:
        case PREVIEW_WEBVIEW: {
            Debug("Preview by webview %@\n", self.preViewItem.previewItemTitle);
            NSURLRequest *request = [[NSURLRequest alloc] initWithURL:self.preViewItem.previewItemURL cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
            if (self.state == PREVIEW_WEBVIEW_JS)
                self.webView.delegate = self;
            else
                self.webView.delegate = nil;
            self.webView.frame = r;
            [self.webView loadRequest:request];
            self.webView.hidden = NO;
            break;
        }
        case PREVIEW_PHOTO:
            Debug("Preview photo %@\n", self.preViewItem.previewItemTitle);
            self.mwPhotoBrowser.view.frame = r;
            break;
        case PREVIEW_NONE:
            break;
        default:
            break;
    }
}

- (void)setPreViewItem:(id<SeafPreView>)item master:(UIViewController<SeafDentryDelegate> *)c
{
    if (self.masterPopoverController != nil)
        [self.masterPopoverController dismissPopoverAnimated:YES];
    if (item) Debug("preview %@", item.previewItemTitle);
    self.masterVc = c;
    self.photos = nil;
    self.preViewItem = item;
    [item load:(self.masterVc ? self.masterVc:self) force:NO];
    [self refreshView];
}

- (void)setPreViewPhotos:(NSArray *)items current:(id<SeafPreView>)item master:(UIViewController<SeafDentryDelegate> *)c
{
    [self clearPreView];
    if (self.masterPopoverController != nil)
        [self.masterPopoverController dismissPopoverAnimated:YES];
    self.masterVc = c;
    NSMutableArray *seafPhotos = [[NSMutableArray alloc] init];
    for (id<SeafPreView> file in items) {
        [file setDelegate:(self.masterVc ? self.masterVc:self)];
        [seafPhotos addObject:[[SeafPhoto alloc] initWithSeafPreviewIem: file]];
    }
    self.photos = seafPhotos;
    _state = PREVIEW_PHOTO;
    Debug("Preview photos PREVIEW_PHOTO: %d, %@ hasCache:%d", self.state, [item name], [item hasCache]);
    self.preViewItem = item;
    self.currentPageIndex = [items indexOfObject:item];
    _mwPhotoBrowser = nil;// force recreate mwPhotoBrowser
    [self.mwPhotoBrowser setCurrentPhotoIndex:self.currentPageIndex];
    [self.view addSubview:self.mwPhotoBrowser.view];
    self.mwPhotoBrowser.view.frame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
    [self.mwPhotoBrowser viewDidAppear:false];
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
        self.edgesForExtendedLayout = UIRectEdgeAll;
    // Do any additional setup after loading the view, typically from a nib.

    self.backItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Back", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(goBack:)];

    self.view.autoresizesSubviews = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;

    self.editItem = [self getBarItem:@"editfile".navItemImgName action:@selector(editFile:)size:18];
    self.exportItem = [self getBarItemAutoSize:@"export".navItemImgName action:@selector(export:)];
    self.shareItem = [self getBarItemAutoSize:@"share".navItemImgName action:@selector(share:)];
    //UIBarButtonItem *deleteItem = [self getBarItemAutoSize:@"delete".navItemImgName action:@selector(delete:)];
    UIBarButtonItem *starItem = [self getBarItem:@"star".navItemImgName action:@selector(unstarFile:)size:24];
    UIBarButtonItem *unstarItem = [self getBarItem:@"unstar".navItemImgName action:@selector(starFile:)size:24];
    UIBarButtonItem *space = [self getSpaceBarItem];
    self.barItemsStar  = [NSArray arrayWithObjects:self.exportItem, space, self.shareItem, space, starItem, space, nil];
    self.barItemsUnStar  = [NSArray arrayWithObjects:self.exportItem, space, self.shareItem, space, unstarItem, space, nil];

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
    self.webView = [[UIWebView alloc] initWithFrame:self.view.frame];
    self.webView.backgroundColor = [UIColor whiteColor];
    self.webView.scalesPageToFit = YES;
    self.webView.autoresizesSubviews = YES;
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.failedView];
    [self.view addSubview:self.progressView];
    [self.view addSubview:self.webView];

    self.qlSubViewController = [[QLPreviewController alloc] init];
    self.qlSubViewController.delegate = self;
    self.qlSubViewController.dataSource = self;
    self.qlSubViewController.navigationItem.leftBarButtonItem = nil;
    self.qlSubViewController.navigationItem.rightBarButtonItem = nil;
    [self addChildViewController:self.qlSubViewController];
    [self.view addSubview:self.qlSubViewController.view];
    [self.qlSubViewController didMoveToParentViewController:self];

    [self.progressView.cancelBt addTarget:self action:@selector(cancelDownload:) forControlEvents:UIControlEventTouchUpInside];
    [self.failedView.openElseBtn addTarget:self action:@selector(openElsewhere:) forControlEvents:UIControlEventTouchUpInside];

    self.view.autoresizesSubviews = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    [self refreshView];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    self.preViewItem = nil;
    self.qlSubViewController = nil;
    self.failedView = nil;
    self.progressView = nil;
    self.docController = nil;
    self.webView = nil;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGRect r = CGRectMake(self.view.frame.origin.x, 64, self.view.frame.size.width, self.view.frame.size.height - 64);
    if (IsIpad()) {
        r = CGRectMake(self.view.frame.origin.x, 0, self.view.frame.size.width, self.view.frame.size.height - 0);
    }
    if (self.state == PREVIEW_QL_SUBVIEW) {
        self.qlSubViewController.view.frame = r;
    } else if (self.state == PREVIEW_PHOTO){
        if (IsIpad()) {
            self.mwPhotoBrowser.view.frame = r;
        } else {
            UIDeviceOrientation orientation = (UIDeviceOrientation)[UIApplication sharedApplication].statusBarOrientation;
            if (orientation == UIDeviceOrientationPortrait || orientation == UIDeviceOrientationPortraitUpsideDown) {
                self.mwPhotoBrowser.view.frame = r;
            } else {
                self.mwPhotoBrowser.view.frame = CGRectMake(self.view.frame.origin.x, 32, self.view.frame.size.width, self.view.frame.size.height - 32);
            }
        }
    } else {
        if (self.view.subviews.count > 1) {
            UIView *v = [self.view.subviews objectAtIndex:0];
            v.frame = r;
        }
    }
}
- (void)viewWillAppear:(BOOL)animated
{
    [self updateNavigation];
    [super viewWillAppear:animated];
}

#pragma mark - Split view

- (void)splitViewController:(UISplitViewController *)splitController willHideViewController:(UIViewController *)viewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)popoverController
{
    [self.navigationItem setLeftBarButtonItem:barButtonItem animated:NO];
    self.masterPopoverController = popoverController;
}

- (void)splitViewController:(UISplitViewController *)splitController willShowViewController:(UIViewController *)viewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    // Called when the view is shown again in the split view, invalidating the button and popover controller.
    [self.navigationItem setLeftBarButtonItem:nil animated:NO];
    self.masterPopoverController = nil;
}

- (BOOL)splitViewController:(UISplitViewController *)svc shouldHideViewController:(UIViewController *)vc inOrientation:(UIInterfaceOrientation)orientation
{
    return !UIInterfaceOrientationIsLandscape(orientation);
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }
    [super viewWillDisappear:animated];
}

#pragma mark - SeafDentryDelegate
- (void)download:(SeafBase *)entry progress:(float)progress
{
    if (_preViewItem != entry) return;

    if (self.state == PREVIEW_PHOTO) {
        SeafPhoto *photo = [self getSeafPhoto:(id<SeafPreView>)entry];
        if (photo != nil)
            [photo setProgress:progress];
        return;
    }
    if (self.state != PREVIEW_DOWNLOADING) {
        [self refreshView];
    } else
        [self.progressView configureViewWithItem:self.preViewItem progress:progress];
}

- (void)download:(SeafBase *)entry complete:(BOOL)updated
{
    if (self.state == PREVIEW_PHOTO) {
        SeafPhoto *photo = [self getSeafPhoto:(id<SeafPreView>)entry];
        if (photo == nil)
            return;
        [photo complete:updated error:nil];
        [self updateNavigation];
        return;
    }
    if (_preViewItem != entry) return;
    if (updated) {
        [self refreshView];
    }
}

- (void)showDownloadError:(NSString *)filename
{
    if (self.isVisible) {
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to download file '%@'", @"Seafile"), self.preViewItem.previewItemTitle]];
    }
}

- (void)download:(SeafBase *)entry failed:(NSError *)error
{
    Debug("Failed to download %@ : %@ ", entry.name, error);
    if (self.state == PREVIEW_PHOTO) {
        SeafPhoto *photo = [self getSeafPhoto:(id<SeafPreView>)entry];
        if (photo == nil) return;
        if (self.preViewItem == entry) {
            [self showDownloadError:self.preViewItem.previewItemTitle];
        }
        NSError *error = [NSError errorWithDomain:[NSString stringWithFormat:@"Failed to download file '%@'",self.preViewItem.previewItemTitle] code:-1 userInfo:nil];
        [photo complete:false error:error];
        return;
    }

    if (self.preViewItem != entry || self.preViewItem.hasCache)
        return;

    [self showDownloadError:self.preViewItem.previewItemTitle];
    [self setPreViewItem:nil master:nil];
}

#pragma mark - file operations
- (IBAction)delete:(id)sender
{
    if (_masterVc && [_masterVc isKindOfClass:[SeafFileViewController class]]) {
        [(SeafFileViewController *)_masterVc deleteFile:(SeafFile *)self.preViewItem];
    }
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
        [self alertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"File '%@' is too large to edit", @"Seafile"), self.preViewItem.name]];
        return;
    }
    if (!self.preViewItem.strContent) {
        [self alertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Failed to identify the coding of '%@'", @"Seafile"), self.preViewItem.name]];
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
    id<SeafPreView> item = self.preViewItem;
    [self setPreViewItem:nil master:nil];
    [item cancelAnyLoading];
    if (!IsIpad())
        [self goBack:nil];
}

- (IBAction)openElsewhere:(id)sender
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

- (void)showAlertWithAction:(NSArray *)arr fromBarItem:(UIBarButtonItem *)item withTitle:(NSString *)title
{
    UIAlertController *alert = [self generateAlert:arr withTitle:title handler:^(UIAlertAction *action) {
        [self handleAction:action.title];
    }];
    alert.popoverPresentationController.barButtonItem = item;
    [self presentViewController:alert animated:true completion:nil];
}

- (IBAction)export:(id)sender
{
    if (![self.preViewItem isKindOfClass:[SeafFile class]]) return;

    //image :save album, copy clipboard, print
    //pdf :print
    NSMutableArray *bts = [[NSMutableArray alloc] init];
    SeafFile *file = (SeafFile *)self.preViewItem;
    if ([Utils isImageFile:file.name]) {
        [bts addObject:NSLocalizedString(@"Save to album", @"Seafile")];
        [bts addObject:NSLocalizedString(@"Copy image to clipboard", @"Seafile")];
    } else if ([Utils isVideoFile:file.name]) {
        [bts addObject:NSLocalizedString(@"Save to album", @"Seafile")];
    }
    if ([self isPrintable:file])
        [bts addObject:NSLocalizedString(@"Print", @"Seafile")];
    if (bts.count == 0) {
        [self openElsewhere:nil];
    } else {
        [bts addObject:NSLocalizedString(@"Open elsewhere...", "Seafile")];
        [self showAlertWithAction:bts fromBarItem:self.exportItem withTitle:nil];
    }
}

- (IBAction)share:(id)sender
{
    if (![self.preViewItem isKindOfClass:[SeafFile class]]) return;
    [self.preViewItem setDelegate:self];
    NSString *email = NSLocalizedString(@"Email", @"Seafile");
    NSString *copy = NSLocalizedString(@"Copy Link to Clipboard", @"Seafile");
    [self showAlertWithAction:[NSArray arrayWithObjects:email, copy, nil] fromBarItem:self.shareItem withTitle:SHARE_TITLE];
}

- (void)savedToPhotoAlbumWithError:(NSError *)error file:(SeafFile *)file
{
    if (error) {
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to save %@ to album", @"Seafile"), file.name]];
    } else {
        [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Succeeded to save %@ to album", @"Seafile"), file.name]];
    }
}
- (void)thisImage:(UIImage *)image hasBeenSavedInPhotoAlbumWithError:(NSError *)error usingContextInfo:(void *)ctxInfo
{
    SeafFile *file = (__bridge SeafFile *)ctxInfo;
    [self savedToPhotoAlbumWithError:error file:file];
}

- (void)video: (NSString *)videoPath didFinishSavingWithError:(NSError *)error contextInfo:(void *)ctxInfo
{
    SeafFile *file = (__bridge SeafFile *)ctxInfo;
    [self savedToPhotoAlbumWithError:error file:file];
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

- (void)handleAction:(NSString *)title
{
    SeafFile *file = (SeafFile *)self.preViewItem;
    if ([NSLocalizedString(@"Open elsewhere...", @"Seafile") isEqualToString:title]) {
        [self performSelector:@selector(openElsewhere:) withObject:nil afterDelay:0.0f];
    } else if ([NSLocalizedString(@"Save to album", @"Seafile") isEqualToString:title]) {
        if ([Utils isImageFile:file.name]) {
            UIImage *img = [UIImage imageWithContentsOfFile:file.previewItemURL.path];
            UIImageWriteToSavedPhotosAlbum(img, self, @selector(thisImage:hasBeenSavedInPhotoAlbumWithError:usingContextInfo:), (void *)CFBridgingRetain(file));
        } else {
            Debug("Save video %@ to album", file.previewItemURL.path);
            UISaveVideoAtPathToSavedPhotosAlbum(file.previewItemURL.path, self, @selector(video:didFinishSavingWithError:contextInfo:), (void *)CFBridgingRetain(file));
        }
    }  else if ([NSLocalizedString(@"Copy image to clipboard", @"Seafile") isEqualToString:title]) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        NSData *data = [NSData dataWithContentsOfFile:file.previewItemURL.path];
        [pasteboard setData:data forPasteboardType:file.name];
    } else if ([NSLocalizedString(@"Print", @"Seafile") isEqualToString:title]) {
        [self printFile:file];
    } else if ([NSLocalizedString(@"Email", @"Seafile") isEqualToString:title]
               || [NSLocalizedString(@"Copy Link to Clipboard", @"Seafile") isEqualToString:title]) {
        if (![self checkNetworkStatus])
            return;

        if ([NSLocalizedString(@"Email", @"Seafile") isEqualToString:title])
            _shareStatus = SHARE_BY_MAIL;
        else
            _shareStatus = SHARE_BY_LINK;
        if (!file.shareLink) {
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Generate share link ...", @"Seafile")];
            [file generateShareLink:self];
        } else {
            [self generateSharelink:file WithResult:YES];
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
    Debug("file %@ sharelink;%@", file.name, file.shareLink);

    if (_shareStatus == SHARE_BY_MAIL) {
        [self sendMailInApp:file.name shareLink:file.shareLink];
    } else if (_shareStatus == SHARE_BY_LINK){
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        [pasteboard setString:file.shareLink];
    }
}

#pragma mark - sena mail inside app
- (void)sendMailInApp:(NSString *)name shareLink:(NSString *)shareLink
{
    Debug("send mail: %@", shareLink);
    Class mailClass = (NSClassFromString(@"MFMailComposeViewController"));
    if (!mailClass) {
        [self alertWithTitle:NSLocalizedString(@"This function is not supportted yet，you can copy it to the pasteboard and send mail by yourself", @"Seafile")];
        return;
    }
    if (![mailClass canSendMail]) {
        [self alertWithTitle:NSLocalizedString(@"The mail account has not been set yet", @"Seafile")];
        return;
    }
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    MFMailComposeViewController *mailPicker = appdelegate.globalMailComposer;
    mailPicker.mailComposeDelegate = self;

    [mailPicker setSubject:[NSString stringWithFormat:NSLocalizedString(@"File '%@' is shared with you using %@", @"Seafile"), name, APP_NAME]];
    NSString *emailBody = [NSString stringWithFormat:NSLocalizedString(@"Hi,<br/><br/>Here is a link to <b>'%@'</b> in my %@:<br/><br/> <a href=\"%@\">%@</a>\n\n", @"Seafile"), name, APP_NAME, shareLink, shareLink];
    [mailPicker setMessageBody:emailBody isHTML:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self presentViewController:mailPicker animated:YES completion:nil];
    });
}
#pragma mark - MFMailComposeViewControllerDelegate
- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
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
    [self dismissViewControllerAnimated:YES completion:^{
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate cycleTheGlobalMailComposer];
    }];

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
    float spacewidth = IsIpad() ? 20.0f : 8.0f;
    UIBarButtonItem *space = [self getSpaceBarItem:spacewidth];
    return space;
}

#pragma -mark QLPreviewControllerDataSource
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller
{
    if (self.state != PREVIEW_QL_SUBVIEW && self.state != PREVIEW_QL_MODAL)
        return 0;
    return 1;
}

- (id <QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index;
{
    if (!ios7 && index < 0) index = 0;
    if (index < 0 || index >= 1) {
        return nil;
    }
    return self.preViewItem;
}

- (MWPhotoBrowser *)mwPhotoBrowser
{
    if (!_mwPhotoBrowser) {
        _mwPhotoBrowser = [[MWPhotoBrowser alloc] initWithDelegate:self];
        _mwPhotoBrowser.displayActionButton = false;
        _mwPhotoBrowser.displayNavArrows = false;
        _mwPhotoBrowser.displaySelectionButtons = false;
        _mwPhotoBrowser.alwaysShowControls = false;
        _mwPhotoBrowser.zoomPhotosToFill = YES;
        _mwPhotoBrowser.enableGrid = true;
        _mwPhotoBrowser.startOnGrid = false;
        _mwPhotoBrowser.enableSwipeToDismiss = true;
        _mwPhotoBrowser.backgroundColor = [UIColor whiteColor];
        _mwPhotoBrowser.trackTintColor = SEAF_COLOR_LIGHT;
        _mwPhotoBrowser.progressColor = SEAF_COLOR_DARK;
        _mwPhotoBrowser.preLoadNumLeft = 0;
        _mwPhotoBrowser.preLoadNumRight = 1;
    }
    return _mwPhotoBrowser;
}

- (SeafPhoto *)getSeafPhoto:(id<SeafPreView>)photo {
    for (SeafPhoto *sphoto in _photos) {
        if (sphoto.file == photo) {
            return sphoto;
        }
    }
    return nil;
}

- (void)clearPhotosVIew
{
    [_mwPhotoBrowser.view removeFromSuperview];
    _photos = nil;
}

#pragma mark - MWPhotoBrowserDelegate
- (NSUInteger)numberOfPhotosInPhotoBrowser:(MWPhotoBrowser *)photoBrowser {
    if (!self.photos) return 0;
    return self.photos.count;
}

- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index {
    if (index < self.photos.count) {
        return [self.photos objectAtIndex:index];
    }
    return nil;
}

- (NSString *)photoBrowser:(MWPhotoBrowser *)photoBrowser titleForPhotoAtIndex:(NSUInteger)index
{
    if (index < self.photos.count) {
        SeafPhoto *photo = [self.photos objectAtIndex:index];
        return photo.file.name;
    } else {
        Warning("index %lu out of bound %lu", (unsigned long)index, (unsigned long)self.photos.count);
        return nil;
    }
}

- (void)photoBrowser:(MWPhotoBrowser *)photoBrowser didDisplayPhotoAtIndex:(NSUInteger)index
{
    if (index >= self.photos.count) return;
    NSUInteger previousCurrentPage = _currentPageIndex;
    _currentPageIndex = index;
    id<SeafPreView> pre = self.preViewItem;
    self.preViewItem = [[self.photos objectAtIndex:index] file];
    if (_currentPageIndex != previousCurrentPage) {
        if (IsIpad() && [self.masterVc isKindOfClass: [SeafFileViewController class]]) {
            SeafFileViewController *c = (SeafFileViewController *)self.masterVc;
            [c photoSelectedChanged:pre to:self.preViewItem];
        }
    }
    [self updateNavigation];
}

@end
