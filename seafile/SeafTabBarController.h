//
//  SeafTabBarController.h
//  seafile
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Preserves theme title colors in the iPhone Liquid Glass tab bar.
@interface SeafTabBar : UITabBar
@end

/// Root tab bar controller. Keeps the tab bar's translucency in step with its
/// placement, which can change at runtime (iPhone Duo fold / unfold).
@interface SeafTabBarController : UITabBarController

@end

NS_ASSUME_NONNULL_END
