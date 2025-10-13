//  SeafSDocOutlineSheetViewController.h

#import <UIKit/UIKit.h>

@class OutlineItemModel;

NS_ASSUME_NONNULL_BEGIN

typedef void(^SeafSDocOutlineSelectHandler)(NSDictionary * _Nullable payload, NSUInteger index, OutlineItemModel *item);

@interface SeafSDocOutlineSheetViewController : UIViewController

- (instancetype)initWithItems:(NSArray<OutlineItemModel *> *)items origin:(NSArray *)origin;

@property (nonatomic, copy) SeafSDocOutlineSelectHandler onSelect;

@end

NS_ASSUME_NONNULL_END

