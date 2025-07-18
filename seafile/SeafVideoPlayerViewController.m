#import "SeafVideoPlayerViewController.h"
#import "SeafConnection.h"
#import "SVProgressHUD.h"
#import "Debug.h"
#import "Version.h"
#import "SeafFile.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

// For KVO context
static void *SeafPlayerItemStatusContext = &SeafPlayerItemStatusContext;

// Singleton to manage active video player
static SeafVideoPlayerViewController *activeVideoPlayer = nil;

@interface SeafVideoPlayerViewController ()
@property (strong, nonatomic) SeafFile *file;
@property (strong, nonatomic) AVPlayerViewController *playerViewController;
@property (strong, nonatomic) AVPlayerItem *playerItem;
@property (strong, nonatomic) AVPlayer *player;
@property (strong, nonatomic) id periodicTimeObserver;
@end

@implementation SeafVideoPlayerViewController

- (instancetype)initWithFile:(SeafFile *)file {
    self = [super init];
    if (self) {
        _file = file;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        
        // Close any existing active video player
        [self closeActiveVideoPlayer];
        
        // Set this as the active video player
        activeVideoPlayer = self;
    }
    return self;
}

+ (void)closeActiveVideoPlayer {
    if (activeVideoPlayer) {
        [activeVideoPlayer stopAndCleanup];
        activeVideoPlayer = nil;
    }
}

- (void)closeActiveVideoPlayer {
    if (activeVideoPlayer && activeVideoPlayer != self) {
        [activeVideoPlayer stopAndCleanup];
        activeVideoPlayer = nil;
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self setupAudioSession];
    [self setupPlayerViewController];
    [self startPlayback];
    [self setupRemoteCommandCenter];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.playerViewController.view.frame = self.view.bounds;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // 如果是通过手势或其他方式关闭，确保清理资源
    if (self.isBeingDismissed) {
        [self stopAndCleanup];
        if (activeVideoPlayer == self) {
            activeVideoPlayer = nil;
        }
    }
}

- (void)setupAudioSession {
    NSError *error = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    // 设置音频会话类别为播放，允许后台播放
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (error) {
        Warning(@"Failed to set audio session category: %@", error);
    }
    
    // 激活音频会话
    [audioSession setActive:YES error:&error];
    if (error) {
        Warning(@"Failed to activate audio session: %@", error);
    }
}

- (void)setupPlayerViewController {
    self.playerViewController = [[AVPlayerViewController alloc] init];
    [self addChildViewController:self.playerViewController];
    [self.view addSubview:self.playerViewController.view];
    [self.playerViewController didMoveToParentViewController:self];
    
    // 允许画中画模式（iOS 14+）
    if (@available(iOS 14.0, *)) {
        self.playerViewController.allowsPictureInPicturePlayback = YES;
    }
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
    
    // 添加播放状态监听
    [self addPlayerObservers];
}

- (void)addPlayerObservers {
    // 监听播放速率变化（播放/暂停）
    [self.player addObserver:self forKeyPath:@"rate" options:NSKeyValueObservingOptionNew context:nil];
    
    // 定期更新播放信息
    __weak typeof(self) weakSelf = self;
    self.periodicTimeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        [weakSelf updateNowPlayingInfo];
    }];
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
                    // 视频准备好后立即更新播放信息
                    [self updateNowPlayingInfo];
                });
            }
        }
    } else if ([keyPath isEqualToString:@"rate"]) {
        // 播放状态改变时更新控制中心信息
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateNowPlayingInfo];
        });
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)showErrorAndDismiss:(NSString *)message {
    [SVProgressHUD showErrorWithStatus:message];
    [self dismissViewController];
}

