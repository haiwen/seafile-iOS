//
//  SeafLivePhotoPlayerView.m
//  seafile
//
//  Created for Live Photo / Motion Photo playback support.
//

#import "SeafLivePhotoPlayerView.h"
#import "Debug.h"
#import "SeafMotionPhotoExtractor.h"

@interface SeafLivePhotoPlayerView ()

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) UILabel *liveBadge;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;

@property (nonatomic, strong, readwrite) UIImage *staticImage;
@property (nonatomic, assign, readwrite) BOOL isPlaying;
@property (nonatomic, assign, readwrite) BOOL hasMotionPhotoContent;

@property (nonatomic, copy) NSString *tempVideoPath;
@property (nonatomic, strong) NSURL *videoURL;

@property (nonatomic, assign) BOOL waitingForFirstFrame;
@property (nonatomic, assign) BOOL transitionCompleted;
@property (nonatomic, strong) UIImpactFeedbackGenerator *hapticFeedback;

@end

@implementation SeafLivePhotoPlayerView

#pragma mark - Initialization

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.backgroundColor = [UIColor colorWithRed:249/255.0 green:249/255.0 blue:249/255.0 alpha:1.0]; // #F9F9F9
    self.clipsToBounds = YES;
    
    _imageContentMode = UIViewContentModeScaleAspectFit;
    _showLiveBadge = YES;
    _longPressToPlayEnabled = YES;
    _isPlaying = NO;
    _hasMotionPhotoContent = NO;
    
    [self setupImageView];
    [self setupLiveBadge];
    [self setupGestures];
    [self setupHapticFeedback];
}

- (void)setupHapticFeedback {
    _hapticFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [_hapticFeedback prepare];
}

- (void)setupImageView {
    _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
    _imageView.contentMode = _imageContentMode;
    _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _imageView.backgroundColor = [UIColor clearColor];
    [self addSubview:_imageView];
}

- (void)setupLiveBadge {
    _liveBadge = [[UILabel alloc] init];
    _liveBadge.text = @"LIVE";
    _liveBadge.font = [UIFont boldSystemFontOfSize:10];
    _liveBadge.textColor = [UIColor whiteColor];
    _liveBadge.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    _liveBadge.textAlignment = NSTextAlignmentCenter;
    _liveBadge.layer.cornerRadius = 4;
    _liveBadge.layer.masksToBounds = YES;
    _liveBadge.hidden = YES;
    [self addSubview:_liveBadge];
}

- (void)setupGestures {
    _longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    _longPressGesture.minimumPressDuration = 0.3;
    [self addGestureRecognizer:_longPressGesture];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    
    _imageView.frame = self.bounds;
    _playerLayer.frame = self.bounds;
    
    // Position live badge in top-left corner with padding
    CGFloat badgePadding = 12;
    CGFloat badgeWidth = 40;
    CGFloat badgeHeight = 18;
    _liveBadge.frame = CGRectMake(badgePadding, badgePadding, badgeWidth, badgeHeight);
}

