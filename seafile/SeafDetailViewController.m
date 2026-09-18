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
#import "SeafWechatHelper.h"
#import "SeafActionsManager.h"
#import <WebKit/WebKit.h>
#import <QuickLook/QuickLook.h>
#import <SafariServices/SafariServices.h>
#import "SeafDataTaskManager.h"
#import "SeafNavigationBarStyler.h"
#import "SeafSdocWebViewController.h"
#import "SeafTheme.h"
#import "SeafNavLeftItem.h"

extern NSString * const AFNetworkingOperationFailingURLResponseErrorKey;

enum SHARE_STATUS {
    SHARE_BY_MAIL = 0,
    SHARE_BY_LINK = 1
};

#define PADDING                  10
#define ACTION_SHEET_OLD_ACTIONS 2000

#define SHARE_TITLE NSLocalizedString(@"How would you like to share this file?", @"Seafile")

/// Quick Look controller bound to the item it was created for, so the data source
/// never has to read a mutable property that a newer tap may already have changed.
@interface SeafQLPreviewController : QLPreviewController
@property (nonatomic, strong) id<SeafPreView> seafItem;
/// previewItemURL path handed to Quick Look for `seafItem`. A cache hit reports
/// download:complete: with updated=YES too, so this is what tells a real new version
/// (content-addressed temp path changes) apart from "the bytes you already show".
@property (nonatomic, copy) NSString *presentedPath;
@property (nonatomic, assign) BOOL didEditItem;
@end

@implementation SeafQLPreviewController
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.accessibilityIdentifier = @"seafile_quicklook"; // UI tests locate the preview by this
}
@end

@interface SeafDetailViewController ()<MFMailComposeViewControllerDelegate, MWPhotoBrowserDelegate, WKNavigationDelegate, SeafFileUpdateDelegate, QLPreviewControllerDelegate, QLPreviewControllerDataSource>
@property (retain) FailToPreview *failedView;
@property (retain) DownloadingProgressView *progressView;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) MWPhotoBrowser *mwPhotoBrowser;
@property (nonatomic, strong) UITextView *textView;

@property BOOL performingLayout;
@property (retain) NSArray *photos;
@property NSUInteger currentPageIndex;

@property (strong) NSArray *barItemsStar;
@property (strong) NSArray *barItemsUnStar;
@property (strong) UIBarButtonItem *editItem;
@property (strong) UIBarButtonItem *exportItem;
@property (strong) UIBarButtonItem *deleteItem;
@property (strong) UIBarButtonItem *backItem;

@property (strong) UIDocumentInteractionController *docController;
@property int shareStatus;

/// The Quick Look controller this view controller currently owns. A fresh one is used
/// for every preview (a reused instance flashes the previous file before re-rendering),
/// so anything else arriving in a callback is a superseded instance.
@property (nonatomic, strong) SeafQLPreviewController *qlViewController;
/// Next controller, created and view-loaded ahead of time so the system Quick Look
/// extension is already attached when the user taps the next file.
@property (nonatomic, strong) SeafQLPreviewController *spareQuickLook;
/// Presenter and animation named by the caller of -previewItem:master:presentFrom:animated:.
/// Only set for the duration of that call: a preview that opens later on its own (download
/// finished) must not be pushed over whatever the user moved on to.
@property (nonatomic, weak) UIViewController *quickLookPresenter;
@property (nonatomic, assign) BOOL quickLookUnanimated;

@end


@implementation SeafDetailViewController

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];
    return self;
}
#pragma mark - Managing the detail item
// Check if preview was successful based on the current preview state.
- (BOOL)previewSuccess
{
    return (self.state == PREVIEW_WEBVIEW) || (self.state == PREVIEW_WEBVIEW_JS) || (self.state == PREVIEW_TEXT);
}

// Check if the current view controller is presented modally.
- (BOOL)isModal
{
    return self.presentingViewController != nil;
}

