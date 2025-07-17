#import "SeafVideoPlayerViewController.h"
#import "SeafConnection.h"
#import "SVProgressHUD.h"
#import "Debug.h"
#import "Version.h"
#import "SeafFile.h"
#import "SeafCacheManager+Thumb.h"
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
@property (strong, nonatomic) UIImage *videoThumbnail;
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
    [self loadVideoThumbnail];
    [self startPlayback];
    [self setupRemoteCommandCenter];
    [self setupApplicationLifecycleObservers];
}

- (void)loadVideoThumbnail {
    // Try to get video thumbnail
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // First try to get existing thumbnail
        UIImage *thumb = [[SeafCacheManager sharedManager] thumbForFile:self.file];
        
        if (!thumb) {
            // If no thumbnail, try to get file icon
            thumb = [[SeafCacheManager sharedManager] iconForFile:self.file];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (thumb) {
                self.videoThumbnail = thumb;
                Debug(@"Video thumbnail loaded successfully");
                // If player is ready, immediately update Now Playing info
                if (self.player && self.playerItem) {
                    [self updateNowPlayingInfo];
                }
            } else {
                Debug(@"No thumbnail available for video file");
                // Use file's default icon
                self.videoThumbnail = [self.file icon];
                if (self.player && self.playerItem) {
                    [self updateNowPlayingInfo];
                }
            }
        });
    });
}

- (void)setupApplicationLifecycleObservers {
    // Listen for application become active events
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    // Listen for application enter background events
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    Debug(@"Application became active, reactivating media controls");
    if (self.player && self.playerItem) {
        [self forceActivateNowPlayingInfo];
    }
}

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    Debug(@"Application entered background, ensuring media controls are active");
    if (self.player && self.playerItem && self.player.rate > 0) {
        [self forceActivateNowPlayingInfo];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.playerViewController.view.frame = self.view.bounds;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    // If being dismissed or popped, ensure resource cleanup
    if (self.isBeingDismissed || self.isMovingFromParentViewController) {
        [self stopAndCleanup];
        if (activeVideoPlayer == self) {
            activeVideoPlayer = nil;
        }
    }
}

