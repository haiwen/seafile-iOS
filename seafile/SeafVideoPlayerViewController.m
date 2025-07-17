#import "SeafVideoPlayerViewController.h"
#import "SeafConnection.h"
#import "SVProgressHUD.h"
#import "Debug.h"
#import "Version.h"
#import "SeafFile.h"
#import "SeafCacheManager+Thumb.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <CoreMedia/CMMetadata.h>

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
                    [self updateMetadataForPlayerItem];
                }
            } else {
                Debug(@"No thumbnail available for video file");
                // Use file's default icon
                self.videoThumbnail = [self.file icon];
                if (self.player && self.playerItem) {
                    [self updateMetadataForPlayerItem];
                }
            }
        });
    });
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
    // Register for audio session interruption notifications so we can resume playback
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAudioSessionInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:audioSession];

    // Observe route change as well for debugging purposes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAudioSessionRouteChange:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:audioSession];
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

#pragma mark - Audio session interruption

- (void)handleAudioSessionInterruption:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    AVAudioSessionInterruptionType type = [info[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];

    if (type == AVAudioSessionInterruptionTypeEnded) {
        AVAudioSessionInterruptionOptions options = [info[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];

        Debug(@"Audio session interruption ended. options=%lu, player.rate=%f", (unsigned long)options, self.player.rate);

        if (options & AVAudioSessionInterruptionOptionShouldResume) {
            // Reactivate audio session and resume playback if possible
            NSError *err = nil;
            [[AVAudioSession sharedInstance] setActive:YES error:&err];
            if (err) {
                Warning(@"Failed to reactivate audio session after interruption: %@", err);
            }

            if (self.player && self.player.rate == 0) {
                Debug(@"Resuming player after interruption");
                [self.player play];
            }
        }
    } else if (type == AVAudioSessionInterruptionTypeBegan) {
        Debug(@"Audio session interruption began. player.rate=%f", self.player.rate);
    }
}

#pragma mark - Audio session route change (debug)

- (void)handleAudioSessionRouteChange:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    AVAudioSessionRouteChangeReason reason = [info[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    Debug(@"Audio session route changed. reason=%lu", (unsigned long)reason);
}

- (void)setupPlayerViewController {
    self.playerViewController = [[AVPlayerViewController alloc] init];
    // Ensure the player view controller automatically updates the Now Playing info center
    if (@available(iOS 10.0, *)) {
        self.playerViewController.updatesNowPlayingInfoCenter = YES;
    }
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
    if (@available(iOS 15.0, *)) {
        self.player.audiovisualBackgroundPlaybackPolicy = AVPlayerAudiovisualBackgroundPlaybackPolicyContinuesIfPossible;
    }
    self.playerViewController.player = self.player;
    
    // Add metadata so the system automatically updates Now Playing info
    [self updateMetadataForPlayerItem];
    
    [self.playerViewController.player play];
    
    // Add playback status listeners
//    [self addPlayerObservers];
}

- (void)addPlayerObservers {
    // Listen for playback rate changes (play/pause)
    [self.player addObserver:self forKeyPath:@"rate" options:NSKeyValueObservingOptionNew context:nil];
    
    // No need for periodic updates since AVPlayerViewController now manages Now Playing info automatically.
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
                    // Metadata already set; system will handle Now Playing info.
                });
            }
        }
    }else {
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
    commandCenter.skipForwardCommand.preferredIntervals = @[@10];
    commandCenter.skipBackwardCommand.preferredIntervals = @[@10];

    [commandCenter.skipForwardCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return MPRemoteCommandHandlerStatusCommandFailed;
        CMTime currentTime = strongSelf.player.currentTime;
        CMTime newTime = CMTimeAdd(currentTime, CMTimeMakeWithSeconds(10, NSEC_PER_SEC));
        [strongSelf.player seekToTime:newTime];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.skipBackwardCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return MPRemoteCommandHandlerStatusCommandFailed;
        CMTime currentTime = strongSelf.player.currentTime;
        CMTime newTime = CMTimeSubtract(currentTime, CMTimeMakeWithSeconds(10, NSEC_PER_SEC));
        [strongSelf.player seekToTime:newTime];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
}

- (void)forceActivateNowPlayingInfo {
    // Force activate Now Playing info to ensure lock screen controls display
    dispatch_async(dispatch_get_main_queue(), ^{
        // Clear first, then set, ensuring system receives the update
//        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
//        [self updateNowPlayingInfo];
        
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
//    if (_player) {
//        @try {
//            [_player removeObserver:self forKeyPath:@"rate"];
//        } @catch (NSException *exception) {
//            Debug(@"Exception while removing rate observer: %@", exception);
//        }
//    }
    
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

#pragma mark - AVPlayerItem Metadata Helper

- (void)updateMetadataForPlayerItem {
    if (!self.playerItem) return;

    NSMutableArray<AVMetadataItem *> *metadataItems = [NSMutableArray array];

    // Title
    AVMutableMetadataItem *titleItem = [[AVMutableMetadataItem alloc] init];
    titleItem.identifier = AVMetadataCommonIdentifierTitle;
    titleItem.keySpace = AVMetadataKeySpaceCommon;
    titleItem.value = self.file.name ?: @"Video";
    titleItem.extendedLanguageTag = @"und"; // undefined language
    [metadataItems addObject:titleItem];

    // Artist / app name
//    AVMutableMetadataItem *artistItem = [[AVMutableMetadataItem alloc] init];
//    artistItem.identifier = AVMetadataCommonIdentifierArtist;
//    artistItem.keySpace = AVMetadataKeySpaceCommon;
//    artistItem.value = @"Seafile";
//    artistItem.extendedLanguageTag = @"und";
//    [metadataItems addObject:artistItem];

    // Subtitle (shows beneath title in system UI for video)
//    AVMutableMetadataItem *subtitleItem = [[AVMutableMetadataItem alloc] init];
//    if (@available(iOS 9.3, *)) { // identifier introduced earlier, but guard just in case
//        subtitleItem.identifier = AVMetadataIdentifieriTunesMetadataTrackSubTitle;
//    }
//    subtitleItem.keySpace = AVMetadataKeySpaceiTunes;
//    subtitleItem.value = @"Seafile";
//    [metadataItems addObject:subtitleItem];

    // Artwork (thumbnail) if available
    if (self.videoThumbnail) {
        NSData *imageData = UIImagePNGRepresentation(self.videoThumbnail);
        if (!imageData) {
            imageData = UIImageJPEGRepresentation(self.videoThumbnail, 0.9);
        }
        if (imageData) {
            AVMutableMetadataItem *artworkItem = [[AVMutableMetadataItem alloc] init];
            artworkItem.identifier = AVMetadataCommonIdentifierArtwork;
            artworkItem.keySpace = AVMetadataKeySpaceCommon;
            artworkItem.value = imageData;
            artworkItem.dataType = (__bridge NSString *)kCMMetadataBaseDataType_PNG;
            [metadataItems addObject:artworkItem];
        }
    }

    // Assign to player item. This replaces any existing external metadata we may have set earlier.
    self.playerItem.externalMetadata = metadataItems;

    // The system may ignore the Artist field for video assets in some cases. Explicitly add it to
    // the Now Playing info dictionary without disturbing other automatically-managed fields.
//    dispatch_async(dispatch_get_main_queue(), ^{
//        NSMutableDictionary *info = [[[MPNowPlayingInfoCenter defaultCenter] nowPlayingInfo] mutableCopy] ?: [NSMutableDictionary dictionary];
//        info[MPMediaItemPropertyArtist] = @"Seafile";
//        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:info];
//    });
}

@end 