- (void)dismissViewController {
    // 停止播放并清理资源
    [self stopAndCleanup];
    
    // 清空活跃播放器引用
    if (activeVideoPlayer == self) {
        activeVideoPlayer = nil;
    }
    
    // 关闭视频播放器界面
    if (self.presentingViewController) {
        [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)setupRemoteCommandCenter {
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    
    // 启用播放/暂停命令
    [commandCenter.playCommand setEnabled:YES];
    [commandCenter.pauseCommand setEnabled:YES];
    
    // 处理播放命令
    [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        if (self.player && self.player.rate == 0.0) {
            [self.player play];
            return MPRemoteCommandHandlerStatusSuccess;
        }
        return MPRemoteCommandHandlerStatusCommandFailed;
    }];
    
    // 处理暂停命令
    [commandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        if (self.player && self.player.rate > 0.0) {
            [self.player pause];
            return MPRemoteCommandHandlerStatusSuccess;
        }
        return MPRemoteCommandHandlerStatusCommandFailed;
    }];
    
    // 启用跳过命令（可选）
    [commandCenter.skipForwardCommand setEnabled:YES];
    [commandCenter.skipBackwardCommand setEnabled:YES];
    commandCenter.skipForwardCommand.preferredIntervals = @[@15];
    commandCenter.skipBackwardCommand.preferredIntervals = @[@15];
    
    [commandCenter.skipForwardCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        CMTime currentTime = self.player.currentTime;
        CMTime newTime = CMTimeAdd(currentTime, CMTimeMakeWithSeconds(15, NSEC_PER_SEC));
        [self.player seekToTime:newTime];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    [commandCenter.skipBackwardCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        CMTime currentTime = self.player.currentTime;
        CMTime newTime = CMTimeSubtract(currentTime, CMTimeMakeWithSeconds(15, NSEC_PER_SEC));
        [self.player seekToTime:newTime];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
}

- (void)updateNowPlayingInfo {
    if (!self.player || !self.playerItem) return;
    
    NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];
    
    // 设置媒体标题
    nowPlayingInfo[MPMediaItemPropertyTitle] = self.file.name ?: @"Video";
    
    // 设置时长
    if (CMTIME_IS_VALID(self.playerItem.duration) && !CMTIME_IS_INDEFINITE(self.playerItem.duration)) {
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = @(CMTimeGetSeconds(self.playerItem.duration));
    }
    
    // 设置当前播放时间
    if (CMTIME_IS_VALID(self.player.currentTime)) {
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(CMTimeGetSeconds(self.player.currentTime));
    }
    
    // 设置播放速率
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(self.player.rate);
    
    // 更新控制中心信息
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nowPlayingInfo];
}

- (void)stopAndCleanup {
    // 移除定时器（在停止播放器之前）
    if (self.periodicTimeObserver && self.player) {
        [self.player removeTimeObserver:self.periodicTimeObserver];
        self.periodicTimeObserver = nil;
    }
    
    // 停止播放
    if (self.player) {
        [self.player pause];
        self.player = nil;
    }
    
    // 清理远程控制中心
    [self cleanupRemoteCommandCenter];
    
    // 移除播放器观察者
    [self cleanupObservers];
    
    // 停用音频会话
    [[AVAudioSession sharedInstance] setActive:NO error:nil];
    
    // 清空当前播放信息
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
    
    Debug(@"SeafVideoPlayerViewController stopped and cleaned up");
}

- (void)cleanupRemoteCommandCenter {
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.playCommand removeTarget:self];
    [commandCenter.pauseCommand removeTarget:self];
    [commandCenter.skipForwardCommand removeTarget:self];
    [commandCenter.skipBackwardCommand removeTarget:self];
    
    // 禁用命令
    [commandCenter.playCommand setEnabled:NO];
    [commandCenter.pauseCommand setEnabled:NO];
    [commandCenter.skipForwardCommand setEnabled:NO];
    [commandCenter.skipBackwardCommand setEnabled:NO];
}

- (void)cleanupObservers {
    if (_player) {
        @try {
            [_player removeObserver:self forKeyPath:@"rate"];
        } @catch (NSException *exception) {
            Debug(@"Exception while removing rate observer: %@", exception);
        }
    }
    
    if (_playerItem) {
        @try {
            [_playerItem removeObserver:self forKeyPath:NSStringFromSelector(@selector(status)) context:SeafPlayerItemStatusContext];
        } @catch (NSException *exception) {
            Debug(@"Exception while removing observer: %@", exception);
        }
    }
}

- (void)dealloc {
    // 清理资源
    [self cleanupRemoteCommandCenter];
    
    // 移除定时器
    if (self.periodicTimeObserver && self.player) {
        [self.player removeTimeObserver:self.periodicTimeObserver];
        self.periodicTimeObserver = nil;
    }
    
    // 移除播放器观察者
    [self cleanupObservers];
    
    // 停用音频会话
    [[AVAudioSession sharedInstance] setActive:NO error:nil];
    
    // 清空当前播放信息
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
    
    // 如果是当前活跃的播放器，清空引用
    if (activeVideoPlayer == self) {
        activeVideoPlayer = nil;
    }
    
    Debug(@"SeafVideoPlayerViewController dealloc");
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end 