- (void)setupAudioSession {
    NSError *error = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    // Set audio session category to playback, allow background playback
    BOOL success = [audioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (!success || error) {
        Warning(@"Failed to set audio session category: %@", error);
        error = nil; // Reset error
        
        // Try simpler settings
        [audioSession setCategory:AVAudioSessionCategoryPlayback 
                     withOptions:0 
                           error:&error];
        if (error) {
            Warning(@"Failed to set basic audio session category: %@", error);
        }
    }
    
    // Activate audio session
    error = nil;
    success = [audioSession setActive:YES error:&error];
    if (!success || error) {
        Warning(@"Failed to activate audio session: %@", error);
        
        // Try different activation options
        error = nil;
        [audioSession setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
        if (error) {
            Warning(@"Failed to activate audio session with options: %@", error);
        }
    }
    
    Debug(@"Audio session setup complete for video playback");
}

- (void)setupPlayerViewController {
    self.playerViewController = [[AVPlayerViewController alloc] init];
    [self addChildViewController:self.playerViewController];
    [self.view addSubview:self.playerViewController.view];
    [self.playerViewController didMoveToParentViewController:self];
    
    // Allow picture-in-picture mode (iOS 14+)
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
    
    // Immediately set initial Now Playing info (even if player isn't fully ready)
    [self updateNowPlayingInfo];
    
    [self.playerViewController.player play];
    
    // Add playback status listeners
    [self addPlayerObservers];
}

- (void)addPlayerObservers {
    // Listen for playback rate changes (play/pause)
    [self.player addObserver:self forKeyPath:@"rate" options:NSKeyValueObservingOptionNew context:nil];
    
    // Periodically update playback info
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
                    // Force activate Now Playing info after video is ready
                    [self forceActivateNowPlayingInfo];
                });
            }
        }
    } else if ([keyPath isEqualToString:@"rate"]) {
        // Update control center info when playback state changes
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
    // Stop playback and cleanup resources
    [self stopAndCleanup];
    
    // Clear active player reference
    if (activeVideoPlayer == self) {
        activeVideoPlayer = nil;
    }
    
    // Close video player interface
    if (self.presentingViewController) {
        [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)setupRemoteCommandCenter {
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    __weak typeof(self) weakSelf = self;

    // Enable play/pause commands
    [commandCenter.playCommand setEnabled:YES];
    [commandCenter.pauseCommand setEnabled:YES];

    // Handle play command
    [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return MPRemoteCommandHandlerStatusCommandFailed;
        if (strongSelf.player && strongSelf.player.rate == 0.0) {
            [strongSelf.player play];
            return MPRemoteCommandHandlerStatusSuccess;
        }
        return MPRemoteCommandHandlerStatusCommandFailed;
    }];

    // Handle pause command
    [commandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return MPRemoteCommandHandlerStatusCommandFailed;
        if (strongSelf.player && strongSelf.player.rate > 0.0) {
            [strongSelf.player pause];
            return MPRemoteCommandHandlerStatusSuccess;
        }
        return MPRemoteCommandHandlerStatusCommandFailed;
    }];

    // Enable skip commands (optional)
    [commandCenter.skipForwardCommand setEnabled:YES];
    [commandCenter.skipBackwardCommand setEnabled:YES];
    commandCenter.skipForwardCommand.preferredIntervals = @[@15];
    commandCenter.skipBackwardCommand.preferredIntervals = @[@15];

    [commandCenter.skipForwardCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return MPRemoteCommandHandlerStatusCommandFailed;
        CMTime currentTime = strongSelf.player.currentTime;
        CMTime newTime = CMTimeAdd(currentTime, CMTimeMakeWithSeconds(15, NSEC_PER_SEC));
        [strongSelf.player seekToTime:newTime];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.skipBackwardCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return MPRemoteCommandHandlerStatusCommandFailed;
        CMTime currentTime = strongSelf.player.currentTime;
        CMTime newTime = CMTimeSubtract(currentTime, CMTimeMakeWithSeconds(15, NSEC_PER_SEC));
        [strongSelf.player seekToTime:newTime];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
}

- (void)updateNowPlayingInfo {
    if (!self.player || !self.playerItem) return;
    
    NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];
    
    // Set media title
    nowPlayingInfo[MPMediaItemPropertyTitle] = self.file.name ?: @"Video";
    
    // Set media type to video
    nowPlayingInfo[MPMediaItemPropertyMediaType] = @(MPMediaTypeAnyVideo);
    
    // Set app name as artist
    nowPlayingInfo[MPMediaItemPropertyArtist] = @"Seafile";
    
    // Set album name (optional)
    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = @"Seafile Videos";
    
    // Set video thumbnail as album artwork
    if (self.videoThumbnail) {
        UIImage *artworkImage = self.videoThumbnail;
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:artworkImage.size requestHandler:^UIImage * _Nonnull(CGSize requestedSize) {
            // Scale if requested size differs significantly from original
            if (requestedSize.width > 0 && requestedSize.height > 0) {
                CGSize originalSize = artworkImage.size;
                if (originalSize.width <= 0 || originalSize.height <= 0) {
                    return artworkImage;
                }
                CGFloat aspectRatio = originalSize.width / originalSize.height;
                CGFloat requestedAspectRatio = requestedSize.width / requestedSize.height;
                
                // Return original if size difference is small
                if (fabs(aspectRatio - requestedAspectRatio) < 0.1 && 
                    fabs(originalSize.width - requestedSize.width) < 100) {
                    return artworkImage;
                }
                
                // Otherwise perform proportional scaling
                CGSize targetSize = requestedSize;
                if (aspectRatio > requestedAspectRatio) {
                    // Original is wider, scale based on width
                    targetSize.height = requestedSize.width / aspectRatio;
                } else {
                    // Original is taller, scale based on height
                    targetSize.width = requestedSize.height * aspectRatio;
                }
                
                UIGraphicsBeginImageContextWithOptions(targetSize, NO, 0.0);
                [artworkImage drawInRect:CGRectMake(0, 0, targetSize.width, targetSize.height)];
                UIImage *scaledImage = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                
                return scaledImage ?: artworkImage;
            }
            return artworkImage;
        }];
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork;
        Debug(@"Set video thumbnail as album artwork");
    }
    
    // Set duration
    if (CMTIME_IS_VALID(self.playerItem.duration) && !CMTIME_IS_INDEFINITE(self.playerItem.duration)) {
        Float64 duration = CMTimeGetSeconds(self.playerItem.duration);
        if (duration > 0) {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = @(duration);
        }
    }
    
    // Set current playback time
    if (CMTIME_IS_VALID(self.player.currentTime)) {
        Float64 currentTime = CMTimeGetSeconds(self.player.currentTime);
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(currentTime);
    }
    
    // Set playback rate
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(self.player.rate);
    
    // Set default playback rate (important: tells system this is controllable media)
    nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = @(1.0);
    
    // Update control center info
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nowPlayingInfo];
    
    Debug(@"Updated Now Playing Info with %@artwork: %@", self.videoThumbnail ? @"" : @"no ", nowPlayingInfo);
}

