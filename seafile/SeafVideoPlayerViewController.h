#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>

@class SeafFile;

NS_ASSUME_NONNULL_BEGIN

/**
 * A view controller dedicated to playing video files from a SeafFile object.
 * It handles fetching video URLs (both local cache and remote), setting up the AVPlayer,
 * and presenting the video content in a standard player interface.
 */
@interface SeafVideoPlayerViewController : UIViewController

/**
 * Initializes the video player view controller with a SeafFile object.
 *
 * @param file The SeafFile object representing the video to be played.
 * @return An initialized SeafVideoPlayerViewController instance.
 */
- (instancetype)initWithFile:(SeafFile *)file;

/**
 * Class method to close any currently active video player.
 * This ensures only one video player can be active at a time.
 */
+ (void)closeActiveVideoPlayer;

@end

NS_ASSUME_NONNULL_END 