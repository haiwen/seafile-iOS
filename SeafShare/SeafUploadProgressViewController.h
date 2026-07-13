//
//  SeafUploadProgressViewController.h
//  SeafShare
//
//  Custom alert-style overlay that shows upload progress (filename, progress bar,
//  and file count).  Replaces the previous approach of injecting a custom view
//  controller into UIAlertController via the private "contentViewController" KVC
//  key, which is unsupported and may break in future iOS versions.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafUploadProgressViewController : UIViewController

/// The label that displays the current file name being uploaded.
@property (nonatomic, strong, readonly) UILabel *fileNameLabel;

/// The progress bar that shows upload progress (0.0 – 1.0).
@property (nonatomic, strong, readonly) UIProgressView *progressView;

/// The label that displays "N / Total" when uploading multiple files.
@property (nonatomic, strong, readonly) UILabel *countLabel;

/// Called when the user taps the Cancel button.
@property (nonatomic, copy, nullable) void (^onCancel)(void);

/// Designated initializer.
/// @param fileName   The name of the first file being uploaded.
/// @param totalCount Total number of files to upload (count label is hidden when <= 1).
- (instancetype)initWithFileName:(NSString *)fileName totalCount:(NSInteger)totalCount;

@end

NS_ASSUME_NONNULL_END