- (void)forceActivateNowPlayingInfo {
    // Force activate Now Playing info to ensure lock screen controls display
    dispatch_async(dispatch_get_main_queue(), ^{
        // Clear first, then set, ensuring system receives the update
        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
        [self updateNowPlayingInfo];
        
        // Ensure audio session is active
        NSError *error = nil;
        [[AVAudioSession sharedInstance] setActive:YES error:&error];
        if (error) {
            Warning(@"Failed to reactivate audio session: %@", error);
        }
    });
}

- (void)stopAndCleanup {
    // If PiP is active, stop it by setting player to nil
    if (self.playerViewController) {
        self.playerViewController.player = nil;
    }

    // Remove timer (before stopping player)
    if (self.periodicTimeObserver && self.player) {
        [self.player removeTimeObserver:self.periodicTimeObserver];
        self.periodicTimeObserver = nil;
    }
    
    // Stop playback
    if (self.player) {
        [self.player pause];
        self.player = nil;
    }
    
    // Cleanup remote command center
    [self cleanupRemoteCommandCenter];
    
    // Remove player observers
    [self cleanupObservers];
    
    // Cancel thumbnail download
    if (self.file) {
        [[SeafCacheManager sharedManager] cancelThumbForFile:self.file];
    }
    
    // Cleanup thumbnail reference
    self.videoThumbnail = nil;
    
    // Deactivate audio session
    [[AVAudioSession sharedInstance] setActive:NO error:nil];
    
    // Clear current playing info
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
    
    Debug(@"SeafVideoPlayerViewController stopped and cleaned up");
}

- (void)cleanupRemoteCommandCenter {
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.playCommand removeTarget:self];
    [commandCenter.pauseCommand removeTarget:self];
    [commandCenter.skipForwardCommand removeTarget:self];
    [commandCenter.skipBackwardCommand removeTarget:self];
    
    // Disable commands
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
    // Remove notification observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Cleanup resources
    [self cleanupRemoteCommandCenter];
    
    // Remove timer
    if (self.periodicTimeObserver && self.player) {
        [self.player removeTimeObserver:self.periodicTimeObserver];
        self.periodicTimeObserver = nil;
    }
    
    // Remove player observers
    [self cleanupObservers];
    
    // Deactivate audio session
    [[AVAudioSession sharedInstance] setActive:NO error:nil];
    
    // Clear current playing info
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
    
    // If this is the current active player, clear reference
    if (activeVideoPlayer == self) {
        activeVideoPlayer = nil;
    }
    
    Debug(@"SeafVideoPlayerViewController dealloc");
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end 