// Update navigation items depending on the current state and item properties.
- (void)updateNavigation
{
    if ([self isModal]) {
        [self.navigationItem setLeftBarButtonItem:self.backItem animated:NO];
    } else if (!(IsIpad() && [self isPortrait])
               && ![self.navigationItem.leftBarButtonItem.customView isKindOfClass:[SeafNavLeftItem class]]) {
        // Match the file list back button (SeafNavLeftItem) for push presentations on
        // iPhone and iPad landscape; iPad portrait keeps the split-view displayMode button.
        UIView *backView = [SeafNavLeftItem navLeftItemWithDirectory:nil
                                                                title:@""
                                                               target:self
                                                               action:@selector(goBack:)];
        UIBarButtonItem *customBack = [[UIBarButtonItem alloc] initWithCustomView:backView];
        [self.navigationItem setLeftBarButtonItem:customBack animated:NO];
    }

    // Set title using style tool
    NSString *titleText = self.preViewItem.previewItemTitle;
    if (!self.navigationItem.titleView) {
        UILabel *titleLabel = [SeafNavigationBarStyler createCustomTitleViewWithText:titleText 
                                                             maxWidthPercentage:0.7 
                                                                  viewController:self];
        self.navigationItem.titleView = titleLabel;
    } else {
        [SeafNavigationBarStyler updateTitleView:(UILabel *)self.navigationItem.titleView withText:titleText];
    }
    
    // Restore navigation bar right button display
    NSMutableArray *rightItems = [NSMutableArray array];
    
    // Check current file status to determine which buttons to display
    if ([self.preViewItem isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)self.preViewItem;
        
        // Add edit button (if file is editable)
        if (self.preViewItem.editable && (self.state == PREVIEW_TEXT || self.state == PREVIEW_WEBVIEW || self.state == PREVIEW_WEBVIEW_JS)) {
            [rightItems addObject:self.editItem];
        }
    }
    
    // Set navigation bar right buttons
    if (rightItems.count > 0) {
        self.navigationItem.rightBarButtonItems = rightItems;
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
    
    // Update bottom toolbar button states
    [self updateToolbarButtons];
}

// Clear current preview settings and restore to initial state.
- (void)resetNavigation {
    self.navigationItem.titleView = nil;
    self.navigationItem.rightBarButtonItems = nil;
}

// Clear all views associated with the current preview.
- (void)clearPreView
{
    self.failedView.hidden = YES;
    self.progressView.hidden = YES;
    self.webView.hidden = YES;
    [self.textView removeFromSuperview];
    self.textView = nil;
    [self.webView evaluateJavaScript:@"document.body.innerHTML='';" completionHandler:nil];
    [self clearPhotosVIew];
}

// Update the preview state based on the current item's properties and state.
- (void)updatePreviewState
{
    if (self.state == PREVIEW_PHOTO && self.photos)
        return; // No change needed if already displaying photos

    _state = PREVIEW_NONE;
    if (!self.preViewItem) { // No item to preview

    } else if (self.preViewItem.previewItemURL) {
        _state = PREVIEW_QL_MODAL; // Default state

        /*
         * Special handling: For video files (mime type starts with "video/" or
         * isVideoFile returns YES), Quick Look will internally create its own
         * AVPlayer and keep the MPRemoteCommandCenter targets registered while
         * the app is in background. After the download finishes this hidden
         * player may resume and compete with our custom player for audio
         * output, yielding double-audio issues.
         *
         * Hence, once a video file is detected we skip the Quick Look preview
         * entirely and leave state as PREVIEW_NONE. The real playback is
         * handled later by SeafFileViewController, which presents
         * SeafVideoPlayerViewController after the download completes.
         */
        if ([self.preViewItem isKindOfClass:[SeafFile class]]) {
            SeafFile *videoCheckFile = (SeafFile *)self.preViewItem;
            if ([videoCheckFile isVideoFile] || [videoCheckFile.mime hasPrefix:@"video/"]) {
                _state = PREVIEW_NONE;
                if (_state != PREVIEW_QL_MODAL) {
                    [self clearPreView];
                }
                Debug("preview %@ %@ state: %d (video file skipped QL)", self.preViewItem.name, self.preViewItem.previewItemURL, _state);
                return;
            }
        }
        if ([self.preViewItem.mime isEqualToString:@"image/svg+xml"] || [self.preViewItem.mime isEqualToString:@"application/sdoc"] || [self.preViewItem.mime isEqualToString:@"application/x-exdraw"] || [self.preViewItem.mime isEqualToString:@"application/x-draw"]) {
            _state = PREVIEW_WEBVIEW;
        } else if([self.preViewItem.mime isEqualToString:@"text/x-markdown"] || [self.preViewItem.mime isEqualToString:@"text/x-seafile"]) {
            _state = PREVIEW_WEBVIEW_JS;
        } else if ([self.preViewItem.mime containsString:@"text/"]) {
            _state = PREVIEW_TEXT;
        } else if (!IsIpad()) { // Use Quick Look for non-editable files on iPhone
            _state = self.preViewItem.editable ? PREVIEW_WEBVIEW : PREVIEW_QL_MODAL;
        } else if (![QLPreviewController canPreviewItem:self.preViewItem]) {
            _state = PREVIEW_FAILED; // Mark as failed if Quick Look can't preview the item
        }
    } else {
        _state = PREVIEW_DOWNLOADING; // Set state as downloading if no URL is available
    }
    if (_state != PREVIEW_QL_MODAL) { // Clear the preview if state is not Quick Look modal
        [self clearPreView];
    }
    Debug("preview %@ %@ state: %d", self.preViewItem.name, self.preViewItem.previewItemURL, _state);
}

- (void)refreshView
{
    [self updatePreviewState]; // Update the state based on the current item
    if (!self.isViewLoaded) return;

    [self updateNavigation]; // Update the navigation items

    // --- Toolbar Visibility Control (iPad only) ---
    if (IsIpad()) {
        BOOL shouldShowToolbar = NO;
        // Determine if current preview item is a video file
        BOOL isMediaFile = NO;
        if (self.preViewItem && [self.preViewItem isKindOfClass:[SeafFile class]]) {
            SeafFile *mediaCheckFile = (SeafFile *)self.preViewItem;
            // Hide toolbar for both video and audio file types
            if ([mediaCheckFile isVideoFile] || [mediaCheckFile.mime hasPrefix:@"audio/"]) {
                isMediaFile = YES;
            }
        }
        // Show toolbar only if there is a valid item being previewed successfully or potentially via QL
        if (self.preViewItem && !isMediaFile) {
            switch (self.state) {
                case PREVIEW_WEBVIEW_JS:
                case PREVIEW_WEBVIEW:
                case PREVIEW_TEXT:
                case PREVIEW_PHOTO:
                case PREVIEW_QL_MODAL: // Assume toolbar context is relevant even if QL is modal
                case PREVIEW_FAILED:
                    shouldShowToolbar = YES;
                    break;
                // Don't show for downloading, none states, or explicitly when video
                case PREVIEW_DOWNLOADING:
                case PREVIEW_NONE:
                default:
                    shouldShowToolbar = NO;
                    break;
            }
        } else {
             // No preview item or media file, definitely hide toolbar
             shouldShowToolbar = NO;
        }
        // Only hide/show if toolbarView actually exists
        if (self.toolbarView) {
            self.toolbarView.hidden = !shouldShowToolbar;
        }
    } else {
         // Ensure toolbar is visible on non-iPad devices if it exists
         if (self.toolbarView) {
             self.toolbarView.hidden = NO;
         }
    }
    // --- End Toolbar Visibility Control ---

    CGFloat y = 64;
    if (IsIpad()) {
        y = 0;
    } else {
        y = 44 + [SeafAppDelegate activeWindow].safeAreaInsets.top;
    }
    
    // Calculate bottom margin to account for toolbar, including safe area
    CGFloat bottomMargin = 0;
    if (self.toolbarView && !self.toolbarView.hidden) {
        CGFloat toolbarHeight = 36; // Toolbar standard height
        CGFloat safeAreaBottom = 0;
        safeAreaBottom = self.view.safeAreaInsets.bottom; // Get bottom safe area inset
        bottomMargin = toolbarHeight + safeAreaBottom; // Total height occupied by toolbar
    }
    
    CGRect r = CGRectMake(self.view.frame.origin.x, y, self.view.frame.size.width, self.view.frame.size.height - y - bottomMargin);
    switch (self.state) {
        case PREVIEW_DOWNLOADING:
            Debug (@"DownLoading file %@\n", self.preViewItem.previewItemTitle);
            self.progressView.frame = r;
            self.progressView.hidden = NO;
            [self.progressView configureViewWithItem:self.preViewItem progress:0]; // Initialize progress view
            break;
        case PREVIEW_FAILED:
            Debug ("Can not preview file %@ %@\n", self.preViewItem.previewItemTitle, self.preViewItem.previewItemURL);
            self.failedView.frame = r;
            self.failedView.hidden = NO;
            [self.failedView configureViewWithPrevireItem:self.preViewItem]; // Initialize failure view
            break;
        case PREVIEW_QL_MODAL: {
            Debug (@"Preview file %@ mime=%@ QL modal\n", self.preViewItem.previewItemTitle, self.preViewItem.mime);
            [self presentQuickLookForItem:self.preViewItem];
            break;
        }
        case PREVIEW_WEBVIEW_JS:
        case PREVIEW_WEBVIEW: {
            Debug("Preview by webview %@\n", self.preViewItem.previewItemTitle);
            self.webView.navigationDelegate = self;
            self.webView.frame = r;
            if ([self.preViewItem isKindOfClass:[SeafFile class]]) {
                SeafFile *sFile = (SeafFile *)self.preViewItem;
                if ([sFile isWebOpenFile]) {
                    if ([sFile.mime isEqualToString:@"application/sdoc"]) {
                        NSString *routeUrl = [sFile getWebViewURLString];
                        Debug(@"[SDOC] route to SeafSdocWebViewController, mime=%@ url=%@", sFile.mime, routeUrl);
                        SeafSdocWebViewController *vc = [[SeafSdocWebViewController alloc] initWithFile:sFile fileName:self.preViewItem.previewItemTitle];
                        if (IsIpad()) {
                            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
                            [appdelegate showDetailView:vc];
                            Debug(@"[SDOC] presented SeafSdocWebViewController fullscreen on iPad");
                        } else {
                            [self.navigationController pushViewController:vc animated:YES];
                            Debug(@"[SDOC] pushed SeafSdocWebViewController");
                        }
                        return;
                    }
                    NSString *webViewURLString = [sFile getWebViewURLString];

                    Debug(@"[WEBOPEN] load in WKWebView url=%@", webViewURLString);
                    NSURLRequest *urlRequest = [sFile.connection buildRequest:webViewURLString method:@"GET" form:nil];
                    [self.webView loadRequest:urlRequest];
                } else {
                    [self.webView loadFileURL:self.preViewItem.previewItemURL allowingReadAccessToURL:self.preViewItem.previewItemURL];
                }
            } else {
                [self.webView loadFileURL:self.preViewItem.previewItemURL allowingReadAccessToURL:self.preViewItem.previewItemURL];
            }
            
            self.webView.hidden = NO;
            break;
        }
        case PREVIEW_TEXT:
            Debug("Preview text %@\n", self.preViewItem.previewItemTitle);
            [self.view addSubview:self.textView];
            self.textView.frame = r;
            self.textView.attributedText = [self attributedTextOfPreViewItem];
            self.textView.hidden = NO;
            [self.textView scrollsToTop]; // Scroll to top
            break;
        case PREVIEW_PHOTO:
            Debug("Preview photo %@\n", self.preViewItem.previewItemTitle);
            self.mwPhotoBrowser.view.frame = r;
            break;
        case PREVIEW_NONE:
            break;
        default:
            break;
    }
    if ([self isPortrait]) {
        self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeSecondaryOnly; // Adjust split view controller display mode for portrait
    } else {
        self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary; // Adjust split view controller display mode for landscape
    }

    
    // Ensure toolbar always stays on top layer
    if (self.toolbarView) {
        [self.view bringSubviewToFront:self.toolbarView];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [SeafTheme primarySurface];
    // Do any additional setup after loading the view, typically from a nib.

    // Use the same SeafNavLeftItem as the file list so the back button icon, size, and
    // tint behavior stay consistent across pages (especially in dark mode).
    UIView *backView = [SeafNavLeftItem navLeftItemWithDirectory:nil
                                                            title:@""
                                                           target:self
                                                           action:@selector(goBack:)];
    self.backItem = [[UIBarButtonItem alloc] initWithCustomView:backView];

    self.view.autoresizesSubviews = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;

    self.editItem = [self getBarItem:@"editfile2" action:@selector(editFile:)size:18];
    self.exportItem = [self getBarItem:@"export2" action:@selector(export:)size:18];
    self.deleteItem = [self getBarItemAutoSize:@"delete" action:@selector(delete:)];

    UIBarButtonItem *starItem = [self getBarItem:@"star" action:@selector(unstarFile:)size:22];
    UIBarButtonItem *unstarItem = [self getBarItem:@"unstar" action:@selector(starFile:)size:22];
    UIBarButtonItem *space = [self getSpaceBarItem];
    self.barItemsStar  = [NSArray arrayWithObjects:self.exportItem, space, self.deleteItem, space, starItem, space, nil];
    self.barItemsUnStar  = [NSArray arrayWithObjects:self.exportItem, space, self.deleteItem, space, unstarItem, space, nil];

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
    self.webView = [[WKWebView alloc] initWithFrame:self.view.frame];
    self.webView.backgroundColor = [SeafTheme primarySurface];
    self.webView.autoresizesSubviews = YES;
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.failedView];
    [self.view addSubview:self.progressView];
    [self.view addSubview:self.webView];

    [self.progressView.cancelBt addTarget:self action:@selector(cancelDownload:) forControlEvents:UIControlEventTouchUpInside];

    self.view.autoresizesSubviews = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    
    if (IsIpad() && self.navigationItem.leftBarButtonItem == nil && [self isPortrait]) {
        [self.navigationItem setLeftBarButtonItem:self.splitViewController.displayModeButtonItem animated:NO];
    }
    
    // Setup bottom toolbar
    [self setupToolbar];
    // Ensure toolbar starts hidden on iPad, will be shown by refreshView if needed
    if (IsIpad() && self.toolbarView) {
         self.toolbarView.hidden = YES;
    }
    
    [self refreshView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Apply navigation styling
    if (self.navigationController) {
        [SeafNavigationBarStyler applyStandardAppearanceToNavigationController:self.navigationController];
        self.navigationController.navigationBar.tintColor = BAR_COLOR;
    }

    [self updateNavigation];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    self.preViewItem = nil;
    self.failedView = nil;
    self.progressView = nil;
    self.docController = nil;
    self.webView = nil;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)dealloc {
    [self.webView stopLoading];
    self.webView.navigationDelegate = nil;
    [self.webView removeFromSuperview];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    // Calculate layout y offset: iPad detail view starts below nav bar already, so y=0
    CGFloat layoutY = 0;
    if (!IsIpad()) {
        layoutY = 64;
        layoutY = 44 + [SeafAppDelegate activeWindow].safeAreaInsets.top;
    }
    
    // Calculate bottom margin to avoid toolbar overlap
    CGFloat layoutBottomMargin = 0;
    if (self.toolbarView && !self.toolbarView.hidden) {
        CGFloat toolbarHeight = 36;
        CGFloat safeAreaBottom = self.view.safeAreaInsets.bottom;
        layoutBottomMargin = toolbarHeight + safeAreaBottom;
    }
    
    CGRect r = CGRectMake(0, layoutY, self.view.bounds.size.width, self.view.bounds.size.height - layoutY - layoutBottomMargin);
    
    if (self.state == PREVIEW_PHOTO){
        if (IsIpad()) {
            self.mwPhotoBrowser.view.frame = r;// Adjust photo browser frame for iPad
        } else {
            if (UIInterfaceOrientationIsPortrait([SeafAppDelegate activeInterfaceOrientation])) {
                self.mwPhotoBrowser.view.frame = r;// Adjust photo browser frame for portrait orientation
            } else {
                self.mwPhotoBrowser.view.frame = CGRectMake(self.view.frame.origin.x, 32, self.view.frame.size.width, self.view.frame.size.height - 32);// Adjust photo browser frame for landscape orientation
            }
        }
    } else {
        // Update the actual visible content view based on current preview state
        switch (self.state) {
            case PREVIEW_WEBVIEW:
            case PREVIEW_WEBVIEW_JS:
                self.webView.frame = r;
                break;
            case PREVIEW_TEXT:
                self.textView.frame = r;
                break;
            case PREVIEW_DOWNLOADING:
                self.progressView.frame = r;
                break;
            case PREVIEW_FAILED:
                self.failedView.frame = r;
                break;
            default:
                break;
        }
    }
    
    // Position the toolbar at the bottom of the screen
    if (self.toolbarView) {
        CGFloat toolbarHeight = 36; // Reduced height from 44 to 36
        CGFloat safeAreaBottom = self.view.safeAreaInsets.bottom;
        
        
        CGRect toolbarFrame = CGRectMake(0,
                                      self.view.bounds.size.height - toolbarHeight - safeAreaBottom,
                                      self.view.bounds.size.width,
                                      toolbarHeight + safeAreaBottom); // Include safe area in height
        self.toolbarView.frame = toolbarFrame;
        
        // Recalculate buttons layout for new width
        [self layoutToolbarButtons];
        
        // Ensure toolbar always stays on top layer
        [self.view bringSubviewToFront:self.toolbarView];
    }
    
    // Apply navigation bar style using style tool
    if (self.navigationController) {
        [SeafNavigationBarStyler applyStandardAppearanceToNavigationController:self.navigationController];
        self.navigationController.navigationBar.tintColor = BAR_COLOR;
    }
}

#pragma mark - Split view

- (void)splitViewController:(UISplitViewController *)splitController willShowViewController:(UIViewController *)viewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    [self.navigationItem setLeftBarButtonItem:nil animated:NO];
}

- (BOOL)splitViewController:(UISplitViewController *)svc shouldHideViewController:(UIViewController *)vc inOrientation:(UIInterfaceOrientation)orientation
{
    return !UIInterfaceOrientationIsLandscape(orientation); // Determine if the view controller should be hidden based on orientation
}

#pragma mark - SeafDentryDelegate
- (void)download:(SeafBase *)entry progress:(float)progress
{
    if (_preViewItem != entry) return; // Return if the entry is not the current preview item

    if (self.state == PREVIEW_PHOTO) {
        SeafPhoto *photo = [self getSeafPhoto:(id<SeafPreView>)entry];
        if (photo != nil)
            [photo setProgress:progress];// Update progress for the photo
        return;
    }
    if (self.state != PREVIEW_DOWNLOADING) {
        [self refreshView];// Refresh the view if state is not downloading
    } else
        [self.progressView configureViewWithItem:self.preViewItem progress:progress];// Update progress view
}

- (void)download:(SeafBase *)entry complete:(BOOL)updated
{
    if (self.state == PREVIEW_PHOTO) {
        SeafPhoto *photo = [self getSeafPhoto:(id<SeafPreView>)entry];
        if (photo == nil)
            return;// Return if no photo is found
        [photo complete:updated error:nil];
        [self updateNavigation];// Update navigation items
        return;
    }
    if (_preViewItem != entry) return;
    if (updated) {
        SeafQLPreviewController *ql = self.qlViewController;
        NSString *path = ((id<SeafPreView>)entry).previewItemURL.path;
        if (ql.seafItem == entry && ql.presentingViewController
            && path && ![ql.presentedPath isEqualToString:path]) {
            // Quick Look is already up for this file and a newer version arrived.
            Debug("QL %p refresh: %@ -> %@", ql, ql.presentedPath, path);
            ql.presentedPath = path;
            [ql refreshCurrentPreviewItem];
        }
        [self refreshView];
        [self updateToolbarButtons]; // Update toolbar buttons after download completes
    } else if (self.state == PREVIEW_DOWNLOADING && entry.hasCache) {
        // If not updated but still showing loading page and file has cache
        // This can happen when file was already cached before but UI still shows loading
        Debug("File not updated but has cache, refreshing view: %@", entry.name);
        [self refreshView]; // This will update the view state based on cache
        [self updateToolbarButtons]; // Update toolbar buttons
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
        if (photo == nil) return;// Return if no photo is found
        if (self.preViewItem == entry) {// Show download error
            [self showDownloadError:self.preViewItem.previewItemTitle];
        }
        NSError *error = [NSError errorWithDomain:[NSString stringWithFormat:@"Failed to download file '%@'",self.preViewItem.previewItemTitle] code:-1 userInfo:nil];
        [photo complete:false error:error];// Mark the photo as not complete with error
        return;
    }

    if (self.preViewItem != entry || self.preViewItem.hasCache)
        return;// Return if the entry is not the current item or if it is cached

    // If it is a network unreachable error, display a specific prompt
    if (error && error.code == NSURLErrorNotConnectedToInternet) {
        if (self.isVisible) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Network unavailable", @"Seafile")];
        }
    } else {
         // Otherwise, display a generic download failed prompt
        [self showDownloadError:self.preViewItem.previewItemTitle];
    }
    [self setPreViewItem:nil master:nil];// Clear the preview item and master
}

