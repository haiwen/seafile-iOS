//  SeafImagePreviewController.m

#import "SeafImagePreviewController.h"
#import "SeafConnection.h"
#import "Version.h"
#import "SeafDataTaskManager.h"
#import <CommonCrypto/CommonDigest.h>
#import "SVProgressHUD.h"
#import "SeafCacheManager.h"

@interface SeafImagePreviewController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, copy) NSString *imageURL;
@property (nonatomic, weak) SeafConnection *connection;
@property (nonatomic, strong) UIActivityIndicatorView *indicator;
@property (nonatomic, strong) NSOperation *imageOperation;
@end

@implementation SeafImagePreviewController

// Reuse the same approach as the comment cell: same disk directory name, use URL SHA1 as filename
- (UIImage *)_cachedImageForURL:(NSString *)url
{
    return [[SeafCacheManager sharedManager] getImageForURL:url];
}

- (void)_storeImage:(UIImage *)img forURL:(NSString *)url
{
    [[SeafCacheManager sharedManager] storeImage:img forURL:url];
}

- (instancetype)initWithURL:(NSString *)url connection:(SeafConnection *)connection
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _imageURL = [url copy] ?: @"";
        _connection = connection;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.view.backgroundColor = [UIColor blackColor];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    
    _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.delegate = self;
    _scrollView.minimumZoomScale = 1.0;
    _scrollView.maximumZoomScale = 3.0;
    _scrollView.backgroundColor = [UIColor blackColor];
    [self.view addSubview:_scrollView];
    
    _imageView = [[UIImageView alloc] initWithFrame:_scrollView.bounds];
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _imageView.backgroundColor = [UIColor blackColor];
    [_scrollView addSubview:_imageView];
    
    // Loading indicator
    UIActivityIndicatorViewStyle st = UIActivityIndicatorViewStyleWhiteLarge;
    if (@available(iOS 13.0, *)) {
        st = UIActivityIndicatorViewStyleLarge;
    }
    _indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:st];
    _indicator.color = [UIColor whiteColor];
    _indicator.translatesAutoresizingMaskIntoConstraints = NO;
    _indicator.hidesWhenStopped = YES;
    [self.view addSubview:_indicator];
    [NSLayoutConstraint activateConstraints:@[
        [_indicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_indicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];

    UITapGestureRecognizer *single = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onSingleTap:)];
    [self.view addGestureRecognizer:single];
    
    [self loadImage];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return _imageView; }

- (void)onSingleTap:(UITapGestureRecognizer *)gr
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)dealloc
{
    if (self.imageOperation && !self.imageOperation.isFinished && !self.imageOperation.isCancelled) {
        [self.imageOperation cancel];
    }
    [SVProgressHUD dismiss];
}

- (void)loadImage
{
    if (self.imageURL.length == 0) return;

    // Check memory/disk cache first (shared with the comment list's disk directory)
    UIImage *cached = [self _cachedImageForURL:self.imageURL];
    if (cached) {
        self.imageView.image = cached;
        [self adjustImageLayout];
        [self.indicator stopAnimating];
        return;
    }

    [SVProgressHUD showWithStatus:NSLocalizedString(@"Loading...", nil)];
    __weak typeof(self) wself = self;
    self.imageOperation = [SeafDataTaskManager.sharedObject addCommentImageDownload:self.imageURL
                                                                         connection:self.connection
                                                                         completion:^(UIImage * _Nullable image, NSString * _Nonnull urlStr) {
        __strong typeof(wself) sself = wself; if (!sself) return;
        if (image) {
            sself.imageView.image = image;
            [sself _storeImage:image forURL:urlStr];
            [sself adjustImageLayout];
            [SVProgressHUD dismiss];
        }
        else {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Load failed", nil)];
        }
        [sself.indicator stopAnimating];
    }];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self adjustImageLayout];
}

- (void)adjustImageLayout
{
    if (!_imageView.image) return;
    CGSize imgSize = _imageView.image.size;
    CGSize bounds = self.view.bounds.size;
    if (imgSize.width <= 0 || imgSize.height <= 0) return;
    CGFloat scale = MIN(bounds.width / imgSize.width, bounds.height / imgSize.height);
    CGFloat w = floor(imgSize.width * scale);
    CGFloat h = floor(imgSize.height * scale);
    _imageView.frame = CGRectMake((bounds.width - w)/2.0, (bounds.height - h)/2.0, w, h);
    _scrollView.contentSize = _imageView.frame.size;
}

@end

