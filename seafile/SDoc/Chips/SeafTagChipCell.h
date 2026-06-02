//  SeafTagChipCell.h
//  UICollectionViewCell wrapper around SeafTagChipView for dot-style tags,
//  with fallback filled-style support for multi-select options.
//  Used in the profile sheet's inline collection views.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafTagChipCell : UICollectionViewCell
/// Filled style: colored background with text (for multi-select options)
- (void)configureWithText:(NSString *)text color:(NSString * _Nullable)colorHex textColor:(NSString * _Nullable)textColorHex;
/// Dot style: white background, gray border, left colored dot, dark text (for tags)
- (void)configureDotStyleWithText:(NSString *)text dotColor:(NSString * _Nullable)dotColorHex textColor:(NSString * _Nullable)textColorHex;
@end

NS_ASSUME_NONNULL_END

