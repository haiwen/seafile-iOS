//
//  FileViewController.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "FailToPreview.h"
#import "DownloadingProgressView.h"
#import "FileViewController.h"

#import "UIViewController+AlertMessage.h"
#import "SVProgressHUD.h"
#import "Debug.h"

@interface PrevFile : NSObject<QLPreviewItem>
@end

static PrevFile *pfile;

@implementation PrevFile

- (NSString *)previewItemTitle
{
    return nil;
}

- (NSURL *)previewItemURL
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"app-icon-ipad-50" ofType:@"png"];
    return [NSURL fileURLWithPath:path];
}

+ (PrevFile *)defaultFile
{
    if (!pfile)
        pfile = [[PrevFile alloc] init];
    return pfile;
}


@end

enum PREVIEW_STATE {
    PREVIEW_SUCCESS = 0,
    PREVIEW_AUDIO,
    PREVIEW_DOWNLOADING,
    PREVIEW_FAILED
};

@interface FileViewController ()
@property (strong) NSArray *barItemsStar;
@property (strong) NSArray *barItemsUnStar;
@property (strong) FailToPreview *failedView;
@property (strong) DownloadingProgressView *progressView;
@property (strong) UIWebView *webView;
@property id<QLPreviewItem, PreViewDelegate> preViewItem;
@property (strong) UIDocumentInteractionController *docController;
@property int state;
@property int buttonIndex;
@property UINavigationItem *navItem;
@end


@implementation FileViewController
@synthesize preViewItem = _preViewItem;
@synthesize barItemsStar = _barItemsStar;
@synthesize barItemsUnStar = _barItemsUnStar;
@synthesize failedView = _failedView;
@synthesize progressView = _progressView;
@synthesize webView = _webView;
@synthesize state = _state;
@synthesize buttonIndex = _buttonIndex;
@synthesize navItem;
@synthesize docController;

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];

    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [SVProgressHUD dismiss];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

- (void)checkBarItems
{
    if ([_preViewItem isKindOfClass:[SeafFile class]]) {
        if ([(SeafFile *)_preViewItem isStarred])
            self.navItem.rightBarButtonItems = _barItemsStar;
        else
            self.navItem.rightBarButtonItems = _barItemsUnStar;
    } else
        self.navItem.rightBarButtonItems = nil;
}

- (void)configureView
{
    NSURLRequest *request;
    self.title = _preViewItem.previewItemTitle;
    Debug("Preview file:%@,%@,%@ [%d]\n", _preViewItem.previewItemTitle, [_preViewItem checkoutURL],_preViewItem.previewItemURL, [QLPreviewController canPreviewItem:_preViewItem]);
    [self checkBarItems];
    if (_state == PREVIEW_FAILED)
        [_failedView removeFromSuperview];
    if (_state == PREVIEW_DOWNLOADING)
        [_progressView removeFromSuperview];
    if (_state == PREVIEW_AUDIO) {
        [_webView removeFromSuperview];
        _webView = nil;
    }
    NSAssert(_preViewItem, @"the file to preview must not be nil");

    if (_preViewItem.previewItemURL) {
        if (![QLPreviewController canPreviewItem:_preViewItem]) {
            _state = PREVIEW_FAILED;
        } else {
            Debug (@"Preview file %@ mime=%@ success\n", _preViewItem.previewItemTitle, _preViewItem.mime);
            _state = PREVIEW_SUCCESS;
            if ([_preViewItem.mime hasPrefix:@"audio"])
                _state = PREVIEW_AUDIO;
        }
    } else {
        _state = PREVIEW_DOWNLOADING;
    }
    [self reloadData];

    switch (_state) {
        case PREVIEW_DOWNLOADING:
            Debug (@"DownLoading file %@\n", _preViewItem.previewItemTitle);
            //Debug("%d, frame=%f,%f,%f,%f\n", self.view.autoresizesSubviews, _progressView.frame.origin.x, _progressView.frame.origin.y, _progressView.frame.size.width, _progressView.frame.size.height);
            [self.view addSubview:_progressView];
            _progressView.frame = self.view.frame;
            //Debug("%d, frame=%f,%f,%f,%f\n", self.view.autoresizesSubviews, _progressView.frame.origin.x, _progressView.frame.origin.y, _progressView.frame.size.width, _progressView.frame.size.height);
            [_progressView configureViewWithItem:_preViewItem completeness:0];
            break;
        case PREVIEW_FAILED:
            Debug ("Can not preview file %@\n", _preViewItem.previewItemTitle);
            [self.view addSubview:_failedView];
            //Debug("%d, frame=%f,%f,%f,%f\n", self.view.autoresizesSubviews, _failedView.frame.origin.x, _failedView.frame.origin.y, _failedView.frame.size.width, _failedView.frame.size.height);
            _failedView.frame = self.view.frame;
            //Debug("%d, frame=%f,%f,%f,%f\n", self.view.autoresizesSubviews, _failedView.frame.origin.x, _failedView.frame.origin.y, _failedView.frame.size.width, _failedView.frame.size.height);
            [_failedView configureViewWithPrevireItem:_preViewItem];
            break;
        case PREVIEW_AUDIO:
            Debug("Preview audio\n");
            request = [[NSURLRequest alloc] initWithURL:_preViewItem.previewItemURL cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
            _webView = [[UIWebView alloc] initWithFrame:self.view.frame];
            [_webView loadRequest: request];
            _webView.frame = self.view.frame;
            [self.view addSubview:_webView];
            break;
        default:
            break;
    }
    [self setCurrentPreviewItemIndex:0];
}

- (void)updateDownloadProgress:(BOOL)res completeness:(int)percent;
{
    if (_state != PREVIEW_DOWNLOADING)
        return;

    if (!res) {
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:@"Failed to download file '%@'",_preViewItem.previewItemTitle]];
    } else {
        //Debug ("DownLoading file %@, percent=%d\n", _preViewItem.previewItemTitle, percent);
        if (_state == PREVIEW_DOWNLOADING) {
            [_progressView configureViewWithItem:_preViewItem completeness:percent];
        }
        if (percent == 100) {
            [self configureView];
        }
    }
}


