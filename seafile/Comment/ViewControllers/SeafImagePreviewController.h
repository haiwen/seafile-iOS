//  SeafImagePreviewController.h

#import <UIKit/UIKit.h>

@class SeafConnection;

NS_ASSUME_NONNULL_BEGIN

@interface SeafImagePreviewController : UIViewController <UIScrollViewDelegate>

- (instancetype)initWithURL:(NSString *)url connection:(SeafConnection * _Nullable)connection;

@end

NS_ASSUME_NONNULL_END