- (void)dealloc {
    [self cleanup];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Properties

- (void)setImageContentMode:(UIViewContentMode)imageContentMode {
    _imageContentMode = imageContentMode;
    _imageView.contentMode = imageContentMode;
}

- (void)setShowLiveBadge:(BOOL)showLiveBadge {
    _showLiveBadge = showLiveBadge;
    [self updateLiveBadgeVisibility];
}

- (void)updateLiveBadgeVisibility {
    _liveBadge.hidden = !(_showLiveBadge && _hasMotionPhotoContent && !_isPlaying);
}

#pragma mark - Loading Methods

- (void)loadMotionPhotoFromData:(NSData *)data {
    [self cleanup];
    
    Debug(@"[LivePhotoPlayer] loadMotionPhotoFromData called, data size: %lu bytes", (unsigned long)data.length);
    
    if (!data || data.length == 0) {
        Debug(@"[LivePhotoPlayer] ERROR: No data provided");
        return;
    }
    
    // Check if this is a Motion Photo
    BOOL isMotionPhoto = [SeafMotionPhotoExtractor isMotionPhoto:data];
    Debug(@"[LivePhotoPlayer] isMotionPhoto detection result: %@", isMotionPhoto ? @"YES" : @"NO");
    
    if (!isMotionPhoto) {
        // Not a Motion Photo, just display as static image
        Debug(@"[LivePhotoPlayer] Not a Motion Photo, loading as static image");
        UIImage *image = [UIImage imageWithData:data];
        Debug(@"[LivePhotoPlayer] Static image created: %@, size: %@",
              image ? @"SUCCESS" : @"FAILED",
              image ? NSStringFromCGSize(image.size) : @"N/A");
        [self loadStaticImage:image];
        return;
    }
    
    _hasMotionPhotoContent = YES;
    Debug(@"[LivePhotoPlayer] Motion Photo detected, extracting components...");
    
    // Extract static image
    NSData *imageData = [SeafMotionPhotoExtractor extractImageFromMotionPhoto:data];
    Debug(@"[LivePhotoPlayer] Extracted image data: %@",
          imageData ? [NSString stringWithFormat:@"%lu bytes", (unsigned long)imageData.length] : @"FAILED");
    
    if (imageData) {
        _staticImage = [UIImage imageWithData:imageData];
        Debug(@"[LivePhotoPlayer] Created UIImage from extracted data: %@, size: %@",
              _staticImage ? @"SUCCESS" : @"FAILED",
              _staticImage ? NSStringFromCGSize(_staticImage.size) : @"N/A");
    } else {
        // Fallback: try to load the whole data as image
        Debug(@"[LivePhotoPlayer] FALLBACK: Trying to create image from full data");
        _staticImage = [UIImage imageWithData:data];
        Debug(@"[LivePhotoPlayer] Fallback image creation: %@, size: %@",
              _staticImage ? @"SUCCESS" : @"FAILED",
              _staticImage ? NSStringFromCGSize(_staticImage.size) : @"N/A");
    }
    
    _imageView.image = _staticImage;
    
    // Extract video to temp file
    Debug(@"[LivePhotoPlayer] Extracting video to temp file...");
    _tempVideoPath = [SeafMotionPhotoExtractor extractVideoToTempFileFromMotionPhoto:data];
    
    if (_tempVideoPath) {
        _videoURL = [NSURL fileURLWithPath:_tempVideoPath];
        Debug(@"[LivePhotoPlayer] Video extracted successfully: %@", _tempVideoPath);
        
        // Verify the video file
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDictionary *attrs = [fm attributesOfItemAtPath:_tempVideoPath error:nil];
        Debug(@"[LivePhotoPlayer] Video file size: %llu bytes", [attrs fileSize]);
        
        // Check video format
        NSData *videoHeader = [NSData dataWithContentsOfFile:_tempVideoPath options:NSDataReadingMappedIfSafe error:nil];
        if (videoHeader && videoHeader.length >= 12) {
            char type[5] = {0};
            char brand[5] = {0};
            [videoHeader getBytes:type range:NSMakeRange(4, 4)];
            [videoHeader getBytes:brand range:NSMakeRange(8, 4)];
            Debug(@"[LivePhotoPlayer] Video format: type='%s', brand='%s'", type, brand);
        }
    } else {
        Debug(@"[LivePhotoPlayer] ERROR: Failed to extract video to temp file!");
        
        // Additional debug: try to get video data directly
        NSData *videoData = [SeafMotionPhotoExtractor extractVideoFromMotionPhoto:data];
        if (videoData) {
            Debug(@"[LivePhotoPlayer] Video data exists (%lu bytes) but failed to write to temp file",
                  (unsigned long)videoData.length);
        } else {
            Debug(@"[LivePhotoPlayer] Video extraction also failed - no video data found");
        }
    }
    
    [self updateLiveBadgeVisibility];
    Debug(@"[LivePhotoPlayer] Load complete. hasMotionPhotoContent=%@, hasVideo=%@, hasImage=%@",
          _hasMotionPhotoContent ? @"YES" : @"NO",
          _videoURL ? @"YES" : @"NO",
          _staticImage ? @"YES" : @"NO");
}

- (void)loadMotionPhotoFromPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    [self loadMotionPhotoFromData:data];
}

- (void)loadStaticImage:(UIImage *)image {
    [self cleanup];
    
    _staticImage = image;
    _imageView.image = image;
    _hasMotionPhotoContent = NO;
    
    [self updateLiveBadgeVisibility];
}

- (void)loadWithImageData:(NSData *)imageData videoURL:(NSURL *)videoURL {
    [self cleanup];
    
    _staticImage = [UIImage imageWithData:imageData];
    _imageView.image = _staticImage;
    _videoURL = videoURL;
    _hasMotionPhotoContent = (videoURL != nil);
    
    [self updateLiveBadgeVisibility];
}

#pragma mark - Playback Control