#pragma mark - file operations
- (IBAction)delete:(id)sender {
    [self alertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete %@ ?", @"Seafile"), self.preViewItem.name] message:nil yes:^{
        if (_masterVc && [_masterVc isKindOfClass:[SeafFileViewController class]]) {
            [self goBack:nil];// Go back if deletion is confirmed
            [(SeafFileViewController *)_masterVc deleteFile:(SeafFile *)self.preViewItem];// Delete the file
        }
    } no:nil];
}

- (IBAction)starFile:(id)sender
{
    __weak SeafDetailViewController *weakSelf = self;
    [(SeafFile *)self.preViewItem setStarred:YES withBlock:^(BOOL success) {
        if (success) {
            [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Successfully starred", @"Seafile")];
            [weakSelf updateToolbarButtons]; // Use weakSelf to avoid retain cycle
        } else {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to star", @"Seafile")];
        }
    }];
}

- (IBAction)unstarFile:(id)sender
{
    __weak SeafDetailViewController *weakSelf = self;
    [(SeafFile *)self.preViewItem setStarred:NO withBlock:^(BOOL success) {
        if (success) {
            [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Successfully unstarred", @"Seafile")];
            [weakSelf updateToolbarButtons]; // Use weakSelf to avoid retain cycle
        } else {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to unstar", @"Seafile")];
        }
    }];
}

- (IBAction)editFile:(id)sender
{
    if (self.preViewItem.filesize > 10 * 1024 * 1024) {// Alert if file is too large to edit
        [self alertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"File '%@' is too large to edit", @"Seafile"), self.preViewItem.name]];
        return;
    }
    if (!self.preViewItem.strContent) { // Alert if file encoding is unidentified
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
    if (!item) return;

    // If the preview item is a SeafFile, use its built-in cancel logic which also
    // removes the persisted task from storage, ensuring the download will **not**
    // be restarted on the next app launch.
    if ([item isKindOfClass:[SeafFile class]]) {
        [(SeafFile *)item cancelDownload];
    } else {
        // Fallback for legacy preview item types that are not SeafFile.
        for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
            if (conn.accountIdentifier) {
                SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:conn];
                [accountQueue removeFileDownloadTask:item];
            }
        }
    }

    // Clear UI state after cancellation.
    [self setPreViewItem:nil master:nil];
    if (!IsIpad())
        [self goBack:nil];
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
    if (![self.preViewItem isKindOfClass:[SeafFile class]]) return;// Return if the preview item is not a file
    SeafFile *file = (SeafFile *)self.preViewItem;
    NSArray *array = @[file.exportURL];
    [SeafActionsManager exportByActivityView:array item:self.exportItem targerVC:self];// Export the file using the activity view
}