#pragma mark -
- (id)initWithNavigationItem:(UINavigationItem *)navitem
{
    if (self = [super init]) {
        UIBarButtonItem *item1 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(openElsewhere:)];
        NSString* path = [[NSBundle mainBundle] pathForResource:@"gray-share-icon" ofType:@"png"];
        UIBarButtonItem *item2 = [[UIBarButtonItem alloc] initWithImage:[UIImage imageWithContentsOfFile:path] style:UIBarButtonItemStylePlain target:self action:@selector(share:)];
        path = [[NSBundle mainBundle] pathForResource:@"gray-star-icon" ofType:@"png"];
        UIBarButtonItem *item3 = [[UIBarButtonItem alloc] initWithImage:[UIImage imageWithContentsOfFile:path] style:UIBarButtonItemStylePlain target:self action:@selector(unstarFile:)];

        path = [[NSBundle mainBundle] pathForResource:@"gray-unstar-icon" ofType:@"png"];
        UIBarButtonItem *item4 = [[UIBarButtonItem alloc] initWithImage:[UIImage imageWithContentsOfFile:path] style:UIBarButtonItemStylePlain target:self action:@selector(starFile:)];

        _barItemsStar  = [NSArray arrayWithObjects:item1, item2, item3, nil];
        _barItemsUnStar  = [NSArray arrayWithObjects:item1, item2, item4, nil];
        self.navItem = navitem;
        _state = PREVIEW_SUCCESS;
        self.dataSource = self;
        [self.navItem setHidesBackButton:YES];
        if(IsIpad()) {
            NSArray *views = [[NSBundle mainBundle] loadNibNamed:@"FailToPreview_iPad" owner:self options:nil];
            _failedView = [views objectAtIndex:0];
            views = [[NSBundle mainBundle] loadNibNamed:@"DownloadingProgress_iPad" owner:self options:nil];
            _progressView = [views objectAtIndex:0];
        } else {
            NSArray *views = [[NSBundle mainBundle] loadNibNamed:@"FailToPreview_iPhone" owner:self options:nil];
            _failedView = [views objectAtIndex:0];
            views = [[NSBundle mainBundle] loadNibNamed:@"DownloadingProgress_iPhone" owner:self options:nil];
            _progressView = [views objectAtIndex:0];
        }
        self.view.autoresizesSubviews = YES;
    }
    return self;
}

- (void)setPreItem:(id<QLPreviewItem, PreViewDelegate>)prevItem
{
    _preViewItem = prevItem;
    [SVProgressHUD dismiss];
    [self configureView];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller
{
    return 1;
}

- (id <QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index;
{
    if (_state == PREVIEW_SUCCESS)
        return _preViewItem;
    return [PrevFile defaultFile];
}


#pragma mark - file operations
- (IBAction)starFile:(id)sender
{
    [(SeafFile *)_preViewItem setStarred:YES];
    [self checkBarItems];
}

- (IBAction)unstarFile:(id)sender
{
    [(SeafFile *)_preViewItem setStarred:NO];
    [self checkBarItems];
}

- (IBAction)openElsewhere:(id)sender
{
    NSURL *url = [_preViewItem checkoutURL];
    if (!url)
        return;
    docController = [UIDocumentInteractionController interactionControllerWithURL:url];
    BOOL ret = [docController presentOpenInMenuFromBarButtonItem:sender animated:YES];
    if (ret == NO) {
        [SVProgressHUD showErrorWithStatus:@"There is no app which can open this type of file on this machine"];
    }
}

- (IBAction)share:(id)sender
{
    if (![_preViewItem isKindOfClass:[SeafFile class]])
        return;

    UIActionSheet *actionSheet;
    if (IsIpad())
        actionSheet = [[UIActionSheet alloc] initWithTitle:@"How would you like to share this file?" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:@"Email", @"Copy Link to Clipboard", nil ];
    else
        actionSheet = [[UIActionSheet alloc] initWithTitle:@"How would you like to share this file?" delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Email", @"Copy Link to Clipboard", nil ];

    [actionSheet showFromBarButtonItem:sender animated:YES];
}

#pragma mark - SeafFileDelegate
- (void)generateSharelink:(SeafFile *)entry WithResult:(BOOL)success
{
    if (entry != _preViewItem)
        return;

    SeafFile *file = (SeafFile *)_preViewItem;
    if (!success) {
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:@"Failed to generate share link of file '%@'", file.name]];
        return;
    }
    [SVProgressHUD showSuccessWithStatus:@"Generate share link success"];

    if (_buttonIndex == 0) {
        [self sendMailInApp];
    } else if (_buttonIndex == 1){
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        [pasteboard setString:file.shareLink];
    }
}

#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    _buttonIndex = buttonIndex;
    if (buttonIndex == 0 || buttonIndex == 1) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        if (![appdelegate checkNetworkStatus])
            return;

        SeafFile *file = (SeafFile *)_preViewItem;
        if (!file.shareLink) {
            [SVProgressHUD showWithStatus:@"Generate share link ..."];
            [file generateShareLink:self];
        } else {
            [self generateSharelink:file WithResult:YES];
        }
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

    SeafFile *file = (SeafFile *)_preViewItem;
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

@end
