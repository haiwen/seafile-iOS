#import "SeafVideoPlayerViewController.h"
#import "SeafConnection.h"
#import "SVProgressHUD.h"
#import "Debug.h"
#import "Version.h"
#import "SeafFile.h"

// For KVO context
static void *SeafPlayerItemStatusContext = &SeafPlayerItemStatusContext;

@interface SeafVideoPlayerViewController ()
@property (strong, nonatomic) SeafFile *file;
@property (strong, nonatomic) AVPlayerViewController *playerViewController;
@property (strong, nonatomic) AVPlayerItem *playerItem;
@property (strong, nonatomic) AVPlayer *player;
@end

@implementation SeafVideoPlayerViewController

- (instancetype)initWithFile:(SeafFile *)file {
    self = [super init];
    if (self) {
        _file = file;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self setupPlayerViewController];
    [self startPlayback];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.playerViewController.view.frame = self.view.bounds;
}

- (void)setupPlayerViewController {
    self.playerViewController = [[AVPlayerViewController alloc] init];
    [self addChildViewController:self.playerViewController];
    [self.view addSubview:self.playerViewController.view];
    [self.playerViewController didMoveToParentViewController:self];
}

- (void)startPlayback {
    [SVProgressHUD show];

    if ([self.file hasCache]) {
        NSURL *localURL = [self.file exportURL];
        if (localURL && [[NSFileManager defaultManager] fileExistsAtPath:localURL.path]) {
            Debug(@"Playing video from local cache: %@", localURL.path);
            self.playerItem = [AVPlayerItem playerItemWithURL:localURL];
            [self setupPlayerWithItem:self.playerItem];
            return;
        }
    }

    [self.file.connection getFileDownloadLink:self.file.repoId
                                         path:self.file.path
                                      success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        Debug(@"Get video link success. Response: %@", JSON);
        NSString *dlink = nil;
        if ([JSON isKindOfClass:[NSDictionary class]]) {
            dlink = [JSON objectForKey:@"url"];
        } else if ([JSON isKindOfClass:[NSString class]]) {
            dlink = [(NSString *)JSON stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
        }

        if (!dlink || dlink.length == 0) {
            [self showErrorAndDismiss:NSLocalizedString(@"Failed to get video link", @"Seafile")];
            Warning(@"Failed to get video link: dlink is nil or empty");
            return;
        }

        NSURL *videoURL = [NSURL URLWithString:dlink];
        Debug(@"Playing video from URL: %@", videoURL);

        NSDictionary *headers = @{
            @"Authorization": [NSString stringWithFormat:@"Token %@", self.file.connection.token],
            @"X-Seafile-Client-Version": SEAFILE_VERSION,
            @"X-Seafile-Platform-Version": [[UIDevice currentDevice] systemVersion]
        };
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoURL options:@{@"AVURLAssetHTTPHeaderFieldsKey": headers}];
        self.playerItem = [AVPlayerItem playerItemWithAsset:asset];
        self.playerItem.preferredForwardBufferDuration = 3.0;
        [self setupPlayerWithItem:self.playerItem];

    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        [self showErrorAndDismiss:NSLocalizedString(@"Failed to get video link", @"Seafile")];
        Warning(@"Failed to get video link. Error: %@, Response: %@", error, JSON);
    }];
}

- (void)setupPlayerWithItem:(AVPlayerItem *)playerItem {
    [playerItem addObserver:self forKeyPath:NSStringFromSelector(@selector(status)) options:NSKeyValueObservingOptionNew context:SeafPlayerItemStatusContext];

    self.player = [AVPlayer playerWithPlayerItem:playerItem];
    self.player.automaticallyWaitsToMinimizeStalling = YES;
    self.playerViewController.player = self.player;
    [self.playerViewController.player play];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if (context == SeafPlayerItemStatusContext) {
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(status))]) {
            AVPlayerItem *playerItem = (AVPlayerItem *)object;
            if (playerItem.status == AVPlayerItemStatusFailed) {
                Warning(@"AVPlayerItem failed to play. Error: %@", playerItem.error);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD dismiss];
                    NSString *errorMsg = playerItem.error.localizedDescription ?: NSLocalizedString(@"Failed to play video", @"Seafile");
                    [self showErrorAndDismiss:errorMsg];
                });
            } else if (playerItem.status == AVPlayerItemStatusReadyToPlay) {
                Debug(@"AVPlayerItem is ready to play.");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD dismiss];
                });
            }
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)showErrorAndDismiss:(NSString *)message {
    [SVProgressHUD showErrorWithStatus:message];
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)dealloc {
    if (_playerItem) {
        @try {
            [_playerItem removeObserver:self forKeyPath:NSStringFromSelector(@selector(status)) context:SeafPlayerItemStatusContext];
        } @catch (NSException *exception) {
            Debug(@"Exception while removing observer: %@", exception);
        }
    }
    Debug(@"SeafVideoPlayerViewController dealloc");
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end 