- (IBAction)share:(id)sender
{
    if (![self.preViewItem isKindOfClass:[SeafFile class]]) return;// Return if the preview item is not a file
    [self.preViewItem setDelegate:self];
    NSString *email = NSLocalizedString(@"Email", @"Seafile");
    NSString *copy = NSLocalizedString(@"Copy Link to Clipboard", @"Seafile");
    NSMutableArray *titles = [NSMutableArray arrayWithObjects:email, copy, nil];
    if ([SeafWechatHelper wechatInstalled] && [self.preViewItem exportURL]) { // Add "Share to WeChat" option
        NSString *wechat = NSLocalizedString(@"Share to WeChat", @"Seafile");
        [titles addObject:wechat];
    }
//    [self showAlertWithAction:titles fromBarItem:self.deleteItem withTitle:SHARE_TITLE];
}

- (void)savedToPhotoAlbumWithError:(NSError *)error file:(SeafFile *)file
{
    if (error) {
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to save %@ to album", @"Seafile"), file.name]];
    } else {
        [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Succeeded to save %@ to album", @"Seafile"), file.name]];
    }
}

- (void)handleAction:(NSString *)title
{
    SeafFile *file = (SeafFile *)self.preViewItem;
    if ([NSLocalizedString(@"Email", @"Seafile") isEqualToString:title]
               || [NSLocalizedString(@"Copy Link to Clipboard", @"Seafile") isEqualToString:title]) {
        if (![self checkNetworkStatus])// Return if there is no network connection
            return;

        if ([NSLocalizedString(@"Email", @"Seafile") isEqualToString:title])// Set share status to "Share by Mail"
            _shareStatus = SHARE_BY_MAIL;
        else
            _shareStatus = SHARE_BY_LINK;// Set share status to "Share by Link"
        if (!file.shareLink) {// Show status for generating share link
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Generate share link ...", @"Seafile")];
            [file generateShareLink:self];// Generate share link
        } else {
            [self generateSharelink:file WithResult:YES];// Handle generated share link
        }
    } else if ([NSLocalizedString(@"Share to WeChat", @"Seafile") isEqualToString:title]) {
        [SeafWechatHelper shareToWechatWithFile:file];// Share file to WeChat
    }
}

#pragma mark - SeafShareDelegate
- (void)generateSharelink:(SeafBase*)entry WithResult:(BOOL)success
{
    if (entry != self.preViewItem) {// Dismiss the progress HUD if the entry is not the current item
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
        [self sendMailInApp:file.name shareLink:file.shareLink];// Send mail with the share link
    } else if (_shareStatus == SHARE_BY_LINK){
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        [pasteboard setString:file.shareLink];// Set the share link in the pasteboard
    }
}

#pragma mark - sena mail inside app
- (void)sendMailInApp:(NSString *)name shareLink:(NSString *)shareLink
{
    Debug("send mail: %@", shareLink);
    Class mailClass = (NSClassFromString(@"MFMailComposeViewController"));// Get the mail compose view controller class
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
    mailPicker.modalPresentationStyle = UIModalPresentationFullScreen;

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

# pragma - WKWebViewDelegate
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    SeafFile *sFile = (SeafFile *)self.preViewItem;
    if (![sFile isWebOpenFile]) {
        if (self.preViewItem) {
            NSString *js = [NSString stringWithFormat:@"setContent(\"%@\");", [self.preViewItem.strContent stringEscapedForJavasacript]];// Prepare JavaScript for setting content
            [self.webView evaluateJavaScript:js completionHandler:nil];// Evaluate JavaScript
        }
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    SeafFile *sFile = (SeafFile *)self.preViewItem;
    if ([sFile isWebOpenFile]) {
        NSURL *originalURL = navigationAction.request.URL;
        Debug(@"Request URL: %@", navigationAction.request.URL);
        if ([originalURL.absoluteString containsString:@"login/?next"] && ![originalURL.absoluteString containsString:@"mobile-login/?next"]) {
            // Cancel current loading first
            decisionHandler(WKNavigationActionPolicyCancel);
            
            NSString *webViewURLString = [sFile getWebViewURLString];
            
            NSString *mobileLoginURLString = [NSString stringWithFormat:@"%@/mobile-login/?next=%@",
                                              sFile.connection.address,
                                              webViewURLString];
            NSURLRequest *urlRequest = [sFile.connection buildRequest:mobileLoginURLString method:@"GET" form:nil];
            
            [webView loadRequest:urlRequest];
            
            // Return here to avoid calling decisionHandler twice
            return;
        }
    }
    
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (UIBarButtonItem *)getSpaceBarItem {
    float spacewidth = IsIpad() ? 20.0f : 8.0f;
    UIBarButtonItem *space = [self getSpaceBarItem:spacewidth];
    return space;
}

#pragma -mark QLPreviewControllerDataSource
// Every Quick Look this view controller drives is a SeafQLPreviewController. The item is
// read off the controller itself: self.preViewItem may already belong to a newer tap by
// the time Quick Look gets around to asking.
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller
{
    return ((SeafQLPreviewController *)controller).seafItem ? 1 : 0; // 0 for the pre-warmed spare
}

- (id <QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index;
{
    if (index != 0) {
        return nil;
    }
    id<SeafPreView> item = ((SeafQLPreviewController *)controller).seafItem;
    Debug("QL %p asks for item: %@", controller, item.previewItemTitle);
    return item;
}

#pragma -mark QLPreviewControllerDelegate

- (QLPreviewItemEditingMode)previewController:(QLPreviewController *)controller editingModeForPreviewItem:(id<QLPreviewItem>)previewItem {
    if ([previewItem isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)previewItem;
        if ([file.mime isEqualToString:@"application/pdf"]) {
            return QLPreviewItemEditingModeCreateCopy;// Allow creating a copy for PDF files
        }
    }
    return QLPreviewItemEditingModeDisabled;
}

- (void)previewController:(QLPreviewController *)controller didUpdateContentsOfPreviewItem:(id<QLPreviewItem>)previewItem {
    Debug(@"previewItem did update :%@", previewItem);
}

- (void)previewController:(QLPreviewController *)controller didSaveEditedCopyOfPreviewItem:(id<QLPreviewItem>)previewItem atURL:(NSURL *)modifiedContentsURL {
    if (!modifiedContentsURL || ![previewItem isKindOfClass:[SeafFile class]]) return;
    ((SeafQLPreviewController *)controller).didEditItem = YES;
    [(SeafFile *)previewItem saveEditedPreviewFile:modifiedContentsURL];
}

- (void)previewControllerDidDismiss:(QLPreviewController *)controller {
    SeafQLPreviewController *ql = (SeafQLPreviewController *)controller;
    id<SeafPreView> item = ql.seafItem;

    // Honour the edit even for a superseded controller, otherwise the markup is lost:
    // self.preViewItem may already point at the file the user opened next.
    if (ql.didEditItem && [item isKindOfClass:[SeafFile class]]) {
        [(SeafFile *)item autoupload];
    }

    if (ql != self.qlViewController) {
        // A newer preview already took over; leave its state alone.
        Debug("QL %p dismissed, superseded by %p - ignored", controller, self.qlViewController);
        return;
    }
    self.qlViewController = nil;
    if (self.preViewItem == item) self.preViewItem = nil;
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
        _mwPhotoBrowser.backgroundColor = [SeafTheme primarySurface];
        _mwPhotoBrowser.trackTintColor = SEAF_COLOR_LIGHT;
        _mwPhotoBrowser.progressColor = SEAF_COLOR_ORANGE;
        _mwPhotoBrowser.preLoadNumLeft = 0;
        _mwPhotoBrowser.preLoadNumRight = 1;
    }
    
    // Ensure toolbar always stays on top layer
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.toolbarView) {
            [self.view bringSubviewToFront:self.toolbarView];
        }
    });
    
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
    
    // Ensure toolbar always stays on top layer
    if (self.toolbarView) {
        [self.view bringSubviewToFront:self.toolbarView];
    }
}

