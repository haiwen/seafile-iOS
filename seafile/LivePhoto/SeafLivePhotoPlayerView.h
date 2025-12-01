//
//  SeafLivePhotoPlayerView.h
//  seafile
//
//  Created for Live Photo / Motion Photo playback support.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SeafLivePhotoPlayerView;

@protocol SeafLivePhotoPlayerViewDelegate <NSObject>
@optional
- (void)livePhotoPlayerViewDidStartPlaying:(SeafLivePhotoPlayerView *)playerView;
- (void)livePhotoPlayerViewDidFinishPlaying:(SeafLivePhotoPlayerView *)playerView;
- (void)livePhotoPlayerView:(SeafLivePhotoPlayerView *)playerView didFailWithError:(NSError *)error;
@end

/**
 * A view that displays and plays Motion Photo / Live Photo content.
 * Shows a static image by default and plays the embedded video on long press.
 */
@interface SeafLivePhotoPlayerView : UIView

/// Delegate for playback events
@property (nonatomic, weak, nullable) id<SeafLivePhotoPlayerViewDelegate> delegate;

/// The static image being displayed
@property (nonatomic, strong, readonly, nullable) UIImage *staticImage;

/// Whether the view is currently playing video
@property (nonatomic, assign, readonly) BOOL isPlaying;

/// Whether this view contains valid Motion Photo content
@property (nonatomic, assign, readonly) BOOL hasMotionPhotoContent;

/// Content mode for the image view
@property (nonatomic, assign) UIViewContentMode imageContentMode;

/// Whether to show the "LIVE" badge indicator
@property (nonatomic, assign) BOOL showLiveBadge;

/// Whether to enable long press to play (default: YES)
@property (nonatomic, assign) BOOL longPressToPlayEnabled;

#pragma mark - Loading Methods

/**
 * Load Motion Photo from file data.
 * @param data Motion Photo file data
 */
- (void)loadMotionPhotoFromData:(NSData *)data;

/**
 * Load Motion Photo from file path.
 * @param path Path to Motion Photo file
 */
- (void)loadMotionPhotoFromPath:(NSString *)path;

/**
 * Load static image only (for non-Motion Photos).
 * @param image Static image to display
 */
- (void)loadStaticImage:(UIImage *)image;

/**
 * Set the video URL directly (for pre-extracted video).
 * @param imageData Static image data
 * @param videoURL URL to the video file
 */
- (void)loadWithImageData:(NSData *)imageData videoURL:(NSURL *)videoURL;

#pragma mark - Playback Control

/**
 * Start playing the embedded video.
 */
- (void)play;

/**
 * Pause video playback.
 */
- (void)pause;

/**
 * Stop video playback and reset to static image.
 */
- (void)stop;

/**
 * Toggle between playing and stopped states.
 */
- (void)togglePlayback;

#pragma mark - Cleanup

/**
 * Clean up resources and temporary files.
 */
- (void)cleanup;

@end

NS_ASSUME_NONNULL_END

