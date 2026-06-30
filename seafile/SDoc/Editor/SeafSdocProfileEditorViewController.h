//  SeafSdocProfileEditorViewController.h
//  Align Android: FileProfileEditorActivity

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SeafConnection;
@class SeafFileProfileAggregate;

@interface SeafSdocProfileEditorViewController : UIViewController

/// Designated initializer
/// @param connection The connection for API calls
/// @param repoId The repo ID
/// @param aggregate The file profile aggregate data (raw data needed for editing)
- (instancetype)initWithConnection:(SeafConnection *)connection
                            repoId:(NSString *)repoId
                         aggregate:(SeafFileProfileAggregate *)aggregate;

@end

NS_ASSUME_NONNULL_END