- (BOOL)isPortrait {
    return UIInterfaceOrientationIsPortrait([SeafAppDelegate activeInterfaceOrientation]);
}

- (UITextView *)textView {
    if (!_textView) {
        _textView = [[UITextView alloc] initWithFrame:self.view.frame];
        _textView.editable = false;
        _textView.backgroundColor = [SeafTheme primarySurface];
        _textView.textColor = [SeafTheme primaryText];
        _textView.contentInset =UIEdgeInsetsMake(6, 10, 6, 10);
        _textView.alwaysBounceVertical = YES;
    }
    return _textView;
}

#pragma mark - Quick Look presentation

// Where a Quick Look goes. Deliberately not [SeafAppDelegate topViewController]: that
// helper walks through presentedViewController, so once a Quick Look is up it returns the
// Quick Look itself, whose parentViewController is nil, and the presentation is dropped.
- (UIViewController *)quickLookHost
{
    // The detail view is itself a modal (iPhone, file was not cached at tap time):
    // the Quick Look replaces it, presented from the same controller that presented us.
    if (self.isModal && self.isVisible) return self.presentingViewController;
    if (IsIpad()) return self.navigationController ?: self;   // split view: always on screen
    return self.quickLookPresenter;                           // iPhone: only inside -previewItem:...
}

