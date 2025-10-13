//  SeafTagChipCell.h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafTagChipCell : UICollectionViewCell
- (void)configureWithText:(NSString *)text color:(NSString * _Nullable)colorHex textColor:(NSString * _Nullable)textColorHex;
// Dot style: white background, gray border, left colored dot, dark text
- (void)configureDotStyleWithText:(NSString *)text dotColor:(NSString * _Nullable)dotColorHex textColor:(NSString * _Nullable)textColorHex;
@end

NS_ASSUME_NONNULL_END

