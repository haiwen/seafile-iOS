//
//  SeafIconFont.h
//  seafilePro
//
//  Runtime loader for the bundled "haiwen-iconfont" glyph font.
//
//  Seahub returns a wiki's icon as a glyph name (e.g. "bank-fill"). The font and
//  its name -> unicode table are the same assets the Android client ships, so the
//  two clients render an identical icon for the same server value.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafIconFont : NSObject

+ (instancetype)sharedInstance;

/// The icon font at the given size, or nil when the bundled font failed to load.
/// Callers must fall back to a regular image when this returns nil.
- (nullable UIFont *)fontOfSize:(CGFloat)size;

/// The single-character string that renders @c name in the icon font, or nil when
/// the font does not define that glyph. @c name is the raw server value, without
/// the "haiwen-" CSS prefix.
- (nullable NSString *)glyphForName:(nullable NSString *)name;

@end

NS_ASSUME_NONNULL_END