// YES when `vc` is something a new Quick Look may take the place of: an earlier Quick
// Look, or the modal container this detail view lives in. Anything else (photo gallery,
// share sheet, alert, editor) belongs to the user and is left alone.
- (BOOL)quickLookMayReplace:(UIViewController *)vc
{
    if ([vc isKindOfClass:[SeafQLPreviewController class]]) return YES;
    for (UIViewController *ancestor = self; ancestor; ancestor = ancestor.parentViewController) {
        if (ancestor == vc) return YES;
    }
    return NO;
}

// NO once `ql` is no longer the Quick Look this view controller wants on screen: a newer
// tap replaced it, or the detail view moved on to a non-Quick Look item while `ql` was
// waiting for a transition. Drops the claim so the next request for the same file is
// not mistaken for "already showing".
- (BOOL)quickLookStillWanted:(SeafQLPreviewController *)ql
{
    if (ql != self.qlViewController) return NO;
    if (self.state == PREVIEW_QL_MODAL && self.preViewItem == ql.seafItem) return YES;
    Debug("QL %p dropped: state=%d item=%@", ql, self.state, self.preViewItem.previewItemTitle);
    self.qlViewController = nil;
    return NO;
}

// Attaching the system Quick Look extension is the slow part of showing a fresh
// controller, and it happens when the view loads. Do it ahead of the next tap.
- (void)prepareSpareQuickLook
{
    if (self.spareQuickLook) return;
    SeafQLPreviewController *spare = [[SeafQLPreviewController alloc] init];
    spare.delegate = self;
    spare.dataSource = self;
    self.spareQuickLook = spare;
    [spare loadViewIfNeeded];
}

- (SeafQLPreviewController *)takeQuickLook
{
    SeafQLPreviewController *ql = self.spareQuickLook;
    self.spareQuickLook = nil;
    if (!ql) {
        ql = [[SeafQLPreviewController alloc] init];
        ql.delegate = self;
        ql.dataSource = self;
    }
    return ql;
}

// Takes a *new* Quick Look controller, binds `item` to it and presents it. Reusing one
// instance is what made a preview that was still dismissing come back with the previous
// file's contents (issue #549), and even after a clean dismissal a reused instance
// flashes the previous file before it re-renders.
- (void)presentQuickLookForItem:(id<SeafPreView>)item
{
    if (!item || self.state != PREVIEW_QL_MODAL) return;
    // Already showing or on its way - e.g. the asynchronous download:complete: refresh
    // arriving after the tap already opened it.
    if (self.qlViewController.seafItem == item) return;
    UIViewController *host = [self quickLookHost];
    if (!host) return;

    UIViewController *presented = host.presentedViewController;
    if (presented && ![self quickLookMayReplace:presented]) {
        Debug("QL for %@ not presented: %@ is up", item.previewItemTitle, presented);
        return;
    }

    SeafQLPreviewController *ql = [self takeQuickLook];
    ql.seafItem = item;
    ql.presentedPath = item.previewItemURL.path;
    if (ql.isViewLoaded) [ql reloadData]; // the spare was loaded with no item
    // Claim it synchronously so a refreshView in the meantime will not start a second one.
    self.qlViewController = ql;
    Debug("QL %p present item=%@ host=%@", ql, item.previewItemTitle, host);
    [self presentQuickLook:ql from:host animated:!self.quickLookUnanimated];
}

