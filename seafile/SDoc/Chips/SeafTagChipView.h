//  SeafTagChipView.h
//  Single source-of-truth for tag chip UI across the app.
//  Used by: profile sheet (SeafTagChipCell), editor (SeafTagChipView), tag selector.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SeafTagChipRemoveHandler)(void);

@interface SeafTagChipView : UIView
/// Configure dot-style tag chip: white bg, border, color dot + name (no remove button)
- (void)configureWithName:(NSString *)name color:(NSString * _Nullable)colorHex;
/// Configure dot-style tag chip with optional remove button (editable mode)
- (void)configureWithName:(NSString *)name color:(NSString * _Nullable)colorHex showRemove:(BOOL)showRemove removeHandler:(SeafTagChipRemoveHandler _Nullable)handler;

/// Calculate the width needed for a chip with the given text (used for collection view sizing)
+ (CGFloat)widthForText:(NSString *)text showRemove:(BOOL)showRemove;

/// Shared hex color parser
+ (UIColor * _Nullable)colorFromHex:(NSString * _Nullable)hex;
@end

NS_ASSUME_NONNULL_END
