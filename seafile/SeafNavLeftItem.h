#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Noninteractive navigation title with an optional save-state label.
@interface SeafNavLeftItem : UIView
+ (instancetype)titleViewWithTitle:(NSString *)title;
@property (nonatomic, copy, readonly, nullable) NSString *statusText;
- (void)applyStatusText:(nullable NSString *)statusText;
@end

NS_ASSUME_NONNULL_END