// Presents `ql` once nothing stands in the way. A controller still animating in or out
// is waited out rather than dismissed: dismissing mid-transition is undefined and UIKit
// may never run the completion, which would leave `ql` claimed but never shown.
- (void)presentQuickLook:(SeafQLPreviewController *)ql
                    from:(UIViewController *)host
                animated:(BOOL)animated
{
    if (![self quickLookStillWanted:ql]) return;

    __weak typeof(self) weakSelf = self;
    UIViewController *presented = host.presentedViewController;
    if (!presented) {
        [host presentViewController:ql animated:animated completion:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            // Warm the next one now that this presentation is done with the main thread.
            [strongSelf prepareSpareQuickLook];
            if (ql != strongSelf.qlViewController) return;
            // Only tidy a detail view that exists. On iPhone the detail view is usually
            // never loaded for a Quick Look file, and clearPreView would load it here
            // (WKWebView, nibs, toolbar) right as the preview appears.
            if (!strongSelf.isViewLoaded) return;
            [strongSelf clearPreView];
            if (IsIpad()) [strongSelf resetNavigation];
        }];
        return;
    }
    if (![self quickLookMayReplace:presented]) {
        // Something unrelated appeared while we waited; leave it and forget this request.
        Debug("QL %p dropped: %@ is up", ql, presented);
        self.qlViewController = nil;
        return;
    }
    Debug("QL %p waiting: %@ presented, transition=%d", ql, presented, presented.transitionCoordinator != nil);
    if (presented.transitionCoordinator) {
        // Presenting into a dismissal that is still in flight is exactly what made the
        // old controller reappear with stale contents (issue #549).
        [presented.transitionCoordinator animateAlongsideTransition:nil
                                                         completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf presentQuickLook:ql from:host animated:animated];
            });
        }];
    } else {
        [host dismissViewControllerAnimated:NO completion:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf presentQuickLook:ql from:host animated:animated];
            });
        }];
    }
}

- (BOOL)previewItem:(id<SeafPreView>)item
             master:(UIViewController<SeafDentryDelegate> *)c
        presentFrom:(UIViewController *)presenter
           animated:(BOOL)animated
{
    // setPreViewItem: -> refreshView presents the Quick Look when the item is cached;
    // otherwise download:complete: does, by which time the caller's presenter no longer
    // applies (see quickLookPresenter).
    self.quickLookPresenter = presenter;
    self.quickLookUnanimated = !animated;
    [self setPreViewItem:item master:c];
    // refreshView bails out before presenting while the detail view has never been
    // loaded (iPhone, first preview after launch); the same-item guard makes this a no-op
    // whenever refreshView did present.
    [self presentQuickLookForItem:item];
    self.quickLookPresenter = nil;
    self.quickLookUnanimated = NO;
    return self.state == PREVIEW_QL_MODAL;
}

- (NSAttributedString *)attributedTextOfPreViewItem {
    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithURL:self.preViewItem.previewItemURL options:@{NSDocumentTypeDocumentAttribute : NSPlainTextDocumentType} documentAttributes:nil error:nil];
    [attributedText addAttributes:@{
        NSFontAttributeName : [UIFont systemFontOfSize:14.0],
        NSForegroundColorAttributeName : [SeafTheme primaryText]
    } range:NSMakeRange(0, attributedText.length)];
    return attributedText;
}

// New method to setup the toolbar
- (void)setupToolbar {
    // Bottom action bar - including bottom safe area
    CGFloat toolbarH = 36; // Reduced height from 44 to 36
    CGFloat safeAreaBottom = self.view.safeAreaInsets.bottom;
    
    
    CGRect tbFrame = CGRectMake(0,
                                self.view.bounds.size.height - toolbarH - safeAreaBottom,
                                self.view.bounds.size.width,
                                toolbarH + safeAreaBottom); // Include bottom safe area
    
    // Remove existing toolbar (if exists) to avoid duplication
    if (self.toolbarView) {
        [self.toolbarView removeFromSuperview];
    }
    
    self.toolbarView = [[UIView alloc] initWithFrame:tbFrame];
    self.toolbarView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin;
    self.toolbarView.backgroundColor = [SeafTheme primarySurface];
    [self.view addSubview:self.toolbarView];

    // Add top separator line
    UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.toolbarView.bounds.size.width, 0.5)];
    separator.backgroundColor = [SeafTheme separator];
    separator.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.toolbarView addSubview:separator];

    // Use same icons as SeafPhotoGalleryViewController, remove download and info buttons
    NSArray<NSString*> *icons = @[@"detail_delete", @"detail_starred", @"detail_share"];
    NSUInteger count = icons.count;
    
    // Adjust spacing and size according to design
    CGFloat totalWidth = self.toolbarView.bounds.size.width;
    
    // Button spacing should be even, each button occupies the same space
    CGFloat itemWidth = totalWidth / count;
    
    // Icon size itself
    CGFloat iconSize = 20.0; // Icon size set to 20pt
    
    // Create and distribute buttons evenly
    for (int i = 0; i < count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        
        // Center button in its area
        CGFloat x = i * itemWidth;
        btn.frame = CGRectMake(x, 0, itemWidth, toolbarH);
        
        // Set icon
        NSString *iconName = icons[i];
        UIImage *image = [UIImage imageNamed:iconName];
        
        if (image) {
            // Use template rendering mode
            image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            
            // Calculate the target size while maintaining aspect ratio
            CGSize originalSize = image.size;
            CGFloat aspectRatio = originalSize.width / originalSize.height;
            CGFloat targetWidth, targetHeight;
            
            if (aspectRatio >= 1.0) {
                // Wider than tall: fit to width
                targetWidth = iconSize;
                targetHeight = iconSize / aspectRatio;
            } else {
                // Taller than wide: fit to height
                targetHeight = iconSize;
                targetWidth = iconSize * aspectRatio;
            }
            
            // Adjust icon size while maintaining aspect ratio
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(targetWidth, targetHeight), NO, 0.0);
            [image drawInRect:CGRectMake(0, 0, targetWidth, targetHeight)];
            UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            
            resizedImage = [resizedImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [btn setImage:resizedImage forState:UIControlStateNormal];
            btn.imageView.contentMode = UIViewContentModeScaleAspectFit;
            // Set gray color (#666666) to match other icons
            btn.tintColor = [SeafTheme secondaryText];
            // Vertically center icon inside the button
            CGFloat verticalOffset = (toolbarH - iconSize)/2.0;
            btn.imageEdgeInsets = UIEdgeInsetsMake(verticalOffset, 0, verticalOffset, 0);
        }
        
        // Set button label and event
        btn.tag = i;
        [btn addTarget:self action:@selector(toolbarButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.toolbarView addSubview:btn];
    }
    
    // Initial layout calculation
    [self layoutToolbarButtons];
    
    // Ensure toolbar stays on top layer
    [self.view bringSubviewToFront:self.toolbarView];
}