- (void)play {
    if (!_hasMotionPhotoContent || !_videoURL || _isPlaying) {
        return;
    }
    
    [_hapticFeedback impactOccurred];
    [self setupPlayer];
    
    _isPlaying = YES;
    _waitingForFirstFrame = YES;
    _transitionCompleted = NO;
    
    // playerLayer is below imageView; hide imageView when first frame is ready
    _playerLayer.opacity = 1.0;
    _playerLayer.hidden = NO;
    _imageView.hidden = NO;
    _imageView.alpha = 1.0;
    
    if (_playerLayer.readyForDisplay) {
        [self performCrossFadeTransition];
    }
    
    [_player seekToTime:kCMTimeZero];
    [_player play];
    [self updateLiveBadgeVisibility];
    
    if ([_delegate respondsToSelector:@selector(livePhotoPlayerViewDidStartPlaying:)]) {
        [_delegate livePhotoPlayerViewDidStartPlaying:self];
    }
}

- (void)pause {
    if (!_isPlaying) {
        return;
    }
    
    [_player pause];
}

- (void)stop {
    if (!_isPlaying) {
        return;
    }
    
    [_player pause];
    
    _isPlaying = NO;
    _waitingForFirstFrame = NO;
    _transitionCompleted = NO;
    
    _imageView.hidden = NO;
    _imageView.alpha = 1.0;
    
    [self destroyPlayer];
    [self updateLiveBadgeVisibility];
}

- (void)destroyPlayer {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:_player.currentItem];
    
    @try {
        if (_playerLayer) {
            [_playerLayer removeObserver:self forKeyPath:@"readyForDisplay"];
        }
        if (_player.currentItem) {
            [_player.currentItem removeObserver:self forKeyPath:@"status"];
        }
    } @catch (NSException *exception) {
        Debug(@"[LivePhoto] Exception removing KVO: %@", exception);
    }
    
    // Destroy player
    [_player pause];
    _player = nil;
    
    // Destroy playerLayer
    [_playerLayer removeFromSuperlayer];
    _playerLayer = nil;
    
    Debug(@"[LivePhoto] Player destroyed for clean state");
}

- (void)togglePlayback {
    if (_isPlaying) {
        [self stop];
    } else {
        [self play];
    }
}

#pragma mark - Player Setup

- (void)setupPlayer {
    if (_player) {
        return;
    }
    
    if (!_videoURL) {
        return;
    }
    
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:_videoURL];
    _player = [AVPlayer playerWithPlayerItem:playerItem];
    _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    
    _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
    _playerLayer.frame = self.bounds;
    _playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    _playerLayer.hidden = YES;
    [self.layer insertSublayer:_playerLayer below:_imageView.layer];
    
    [_playerLayer addObserver:self forKeyPath:@"readyForDisplay" options:NSKeyValueObservingOptionNew context:nil];
    [playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerDidFinishPlaying:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:playerItem];
}

- (void)playerDidFinishPlaying:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self stop];
        
        if ([self.delegate respondsToSelector:@selector(livePhotoPlayerViewDidFinishPlaying:)]) {
            [self.delegate livePhotoPlayerViewDidFinishPlaying:self];
        }
    });
}

#pragma mark - Cross-Fade Transition

/// Switch from static image to video when first frame is ready.
- (void)performCrossFadeTransition {
    if (_transitionCompleted || !_isPlaying) {
        return;
    }
    
    _waitingForFirstFrame = NO;
    _transitionCompleted = YES;
    _imageView.hidden = YES;
}

#pragma mark - KVO Observer

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"readyForDisplay"]) {
        BOOL ready = [change[NSKeyValueChangeNewKey] boolValue];
        if (ready && _waitingForFirstFrame && _isPlaying) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self performCrossFadeTransition];
            });
        }
    } else if ([keyPath isEqualToString:@"status"]) {
        AVPlayerItemStatus status = [change[NSKeyValueChangeNewKey] integerValue];
        if (status == AVPlayerItemStatusFailed) {
            Debug(@"[LivePhoto] AVPlayerItem failed: %@", _player.currentItem.error);
        }
    }
}

#pragma mark - Gesture Handling

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (!_longPressToPlayEnabled || !_hasMotionPhotoContent) {
        return;
    }
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            [self play];
            break;
            
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [self stop];
            break;
            
        default:
            break;
    }
}

#pragma mark - Cleanup

- (void)cleanup {
    if (_isPlaying) {
        [self stop];
    } else {
        [self destroyPlayer];
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    _videoURL = nil;
    
    if (_tempVideoPath) {
        [[NSFileManager defaultManager] removeItemAtPath:_tempVideoPath error:nil];
        _tempVideoPath = nil;
    }
    
    _staticImage = nil;
    _imageView.image = nil;
    _imageView.alpha = 1.0;
    _imageView.hidden = NO;
    _hasMotionPhotoContent = NO;
    _isPlaying = NO;
    _waitingForFirstFrame = NO;
    _transitionCompleted = NO;
}

@end