// Helper method: Set color for icon
- (UIImage *)imageWithTintColor:(UIColor *)tintColor image:(UIImage *)image {
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    CGRect rect = CGRectMake(0, 0, image.size.width, image.size.height);
    
    [image drawInRect:rect];
    [tintColor set];
    UIRectFillUsingBlendMode(rect, kCGBlendModeSourceAtop);
    
    UIImage *tintedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return tintedImage;
}

// New method to handle toolbar button taps
- (void)toolbarButtonTapped:(UIButton*)btn {
    if (![self.preViewItem isKindOfClass:[SeafFile class]]) return;
    SeafFile *file = (SeafFile *)self.preViewItem;
    
    switch (btn.tag) {
        case 0: // Delete button
            [self delete:btn];
            break;
            
        case 1: // Star button
            if ([file isStarred]) {
                [self unstarFile:btn]; // Call existing unstar method
            } else {
                [self starFile:btn]; // Call existing star method
            }
            break;
            
        case 2: // Share button
            [self export:btn];
            break;
    }
}

// Update bottom toolbar button states
- (void)updateToolbarButtons {
    if (!self.toolbarView) return;
    
    // Check current file star status
    BOOL isStarred = NO;
    if ([self.preViewItem isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)self.preViewItem;
        isStarred = [file isStarred];
    }
    
    // Update star button
    for (UIView *subview in self.toolbarView.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)subview;
            if (btn.tag == 1) { // Star button is now index 1
                NSString *iconName = isStarred ? @"detail_starred_selected" : @"detail_starred";
                UIImage *image = [UIImage imageNamed:iconName];
                
                if (image) {
                    // Use template rendering mode
                    image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    
                    // Calculate the target size while maintaining aspect ratio
                    CGFloat iconSize = 20.0;
                    CGSize originalSize = image.size;
                    CGFloat aspectRatio = originalSize.width / originalSize.height;
                    CGFloat targetWidth, targetHeight;
                    
                    if (aspectRatio >= 1.0) {
                        targetWidth = iconSize;
                        targetHeight = iconSize / aspectRatio;
                    } else {
                        targetHeight = iconSize;
                        targetWidth = iconSize * aspectRatio;
                    }
                    
                    // Adjust icon size while maintaining aspect ratio
                    UIGraphicsBeginImageContextWithOptions(CGSizeMake(targetWidth, targetHeight), NO, 0.0);
                    [image drawInRect:CGRectMake(0, 0, targetWidth, targetHeight)];
                    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
                    UIGraphicsEndImageContext();
                    
                    resizedImage = [resizedImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    [btn setImage:resizedImage forState:UIControlStateNormal];
                    btn.imageView.contentMode = UIViewContentModeScaleAspectFit;
                    // Set gray color (#666666) for all states (selected states differ by icon style, not color)
                    btn.tintColor = [SeafTheme secondaryText];
                    // Vertically center icon again in case of state change
                    CGFloat toolbarH = 36.0f;
                    CGFloat verticalOffset = (toolbarH - iconSize)/2.0f;
                    btn.imageEdgeInsets = UIEdgeInsetsMake(verticalOffset, 0, verticalOffset, 0);
                }
            }
        }
    }
}

// New helper method: layout toolbar buttons to fit current width
- (void)layoutToolbarButtons {
    if (!self.toolbarView) return;
    // Determine the design height we used when creating buttons
    CGFloat toolbarHeight = 36.0f; // Must be in sync with setupToolbar

    // Safe-area bottom is already included in toolbarView height, but the buttons themselves
    // should stay in the top part (outside the safe-area region).
    // Therefore, keep button height equal to toolbarHeight, starting at y = 0.
    NSUInteger buttonCount = 0;
    for (UIView *v in self.toolbarView.subviews) {
        if ([v isKindOfClass:[UIButton class]]) buttonCount += 1;
    }
    if (buttonCount == 0) return;

    CGFloat totalWidth = self.toolbarView.bounds.size.width;
    CGFloat itemWidth  = totalWidth / buttonCount;

    // Re-position each button according to its tag order (tags were assigned 0,1,2 when created).
    for (UIView *v in self.toolbarView.subviews) {
        if (![v isKindOfClass:[UIButton class]]) continue;
        UIButton *btn = (UIButton *)v;
        NSInteger index = btn.tag; // 0,1,2
        CGRect frame = CGRectMake(index * itemWidth, 0, itemWidth, toolbarHeight);
        btn.frame = frame;
        // Ensure icon remains vertically centered after layout change
        CGFloat iconSize = 20.0f;
        CGFloat verticalOffset = (toolbarHeight - iconSize)/2.0f;
        btn.imageEdgeInsets = UIEdgeInsetsMake(verticalOffset, 0, verticalOffset, 0);
    }
}

// Set the preview item and refresh the view.
- (void)setPreViewItem:(id<SeafPreView>)item master:(UIViewController<SeafDentryDelegate> *)c
{
    if (item) Debug("preview %@", item.previewItemTitle);
    self.masterVc = c;
    self.photos = nil;
    self.preViewItem = item;
    //if need load from cache.
    [item load:(self.masterVc ? self.masterVc:self) force:NO];
    [self refreshView];
    [self updateToolbarButtons]; // Update toolbar buttons when setting a new preview item
    
    // Ensure toolbar always stays on top layer
    if (self.toolbarView) {
        [self.view bringSubviewToFront:self.toolbarView];
    }
}

// Set and prepare photo views for preview.
- (void)setPreViewPhotos:(NSArray *)items current:(id<SeafPreView>)item master:(UIViewController<SeafDentryDelegate> *)c
{
    [self clearPreView];
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
    
    // Ensure toolbar always stays on top layer
    if (self.toolbarView) {
        [self.view bringSubviewToFront:self.toolbarView];
    }
}

// Handle the back button action.
- (void)goBack:(id)sender
{
    if (self.isModal)
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    else
        [self.navigationController popViewControllerAnimated:NO];
}

#pragma mark - SeafFileUpdateDelegate
- (void)updateProgress:(nonnull SeafFile *)file progress:(float)progress {
    if (file != self.preViewItem) return;
    [SVProgressHUD showProgress:progress status:NSLocalizedString(@"Uploading", @"Seafile")];
}

- (void)updateComplete:(nonnull SeafFile *)file result:(BOOL)res {
    if (file != self.preViewItem) return;
    if (res) {
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Success", @"Seafile")];
    } else {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to upload file", @"Seafile")];
    }
}

@end
